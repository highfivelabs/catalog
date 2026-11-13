#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The snapshots the fake-cloud and live runs read (task cce-snapshot,
# ackx-snapshot, asox-snapshot): a `git archive` of one commit of a sibling
# repository, in Cloud Storage.
#
#   hack/snapshot.sh upload REPO_DIR COMMIT gs://.../NAME.tar.gz
#   hack/snapshot.sh present gs://.../NAME.tar.gz   (the tasks' status:)
#
# upload writes the archive to a temporary file first, checks it is a
# non-empty gzip, and only then copies it up. Piping `git archive` straight
# into `gcloud storage cp -` made the object before the pipeline's failure
# was seen: from .worktrees/<task>, where ../<repo> does not resolve, it left
# a 0-byte object behind, which the status check then took as present.
# present succeeds only for an object of more than 0 bytes.
set -o errexit -o nounset -o pipefail

die() { echo "snapshot: $*" >&2; exit 1; }

case "${1:-}" in
  upload)
    [[ $# -eq 4 ]] || die "usage: $0 upload REPO_DIR COMMIT gs://BUCKET/NAME.tar.gz"
    repo="$2" commit="$3" dest="$4"
    [[ "${dest}" == gs://* ]] || die "${dest} is not a gs:// URL"
    git -C "${repo}" rev-parse --verify --quiet "${commit}^{commit}" >/dev/null \
      || die "${repo} has no commit ${commit} (is ${repo} a checkout of the repository, relative to $(pwd)?)"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/snapshot.XXXXXX")"
    trap 'rm -rf "${tmp}"' EXIT
    git -C "${repo}" archive --format=tar.gz "${commit}" >"${tmp}/s.tar.gz"
    [[ -s "${tmp}/s.tar.gz" ]] || die "git archive of ${repo} at ${commit} is empty"
    gzip -t "${tmp}/s.tar.gz" || die "git archive of ${repo} at ${commit} is not a valid gzip"
    gcloud storage cp --quiet "${tmp}/s.tar.gz" "${dest}"
    ;;
  present)
    [[ $# -eq 2 ]] || die "usage: $0 present gs://BUCKET/NAME.tar.gz"
    size="$(gcloud storage objects describe "$2" --format='value(size)' 2>/dev/null)" || exit 1
    [[ "${size}" =~ ^[0-9]+$ && "${size}" -gt 0 ]]
    ;;
  *) die "usage: $0 upload REPO_DIR COMMIT DEST | present DEST" ;;
esac
