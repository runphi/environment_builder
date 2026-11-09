#!/bin/sh
#
# make_test_images.sh - build the runPHI test images of the KV260
# (runphi-kvm-guest:initramfs, :pinned-net, :lvm, :steer, see RUNPHI.md of
# kria-kvm) from the guest kernel and initramfs in this directory:
#   Image           the guest kernel: this environment's own Image, copied here
#                   by load_components_to_remote.sh -g
#   rootfs.cpio.gz  the guest initramfs (busybox, udhcpc, cyclictest, stress-ng),
#                   the one of the KV260's test images
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

# image <tag> <config.json>: kernel, initramfs and configuration, nothing else
image() {
	rm -rf "$work/img" && mkdir -p "$work/img/boot"
	cp Image rootfs.cpio.gz "$work/img/boot/"
	echo "$2" > "$work/img/boot/config.json"
	tar -C "$work/img" -c . | docker import --change 'CMD ["/bin/sh"]' - "runphi-kvm-guest:$1" >/dev/null
	echo "runphi-kvm-guest:$1"
}

image initramfs '{ "os_var": "linux", "inmate": "/boot/Image", "ramdisk": "/boot/rootfs.cpio.gz",
  "memory": 256, "vcpus": 1 }'

image pinned-net '{ "os_var": "linux", "inmate": "/boot/Image", "ramdisk": "/boot/rootfs.cpio.gz",
  "memory": 512, "vcpus": 2,
  "vcpu_pinning": [ { "vcpu": 0, "pcpu": 2 }, { "vcpu": 1, "pcpu": 3 } ],
  "net": "user" }'

image steer '{ "os_var": "linux", "inmate": "/boot/Image", "ramdisk": "/boot/rootfs.cpio.gz",
  "memory": 256, "vcpus": 1,
  "vcpu_pinning": [ { "vcpu": 0, "pcpu": 3 } ],
  "steer_irq": [0, 1] }'

# lvm: the initramfs unpacked as the image's root filesystem, which runPHI
# copies into a logical volume of test-vg; no ramdisk
rm -rf "$work/img" && mkdir -p "$work/img/boot"
(cd "$work/img" && zcat "$guest/rootfs.cpio.gz" | cpio -id 2>/dev/null)
cp Image "$work/img/boot/"
echo '{ "os_var": "linux", "inmate": "/boot/Image", "disk_type": "lvm", "memory": 256 }' > "$work/img/boot/config.json"
tar -C "$work/img" -c . | docker import --change 'CMD ["/bin/sh"]' - runphi-kvm-guest:lvm >/dev/null
echo "runphi-kvm-guest:lvm"
