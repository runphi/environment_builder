#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  This script loads the selected components into the target filesystem:\r\n \
    [-a load all]\r\n \
    [-j load jailhouse]\r\n \
    [-r <RUNPHI MANAGER PATH> load runPHI]\r\n \
    [-g load the guest kernel of the test images (kvm and xen backends)]\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-p <runPHI_manager_path> (required with -r or -a)]\r\n \
    [-h help]" 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source ${script_dir}/common/common.sh

J=0
R=0
G=0
A=0

while getopts "jragt:b:p:h" o; do
  case "${o}" in
  j)
    J=1
    ;;
  r)
    R=1
    runPHI_dir=${OPTARG}
    ;;
  a)
    J=1
    R=1
    A=1
    ;;
  g)
    G=1
    ;;
  t)
    TARGET=${OPTARG}
    ;;
  b)
    BACKEND=${OPTARG}
    ;;
  p)
    runPHI_dir=${OPTARG}
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

# Validate input
if [ "${J}" -eq 0 ] && [ "${R}" -eq 0 ] && [ "${G}" -eq 0 ]; then
  echo "ERROR: Select a project to sync!"
  usage
fi

if [ "${R}" -eq 1 ]; then
  if [ -z "${runPHI_dir}" ]; then
    echo "ERROR: -p <runPHI_manager_path> is required when using -r or -a"
    usage
  fi
  if [ ! -d "${runPHI_dir}" ]; then
    echo "ERROR: The provided path '${runPHI_dir}' does not exist or is not a directory."
    exit 1
  fi
fi

# Set the Environment
source ${script_dir}/common/set_environment.sh ${TARGET} ${BACKEND}

echo "REMOTE: ${USER}@${IP}:${RSYNC_REMOTE_PATH}"
echo "ARGS: ${RSYNC_ARGS} ${RSYNC_ARGS_SSH}"

RUNPHI_INSTALL_DIR="/usr/share/runPHI"

# KVM and Xen backends: there is no Jailhouse, and runPHI is a single binary (with
# caronte, the keep-alive helper of backend_xen); -a loads it and the guest kernel
if [[ "${BACKEND}" == "kvm" || "${BACKEND}" == "xen" ]]; then
  if [ "${J}" -eq 1 ] && [ "${A}" -eq 0 ]; then
    echo "ERROR: the ${BACKEND} backend has no Jailhouse to load"
    exit 1
  fi
  J=0
  [ "${A}" -eq 1 ] && G=1
  runphi_bin=${runPHI_dir}/rust_runphi/target/aarch64-unknown-linux-gnu/release/runphi
  if [ "${R}" -eq 1 ] && [ ! -f "${runphi_bin}" ]; then
    echo "ERROR: no ${runphi_bin}: build runPHI first (see environment/${TARGET}/${BACKEND}/SETUP.md)"
    exit 1
  fi
elif [ "${G}" -eq 1 ]; then
  echo "ERROR: -g is for the kvm and xen backends only"
  exit 1
fi

ssh ${SSH_ARGS} ${USER}@${IP} "date -u -s '$(date -u +'%Y-%m-%d %H:%M:%S')'"

if [[ "${BACKEND}" == "kvm" || "${BACKEND}" == "xen" ]]; then
  # runPHI where /etc/docker/daemon.json expects it, and the kernel that
  # /root/guest/make_test_images.sh puts in the test images
  [ ${R} -eq 1 ] && rsync -tpv --chmod=755 ${RSYNC_ARGS} ${RSYNC_ARGS_SSH:+"${RSYNC_ARGS_SSH}"} "${runphi_bin}" ${USER}@${IP}:/usr/local/sbin/runphi
  if [ ${R} -eq 1 ] && [[ "${BACKEND}" == "xen" ]]; then
    ssh ${SSH_ARGS} ${USER}@${IP} "mkdir -p ${RUNPHI_INSTALL_DIR}"
    rsync -tpv --chmod=755 ${RSYNC_ARGS} ${RSYNC_ARGS_SSH:+"${RSYNC_ARGS_SSH}"} "${runPHI_dir}"/target/runPHI_cell_configs/caronte ${USER}@${IP}:${RUNPHI_INSTALL_DIR}/caronte
  fi
  [ ${G} -eq 1 ] && rsync -tv ${RSYNC_ARGS} ${RSYNC_ARGS_SSH:+"${RSYNC_ARGS_SSH}"} "${boot_dir}"/Image ${USER}@${IP}:/root/guest/Image
  exit 0
fi

if [ -z "${RSYNC_ARGS_SSH}" ]; then
  [ ${J} -eq 1 ] && rsync -ruv --modify-window=1 ${RSYNC_ARGS} ${jailhouse_dir} ${USER}@${IP}:${RSYNC_REMOTE_PATH}

  if [ ${R} -eq 1 ]; then
    rsync -ruv ${RSYNC_ARGS} ${runPHI_dir}/target ${USER}@${IP}:${RSYNC_REMOTE_PATH}
    ssh ${SSH_ARGS} ${USER}@${IP} "mkdir -p ${RUNPHI_INSTALL_DIR}"
    rsync -ruv ${RSYNC_ARGS} ${runPHI_dir}/target/runPHI_cell_configs/* ${USER}@${IP}:${RUNPHI_INSTALL_DIR}
    rsync -ruv ${RSYNC_ARGS} ${runPHI_dir}/target/target_configs/${TARGET}_platform_info.toml ${USER}@${IP}:${RUNPHI_INSTALL_DIR}/platform_info.toml
    rsync -ruv ${RSYNC_ARGS} ${runPHI_dir}/target/target_configs/${TARGET}_state.toml ${USER}@${IP}:${RUNPHI_INSTALL_DIR}/state.toml
    rsync -ruv ${RSYNC_ARGS} ${runPHI_dir}/target/target_configs/${TARGET}_state.toml ${USER}@${IP}:${RUNPHI_INSTALL_DIR}/initial_state.toml

  fi
else
  [ ${J} -eq 1 ] && rsync -ruv --modify-window=1 ${RSYNC_ARGS} "${RSYNC_ARGS_SSH}" ${jailhouse_dir} ${USER}@${IP}:${RSYNC_REMOTE_PATH}
  [ ${R} -eq 1 ] && rsync -ruv ${RSYNC_ARGS} "${RSYNC_ARGS_SSH}" ${runPHI_dir} ${USER}@${IP}:${RSYNC_REMOTE_PATH}

  [ ${R} -eq 1 ] && rsync -ruv ${RSYNC_ARGS} "${RSYNC_ARGS_SSH}" ${runPHI_dir}/target ${USER}@${IP}:${RSYNC_REMOTE_PATH} # cp all runPHI_dir
  [ ${R} -eq 1 ] && ssh ${SSH_ARGS} ${USER}@${IP} "mkdir -p ${RUNPHI_INSTALL_DIR}"
  [ ${R} -eq 1 ] && rsync -ruv ${RSYNC_ARGS} "${RSYNC_ARGS_SSH}" ${runPHI_dir}/target/runPHI_cell_configs/* ${USER}@${IP}:${RUNPHI_INSTALL_DIR}
  [ ${R} -eq 1 ] && rsync -ruv ${RSYNC_ARGS} "${RSYNC_ARGS_SSH}" ${runPHI_dir}/target/target_configs/${TARGET}_platform_info.toml ${USER}@${IP}:${RUNPHI_INSTALL_DIR}/platform_info.toml
  [ ${R} -eq 1 ] && rsync -ruv ${RSYNC_ARGS} "${RSYNC_ARGS_SSH}" ${runPHI_dir}/target/target_configs/${TARGET}_state.toml ${USER}@${IP}:${RUNPHI_INSTALL_DIR}/state.toml
fi
