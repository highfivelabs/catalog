#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Exports the schemas of the pinned Terraform providers with OpenTofu and
# flattens them into CSVs (hack/terraform/flatten.py). Heavy (the AWS
# provider's schema is a few hundred MB of JSON), so run it on an offload
# VM, never on a laptop:
#
#   ../offload/offload run --machine e2-standard-4 -- hack/terraform/export-schemas.sh
#
# Writes offload-artifacts/terraform/: <cloud>.attributes.csv.gz,
# <cloud>.tf-resources.csv, versions.txt. Needs network (OpenTofu releases and
# registry.opentofu.org); no cloud credentials.
set -euo pipefail

TOFU_VERSION=1.13.9
# The pins of docs/terraform-leverage.md ("Pinned sources").
GOOGLE=8.10.0
AWS=6.72.0
AZURERM=5.13.0
AZAPI=2.13.0

root=$(cd "$(dirname "$0")/../.." && pwd)
out=$root/offload-artifacts/terraform
work=$(mktemp -d)
mkdir -p "$out"
cd "$work"

if ! command -v tofu >/dev/null; then
  base=https://github.com/opentofu/opentofu/releases/download/v$TOFU_VERSION
  curl -fsSLO "$base/tofu_${TOFU_VERSION}_linux_amd64.zip"
  curl -fsSLO "$base/tofu_${TOFU_VERSION}_SHA256SUMS"
  grep "tofu_${TOFU_VERSION}_linux_amd64.zip" "tofu_${TOFU_VERSION}_SHA256SUMS" | sha256sum -c -
  python3 -c "import zipfile;zipfile.ZipFile('tofu_${TOFU_VERSION}_linux_amd64.zip').extract('tofu')"
  chmod +x tofu
  export PATH=$work:$PATH
fi
tofu version | head -1 | tee "$out/versions.txt"

export_one() { # name provider-block...
  local name=$1; shift
  mkdir -p "$work/$name"
  (cd "$work/$name"
   {
     printf 'terraform {\n  required_providers {\n'
     printf '    %s\n' "$@"
     printf '  }\n}\n'
   } > main.tf
   tofu init -input=false -no-color >init.log 2>&1 || { cat init.log; exit 1; }
   tofu providers schema -json > schema.json
   ls -l schema.json
   grep -h 'Installed\|Installing' init.log | tee -a "$out/versions.txt"
   python3 "$root/hack/terraform/flatten.py" schema.json "$out/$name")
}

export_one gcp \
  "google = { source = \"hashicorp/google\", version = \"$GOOGLE\" }" \
  "google-beta = { source = \"hashicorp/google-beta\", version = \"$GOOGLE\" }"
export_one aws "aws = { source = \"hashicorp/aws\", version = \"$AWS\" }"
export_one azure \
  "azurerm = { source = \"hashicorp/azurerm\", version = \"$AZURERM\" }" \
  "azapi = { source = \"Azure/azapi\", version = \"$AZAPI\" }"

ls -l "$out"

# Azure: which ARM resource type each azurerm resource uses. The provider's
# source imports go-azure-sdk/resource-manager/<service>/<api-version>/<type>
# (the package is the lower-case last segment of the ARM type), and the
# resource's file is <name>_resource.go. Read from the tagged source, not
# from the schema (which has no such link). Output: azure.sdkmap.csv
# (tf_resource, sdk_service, sdk_package; one row for each import).
git clone -q --depth 1 --branch "v$AZURERM" https://github.com/hashicorp/terraform-provider-azurerm "$work/azurerm-src"
python3 - "$work/azurerm-src" "$out/azure.sdkmap.csv" <<'PY'
import csv, os, re, sys
src, outf = sys.argv[1], sys.argv[2]
rows = set()
imp = re.compile(r'go-azure-sdk/resource-manager/([a-z0-9]+)/([0-9a-z-]+)/([a-z0-9]+)"')
for root, _, files in os.walk(os.path.join(src, "internal/services")):
    for f in files:
        if not f.endswith("_resource.go") or f.endswith("_test.go"):
            continue
        text = open(os.path.join(root, f), errors="replace").read()
        names = set(re.findall(r'return "(azurerm_[a-z0-9_]+)"', text)) or {"azurerm_" + f[: -len("_resource.go")]}
        for n in names:
            for svc, _ver, pkg in imp.findall(text):
                rows.add((n, svc, pkg))
with open(outf, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["tf_resource", "sdk_service", "sdk_package"])
    w.writerows(sorted(rows))
print(outf, len(rows), "imports")
PY
