#!/bin/bash

# The KR260 (Kria K26 SOM on the KR carrier) as a KVM host for runPHI's
# backend_kvm: linux-xlnx 6.18 LTS with PREEMPT_RT and KVM, Buildroot 2026.08.1
# with libvirt and QEMU, TFTP+NFS boot from 192.168.100.45 like the KV260's
# environments (scripts/remote/switch_backend.sh -t kr260 -b kvm), and the same
# system on the SD card. See environment/kr260/kvm/SETUP.md.

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
# boot_tftp.cmd: TFTP kernel+DTB from kr260-kvm/, NFS root, SD fallback.
# boot_sd.cmd: the same kernel, DTB and rootfs from the SD card.
# system_kvm.dts: linux-xlnx 6.18's DT of the KR260 (zynqmp-smk-k26-revA with
# the zynqmp-sck-kr-g-revB carrier overlay), decompiled. KVM needs no special
# bootargs: the QSPI firmware enters the kernel at EL2, and the GIC-400 node
# describes GICH/GICV and the maintenance IRQ of the KVM vGICv2.
BOOTCMD_CONFIG="tftp"
DTS_CONFIG="kvm"

## COMPONENTS ##
# QEMU (host-side QEMU emulation of the board, not the on-target VMM:
# qemu-system-aarch64 for the guests is built by BUILDROOT, with libvirt)
QEMU_BUILD="n"

# ATF, U-BOOT, BOOTGEN
# Not built: the Kria boots BOOT.BIN from QSPI. The KR260's QSPI holds
# Xilinx's 2022.1 Kria SOM firmware (U-Boot 2022.01-g14ce5558), which hands over
# to Linux at EL2, all that KVM needs.
ATF_BUILD="n"
UBOOT_BUILD="n"
BOOTGEN_BUILD="n"

# LINUX
# linux-xlnx 6.18 LTS (the newest Xilinx LTS), as kria-xen. KVM is built in (no
# hypervisor component to clone): kvm_kr260_kernel_defconfig is kria-xen's
# xen_kria_kernel_defconfig (xilinx_defconfig plus PREEMPT_RT, Docker 28 on
# cgroup v2, LVM and CPU isolation) without Xen, plus kria-kvm's KVM, vhost,
# libvirt networking (legacy iptables) and the virtio/PL031 drivers that let
# the same Image boot as a QEMU 'virt' guest.
# preempt_rt: the 6.18.57-rt9 patch set, as kria-xen's.
# cma_default_heap: mainline's c33efdfcfa6f, as kria-xen's: without it a guest
# too small for the default CMA area (256 MB) crashes at boot.
# kvm_stage2_free_flush: invalidate all TLBs when a VM is torn down; on the
# Cortex-A53, what a dead guest leaves in the TLBs slows down the host's TLB
# invalidations, also on the isolated CPU, until a VMID rollover (see the patch).
# -s: stop the build if Kconfig drops any option of the defconfig.
LINUX_BUILD="y"
UPD_LINUX_COMPILE_ARGS="-s"
LINUX_COMPILE_ARGS="-m"
LINUX_PATCH_ARGS="-d preempt_rt,cma_default_heap,kvm_stage2_free_flush"
LINUX_REPOSITORY="https://github.com/Xilinx/linux-xlnx.git"
LINUX_BRANCH="xlnx_rebase_v6.18_LTS"
LINUX_COMMIT=""
LINUX_CONFIG=""

# BUILDROOT
# kria-kvm's userspace for runPHI backend_kvm, which drives guests through
# virsh/libvirtd -> qemu-system-aarch64: libvirt 12.9 (daemon + QEMU driver),
# QEMU (aarch64 softmmu, SLIRP), LVM2 and e2fsprogs (disk_type "lvm"), Docker.
# libvirt requires udev, so /dev is managed by eudev. Kernel headers 6.18.
# -s: stop the build if Kconfig drops any option of the defconfig.
BUILDROOT_BUILD="y"
UPD_BUILDROOT_COMPILE_ARGS="-s"
BUILDROOT_COMPILE_ARGS=""
BUILDROOT_PATCH_ARGS="-d gcc_enabled,libvirt_cgroup_v2,libvirt_12"
BUILDROOT_REPOSITORY="https://github.com/buildroot/buildroot.git"
BUILDROOT_BRANCH="2026.08.x"
BUILDROOT_COMMIT="7fdeadb3b9f12f78e5fccca914d7fef47090ab9a"
BUILDROOT_CONFIG=""

# JAILHOUSE
JAILHOUSE_BUILD="n"
