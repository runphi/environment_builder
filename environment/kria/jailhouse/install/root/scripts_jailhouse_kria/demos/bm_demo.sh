#!/bin/bash
#
# Start a bare-metal demo cell on the KV260 with the Omnivisor Jailhouse fork.
# Enable the hypervisor first with the Omnivisor root cell:
#   ~/scripts_jailhouse_kria/jailhouse_setup/jailhouse_start.sh -o
#
# Usage: bm_demo.sh [CPU] [DEMO]
#   CPU:  APU | RPU0 | RPU1 | RISCV   (RPU is RPU0)
#   DEMO: the demo name; run without it to list the demos of that CPU.
#
#   APU:   ${JAILHOUSE_DIR}/inmates/demos/arm64/<demo>.bin, loaded in the cell's memory
#   RPU0/RPU1/RISCV: ${JAILHOUSE_DIR}/inmates/demos/<arch>/src_<demo>/<demo>-demo.elf,
#          copied into /lib/firmware and loaded with "jailhouse cell load <cell> -r <elf> <core>"
#          (Documentation/omnivisor.md). The RISC-V soft core (core 2) also needs the bitstreams,
#          the device-tree overlay and the pico32_remoteproc module named in the cells
#          (dfx_wrapper.bit, dfx_picorv.bit, pico32.dtbo) in /lib/firmware.

PLATFORM="zynqmp-kv260"
JAILHOUSE_DIR="${JAILHOUSE_DIR:-/root/jailhouse}"
FIRMWARE_DIR="${FIRMWARE_DIR:-/lib/firmware}"

CPU="${1:-}"
DEMO="${2:-}"

if [ -z "${CPU}" ]; then
    echo "Choose the CPU of the inmate cell (APU, RPU0, RPU1, RISCV):"
    read -r CPU
fi
[ "${CPU}" == "RPU" ] && CPU="RPU0"

case "${CPU}" in
    APU)   ARCH="arm64"; CORE="" ;;
    RPU0)  ARCH="armr5"; CORE=0; PREFIX="rpu0" ;;
    RPU1)  ARCH="armr5"; CORE=1; PREFIX="rpu1" ;;
    RISCV) ARCH="riscv"; CORE=2; PREFIX="riscv" ;;
    *) echo "Invalid CPU '${CPU}' (APU, RPU0, RPU1, RISCV)"; exit 1 ;;
esac

CELL="${JAILHOUSE_DIR}/configs/arm64/${PLATFORM}-${CPU}-inmate-demo.cell"
INMATE="inmate-demo-${CPU}"
DEMO_DIR="${JAILHOUSE_DIR}/inmates/demos/${ARCH}"

# The demos of this CPU: name -> file
demo_files() {
    if [ "${ARCH}" == "arm64" ]; then
        ls "${DEMO_DIR}"/*.bin 2>/dev/null
    else
        ls "${DEMO_DIR}"/src_"${PREFIX}"-*/"${PREFIX}"-*-demo.elf 2>/dev/null
    fi
}
demo_name() {
    local f
    f=$(basename "$1")
    if [ "${ARCH}" == "arm64" ]; then
        echo "${f%.bin}"
    else
        f="${f#"${PREFIX}"-}"
        echo "${f%-demo.elf}"
    fi
}

if [ -z "${DEMO}" ]; then
    echo "Choose the demo:"
    for f in $(demo_files); do demo_name "$f"; done
    read -r DEMO
fi

DEMO_FILE=""
for f in $(demo_files); do
    if [ "$(demo_name "$f")" == "${DEMO}" ]; then
        DEMO_FILE="$f"
        break
    fi
done
if [ -z "${DEMO_FILE}" ]; then
    echo "No demo '${DEMO}' for ${CPU}; the demos are:"
    for f in $(demo_files); do demo_name "$f"; done
    exit 1
fi

set -e
jailhouse cell create "${CELL}"
if [ -z "${CORE}" ]; then
    jailhouse cell load "${INMATE}" "${DEMO_FILE}"
else
    mkdir -p "${FIRMWARE_DIR}"
    cp "${DEMO_FILE}" "${FIRMWARE_DIR}/"
    jailhouse cell load "${INMATE}" -r "$(basename "${DEMO_FILE}")" "${CORE}"
fi
jailhouse cell start "${INMATE}"
echo "Started ${INMATE} with ${DEMO_FILE}; stop it with: jailhouse cell destroy ${INMATE}"
