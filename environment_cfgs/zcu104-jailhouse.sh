#!/bin/bash

## Connection
#IP="143.225.229.215"
IP="192.168.100.47"
#IP="192.168.100.52"
USER="root"
SSH_ARGS=""
RSYNC_ARGS_SSH=""
RSYNC_ARGS=""
RSYNC_REMOTE_PATH=""

### CROSS COMPILING ARCHITECTURES
ARCH="arm64"
BUILD_ARCH="aarch64"
CROSS_COMPILE="aarch64-linux-gnu-"
REMOTE_COMPILE="arm-none-eabi-"

## Boot Sources Configuration
# boot_jailhouse.cmd: SD boot + isolcpus 2-3 for the non-root cells
# system_jailhouse.dts: reserves jailhouse@6f000000 and caps the memory node at
# 0x7f000000, so it fits both the -omnv (hv @0x6f000000) and the -root-col*
# (hv @0x7f000000) cells. NOTE: system.dts and system_omnv.dts do not compile
# (duplicate phandles, dma@fd5x0000 vs cpu@0-3).
BOOTCMD_CONFIG="jailhouse"
DTS_CONFIG="jailhouse"

## COMPONENTS ##
# QEMU
QEMU_BUILD="n"

# ATF
ATF_BUILD="y"
ATF_COMPILE_ARGS=""
ATF_PATCH_ARGS=""
ATF_REPOSITORY="https://github.com/DanieleOttaviano/arm-trusted-firmware.git"
ATF_BRANCH="master"
ATF_COMMIT=""
ATF_CONFIG=""

# U-BOOT 
UBOOT_BUILD="n"

# U-BOOT 
UBOOT_BUILD="n"

# LINUX
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS=""
LINUX_COMPILE_ARGS="-m -n"
LINUX_PATCH_ARGS="-d jailhouse_enable, omnivisor" #preempt_rt # STANDARD LINE
#LINUX_PATCH_ARGS=""
LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"
LINUX_BRANCH="xlnx_rebase_v6.1_LTS"
LINUX_COMMIT=""
LINUX_CONFIG=""

# BUILDROOT
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS=""
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-p 0001-gcc-target.patch"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2023.05.x"
BUILDROOT_COMMIT="25d59c073ac355d5b499a9db5318fb4dc14ad56c"
BUILDROOT_CONFIG=""

# JAILHOUSE
JAILHOUSE_BUILD="y"
UPD_JAILHOUSE_COMPILE_ARGS=""
JAILHOUSE_COMPILE_ARGS="-n -r all"
# GICv2 SGI fix: without it Jailhouse silently drops guest IPIs whose interrupt ID
# matches one already in a list register, ignoring the sender. That loses Linux
# wakeup IPIs (SGI 1 = IPI_CALL_FUNC) and wedges the root cell with the RCU
# grace-period kthread stuck in TASK_WAKING. Diagnosed 2026-08-06 on this board;
# see runphi_testing/tacle-bench-jailhouse-APU-baremetal/BUG_jailhouse_lost_sgi.md
JAILHOUSE_PATCH_ARGS="-p 0001-gicv2-do-not-drop-SGIs-from-different-senders.patch"
JAILHOUSE_REPOSITORY="https://github.com/DanieleOttaviano/jailhouse.git"
JAILHOUSE_BRANCH="master"
JAILHOUSE_COMMIT=""
JAILHOUSE_CONFIG=""

# BOOTGEN
BOOTGEN_BUILD="y"
BOOTGEN_COMPILE_ARGS=""
BOOTGEN_PATCH_ARGS=""
BOOTGEN_REPOSITORY="https://github.com/Xilinx/bootgen.git"
BOOTGEN_BRANCH="xlnx_rel_v2022.1"
BOOTGEN_COMMIT="c77d7998d0db56f8a19642275e061b308bc24d53"
BOOTGEN_CONFIG=""
