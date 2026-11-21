#!/usr/bin/env python3
"""Capture the real GRUB theme in QEMU, using a UI-only preview ISO."""
import json
import pathlib
import shutil
import socket
import subprocess
import sys
import time

source = pathlib.Path(__file__).resolve().parent
work = pathlib.Path(sys.argv[1]).resolve()
tree = work / "iso"
(tree / "boot/grub").mkdir(parents=True, exist_ok=True)
shutil.copytree(source / "overlay/usr/share/grub", tree / "usr/share/grub", dirs_exist_ok=True)
subprocess.run(["grub-mkfont", "-s", "20", "-o", str(tree / "usr/share/grub/themes/openhd/openhd.pf2"), "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"], check=True)
subprocess.run(["grub-mkfont", "-s", "12", "-o", str(tree / "usr/share/grub/themes/openhd/console.pf2"), "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"], check=True)
menu = subprocess.check_output(["sh", str(source / "overlay/usr/local/sbin/openhd-grub-menu"), "preview-root", "vmlinuz-preview"], text=True)
(tree / "boot/grub/grub.cfg").write_text("""insmod serial
serial --unit=0 --speed=115200
terminal_output console serial
echo PREVIEW_ROOT=$root PREFIX=$prefix
ls /usr/share/grub/themes/openhd/
if loadfont /usr/share/grub/themes/openhd/openhd.pf2; then
    echo PREVIEW_FONT_OK
else
    echo PREVIEW_FONT_FAILED
fi
set timeout=-1
set default=openhd
""" + menu + "\nterminal_output --append serial\necho PREVIEW_THEME=$theme\n")
subprocess.run(["grub-mkrescue", "-o", str(work / "preview.iso"), str(tree)], check=True)
qmp_path = work / "qmp.sock"
qmp_path.unlink(missing_ok=True)
log = (work / "qemu.log").open("w")
process = subprocess.Popen(["qemu-system-x86_64", "-m", "512", "-display", "none", "-vga", "std", "-serial", "file:" + str(work / "serial.log"), "-boot", "d", "-cdrom", str(work / "preview.iso"), "-qmp", "unix:" + str(qmp_path) + ",server=on,wait=off"], stdout=log, stderr=log)
try:
    connection = socket.socket(socket.AF_UNIX)
    for attempt in range(100):
        try:
            connection.connect(str(qmp_path))
            break
        except (FileNotFoundError, ConnectionRefusedError):
            if process.poll() is not None:
                raise RuntimeError((work / "qemu.log").read_text())
            time.sleep(0.1)
    stream = connection.makefile("rwb", buffering=0)
    stream.readline()
    def command(name, arguments=None):
        stream.write((json.dumps({"execute": name, "arguments": arguments or {}}) + "\n").encode())
        while True:
            result = json.loads(stream.readline())
            if "error" in result:
                raise RuntimeError(result)
            if "return" in result:
                return result["return"]
    command("qmp_capabilities")
    time.sleep(12)
    command("screendump", {"filename": str(work / "openhd-boot-menu.png"), "format": "png"})
    command("quit")
    process.wait(timeout=10)
    print((work / "serial.log").read_text(errors="replace"))
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
