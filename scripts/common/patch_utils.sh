#!/bin/bash
# Helpers shared by the scripts in scripts/patch/.
#WARNING: the script needs a defined ${REMOVE} ("" to apply, "-R" to remove)

# File, in the root of a patched tree, that records the applied patches as
# "<sha256>  <patch name>" lines (the same idea as buildroot/quilt stamps).
PATCH_STAMP_NAME=".environment_builder_patches"

# apply_patch <tree> <patch_file>
#
# Apply (or, with REMOVE="-R", revert) a single patch in an idempotent and
# atomic way:
#   - patch already in the requested state -> skipped, returns 0
#   - patch applies cleanly                -> applied and recorded, returns 0
#   - anything else                        -> tree left untouched, returns 1
#
# Plain "patch" used to be called directly. When a hunk failed it still applied
# the rest of the file, and the failure was then ignored by the caller, so a
# patch could silently end up half-applied (e.g. PREEMPT_RT never taking effect).
#
# "Already applied" comes from the stamp file and not from a reverse dry run:
# in a series, later patches modify what earlier ones added (e.g. the
# ivshmem-net patches of jailhouse_enable), so on a fully patched tree the
# earlier patches no longer reverse-apply cleanly.
apply_patch() {
  local tree="$1"
  local patch_file="$2"
  local stamp="${tree}/${PATCH_STAMP_NAME}"
  local name sum recorded
  name=$(basename "${patch_file}")
  sum=$(sha256sum "${patch_file}" | cut -d' ' -f1)
  recorded=$(awk -v n="${name}" '$2 == n { print $1 }' "${stamp}" 2>/dev/null)

  if [[ -z "${REMOVE}" ]]; then
    if [[ "${recorded}" == "${sum}" ]]; then
      echo "Skipping ${name}: already applied"
      return 0
    fi
    if [[ -n "${recorded}" ]]; then
      echo "ERROR: a different version of ${name} is applied to ${tree}."
      echo "  Reset the tree (or remove the old version) and run again."
      return 1
    fi
    # Trees patched before the stamp file existed: accept a patch that is
    # cleanly applied already, and record it.
    if patch -p1 -f -s --dry-run -R -d "${tree}" <"${patch_file}" >/dev/null 2>&1; then
      echo "Skipping ${name}: already applied"
      echo "${sum}  ${name}" >>"${stamp}"
      return 0
    fi
  else
    if [[ -z "${recorded}" ]]; then
      echo "Skipping ${name}: not applied"
      return 0
    fi
  fi

  # Dry run first, so that a failing patch does not touch the tree at all.
  local out
  if ! out=$(patch -p1 -f --dry-run ${REMOVE} -d "${tree}" <"${patch_file}" 2>&1); then
    echo "ERROR: ${name} does not apply cleanly to ${tree}:"
    echo "${out}" | grep -E "FAILED|can't find file|Reversed|No file to patch" | sed 's/^/  /'
    echo "  (if the tree was patched by an older version of these scripts, reset it first)"
    return 1
  fi

  patch -p1 -f -s --no-backup-if-mismatch ${REMOVE} -d "${tree}" <"${patch_file}" || return 1
  if [[ -z "${REMOVE}" ]]; then
    echo "${sum}  ${name}" >>"${stamp}"
    echo "Patch ${name} applied"
  else
    sed -i "/  ${name//./\\.}\$/d" "${stamp}"
    echo "Patch ${name} removed"
  fi
  return 0
}

# apply_patch_dir <tree> <patch_dir>
#
# Apply every *.patch in <patch_dir> in name order (0001-, 0002-, ...), or
# revert them in reverse order with REMOVE="-R". Stops at the first failure,
# since the following patches of a series depend on it.
# Returns 1 if the directory is missing or a patch failed.
apply_patch_dir() {
  local tree="$1"
  local patch_dir="$2"

  if [[ ! -d "${patch_dir}" ]]; then
    echo "ERROR: Directory not found: ${patch_dir}"
    return 1
  fi

  echo "Processing patches from directory: ${patch_dir}"
  local order="sort"
  [[ -n "${REMOVE}" ]] && order="sort -r"
  local patches
  patches=$(find "${patch_dir}/" -type f -name "*.patch" | ${order})
  if [[ -z "${patches}" ]]; then
    echo "No patches found in directory: ${patch_dir}"
    return 0
  fi

  local patch_file
  for patch_file in ${patches}; do
    apply_patch "${tree}" "${patch_file}" || return 1
  done
  return 0
}

# split_patch_dirs <list>
#
# Split a comma-separated list of patch directories into the PATCH_DIRS array,
# trimming blanks around each entry, so "a, b" and "a,b" mean the same thing.
split_patch_dirs() {
  local entry
  PATCH_DIRS=()
  IFS=',' read -r -a _entries <<<"$1"
  for entry in "${_entries[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -n "${entry}" ]] && PATCH_DIRS+=("${entry}")
  done
}

# reject_extra_args <args...>
#
# Fail on arguments left over after getopts. They typically come from a blank
# after a comma in *_PATCH_ARGS ("-d dir1, dir2"): the variable is expanded
# unquoted, so "dir2" becomes a separate word and used to be silently ignored.
reject_extra_args() {
  if [[ $# -gt 0 ]]; then
    echo "ERROR: unexpected argument(s): $*"
    echo "       (a blank after a comma in a '-d' list splits it into separate words)"
    exit 1
  fi
}
