#!/bin/bash

set -e

# Optional: Import test library
# shellcheck disable=SC1091
source dev-container-features-test-lib

# Feature specific tests
check "docker-daemon-check" bash -c "./_docker_daemon_check.sh"

check "no buildx" bash -c "docker buildx version 2>&1 | grep 'unknown command: docker buildx'"
check "docker-build" docker build ./

# Report result
reportResults
