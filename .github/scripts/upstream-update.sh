#!/usr/bin/env bash
# Moves the chart to the newest 2FAuth release that is at least MIN_AGE_HOURS
# old, both on GitHub and on Docker Hub. The quarantine leaves time for a
# compromised or broken release to be noticed and pulled before we ship it.
#
# The chart version follows the size of the upstream bump:
#   9.0.0 -> 9.0.1   chart 2.0.0 -> 2.0.1
#   9.0.x -> 9.1.0   chart 2.0.x -> 2.1.0
#   9.x.x -> 10.0.0  chart 2.x.x -> 3.0.0
#
# Stops with an error if upstream changed its Laravel task schedule, which the
# chart's scheduler docs depend on.
#
# Edits Chart.yaml and every tracked Markdown file in place. In GitHub Actions it also writes
# `updated`, `app_version` and `chart_version` to $GITHUB_OUTPUT.
#
# Usage: .github/scripts/upstream-update.sh [chart-dir]
# Needs: gh (authenticated), curl, jq.
set -euo pipefail

CHART="${1:-charts/2fauth}"
UPSTREAM_REPO="${UPSTREAM_REPO:-Bubka/2FAuth}"
IMAGE_REPO="${IMAGE_REPO:-2fauth/2fauth}"
MIN_AGE_HOURS="${MIN_AGE_HOURS:-48}"
# What the chart's docs and its opt-in scheduler CronJob assume 2FAuth
# schedules. If upstream changes it, a human has to review the chart first.
EXPECTED_SCHEDULE="\$schedule->command('cache:prune-stale-tags')->hourly();"

output() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1=$2" >> "${GITHUB_OUTPUT}"; return 0; }

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
current_app=$(awk '/^appVersion:/ {gsub(/"/, "", $2); print $2}' "${CHART}/Chart.yaml")
current_chart=$(awk '/^version:/ {print $2}' "${CHART}/Chart.yaml")
for v in "${current_app}" "${current_chart}"; do
  [[ "${v}" =~ ${semver_re} ]] || { echo "::error::'${v}' in Chart.yaml is not plain x.y.z"; exit 1; }
done
echo "Current: chart ${current_chart}, 2FAuth ${current_app}"

# Stable releases (no drafts, prereleases or odd tags) that have been public
# for at least MIN_AGE_HOURS, newest version first.
candidates=$(
  gh api --paginate "repos/${UPSTREAM_REPO}/releases?per_page=100" --jq '.[]' |
    jq -r --argjson min_age "$((MIN_AGE_HOURS * 3600))" '
      select(.draft | not) | select(.prerelease | not)
      | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | select((.published_at | fromdateiso8601) <= (now - $min_age))
      | .tag_name | ltrimstr("v")' |
    sort -rV
)

newer_than_current() { [[ "$1" != "${current_app}" && "$(printf '%s\n%s\n' "$1" "${current_app}" | sort -V | tail -n1)" == "$1" ]]; }

# Docker Hub must have had the image for MIN_AGE_HOURS too: that is what
# users actually run. Prints nothing if the tag is missing or too fresh.
image_old_enough() {
  curl -fsS "https://hub.docker.com/v2/repositories/${IMAGE_REPO}/tags/$1" 2>/dev/null |
    jq -r --argjson min_age "$((MIN_AGE_HOURS * 3600))" '
      .tag_last_pushed // empty | sub("\\.[0-9]+Z$"; "Z")
      | select(fromdateiso8601 <= (now - $min_age)) | "ok"' 2>/dev/null || true
}

target=""
for v in ${candidates}; do
  newer_than_current "${v}" || break # sorted newest first: the rest are older
  if [[ "$(image_old_enough "${v}")" == "ok" ]]; then
    target="${v}"
    break
  fi
  echo "::notice::2FAuth ${v} is old enough on GitHub but ${IMAGE_REPO}:${v} is missing or newer than ${MIN_AGE_HOURS}h on Docker Hub; skipping."
done

if [[ -z "${target}" ]]; then
  echo "No 2FAuth release newer than ${current_app} has passed the ${MIN_AGE_HOURS}h quarantine."
  output updated false
  exit 0
fi

schedule=$(
  gh api "repos/${UPSTREAM_REPO}/contents/app/Console/Kernel.php?ref=v${target}" --jq .content |
    base64 -d | grep -F '$schedule->' | sed -E 's/^[[:space:]]+//' || true
)
if [[ "${schedule}" != "${EXPECTED_SCHEDULE}" ]]; then
  echo "::error::2FAuth ${target} changed its task schedule (app/Console/Kernel.php). The chart documents the scheduler as optional and only useful with Redis; review that (README, values.yaml, templates/cronjob-scheduler.yaml), update EXPECTED_SCHEDULE in $0, then rerun."
  echo "Expected: ${EXPECTED_SCHEDULE}"
  echo "Found:"; echo "${schedule:-<nothing>}"
  exit 1
fi

IFS=. read -r a_maj a_min _ <<<"${current_app}"
IFS=. read -r t_maj t_min _ <<<"${target}"
IFS=. read -r c_maj c_min c_pat <<<"${current_chart}"
if ((t_maj != a_maj)); then
  new_chart="$((c_maj + 1)).0.0"
elif ((t_min != a_min)); then
  new_chart="${c_maj}.$((c_min + 1)).0"
else
  new_chart="${c_maj}.${c_min}.$((c_pat + 1))"
fi
echo "Updating: 2FAuth ${current_app} -> ${target}, chart ${current_chart} -> ${new_chart}"

# Portable in-place edit (GNU and BSD sed disagree on -i).
edit() { local f="$1"; shift; sed -E "$@" "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"; }

edit "${CHART}/Chart.yaml" \
  -e "s/^version: .*/version: ${new_chart}/" \
  -e "s/^appVersion: .*/appVersion: \"${target}\"/"

# Install snippets and the "deploys 2FAuth" line, in every tracked doc.
git ls-files -z -- '*.md' | while IFS= read -r -d '' doc; do
  edit "${doc}" \
    -e "s/(--version )[0-9]+\.[0-9]+\.[0-9]+/\1${new_chart}/g" \
    -e "s#(The current chart, \`)[^\`]+(\`, deploys 2FAuth \[\`)[^\`]+(\`\]\(https://github.com/${UPSTREAM_REPO}/releases/tag/v)[^)]+\)#\1${new_chart}\2${target}\3${target})#"
done

# Same check CI runs: anything we failed to rewrite stops the update here.
"$(dirname "$0")/check-versions.sh" "${CHART}"

output updated true
output app_version "${target}"
output chart_version "${new_chart}"
