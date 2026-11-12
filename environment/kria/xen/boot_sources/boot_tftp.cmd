#---------------------------------------------------------------
# boot_tftp.cmd - Kria KV260 / Xen: Xen, Dom0's kernel and the DTB over TFTP,
# Dom0's root filesystem over NFS
#
# Build with scripts/compile/bootscr_compile.sh -t kria -b xen (boot.scr),
# then copy it to tftpboot/kria-xen/. The SD card's boot script fetches
# kria.scr from the server, which scripts/remote/switch_backend.sh -t kria
# -b xen points here (scripts/remote/boot_select.cmd). It can also be started
# by hand from the U-Boot prompt:
#   setenv ipaddr 192.168.100.46; setenv serverip 192.168.100.45
#   tftpboot ${scriptaddr} kria-xen/boot.scr; source ${scriptaddr}
#
# If a TFTP fetch fails this boots kria-kvm from the SD card (as its
# boot_sd.cmd does), so the board stays bootable without the server.
#---------------------------------------------------------------

# ---------- network parameters ----------
# Static, the board's only address (as in kria-kvm).
setenv ipaddr     192.168.100.46          # the board (kriakv260)
setenv serverip   192.168.100.45          # TFTP + NFS server
setenv gatewayip  192.168.100.254
setenv netmask    255.255.255.0

# ---------- where the files live on the server ----------
# tftppath is relative to TFTP_DIRECTORY in /etc/default/tftpd-hpa on the
# server, which is <clone>/tftpboot - matching tftp_boot_dir in
# scripts/common/set_environment.sh.
setenv tftppath   kria-xen
setenv nfspath    /root/runphi/environment_builder/environment/kria/xen/output/rootfs/kria

# ---------- where to put them in RAM ----------
# Dom0's kernel where kria-kvm loads its kernel, Xen above it, the DTB where
# kria-kvm puts it. Xen copies Dom0's kernel into Dom0's memory and frees
# these areas.
setenv dom0_addr  0x00200000
setenv xen_addr   0x0c000000
setenv fdt_addr   0x20000000

# ---------- Xen's command line ----------
# console=dtuart dtuart=serial1: Xen's console is the UART of the alias
#   serial1 (serial@ff010000, Linux's ttyPS1, the USB serial port of the
#   carrier card); Xen keeps it for itself, Dom0's console is hvc0.
# dom0_mem=1024M: Dom0's memory, mapped 1:1 onto RAM (the SMMU is disabled in
#   the DTB); the rest of the 4 GB is for the domains.
# dom0_max_vcpus=1 dom0_vcpus_pin: Dom0 has one vCPU, pinned to CPU 0, so
#   runPHI's domains have CPUs 1-3 to themselves (backend_xen reserves the
#   CPUs that Dom0's vCPUs are pinned to).
# vwfi=native: a vCPU's WFI does not trap to Xen, as on the ZCU104 and in
#   qemu-xen (lower interrupt latency for the domains).
setenv xenargs "console=dtuart dtuart=serial1 dom0_mem=1024M dom0_max_vcpus=1 dom0_vcpus_pin vwfi=native"

# ---------- the SD card's FAT partition ----------
# Distro boot sets devtype/devnum/distro_bootpart when it runs this script
# from the SD card; started by hand, the SD card is mmc 1 on the KV260.
if test -z "${devtype}"; then
	setenv devtype mmc
	setenv devnum 1
	setenv distro_bootpart 1
fi

# ---------- boot ----------
# /chosen gets Xen's boot modules as Xen's ImageBuilder writes them: Xen's
# command line in xen,xen-bootargs, Dom0's kernel in a multiboot,kernel node,
# Dom0's command line in xen,dom0-bootargs. fdt_high leaves the DTB where it
# is, and bootargs is cleared: Xen does not read it when xen,xen-bootargs is
# there.
echo "------------------------------------------------------------"
echo "TFTP: ${serverip}:${tftppath} -> xen ${xen_addr}, Dom0 kernel ${dom0_addr}, dtb ${fdt_addr}"

if tftpboot ${xen_addr} ${tftppath}/xen; then
	if tftpboot ${dom0_addr} ${tftppath}/Image; then
		setenv dom0_size 0x${filesize}
		if tftpboot ${fdt_addr} ${tftppath}/system.dtb; then
			fdt addr ${fdt_addr}
			fdt resize 0x10000
			fdt set /chosen \#address-cells <0x2>
			fdt set /chosen \#size-cells <0x2>
			fdt set /chosen xen,xen-bootargs "${xenargs}"
			fdt mknod /chosen dom0
			fdt set /chosen/dom0 compatible "multiboot,kernel" "multiboot,module"
			fdt set /chosen/dom0 reg <0x0 ${dom0_addr} 0x0 ${dom0_size}>
			fdt set /chosen xen,dom0-bootargs "console=hvc0 earlycon=xenboot clk_ignore_unused root=/dev/nfs rw nfsroot=${serverip}:${nfspath},tcp,nfsvers=3 ip=${ipaddr}::${gatewayip}:${netmask}:kriakv260:eth0:off rootwait"
			setenv fdt_high 0xffffffffffffffff
			setenv bootargs
			echo "Xen: ${xenargs}"
			echo "Dom0: ${dom0_size} bytes, NFS root ${serverip}:${nfspath}"
			echo "------------------------------------------------------------"
			booti ${xen_addr} - ${fdt_addr}
		else
			echo "TFTP: DTB fetch failed"
		fi
	else
		echo "TFTP: Dom0 kernel fetch failed"
	fi
else
	echo "TFTP: xen fetch failed"
fi

# ---------- fallback: kria-kvm from the SD card ----------
# As kria-kvm's boot_sd.cmd, with its CPU isolation (isolargs.txt).
echo "------------------------------------------------------------"
echo "Falling back to kria-kvm on the SD card ..."
setenv kernel_addr 0x00200000
setenv isolargs ""
setenv isoenv_addr 0x10000000
if load ${devtype} ${devnum}:${distro_bootpart} ${isoenv_addr} isolargs.txt; then
	env import -t -r ${isoenv_addr} ${filesize} isolargs
fi
if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image; then
	if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb; then
		fdt addr ${fdt_addr}
		fdt resize 0x10000
		setenv bootargs "earlycon clk_ignore_unused console=ttyPS1,115200 ${isolargs} root=/dev/mmcblk1p2 rw rootwait"
		booti ${kernel_addr} - ${fdt_addr}
	fi
fi

echo "No boot path succeeded; resetting in 5s ..."
sleep 5
reset
