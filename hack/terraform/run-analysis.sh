#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Re-runs the analysis over the three coverage dashboards, then writes the
# per-repository files and the summary. Usage:
#   hack/terraform/run-analysis.sh DIR   (DIR holds config-connector-extensions,
#                                         ack-extensions and aso-extensions checkouts)
set -euo pipefail
dir=${1:?directory with the three extensions checkouts}
here=$(cd "$(dirname "$0")/../.." && pwd)
run() { # cloud repo providers tag
  python3 "$here/hack/terraform/analyze.py" "$1" "$dir/$2-extensions/docs/coverage" \
    "$here/docs/terraform/data/$1" "$here/docs/terraform/data" \
    --overrides "$here/hack/terraform/overrides.csv" ${3:+--providers $3} ${4:+--tag $4} | head -1
}
run gcp config-connector google-beta -google-beta
run gcp config-connector google -google
run aws ack aws ""
run azure aso azurerm -azurerm
python3 "$here/hack/terraform/repo-files.py" "$dir"
