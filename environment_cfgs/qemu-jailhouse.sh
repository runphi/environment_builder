#!/bin/bash

## Connection
## QEMU_NET is the network of the QEMU VM, for start_qemu.sh and the remote scripts:
##  "slirp": user-mode network, no root needed; the VM's ssh is forwarded to
##           localhost:${QEMU_SSH_PORT}
##  "tap":   the VM's eth0 on tap0, bridged to br0 by setup_bridge_tap.sh (as root),
##           at ${IP}; needed by the Zephyr DHCP and micro-ROS demos
## Override it without editing this file, e.g., export QEMU_NET=tap
QEMU_NET="${QEMU_NET:-slirp}"
USER="root"
if [[ "${QEMU_NET}" == "slirp" ]]; then
  QEMU_SSH_PORT="5022"
  IP="localhost"
  SSH_ARGS="-p ${QEMU_SSH_PORT}"
  RSYNC_ARGS_SSH="ssh -p ${QEMU_SSH_PORT}"
  RSYNC_ARGS="-e"
  RSYNC_REMOTE_PATH="/root"
elif [[ "${QEMU_NET}" == "tap" ]]; then
  IP="192.0.3.76"
  QEMU_TAP_GATEWAY="192.0.3.1" # br0's address in setup_bridge_tap.sh
  SSH_ARGS=""
  RSYNC_ARGS_SSH=""
  RSYNC_ARGS=""
  RSYNC_REMOTE_PATH=""
else
  echo "ERROR: QEMU_NET must be \"slirp\" or \"tap\", not \"${QEMU_NET}\""
  exit 1
fi


## CROSS COMPILING ARCHITECTURES
ARCH="arm64"

## If BUILDROOT_BUILD="y" you can use the buildroot compiler
# CROSS_COMPILE="${aarch64_buildroot_linux_gnu_dir}/aarch64-buildroot-linux-gnu-"
CROSS_COMPILE="aarch64-linux-gnu-" 

REMOTE_COMPILE="arm-none-eabi-"

## Boot Sources Configuration
BOOTCMD_CONFIG=""
DTS_CONFIG=""

## COMPONENTS ##

### EMULATION

# QEMU
# "y" builds the pinned release below in build/qemu, the same on every host;
# "n" runs the host's qemu-system-aarch64 instead (the target only needs the
# generic virt machine: Jailhouse also works with Ubuntu 24.04's QEMU 8.2.2).
QEMU_BUILD="y"
QEMU_COMPILE_ARGS=""
QEMU_PATCH_ARGS=""
QEMU_REPOSITORY="https://github.com/Xilinx/qemu.git"
QEMU_BRANCH="xlnx_rel_v2026.1.1"
QEMU_COMMIT="09c90f09b99af539a56b25fd91e005e1884e8d18"
QEMU_CONFIG=""

### FIRMWARE 

# ATF
ATF_BUILD="n"

# U-BOOT 
UBOOT_BUILD="n"

### KERNEL

# LINUX
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS=""
LINUX_COMPILE_ARGS="-m"
LINUX_PATCH_ARGS=""

## You can use Xilinx Linux by setting proper repo (no ivshmem-net support)
# LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"

LINUX_REPOSITORY="https://github.com/siemens/linux.git"
LINUX_BRANCH="jailhouse-enabling/5.15"
LINUX_COMMIT="" #E.g., LINUX_COMMIT="9f943ff23cec02b0b2db9e777197fb298ca2c4aa", LINUX_COMMIT="7484228ddbb5760eac350b1b4ffe685c9da9e765"
LINUX_CONFIG=""

### FILESYSTEM 

# BUILDROOT
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS=""
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-p 0001-gcc-target.patch"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2023.05.x"
BUILDROOT_COMMIT="25d59c073ac355d5b499a9db5318fb4dc14ad56c"
BUILDROOT_CONFIG=""

### BACKEND (e.g., Jailhouse, Xen, Linux full isol)

# JAILHOUSE
JAILHOUSE_BUILD="y"
UPD_JAILHOUSE_COMPILE_ARGS=""
JAILHOUSE_COMPILE_ARGS=""
JAILHOUSE_PATCH_ARGS="-p 0001-Update-for-kernel-version-greater-then-5-7-and-5-15.patch"
JAILHOUSE_REPOSITORY="https://gitlab.com/minervasys/public/jailhouse.git"
JAILHOUSE_BRANCH="minerva/public"
JAILHOUSE_COMMIT="b817b436e3fdaa7fad999b47adc94180b18bff75"
JAILHOUSE_CONFIG=""

### TARGET SPECIFIC (e.g., bootgen create BOOTBIN for Xilinx board)

# BOOTGEN
BOOTGEN_BUILD="n"
