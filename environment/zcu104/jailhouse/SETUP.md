# ZCU104 Board Environment Setup Guide

For the SD-card setup (partitioning, copying `BOOT.BIN`, `Image`, `boot.scr`,
`system.dtb` and the rootfs) read [here](../../zcu102/jailhouse/SETUP.md).

---

## TFTP + NFS boot

The board can boot its kernel and device tree over TFTP and mount its root
filesystem over NFS, both served by **`192.168.100.45`**. SD-card boot remains
the default and the fallback; nothing below removes it.

### Topology

| | |
|---|---|
| board (`zcu104a`) | `192.168.100.47` |
| TFTP + NFS server | `192.168.100.45` (ssh on port **19500**) |
| gateway / netmask | `192.168.100.254` / `255.255.255.0` |

There is **no DHCP server** on this network, so the boot script assigns the
board a static address via the `ip=` kernel parameter.

### Server layout

The TFTP root is the clone's `tftpboot/` directory (`TFTP_DIRECTORY` in
`/etc/default/tftpd-hpa` on the server), which is exactly what `tftp_boot_dir`
in `scripts/common/set_environment.sh` resolves to. So
`scripts/compile/linux_compile.sh` run on the server drops `Image` straight into
the right place.

```
/root/runphi/environment_builder/
├── tftpboot/zcu104-jailhouse/                          <- Image, system.dtb  (TFTP)
└── environment/zcu104/jailhouse/output/rootfs/zcu104/  <- root filesystem    (NFS)
```

The NFS export lives in `/etc/exports` on the server:

```
/root/runphi/environment_builder/environment/zcu104/jailhouse/output/rootfs/zcu104 *(rw,sync,no_root_squash,no_subtree_check)
```

After changing it, run `exportfs -r`.

> [!IMPORTANT]
> Extract the root filesystem **as root** (e.g. `tar xf rootfs.tar` from
> `output/rootfs/`); do not rsync a tree that was checked out as a normal user.
> A user-owned copy loses `root:root` ownership and the setuid bit on
> `/bin/busybox`, which breaks `mount`, `umount` and `su` on the target.
> Overlay the built artefacts (`lib/modules`, `root/jailhouse`, `usr/local`,
> `etc/profile.d`, `root/scripts_jailhouse_zcu104`) on top with
> `rsync --chown=root:root`.

### Boot scripts

`boot_sources/boot_tftp.cmd` fetches the kernel and DTB over TFTP and boots with
an NFS root. If either transfer fails it **falls back to the SD card**, so a
network outage does not leave the board unbootable.

Build it with `scripts/compile/bootscr_compile.sh` after setting
`BOOTCMD_CONFIG="tftp"` in `environment_cfgs/zcu104-jailhouse.sh`.

> [!NOTE]
> `bootscr_compile.sh` always writes `${boot_dir}/boot.scr`. To keep both
> variants, build the TFTP one first and rename the result to `boot_tftp.scr`,
> then set `BOOTCMD_CONFIG` back to `"jailhouse"` and rebuild to regenerate the
> SD `boot.scr`.

### Docker needs a local filesystem

`dockerd` cannot start with `/var/lib/docker` on NFS. Its `overlay2` driver
needs an upper directory that supports whiteouts and xattrs, which NFS does not:

```
overlayfs: upper fs does not support RENAME_WHITEOUT.
overlayfs: failed to set xattr on upper
overlayfs: upper fs missing required features.
```

The fix — the same one `zcu104b` (`192.168.100.52`, the Xen board) already uses —
is to keep docker's storage on the SD card's ext4 partition. Note that board is
*not* running docker on NFS either: only its root filesystem is NFS, while
`docker info` there reports `Backing Filesystem: extfs`.

In the NFS rootfs `/etc/fstab`:

```
/dev/mmcblk0p2	/mnt/docker	ext4	defaults,user_xattr	0	2
```

and in `/etc/docker/daemon.json`:

```json
{
  "data-root": "/mnt/docker/var/lib/docker"
}
```

The SD partition still holds the original store, so all images survive the
switch. (`zcu104b` points `data-root` at `/mnt/docker` directly because its SD
partition is dedicated to docker; here the partition is the old SD rootfs, so
the path keeps its existing `var/lib/docker` subdirectory.)

Verify with:

```sh
docker info | grep -iE "storage driver|backing filesystem|docker root dir"
docker run --rm alpine echo works
```

Do not "fix" this by switching to the `vfs` storage driver. It does work on NFS,
but it is drastically slower and copies whole image layers instead of sharing
them. No kernel option changes this — overlay2 needs a local upper filesystem.

### Switching between SD and network boot

Both scripts live on the boot partition. **The board currently boots over
TFTP/NFS**: `boot.scr` is the TFTP variant and `boot.scr.sd` is the SD one.

To go back to SD boot:

```sh
mount -o remount,rw /boot/firmware
cp /boot/firmware/boot.scr.sd /boot/firmware/boot.scr
sync
mount -o remount,ro /boot/firmware
reboot
```

To switch to network boot from an SD-booted system, copy `boot_tftp.scr` over
`boot.scr` the same way (keeping a copy of the SD one first).

> [!WARNING]
> Always leave `/boot/firmware` mounted **read-only**. An unclean shutdown with
> it writable corrupts `BOOT.BIN` / `Image` / `boot.scr` and the board will not
> boot. Recovery copies already on the boot partition: `Image.bak`,
> `Image.prepreempt.bak`, `boot.scr.bak`, `boot.scr.prepreempt.bak`.

### Verifying without rebooting

TFTP, from the board:

```sh
tftp -g -r zcu104-jailhouse/system.dtb -l /tmp/dtb.tftp 192.168.100.45
md5sum /tmp/dtb.tftp /boot/firmware/system.dtb    # should match
```

NFS, from the server:

```sh
showmount -e 192.168.100.45
mount -t nfs -o vers=3,ro 192.168.100.45:<export path> /mnt/test && ls /mnt/test
```

Mounting the export **from the board** fails with
`bad option; ... you might need a /sbin/mount.<type> helper program`, because the
buildroot rootfs has no `nfs-utils`. That does not affect NFS-root boot, which
the kernel performs itself via `CONFIG_ROOT_NFS`; it only prevents userspace
`mount -t nfs`.

### Kernel requirements

Already satisfied by `jailhouse_zcu104_kernel_defconfig`, but if you rebuild
with a different config, NFS root needs all of these built in (`=y`, not `=m`):

```
CONFIG_NFS_FS  CONFIG_NFS_V3  CONFIG_ROOT_NFS  CONFIG_IP_PNP  CONFIG_MACB
```

---

## MAC addresses with more than one board

Every ZCU104 running these images comes up with the same MAC address,
`00:0a:35:00:22:01` (the Xilinx default). With a single board that is fine.
With two or more boards on the same L2 segment, the switch can only keep one
forwarding entry for that MAC. It points that entry at whichever board sent a
frame most recently and drops traffic meant for the others. The symptom is SSH
sessions that hang and then resume, worst when you use several boards at once,
and `ping` showing one board up and another 100% lost, alternating between them.

To check, run this from any host on the same network for each board:

```sh
arping -c 2 -I <iface> <board-ip>
```

If two boards report the same MAC, they collide.

### Where the MAC comes from

The MAC does not come from the device tree. At boot, U-Boot's `fdt_fixup_ethernet()`
rewrites the `local-mac-address` property of the node aliased as `ethernet0`,
using its saved `ethaddr` environment variable. It does this on whichever DTB it
loaded, from SD or TFTP. So `ethaddr` in the U-Boot environment takes priority
over the `local-mac-address` in `boot_sources/*.dts`, and editing the DTS changes
nothing.

This U-Boot is built without `CONFIG_ENV_OVERWRITE`, so you cannot change `ethaddr`
from the U-Boot prompt either:

```
setenv ethaddr <new-mac>    ## Error: Can't overwrite "ethaddr"
env delete ethaddr          ## Error: Can't delete "ethaddr"
```

### Giving a board its own MAC

The environment is a plain file, `uboot-redund.env`, on the FAT boot partition
(`/boot/firmware` on the target). It starts with a little-endian CRC32 covering
everything from byte 5 onwards, then a one-byte flags field, then NUL-separated
`key=value` entries. If you patch the file offline, U-Boot loads the new value at
startup. The overwrite protection only blocks changes made at runtime.

Use a locally administered address, meaning the first octet has bit 1 set, for
example `02:...`. That way it cannot clash with a real vendor's OUI. Keep it the
same length as the original so nothing else in the file moves:

```python
import zlib, struct
NEW_MAC = b"02:0a:35:00:22:02"   # pick a different one for each board
d = bytearray(open("uboot-redund.env", "rb").read())
assert struct.unpack("<I", d[:4])[0] == zlib.crc32(bytes(d[5:])) & 0xffffffff
old = b"ethaddr=00:0a:35:00:22:01"
new = b"ethaddr=" + NEW_MAC
assert len(old) == len(new) and d.count(old) == 1
i = d.index(old)
d[i:i + len(old)] = new
d[0:4] = struct.pack("<I", zlib.crc32(bytes(d[5:])) & 0xffffffff)
open("uboot-redund.env.new", "wb").write(bytes(d))
```

The first `assert` checks that the CRC layout above matches your file before
anything changes. Next, copy the result into place on the target. Keep a backup
and remount the partition read-only straight after: an unclean shutdown while it
is writable corrupts `BOOT.BIN`/`Image`/`boot.scr`.

```sh
mount -o remount,rw /boot/firmware
cp /boot/firmware/uboot-redund.env /boot/firmware/uboot-redund.env.bak
# ... write the new file, check its md5 ...
sync
mount -o remount,ro /boot/firmware
```

Reboot, then confirm with `ifconfig eth0` on the board or `arping` from another
host. On the next boot U-Boot prints
`Warning: ethernet@ff0e0000 MAC addresses don't match:`. You can ignore it. U-Boot
is comparing `ethaddr` with the MAC in its own built-in control device tree, and
it uses `ethaddr`.

> [!NOTE]
> A broken environment does not stop the board from booting. U-Boot falls back to
> its built-in default environment, which still finds `boot.scr` on the SD card.
> Keep a serial console attached (UART0, 115200 8N1) while doing this, so you can
> recover if the board does not come back on the network.
