load mmc 0:1 0xE00000 Image
load mmc 0:1 0xFC00000 xen
load mmc 0:1 0xFE00000 system.dtb

fdt addr 0xFE00000
fdt resize 0x10000

fdt set /chosen xen,xen-bootargs "console=dtuart dtuart=serial0 dom0_mem=1500M dom0_max_vcpus=1 vwfi=native"
fdt mknod /chosen dom0
fdt set /chosen/dom0 compatible "xen,linux-zimage" "xen,multiboot-module"
fdt set /chosen/dom0 reg <0x0 0xE00000 0x0 0x1C00000>
fdt set /chosen xen,dom0-bootargs "console=hvc0 root=/dev/mmcblk0p2 rw rootwait rootdelay=3 clk_ignore_unused"

setenv fdt_high 0xffffffffffffffff
booti 0xFC00000 - 0xFE00000

