#---------------------------------------------------------------
# boot_tftp.cmd - Kria KV260 / KVM: TFTP kernel+DTB, NFS-root rootfs
#
# Build with scripts/compile/bootscr_compile.sh (BOOTCMD_CONFIG="tftp"),
# or by hand:
#   mkimage -A arm64 -O linux -T script -C none -d boot_tftp.cmd boot.scr
#
# Put the resulting boot.scr on the FAT partition of the SD card (U-Boot's
# distro boot runs it), or start it by hand from the U-Boot prompt (it must
# then also be in tftpboot/kria-kvm/):
#   setenv ipaddr 192.168.100.46; setenv serverip 192.168.100.45
#   tftpboot ${scriptaddr} kria-kvm/boot.scr; source ${scriptaddr}
#
# If TFTP or the DTB fetch fails this falls back to the SD card, so the
# board stays bootable when the network path is unavailable.
#---------------------------------------------------------------

# ---------- network parameters ----------
# No DHCP server on the lab network, so everything is static.
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
# On the KV260 the SD card is mmc 1 in U-Boot (mmcblk1 in Linux).
echo "------------------------------------------------------------"
echo "Falling back to SD card boot ..."
if load mmc 1:1 ${kernel_addr} Image; then
	load mmc 1:1 ${fdt_addr} system.dtb
	setenv bootargs "${baseargs} ${isolargs} root=/dev/mmcblk1p2 rw rootwait"
	booti ${kernel_addr} - ${fdt_addr}
fi

echo "No boot path succeeded; resetting in 5s ..."
sleep 5
reset
