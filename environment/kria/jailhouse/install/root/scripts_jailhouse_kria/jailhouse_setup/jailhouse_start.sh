#!/bin/bash

# Default cell configuration
PLATFORM="zynqmp-kv260"

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

# The Omnivisor root cell loads its FPGA base design at enable time
# (.fpga_base_bitstream of configs/arm64/zynqmp-kv260-omnv.c): without it,
# "jailhouse enable" fails with "failed to load root bitstream"
BASE_BITSTREAM="dfx_wrapper.bit"
if [ "${ROOT_CELL}" == "${PLATFORM}-omnv.cell" ] && [ ! -e "/lib/firmware/${BASE_BITSTREAM}" ]; then
       echo "ERROR: /lib/firmware/${BASE_BITSTREAM} is missing: the Omnivisor root cell loads it"
       echo "       into the FPGA when Jailhouse is enabled (see SETUP.md, Jailhouse and the Omnivisor)"
       exit 1
fi

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
