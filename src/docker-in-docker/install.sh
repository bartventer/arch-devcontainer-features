#!/usr/bin/env bash
#-----------------------------------------------------------------------------------------------------------------
# Copyright (c) Bart Venter.
# Licensed under the MIT License. See https://github.com/bartventer/arch-devcontainer-features for license information.
#-----------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/bartventer/arch-devcontainer-features/tree/main/src/git/README.md
# Maintainer: Bart Venter <https://github.com/bartventer>
set -e

# shellcheck disable=SC2034
DOCKER_VERSION="${VERSION:-"latest"}"                               # The Docker Engine + CLI should match in version
DOCKER_DASH_COMPOSE_VERSION="${DOCKERDASHCOMPOSEVERSION:-"latest"}" #latest, v2 or none
AZURE_DNS_AUTO_DETECTION="${AZUREDNSAUTODETECTION:-"true"}"
DOCKER_DEFAULT_ADDRESS_POOL="${DOCKERDEFAULTADDRESSPOOL:-""}"
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
INSTALL_DOCKER_BUILDX="${INSTALLDOCKERBUILDX:-"true"}"
INSTALL_DOCKER_COMPOSE_SWITCH="${INSTALLDOCKERCOMPOSESWITCH:-"true"}"

# Determine architecture
architecture=$(uname -m)
if [ "${architecture}" = "x86_64" ]; then
    architecture="amd64"
fi

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

# Setup STDERR.
err() {
    echo "(!) $*" >&2
}

# Source /etc/os-release to get OS info
# shellcheck disable=SC1091
. /etc/os-release

# Run checks
check_root
check_system
check_pacman

###################
# Helper Functions
# See: https://github.com/microsoft/vscode-dev-containers/blob/main/script-library/shared/utils.sh
###################

# Figure out correct version of a three part version number is not passed
find_version_from_git_tags() {
    local variable_name=$1
    local requested_version=${!variable_name}
    if [ "${requested_version}" = "none" ]; then return; fi
    local repository=$2
    local prefix=${3:-"tags/v"}
    local separator=${4:-"."}
    local last_part_optional=${5:-"false"}
    if [ "$(echo "${requested_version}" | grep -o "." | wc -l)" != "2" ]; then
        local escaped_separator=${separator//./\\.}
        local last_part
        if [ "${last_part_optional}" = "true" ]; then
            last_part="(${escaped_separator}[0-9]+)?"
        else
            last_part="${escaped_separator}[0-9]+"
        fi
        local regex="${prefix}\\K[0-9]+${escaped_separator}[0-9]+${last_part}$"
        # shellcheck disable=SC2155
        local version_list="$(git ls-remote --tags "${repository}" | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; then
            declare -g "${variable_name}"="$(echo "${version_list}" | head -n 1)"
        else
            set +e
            declare -g "${variable_name}"="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
    fi
    if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" >/dev/null 2>&1; then
        err "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
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

###########################################
# Start docker-in-docker installation
###########################################

# Dependencies
check_and_install_packages curl ca-certificates pigz iptables gnupg wget jq git docker
echo "Finished installing docker!"

# If 'docker-compose' command is to be included
docker_compose_path="/usr/bin/docker-compose"
if [ "${DOCKER_DASH_COMPOSE_VERSION}" != "none" ]; then
    check_and_install_packages docker-compose || echo "(*) Package docker-compose (Docker Compose v2) not available for OS ${ID}. Skipping."

    echo "Changing permissions for docker-compose..."
    chmod +x "${docker_compose_path}"
fi

# Install docker-compose switch if not already installed - https://github.com/docker/compose-switch#manual-installation
if [ "${INSTALL_DOCKER_COMPOSE_SWITCH}" = "true" ] && ! type compose-switch >/dev/null 2>&1; then
    if type docker-compose >/dev/null 2>&1; then
        check_and_install_packages which

        echo "(*) Installing compose-switch..."
        current_compose_path="$(which docker-compose)"
        compose_version=$(docker-compose --version | awk '{print $4}')
        target_compose_path="$(dirname "${current_compose_path}")/docker-compose-v${compose_version}"
        compose_switch_version="latest"
        find_version_from_git_tags compose_switch_version "https://github.com/docker/compose-switch"
        curl -fsSL "https://github.com/docker/compose-switch/releases/download/v${compose_switch_version}/docker-compose-linux-${architecture}" -o /usr/local/bin/compose-switch
        chmod +x /usr/local/bin/compose-switch
        # TODO: Verify checksum once available: https://github.com/docker/compose-switch/issues/11
        # Setup v1 CLI as alternative in addition to compose-switch (which maps to v2)
        echo "(*) Setting up compose-switch..."
        mv "${current_compose_path}" "${target_compose_path}"
        # update-alternatives is not available in Arch Linux, so we'll use a symlink instead
        ln -sf "${target_compose_path}" "${docker_compose_path}"
    else
        err "Skipping installation of compose-switch as docker compose is unavailable..."
    fi
fi

# If init file already exists, exit
if [ -f "/usr/local/share/docker-init.sh" ]; then
    echo "/usr/local/share/docker-init.sh already exists, so exiting."
    exit 0
fi
echo "docker-init doesn't exist, adding..."

# Create the docker group if it does not exist
# shellcheck disable=SC2002
if ! cat /etc/group | grep -e "^docker:" >/dev/null 2>&1; then
    groupadd -r docker
fi

# Add the user to the docker group
usermod -aG docker "${USERNAME}"

# Install docker-buildx if not already installed
if [ "${INSTALL_DOCKER_BUILDX}" = "true" ]; then
    check_and_install_packages docker-buildx

    docker_home="/usr/lib/docker"
    cli_plugins_dir="${docker_home}/cli-plugins"
    mkdir -p "${cli_plugins_dir}"
    buildx_path="${cli_plugins_dir}/docker-buildx"
    chmod +x "${buildx_path}"

    echo "Setting permissions for Docker home directory..."
    chown -R "${USERNAME}:docker" "${docker_home}"
    chmod -R g+r+w "${docker_home}"
    find "${docker_home}" -type d -print0 | xargs -n 1 -0 chmod g+s
fi

declare -A _completion_paths=(
    ["${HOME}/.zsh/completions/_docker"]="https://raw.githubusercontent.com/docker/cli/master/contrib/completion/zsh/_docker"
    ["${HOME}/.bash_completion.d/docker"]="https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker"
    ["${HOME}/.config/fish/completions/docker.fish"]="https://raw.githubusercontent.com/docker/cli/master/contrib/completion/fish/docker.fish"
)

for _completion_path in "${!_completion_paths[@]}"; do
    _completion_url="${_completion_paths[$_completion_path]}"
    if [ ! -f "${_completion_path}" ]; then
        echo "Enabling shell auto-completion for docker (${_completion_path})..."
        mkdir -p "$(dirname "${_completion_path}")"
        curl -sSL -o "${_completion_path}" "${_completion_url}"
        echo "OK. Autocompletion enabled."
    fi
done

unset _completion_paths

tee /usr/local/share/docker-init.sh >/dev/null \
    <<EOF
#!/bin/sh
#-----------------------------------------------------------------------------------------------------------------
# Copyright (c) Bart Venter.
# Licensed under the MIT License. See https://github.com/bartventer/arch-devcontainer-features for license information.
#-----------------------------------------------------------------------------------------------------------------

set -e

AZURE_DNS_AUTO_DETECTION=${AZURE_DNS_AUTO_DETECTION}
DOCKER_DEFAULT_ADDRESS_POOL=${DOCKER_DEFAULT_ADDRESS_POOL}
EOF

tee -a /usr/local/share/docker-init.sh >/dev/null \
    <<'EOF'
dockerd_start="AZURE_DNS_AUTO_DETECTION=${AZURE_DNS_AUTO_DETECTION} DOCKER_DEFAULT_ADDRESS_POOL=${DOCKER_DEFAULT_ADDRESS_POOL} $(cat << 'INNEREOF'
    # explicitly remove dockerd and containerd PID file to ensure that it can start properly if it was stopped uncleanly
    find /run /var/run -iname 'docker*.pid' -delete || :
    find /run /var/run -iname 'container*.pid' -delete || :

    # -- Start: dind wrapper script --
    # Maintained: https://github.com/docker/docker/blob/master/hack/dind

    export container=docker

    if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
        mount -t securityfs none /sys/kernel/security || {
            echo >&2 'Could not mount /sys/kernel/security.'
            echo >&2 'AppArmor detection and --privileged mode might break.'
        }
    fi

    # Mount /tmp (conditionally)
    if ! mountpoint -q /tmp; then
        mount -t tmpfs none /tmp
    fi

    set_cgroup_nesting()
    {
        # cgroup v2: enable nesting
        if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
            # move the processes from the root group to the /init group,
            # otherwise writing subtree_control fails with EBUSY.
            # An error during moving non-existent process (i.e., "cat") is ignored.
            mkdir -p /sys/fs/cgroup/init
            xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || :
            # enable controllers
            sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
                > /sys/fs/cgroup/cgroup.subtree_control
        fi
    }

    # Set cgroup nesting, retrying if necessary
    retry_cgroup_nesting=0

    until [ "${retry_cgroup_nesting}" -eq "5" ];
    do
        set +e
            set_cgroup_nesting

            if [ $? -ne 0 ]; then
                echo "(*) cgroup v2: Failed to enable nesting, retrying..."
            else
                break
            fi

            retry_cgroup_nesting=`expr $retry_cgroup_nesting + 1`
        set -e
    done

    # -- End: dind wrapper script --

    # Handle DNS
    set +e
        cat /etc/resolv.conf | grep -i 'internal.cloudapp.net' > /dev/null 2>&1
        if [ $? -eq 0 ] && [ "${AZURE_DNS_AUTO_DETECTION}" = "true" ]
        then
            echo "Setting dockerd Azure DNS."
            CUSTOMDNS="--dns 168.63.129.16"
        else
            echo "Not setting dockerd DNS manually."
            CUSTOMDNS=""
        fi
    set -e

    if [ -z "$DOCKER_DEFAULT_ADDRESS_POOL" ]
    then
        DEFAULT_ADDRESS_POOL=""
    else
        DEFAULT_ADDRESS_POOL="--default-address-pool $DOCKER_DEFAULT_ADDRESS_POOL"
    fi

    # Start docker engine
    ( dockerd $CUSTOMDNS $DEFAULT_ADDRESS_POOL > /tmp/dockerd.log 2>&1 ) &
INNEREOF
)"

sudo_if() {
    COMMAND="$*"

    if [ "$(id -u)" -ne 0 ]; then
        sudo $COMMAND
    else
        $COMMAND
    fi
}

retry_docker_start_count=0
docker_ok="false"

until [ "${docker_ok}" = "true"  ] || [ "${retry_docker_start_count}" -eq "5" ];
do
    # Start using sudo if not invoked as root
    if [ "$(id -u)" -ne 0 ]; then
        sudo /bin/sh -c "${dockerd_start}"
    else
        eval "${dockerd_start}"
    fi

    retry_count=0
    until [ "${docker_ok}" = "true"  ] || [ "${retry_count}" -eq "5" ];
    do
        sleep 1s
        set +e
            docker info > /dev/null 2>&1 && docker_ok="true"
        set -e

        retry_count=`expr $retry_count + 1`
    done

    if [ "${docker_ok}" != "true" ] && [ "${retry_docker_start_count}" != "4" ]; then
        echo "(*) Failed to start docker, retrying..."
        set +e
            sudo_if pkill dockerd
            sudo_if pkill containerd
        set -e
    fi

    retry_docker_start_count=`expr $retry_docker_start_count + 1`
done

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
exec "$@"
EOF

chmod +x /usr/local/share/docker-init.sh
chown "${USERNAME}":root /usr/local/share/docker-init.sh

echo 'Done. Docker-in-Docker installed successfully!'
