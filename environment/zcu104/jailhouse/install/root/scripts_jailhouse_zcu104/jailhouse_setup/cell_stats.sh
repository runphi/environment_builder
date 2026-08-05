#!/bin/bash
#
# Plain-text replacement for "jailhouse cell stats".
#
# The upstream jailhouse-cell-stats tool imports Python's curses module, which
# this buildroot rootfs does not ship (BR2_PACKAGE_PYTHON3_CURSES is not set,
# and ncurses headers are absent from staging). curses is only used to draw the
# live-updating screen: the counters themselves are ordinary sysfs files under
# /sys/devices/jailhouse/cells/<id>/statistics/, so no Python is needed at all.
#
# Usage: cell_stats.sh [-c CELL] [-i INTERVAL] [-p] [-h]

SYSFS="/sys/devices/jailhouse/cells"
CELL=""
INTERVAL=0
PERCPU=0

usage() {
	echo "Usage: $0 [-c CELL] [-i INTERVAL] [-p] [-h]"
	echo "  -c CELL       cell id or name (default: all cells)"
	echo "  -i INTERVAL   repeat every INTERVAL seconds, showing the delta"
	echo "  -p            also show the per-CPU breakdown"
	echo "  -h            this help"
	exit 0
}

while getopts "c:i:ph" o; do
	case "${o}" in
	c) CELL=${OPTARG} ;;
	i) INTERVAL=${OPTARG} ;;
	p) PERCPU=1 ;;
	h) usage ;;
	*) usage ;;
	esac
done

if [ ! -d "${SYSFS}" ]; then
	echo "ERROR: ${SYSFS} not found - is the hypervisor enabled?" >&2
	exit 1
fi

# Resolve a cell id or name to its sysfs directory.
resolve_cell() {
	for d in "${SYSFS}"/*/; do
		[ -d "${d}" ] || continue
		id=$(basename "${d}")
		name=$(cat "${d}/name" 2>/dev/null)
		if [ -z "$1" ] || [ "$1" = "${id}" ] || [ "$1" = "${name}" ]; then
			echo "${d}"
		fi
	done
}

print_cell() {
	d="$1"
	id=$(basename "${d}")
	name=$(cat "${d}/name" 2>/dev/null)
	state=$(cat "${d}/state" 2>/dev/null)
	cpus=$(cat "${d}/cpus_assigned_list" 2>/dev/null)
	echo "cell ${id}  \"${name}\"  state=${state}${cpus:+  cpus=${cpus}}"

	for f in "${d}"/statistics/*; do
		[ -f "${f}" ] || continue
		k=$(basename "${f}")
		v=$(cat "${f}" 2>/dev/null)
		if [ "${INTERVAL}" != "0" ]; then
			prev_var="prev_${id}_${k}"
			eval "prev=\${${prev_var}:-}"
			if [ -n "${prev}" ]; then
				printf "  %-22s %12s  (%+d)\n" "${k}" "${v}" "$((v - prev))"
			else
				printf "  %-22s %12s\n" "${k}" "${v}"
			fi
			eval "${prev_var}=\${v}"
		else
			printf "  %-22s %12s\n" "${k}" "${v}"
		fi
	done

	if [ "${PERCPU}" = "1" ]; then
		for c in "${d}"/statistics/cpu*/; do
			[ -d "${c}" ] || continue
			echo "  [$(basename "${c}")]"
			for f in "${c}"*; do
				[ -f "${f}" ] || continue
				printf "    %-20s %12s\n" "$(basename "${f}")" "$(cat "${f}" 2>/dev/null)"
			done
		done
	fi
}

cells=$(resolve_cell "${CELL}")
if [ -z "${cells}" ]; then
	echo "ERROR: no cell matching '${CELL}'. Available:" >&2
	for d in "${SYSFS}"/*/; do
		[ -d "${d}" ] && echo "  $(basename "${d}")  $(cat "${d}/name" 2>/dev/null)" >&2
	done
	exit 1
fi

while true; do
	[ "${INTERVAL}" != "0" ] && printf "\033[H\033[2J"
	date
	for d in ${cells}; do
		print_cell "${d}"
	done
	[ "${INTERVAL}" = "0" ] && break
	sleep "${INTERVAL}"
done
