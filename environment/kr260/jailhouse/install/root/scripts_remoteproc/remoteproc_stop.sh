#!/bin/bash

cd /lib/firmware

echo stop > /sys/class/remoteproc/remoteproc0/state
