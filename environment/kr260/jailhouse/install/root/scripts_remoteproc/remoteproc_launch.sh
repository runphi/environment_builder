#!/bin/bash

cd /lib/firmware

echo stop > /sys/class/remoteproc/remoteproc0/state
cp /root/jailhouse/inmates/demos/armr5/baremetal-demo.elf /lib/firmware
echo baremetal-demo.elf  > /sys/class/remoteproc/remoteproc0/firmware
echo start > /sys/class/remoteproc/remoteproc0/state
