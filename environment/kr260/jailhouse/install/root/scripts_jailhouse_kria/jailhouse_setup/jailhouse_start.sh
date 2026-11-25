#!/bin/bash

# Default cell configuration
PLATFORM="zynqmp-kr260"

# Check for input parameter
if [ "$1" == "-o" ] || [ "$1" == "--omnv" ]; then
       ROOT_CELL="${PLATFORM}-omnv.cell"
elif [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
       echo "Usage: $0 [-o | --omnv] [-h | --help]"
       echo "  -o, --omnv    Use the OMNV cell configuration"
       echo "  -h, --help    Display this help message"
       exit 0
else
       ROOT_CELL="${PLATFORM}.cell"
fi

echo "Using root cell configuration: ${ROOT_CELL}"

# The KR260's Omnivisor root cell (configs/arm64/zynqmp-kr260-omnv.c, as patched by
# environment_builder) loads no FPGA base design at enable time: there is no DFX
# design of the Omnivisor for the KR260 (the KV260's root cell loads dfx_wrapper.bit).

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
