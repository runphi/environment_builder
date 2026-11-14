#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  This script patches jailhouse with the following options:\r\n \
    [-p <patch>] (single patch)\r\n \
    [-d <dir1,dir2,...>] (directories containing patches)\r\n \
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

ERROR=0
REMOVE=""
PATCH=""
PATCH_DIRS=()

while getopts "p:d:t:b:h" o; do
  case "${o}" in
  p)
    PATCH=${OPTARG}
    ;;
  d)
    split_patch_dirs "${OPTARG}"  # Read directories into an array
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

# Apply a single patch if provided
if [[ -n "${PATCH}" ]]; then
  if [[ -f "${custom_jailhouse_patch_dir}/${PATCH}" ]]; then
    apply_patch "${jailhouse_dir}" "${custom_jailhouse_patch_dir}/${PATCH}" || exit 1
  else
    echo "Patch not found!"
    echo "The available patches are:"
    ls ${custom_jailhouse_patch_dir}
    exit 1
  fi
fi

# Apply the patches of the directories, in the order given
for dir in "${PATCH_DIRS[@]}"; do
  apply_patch_dir "${jailhouse_dir}" "${custom_jailhouse_patch_dir}/${dir}" || { ERROR=1; break; }
done

if [[ -z "${PATCH}" && ${#PATCH_DIRS[@]} -eq 0 ]]; then
  echo "Skipping patch application."
fi

if [[ ${ERROR} -ne 0 ]]; then
  echo "ERROR: one or more JAILHOUSE patches failed (see above)"
fi
exit ${ERROR}
