#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  This script selects the environment (the backend) that a <target> board boots over TFTP+NFS.\r\n \
  Run it where tftpboot/ is served (the TFTP and NFS server, default is 192.168.100.45):\r\n \
  it makes tftpboot/<target>.scr a link to <target>-<backend>/boot.scr, which the board's\r\n \
  SD card fetches at every boot (its boot script is boot_select.cmd, see -g).\r\n \
  Selecting also gives the environment's NFS root the board's ssh host keys, those of\r\n \
  the target's other environments (scripts/common/host_keys.sh), so ssh knows the board.\r\n \
    [-t <target>]\r\n \
    [-b <backend> select <target>-<backend> from the next boot on]\r\n \
    [-r reboot the board now (ssh to the IP of the environment)]\r\n \
    [-l list the environments of <target> and the selected one (the default)]\r\n \
    [-g <file> write the SD card's boot script for <target> (boot_select.cmd, compiled)]\r\n \
    [-h help]\r\n \
  -g takes the board's IP from the environment configurations of <target>, and the\r\n \
  server, the gateway and the netmask from BOOT_SERVER_IP, BOOT_GATEWAY_IP and\r\n \
  BOOT_NETMASK (default 192.168.100.45, 192.168.100.254, 255.255.255.0)." 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source "${script_dir}"/common/common.sh
source "${script_dir}"/common/host_keys.sh

SELECT=""
REBOOT=0
LIST=0
GENERATE=""
while getopts "t:b:rlg:h" o; do
  case "${o}" in
  t)
    TARGET=${OPTARG}
    ;;
  b)
    SELECT=${OPTARG}
    ;;
  r)
    REBOOT=1
    ;;
  l)
    LIST=1
    ;;
  g)
    GENERATE=${OPTARG}
    ;;
  h)
    usage
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND - 1))

if [[ -z "${TARGET}" ]]; then
  echo "ERROR: no target (-t)"
  usage
fi
[[ -z "${SELECT}${GENERATE}" && ${REBOOT} -eq 0 ]] && LIST=1

tftp_root=${TFTP_BOOT_ROOT:-${project_dir}/tftpboot}
link="${tftp_root}/${TARGET}.scr"

# The environments of the target, from environments.txt
mapfile -t environments < <(grep -x "${TARGET}-[^ ]*" "${ENVIRONMENTS_LIST}")
if [[ ${#environments[@]} -eq 0 ]]; then
  echo "ERROR: no environment of target ${TARGET} in ${ENVIRONMENTS_LIST}"
  exit 1
fi

# The environment that ${link} points to, or ""
selected() {
  local dest
  dest=$(readlink "${link}" 2>/dev/null) || return 0
  dest=${dest%/boot.scr}
  echo "${dest##*/}"
}

# config_value <environment> <variable>: a variable of environment_cfgs/<environment>.sh
config_value() {
  (source "${environment_dir}/../environment_cfgs/$1.sh" >/dev/null 2>&1 && eval echo "\${$2}")
}

if [[ -n "${GENERATE}" ]]; then
  # One static address per board: every environment of the target must agree
  board_ip=""
  for e in "${environments[@]}"; do
    ip=$(config_value "${e}" IP)
    if [[ -n "${board_ip}" && "${ip}" != "${board_ip}" ]]; then
      echo "ERROR: the environments of ${TARGET} have different IPs (${board_ip}, ${ip} in ${e})"
      exit 1
    fi
    board_ip=${ip}
  done
  cmd=$(mktemp)
  sed -e "s/@TARGET@/${TARGET}/g" \
    -e "s/@IP@/${board_ip}/" \
    -e "s/@SERVER_IP@/${BOOT_SERVER_IP:-192.168.100.45}/" \
    -e "s/@GATEWAY_IP@/${BOOT_GATEWAY_IP:-192.168.100.254}/" \
    -e "s/@NETMASK@/${BOOT_NETMASK:-255.255.255.0}/" \
    -e "s/@SCRIPT_ADDR@/${BOOT_SCRIPT_ADDR:-0x30000000}/" \
    "${current_dir}/boot_select.cmd" >"${cmd}"
  mkimage -A arm64 -T script -C none -n "${TARGET} boot_select" -d "${cmd}" "${GENERATE}" >/dev/null
  status=$?
  rm -f "${cmd}"
  if [[ ${status} -ne 0 ]]; then
    echo "ERROR: mkimage failed"
    exit 1
  fi
  echo "SD card boot script for ${TARGET} (board ${board_ip}): ${GENERATE}"
fi

if [[ -n "${SELECT}" ]]; then
  env="${TARGET}-${SELECT}"
  if ! printf '%s\n' "${environments[@]}" | grep -qx "${env}"; then
    echo "ERROR: ${env} is not an environment (${environments[*]})"
    exit 1
  fi
  if [[ ! -f "${tftp_root}/${env}/boot.scr" ]]; then
    echo "ERROR: ${tftp_root}/${env}/boot.scr not found (bootscr_compile.sh, then copy it there)"
    exit 1
  fi
  # The NFS root of the environment: populated and exported?
  source "${script_dir}"/common/set_environment.sh "${TARGET}" "${SELECT}" >/dev/null
  nfs_root="${rootfs_dir}/${TARGET}"
  if [[ ! -e "${nfs_root}/bin/busybox" ]]; then
    echo -e "${warn}WARNING: ${nfs_root} is not populated (setup_nfs_rootfs.sh)${norm}"
  fi
  if command -v exportfs >/dev/null 2>&1 && [[ $(id -u) -eq 0 ]]; then
    exportfs | grep -q "^${nfs_root}\([[:space:]]\|$\)" ||
      echo -e "${warn}WARNING: ${nfs_root} is not exported (/etc/exports, exportfs -r)${norm}"
  fi
  # The board presents the same ssh host keys in every environment: copy the
  # types this NFS root lacks from the other environments (host_keys.sh)
  if [[ $(id -u) -eq 0 ]]; then
    install_board_host_keys "${TARGET}" "${SELECT}"
  else
    other=$(host_key_source "${TARGET}" "${SELECT}")
    [[ -n "${other}" && -n "$(host_keys_differ "${TARGET}" "${SELECT}" "${other}")" ]] &&
      echo -e "${warn}WARNING: ${env} has other ssh host keys than ${TARGET}-${other}${norm}"
  fi
  ln -sfn "${env}/boot.scr" "${link}" || exit 1
  echo "${TARGET} boots ${env} from the next boot on (${link} -> ${env}/boot.scr)"
fi

if [[ ${LIST} -eq 1 ]]; then
  current=$(selected)
  echo "Environments of ${TARGET} (${link}):"
  for e in "${environments[@]}"; do
    mark=" "
    [[ "${e}" == "${current}" ]] && mark="*"
    if [[ -f "${tftp_root}/${e}/boot.scr" ]]; then
      echo "  ${mark} ${e}"
    else
      echo "  ${mark} ${e} (no ${e}/boot.scr: not selectable)"
    fi
  done
  [[ -z "${current}" ]] && echo "  none selected: the board boots from its SD card"
fi

if [[ ${REBOOT} -eq 1 ]]; then
  env=$(selected)
  if [[ -z "${env}" ]]; then
    echo "ERROR: nothing selected for ${TARGET}, not rebooting"
    exit 1
  fi
  ip=$(config_value "${env}" IP)
  user=$(config_value "${env}" USER)
  ssh_args=$(config_value "${env}" SSH_ARGS)
  echo "Rebooting ${user:-root}@${ip} ..."
  # Detached, so that ssh returns before the connection drops
  if ! ssh -o ConnectTimeout=10 ${ssh_args} "${user:-root}@${ip}" 'nohup sh -c "sleep 1; reboot" >/dev/null 2>&1 &'; then
    echo "The board did not answer: power-cycle it, the selection applies at its next boot"
    exit 1
  fi
fi

exit 0
