#---------------------------------------------------------------
# boot_sd.cmd - Kria KV260 / KVM: kernel, DTB and rootfs from the SD card
#
# The FAT partition of the SD card holds the same Image and system.dtb as
# tftpboot/kria-kvm/, and its ext4 partition a copy of the NFS rootfs, so this
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
# Same as boot_tftp.cmd; see there for isolargs.
setenv isolargs ""
setenv baseargs "earlycon clk_ignore_unused console=ttyPS1,115200"

# ---------- where the files are ----------
# Distro boot sets devtype/devnum/distro_bootpart when it runs this script
# from the SD card. Started by hand, use the SD card: mmc 1 on the KV260
# (mmcblk1 in Linux).
if test -z "${devtype}"; then
	setenv devtype mmc
	setenv devnum 1
	setenv distro_bootpart 1
fi

echo "------------------------------------------------------------"
echo "SD: ${devtype} ${devnum}:${distro_bootpart} -> kernel ${kernel_addr}, dtb ${fdt_addr}, root /dev/mmcblk1p2"

if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image; then
	if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb; then
		fdt addr ${fdt_addr}
		fdt resize 0x10000
		setenv bootargs "${baseargs} ${isolargs} root=/dev/mmcblk1p2 rw rootwait"
		echo "------------------------------------------------------------"
		booti ${kernel_addr} - ${fdt_addr}
	fi
fi

# Not reached when the kernel boots. Return to distro boot, which goes on with
# its other boot targets, instead of resetting in a loop.
echo "SD boot failed (Image or system.dtb missing?)"
