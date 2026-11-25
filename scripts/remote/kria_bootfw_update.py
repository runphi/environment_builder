#!/usr/bin/env python3
"""kria_bootfw_update.py - A/B update of the boot firmware in the QSPI of a Kria
SOM Starter Kit (KV260, KR260), from the board's Linux, as root:

    kria_bootfw_update.py -p            the A/B state and what each image holds
    kria_bootfw_update.py -i BOOT.BIN   write BOOT.BIN to the image that is not
                                        running and request it for the next boot
    kria_bootfw_update.py -v            mark the running image as bootable
    -n                                  with -i or -v: show what would be done

The same procedure as Xilinx's image_update (xmutil bootfw_update, Debian
package xlnx-image-update 1.5), for systems without it: python3 only, no
mtd-utils. The QSPI partitions are found by name in /proc/mtd, so the mtd
numbers of the kernel do not matter.

The persistent register (and its backup) is "ABUM", version, length, checksum
(0xffffffff minus the sum of the other words), then last booted image,
requested image, image B bootable, image A bootable (0 = A / not bootable,
1 = B / bootable) and the offsets of A, B and the recovery image. -i:
  1. marks the running (last booted) image as bootable;
  2. marks the other image as not bootable;
  3. erases it, writes BOOT.BIN, reads it back and compares;
  4. requests it for the next boot;
  5. as image_update does when the running image's version (at 0x79) is older
     than 1.03, clears the CSU multiboot register, so that a reboot goes
     through the Image Selector (a power cycle always does).
At the next boot the Image Selector boots the requested image once. If it
reaches Linux, -v marks it bootable and it stays the image that boots; if it
does not, or the board is rebooted without -v, the Image Selector falls back to
the image that last booted fine (Kria boot firmware docs, "A/B Boot Concept").
"""
import argparse
import fcntl
import os
import struct
import sys

PERS = "Persistent Register"
PERS_BACKUP = "Persistent Register Backup"
IMAGE = {0: "Image A (FSBL, PMU, ATF, U-Boot)", 1: "Image B (FSBL, PMU, ATF, U-Boot)"}
LETTER = {0: "A", 1: "B"}
MEMERASE = 0x40084D02  # _IOW('M', 2, struct erase_info_user)
CONFIG_REG = "/sys/firmware/zynqmp/config_reg"


def mtd_devices():
    devs = {}
    with open("/proc/mtd") as f:
        for line in f.readlines()[1:]:
            dev, size, erasesize, name = line.split(None, 3)
            devs[name.strip().strip('"')] = ("/dev/" + dev.rstrip(":"), int(size, 16), int(erasesize, 16))
    for name in (PERS, PERS_BACKUP, IMAGE[0], IMAGE[1]):
        if name not in devs:
            sys.exit(f"ERROR: no QSPI partition named {name!r} in /proc/mtd (not a Kria SOM Starter Kit?)")
    return devs


def read(dev, length, offset=0):
    with open(dev, "rb") as f:
        f.seek(offset)
        return f.read(length)


def checksum(words):
    return (0xFFFFFFFF - sum(w for i, w in enumerate(words) if i != 3)) & 0xFFFFFFFF


def parse_register(raw):
    words = list(struct.unpack("<8I", raw[:32]))
    if raw[:4] != b"ABUM":
        return None
    if words[3] != checksum(words):
        return None
    return words


def state(words):
    last, requested, b_ok, a_ok = struct.pack("<I", words[4])
    return {"last": last, "requested": requested, "bootable": {0: a_ok, 1: b_ok}}


def pack_state(words, st):
    words = list(words)
    words[4] = struct.unpack("<I", bytes([st["last"], st["requested"], st["bootable"][1], st["bootable"][0]]))[0]
    words[3] = checksum(words)
    return struct.pack("<8I", *words)


def erase(dev, size, erasesize, length):
    length = min(size, (length + erasesize - 1) // erasesize * erasesize)
    fd = os.open(dev, os.O_RDWR)
    try:
        fcntl.ioctl(fd, MEMERASE, struct.pack("<II", 0, length))
    finally:
        os.close(fd)


def write(dev, size, erasesize, data, erase_all=False):
    erase(dev, size, erasesize, size if erase_all else len(data))
    fd = os.open(dev, os.O_WRONLY)
    try:
        # mtdchar writes go to the flash before write() returns (no fsync on
        # an mtd device: EINVAL); the read back below checks them
        view = memoryview(data)
        while view:
            n = os.write(fd, view[:65536])
            view = view[n:]
    finally:
        os.close(fd)
    if read(dev, len(data)) != data:
        sys.exit(f"ERROR: {dev} reads back different from what was written")


def write_registers(devs, words, st, dry):
    raw = pack_state(words, st)
    s = state(struct.unpack("<8I", raw))
    desc = (f"last {LETTER[s['last']]}, requested {LETTER[s['requested']]}, "
            f"A {'bootable' if s['bootable'][0] else 'NOT bootable'}, "
            f"B {'bootable' if s['bootable'][1] else 'NOT bootable'}")
    if dry:
        print(f"  (dry run) persistent registers -> {desc}")
        return
    for name in (PERS, PERS_BACKUP):
        dev, size, erasesize = devs[name]
        write(dev, size, erasesize, raw)
    print(f"  persistent registers -> {desc}")


def image_info(devs, n):
    dev = devs[IMAGE[n]][0]
    head = read(dev, 0x100)
    if head[0x24:0x28] != b"XNLX":
        return "no boot image"
    rev = head[0x70:0x94].split(b"\0")[0].decode("ascii", "replace").strip()
    data = read(dev, devs[IMAGE[n]][1])
    found = []
    for key in (b"v2.", b"U-Boot 20"):
        i = data.find(key)
        while i >= 0:
            s = data[i:i + 40].split(b"\0")[0].split(b"\n")[0].decode("ascii", "replace")
            if (key == b"v2." and "(release)" in s) or (key == b"U-Boot 20" and "(" in s):
                found.append(s)
                break
            i = data.find(key, i + 1)
    return f"{rev or '(no revision string)'}; " + "; ".join(found)


def load_registers(devs):
    main = parse_register(read(devs[PERS][0], 32))
    backup = parse_register(read(devs[PERS_BACKUP][0], 32))
    if main is None and backup is None:
        sys.exit("ERROR: neither persistent register is valid")
    if main is None or backup is None or main != backup:
        print("WARNING: the persistent registers differ or one is invalid; using the valid main one"
              if main else "WARNING: the main persistent register is invalid; using the backup")
    return main or backup


def print_status(devs, words):
    st = state(words)
    print(f"Persistent register: last booted {LETTER[st['last']]}, requested {LETTER[st['requested']]}, "
          f"A {'bootable' if st['bootable'][0] else 'NOT bootable'}, "
          f"B {'bootable' if st['bootable'][1] else 'NOT bootable'} "
          f"(offsets A 0x{words[5]:x}, B 0x{words[6]:x}, recovery 0x{words[7]:x})")
    for n in (0, 1):
        print(f"Image {LETTER[n]} ({devs[IMAGE[n]][0]}): {image_info(devs, n)}")


def image_version(devs, n):
    raw = read(devs[IMAGE[n]][0], 4, 0x79).split(b"\0")[0]
    try:
        return float(raw.decode("ascii"))
    except ValueError:
        return 0.0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("-p", action="store_true", help="print the A/B state")
    g.add_argument("-i", metavar="BOOT.BIN", help="update the image that is not running")
    g.add_argument("-v", action="store_true", help="mark the running image bootable")
    ap.add_argument("-n", action="store_true", help="dry run")
    args = ap.parse_args()

    devs = mtd_devices()
    words = load_registers(devs)
    if args.p:
        print_status(devs, words)
        return
    st = state(words)
    last = st["last"]

    if args.v:
        st["bootable"][last] = 1
        print(f"Marking the running image {LETTER[last]} as bootable")
        write_registers(devs, words, st, args.n)
        return

    data = open(args.i, "rb").read()
    target = 1 - last
    dev, size, erasesize = devs[IMAGE[target]]
    if data[0x24:0x28] != b"XNLX":
        sys.exit(f"ERROR: {args.i} is not a ZynqMP boot image")
    if len(data) > size:
        sys.exit(f"ERROR: {args.i} (0x{len(data):x} bytes) does not fit image {LETTER[target]} (0x{size:x})")
    print(f"Running image: {LETTER[last]}; updating image {LETTER[target]} ({dev}) with {args.i} (0x{len(data):x} bytes)")
    st["bootable"][last] = 1
    write_registers(devs, words, st, args.n)
    st["bootable"][target] = 0
    write_registers(devs, words, st, args.n)
    if args.n:
        print(f"  (dry run) erase {dev} and write {args.i}")
    else:
        write(dev, size, erasesize, data, erase_all=True)
        print(f"  {dev}: written and read back")
    st["requested"] = target
    write_registers(devs, words, st, args.n)
    if image_version(devs, last) < 1.03:
        if args.n:
            print("  (dry run) clear the multiboot register")
        else:
            try:
                with open(CONFIG_REG, "w") as f:
                    f.write("0xffca0010 0xfffffff 0x0")
                print("  multiboot register cleared: a reboot goes through the Image Selector")
            except OSError as e:
                print(f"  WARNING: could not clear the multiboot register ({e}): power-cycle the board "
                      "(a reboot could start the running image again)")
    print(f"Next boot: image {LETTER[target]}, once. If it reaches Linux, run {sys.argv[0]} -v "
          f"to keep it; otherwise the board falls back to image {LETTER[last]}.")


if __name__ == "__main__":
    main()
