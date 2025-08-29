#!/bin/sh
# shellcheck disable=SC2034
#-----------------------------------------------------------------------------------------------------------------
# Copyright (c) Bart Venter.
# Licensed under the MIT License. See https://github.com/bartventer/arch-devcontainer-features for license information.
#-----------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/bartventer/arch-devcontainer-features/tree/main/src/common-utils/README.md
# Maintainer: Bart Venter <https://github.com/bartventer>

set -e

INSTALL_ZSH="${INSTALLZSH:-"true"}"
ADDITIONAL_PACKAGES="${ADDITIONALPACKAGES:-""}"
CONFIGURE_ZSH_AS_DEFAULT_SHELL="${CONFIGUREZSHASDEFAULTSHELL:-"false"}"
INSTALL_OH_MY_ZSH="${INSTALLOHMYZSH:-"true"}"
INSTALL_OH_MY_ZSH_CONFIG="${INSTALLOHMYZSHCONFIG:-"true"}"
UPGRADE_PACKAGES="${UPGRADEPACKAGES:-"true"}"
USERNAME="${USERNAME:-"automatic"}"
# shellcheck disable=SC3028
USER_UID="${UID:-"automatic"}"
USER_GID="${GID:-"automatic"}"
MARKER_FILE="/usr/local/etc/vscode-dev-containers/common"

# Setup script dependencies
curl -sSL https://raw.githubusercontent.com/bartventer/arch-devcontainer-features/main/scripts/archlinux_util_setup.sh | sh

# shellcheck source=scripts/archlinux_util.sh disable=SC1091
. archlinux_util.sh

# Get OS info
# shellcheck source=/etc/os-release disable=SC1091
. /etc/os-release

# Run checks
check_root
check_system
check_pacman

# Install bash
check_and_install_packages "bash"

# Execute main script
exec /bin/bash "$(dirname "$0")/main.sh" "$@"
exit $?
