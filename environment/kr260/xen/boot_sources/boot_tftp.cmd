#---------------------------------------------------------------
# boot_tftp.cmd - Kria KR260 / Xen: Xen, Dom0's kernel and the DTB over TFTP,
# Dom0's root filesystem over NFS
#
# Build with scripts/compile/bootscr_compile.sh -t kr260 -b xen (boot.scr),
# then copy it to tftpboot/kr260-xen/. The SD card's boot script fetches
# kr260.scr from the server, which scripts/remote/switch_backend.sh -t kr260
# -b xen points here (scripts/remote/boot_select.cmd). It can also be started
# by hand from the U-Boot prompt:
#   setenv ipaddr 192.168.100.53; setenv serverip 192.168.100.45
#   tftpboot ${scriptaddr} kr260-xen/boot.scr; source ${scriptaddr}
#
# If a TFTP fetch fails this boots kr260-kvm from the SD card (as its
# boot_sd.cmd does), so the board stays bootable without the server.
#
# The network is the PS GEM0 port, J10D, U-Boot's default ethact; in Dom0 it
# is eth1 (GEM0's PHY is on GEM1's MDIO bus, so GEM1 registers first, as eth0).
#---------------------------------------------------------------

# ---------- network parameters ----------
# Static, the board's only address (as in kr260-kvm).
setenv ipaddr     192.168.100.53          # the board (kr260)
setenv serverip   192.168.100.45          # TFTP + NFS server
setenv gatewayip  192.168.100.254
setenv netmask    255.255.255.0

# ---------- where the files live on the server ----------
# tftppath is relative to TFTP_DIRECTORY in /etc/default/tftpd-hpa on the
# server, which is <clone>/tftpboot - matching tftp_boot_dir in
# scripts/common/set_environment.sh.
setenv tftppath   kr260-xen
setenv nfspath    /root/runphi/environment_builder/environment/kr260/xen/output/rootfs/kr260

# ---------- where to put them in RAM ----------
# Dom0's kernel where kr260-kvm loads its kernel, Xen above it, the DTB where
# kr260-kvm puts it. Xen copies Dom0's kernel into Dom0's memory and frees
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
# On the KR260 the microSD card is behind a USB bridge: distro boot finds it
# as usb 0 and sets devtype/devnum/distro_bootpart when it runs this script
# from the card. Started by hand, it is usb 0, partition 1 (after "usb start").
if test -z "${devtype}"; then
	usb start
	setenv devtype usb
	setenv devnum 0
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
			fdt set /chosen xen,dom0-bootargs "console=hvc0 earlycon=xenboot clk_ignore_unused root=/dev/nfs rw nfsroot=${serverip}:${nfspath},tcp,nfsvers=3 ip=${ipaddr}::${gatewayip}:${netmask}:kr260:eth1:off rootwait"
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

# ---------- fallback: kr260-kvm from the SD card ----------
# As kr260-kvm's boot_sd.cmd, with its CPU isolation (isolargs.txt): the root
# is the card's second partition, by its PARTUUID.
echo "------------------------------------------------------------"
echo "Falling back to kr260-kvm on the SD card ..."
setenv kernel_addr 0x00200000
setenv isolargs ""
setenv isoenv_addr 0x10000000
if load ${devtype} ${devnum}:${distro_bootpart} ${isoenv_addr} isolargs.txt; then
	env import -t -r ${isoenv_addr} ${filesize} isolargs
fi
if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image; then
	if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb; then
		if part uuid ${devtype} ${devnum}:2 rootuuid; then
			fdt addr ${fdt_addr}
			fdt resize 0x10000
			setenv bootargs "earlycon clk_ignore_unused console=ttyPS1,115200 ${isolargs} root=PARTUUID=${rootuuid} rw rootwait"
			booti ${kernel_addr} - ${fdt_addr}
		fi
	fi
fi

echo "No boot path succeeded; resetting in 5s ..."
sleep 5
reset
