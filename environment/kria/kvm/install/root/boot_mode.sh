#!/bin/sh
#
# boot_mode.sh - choose how the Kria boots next time
#
#   boot_mode.sh              show the boot mode and where / comes from now
#   boot_mode.sh sd [-r]      kernel, DTB and rootfs from the SD card
#   boot_mode.sh tftp [-r]    kernel and DTB over TFTP, rootfs over NFS from
#                             192.168.100.45 (falls back to the SD card)
#   -r                        reboot right after switching
#
# U-Boot's distro boot runs boot.scr from the FAT partition of the SD card.
# Both variants are kept next to it, as boot_sd.scr and boot_tftp.scr, and
# switching copies one of them over boot.scr. Works from either boot mode.
# The SD and NFS root filesystems are separate copies: what changes in one
# does not appear in the other.

BOOT_PART=/dev/mmcblk1p1

usage() {
	sed -n '4,9s/^# //p' "$0"
	exit 1
}

MODE=""
REBOOT=0
for arg in "$@"; do
	case "$arg" in
	sd | tftp) MODE="$arg" ;;
	-r) REBOOT=1 ;;
	*) usage ;;
	esac
done
[ "$REBOOT" -eq 1 ] && [ -z "$MODE" ] && usage

# Use the boot partition where it is mounted, or mount it for the duration
MNT=$(awk -v d="$BOOT_PART" '$1 == d { print $2; exit }' /proc/mounts)
if [ -z "$MNT" ]; then
	MNT=/tmp/boot_mode.$$
	mkdir -p "$MNT" && mount "$BOOT_PART" "$MNT" || {
		echo "ERROR: cannot mount $BOOT_PART"
		exit 1
	}
	trap 'umount "$MNT" && rmdir "$MNT"' EXIT
fi

next_mode() {
	for m in sd tftp; do
		if cmp -s "$MNT/boot.scr" "$MNT/boot_$m.scr"; then
			echo "$m"
			return
		fi
	done
	echo "unknown (boot.scr matches neither boot_sd.scr nor boot_tftp.scr)"
}

running_from() {
	if awk '$2 == "/" && $3 == "nfs" { found = 1 } END { exit !found }' /proc/mounts; then
		echo "NFS (tftp mode)"
	else
		echo "SD card (sd mode)"
	fi
}

if [ -n "$MODE" ]; then
	if [ ! -f "$MNT/boot_$MODE.scr" ]; then
		echo "ERROR: $MNT/boot_$MODE.scr not found"
		exit 1
	fi
	cp "$MNT/boot_$MODE.scr" "$MNT/boot.scr" && sync || {
		echo "ERROR: could not update $MNT/boot.scr"
		exit 1
	}
fi

echo "running from: $(running_from)"
echo "next boot:    $(next_mode)"

if [ "$REBOOT" -eq 1 ]; then
	trap - EXIT
	[ "$MNT" = "/tmp/boot_mode.$$" ] && umount "$MNT" && rmdir "$MNT"
	echo "rebooting ..."
	reboot
fi
