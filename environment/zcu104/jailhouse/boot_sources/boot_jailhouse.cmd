# This is a boot script for U-Boot
# Generate boot.scr:
# mkimage -c none -A arm -T script -d boot.cmd.default boot.scr
#
################
## Please change the kernel_offset and kernel_size if the kernel image size more than
## the 100MB and BOOT.BIN size more than the 30MB
## kernel_offset --> is the address of qspi which you want load the kernel image
## kernel_size --> size of the kernel image in hex
###############
imageub_addr=0x10000000
#fdt_addr=0x2A00000
#kernel_addr=0x3000000
kernel_addr=0x00200000
fdt_addr=0x00100000


for boot_target in ${boot_targets};
do
	if test "${boot_target}" = "mmc0" || test "${boot_target}" = "mmc1" ; then
		if test -e ${devtype} ${devnum}:${distro_bootpart} /image.ub; then
			fatload ${devtype} ${devnum}:${distro_bootpart} ${imageub_addr} image.ub;
			bootm ${imageub_addr};
			exit;
		fi
		if test -e ${devtype} ${devnum}:${distro_bootpart} /Image; then
			# NOTE: nohz/nohz_full/rcu_nocbs/nosoftlockup/nowatchdog are no-ops here;
			# they need a kernel with NO_HZ_FULL / RCU_NOCB_CPU / lockup detector
			# CPU 3 only: the inmate cell (zynqmp-zcu104-APU-inmate-demo.cell) runs
			# there, and the root cell needs 0-2 for the interference workload.
			# The "nohz," prefix and the nohz_full / rcu_nocbs parameters are only
			# legal because the defconfig now sets CONFIG_NO_HZ_FULL (which selects
			# RCU_NOCB_CPU); with NO_HZ_FULL off the kernel rejects the whole
			# isolcpus parameter and silently isolates nothing.
			# processor.max_cstate / processor_idle.max_cstate are x86-only, omitted.
			# deferred_probe_timeout works around a dead i2c mux on this board.
			# NOTE: keep "=" out of these comments so that the boot.scr
			# verification grep in HANDOFF/DEMO still matches only the real line.
			# nosoftlockup / nowatchdog are omitted on purpose: this defconfig has
			# CONFIG_SOFTLOCKUP_DETECTOR unset, so the kernel does not register
			# those parameters and reports them under "Unknown kernel command line
			# parameters". They are no-ops here; the KV260 cmdline carries them
			# only because that config enables the lockup detector.
			setenv bootargs "isolcpus=nohz,domain,managed_irq,3 nohz_full=3 rcu_nocbs=3 rcu_nocb_poll skew_tick=1 deferred_probe_timeout=1 earlycon clk_ignore_unused root=/dev/mmcblk0p2 rw rootwait"
			setenv uenvcmd "fatload mmc 0 0x3000000 Image && fatload mmc 0 0x2A00000 system.dtb && booti 0x3000000 - 0x2A00000"
			setenv bootcmd "run uenvcmd"
			fatload ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr} Image;
			fatload ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr} system.dtb;
			booti ${kernel_addr} - ${fdt_addr};
			exit;
		fi
		booti ${kernel_addr} - ${fdt_addr};
		exit;
	fi
done
