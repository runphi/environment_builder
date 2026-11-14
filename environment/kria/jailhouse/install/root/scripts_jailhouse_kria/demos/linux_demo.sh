#!/bin/bash

#WARNING: configure with the right .cell and .dtb
# The cell (CPUs 2-3, RAM at 0x47000000, reserved in system_omnv.dts) shares the
# root cell's UART (0xff010000), its ttyPS0: its console is the board's serial port.

LINUX_INMATE_CELL="zynqmp-kv260-linux-demo.cell"
LINUX_INMATE_DTB="inmate-zynqmp-kv260.dtb"

jailhouse cell linux \
	${JAILHOUSE_DIR}/configs/arm64/${LINUX_INMATE_CELL} \
	${NON_ROOTCELL_LINUX_DIR}/Image \
	-d ${JAILHOUSE_DIR}/configs/arm64/dts/${LINUX_INMATE_DTB} \
	-i ${NON_ROOTCELL_LINUX_DIR}/initrd \
	-c "console=ttyPS0,115200"
