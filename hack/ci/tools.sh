#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The tools ci.yml's check job installs, at the versions ci.yml pins
# (its env: TASK_VERSION, HELM_VERSION, KUBECONFORM_VERSION,
# ACTIONLINT_VERSION), into one directory. ci.yml's "Install kubeconform
# and actionlint" step runs this script; on a laptop, `task ci:tools` does.
#
#   hack/ci/tools.sh [TOOL...]   task, helm, kubeconform, actionlint (default: all)
#
# The directory is $HFL_TOOLS (default ~/.local/hfl-tools, the path
# ci.yml caches). Put it first on PATH; hack/ci/gate.sh fails unless the
# tools it finds are these versions. kubeconform and actionlint are built
# with `go install` as ci.yml always did (GOTOOLCHAIN=auto: kubeconform
# v0.8.0 needs a newer Go than tools/go.mod's); task and helm are their
# release binaries for this OS and CPU. shellcheck is not pinned (ci.yml
# takes the runner image's): install it with your package manager.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI="$ROOT/.github/workflows/ci.yml"
DIR="${HFL_TOOLS:-$HOME/.local/hfl-tools}"
die() { echo "tools: $*" >&2; exit 2; }

# pin NAME: ci.yml's env value of NAME.
pin() {
  local v
  v="$(sed -n -E "s/^  $1: *['\"]?([^'\" ]+)['\"]?.*/\1/p" "$CI" | head -n 1)"
  [[ -n "$v" ]] || die "ci.yml pins no $1"
  echo "$v"
}

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) die "unsupported CPU $(uname -m)" ;;
esac

# current BIN WANT VERSION_ARGS...: true when $DIR/BIN reports version WANT.
current() {
  local bin="$DIR/$1" want="${2#v}"; shift 2
  [[ -x "$bin" ]] || return 1
  local got
  got="$("$bin" "$@" 2>/dev/null || true)"
  [[ "$got" == *"$want"* ]]
}

install_task() {
  local v; v="$(pin TASK_VERSION)"
  if current task "$v" --version; then echo "tools: task $v (already)"; return; fi
  local tgz="$DIR/.task.tgz"
  curl -fsSL -o "$tgz" "https://github.com/go-task/task/releases/download/v${v#v}/task_${os}_${arch}.tar.gz"
  tar -xzf "$tgz" -C "$DIR" task
  rm -f "$tgz"
  echo "tools: task $v"
}

install_helm() {
  local v; v="$(pin HELM_VERSION)"
  if current helm "$v" version --short; then echo "tools: helm $v (already)"; return; fi
  local tgz="$DIR/.helm.tgz"
  curl -fsSL -o "$tgz" "https://get.helm.sh/helm-${v}-${os}-${arch}.tar.gz"
  tar -xzf "$tgz" -C "$DIR" --strip-components=1 "${os}-${arch}/helm"
  rm -f "$tgz"
  echo "tools: helm $v"
}

# A `go install`ed binary reports "development" to -v; its module version
# is in its build info.
install_go_tool() {
  local name="$1" pkg="$2" v="$3"
  if [[ -x "$DIR/$name" && "$(go version -m "$DIR/$name" 2>/dev/null | awk '$1 == "mod" {print $3}')" == "$v" ]]; then
    echo "tools: $name $v (already)"; return
  fi
  GOTOOLCHAIN=auto GOBIN="$DIR" go install "$pkg@$v"
  echo "tools: $name $v"
}

mkdir -p "$DIR"
tools=("$@")
[[ ${#tools[@]} -gt 0 ]] || tools=(task helm kubeconform actionlint)
for t in "${tools[@]}"; do
  case "$t" in
    task) install_task ;;
    helm) install_helm ;;
    kubeconform) install_go_tool kubeconform github.com/yannh/kubeconform/cmd/kubeconform "$(pin KUBECONFORM_VERSION)" ;;
    actionlint) install_go_tool actionlint github.com/rhysd/actionlint/cmd/actionlint "$(pin ACTIONLINT_VERSION)" ;;
    *) die "unknown tool $t (task, helm, kubeconform, actionlint)" ;;
  esac
done
case ":$PATH:" in
  *":$DIR:"*) ;;
  *) echo "tools: put $DIR first on PATH: export PATH=\"$DIR:\$PATH\"" ;;
esac
