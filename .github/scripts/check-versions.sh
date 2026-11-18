#!/usr/bin/env bash
# Fails if any doc quotes a chart or 2FAuth version that differs from
# Chart.yaml. Checks every tracked Markdown file for:
#   --version X.Y.Z                         (install snippets)  -> version
#   The current chart, `X`, deploys 2FAuth [`Y`](…/releases/tag/vY)
#                                                               -> version / appVersion
#
# Usage: .github/scripts/check-versions.sh [chart-dir]
set -euo pipefail

CHART="${1:-charts/2fauth}"
version=$(awk '/^version:/ {print $2}' "${CHART}/Chart.yaml")
app_version=$(awk '/^appVersion:/ {gsub(/"/, "", $2); print $2}' "${CHART}/Chart.yaml")
echo "Chart.yaml: version ${version}, appVersion ${app_version}"

status=0
fail() { echo "::error file=$1,line=$2::$3"; status=1; }

while IFS=: read -r file line text; do
  found=$(grep -oE -- '--version [0-9]+\.[0-9]+\.[0-9]+' <<<"${text}" | awk '{print $2}')
  [[ "${found}" == "${version}" ]] || fail "${file}" "${line}" "install snippet says --version ${found}, Chart.yaml says ${version}"
done < <(git grep -nE -- '--version [0-9]+\.[0-9]+\.[0-9]+' -- '*.md' || true)

while IFS=: read -r file line text; do
  expected="The current chart, \`${version}\`, deploys 2FAuth [\`${app_version}\`](https://github.com/Bubka/2FAuth/releases/tag/v${app_version})."
  [[ "${text}" == "${expected}" ]] || fail "${file}" "${line}" "expected: ${expected}"
done < <(git grep -n 'The current chart, `' -- '*.md' || true)

((status == 0)) && echo "All version references match Chart.yaml."
exit "${status}"
