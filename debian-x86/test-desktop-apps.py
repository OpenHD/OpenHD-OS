#!/usr/bin/env python3
"""Test the already assembled Btrfs root with small disposable overlay files.

This verifies application startup while an image size/profile decision is pending.
It never writes the base root, a physical disk, or a release artifact.
"""
import argparse
import importlib.util
import json
import pathlib
import re
import shlex
import shutil
import subprocess
import time

spec = importlib.util.spec_from_file_location("smoke", pathlib.Path(__file__).with_name("smoke-test.py"))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class RootGuest(smoke.Guest):
    def start(self, mode="direct", installed=False):
        for name in ("serial.sock", "qmp.sock"):
            (self.test / name).unlink(missing_ok=True)
        args = ["qemu-system-x86_64", "-accel", "kvm", "-cpu", "host", "-smp", "2", "-m", "4096",
                "-machine", "q35,smm=on", "-display", "none", "-device", "virtio-vga",
                "-device", "qemu-xhci", "-device", "usb-tablet", "-no-reboot",
                "-qmp", "unix:/output/vm-test/qmp.sock,server=on,wait=off",
                "-serial", "unix:/output/vm-test/serial.sock,server=on,wait=off",
                "-nic", "user,model=virtio-net-pci",
                "-drive", "file=/output/vm-test/apps-root.qcow2,if=virtio,format=qcow2"]
        kernel = sorted((self.root / "boot").glob("vmlinuz-*"))[-1].name
        root_uuid = re.search(r"UUID=([^ ]+) / btrfs", (self.root / "etc/fstab").read_text())[1]
        if mode == "direct":
            args += ["-kernel", "/work/root/boot/" + kernel,
                     "-initrd", "/work/root/boot/initrd.img-" + kernel.removeprefix("vmlinuz-"),
                     "-append", f"root=UUID={root_uuid} rw rootflags=compress-force=zstd:6 console=ttyS0,115200 openhd.mode=desktop init=/bin/bash"]
        else:
            shutil.copyfile(self.builder / "usr/share/OVMF/OVMF_VARS_4M.ms.fd", self.test / "OVMF_VARS.fd")
            args += ["-drive", "file=/output/efi.img,if=virtio,format=raw,readonly=on",
                     "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.ms.fd",
                     "-drive", "if=pflash,format=raw,unit=1,file=/output/vm-test/OVMF_VARS.fd"]
        log = open(self.test / "qemu.log", "ab", buffering=0)
        self.process = subprocess.Popen(["chroot", str(self.builder), *args], stdout=log, stderr=log)
        self.serial = self.connect(self.test / "serial.sock")
        self.qmp = self.connect(self.test / "qmp.sock")
        self.qmp_file = self.qmp.makefile("rwb", buffering=0)
        self.qmp_file.readline()
        self.qmp_command("qmp_capabilities")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=pathlib.Path)
    parser.add_argument("--boot-menu", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    guest = RootGuest(work / "builder", work / "output", work / "root")
    try:
        guest.tool("qemu-img", "create", "-f", "qcow2", "-F", "raw", "-b", "/output/root.btrfs", "/output/vm-test/apps-root.qcow2")
        guest.start()
        guest.ready()
        guest.run("mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev")
        guest.run("sed -i '/ \\/Config /d; / \\/boot\\/efi /d' /etc/fstab; touch /etc/openhd/root-expanded")
        guest.run("mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d; printf '[Service]\\nExecStart=\\nExecStart=-/sbin/agetty --autologin root --noclear 115200 - vt220\\n' > /etc/systemd/system/serial-getty@ttyS0.service.d/test.conf; systemctl enable serial-getty@ttyS0.service")
        guest.serial.sendall(b"exec /sbin/init\n")
        guest.read_until(rb"openhd login:")
        guest.ready()
        guest.desktop_ui()
        launcher_apps = json.loads((work / "root/usr/share/openhd/launcher-apps.json").read_text())
        expected_launchers = ["qopenhd", "ardudeck", "kite-gc", "inav-configurator", "betaflight", "qgroundcontrol"]
        if [app["id"] for app in launcher_apps] != expected_launchers:
            raise RuntimeError("The launcher catalog is missing an expected app or has an unexpected order")
        if not all(app.get("icon") and app.get("exec") for app in launcher_apps):
            raise RuntimeError("A launcher entry has no installed icon or executable")
        guest.run("test $(pgrep -xc qs) = 1 && ! pgrep -x waybar && ! pgrep -x wofi")
        guest.run("mount -t tmpfs -o size=768M tmpfs /home/openhd; chown openhd:openhd /home/openhd")
        for name in expected_launchers:
            log = f"/run/user/1000/openhd-test-{name}.log"
            pid = f"/run/user/1000/openhd-test-{name}.pid"
            launch = f"echo $$ > {pid}; exec /usr/local/sbin/openhd-desktop-app {name} > {log} 2>&1"
            dispatch = "hl.dsp.exec_cmd(" + json.dumps("setsid sh -c " + shlex.quote(launch)) + ")"
            guest.run(
                "signature=$(tr '\\0' '\\n' < /proc/$(pgrep -x qs)/environ | "
                "sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p'); test -n \"$signature\" && "
                "runuser -u openhd -- env XDG_RUNTIME_DIR=/run/user/1000 "
                f"HYPRLAND_INSTANCE_SIGNATURE=\"$signature\" hyprctl dispatch {shlex.quote(dispatch)}"
            )
            time.sleep(12)
            result = guest.run(f"cat {log}; ps -u openhd -o pid,comm; kill -0 $(cat {pid})", expected=None)
            (guest.test / (name + ".log")).write_text(result)
            guest.screenshot(name)
            guest.run(f"kill -TERM -- -$(cat {pid}) || true")
            if not re.search(r"OPENHD_TEST_[a-f0-9]+:0\r?\n", result):
                raise RuntimeError("Application startup failed: " + name + "\n" + result)
            print("PASS: graphical application startup:", name, flush=True)
        guest.run("sed -i 's/set timeout=1/set timeout=30/' /boot/grub/grub.cfg")
        guest.shutdown()
        if args.boot_menu:
            guest.start("uefi")
            time.sleep(18)
            guest.screenshot("graphical-boot-menu")
            guest.process.terminate()
            guest.process.wait(timeout=10)
    finally:
        if guest.process and guest.process.poll() is None:
            guest.process.terminate()
            guest.process.wait(timeout=10)
        guest.transcript.close()


if __name__ == "__main__":
    main()
