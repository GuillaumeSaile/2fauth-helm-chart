# 2FAuth Helm chart

Deploy [2FAuth](https://github.com/Bubka/2FAuth) — a self-hosted web app to manage
your Two-Factor Authentication accounts — on Kubernetes.

> **Unofficial.** This is a community chart, not affiliated with or endorsed by
> the 2FAuth project. Report chart issues here, not upstream.

2FAuth ships only bare-metal and Docker install paths upstream. This chart wraps
the official `2fauth/2fauth` image (nginx + PHP-FPM under supervisord, listening
on port 8000, running as uid/gid 1000) into a proper Kubernetes deployment.

## TL;DR

```sh
git clone <this repo> && cd <this repo>
helm install my-2fauth ./charts/2fauth \
  --namespace 2fauth --create-namespace \
  --set config.app.url=https://2fa.example.com \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=2fa.example.com
```

Then open the URL and register **straight away**: the first account created
becomes the administrator, and registration is open to anyone who can reach the
instance until you disable it in the admin settings. Consider keeping the
ingress private (VPN, IP allow-list) until you have registered.

## Requirements

- Kubernetes 1.21+ (uses `policy/v1` PDB and `networking.k8s.io/v1` Ingress)
- Helm 3.8+ (the chart uses `lookup` to keep `APP_KEY` stable across upgrades)
- A default StorageClass, or `persistence.storageClass` set

## Things that will bite you if you skip them

### 1. `APP_KEY` is the key to all your 2FA secrets

Every OTP secret in the database is encrypted with `APP_KEY`. Lose it and your
accounts are unrecoverable; change it and existing data stops decrypting.

By default the chart generates a 32-character key on install and stores it in
the `<release>-env` Secret. On every subsequent `helm upgrade` it reads the key
back out of that Secret and reuses it, so upgrades never rotate it — **but only
as long as that Secret survives**. A `helm uninstall` deletes it.

Back it up right after install:

```sh
kubectl -n 2fauth get secret my-2fauth-env -o jsonpath='{.data.app-key}' | base64 -d
```

Or manage it yourself:

```yaml
appKey:
  existingSecret: 2fauth-app-key
  existingSecretKey: app-key
```

> **Argo CD, `helm template | kubectl apply`, and anything else that renders
> without cluster access: you MUST set `appKey.existingSecret` (or
> `appKey.value`).** Those tools don't support Helm's `lookup`, so the chart
> can't see the existing key and generates a new one on every render — each
> sync would replace `APP_KEY` and make every stored 2FA secret unreadable.
> Flux's helm-controller and plain `helm install/upgrade` are unaffected.

Rotating the key later? Move the old one to `appKey.previousKeys` (comma
separated) so existing rows stay readable.

### 2. `config.app.url` must match the address users type

WebAuthn (passkeys, security keys) validates the origin. If `APP_URL` doesn't
match the browser's address bar exactly, WebAuthn registration and login fail.

When `ingress.enabled=true` the chart derives `APP_URL` from the first ingress
host (and uses `https` if that host appears in `ingress.tls`). Otherwise set
`config.app.url` explicitly.

### 3. Persistence is not optional for real installs

The image keeps all state under `/2fauth`:

| Path | Contents |
| --- | --- |
| `database.sqlite` | the database, when `database.type=sqlite` |
| `storage/` | Passport OAuth keys, uploaded icons, logs |
| `installed` | marker recording the commit of the last successful install |

The entrypoint only runs `php artisan migrate` when it finds the `installed`
marker. **Without it, it runs `php artisan migrate:fresh`, which drops every
table — including on an external database.** The chart refuses to render a
release that combines an external database with `persistence.enabled=false`
for exactly this reason.

Losing `storage/` alone is milder but still disruptive: all issued API tokens
are invalidated because the Passport signing keys are regenerated.

### 4. One replica

The startup sequence runs migrations, and the OAuth keys live on the volume.
Keep `replicaCount: 1` with the default `Recreate` strategy. The chart rejects
`replicaCount > 1` unless you use an external database *and* a ReadWriteMany
volume, and even then 2FAuth is not designed for horizontal scale.

## Configuration

Every 2FAuth environment variable documented at
<https://docs.2fauth.app/getting-started/config/env-vars/> is reachable. The
common ones have typed values (`config.*`); anything else goes through
`extraEnv`.

Values set to `null` are omitted from the rendered ConfigMap so 2FAuth falls
back to its own defaults.

### Key values

| Value | Default | Description |
| --- | --- | --- |
| `image.repository` | `2fauth/2fauth` | Image repository |
| `image.tag` | `""` (chart `appVersion`) | Image tag |
| `replicaCount` | `1` | Replicas; see above |
| `config.app.url` | `""` | `APP_URL`; derived from ingress when empty |
| `config.app.name` | `2FAuth` | `APP_NAME` |
| `config.app.env` | `local` | `APP_ENV`; `production` makes artisan prompt |
| `config.app.timezone` | `UTC` | `APP_TIMEZONE` |
| `config.app.siteOwner` | `mail@example.com` | `SITE_OWNER` |
| `config.log.channel` | `stderr` | `LOG_CHANNEL`; `stderr` surfaces app logs in `kubectl logs` |
| `config.log.level` | `notice` | `LOG_LEVEL` |
| `config.security.trustedProxies` | `"*"` | `TRUSTED_PROXIES`; needed behind an ingress controller |
| `config.auth.guard` | `web-guard` | `AUTHENTICATION_GUARD` |
| `config.webauthn.userVerification` | `preferred` | `WEBAUTHN_USER_VERIFICATION` |
| `appKey.value` | `""` | Explicit `APP_KEY`; generated when empty |
| `appKey.existingSecret` | `""` | Read `APP_KEY` from your own Secret |
| `database.type` | `sqlite` | `sqlite`, `mysql`, `pgsql` or `sqlsrv` |
| `persistence.enabled` | `true` | Mount a PVC at `/2fauth` |
| `persistence.size` | `1Gi` | Volume size |
| `persistence.retain` | `true` | Keep the PVC on `helm uninstall` |
| `service.type` / `service.port` | `ClusterIP` / `80` | Service exposure |
| `ingress.enabled` | `false` | Create an Ingress |
| `probes.path` | `/up` | 2FAuth's built-in health view |
| `resources.limits.memory` | `768Mi` | Keep above `config.security.phpMemoryLimitTempOverride` |

See [`values.yaml`](values.yaml) for the full annotated list, including SSO,
mail, Redis, NetworkPolicy, PDB, the scheduler CronJob and the usual scheduling knobs.

`values.schema.json` validates the important fields, and a template-level
validator rejects configurations that are outright broken or destructive
(missing DB host, external DB without persistence, bad `APP_KEY` length,
multi-replica on SQLite, Redis drivers without a Redis host).

## Recipes

### Behind an ingress with TLS

```yaml
config:
  app:
    url: https://2fa.example.com
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    # QR-code uploads need a body size above nginx's 1m default
    nginx.ingress.kubernetes.io/proxy-body-size: 10m
  hosts:
    - host: 2fa.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: 2fauth-tls
      hosts:
        - 2fa.example.com
```

### External PostgreSQL

```yaml
database:
  type: pgsql
  host: postgres.databases.svc.cluster.local
  port: 5432
  name: twofauth
  username: twofauth
  existingSecret: postgres-credentials
  existingSecretKey: password

# still required: Passport keys and the `installed` marker live here
persistence:
  enabled: true
  size: 1Gi
```

The chart does not bundle a database subchart, so it has no dependencies to
fetch. Point it at whatever operator or managed instance you already run.

### SMTP

```yaml
mail:
  mailer: smtp
  host: smtp.example.com
  port: 587
  encryption: tls
  username: 2fauth@example.com
  existingSecret: smtp-credentials
  existingSecretKey: password
  fromName: 2FAuth
  fromAddress: 2fauth@example.com
```

### SSO via OpenID Connect

```yaml
config:
  sso:
    openid:
      enabled: true
      authorizeUrl: https://idp.example.com/authorize
      tokenUrl: https://idp.example.com/token
      userinfoUrl: https://idp.example.com/userinfo
      clientId: 2fauth
      existingSecret: oidc-credentials
      existingSecretKey: client-secret
```

### Authentication handled by a reverse proxy

```yaml
config:
  auth:
    guard: reverse-proxy-guard
    proxyHeaderForUser: HTTP_X_FORWARDED_USER
    proxyHeaderForEmail: HTTP_X_FORWARDED_EMAIL
    proxyLogoutUrl: https://auth.example.com/logout
  security:
    trustedProxies: "*"
```

With this guard 2FAuth performs **no** authentication checks of its own — it
trusts those headers unconditionally. Make sure nothing can reach the Service
except your proxy; `networkPolicy.allowedIngress` is the tool for that.

### Enforcing user preferences

```yaml
config:
  userPreferences:
    defaults:
      THEME: dark
      SHOW_OTP_AS_DOT: true
    locked:
      THEME: true
```

Renders `USERPREF_DEFAULT__THEME`, `USERPREF_DEFAULT__SHOW_OTP_AS_DOT` and
`USERPREF_LOCKED__THEME`. Names come from
<https://docs.2fauth.app/getting-started/config/user-preferences/>.

### Subdirectory hosting

```yaml
config:
  app:
    url: https://example.org/2fa
    subdirectory: "2fa"
```

### The Laravel task scheduler

The upstream image runs only nginx and PHP-FPM under supervisord, so Laravel's
scheduler never fires — on Docker either. In 2FAuth 8.x the schedule contains a
single task, `cache:prune-stale-tags`, which does nothing unless the cache store
supports tags. So you only need this with Redis:

```yaml
config:
  cacheDriver: redis
redis:
  host: redis.cache.svc.cluster.local
scheduler:
  enabled: true
  schedule: "0 * * * *"
```

Authentication and OTP log retention do **not** depend on this — 2FAuth purges
those from the request path, so `config.auth.logRetention` and
`config.auth.otpLogRetention` work without any CronJob.

The job overrides the image entrypoint (which would otherwise migrate the
database and start supervisord), so the symlinks that entrypoint normally
creates are absent. Set `scheduler.mountData: true` if your command needs the
SQLite file or `storage/`; the chart then repoints `DB_DATABASE` at
`/2fauth/database.sqlite` for you. Note that with a ReadWriteOnce volume this
pins the job to the app pod's node.

### Locking down egress

```yaml
networkPolicy:
  enabled: true
  allowAllEgress: false          # DNS stays allowed automatically
  allowedIngress:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  extraEgress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: databases
      ports:
        - port: 5432
          protocol: TCP
```

Note that 2FAuth reaches out to the internet for release checks and for
fetching service logos; both are optional features you can disable in-app.

## Operations

### Verify a deployment

```sh
helm test my-2fauth -n 2fauth
```

Hits `/up` through the Service and asserts HTTP 200.

### Back up

```sh
kubectl -n 2fauth exec deploy/my-2fauth -- tar cf - -C /2fauth . > 2fauth-$(date +%F).tar
kubectl -n 2fauth get secret my-2fauth-env -o yaml > 2fauth-secret-$(date +%F).yaml
```

Back up both. The volume without the key is useless.

### Upgrade

```sh
helm upgrade my-2fauth ./charts/2fauth -n 2fauth --reuse-values
```

The entrypoint compares the image's commit against the `installed` marker and
runs `php artisan migrate` when they differ. Back up the database first — schema
migrations are not reversible.

### Run artisan commands

```sh
kubectl -n 2fauth exec -it deploy/my-2fauth -- php artisan 2fauth:check-db-connection
kubectl -n 2fauth exec -it deploy/my-2fauth -- php artisan 2fauth:fix-orphan
```

### Uninstall

```sh
helm uninstall my-2fauth -n 2fauth
```

The PVC is annotated `helm.sh/resource-policy: keep`, so your data survives.
Delete it deliberately:

```sh
kubectl -n 2fauth delete pvc my-2fauth-data
```

## What the chart creates

| Resource | Condition |
| --- | --- |
| Deployment | always |
| Service | always |
| ConfigMap (non-secret env) | always |
| Secret (chart-managed credentials) | unless every credential comes from an `existingSecret` |
| PersistentVolumeClaim | `persistence.enabled` and no `existingClaim` |
| ServiceAccount | `serviceAccount.create` |
| Ingress | `ingress.enabled` |
| CronJob (Laravel scheduler) | `scheduler.enabled` |
| NetworkPolicy | `networkPolicy.enabled` |
| PodDisruptionBudget | `podDisruptionBudget.enabled` |
| Test pod | `helm test` |

Components are separated by `app.kubernetes.io/component` (`application`,
`scheduler`, `test`), which is part of the Service selector — scheduler and test
pods never become Service endpoints.

## Implementation notes

- **Security context.** Runs as uid/gid 1000 non-root, all capabilities
  dropped, `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`,
  and the ServiceAccount token is not mounted.
- **`readOnlyRootFilesystem` is `false`** and cannot be turned on: the
  entrypoint rewrites symlinks under `/srv`, moves `storage/` onto the volume
  and caches the Laravel config at every start.
- **`fsGroup: 1000`** with `fsGroupChangePolicy: OnRootMismatch` makes the
  provisioned volume writable by the container user without re-chowning it on
  every restart.
- **Config changes roll the pods** via `checksum/config` and `checksum/secret`
  annotations — needed because the entrypoint bakes env vars into a cached
  Laravel config at boot.
- **Probes** all target `/up`, a route registered without session or CSRF
  middleware. The startup probe allows 5 minutes so the initial migration has
  room to finish before the liveness probe starts.

## License

The chart is licensed under [Apache-2.0](../../LICENSE). 2FAuth itself, including
the `2fauth/2fauth` image this chart deploys, is licensed under AGPL-3.0.
