# Kria KV260 + Jailhouse (Omnivisor) Environment Setup

`kria-jailhouse` turns the KV260 into a Jailhouse host for the runPHI
`backend_jailhouse`, which runs containers as Jailhouse cells on the
Cortex-A53 cores (APU) and, through the Omnivisor, on the Cortex-R5 cores
(RPU) and FPGA soft cores. It is the board setup of
[kria-kvm](../kvm/SETUP.md) and [kria-xen](../xen/SETUP.md) (the same board at
the same address, TFTP+NFS boot from 192.168.100.45, Docker on the SD card)
with the Omnivisor fork of Jailhouse.

| Component | Built | Notes |
|---|---|---|
| Firmware (FSBL, PMUFW, ATF, U-Boot) | yes, but not flashed | the BOOT.BIN in QSPI, which all the Kria environments boot from; see [Firmware](#firmware) |
| Linux (`xlnx_rebase_v6.1_LTS`, 6.1.70) | yes | `jailhouse_kria_isolcpu_kernel_defconfig`, PREEMPT_RT; patches `jailhouse_enable`, `omnivisor`, `preempt_rt` (6.1.69-rt21); see [Kernel](#kernel) |
| Buildroot 2026.08.1 | yes | `jailhouse_kria_buildroot_defconfig`: Docker 28.5.2 with containerd, gcc on the target |
| Jailhouse (Omnivisor fork, `628a02d8`) | yes | driver, hypervisor, KV260 cells, APU/RPU/RISC-V demos (`-n -r all`); a pyjailhouse fix, see [Jailhouse](#jailhouse) |
| runPHI (`backend_jailhouse`) | from runphi_manager | `install/root/runphi`, built with this environment's Buildroot toolchain, see [runPHI](#runphi-backend_jailhouse) |
| KVM, Xen | no | Jailhouse owns EL2 |

## Firmware

The Kria boots BOOT.BIN from QSPI (A/B images, `xmutil bootfw_status`), not
from the SD card. The one in QSPI is a build of this environment's
firmware components: FSBL and PMUFW from the 2022.1 hardware description, the
ATF fork `DanieleOttaviano/arm-trusted-firmware` (v2.8 `6fca8a8`, with the
Omnivisor's changes) and U-Boot `xlnx_rebase_v2022.01` (`2022.01-gff67091f`).
Its U-Boot starts the next stage at EL2 and runs `boot.scr` from the SD card
(distro boot), which selects the environment (see
[Boot mode](#boot-mode-and-the-sd-card)).

This environment keeps that firmware: its scripts still build it
(`ATF_BUILD`, `UBOOT_BUILD`, `BOOTGEN_BUILD`, the tracked
`output/boot/BOOT.BIN`), but the update to newer sources (e.g. U-Boot
`xlnx_rebase_v2026.01`) is a separate step, not done yet. To flash a
BOOT.BIN, boot a Linux that has `xmutil` (the Kria Ubuntu image,
https://ubuntu.com/download/amd) and, with the new BOOT.BIN on the board:

```sh
sudo xmutil bootfw_update -i <path to BOOT.BIN>   # writes the inactive image (A or B)
sudo xmutil bootfw_status                         # the new image is the next to boot
# reboot; if ATF and U-Boot come up, keep it:
sudo xmutil bootfw_update -v
```

If the new image does not boot, the board falls back to the other one. See
https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/3020685316/Kria+SOM+Boot+Firmware+Update.
`REMOTE_SETUP.md` describes the older lab setup (DHCP, a U-Boot with a
built-in TFTP boot command): it is superseded by this file.

## What the configuration contains

### Kernel

linux-xlnx 6.1 LTS, at 6.1.70, the last commit of the branch (`846ca23f`).
The Jailhouse driver of the fork and the enabling patches support it; see
[Moving to 6.18](#moving-to-linux-618) for a newer kernel. Patches
(`custom_build/linux/patch/`, applied in this order):

- `jailhouse_enable`: the enabling patches (the symbols the driver needs,
  ivshmem: `uio_ivshmem`, `ivshmem-net`, `virtio_ivshmem`; no VHE switch)
- `omnivisor`: remoteproc's `rproc_start()` returns before powering the core
  on, which Jailhouse does at `cell start` (the fork no longer needs it since
  its 184c7dce, where the hypervisor filters the power-on calls itself; with
  it the R5 cells work too)
- `preempt_rt`: 6.1.69-rt21 adapted to 6.1.70, the same as kria-kvm's

`jailhouse_kria_isolcpu_kernel_defconfig`:

- `PREEMPT_RT`, `HZ_1000`, `NO_HZ_FULL`, `NR_CPUS=4`; no `RT_GROUP_SCHED`
  (which the omnv defconfig has): with it every new cgroup (Docker's,
  containerd's) starts with a real-time budget of 0, and no real-time task
  can run in a container (as in kria-kvm)
- the root cell's view of Jailhouse: `PCI_HOST_GENERIC` (the virtual PCI host
  that the driver adds when it enables the hypervisor) and the ivshmem drivers
  (`IVSHMEM_NET`, `UIO_IVSHMEM`, `VIRTIO_IVSHMEM`) for the root cell's two
  ivshmem devices (`00:01.0`, `00:02.0`), which runPHI hands out to the cells.
  `jailhouse_kria_omnv_kernel_defconfig` and the default defconfig have them;
  the isolcpu variant, which this environment has used since 2025-05, did
  not (added 2026-11)
- the Omnivisor's: `ZYNQMP_R5_REMOTEPROC`, the FPGA manager and regions
- Docker 28 and containerd on cgroup v2: namespaces, the cgroup controllers,
  `BPF_SYSCALL` and `CGROUP_BPF`, `OVERLAY_FS`, `VETH`, `VXLAN`,
  `BRIDGE_NETFILTER`, IPVS, nftables and the legacy iptables tables
  (`IP_NF_NAT`, `IP_NF_RAW`, which 6.1 still allows with PREEMPT_RT), device
  mapper, `KPROBES`, `MTD_OOPS`
- no KVM: Jailhouse needs EL2

The environment passes `-s` to the defconfig update scripts: if Kconfig drops
any option of the defconfig, the build stops. Before this check,
`PREEMPT_RT=y` was in the defconfig without the `preempt_rt` patch, and
Kconfig dropped it silently.

### Rootfs (`custom_build/buildroot/configs/jailhouse_kria_buildroot_defconfig`)

qemu-jailhouse's rootfs (Buildroot 2026.08.1: Docker 28.5.2, containerd,
python3, gcc and make on the target, which runPHI uses to compile its cell
configurations, dtc, ...) with:

- the hostname `kv260-jailhouse`, 6.1 kernel headers
- the `kria/jailhouse/install` overlay, no disk image
- no DHCP client (`dhcpcd`): the board has one static address
- the full dropbear (host keys of every type: the board has one set in all
  its environments, `setup_nfs_rootfs.sh` copies it),
  `rt-tests`, `tcpdump`, CA certificates

Patch (`custom_build/buildroot/patch/`): `gcc_enabled`, gcc on the target,
the 2023.05 patch ported to 2026.08.1 (the same as kria-kvm's).

### Jailhouse

The fork's newest commit (`628a02d8`, 2025-10), with `config_omnv.h`
(`CONFIG_OMNIVISOR`, XMPU isolation, FPGA loading). `jailhouse_compile.sh -n
-r all` builds the driver against this kernel, the hypervisor, the cells and
the demos: APU (`inmates/demos/arm64/*.bin`), R5
(`inmates/demos/armr5/src_*/*.elf`, `arm-none-eabi-gcc`) and RISC-V
(`inmates/demos/riscv/src_*/*.elf`). `load_components_to_remote.sh -j` copies
the tree to the board's `/root/jailhouse`.

Patch (`custom_build/jailhouse/patch/`,
`0001-pyjailhouse-the-Omnivisor-s-cell-header-and-cell_load.patch`):
pyjailhouse, which `jailhouse cell linux` uses, does not follow the fork's
own structures. Its cell parser misses `num_rcpu_devices` and
`num_fpga_devices` and reads the memory regions 8 bytes off ("No space found
to load all images"); its image loader chooses the `cell_load` layout from a
`config.h` that does not exist (and without `import os`), and uses the ioctl
number of the structure without the remote-CPU fields (`EINVAL`). The C tool
(`jailhouse cell create/load/start`) is not affected.

Root cells (`configs/arm64/`): `zynqmp-kv260.cell` (Jailhouse alone) and
`zynqmp-kv260-omnv.cell` (with the R5 cores and the FPGA regions). Both keep
the four A53 cores in the root cell until a cell takes them.

### Boot sources

- `system_omnv.dts`: the KV260 with the Omnivisor's remoteproc nodes and the
  reserved memory: `jailhouse@7e000000` (32 MB, the hypervisor),
  `rproc@3ed00000` (128 MB, R5 core 0's DDR and runPHI's cells, see
  [Known issues](#known-issues)), `rproc@3ad00000` (64 MB, R5 core 1's
  DDR), `cell@46d00000` (131 MB, the Linux demo cell: its communication
  region and its RAM at 0x47000000, and the shared memory of the `rpu0-demo`
  R5 demo at 0x46d00000; without it the root Linux uses that RAM). The
  reservation was in `system_omnv.dts` when it was created (2025-02) and
  dropped in 2025-05 (04c47443, no reason given); restored 2026-11.
  `system.dts` is now the same file.
- `boot_tftp.cmd` (default): kernel and DTB from `tftpboot/kria-jailhouse/` on
  192.168.100.45, NFS root from `output/rootfs/kria`; if a TFTP fetch fails,
  kria-kvm from the SD card. Jailhouse needs nothing on the kernel command
  line; `isolargs.txt` on the SD card adds CPU isolation as for kria-kvm.
- the older scripts (`boot*.cmd`: SD card, NFS with DHCP) and DTS variants are
  kept for reference.

### Board setup (`install/` overlay)

As kria-kvm's (see its SETUP.md: static address, `/etc/resolv.conf`, the SD
card's ext4 partition on `/mnt/sd`, `/root/.profile`, `adjust_time.sh`,
`boot_mode.sh`, the authorized ssh keys), plus:

- `etc/docker/daemon.json`, for a Docker started by hand: its store in
  `/mnt/sd/runphi-jailhouse/docker` (overlay2 on the SD card, next to
  kria-kvm's and kria-xen's), the `runphi` runtime (`/root/runphi`)
- `etc/containerd/containerd_default_config.toml`: containerd's store in
  `/mnt/sd/runphi-jailhouse/containerd`; `etc/init.d/S91containerd` stops
  Docker's daemon once it is up and starts containerd with this file
- `etc/profile.d/jailhouse_path.sh`: `JAILHOUSE_DIR=/root/jailhouse`
- `root/scripts_jailhouse_kria/`: `jailhouse_setup/jailhouse_start.sh`
  (`-o`: the Omnivisor root cell), `demos/bm_demo.sh` (bare-metal cells on
  APU, RPU0, RPU1, RISC-V), `demos/linux_demo.sh`,
  `jailhouse_setup/config_net_eth1_zephyr_dhcp_demo.sh`
- `root/non_rootcell/`, `root/bitstreams/`, `lib/firmware/mempol_reg_r5_0.elf`
  and `bin/{bench,membw_ctrl}` ([MEMPOL.md](MEMPOL.md)): prebuilt demo
  binaries
- `lib/firmware/dfx_wrapper.bit`: the Omnivisor root cell's FPGA base design,
  for now a link to the stand-in `root/bitstreams/base_pico32_tg.bit` (see
  [Jailhouse and the Omnivisor](#jailhouse-and-the-omnivisor))
- `root/runphi`: runPHI with `backend_jailhouse`

No address but eth0's: the QEMU-only `S93config_net` (a second address,
192.0.3.76) is gone.

## Build

The firmware is not rebuilt (see [Firmware](#firmware)), so build the other
components one by one rather than with `build_environment.sh` (in the
`env_builder` container, from the repository root):

```sh
yes n | ./scripts/patch/linux_patch.sh -t kria -b jailhouse -d jailhouse_enable,omnivisor,preempt_rt
yes y | ./scripts/defconfigs/linux_update_defconfigs.sh -t kria -b jailhouse -s
yes y | ./scripts/compile/linux_compile.sh -t kria -b jailhouse -m
./scripts/patch/jailhouse_patch.sh -t kria -b jailhouse -p 0001-pyjailhouse-the-Omnivisor-s-cell-header-and-cell_load.patch
yes y | ./scripts/compile/jailhouse_compile.sh -t kria -b jailhouse -n -r all
yes n | ./scripts/patch/buildroot_patch.sh -t kria -b jailhouse -d gcc_enabled
yes y | ./scripts/defconfigs/buildroot_update_defconfigs.sh -t kria -b jailhouse -s
yes y | ./scripts/compile/buildroot_compile.sh -t kria -b jailhouse
./scripts/compile/dts_compile.sh -t kria -b jailhouse
./scripts/compile/bootscr_compile.sh -t kria -b jailhouse
cp environment/kria/jailhouse/output/boot/system.dtb environment/kria/jailhouse/output/boot/boot.scr tftpboot/kria-jailhouse/
```

(`linux_compile.sh` copies `Image` to `tftpboot/kria-jailhouse/` and the
modules to the overlay; build Linux before Buildroot, which copies the
overlay into the rootfs.) Then, on the server, populate the NFS root and
export it. `setup_nfs_rootfs.sh` also gives it the board's ssh host keys,
those of the Kria's other NFS roots (`scripts/common/host_keys.sh`):

```sh
sudo ./scripts/remote/setup_nfs_rootfs.sh -t kria -b jailhouse
echo '/root/runphi/environment_builder/environment/kria/jailhouse/output/rootfs/kria *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
exportfs -r
```

## Boot mode and the SD card

kria-jailhouse boots only over TFTP+NFS; the SD card holds kria-kvm's system,
which is also the fallback. On the server (as root, in
`/root/runphi/environment_builder`):

```sh
./scripts/remote/switch_backend.sh -t kria -b jailhouse -r  # kria-jailhouse, reboot the board now
./scripts/remote/switch_backend.sh -t kria -b kvm -r        # back to kria-kvm
./scripts/remote/switch_backend.sh -t kria                  # the environments and the selected one
```

On the board, `/root/boot_mode.sh` (the same script in the three Kria
environments) shows where the system comes from and the server's selection,
and `boot_mode.sh sd -r` boots kria-kvm from the SD card. See kria-kvm's
[SETUP.md](../kvm/SETUP.md#switching-environments-kria-kvm-kria-xen-kria-jailhouse).

## Jailhouse and the Omnivisor

First load the Jailhouse tree (and runPHI's files, see below) from the
build machine:

```sh
./scripts/remote/load_components_to_remote.sh -t kria -b jailhouse -j -r -p <runphi_manager>
```

Then, on the board (`JAILHOUSE_DIR=/root/jailhouse`, `jailhouse` in `PATH`):

```sh
~/scripts_jailhouse_kria/jailhouse_setup/jailhouse_start.sh -o   # insmod, jailhouse enable zynqmp-kv260-omnv.cell
jailhouse cell list      # ZynqMP-KV260: CPUs 0-3, rCPUs 0-1, FPGA regions 0-2
~/scripts_jailhouse_kria/demos/bm_demo.sh APU gic-demo        # gic-demo.bin on an A53 core
~/scripts_jailhouse_kria/demos/bm_demo.sh RPU0 demo           # rpu0-demo-demo.elf on R5 core 0
jailhouse cell destroy inmate-demo-APU
~/scripts_jailhouse_kria/demos/linux_demo.sh                  # Linux on CPUs 2-3, console on the serial port
jailhouse disable
```

**The FPGA base design.** The Omnivisor root cell loads
`/lib/firmware/dfx_wrapper.bit` into the FPGA when Jailhouse is enabled
(`.fpga_base_bitstream` of `zynqmp-kv260-omnv.c`, since the fork's 9b2066ec);
without it `jailhouse enable` fails ("failed to load root bitstream") and
`jailhouse_start.sh -o` stops with an error. The fork's cells name the DFX
design of `DanieleOttaviano/vs_test_omnv` (`FPGA_VS_controller/`: the base
`dfx_wrapper.bit`, the partial bitstreams `dfx_picorv.bit` and
`dfx_reg0_vs_controller.bit`, the overlays `pico32.dtbo` and
`vs_classic.dtbo`), which this environment does not have yet; the overlay's
`root/bitstreams/` holds the previous design (`base_pico32_tg.bit`,
`pico32_partial.bit`, `pico32.dtbo`). For now `lib/firmware/dfx_wrapper.bit`
is a link to `/root/bitstreams/base_pico32_tg.bit`, a stand-in: a KV260 base
design with the same configuration ports (0x80000000) and three regions,
enough to enable Jailhouse and to run the APU, R5 and Linux cells, but not
the partial bitstreams of the DFX design (a partial bitstream only fits the
base it was built with).

The cells print on the board's serial console (`ttyPS1`, the USB serial port
of the carrier card; the Linux cell's `ttyPS0` is the same UART).
`bm_demo.sh` without a demo name lists the demos of a core. An R5 or RISC-V
cell is loaded with `jailhouse cell load <cell> -r <elf> <core>`, the ELF in
`/lib/firmware` (the script copies it there); the RISC-V soft core (core 2)
also needs its partial bitstream and device-tree overlay in `/lib/firmware`
and the `pico32_remoteproc` module, which this environment does not have yet
(see [Known issues](#known-issues) and `Documentation/omnivisor.md` of the
fork).

## runPHI (backend_jailhouse)

runPHI runs a container as a Jailhouse cell when its image has a
`/boot/config.json` (see `doc/README.md` in runphi_manager), and hands any
other container to runc. For each container it writes the cell's C
configuration from the templates in `/usr/share/runPHI` (with
`kria_platform_info.toml`: memory in `rproc@3ed00000`, the UART, an ivshmem
device), compiles it with the board's gcc, and runs `jailhouse cell create`,
`load`, `start`. A bare-metal image:

```json
{ "os_var": "baremetal", "inmate": "/boot/gic-demo.bin", "net": "none", "rpu_req": false }
```

runs on one A53 core (the container's CPU quota, default 1), in 64 MB of
`rproc@3ed00000` (its memory limit, default 64 MB); with `"rpu_req": true`
and an R5 ELF as `inmate`, on R5 core 0. `"net": "yes"` gives the cell one of
the root cell's two ivshmem devices (`00:01.0`, `00:02.0`, the root cell's
`eth1`, `eth2`), `"none"` none. Any `os_var` but `linux` is a single image
(`jailhouse cell load`); Linux guests are not implemented in
`backend_jailhouse`. The binary in the overlay is built with this
environment's Buildroot toolchain, so that it uses the board's glibc (2.44).
In `runphi_manager/rust_runphi`:

```sh
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=<environment_builder>/environment/kria/jailhouse/build/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc ./compile_rust.sh jailhouse
cp target/aarch64-unknown-linux-gnu/release/runphi <environment_builder>/environment/kria/jailhouse/install/root/runphi
```

`load_components_to_remote.sh -r` installs the rest in `/usr/share/runPHI`
(templates, `platform_info.toml`, `state.toml`, `caronte`) and the headers
that runPHI compiles each cell against: those of the Jailhouse tree that `-j`
loads (configuration revision 14, with the remote CPUs and the FPGA), not
runphi_manager's copies, which are qemu-jailhouse's (revision 13). runPHI
compiles with the board's gcc 15 with `-std=gnu11` (Jailhouse's dialect).

containerd is the container manager: `S91containerd` stops Docker's daemon
and starts containerd with `containerd_default_config.toml` (as in
qemu-jailhouse). To run containers through runPHI, replace runc with it
(`/usr/local/sbin/runc_vanilla` keeps runc, to which runPHI hands the
ordinary containers; `switch_to_vanilla.sh` undoes it), then use `ctr`:

```sh
bash /root/target/switch_to_runphi.sh
ctr images import --platform linux/arm64 images.tar     # or ctr images pull
ctr run -d docker.io/library/<image> <name>
jailhouse cell list                                     # the container's cell
ctr task kill <name>; ctr task rm <name>; ctr c rm <name>
```

After a power cycle the board's clock starts at 1970: `/root/adjust_time.sh`
sets it (registries refuse TLS otherwise).

## Tests

Tested on the KV260 (runphi_manager with the fixes of 2026-11-13, see
[Known issues](#known-issues)):

- the board boots kria-jailhouse over TFTP+NFS (6.1.70-rt21 PREEMPT_RT,
  `/sys/kernel/realtime` 1), with eth0's static address only; the root
  Linux has 3.5 GB
- `jailhouse_start.sh -o`: the Omnivisor root cell with CPUs 0-3, rCPUs 0-1,
  FPGA regions 0-2; the virtual PCI host and `ivshmem-net` (`eth1`, `eth2`,
  no address)
- `bm_demo.sh APU gic-demo`: the cell takes CPU 0, timer jitter 0.8-1.8 us;
  `bm_demo.sh RPU0 demo`: R5 core 0 runs the demo (`[RPU-0] time(us):
  68090`); both cells destroyed, the cores back in the root cell
- `linux_demo.sh`: Linux boots on CPUs 2-3 to its shell on the serial port
- runPHI (containerd, `ctr`): a gic-demo image in a cell on CPU 0, with and
  without network (`os_var` `zephyr` and `baremetal`); the FreeRTOS demo
  (`rpu0-freertos-demo.elf`) on R5 core 0 next to an APU cell; a plain
  busybox container through runc; `ctr task kill`, `ctr c rm` destroy the
  cells and give the CPUs, rCPU, memory and ivshmem devices back to
  `state.toml`
- `jailhouse disable` releases every CPU and both R5 cores
- `cyclictest -m -p 95 -i 1000 -D 15 -t 4 -a 0-3` on the idle root Linux
  (Jailhouse disabled): max 9-11 us

## Known issues

- **runPHI's memory pool and the R5.** `kria_platform_info.toml` hands the
  cells 0x3ed00000-0x46d00000 (`rproc@3ed00000`), the region where the R5
  ELFs are linked (0x3ed00000). runPHI gives a container the first free
  64 MB, but remoteproc loads an R5 ELF at its link address: an R5 container
  works only when it gets 0x3ed00000, i.e. when it starts while no APU cell
  holds it. Otherwise the root cell writes the ELF into another cell's memory
  and the hypervisor stops that root CPU (seen once: CPU 2 "failed", RCU
  stalls, a power cycle). Start R5 containers first; the fix belongs in
  runPHI (give an R5 cell the region of its ELF, and keep the APU cells out
  of it).
- **runPHI error handling.** If a cell configuration does not compile, runPHI
  logs "Compilation failed!!!" but `create` succeeds: the container is
  RUNNING without a cell, `ctr task kill` fails (no cell to destroy), and the
  container must be removed by hand (kill its `caronte`, then
  `/usr/share/runPHI/cleanup.sh -c -r`, `ctr task rm`, `ctr c rm`).
- **R5 demos.** `rpu0-demo` writes to a shared memory at 0x46d00000 that only
  the fork's demo cell grants: in a runPHI container it stops after
  `[RPU-0] Start!`. runPHI links each R5 ELF into `/lib/firmware` under its
  own name (replacing a copy that `bm_demo.sh` put there) and leaves the link
  behind.
- **The Linux demo cell's network.** `zynqmp-kv260-linux-demo.cell` places its
  ivshmem memory at 0x800400000, the Omnivisor root cell at 0x7e000000: the
  link between them does not come up (and the prebuilt inmate kernel in
  `root/non_rootcell/linux` does not probe it).
- **RISC-V soft core and VS controller.** Need the fork's DFX design
  (`dfx_wrapper.bit`, `dfx_picorv.bit`, `dfx_reg0_vs_controller.bit`,
  `pico32.dtbo`, `vs_classic.dtbo`) and the `pico32_remoteproc` and
  `vs_classic_remoteproc` modules, which the driver loads with
  `request_module()`: not tested; the base design is a stand-in (see
  [Jailhouse and the Omnivisor](#jailhouse-and-the-omnivisor)).

## Moving to Linux 6.18

linux-xlnx 6.18 LTS (kria-xen's kernel) is possible but not done; the work
items:

- upstream Jailhouse (Siemens) has had no commits since 2023-01, and its
  enabling branches stop at 5.15: the `jailhouse_enable` patches here are
  already a port to 6.1 and would need porting again, the ivshmem drivers
  (virtio's `find_vqs` changed in 6.11, the network driver API) being most of
  the work; the VHE patch can become `id_aa64mmfr1.vh=0` (the A53 has no VHE
  anyway)
- the fork's driver has version checks up to 5.8: `of_overlay_fdt_apply()`
  changed in 6.5, and the symbols it takes from the kernel (exported by the
  patches or found through kallsyms) must still exist
- 6.18 has the upstream `xlnx_r5_remoteproc` driver, with another device-tree
  binding (`xlnx,zynqmp-r5fss`): the `omnivisor` patch, the KV260 DTS and the
  root cell's remote-core names must follow it
- mainline PREEMPT_RT (plus the rt set, as kria-xen)
