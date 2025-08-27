#!/usr/bin/env bash
# MIT License
#
# Copyright (c) 2024 Bart Venter <bartventer@outlook.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#-----------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/bartventer/arch-devcontainer-features/tree/main/src/go/README.md
# Maintainer: Bart Venter <https://github.com/bartventer>

set -e

GOVERSION=${GOVERSION:-"latest"}
GOLANGCI_LINT_VERSION=${GOLANGCILINTVERSION:-"latest"}
INSTALL_GO_RELEASER=${INSTALLGORELEASER:-"false"}
INSTALL_GOX=${INSTALLGOX:-"false"}
INSTALL_KO=${INSTALLKO:-"false"}
INSTALL_YAEGI=${INSTALLYAEGI:-"false"}
INSTALL_AIR=${INSTALLAIR:-"false"}
INSTALL_COBRA_CLI=${INSTALLCOBRACLI:-"false"}

TARGET_GOPATH=${TARGET_GOPATH:-"/go"}
TARGET_GOROOT=${TARGET_GOROOT:-"/usr/local/go"}
USERNAME=${USERNAME:-"${_REMOTE_USER:-"automatic"}"}
GROUPNAME=${GROUPNAME:-"golang"}

# get_major_version extracts the major version from a version string.
# Arguments:
#   $1 - The version string to extract the major version from. Examples: "v1.2.3", "1.2.3", "v2.0.0"
# Returns:
#   The major version number.
# Example:
#   $ get_major_version "v1.2.3" -> 1
#   $ get_major_version "1.2.3" -> 1
get_major_version() {
  version="$1"
  major_version=$(echo "$version" | sed -E 's/[^0-9]*([0-9]+).*/\1/')
  if [ -z "$major_version" ]; then
    echo "Error: Unable to extract major version from '$version'."
    exit 1
  fi
  echo "$major_version"
}

# get_golangci_package_path generates the Go module path for the specified GolangCI-Lint version.
# Arguments:
#   $1 - The GolangCI-Lint version to revise. Examples: "latest", "v2", "1.50.0"
# Returns:
#   The Go module path for the specified version.
#
# Example:
#   $ get_golangci_package_path "latest" -> github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
#   $ get_golangci_package_path "v2" -> github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2
#   $ get_golangci_package_path "1.50.0" -> github.com/golangci/golangci-lint/cmd/golangci-lint@v1.50.0
get_golangci_package_path() {
  version="$1"
  _repo="github.com/golangci/golangci-lint"
  _exists=false

  if [ "$version" = "latest" ]; then
    version=$(curl --silent "https://api.github.com/repos/golangci/golangci-lint/releases/latest" | jq -r '.tag_name')
    _exists=true
  fi

  major_version=$(get_major_version "$version")
  if [ "$_exists" = false ]; then
    if ! curl --silent --head --fail "${_repo}/releases/tag/${version}" >/dev/null; then
      echo "Version $version does not exist in the repository."
      exit 1
    fi
  fi

  if [ "$major_version" -gt 1 ]; then
    echo "${_repo}/v${major_version}/cmd/golangci-lint@${version}"
  else
    echo "${_repo}/cmd/golangci-lint@${version}"
  fi
}

# golangci_lint_v2_compatibility is a temporary hack to ensure compatibility with golangci-lint v2.
# https://github.com/golang/vscode-go/issues/3732#issuecomment-2758960259
golangci_lint_v2_compatibility() {
  major_version="$1"
  if [ "$major_version" = 2 ]; then
    install_path="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
    golangci_lint_path="${install_path}/golangci-lint"
    symlink_path="${install_path}/golangci-lint-v2"

    echo_msg "Ensuring golangci-lint/v2 compatibility by creating or verifying symlink for diagnostics."
    if [ -x "$golangci_lint_path" ]; then
      if [ ! -L "$symlink_path" ]; then
        ln -sfv "$golangci_lint_path" "$symlink_path"
      else
        echo "Symlink already exists: $symlink_path"
      fi
      echo_ok "Completed golangci-lint/v2 compatibility."
    else
      echo "Error: $golangci_lint_path does not exist or is not executable."
      exit 1
    fi
  fi
}

# dump_golangci_upgrade_script creates a script to upgrade GolangCI-Lint.
dump_golangci_upgrade_script() {
  echo_msg "Creating upgrade script for GolangCI-Lint..."
  golangci_upgrade_script_path="/usr/local/bin/go-golangci-lint-upgrade.sh"
  mkdir -p "$(dirname "$golangci_upgrade_script_path")"
  cat <<'EOF' >"$golangci_upgrade_script_path"
#!/usr/bin/env bash
# This script upgrades GolangCI-Lint to the specified version or the latest version.
# Usage: ./go-golangci-lint-upgrade.sh <version>
# Example: ./go-golangci-lint-upgrade.sh latest

set -euo pipefail

GOLANGCI_LINT_VERSION=${1:-"latest"}
INSTALL_PATH="${GOBIN:-${GOPATH:-$HOME/go}/bin}"

if ! command -v golangci-lint >/dev/null; then
    echo "Error: GolangCI-Lint is not installed. Please install it first."
    exit 1
fi

if [ "$GOLANGCI_LINT_VERSION" = "latest" ]; then
    GOLANGCI_LINT_VERSION=$(curl -sL "https://api.github.com/repos/golangci/golangci-lint/releases/latest" | jq -r '.tag_name')
fi

MAJOR_VERSION=$(echo "$GOLANGCI_LINT_VERSION" | grep -oE '^[^0-9]*([0-9]+)' | cut -d'v' -f2 || echo 1)
PACKAGE="github.com/golangci/golangci-lint${MAJOR_VERSION:+/v$MAJOR_VERSION}/cmd/golangci-lint@$GOLANGCI_LINT_VERSION"

# Remove existing symlink if it exists
if [ -L "$INSTALL_PATH/golangci-lint-v2" ]; then
    echo "Removing existing symlink: $INSTALL_PATH/golangci-lint-v2"
    rm -fv "$INSTALL_PATH/golangci-lint-v2"
fi

echo "Installing GolangCI-Lint version $GOLANGCI_LINT_VERSION..."
go install -v "$PACKAGE" || {
    echo "Error: Failed to install GolangCI-Lint version $GOLANGCI_LINT_VERSION."
    exit 1
}

# Create a symlink for diagnostics (v2 compatibility)
if [[ "$MAJOR_VERSION" == 2 ]]; then
    echo "Creating symlink for diagnostics (v2 compatibility)..."
    ln -sfv "$INSTALL_PATH/golangci-lint" "$INSTALL_PATH/golangci-lint-v2"
fi


echo "GolangCI-Lint upgraded to version $GOLANGCI_LINT_VERSION."
EOF
  chmod +x "$golangci_upgrade_script_path"
  echo "Upgrade script created at $golangci_upgrade_script_path"
  echo "You can run the script with the following command:"
  echo "  $golangci_upgrade_script_path <version>"
  echo "Replace <version> with the desired version (e.g., latest, v2, 1.50.0)."
  echo "You can also run the script without arguments to install the latest version."
}

get_go_version() {
  local requested_version=${1:-"latest"}
  local all_versions # Example versions: go1.20.5, go1.21rc1
  all_versions=$(git ls-remote --tags "https://github.com/golang/go.git" |
    awk '$2 ~ /^refs\/tags\/go[[:digit:]]+\.[[:alnum:]]+(\.[[:digit:]]+)?$/ {print $2}' |
    sed 's|refs/tags/||' |
    sort -V)
  log_available_versions() {
    echo "Available Go versions are:"
    awk '{print "  - " $0}' <<<"$all_versions"
  }
  case "$requested_version" in
  latest)
    # latest stable version (ignore rc/beta/alpha versions)
    grep -E '^go[0-9]+\.[0-9]+(\.[0-9]+)?$' <<<"$all_versions" | tail -n 1
    return
    ;;
  go*)
    # specific version requested, e.g., go1.20.5
    if grep -qx "$requested_version" <<<"$all_versions"; then
      echo "$requested_version"
      return
    else
      echo "Error: Version '$requested_version' not found."
      log_available_versions
      exit 1
    fi
    ;;
  *)
    echo "Error: Invalid version format '$requested_version'. Use 'latest' or 'go<version>' (e.g., go1.20.5)."
    log_available_versions
    exit 1
    ;;
  esac
}

get_go_architecture() {
  local arch
  arch=$(uname -m)
  case $arch in
  x86_64) echo "amd64" ;;
  aarch64 | armv8*) echo "arm64" ;;
  i?86) echo "386" ;;
  *)
    echo "Error: Unsupported architecture '$arch'. Supported architectures are x86_64 (amd64), aarch64 (arm64), and i386 (386)."
    exit 1
    ;;
  esac
}

install_go() {
  check_and_install_packages curl tar gawk sed git
  local go_version go_architecture
  go_version=$(get_go_version "$1")
  go_architecture=$(get_go_architecture)
  local download_url="https://go.dev/dl/${go_version}.linux-${go_architecture}.tar.gz"
  echo_msg "Installing Go version $go_version for architecture $go_architecture..."

  echo "Removing any existing Go installation"
  rm -rfv "$TARGET_GOROOT"

  echo "Downloading and extracting Go from $download_url to $(dirname "$TARGET_GOROOT")..."
  curl -sSL "$download_url" | tar -C "$(dirname "$TARGET_GOROOT")" -xz
  echo_ok "Go $go_version installed to $TARGET_GOROOT."
}

dump_go_upgrade_script() {
  echo_msg "Creating upgrade script for Go..."
  go_upgrade_script_path="/usr/local/bin/go-upgrade.sh"
  mkdir -p "$(dirname "$go_upgrade_script_path")"
  cat <<'EOF' >"$go_upgrade_script_path"
#!/usr/bin/env bash
# This script upgrades Go to the specified version.
# Usage: ./go-upgrade.sh <version>
# Example: ./go-upgrade.sh go1.20.5
set -euo pipefail

install_go() {
  local go_version="$1"
  local go_architecture
  go_architecture=$(uname -m)
  case $go_architecture in
  x86_64) go_architecture="amd64" ;;
  aarch64 | armv8*) go_architecture="arm64" ;;
  i?86) go_architecture="386" ;;
  *)
    echo "Error: Unsupported architecture '$go_architecture'. Supported architectures are x86_64 (amd64), aarch64 (arm64), and i386 (386)."
    exit 1
    ;;
  esac
  local download_url="https://go.dev/dl/${go_version}.linux-${go_architecture}.tar.gz"
  local target_goroot="/usr/local/go"
  echo "Removing any existing Go installation"
  rm -rfv "$target_goroot"
  echo "Downloading and extracting Go from $download_url to $(dirname "$target_goroot")..."
  curl -sSL "$download_url" | tar -C "$(dirname "$target_goroot")" -xz
  echo "Go $go_version installed to $target_goroot."
}
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 go1.20.5"
    echo "See https://go.dev/dl/ and https://github.com/golang/go/tags for available versions."
    exit 1
fi
install_go "$1"
EOF
  chmod +x "$go_upgrade_script_path"
  echo_ok "Upgrade script created at $go_upgrade_script_path"
  echo "You can run the script with the following command:"
  echo "  $go_upgrade_script_path <version>"
  echo "Replace <version> with the desired version (e.g., go1.20.5)."
}

dump_go_tools_upgrade_script() {
  local go_tools="$1"

  echo_msg "Creating upgrade script for Go tools..."
  go_tools_list_path="/usr/local/share/go-tools-list.txt"
  echo "$go_tools" >"$go_tools_list_path"
  go_tools_upgrade_script_path="/usr/local/bin/go-tools-upgrade.sh"
  mkdir -p "$(dirname "$go_tools_upgrade_script_path")"
  cat <<'EOF' >"$go_tools_upgrade_script_path"
#!/usr/bin/env bash
# This script upgrades all Go tools listed in /usr/local/share/go-tools-list.txt.
# Usage: ./go-tools-upgrade.sh
set -euo pipefail
TOOLS_LIST="/usr/local/share/go-tools-list.txt"
if [ ! -f "$TOOLS_LIST" ]; then
    echo "Error: Tools list file '$TOOLS_LIST' not found."
    exit 1
fi
while IFS= read -r tool; do
    if [ -n "$tool" ]; then
        tool_name=$(basename "$(echo "$tool" | cut -d'@' -f1)")
        if command -v "$tool_name" >/dev/null 2>&1; then
            echo "Removing existing binary: $tool_name"
            rm -fv "$(command -v "$tool_name")"
        fi
        echo "Installing/upgrading tool: $tool"
        go install -v "$tool" || {
            echo "Error: Failed to install/upgrade tool '$tool'."
            exit 1
        }
    fi
done <"$TOOLS_LIST"
echo "All Go tools upgraded."
EOF
  chmod +x "$go_tools_upgrade_script_path"
  echo_ok "Upgrade script created at $go_tools_upgrade_script_path"
  echo "You can run the script with the following command:"
  echo "  $go_tools_upgrade_script_path"
}

install_go_and_tools() {
  install_go "${GOVERSION}"
  dump_go_upgrade_script

  echo_msg "Installing Go tools..."
  # go-tools: https://gitlab.archlinux.org/archlinux/packaging/packages/go-tools/-/blob/main/PKGBUILD?ref_type=heads
  PACKAGES="go-tools delve which jq"
  if [ "$INSTALL_GO_RELEASER" = "true" ]; then
    PACKAGES="$PACKAGES goreleaser"
  fi
  if [ "$INSTALL_GOX" = "true" ]; then
    PACKAGES="$PACKAGES gox"
  fi
  if [ "$INSTALL_KO" = "true" ]; then
    PACKAGES="$PACKAGES ko"
  fi
  if [ "$INSTALL_YAEGI" = "true" ]; then
    PACKAGES="$PACKAGES yaegi"
  fi
  # shellcheck disable=SC2086
  check_and_install_packages $PACKAGES

  # Install Go tools that are isImportant && !replacedByGopls based on
  # https://github.com/golang/vscode-go/blob/v0.46.1/extension/src/goToolsInformation.ts
  GO_TOOLS=$(cat tools.txt)

  if [ "$GOLANGCI_LINT_VERSION" != "none" ]; then
    GOLANGCI_LINT_PACKAGE=$(get_golangci_package_path "$GOLANGCI_LINT_VERSION")
    GO_TOOLS="${GO_TOOLS} ${GOLANGCI_LINT_PACKAGE}"
  fi

  if [ "$INSTALL_AIR" = "true" ]; then
    GO_TOOLS="${GO_TOOLS} github.com/air-verse/air@latest"
  fi

  if [ "$INSTALL_COBRA_CLI" = "true" ]; then
    GO_TOOLS="${GO_TOOLS} github.com/spf13/cobra-cli@latest"
  fi

  echo "${GO_TOOLS}" | xargs -n 1 go install

  _BASH_COMPLETION_DIR="/etc/bash_completion.d"
  _ZSH_COMPLETION_DIR="/usr/share/zsh/site-functions"
  _FISH_COMPLETION_DIR="/usr/share/fish/vendor_completions.d"

  if [ "$INSTALL_COBRA_CLI" = "true" ]; then
    echo_msg "Installing cobra-cli completion scripts..."
    mkdir -pv "$_BASH_COMPLETION_DIR" "$_ZSH_COMPLETION_DIR" "$_FISH_COMPLETION_DIR"
    cobra-cli completion bash >"$_BASH_COMPLETION_DIR/cobra-cli"
    cobra-cli completion zsh >"$_ZSH_COMPLETION_DIR/_cobra-cli"
    cobra-cli completion fish >"$_FISH_COMPLETION_DIR/cobra-cli.fish"
    echo_ok "cobra-cli completion scripts installed."
  fi

  if [ "$GOLANGCI_LINT_VERSION" != "none" ]; then
    _version=$(basename "$(echo "$GOLANGCI_LINT_PACKAGE" | cut -d'@' -f2)")
    golangci_lint_v2_compatibility "$(get_major_version "$_version")"
    dump_golangci_upgrade_script

    echo_msg "Installing golangci-lint completion scripts..."
    mkdir -pv "$_BASH_COMPLETION_DIR" "$_ZSH_COMPLETION_DIR" "$_FISH_COMPLETION_DIR"
    golangci-lint completion bash >"$_BASH_COMPLETION_DIR/golangci-lint"
    golangci-lint completion zsh >"$_ZSH_COMPLETION_DIR/_golangci-lint"
    golangci-lint completion fish >"$_FISH_COMPLETION_DIR/golangci-lint.fish"
    echo_ok "golangci-lint completion scripts installed."
  fi

  dump_go_tools_upgrade_script "$GO_TOOLS"

  echo_ok "Go and Go tools installed."
}

setup_user() {
  if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS="vscode node codespace $(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)"
    for CURRENT_USER in ${POSSIBLE_USERS}; do
      if id -u "${CURRENT_USER}" >/dev/null 2>&1; then
        USERNAME=${CURRENT_USER}
        break
      fi
    done
    if [ "${USERNAME}" = "" ]; then
      USERNAME=root
    fi
  elif [ "${USERNAME}" = "none" ] || ! id -u "${USERNAME}" >/dev/null 2>&1; then
    USERNAME=root
  fi
}

setup_golang_group() {
  echo_msg "Setting up Go group and directories..."
  if ! getent group "$GROUPNAME" >/dev/null; then
    groupadd -r "$GROUPNAME"
  else
    echo "Group $GROUPNAME already exists."
  fi
  if id "$USERNAME" >/dev/null 2>&1; then
    usermod -a -G "$GROUPNAME" "$USERNAME"
  else
    echo "Warning: User $USERNAME does not exist. Skipping group addition."
  fi
  mkdir -pv "$TARGET_GOROOT" "$TARGET_GOPATH"
  echo_ok "Go group and directories set up."
}

finalize_permissions() {
  echo_msg "Finalizing permissions for Go directories..."
  chown -R "$USERNAME:$GROUPNAME" "$TARGET_GOROOT" "$TARGET_GOPATH"
  chmod -R g+r+w "$TARGET_GOROOT" "$TARGET_GOPATH"
  find "$TARGET_GOROOT" -type d -print0 | xargs -n 1 -0 chmod g+s
  find "$TARGET_GOPATH" -type d -print0 | xargs -n 1 -0 chmod g+s
  echo_ok "Permissions finalized."
}

# ***********************
# ** Utility functions **
# ***********************

_UTILS_SETUP_SCRIPT=$(mktemp)
curl -sSL -o "$_UTILS_SETUP_SCRIPT" https://raw.githubusercontent.com/bartventer/arch-devcontainer-features/main/scripts/archlinux_util_setup.sh
sh "$_UTILS_SETUP_SCRIPT"
rm -f "$_UTILS_SETUP_SCRIPT"

# shellcheck disable=SC1091
# shellcheck source=scripts/archlinux_util.sh
. archlinux_util.sh

# Source /etc/os-release to get OS info
# shellcheck disable=SC1091
# shellcheck source=/etc/os-release
. /etc/os-release

# Run checks
check_root
check_system
check_pacman

setup_user
umask 0002
setup_golang_group
install_go_and_tools
finalize_permissions

echo "Done. Successfully installed Go and Go tools."
