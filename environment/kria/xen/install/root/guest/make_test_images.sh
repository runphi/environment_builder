#!/bin/sh
#
# make_test_images.sh - build runPHI test images for backend_xen from the guest
# kernel and initramfs in this directory:
#   Image           the guest kernel: this environment's own Image (the Dom0
#                   kernel, which also runs as a domU), copied here by
#                   load_components_to_remote.sh -g
#   rootfs.cpio.gz  the guest initramfs (busybox, udhcpc, cyclictest, stress-ng),
#                   the one of the KV260's test images, whose login prompt is on
#                   ttyAMA0 (QEMU's PL011, for the KVM guests): the images move
#                   it to hvc0, a Xen domain's console (xl console <domain>)
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

# The guest's /etc/inittab with the login prompt on hvc0 instead of ttyAMA0
zcat rootfs.cpio.gz | (cd "$work" && cpio -id etc/inittab 2>/dev/null)
sed -i 's/ttyAMA0/hvc0/g' "$work/etc/inittab"

# An initramfs archive with that file only: appended to rootfs.cpio.gz, it
# replaces the file of the same name (the kernel unpacks the archives in turn)
python3 - "$work/etc/inittab" >"$work/console.cpio" <<'EOF'
import sys
def entry(name, mode, data):
    fields = [1, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name) + 1, 0]
    head = ("070701" + "".join("%08X" % f for f in fields)).encode() + name.encode() + b"\0"
    head += b"\0" * (-len(head) % 4)
    return head + data + b"\0" * (-len(data) % 4)
data = open(sys.argv[1], "rb").read()
out = entry("etc/inittab", 0o100644, data) + entry("TRAILER!!!", 0, b"")
sys.stdout.buffer.write(out + b"\0" * (-len(out) % 512))
EOF

rm -rf "$work/img" && mkdir -p "$work/img/boot"
cp Image "$work/img/boot/"
cat rootfs.cpio.gz "$work/console.cpio" >"$work/img/boot/rootfs.cpio.gz"
echo '{ "os_var": "linux", "inmate": "/boot/Image", "ramdisk": "/boot/rootfs.cpio.gz", "memory": 256 }' > "$work/img/boot/config.json"
guest_image initramfs

rm -rf "$work/img" && mkdir -p "$work/img/boot"
(cd "$work/img" && zcat "$guest/rootfs.cpio.gz" | cpio -id 2>/dev/null)
cp "$work/etc/inittab" "$work/img/etc/inittab"
cp Image "$work/img/boot/"
echo '{ "os_var": "linux", "inmate": "/boot/Image", "disk_type": "lvm", "memory": 256 }' > "$work/img/boot/config.json"
guest_image lvm
