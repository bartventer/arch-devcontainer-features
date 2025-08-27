#!/bin/bash

set -e

# Optional: Import test library
# shellcheck disable=SC1091
source dev-container-features-test-lib

# go
check "version" go version | awk '{print $3}' | grep -E '^go1\.25rc1$'

# Report result
reportResults
