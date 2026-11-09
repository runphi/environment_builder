# QEMU + KVM Environment Setup

`qemu-kvm` is the [kria-kvm](../../kria/kvm/SETUP.md) environment on an
emulated board: a KVM host for the runPHI `backend_kvm`, which drives guests
through `virsh` -> `libvirtd` -> `qemu-system-aarch64`, without a KV260. It
runs the same kernel (linux-xlnx 6.1, PREEMPT_RT, KVM) and the same rootfs
packages (libvirt, QEMU, Docker, LVM) on 4 emulated Cortex-A53 at EL2, in newer
versions: the rootfs is built with Buildroot 2026.08.1, while kria-kvm is still
on 2023.05.

QEMU emulates every instruction of the host and of its guests (TCG), so this
environment is for functional tests: how runPHI creates, pins, connects and
removes guests. Latencies and timings mean nothing here; measure on the board.

| Component | Built | Notes |
|---|---|---|
| QEMU (`xlnx_rel_v2026.1.1`, QEMU 8.2.7) | yes | the emulated board, the same release as `qemu-jailhouse` |
| Linux (`xlnx_rebase_v6.1_LTS`) | yes | `kvm_qemu_kernel_defconfig`: `kvm_kria_kernel_defconfig` plus what Docker 28 and libvirt need on cgroup v2 (see `environment_cfgs/qemu-kvm.sh`), with the same patches (`preempt_rt`, `kvm_stage2_free_flush`) |
| Buildroot 2026.08.1 | yes | `kvm_qemu_buildroot_defconfig`: `kvm_kria_buildroot_defconfig` with an ext4 disk image; patches `gcc_enabled` (ported), `libvirt_cgroup_v2`, `libvirt_12` (libvirt 12.9.0) |
| runPHI (`backend_kvm`) | from runphi_manager | built with this environment's Buildroot toolchain, see [runPHI](#runphi) |

## The emulated board

`environment_cfgs/qemu-kvm.sh` sets the machine that `start_qemu.sh` starts
(`QEMU_CPU`, `QEMU_SMP`, `QEMU_MEM`, `QEMU_MACHINE`, `QEMU_APPEND`):

| | KV260 (`kria-kvm`) | QEMU (`qemu-kvm`) |
|---|---|---|
| CPUs | 4 Cortex-A53 | 4 emulated Cortex-A53, `virtualization=on` (EL2) |
| KVM | nVHE (ARMv8.0, no VHE) | nVHE as well |
| GIC | GIC-400 (GICv2): guests get a GICv2, at most 8 vCPUs | GICv3: guests get a GICv3 |
| RAM | 3.7 GB usable | 4 GB |
| Root filesystem | NFS or SD card | `output/rootfs/rootfs.ext2` (ext4, 6 GB) on a virtio disk |
| Userspace | Buildroot 2023.05: Docker 23, libvirt 7.10, QEMU 8.0 | Buildroot 2026.08.1: Docker 28.5, libvirt 12.9, QEMU 11.0 |
| cgroups | v1 | v2: Buildroot's Docker only mounts cgroup v2 without systemd |
| Docker data | `/mnt/sd/runphi/docker` | `/var/lib/docker` |
| LVM (`test-vg`) | loop file on the SD card, created by hand | loop file `/var/lib/runphi/lvm.img` (3 GB, sparse), created at the first boot by `S29lvm-loop` |
| Clock | starts at 1970, `adjust_time.sh` | QEMU's RTC: the PC's time |
| CPU isolation | `boot_mode.sh iso <cpus>` | none by default; add the arguments to `QEMU_APPEND` |

## Build

As for the other environments, preferably in the Docker container (see the
main [README](../../../README.md)):

```sh
./scripts/build_environment.sh -t qemu -b kvm
```

This builds QEMU, the kernel (`output/boot/Image`, modules in
`install/lib/modules`) and the rootfs (`output/rootfs/rootfs.ext2`, a sparse
file of about 800 MB on disk): about an hour in Docker on a 16-thread PC.

### runPHI

runPHI is built from runphi_manager with the Buildroot toolchain of this
environment (GCC 15), so that it uses the rootfs's glibc (2.44): a binary
linked with a newer glibc does not start.
In `runphi_manager/rust_runphi` (with Rust and its `aarch64-unknown-linux-gnu`
target installed):

```sh
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=<environment_builder>/environment/qemu/kvm/build/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc ./compile_rust.sh kvm
```

The binary is `target/aarch64-unknown-linux-gnu/release/runphi`; the next
step copies it into the VM.

## Run

```sh
./scripts/qemu/start_qemu.sh -t qemu -b kvm     # login: root / root
```

The network is QEMU's user-mode network by default: the VM reaches the
Internet, and its ssh is forwarded to `localhost:5022`
(`./scripts/remote/ssh_connection.sh -t qemu -b kvm`). `QEMU_NET=tap` puts it
on `tap0` instead, as described in [qemu/jailhouse/DEMO.md](../jailhouse/DEMO.md).

From another shell, copy runPHI and the guest kernel into the VM:

```sh
./scripts/remote/load_components_to_remote.sh -t qemu -b kvm -a -p <runphi_manager>
```

`-a` is `-r` (runPHI, to `/usr/local/sbin/runphi`) plus `-g` (this
environment's `Image`, to `/root/guest/Image`, the kernel of the test guests).
Both stay in the VM's disk image until the next Buildroot build rewrites it.

The VM reaches the login prompt in about 15 seconds.

runPHI from runphi_manager `d0fb1d3` on is needed with this Docker: Docker 28
moves the container's network interface into the network namespace of the
container's first process, runPHI's watcher, which older versions left in the
host's namespace, where `eth0` exists; their containers fail with `error
renaming interface ... to "eth0": file exists` unless run with `--network
none`. The guest's network comes from `/boot/config.json` (`"net"`) anyway.

Check the KVM host in the VM:

```sh
dmesg | grep kvm         # ... kvm [1]: Hyp mode initialized successfully
ls -l /dev/kvm
virsh capabilities | grep -A2 "domain type='kvm'"
vgs test-vg              # 3 GB, free
```

## Test images and tests

`/root/guest/make_test_images.sh` builds, in the VM, the four test images of
the KV260 from `/root/guest/Image` and `/root/guest/rootfs.cpio.gz` (the
initramfs of the board's test guests, with `cyclictest` and `stress-ng`):

```sh
/root/guest/make_test_images.sh
docker images | grep runphi-kvm-guest   # initramfs, pinned-net, steer, lvm
```

The tests of [kria-kvm's RUNPHI.md](../../kria/kvm/RUNPHI.md#5-tests-to-run-by-hand)
then run as they are (runphi_manager `08ff770`), as does everything else in that guide (how runPHI drives the guests, every
`/boot/config.json` field, troubleshooting), with the differences of the
table above. The cgroup of a container is `/sys/fs/cgroup/docker/<full id>`
(cgroup v2) instead of `/sys/fs/cgroup/cpuset/docker/<full id>`. All of them
(5.1 to 5.7) give the results that the guide shows for the board, except that
the guests' GIC is a GICv3: the domain type is `kvm`, a guest reaches its
login prompt in about 30 to 45 seconds, pinned vCPUs run at SCHED_FIFO 99 on
their CPUs with QEMU's other threads on the remaining ones (QEMU in the
container's cgroup, `0::/docker/<id>`, cpuset `0-3`), `hello-world` is pulled
from Docker Hub through the default network, and nothing is left behind.

## Limitations

- **Emulated.** The host and its guests run on TCG, at a fraction of the
  board's speed: no latency or performance figure from this environment says
  anything about the hardware.
- **No nested virtualization for the guests.** The Cortex-A53 has no
  FEAT_NV, so the guests run at EL1 only, as on the board.
- **The tap network needs root** on the PC, once per boot, for
  `setup_bridge_tap.sh` (see [qemu/jailhouse/DEMO.md](../jailhouse/DEMO.md)).
