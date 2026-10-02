
- jailhouse_enable: A collection of patches from the jailhouse mantainer Kizka. The patches are necessary to run jailhouse the kernel with all its features.

- preempt-rt: The patch enable the fully preemption mode in the kernel (https://wiki.linuxfoundation.org/realtime/start). It is 6.1.69-rt21 adapted to linux-xlnx 6.1.70 (xlnx_rebase_v6.1_LTS); the header of the patch says what was changed. Enable PREEMPT_RT (needs EXPERT) in the kernel defconfig as well.
