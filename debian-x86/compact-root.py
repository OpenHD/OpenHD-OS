#!/usr/bin/env python3
"""Resize a regular-file Btrfs image using the image's own Linux kernel."""
import argparse
import os
import pathlib
import re
import select
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=pathlib.Path)
    parser.add_argument("kernel", type=pathlib.Path)
    parser.add_argument("initrd", type=pathlib.Path)
    parser.add_argument("size", type=int)
    options = parser.parse_args()
    if not all(p.is_file() for p in (options.image, options.kernel, options.initrd)):
        raise SystemExit("Compaction accepts regular image/kernel files only.")
    args = ["qemu-system-x86_64", "-accel", "kvm", "-cpu", "host", "-m", "1536",
            "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot",
            "-drive", f"file={options.image},format=raw,if=virtio",
            "-kernel", str(options.kernel), "-initrd", str(options.initrd),
            "-append", "root=/dev/vda rw console=ttyS0,115200 init=/bin/bash"]
    process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
    data = b""
    sent = False
    deadline = time.monotonic() + 240
    with options.image.with_suffix(".compact.log").open("wb") as log:
        try:
            while process.poll() is None and time.monotonic() < deadline:
                if not select.select([process.stdout], [], [], 1)[0]:
                    continue
                chunk = os.read(process.stdout.fileno(), 65536)
                log.write(chunk)
                log.flush()
                data += chunk
                if not sent and re.search(rb"(?:bash-[0-9.]+|root@[^\r\n]+)# ", data):
                    command = ("mount -t proc proc /proc; mount -t sysfs sys /sys; "
                               "mount -t devtmpfs dev /dev; "
                               f"btrfs filesystem resize {options.size} /; "
                               "printf '\\nCOMPACT_RESULT:%s\\n' $?; sync; /sbin/poweroff -f\n")
                    process.stdin.write(command.encode())
                    process.stdin.flush()
                    sent = True
            if process.poll() is None:
                raise TimeoutError("Root compaction timed out; see compact log.")
            if b"\nCOMPACT_RESULT:0\r\n" not in data:
                raise RuntimeError(data[-5000:].decode(errors="replace"))
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    with options.image.open("r+b") as image:
        image.truncate(options.size)


if __name__ == "__main__":
    main()
