#!/bin/bash

# QEMU emulation of a KVM host for runPHI backend_kvm: the kria-kvm kernel and
# rootfs (libvirt, QEMU, Docker, LVM) on an emulated board with 4 Cortex-A53 at
# EL2, like the KV260. Functional tests only: every instruction is emulated, so
# timings mean nothing. See environment/qemu/kvm/SETUP.md.

## Connection
## QEMU_NET is the network of the QEMU VM, for start_qemu.sh and the remote scripts:
##  "slirp": user-mode network, no root needed; the VM's ssh is forwarded to
##           localhost:${QEMU_SSH_PORT}
##  "tap":   the VM's eth0 on tap0, bridged to br0 by setup_bridge_tap.sh (as root),
##           at ${IP}
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
BUILD_ARCH="aarch64"
CROSS_COMPILE="aarch64-linux-gnu-"
REMOTE_COMPILE="arm-none-eabi-"

## Boot Sources Configuration
BOOTCMD_CONFIG=""
DTS_CONFIG=""

## COMPONENTS ##

### EMULATION

# QEMU
# The same pinned release as qemu-jailhouse; "n" runs the host's qemu-system-aarch64.
QEMU_BUILD="y"
QEMU_COMPILE_ARGS=""
QEMU_PATCH_ARGS=""
QEMU_REPOSITORY="https://github.com/Xilinx/qemu.git"
QEMU_BRANCH="xlnx_rel_v2026.1.1"
QEMU_COMMIT="09c90f09b99af539a56b25fd91e005e1884e8d18"
QEMU_CONFIG=""
# Machine of start_qemu.sh: the KV260's 4 Cortex-A53 (ARMv8.0, no VHE: KVM runs in
# nVHE mode, as on the board) and 4 GB, at EL2 (virtualization=on). The GIC is a
# GICv3, not the KV260's GICv2: KVM gives the guests the host's GIC version.
QEMU_CPU="cortex-a53"
QEMU_SMP="4"
QEMU_MEM="4G"
QEMU_MACHINE="virt,gic-version=3,virtualization=on"
QEMU_APPEND=""

### FIRMWARE

# ATF, U-BOOT, BOOTGEN: QEMU loads the kernel itself, at EL2
ATF_BUILD="n"
UBOOT_BUILD="n"
BOOTGEN_BUILD="n"

### KERNEL

# LINUX
# The kria-kvm kernel: linux-xlnx 6.1 with the same patches and defconfig
# (kvm_qemu_kernel_defconfig is a copy of kvm_kria_kernel_defconfig, which already
# has the virtio, PL011, PCI and GICv3 drivers of QEMU's virt board).
# preempt_rt: 6.1.69-rt21 adapted to linux-xlnx 6.1.70 (see the patch header).
# kvm_stage2_free_flush: invalidate all TLBs when a VM is torn down (see the patch).
# -s: stop the build if Kconfig drops any option of the defconfig.
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS="-s"
LINUX_COMPILE_ARGS="-m"
LINUX_PATCH_ARGS="-d preempt_rt,kvm_stage2_free_flush"
LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"
LINUX_BRANCH="xlnx_rebase_v6.1_LTS"
LINUX_COMMIT=""
LINUX_CONFIG=""

### FILESYSTEM

# BUILDROOT
# The kria-kvm rootfs (libvirt, QEMU, Docker, LVM2, eudev, ...) as an ext4 disk
# image for QEMU, with this environment's overlay.
# -s: stop the build if Kconfig drops any option of the defconfig.
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS="-s"
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-d gcc_enabled"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2023.05.x"
BUILDROOT_COMMIT="25d59c073ac355d5b499a9db5318fb4dc14ad56c"
BUILDROOT_CONFIG=""

### BACKEND

# JAILHOUSE: KVM owns EL2
JAILHOUSE_BUILD="n"
