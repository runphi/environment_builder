#!/bin/bash

#WARNING: configure with the right .cell
BAREMETAL_INMATE_CELL="zynqmp-zcu104-APU-inmate-demo.cell"

jailhouse cell create ${JAILHOUSE_DIR}/configs/arm64/${BAREMETAL_INMATE_CELL}
jailhouse cell load inmate-demo-APU ${JAILHOUSE_DIR}/inmates/demos/arm64/gic-demo.bin 
jailhouse cell start inmate-demo-APU
