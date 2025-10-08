#!/bin/bash

usage() {
  echo -e "Usage: $0 \r\n \
  This script load the <backend> specific install directory in the root of the <target> filesystem:\r\n \
    [-t <target>]\r\n \
    [-b <backend>]\r\n \
    [-f force sync all files]\r\n \
    [-h help]" 1>&2
  exit 1
}

# DIRECTORIES
current_dir=$(dirname -- "$(readlink -f -- "$0")")
script_dir=$(dirname "${current_dir}")
source ${script_dir}/common/common.sh

FORCE_SYNC=false

while getopts "t:b:fh" o; do
  case "${o}" in
  t)
    TARGET=${OPTARG}
    ;;
  b)
    BACKEND=${OPTARG}
    ;;
  f)
    FORCE_SYNC=true
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

# Set the Environment
source ${script_dir}/common/set_environment.sh ${TARGET} ${BACKEND}

echo "REMOTE: ${USER}@${IP}:${RSYNC_REMOTE_PATH}"
echo "ARGS: ${RSYNC_ARGS} ${RSYNC_ARGS_SSH}"

# Determine rsync flags based on force option
if [ "$FORCE_SYNC" = true ]; then
  RSYNC_FLAGS="-rIv"  # Remove -u, add -I to ignore timestamps
  echo "FORCE SYNC: Transferring all files unconditionally"
else
  RSYNC_FLAGS="-ruv"  # Standard sync with -u flag
fi

if [ -z "${RSYNC_ARGS_SSH}" ]; then
  rsync ${RSYNC_FLAGS} ${RSYNC_ARGS} ${install_dir}/* root@${IP}:/
else
  rsync ${RSYNC_FLAGS} ${RSYNC_ARGS} "${RSYNC_ARGS_SSH}" ${install_dir}/* root@${IP}:/
fi
