#!/bin/bash

# QEMU emulation of a Xen host for runPHI backend_xen: the zcu104-xen kernel
# and rootfs (Xen tools, Docker, LVM) with the Xen hypervisor on an emulated
# board with 4 Cortex-A53 at EL2 and a GICv2, like the ZCU104. Functional tests
# only: every instruction is emulated, so timings mean nothing. See
# environment/qemu/xen/SETUP.md.

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
# Machine of start_qemu.sh: the ZCU104's 4 Cortex-A53 and 2 GB, at EL2
# (virtualization=on), with a GICv2 and its virtualization extensions, like the
# ZCU104's GIC-400: runPHI gives the Xen guests a GICv2 (gic_version="v2").
# Without an IOMMU, Xen maps Dom0 1:1 onto the RAM, and with 4 GB it does not
# find room for dom0_mem=1500M ("Failed to allocate requested dom0 memory").
QEMU_CPU="cortex-a53"
QEMU_SMP="4"
QEMU_MEM="2G"
QEMU_MACHINE="virt,gic-version=2,virtualization=on"
QEMU_APPEND=""
# Xen: QEMU boots the hypervisor built by Buildroot (output/rootfs/xen) with
# QEMU_XEN_ARGS, and hands the kernel to it as Dom0 (guest-loader), whose console
# is hvc0. The arguments are the ZCU104's (boot_sources/boot_xen.cmd of zcu104-xen)
# without dtuart=serial0: QEMU's device tree has no serial0 alias, and without
# dtuart Xen takes its UART from /chosen/stdout-path.
QEMU_XEN="y"
QEMU_XEN_ARGS="console=dtuart dom0_mem=1500M dom0_max_vcpus=1 vwfi=native"

### FIRMWARE

# ATF, U-BOOT, BOOTGEN: QEMU loads the kernel itself, at EL2
ATF_BUILD="n"
UBOOT_BUILD="n"
BOOTGEN_BUILD="n"

### KERNEL

# LINUX
# The zcu104-xen kernel, Dom0 and the guests' kernel at once: linux-xlnx 6.1,
# xen_qemu_kernel_defconfig is xen_zcu104_kernel_defconfig plus the drivers of
# QEMU's virt board (virtio-blk, PCI host, PL011, PL031), device-mapper built in
# (LVM guest disks), and what Docker 28 on cgroup v2 needs (Buildroot 2026.08.1):
# BPF_SYSCALL and CGROUP_BPF (runc's device rules), the iptables raw table and
# IPv6 NAT (its bridge network).
# -s: stop the build if Kconfig drops any option of the defconfig.
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS="-s"
LINUX_COMPILE_ARGS="-m"
LINUX_PATCH_ARGS=""
LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"
LINUX_BRANCH="xlnx_rebase_v6.1_LTS"
LINUX_COMMIT=""
LINUX_CONFIG=""

### FILESYSTEM

# BUILDROOT
# The zcu104-xen rootfs (Xen tools, Docker, LVM2, ...) as an ext4 disk image for
# QEMU, with this environment's overlay, plus the Xen hypervisor: hypervisor and
# tools from Buildroot's xen package, so always of the same version. Buildroot
# 2026.08.1 (zcu104-xen is still on 2023.05).
# gcc_enabled: gcc on the target, the 2023.05 patch ported to 2026.08.1.
# xen_4_22: Xen 4.22.0 instead of 2026.08.1's 4.21.1, Buildroot master's
# "package/xen: bump to version 4.22.0" (a962be2e).
# -s: stop the build if Kconfig drops any option of the defconfig.
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS="-s"
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-d gcc_enabled,xen_4_22"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2026.08.x"
BUILDROOT_COMMIT="7fdeadb3b9f12f78e5fccca914d7fef47090ab9a"
BUILDROOT_CONFIG=""

### BACKEND

# JAILHOUSE: Xen owns EL2
JAILHOUSE_BUILD="n"
