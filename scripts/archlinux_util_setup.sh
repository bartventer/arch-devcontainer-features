#!/bin/sh
set -e

_UTIL_SCRIPT="/usr/local/bin/archlinux_util.sh"
if [ ! -x "$_UTIL_SCRIPT" ]; then
    echo ":: Setting up archlinux_util.sh..."
    _TMP_DIR=$(mktemp -d)
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
    mv "$_TMP_DIR/scripts/archlinux_util.sh" "$_UTIL_SCRIPT"
    chmod +x "$_UTIL_SCRIPT"
    echo "archlinux_util.sh setup complete."

    # Clean up
    rm -rf "$_TMP_DIR"
fi