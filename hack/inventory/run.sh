#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Regenerate the tables of docs/gcp-inventory.md (everything after the
# "generated below" marker) from fabric and Config Connector at the
# commits in UPSTREAM.md. Light: shallow, sparse clones and Python with
# PyYAML (through uv).
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="${ROOT}/hack/inventory"
WORK="${ROOT}/.cache/inventory"
row() { sed -n "s/^| $1 | \`\([^\`]*\)\`.*/\1/p" "${ROOT}/UPSTREAM.md"; }
FABRIC_TAG="$(row 'Fabric release')"; FABRIC_COMMIT="$(row 'Fabric commit')"
KCC_TAG="$(row 'Config Connector release')"; KCC_COMMIT="$(row 'Config Connector commit')"
mkdir -p "${WORK}"
fetch() { # dir repo tag commit paths...
  local dir="$1" repo="$2" tag="$3" commit="$4"; shift 4
  if [[ ! -d "${dir}/.git" ]]; then
    git clone -q --filter=blob:none --no-checkout --depth 1 --branch "${tag}" "${repo}" "${dir}"
    git -C "${dir}" sparse-checkout set "$@"
    git -C "${dir}" checkout -q "${tag}"
  fi
  [[ "$(git -C "${dir}" rev-parse HEAD)" == "${commit}" ]] || { echo "inventory: ${dir} is not ${commit}" >&2; exit 1; }
}
fetch "${WORK}/fabric" https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git "${FABRIC_TAG}" "${FABRIC_COMMIT}" modules
fetch "${WORK}/kcc" https://github.com/GoogleCloudPlatform/k8s-config-connector.git "${KCC_TAG}" "${KCC_COMMIT}" config/crds/resources config/servicemappings
py() { uv run -q --no-project --with pyyaml python -I "$@"; }
py "${HERE}/extract.py" "${WORK}/fabric" "${WORK}/kcc" "${WORK}/data.json"
py "${HERE}/classify.py" "${WORK}/data.json" "${HERE}" "${WORK}/cls.json"
for m in "${WORK}"/fabric/modules/*/; do
  m="$(basename "$m")"
  printf '%s|%s\n' "$m" "$(sed -n '1,12p' "${WORK}/fabric/modules/$m/README.md" 2>/dev/null | grep -v '^#' | grep -v '^\s*$' | grep -v '^<!--\|^- \[' | head -1 | cut -c1-140)"
done >"${WORK}/desc.txt"
(cd "${WORK}" && py "${HERE}/gen.py" "${WORK}/body.md" "${ROOT}/upstream/modules.yaml")
doc="${ROOT}/docs/gcp-inventory.md"
marker='<!-- generated below by hack/inventory/run.sh; edit above this line -->'
{ sed "/^${marker//\//\\/}\$/,\$d" "${doc}"; echo "${marker}"; echo; cat "${WORK}/body.md"; } >"${doc}.new"
mv "${doc}.new" "${doc}"
echo "inventory: wrote ${doc}"
