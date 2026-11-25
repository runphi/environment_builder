#!/bin/bash

# The KR260 as a Jailhouse host (the Omnivisor fork) for runPHI's
# backend_jailhouse: kria-jailhouse (linux-xlnx 6.1 LTS with the Jailhouse
# enabling patches and PREEMPT_RT, Buildroot 2026.08.1, the Omnivisor fork) with
# the board setup of kr260-kvm (TFTP+NFS boot from 192.168.100.45,
# scripts/remote/switch_backend.sh -t kr260 -b jailhouse, Docker on the SD card).
# The QSPI boot firmware needs the Omnivisor's TF-A. See
# environment/kr260/jailhouse/SETUP.md.

## Connection
IP="192.168.100.53"
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
# boot_tftp.cmd: kernel and DTB over TFTP from kr260-jailhouse/, NFS root; if
# TFTP fails, kr260-kvm from the SD card.
# system_omnv.dts: linux-xlnx 6.1's DT of the KR260 with the Omnivisor's
# additions of kria-jailhouse's (the reserved memory of Jailhouse, its cells and
# the R5 cores, the R5 TCMs, remoteproc and IPI mailboxes).
BOOTCMD_CONFIG="tftp"
DTS_CONFIG="omnv"

## COMPONENTS ##
# QEMU
QEMU_BUILD="n"

# ATF, U-BOOT, BOOTGEN: the Kria boots BOOT.BIN from QSPI. The Omnivisor needs
# its TF-A fork (two SMCs that let Jailhouse read and write the XMPU and QoS
# registers): output/boot/BOOT.BIN is the KR260's own QSPI image (Xilinx's
# 2022.1 Kria SOM firmware: FSBL, PMU firmware, U-Boot) with only its BL31
# replaced by the fork's (scripts/compile/zynqmp_bootbin.py), flashed to the
# A/B image that is not running (scripts/remote/kria_bootfw_update.py), see
# SETUP.md. Only TF-A is built here; U-Boot and bootgen are not needed.
ATF_BUILD="y"
ATF_COMPILE_ARGS=""
ATF_PATCH_ARGS=""
ATF_REPOSITORY="https://github.com/DanieleOttaviano/arm-trusted-firmware.git"
ATF_BRANCH="master"
ATF_COMMIT="6fca8a86ef1bbc61d8707445fe144076f626956b"
ATF_CONFIG=""

UBOOT_BUILD="n"

# LINUX
# linux-xlnx 6.1 LTS (6.1.70, the last of the branch): the newest kernel that
# the Jailhouse driver and the enabling patches support (SETUP.md has what a
# move to 6.18 would take).
# jailhouse_enable: the Jailhouse enabling patches (exports, ivshmem, ...).
# omnivisor: the remoteproc changes of the Omnivisor.
# preempt_rt: 6.1.69-rt21 adapted to linux-xlnx 6.1.70, as kria-kvm's.
# omnv_fpga_rproc: the remoteproc drivers of the FPGA soft cores (PicoRV32, VS
# controller) that the Omnivisor loads for the cells of the DFX design.
# jailhouse_kr260_isolcpu_kernel_defconfig (kria-jailhouse's): PREEMPT_RT, NO_HZ_FULL, HZ_1000, and
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
# omnv (custom_build/jailhouse/patch/omnv): kria-jailhouse's patches
# (pyjailhouse follows the Omnivisor's structures, the KV260 Linux demo cell gets
# the root cells' ivshmem links, the root cell's firmware calls get all their
# results back) and the KR260 root cell with the KV260's memory layout and no
# FPGA base design (the Omnivisor has no DFX design for the KR260).
JAILHOUSE_BUILD="y"
UPD_JAILHOUSE_COMPILE_ARGS=""
JAILHOUSE_COMPILE_ARGS="-n -r all"
JAILHOUSE_PATCH_ARGS="-d omnv"
JAILHOUSE_REPOSITORY="https://github.com/DanieleOttaviano/jailhouse.git"
JAILHOUSE_BRANCH="master"
JAILHOUSE_COMMIT="628a02d8cbba8a288793e09238e33b40cf4910b0"
JAILHOUSE_CONFIG="omnv"

# BOOTGEN
BOOTGEN_BUILD="n"
