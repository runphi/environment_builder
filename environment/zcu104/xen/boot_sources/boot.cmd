#---------------------------------------------------------------
# boot.cmd  –  ZCU104 + Xen:  TFTP hypervisor & dom0, NFS-root FS
#---------------------------------------------------------------

# ---------- static network ----------
setenv ipaddr     192.168.100.52
setenv serverip   192.168.100.45
setenv gatewayip  192.168.100.254
setenv netmask    255.255.255.0

# ---------- file locations on TFTP server ----------
setenv tftppath   zcu104-xen                    # folder under /var/lib/tftpboot
setenv nfspath    /root/runphi/environment_builder/environment/zcu104/xen/output/rootfs/zcu104

# ---------- load addresses in RAM ----------
setenv  dom0_addr  0x00E00000   # ~14 MiB, well below 128 MiB
setenv  xen_addr   0x0FC00000   # 252 MiB
setenv  fdt_addr   0x0FE00000   # 254 MiB

echo "------------------------------------------------------------"
echo "TFTP: hypervisor  ${tftppath}/xen ..."
tftpboot  ${xen_addr}   ${tftppath}/xen         || exit

echo "TFTP: dom0 kernel ${tftppath}/Image ..."
tftpboot  ${dom0_addr}  ${tftppath}/Image       || exit

echo "TFTP: device tree ${tftppath}/system.dtb ..."
tftpboot  ${fdt_addr}   ${tftppath}/system.dtb  || exit
echo "------------------------------------------------------------"

# ---------- patch DTB for Xen ----------
fdt addr   ${fdt_addr}
fdt resize 0x10000

# Xen hypervisor boot-args (note: quote the whole string; spaces are fine)
fdt set /chosen xen,xen-bootargs "console=dtuart dtuart=serial0 dom0_uart dom0_mem=1500M dom0_max_vcpus=2 vwfi=native"
fdt print /chosen xen,xen-bootargs

# Declare Dom-0 kernel as multiboot module (32 MiB span)
fdt mknod /chosen dom0
fdt set  /chosen/dom0 compatible "xen,linux-zimage" "xen,multiboot-module"
fdt set  /chosen/dom0 reg <0x0 ${dom0_addr} 0x0 0x02000000>

# *** Dom-0 command line ***
fdt set /chosen xen,dom0-bootargs "console=hvc0 earlycon=xen root=/dev/nfs rw nfsroot=${serverip}:${nfspath},tcp,nfsvers=3 ip=${ipaddr}::${gatewayip}:${netmask}:zcu104:eth0:off clk_ignore_unused"

# Allow Xen to relocate DTB if it wants
setenv fdt_high 0xffffffffffffffff

# ---------- guarantee /hypervisor node with HVC ----------
if ! fdt pathexists /hypervisor; then
        fdt mknode / hypervisor
        fdt set    /hypervisor compatible "xen,xen-4.18" "xen,xen"
fi
fdt set /hypervisor method "hvc"

echo "Booting Xen ..."
booti ${xen_addr} - ${fdt_addr}

