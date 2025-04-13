#!/bin/sh
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

GOLANGCI_LINT_VERSION=${GOLANGCILINTVERSION:-"latest"}
INSTALL_GO_RELEASER=${INSTALLGORELEASER:-"false"}
INSTALL_GOX=${INSTALLGOX:-"false"}
INSTALL_KO=${INSTALLKO:-"false"}
INSTALL_YAEGI=${INSTALLYAEGI:-"false"}
INSTALL_AIR=${INSTALLAIR:-"false"}
INSTALL_COBRA_CLI=${INSTALLCOBRACLI:-"false"}

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

# add_cobra_cli_autocompletion Adds shell auto-completion for Cobra CLI.
# Supported shells: bash, zsh, fish
add_cobra_cli_autocompletion() {
    command_name="cobra-cli"
    echo "Enabling shell auto-completion for $command_name..."
    tmp_file=$(mktemp)

    # Helper function to handle common logic
    handle_shell() {
        shell_name=$1
        if [ -f "$HOME/.${shell_name}rc" ] || type "$shell_name" >/dev/null 2>&1; then
            echo "Setting up auto-completion for $shell_name..."
            cobra-cli completion "$shell_name" >"$tmp_file"
            enable_autocompletion "$tmp_file" "$command_name"
        fi
    }

    for shell_name in zsh bash fish; do
        handle_shell "$shell_name"
    done

    # Clean up
    rm "$tmp_file" >/dev/null
}

# ***********************
# ** Utility functions **
# ***********************

_UTIL_SCRIPT="/usr/local/bin/archlinux_util.sh"
if [ ! -x "$_UTIL_SCRIPT" ]; then
    (
        _TMP_DIR=$(mktemp --directory --suffix=arch-devcontainer)
        echo ":: Downloading release tar..."
        _TAG_NAME=$(curl --silent "https://api.github.com/repos/bartventer/arch-devcontainer-features/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        _BASE_URL="https://github.com/bartventer/arch-devcontainer-features/releases/download/$_TAG_NAME"
        _TARFILE="arch-devcontainer-features-$_TAG_NAME.tar.gz"
        curl -sSL -o "$_TMP_DIR/${_TARFILE}" "$_BASE_URL/$_TARFILE"
        curl -sSL -o "$_TMP_DIR/checksums.txt" "$_BASE_URL/checksums.txt"
        curl -sSL -o "$_TMP_DIR/checksums.txt.asc" "$_BASE_URL/checksums.txt.asc"
        echo "OK"

        echo ":: Importing GPG key..."
        _REPO_GPG_KEY=A080EEF8607B049ED39BE8F6077F8B92C2B891F9
        gpg --keyserver keyserver.ubuntu.com --recv-keys "$_REPO_GPG_KEY"
        echo "OK"

        echo ":: Verifying checksums signature..."
        cd "$_TMP_DIR"
        gpg --verify checksums.txt.asc checksums.txt
        echo "OK"

        echo ":: Verifying checksums..."
        sha256sum -c checksums.txt
        echo "OK"

        echo ":: Extracting tar..."
        tar xzf "$_TMP_DIR/$_TARFILE" -C "$_TMP_DIR"
        echo "OK"

        echo ":: Moving scripts..."
        mv ./scripts/archlinux_util.sh "$_UTIL_SCRIPT"
        chmod +x "$_UTIL_SCRIPT"
        echo "OK"

        # Clean up
        rm -rf "$_TMP_DIR"
    )
fi

# shellcheck disable=SC1091
# shellcheck source=scripts/archlinux_util.sh
. "$_UTIL_SCRIPT"

# Source /etc/os-release to get OS info
# shellcheck disable=SC1091
# shellcheck source=/etc/os-release
. /etc/os-release

# Run checks
check_root
check_system
check_pacman

# Install Go (and other tools)
# go-tools: https://gitlab.archlinux.org/archlinux/packaging/packages/go-tools/-/blob/main/PKGBUILD?ref_type=heads
PACKAGES="go go-tools delve which jq"
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

GO_TOOLS="\
    golang.org/x/tools/gopls@latest \
    honnef.co/go/tools/cmd/staticcheck@latest \
    github.com/mgechev/revive@latest \
    github.com/incu6us/goimports-reviser/v2@latest \
    github.com/segmentio/golines@latest \
    github.com/fatih/gomodifytags@latest \
    github.com/cweill/gotests/gotests@latest \
    github.com/josharian/impl@latest \
    golang.org/x/lint/golint@latest \
    github.com/haya14busa/goplay/cmd/goplay@latest \
    github.com/766b/go-outliner@latest"

if [ "$GOLANGCI_LINT_VERSION" != "none" ]; then
    GO_TOOLS="${GO_TOOLS} $(get_golangci_package_path "$GOLANGCI_LINT_VERSION")"
fi

if [ "$INSTALL_AIR" = "true" ]; then
    GO_TOOLS="${GO_TOOLS} github.com/air-verse/air@latest"
fi

if [ "$INSTALL_COBRA_CLI" = "true" ]; then
    GO_TOOLS="${GO_TOOLS} github.com/spf13/cobra-cli@latest"
fi

echo_msg "Installing Go tools..."
echo "${GO_TOOLS}" | xargs -n 1 go install

if [ "$(command -v cobra-cli)" ]; then
    add_cobra_cli_autocompletion
fi

# golangci_lint_v2_compatibility is a temporary hack to ensure compatibility with golangci-lint v2.
# https://github.com/golang/vscode-go/issues/3732#issuecomment-2758960259
golangci_lint_v2_compatibility() {
    if [ "$(get_major_version "$GOLANGCI_LINT_VERSION")" = 2 ]; then
        install_path="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
        golangci_lint_path="${install_path}/golangci-lint"
        symlink_path="${install_path}/golangci-lint-v2"

        echo_msg "Ensuring golangci-lint/v2 compatibility by creating or verifying symlink for diagnostics."
        if [ -x "$golangci_lint_path" ]; then
            if [ ! -L "$symlink_path" ]; then
                ln -sf "$golangci_lint_path" "$symlink_path"
                echo "Created symlink: $symlink_path -> $golangci_lint_path"
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
    upgrade_script_path="/usr/local/bin/go-golangci-lint-upgrade.sh"
    cat <<'EOF' >"$upgrade_script_path"
#!/usr/bin/env bash
# This script upgrades GolangCI-Lint to the specified version or the latest version.
# Usage: ./go-golangci-lint-upgrade.sh <version>
# Example: ./go-golangci-lint-upgrade.sh latest

set -e

GOLANGCI_LINT_VERSION=${1:-"latest"}

INSTALL_PATH="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
GOLANGCI_LINT_PATH="${INSTALL_PATH}/golangci-lint"
SYMLINK_PATH="${INSTALL_PATH}/golangci-lint-v2"

echo "Removing old GolangCI-Lint binary..."
rm -f "$GOLANGCI_LINT_PATH" "$SYMLINK_PATH"

echo "Installing GolangCI-Lint version $GOLANGCI_LINT_VERSION..."
go install "github.com/golangci/golangci-lint/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"

# Handle symlink for v2 compatibility
if [ "$(echo "$GOLANGCI_LINT_VERSION" | grep -o '^v2')" = "v2" ]; then
    ln -sf "$GOLANGCI_LINT_PATH" "$SYMLINK_PATH"
    echo "Created symlink: $SYMLINK_PATH -> $GOLANGCI_LINT_PATH"
fi

echo "GolangCI-Lint upgraded to version $GOLANGCI_LINT_VERSION."
EOF
    chmod +x "$HOME/go-golangci-lint-upgrade.sh"
    echo "Upgrade script created at $HOME/go-golangci-lint-upgrade.sh"
    echo "You can run the script with the following command:"
    echo "  $HOME/go-golangci-lint-upgrade.sh <version>"
    echo "Replace <version> with the desired version (e.g., latest, v2, 1.50.0)."
    echo "You can also run the script without arguments to install the latest version."
    unset upgrade_script_path
}

if [ "$GOLANGCI_LINT_VERSION" != "none" ]; then
    golangci_lint_v2_compatibility
    dump_golangci_upgrade_script
fi

echo "Done. Successfully installed Go and Go tools."
