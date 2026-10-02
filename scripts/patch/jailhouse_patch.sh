#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  This script patch jailhouse with the <patch>:\r\n \
    [-p <patch>]\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-h help]" 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source "${script_dir}"/common/common.sh
source "${script_dir}"/common/patch_utils.sh

REMOVE=""

while getopts "p:t:b:h" o; do
  case "${o}" in
  p)
    PATCH=${OPTARG}
    ;;
  t)
    TARGET=${OPTARG}
    ;;
  b)
    BACKEND=${OPTARG}
    ;;
  h)
    usage
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND - 1))
reject_extra_args "$@"

# Set the Environment
source "${script_dir}"/common/set_environment.sh "${TARGET}" "${BACKEND}"

# Apply Patch if ${PATCH} exists
if [[ -z "${PATCH}" ]]; then
    echo "Skipping patch application."
elif [[ -f "${custom_jailhouse_patch_dir}/${PATCH}" ]]; then
    apply_patch "${jailhouse_dir}" "${custom_jailhouse_patch_dir}/${PATCH}" || exit 1
else
    echo "Patch not found!"
    echo "The available patches are:"
    ls ${custom_jailhouse_patch_dir}
    exit 1
fi
