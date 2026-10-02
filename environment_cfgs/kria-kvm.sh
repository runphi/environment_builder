#!/bin/bash

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
# boot_tftp.cmd: TFTP kernel+DTB from kria-kvm/, NFS root, SD fallback.
# system_kvm.dts: system_omnv.dts without the jailhouse@7e000000 reservation.
# KVM needs no special bootargs: the QSPI firmware already enters the kernel at
# EL2 (same requirement as Jailhouse) and the GIC-400 node already describes
# GICH/GICV and the maintenance IRQ used by the KVM vGICv2.
BOOTCMD_CONFIG="tftp"
DTS_CONFIG="kvm"

## COMPONENTS ##
# QEMU (host-side QEMU emulation of the board, not the on-target VMM:
# qemu-system-aarch64 for the guests is built by BUILDROOT, with libvirt)
QEMU_BUILD="n"

# ATF, U-BOOT, BOOTGEN
# Not built: the Kria boots BOOT.BIN from QSPI, and the firmware flashed for
# kria-jailhouse already hands over to Linux at EL2, which is all KVM needs.
ATF_BUILD="n"
UBOOT_BUILD="n"
BOOTGEN_BUILD="n"

# LINUX
# Same 6.1 LTS kernel as the other backends. KVM is built in (no hypervisor
# component to clone): kvm_kria_kernel_defconfig is the kube defconfig plus
# PREEMPT_RT, KVM, vhost, libvirt networking, LVM (device-mapper), FPGA regions
# and the virtio/PL011 drivers that let the same Image boot as a QEMU 'virt'
# guest.
# preempt_rt: 6.1.69-rt21 adapted to linux-xlnx 6.1.70 (see the patch header).
# No jailhouse_enable patches: KVM owns EL2, so jailhouse.ko could not load.
# -s: stop the build if Kconfig drops any option of the defconfig, so that a
# patch problem cannot silently produce a non-RT kernel.
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS="-s"
LINUX_COMPILE_ARGS="-m"
LINUX_PATCH_ARGS="-d preempt_rt"
LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"
LINUX_BRANCH="xlnx_rebase_v6.1_LTS"
LINUX_COMMIT=""
LINUX_CONFIG=""

# BUILDROOT
# Userspace for runPHI backend_kvm, which drives guests through virsh/libvirtd
# -> qemu-system-aarch64: libvirt (daemon + QEMU driver), QEMU (aarch64
# softmmu, SLIRP), LVM2 and e2fsprogs (disk_type "lvm"), Docker. libvirt
# requires udev, so /dev is managed by eudev instead of plain devtmpfs.
# -s: stop the build if Kconfig drops any option of the defconfig.
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS="-s"
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-d gcc_enabled"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2023.05.x"
BUILDROOT_COMMIT="25d59c073ac355d5b499a9db5318fb4dc14ad56c"
BUILDROOT_CONFIG=""

# JAILHOUSE
JAILHOUSE_BUILD="n"
