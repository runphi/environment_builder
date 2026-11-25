#!/bin/bash

cd /lib/firmware

echo stop > /sys/class/remoteproc/remoteproc1/state
cp /root/non_rootcell/RPU1/rpu1-membomb.elf /lib/firmware
echo rpu1-membomb.elf  > /sys/class/remoteproc/remoteproc1/firmware
echo start > /sys/class/remoteproc/remoteproc1/state
