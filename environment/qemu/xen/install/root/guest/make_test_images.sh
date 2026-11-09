#!/bin/sh
#
# make_test_images.sh - build runPHI test images for backend_xen from the guest
# kernel and initramfs in this directory:
#   Image           the guest kernel: this environment's own Image (the Dom0
#                   kernel, which also runs as a domU), copied here by
#                   load_components_to_remote.sh -g
#   rootfs.cpio.gz  the guest initramfs (busybox, udhcpc, cyclictest, stress-ng),
#                   the one of the KV260's test images
# Images:
#   runphi-xen-guest:initramfs  256 MB, the initramfs as root filesystem
#   runphi-xen-guest:lvm        256 MB, no initramfs: runPHI copies the image's
#                               root filesystem into a logical volume of test-vg
# Run it again after updating either file.

set -e
cd "$(dirname "$0")"
guest=$(pwd)
for f in Image rootfs.cpio.gz; do
	if [ ! -f "$f" ]; then
		echo "ERROR: no $guest/$f (load the kernel with load_components_to_remote.sh -g)"
		exit 1
	fi
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# guest_image <tag>: import the image in $work/img
guest_image() {
	tar -C "$work/img" -c . | docker import --change 'CMD ["/bin/sh"]' - "runphi-xen-guest:$1" >/dev/null
	echo "runphi-xen-guest:$1"
}

rm -rf "$work/img" && mkdir -p "$work/img/boot"
cp Image rootfs.cpio.gz "$work/img/boot/"
echo '{ "os_var": "linux", "inmate": "/boot/Image", "ramdisk": "/boot/rootfs.cpio.gz", "memory": 256 }' > "$work/img/boot/config.json"
guest_image initramfs

rm -rf "$work/img" && mkdir -p "$work/img/boot"
(cd "$work/img" && zcat "$guest/rootfs.cpio.gz" | cpio -id 2>/dev/null)
cp Image "$work/img/boot/"
echo '{ "os_var": "linux", "inmate": "/boot/Image", "disk_type": "lvm", "memory": 256 }' > "$work/img/boot/config.json"
guest_image lvm
