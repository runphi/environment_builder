# QEMU + Xen Environment Setup

`qemu-xen` is the `zcu104-xen` environment on an emulated board: a Xen host
for the runPHI `backend_xen`, which runs containers as Xen domains (`xl
create`), without a ZCU104. Dom0 runs the zcu104-xen kernel (linux-xlnx 6.1)
and rootfs (Xen tools, Docker, LVM) on 4 emulated Cortex-A53 at EL2 with a
GICv2.

QEMU emulates every instruction of Xen, Dom0 and the guests (TCG), so this
environment is for functional tests: how runPHI creates and removes domains.
Latencies and timings mean nothing here.

| Component | Built | Notes |
|---|---|---|
| QEMU (`xlnx_rel_v2026.1.1`, QEMU 8.2.7) | yes | the emulated board, the same release as `qemu-jailhouse` and `qemu-kvm` |
| Xen 4.22.0 | yes, by Buildroot | hypervisor (`output/rootfs/xen`) and tools (`xl`, `xenstored`, ...) of the same version: Buildroot's `xen` package, bumped from 4.21.1 by the `xen_4_22` patches (Buildroot master's commit), with Xen's stable-4.22 fix of the SMCCC call arguments (see the patch README: qemu-xen worked without it, on the ZynqMP of kria-xen Dom0 has no clocks without it) |
| Linux (`xlnx_rebase_v6.1_LTS`) | yes | `xen_qemu_kernel_defconfig`: `xen_zcu104_kernel_defconfig` plus the drivers of QEMU's `virt` board and what Docker 28 needs on cgroup v2 (see `environment_cfgs/qemu-xen.sh`); Dom0 and the guests' kernel |
| Buildroot 2026.08.1 | yes | `xen_qemu_buildroot_defconfig`: `xen_zcu104_buildroot_defconfig` with the hypervisor and an ext4 disk image (zcu104-xen is still on Buildroot 2023.05) |
| runPHI (`backend_xen`) | from runphi_manager | built with this environment's Buildroot toolchain, see [runPHI](#runphi) |

## The emulated board

`environment_cfgs/qemu-xen.sh` sets the machine that `start_qemu.sh` starts:

| | ZCU104 (`zcu104-xen`) | QEMU (`qemu-xen`) |
|---|---|---|
| CPUs | 4 Cortex-A53 | 4 emulated Cortex-A53, `virtualization=on` (EL2) |
| GIC | GIC-400 (GICv2) | GICv2 with the virtualization extensions: the domains get the host's GICv2, unless `gic_version` in their `/boot/config.json` asks for another |
| RAM | 2 GB, Dom0 1500 MB | 2 GB, Dom0 1024 MB: without an IOMMU, Xen maps Dom0 1:1 onto the RAM in large aligned blocks, and here it does not always find room for 1500 MB (with 2 GB as with 4 GB) |
| Xen | a prebuilt 4.20.0 hypervisor in `tftpboot/zcu104-xen/`, Buildroot 2023.05's 4.14.5 tools | Xen 4.22.0, hypervisor and tools built together |
| Boot | U-Boot puts Dom0 in the device tree (`boot_xen.cmd`) | QEMU boots `xen` and hands it the kernel as Dom0 (`guest-loader`) |
| Xen arguments | `console=dtuart dtuart=serial0 dom0_mem=1500M dom0_max_vcpus=1 vwfi=native` | `console=dtuart dom0_mem=1024M dom0_max_vcpus=1 vwfi=native noreboot` (`QEMU_XEN_ARGS`): QEMU's device tree has no `serial0` alias, and without `dtuart` Xen takes its UART from `/chosen/stdout-path`; with `noreboot` a Xen panic stops there, readable, instead of rebooting into a Xen that has its boot CPU only |
| Root filesystem | NFS or SD card | `output/rootfs/rootfs.ext2` (ext4, 6 GB) on a virtio disk |
| LVM (`test-vg`) | | loop file `/var/lib/runphi/lvm.img` (3 GB, sparse), created at the first boot by `S29lvm-loop`, as in `qemu-kvm` |
| Docker | 23 on cgroup v1; runPHI replaces runc | 28.5 on cgroup v2; runPHI is the `runphi` runtime (`/etc/docker/daemon.json`), runc stays the default |

## Build

As for the other environments, preferably in the Docker container (see the
main [README](../../../README.md)):

```sh
./scripts/build_environment.sh -t qemu -b xen
```

### runPHI

runPHI is built from runphi_manager with the Buildroot toolchain of this
environment, so that it uses the rootfs's glibc. In
`runphi_manager/rust_runphi` (with Rust and its `aarch64-unknown-linux-gnu`
target installed):

```sh
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=<environment_builder>/environment/qemu/xen/build/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc ./compile_rust.sh xen
```

## Run

```sh
./scripts/qemu/start_qemu.sh -t qemu -b xen     # login: root / root
```

Xen's messages and Dom0's console share the terminal: `Ctrl+A` three times
switches the input between Xen and Dom0. The network is QEMU's user-mode
network by default, with Dom0's ssh on `localhost:5022`; `QEMU_NET=tap` puts
it on `tap0` instead, as described in [qemu/jailhouse/DEMO.md](../jailhouse/DEMO.md).

From another shell, copy runPHI (with `caronte`, its keep-alive helper for
Xen) and the guest kernel into Dom0:

```sh
./scripts/remote/load_components_to_remote.sh -t qemu -b xen -a -p <runphi_manager>
```

Xen and Dom0 reach the login prompt in about 15 seconds. Check Xen in Dom0:

```sh
xl info | grep -E 'xen_version|nr_cpus|free_memory'   # 4.22.0, 4, about 990 MB
xl list                  # Domain-0, 1024 MB, 1 vCPU
vgs test-vg              # 3 GB, free
```

## Test images and tests

`/root/guest/make_test_images.sh` builds two images from `/root/guest/Image`
(this environment's kernel) and `/root/guest/rootfs.cpio.gz`:
`runphi-xen-guest:initramfs` and `runphi-xen-guest:lvm`. The initramfs has its
login prompt on `ttyAMA0` (QEMU's PL011, for the KVM guests), which a Xen
domain does not have: the images put it on `hvc0`, the domain's console.

```sh
/root/guest/make_test_images.sh
docker run -d --name x1 --runtime=runphi runphi-xen-guest:initramfs
xl list                  # the domain, named after the container ID (24 characters)
cat /run/runPHI/*/config.cfg   # the xl configuration runPHI generated
xl console <domain>      # the guest's console (login prompt on hvc0); leave with Ctrl+]
docker rm -f x1
xl list; ls /run/runPHI  # only Domain-0, nothing left

docker run -d --name x2 --runtime=runphi runphi-xen-guest:lvm
lvs test-vg              # lv_<id>, about 150 MB; the guest boots from it (root=/dev/xvda)
docker rm -f x2
lvs test-vg              # the volume is gone
```

Each domain gets physical CPUs of its own (`cpus` in its `config.cfg`), the
highest free ones; Dom0 keeps CPU 0 for its vCPU. With 4 CPUs, three
single-vCPU guests run at once (CPUs 3, 2 and 1), and a fourth is refused with
`not enough free CPUs: need 1, have 0 of 4`.

runPHI from runphi_manager `d0fb1d3` on is needed with this Docker: Docker 28
moves the container's network interface into the network namespace of the
container's first process, `caronte` for runPHI, which older versions left in
Dom0's namespace, where `eth0` exists; their containers fail with `error
renaming interface ... to "eth0": file exists` unless run with `--network
none`. The guest has no network through Docker anyway.

Tested (runphi_manager `08ff770`, and `6591f4f` for the LVM image, whose
lvcreate failed over the signatures of an earlier volume): both images boot
and are removed with nothing left behind, on Docker's default network; three
guests run at once on CPUs 3, 2 and 1, and a fourth and a guest larger than
Xen's free memory are refused (`not enough free memory: need 1200 MB, have 992
MB`).

Retested on 2026-11-12 (runphi_manager `04473e0`) with Xen's SMCCC fix and
the images' login prompt on `hvc0`: the same results, and both images reach
their login prompt in about 15 seconds.

## Limitations

- **Emulated.** Xen, Dom0 and the guests run on TCG: no timing from this
  environment says anything about the hardware.
- **Guest network.** runPHI's Xen backend gives the guests no network.
