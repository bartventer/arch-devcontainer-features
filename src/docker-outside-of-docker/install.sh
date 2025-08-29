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
DOCKER_VERSION="${VERSION:-"latest"}"
DOCKER_DASH_COMPOSE_VERSION="${DOCKERDASHCOMPOSEVERSION:-"v2"}" # v1 or v2 or none

ENABLE_NONROOT_DOCKER="${ENABLE_NONROOT_DOCKER:-"true"}"
SOURCE_SOCKET="${SOURCE_SOCKET:-"/var/run/docker-host.sock"}"
TARGET_SOCKET="${TARGET_SOCKET:-"/var/run/docker.sock"}"
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
INSTALL_DOCKER_BUILDX="${INSTALLDOCKERBUILDX:-"true"}"
INSTALL_DOCKER_COMPOSE_SWITCH="${INSTALLDOCKERCOMPOSESWITCH:-"true"}"

# Determine architecture
architecture=$(uname -m)
if [ "${architecture}" = "x86_64" ]; then
    architecture="amd64"
fi

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
        echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

#############################################
# Start docker-outside-of-docker installation
#############################################

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

# Setup a docker group in the event the docker socket's group is not root
if ! grep -qE '^docker:' /etc/group; then
    echo "(*) Creating missing docker group..."
    groupadd --system docker
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

# By default, make the source and target sockets the same
if [ "${SOURCE_SOCKET}" != "${TARGET_SOCKET}" ]; then
    touch "${SOURCE_SOCKET}"
    ln -s "${SOURCE_SOCKET}" "${TARGET_SOCKET}"
fi

# Add a stub if not adding non-root user access, user is root
if [ "${ENABLE_NONROOT_DOCKER}" = "false" ] || [ "${USERNAME}" = "root" ]; then
    echo -e '#!/usr/bin/env bash\nexec "$@"' >/usr/local/share/docker-init.sh
    chmod +x /usr/local/share/docker-init.sh
    exit 0
fi

DOCKER_GID="$(grep -oP '^docker:x:\K[^:]+' /etc/group)"

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

# If enabling non-root access and specified user is found, setup socat and add script
chown -h "${USERNAME}":root "${TARGET_SOCKET}"
check_and_install_packages socat
tee /usr/local/share/docker-init.sh >/dev/null \
    <<EOF
#!/usr/bin/env bash
#-----------------------------------------------------------------------------------------------------------------
# Copyright (c) Bart Venter.
# Licensed under the MIT License. See https://github.com/bartventer/arch-devcontainer-features for license information.
#-----------------------------------------------------------------------------------------------------------------

set -e

SOCAT_PATH_BASE=/tmp/vscr-docker-from-docker
SOCAT_LOG=\${SOCAT_PATH_BASE}.log
SOCAT_PID=\${SOCAT_PATH_BASE}.pid

# Wrapper function to only use sudo if not already root
sudoIf()
{
    if [ "\$(id -u)" -ne 0 ]; then
        sudo "\$@"
    else
        "\$@"
    fi
}

# Log messages
log()
{
    echo -e "[\$(date)] \$@" | sudoIf tee -a \${SOCAT_LOG} > /dev/null
}

echo -e "\n** \$(date) **" | sudoIf tee -a \${SOCAT_LOG} > /dev/null
log "Ensuring ${USERNAME} has access to ${SOURCE_SOCKET} via ${TARGET_SOCKET}"

# If enabled, try to update the docker group with the right GID. If the group is root,
# fall back on using socat to forward the docker socket to another unix socket so
# that we can set permissions on it without affecting the host.
if [ "${ENABLE_NONROOT_DOCKER}" = "true" ] && [ "${SOURCE_SOCKET}" != "${TARGET_SOCKET}" ] && [ "${USERNAME}" != "root" ] && [ "${USERNAME}" != "0" ]; then
    SOCKET_GID=\$(stat -c '%g' ${SOURCE_SOCKET})
    if [ "\${SOCKET_GID}" != "0" ] && [ "\${SOCKET_GID}" != "${DOCKER_GID}" ] && ! grep -E ".+:x:\${SOCKET_GID}" /etc/group; then
        sudoIf groupmod --gid "\${SOCKET_GID}" docker
    else
        # Enable proxy if not already running
        if [ ! -f "\${SOCAT_PID}" ] || ! ps -p \$(cat \${SOCAT_PID}) > /dev/null; then
            log "Enabling socket proxy."
            log "Proxying ${SOURCE_SOCKET} to ${TARGET_SOCKET} for vscode"
            sudoIf rm -rf ${TARGET_SOCKET}
            (sudoIf socat UNIX-LISTEN:${TARGET_SOCKET},fork,mode=660,user=${USERNAME},backlog=128 UNIX-CONNECT:${SOURCE_SOCKET} 2>&1 | sudoIf tee -a \${SOCAT_LOG} > /dev/null & echo "\$!" | sudoIf tee \${SOCAT_PID} > /dev/null)
        else
            log "Socket proxy already running."
        fi
    fi
    log "Success"
fi

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
set +e
exec "\$@"
EOF
chmod +x /usr/local/share/docker-init.sh
chown "${USERNAME}":root /usr/local/share/docker-init.sh

echo "Done. Docker-outside-of-docker installed successfully!"
