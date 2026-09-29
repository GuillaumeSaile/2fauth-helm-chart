{{/*
Expand the name of the chart.
*/}}
{{- define "2fauth.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "2fauth.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Namespace to install into.
*/}}
{{- define "2fauth.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Chart name and version, as used by the helm.sh/chart label.
*/}}
{{- define "2fauth.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels for the application pods.

`app.kubernetes.io/component` is part of the selector on purpose: it keeps the
Service (and the Deployment selector) from matching the scheduler CronJob pods
and the `helm test` pod, which would otherwise be registered as endpoints.
*/}}
{{- define "2fauth.selectorLabels" -}}
app.kubernetes.io/name: {{ include "2fauth.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: application
{{- end }}

{{/*
Labels matching every pod of the release, whatever its component. Used by the
NetworkPolicy so the scheduler pods are covered too.
*/}}
{{- define "2fauth.instanceSelectorLabels" -}}
app.kubernetes.io/name: {{ include "2fauth.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for the scheduler CronJob pods.
*/}}
{{- define "2fauth.schedulerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "2fauth.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: scheduler
{{- end }}

{{/*
Selector labels for the `helm test` pod.
*/}}
{{- define "2fauth.testSelectorLabels" -}}
app.kubernetes.io/name: {{ include "2fauth.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: test
{{- end }}

{{/*
Labels shared by every resource, minus the identifying selector labels.
*/}}
{{- define "2fauth.baseLabels" -}}
helm.sh/chart: {{ include "2fauth.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: 2fauth
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Full label set for the application resources.
*/}}
{{- define "2fauth.labels" -}}
{{ include "2fauth.baseLabels" . }}
{{ include "2fauth.selectorLabels" . }}
{{- end }}

{{/*
Full label set for the scheduler CronJob.
*/}}
{{- define "2fauth.schedulerLabels" -}}
{{ include "2fauth.baseLabels" . }}
{{ include "2fauth.schedulerSelectorLabels" . }}
{{- end }}

{{/*
Full label set for the test pod.
*/}}
{{- define "2fauth.testLabels" -}}
{{ include "2fauth.baseLabels" . }}
{{ include "2fauth.testSelectorLabels" . }}
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "2fauth.annotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "2fauth.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "2fauth.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the chart-managed Secret.
*/}}
{{- define "2fauth.secretName" -}}
{{- printf "%s-env" (include "2fauth.fullname" .) }}
{{- end }}

{{/*
Name of the chart-managed ConfigMap.
*/}}
{{- define "2fauth.configMapName" -}}
{{- printf "%s-env" (include "2fauth.fullname" .) }}
{{- end }}

{{/*
Name of the PVC holding /2fauth.
*/}}
{{- define "2fauth.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "2fauth.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Container image reference.
*/}}
{{- define "2fauth.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{/*
APP_KEY resolution.

Order of precedence:
  1. an explicit .Values.appKey.value
  2. the key already stored in the chart-managed Secret (so upgrades never
     rotate it, which would make every stored 2FA secret unreadable)
  3. a freshly generated 32-character key
*/}}
{{- define "2fauth.appKey" -}}
{{- if .Values.appKey.value }}
{{- .Values.appKey.value }}
{{- else }}
{{- $secret := lookup "v1" "Secret" (include "2fauth.namespace" .) (include "2fauth.secretName" .) }}
{{- if and $secret $secret.data (index $secret.data "app-key") }}
{{- index $secret.data "app-key" | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Default database port for the configured engine.
*/}}
{{- define "2fauth.databasePort" -}}
{{- if .Values.database.port }}
{{- .Values.database.port }}
{{- else if eq .Values.database.type "mysql" }}3306
{{- else if eq .Values.database.type "pgsql" }}5432
{{- else if eq .Values.database.type "sqlsrv" }}1433
{{- end }}
{{- end }}

{{/*
Path of the SQLite file inside the container. Keeping the default makes the
entrypoint symlink it to /2fauth/database.sqlite on the data volume.
*/}}
{{- define "2fauth.sqlitePath" -}}
{{- default "/srv/database/database.sqlite" .Values.database.name }}
{{- end }}

{{/*
External URL of the instance (APP_URL). Derived from the first ingress host
when not set explicitly.
*/}}
{{- define "2fauth.appUrl" -}}
{{- if .Values.config.app.url }}
{{- .Values.config.app.url | trimSuffix "/" }}
{{- else if and .Values.ingress.enabled .Values.ingress.hosts }}
{{- $host := (first .Values.ingress.hosts).host }}
{{- $scheme := "http" }}
{{- range .Values.ingress.tls }}
{{- if has $host .hosts }}{{ $scheme = "https" }}{{ end }}
{{- end }}
{{- printf "%s://%s" $scheme $host }}
{{- if .Values.config.app.subdirectory }}{{ printf "/%s" (.Values.config.app.subdirectory | trim | trimAll "/") }}{{ end }}
{{- else }}
{{- printf "http://localhost" }}
{{- end }}
{{- end }}

{{/*
Non-secret environment variables, as a YAML map.

Entries whose value is nil are dropped so that 2FAuth falls back to its own
defaults instead of receiving the literal string "null" where it matters.
*/}}
{{- define "2fauth.configEnv" -}}
{{- $c := .Values.config }}
{{- $raw := dict
  "APP_NAME"                          $c.app.name
  "APP_ENV"                           $c.app.env
  "APP_URL"                           (include "2fauth.appUrl" .)
  "ASSET_URL"                         $c.app.assetUrl
  "APP_SUBDIRECTORY"                  $c.app.subdirectory
  "APP_TIMEZONE"                      $c.app.timezone
  "APP_DEBUG"                         $c.app.debug
  "SITE_OWNER"                        $c.app.siteOwner
  "IS_DEMO_APP"                       $c.app.isDemoApp
  "LOG_CHANNEL"                       $c.log.channel
  "LOG_LEVEL"                         $c.log.level
  "CACHE_DRIVER"                      $c.cacheDriver
  "SESSION_DRIVER"                    $c.sessionDriver
  "CONTENT_SECURITY_POLICY"           $c.security.contentSecurityPolicy
  "BLOCK_OPTAUTH_IMAGELINK_FETCHING"  $c.security.blockOtpauthImagelinkFetching
  "TRUSTED_PROXIES"                   $c.security.trustedProxies
  "PROXY_FOR_OUTGOING_REQUESTS"       $c.security.proxyForOutgoingRequests
  "PHP_MEMORY_LIMIT_TEMP_OVERRIDE"    $c.security.phpMemoryLimitTempOverride
  "THROTTLE_API"                      $c.api.throttle
  "THROTTLE_API_DURING_IMPORT"        $c.api.throttleDuringImport
  "AUTHENTICATION_GUARD"              $c.auth.guard
  "LOGIN_THROTTLE"                    $c.auth.loginThrottle
  "AUTHENTICATION_LOG_RETENTION"      $c.auth.logRetention
  "OTP_LOG_RETENTION"                 $c.auth.otpLogRetention
  "AUTH_PROXY_HEADER_FOR_USER"        $c.auth.proxyHeaderForUser
  "AUTH_PROXY_HEADER_FOR_EMAIL"       $c.auth.proxyHeaderForEmail
  "PROXY_LOGOUT_URL"                  $c.auth.proxyLogoutUrl
  "WEBAUTHN_NAME"                     $c.webauthn.name
  "WEBAUTHN_ID"                       $c.webauthn.id
  "WEBAUTHN_USER_VERIFICATION"        $c.webauthn.userVerification
  "MAIL_MAILER"                       .Values.mail.mailer
  "MAIL_HOST"                         .Values.mail.host
  "MAIL_PORT"                         .Values.mail.port
  "MAIL_USERNAME"                     .Values.mail.username
  "MAIL_ENCRYPTION"                   .Values.mail.encryption
  "MAIL_FROM_NAME"                    .Values.mail.fromName
  "MAIL_FROM_ADDRESS"                 .Values.mail.fromAddress
  "MAIL_VERIFY_SSL_PEER"              .Values.mail.verifySslPeer
  "BROADCAST_DRIVER"                  "log"
  "QUEUE_DRIVER"                      "sync"
}}

{{/* Database */}}
{{- if eq .Values.database.type "sqlite" }}
{{- $_ := set $raw "DB_CONNECTION" "sqlite" }}
{{- $_ := set $raw "DB_DATABASE" (include "2fauth.sqlitePath" .) }}
{{- else }}
{{- $_ := set $raw "DB_CONNECTION" .Values.database.type }}
{{- $_ := set $raw "DB_HOST" .Values.database.host }}
{{- $_ := set $raw "DB_PORT" (include "2fauth.databasePort" .) }}
{{- $_ := set $raw "DB_DATABASE" .Values.database.name }}
{{- $_ := set $raw "DB_USERNAME" .Values.database.username }}
{{- if .Values.database.mysqlSslCa }}
{{- $_ := set $raw "MYSQL_ATTR_SSL_CA" .Values.database.mysqlSslCa }}
{{- end }}
{{- end }}

{{/* Redis */}}
{{- if or (eq .Values.config.cacheDriver "redis") (eq .Values.config.sessionDriver "redis") }}
{{- $_ := set $raw "REDIS_HOST" .Values.redis.host }}
{{- $_ := set $raw "REDIS_PORT" .Values.redis.port }}
{{- end }}

{{/* SSO */}}
{{- if .Values.config.sso.openid.enabled }}
{{- $o := .Values.config.sso.openid }}
{{- $_ := set $raw "OPENID_AUTHORIZE_URL" $o.authorizeUrl }}
{{- $_ := set $raw "OPENID_TOKEN_URL" $o.tokenUrl }}
{{- $_ := set $raw "OPENID_USERINFO_URL" $o.userinfoUrl }}
{{- $_ := set $raw "OPENID_CLIENT_ID" $o.clientId }}
{{- $_ := set $raw "OPENID_HTTP_VERIFY_SSL_PEER" $o.verifySslPeer }}
{{- end }}
{{- if .Values.config.sso.github.enabled }}
{{- $_ := set $raw "GITHUB_CLIENT_ID" .Values.config.sso.github.clientId }}
{{- end }}

{{/* User preferences */}}
{{- range $k, $v := .Values.config.userPreferences.defaults }}
{{- $_ := set $raw (printf "USERPREF_DEFAULT__%s" $k) $v }}
{{- end }}
{{- range $k, $v := .Values.config.userPreferences.locked }}
{{- $_ := set $raw (printf "USERPREF_LOCKED__%s" $k) $v }}
{{- end }}

{{/* Drop nils, stringify the rest */}}
{{- $env := dict }}
{{- range $k, $v := $raw }}
{{- if not (kindIs "invalid" $v) }}
{{- $_ := set $env $k (toString $v) }}
{{- end }}
{{- end }}
{{- toYaml $env }}
{{- end }}

{{/*
Environment variables sourced from Secrets.
*/}}
{{- define "2fauth.secretEnv" -}}
{{- $chartSecret := include "2fauth.secretName" . -}}
- name: APP_KEY
  valueFrom:
    secretKeyRef:
      name: {{ default $chartSecret .Values.appKey.existingSecret }}
      key: {{ if .Values.appKey.existingSecret }}{{ .Values.appKey.existingSecretKey }}{{ else }}app-key{{ end }}
{{- if .Values.appKey.previousKeys }}
- name: APP_PREVIOUS_KEYS
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: app-previous-keys
{{- end }}
{{- if and (ne .Values.database.type "sqlite") (or .Values.database.password .Values.database.existingSecret) }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ default $chartSecret .Values.database.existingSecret }}
      key: {{ if .Values.database.existingSecret }}{{ .Values.database.existingSecretKey }}{{ else }}db-password{{ end }}
{{- end }}
{{- if or .Values.mail.password .Values.mail.existingSecret }}
- name: MAIL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ default $chartSecret .Values.mail.existingSecret }}
      key: {{ if .Values.mail.existingSecret }}{{ .Values.mail.existingSecretKey }}{{ else }}mail-password{{ end }}
{{- end }}
{{- if and (or (eq .Values.config.cacheDriver "redis") (eq .Values.config.sessionDriver "redis")) (or .Values.redis.password .Values.redis.existingSecret) }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ default $chartSecret .Values.redis.existingSecret }}
      key: {{ if .Values.redis.existingSecret }}{{ .Values.redis.existingSecretKey }}{{ else }}redis-password{{ end }}
{{- end }}
{{- if .Values.config.sso.openid.enabled }}
- name: OPENID_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ default $chartSecret .Values.config.sso.openid.existingSecret }}
      key: {{ if .Values.config.sso.openid.existingSecret }}{{ .Values.config.sso.openid.existingSecretKey }}{{ else }}openid-client-secret{{ end }}
{{- end }}
{{- if .Values.config.sso.github.enabled }}
- name: GITHUB_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ default $chartSecret .Values.config.sso.github.existingSecret }}
      key: {{ if .Values.config.sso.github.existingSecret }}{{ .Values.config.sso.github.existingSecretKey }}{{ else }}github-client-secret{{ end }}
{{- end }}
{{- end }}

{{/*
Refuse obviously broken or data-destroying configurations.
*/}}
{{- define "2fauth.validateValues" -}}
{{- $errors := list }}

{{- if not (has .Values.database.type (list "sqlite" "mysql" "pgsql" "sqlsrv")) }}
{{- $errors = append $errors (printf "database.type must be one of sqlite, mysql, pgsql, sqlsrv (got %q)" .Values.database.type) }}
{{- end }}

{{- if ne .Values.database.type "sqlite" }}
{{- if not .Values.database.host }}
{{- $errors = append $errors (printf "database.host is required when database.type is %q" .Values.database.type) }}
{{- end }}
{{- if not .Values.database.name }}
{{- $errors = append $errors (printf "database.name is required when database.type is %q" .Values.database.type) }}
{{- end }}
{{- end }}

{{/*
The entrypoint only skips `php artisan migrate:fresh` when it finds the
/2fauth/installed marker. On an external database an ephemeral volume would
therefore drop every table on each pod restart.
*/}}
{{- if and (not .Values.persistence.enabled) (ne .Values.database.type "sqlite") }}
{{- $errors = append $errors "persistence.enabled must be true when using an external database: without the persisted /2fauth/installed marker the entrypoint runs 'artisan migrate:fresh' on every start and DROPS ALL DATA" }}
{{- end }}

{{- if .Values.appKey.value }}
{{- if not (or (eq (len .Values.appKey.value) 32) (hasPrefix "base64:" .Values.appKey.value)) }}
{{- $errors = append $errors (printf "appKey.value must be exactly 32 characters or a 'base64:'-prefixed Laravel key (got %d characters)" (len .Values.appKey.value)) }}
{{- end }}
{{- end }}

{{- if gt (int .Values.replicaCount) 1 }}
{{- if eq .Values.database.type "sqlite" }}
{{- $errors = append $errors "replicaCount > 1 requires an external database: SQLite on a shared volume corrupts under concurrent writes" }}
{{- end }}
{{- if and .Values.persistence.enabled (not .Values.persistence.existingClaim) (not (has "ReadWriteMany" .Values.persistence.accessModes)) }}
{{- $errors = append $errors "replicaCount > 1 requires persistence.accessModes to include ReadWriteMany" }}
{{- end }}
{{- end }}

{{- if and (or (eq .Values.config.cacheDriver "redis") (eq .Values.config.sessionDriver "redis")) (not .Values.redis.host) }}
{{- $errors = append $errors "redis.host is required when cacheDriver or sessionDriver is 'redis'" }}
{{- end }}

{{- if and .Values.podDisruptionBudget.enabled .Values.podDisruptionBudget.minAvailable .Values.podDisruptionBudget.maxUnavailable }}
{{- $errors = append $errors "podDisruptionBudget.minAvailable and podDisruptionBudget.maxUnavailable are mutually exclusive" }}
{{- end }}

{{- if $errors }}
{{- fail (printf "\n\n2fauth chart: invalid values\n\n  - %s\n" (join "\n  - " $errors)) }}
{{- end }}
{{- end }}
