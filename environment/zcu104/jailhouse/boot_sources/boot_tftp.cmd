#---------------------------------------------------------------
# boot_tftp.cmd - ZCU104 / Jailhouse: TFTP kernel+DTB, NFS-root rootfs
#
# Build with scripts/compile/bootscr_compile.sh (BOOTCMD_CONFIG="tftp"),
# or by hand:
#   mkimage -A arm64 -O linux -T script -C none -d boot_tftp.cmd boot.scr
#
# If TFTP or the DTB fetch fails this falls back to the SD card, so the
# board stays bootable when the network path is unavailable.
#---------------------------------------------------------------

# ---------- network parameters ----------
# No DHCP server on the lab network, so everything is static.
setenv ipaddr     192.168.100.47          # the board (zcu104a)
setenv serverip   192.168.100.45          # TFTP + NFS server
setenv gatewayip  192.168.100.254
setenv netmask    255.255.255.0

# ---------- where the files live on the server ----------
# tftppath is relative to TFTP_DIRECTORY in /etc/default/tftpd-hpa on the
# server, which is <clone>/tftpboot - matching tftp_boot_dir in
# scripts/common/set_environment.sh.
setenv tftppath   zcu104-jailhouse
setenv nfspath    /root/runphi/environment_builder/environment/zcu104/jailhouse/output/rootfs/zcu104

# ---------- where to put them in RAM ----------
# Same addresses the SD boot script uses on this board; both are far below
# the Jailhouse hypervisor region at 0x6f000000.
setenv kernel_addr 0x00200000
setenv fdt_addr    0x00100000

# ---------- kernel command line ----------
# CPU 3 only: the inmate cell runs there and the root cell needs 0-2.
#
# 2026-08-05: nohz_full=3 / rcu_nocbs=3 / rcu_nocb_poll REMOVED, and the "nohz,"
# prefix with them. They were added on the assumption that CPU 3 is a latency-
# sensitive Linux CPU. It is not: Jailhouse hotplugs CPU 3 out and runs the
# inmate there, so for almost the whole campaign CPU 3 is offline as far as
# Linux is concerned. Consequences of setting them anyway:
#   - nohz_full=3 governs tickless execution of Linux *userspace* on that CPU.
#     No Linux userspace ever runs there, so it buys nothing.
#   - rcu_nocbs=3 offloads CPU 3's RCU callbacks to rcuo kthreads that run on
#     the housekeeping CPUs -- 0-2, precisely the cores whose interference the
#     experiment measures.
#   - rcu_nocb_poll makes those kthreads poll instead of sleeping, i.e. adds a
#     permanently runnable task to a 3-CPU set already saturated by stressors.
# Empirically the Jailhouse+stressor wedge went from ~2-6 min to 20-45 s when
# these were introduced. Reverting to the parameter set under which baseline,
# fork4 and open4 completed 52/52.
setenv isolargs "isolcpus=domain,managed_irq,3 skew_tick=1 deferred_probe_timeout=1 earlycon clk_ignore_unused"

echo "------------------------------------------------------------"
echo "TFTP: ${serverip}:${tftppath} -> kernel ${kernel_addr}, dtb ${fdt_addr}"

if tftpboot ${kernel_addr} ${tftppath}/Image; then
	if tftpboot ${fdt_addr} ${tftppath}/system.dtb; then
		setenv bootargs "${isolargs} console=ttyPS0,115200 root=/dev/nfs rw nfsroot=${serverip}:${nfspath},tcp,nfsvers=3 ip=${ipaddr}::${gatewayip}:${netmask}:zcu104a:eth0:off rootwait"
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
echo "------------------------------------------------------------"
echo "Falling back to SD card boot ..."
if load mmc 0:1 ${kernel_addr} Image; then
	load mmc 0:1 ${fdt_addr} system.dtb
	setenv bootargs "${isolargs} root=/dev/mmcblk0p2 rw rootwait"
	booti ${kernel_addr} - ${fdt_addr}
fi

echo "No boot path succeeded; resetting in 5s ..."
sleep 5
reset
