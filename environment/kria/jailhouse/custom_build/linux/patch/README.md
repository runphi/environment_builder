
- jailhouse_enable: A collection of patches from the jailhouse mantainer Kizka. The patches are necessary to run jailhouse the kernel with all its features.

- preempt_rt: The patch enable the fully preemption mode in the kernel (https://wiki.linuxfoundation.org/realtime/start). It is 6.1.69-rt21 adapted to linux-xlnx 6.1.70 (xlnx_rebase_v6.1_LTS), the same as kria-kvm's; the header of the patch says what was changed. Applied after jailhouse_enable and omnivisor (environment_cfgs/kria-jailhouse.sh); jailhouse_kria_isolcpu_kernel_defconfig selects PREEMPT_RT, and the kernel and the Jailhouse driver build with it.

- omnvisor: The patches modifies the remoteproc driver to make it compatible with jailhouse-omnivisor. N.B. remoteproc doesn't work standalone with this patch