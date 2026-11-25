
- jailhouse_enable: A collection of patches from the jailhouse mantainer Kizka. The patches are necessary to run jailhouse the kernel with all its features.

- preempt_rt: The patch enable the fully preemption mode in the kernel (https://wiki.linuxfoundation.org/realtime/start). It is 6.1.69-rt21 adapted to linux-xlnx 6.1.70 (xlnx_rebase_v6.1_LTS), the same as kria-kvm's; the header of the patch says what was changed. Applied after jailhouse_enable and omnivisor (environment_cfgs/kria-jailhouse.sh); jailhouse_kria_isolcpu_kernel_defconfig selects PREEMPT_RT, and the kernel and the Jailhouse driver build with it.

- omnvisor: The patches modifies the remoteproc driver to make it compatible with jailhouse-omnivisor. N.B. remoteproc doesn't work standalone with this patch

- omnv_fpga_rproc: the remoteproc drivers of the Omnivisor's FPGA soft cores, pico32_remoteproc (PicoRV32 RISC-V) and vs_classic_remoteproc (VS controller), from DanieleOttaviano/vs_test_omnv with two probe fixes (see the patch header). The Jailhouse driver loads them when a cell loads their partial bitstream; jailhouse_kria_isolcpu_kernel_defconfig builds them as modules.
