load mmc 0:1 0xE00000 xen-Image
load mmc 0:1 0x2600000 xen-rootfs.cpio.gz
load mmc 0:1 0x6600000 xen
load mmc 0:1 0x6800000 xen.dtb
fdt addr 0x6800000
fdt resize 1024
fdt set /chosen \#address-cells <0x2>
fdt set /chosen \#size-cells <0x2>
fdt set /chosen xen,xen-bootargs "console=dtuart dtuart=serial0 dom0_mem=1500M dom0_max_vcpus=1 bootscrub=0 vwfi=native sched=null   "
fdt mknod /chosen dom0
fdt set /chosen/dom0 compatible  "xen,linux-zimage" "xen,multiboot-module" "multiboot,module"
fdt set /chosen/dom0 reg <0x0 0xE00000 0x0 0x1725200 >
fdt set /chosen xen,dom0-bootargs "console=hvc0 earlycon=xen earlyprintk=xen clk_ignore_unused root=/dev/ram0"
fdt mknod /chosen dom0-ramdisk
fdt set /chosen/dom0-ramdisk compatible  "xen,linux-initrd" "xen,multiboot-module" "multiboot,module"
fdt set /chosen/dom0-ramdisk reg <0x0 0x2600000 0x0 0x3EC3749 >
setenv fdt_high 0xffffffffffffffff
booti 0x6600000 - 0x6800000
