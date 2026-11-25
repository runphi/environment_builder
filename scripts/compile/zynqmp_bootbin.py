#!/usr/bin/env python3
"""zynqmp_bootbin.py - inspect a ZynqMP boot image (BOOT.BIN), or replace one of
its partitions with the contents of an ELF file, leaving everything else as it is.

    zynqmp_bootbin.py info <image>
    zynqmp_bootbin.py replace <image> <partition name> <elf> -o <output>

Used to put a different BL31 (TF-A) into a boot firmware image whose other
components (FSBL, PMU firmware, U-Boot, ...) are only available as that image,
e.g. the Kria SOM boot firmware in the QSPI of a Kria Starter Kit:

    zynqmp_bootbin.py replace imageA.bin bl31.elf build/.../bl31.elf -o BOOT.BIN

The layout is the one of UG1085 ("Boot Image Format") and UG1283 (bootgen): the
boot header, the image header table, image headers (which carry the partition
names, as bootgen writes them: the file name of the partition's source) and
64-byte partition headers. Only unencrypted, unauthenticated partitions without
a partition checksum can be replaced (refused otherwise).

The new partition data is the ELF's allocated PROGBITS sections, from the lowest
to the highest address, gaps filled with zeros (what objcopy -O binary gives);
the load address is the lowest section address and the execution address the
ELF entry point. The data goes where the old one was if it fits before the next
partition's data, else after the last partition. Only the replaced partition's
header changes (lengths, addresses, data offset, header checksum); the output
is checked: every other partition and the boot header are byte-identical. The
output ends after the last partition (an image read back from flash is padded
with 0xff up to the size of its flash partition).
"""
import argparse
import struct
import sys

PH_SIZE = 64
ALIGN = 64


def u32(d, off):
    return struct.unpack_from("<I", d, off)[0]


def image_name(d, off):
    # bootgen stores the name as 32-bit words with the bytes of each word reversed
    raw = b"".join(d[off + 16 + 4 * i:off + 20 + 4 * i][::-1] for i in range(32))
    return raw.split(b"\0")[0].decode("ascii", "replace")


def parse(d):
    if d[0x24:0x28] != b"XNLX" or u32(d, 0x20) != 0xAA995566:
        sys.exit("ERROR: not a ZynqMP boot image (no XNLX header)")
    iht = u32(d, 0x98)
    parts = []
    off = u32(d, iht + 8) * 4
    while off:
        words = list(struct.unpack_from("<16I", d, off))
        parts.append({"hdr_off": off, "words": words})
        off = words[3] * 4
        if len(parts) > 32:
            sys.exit("ERROR: partition header chain does not end")
    # names from the image headers (each points to its first partition header)
    names = {}
    ioff = u32(d, iht + 12) * 4
    while ioff:
        nxt, ph = struct.unpack_from("<2I", d, ioff)[:2]
        names[ph * 4] = image_name(d, ioff)
        ioff = nxt * 4
    for p in parts:
        w = p["words"]
        p["name"] = names.get(p["hdr_off"], "?")
        p["data_off"] = w[8] * 4
        p["len"] = w[1] * 4
        p["total"] = w[2] * 4
        p["exec"] = w[4] | (w[5] << 32)
        p["load"] = w[6] | (w[7] << 32)
        p["checksum_ok"] = ((~sum(w[:15])) & 0xFFFFFFFF) == w[15]
    return parts


def end_of_partitions(parts):
    return max(p["data_off"] + p["total"] for p in parts)


def elf_data(path):
    e = open(path, "rb").read()
    if e[:4] != b"\x7fELF" or e[4] != 2 or e[5] != 1:
        sys.exit(f"ERROR: {path} is not a 64-bit little-endian ELF")
    entry = struct.unpack_from("<Q", e, 0x18)[0]
    shoff = struct.unpack_from("<Q", e, 0x28)[0]
    shentsize, shnum = struct.unpack_from("<HH", e, 0x3A)
    secs = []
    for i in range(shnum):
        s = shoff + i * shentsize
        sh_type, sh_flags = struct.unpack_from("<IQ", e, s + 4)
        addr, off, size = struct.unpack_from("<QQQ", e, s + 0x10)
        if sh_type == 1 and sh_flags & 2 and size:  # PROGBITS, SHF_ALLOC
            secs.append((addr, off, size))
    if not secs:
        sys.exit(f"ERROR: {path} has no allocated PROGBITS sections")
    lo = min(a for a, _, _ in secs)
    hi = max(a + s for a, _, s in secs)
    data = bytearray(hi - lo)
    for a, o, s in secs:
        data[a - lo:a - lo + s] = e[o:o + s]
    return bytes(data), lo, entry


def cmd_info(args):
    d = open(args.image, "rb").read()
    print(f"FSBL exec 0x{u32(d, 0x2C):x}, PMU firmware 0x{u32(d, 0x34):x} bytes, "
          f"FSBL 0x{u32(d, 0x3C):x} bytes, key source 0x{u32(d, 0x28):x}")
    parts = parse(d)
    for i, p in enumerate(parts):
        w = p["words"]
        print(f"{i}: {p['name']:<14} data 0x{p['data_off']:08x} len 0x{p['len']:08x} "
              f"load 0x{p['load']:x} exec 0x{p['exec']:x} attr 0x{w[9]:08x} "
              f"header checksum {'ok' if p['checksum_ok'] else 'BAD'}")
    print(f"partitions end at 0x{end_of_partitions(parts):x} (file 0x{len(d):x})")


def cmd_replace(args):
    d = bytearray(open(args.image, "rb").read())
    parts = parse(d)
    end = end_of_partitions(parts)
    d = d[:end]
    match = [p for p in parts if p["name"] == args.name]
    if len(match) != 1:
        sys.exit(f"ERROR: {len(match)} partitions named {args.name!r} "
                 f"({', '.join(p['name'] for p in parts)})")
    p = match[0]
    w = p["words"]
    if w[0] != w[1] or w[1] != w[2] or w[11] or w[13] or u32(d, 0x28):
        sys.exit("ERROR: the partition is encrypted, authenticated or has a checksum")

    new, load, entry = elf_data(args.elf)
    padded = new + b"\0" * (-len(new) % ALIGN)
    if load != p["load"] or entry != p["exec"]:
        print(f"note: load/exec 0x{p['load']:x}/0x{p['exec']:x} -> 0x{load:x}/0x{entry:x}")

    following = [q["data_off"] for q in parts if q["data_off"] > p["data_off"]]
    slot_end = min(following) if following else end
    if p["data_off"] + len(padded) <= slot_end:
        data_off = p["data_off"]
        d[data_off:slot_end] = padded + b"\0" * (slot_end - data_off - len(padded))
        where = "in place"
    else:
        data_off = len(d) + (-len(d) % ALIGN)
        d += b"\0" * (data_off - len(d)) + padded
        d[p["data_off"]:p["data_off"] + p["total"]] = b"\0" * p["total"]
        where = f"appended at 0x{data_off:x}"

    words = len(padded) // 4
    w = list(w)
    w[0] = w[1] = w[2] = words
    w[4], w[5] = entry & 0xFFFFFFFF, entry >> 32
    w[6], w[7] = load & 0xFFFFFFFF, load >> 32
    w[8] = data_off // 4
    w[15] = (~sum(w[:15])) & 0xFFFFFFFF
    struct.pack_into("<16I", d, p["hdr_off"], *w)

    # check: re-parse, compare everything else with the original
    orig = open(args.image, "rb").read()
    out_parts = parse(d)
    for q, o in zip(out_parts, parts):
        if not q["checksum_ok"]:
            sys.exit(f"ERROR: header checksum of {q['name']} is wrong")
        if q["name"] == args.name:
            if d[q["data_off"]:q["data_off"] + q["len"]] != padded:
                sys.exit("ERROR: the new partition data reads back different")
            continue
        if (q["words"] != o["words"] or
                d[q["data_off"]:q["data_off"] + q["total"]] != orig[o["data_off"]:o["data_off"] + o["total"]]):
            sys.exit(f"ERROR: partition {q['name']} changed")
    if d[:p["hdr_off"]] != orig[:p["hdr_off"]]:
        sys.exit("ERROR: the headers before the replaced partition header changed")

    open(args.output, "wb").write(d)
    print(f"{args.name}: 0x{p['len']:x} -> 0x{len(padded):x} bytes ({where}), "
          f"load 0x{load:x}, exec 0x{entry:x}; {args.output}: 0x{len(d):x} bytes")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("info")
    a.add_argument("image")
    a.set_defaults(func=cmd_info)
    a = sub.add_parser("replace")
    a.add_argument("image")
    a.add_argument("name")
    a.add_argument("elf")
    a.add_argument("-o", "--output", required=True)
    a.set_defaults(func=cmd_replace)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
