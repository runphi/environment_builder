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
- no RT group scheduling (`CONFIG_RT_GROUP_SCHED`, which the kube base has):
  backend_kvm gives pinned vCPUs `SCHED_FIFO` priority 99, and with RT group
  scheduling every new cgroup (libvirt's `machine`, the container's) starts
  with a real-time budget of 0, so libvirt fails with `Cannot set scheduler
  parameters ...: Operation not permitted`
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
- `ca-certificates`: the Mozilla CA bundle in `/etc/ssl/certs`, without which
  `docker pull` fails with "x509: certificate signed by unknown authority"

### Boot sources

- `system_kvm.dts`: `system_omnv.dts` without the `jailhouse@7e000000`
  reservation. The GIC-400 node already lists GICD/GICC/GICH/GICV and the
  maintenance interrupt (PPI 9) that the KVM vGICv2 needs.
- `boot_tftp.cmd` (default): kernel and DTB from `tftpboot/kria-kvm/` on
  192.168.100.45, NFS root from `output/rootfs/kria`, SD fallback.
- `boot_sd.cmd`: the same kernel, DTB and rootfs, entirely from the SD card
  (see [SD card](#sd-card-standalone-boot-and-boot-mode)).

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
- `etc/network/interfaces`: eth0 statically on 192.168.100.46 when booted from
  the SD card (with an NFS root, `nfs_check` leaves eth0 to the kernel's `ip=`).
  The gateway also serves DHCP, so `dhcpcd` adds a dynamic second address and
  the DNS server in both modes.
- `root/boot_mode.sh`: switches between SD and TFTP+NFS boot, and sets the
  CPU isolation of the next boot (see below).
- runPHI with the KVM backend (see [runPHI](#runphi-backend_kvm)):
  `usr/local/sbin/runphi`, `etc/docker/daemon.json` registers it as the
  `runphi` Docker runtime (`runc` stays the default), and
  `usr/local/sbin/runc_vanilla` (a link to `/usr/bin/runc`) is where runPHI
  hands over containers that are not partitioned ones.
- `root/adjust_time.sh`: sets the clock, which starts at 1970 on every boot
  (no RTC battery, no NTP client): from the `Date:` header of a plain-HTTP
  request (`curl http://1.1.1.1` etc.), or asks for it. Same script as zcu104b.

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
./scripts/compile/bootscr_compile.sh -t kria -b kvm -c tftp -o boot_tftp.scr
./scripts/compile/bootscr_compile.sh -t kria -b kvm -c sd -o boot_sd.scr
```

`linux_compile.sh` copies `Image` to `tftpboot/kria-kvm/`, but `dts_compile.sh`
and `bootscr_compile.sh` only write to `output/boot/`, so copy the rest by hand:

```sh
cp environment/kria/kvm/output/boot/system.dtb environment/kria/kvm/output/boot/boot.scr tftpboot/kria-kvm/
```

`boot.scr` (= `boot_tftp.scr`) is what U-Boot runs when started by hand over
TFTP. On the SD card, `boot_sd.scr` and `boot_tftp.scr` sit next to `boot.scr`
and `boot_mode.sh` picks one of them.

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

## SD card: standalone boot and boot mode

The SD card holds the same kernel and a copy of the rootfs, so the board boots
the same system with or without the TFTP/NFS server:

| Partition | Contents |
|---|---|
| `mmcblk1p1` (FAT) | `Image`, `system.dtb` (as in `tftpboot/kria-kvm/`), `boot_sd.scr`, `boot_tftp.scr`, `boot.scr` (a copy of one of the two), `isolargs.txt` (optional, see below), `BOOT.BIN` (not used: the Kria boots from QSPI), `old/` (the previous SD system's boot files) |
| `mmcblk1p2` (ext4) | a copy of the NFS rootfs, `runphi/` (Docker store and LVM file, shared by both modes), `old-sd-rootfs/` (the previous SD system) |

`/root/boot_mode.sh` selects the next boot, from either mode:

```sh
/root/boot_mode.sh              # where / comes from, isolated CPUs, next boot mode and isolation
/root/boot_mode.sh sd -r        # boot from the SD card, reboot now
/root/boot_mode.sh tftp -r      # boot over TFTP + NFS, reboot now
/root/boot_mode.sh iso 3        # isolate CPU 3 from the next boot on
/root/boot_mode.sh iso off      # no isolation
/root/boot_mode.sh sd iso 3 -r  # both at once
```

### CPU isolation

Both boot scripts add `isolargs` to the kernel command line, and read it from
`isolargs.txt` on the FAT partition (one line, `isolargs=...`, imported with
U-Boot's `env import -t`), so the isolation is the same in both boot modes and
changes without recompiling anything. Without the file the kernel gets no
isolation arguments; a U-Boot that could not import it would boot the same
way. `boot_mode.sh iso <cpus>` writes

```
isolcpus=managed_irq,domain,nohz,<cpus> nohz_full=<cpus> rcu_nocbs=<cpus> irqaffinity=<the other CPUs>
```

which keeps the scheduler's load balancing, the tick, RCU callbacks and the
device interrupts off `<cpus>` (e.g. `iso 3`: `irqaffinity=0,1,2`). Check
after the reboot with `/root/boot_mode.sh` or
`cat /sys/devices/system/cpu/isolated /sys/devices/system/cpu/nohz_full`.
Note that `isolcpus=domain` takes the CPUs out of load balancing: a task runs
there only when pinned to them (`vcpu_pinning`, `docker run --cpuset-cpus`).

When booted from the SD card, `/mnt/sd` is the root partition mounted a second
time, so `/mnt/sd/runphi` is the same Docker store and LVM file in both modes.

The two root filesystems are independent copies. To refresh the SD copy from
the NFS root, from a TFTP+NFS boot (stops Docker and the VG, which live on the
SD card):

```sh
/etc/init.d/S60dockerd stop; /etc/init.d/S29lvm-loop stop
mkdir -p /tmp/nfsroot && mount -o bind / /tmp/nfsroot
cd /mnt/sd && rm -rf bin dev etc lib lib64 linuxrc media mnt opt proc root run sbin sys tmp usr var
tar -C /tmp/nfsroot --numeric-owner -cf - . | tar -C /mnt/sd --numeric-owner -xpf -
umount /tmp/nfsroot; /etc/init.d/S29lvm-loop start; /etc/init.d/S60dockerd start
```

(The bind mount shows the NFS root without `/proc`, `/sys`, `/dev`, `/tmp` and
`/mnt/sd` mounted on top.) After a kernel or DTB update, copy `Image` and
`system.dtb` to the FAT partition as well.

The previous SD system (a Buildroot rootfs with a 6.18 kernel) is saved on the
server in `/root/backups/kriakv260-sd-2026-10-02/` (`sd-p1-boot.tar`,
`sd-p2-rootfs.tar`, see the README there), and also kept on the card in
`old/` and `old-sd-rootfs/` until that space is needed.

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

## runPHI (backend_kvm)

runPHI runs a container as a KVM guest when its image has a
`/boot/config.json` (see `doc/backend_kvm_docs/` in runphi_manager), and hands
any other container to `runc`. [RUNPHI.md](RUNPHI.md) is the complete guide:
how runPHI drives the guests, every `/boot/config.json` field and `docker run`
option, and tests to run by hand. It is installed by the overlay; with the
files from the [smoke test](#smoke-test):

```sh
mkdir -p /tmp/img/boot && cd /tmp/img && cp /root/guest/Image /root/guest/rootfs.cpio.gz boot/
cat > boot/config.json <<EOF
{ "os_var": "linux", "inmate": "/boot/Image", "ramdisk": "/boot/rootfs.cpio.gz",
  "memory": 512, "vcpus": 2, "vcpu_pinning": [ {"vcpu": 0, "pcpu": 2}, {"vcpu": 1, "pcpu": 3} ],
  "net": "user" }
EOF
tar -c . | docker import --change 'CMD ["/bin/sh"]' - kvm-guest
docker run -d --name guest --runtime=runphi kvm-guest
virsh list; tail /var/log/libvirt/qemu/runphi-*-serial.log
docker rm -f guest
```

`/usr/share/runPHI/log.txt` is runPHI's log; `"disk_type": "lvm"` puts the
guest's root filesystem in a logical volume of `test-vg`.

The binary in the overlay is built from runphi_manager with the Buildroot
toolchain of this environment, so that it uses the board's glibc (2.37): a
binary linked with a newer host's `aarch64-linux-gnu-gcc` needs a newer glibc
and does not start. In `runphi_manager/rust_runphi`:

```sh
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=<environment_builder>/environment/kria/kvm/build/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc ./compile_rust.sh kvm
cp target/aarch64-unknown-linux-gnu/release/runphi <environment_builder>/environment/kria/kvm/install/usr/local/sbin/
```

## Platform constraints

- **GICv2.** The ZynqMP has a GIC-400, and KVM cannot emulate a GICv3 on a
  GICv2 host, so guests get a GICv2 (backend_kvm uses `<gic version='host'/>`,
  plain QEMU `gic-version=2`). Maximum 8 vCPUs per guest, no ITS.
- **nVHE.** The Cortex-A53 is ARMv8.0 without VHE, so every VM exit is a full
  EL1/EL2 world switch.
- **Guest console is PL011.** On the QEMU `virt` machine the serial console is
  `ttyAMA0` and the libvirt serial target is `system-serial`, not
  `isa-serial`/`ttyS0` as on x86 (backend_kvm picks them per architecture).
- **GIC CPU interface aliasing.** On the ZynqMP the 4K GIC CPU-interface pages
  repeat every 64K. KVM maps the GICV region directly into the guest, so a
  guest that uses `GICC_DIR` (EOImode 1) would hit an alias. Linux guests at
  EL1 do not use it; check before running other guest OSes.
