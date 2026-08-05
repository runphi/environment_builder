# U-Boot boot script for ZCU104 (AArch64)

# If these aren't pre-set by your U-Boot, define safe load addresses.
if test -z "${kernel_addr_r}"; then setenv kernel_addr_r 0x02000000; fi
if test -z "${fdt_addr_r}";    then setenv fdt_addr_r    0x01000000; fi

# Avoid relocation limits
setenv fdt_high    0xffffffffffffffff
setenv initrd_high 0xffffffffffffffff

# Default to partition 1 for boot files if not provided by distro_bootcmd
if test -z "${distro_bootpart}"; then setenv distro_bootpart 1; fi

# Try mmc0 then mmc1 (or whatever is in ${boot_targets})
for boot_target in ${boot_targets}; do
    if test "${boot_target}" = "mmc0" || test "${boot_target}" = "mmc1"; then
        setenv devtype mmc
        if test "${boot_target}" = "mmc0"; then setenv devnum 0; else setenv devnum 1; fi

        if mmc dev ${devnum}; then
            # Rootfs is on partition 2 -> fetch PARTUUID and compose bootargs
            part uuid ${devtype} ${devnum}:2 rootuuid
            setenv bootargs "clk_ignore_unused earlycon console=ttyPS0,115200 root=PARTUUID=${rootuuid} rw rootwait"

            # Prefer a FIT image if present
            if test -e ${devtype} ${devnum}:${distro_bootpart} /image.ub; then
                echo "Booting FIT from ${devtype} ${devnum}:${distro_bootpart} ..."
                fatload ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} image.ub
                bootm ${kernel_addr_r}
            elif test -e ${devtype} ${devnum}:${distro_bootpart} /Image; then
                echo "Booting Image+DTB from ${devtype} ${devnum}:${distro_bootpart} ..."
                fatload ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} Image
                fatload ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} system.dtb
                booti ${kernel_addr_r} - ${fdt_addr_r}
            else
                echo "No kernel found on ${devtype} ${devnum}:${distro_bootpart}"
            fi
        fi
    fi
done

echo "No valid boot target succeeded; resetting..."
sleep 2
reset
