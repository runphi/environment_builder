#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  Start the qemu emulation for the specified <target> and <backend>, with the\r\n \
  network chosen by QEMU_NET in its environment_cfgs file (slirp or tap):\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-h help]" 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source "${script_dir}"/common/common.sh


while getopts "t:b:h" o; do
  case "${o}" in
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

if [[ "${TARGET}" != "qemu" ]]; then
  echo "ERROR: Only qemu target is supported."
  exit 1
fi

# Network: slirp forwards the VM's ssh to localhost; with tap, the VM has no DHCP
# server and its init script (S93config_net) takes its address from the kernel
# command line
case "${QEMU_NET}" in
slirp)
  netdev="user,id=eth0,hostfwd=tcp::${QEMU_SSH_PORT}-:22"
  net_append=""
  ;;
tap)
  if ! ip link show tap0 >/dev/null 2>&1; then
    echo "ERROR: no tap0 interface, run ${current_dir}/setup_bridge_tap.sh as root first"
    exit 1
  fi
  netdev="tap,id=eth0,ifname=tap0,script=no,downscript=no"
  net_append=" runphi.tap_ip=${IP}/24 runphi.tap_gw=${QEMU_TAP_GATEWAY}"
  ;;
*)
  echo "ERROR: ${TARGET}-${BACKEND} does not set QEMU_NET"
  exit 1
  ;;
esac

exec "${qemu_bin}" \
  -cpu cortex-a53 \
  -smp 16 \
  -m 4G \
  -machine virt,gic-version=3,virtualization=on,its=off \
  -nographic \
  -netdev "${netdev}" \
  -device virtio-net-device,netdev=eth0 \
  -drive file="${rootfs_dir}"/rootfs.ext2,if=none,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -kernel "${boot_dir}"/Image \
  -append "rootwait root=/dev/vda console=ttyAMA0 mem=768M${net_append}"
