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
