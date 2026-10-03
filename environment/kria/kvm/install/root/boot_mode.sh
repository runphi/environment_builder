#!/bin/sh
#
# boot_mode.sh - choose how the Kria boots next time
#
#   boot_mode.sh                 show the boot mode, CPU isolation and where / comes from
#   boot_mode.sh sd              kernel, DTB and rootfs from the SD card
#   boot_mode.sh tftp            kernel and DTB over TFTP, rootfs over NFS from
#                                192.168.100.45 (falls back to the SD card)
#   boot_mode.sh iso <cpus>      isolate <cpus> (e.g. 3, 2-3) from the host kernel
#   boot_mode.sh iso off         no CPU isolation
#   -r                           reboot right after switching
#
# A mode and an isolation setting can be given together, e.g.
# "boot_mode.sh sd iso 3 -r".
#
# U-Boot's distro boot runs boot.scr from the FAT partition of the SD card.
# Both variants are kept next to it, as boot_sd.scr and boot_tftp.scr, and
# switching copies one of them over boot.scr. Works from either boot mode.
# The SD and NFS root filesystems are separate copies: what changes in one
# does not appear in the other.
#
# Both boot scripts read the isolation arguments from isolargs.txt on the
# same FAT partition (one line, isolargs=...), which "iso" writes:
#   isolcpus=managed_irq,domain,nohz,<cpus> nohz_full=<cpus> rcu_nocbs=<cpus>
#   irqaffinity=<the other CPUs>
# so the scheduler, the tick, RCU callbacks and the device interrupts stay off
# <cpus>. Without the file the kernel gets no isolation arguments.

BOOT_PART=/dev/mmcblk1p1
ISO_FILE=isolargs.txt

usage() {
	sed -n '5,14s/^# \{0,1\}//p' "$0"
	exit 1
}

MODE=""
ISO=""
REBOOT=0
while [ $# -gt 0 ]; do
	case "$1" in
	sd | tftp) MODE="$1" ;;
	iso)
		[ $# -ge 2 ] || usage
		ISO="$2"
		shift
		;;
	-r) REBOOT=1 ;;
	*) usage ;;
	esac
	shift
done
[ "$REBOOT" -eq 1 ] && [ -z "$MODE$ISO" ] && usage

# CPU list ("0-1,3") -> one CPU per line
expand_cpus() {
	echo "$1" | tr ',' '\n' | while IFS=- read -r first last; do
		[ -n "$first" ] || continue
		[ -n "$last" ] || last=$first
		i=$first
		while [ "$i" -le "$last" ]; do
			echo "$i"
			i=$((i + 1))
		done
	done
}

# Kernel arguments that isolate the CPUs in $1 from the others
iso_args() {
	case "$1" in
	*[!0-9,-]* | "")
		echo "ERROR: '$1' is not a CPU list (e.g. 3, 2-3, 1,3)" >&2
		return 1
		;;
	esac
	isolated=$(expand_cpus "$1")
	housekeeping=""
	for c in $(expand_cpus "$(cat /sys/devices/system/cpu/possible)"); do
		echo "$isolated" | grep -qx "$c" || housekeeping="$housekeeping${housekeeping:+,}$c"
	done
	for c in $isolated; do
		[ -d "/sys/devices/system/cpu/cpu$c" ] || {
			echo "ERROR: there is no CPU $c" >&2
			return 1
		}
	done
	[ -n "$housekeeping" ] || {
		echo "ERROR: at least one CPU must stay with the host" >&2
		return 1
	}
	echo "isolcpus=managed_irq,domain,nohz,$1 nohz_full=$1 rcu_nocbs=$1 irqaffinity=$housekeeping"
}

if [ -n "$ISO" ] && [ "$ISO" != off ]; then
	ARGS=$(iso_args "$ISO") || exit 1
fi

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

next_iso() {
	if [ -s "$MNT/$ISO_FILE" ]; then
		sed -n 's/^isolargs=//p' "$MNT/$ISO_FILE"
	else
		echo "none"
	fi
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

if [ "$ISO" = off ]; then
	rm -f "$MNT/$ISO_FILE" && sync || {
		echo "ERROR: could not remove $MNT/$ISO_FILE"
		exit 1
	}
elif [ -n "$ISO" ]; then
	printf 'isolargs=%s\n' "$ARGS" >"$MNT/$ISO_FILE" && sync || {
		echo "ERROR: could not write $MNT/$ISO_FILE"
		exit 1
	}
fi

isolated_now=$(cat /sys/devices/system/cpu/isolated)
echo "running from:       $(running_from)"
echo "isolated CPUs now:  ${isolated_now:-none}"
echo "next boot:          $(next_mode)"
echo "next boot isolargs: $(next_iso)"

if [ "$REBOOT" -eq 1 ]; then
	trap - EXIT
	[ "$MNT" = "/tmp/boot_mode.$$" ] && umount "$MNT" && rmdir "$MNT"
	echo "rebooting ..."
	reboot
fi
