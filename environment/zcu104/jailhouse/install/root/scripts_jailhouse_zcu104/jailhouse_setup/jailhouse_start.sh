#!/bin/bash

# Default cell configuration
PLATFORM="zynqmp-zcu104"

# The default is the Omnivisor root cell WITHOUT cache colouring, which is the
# combination verified working on this board. The colouring variants (-c) leave
# part of root Linux's RAM read-only in stage-2: random pages fault on write
# (ESR 0x9600004f = data abort, write, permission fault at level 3), which shows
# up as processes dying in execve. Keep them behind an explicit flag until the
# colouring configuration is fixed.
if [ "$1" == "-c" ] || [ "$1" == "--col" ]; then
       ROOT_CELL="${PLATFORM}-root-col-omnv.cell"
       echo "WARNING: cache colouring is currently broken on this board;"
       echo "         expect stage-2 write permission faults in the root cell."
elif [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
       echo "Usage: $0 [-o | --omnv] [-c | --col] [-h | --help]"
       echo "  (no args)     Omnivisor root cell, no colouring (verified working)"
       echo "  -o, --omnv    Same as the default; kept for backwards compatibility"
       echo "  -c, --col     Colouring + Omnivisor root cell (currently broken)"
       echo "  -h, --help    Display this help message"
       exit 0
else
       # covers both the no-argument case and -o/--omnv
       ROOT_CELL="${PLATFORM}-omnv.cell"
fi

echo "Using root cell configuration: ${ROOT_CELL}"

# Check if the firmware directory exists
if [ -d "/lib/firmware" ]; then
       echo "firmware directory exists!"
else
       mkdir /lib/firmware
fi

# Clean up
jailhouse disable
rmmod jailhouse

# Copy the hypervisor image in the firmware directory
cp ${JAILHOUSE_DIR}/hypervisor/jailhouse.bin /lib/firmware/

# Insert the jailhouse module
insmod ${JAILHOUSE_DIR}/driver/jailhouse.ko

# Start the hypervisor
jailhouse enable ${JAILHOUSE_DIR}/configs/arm64/${ROOT_CELL}
