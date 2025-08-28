#!/usr/bin/env bash
# This script upgrades Go to the specified version.
# Usage: ./go-install.sh <version>
# Example: ./go-install.sh go1.20.5
# Note: Ensure that the GOROOT environment variable is set to the desired
# installation path before running this script.
set -euo pipefail

install_go() {
  local go_version="${1:?Version argument is required}"
  local go_root="${GOROOT:?Environment variable GOROOT must be set}"

  local go_arch
  go_arch=$(uname -m)
  case $go_arch in
  x86_64) go_arch="amd64" ;;
  aarch64 | armv8*) go_arch="arm64" ;;
  i?86) go_arch="386" ;;
  *)
    echo "Error: Unsupported architecture '$go_arch'. Supported architectures are x86_64 (amd64), aarch64 (arm64), and i386 (386)."
    exit 1
    ;;
  esac
  local download_url="https://go.dev/dl/${go_version}.linux-${go_arch}.tar.gz"

  echo "Removing any existing Go installation"
  rm -rfv "$go_root"
  echo "Downloading and extracting Go from $download_url to $(dirname "$go_root")..."
  curl -sSL "$download_url" | tar -C "$(dirname "$go_root")" -xz

  echo "Go $go_version installed to $go_root."
  echo "(*) Please ensure that $go_root/bin is in your PATH."
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 go1.20.5"
  echo "See https://go.dev/dl/ and https://github.com/golang/go/tags for available versions."
  exit 1
fi

install_go "$1"
