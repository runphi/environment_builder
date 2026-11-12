#---------------------------------------------------------------
# boot_select.cmd - network boot entry of the @TARGET@ board, for its SD card
#
# Template: scripts/remote/switch_backend.sh -t <target> -g <file> fills in
# the @...@ fields and compiles it. On the SD card's FAT partition it is the
# boot script of the network boot mode (on the Kria, boot_tftp.scr, which
# /root/boot_mode.sh tftp copies over boot.scr).
#
# It fetches @TARGET@.scr from the TFTP server and runs it. On the server,
# switch_backend.sh -t @TARGET@ -b <backend> makes @TARGET@.scr a link to
# @TARGET@-<backend>/boot.scr, the network boot script of that environment,
# so the server selects the environment (the backend) that the board boots.
# Without the server or without a selection, it runs boot_sd.scr from the
# same FAT partition, the board's own system, if there is one.
#---------------------------------------------------------------

setenv ipaddr      @IP@
setenv serverip    @SERVER_IP@
setenv gatewayip   @GATEWAY_IP@
setenv netmask     @NETMASK@

# Where the selected script goes: away from what the boot scripts of the
# environments load (kernels, Xen, DTBs, isolargs.txt).
setenv select_addr @SCRIPT_ADDR@

echo "------------------------------------------------------------"
echo "TFTP: ${serverip}:@TARGET@.scr, the environment the server selects"
if tftpboot ${select_addr} @TARGET@.scr; then
	source ${select_addr}
fi

echo "------------------------------------------------------------"
echo "No @TARGET@.scr from ${serverip}: running boot_sd.scr from the SD card"
if test -n "${devtype}"; then
	if load ${devtype} ${devnum}:${distro_bootpart} ${select_addr} boot_sd.scr; then
		source ${select_addr}
	fi
fi
echo "boot_sd.scr failed or is missing: back to U-Boot's distro boot"
