#!/usr/bin/env python3
"""Boot and install the real image using disposable QEMU disks, never host disks."""
import argparse
import json
import pathlib
import re
import shlex
import shutil
import socket
import subprocess
import time
import uuid


class Guest:
    def __init__(self, builder, output, root):
        self.builder, self.output, self.root = builder, output, root
        self.test = output / "vm-test"
        self.test.mkdir(exist_ok=True)
        self.process = None
        self.transcript = open(self.test / "serial.log", "ab", buffering=0)

    def tool(self, *args):
        return subprocess.run(["chroot", str(self.builder), *args], check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.decode()

    def connect(self, path, timeout=60):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                connection = socket.socket(socket.AF_UNIX)
                connection.connect(str(path))
                connection.settimeout(1)
                return connection
            except (FileNotFoundError, ConnectionRefusedError):
                connection.close()
                if self.process.poll() is not None:
                    raise RuntimeError((self.test / "qemu.log").read_text())
                time.sleep(0.25)
        raise TimeoutError(path)

    def start(self, mode="bios", installed=False):
        for name in ("serial.sock", "qmp.sock"):
            (self.test / name).unlink(missing_ok=True)
        args = ["qemu-system-x86_64", "-accel", "kvm", "-cpu", "host", "-smp", "2",
                "-m", "2048", "-machine", "q35,smm=on", "-display", "none",
                "-device", "virtio-vga", "-device", "qemu-xhci", "-device", "usb-tablet", "-no-reboot",
                "-audiodev", "none,id=test-audio", "-device", "ich9-intel-hda",
                "-device", "hda-duplex,audiodev=test-audio",
                "-qmp", "unix:/output/vm-test/qmp.sock,server=on,wait=off",
                "-serial", "unix:/output/vm-test/serial.sock,server=on,wait=off",
                "-nic", "user,model=virtio-net-pci"]
        if not installed:
            args += ["-drive", "file=/output/vm-test/usb.qcow2,if=virtio,format=qcow2"]
        args += ["-drive", "file=/output/vm-test/internal.qcow2,if=virtio,format=qcow2"]
        if mode == "direct":
            kernel = sorted((self.root / "boot").glob("vmlinuz-*"))[-1].name
            root_uuid = re.search(r"UUID=([^ ]+) / btrfs", (self.root / "etc/fstab").read_text())[1]
            args += ["-kernel", "/work/root/boot/" + kernel,
                     "-initrd", "/work/root/boot/initrd.img-" + kernel.removeprefix("vmlinuz-"),
                     "-append", f"root=UUID={root_uuid} rw rootflags=compress-force=zstd:6 console=ttyS0,115200 init=/bin/bash"]
        elif mode in ("uefi", "uefi32"):
            code = "OVMF32_CODE_4M.fd" if mode == "uefi32" else "OVMF_CODE_4M.ms.fd"
            variables = "OVMF32_VARS_4M.fd" if mode == "uefi32" else "OVMF_VARS_4M.ms.fd"
            shutil.copyfile(self.builder / "usr/share/OVMF" / variables, self.test / "OVMF_VARS.fd")
            args += ["-drive", "if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/" + code,
                     "-drive", "if=pflash,format=raw,unit=1,file=/output/vm-test/OVMF_VARS.fd"]
        log = open(self.test / "qemu.log", "ab", buffering=0)
        self.process = subprocess.Popen(["chroot", str(self.builder), *args], stdout=log, stderr=log)
        self.serial = self.connect(self.test / "serial.sock")
        self.qmp = self.connect(self.test / "qmp.sock")
        self.qmp_file = self.qmp.makefile("rwb", buffering=0)
        self.qmp_file.readline()
        self.qmp_command("qmp_capabilities")

    def qmp_command(self, execute, arguments=None):
        self.qmp_file.write((json.dumps({"execute": execute, "arguments": arguments or {}}) + "\n").encode())
        while True:
            response = json.loads(self.qmp_file.readline())
            if "error" in response:
                raise RuntimeError(response)
            if "return" in response:
                return response["return"]

    def read_until(self, pattern, timeout=120):
        data = b""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                chunk = self.serial.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                raise RuntimeError("Guest serial connection closed")
            self.transcript.write(chunk)
            data += chunk
            if re.search(pattern, data):
                return data.decode(errors="replace")
        raise TimeoutError(data[-4000:].decode(errors="replace"))

    def run(self, command, expected=0, timeout=120):
        marker = "OPENHD_TEST_" + uuid.uuid4().hex
        self.serial.sendall((command + f"; printf '\\n{marker}:%s\\n' $?\n").encode())
        result = self.read_until((r"\n" + marker + r":(\d+)\r?\n").encode(), timeout)
        code = int(re.search(marker + r":(\d+)", result)[1])
        if expected is not None and code != expected:
            raise RuntimeError(f"Guest command failed ({code}): {command}\n{result[-7000:]}")
        return result

    def ready(self):
        self.read_until(rb"(?:bash-[0-9.]+|root@[^\r\n]+)[#] ", timeout=150)

    def flight_ui(self):
        self.run("journalctl -b -u qopenhd --no-pager -n 80")
        self.run("timeout 90 sh -c 'until journalctl -b -u qopenhd --no-pager | grep -Fq \"QOpenHD boot video: playing\"; do sleep 1; done'", timeout=100)
        if not (self.test / "boot-animation.png").exists():
            self.screenshot("boot-animation")
        self.run("timeout 90 sh -c 'until journalctl -b -u qopenhd --no-pager | grep -Fq \"QOpenHD boot video: finished\"; do sleep 1; done'", timeout=100)
        self.wait_view("flight", 1)
        self.run("timeout 90 sh -c 'until journalctl -b -u qopenhd --no-pager | grep -Fq \"OpenHD flight view ready\"; do sleep 1; done'", timeout=100)
        self.run("systemctl is-active qopenhd openhd openhd-sys-utils NetworkManager")
        self.run("test $(systemctl show qopenhd -p NRestarts --value) = 0")

    def shutdown(self):
        self.run("sync")
        self.serial.sendall(b"systemctl --no-block poweroff\n")
        # Drain the serial console while waiting. Backpressure can otherwise
        # stall the guest's shutdown logging and look like a service hang.
        deadline = time.monotonic() + 120
        shutdown_log = bytearray()
        while self.process.poll() is None and time.monotonic() < deadline:
            try:
                chunk = self.serial.recv(65536)
                if not chunk:
                    break
                self.transcript.write(chunk)
                shutdown_log.extend(chunk)
            except socket.timeout:
                pass
        try:
            self.process.wait(timeout=max(1, deadline - time.monotonic()))
        except subprocess.TimeoutExpired as error:
            raise RuntimeError("Guest did not shut down within 120 seconds:\n" +
                               shutdown_log[-4000:].decode(errors="replace")) from error
        if self.process.returncode != 0:
            raise RuntimeError(f"QEMU exited with status {self.process.returncode} during shutdown")
        self.serial.close()
        self.qmp_file.close()
        self.qmp.close()

    def screenshot(self, name):
        self.qmp_command("screendump", {"filename": "/output/vm-test/" + name + ".png", "format": "png"})

    def desktop_ui(self):
        self.run("timeout 90 sh -c 'until pgrep -x Hyprland && pgrep -x qs; do sleep 1; done'", timeout=100)
        time.sleep(15)
        self.run("journalctl -b -u qopenhd --no-pager -n 80")
        self.screenshot("openhd-os-desktop")

    def desktop_controls(self):
        session = (
            "session_bus=$(tr '\\0' '\\n' < /proc/$(pgrep -x qs)/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p'); "
            "session_display=$(tr '\\0' '\\n' < /proc/$(pgrep -x qs)/environ | sed -n 's/^WAYLAND_DISPLAY=//p'); "
            "runuser -u openhd -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=\"$session_bus\" WAYLAND_DISPLAY=\"$session_display\" "
        )
        control = "qs ipc -p /usr/share/openhd/desktop-config/quickshell"
        self.run(session + control + " show 2>&1 | grep -iF 'target desktop'")
        self.run("pgrep -x nm-tray && pgrep -x lxpolkit && command -v nm-connection-editor && systemctl is-active NetworkManager")

        self.click(640, 700)  # Clicking bare desktop must leave the launcher visible.
        self.screenshot("desktop-launcher-persistent")
        self.click(67, 32)
        self.screenshot("desktop-power-menu")
        self.click(140, 113)
        self.run("timeout 15 sh -c 'until pgrep -fu openhd ^/usr/bin/gnome-system-monitor; do sleep 0.25; done'")
        self.run("pkill -fu openhd ^/usr/bin/gnome-system-monitor")
        self.run("timeout 15 sh -c 'while pgrep -fu openhd ^/usr/bin/gnome-system-monitor; do sleep 0.25; done'")
        self.click(1150, 32)
        self.screenshot("desktop-sound-menu")
        self.click(640, 700)
        self.run(session + "/usr/local/sbin/openhd-shell-action network")
        self.screenshot("desktop-network-menu")
        self.click(640, 700)
        # Check the visible feedback without depending on VM backlight support.
        self.run(session + control + " call desktop hud Brightness 65")
        self.screenshot("desktop-brightness-hud")

    def send_shortcut(self, *keys):
        self.qmp_command("send-key", {"keys": [{"type": "qcode", "data": key} for key in keys], "hold-time": 120})

    def view_shortcut(self):
        self.send_shortcut("meta_l", "tab")

    def wait_view(self, view, vt):
        self.run(
            f"timeout 50 sh -c 'until grep -qx {view} /run/openhd-view/current && "
            f"grep -qx tty{vt} /sys/class/tty/tty0/active; do sleep 0.25; done'",
            timeout=55,
        )

    def open_installer(self, desktop):
        self.view_shortcut()
        if desktop:
            self.wait_view("desktop", 2)
            self.desktop_ui()
            self.run("dpkg-query -W hyprland-guiutils && runuser -u openhd -- sudo -n -l /usr/local/sbin/openhd-switch-session flight && runuser -u openhd -- sudo -n -l /usr/local/sbin/openhd-switch-session install")
            hyprctl = (
                "signature=$(tr '\\0' '\\n' < /proc/$(pgrep -x qs)/environ | "
                "sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p'); "
                'runuser -u openhd -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE="$signature" hyprctl '
            )
            config = self.run(hyprctl + "configerrors")
            if "Config error" in config:
                raise RuntimeError("Hyprland configuration errors:\n" + config)
            self.run(hyprctl + "plugin list | grep -qi hyprbars")
            self.run("runuser -u openhd -- sudo -n id -u | grep -qx 0")
            permissions = "/run/user/1000/openhd-nm-permissions"
            query = f"hl.exec_cmd('nmcli -t -f PERMISSION,VALUE general permissions >{permissions}')"
            self.run(hyprctl + "eval " + shlex.quote(query))
            self.run("timeout 10 sh -c " + shlex.quote(
                f"until grep -qx 'org.freedesktop.NetworkManager.settings.modify.system:yes' {permissions} 2>/dev/null; do sleep 0.25; done"
            ))
            self.click(640, 550)  # Kite GCS, center tile on the Albatross launcher.
            self.run("timeout 10 sh -c 'until test -f /home/openhd/.local/state/openhd/apps/kite-gc.log; do sleep 0.25; done'")
            self.run("timeout 35 sh -c " + shlex.quote("until " + hyprctl + "clients | grep -q '^Window '; do sleep 0.25; done"))
            self.screenshot("kite-gc-from-launcher")
            # Use the desktop command here so this test can verify the installer
            # while Kite is running. Menu clicks are checked in desktop_controls.
            self.run(hyprctl + "eval " + shlex.quote(
                "hl.exec_cmd('/usr/local/sbin/openhd-shell-action install')"
            ))
        self.wait_view("installer", 1)
        self.installer_page(1)

    def click(self, x, y):
        self.qmp_command("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / 1280)}},
            {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / 800)}}]})
        time.sleep(0.1)
        self.qmp_command("input-send-event", {"events": [
            {"type": "btn", "data": {"button": "left", "down": True}}]})
        time.sleep(0.1)
        self.qmp_command("input-send-event", {"events": [
            {"type": "btn", "data": {"button": "left", "down": False}}]})
        time.sleep(0.15)

    def welcome(self, install=False):
        self.run("timeout 45 sh -c 'until journalctl -b -u openhd-installer --no-pager | grep -q \"OpenHD installer page: 0\"; do sleep 1; done'", timeout=55)
        time.sleep(1)
        self.screenshot("installer-welcome")
        self.click(640, 718 if install else 654)
        time.sleep(1)
        self.screenshot("installer-after-welcome-action")

    def installer_page(self, index):
        self.run(f"timeout 45 sh -c 'until journalctl -b -u openhd-installer --no-pager | grep -q \"OpenHD installer page: {index}\"; do sleep 1; done'", timeout=55)
        time.sleep(1)

    def gui_install(self):
        self.installer_page(1)
        self.screenshot("installer-disks")
        self.click(640, 220)  # Running USB cannot be selected.
        self.click(640, 687)
        self.run("journalctl -b -u openhd-installer --no-pager | grep 'OpenHD installer page:' | tail -1 | grep -q 'page: 1'")
        self.click(640, 325)  # second disk; the running USB row is disabled
        time.sleep(1)
        self.screenshot("installer-disk-selected")
        self.click(640, 687)
        self.installer_page(2)
        self.screenshot("installer-review")
        # The install button is disabled before both explicit acknowledgements.
        self.click(640, 685)
        self.run("test $(lsblk -nr /dev/vdb | wc -l) = 1")
        self.click(48, 569)
        self.click(48, 625)
        self.screenshot("installer-confirmed")
        self.click(640, 685)
        self.installer_page(3)
        self.screenshot("installer-progress")
        self.run(
            "timeout 600 sh -c 'until journalctl -b -u openhd-installer --no-pager | "
            "grep -q \"OpenHD installer page: 4\"; do systemctl is-active --quiet openhd-installer || exit 1; "
            "sleep 1; done'", timeout=610,
        )
        time.sleep(1)
        self.screenshot("installer-complete")
        self.run("test $(blkid -s TYPE -o value /dev/vdb4) = btrfs && test $(blkid -s TYPE -o value /dev/vdb1) = vfat")
        self.click(640, 750)  # Continue using USB, then release DRM to QOpenHD


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builder", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--desktop-only", action="store_true")
    options = parser.parse_args()
    guest = Guest(options.builder, options.output, options.root)
    if options.desktop_only:
        try:
            guest.start("uefi", installed=True)
            guest.ready()
            guest.desktop_ui()
            guest.shutdown()
        finally:
            if guest.process and guest.process.poll() is None:
                guest.process.terminate()
                guest.process.wait(timeout=10)
            guest.transcript.close()
        return
    (guest.test / "boot-animation.png").unlink(missing_ok=True)
    try:
        guest.tool("qemu-img", "create", "-f", "qcow2", "-F", "raw", "-b",
                   "/output/openhd-debian-x86-minimal.img", "/output/vm-test/usb.qcow2")
        guest.tool("qemu-img", "resize", "/output/vm-test/usb.qcow2", "2G")
        guest.tool("qemu-img", "create", "-f", "qcow2", "/output/vm-test/internal.qcow2", "4G")
        guest.start("direct")
        guest.ready()
        guest.run("mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d")
        guest.run("printf '[Service]\\nExecStart=\\nExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 - vt220\\n' > /etc/systemd/system/serial-getty@ttyS0.service.d/test.conf")
        guest.run("systemctl enable serial-getty@ttyS0.service")
        guest.run("sed -i 's/quiet loglevel/console=ttyS0,115200 quiet loglevel/g' /boot/grub/grub.cfg /etc/default/grub")
        guest.serial.sendall(b"exec /sbin/init\n")
        # Consume the new login banner; a pending prompt from the init shell
        # must not be mistaken for the fully booted system's shell.
        guest.read_until(rb"openhd login:")
        guest.ready()
        guest.screenshot("early-boot")
        guest.flight_ui()
        guest.run("test -S /run/user/$(id -u openhd)/pulse/native && ss -lunp | grep -E ':5610[[:space:]].*QOpenHD'")
        guest.run("grep -q '^set timeout=0$' /boot/grub/grub.cfg && grep -q \"menuentry 'OpenHD'\" /boot/grub/grub.cfg && ! grep -q 'openhd.install' /boot/grub/grub.cfg")
        guest.run("test $(findmnt -n -o FSTYPE /) = btrfs && findmnt / && df -h /")
        guest.run("test $(systemctl is-enabled getty@tty1.service) = masked && test $(systemctl is-enabled autovt@tty1.service) = masked && ! systemctl is-active --quiet getty@tty1.service && systemctl is-active --quiet getty@tty3.service")
        guest.run("adb version")
        guest.run("test $(systemctl is-enabled openhd-grow-root.service) = masked && passwd -S openhd | grep -q '^openhd P '")
        guest.run("test $(findmnt -n -o FSTYPE /Config) = vfat && test $(findmnt -n -o SOURCE /Config) = /dev/vda1 && test -f /Config/config.txt && test $(readlink /boot/openhd) = /Config/openhd")
        guest.run("printf '{\"role\":\"ground\",\"debug\":true}\\n' > /Config/openhd/settings.json; echo imagewriter-config-persistent > /Config/imagewriter-test.txt")
        guest.run("printf '[General]\\nimagewriter_import_test=true\\n' > /Config/openhd/QOpenHD.conf")
        guest.run("apt-get update && apt-get install -y --no-install-recommends hello", timeout=180)
        guest.run("echo persistent-native-root > /etc/openhd/persistence-test; hello")
        guest.screenshot("usb-qopenhd")
        guest.shutdown()
        print("PASS: native writable root, APT install and QOpenHD services", flush=True)
        guest.start("bios")
        guest.ready()
        guest.flight_ui()
        desktop = bool(re.search(r"(?m)^DESKTOP_AVAILABLE\r?$",
                                 guest.run("test ! -x /usr/bin/Hyprland || echo DESKTOP_AVAILABLE")))
        guest.open_installer(desktop)
        guest.screenshot("installer-from-session")
        # SysUtils can request a QOpenHD start while the wizard owns VT1.
        guest.run("systemctl start qopenhd && systemctl is-active --quiet openhd-installer "
                  "&& ! systemctl is-active --quiet qopenhd")
        guest.run("openhd-install --target /dev/vda --dry-run", expected=1)
        guest.run("openhd-install --target /dev/vdb --dry-run")
        guest.gui_install()
        guest.wait_view("desktop" if desktop else "flight", 2 if desktop else 1)
        guest.run("grep -q persistent-native-root /etc/openhd/persistence-test && hello")
        guest.run("test ! -e /Config/openhd/settings.json && grep -Eq '\"debug\"[[:space:]]*:[[:space:]]*true' /usr/local/share/OpenHD/SysUtils/config.json && grep -q imagewriter-config-persistent /Config/imagewriter-test.txt")
        guest.run("grep -q imagewriter_import_test=true /root/.config/OpenHD/QOpenHD.conf && test -s /etc/openhd/qopenhd-import.sha256")
        guest.run("test $(findmnt -n -o SOURCE /Config) = /dev/vda1")
        guest.shutdown()
        print("PASS: BIOS boot, reboot persistence, source protection and graphical virtual-disk installation", flush=True)
        guest.start("uefi")
        guest.ready()
        guest.flight_ui()
        guest.run("od -An -j4 -N1 -tu1 /sys/firmware/efi/efivars/SecureBoot-* | tee /run/secureboot-test; grep -qw 1 /run/secureboot-test")
        guest.screenshot("uefi-usb-qopenhd")
        guest.shutdown()
        print("PASS: USB boots through x64 UEFI", flush=True)
        guest.start("uefi32")
        guest.ready()
        guest.flight_ui()
        guest.shutdown()
        print("PASS: USB boots an amd64 kernel through IA32 UEFI", flush=True)
        guest.start("uefi", installed=True)
        guest.ready()
        guest.flight_ui()
        guest.run("grep -q persistent-native-root /etc/openhd/persistence-test && hello && findmnt / && df -h /")
        guest.run("findmnt /Config && grep -q imagewriter-config-persistent /Config/imagewriter-test.txt")
        guest.run("journalctl -b -u qopenhd --no-pager -n 60")
        guest.screenshot("installed-qopenhd")
        guest.run("test ! -e /etc/openhd/usb-welcome")
        print("PASS: installed disk boots through x64 UEFI with the USB absent", flush=True)
        if desktop:
            guest.view_shortcut()
            guest.wait_view("desktop", 2)
            guest.desktop_ui()
            guest.desktop_controls()
            guest.run("pgrep -x Hyprland >/run/desktop-before-switch; systemctl is-active openhd openhd-sys-utils")
            guest.send_shortcut("ctrl", "alt", "delete")
            guest.run("timeout 15 sh -c 'until pgrep -fu openhd \"(^|/)gnome-system-monitor([[:space:]]|$)\"; do sleep 0.25; done'")
            guest.run("pid=$(pgrep -fu openhd '^/usr/bin/gnome-system-monitor([[:space:]]|$)') && "
                      "tr '\\0' '\\n' </proc/\"$pid\"/environ | grep -Eq '^XDG_CONFIG_HOME=.*/openhd/task-manager$'")
            guest.screenshot("task-manager")
            guest.view_shortcut()
            guest.wait_view("flight", 1)
            guest.run("timeout 40 sh -c 'until [ \"$(journalctl -b -u qopenhd --no-pager | grep -Fc \"OpenHD flight view ready\")\" -ge 2 ]; do sleep 1; done'", timeout=45)
            guest.screenshot("flight-after-desktop")
            guest.view_shortcut()
            guest.wait_view("desktop", 2)
            guest.run("pgrep -x Hyprland | cmp - /run/desktop-before-switch; systemctl is-active openhd openhd-sys-utils")
            guest.screenshot("desktop-after-flight")
            guest.shutdown()
            print("PASS: Win+Tab switches both ways without restarting Hyprland", flush=True)
        else:
            guest.shutdown()
    except Exception:
        if guest.process and guest.process.poll() is None:
            try:
                diagnostic = guest.run("journalctl -b -u qopenhd -u openhd-installer -u openhd-desktop --no-pager; journalctl -b --no-pager | grep -Ei 'quickshell|\\bqs\\b|hyprland|greetd|sudo|openhd-app-launch' | tail -n 160; cat /home/openhd/.local/state/openhd/quickshell.log /home/openhd/.local/state/openhd/apps/*.log 2>&1 || true; pgrep -af 'qs|Hyprland|greetd' || true; ls -la /run/user/1000 /dev/dri /etc/sudoers.d 2>&1; systemctl --failed --no-pager", expected=None, timeout=30)
                (guest.test / "failure-diagnostics.txt").write_text(diagnostic)
                print("Desktop failure diagnostics:\n" + diagnostic, flush=True)
                guest.screenshot("failure")
            except Exception as error:
                print("Diagnostic collection:", error, flush=True)
        raise
    finally:
        if guest.process and guest.process.poll() is None:
            guest.process.terminate()
            guest.process.wait(timeout=10)
        guest.transcript.close()


if __name__ == "__main__":
    main()
