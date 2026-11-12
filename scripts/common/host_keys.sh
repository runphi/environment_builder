#!/bin/bash
#WARNING: the script needs a defined ${environment_dir} (common.sh)
#
# One set of ssh host keys per board. The environments of a target are the
# same machine at the same address (one static IP per platform), so their NFS
# roots must present the same host keys: otherwise, after every
# switch_backend.sh, ssh refuses the board ("REMOTE HOST IDENTIFICATION HAS
# CHANGED") on every machine that knows it. dropbear writes its keys into
# /etc/dropbear of the NFS root at the first boot (S50dropbear turns the link
# to /var/run/dropbear into a directory) and creates other key types when a
# client asks for them (-R), so the set lives in the NFS roots themselves:
# these helpers copy it between the NFS roots of a target.

# host_key_dir <target> <backend>: /etc/dropbear of the environment's NFS root
host_key_dir() {
  echo "${environment_dir}/$1/$2/output/rootfs/$1/etc/dropbear"
}

# host_key_files <dir>: the host key files in <dir>, if it is a directory (a
# freshly extracted rootfs has the link to /var/run/dropbear instead)
host_key_files() {
  [[ -d "$1" && ! -L "$1" ]] || return 0
  find "$1" -maxdepth 1 -type f -name 'dropbear_*_host_key' -printf '%f\n' | sort
}

# host_key_source <target> <backend>: the other environment of <target> whose
# NFS root has the most host keys, or nothing
host_key_source() {
  local env best="" best_n=0 n
  while IFS= read -r env; do
    [[ "${env}" == "$1-$2" ]] && continue
    n=$(host_key_files "$(host_key_dir "$1" "${env#"$1"-}")" | wc -l)
    if [[ ${n} -gt ${best_n} ]]; then
      best=${env#"$1"-}
      best_n=${n}
    fi
  done < <(grep -x "$1-[^ ]*" "${ENVIRONMENTS_LIST}")
  echo "${best}"
}

# host_keys_differ <target> <backend> <source backend>: the key types that both
# NFS roots have but with different keys, one per line
host_keys_differ() {
  local dst src f
  dst=$(host_key_dir "$1" "$2")
  src=$(host_key_dir "$1" "$3")
  for f in $(host_key_files "${src}"); do
    [[ -f "${dst}/${f}" ]] && ! cmp -s "${src}/${f}" "${dst}/${f}" && echo "${f}"
  done
}

# install_board_host_keys <target> <backend> [<source backend>]
#
# Give the NFS root of <target>-<backend> the host keys of another environment
# of the target: <source backend> if given (replacing its keys of the same
# types; the old ones are kept in /etc/dropbear.replaced-<date>), else the one
# with the most keys (adding only the key types it lacks). Returns 0 when the keys are the
# board's (also when no environment of the target has any yet: the first boot
# creates them), 1 on an error, 2 when both have different keys of a type and
# no source was given: then nothing is changed.
install_board_host_keys() {
  local target=$1 backend=$2 source=${3:-} replace=0 dst src f conflicts
  if [[ -n "${source}" ]]; then
    if [[ "${source}" == "${backend}" ]] || ! grep -qx "${target}-${source}" "${ENVIRONMENTS_LIST}"; then
      echo "ERROR: ${target}-${source} is not another environment of ${target}"
      return 1
    fi
    replace=1
  else
    source=$(host_key_source "${target}" "${backend}")
  fi
  dst=$(host_key_dir "${target}" "${backend}")
  if [[ -z "${source}" ]]; then
    echo "ssh host keys: no other environment of ${target} has any; the first boot creates them"
    return 0
  fi
  src=$(host_key_dir "${target}" "${source}")
  if [[ -z "$(host_key_files "${src}")" ]]; then
    echo "ERROR: ${target}-${source} has no ssh host keys in ${src}"
    return 1
  fi
  conflicts=$(host_keys_differ "${target}" "${backend}" "${source}")
  if [[ -n "${conflicts}" && ${replace} -eq 0 ]]; then
    echo -e "${warn}WARNING: the ssh host keys of ${target}-${backend} are not those of ${target}-${source}:${norm}"
    echo "${conflicts}" | sed 's/^/  /'
    echo "  the board presents other host keys in each environment. To give ${target}-${backend}"
    echo "  the keys of ${target}-${source}: setup_nfs_rootfs.sh -t ${target} -b ${backend} -k ${source}"
    return 2
  fi
  # A freshly extracted rootfs: the link to /var/run/dropbear becomes a
  # directory, as S50dropbear would do at the first boot
  if [[ -L "${dst}" ]]; then
    rm -f "${dst}" || return 1
  fi
  mkdir -p "${dst}" && chmod 755 "${dst}" || return 1
  if [[ -n "${conflicts}" ]]; then
    local saved
    saved="${dst}.replaced-$(date +%Y-%m-%d-%H%M%S)"
    mkdir -p "${saved}" && for f in ${conflicts}; do cp -a "${dst}/${f}" "${saved}/"; done
    echo "ssh host keys: the replaced ones are in ${saved}"
  fi
  local copied=""
  for f in $(host_key_files "${src}"); do
    if [[ ! -f "${dst}/${f}" ]] || ! cmp -s "${src}/${f}" "${dst}/${f}"; then
      install -o root -g root -m 600 "${src}/${f}" "${dst}/${f}" || return 1
      copied="${copied} ${f}"
    fi
  done
  if [[ -n "${copied}" ]]; then
    echo "ssh host keys of ${target}-${source} copied to ${target}-${backend}:${copied}"
  else
    echo "ssh host keys: ${target}-${backend} has those of ${target}-${source}"
  fi
  return 0
}
