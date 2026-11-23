#---------------------------------------------------------------
# boot_tftp.cmd - Kria KR260 / KVM: TFTP kernel+DTB, NFS-root rootfs
#
# Build with scripts/compile/bootscr_compile.sh -t kr260 -b kvm (boot.scr),
# then copy it to tftpboot/kr260-kvm/. The SD card's boot script fetches
# kr260.scr from the server, which scripts/remote/switch_backend.sh -t kr260
# -b kvm points here (scripts/remote/boot_select.cmd); /root/boot_mode.sh
# chooses between that network boot and boot_sd.scr.
# It can also be started by hand from the U-Boot prompt (from
# tftpboot/kr260-kvm/boot.scr):
#   setenv ipaddr 192.168.100.53; setenv serverip 192.168.100.45
#   tftpboot ${scriptaddr} kr260-kvm/boot.scr; source ${scriptaddr}
#
# If TFTP or the DTB fetch fails this falls back to the SD card, so the
# board stays bootable when the network path is unavailable.
#
# The network is the PS GEM0 port, J10D (ethernet@ff0b0000, SGMII): U-Boot's
# default ethact, and eth1 in Linux: GEM0's PHY is on the MDIO bus of GEM1
# (J10C), so GEM0 probes after GEM1, which gets eth0 (the DT aliases do not
# name the interfaces). J10A and J10B are PL ports, which need an FPGA design.
#---------------------------------------------------------------

# ---------- network parameters ----------
# Static, so that the board is always at the same address. (The gateway does
# serve DHCP, but with dynamic addresses.)
setenv ipaddr     192.168.100.53          # the board (kr260)
setenv serverip   192.168.100.45          # TFTP + NFS server
setenv gatewayip  192.168.100.254
setenv netmask    255.255.255.0

# ---------- where the files live on the server ----------
# tftppath is relative to TFTP_DIRECTORY in /etc/default/tftpd-hpa on the
# server, which is <clone>/tftpboot - matching tftp_boot_dir in
# scripts/common/set_environment.sh.
setenv tftppath   kr260-kvm
setenv nfspath    /root/runphi/environment_builder/environment/kr260/kvm/output/rootfs/kr260

# ---------- where to put them in RAM ----------
# As on the KV260: the kernel low, the DTB above it.
setenv kernel_addr 0x00200000
setenv fdt_addr    0x20000000

# ---------- kernel command line ----------
# KVM needs nothing here: the firmware enters Linux at EL2 and KVM takes
# over EL2 at boot in nVHE mode (Cortex-A53 has no VHE).
setenv baseargs "earlycon clk_ignore_unused console=ttyPS1,115200"

# ---------- the SD card's FAT partition ----------
# On the KR260 the microSD card is behind a USB bridge: distro boot finds it
# as usb 0 and sets devtype/devnum/distro_bootpart when it runs this script
# from the card. Started by hand, it is usb 0, partition 1 (after "usb start").
# Used for isolargs.txt and for the fallback below.
if test -z "${devtype}"; then
	usb start
	setenv devtype usb
	setenv devnum 0
	setenv distro_bootpart 1
fi

# ---------- CPU isolation ----------
# isolargs (isolcpus=, nohz_full=, ...) comes from isolargs.txt on the SD
# card's FAT partition, one line "isolargs=...", which /root/boot_mode.sh
# iso <cpus> writes and "iso off" removes. Without the file the kernel gets
# no isolation arguments. Read in both boot modes, so the isolation does not
# change when switching between SD and TFTP+NFS. The address is free RAM
# between the kernel (from kernel_addr) and the DTB (fdt_addr).
setenv isolargs ""
setenv isoenv_addr 0x10000000
if load ${devtype} ${devnum}:${distro_bootpart} ${isoenv_addr} isolargs.txt; then
	env import -t -r ${isoenv_addr} ${filesize} isolargs
fi
echo "isolargs: ${isolargs}"

echo "------------------------------------------------------------"
echo "TFTP: ${serverip}:${tftppath} -> kernel ${kernel_addr}, dtb ${fdt_addr}"

if tftpboot ${kernel_addr} ${tftppath}/Image; then
	if tftpboot ${fdt_addr} ${tftppath}/system.dtb; then
		fdt addr ${fdt_addr}
		fdt resize 0x10000
		setenv bootargs "${baseargs} ${isolargs} root=/dev/nfs rw nfsroot=${serverip}:${nfspath},tcp,nfsvers=3 ip=${ipaddr}::${gatewayip}:${netmask}:kr260:eth1:off rootwait"
		echo "NFS root: ${serverip}:${nfspath}"
		echo "------------------------------------------------------------"
		booti ${kernel_addr} - ${fdt_addr}
	else
		echo "TFTP: DTB fetch failed"
	fi
else
	echo "TFTP: kernel fetch failed"
fi

# ---------- fallback: boot from the SD card ----------
# Same as boot_sd.cmd: the SD card holds the same kernel and DTB and a copy of
# the rootfs, on its second partition (found by its PARTUUID: in Linux the
# card is a USB disk, sdX, whose name depends on what else is plugged in).
echo "------------------------------------------------------------"
echo "Falling back to SD card boot ..."
if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image; then
	if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb; then
		if part uuid ${devtype} ${devnum}:2 rootuuid; then
			fdt addr ${fdt_addr}
			fdt resize 0x10000
			setenv bootargs "${baseargs} ${isolargs} root=PARTUUID=${rootuuid} rw rootwait"
			booti ${kernel_addr} - ${fdt_addr}
		fi
	fi
fi

echo "No boot path succeeded; resetting in 5s ..."
sleep 5
reset
