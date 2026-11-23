# Kria KR260 + KVM Environment Setup

`kr260-kvm` turns the KR260 (the Kria K26 SOM on the KR carrier card) into a
KVM host for the runPHI `backend_kvm`, which drives guests through `virsh` ->
`libvirtd` -> `qemu-system-aarch64`. It is kria-kvm (the KV260's) moved to the
KR260 and to the newest components: linux-xlnx 6.18 LTS, as kria-xen.

| Component | Built | Notes |
|---|---|---|
| Firmware (FSBL, PMUFW, ATF, U-Boot) | no | The BOOT.BIN in QSPI, see below |
| Linux (`xlnx_rebase_v6.18_LTS`) | yes | `kvm_kr260_kernel_defconfig`, PREEMPT_RT |
| Buildroot 2026.08.1 | yes | `kvm_kr260_buildroot_defconfig`, with the patches below |
| Jailhouse | no | KVM owns EL2, `jailhouse.ko` cannot load next to it |

The board: 192.168.100.53, `ssh root@192.168.100.53` (key login, the keys of
`install/root/.ssh/authorized_keys`, which stays local to each clone). Its
console is the USB-UART of the carrier (FT4232, interface 1, 115200), which
U-Boot and Linux (`ttyPS1`) share.

## Firmware

The Kria boots BOOT.BIN from QSPI. This KR260's QSPI holds Xilinx's 2022.1
Kria SOM firmware (`U-Boot 2022.01-g14ce5558 ... som_qspi_generation-12`),
which enters Linux at EL2, all that KVM needs:

```sh
dmesg | grep 'started at EL2'
# CPU: All CPU(s) started at EL2
```

Its U-Boot looks for boot scripts (`boot.scr.uimg`, `boot.scr`) on USB
storage only when the carrier is a KR (`card1_name` SCK-KR-G): its
`boot_targets` are `usb0 usb1 usb2 usb3 pxe dhcp`. On the KR260 the microSD
card is behind a USB bridge, on the carrier's USB hub, so U-Boot sees it as
`usb 0` and Linux as a USB disk (`/dev/sdX`), not as an MMC device as on the
KV260.

## The network port

Of the four RJ45 jacks, two are wired to the processing system and two to the
FPGA:

| Jack | Controller | Used |
|---|---|---|
| J10A, J10B | PL GEM3, GEM2 | no: they need an FPGA design |
| J10C | PS GEM1 (`ethernet@ff0c0000`, RGMII) | no |
| **J10D** | PS GEM0 (`ethernet@ff0b0000`, SGMII) | **yes** |

The cable goes in **J10D**: GEM0 is U-Boot's default interface (`ethact`), so
the boot scripts need no interface setting. In Linux GEM0 is **`eth1`**: its PHY
is on the MDIO bus of GEM1, so GEM0's probe waits for GEM1, which registers
first and gets `eth0` (macb does not name the interfaces after the `ethernet0`/
`ethernet1` aliases of the DT). The order is fixed by that dependency, so the
names do not change between boots; `/etc/network/interfaces` and the `ip=`
argument of `boot_tftp.cmd` configure `eth1`, and `eth0` (J10C) stays down.

## What the configuration contains

### Kernel (`custom_build/linux/arch/arm64/configs/kvm_kr260_kernel_defconfig`)

kria-xen's `xen_kria_kernel_defconfig` (xilinx_defconfig plus PREEMPT_RT,
NO_HZ_FULL, HZ_1000, Docker 28 on cgroup v2, LVM and the CPU isolation options)
without Xen, plus what kria-kvm has for KVM:

- `VIRTUALIZATION`, `KVM`, `VHOST_NET`, `VHOST_VSOCK`, `VSOCKETS`, `MACVTAP`;
- the virtio (PCI and MMIO: blk, net, console, balloon, rng), `PCI_HOST_GENERIC`
  and PL031 drivers, so that the same Image boots as a QEMU `virt` guest;
- nftables for the host's packet filtering (`NF_TABLES_IPV4/IPV6/BRIDGE`, the
  fib and reject expressions; `xilinx_defconfig` already has the rest).

The KR260 needs nothing special: the USB5744 hubs of the carrier
(`USB_ONBOARD_DEV_USB5744`), USB mass storage, the GEMs (`MACB`, DP83867 PHYs)
and the PS-GTR lanes (`PHY_XILINX_ZYNQMP`) are all in xilinx_defconfig.

Patches (`custom_build/linux/patch/`, see its README):

- `preempt_rt`: 6.18.57-rt9 against linux-xlnx 6.18.40, as kria-xen's;
- `cma_default_heap`: mainline's c33efdfcfa6f, as kria-xen's (a guest too small
  for the default 256 MB CMA area crashes at boot without it);
- `kvm_stage2_free_flush`: invalidate all TLBs when a VM's stage 2 is freed, in
  nVHE mode; on the Cortex-A53 a dead guest's TLB entries slow down the host's
  broadcast TLB invalidations, also on the isolated CPUs, until the next VMID
  rollover. The 6.18 form of kria-kvm's patch (the version sent as an RFC).

**No legacy iptables.** In 6.18 `NETFILTER_XTABLES_LEGACY` (and with it
`IP_NF_IPTABLES_LEGACY`, the `ebtables` tables) depends on `!PREEMPT_RT`. The
rootfs therefore uses iptables with the nftables backend (`iptables-nft`), as
kria-xen; Docker and libvirt's network driver work with it. The legacy
`ebtables` that libvirt's QEMU driver pulls in cannot work (libvirt only needs
it for nwfilter).

### Rootfs (`custom_build/buildroot/configs/kvm_kr260_buildroot_defconfig`)

kria-kvm's, with the kernel headers of 6.18, the hostname `kr260`, its own
overlay and `iptables` with `IPTABLES_NFTABLES` (+ `_DEFAULT`) and `kmod`
(see above). The same patches: `gcc_enabled` (gcc on the target),
`libvirt_cgroup_v2`, `libvirt_12` (libvirt 12.9.0).

### Boot sources

- `system_kvm.dts`: linux-xlnx 6.18's own DT of the KR260,
  `zynqmp-smk-k26-revA.dts` with the `zynqmp-sck-kr-g-revB.dtso` carrier overlay
  as the kernel builds it (`zynqmp-smk-k26-revA-sck-kr-g-revB.dtb`), decompiled.
  The GIC-400 node lists GICD/GICC/GICH/GICV and the maintenance interrupt
  (PPI 9) that the KVM vGICv2 needs. To regenerate it from a configured tree:
  `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- xilinx/zynqmp-smk-k26-revA-sck-kr-g-revB.dtb`,
  then `dtc -I dtb -O dts`.
- `boot_tftp.cmd` (default): kernel and DTB from `tftpboot/kr260-kvm/` on
  192.168.100.45, NFS root from `output/rootfs/kr260`, SD fallback.
- `boot_sd.cmd`: the same kernel, DTB and rootfs, entirely from the SD card.
  The root is the card's second partition by its PARTUUID (`part uuid`): the
  name of the USB disk in Linux depends on what else is plugged in.

### Board setup (`install/` overlay)

kria-kvm's overlay, with:

- `etc/network/interfaces`: eth1 (J10D) static, 192.168.100.53/24, gateway
  192.168.100.254, the only address (no DHCP client); `etc/resolv.conf` the
  gateway.
- `etc/fstab` and `etc/init.d/S28mnt-sd`: the SD card's ext4 partition (label
  `kr260root`) on `/mnt/sd`, where Docker (`etc/docker/daemon.json`,
  `/mnt/sd/runphi/docker`) and the LVM volume group of backend_kvm
  (`etc/init.d/S29lvm-loop`, `/mnt/sd/runphi/lvm.img`) live, because an NFS
  root cannot hold them. The card is a USB disk that may appear after
  `mount -a`: fstab marks it `noauto` and S28mnt-sd waits for it (up to 30 s).
- `root/boot_mode.sh`: kria-kvm's, for the KR260: it finds the FAT partition by
  its label (`KR260BOOT`) and asks the server for `kr260.scr`.
- `root/.profile`: kria-kvm's, but the prompt's address is the first global
  IPv4 address of any interface (kria-kvm's looks at eth0 only).
- `usr/local/sbin/runphi`: runPHI with the KVM backend (see below);
  `usr/local/sbin/runc_vanilla` -> `/usr/bin/runc`.

## Build

```sh
./scripts/build_environment.sh -t kr260 -b kvm
./scripts/compile/dts_compile.sh -t kr260 -b kvm
./scripts/compile/bootscr_compile.sh -t kr260 -b kvm
./scripts/compile/bootscr_compile.sh -t kr260 -b kvm -c sd -o boot_sd.scr
./scripts/remote/switch_backend.sh -t kr260 -g environment/kr260/kvm/output/boot/boot_tftp.scr
```

The last one is the SD card's network boot script (`scripts/remote/boot_select.cmd`
for the KR260). For the TFTP server, copy `Image`, `system.dtb` and `boot.scr`
from `output/boot/` to `tftpboot/kr260-kvm/`.

## SD card

The card holds the same kernel and a copy of the rootfs, so the board boots
without the server, and the board's local disk (`/mnt/sd/runphi`):

| Partition | Contents |
|---|---|
| 1, FAT32, `KR260BOOT` | `Image`, `system.dtb`, `boot_sd.scr`, `boot_tftp.scr` (the network boot: the environment that the server selects), `boot.scr` (a copy of one of the two), `isolargs.txt` (optional, see kria-kvm's SETUP.md) |
| 2, ext4, `kr260root` | the rootfs, and `/runphi` (Docker's storage, `lvm.img`) |

`scripts/remote/prepare_sd_card.sh` writes it from a PC, without root (write
access to the card is enough, e.g. the `disk` group), into the two partitions
that the card already has (1 GB FAT and the rest, see the script's header):

```sh
./scripts/remote/prepare_sd_card.sh -t kr260 -b kvm -d /dev/sdX      # boot.scr = boot_tftp.scr
./scripts/remote/prepare_sd_card.sh -t kr260 -b kvm -d /dev/sdX -m sd
```

It reads every file of the FAT partition back and checks the ext4 one with
`e2fsck`. The card's rootfs has no ssh host keys: the first boot from it
creates them. Copy them into the NFS root on the server
(`output/rootfs/kr260/etc/dropbear/`) so that the board has the same keys in
both boot modes (`scripts/common/host_keys.sh` then hands them to the other
environments of the KR260).

`boot_mode.sh` on the board switches between the two boot modes and sets the
CPU isolation, as on the KV260 (see kria-kvm's SETUP.md):

```sh
/root/boot_mode.sh            # where / comes from, next boot mode, isolation
/root/boot_mode.sh sd -r      # boot from the SD card, reboot now
/root/boot_mode.sh tftp -r    # boot what the server selects (falls back to the SD card)
```

With `boot_tftp.scr`, a board that cannot reach 192.168.100.45 (e.g. cabled to a
PC) waits for the TFTP timeouts, then boots `boot_sd.scr`.

## TFTP+NFS on the server

As for the KV260, on 192.168.100.45 in its clone of this repository:

```sh
sudo ./scripts/remote/setup_nfs_rootfs.sh -t kr260 -b kvm
# /etc/exports: /root/runphi/environment_builder/environment/kr260/kvm/output/rootfs/kr260 *(rw,sync,no_root_squash,no_subtree_check)
sudo exportfs -ra
./scripts/remote/switch_backend.sh -t kr260 -b kvm      # tftpboot/kr260.scr -> kr260-kvm/boot.scr
```

## Verify the KVM host

As on the KV260 (kria-kvm's SETUP.md has the smoke test with QEMU and libvirt):

```sh
uname -v                           # ... SMP PREEMPT_RT ...
dmesg | grep -i kvm                # ... kvm [1]: Hyp mode initialized successfully
ls -l /dev/kvm
virsh capabilities | grep -A2 "domain type='kvm'"
```

## runPHI (backend_kvm)

As on the KV260: kria-kvm's [RUNPHI.md](../../kria/kvm/RUNPHI.md) is the guide
(the board's address is 192.168.100.53). The binary in the overlay is built
from runphi_manager with the Buildroot toolchain of this environment (glibc
2.44); in `runphi_manager/rust_runphi`:

```sh
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=<environment_builder>/environment/kr260/kvm/build/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc ./compile_rust.sh kvm
cp target/aarch64-unknown-linux-gnu/release/runphi <environment_builder>/environment/kr260/kvm/install/usr/local/sbin/
```

### Tests

Run on the board on 2026-11-23, booted from the SD card (runphi_manager
7dee20e): the tests of kria-kvm's RUNPHI.md, section 5, with the four
`runphi-kvm-guest` images rebuilt on the board as RUNPHI.md describes (this
environment's kernel, the Jailhouse Linux inmate's initramfs) and the
`test-vg` volume group created once as in kria-kvm's SETUP.md:

| Test | Result |
|---|---|
| 5.1 plain guest | boots (256 MB, 1 CPU), nothing left after `docker rm -f` |
| 5.2 pinned vCPUs + net | vCPUs on CPUs 2 and 3, SCHED_FIFO 99, emulator threads on 0-1, container cgroup, lease 10.0.2.15 |
| 5.3 root on LVM | `lv_<id>` 168 MB, guest root `vda` ext4, volume removed |
| 5.4 IRQ steering | 33 interrupts moved to 0-1 while running, all restored |
| 5.5 an error | "cannot pin vCPU 0 ... to CPU 2", nothing left behind |
| 5.6 ordinary container | forwarded to runc (a local busybox image: no Internet on the bench) |
| 5.7 `runphi state` | the container's state |

## Platform constraints

Those of the KV260 (kria-kvm's SETUP.md): GICv2 (at most 8 vCPUs per guest,
no ITS), nVHE, PL011 guest console, GIC CPU interface aliasing.
