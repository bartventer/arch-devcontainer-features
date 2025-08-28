#!/usr/bin/env bash
# This script installs Go tools specified in a tools.txt file.
# Usage: ./go-tools-install.sh <path/to/tools.txt>
# Example: ./go-tools-install.sh /usr/local/share/go-tools.txt

set -euo pipefail

make_bin_completions() {
  local _completion_dir_bash="/etc/bash_completion.d"
  local _completion_dir_zsh="/usr/share/zsh/site-functions"
  local _completion_dir_fish="/usr/share/fish/vendor_completions.d"
  echo "::Detected $1, generating completions..."
  local bin_name="$1"
  mkdir -pv "$_completion_dir_bash" "$_completion_dir_zsh" "$_completion_dir_fish"
  "$GOBIN/$bin_name" completion bash >"$_completion_dir_bash/$bin_name"
  "$GOBIN/$bin_name" completion zsh >"$_completion_dir_zsh/_$bin_name"
  "$GOBIN/$bin_name" completion fish >"$_completion_dir_fish/$bin_name.fish"
  echo "$bin_name completion scripts installed."
}

install_go_tools() {
  local go_toolstxt_path="${1:?Path to tools.txt is required}"
  local go_tools
  go_tools=$(cat "$go_toolstxt_path")
  echo "Tools to be installed:"
  xargs -I{} -n 1 echo " -  {}" <<<"$go_tools"
  [[ -z "${GOBIN:-}" ]] && {
    echo "Error: GOBIN environment variable must be set."
    exit 1
  }
  xargs -n 1 go install -v <<<"$go_tools"
  echo "Go tools installed (via go install)."
  if grep -xqE "github.com/golangci/golangci-lint/(v[0-9]+/)?cmd/golangci-lint@([a-zA-Z0-9._-]+)?" <<<"$go_tools"; then
    make_bin_completions "golangci-lint"
  fi
  if grep -xqE "github.com/spf13/cobra-cli@([a-zA-Z0-9._-]+)?" <<<"$go_tools"; then
    make_bin_completions "cobra-cli"
  fi
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <path/to/tools.txt>"
  echo "Example: $0 /usr/local/share/go-tools.txt"
  exit 1
fi

install_go_tools "$1"
