#---------------------------------------------------------------
# boot_sd.cmd - Kria KR260 / KVM: kernel, DTB and rootfs from the SD card
#
# The FAT partition of the SD card holds the same Image and system.dtb as
# tftpboot/kr260-kvm/, and its ext4 partition a copy of the NFS rootfs, so this
# boots the same system without the TFTP/NFS server. The two rootfs copies are
# independent: changes made in one boot mode do not appear in the other.
#
# Build with scripts/compile/bootscr_compile.sh -c sd -o boot_sd.scr
# /root/boot_mode.sh on the board selects this script or boot_tftp.scr.
#---------------------------------------------------------------

# ---------- where to put the files in RAM ----------
# Same addresses as boot_tftp.cmd.
setenv kernel_addr 0x00200000
setenv fdt_addr    0x20000000

# ---------- kernel command line ----------
setenv baseargs "earlycon clk_ignore_unused console=ttyPS1,115200"

# ---------- where the files are ----------
# On the KR260 the microSD card is behind a USB bridge: distro boot finds it
# as usb 0 and sets devtype/devnum/distro_bootpart when it runs this script
# from the card. Started by hand, it is usb 0, partition 1 (after "usb start").
if test -z "${devtype}"; then
	usb start
	setenv devtype usb
	setenv devnum 0
	setenv distro_bootpart 1
fi

# ---------- CPU isolation ----------
# As in boot_tftp.cmd: isolargs.txt on the FAT partition, written by
# /root/boot_mode.sh iso <cpus>.
setenv isolargs ""
setenv isoenv_addr 0x10000000
if load ${devtype} ${devnum}:${distro_bootpart} ${isoenv_addr} isolargs.txt; then
	env import -t -r ${isoenv_addr} ${filesize} isolargs
fi
echo "isolargs: ${isolargs}"

# ---------- the root filesystem ----------
# The card's second partition, by its PARTUUID: in Linux the card is a USB
# disk (sdX), whose name depends on what else is plugged in.
setenv rootuuid ""
part uuid ${devtype} ${devnum}:2 rootuuid

echo "------------------------------------------------------------"
echo "SD: ${devtype} ${devnum}:${distro_bootpart} -> kernel ${kernel_addr}, dtb ${fdt_addr}, root PARTUUID=${rootuuid}"
if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image; then
	if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb; then
		if test -n "${rootuuid}"; then
			fdt addr ${fdt_addr}
			fdt resize 0x10000
			setenv bootargs "${baseargs} ${isolargs} root=PARTUUID=${rootuuid} rw rootwait"
			echo "------------------------------------------------------------"
			booti ${kernel_addr} - ${fdt_addr}
		fi
	fi
fi
echo "SD boot failed (Image, system.dtb or the second partition missing?)"
