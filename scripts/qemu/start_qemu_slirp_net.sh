#!/bin/bash

# start_qemu.sh with the slirp network, whatever QEMU_NET says: the VM's ssh is
# forwarded to localhost (port QEMU_SSH_PORT of the environment_cfgs file)
current_dir=$(dirname -- "$(readlink -f -- "$0")")
QEMU_NET=slirp exec "${current_dir}"/start_qemu.sh "$@"
