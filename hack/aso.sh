#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Fetch Azure Service Operator's CRDs at the release in UPSTREAM.md (the
# release's azureserviceoperator_customresourcedefinitions_<v>.yaml, one
# GET, checked against the SHA-256 there) into .cache/aso-<version>/, keep
# the CRDs of the API groups the Azure charts render, and write kubeconform
# schemas from them to .cache/schemas-aso-<version>/. Prints the schema
# directory. The ASO counterpart of hack/kcc.sh.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^| Azure Service Operator release | `v\([0-9.]*\)`.*/\1/p' "${ROOT}/UPSTREAM.md")"
SUM="$(sed -n 's/^| Azure Service Operator CRDs SHA-256 | `\([0-9a-f]*\)`.*/\1/p' "${ROOT}/UPSTREAM.md")"
[[ -n "${VERSION}" && -n "${SUM}" ]] || { echo "aso.sh: no Azure Service Operator release in UPSTREAM.md" >&2; exit 1; }
# The ASO API groups (<group>.azure.com) the Azure charts render. A chart
# that renders a kind of another group adds it here.
GROUPS_USED="resources network storage keyvault authorization insights managedidentity operationalinsights containerregistry"
DIR="${ROOT}/.cache/aso-${VERSION}"
SCHEMAS="${ROOT}/.cache/schemas-aso-${VERSION}"
BUNDLE="${DIR}/azureserviceoperator_customresourcedefinitions_v${VERSION}.yaml"
URL="https://github.com/Azure/azure-service-operator/releases/download/v${VERSION}/azureserviceoperator_customresourcedefinitions_v${VERSION}.yaml"
mkdir -p "${DIR}"
if [[ ! -f "${BUNDLE}" ]]; then
  curl -sSfL --retry 3 -o "${BUNDLE}.part" "${URL}" >&2
  mv "${BUNDLE}.part" "${BUNDLE}"
fi
if command -v sha256sum >/dev/null; then got="$(sha256sum "${BUNDLE}" | cut -d' ' -f1)"; else got="$(shasum -a 256 "${BUNDLE}" | cut -d' ' -f1)"; fi
[[ "${got}" == "${SUM}" ]] || { echo "aso.sh: ${BUNDLE} has SHA-256 ${got}, UPSTREAM.md says ${SUM}" >&2; rm -f "${BUNDLE}"; exit 1; }
stamp="${SCHEMAS}/.groups"
if [[ ! -f "${stamp}" || "$(cat "${stamp}")" != "${GROUPS_USED}" ]]; then
  rm -rf "${DIR}/crds" "${SCHEMAS}"
  mkdir -p "${DIR}/crds"
  # One file per CRD (the bundle is one YAML stream), keeping the groups above.
  awk -v groups=" ${GROUPS_USED} " -v out="${DIR}/crds" '
    function flush(   i) { if (m > 0 && keep) { n++; f = sprintf("%s/%04d.yaml", out, n); for (i = 1; i <= m; i++) print lines[i] > f; close(f) } m = 0; keep = 0 }
    /^---/ { flush(); next }
    { lines[++m] = $0 }
    /^  group: / { g = $2; sub(/\.azure\.com$/, "", g); if (index(groups, " " g " ") > 0 && $2 ~ /\.azure\.com$/) keep = 1 }
    END { flush() }
  ' "${BUNDLE}"
  (cd "${ROOT}/tools" && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)
  "${ROOT}/bin/catalogtool" schemas "${DIR}/crds" "${SCHEMAS}" >&2
  echo "${GROUPS_USED}" >"${stamp}"
fi
echo "${SCHEMAS}"
