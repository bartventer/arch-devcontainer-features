#!/usr/bin/env bash
#-----------------------------------------------------------------------------------------------------------------
# Copyright © 2024 Bart Venter <bartventer@outlook.com>

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-----------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/bartventer/arch-devcontainer-features/tree/main/src/git/README.md
# Maintainer: Bart Venter <https://github.com/bartventer>
#
# This script will:
#
# 1. Check if the script is running in dry run mode. If so, it will log a warning and make no changes.
# 2. Install the necessary tools (npm and system dependencies[git, curl, jq]).
# 3. Iterate over each feature in the src directory.
# 4. For each feature, it will:
#    - Get the last git tag.
#    - Check for diffs between the last tag and the HEAD for the feature. If no changes are detected, it will skip the version bump for this feature.
#    - Get the version increment based on the commit type. If no valid commit type is found, it will skip the version bump for this feature.
#    - Get the latest version of the feature.
#    - Increment the version.
#    - Update the version file.
#    - Commit the changes, push them, and create a PR.
#
# You can run this script manually or set up a GitHub Action to run it automatically.
# Here is an example of a GitHub Action that runs the script:
# Path: .github/workflows/bump-version.yml
#-----------------------------------------------------------------------------------------------------------------

set -euo pipefail

DRYRUN=${1:-"false"}

# GitHub Actions environment variables
CI=${CI:-"false"}
GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-"."}
# GitHub Actions repository variables
GH_USERNAME="${GH_ACTIONS_USERNAME:-"github-actions[bot]"}"
GH_USER_EMAIL="$GH_USERNAME@users.noreply.github.com"
GITHUB_REPOSITORY_OWNER="${GITHUB_REPOSITORY_OWNER:-"bartventer"}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-"${GITHUB_REPOSITORY_OWNER}/arch-devcontainer-features"}"

# Script variables
VERSION_FILE_NAME="devcontainer-feature.json"
JS_DEPS=("semver")
SYS_DEPS=("git" "curl" "jq")
DEFAULT_VERSION="0.0.0"
INITIAL_VERSION="1.0.0"
ISSUE_LABEL="bug"
FEATURE_DIR="src"

# Terminal colors
BLUE="\033[1;34m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"
CYAN="\033[1;36m"

log_message() {
    local symbol=$1
    shift
    echo -e "(${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${RESET}) [${BLUE}INFO${RESET}] ${symbol} $1"
}

log_info() {
    log_message "ℹ️" "$1"
}

log_checkpoint() {
    log_message "✔" "$1"
}

log_warn() {
    echo -e "(${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${RESET}) [${YELLOW}WARN${RESET}] 🔔 ${YELLOW}$1${RESET}" >&2
}

log_error() {
    echo -e "(${RED}$(date '+%Y-%m-%d %H:%M:%S')${RESET}) [${RED}ERROR${RESET}] ❕ ${RED}$1${RESET}" >&2
}

log_fatal() {
    echo -e "(${RED}$(date '+%Y-%m-%d %H:%M:%S')${RESET}) [${RED}FATAL${RESET}] ❌ ${RED}$1${RESET}" >&2
    exit 1
}

install_tools() {
    local missing_deps=0
    if [ "$CI" != "true" ]; then
        for tool in "${JS_DEPS[@]}" "${SYS_DEPS[@]}"; do
            if ! command -v $tool &>/dev/null; then
                log_error "Tool not found: $tool"
                missing_deps=1
                case $tool in
                "gh") log_error "Install GitHub CLI: see https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
                esac
            fi
        done
        if [ $missing_deps -eq 1 ]; then
            log_fatal "Missing dependencies. Exiting..."
        else
            return 0
        fi
    fi

    log_info "Installing JavaScript dependencies..."
    yarn global add "${JS_DEPS[@]}" || {
        echo "Failed to install JavaScript tools"
        exit 1
    }

    log_info "Installing system dependencies..."
    sudo apt-get install -y "${SYS_DEPS[@]}" || {
        echo "Failed to install system tools"
        exit 1
    }
}

get_version_increment() {
    local feature_name=$1
    local current_tag=$2
    local commit_messages=$(git log --pretty=format:"%s%n%n%b" $current_tag..HEAD -- $FEATURE_DIR/$feature_name)
    if echo "$commit_messages" | grep -qE 'BREAKING CHANGE'; then
        echo 'major'
    elif echo "$commit_messages" | grep -qE '^feat(\(.+\))?:'; then
        echo 'minor'
    elif echo "$commit_messages" | grep -qE '^fix(\(.+\))?:'; then
        echo 'patch'
    else
        echo ''
    fi
}

# ref: https://github.community/t/how-to-check-if-a-container-image-exists-on-ghcr/154836/3
get_latest_version() {
    local feature=$1
    local user_image="${GITHUB_REPOSITORY}/$(basename $feature)"
    local token=$(curl -s "https://ghcr.io/token?scope=repository:${user_image}:pull" | awk -F'"' '$0=$4')
    local tags=$(curl -s -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/${user_image}/tags/list" | jq -r '.tags[]' 2>/dev/null)
    if [ -z "$tags" ]; then
        echo $DEFAULT_VERSION
    else
        # Filter out non-numeric tags, sort the remaining tags, and select the last one
        echo $tags | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
    fi
}

increment_version() {
    local version_increment=$1
    local latest_version=$2
    if [ "$latest_version" = "$DEFAULT_VERSION" ]; then
        echo $INITIAL_VERSION
    else
        semver -i $version_increment $latest_version || {
            echo "Failed to increment version"
            exit 1
        }
    fi
}

update_version_file() {
    local new_version=$1
    local version_file_path=$2
    if [ ! -f $version_file_path ]; then
        log_fatal "Version file not found: $version_file_path"
    fi
    log_info "==> Version file path: $version_file_path"
    if [ "$CI" = "true" ]; then
        jq --arg new_version "$new_version" '.version |= $new_version' $version_file_path >"$version_file_path.tmp" &&
            mv "$version_file_path.tmp" $version_file_path ||
            { log_fatal "Failed to update version file"; }
    else
        log_warn "Dry run enabled. Redirecting output to stdout. \
                    \n :: feature: $feature \
                    \n :: new_version: $new_version"
        jq --arg new_version "$new_version" '.version |= $new_version' $version_file_path
    fi
}

commit_push_and_create_pr() {
    local feature=$1
    local latest_version=$2
    local new_version=$3
    local version_file_path=$4

    # Commit message and PR body (differentiate between initial release and subsequent releases)
    local commit_message
    local body="## :robot: This is an auto-generated PR to bump the image version.
- **Feature:** \`$(basename $feature)\`"
    if [ "$new_version" = "$INITIAL_VERSION" ]; then
        commit_message="chore(release/$(basename $feature)): initial release"
        body=$(printf "%s\n- **Version:** \`%s\`" "$body" "$new_version")
    else
        commit_message="chore(release/$(basename $feature)): bump version from $latest_version to $new_version"
        body=$(printf "%s\n- **Latest Version:** \`%s\`\n- **New Version:** \`%s\`" "$body" "$latest_version" "$new_version")
    fi
    commit_message="$commit_message [skip ci]"

    # Dry run
    if [ "$DRYRUN" = "true" ]; then
        log_warn "Dry run enabled. Skipping commit, push and PR creation. Redirecting output to stdout.
                    \n :: Commit message: $commit_message
                    \n :: PR body: \n$body"
        return
    fi

    # GitHub runner
    local workflow_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
    local workflow_info="### Workflow Information:
- **GitHub Actor:** \`$GITHUB_ACTOR\`
- **GitHub Repository:** \`$GITHUB_REPOSITORY\`
- **GitHub Triggering Actor:** \`$GITHUB_TRIGGERING_ACTOR\`
- **GitHub Workflow:** \`$GITHUB_WORKFLOW\`
- **GitHub Job:** \`$GITHUB_JOB\`
- **GitHub Run Number:** \`$GITHUB_RUN_NUMBER\`
- **GitHub Run Attempt:** \`$GITHUB_RUN_ATTEMPT\`
- **GitHub Event Name:** \`$GITHUB_EVENT_NAME\`
- **GitHub Runner OS:** \`$RUNNER_OS\`
- **GitHub Workflow URL:** [$workflow_url]($workflow_url)"

    # Git operations
    set -x
    git config --global user.email $GH_USER_EMAIL
    git config --global user.name $GH_USERNAME
    git config pull.rebase false
    local branch_name="bump-$(basename $feature)"
    # Delete remote branch if it exists
    # But first get open PRs on the branch
    open_prs=$(gh pr list --base $branch_name --state open)
    git push origin --delete $branch_name || true
    # Create new branch
    git checkout -B $branch_name main || { log_fatal "Failed to checkout branch"; }
    set +x

    log_info "Updating version file..."
    update_version_file "$new_version" "$version_file_path" || { log_fatal "Failed to update version file"; }
    log_checkpoint "OK. Version file updated."

    # Git operations
    set -x
    git add "$version_file_path" || { log_fatal "Failed to add changes"; }
    git commit -m "$commit_message" || { log_fatal "Failed to commit changes"; }
    git push origin $branch_name || { log_fatal "Failed to push changes"; }
    set +x

    # PR creation
    body=$(printf '%s\n%s' "$body" "$workflow_info")
    if ! new_pr=$(gh pr create \
        --title "$commit_message" \
        --body "$body" \
        --reviewer "$GITHUB_ACTOR" \
        --label "documentation" \
        --head "$(git rev-parse --abbrev-ref HEAD)"); then
        # Failure: Create an issue
        echo "Failed to create PR. Creating an issue instead."
        local issue_title="Failed to create PR: $commit_message"
        local existing_issue=$(gh issue list --label "$ISSUE_LABEL" --state open --search "$issue_title")
        if [ -z "$existing_issue" ]; then
            local issue_body="## :x: An error occurred while trying to create a PR.

### Error Details:
Please check the logs for more information.

$workflow_info"
            issue_body=$(printf '%s' "$issue_body")
            gh issue create --title "$issue_title" --label "$ISSUE_LABEL" --body "$issue_body" || { log_fatal "Failed to create issue"; }
        else
            echo "An issue with the same title already exists. Updating the existing issue instead."
            local issue_number=$(echo $existing_issue | cut -d' ' -f1)
            gh issue comment $issue_number --body "The workflow failed again. Please check the logs.\n\nWorkflow URL: $workflow_url" || { log_fatal "Failed to update issue"; }
        fi
    else
        log_checkpoint "OK. PR created: $new_pr"
        # If there were open PRs, comment on them to notify that they have been replaced
        if [ -n "$open_prs" ]; then
            echo "$open_prs" | while read pr; do
                pr_number=$(echo "${pr}" | cut -f1)
                gh pr comment "${pr_number}" --body "This PR has been replaced by #${new_pr}."
            done
        fi
    fi
}

main() {
    if [ "$DRYRUN" = "true" ]; then
        log_warn "Running in dry run mode. No changes will be made."
    fi
    log_info "Installing dependencies..."
    install_tools
    log_checkpoint "OK. Dependencies installed."

    current_tag=$(git describe --tags --abbrev=0) || { log_fatal "Failed to get the last tag"; }
    for feature in $FEATURE_DIR/*; do
        feature_name=$(basename $feature)
        log_info "[${CYAN}${feature_name}${RESET}] [tag: ${GREEN}${current_tag}${RESET}] Checking for diffs..."
        if ! git diff --name-only $current_tag..HEAD | grep -q "${FEATURE_DIR}/$feature_name"; then
            log_checkpoint "No changes detected. Skipping version bump."
            continue
        fi
        log_warn "OK. Changes detected."

        log_info "Getting version increment..."
        version_increment=$(get_version_increment "$feature_name" "$current_tag") ||
            { log_fatal "Failed to get version increment"; }
        if [ -z "$version_increment" ]; then
            log_checkpoint "No valid commit type found. Skipping version bump."
            continue
        fi
        log_checkpoint "OK. Version increment: $version_increment"

        log_info "Getting latest version..."
        latest_version=$(get_latest_version "$feature") ||
            { log_fatal "Failed to get latest version"; }
        log_checkpoint "OK. Latest version: $latest_version"

        log_info "Incrementing version..."
        new_version=$(increment_version "$version_increment" "$latest_version") ||
            { log_fatal "Failed to increment version"; }
        log_checkpoint "OK. New version: $new_version"

        log_info "Committing, pushing changes and creating PR..."
        version_file_path="$feature/$VERSION_FILE_NAME"
        if [ "$CI" = "true" ]; then
            version_file_path="${GITHUB_WORKSPACE}/$version_file_path"
        fi
        commit_push_and_create_pr "$feature" "$latest_version" "$new_version" "$version_file_path" ||
            { log_fatal "Failed to commit, push changes and create PR"; }
        log_checkpoint "OK. Changes committed, pushed and PR created."
    done
}

log_message "🚀" "Starting version bump..."
main
log_message "✅" "Done. Version bump completed."
