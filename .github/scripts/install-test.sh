#!/usr/bin/env bash
# End-to-end test against the current kube context:
#   install -> helm test -> upgrade -> assert APP_KEY survived -> helm test
#   -> (if enabled) run the scheduler CronJob once -> uninstall.
#
# Usage: .github/scripts/install-test.sh <values-file> [chart-dir]
set -euo pipefail

VALUES="${1:?usage: $0 <values-file> [chart-dir]}"
CHART="${2:-charts/2fauth}"
SCENARIO="$(basename "${VALUES}" -values.yaml)"
NAMESPACE="2fauth-ci-${SCENARIO}"
RELEASE="ci"
FULLNAME="${RELEASE}-2fauth"
TIMEOUT="10m"

diagnostics() {
  echo "::group::diagnostics (${NAMESPACE})"
  kubectl -n "${NAMESPACE}" get all,pvc,secret,configmap,networkpolicy,ingress -o wide || true
  kubectl -n "${NAMESPACE}" describe pods || true
  kubectl -n "${NAMESPACE}" logs -l app.kubernetes.io/instance="${RELEASE}" --all-containers --tail=200 --prefix || true
  kubectl -n "${NAMESPACE}" get events --sort-by=.lastTimestamp || true
  echo "::endgroup::"
}
trap 'diagnostics' ERR

app_key() {
  kubectl -n "${NAMESPACE}" get secret "${FULLNAME}-env" -o jsonpath='{.data.app-key}'
}

echo "::group::install (${SCENARIO})"
helm install "${RELEASE}" "${CHART}" -n "${NAMESPACE}" --create-namespace \
  -f "${VALUES}" --wait --timeout "${TIMEOUT}"
echo "::endgroup::"

echo "::group::helm test after install"
helm test "${RELEASE}" -n "${NAMESPACE}" --logs --timeout 5m
echo "::endgroup::"

key_before="$(app_key)"
test -n "${key_before}" || { echo "::error::APP_KEY missing after install"; exit 1; }

echo "::group::upgrade with a config change"
helm upgrade "${RELEASE}" "${CHART}" -n "${NAMESPACE}" \
  -f "${VALUES}" --set config.app.name=CI-Upgraded --wait --timeout "${TIMEOUT}"
echo "::endgroup::"

key_after="$(app_key)"
if [ "${key_before}" != "${key_after}" ]; then
  echo "::error::APP_KEY changed across helm upgrade — stored 2FA secrets would become unreadable"
  exit 1
fi
echo "ok: APP_KEY preserved across upgrade"

app_name="$(kubectl -n "${NAMESPACE}" exec "deploy/${FULLNAME}" -- printenv APP_NAME)"
if [ "${app_name}" != "CI-Upgraded" ]; then
  echo "::error::config change did not reach the pod (APP_NAME=${app_name}); checksum rollout broken?"
  exit 1
fi
echo "ok: config change rolled out to the pod"

echo "::group::helm test after upgrade"
helm test "${RELEASE}" -n "${NAMESPACE}" --logs --timeout 5m
echo "::endgroup::"

if kubectl -n "${NAMESPACE}" get cronjob "${FULLNAME}-scheduler" >/dev/null 2>&1; then
  echo "::group::run the scheduler CronJob once"
  kubectl -n "${NAMESPACE}" create job scheduler-manual --from="cronjob/${FULLNAME}-scheduler"
  kubectl -n "${NAMESPACE}" wait --for=condition=complete job/scheduler-manual --timeout=5m
  kubectl -n "${NAMESPACE}" logs job/scheduler-manual
  echo "::endgroup::"
fi

echo "::group::uninstall"
helm uninstall "${RELEASE}" -n "${NAMESPACE}" --wait --timeout 5m
kubectl delete namespace "${NAMESPACE}" --wait=false
echo "::endgroup::"

echo "Scenario '${SCENARIO}' passed."
