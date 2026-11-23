#!/bin/bash
# Write a board's SD card from the outputs of a <target>/<backend>: the system
# that the board boots from the card (boot_sd.cmd), and the boot script that
# selects the network boot (boot_select.cmd).
#
# The card must already have two partitions, which are reformatted:
#   1: FAT32, label <TARGET>BOOT (upper case): Image, system.dtb, boot_sd.scr,
#      boot_tftp.scr (switch_backend.sh -g) and boot.scr, a copy of one of the
#      two (-m), which U-Boot's distro boot runs;
#   2: ext4, label <target>root: the rootfs (the buildroot tarball plus the
#      install overlay, as setup_nfs_rootfs.sh makes the NFS root), with an
#      empty /runphi directory for the board's local data.
# Create them with any partitioning tool first, e.g. (as root)
#   echo -e 'start=2048, size=1G, type=c, bootable\ntype=83' | sfdisk /dev/sdX
#
# No root needed: write access to the partitions is enough (the "disk" group),
# and nothing is mounted. The FAT partition is filled with mtools; the ext4
# one is created by mke2fs -d from the rootfs extracted under fakeroot, so it
# keeps the tarball's root:root ownership and the setuid bit of busybox.
#
# Every file of the FAT partition is read back and compared, and the ext4
# partition is checked with e2fsck -fn.
#
# The ssh host keys: the card's rootfs has none, so the first boot from it
# creates them; give them to the NFS roots of the target afterwards (copy
# /etc/dropbear from the board), so that the board has the same keys in both
# boot modes (scripts/common/host_keys.sh).

usage() {
  echo -e "Usage: $0 \r\n \
  This script writes the SD card of <target> from the outputs of <target>-<backend>:\r\n \
    -d <disk> the card (e.g. /dev/sdX or /dev/mmcblk0), with two partitions\r\n \
    [-m sd|tftp boot mode of the card: boot.scr is boot_sd.scr or boot_tftp.scr (default tftp)]\r\n \
    [-y do not ask for confirmation]\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-h help]" 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source "${script_dir}"/common/common.sh

DISK=""
MODE="tftp"
ASSUME_YES=0
while getopts "d:m:yt:b:h" o; do
  case "${o}" in
  d)
    DISK=${OPTARG}
    ;;
  m)
    MODE=${OPTARG}
    ;;
  y)
    ASSUME_YES=1
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

[[ -n "${DISK}" ]] || usage
[[ "${MODE}" == sd || "${MODE}" == tftp ]] || usage

# Set the Environment
source "${script_dir}"/common/set_environment.sh "${TARGET}" "${BACKEND}"

for tool in mkfs.vfat mcopy mdir mke2fs e2fsck fakeroot tar rsync; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: ${tool} not found (packages: dosfstools, mtools, e2fsprogs, fakeroot, tar, rsync)"
    exit 1
  fi
done

# The partitions of the card
case "${DISK}" in
*[0-9]) PART1=${DISK}p1 PART2=${DISK}p2 ;;
*) PART1=${DISK}1 PART2=${DISK}2 ;;
esac
for p in "${PART1}" "${PART2}"; do
  if [[ ! -b "${p}" ]]; then
    echo "ERROR: ${p} is not a block device: ${DISK} needs two partitions (see the header)"
    exit 1
  fi
  if [[ ! -w "${p}" ]]; then
    echo "ERROR: no write access to ${p} (root, or the group of the device: $(stat -c %G "${p}"))"
    exit 1
  fi
  if awk -v d="$(readlink -f "${p}")" '$1 == d { found = 1 } END { exit !found }' /proc/mounts; then
    echo "ERROR: ${p} is mounted; unmount it first"
    exit 1
  fi
done

BOOT_LABEL=${TARGET^^}BOOT
ROOT_LABEL=${TARGET}root
if [[ ${#BOOT_LABEL} -gt 11 ]]; then
  echo "ERROR: FAT label ${BOOT_LABEL} is longer than 11 characters"
  exit 1
fi

# The files
ROOTFS_TAR="${rootfs_dir}/rootfs.tar"
FAT_FILES=("${boot_dir}/Image" "${boot_dir}/system.dtb" "${boot_dir}/boot_sd.scr" "${boot_dir}/boot_tftp.scr")
for f in "${ROOTFS_TAR}" "${FAT_FILES[@]}"; do
  if [[ ! -f "${f}" ]]; then
    echo "ERROR: ${f} not found"
    case "${f}" in
    */boot_sd.scr) echo "       scripts/compile/bootscr_compile.sh -t ${TARGET} -b ${BACKEND} -c sd -o boot_sd.scr" ;;
    */boot_tftp.scr) echo "       scripts/remote/switch_backend.sh -t ${TARGET} -g ${f}" ;;
    *) echo "       build the environment first (scripts/build_environment.sh)" ;;
    esac
    exit 1
  fi
done

echo "Card:   ${DISK} ($(lsblk -dno SIZE,MODEL "${DISK}" 2>/dev/null | xargs))"
echo "  ${PART1}: FAT32 ${BOOT_LABEL}: $(for f in "${FAT_FILES[@]}"; do basename "${f}"; done | xargs), boot.scr = boot_${MODE}.scr"
echo "  ${PART2}: ext4 ${ROOT_LABEL}: ${ROOTFS_TAR#"${project_dir}/"} + ${install_dir#"${project_dir}/"}"
if [[ ${ASSUME_YES} -eq 0 ]]; then
  read -r -p "Everything on ${PART1} and ${PART2} will be lost. Continue? (y/n): " answer
  [[ "${answer,,}" =~ ^y(es)?$ ]] || exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# ---------- partition 1: FAT32 ----------
echo "Formatting ${PART1} (FAT32, ${BOOT_LABEL}) ..."
mkfs.vfat -F 32 -n "${BOOT_LABEL}" "${PART1}" >/dev/null || {
  echo "ERROR: mkfs.vfat failed"
  exit 1
}
export MTOOLS_SKIP_CHECK=1
cp "${boot_dir}/boot_${MODE}.scr" "${work}/boot.scr"
for f in "${FAT_FILES[@]}" "${work}/boot.scr"; do
  mcopy -o -i "${PART1}" "${f}" "::$(basename "${f}")" || {
    echo "ERROR: copying $(basename "${f}") failed"
    exit 1
  }
done
sync
mkdir -p "${work}/check"
for f in "${FAT_FILES[@]}" "${work}/boot.scr"; do
  mcopy -n -i "${PART1}" "::$(basename "${f}")" "${work}/check/" &&
    cmp -s "${f}" "${work}/check/$(basename "${f}")" || {
    echo "ERROR: $(basename "${f}") reads back different from ${PART1}"
    exit 1
  }
done
echo "  written and verified: $(mdir -b -i "${PART1}" :: | xargs -n1 basename | xargs)"

# ---------- partition 2: ext4 ----------
# Inside one fakeroot session: extract the tarball, apply the install overlay
# with root ownership and without group/other write permission (as
# setup_nfs_rootfs.sh does, for dropbear), create the filesystem from it.
echo "Creating ${PART2} (ext4, ${ROOT_LABEL}) from the rootfs ..."
mkdir -p "${work}/rootfs"
fakeroot -- bash -c '
  set -e
  tar -xpf "$1" -C "$2"
  rsync -a --chown=root:root --chmod=go-w "$3"/ "$2"/
  mkdir -p "$2/runphi"
  mke2fs -q -F -t ext4 -L "$4" -d "$2" "$5"
' _ "${ROOTFS_TAR}" "${work}/rootfs" "${install_dir}" "${ROOT_LABEL}" "${PART2}" || {
  echo "ERROR: creating the ext4 filesystem failed"
  exit 1
}
sync
e2fsck -fn "${PART2}" >"${work}/e2fsck.log" 2>&1 || {
  cat "${work}/e2fsck.log"
  echo "ERROR: e2fsck found problems on ${PART2}"
  exit 1
}
echo "  $(tail -1 "${work}/e2fsck.log")"

echo ""
echo "SD card ready: the board boots $([[ ${MODE} == tftp ]] && echo "the environment that ${TARGET}.scr on the TFTP server selects, else boot_sd.scr" || echo "from the card (boot_sd.scr)")"
