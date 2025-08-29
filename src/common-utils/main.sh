#!/bin/bash
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
USERNAME="${USERNAME:-"automatic"}"
USER_UID="${USERUID:-"automatic"}"
USER_GID="${USERGID:-"automatic"}"

MARKER_FILE="/usr/local/etc/vscode-dev-containers/common"

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ***********************
# ** Utility functions **
# ***********************

UTIL_SCRIPT="/usr/local/bin/archlinux_util.sh"

# Check if the utility script exists
if [ ! -x "$UTIL_SCRIPT" ]; then
    echo "Error: Required utility script not found: $UTIL_SCRIPT"
    exit 1
fi

# Source the utility script
# shellcheck disable=SC1091
# shellcheck source=scripts/archlinux_util.sh
. "$UTIL_SCRIPT"

# Arch Linux packages
install_arch_packages() {
    local package_list=()
    if [ "${PACKAGES_ALREADY_INSTALLED}" != "true" ]; then
        package_list=(
            "openssh"
            "gnupg"
            "iproute2"
            "procps-ng"
            "lsof"
            "htop"
            "inetutils"
            "psmisc"
            "curl"
            "tree"
            "wget"
            "rsync"
            "ca-certificates"
            "unzip"
            "bzip2"
            "xz"
            "zip"
            "nano"
            "vim"
            "less"
            "jq"
            "lsb-release"
            "dialog"
            "gcc-libs"
            "krb5"
            "icu"
            "lttng-ust"
            "zlib"
            "sudo"
            "ncdu"
            "man-db"
            "strace"
            "man-pages"
            "systemd-sysvcompat"
            "diffutils"
            "github-cli"
        )

        # Include git if not already installed (may be more recent than distro version)
        if ! type git >/dev/null 2>&1; then
            package_list+=("git")
        fi

        # Additonal packages (space separated string). Eg: "docker-compose kubectl"
        if [ -n "${ADDITIONAL_PACKAGES}" ]; then
            echo "Additional packages to install: ${ADDITIONAL_PACKAGES}..."
            IFS=' ' read -r -a additional_pkgs <<<"${ADDITIONAL_PACKAGES}"
            package_list+=("${additional_pkgs[@]}")
        fi

    fi

    # Install the list of packages
    echo "Packages to verify are installed: ${package_list[*]}"
    check_and_install_packages "${package_list[@]}"

    # Install zsh (and recommended packages) if needed
    if [ "${INSTALL_ZSH}" = "true" ] && ! type zsh >/dev/null 2>&1; then
        check_and_install_packages zsh zsh-autocomplete zsh-completions zsh-syntax-highlighting
    fi

    PACKAGES_ALREADY_INSTALLED="true"

}

# ******************
# ** Main section **
# ******************

# Check if script is run as root
check_root

# Load markers to see which steps have already run
if [ -f "${MARKER_FILE}" ]; then
    echo "Marker file found:"
    cat "${MARKER_FILE}"
    # shellcheck disable=SC1090
    source "${MARKER_FILE}"
fi

# Ensure that login shells get the correct path if the user updated the PATH using ENV.
rm -f /etc/profile.d/00-restore-env.sh
echo "export PATH=${PATH//$(sh -lc 'echo $PATH')/\$PATH}" >/etc/profile.d/00-restore-env.sh
chmod +x /etc/profile.d/00-restore-env.sh

# Get OS info
# shellcheck source=/etc/os-release disable=SC1091
. /etc/os-release

# Install packages for appropriate OS
install_arch_packages

# If in automatic mode, determine if a user already exists, if not use vscode
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    if [ "${_REMOTE_USER}" != "root" ]; then
        USERNAME="${_REMOTE_USER}"
    else
        USERNAME=""
        POSSIBLE_USERS=("devcontainer" "vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
        for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
            if id -u "${CURRENT_USER}" >/dev/null 2>&1; then
                USERNAME=${CURRENT_USER}
                break
            fi
        done
        if [ "${USERNAME}" = "" ]; then
            USERNAME=vscode
        fi
    fi
elif [ "${USERNAME}" = "none" ]; then
    USERNAME=root
    USER_UID=0
    USER_GID=0
fi

# Create or update a non-root user to match UID/GID.
group_name="${USERNAME}"
if id -u "${USERNAME}" >/dev/null 2>&1; then
    # User exists, update if needed
    if [ "${USER_GID}" != "automatic" ] && [ "$USER_GID" != "$(id -g "$USERNAME")" ]; then
        group_name="$(id -gn "$USERNAME")"
        groupmod --gid "$USER_GID" "${group_name}"
        usermod --gid "$USER_GID" "$USERNAME"
    fi
    if [ "${USER_UID}" != "automatic" ] && [ "$USER_UID" != "$(id -u "$USERNAME")" ]; then
        usermod --uid "$USER_UID" "$USERNAME"
    fi
else
    # Create user
    if [ "${USER_GID}" = "automatic" ]; then
        groupadd "$USERNAME"
    else
        groupadd --gid "$USER_GID" "$USERNAME"
    fi
    if [ "${USER_UID}" = "automatic" ]; then
        useradd -s /bin/bash --gid "$USERNAME" -m "$USERNAME"
    else
        useradd -s /bin/bash --uid "$USER_UID" --gid "$USERNAME" -m "$USERNAME"
    fi
fi

# Add add sudo support for non-root user
if [ "${USERNAME}" != "root" ] && [ "${EXISTING_NON_ROOT_USER}" != "${USERNAME}" ]; then
    echo "$USERNAME" ALL=\(root\) NOPASSWD:ALL >/etc/sudoers.d/"$USERNAME"
    chmod 0440 /etc/sudoers.d/"$USERNAME"
    EXISTING_NON_ROOT_USER="${USERNAME}"
fi

# *********************************
# ** Shell customization section **
# *********************************

if [ "${USERNAME}" = "root" ]; then
    user_home="/root"
# Check if user already has a home directory other than /home/${USERNAME}
elif [ "/home/${USERNAME}" != "$(getent passwd "$USERNAME" | cut -d: -f6)" ]; then
    user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
else
    user_home="/home/${USERNAME}"
    if [ ! -d "${user_home}" ]; then
        mkdir -p "${user_home}"
        chown "${USERNAME}":"${group_name}" "${user_home}"
    fi
fi

# Restore user .bashrc / .profile / .zshrc defaults from skeleton file if it doesn't exist or is empty
possible_rc_files=(".bashrc" ".profile")
[ "$INSTALL_OH_MY_ZSH_CONFIG" == "true" ] && possible_rc_files+=('.zshrc')
[ "$INSTALL_ZSH" == "true" ] && possible_rc_files+=('.zprofile')
for rc_file in "${possible_rc_files[@]}"; do
    if [ -f "/etc/skel/${rc_file}" ]; then
        if [ ! -e "${user_home}/${rc_file}" ] || [ ! -s "${user_home}/${rc_file}" ]; then
            cp "/etc/skel/${rc_file}" "${user_home}/${rc_file}"
            chown "${USERNAME}":"${group_name}" "${user_home}/${rc_file}"
        fi
    fi
done

# Add RC snippet and custom bash prompt
if [ "${RC_SNIPPET_ALREADY_ADDED}" != "true" ]; then
    global_rc_path="/etc/bash.bashrc"
    cat "${FEATURE_DIR}/scripts/rc_snippet.sh" >>"${global_rc_path}"
    cat "${FEATURE_DIR}/scripts/bash_theme_snippet.sh" >>"${user_home}/.bashrc"
    if [ "${USERNAME}" != "root" ]; then
        cat "${FEATURE_DIR}/scripts/bash_theme_snippet.sh" >>"/root/.bashrc"
        chown "${USERNAME}":"${group_name}" "${user_home}/.bashrc"
    fi
    RC_SNIPPET_ALREADY_ADDED="true"
fi

# Optionally configure zsh and Oh My Zsh!
if [ "${INSTALL_ZSH}" = "true" ]; then
    if [ ! -f "${user_home}/.zprofile" ]; then
        touch "${user_home}/.zprofile"
        # shellcheck disable=SC2016
        echo 'source $HOME/.profile' >>"${user_home}/.zprofile" # TODO: Reconsider adding '.profile' to '.zprofile'
        chown "${USERNAME}":"${group_name}" "${user_home}/.zprofile"
    fi

    if [ "${ZSH_ALREADY_INSTALLED}" != "true" ]; then
        global_rc_path="/etc/zsh/zshrc"
        cat "${FEATURE_DIR}/scripts/rc_snippet.sh" >>${global_rc_path}
        ZSH_ALREADY_INSTALLED="true"
    fi

    if [ "${CONFIGURE_ZSH_AS_DEFAULT_SHELL}" == "true" ]; then
        # Fixing chsh always asking for a password on alpine linux
        # ref: https://askubuntu.com/questions/812420/chsh-always-asking-a-password-and-get-pam-authentication-failure.
        if [ ! -f "/etc/pam.d/chsh" ] || ! grep -Eq '^auth(.*)pam_rootok\.so$' /etc/pam.d/chsh; then
            echo "auth sufficient pam_rootok.so" >>/etc/pam.d/chsh
        elif [[ -n "$(awk '/^auth(.*)pam_rootok\.so$/ && !/^auth[[:blank:]]+sufficient[[:blank:]]+pam_rootok\.so$/' /etc/pam.d/chsh)" ]]; then
            awk '/^auth(.*)pam_rootok\.so$/ { $2 = "sufficient" } { print }' /etc/pam.d/chsh >/tmp/chsh.tmp && mv /tmp/chsh.tmp /etc/pam.d/chsh
        fi

        chsh --shell /bin/zsh "${USERNAME}"
    fi

    # Adapted, simplified inline Oh My Zsh! install steps that adds, defaults to a codespaces theme.
    # See https://github.com/ohmyzsh/ohmyzsh/blob/master/tools/install.sh for official script.
    if [ "${INSTALL_OH_MY_ZSH}" = "true" ]; then
        user_rc_file="${user_home}/.zshrc"
        oh_my_install_dir="${user_home}/.oh-my-zsh"
        template_path="${oh_my_install_dir}/templates/zshrc.zsh-template"
        if [ ! -d "${oh_my_install_dir}" ]; then
            umask g-w,o-w
            mkdir -p "${oh_my_install_dir}"
            git clone --depth=1 \
                -c core.eol=lf \
                -c core.autocrlf=false \
                -c fsck.zeroPaddedFilemode=ignore \
                -c fetch.fsck.zeroPaddedFilemode=ignore \
                -c receive.fsck.zeroPaddedFilemode=ignore \
                "https://github.com/ohmyzsh/ohmyzsh" "${oh_my_install_dir}" 2>&1

            # Shrink git while still enabling updates
            cd "${oh_my_install_dir}"
            git repack -a -d -f --depth=1 --window=1
        fi

        # Add Dev Containers theme
        mkdir -p "${oh_my_install_dir}"/custom/themes
        cp -f "${FEATURE_DIR}/scripts/devcontainers.zsh-theme" "${oh_my_install_dir}/custom/themes/devcontainers.zsh-theme"
        ln -sf "${oh_my_install_dir}/custom/themes/devcontainers.zsh-theme" "${oh_my_install_dir}/custom/themes/codespaces.zsh-theme"

        # Add devcontainer .zshrc template
        if [ "$INSTALL_OH_MY_ZSH_CONFIG" = "true" ]; then
            echo -e "$(cat "${template_path}")\nDISABLE_AUTO_UPDATE=true\nDISABLE_UPDATE_PROMPT=true" >"${user_rc_file}"
            sed -i -e 's/ZSH_THEME=.*/ZSH_THEME="devcontainers"/g' "${user_rc_file}"
        fi

        # Copy to non-root user if one is specified
        if [ "${USERNAME}" != "root" ]; then
            copy_to_user_files=("${oh_my_install_dir}")
            [ -f "$user_rc_file" ] && copy_to_user_files+=("$user_rc_file")
            cp -rf "${copy_to_user_files[@]}" /root
            chown -R "${USERNAME}":"${group_name}" "${copy_to_user_files[@]}"
        fi
    fi
fi

# *********************************
# ** Ensure config directory **
# *********************************
user_config_dir="${user_home}/.config"
if [ ! -d "${user_config_dir}" ]; then
    mkdir -p "${user_config_dir}"
    chown "${USERNAME}":"${group_name}" "${user_config_dir}"
fi

# ****************************
# ** Utilities and commands **
# ****************************

# code shim, it fallbacks to code-insiders if code is not available
cp -f "${FEATURE_DIR}/bin/code" /usr/local/bin/
chmod +rx /usr/local/bin/code

# On Arch Linux, 'systemctl' is the standard command for managing systemd services,
# and systemd is always running. Therefore, a shim for 'systemctl' is not necessary.

# Persist image metadata info, script if meta.env found in same directory
if [ -f "/usr/local/etc/vscode-dev-containers/meta.env" ] || [ -f "/usr/local/etc/dev-containers/meta.env" ]; then
    cp -f "${FEATURE_DIR}/bin/devcontainer-info" /usr/local/bin/devcontainer-info
    chmod +rx /usr/local/bin/devcontainer-info
fi

# Write marker file
if [ ! -d "/usr/local/etc/vscode-dev-containers" ]; then
    mkdir -p "$(dirname "${MARKER_FILE}")"
fi
echo -e "\
    PACKAGES_ALREADY_INSTALLED=${PACKAGES_ALREADY_INSTALLED}\n\
    LOCALE_ALREADY_SET=${LOCALE_ALREADY_SET}\n\
    EXISTING_NON_ROOT_USER=${EXISTING_NON_ROOT_USER}\n\
    RC_SNIPPET_ALREADY_ADDED=${RC_SNIPPET_ALREADY_ADDED}\n\
    ZSH_ALREADY_INSTALLED=${ZSH_ALREADY_INSTALLED}" >"${MARKER_FILE}"

echo "Done! Common utilities devcontainer feature has been installed."
