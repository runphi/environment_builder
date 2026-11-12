#!/bin/bash

# The KV260 as a Xen host for runPHI backend_xen, which runs containers as Xen
# domains (xl create): the Xen hypervisor and tools of qemu-xen (Buildroot
# 2026.08.1, Xen 4.22.0), the board setup of kria-kvm (TFTP+NFS boot from
# 192.168.100.45, Docker and LVM on the SD card), and linux-xlnx 6.18 LTS with
# PREEMPT_RT for Dom0 and the guests. See environment/kria/xen/SETUP.md.

## Connection
IP="192.168.100.46"
USER="root"
SSH_ARGS=""
RSYNC_ARGS_SSH=""
RSYNC_ARGS=""
RSYNC_REMOTE_PATH=""

## CROSS COMPILING ARCHITECTURES
ARCH="arm64"
BUILD_ARCH="aarch64"
CROSS_COMPILE="aarch64-linux-gnu-"
REMOTE_COMPILE="arm-none-eabi-"

## Boot Sources Configuration
# boot_tftp.cmd: Xen, Dom0's kernel and the DTB over TFTP from kria-xen/, Dom0's
# root over NFS; if TFTP fails, kria-kvm's system on the SD card.
# system_xen.dts: kria-kvm's system_kvm.dts (no jailhouse@7e000000
# reservation). U-Boot adds Xen's arguments and Dom0's kernel to /chosen.
BOOTCMD_CONFIG="tftp"
DTS_CONFIG="xen"

## COMPONENTS ##
# QEMU (host-side emulation of the board: qemu-xen is the emulated twin)
QEMU_BUILD="n"

# ATF, U-BOOT, BOOTGEN
# Not built: the Kria boots BOOT.BIN from QSPI, whose U-Boot starts Xen at EL2
# (the firmware flashed for kria-jailhouse, as for kria-kvm).
ATF_BUILD="n"
UBOOT_BUILD="n"
BOOTGEN_BUILD="n"

# LINUX
# Dom0 and the guests' kernel at once: linux-xlnx 6.18 LTS (the newest Xilinx
# LTS, release xilinx-v2026.1). xen_kria_kernel_defconfig is xilinx_defconfig
# plus PREEMPT_RT, Dom0 and domU Xen drivers, Docker 28 on cgroup v2, LVM
# (device-mapper) and the CPU isolation options of kria-kvm (see SETUP.md).
# preempt_rt: the 6.18.57-rt9 patch set. PREEMPT_RT is in mainline since 6.12;
# on arm64 the set only adds /sys/kernel/realtime, the -rt version suffix and a
# printk fix (see the patch README).
# cma_default_heap: mainline's c33efdfcfa6f, missing in linux-xlnx 6.18: without
# it a guest too small for the default CMA area (256 MB) crashes at boot.
# -s: stop the build if Kconfig drops any option of the defconfig.
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS="-s"
LINUX_COMPILE_ARGS="-m"
LINUX_PATCH_ARGS="-d preempt_rt,cma_default_heap"
LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"
LINUX_BRANCH="xlnx_rebase_v6.18_LTS"
LINUX_COMMIT=""
LINUX_CONFIG=""

# BUILDROOT
# qemu-xen's rootfs (Xen tools, Docker, LVM2, ...) with the Xen hypervisor
# (output/rootfs/xen, copied to tftpboot/kria-xen/), the kria-kvm board
# overlay, no disk image. Hypervisor and tools from Buildroot's xen package, so
# always of the same version.
# gcc_enabled: gcc on the target.
# xen_4_22: Xen 4.22.0 instead of 2026.08.1's 4.21.1, Buildroot master's
# "package/xen: bump to version 4.22.0" (a962be2e), and Xen's stable-4.22
# fix "xen/arm: Fix evaluation of parameters for SMCCC calls" (781b60f95140),
# without which every firmware call that Xen forwards for Dom0 fails: Dom0
# has no clocks, so no Ethernet (see the patch README).
# -s: stop the build if Kconfig drops any option of the defconfig.
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS="-s"
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-d gcc_enabled,xen_4_22"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2026.08.x"
BUILDROOT_COMMIT="7fdeadb3b9f12f78e5fccca914d7fef47090ab9a"
BUILDROOT_CONFIG=""

# JAILHOUSE: Xen owns EL2
JAILHOUSE_BUILD="n"
