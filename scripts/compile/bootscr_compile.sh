#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  This script compile the bootscr for the specified <target> and <backend>:\r\n \
    [-c <config> compile boot_<config>.cmd instead of the BOOTCMD_CONFIG one]\r\n \
    [-o <name> output file name in the boot directory (default: boot.scr)]\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-h help]" 1>&2
  exit 1
}

curr_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${curr_dir}")
source "${script_dir}"/common/common.sh

# Output name, so that alternative boot scripts (e.g. a TFTP/NFS variant built
# with BOOTCMD_CONFIG="tftp") can be produced without overwriting the default
# boot.scr and without having to rename the result by hand afterwards.
OUTPUT_NAME="boot.scr"

# Boot script to compile, when not the one selected by BOOTCMD_CONFIG in the
# environment configuration (e.g. both boot_sd.cmd and boot_tftp.cmd).
CONFIG_OVERRIDE=""

while getopts "c:o:t:b:h" o; do
  case "${o}" in
  c)
    CONFIG_OVERRIDE=${OPTARG}
    ;;
  o)
    OUTPUT_NAME=${OPTARG}
    ;;
  t)
    TARGET=${OPTARG}
    ;;
  b)
    BACKEND=${OPTARG}
    ;;
  h)
    usage
    exit 1
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND - 1))

# Set the Environment
source "${script_dir}"/common/set_environment.sh "${TARGET}" "${BACKEND}"

if [[ -n "${CONFIG_OVERRIDE}" ]]; then
  bootcmd_file=boot_${CONFIG_OVERRIDE}.cmd
fi

if [ "${UBUNTU_ROOTFS}" == "y" ]; then
  echo "UBUNTU_ROOTFS"
  mkimage -c none -A arm64 -T script -d "${boot_sources_dir}"/boot.script "${boot_dir}"/"${OUTPUT_NAME}".uimg
else
  mkimage -c none -A arm64 -T script -d "${boot_sources_dir}"/"${bootcmd_file}" "${boot_dir}"/"${OUTPUT_NAME}"
fi

if [ $? -ne 0 ]; then
  echo "ERROR: Boot script compilation failed!"
  exit 1
fi
echo "Boot script compiled successfully: ${boot_dir}/${OUTPUT_NAME}"
