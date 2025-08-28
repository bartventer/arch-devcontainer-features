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

get_go_version() {
  local requested_version=${1:-"latest"}
  local all_versions # Example versions: go1.20.5, go1.21rc1
  all_versions=$(git ls-remote --tags "https://github.com/golang/go.git" |
    awk '$2 ~ /^refs\/tags\/go[[:digit:]]+\.[[:alnum:]]+(\.[[:digit:]]+)?$/ {print $2}' |
    sed 's|refs/tags/||' |
    sort -V)
  log_available_versions() {
    echo "Available Go versions are:"
    xargs -I{} -n 1 echo "  -  {}" <<<"$all_versions"
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

# install_go installs the specified version of Go using the go installation script,
# then copies the script to the container for future use.
# Arguments:
#   $1 - The Go version to install. Examples: "latest", "go1.20.5"
# Example:
#   $ install_go "latest"
install_go() {
  check_and_install_packages curl tar gawk sed git
  local go_install_script_path="./bin/go-install.sh"
  [[ ! -x "$go_install_script_path" ]] && {
    echo "Error: Go install script '$go_install_script_path' not found or not executable."
    exit 1
  }
  local go_version
  go_version=$(get_go_version "$1")
  GOROOT="$TARGET_GOROOT" bash "$go_install_script_path" "$go_version" || {
    echo "Error: Failed to install Go version $go_version."
    exit 1
  }
  local go_install_script_dst_path="/usr/local/bin/go-install.sh"
  cp -v "$go_install_script_path" "$go_install_script_dst_path"
  chmod +x "$go_install_script_dst_path"
  echo "Go install script copied to $go_install_script_dst_path"
  echo "You can run the script with the following command:"
  echo "  $go_install_script_dst_path <version>"
}

install_go_tools() {
  echo_msg "Installing Go tools (via package manager)..."
  # go-tools: https://gitlab.archlinux.org/archlinux/packaging/packages/go-tools/-/blob/main/PKGBUILD?ref_type=heads
  PACKAGES="go-tools delve which jq"
  [[ "$INSTALL_GO_RELEASER" == "true" ]] && PACKAGES+=" goreleaser"
  [[ "$INSTALL_GOX" == "true" ]] && PACKAGES+=" gox"
  [[ "$INSTALL_KO" == "true" ]] && PACKAGES+=" ko"
  [[ "$INSTALL_YAEGI" == "true" ]] && PACKAGES+=" yaegi"
  # shellcheck disable=SC2086
  check_and_install_packages $PACKAGES
  echo_ok "Go tools installed (via package manager)."

  echo_msg "Installing Go tools (via go install)..."
  # Install Go tools that are isImportant && !replacedByGopls based on
  # https://github.com/golang/vscode-go/blob/v0.46.1/extension/src/goToolsInformation.ts
  # echo_msg "Installing Go tools (via go install)..."
  local go_tools_install_script_path="./bin/go-tools-install.sh"
  [[ ! -x "$go_tools_install_script_path" ]] && {
    echo "Error: Go tools install script '$go_tools_install_script_path' not found or not executable."
    exit 1
  }
  local go_tools_list_tmpfile
  go_tools_list_tmpfile=$(mktemp)
  cat ./share/tools.txt >"$go_tools_list_tmpfile"
  [[ "$GOLANGCI_LINT_VERSION" != "none" ]] && echo "$(get_golangci_package_path "$GOLANGCI_LINT_VERSION")" >>"$go_tools_list_tmpfile"
  [[ "$INSTALL_AIR" == "true" ]] && echo "github.com/air-verse/air@latest" >>"$go_tools_list_tmpfile"
  [[ "$INSTALL_COBRA_CLI" == "true" ]] && echo "github.com/spf13/cobra-cli@latest" >>"$go_tools_list_tmpfile"

  GOBIN="${TARGET_GOPATH}/bin" bash "$go_tools_install_script_path" "$go_tools_list_tmpfile" || {
    echo "Error: Failed to install Go tools."
    rm -f "$go_tools_list_tmpfile"
    exit 1
  }

  local go_tools_list_dst_path="/usr/local/share/go-tools.txt"
  cp -v "$go_tools_list_tmpfile" "$go_tools_list_dst_path"
  rm -f "$go_tools_list_tmpfile"
  echo "Go tools list copied to $go_tools_list_dst_path"
  echo "You can edit this file to add or remove tools, then run the install script to apply changes."

  local go_tools_install_script_dst_path="/usr/local/bin/_go-tools-install.sh"
  cp -v "$go_tools_install_script_path" "$go_tools_install_script_dst_path"
  chmod +x "$go_tools_install_script_dst_path"
  local go_tools_install_wrapper_dst_path="/usr/local/bin/go-tools-install.sh"
  cat <<EOF >"$go_tools_install_wrapper_dst_path"
#!/usr/bin/env bash
# Wrapper script to call the Go tools install script with the default tools.txt path.
set -euo pipefail
GOBIN="${TARGET_GOPATH}/bin" "$go_tools_install_script_dst_path" "$go_tools_list_dst_path"
EOF
  chmod +x "$go_tools_install_wrapper_dst_path"
  echo "Go tools install script copied to $go_tools_install_wrapper_dst_path"
  echo "You can run the script with the following command:"
  echo "  $go_tools_install_wrapper_dst_path"
  echo_ok "Go tools installed (via go install)."
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
install_go "${GOVERSION}"
install_go_tools

finalize_permissions

echo "Done. Successfully installed Go and Go tools."
