# Kria KR260 + Jailhouse (Omnivisor) Environment Setup

`kr260-jailhouse` turns the KR260 into a Jailhouse host for the runPHI
`backend_jailhouse`, which runs containers as Jailhouse cells on the
Cortex-A53 cores (APU) and, through the Omnivisor, on the Cortex-R5 cores
(RPU). It is [kria-jailhouse](../../kria/jailhouse/SETUP.md) (the KV260's:
linux-xlnx 6.1 LTS with the Jailhouse enabling patches and PREEMPT_RT,
Buildroot 2026.08.1, the Omnivisor fork of Jailhouse) with the board setup of
[kr260-kvm](../kvm/SETUP.md) and [kr260-xen](../xen/SETUP.md): the KR260 at
192.168.100.53, TFTP+NFS boot from 192.168.100.45, Docker and containerd on
the SD card, kr260-kvm on the SD card as the fallback.

| Component | Built | Notes |
|---|---|---|
| Firmware (FSBL, PMUFW, U-Boot) | no | the KR260's own QSPI firmware (Xilinx's 2022.1 Kria SOM firmware) |
| TF-A (Omnivisor fork, `6fca8a86e`) | yes | `bl31.elf`, put into the QSPI image, see [Firmware](#firmware) |
| Linux (`xlnx_rebase_v6.1_LTS`, 6.1.70) | yes | kria-jailhouse's: `jailhouse_kr260_isolcpu_kernel_defconfig`, PREEMPT_RT, patches `jailhouse_enable`, `omnivisor`, `preempt_rt`, `omnv_fpga_rproc` |
| Buildroot 2026.08.1 | yes | `jailhouse_kr260_buildroot_defconfig`: kria-jailhouse's with the hostname `kr260-jailhouse` and this overlay |
| Jailhouse (Omnivisor fork, `628a02d8`) | yes | kria-jailhouse's three fixes, the KR260 root cell and an interrupt routing fix, see [Jailhouse](#jailhouse) |
| runPHI (`backend_jailhouse`) | from runphi_manager | `install/root/runphi`, built with this environment's Buildroot toolchain |
| FPGA design | none | the Omnivisor has no DFX design for the KR260: no FPGA soft cores |
| KVM, Xen | no | Jailhouse owns EL2 |

Access as for kr260-kvm: `ssh root@192.168.100.53`; the carrier's USB-UART
(interface 1, 115200) is U-Boot's, Linux's (`ttyPS1`) and the hypervisor's
console.

## Firmware

The Kria boots BOOT.BIN from QSPI, in two copies, image A and image B, and an
Image Selector that boots one of them according to the A/B persistent register
(the Kria boot firmware's "A/B Boot Concept"). The Omnivisor needs its TF-A
fork, `DanieleOttaviano/arm-trusted-firmware` `6fca8a86e`: Xilinx's TF-A 2.8
with two SMCs (`0x8400ff04`, `0x8400ff05`) that read and write any register
that BL31 maps, which the hypervisor uses to program the XMPU and the QoS
registers, BL31's mappings widened to those registers, and its console moved to
UART1. Without it Jailhouse and the R5 cells run, but not the XMPU and QoS
features.

The KR260's QSPI holds Xilinx's 2022.1 Kria SOM firmware (FSBL, PMU firmware,
BL31 v2.6 `145c616`, U-Boot `2022.01-g14ce5558`). `output/boot/BOOT.BIN` is
that image with only its BL31 replaced by the fork's, everything else
byte-identical (also what kr260-kvm and kr260-xen boot with):

```sh
# on the board (any environment), read the running image (A here)
dd if=/dev/mtd6 of=/tmp/imageA.bin bs=64k   # "Image A (FSBL, PMU, ATF, U-Boot)" in /proc/mtd
# on the build machine
./scripts/compile/atf_compile.sh -t kr260 -b jailhouse     # output/boot/bl31.elf
./scripts/compile/zynqmp_bootbin.py info imageA.bin
./scripts/compile/zynqmp_bootbin.py replace imageA.bin bl31.elf environment/kr260/jailhouse/output/boot/bl31.elf -o environment/kr260/jailhouse/output/boot/BOOT.BIN
```

`zynqmp_bootbin.py replace` puts the new BL31 where the old one was (it fits),
rewrites only that partition's header and checks that the rest is unchanged.
The tracked `BOOT.BIN` is the result for the KR260's 2022.1 image A
(`XilinxSOM_BootFW_20220603`).

It is flashed from the board's Linux (python3, no `xmutil` needed) with
`scripts/remote/kria_bootfw_update.py`, which does what Xilinx's
`xmutil bootfw_update` does: it writes the image that is not running and
requests it for the next boot, marked not yet bootable; the Image Selector
boots it once, and falls back to the other image unless it is then marked
bootable:

```sh
scp -O scripts/remote/kria_bootfw_update.py environment/kr260/jailhouse/output/boot/BOOT.BIN root@192.168.100.53:/tmp/
# on the board
python3 /tmp/kria_bootfw_update.py -p              # A/B state, what each image holds
python3 /tmp/kria_bootfw_update.py -i /tmp/BOOT.BIN
# power-cycle (a reboot may restart the running image); the console shows
#   MultiBootOffset: 0x1F0 (image B) ... BL31: v2.8(release):6fca8a86e ... OMNIVISOR PATCH
python3 /tmp/kria_bootfw_update.py -v              # keep it: mark the running image bootable
```

The other image keeps Xilinx's firmware as the fallback. All the KR260's
environments boot with this BOOT.BIN (kr260-kvm and kr260-xen were tested on
it).

## What the configuration contains

### Kernel, rootfs

kria-jailhouse's (see its SETUP.md): the 6.1.70 kernel with the same patches
and defconfig, the same Buildroot rootfs. The KR260's carrier needs nothing
more: GEM0's SGMII link through the PS-GTR (`PHY_XILINX_ZYNQMP`), the USB
hubs and the SD card's USB bridge (`USB_USB5744`, `USB_USB2244` as modules,
behind the `PCA954x` I2C mux and the `slg7xl45106` reset GPIOs,
`GPIO_PCA9570`), `USB_STORAGE` are in the defconfig.

### Jailhouse

The fork's newest commit (`628a02d8`), with `config_omnv.h`, as
kria-jailhouse. Patches (`custom_build/jailhouse/patch/omnv/`, see its
README): kria-jailhouse's three (pyjailhouse, the KV260 Linux demo cell's
ivshmem links, the results of the root cell's firmware calls) and:

- `0004-configs-kr260-omnv-...`: the fork's KR260 root cell
  (`zynqmp-kr260-omnv.c`) is its KV260 root cell with two differences that
  stop it: the hypervisor at 0x7e000000, on the root cell's own ivshmem
  regions (0x7e000000, 0x7e100000), and a base design `system.bit` that does
  not exist ("to do"), which the driver loads into the FPGA at `jailhouse
  enable`. Now the hypervisor is at 0x7f000000, as on the KV260, with 15 MB
  instead of 16: the K26 SOM's DT reserves `pmu@7ff00000` (1 MB) for the PMU
  firmware, which the KV260 root cell's last megabyte overlaps. The base
  design is empty, which the driver skips.
- `0005-arm-gic-v2-SPI-targets-of-cells-without-CPUs`: a cell with no
  CPU, only R5 cores, that is given an SPI (runPHI gives an R5 container
  with network the INTx of its ivshmem link, IRQ 141 or 142) had that SPI
  routed to no CPU: the hypervisor took the target of the cell's first CPU
  from past the end of its CPU map (the set is empty), wrote 0 into the
  SPI's `ITARGETSR` byte, and did not repair it when the SPI went back to
  the root cell. Every later cell on that ivshmem link then got none of the
  root cell's interrupts, until a reboot. Now the routing of a cell without
  CPUs is left alone, and an SPI that targets no CPU is retargeted. The
  code is not the KR260's: kria-jailhouse has the same bug.

The fork has no KR260 demo cells. Its KV260 demo cells (`zynqmp-kv260-APU-`,
`-RPU0-`, `-RPU1-inmate-demo`, `zynqmp-kv260-linux-demo`) only use resources
of the K26 SOM (DDR, the R5 cores, UART1), the same on the KR260, and the
KR260 root cell has the KV260's layout: the scripts use them. The RISC-V and
VS-Classic cells need the KV260's DFX design.

### Boot sources

- `system_omnv.dts`: linux-xlnx 6.1's DT of the KR260
  (`zynqmp-smk-k26-revA.dts` with the `zynqmp-sck-kr-g-revB` carrier overlay,
  decompiled) with kria-jailhouse's Omnivisor additions, which refer to the
  base's nodes by path: the reserved memory (`jailhouse@7e000000` 32 MB,
  `rproc@3ed00000` 128 MB and `rproc@3ad00000` 64 MB for the R5 cores,
  `runphi@4f000000` 256 MB for runPHI's A53 cells, `cell@46d00000` for the
  Linux demo cell, `other@70000000`), the R5 TCMs, the R5 remoteproc
  (`rf5ss@ff9a0000`) and its IPI mailboxes. The SOM's `pmu@7ff00000` stays.
  No FPGA regions (no design). `r5f_0` and `r5f_1` have explicit phandles
  (as in kria-jailhouse's DT): the Jailhouse driver finds the R5 cores'
  remoteproc by phandle, and dtc gives none to a node that nothing refers
  to (`jailhouse enable` then says `Failed to fetch rproc for rCPU 0` and
  the root cell has no rCPUs).
- `boot_tftp.cmd`: kernel and DTB from `tftpboot/kr260-jailhouse/` on
  192.168.100.45, NFS root from `output/rootfs/kr260`, eth1 (J10D, see
  kr260-kvm); if a TFTP fetch fails, kr260-kvm from the SD card.

### Board setup (`install/` overlay)

kria-jailhouse's (Docker's store in `/mnt/sd/runphi-jailhouse/docker`,
containerd's in `/mnt/sd/runphi-jailhouse/containerd`, `S91containerd`,
`jailhouse_path.sh`, the demo binaries and scripts, `root/runphi`) without the
KV260's FPGA design and Kubernetes files, with kr260-kvm's KR260 files (the SD
card by label and `S28mnt-sd`, `eth1` with 192.168.100.53, `boot_mode.sh`,
`.profile`). The scripts in `root/scripts_jailhouse_kria/`:
`jailhouse_start.sh -o` enables `zynqmp-kr260-omnv.cell` (no FPGA design to
check for), `bm_demo.sh` runs the KV260 demo cells on APU, RPU0, RPU1,
`linux_demo.sh` the KV260 Linux demo cell. `root/non_rootcell/linux/Image` is
this environment's kernel.

## Build

As kria-jailhouse, with `build_environment.sh` (TF-A, Linux, Buildroot,
Jailhouse; no U-Boot, no bootgen):

```sh
./scripts/build_environment.sh -t kr260 -b jailhouse
./scripts/compile/dts_compile.sh -t kr260 -b jailhouse
./scripts/compile/bootscr_compile.sh -t kr260 -b jailhouse
cp environment/kr260/jailhouse/output/boot/{system.dtb,boot.scr} tftpboot/kr260-jailhouse/
cp tftpboot/kr260-jailhouse/Image environment/kr260/jailhouse/install/root/non_rootcell/linux/Image
```

On the server, as for kr260-kvm:

```sh
sudo ./scripts/remote/setup_nfs_rootfs.sh -t kr260 -b jailhouse
echo '/root/runphi/environment_builder/environment/kr260/jailhouse/output/rootfs/kr260 *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
exportfs -r
./scripts/remote/switch_backend.sh -t kr260 -b jailhouse -r
```

Then load the Jailhouse tree and runPHI's files on the running board:

```sh
./scripts/remote/load_components_to_remote.sh -t kr260 -b jailhouse -j -r -p <runphi_manager>
```

(runphi_manager's `kr260_platform_info.toml` and `kr260_state.toml`, the
same as `kria_*`: same SOM, same root cell layout.)

## Jailhouse, the Omnivisor and runPHI

As on the KV260 (kria-jailhouse's SETUP.md), with the KR260 root cell:

```sh
~/scripts_jailhouse_kria/jailhouse_setup/jailhouse_start.sh -o   # zynqmp-kr260-omnv.cell
jailhouse cell list      # ZynqMP-KR260: CPUs 0-3, rCPUs 0-1
~/scripts_jailhouse_kria/demos/bm_demo.sh APU gic-demo
~/scripts_jailhouse_kria/demos/bm_demo.sh RPU0 demo
~/scripts_jailhouse_kria/demos/bm_demo.sh RPU1 latency
```

The Linux demo cell's two ivshmem-net links are the root cell's `eth2` and
`eth3` on the KR260 (`eth0` and `eth1` are its PS Ethernet ports):

```sh
ip addr add 192.0.2.1/24 dev eth2; ip link set eth2 up
~/scripts_jailhouse_kria/demos/linux_demo.sh ip=192.0.2.10::192.0.2.1:255.255.255.0::eth0:off
ping 192.0.2.10
```

runPHI (containerd and `ctr`, `/root/target/switch_to_runphi.sh`) works as
on the KV260: A53 cells in `runphi@4f000000`, R5 cells on the core whose DDR
their ELF is linked into, ivshmem links with IRQs 141 and 142.

## Tests

Tested on the KR260 on 2026-11-23 and 2026-11-25 (runphi_manager 7dee20e):

- the QSPI's image B is `output/boot/BOOT.BIN` (`MultiBootOffset: 0x1F0`,
  `BL31: v2.8(release):6fca8a86e`, `OMNIVISOR PATCH`), image A Xilinx's
  firmware; kr260-kvm and kr260-xen boot with it as well
- the board boots kr260-jailhouse over TFTP+NFS (6.1.70-rt21 PREEMPT_RT),
  with eth1's static address only; the SD card is mounted on `/mnt/sd`; the
  root Linux has 3.2 GB
- `jailhouse_start.sh -o` enables the KR260 root cell (CPUs 0-3, rCPUs
  0-1) with the XMPU unit, the virtual PCI host and `ivshmem-net` (`eth2`,
  `eth3`, no address); the XMPU is set for each cell and removed with it
- `bm_demo.sh`: `gic-demo` on CPU 0 (timer jitter 0.8-2.1 us),
  `rpu0-demo` on R5 core 0, `rpu1-latency` on R5 core 1, all three at
  once; the cells destroyed, the cores back in the root cell
- `linux_demo.sh`: Linux on CPUs 2-3; the root cell pings it over the
  first ivshmem-net link, `eth2` (192.0.2.1 to 192.0.2.10)
- runPHI (containerd, `ctr`): at the same time a gic-demo cell on CPU 0
  (64 MB of the pool, network: 00:01.0, IRQ 141), the FreeRTOS demo on R5
  core 0 (core 0's region, 00:02.0, run to "Successfully ran FreeRTOS
  Hello World Example") and `rpu1-latency` on R5 core 1 (core 1's TCMs),
  each core chosen from its ELF; a second gic-demo cell, without network
  (no ivshmem device), on CPU 1; an ordinary container through runc.
  Refused, with nothing left behind: a third R5 program for core 0 ("R5
  core 0 is not free"), a non-ELF R5 program, 300 MB of memory, `os_var`
  `linux`, a configuration that does not compile (gcc's error), a
  container named like a cell made by hand (that cell left running).
  Stopping the containers gives every resource back to `state.toml`
- runPHI's ivshmem interrupts, with a test inmate built from Jailhouse's
  `ivshmem-demo` that reports its device's INTx: two cells with network got
  00:01.0 (IRQ 141) and 00:02.0 (IRQ 142) and received the root cell's
  interrupts when `eth2` and `eth3` went up and down, also after an R5
  container with network had used the link (patch 0005: without it the
  link's IRQ was routed to no CPU from then on)
- `jailhouse disable` releases every CPU and both R5 cores
- `cyclictest -m -p 95 -i 1000 -D 15 -t 4 -a 0-3` on the idle root Linux
  (Jailhouse disabled): max 10-12 us

## Known issues

- No FPGA design: the Omnivisor's FPGA regions and soft cores (PicoRV32,
  VS controller) are not available on the KR260. kria-jailhouse's partial
  reconfiguration problem (see its SETUP.md) applies to boards that have one.
- The PMU firmware's `pmu@7ff00000`: see [Jailhouse](#jailhouse); the KV260's
  root cell overlaps it.
- Once (2026-11-25), after a day of tests, R5 core 0 stopped running any
  program: its cells were created, loaded and started without errors, the
  core reported running, but it printed nothing (R5 core 1 was fine). A
  reboot did not clear it, a power cycle did, and the same sequence of
  cells did not bring it back. Its cause is not known.
