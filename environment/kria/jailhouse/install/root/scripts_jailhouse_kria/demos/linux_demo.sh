#!/bin/bash

#WARNING: configure with the right .cell and .dtb
# The cell (CPUs 2-3, RAM at 0x47000000, reserved in system_omnv.dts) shares the
# root cell's UART (0xff010000), its ttyPS0: its console is the board's serial port.
# The kernel is this environment's (it has the PCI host and ivshmem-net drivers for
# the cell's two ivshmem links to the root cell's eth1 and eth2). Arguments are
# added to the kernel command line, e.g. a static address on the first link:
#   linux_demo.sh ip=192.0.2.10::192.0.2.1:255.255.255.0::eth0:off

LINUX_INMATE_CELL="zynqmp-kv260-linux-demo.cell"
LINUX_INMATE_DTB="inmate-zynqmp-kv260.dtb"

jailhouse cell linux \
	${JAILHOUSE_DIR}/configs/arm64/${LINUX_INMATE_CELL} \
	${NON_ROOTCELL_LINUX_DIR}/Image \
	-d ${JAILHOUSE_DIR}/configs/arm64/dts/${LINUX_INMATE_DTB} \
	-i ${NON_ROOTCELL_LINUX_DIR}/initrd \
	-c "console=ttyPS0,115200 $*"
