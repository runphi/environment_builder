# This is a boot script for U-Boot to boot Xen automatically
# Generate boot.scr with:
# mkimage -c none -A arm -T script -d boot_xen.cmd boot.scr

xen_addr=0xFC00000
kernel_addr=0xE00000
fdt_addr=0xFE00000

setenv fdt_high 0xffffffffffffffff

for boot_target in ${boot_targets}; do
	if test "${boot_target}" = "mmc0" || test "${boot_target}" = "mmc1" ; then
		if test -e ${devtype} ${devnum}:${distro_bootpart} /xen; then
			fatload ${devtype} ${devnum}:${distro_bootpart} ${xen_addr} xen;
			fatload ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image;
			fatload ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb;

			fdt addr ${fdt_addr}
			fdt resize 0x10000

			fdt set /chosen xen,xen-bootargs "console=dtuart dtuart=serial0 dom0_mem=1500M dom0_max_vcpus=1 vwfi=native"
			fdt mknod /chosen dom0
			fdt set /chosen/dom0 compatible "xen,linux-zimage" "xen,multiboot-module"
			fdt set /chosen/dom0 reg <0x0 ${kernel_addr} 0x0 0x1C00000>
			fdt set /chosen xen,dom0-bootargs "console=hvc0 root=/dev/mmcblk0p2 rw rootwait rootdelay=3 clk_ignore_unused"

			booti ${xen_addr} - ${fdt_addr};
			exit;
		fi
	fi
done
