#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Regenerate docs/coverage and the README's coverage section (between
# <!-- coverage:start --> and <!-- coverage:end -->), or with --check fail
# when they differ from what is committed. Light: it downloads each
# tracked module's repository tarball at the pinned tag once (GET of
# codeload.github.com, spaced 300 ms apart, cached under .cache/upstream)
# and parses the HCL in Go (tools/tfmod).
#
#   hack/coverage/run.sh            write the outputs
#   hack/coverage/run.sh --check    exit 1 if they are out of date
#   hack/coverage/run.sh --offline  use only the cache (fail if a module is missing)
#   hack/coverage/run.sh verify     render each chart with its refused variables set
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)
exec bin/catalogtool coverage "$@"
