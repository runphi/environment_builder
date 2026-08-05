# Handoff: ZCU104 Jailhouse kernel rebuild + TFTP/NFS boot

Two tasks, in this order:

1. **Rebuild the ZCU104 Jailhouse kernel with `PREEMPT_RT`** — the current one is
   `PREEMPT_NONE` and it wedges the board under load. Root cause is diagnosed and
   the fix is a one-line config change; details below.
2. **Set up TFTP + NFS boot for `zcu104/jailhouse`**, modelled on the existing
   `zcu104/xen` setup.

**Please use the environment builder's own scripts wherever possible**
(`scripts/build_environment.sh`, `scripts/compile/*.sh`,
`scripts/defconfigs/*.sh`) rather than hand-rolling build steps or editing
generated artefacts.

If anything here is unclear or you need information I have not provided, **ask
the user** rather than guessing — several plausible-looking assumptions have
already cost days on this problem.

---

## 1. Context: what the experiment is

We benchmark the TACLeBench suite running **bare-metal in a Jailhouse non-root
cell** on APU core 3 of a ZCU104, while `stress-ng` generates interference from
the **root cell** (Linux) on cores 0-2. The point is to quantify how much a
co-located Linux workload perturbs an isolated bare-metal partition.

The harness lives in a *different* repo — `runphi_testing/tacle-bench-jailhouse-APU-baremetal/`
— and has its own README. You should not need to touch it. It is mentioned only
so you know what is driving the board.

The same campaign ran to completion on a **Kria KV260** (same MPSoC, marginally
higher A53 clock, same software stack: Jailhouse, stress-ng, TACLeBench) with
**8 stressor workers** and no trouble at all.

On the ZCU104 the campaign is **stuck at 3 of 6 configurations**:

| configuration | state |
|---|---|
| `baseline`, `fork4`, `open4` | complete, 52/52 benchmarks |
| `cpu4`, `udp4`, `memcpy4` | **cannot complete** — board wedges within minutes |

---

## 2. The problem, and the evidence

### Symptom

A few minutes into any configuration whose stressor **saturates the CPUs**, the
board wedges. Sometimes ssh dies with a banner-exchange timeout while the console
still prints; sometimes the console goes instantly silent. Recovery needs a power
cycle. The console shows no panic and no self-detected RCU stall, only:

```
rcu: rcu_sched kthread timer wakeup didn't happen for 5254 jiffies! RCU_GP_WAIT_FQS(5)
rcu: 	Possible timer handling issue on cpu=2 timer-softirq=91070
rcu: rcu_sched kthread starved for 5260 jiffies! ... ->cpu=2
task:stress-ng-cpu   state:R  running task
```

`rcu_sched` is **asleep in `schedule_timeout()` and its wakeup timer never
fired**. It is *not* a runnable task being denied CPU — this matters, see
"what does not work" below.

### Root cause

The KV260 ran a **`PREEMPT_RT`** kernel. The ZCU104 is running
**`CONFIG_PREEMPT_NONE`** — verified on the live board via `/proc/config.gz`, not
just inferred from the build tree.

| | KV260 (worked, 8 workers) | ZCU104 (as built) |
|---|---|---|
| preemption | `CONFIG_PREEMPT_RT=y` | **`CONFIG_PREEMPT_NONE=y`** |
| tick rate | `CONFIG_HZ_1000` | `CONFIG_HZ=250` |
| `CONFIG_NO_HZ_FULL` | `=y` | not set |
| `CONFIG_RCU_NOCB_CPU` | selected by `NO_HZ_FULL` | not set |

Under `PREEMPT_NONE` the kernel is never preempted, and RCU grace periods advance
only through quiescent states (context switch, userspace, idle). A CPU inside a
long non-preemptible section delays its own timer softirq — exactly the "Possible
timer handling issue" the kernel reports. Jailhouse makes it acute because cell
operations suspend and re-synchronise **every root CPU at once**.

This predicts the observed split precisely:

| configuration | stressor behaviour | result |
|---|---|---|
| `fork4`, `open4` | block on syscalls constantly → plenty of quiescent states | **52/52** |
| `cpu4`, `udp4`, `memcpy4` | compute-bound, almost never yield | **all wedge** |

### Why it happened — the actual bug in the config

`scripts/common/set_environment.sh:164` builds the defconfig name as:

```sh
defconfig_linux_name=${BACKEND}_${TARGET}_${LINUX_CONFIG}_kernel_defconfig   # if LINUX_CONFIG set
defconfig_linux_name=${BACKEND}_${TARGET}_kernel_defconfig                   # if empty
```

And the two board configs differ in exactly one line:

| file | `LINUX_CONFIG` | resulting defconfig | preemption |
|---|---|---|---|
| `environment_cfgs/kria-jailhouse.sh` | `"isolcpu"` | `jailhouse_kria_isolcpu_kernel_defconfig` | **`PREEMPT_RT=y`** |
| `environment_cfgs/zcu104-jailhouse.sh` | **`""`** | `jailhouse_zcu104_kernel_defconfig` | **none set → `PREEMPT_NONE`** |

Note that *every* KV260 jailhouse defconfig sets `PREEMPT_RT`, including the
plain one — so on that board the empty-vs-set distinction never mattered. On the
ZCU104 it does. The board is not even running its own intended configuration:
`jailhouse_zcu104_isol_kernel_defconfig` **already specifies `CONFIG_PREEMPT_RT=y`**.

The two `isol` defconfigs differ by only 14 lines; the significant ones are
`CONFIG_HZ_1000` and `CONFIG_NO_HZ_FULL`, present on the KV260 only.

### What does NOT fix it — do not re-try these

All measured on the board, all insufficient:

- **`rcutree.kthread_prio=1`, and `chrt -f -p 1` on `rcu_sched`.** Priority cannot
  help a task sleeping on a timer that is not being delivered.
- **`nice -n 19` on the stressors.** Cannot make a non-preemptible kernel section
  yield.
- **Avoiding CPU hotplug** (reusing the cell instead of create/destroy per
  iteration). Cut hotplugs from 1612 per configuration to 1; board still wedged.
- **Pausing the stressors around Jailhouse cell operations.** Helped marginally
  (`cpu4` reached 10/52 instead of 6/52), still wedged.
- **Reducing workers 8 → 4.** Did not fix it, and going lower (2) would stop
  saturating the cores, i.e. buy stability by weakening the interference we are
  trying to measure.

Also ruled out: **thermal** (the `xilinx-ams` sensor reads ~44 °C under full load
— `/sys/bus/iio/devices/iio:device0/in_temp8_input`, millidegrees) and
**hardware** (the board survives 8 min of the identical stressor with Jailhouse
not even loaded).

Isolation matrix — the failure needs the hypervisor **and** the inmate **and** a
saturating stressor:

| | |
|---|---|
| stressor alone, no Jailhouse | survives 8 min |
| Jailhouse root cell + stressor, no inmate | survives 7 min |
| inmate cycling, no stressor (`baseline`) | survives, 52/52 |
| inmate cycling + stressor | **dies in ~4 min** |

> **Confidence:** the `PREEMPT_NONE` finding is solid and verified on the live
> kernel. That `PREEMPT_RT` *will* fix the wedge is a strong inference — it is the
> configuration under which this exact campaign demonstrably ran at 8 workers —
> but it has not been proven on this board yet. Rebuild, then retest before
> declaring victory.

---

## 3. Task 1 — rebuild the kernel with PREEMPT_RT

### Minimum change

In `environment_cfgs/zcu104-jailhouse.sh`:

```sh
LINUX_CONFIG="isol"        # was "" -> selects jailhouse_zcu104_isol_kernel_defconfig
```

### Preferred: match the KV260 fully

Also add to
`environment/zcu104/jailhouse/custom_build/linux/arch/arm64/configs/jailhouse_zcu104_isol_kernel_defconfig`:

```
CONFIG_HZ_1000=y
CONFIG_NO_HZ_FULL=y
```

(`NO_HZ_FULL` selects `RCU_NOCB_CPU`, which is what makes the KV260's
`rcu_nocbs=` / `rcu_nocb_poll` cmdline parameters meaningful. Without it they are
silently ignored.) Use `scripts/defconfigs/linux_update_defconfigs.sh` /
`linux_save_defconfigs.sh` rather than hand-editing generated `.config` files.

Note `environment_cfgs/zcu104-jailhouse.sh` also has a commented `#preempt_rt` in
`LINUX_PATCH_ARGS`; the KV260 has it commented too and gets RT purely from the
defconfig, so a patch should not be needed. Confirm rather than assume.

### Boot command line

Current (in `environment/zcu104/jailhouse/boot_sources/boot_jailhouse.cmd`):

```
isolcpus=domain,managed_irq,3 rcutree.kthread_prio=1 skew_tick=1 deferred_probe_timeout=1 earlycon clk_ignore_unused root=/dev/mmcblk0p2 rw rootwait
```

KV260 reference (`environment/kria/jailhouse/boot_sources/boot_isolcpu.cmd`):

```
isolcpus=nohz,domain,managed_irq,2-3 skew_tick=1 nosoftlockup nowatchdog nohz_full=2-3 rcu_nocbs=2-3 rcu_nocb_poll processor.max_cstate=0 processor_idle.max_cstate=0 earlycon clk_ignore_unused earlyprintk root=/dev/mmcblk1p2 rw rootwait
```

Mirror it, but **adapted for this board — do not copy verbatim**:

- **CPU 3 only.** The inmate cell (`zynqmp-zcu104-APU-inmate-demo.cell`) uses APU
  core 3, and the root cell needs 0-2 for the stressors. So `,3` and
  `nohz_full=3 rcu_nocbs=3`, not `2-3`. Isolating CPU 2 as well would leave only
  two interfering cores and change the experiment.
- **`isolcpus=nohz,...` is a trap.** If `CONFIG_NO_HZ_FULL` is off, the kernel
  rejects the *entire* `isolcpus` parameter and silently isolates nothing (it
  appears under "Unknown kernel command line parameters"). This already bit us
  once. Only use the `nohz,` prefix if you actually enabled `NO_HZ_FULL`.
- `processor.max_cstate` / `processor_idle.max_cstate` are **x86-only no-ops** —
  drop them.
- `root=` differs: ZCU104 is `/dev/mmcblk0p2`, KV260 is `mmcblk1p2`. Keep the
  ZCU104 value (or the NFS root, for task 2).
- `deferred_probe_timeout=1` is a ZCU104-specific fix for a dead i2c mux that
  otherwise adds ~10 s to boot. Keep it.
- `rcutree.kthread_prio=1` can stay or go; it is harmless but does not fix
  anything.

### Deploying boot.scr by hand (if not using the scripts)

`/boot/firmware/boot.scr` is a U-Boot script image. Prefer
`scripts/compile/bootscr_compile.sh`. Manually it is:

```sh
mkimage -A arm64 -O linux -T script -C gzip -a 0 -e 0 -n "" -d boot_jailhouse.cmd boot.scr
```

On the board the boot partition **must be remounted `ro` afterwards** — left
writable, an unclean shutdown corrupts `BOOT.BIN`/`Image`/`boot.scr` and the
board will not boot:

```sh
mount -o remount,rw /boot/firmware
cp boot.scr /boot/firmware/boot.scr && sync
mount -o remount,ro /boot/firmware
# verify what actually landed:
dd if=/boot/firmware/boot.scr bs=1 skip=72 2>/dev/null | grep -o 'isolcpus=[^"]*'
```

Existing backups on the board: `/root/boot.scr.isolcpus2-3.bak`,
`/root/boot.scr.isolcpus3`, and `/boot/firmware/boot.scr.bak`.
On this host: `boot_jailhouse.cmd.isolcpus2-3.bak` and `.pre-rcuprio.bak`.

### Verification after reboot

```sh
cat /proc/cmdline
zcat /proc/config.gz | grep -E "PREEMPT|NO_HZ|CONFIG_HZ=|RCU_NOCB"   # want PREEMPT_RT=y
uname -a                                                             # should show PREEMPT_RT
cat /sys/devices/system/cpu/isolated                                 # want 3
dmesg | grep -iA3 "Unknown kernel command line parameters"           # want nothing
```

Then the real test — ask the user to re-run the blocked configurations. The
failure reproduces in **2-6 minutes** with `cpu4`, so a 20-minute clean run is
strong evidence.

---

## 4. Task 2 — TFTP + NFS boot for zcu104/jailhouse

Model it on the working **`environment/zcu104/xen`** setup, which already has:

- `boot_sources/boot_tftp.cmd`, `boot_tftp_xen.cmd`, and a `boot.cmd` with
  TFTP/NFS branches
- `tftpboot/zcu104-xen/` on the builder host

There is already a `tftpboot/zcu104-jailhouse/` directory here to populate.
For reference, `environment/kria/jailhouse/boot_sources/` has NFS variants —
`boot_nfs.cmd` and `boot_nfs_isolcpu.cmd` — showing the NFS root form used for a
jailhouse backend:

```
root=/dev/nfs nfsroot=/tftpboot/%s,vers=3,sec=sys ip=dhcp rw rootwait nfsrootdebug
```

**The TFTP and NFS servers must live on `192.168.100.45`**, not on this
workstation. See the topology below.

Keep the SD-card boot path working as a fallback — the board must remain
bootable if the network path fails, since recovering it otherwise means serial
plus a power cycle.

---

## 5. Machines, access, and the push/pull rule

| host | role |
|---|---|
| this workstation | primary `environment_builder` clone (`/home/boccolarg/runphi/environment_builder`), cross-toolchain, builds |
| **`192.168.100.45`** | lab console host; **TFTP + NFS server**; clone at **`/root/runphi/environment_builder`**. ssh on **port 19500**, user `root` |
| **`192.168.100.47`** | the board, `zcu104a`, user `root` / password `root` |

### Order of operations — important

1. Commit and push the changes we want to keep **from this workstation** to
   `origin` (`https://github.com/runphi/environment_builder.git`, branch `main`).
2. **Then `git pull` on `192.168.100.45`** in `/root/runphi/environment_builder`
   before doing any work there.

Do not start editing on `.45` first; its clone is behind.

Uncommitted here right now (review with `git status` and commit deliberately —
this is *not* a blanket "commit everything" instruction):

- `environment_cfgs/zcu104-jailhouse.sh` *(this is where the `LINUX_CONFIG` fix goes)*
- `environment/zcu104/jailhouse/boot_sources/boot_jailhouse.cmd` **(untracked)** — the current working cmdline
- `boot_jailhouse.cmd.isolcpus2-3.bak`, `boot_jailhouse.cmd.pre-rcuprio.bak` **(untracked)** — revert points
- `environment/zcu104/jailhouse/DEMO.md` **(untracked)** — how to run cells on this board
- `scripts/compile/jailhouse_compile.sh`, `scripts/common/set_environment.sh`, `scripts/common/current_environment.sh`
- `environment/zcu104/jailhouse/install/root/scripts_jailhouse_zcu104/jailhouse_setup/jailhouse_start.sh`
- various `output/boot/` binaries — check whether these belong in git before committing

⚠️ There is an untracked **`.bashrc` in the repo root** — almost certainly should
not be committed. Check with the user.

### Board access notes (these have cost time before)

- **`scp` needs `-O`** — the board has no `sftp-server`.
- **Power cycling: `tapo … reset` is NOT enough.** Use explicit off, wait ~12 s,
  then on. Credentials are `TAPO_*` in `/root/.bashrc` on `.45` and are **not**
  loaded by a non-interactive ssh:
  ```sh
  ssh -p 19500 root@192.168.100.45 'bash -s' <<'EOF'
  eval "$(grep -E '^[[:space:]]*(export[[:space:]]+)?TAPO_(USERNAME|PASSWORD|P300_IPS)=' /root/.bashrc)"
  export TAPO_USERNAME TAPO_PASSWORD TAPO_P300_IPS
  /tools/tapo/tapo_control.py zcu104a off; sleep 12; /tools/tapo/tapo_control.py zcu104a on
  EOF
  ```
- **Serial** on `.45`: `/dev/zcu104a-01` = Linux console + hypervisor log,
  `/dev/zcu104a-02` = inmate cell console. `picocom -b 115200`.
  A background capture holds the tty exclusively — kill it
  (`pkill -f "cat /dev/zcu104a-01"`) before attaching, or you will see nothing
  and think the board is dead. Capture to `/root/zcu104a_logs/`, **not `/tmp`**,
  which that host clears.
- The board's **RTC drifts and has jumped backwards**; run `hwclock -w` after
  setting the time, and do not trust file mtimes for forensics.
- The board's busybox has **no `timeout`, `pgrep` or `taskset`**.
- After every reboot, before benchmarking: `/root/max_perf.sh` (cpufreq resets;
  only the `userspace` governor exists) and unbind the EDAC poller:
  `echo edac > /sys/bus/platform/drivers/cortex_edac/unbind` (a separate,
  already-fixed deadlock — its 100 ms per-CPU IPI poll hangs against Jailhouse
  CPU handover).

---

## 6. Definition of done

- [ ] Changes from this workstation committed and pushed; `.45` clone pulled.
- [ ] ZCU104 Jailhouse kernel builds with `CONFIG_PREEMPT_RT=y` via the
      environment builder scripts, confirmed on the booted board through
      `/proc/config.gz`.
- [ ] Board boots, Jailhouse root cell starts, an inmate cell can be created and
      run.
- [ ] `cpu4` runs clean for ≥20 minutes where it previously died in 2-6 min.
- [ ] TFTP + NFS boot works for `zcu104/jailhouse` from `192.168.100.45`, with
      SD-card boot retained as a fallback.
- [ ] If `PREEMPT_RT` alone does not fix the wedge, report back with the console
      trace before trying further workarounds — the list in §2 is already
      exhausted.
