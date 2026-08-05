# Run demos

## Start the Jailhouse hypervisor (with Omnivisor)

Run the script available in the `/root` directory:
```sh
./scripts_jailhouse_zcu104/jailhouse_setup/jailhouse_start.sh
```

With no arguments this uses `zynqmp-zcu104-omnv.cell`: the Omnivisor root cell
**without** cache colouring. That is the combination verified working on this
board. `-o`/`--omnv` is accepted as a synonym and selects the same cell.

> [!WARNING]
> Do not use `-c`/`--col`. The cache-colouring root cells
> (`zynqmp-zcu104-root-col.cell`, `zynqmp-zcu104-root-col-omnv.cell`) leave part
> of root Linux's RAM read-only in stage-2. Random pages then fault on write:
> ```
> Unable to handle kernel write to read-only memory at ffffff800a50c000
> Internal error: Oops: 000000009600004f
> ```
> `ESR 0x9600004f` = data abort, write, permission fault at level 3. In practice
> processes start dying inside `execve`, so `ssh` stops working even though the
> network is still up. Fix the colouring configuration before using these.

Verify the resources available to the rootcell:
```sh
jailhouse cell list
```

The expected output is:
```sh
ID      Name                    State             Assigned CPUs           Assigned rCPUs          Assigned FPGA regions   Failed CPUs
0       ZynqMP-ZCU104           running           0-3                     0-1                     0
```


## Start a VM (cell) on an APU core

### The provided demo

```sh
./scripts_jailhouse_zcu104/demos/bm_demo.sh APU gic
```

or, equivalently, by hand:

```sh
jailhouse cell create ${JAILHOUSE_DIR}/configs/arm64/zynqmp-zcu104-APU-inmate-demo.cell
jailhouse cell load   inmate-demo-APU ${JAILHOUSE_DIR}/inmates/demos/arm64/gic-demo.bin
jailhouse cell start  inmate-demo-APU
```

`jailhouse cell list` should then show CPU 3 moved out of the root cell:
```sh
ID      Name                    State             Assigned CPUs           Assigned rCPUs          Assigned FPGA regions   Failed CPUs
0       ZynqMP-ZCU104           running           0-2                     0-1                     0
1       inmate-demo-APU         running           3
```

The expected output (on the inmate console, see [Watching the output](#watching-the-output)):
```sh
Initializing the GIC...
Initializing the timer...
Timer fired, jitter:   1639 ns, min:   1639 ns, max:   1639 ns
Timer fired, jitter:   1059 ns, min:   1059 ns, max:   1639 ns
Timer fired, jitter:    849 ns, min:    849 ns, max:   1639 ns
Timer fired, jitter:    839 ns, min:    839 ns, max:   1639 ns
...
```

To stop the VM and give CPU 3 back to Linux:
```sh
jailhouse cell destroy inmate-demo-APU
```


### What the APU cell gives the inmate

`zynqmp-zcu104-APU-inmate-demo.cell` is defined in
`custom_build/jailhouse/configs/arm64/zynqmp-zcu104-APU-inmate-demo.c`:

| | |
|---|---|
| cell name | `inmate-demo-APU` |
| CPU | 3 — held out of the Linux scheduler by `isolcpus=domain,managed_irq,2-3` |
| RAM | phys `0x3ae00000`, **virt `0`**, 32 MB, loadable |
| console | UART1 `0xff010000` |
| comm region | virt `0x80000000` |
| ivshmem | none (`num_pci_devices = 0`) |

The RAM lives inside the `rproc@3ad00000` reservation of `system_jailhouse.dts`
(`0x3ad00000..0x3ecfffff`, 64 MB, `no-map`), so Linux never maps those pages.
The `rproc@3ed00000` block is deliberately left alone: the Omnivisor root cell
uses `0x3ed00000` and `0x3ed40000` for RPU firmware.

> [!NOTE]
> Use this cell rather than the legacy `zynqmp-zcu104-inmate-demo.cell`. The
> latter declares an ivshmem device with `.domain = 1`, `.bdf = 1 << 3` and
> `.shmem_dev_id = 0`, all identical to the root cell's first ivshmem endpoint,
> so `cell create` fails with `ivshmem.c: returning error -EBUSY`. It also
> declares `mem_regions[7]` while initialising only 3 of them, with
> `.shmem_regions_start = 0` pointing at the UART region instead of a shared
> memory block.


## Running your own APU binary

### Commands

```sh
. /etc/profile.d/jailhouse_path.sh

jailhouse cell create ${JAILHOUSE_DIR}/configs/arm64/zynqmp-zcu104-APU-inmate-demo.cell
jailhouse cell load   inmate-demo-APU /root/my-workload.bin
jailhouse cell start  inmate-demo-APU
```

`load` places the image at offset 0 of the first loadable region. To put it
somewhere else, or to load several images at once:

```sh
jailhouse cell load inmate-demo-APU boot.bin -a 0 payload.bin -a 0x100000
```

To swap the payload without recreating the cell:
```sh
jailhouse cell shutdown inmate-demo-APU
jailhouse cell load     inmate-demo-APU /root/my-workload-v2.bin
jailhouse cell start    inmate-demo-APU
```

`destroy` is only needed when the cell *configuration* itself changes:
```sh
jailhouse cell destroy inmate-demo-APU
```

### What the binary must be

The AArch64 inmate linker script (`inmates/lib/arm64/inmate.lds`) starts at
`. = 0x0` with `.boot` first, and the cell's RAM region has `virt_start = 0`.
So the image must be:

- a **raw binary, not an ELF** — `aarch64-linux-gnu-objcopy -O binary foo.elf foo.bin`
- **linked at address 0**, with the entry point at offset 0
- AArch64 bare metal
- no larger than 32 MB (the size of the loadable region)

### Building it inside the Jailhouse framework

The simplest route is to let Jailhouse link it for you — you then get the
linker script and `libinmate` (printk, timer and GIC helpers) for free. Add the
object to `INMATES` in `inmates/demos/arm64/Makefile`:

```make
INMATES += my-workload.bin
my-workload-y := ../arm/my-workload.o
```

To make that survive a rebuild of the environment, put the sources in
`environment/zcu104/jailhouse/custom_build/jailhouse/inmates/demos/`.
`scripts/compile/jailhouse_compile.sh` copies that directory over the build
tree before every build (and tolerates it being absent).

### Validate the configuration before touching the board

`config check` compares a cell config against the root cell config and reports
conflicts offline — this catches resource collisions such as the ivshmem clash
described above:

```sh
jailhouse config check ${JAILHOUSE_DIR}/configs/arm64/zynqmp-zcu104-omnv.cell \
                       ${JAILHOUSE_DIR}/configs/arm64/zynqmp-zcu104-APU-inmate-demo.cell
```

### Watching the output

The inmate writes straight to UART1, which is a **different channel from the
Linux console**. The ZCU104 exposes four UART channels through its USB bridge;
on the lab console host the mapping is:

| channel | carries |
|---|---|
| `/dev/zcu104a-01` | Linux console + Jailhouse hypervisor log (UART0, `0xff000000`) |
| `/dev/zcu104a-02` | **inmate cell console** (UART1, `0xff010000`) |

```sh
picocom -b 115200 /dev/zcu104a-02
```

Note that `jailhouse console -f` shows the *hypervisor's* log, not the inmate's.

## Cell statistics

`jailhouse cell stats` does **not** work on this rootfs:

```sh
ModuleNotFoundError: No module named 'curses'
```

The buildroot image ships Python without curses (`BR2_PACKAGE_PYTHON3_CURSES`
is not set, and the ncurses headers are absent from staging), so the upstream
tool cannot draw its live screen. The counters themselves are ordinary sysfs
files, so use the plain-text reader instead:

```sh
./scripts_jailhouse_zcu104/jailhouse_setup/cell_stats.sh              # all cells
./scripts_jailhouse_zcu104/jailhouse_setup/cell_stats.sh -c inmate-demo-APU -p
./scripts_jailhouse_zcu104/jailhouse_setup/cell_stats.sh -c inmate-demo-APU -i 2
```

`-p` adds the per-CPU breakdown and `-i N` repeats every N seconds showing the
delta, which is the part `jailhouse cell stats` used curses for:

```sh
cell 1  "inmate-demo-APU"  state=running  cpus=3
  vmexits_total                   311  (+20)
  vmexits_virt_irq                307  (+20)
```

Or read the raw values directly:

```sh
grep . /sys/devices/jailhouse/cells/1/statistics/*
```

`jailhouse cell list` is unaffected.
