# runPHI with the KVM backend on the Kria KV260

This guide explains how runPHI runs containers as KVM virtual machines on the
Kria KV260 of the `kria-kvm` environment, which settings control those
machines, and how to test them by hand. Setting the board up is covered in
[SETUP.md](SETUP.md). The code is `rust_runphi/crates/backend_kvm` in
runphi_manager, whose `doc/backend_kvm_docs/` describes the backend on any
host, x86 included.

Unless stated otherwise, every command runs on the board, as root, after
logging in from the PC:

```sh
ssh root@192.168.100.46
```

Contents:

1. [How it works](#1-how-it-works)
2. [The board](#2-the-board)
3. [`/boot/config.json`](#3-bootconfigjson)
4. [`docker run` options](#4-docker-run-options)
5. [Tests to run by hand](#5-tests-to-run-by-hand)
6. [Building your own images](#6-building-your-own-images)
7. [Looking at a running guest](#7-looking-at-a-running-guest)
8. [Troubleshooting](#8-troubleshooting)
9. [Updating runPHI on the board](#9-updating-runphi-on-the-board)
10. [Limitations](#10-limitations)

## 1. How it works

### runPHI is a container runtime

Docker does not start containers itself. It asks containerd, which runs an
OCI runtime, normally `runc`, with the commands `create`, `start`, `kill`,
`delete` and `state`. `/etc/docker/daemon.json` registers runPHI
(`/usr/local/sbin/runphi`) as a second runtime named `runphi`, so
`docker run --runtime=runphi` sends those commands to runPHI instead of runc.

runPHI then looks at the container's root filesystem:

- **With a `/boot/config.json`**, the container is a *partitioned container*:
  runPHI boots what the image carries (a Linux kernel, an initramfs, a disk
  image) as a KVM virtual machine, configured by that file.
- **Without it**, runPHI passes the command, unchanged, to runc
  (`/usr/local/sbin/runc_vanilla`, a link to `/usr/bin/runc`). Ordinary images
  therefore work under the `runphi` runtime too.

The OCI annotation `org.runphi.runtime` (`"runphi"` or `"runc"`) overrides
this choice. Docker 23 on the board has no option to set annotations;
Kubernetes, through containerd, has.

### From `docker run` to a virtual machine

| OCI command (from Docker) | What runPHI does |
|---|---|
| `create` (`docker run`, `docker create`) | 1. reads `/boot/config.json` from the container rootfs<br>2. writes the libvirt domain to `/run/runPHI/<id>/domain.xml`<br>3. with `"disk_type": "lvm"`, creates the logical volume and copies the rootfs into it<br>4. `virsh create --paused`: QEMU starts, the guest does not run yet<br>5. moves QEMU into the container's cgroup, so `--cpuset-cpus`, `--memory` and `--cpus` apply to it<br>6. pins the vCPU threads again (the cgroup move resets their affinity)<br>7. starts a *watcher* process and gives its PID to containerd<br>8. with `steer_irq`, moves the host interrupts |
| `start` (`docker run`, `docker start`) | `virsh resume`: the guest starts booting |
| `kill` (`docker stop`, `docker kill`, `docker rm -f`) | `virsh suspend` and `virsh destroy`, then restores the interrupts, removes the logical volume, the cgroup and `/run/runPHI/<id>` |
| `delete` (`docker rm`) | the same teardown, when `kill` has not already done it |
| `state` | prints the container's state as JSON |

Names used everywhere below:

- `<id>` is the container ID cut to 24 characters (Jailhouse cannot handle
  longer cell names, and runPHI uses the same rule for every backend).
- The libvirt domain is called `runphi-<id>`.
- `/run/runPHI/<id>/` holds runPHI's state for the container while it exists:
  the domain XML, the bundle and PID file paths, the cgroup path, the disk and
  the saved IRQ affinities.

**The watcher.** QEMU is started by `libvirtd`, so it is not a child of
runPHI or containerd, and containerd cannot wait for it. runPHI starts a small
`sh` loop that lives as long as the QEMU process and gives containerd that
PID instead. When the guest powers off, reboots or crashes, QEMU exits (the
domain is set to *destroy* on all three), the watcher exits, and Docker shows
the container as *Exited*.

### The virtual machine

The domain that runPHI generates on the Kria:

| Domain XML | Value | Why |
|---|---|---|
| `<domain type=…>` | `kvm` (`qemu`, i.e. emulation, if `/dev/kvm` is missing) | hardware virtualization |
| machine | `virt` | QEMU's generic ARM board: GIC, PL011 UART, PCIe with virtio devices. QEMU writes its device tree itself. |
| `<cpu>` | `host-passthrough` | the guest sees the real Cortex-A53 |
| `<gic version='host'/>` | GICv2 on the KV260 | KVM can only give a guest the host's GIC version |
| `<memory>` | `memory` MB, `<locked/>` | guest RAM is allocated and locked in host RAM: never swapped, no faults on first use |
| `<cputune>` | `<vcpupin>` and `<vcpusched scheduler='fifo' priority='99'>` | only for the vCPUs listed in `vcpu_pinning` |
| `<os>` | `<kernel>`, `<initrd>`, `<cmdline>` | direct kernel boot: no firmware, no bootloader |
| `<serial>` | PL011 on a pty | the guest console (`ttyAMA0`), also logged to a file |
| `<disk>`, `<interface>` | virtio | only with `disk_type` and `net` |
| `<seclabel>` | QEMU runs as root | so it can read the files inside the container rootfs |

See it with `virsh dumpxml runphi-<id>` or `cat /run/runPHI/<id>/domain.xml`.

## 2. The board

| | |
|---|---|
| CPUs | 4 Cortex-A53, CPUs 0–3 |
| RAM | 3.7 GB usable |
| Kernel | Linux 6.1.70 PREEMPT_RT, KVM in nVHE mode, cgroup v1, no `CONFIG_RT_GROUP_SCHED` |
| Virtualization | libvirt 7.10 (`libvirtd`), QEMU 8.0.2 (`qemu-system-aarch64`) |
| Docker | 23.0.5, data on the SD card (`/mnt/sd/runphi/docker`), runtimes `runc` (default) and `runphi` |
| LVM | volume group `test-vg`, 6 GB, on the loop file `/mnt/sd/runphi/lvm.img`, attached at boot by `/etc/init.d/S29lvm-loop` |
| Tools | `virsh`, `ps` (procps-ng), `chrt`, `lvs`/`vgs`, `cyclictest`, `stress-ng`, `curl` |

The clock starts at 1970 after every boot. Run `/root/adjust_time.sh` before
pulling images: TLS refuses certificates that are not valid yet.

### Test images

Four images are already loaded (`docker images | grep runphi-kvm-guest`).
They all boot a copy of this environment's kernel (`/root/guest/Image`), with
the initramfs of the Jailhouse Linux inmate (`/root/guest/rootfs.cpio.gz`):

| Image | `/boot/config.json` | Tests |
|---|---|---|
| `runphi-kvm-guest:initramfs` | 1 vCPU, 256 MB, no network | the basic boot |
| `runphi-kvm-guest:pinned-net` | 2 vCPUs pinned to CPUs 2 and 3, 512 MB, `"net": "user"` | pinning, SCHED_FIFO, networking |
| `runphi-kvm-guest:lvm` | 1 vCPU, 256 MB, `"disk_type": "lvm"`, no initramfs | root filesystem on a logical volume |
| `runphi-kvm-guest:steer` | vCPU 0 pinned to CPU 3, `"steer_irq": [0, 1]` | IRQ steering |

Guest login: `root` / `root`. The guest gets an address with `udhcpc` on
`eth0` when it has a network, and has `cyclictest` and `stress-ng`.

## 3. `/boot/config.json`

The file lives inside the image, at `/boot/config.json`. For example, the
`pinned-net` image:

```json
{
  "os_var": "linux",
  "inmate": "/boot/Image",
  "ramdisk": "/boot/rootfs.cpio.gz",
  "memory": 512,
  "vcpus": 2,
  "vcpu_pinning": [ { "vcpu": 0, "pcpu": 2 }, { "vcpu": 1, "pcpu": 3 } ],
  "net": "user"
}
```

All fields are optional, and unknown ones are ignored.

| Field | Default | Meaning with the KVM backend |
|---|---|---|
| `os_var` | `""` | `"linux"` for a Linux guest: kernel, initramfs and a command line (`console=ttyAMA0`, plus `root=/dev/vda rw` with a disk). Anything else is booted as a bare-metal binary: only `<kernel>`, no command line, no initramfs. **Set it for every Linux image**: without it the guest also gets 32 MB of RAM by default. |
| `inmate` | `/boot/boot.bin` | the kernel (`/boot/Image`) or bare-metal binary, as a path inside the image |
| `ramdisk` | none | the initramfs, as a path inside the image. Without it (and without a disk) the kernel has no root filesystem. |
| `dtb` | none | a device tree for the guest. Not needed: QEMU generates one for `virt`. Unlike the other paths, this one is passed to libvirt as it is, so it is a path on the board, not in the image. |
| `memory` | `--memory`, else 1024 (Linux) or 32 (other) | guest RAM in MB. When set and `docker run` has no `--memory`, it also becomes the container's cgroup memory limit. |
| `vcpus` | see [below](#vcpus-pinning-and-real-time) | number of vCPUs |
| `vcpu_pinning` | `[]` | `[{"vcpu": N, "pcpu": M}, …]`: vCPU N runs only on host CPU M, with SCHED_FIFO priority 99 |
| `steer_irq` (or `irq_steering`) | none | host CPUs that get all movable host interrupts while the guest runs, e.g. `[0, 1]` |
| `isolcpu`, `nohz_full` | `""` | CPU lists (`"2,3"`, `"2-3"`) that you consider isolated. Only used to warn in runPHI's log when `steer_irq` sends interrupts to one of them; isolation itself comes from the kernel command line. |
| `net` | `"no"` | the guest's network, see [below](#networking) |
| `netconf` | `""` | bridge or libvirt network name for `"net": "bridge"` and `"net": true` |
| `disk_type` | `""` | the guest's root filesystem: `""` (the initramfs), `"file"` or `"lvm"`, see [below](#root-filesystem) |
| `disk_image` | none | for `"disk_type": "file"`: the raw disk image, as a path inside the image |
| `disk_size` | rootfs size × 1.3 + 64 | for `"disk_type": "lvm"`: size of the logical volume in MB |

`inmate`, `ramdisk` and `disk_image` are resolved inside the container's root
filesystem: `/boot/Image` means the image's `/boot/Image`, not the board's.

The fields `kernel`, `initrd`, `cpio`, `starting_vaddress` and `rpu_req` exist
for the Jailhouse and Xen backends; the KVM backend ignores them.

### vCPUs, pinning and real time

The number of vCPUs is the first of:

1. `vcpus`;
2. the number of entries in `vcpu_pinning`;
3. the CPU limit of `docker run --cpus` (rounded up);
4. 1.

Each vCPU is a thread of the QEMU process, named `CPU <n>/KVM`. Without
pinning, the host scheduler moves these threads freely across the CPUs that
the container may use, as normal (SCHED_OTHER) threads.

A vCPU listed in `vcpu_pinning` is bound to its host CPU and runs as
SCHED_FIFO priority 99, the highest real-time priority. libvirt applies both
when it creates the domain. Then runPHI moves QEMU into the container's
cgroup, which on this kernel (cgroup v1) resets the threads' CPU affinity, so
runPHI pins them again with `sched_setaffinity`. With `docker run
--cpuset-cpus`, every pinned CPU must be in that set, or creating the
container fails with `EINVAL`.

To give a guest CPUs of its own:

- **Isolate them on the host.** `isolcpus=` and `nohz_full=` on the kernel
  command line keep the host scheduler, timers and kernel threads away from
  them. In this environment, `/root/boot_mode.sh iso 3` sets them (with
  `rcu_nocbs=` and `irqaffinity=`) for the next boot, and `iso off` removes
  them; see [SETUP.md](SETUP.md#cpu-isolation).
- **Pin the vCPUs to them** with `vcpu_pinning`, and restrict the container to
  them with `--cpuset-cpus`, so that QEMU's other threads (I/O, emulation)
  stay there as well.
- **Move the host's interrupts away** with `"steer_irq"`, listing the other
  CPUs.
- **List them in `isolcpu` / `nohz_full`** so runPHI warns you if `steer_irq`
  ever points at them.

A vCPU at SCHED_FIFO 99 that never sleeps keeps its CPU forever. Linux limits
real-time threads to 95% of each second by default
(`/proc/sys/kernel/sched_rt_runtime_us`), which leaves other work on that CPU
a 5% share.

`cyclictest` and `stress-ng` are installed both on the board and in the test
guest, for latency measurements.

### Networking

QEMU is started by `libvirtd` on the host, outside the container's network
namespace, so the container's Docker networking has no effect. The guest gets
a virtio network card according to `net`:

| `net` | Network |
|---|---|
| `"no"`, `false`, `""` (default) | none |
| `"user"` or `"slirp"` | QEMU user-mode networking: a private NAT inside the QEMU process. The guest is `10.0.2.15`, the gateway `10.0.2.2`, DNS `10.0.2.3`, given by QEMU's built-in DHCP. The guest reaches the outside, nothing reaches the guest. No host configuration needed. **Tested on the board.** |
| `"bridge:<name>"`, or the name of a host bridge | attached to an existing host bridge |
| `"bridge"` | the bridge named in `netconf`, otherwise the first of `virbr0`, `docker0`, `xenbr0`, `br0` that exists |
| `"network:<name>"`, `"network"` | a libvirt virtual network (`default` if no name) |
| `"yes"`, `true` | the libvirt network in `netconf` (default `default`) if libvirt's modular network daemon (`virtnetworkd`) runs, which is not the case on this board; otherwise as `"bridge"` |

On this board only `docker0` exists (Docker's bridge, `172.17.0.1/16`, no
DHCP server for guests), and libvirt's `default` network is defined but
inactive (`virsh net-start default` starts it). The bridge and network modes
have not been tested on the board.

### Root filesystem

| `disk_type` | Root filesystem | Notes |
|---|---|---|
| `""` (default) | the initramfs in `ramdisk`, in RAM | the simplest: changes are lost at shutdown |
| `"file"` | the raw image `disk_image` from the container image, attached as virtio disk `/dev/vda` | the guest writes into the image file in the container's filesystem |
| `"lvm"` | a new logical volume `test-vg/lv_<id>`, formatted as ext4 and filled with a copy of the whole container rootfs, attached as `/dev/vda` | removed with the container: changes are lost then |

With a disk, the command line gets `root=/dev/vda rw`, and an `lvm` image needs
no `ramdisk`. The volume group is `test-vg` unless the file
`/usr/share/runPHI/kvm_lvm_vg` contains another name; creating the container
fails if the group has less free space than the volume needs.

### IRQ steering

With `"steer_irq": [0, 1]`, runPHI writes `0,1` to
`/proc/irq/<n>/smp_affinity_list` for every host interrupt that accepts it,
after saving the original values in
`/run/runPHI/<id>/saved_irq_affinities.json`. Removing the container writes
them back. Some interrupts (per-CPU timers, IPIs) cannot be moved and are
skipped.

The steering is host-wide. With two steering containers, remove them in the
reverse order of creation: each one saves the affinities it found, so
removing the first one early would restore the original affinities under the
second, and removing the second last would put the first one's steering back.

## 4. `docker run` options

| Option | Effect on a runPHI guest |
|---|---|
| `--runtime=runphi` | required: without it Docker uses runc, which treats the image as an ordinary container and does not boot the guest |
| `-d` | use it always: there is nothing to attach to, the guest's console is not the container's output |
| `--name <name>` | as usual |
| `--rm` | as usual: the container is removed when the guest stops |
| `--cpuset-cpus <list>` | the CPUs all of QEMU's threads may run on. Pinned vCPUs must be inside. |
| `--cpus <n>` | CPU time limit for QEMU's normal threads (it does not throttle SCHED_FIFO vCPUs), and the default number of vCPUs |
| `-m`, `--memory <size>` | cgroup memory limit, and the default guest RAM |
| `docker stop`, `docker kill`, `docker rm -f` | destroy the guest at once, like pulling the power cord: there is no graceful shutdown |

The options that configure a Linux container have no effect, because there
is no Linux container: `-p`, `--network`, `-v`, `-e`, `--user`, `--hostname`,
`--entrypoint`, `--privileged` and the command after the image name. Change the
guest through `/boot/config.json` instead.

| Docker command | With a runPHI guest |
|---|---|
| `docker ps`, `docker inspect` | work; the container is *Up* while QEMU runs |
| `docker logs` | shows nothing: use the serial log or `virsh console` |
| `docker exec`, `docker pause`, `docker unpause`, `docker update` | not implemented by runPHI |
| `docker restart`, restart policies | not tested |

## 5. Tests to run by hand

These tests go through what runPHI does on the board, one feature at a time.
After each test, nothing must be left behind: the last command of each block
checks that.

Two shell helpers save typing; define them once per login:

```sh
dom()  { echo runphi-$(docker inspect -f '{{.Id}}' "$1" | cut -c1-24); }
qpid() { pgrep -f "qemu-system.*$(dom "$1")"; }
```

`dom g1` prints the libvirt domain of container `g1`, and `qpid g1` the PID
of its QEMU process.

### 5.1 A plain guest

The basics: runPHI turns the image into a virtual machine, Docker tracks it,
and removing the container removes the machine.

```sh
docker run -d --name g1 --runtime=runphi runphi-kvm-guest:initramfs
virsh list                         # runphi-<id> running
docker ps                          # g1 Up
grep -E 'Kernel command line|Memory:|Brought up' /var/log/libvirt/qemu/$(dom g1)-serial.log
virsh console $(dom g1)            # Enter, log in as root / root, leave with Ctrl+]
docker rm -f g1
virsh list --all; ls /run/runPHI   # both empty
```

The `grep` shows, from the guest kernel's boot messages, the command line
runPHI gave it (`console=ttyAMA0`) and the machine it got: 256 MB
(`Memory: …/262144K`) and 1 CPU.

### 5.2 Pinned vCPUs and networking

The `pinned-net` guest has 2 vCPUs pinned to CPUs 2 and 3, and QEMU's
user-mode network. `--cpuset-cpus 2,3` keeps all of QEMU on those CPUs too.

```sh
docker run -d --name g2 --runtime=runphi --cpuset-cpus 2,3 runphi-kvm-guest:pinned-net
virsh vcpuinfo $(dom g2) | grep -E '^VCPU|^CPU:'
ps -T -p $(qpid g2) -o tid,comm,psr,cls,rtprio | grep -E 'TID|CPU'
```

Expected:

```
  TID COMMAND         PSR CLS RTPRIO
 4452 CPU 0/KVM         2  FF     99
 4453 CPU 1/KVM         3  FF     99
```

`PSR` is the CPU the thread last ran on, `FF` is SCHED_FIFO. The cgroup of
QEMU is the container's: `grep cpuset /proc/$(qpid g2)/cgroup` shows
`/docker/<full id>`, and
`cat /sys/fs/cgroup/cpuset/docker/$(docker inspect -f '{{.Id}}' g2)/cpuset.cpus`
shows `2-3`.

The network: `grep lease /var/log/libvirt/qemu/$(dom g2)-serial.log` shows
the address the guest got from QEMU (`10.0.2.15`), and so does
`ip addr show eth0` in the guest (`virsh console`).

```sh
docker rm -f g2
virsh list --all; ls /run/runPHI
```

### 5.3 Root filesystem on LVM

The `lvm` image has no initramfs: runPHI copies the image's whole root
filesystem into a new logical volume, and the guest boots from it.

```sh
lvs test-vg                        # no volumes
docker run -d --name g3 --runtime=runphi runphi-kvm-guest:lvm
lvs test-vg                        # lv_<id>, about 150 MB
grep -E 'Kernel command line|EXT4-fs \(vda\)' /var/log/libvirt/qemu/$(dom g3)-serial.log
docker rm -f g3
lvs test-vg                        # the volume is gone
```

The serial log shows the command line `console=ttyAMA0 root=/dev/vda rw` and
the guest mounting `vda` as ext4.

### 5.4 IRQ steering

The `steer` image pins its vCPU to CPU 3 and asks for all host interrupts on
CPUs 0 and 1 while it runs. Removing it must put every affinity back exactly.

```sh
grep -H . /proc/irq/*/smp_affinity_list > /tmp/irq.before
docker run -d --name g4 --runtime=runphi runphi-kvm-guest:steer
grep -H . /proc/irq/*/smp_affinity_list | diff /tmp/irq.before - | grep '^+' | head
docker rm -f g4
grep -H . /proc/irq/*/smp_affinity_list | diff /tmp/irq.before - && echo restored
```

While `g4` runs, the diff lists the moved interrupts, now on `0-1`; at the end
it is empty and the last command prints `restored`.

### 5.5 An error

A container whose pinned CPUs are outside `--cpuset-cpus` cannot be created.
runPHI must say why and leave nothing behind.

```sh
docker run -d --name bad --runtime=runphi --cpuset-cpus 0,1 runphi-kvm-guest:pinned-net
```

Docker prints:

```
docker: Error response from daemon: failed to create shim task: OCI runtime create failed: cannot pin vCPU 0 (thread 3556) to CPU 2: EINVAL: Invalid argument: unknown.
```

```sh
grep -B2 'cannot pin' /usr/share/runPHI/log.txt | tail -3   # the same error in runPHI's log
docker rm bad
virsh list --all; ls /run/runPHI
```

### 5.6 Ordinary containers

An image without `/boot/config.json` goes to runc, even under
`--runtime=runphi`:

```sh
/root/adjust_time.sh
docker run --rm --runtime=runphi hello-world   # pulled from Docker Hub, prints "Hello from Docker!"
tail -2 /usr/share/runPHI/log.txt              # "Forwarding to runc id ..."
docker rmi hello-world
```

### 5.7 `runphi state`

```sh
docker run -d --name g5 --runtime=runphi runphi-kvm-guest:initramfs
runphi state $(docker inspect -f '{{.Id}}' g5)
docker rm -f g5
```

It prints the container's ID, the watcher's PID, the bundle and the root
filesystem. `status` is always `running` and `created` is the current time:
runPHI does not track either yet.

## 6. Building your own images

A runPHI image is a filesystem with `/boot/config.json` and the files it names.
Docker needs a command to create a container, so give the image a `CMD`
(`/bin/sh`), even though runPHI does not run it.

**On the board**, from a directory, with `docker import`:

```sh
mkdir -p /tmp/img/boot && cd /tmp/img
cp /root/guest/Image /root/guest/rootfs.cpio.gz boot/
vi boot/config.json
tar -c . | docker import --change 'CMD ["/bin/sh"]' - my-guest
docker run -d --name mine --runtime=runphi my-guest
```

For an `lvm` (or `file`) guest, the image is the guest's whole root
filesystem, plus the kernel and the configuration, without `ramdisk`:

```sh
mkdir /tmp/lvmimg && cd /tmp/lvmimg
zcat /root/guest/rootfs.cpio.gz | cpio -id
mkdir -p boot && cp /root/guest/Image boot/
cat > boot/config.json <<EOF
{ "os_var": "linux", "inmate": "/boot/Image", "disk_type": "lvm", "memory": 256 }
EOF
tar -c . | docker import --change 'CMD ["/bin/sh"]' - my-lvm-guest
```

**On the PC**, with a Dockerfile next to a `boot/` directory:

```dockerfile
FROM scratch
COPY boot/ /boot/
CMD ["/bin/sh"]
```

```sh
docker build --platform linux/arm64 -t my-guest .
docker save my-guest | ssh root@192.168.100.46 docker load
```

`--platform linux/arm64` only labels the image, since nothing runs during the
build. The board can also pull from a registry.

The kernel must be an arm64 `Image` that boots on QEMU's `virt` board, with
virtio (for disks and networks) and the PL011 console. The `kria-kvm`
kernel does, which is why the test images use it.

## 7. Looking at a running guest

| Command | Shows |
|---|---|
| `virsh list --all` | the runPHI domains (`runphi-<id>`) |
| `virsh dominfo $(dom <name>)` | state, vCPUs, memory |
| `virsh vcpuinfo $(dom <name>)` | each vCPU's current CPU and affinity |
| `virsh dumpxml $(dom <name>)` | the domain as libvirt runs it |
| `virsh console $(dom <name>)` | the guest console (Ctrl+] to leave) |
| `ps -T -p $(qpid <name>) -o tid,comm,psr,cls,rtprio` | QEMU's threads: vCPUs, their CPU and scheduling |
| `cat /proc/$(qpid <name>)/cgroup` | the cgroups QEMU is in |
| `runphi state <container id>` | runPHI's view of the container |

Files:

| File | Content |
|---|---|
| `/usr/share/runPHI/log.txt` | runPHI's log: every create, pin, cgroup and teardown step, and every error |
| `/run/runPHI/<id>/domain.xml` | the domain runPHI generated (while the container exists) |
| `/var/log/libvirt/qemu/runphi-<id>.log` | QEMU's command line and its errors |
| `/var/log/libvirt/qemu/runphi-<id>-serial.log` | everything the guest wrote on its console |

## 8. Troubleshooting

| Symptom | Cause |
|---|---|
| `OCI runtime create failed: cannot pin vCPU …: EINVAL` | a `pcpu` of `vcpu_pinning` is outside `--cpuset-cpus` |
| `unknown or invalid runtime name: runphi` | `/etc/docker/daemon.json` lacks the runtime, or `dockerd` was not restarted after it changed (`/etc/init.d/S60dockerd restart`) |
| `Cannot set scheduler parameters …: Operation not permitted` (from `virsh create`) | a kernel with `CONFIG_RT_GROUP_SCHED`: pinned vCPUs cannot get SCHED_FIFO. This environment's kernel has it off. |
| the container exits at once | the guest stopped: kernel panic, no root filesystem, or it powered off. Read the serial log, then the QEMU log. |
| the guest boots but prints nothing | the kernel has no PL011 driver or console, or `os_var` is not `"linux"` (no `console=ttyAMA0`) |
| LVM: not enough free space, or `test-vg` not found | `vgs`; the loop file is attached by `/etc/init.d/S29lvm-loop` and needs the SD card mounted on `/mnt/sd` |
| `docker pull`: `x509: certificate signed by unknown authority` | no CA certificates (they are in this environment's rootfs); if they were added while `dockerd` ran, restart it |
| `docker pull`: `x509: certificate has expired or is not yet valid` | the clock: run `/root/adjust_time.sh` |
| `docker` says only `did not terminate successfully` | a runPHI older than runphi_manager `5ced581`; the reason is in `/usr/share/runPHI/log.txt` |

If runPHI itself dies halfway, clean up by hand: `virsh destroy runphi-<id>`,
`rm -r /run/runPHI/<id>`, `lvremove -y test-vg/lv_<id>`, and `docker rm -f`
the container. A reboot also resets the IRQ affinities.

## 9. Updating runPHI on the board

The binary is built from runphi_manager with this environment's Buildroot
toolchain, as described in [SETUP.md](SETUP.md#runphi-backend_kvm), and
lives in the overlay at `install/usr/local/sbin/runphi`. A full rootfs update
brings it to the board; to replace only the binary on a running board, copy it
into the NFS root through the server (much faster than `scp` to the board),
then install it on the board:

```sh
# on the PC, in runphi_manager/rust_runphi
scp -P 19500 target/aarch64-unknown-linux-gnu/release/runphi root@192.168.100.45:/root/runphi/environment_builder/environment/kria/kvm/output/rootfs/kria/root/runphi.new
# on the board (wait about a minute for NFS to show the new file)
install -m 755 /root/runphi.new /usr/local/sbin/runphi && rm /root/runphi.new
install -m 755 /usr/local/sbin/runphi /mnt/sd/usr/local/sbin/runphi    # the SD system too
```

The last line applies when the board runs from NFS: `/mnt/sd` is then the SD
card's root filesystem, which the board boots in SD mode.

## 10. Limitations

- **GICv2.** Guests get the host's GICv2 (KVM cannot emulate a GICv3 on it):
  at most 8 vCPUs per guest, and no ITS.
- **nVHE.** The Cortex-A53 has no VHE, so every exit from the guest is a full
  switch between EL1 and EL2, slower than on newer ARM cores.
- **Bare-metal guests** (Zephyr and the like, `os_var` other than `"linux"`)
  are not tested on ARM yet. On the ZynqMP, the GIC CPU interface repeats
  every 64 KB, which matters to guests that use `GICC_DIR`; Linux guests do
  not (see [SETUP.md](SETUP.md#platform-constraints)).
- **No graceful shutdown.** `docker stop` destroys the guest; a shutdown
  inside the guest ends the container.
- **No console through Docker.** Use `virsh console` and the serial log.
- **`runphi state`** always reports `running`, with the current time as
  `created`.
- The guest RAM is locked in host RAM: the sum of the running guests' memory
  must fit in the board's 3.7 GB, next to the host.
