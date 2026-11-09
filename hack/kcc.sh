#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Fetch Config Connector's CRDs at the release in UPSTREAM.md into
# .cache/kcc-<version>/ (a sparse, shallow checkout: only config/crds),
# and write kubeconform schemas from them to .cache/schemas-<version>/.
# Prints the CRD directory.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^| Config Connector release | `v\([0-9.]*\)`.*/\1/p' "${ROOT}/UPSTREAM.md")"
COMMIT="$(sed -n 's/^| Config Connector commit | `\([0-9a-f]*\)`.*/\1/p' "${ROOT}/UPSTREAM.md")"
[[ -n "${VERSION}" && -n "${COMMIT}" ]] || { echo "kcc.sh: no Config Connector release in UPSTREAM.md" >&2; exit 1; }
DIR="${ROOT}/.cache/kcc-${VERSION}"
SCHEMAS="${ROOT}/.cache/schemas-${VERSION}"
if [[ ! -d "${DIR}/config/crds/resources" ]]; then
  rm -rf "${DIR}"
  git clone -q --filter=blob:none --no-checkout --depth 1 --branch "v${VERSION}" \
    https://github.com/GoogleCloudPlatform/k8s-config-connector.git "${DIR}" >&2
  git -C "${DIR}" sparse-checkout set config/crds/resources >&2
  git -C "${DIR}" checkout -q "v${VERSION}" >&2
fi
got="$(git -C "${DIR}" rev-parse HEAD)"
[[ "${got}" == "${COMMIT}" ]] || { echo "kcc.sh: v${VERSION} is ${got}, UPSTREAM.md says ${COMMIT}" >&2; exit 1; }
if [[ ! -d "${SCHEMAS}" ]]; then
  (cd "${ROOT}/tools" && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)
  "${ROOT}/bin/catalogtool" schemas "${DIR}/config/crds/resources" "${SCHEMAS}" >&2
fi
echo "${DIR}/config/crds/resources"
