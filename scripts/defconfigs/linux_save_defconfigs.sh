#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  This script saves the linux configuration of the selected environment:\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-n <name>  also save a copy as this name in custom_linux_config_dir]\r\n \
    [-h help]" 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source "${script_dir}"/common/common.sh

ALT_NAME=""

while getopts "t:b:n:h" o; do
  case "${o}" in
    t) TARGET=${OPTARG} ;;
    b) BACKEND=${OPTARG} ;;
    n) ALT_NAME=${OPTARG} ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

# Set the Environment
source "${script_dir}"/common/set_environment.sh "${TARGET}" "${BACKEND}"

read -r -p "Do you really want to save ${defconfig_linux_name} (if already exists it will be overwritten)? (y/n): " SAVE

# Save!
if [[ "${SAVE,,}" =~ ^y(es)?$ ]]; then
  echo "Saving LINUX config ..."
  echo "Saving default as '${defconfig_linux_name}' ..."
  [[ -n "${ALT_NAME}" ]] && echo "Also saving an additional copy as '${ALT_NAME}' ..."

  # Backup existing default copy, if present
  if [[ -f "${custom_linux_config_dir}/${defconfig_linux_name}" ]]; then
    cp "${custom_linux_config_dir}/${defconfig_linux_name}" \
       "${custom_linux_config_dir}/${defconfig_linux_name}_old"
  fi

  # If an alternate name was requested, back it up too (if present)
  if [[ -n "${ALT_NAME}" && -f "${custom_linux_config_dir}/${ALT_NAME}" ]]; then
    cp "${custom_linux_config_dir}/${ALT_NAME}" \
       "${custom_linux_config_dir}/${ALT_NAME}_old"
  fi

  # Save Linux defconfig
  make -C "${linux_dir}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" savedefconfig
  if [[ $? -ne 0 ]]; then
    echo "ERROR: The make command failed during the savedefconfig of LINUX"
    exit 1
  fi
  echo "LINUX defconfig has been successfully saved"

  # Copy to kernel config dir under the default defconfig name
  cp "${linux_dir}/defconfig" "${linux_config_dir}/${defconfig_linux_name}"

  # Copy default to custom configs dir
  cp "${linux_config_dir}/${defconfig_linux_name}" "${custom_linux_config_dir}/"

  # If requested, also save a second copy under ALT_NAME in custom configs dir
  if [[ -n "${ALT_NAME}" ]]; then
    cp "${linux_config_dir}/${defconfig_linux_name}" \
       "${custom_linux_config_dir}/${ALT_NAME}"
  fi
fi
