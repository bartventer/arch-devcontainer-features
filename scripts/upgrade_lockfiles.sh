#!/usr/bin/env bash

set -euo pipefail

# This script upgrades the devcontainer-feature-lock.json files in the src directory.

DRYRUN=${DRYRUN:-false}
ARCHLINUX_CONTAINER_NAME="archlinux-vercmp-$RANDOM"

# Terminal colors
_BLUE="\033[1;34m"
_YELLOW="\033[1;33m"
_RED="\033[1;31m"
_RESET="\033[0m"

log_message() {
  local symbol=$1
  shift
  echo -e "(${_BLUE}$(date '+%Y-%m-%d %H:%M:%S')${_RESET}) [${_BLUE}INFO${_RESET}] ${symbol} $1"
}

log_info() {
  log_message "ℹ️" "$1"
}

log_checkpoint() {
  log_message "✔" "$1"
}

log_warn() {
  echo -e "(${_YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${_RESET}) [${_YELLOW}WARN${_RESET}] 🔔 ${_YELLOW}$1${_RESET}" >&2
}

log_error() {
  echo -e "(${_RED}$(date '+%Y-%m-%d %H:%M:%S')${_RESET}) [${_RED}ERROR${_RESET}] ❕ ${_RED}$1${_RESET}" >&2
}

log_fatal() {
  echo -e "(${_RED}$(date '+%Y-%m-%d %H:%M:%S')${_RESET}) [${_RED}FATAL${_RESET}] ❌ ${_RED}$1${_RESET}" >&2
  exit 1
}

start_archlinux_container() {
  log_info "Starting Arch Linux container..."
  docker run -d --rm --name "$ARCHLINUX_CONTAINER_NAME" archlinux:latest bash -c "
        pacman-key --init &&
        pacman-key --populate archlinux &&
        pacman -Sy --noconfirm archlinux-keyring &&
        pacman -Sy --noconfirm pacman-contrib &&
        echo 'Ready to use vercmp' &&
        tail -f /dev/null
    "

  # Wait for the container to be in a running state
  for i in {1..45}; do
    if docker logs "$ARCHLINUX_CONTAINER_NAME" 2>&1 | grep -q 'Ready to use vercmp'; then
      log_checkpoint "Arch Linux container started."
      return
    fi
    log_warn "Waiting for Arch Linux container to start... ($i/45)"
    sleep 1
  done

  log_fatal "Failed to start Arch Linux container."
}

stop_archlinux_container() {
  log_info "Stopping Arch Linux container..."
  docker stop "$ARCHLINUX_CONTAINER_NAME" >/dev/null 2>&1 || true
  log_checkpoint "Arch Linux container stopped."
}

# fetch_archlinux_version fetches the latest version of a package through the GitLab API.
# It requires the package name as an argument.
# Example: fetch_archlinux_version "git" -> 2.39.1
#
# References:
# - https://docs.gitlab.com/api/tags/#list-project-repository-tags
# - https://gitlab.archlinux.org/archlinux/packaging/packages
fetch_archlinux_version() {
  local package_name="$1" # e.g. "git"
  local project_id
  # Encode the package name to a URL-friendly format (https://docs.gitlab.com/api/rest/#namespaced-paths)
  project_id=$(jq -Rr @uri <<<"archlinux/packaging/packages/$package_name")
  # The JSON response from the API contains an array of tags, sorted by update time. We take the first one.
  curl -sL "https://gitlab.archlinux.org/api/v4/projects/$project_id/repository/tags" | jq -r '.[0].name' || {
    log_error "Failed to fetch the latest version for $package_name from Arch Linux API"
    return 1
  }
}

# Function to increment semantic versioning
# This function assumes the version format is major.minor.patch
# It increments the patch version by 1.
# Example: 1.2.3 -> 1.2.4
increment_semver() {
  local version="$1"
  local major minor patch
  [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] && log_error "Invalid version format. Expected major.minor.patch" && return 1
  IFS='.' read -r major minor patch <<<"$version"
  ((patch++))
  echo "$major.$minor.$patch"
}

# semver_compare compares two semantic versions.
# Returns:
# - 0 if the versions are equal
# - 1 if version1 is greater than version2
# - -1 if version1 is less than version2
#
# Example usage:
#
# semver_compare "1.2.3" "1.2.3" -> 0
# semver_compare "1.2.3" "1.2.4" -> -1
# semver_compare "1.2.4" "1.2.3" -> 1
semver_compare() {
  local v1="${1//[[:space:]]/}" # Remove spaces from version1
  local v2="${2//[[:space:]]/}" # Remove spaces from version2

  # If either version is empty, treat them as equal
  [[ -z "$v1" || -z "$v2" ]] && echo 0 && return

  # Split the versions into their first components and remaining parts
  local v1_major="${v1%%.*}" v2_major="${v2%%.*}"
  local v1_rest="${v1#*.}" v2_rest="${v2#*.}"

  # Compare the major versions
  # shellcheck disable=SC2194
  case 1 in
  $((v1_major > v2_major))) echo 1 && return ;;
  $((v1_major < v2_major))) echo -1 && return ;;
  esac

  # If major versions are equal, recursively compare the rest
  [[ "$v1" == *.* && "$v2" == *.* ]] && semver_compare "$v1_rest" "$v2_rest" && return

  # If one version has more components, it's considered greater
  [[ "$v1" == *.* ]] && echo 1 && return
  [[ "$v2" == *.* ]] && echo -1 && return

  # Versions are equal
  echo 0
}

# compare_versions compares two versions based on the specified version schemes.
# It returns:
# 0 if the versions are equal
# -1 if version1 is less than version2
# 1 if version1 is greater than version2
#
# Supported version schemes:
# - archlinux: Uses the vercmp command from the Arch Linux container
# - semver: Uses semantic versioning comparison
# - custom: Custom comparison logic (not implemented)
#
# Example usage:
# compare_versions "1.2.3" "1.2.3" "semver" -> 0
# compare_versions "1.2.3" "1.2.4" "semver" -> -1
# compare_versions "1.2.4" "1.2.3" "semver" -> 1
compare_versions() {
  local version1="$1" version2="$2" scheme="$3"

  case "$scheme" in
  archlinux) docker exec "$ARCHLINUX_CONTAINER_NAME" vercmp "$version1" "$version2" ;;
  semver) semver_compare "$version1" "$version2" ;;
  custom) log_error "Custom comparison logic not implemented." && return 1 ;;
  *) log_error "Unknown versioning type: $scheme" && return 1 ;;
  esac
}

process_feature_lock_files() {
  local changelog_json
  changelog_json='{}'

  # For each devcontainer-feature-lock.json file, process the packages
  while read -r file; do
    local feature_dir feature_name devcontainer_file
    feature_dir=$(dirname "$file")
    feature_name=$(basename "$feature_dir")
    devcontainer_file="$feature_dir/devcontainer-feature.json"

    echo "======================================"
    echo "Processing Feature: $feature_name"
    echo "File: $file"
    echo "======================================"

    local feature_changes_made=false

    # Process each package in the lock file
    while read -r package; do
      local package_name package_version_current package_version_scheme package_check_latest_command package_version_latest
      package_name=$(jq -r '.name' <<<"$package")
      package_version_current=$(jq -r '.version' <<<"$package")
      package_version_scheme=$(jq -r '.versionScheme // "archlinux"' <<<"$package")
      package_check_latest_command=$(jq -r '.checkLatestCommand // empty' <<<"$package")

      echo
      log_info "Package: $package_name"
      log_info "Current Version: $package_version_current"
      log_info "Version scheme: $package_version_scheme"

      # Fetch the latest version based on versioning type
      case "$package_version_scheme" in
      archlinux) package_version_latest=$(fetch_archlinux_version "$package_name") ;;
      semver | custom)
        [[ -z "$package_check_latest_command" ]] && log_error "checkLatestCommand is required for $package_version_scheme versions." && continue
        package_version_latest=$(eval "$package_check_latest_command")
        ;;
      *) log_error "Unknown versioning type: $package_version_scheme" && continue ;;
      esac

      [[ -z "$package_version_latest" ]] && log_error "Failed to fetch the latest version for $package_name." && continue
      log_info "Latest Version: $package_version_latest"

      # Compare versions and update if necessary
      local compare_version_result
      compare_version_result=$(compare_versions "$package_version_current" "$package_version_latest" "$package_version_scheme")
      case "$compare_version_result" in
      0) log_info "Nothing to update. Version is already up to date." ;;
      1) log_error "Unexpected result: Current version is greater than latest version." ;;
      -1)
        log_warn "Updating package version for ($package_version_current -> $package_version_latest)."
        if [[ "$DRYRUN" == false ]]; then
          jq --arg name "$package_name" --arg version "$package_version_latest" \
            '(.packages[] | select(.name == $name) | .version) = $version' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
          log_checkpoint "Package version updated."
        fi

        # Add the change directly to changelog_json
        changelog_json=$(jq --arg feature "$feature_name" --arg name "$package_name" --arg from "$package_version_current" --arg to "$package_version_latest" \
          '.[$feature].changes += [{ $name, $from, $to }]' <<<"$changelog_json")
        feature_changes_made=true
        ;;
      *) log_error "Error: Unexpected result from compare_versions: $compare_version_result" ;;
      esac
    done < <(jq -c '.packages[]' "$file")

    if [[ "$feature_changes_made" != "true" ]]; then
      log_info "No changes to update for $feature_name." && continue
    fi

    local feature_version_current feature_version_next
    feature_version_current=$(jq -r '.version // "0.0.0"' "$devcontainer_file")
    feature_version_next=$(increment_semver "$feature_version_current")
    echo
    log_warn "Updating $feature_name version ($feature_version_current -> $feature_version_next)."
    if [[ "$DRYRUN" == false ]]; then
      jq --arg version "$feature_version_next" '(.version) = $version' "$devcontainer_file" \
        >"$devcontainer_file.tmp" && mv "$devcontainer_file.tmp" "$devcontainer_file"
      log_checkpoint "Feature version updated."
    fi

    changelog_json=$(jq --arg feature "$feature_name" --arg from "$feature_version_current" --arg to "$feature_version_next" \
      '.[$feature] += { $from, $to }' <<<"$changelog_json")
  done < <(find ./src -type f -name "devcontainer-feature-lock.json")

  echo "======================================"
  echo "Generating changelog..."
  echo "======================================"

  log_info "Writing JSON changelog..."
  local changelog_json_file="features-changelog.json"
  echo "$changelog_json" >"$changelog_json_file"
  log_checkpoint "JSON changelog written to $changelog_json_file."

  local changelog_md_file="features-changelog.md"
  log_info "Generating Markdown changelog..."
  printf "# Features Changelog\n" >"$changelog_md_file"
  jq -r '
  to_entries | .[] |
  "## \(.key) (\(.value.from) -> \(.value.to))\n\n" +
  "| Package | From | To |\n" +
  "| --- | --- | --- |\n" +
  (.value.changes[] | "| \(.name) | `\(.from)` | `\(.to)` |") +
  "\n"
  ' <"$changelog_json_file" >>"$changelog_md_file"
  log_checkpoint "Markdown changelog written to $changelog_md_file."
}

start_archlinux_container
trap stop_archlinux_container EXIT
process_feature_lock_files
