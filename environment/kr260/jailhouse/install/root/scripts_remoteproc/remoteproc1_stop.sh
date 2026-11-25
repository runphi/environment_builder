#!/bin/bash

cd /lib/firmware

echo stop > /sys/class/remoteproc/remoteproc1/state
