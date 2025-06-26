# Kria kr260 Board Environment with UBUNTU Setup Guide
To have a stable setup, the idea is to load a certfied ubuntu on the sd card of the board. 
Then update the arm-trusted-firmware, the Kernel Image and the device tree to enable Jailhouse and Omnivisor. 

## Loading a Stable Ubuntu on the SD Card

1. **Download Ubuntu Image:**
    - Visit the official Ubuntu website and download the Image (24.04) for the kr260 baord: https://ubuntu.com/download/amd

2. **Prepare the SD Card:**
    - Insert the SD card into your computer.
    - Discover the internal storage device name: This is usually /dev/sda but it’s important to first make sure. 
      One of the easiest ways is to open GParted (sudo apt install gparted) and use the drop-down menu in the top-right to select the correct
      device. You’ll see storage space and layout below. Make a note of the device name. Make sure to remove all partition and clean the sd.
    - Use `dd` to write the Ubuntu image to the SD card:
    - Open the terminal application and enter the following command, adjusting the paths to the Ubuntu Core download and the internal storage device accordingly:
      ```sh 
      xzcat ~/Downloads/<ubuntu_image>.img.xz | \
      sudo dd of=/dev/<target disk device> bs=32M status=progress; sync
      ```

3. **Boot the Kria Board:**
    - Insert the SD card into the Kria board.
    - Connect the board to you PC using the uart
    - Connect to the uart using picocom (or minicom).
      ```sh
      picocom -b 115800 /dev/ttyUSB1
      ```
    - Connect the ethernet port (the up-right one) to the network.
    - Connect the board to a power source to power on the board.

4. **Setup new password**
    - Check that the boot complete succesfully.
    - Setup new Password

## Build The Environment
Launch the build_environment.sh script to generate the needed Kernel Image and jailhouse/omnivisor.
    - Enter the docker container.
    ```sh
    docker run -it --rm --user $(id -u):$(id -g) -v /etc/passwd:/etc/passwd:ro --net=host --name env_builder_container -v ${PWD}:/home -w="/home" runphi_env_builder /bin/bash
    ```
    - Launxh the build.
    ```sh 
    ./scripts/build_environment.sh
    ```

## Update arm trusted firmware
The kria boars doesn't boot from SD but it uses the pre-defined BOOT.BIN in the QSPI memory which contains: 
- zynqmp_fsbl.elf
- pmufw.elf
- system.bit
- bl31.elf
- u-boot.elf

We need to change it since for 2 reasons: 
- We need to change the bl31.elf for using the Omnivisor
- we may need to change the bitstream loaded at boot time. 

To chage the BOOT.BIN into the QSPI memory, we can use the xmutil applicaiton in the Ubuntu image we loaded 
(see https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/3020685316/Kria+SOM+Boot+Firmware+Update).

Copy the BOOT.BIN produced during the build of the environment into the board: 
```sh
scp environment_builder/environment/kr260/jailhouse/output/boot/BOOT.BIN ubuntu@<IP>:~/
```
In the board launch the following command after coping the correct BOOT.BIN:
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


## Load new Kernel Image and the DTB overlay
Now we need to update the kernel with the one we compiled in this repo during the building of the environment,
and we need to upload the device tree overlay for seeing the remotecore, and for reserving memory for jailhouse.

```sh
scp environment_builder/environment/kr260/jailhouse/output/boot/Image root@<IP>:/boot/firmware/Image
scp environment_builder/environment/kr260/jailhouse/output/boot/system.dtb root@<IP>:/boot/firmware/user-override.dtb
```
then reboot the board and stop the boot before u-boot autobooting.


## Load Jailhouse
Now you just need to load jailhouse on the board. We can load all the jailhouse directory 
```sh
scp environment_builder/environment/kr260/jailhouse/build/jailhouse ubuntu@<IP>:~/
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
242.5 MiB/s, 254.2 MB/s
```
