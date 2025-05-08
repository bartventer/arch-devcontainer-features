#!/usr/bin/env bash

# This script generates release assets for a GitHub release.
# Usage: ./generate_assets.sh --dist <dist_dir> --version <version>

set -euo pipefail

_DIST_DIR="dist"
_VERSION=""
_PARAMS=""
_ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"
_REPOSITORY_NAME="$(basename "${GITHUB_REPOSITORY:-"$(git config --get remote.origin.url)"}" .git)"
[[ -z "${_REPOSITORY_NAME}" ]] && echo "Error: Could not determine repository name" && exit 1

while (("$#")); do
    case "$1" in
    --*=*) # support for `--flag=value`
        echo "Error: Unsupported flag $1" >&2
        exit 1
        ;;
    --dist)
        _DIST_DIR=$2
        shift 2
        ;;
    --version)
        _VERSION=$2
        shift 2
        ;;
    --) # end argument parsing
        shift
        break
        ;;
    *) # preserve positional arguments
        _PARAMS="$_PARAMS $1"
        shift
        ;;
    esac
done

[[ -z "${_DIST_DIR:-}" ]] && echo "Error: --dist flag is required" && exit 1
[[ -z "${_VERSION:-}" ]] && echo "Error: --version flag is required" && exit 1
[[ "${_VERSION}" != v* ]] && _VERSION="v${_VERSION}"

cat <<EOT
ℹ️ Generating release assets:
    - Repository: $_REPOSITORY_NAME
    - Version: $_VERSION
    - Dist directory: $_DIST_DIR
    - Root directory: $_ROOT
EOT

mkdir -p "$_DIST_DIR"

_FILENAME=$(basename "${_REPOSITORY_NAME}-${_VERSION}.tar.gz")
tar -czf "$_DIST_DIR/${_FILENAME}" --exclude="$_DIST_DIR" -C "$_ROOT" .

(
    cd "$_DIST_DIR" || exit
    sha256sum "${_FILENAME}" >checksums.txt
)

gpg --detach-sign --armor "$_DIST_DIR/checksums.txt"

echo
echo "ℹ️ Generated the following assets:"
ls -l "$_DIST_DIR"
echo
echo "✔️ OK. All assets generated."

[[ "${CI:-}" == "true" ]] && exit 0
echo
echo -n "🚨 Do you want to upload the assets to the release ($_VERSION) (this will replace the existing assets if they already exist)? (y/N)"
read -re response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "🚀 Uploading assets to the release ($_VERSION)"
    for file in "$_DIST_DIR"/*; do
        gh release upload --clobber "$_VERSION" "$file"
    done
else
    echo "🚫 Skipped uploading assets to the release ($_VERSION)"
fi

echo
echo -n "🚨 Do you want to remove the $_DIST_DIR? (Y/n)"
read -re response
if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    echo "🚫 Skipped removing the $_DIST_DIR"
else
    echo "🗑️ Removing the $_DIST_DIR"
    rm -rf "$_DIST_DIR"
fi
