#!/usr/bin/env bash
# OpenHD Hyprland desktop with the Quickshell Albatross interface.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
work=$(realpath "${1:?Usage: add-desktop.sh WORKDIR}")
here=$(cd -- "$(dirname -- "$0")" && pwd)
[[ $EUID == 0 && -f "$work/root/etc/debian_version" ]] || exit 1
mount --rbind /dev "$work/root/dev"
mount --make-rslave "$work/root/dev"
mount -t proc proc "$work/root/proc"
trap 'umount "$work/root/proc"; umount -R "$work/root/dev"' EXIT
rm -f "$work/root/etc/resolv.conf"
cp --dereference /etc/resolv.conf "$work/root/etc/resolv.conf"
chroot "$work/root" apt-get update
printf 'deb https://deb.debian.org/debian trixie-backports main\n' >"$work/root/etc/apt/sources.list.d/openhd-backports.list"
chroot "$work/root" apt-get update
chroot "$work/root" apt-get -t trixie-backports install -y --no-install-recommends \
    hyprland hyprland-guiutils xdg-desktop-portal-hyprland \
    greetd quickshell mako-notifier foot xwayland thunar \
    dbus-x11 qt6-wayland qtwayland5 wvkbd nm-tray nm-connection-editor gnome-system-monitor lxpolkit arc-theme papirus-icon-theme \
    fonts-inter fonts-font-awesome libnotify-bin brightnessctl brightness-udev \
    pavucontrol xdg-desktop-portal-gtk
for binary in hyprland-dialog start-hyprland; do
    if [[ ! -x "$work/root/usr/bin/$binary" ]]; then
        printf 'Desktop dependency missing: /usr/bin/%s\n' "$binary" >&2
        exit 1
    fi
done
bash "$here/build-window-titlebars.sh" "$work"
chroot "$work/root" apt-get purge -y xfce4-session xfce4-panel xfwm4 xfdesktop4 \
    xfce4-settings xinit xterm xserver-xorg-core xserver-xorg-input-libinput
# The appliance service starts greetd on VT2 only when entering the desktop.
chroot "$work/root" systemctl mask greetd.service
chroot "$work/root" apt-get clean
# shellcheck disable=SC2016
chroot "$work/root" dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' >"$work/packages.tsv"
ln -sfn /run/NetworkManager/resolv.conf "$work/root/etc/resolv.conf"
umount "$work/root/proc"
umount -R "$work/root/dev"
trap - EXIT
python3 "$here/install-desktop-apps.py" "$work"
