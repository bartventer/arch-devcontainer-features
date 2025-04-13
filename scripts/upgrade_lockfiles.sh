#!/usr/bin/env bash

set -euo pipefail

# This script upgrades the devcontainer-feature-lock.json files in the src directory.

DRYRUN=${DRYRUN:-false}
ARCHLINUX_CONTAINER_NAME="archlinux-vercmp-$(date +%s)"

start_archlinux_container() {
    echo "Starting Arch Linux container..."
    docker run -d --rm --name "$ARCHLINUX_CONTAINER_NAME" archlinux:latest bash -c "
        pacman-key --init &&
        pacman-key --populate archlinux &&
        pacman -Sy --noconfirm archlinux-keyring &&
        pacman -Sy --noconfirm pacman-contrib &&
        tail -f /dev/null
    "
}

wait_for_archlinux_container() {
    echo "Waiting for Arch Linux container to be ready..."
    for i in {1..10}; do
        if docker exec "$ARCHLINUX_CONTAINER_NAME" true >/dev/null 2>&1; then
            echo "OK. Arch Linux container is ready."
            echo
            return
        fi
        echo "Waiting for container... ($i/10)"
        sleep 1
    done
    echo "Error: Arch Linux container did not become ready in time." >&2
    exit 1
}

stop_archlinux_container() {
    echo "Stopping Arch Linux container..."
    docker stop "$ARCHLINUX_CONTAINER_NAME" >/dev/null 2>&1 || true
    echo "Ok. Container stopped."
}

fetch_archlinux_version() {
    local archlinux_source="$1" package_name
    package_name=$(basename "$archlinux_source")
    curl -sL "$archlinux_source" | grep -oP "(?<=<title>Arch Linux - $package_name )[^ ]+" || {
        echo "Error: Failed to fetch the latest version for $package_name from $archlinux_source" >&2
        return 1
    }
}

fetch_custom_version() {
    local check_command="$1"
    eval "$check_command"
}

compare_versions() {
    local current_version="$1"
    local latest_version="$2"
    local versioning_type="$3"

    case "$versioning_type" in
    archlinux)
        result=$(docker exec "$ARCHLINUX_CONTAINER_NAME" vercmp "$current_version" "$latest_version")
        ;;
    semver)
        if [ "$(printf '%s\n%s' "$current_version" "$latest_version" | sort -V | head -n 1)" == "$current_version" ]; then
            if [ "$current_version" == "$latest_version" ]; then
                result=0
            else
                result=-1
            fi
        else
            result=1
        fi
        ;;
    custom)
        echo "Custom comparison logic not implemented."
        return
        ;;
    *)
        echo "Unknown versioning type: $versioning_type"
        exit 1
        ;;
    esac

    if [[ "$result" -eq 1 ]]; then
        echo ":: No update needed: Current version ($current_version) is newer than the latest version ($latest_version)."
    elif [[ "$result" -eq -1 ]]; then
        echo ":: Update available: A new version is available: $latest_version (current: $current_version)."
    elif [[ "$result" -eq 0 ]]; then
        echo ":: No update needed: Current version ($current_version) is up-to-date."
    else
        echo "Error comparing versions. Expected 0, 1, or -1 but got $result."
        exit 1
    fi
}

# Main function to process each devcontainer-feature-lock.json file
process_feature_lock_files() {
    local feature_dirs
    feature_dirs=$(find ./src -type f -name "devcontainer-feature-lock.json")

    for file in $feature_dirs; do
        local packages feature_dir
        packages=$(jq -c '.packages[]' "$file")
        feature_dir=$(dirname "$file")
        feature_name=$(basename "$feature_dir")

        echo "======================================"
        echo "Processing Feature: $feature_name"
        echo "File: $file"
        echo "======================================"

        while IFS= read -r package; do
            local name current_version versioning_type archlinux_source check_latest_command
            name=$(echo "$package" | jq -r '.name')
            current_version=$(echo "$package" | jq -r '.version')
            versioning_type=$(echo "$package" | jq -r '.versioningType // "archlinux"')
            archlinux_source=$(echo "$package" | jq -r '.archlinuxSource // empty')
            check_latest_command=$(echo "$package" | jq -r '.checkLatestCommand // empty')

            echo "Package: $name"
            echo "Current Version: $current_version"
            echo "Versioning Type: $versioning_type"

            local latest_version=""
            case "$versioning_type" in
            archlinux)
                if [ -n "$archlinux_source" ]; then
                    latest_version=$(fetch_archlinux_version "$archlinux_source")
                else
                    echo "Error: archlinuxSource is required for archlinux versioning."
                    continue
                fi
                ;;
            semver | custom)
                if [ -n "$check_latest_command" ]; then
                    latest_version=$(fetch_custom_version "$check_latest_command")
                else
                    echo "Error: checkLatestCommand is required for $versioning_type versioning."
                    continue
                fi
                ;;
            *)
                echo "Unknown versioning type: $versioning_type"
                continue
                ;;
            esac
            if [ -z "$latest_version" ]; then
                echo "Error: Failed to fetch the latest version for $name."
                continue
            fi
            echo "Latest Version: $latest_version"

            compare_versions "$current_version" "$latest_version" "$versioning_type"
            if [[ "$result" -eq -1 ]]; then
                if [ "$DRYRUN" == "false" ]; then
                    jq --arg name "$name" --arg version "$latest_version" '(.packages[] | select(.name == $name) | .version) = $version' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
                    echo -e "\033[0;32m:: Updated $file version for $name ($current_version -> $latest_version).\033[0m"
                else
                    echo -e "\033[0;33m:: DRYRUN: Would update $file version for $name ($current_version -> $latest_version).\033[0m"
                fi
            fi

            echo
        done <<<"$packages"
    done

    echo "======================================"
    echo "All features processed."
    echo "======================================"
}

start_archlinux_container
wait_for_archlinux_container
trap stop_archlinux_container EXIT
process_feature_lock_files
