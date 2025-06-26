# Kria Board Remote Setup Guide

To have a stable setup, the idea is to load a certfied ubuntu on the sd card of the board as a 
backup image. Then using TFTP you can load the Image and the device tree generated through 
this repo, and using NFS after that you can load the filesystem.

## Loading a Stable Ubuntu on the SD Card

1. **Download Ubuntu Image:**
    - Visit the official Ubuntu website and download the Image (22.04): https://ubuntu.com/download/amd

2. **Prepare the SD Card:**
    - Insert the SD card into your computer.
    - Discover the internal storage device name: This is usually /dev/sda but it’s important to first make sure. 
      One of the easiest ways is to open GPartEd and use the drop-down menu in the top-right to select the correct
      device. You’ll see storage space and layout below. Make a note of the device name.
    - Use `dd` to write the Ubuntu image to the SD card:
    - Open the terminal application and enter the following command, adjusting the paths to the Ubuntu Core download and the internal storage device accordingly:
      ```sh 
      xzcat ~/Downloads/<ubuntu_image>.img.xz | \
      sudo dd of=/dev/<target disk device> bs=32M status=progress; sync
      ```

3. **Boot the Kria Board:**
    - Insert the SD card into the Kria board.
    - Connect the board to a power source and to the PC using the uart.
    - Power on the board.
    - Connect to the uart using minicom (or picocom).
      ```sh
      sudo minicom -D /dev/ttyUSB1 
      ```

## Setup Server: DHCP, TFTP and NFS 
1. **Setup DHCP Server:**
    - Install DHCP server to give to the board a specific IP every time.

2. **Setup TFTP Server:**
    - Install TFTP server on your host machine:
      ```sh
      sudo apt-get install tftpd-hpa
      ```
    - Configure TFTP server by editing `/etc/default/tftpd-hpa`:
      ```sh
      TFTP_USERNAME="tftp"
      TFTP_DIRECTORY="/home/environment/kria/jailhouse/output/boot"
      TFTP_ADDRESS=":69"
      TFTP_OPTIONS="--secure"
      ```
    - Place the kernel image and device tree in the TFTP directory:
      (Use the repo to generate them)

    - Restart the TFTP service:
      ```sh
      sudo systemctl restart tftpd-hpa
      ```

3. **Setup NFS Server:**
    - Install NFS server on your host machine:
      ```sh
      sudo apt-get install nfs-kernel-server
      ```
    - Configure NFS exports by editing `/etc/exports`:
      ```sh
      /home/environment/kria/jailhouse/output/rootfs/kria <board_IP>(rw,no_subtree_check,no_root_squash)
      ```
    - Every time, after updating the exports, run: 
      ```sh
      sudo /usr/sbin/exportfs -r
      ```
    - Place the root filesystem in the NFS directory:
      (Use the repo to generate the rootfs)

    - Restart the NFS service:
      ```sh
      sudo systemctl restart nfs-kernel-server
      ```

## Build The Environment
Once the Server is ready and the board is working launch the build_environment.sh script to generate all
the needed artifacts (e.g., Image, filesystem).

1. **U-BOOT autmatic boot.scr load using tftp**
    - The kria QSPI cannot be written using saveenv in U-BOOT. So you cannot save the command to load the 
      boot.scr as default. The only way to do it is integrate the command during the U-BOOT compile time.
    - Use the script u-boot_update_defconfig.sh -m  and change the BOOTCMD to do it e.g.: 
      ```sh
      CONFIG_BOOTCOMMAND="if dhcp ${scriptaddr} kria/boot.scr; then source ${scriptaddr}
      ```
    - Alternatively before compiling u-boot with the scripts/compile/u-boot_compile.sh script just append 
      the line to the config file in the u-boot directory:
      ```sh
      echo 'CONFIG_BOOTCOMMAND="if dhcp ${scriptaddr} kria/boot.scr; then source ${scriptaddr}; fi"' >> ${uboot_dir}/.config
      ```
2. **BOOT.BIN**
    - After the u-boot compilation, regenerate the BOOT.BIN using the scripts/compile/bootgen_compile.sh script


## Load BOOT.BIN into QSPI
The kria boars doesn't boot from SD but it uses the pre-defined BOOT.BIN in the QSPI memory which contains: 
- zynqmp_fsbl.elf
- pmufw.elf
- system.bit
- bl31.elf
- u-boot.elf

We need to change it since for 3 reasons: 
- We need to change the bl31.elf for using the Omnivisor
- We need to compile out u-boot.elf to define the automatic load through tftp
- we may need to change the bitstream loaded at boot time. 

To chage the BOOT.BIN into the QSPI memory, we can use the xmutil applicaiton in the Ubuntu image we loaded 
(see https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/3020685316/Kria+SOM+Boot+Firmware+Update).

In the platform launch the following command after coping the correct BOOT.BIN generated through this repo:
```sh
sudo xmutil bootfw_update -i <path to boot.bin>
```
The system has a backup firmware management with two separated system called A and B. 
Using the following command you should see that the loaded firmware will be the next to be booted: 
```sh
sudo xmutil bootfw_status
```

Then reboot the board, if the atf and u-boot are correctly loaded you need to save it before the next reboot.
Login into the Ubuntu image of the kria again and launch the following command to do it:
```sh
sudo xmutil bootfw_update -v
```

# MEMPOL Regulation 
The install directory contains the binaries to run mempol on the kria board as a Jailhouse-Omnivisor cell.
- install/lib/firmware/mempol_reg_r5_0.elf  ->  The regulator program that runs on the Cortex-R5 core.
- install/bin/membw_ctrl                    ->  Linux userspace program to control the regulator (runs on Cortex-A53)
- install/bin/bench                         ->  Linux Userspace program to benchmark the memory utilization

To run mempol as a cell you need the Omnivisor version of jailouse enabled on the kria.
To launch the mempol regulator use the following commands:
```sh
jailhouse cell create ${JAILHOUSE_DIR}/configs/arm64/zynqmp-kv260-RPU0-mempol.cell
jailhouse cell load inmate-mempol-RPU0 -r mempol_reg_r5_0.elf 0
jailhouse cell start inmate-mempol-RPU0
```

You should see on the serial (UART-1) somthing like this:
```
Regulator on R5 core
version: 5, 4 CPUs, 128 history, 2 samples, mode: sliding-window, token-bucket
buildid: dottavia@theia 2025-02-28 17:16:23 RELEASE TRACING VERBOSE WCET_STATS
TSC running at 533333333 Hz
waiting for start signal from main cores
```

Then you can use the userspace program to control the regulation.
As an example this commands apply a regulation of 250Mib/s to each core:
```sh
membw_ctrl --platform kria_k26 init
membw_ctrl --platform kria_k26 start 250 250 250 250 0
```
the outputs wuold be something like:
```
info: cpuidle for all 4 CPUs disabled
OK
controller: ready
```
```
info: cpuidle for all 4 CPUs disabled
controller: start
- mode: sliding-window
- control loop period: 3333 cycles
- weight factors: 1000, 1000
- global budget: 0/8
- core budgets: 24414/8, 24414/8, 24414/8, 24414/8
```


You can test the maximum benchmark on the cores by using the bench application:
```sh
bench -s 8 -c 3 read
```

the expected output is:
```
linear read bandwidth over 8192 KiB (8 MiB) block
242.8 MiB/s, 254.6 MB/s
243.0 MiB/s, 254.8 MB/s
243.0 MiB/s, 254.8 MB/s
243.1 MiB/s, 254.9 MB/s
243.1 MiB/s, 254.9 MB/s
243.0 MiB/s, 254.8 MB/s
243.0 MiB/s, 254.8 MB/s
243.0 MiB/s, 254.8 MB/s
242.9 MiB/s, 254.7 MB/s
243.0 MiB/s, 254.8 MB/s
243.0 MiB/s, 254.8 MB/s
240.4 MiB/s, 252.1 MB/s
242.3 MiB/s, 254.1 MB/s
242.4 MiB/s, 254.2 MB/s
242.4 MiB/s, 254.2 MB/s
242.5 MiB/s, 254.2 MB/s`