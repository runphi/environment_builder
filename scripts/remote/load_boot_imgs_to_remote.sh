#!/bin/bash

#WARNING: The hipotesys is that the board target has the boot partition mounted in /boot/firmware

usage() {
  echo -e "Usage: $0 \r\n \
  This script copy the selected <backend> images files in the <target> boot/firmware directory for the next boot:\r\n \
    [-s load boot script (boot.scr)]\r\n \
    [-c <name> load a named boot script from the boot dir (e.g. boot_tftp.scr)]\r\n \
    [-d load device tree blob]\r\n \
    [-i load Image>]\r\n \
    [-o load BOOT.BIN>]\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-h help]" 1>&2
  exit 1
}

curr_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${curr_dir}")
source ${script_dir}/common/common.sh

S=0
D=0
I=0
O=0
SCRIPT_NAME=""

while getopts "sdioc:t:b:h" o; do
  case "${o}" in
  s)
    S=1
    ;;
  c)
    SCRIPT_NAME=${OPTARG}
    ;;
  d)
    D=1
    ;;
  i)
    I=1
    ;;
  o)
    O=1
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
source ${script_dir}/common/set_environment.sh ${TARGET} ${BACKEND}

# Check input
if [ "${S}" -eq 0 ] && [ "${D}" -eq 0 ] && [ "${I}" -eq 0 ] && [ "${O}" -eq 0 ] && [ -z "${SCRIPT_NAME}" ]; then
  echo "ERROR: Select a project to sync!"
  usage
fi

# The boot partition is normally mounted read-only: leaving it writable means an
# unclean shutdown can corrupt BOOT.BIN/Image/boot.scr and brick the boot. Take
# it rw only for the copies, and put it back even if one of them fails.
RESTORE_RO=0
if ssh root@${IP} 'grep -q " /boot/firmware .* ro,\| /boot/firmware .*[ ,]ro[ ,]" /proc/mounts'; then
  echo "Remounting /boot/firmware read-write ..."
  ssh root@${IP} 'mount -o remount,rw /boot/firmware' || {
    echo "ERROR: could not remount /boot/firmware read-write"
    exit 1
  }
  RESTORE_RO=1
fi

restore_ro() {
  ssh root@${IP} 'sync'
  if [ ${RESTORE_RO} -eq 1 ]; then
    echo "Restoring /boot/firmware read-only ..."
    ssh root@${IP} 'mount -o remount,ro /boot/firmware'
  fi
}
trap restore_ro EXIT

# Copy boot.scr itself, not boot.scr* - the glob also matched the .bak copies
# kept on the host and pushed stale backups onto the target.
[ ${S} -eq 1 ] && scp -O ${boot_dir}/boot.scr root@${IP}:/boot/firmware/
[ -n "${SCRIPT_NAME}" ] && scp -O ${boot_dir}/"${SCRIPT_NAME}" root@${IP}:/boot/firmware/
[ ${D} -eq 1 ] && scp -O ${boot_dir}/*.dtb root@${IP}:/boot/firmware/
[ ${I} -eq 1 ] && scp -O ${boot_dir}/Image root@${IP}:/boot/firmware/
[ ${O} -eq 1 ] && scp -O ${boot_dir}/BOOT.BIN root@${IP}:/boot/firmware/

exit 0
