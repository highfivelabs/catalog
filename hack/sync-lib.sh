#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Copy the shared helpers into every chart's templates/ (a chart is
# published alone, so it carries its own copy): lib/_kcc.tpl into the
# Config Connector charts, lib/_ack.tpl into the ACK charts (charts/aws).
# hack/test.sh fails when a copy differs.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for c in "${ROOT}"/charts/*/*/Chart.yaml; do
  dir="$(dirname "$c")"
  case "$(basename "$(dirname "${dir}")")" in
    aws) cp "${ROOT}/lib/_ack.tpl" "${dir}/templates/_ack.tpl" ;;
    *) cp "${ROOT}/lib/_kcc.tpl" "${dir}/templates/_kcc.tpl" ;;
  esac
done
