# Kria KV260 + Xen Environment Setup

`kria-xen` turns the KV260 into a Xen host for the runPHI `backend_xen`, which
runs containers as Xen domains (`xl create`). It combines the Xen side of
[qemu-xen](../../qemu/xen/SETUP.md) (Buildroot 2026.08.1, Xen 4.22.0) with
the board setup of [kria-kvm](../kvm/SETUP.md): the same board at the same
address, TFTP+NFS boot from 192.168.100.45, Docker and LVM on the SD card.

| Component | Built | Notes |
|---|---|---|
| Firmware (FSBL, PMUFW, ATF, U-Boot) | no | the BOOT.BIN in QSPI, as for kria-kvm: its U-Boot starts Xen at EL2 |
| Xen 4.22.0 | yes, by Buildroot | hypervisor (`output/rootfs/xen`, copied to `tftpboot/kria-xen/`) and tools of the same version: Buildroot's `xen` package with the `xen_4_22` patches (as in qemu-xen), which include Xen's stable-4.22 SMCCC fix, without which Dom0 has no clocks (see [Rootfs](#rootfs-custom_buildbuildrootconfigsxen_kria_buildroot_defconfig)) |
| Linux (`xlnx_rebase_v6.18_LTS`, 6.18.40) | yes | `xen_kria_kernel_defconfig`: Dom0 and the guests' kernel, PREEMPT_RT; patches `preempt_rt` (6.18.57-rt9), `cma_default_heap` (a mainline fix) |
| Buildroot 2026.08.1 | yes | `xen_kria_buildroot_defconfig`: qemu-xen's rootfs without the disk image, iptables over nftables |
| runPHI (`backend_xen`) | from runphi_manager | in the overlay, built with this environment's Buildroot toolchain, see [runPHI](#runphi-backend_xen) |
| Jailhouse | no | Xen owns EL2 |

## Firmware

The Kria boots BOOT.BIN from QSPI (see [../jailhouse/SETUP.md](../jailhouse/SETUP.md)),
whose U-Boot enters the next stage at EL2, which Xen needs as KVM does. The
SD card's `boot.scr` (U-Boot's distro boot) selects what U-Boot starts:
kria-kvm from the SD card, or the environment that the TFTP server selects
(see [Boot mode](#boot-mode-and-the-sd-card)).

## What the configuration contains

### Kernel (`custom_build/linux/arch/arm64/configs/xen_kria_kernel_defconfig`)

linux-xlnx 6.18 LTS, the newest Xilinx LTS (release `xilinx-v2026.1`;
kria-kvm and the Jailhouse environments are on 6.1). The defconfig is
`xilinx_defconfig` of that tree plus (`savedefconfig` of the result):

- `PREEMPT_RT`, in mainline since 6.12, and the `preempt_rt` patch, the
  6.18.57-rt9 set regenerated against 6.18.40. On arm64 the set only adds a
  printk fix (the console kthreads start after the arch initcalls),
  `/sys/kernel/realtime` and the `-rt9` version suffix: the rest is for i915,
  32-bit ARM, PowerPC and the 8250 UART, none of which the KV260 uses (patch
  header). PREEMPT_RT drops `TRANSPARENT_HUGEPAGE` and `LEDS_TRIGGER_CPU` of
  `xilinx_defconfig`, which depend on `!PREEMPT_RT`.
- `HZ_1000`, `NO_HZ_FULL`, `NR_CPUS=4`, as kria-kvm
- Xen: `XEN` (Dom0 support with it), the backends (`XEN_BLKDEV_BACKEND`,
  `XEN_NETDEV_BACKEND`, `XEN_GNTDEV`, `XEN_GRANT_DEV_ALLOC`, PV calls) and the
  frontends with their defaults (`xen-blkfront`, `xen-netfront`, `hvc0`), so
  that the same `Image` is Dom0 and the guests' kernel
- Docker 28 on cgroup v2: namespaces and cgroup controllers, `BPF_SYSCALL`
  and `CGROUP_BPF`, `OVERLAY_FS`, `VETH`, `BRIDGE_NETFILTER`, IPVS, VXLAN
- Docker's iptables rules through nftables (`NF_TABLES`, `NFT_COMPAT`,
  `NFT_NAT`, `NFT_MASQ`, the `xt_` matches and targets Docker uses): on 6.18
  the legacy tables (`NETFILTER_XTABLES_LEGACY`, `IP_NF_NAT`, `IP_NF_RAW`)
  depend on `!PREEMPT_RT`, so the rootfs uses `iptables-nft`
- `"disk_type": "lvm"` guests: device-mapper (`DM_SNAPSHOT`,
  `DM_THIN_PROVISIONING`), `BLK_DEV_LOOP`, `EXT4_FS`
- as kria-kvm: PL loading (`FPGA_BRIDGE`, `FPGA_REGION`, `OF_FPGA_REGION`,
  `XILINX_PR_DECOUPLER`), the R5 remoteproc (`XLNX_R5_REMOTEPROC`, the 6.18
  name of `ZYNQMP_R5_REMOTEPROC`), UIO, `KALLSYMS_ALL`, `KPROBES`, `MTD_OOPS`

and the `cma_default_heap` patch, mainline's c33efdfcfa6f "dma: contiguous:
Check return value of dma_contiguous_reserve_area()": linux-xlnx 6.18.40 has
the commit that it fixes but not the fix. Without it, a guest with less memory
than the default CMA area (256 MB, `CMA_SIZE_MBYTES` of `xilinx_defconfig`),
which runPHI's 256 MB test domains are, crashes at boot in `dma_heap_add()`.

The environment passes `-s` to the defconfig update scripts: if Kconfig drops
any option of the defconfig, the build stops.

### Rootfs (`custom_build/buildroot/configs/xen_kria_buildroot_defconfig`)

qemu-xen's `xen_qemu_buildroot_defconfig` (Xen hypervisor and tools, Docker
28.5.2, LVM2, e2fsprogs, python3, ...) with:

- the hostname `kv260-xen`, Dom0's console `hvc0` for the login prompt
- the `kria/xen/install` overlay, no ext4 disk image and no QEMU post-image
  script
- 6.18 kernel headers
- `iptables-nft` as `iptables` (`BR2_PACKAGE_IPTABLES_NFTABLES_DEFAULT`), see
  above; no `ebtables`, whose legacy tables the kernel cannot have either

Patches (`custom_build/buildroot/patch/`, the same as qemu-xen's):
`gcc_enabled` (gcc on the target) and `xen_4_22`: Xen 4.22.0 instead of
2026.08.1's 4.21.1 (Buildroot master's commit a962be2e), and Xen's
stable-4.22 commit 781b60f95140 "xen/arm: Fix evaluation of parameters for
SMCCC calls" (from 95302b39430c, not in a release yet). Xen 4.22.0 assigns
each argument of an SMC to its register as it evaluates them, so an argument
that calls a function clobbers the ones already loaded. The ZynqMP firmware
mediator forwards Dom0's firmware (EEMI) calls with arguments read through
`get_user_reg()`: without the fix every one of them reaches TF-A with garbage
in x0 and gets `SMC_UNK`, the `zynqmp_firmware` driver does not probe
(`-EINVAL`), and Dom0 has no clocks, so no Ethernet (no NFS root), SD card,
I2C, DMA, ... The same kernel without Xen probes it.

### Boot sources

- `system_xen.dts`: kria-kvm's `system_kvm.dts`. Xen needs nothing else from
  it: the GIC-400 node lists GICH/GICV and the maintenance interrupt, the
  aliases name the UARTs, and the SMMU is disabled, so Dom0 is mapped 1:1 and
  keeps every device. `boot_tftp.cmd` adds the rest to `/chosen`.
- `boot_tftp.cmd`: Xen, Dom0's kernel and the DTB from `tftpboot/kria-xen/`
  on 192.168.100.45, Dom0's root over NFS from `output/rootfs/kria`; if a TFTP
  fetch fails, kria-kvm from the SD card. Xen's command line:

  ```
  console=dtuart dtuart=serial1 dom0_mem=1024M dom0_max_vcpus=1 dom0_vcpus_pin vwfi=native
  ```

  Xen's console is `serial1` (`serial@ff010000`, Linux's `ttyPS1`, the USB
  serial port of the carrier card) and Dom0's is `hvc0`. Dom0 has 1 GB and
  one vCPU pinned to CPU 0, so the domains get CPUs 1-3 and about 2.9 GB.
  `vwfi=native`: a vCPU's WFI does not trap to Xen, as on the ZCU104.

### Board setup (`install/` overlay)

As kria-kvm's (see its SETUP.md), except:

- `etc/docker/daemon.json`: Docker's store in `/mnt/sd/runphi-xen/docker`
  (overlay2 on the SD card), next to kria-kvm's `/mnt/sd/runphi/docker`: each
  system has its own images and containers
- `etc/init.d/S29lvm-loop`: the `test-vg` volume group in
  `/mnt/sd/runphi-xen/lvm.img`, which the first boot creates (6 GB, sparse),
  as in qemu-xen
- `root/boot_mode.sh`: the same script as kria-kvm's (see
  [Boot mode](#boot-mode-and-the-sd-card))
- `root/guest/`: `make_test_images.sh` and the guest initramfs of qemu-xen
  (the images move the guest's login prompt from `ttyAMA0` to `hvc0`)
- runPHI: `usr/local/sbin/runphi` (backend_xen), `usr/share/runPHI/caronte`
  (the process that keeps a domain's container alive, from runphi_manager's
  `target/runPHI_cell_configs/`), `usr/local/sbin/runc_vanilla`

## Build

```sh
./scripts/build_environment.sh -t kria -b xen
./scripts/compile/dts_compile.sh -t kria -b xen
./scripts/compile/bootscr_compile.sh -t kria -b xen
```

`linux_compile.sh` copies `Image` to `tftpboot/kria-xen/`; copy the rest by
hand:

```sh
cp environment/kria/xen/output/rootfs/xen environment/kria/xen/output/boot/system.dtb environment/kria/xen/output/boot/boot.scr tftpboot/kria-xen/
```

Then, on the server, populate the NFS root and export it. `setup_nfs_rootfs.sh`
also gives it the board's ssh host keys, those of kria-kvm's NFS root, so ssh
knows the board in both environments (`scripts/common/host_keys.sh`):

```sh
sudo ./scripts/remote/setup_nfs_rootfs.sh -t kria -b xen
echo '/root/runphi/environment_builder/environment/kria/xen/output/rootfs/kria *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
exportfs -r
```

## Boot mode and the SD card

kria-xen boots only over TFTP+NFS; the SD card holds kria-kvm's system, which
is also the fallback. The SD card's network boot script (`boot_tftp.scr`,
environment_builder's `scripts/remote/boot_select.cmd`) runs `kria.scr` from
the server, which `scripts/remote/switch_backend.sh` points at the boot
script of one environment of the Kria. On the server (as root, in
`/root/runphi/environment_builder`):

```sh
./scripts/remote/switch_backend.sh -t kria -b xen -r  # kria-xen, reboot the board now
./scripts/remote/switch_backend.sh -t kria -b kvm -r  # back to kria-kvm
./scripts/remote/switch_backend.sh -t kria            # the environments and the selected one
```

The selection lives on the server, so it also works when the running system
does not answer: select, then power-cycle. On the board, `/root/boot_mode.sh`
(the same script as kria-kvm's) chooses between that network boot (`tftp`)
and kria-kvm on the SD card (`sd`), and shows the server's selection:

```sh
/root/boot_mode.sh              # running from: NFS, kria-xen (tftp mode) ... next boot: tftp: kria-xen
/root/boot_mode.sh sd -r        # kria-kvm from the SD card
```

`iso` only affects kria-kvm's boots. See kria-kvm's
[SETUP.md](../kvm/SETUP.md#switching-environments-kria-kvm-kria-xen) for how
the selection script is put on the SD card.

## Verify the Xen host

On the board:

```sh
xl info | grep -E 'xen_version|nr_cpus|total_memory|free_memory|xen_commandline'
xl list                          # Domain-0, 1024 MB, 1 vCPU
xl vcpu-list                     # Domain-0's vCPU 0 on CPU 0, affinity 0
uname -v                         # ... SMP PREEMPT_RT ...
cat /sys/kernel/realtime         # 1
vgs test-vg
```

## runPHI (backend_xen)

runPHI runs a container as a Xen domain when its image has a
`/boot/config.json` (see `doc/README.md` in runphi_manager), and hands any
other container to runc. The binary in the overlay is built with this
environment's Buildroot toolchain, so that it uses the board's glibc (2.44).
In `runphi_manager/rust_runphi`:

```sh
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=<environment_builder>/environment/kria/xen/build/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc ./compile_rust.sh xen
cp target/aarch64-unknown-linux-gnu/release/runphi <environment_builder>/environment/kria/xen/install/usr/local/sbin/
```

## Test images and tests

`/root/guest/make_test_images.sh` builds `runphi-xen-guest:initramfs` and
`runphi-xen-guest:lvm` from `/root/guest/Image` (this environment's kernel:
`./scripts/remote/load_components_to_remote.sh -t kria -b xen -g`) and
`/root/guest/rootfs.cpio.gz`; the tests are qemu-xen's (see its
SETUP.md). A guest's console is `xl console <domain>`; to keep the guests'
consoles in files, start `xenconsoled` again with `--log=guest`
(`/var/log/xen/console/guest-<domain>.log`).

Tested on the KV260 (runphi_manager `04473e0`):

- the board boots kria-xen over TFTP+NFS in about 30 seconds: Xen 4.22.0
  (`Platform: Xilinx ZynqMP`, 4 CPUs, credit2), Dom0 6.18.40-rt9 PREEMPT_RT
  with one vCPU pinned to CPU 0 and 1024 MB, 2790 MB free for the domains;
  eth0 has the board's one static address, no DHCP client runs
- Docker 28.5.2 on cgroup v2 with the `runphi` runtime; a plain container
  reaches the Internet through Docker's NAT rules (iptables-nft)
- `runphi-xen-guest:initramfs` boots to its login prompt on `hvc0`, on CPU
  3; three guests run at once on CPUs 3, 2 and 1, and a fourth is refused
  (`not enough free CPUs: need 1, have 0 of 4`), as a guest larger than the
  free memory (`not enough free memory: need 3000 MB, have 2789 MB`)
- `runphi-xen-guest:lvm` gets a 168 MB volume of `test-vg`, mounts it as
  `/dev/xvda` and boots to its login prompt; the volume is removed with the
  container
- nothing is left behind (containers, domains, `/run/runPHI`, volumes)

## Platform constraints

- **GICv2.** The domains get the host's GIC-400 (GICv2): at most 8 vCPUs.
- **Dom0 1:1.** The SMMU is disabled in the DTB, so Xen maps Dom0's memory
  1:1 onto RAM and cannot give devices to the domains.
- **Guest network.** runPHI's Xen backend gives the guests no network.
- **No USB in Dom0.** The USB controller's driver (`dwc3-xilinx`) needs the
  firmware's MMIO calls (`PM_MMIO_READ`/`PM_MMIO_WRITE`), which Xen's
  mediator never forwards: its probe fails with `-EACCES`. Xen does not
  forward `PM_FEATURE_CHECK` either; Linux then makes its firmware calls
  without checking them first, as with older firmware.
- **No timer device.** `/dev/arm_timer`, which backend_xen reads for its
  optional boot-time instrumentation, is a companion kernel module that this
  environment does not build: runPHI logs a warning and works without it.
