# Kria KR260 + Xen Environment Setup

`kr260-xen` turns the KR260 into a Xen host for the runPHI `backend_xen`, which
runs containers as Xen domains (`xl create`). It is [kria-xen](../../kria/xen/SETUP.md)
(Xen 4.22.0 and its tools from Buildroot 2026.08.1, linux-xlnx 6.18 LTS with
PREEMPT_RT for Dom0 and the guests) with the board setup of
[kr260-kvm](../kvm/SETUP.md): the KR260 at 192.168.100.53, TFTP+NFS boot from
192.168.100.45, Docker and LVM on the SD card, kr260-kvm on the SD card as the
fallback.

| Component | Built | Notes |
|---|---|---|
| Firmware (FSBL, PMUFW, ATF, U-Boot) | no | the BOOT.BIN in QSPI (Xilinx's 2022.1 Kria SOM firmware), whose U-Boot starts Xen at EL2 |
| Xen 4.22.0 | yes, by Buildroot | hypervisor (`output/rootfs/xen`, copied to `tftpboot/kr260-xen/`) and tools, kria-xen's `xen_4_22` patches |
| Linux (`xlnx_rebase_v6.18_LTS`, 6.18.40) | yes | `xen_kr260_kernel_defconfig` = kria-xen's `xen_kria_kernel_defconfig`; patches `preempt_rt`, `cma_default_heap` |
| Buildroot 2026.08.1 | yes | `xen_kr260_buildroot_defconfig`: kria-xen's with the hostname `kr260-xen` and this overlay |
| runPHI (`backend_xen`) | from runphi_manager | in the overlay, built with this environment's Buildroot toolchain |
| Jailhouse | no | Xen owns EL2 |

Access as for kr260-kvm: `ssh root@192.168.100.53`; the carrier's USB-UART
(interface 1, 115200) is Xen's console, then Dom0's login on `hvc0`.

## What differs from kria-xen

Everything that kria-xen's SETUP.md says about the kernel, the rootfs, Xen's
command line (`console=dtuart dtuart=serial1 dom0_mem=1024M dom0_max_vcpus=1
dom0_vcpus_pin vwfi=native`) and runPHI applies. The KR260's own parts come
from kr260-kvm (see its SETUP.md):

- `boot_sources/system_xen.dts`: kr260-kvm's `system_kvm.dts`, linux-xlnx
  6.18's DT of the KR260. Xen needs nothing else from it: the GIC-400 node
  lists GICH/GICV and the maintenance interrupt, `serial1` is
  `serial@ff010000` (the console), and the SMMU is disabled, so Dom0 is mapped
  1:1 and keeps every device.
- `boot_sources/boot_tftp.cmd`: kria-xen's, for `tftpboot/kr260-xen/` and
  `output/rootfs/kr260`; Dom0's `ip=` configures `eth1` (the J10D port, PS
  GEM0, see kr260-kvm); the SD card is `usb 0`; if a TFTP fetch fails, it boots
  kr260-kvm from the SD card (root by PARTUUID).
- `install/`: kria-xen's overlay (Docker in `/mnt/sd/runphi-xen/docker`,
  `test-vg` in `/mnt/sd/runphi-xen/lvm.img`, created at the first boot, the
  test images' `root/guest/`, `caronte`) with kr260-kvm's KR260 files: the SD
  card by label (`etc/fstab`, `etc/init.d/S28mnt-sd`, `root/boot_mode.sh`),
  `eth1` with 192.168.100.53 in `etc/network/interfaces`, `root/.profile`.

### USB in Dom0

kria-xen's SETUP.md lists "no USB in Dom0" among its platform constraints. On
the KR260, whose SD card is a USB disk, Dom0 has USB with the same Xen and
kernel: the controllers, the USB5744 hubs and the card's USB bridge probe, and
`/dev/sda2` is mounted on `/mnt/sd`. The USB drivers only make the firmware
calls `PM_RESET_ASSERT`/`PM_RESET_GET_STATUS` and `PM_IOCTL`, which Xen's ZynqMP
mediator forwards for the hardware domain; `xl dmesg` shows no
`No MMIO access` refusal, only two unhandled feature checks
(`PM_FEATURE_CHECK`), which Linux tolerates.

## Build

```sh
./scripts/build_environment.sh -t kr260 -b xen
./scripts/compile/dts_compile.sh -t kr260 -b xen
./scripts/compile/bootscr_compile.sh -t kr260 -b xen
cp environment/kr260/xen/output/rootfs/xen environment/kr260/xen/output/boot/{Image,system.dtb,boot.scr} tftpboot/kr260-xen/
```

On the server, as for kr260-kvm (`setup_nfs_rootfs.sh` gives the NFS root the
board's ssh host keys, those of kr260-kvm's NFS root):

```sh
sudo ./scripts/remote/setup_nfs_rootfs.sh -t kr260 -b xen
echo '/root/runphi/environment_builder/environment/kr260/xen/output/rootfs/kr260 *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
exportfs -r
./scripts/remote/switch_backend.sh -t kr260 -b xen -r   # kr260-xen, reboot the board now
./scripts/remote/switch_backend.sh -t kr260 -b kvm -r   # back to kr260-kvm
```

kr260-xen boots only over TFTP+NFS: the SD card holds kr260-kvm. On the board,
`/root/boot_mode.sh` shows `running from: NFS, kr260-xen (tftp mode)`.

## Verify the Xen host

```sh
xl info | grep -E 'xen_version|nr_cpus|total_memory|free_memory'
xl list                          # Domain-0, 1024 MB, 1 vCPU
xl vcpu-list                     # Domain-0's vCPU 0 on CPU 0
uname -v                         # ... SMP PREEMPT_RT ...
findmnt /mnt/sd                  # /dev/sda2, the SD card
vgs test-vg
```

## Test images and tests

`/root/guest/make_test_images.sh` builds `runphi-xen-guest:initramfs` and
`runphi-xen-guest:lvm` from `/root/guest/Image` (this environment's kernel,
`./scripts/remote/load_components_to_remote.sh -t kr260 -b xen -g`, or copy
`output/boot/Image` there) and `/root/guest/rootfs.cpio.gz`.

Tested on the KR260 on 2026-11-23 (runphi_manager 7dee20e):

- the board boots kr260-xen over TFTP+NFS: Xen 4.22.0 (`Platform: Xilinx
  ZynqMP`, 4 CPUs), Dom0 6.18.40-rt9 PREEMPT_RT with one vCPU pinned to CPU 0
  and 1024 MB, 3012 MB free for the domains; eth1 has the board's one static
  address; the SD card is mounted on `/mnt/sd`, `test-vg` was created at the
  first boot
- Docker 28 on cgroup v2 with the `runphi` runtime; `hello-world` from Docker
  Hub runs through runc (Docker's NAT rules, iptables-nft)
- `runphi-xen-guest:initramfs` runs on CPU 3; three guests run at once on
  CPUs 3, 2 and 1, and a fourth is refused (`not enough free CPUs: need 1,
  have 0 of 4`), as a guest larger than the free memory (`"memory": 3500`:
  `not enough free memory: need 3500 MB, have 3012 MB`)
- `runphi-xen-guest:lvm` gets a 168 MB volume of `test-vg`, mounts it as
  `/dev/xvda` and boots to its login prompt; the volume is removed with the
  container
- nothing is left behind (containers, domains, `/run/runPHI`, volumes)

## Platform constraints

kria-xen's, except USB (see above): GICv2 (at most 8 vCPUs per domain), Dom0
mapped 1:1 (no device passthrough), no network for the guests, no
`/dev/arm_timer`.
