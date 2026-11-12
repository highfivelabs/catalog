#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Keep ONE open tracking issue in this repository with the report of
# `task upstream-watch` (docs/upstream-status.md describes it):
# upstream-watch.yml's last step, also runnable by hand.
#
#   hack/upstream-watch-issue.sh STATUS_JSON ISSUE_MD
#
# STATUS_JSON and ISSUE_MD are what `catalogtool upstream watch --json
# ... --issue ...` wrote. With modules behind their pins it creates or
# updates the issue labelled upstream-watch; with none it closes it.
# It writes only this repository's issues (GH_REPO, default the origin
# remote's repository), with gh's token: GH_TOKEN in the workflow.
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 STATUS_JSON ISSUE_MD" >&2; exit 2; }
json="$1" issue="$2"

title="Upstream releases to take"
label="upstream-watch"
behind="$(jq '.behind | length' "${json}")"
gh label create "${label}" --color 0e8a16 --description "Reports of newer upstream module releases" --force >/dev/null
number="$(gh issue list --state open --label "${label}" --json number --jq '.[0].number // empty')"
if [[ -n "${number}" ]]; then
  if [[ "${behind}" -gt 0 ]]; then
    gh issue edit "${number}" --title "${title}" --body-file "${issue}"
    echo "updated issue #${number}: ${behind} modules behind"
  else
    gh issue edit "${number}" --body-file "${issue}"
    gh issue close "${number}" --comment "Every tracked module is at its latest release."
    echo "closed issue #${number}"
  fi
elif [[ "${behind}" -gt 0 ]]; then
  gh issue create --title "${title}" --label "${label}" --body-file "${issue}"
else
  echo "nothing behind, no issue open"
fi
