# Kria KV260 + KVM Environment Setup

`kria-kvm` turns the KV260 into a KVM host for the runPHI `backend_kvm`, which
drives guests through `virsh` -> `libvirtd` -> `qemu-system-aarch64`.

KVM is part of the Linux kernel, so unlike Jailhouse there is no hypervisor
component to clone and build: the environment is the 6.1 LTS kernel with KVM
enabled plus a buildroot rootfs carrying libvirt and QEMU.

| Component | Built | Notes |
|---|---|---|
| Firmware (FSBL, PMUFW, ATF, U-Boot) | no | Reuses the BOOT.BIN in QSPI, see below |
| Linux (`xlnx_rebase_v6.1_LTS`) | yes | `kvm_kria_kernel_defconfig` |
| Buildroot 2023.05 | yes | `kvm_kria_buildroot_defconfig` |
| Jailhouse | no | KVM owns EL2, `jailhouse.ko` cannot load next to it |

## Firmware

The Kria boots BOOT.BIN from QSPI (see [../jailhouse/SETUP.md](../jailhouse/SETUP.md)).
KVM only needs the kernel to be entered at EL2, which the firmware flashed for
`kria-jailhouse` already does. Check it on the running board:

```sh
dmesg | grep 'started at EL2'
# CPU: All CPU(s) started at EL2
```

If that line says EL1, flash the kria-jailhouse BOOT.BIN first.

## What the configuration contains

### Kernel (`custom_build/linux/arch/arm64/configs/kvm_kria_kernel_defconfig`)

Generated from `jailhouse_kria_kube_kernel_defconfig` (cgroups for Docker)
plus:

- `PREEMPT_RT` (with `EXPERT`), from the `preempt_rt` patch: 6.1.69-rt21
  adapted to linux-xlnx 6.1.70. There is no 6.1.70-rt release; the only change
  is a dropped hunk for a function the Xilinx axienet driver does not have
  (details in the patch header). KVM on arm64 has no `!PREEMPT_RT` restriction.
- KVM host: `VIRTUALIZATION`, `KVM`, `VHOST_NET`, `VHOST_VSOCK`, `MACVTAP`
- libvirt networking: NAT/MASQUERADE, mangle, ebtables (as modules, installed by `linux_compile.sh -m`)
- `disk_type: "lvm"` guests: device-mapper (`DM_SNAPSHOT`, `DM_THIN_PROVISIONING`), `EXT4_FS`, `BLK_DEV_LOOP`
- guest drivers, so that the same `Image` also boots as a QEMU `virt` guest:
  `PCI_HOST_GENERIC`, virtio (mmio, pci, blk, net, console, balloon, rng), `SERIAL_AMBA_PL011`, `RTC_DRV_PL031`
- `NO_HZ_FULL`, `HZ_1000`, for the isolcpus/nohz_full handling in backend_kvm
- PL bitstream / DFX loading: `FPGA_BRIDGE`, `FPGA_REGION`, `OF_FPGA_REGION`,
  `XILINX_PR_DECOUPLER` (missing from the kube defconfig, which lacks `FPGA_BRIDGE`)

The environment passes `-s` to the defconfig update scripts
(`UPD_LINUX_COMPILE_ARGS`, `UPD_BUILDROOT_COMPILE_ARGS`): if Kconfig drops any
option of the defconfig, for example `PREEMPT_RT` because the patch did not
apply, the build stops instead of producing a different kernel.

### Rootfs (`custom_build/buildroot/configs/kvm_kria_buildroot_defconfig`)

The kria-jailhouse rootfs plus:

- `libvirt` with `libvirtd` and the QEMU driver (`virsh`, `S91virtlogd`, `S92libvirtd`)
- `qemu` system emulation, aarch64 target only, with SLIRP (`"net": "user"`)
- `lvm2`, `e2fsprogs` (`lvcreate`, `mkfs.ext4`)
- `procps-ng`: backend_kvm finds the QEMU process with `pgrep -f`, which the
  default busybox does not provide
- `eudev` for `/dev` management: libvirt requires udev, so this replaces the
  plain devtmpfs used by the other Kria environments

### Boot sources

- `system_kvm.dts`: `system_omnv.dts` without the `jailhouse@7e000000`
  reservation. The GIC-400 node already lists GICD/GICC/GICH/GICV and the
  maintenance interrupt (PPI 9) that the KVM vGICv2 needs.
- `boot_tftp.cmd` (default): kernel and DTB from `tftpboot/kria-kvm/` on
  192.168.100.45, NFS root from `output/rootfs/kria`, SD fallback.
- `boot.cmd`: SD card boot.

### Board setup (`install/` overlay)

Everything in `install/` ends up in the rootfs, both through buildroot
(`BR2_ROOTFS_OVERLAY`) and through `setup_nfs_rootfs.sh`, so it survives a
rebuild or a re-extraction of the NFS root:

- `root/.profile` (the same prompt and aliases as the zcu104 rootfs)
- `root/.ssh/authorized_keys`: not in git (`install/root/.ssh/` is ignored);
  put the public key of your own PC there before building or deploying, or
  the board only accepts the password login
- `etc/fstab`: buildroot's default plus the SD card's second partition,
  `/dev/mmcblk1p2` (the old SD rootfs, ext4), on `/mnt/sd`. Everything that
  needs a local disk lives in `/mnt/sd/runphi/`.
- `etc/docker/daemon.json`: Docker storage in `/mnt/sd/runphi/docker` with
  `overlay2`. overlay2 cannot use NFS (no whiteouts/xattrs), and without an
  explicit `storage-driver` Docker silently falls back to the slow `vfs`.
- `etc/init.d/S29lvm-loop`: the `test-vg` volume group used by backend_kvm for
  `"disk_type": "lvm"` lives in `/mnt/sd/runphi/lvm.img` (6 GB), because a
  physical volume cannot live on NFS. The script attaches it through a loop
  device and activates the VG at boot, and undoes both at shutdown.

The volume group itself is created once, on the board (also in the script
header):

```sh
mkdir -p /mnt/sd/runphi && fallocate -l 6G /mnt/sd/runphi/lvm.img
losetup -f /mnt/sd/runphi/lvm.img
pvcreate /dev/loop0 && vgcreate test-vg /dev/loop0   # the device losetup -a shows
```

To grow it later: stop the containers, enlarge the file (`fallocate -l 10G`),
then `losetup -c /dev/loop0 && pvresize /dev/loop0`.

## Build

```sh
./scripts/build_environment.sh -t kria -b kvm
./scripts/compile/dts_compile.sh -t kria -b kvm
./scripts/compile/bootscr_compile.sh -t kria -b kvm
```

`linux_compile.sh` copies `Image` to `tftpboot/kria-kvm/`, but `dts_compile.sh`
only writes `output/boot/system.dtb`, so copy the DTB by hand:

```sh
cp environment/kria/kvm/output/boot/system.dtb tftpboot/kria-kvm/
```

`output/boot/boot.scr` (from `boot_tftp.cmd`) goes on the FAT partition of the
SD card, where U-Boot's distro boot finds it; it then fetches everything else
over TFTP and falls back to the SD card if the server is unreachable.

Then populate the NFS root on the server, as for the other environments:

```sh
sudo ./scripts/remote/setup_nfs_rootfs.sh -t kria -b kvm
```

### Updating the rootfs of a running board

`setup_nfs_rootfs.sh -f` re-extracts every file of `rootfs.tar`. Over NFS, a
program whose file is replaced on the server gets "stale file handle" errors,
so only do that while the board is not running from the NFS root. On a running
board, stage the new rootfs and copy only the files whose content changed,
leaving the state that the board manages itself alone (dropbear host keys,
libvirt's own files); as root on the server, in `output/rootfs/`:

```sh
mkdir staging && tar xf rootfs.tar -C staging
rsync -a --checksum --exclude=/etc/dropbear --exclude=/etc/libvirt/ --exclude=/var/lib/libvirt/ staging/ kria/
rm -rf staging
```

then apply the overlay with `setup_nfs_rootfs.sh -t kria -b kvm -o` and reboot
the board.

## Verify the KVM host

On the board:

```sh
uname -v                           # ... SMP PREEMPT_RT ...
cat /sys/kernel/realtime           # 1
dmesg | grep -i kvm
# ... kvm [1]: vgic interrupt IRQ<n>
# ... kvm [1]: Hyp mode initialized successfully
ls -l /dev/kvm
virsh uri                          # qemu:///system
virsh capabilities | grep -A2 "domain type='kvm'"
```

## Smoke test

The kernel `Image` boots as a guest too. Any arm64 initramfs works as the
guest rootfs, for example the one already shipped for the Jailhouse Linux
inmate (`../jailhouse/install/root/non_rootcell/linux/rootfs.cpio.gz`).

Directly with QEMU:

```sh
qemu-system-aarch64 -M virt,gic-version=2 -enable-kvm -cpu host -m 256 -nographic \
  -kernel /root/guest/Image -initrd /root/guest/rootfs.cpio.gz -append "console=ttyAMA0"
```

Through libvirt, as backend_kvm does:

```xml
<domain type='kvm'>
  <name>smoke</name>
  <memory unit='MiB'>256</memory>
  <vcpu>1</vcpu>
  <os>
    <type arch='aarch64' machine='virt'>hvm</type>
    <kernel>/root/guest/Image</kernel>
    <initrd>/root/guest/rootfs.cpio.gz</initrd>
    <cmdline>console=ttyAMA0</cmdline>
  </os>
  <features><gic version='2'/></features>
  <cpu mode='host-passthrough'/>
  <!-- like backend_kvm: run QEMU as root, otherwise the default 'qemu' user
       cannot read the kernel/initrd under /root -->
  <seclabel type='static' model='dac' relabel='no'>
    <label>root:root</label>
  </seclabel>
  <devices>
    <emulator>/usr/bin/qemu-system-aarch64</emulator>
    <console type='pty'><target type='serial'/></console>
  </devices>
</domain>
```

```sh
virsh create smoke.xml && virsh console smoke
```

## Platform constraints (relevant for backend_kvm on aarch64)

- **GICv2 only.** The ZynqMP has a GIC-400, so guests must use
  `<gic version='2'/>` (or `gic-version=2`); KVM cannot emulate a GICv3 on a
  GICv2 host. Maximum 8 vCPUs per guest, no ITS.
- **nVHE.** The Cortex-A53 is ARMv8.0 without VHE, so every VM exit is a full
  EL1/EL2 world switch.
- **Guest console is PL011.** On the QEMU `virt` machine the serial console is
  `ttyAMA0` and the libvirt serial target is `system-serial`, not
  `isa-serial`/`ttyS0` as on x86.
- **GIC CPU interface aliasing.** On the ZynqMP the 4K GIC CPU-interface pages
  repeat every 64K. KVM maps the GICV region directly into the guest, so a
  guest that uses `GICC_DIR` (EOImode 1) would hit an alias. Linux guests at
  EL1 do not use it; check before running other guest OSes.
