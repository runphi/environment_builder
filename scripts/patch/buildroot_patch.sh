#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
This script patches Buildroot with the following options:\r\n \
  [-p <patch>]         (single patch)\r\n \
  [-d <dir1,dir2,...>]  (directories containing patches)\r\n \
  [-t <target>]\r\n \
  [-b <backend>]\r\n \
  [-h help]" 1>&2
  exit 1
}

# Directories
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source "${script_dir}/common/common.sh"
source "${script_dir}/common/patch_utils.sh"

ERROR=0
REMOVE=""
PATCH=""
PATCH_DIRS=()

# Process arguments
while getopts "p:d:t:b:h" o; do
  case "${o}" in
    p)
      PATCH=${OPTARG}
      ;;
    d)
      split_patch_dirs "${OPTARG}"  # Split comma-separated list into an array
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

# Set the environment (expects TARGET and BACKEND to be defined)
source "${script_dir}/common/set_environment.sh" "${TARGET}" "${BACKEND}"

# Apply a single patch if specified
if [[ -n "${PATCH}" ]]; then
  patch_file="${custom_buildroot_patch_dir}/${PATCH}"
  if [[ -f "${patch_file}" ]]; then
    apply_patch "${buildroot_dir}" "${patch_file}" || ERROR=1
  else
    echo "Patch not found: ${patch_file}"
    echo "The available patches are:"
    ls "${custom_buildroot_patch_dir}"
    exit 1
  fi
fi

# Apply patches from directories if specified
if [[ ${#PATCH_DIRS[@]} -gt 0 ]]; then
  # Remove in the reverse order of application
  [[ -n "${REMOVE}" ]] && PATCH_DIRS=($(printf '%s\n' "${PATCH_DIRS[@]}" | tac))
  for dir in "${PATCH_DIRS[@]}"; do
    apply_patch_dir "${buildroot_dir}" "${custom_buildroot_patch_dir}/${dir}" || { ERROR=1; break; }
  done
fi

# If neither a patch nor directories were specified, skip patching.
if [[ -z "${PATCH}" && ${#PATCH_DIRS[@]} -eq 0 ]]; then
  echo "Skipping patch application as no patch or directories were specified."
fi

if [[ ${ERROR} -ne 0 ]]; then
  echo "ERROR: one or more BUILDROOT patches failed (see above)"
fi
exit ${ERROR}
