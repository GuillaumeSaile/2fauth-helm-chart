#!/usr/bin/env bash
# Static checks: lint and render every CI scenario, then make sure the chart's
# guardrails still reject the configurations they are meant to reject.
#
# Usage: .github/scripts/lint.sh [chart-dir]
set -euo pipefail

CHART="${1:-charts/2fauth}"

echo "::group::helm lint (defaults)"
helm lint --strict "${CHART}"
echo "::endgroup::"

for values in "${CHART}"/ci/*-values.yaml; do
  echo "::group::helm lint + template (${values})"
  helm lint --strict "${CHART}" -f "${values}"
  helm template ci "${CHART}" -f "${values}" > /dev/null
  echo "::endgroup::"
done

# expect_failure <expected message fragment> <helm --set args...>
expect_failure() {
  local expected="$1"; shift
  local output
  if output=$(helm template ci "${CHART}" "$@" 2>&1); then
    echo "::error::expected rendering to fail with '${expected}' for: $*"
    return 1
  fi
  if ! grep -qF -- "${expected}" <<<"${output}"; then
    echo "::error::rendering failed for: $*, but not with '${expected}'"
    echo "${output}"
    return 1
  fi
  echo "ok: rejected ($*)"
}

echo "::group::guardrails"
expect_failure "DROPS ALL DATA" \
  --set database.type=pgsql --set database.host=db --set database.name=db --set persistence.enabled=false
expect_failure "requires an external database" \
  --set replicaCount=2
expect_failure "appKey.value must be exactly 32 characters" \
  --set appKey.value=tooshort
expect_failure "database.host is required" \
  --set database.type=mysql --set database.name=db
expect_failure "redis.host is required" \
  --set config.cacheDriver=redis
echo "::endgroup::"

echo "All static checks passed."
