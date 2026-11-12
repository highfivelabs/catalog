#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# terraform fmt, init (no backend) and validate for every fixture. Needs no
# cloud credentials. Run on an offload VM:
#   offload run --machine e2-standard-4 -- offramp/hack/validate.sh
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_VERSION="${TF_VERSION:-1.17.1}"
if ! command -v terraform >/dev/null || [[ "$(terraform version -json | jq -r .terraform_version)" != "${TF_VERSION}" ]]; then
  curl -sfLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  python3 -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract("terraform", "/usr/local/bin")' /tmp/tf.zip
  chmod +x /usr/local/bin/terraform
fi
failed=0
for d in "${ROOT}"/offramp/fixtures/*/; do
  name="$(basename "${d}")"
  work="$(mktemp -d)"
  cp "${d}"*.tf "${work}/"
  if ! terraform -chdir="${work}" fmt -check -diff >"${work}/fmt.log" 2>&1; then
    echo "${name}: terraform fmt differs"; cat "${work}/fmt.log"; failed=$((failed + 1))
  fi
  if terraform -chdir="${work}" init -backend=false -input=false -no-color >"${work}/init.log" 2>&1 &&
    terraform -chdir="${work}" validate -no-color >"${work}/validate.log" 2>&1; then
    echo "${name}: valid ($(grep -h -oE 'Installed hashicorp/google v[0-9.]+' "${work}/init.log" | head -1); modules: $(grep -c 'Downloading registry' "${work}/init.log" || true))"
  else
    echo "${name}: INVALID"; cat "${work}/init.log" "${work}/validate.log" 2>/dev/null | grep -A6 -i error; failed=$((failed + 1))
  fi
done
exit "${failed}"
