#!/usr/bin/env bash
#-----------------------------------------------------------------------------------------------------------------
# Copyright (c) Bart Venter.
# Licensed under the MIT License. See https://github.com/bartventer/arch-devcontainer-features for license information.
#-----------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/bartventer/arch-devcontainer-features/tree/main/src/aws-cli/README.md
# Maintainer: Bart Venter <https://github.com/bartventer>

# Set error handling
set -e

ENABLE_SHELL_COMPLETION=${ENABLESHELLCOMPLETION:-"true"}
INSTALL_SAM=${INSTALLSAM:-"none"}
SAM_VERSION=${SAMVERSION:-"latest"}

# Determine the architecture
architecture="$(uname -m)"
case ${architecture} in
x86_64) architecture="x86_64" ;;
aarch64 | armv8*) architecture="arm64" ;;
*)
    echo "(!) Architecture ${architecture} unsupported"
    exit 1
    ;;
esac

install_aws_cli() {
    echo "
#############################################################
#                                                           #
#  NOTICE: AWS CLI v2 has been moved to the Arch User       #
#  Repository (AUR). This script will now default to        #
#  installing AWS CLI v1 from the official repositories.    #
#                                                           #
#############################################################
"
    check_and_install_packages aws-cli
    echo "OK. AWS CLI installed."
}

install_sam_standalone() {
    check_and_install_packages curl unzip gnupg jq coreutils perl
    # Create a temporary directory
    local tmp_dir
    tmp_dir=$(mktemp -d -t sam-downloads-XXXX)

    # Get the latest release info from GitHub API
    echo ":: Fetching latest release info from GitHub API..."
    local github_api_url="https://api.github.com/repos/aws/aws-sam-cli/releases"
    local version
    case "${SAM_VERSION}" in
    latest) version=$(curl -sSL "${github_api_url}/latest" | jq -r ".tag_name") ;;
    *) version="${SAM_VERSION}" ;;
    esac

    # URL for AWS SAM CLI releases
    github_api_url+="/tags/${version}"
    local sam_base_url="https://github.com/aws/aws-sam-cli/releases/download/${version}"

    # Download AWS SAM CLI
    echo ":: Downloading AWS SAM CLI from ${sam_base_url}..."
    local sam_filename
    local sam_url
    sam_filename="aws-sam-cli-linux-${architecture}.zip"
    sam_url="${sam_base_url}/${sam_filename}"
    curl -sSL -o "${tmp_dir}/${sam_filename}" "${sam_url}"

    # Get the latest release info from GitHub API
    echo ":: Fetching latest release info from GitHub API..."
    local release_info
    release_info=$(curl -sSL "${github_api_url}")
    local body
    body=$(echo "${release_info}" | jq -r ".body")

    # Extract the expected hash for the downloaded file from the release info
    echo ":: Extracting expected hash from release info..."
    local expected_hash
    # shellcheck disable=SC2016
    expected_hash=$(echo "${body}" | perl -lne 'print $1 if /\*\*'"${sam_filename}"'\*\*.*?`([^`]+)`/')

    # Generate the SHA-256 hash of the downloaded file
    echo ":: Generating SHA-256 hash of the downloaded file..."
    local generated_hash
    generated_hash=$(sha256sum "${tmp_dir}/${sam_filename}" | awk '{ print $1 }')
    echo "Generated hash: ${generated_hash}"

    # Compare the generated hash with the expected hash
    if [ "${generated_hash}" != "${expected_hash}" ]; then
        echo "(!) Hash verification failed. Exiting..."
        exit 1
    fi
    echo ":: Hash verification succeeded."

    # Download the signature file
    local sam_sig_filename
    sam_sig_filename="${sam_filename}.sig"
    curl -sSL -o "${tmp_dir}/${sam_sig_filename}" "${sam_url}.sig"

    # Import the primary public key
    echo ":: Importing the primary public key..."
    gpg --import "sam-primary-public-key.txt"

    # Import the signer public key and extract the key ID
    echo ":: Importing the signer public key..."
    local key_output
    local key_id
    key_output=$(gpg --import "sam-signer-public-key.txt" 2>&1)
    key_id=$(echo "${key_output}" | grep -oP 'key \K\w+')

    # Verify the integrity of the signer public key
    echo ":: Verifying the integrity of the signer public key..."
    gpg --fingerprint "${key_id}"
    gpg --check-sigs "${key_id}"

    # Verify the signature of the downloaded zip file
    echo ":: Verifying the signature of the downloaded zip file..."
    if ! gpg --verify "${tmp_dir}/${sam_sig_filename}" "${tmp_dir}/${sam_filename}"; then
        echo "(!) Signature verification failed. Exiting..."
        exit 1
    fi

    # If the signature verification succeeds, proceed with the installation
    echo ":: Signature verification succeeded. Proceeding with the installation..."
    unzip "${tmp_dir}/${sam_filename}" -d sam-installation
    ./sam-installation/install
    echo "OK. AWS SAM CLI is installed."

    # Verify the installation
    local sam_version
    sam_version=$(sam --version)
    echo "SAM CLI version: ${sam_version}"

    # Clean up
    echo ":: Cleaning up..."
    rm -rf "${tmp_dir}"
}

install_sam_python() {
    check_and_install_packages python python-pip

    local sam_venv_path="$HOME/.aws-sam-venv"
    local sam_venv_bin="$sam_venv_path/bin"

    # Virtual environment setup
    echo ":: Setting up a Python virtual environment..."
    if [ ! -d "$sam_venv_path" ]; then
        echo "Directory $sam_venv_path does not exist. Creating it..."
        python3 -m venv "$sam_venv_path"
    fi
    echo "OK. Python virtual environment is set up."

    echo ":: Activating the Python virtual environment..."
    # shellcheck disable=SC1091
    source "$sam_venv_bin"/activate
    echo "OK. Python virtual environment is activated."

    # Upgrade pip, setuptools, and wheel. Then install the AWS SAM CLI
    pip install --upgrade pip setuptools wheel && pip install --upgrade aws-sam-cli

    # Deactivate the virtual environment
    echo ":: Deactivating the Python virtual environment..."
    deactivate
    echo "OK. Python virtual environment is deactivated."

    # Move the AWS SAM CLI executable to /usr/local/bin
    echo ":: Moving the AWS SAM CLI executable to /usr/local/bin..."
    ls -la "$sam_venv_bin"
    mv "$sam_venv_bin/sam" /usr/local/bin/sam

    # Verify the installation
    echo ":: Verifying the installation..."
    sam --version
    echo "OK. AWS SAM CLI is installed.
#####################################################################################################
#                                                                                                   #
#   To upgrade the AWS SAM CLI in the future, follow these steps:                                   #
#   1. Activate the Python virtual environment: source $sam_venv_bin/activate                       #
#   2. Upgrade the AWS SAM CLI: pip install --upgrade aws-sam-cli                                   #
#   3. Move the AWS SAM CLI executable to /usr/local/bin: mv $sam_venv_bin/sam /usr/local/bin/sam   #
#   4. Deactivate the Python virtual environment: deactivate                                        #
#                                                                                                   #
#####################################################################################################
"
}

install_sam() {
    echo "Setting up AWS SAM CLI..."
    case "${INSTALL_SAM}" in
    standalone) install_sam_standalone ;;
    python) install_sam_python ;;
    none) echo "Skipping AWS SAM CLI installation..." ;;
    *)
        echo "Invalid value for INSTALL_SAM. Please set it to 'standalone' or 'python'."
        exit 1
        ;;
    esac
}

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

# ==========
# == Main ==
# ==========

echo_msg "Installing AWS CLI devcontainer feature..."

# Check if script is run as root
check_root

# Run checks
check_system
check_pacman

install_aws_cli
if [ "${ENABLE_SHELL_COMPLETION}" = "true" ]; then
    enable_autocompletion "$(which aws_completer)" aws
fi
install_sam

# Install AWS SAM CLI
echo_msg "Done. AWS CLI devcontainer feature installed."
