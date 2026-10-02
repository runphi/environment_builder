#---------------------------------------------------------------
# boot_tftp.cmd - Kria KV260 / KVM: TFTP kernel+DTB, NFS-root rootfs
#
# Build with scripts/compile/bootscr_compile.sh -c tftp -o boot_tftp.scr
# /root/boot_mode.sh on the board selects this script or boot_sd.scr as the
# boot.scr of the SD card's FAT partition (U-Boot's distro boot runs it).
# It can also be started by hand from the U-Boot prompt (from
# tftpboot/kria-kvm/boot.scr):
#   setenv ipaddr 192.168.100.46; setenv serverip 192.168.100.45
#   tftpboot ${scriptaddr} kria-kvm/boot.scr; source ${scriptaddr}
#
# If TFTP or the DTB fetch fails this falls back to the SD card, so the
# board stays bootable when the network path is unavailable.
#---------------------------------------------------------------

# ---------- network parameters ----------
# Static, so that the board is always at the same address. (The gateway does
# serve DHCP, but with dynamic addresses.)
setenv ipaddr     192.168.100.46          # the board (kriakv260)
setenv serverip   192.168.100.45          # TFTP + NFS server
setenv gatewayip  192.168.100.254
setenv netmask    255.255.255.0

# ---------- where the files live on the server ----------
# tftppath is relative to TFTP_DIRECTORY in /etc/default/tftpd-hpa on the
# server, which is <clone>/tftpboot - matching tftp_boot_dir in
# scripts/common/set_environment.sh.
setenv tftppath   kria-kvm
setenv nfspath    /root/runphi/environment_builder/environment/kria/kvm/output/rootfs/kria

# ---------- where to put them in RAM ----------
# Same addresses as the kria-jailhouse NFS boot script.
setenv kernel_addr 0x00200000
setenv fdt_addr    0x20000000

# ---------- kernel command line ----------
# KVM needs nothing here: the firmware enters Linux at EL2 and KVM takes
# over EL2 at boot in nVHE mode (Cortex-A53 has no VHE).
# runPHI backend_kvm pins vCPUs and steers host IRQs away from the CPUs
# listed in isolcpus/nohz_full, so add them here when needed, e.g.:
#   setenv isolargs "isolcpus=domain,managed_irq,3 nohz_full=3"
setenv isolargs ""
setenv baseargs "earlycon clk_ignore_unused console=ttyPS1,115200"

echo "------------------------------------------------------------"
echo "TFTP: ${serverip}:${tftppath} -> kernel ${kernel_addr}, dtb ${fdt_addr}"

if tftpboot ${kernel_addr} ${tftppath}/Image; then
	if tftpboot ${fdt_addr} ${tftppath}/system.dtb; then
		fdt addr ${fdt_addr}
		fdt resize 0x10000
		setenv bootargs "${baseargs} ${isolargs} root=/dev/nfs rw nfsroot=${serverip}:${nfspath},tcp,nfsvers=3 ip=${ipaddr}::${gatewayip}:${netmask}:kriakv260:eth0:off rootwait"
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
# the rootfs. Distro boot sets devtype/devnum/distro_bootpart when it runs this
# script from the SD card; started by hand, the SD card is mmc 1 on the KV260
# (mmcblk1 in Linux).
echo "------------------------------------------------------------"
echo "Falling back to SD card boot ..."
if test -z "${devtype}"; then
	setenv devtype mmc
	setenv devnum 1
	setenv distro_bootpart 1
fi
if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image; then
	if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb; then
		fdt addr ${fdt_addr}
		fdt resize 0x10000
		setenv bootargs "${baseargs} ${isolargs} root=/dev/mmcblk1p2 rw rootwait"
		booti ${kernel_addr} - ${fdt_addr}
	fi
fi

echo "No boot path succeeded; resetting in 5s ..."
sleep 5
reset
