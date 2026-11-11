#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The merge gate while GitHub Actions is off (the builder, 2026-11-11:
# "run those actions locally (or on the vm) prior to commit; keep the gh
# actions but disable for now").
#
#   hack/ci/gate.sh [SHA]      task ci [SHA=...]; the pre-push hook runs it
#
# For one commit (default HEAD) it runs what .github/workflows/ci.yml's
# pull-request job runs, `task check`, then posts the commit status
# `offload/ci` on that commit, with a link to the run's log. A pull request
# merges only when that status on its head is success (README.md, "The
# merge gate").
#
# It runs on this machine, not a VM: `task check` takes under a minute
# here (measured 2026-11-11), less than a Spot VM takes to boot, and the
# linters it runs (shellcheck, actionlint) are not on the offload image.
# It runs with ci.yml's pins: Go from go-version-file (GOTOOLCHAIN), and
# it fails unless task and every tool ci.yml pins by *_VERSION is
# installed at that version (task ci:tools installs them), and shellcheck
# is installed (ci.yml's runner has it), so that no check is skipped as
# "not installed".
#
# The commit is checked out into a temporary worktree first, so the run
# is of exactly SHA, whatever the working tree holds. The log is uploaded
# to the offload bucket (runs/<id>/log), which the status links to.
#
# GitHub takes a status only for a commit it has. When SHA is not on
# GitHub yet (the pre-push hook runs before the push), a passing run
# pushes SHA to the branch offload-ci/SHA, posts the status, and deletes
# the branch; a failing run posts nothing there (the push is refused).
#
# Environment: CI_NO_STATUS=1 (run, post nothing).
set -euo pipefail

# A git hook runs with GIT_DIR (and GIT_INDEX_FILE ...) set to this
# repository; a test that runs git in a directory of its own would then
# commit, branch and configure here instead (it did, 2026-11-11). Unset them.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

STATUS_CONTEXT=offload/ci
BUCKET=hfl-dev-514205-offload
PROJECT=hfl-dev-514205

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
die() { echo "gate: $*" >&2; exit 2; }

SHA="$(git rev-parse --verify "${1:-HEAD}^{commit}")" || die "no commit ${1:-HEAD}"
REPO="$(git remote get-url origin | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
[[ "$REPO" == */* ]] || die "origin is not a GitHub repository: $(git remote get-url origin)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}"/gate.XXXXXX)"
SRC="$TMP/src"
# shellcheck disable=SC2329 # run by the EXIT trap
cleanup() {
  git worktree remove --force "$SRC" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
git worktree add -q --detach "$SRC" "$SHA"
CI="$SRC/.github/workflows/ci.yml"

# pin NAME: ci.yml's env value of NAME (empty when it pins none).
pin() { sed -n -E "s/^  $1: *['\"]?([^'\" ]+)['\"]?.*/\1/p" "$CI" | head -n 1; }
# have TOOL WANT GOT: fail unless GOT names version WANT.
have() {
  [[ "$3" == *"${2#v}"* ]] || die "$1 is ${3:-not installed}; ci.yml pins $2"
  echo "gate: $1 $2"
}
command -v shellcheck >/dev/null || die "shellcheck is not installed (ci.yml's runner has it)"
v="$(pin TASK_VERSION)";        [[ -z "$v" ]] || have task "$v" "$(task --version 2>/dev/null || true)"
v="$(pin HELM_VERSION)";        [[ -z "$v" ]] || have helm "$v" "$(helm version --short 2>/dev/null || true)"
# A `go install`ed kubeconform (hack/ci/tools.sh) says "development" to
# -v; its module version is in its build info.
gomodver() { go version -m "$(command -v "$1")" 2>/dev/null | awk '$1 == "mod" {print $3}' || true; }
v="$(pin KUBECONFORM_VERSION)"; [[ -z "$v" ]] || have kubeconform "$v" "$(kubeconform -v 2>/dev/null || true) $(gomodver kubeconform)"
v="$(pin ACTIONLINT_VERSION)";  [[ -z "$v" ]] || have actionlint "$v" "$(actionlint -version 2>/dev/null || true)"
gomod="$(sed -n -E 's/.*go-version-file: *([^ ]+).*/\1/p' "$CI" | head -n 1)"
[[ -n "$gomod" ]] || die "ci.yml names no go-version-file"
gover="$(sed -n -E 's/^toolchain go([0-9.]+).*/\1/p' "$SRC/$gomod")"
[[ -n "$gover" ]] || gover="$(sed -n -E 's/^go ([0-9.]+).*/\1/p' "$SRC/$gomod")"
[[ -n "$gover" ]] || die "no go version in $gomod"
echo "gate: Go $gover ($gomod)"

id="local-$(basename "$REPO")-$(date -u +%m%d%H%M%S)-$RANDOM"
echo "gate: $REPO $SHA: task check ($id)"
start=$SECONDS
set +e
(cd "$SRC" && GOTOOLCHAIN="go$gover" task check) </dev/null 2>&1 | tee "$TMP/log"
rc=${PIPESTATUS[0]}
set -e
secs=$((SECONDS - start))

url=""
if gcloud storage cp --quiet "$TMP/log" "gs://$BUCKET/runs/$id/log"; then
  url="https://console.cloud.google.com/storage/browser/$BUCKET/runs/$id?project=$PROJECT"
else
  echo "gate: could not upload the log; the status will have no link" >&2
fi

if [[ $rc -eq 0 ]]; then state=success; verb=passed; else state=failure; verb="failed (exit $rc)"; fi
desc="task check (ci.yml pins, Go $gover): $verb locally in ${secs}s"
desc="${desc:0:140}"
echo "gate: $state: $desc${url:+ ($url)}"

post() {
  gh api "repos/$REPO/statuses/$SHA" -f state="$state" -f context="$STATUS_CONTEXT" \
    -f description="$desc" ${url:+-f target_url="$url"} --silent
  echo "gate: posted $STATUS_CONTEXT=$state on $SHA"
}
if [[ "${CI_NO_STATUS:-}" == 1 ]]; then
  echo "gate: CI_NO_STATUS=1: no status posted"
elif gh api "repos/$REPO/commits/$SHA" --silent 2>/dev/null; then
  post
elif [[ $rc -eq 0 ]]; then
  # Not on GitHub yet: put it there on a branch of its own (the hook
  # passes this push through: OFFLOAD_CI_VERIFIED), post, delete the branch.
  OFFLOAD_CI_VERIFIED="$SHA" git push -q origin "$SHA:refs/heads/offload-ci/$SHA"
  post
  OFFLOAD_CI_VERIFIED="$SHA" git push -q origin --delete "offload-ci/$SHA"
else
  echo "gate: $SHA is not on GitHub and failed: no status posted"
fi
exit "$rc"
