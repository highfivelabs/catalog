#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Fetch the CRDs of the ACK controllers pinned in UPSTREAM.md ("ACK
# controllers") into .cache/ack/<controller>-<release>/ (a sparse, shallow
# checkout: only config/crd/bases), check each tag is the commit
# UPSTREAM.md names, and write kubeconform schemas from all of them to
# .cache/schemas-ack-<hash of the pins>/. Prints the schema directory.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Rows like: | `ec2-controller` | `v1.23.1` | `9303654c...` | ... |
PINS="$(sed -n 's/^| `\([a-z0-9]*-controller\)` | `\(v[0-9.]*\)` | `\([0-9a-f]\{40\}\)`.*/\1 \2 \3/p' "${ROOT}/UPSTREAM.md")"
[[ -n "${PINS}" ]] || { echo "ack.sh: no ACK controller rows in UPSTREAM.md" >&2; exit 1; }
HASH="$(printf '%s\n' "${PINS}" | (sha256sum 2>/dev/null || shasum -a 256) | cut -c1-12)"
SCHEMAS="${ROOT}/.cache/schemas-ack-${HASH}"
CRDS="${ROOT}/.cache/ack/crds-${HASH}"
if [[ ! -d "${SCHEMAS}" ]]; then
  rm -rf "${CRDS}"
  mkdir -p "${CRDS}"
  while read -r name version commit; do
    dir="${ROOT}/.cache/ack/${name}-${version}"
    if [[ ! -d "${dir}/config/crd/bases" ]]; then
      rm -rf "${dir}"
      git clone -q --filter=blob:none --no-checkout --depth 1 --branch "${version}" \
        "https://github.com/aws-controllers-k8s/${name}.git" "${dir}" >&2
      git -C "${dir}" sparse-checkout set config/crd/bases >&2
      git -C "${dir}" checkout -q "${version}" >&2
    fi
    got="$(git -C "${dir}" rev-parse HEAD)"
    [[ "${got}" == "${commit}" ]] || { echo "ack.sh: ${name} ${version} is ${got}, UPSTREAM.md says ${commit}" >&2; exit 1; }
    cp "${dir}"/config/crd/bases/*.yaml "${CRDS}/"
  done <<<"${PINS}"
  (cd "${ROOT}/tools" && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)
  "${ROOT}/bin/catalogtool" schemas "${CRDS}" "${SCHEMAS}" >&2
fi
echo "${SCHEMAS}"
