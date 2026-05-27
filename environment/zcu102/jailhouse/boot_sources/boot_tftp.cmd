#---------------------------------------------------------------
# boot.cmd  –  ZCU102: TFTP kernel+DTB, NFS-root rootfs
# Build:  mkimage -A arm64 -T script -C none -d boot.cmd boot.scr
#---------------------------------------------------------------

# ---------- network parameters ----------
setenv ipaddr     192.168.100.51          # board IP
setenv serverip   192.168.100.45          # TFTP/NFS server IP
setenv gatewayip  192.168.100.254
setenv netmask    255.255.255.0

# ---------- where the files live on the server ----------
setenv tftppath   zcu102-jailhouse
setenv nfspath    /root/runphi/environment_builder/environment/zcu102/jailhouse/output/rootfs/zcu102

# ---------- where to put them in RAM ----------
setenv kernel_addr 0x0080000      # 512 KiB, safely below 128 MiB
setenv fdt_addr    0x02000000     #   32 MiB, well clear of kernel

echo "------------------------------------------------------------"
echo "TFTP: loading kernel from ${serverip}:${tftppath}/Image ..."
tftpboot ${kernel_addr} ${tftppath}/Image  || exit

echo "TFTP: loading DTB    from ${serverip}:${tftppath}/system.dtb ..."
tftpboot ${fdt_addr}   ${tftppath}/system.dtb  || exit
echo "------------------------------------------------------------"

# ---------- kernel command line ----------
setenv bootargs "console=ttyPS0,115200 earlycon \
root=/dev/nfs rw \
nfsroot=${serverip}:${nfspath},tcp,nfsvers=3 \
ip=${ipaddr}::${gatewayip}:${netmask}:zcu102:eth0:off \
clk_ignore_unused"

echo "Boot arguments:"
echo ${bootargs}
echo "------------------------------------------------------------"

# ---------- boot the kernel ----------
booti ${kernel_addr} - ${fdt_addr}

