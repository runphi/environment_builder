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
			# CPU 3 only: the inmate cell (zynqmp-zcu104-APU-inmate-demo.cell) runs
			# there, and the root cell needs 0-2 for the interference workload.
			# deferred_probe_timeout works around a dead i2c mux on this board.
			# processor.max_cstate / processor_idle.max_cstate are x86-only, omitted.
			# nosoftlockup / nowatchdog are omitted on purpose: this defconfig has
			# CONFIG_SOFTLOCKUP_DETECTOR unset, so the kernel does not register
			# those parameters and reports them under "Unknown kernel command line
			# parameters". They are no-ops here; the KV260 cmdline carries them
			# only because that config enables the lockup detector.
			# NOTE: keep "=" out of these comments so that the boot.scr
			# verification grep in HANDOFF/DEMO still matches only the real line.
			#
			# 2026-08-05: nohz_full / rcu_nocbs / rcu_nocb_poll removed, and the
			# "nohz," prefix with them. Jailhouse hotplugs CPU 3 out and runs the
			# inmate there, so no Linux userspace ever runs on it: nohz_full for
			# that CPU buys nothing, rcu_nocbs pushes its RCU callbacks onto the
			# housekeeping CPUs 0-2 that the experiment measures, and rcu_nocb_poll
			# adds a permanently runnable kthread to those same three cores. The
			# Jailhouse+stressor wedge got markedly faster when they were added.
			setenv bootargs "isolcpus=domain,managed_irq,3 skew_tick=1 deferred_probe_timeout=1 earlycon clk_ignore_unused root=/dev/mmcblk0p2 rw rootwait"
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
