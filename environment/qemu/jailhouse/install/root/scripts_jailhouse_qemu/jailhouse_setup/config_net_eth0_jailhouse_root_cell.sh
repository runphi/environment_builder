#!/bin/bash

# Configure eth0 again as at boot: with QEMU_NET="tap", the address and gateway
# that start_qemu.sh put on the kernel command line (see /etc/init.d/S93config_net)
/etc/init.d/S93config_net start
