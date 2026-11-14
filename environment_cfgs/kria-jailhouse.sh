#!/bin/bash

# The KV260 as a Jailhouse host (the Omnivisor fork) for runPHI's
# backend_jailhouse: linux-xlnx 6.1 LTS with the Jailhouse enabling patches and
# PREEMPT_RT, Buildroot 2026.08.1, TFTP+NFS boot from 192.168.100.45 like
# kria-kvm and kria-xen (scripts/remote/switch_backend.sh -t kria -b jailhouse).
# See environment/kria/jailhouse/SETUP.md.

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
# boot_tftp.cmd: kernel and DTB over TFTP from kria-jailhouse/, NFS root; if TFTP
# fails, kria-kvm from the SD card.
# system_omnv.dts: the KV260 with the jailhouse@7e000000 reservation and the
# remoteproc nodes of the Omnivisor.
BOOTCMD_CONFIG="tftp"
DTS_CONFIG="omnv"

## COMPONENTS ##
# QEMU
QEMU_BUILD="n"

# ATF, U-BOOT, BOOTGEN: the BOOT.BIN of the Kria's QSPI (FSBL, PMUFW, the ATF
# fork with the Omnivisor changes, U-Boot), which kria-kvm and kria-xen boot
# from too. The QSPI holds a build of these sources (U-Boot 2022.01-gff67091f,
# ATF v2.8 6fca8a8); updating it (e.g. U-Boot xlnx_rebase_v2026.01) is a
# separate step, see SETUP.md.
ATF_BUILD="y"
ATF_COMPILE_ARGS=""
ATF_PATCH_ARGS=""
ATF_REPOSITORY="https://github.com/DanieleOttaviano/arm-trusted-firmware.git"
ATF_BRANCH="master"
ATF_COMMIT=""
ATF_CONFIG=""

UBOOT_BUILD="y"
UPD_UBOOT_COMPILE_ARGS=""
UBOOT_COMPILE_ARGS=""
UBOOT_PATCH_ARGS=""
UBOOT_REPOSITORY="https://github.com/Xilinx/u-boot-xlnx.git"
UBOOT_BRANCH="xlnx_rebase_v2022.01"
UBOOT_COMMIT=""
UBOOT_CONFIG=""

# LINUX
# linux-xlnx 6.1 LTS (6.1.70, the last of the branch): the newest kernel that
# the Jailhouse driver and the enabling patches support (SETUP.md has what a
# move to 6.18 would take).
# jailhouse_enable: the Jailhouse enabling patches (exports, ivshmem, ...).
# omnivisor: the remoteproc changes of the Omnivisor.
# preempt_rt: 6.1.69-rt21 adapted to linux-xlnx 6.1.70, as kria-kvm's.
# omnv_fpga_rproc: the remoteproc drivers of the FPGA soft cores (PicoRV32, VS
# controller) that the Omnivisor loads for the cells of the DFX design.
# jailhouse_kria_isolcpu_kernel_defconfig: PREEMPT_RT, NO_HZ_FULL, HZ_1000, and
# the namespaces, cgroups and netfilter options of containerd and Docker 28 on
# cgroup v2.
# -s: stop the build if Kconfig drops any option of the defconfig (without the
# preempt_rt patch, PREEMPT_RT used to be dropped silently).
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS="-s"
LINUX_COMPILE_ARGS="-m"
LINUX_PATCH_ARGS="-d jailhouse_enable,omnivisor,preempt_rt,omnv_fpga_rproc"
LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"
LINUX_BRANCH="xlnx_rebase_v6.1_LTS"
LINUX_COMMIT=""
LINUX_CONFIG="isolcpu"

# BUILDROOT
# Buildroot 2026.08.1, as the other Kria environments: qemu-jailhouse's rootfs
# (Docker 28 with containerd, python3, gcc, ...) with the board's overlay.
# gcc_enabled: gcc on the target, the 2023.05 patch ported to 2026.08.1.
# -s: stop the build if Kconfig drops any option of the defconfig.
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS="-s"
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-d gcc_enabled"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2026.08.x"
BUILDROOT_COMMIT="7fdeadb3b9f12f78e5fccca914d7fef47090ab9a"
BUILDROOT_CONFIG=""

# JAILHOUSE
# The Omnivisor fork, its newest commit (rcpu driver cleanup, 2025-10-10).
# -r all: also the R5 and RISC-V inmate demos.
# omnv (custom_build/jailhouse/patch/omnv): pyjailhouse follows the
# Omnivisor's structures ("jailhouse cell linux"), the Linux demo cell gets the
# root cells' ivshmem links, and the root cell's firmware calls get all their
# results back.
JAILHOUSE_BUILD="y"
UPD_JAILHOUSE_COMPILE_ARGS=""
JAILHOUSE_COMPILE_ARGS="-n -r all"
JAILHOUSE_PATCH_ARGS="-d omnv"
JAILHOUSE_REPOSITORY="https://github.com/DanieleOttaviano/jailhouse.git"
JAILHOUSE_BRANCH="master"
JAILHOUSE_COMMIT="628a02d8cbba8a288793e09238e33b40cf4910b0"
JAILHOUSE_CONFIG="omnv"

# BOOTGEN
BOOTGEN_BUILD="y"
BOOTGEN_COMPILE_ARGS=""
BOOTGEN_PATCH_ARGS=""
BOOTGEN_REPOSITORY="https://github.com/Xilinx/bootgen.git"
BOOTGEN_BRANCH="xlnx_rel_v2022.1"
BOOTGEN_COMMIT="c77d7998d0db56f8a19642275e061b308bc24d53"
BOOTGEN_CONFIG=""
