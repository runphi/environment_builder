#!/bin/bash

# Populate the NFS root filesystem for a <target>/<backend> from the buildroot
# tarball plus the environment's install overlay.
#
# Run this ON THE MACHINE THAT EXPORTS THE ROOTFS OVER NFS (the TFTP/NFS server),
# in its own clone of this repository, as root.
#
# Root is required, and not just for write access: the tarball carries the real
# ownership (uid/gid 0) and the setuid bit on /bin/busybox. Extracting it as a
# normal user silently drops both, and the resulting rootfs boots but has a
# non-setuid busybox, so mount, umount and su fail on the target in confusing
# ways. For the same reason the overlay is applied with --chown=root:root.
#
# The kernel modules and the Jailhouse tree are NOT handled here: they come from
#   scripts/compile/linux_compile.sh     -n
#   scripts/compile/jailhouse_compile.sh -n
# which install straight into ${rootfs_dir}/${TARGET}.

usage() {
  echo -e "Usage: $0 \r\n \
  This script populates the NFS root filesystem of the selected <target>/<backend>:\r\n \
    [-f force re-extraction of the tarball over an existing rootfs]\r\n \
    [-o only re-apply the install overlay, do not touch the tarball]\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-h help]" 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source "${script_dir}"/common/common.sh

FORCE=0
OVERLAY_ONLY=0

while getopts "fot:b:h" o; do
  case "${o}" in
  f)
    FORCE=1
    ;;
  o)
    OVERLAY_ONLY=1
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

# Set the Environment
source "${script_dir}"/common/set_environment.sh "${TARGET}" "${BACKEND}"

NFS_ROOT="${rootfs_dir}/${TARGET}"
ROOTFS_TAR="${rootfs_dir}/rootfs.tar"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run this as root, otherwise the extracted rootfs loses root:root"
  echo "       ownership and the setuid bit on /bin/busybox."
  exit 1
fi

mkdir -p "${NFS_ROOT}"

if [ ${OVERLAY_ONLY} -eq 0 ]; then
  if [ ! -f "${ROOTFS_TAR}" ]; then
    echo "ERROR: ${ROOTFS_TAR} not found."
    echo "       Build it first (scripts/compile/buildroot_compile.sh) or copy it"
    echo "       over from the build machine."
    exit 1
  fi

  if [ -e "${NFS_ROOT}/bin/busybox" ] && [ ${FORCE} -eq 0 ]; then
    echo "${NFS_ROOT} already looks populated; use -f to re-extract, or -o to"
    echo "only re-apply the install overlay."
  else
    echo "Extracting $(basename "${ROOTFS_TAR}") into ${NFS_ROOT} ..."
    tar xf "${ROOTFS_TAR}" -C "${NFS_ROOT}"
    if [ $? -ne 0 ]; then
      echo "ERROR: extraction of the root filesystem failed!"
      exit 1
    fi
  fi
fi

# Apply the environment's install overlay on top, forcing root ownership: the
# repository is normally checked out as an unprivileged user, so the files carry
# that uid/gid and would otherwise end up owned by a random uid on the target.
if [ -d "${install_dir}" ]; then
  echo "Applying the install overlay from ${install_dir} ..."
  rsync -a --chown=root:root "${install_dir}"/ "${NFS_ROOT}"/
  if [ $? -ne 0 ]; then
    echo "ERROR: applying the install overlay failed!"
    exit 1
  fi
else
  echo "No install directory at ${install_dir}, skipping the overlay."
fi

echo ""
echo "NFS root filesystem ready: ${NFS_ROOT}"
echo "  size:    $(du -sh "${NFS_ROOT}" | cut -f1)"
echo "  setuid:  $(find "${NFS_ROOT}" -perm /6000 -type f 2>/dev/null | wc -l) file(s) (expect at least /bin/busybox)"
echo "  modules: $(ls "${NFS_ROOT}"/lib/modules 2>/dev/null | tr '\n' ' ')"
echo ""
echo "Remember to export it and reload the exports, e.g.:"
echo "  echo '${NFS_ROOT} *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports"
echo "  exportfs -r"
