#!/usr/bin/env bash
# Wayland desktop with coordinated shell, application launcher and flight apps.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
work=$(realpath "${1:?Usage: add-desktop.sh WORKDIR}")
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
chroot "$work/root" apt-get install -y --no-install-recommends \
    hyprland/trixie-backports xdg-desktop-portal-hyprland/trixie-backports \
    greetd waybar mako-notifier wofi swaybg foot xwayland thunar \
    network-manager-gnome dbus-x11 wvkbd arc-theme papirus-icon-theme \
    fonts-inter fonts-font-awesome libnotify-bin brightnessctl \
    pipewire pipewire-pulse wireplumber xdg-desktop-portal-gtk
chroot "$work/root" apt-get purge -y xfce4-session xfce4-panel xfwm4 xfdesktop4 \
    xfce4-settings xinit xterm xserver-xorg-core xserver-xorg-input-libinput
# The appliance service owns tty1 and starts greetd only in desktop mode.
chroot "$work/root" systemctl mask greetd.service
chroot "$work/root" apt-get clean
# shellcheck disable=SC2016
chroot "$work/root" dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' >"$work/packages.tsv"
ln -sfn /run/NetworkManager/resolv.conf "$work/root/etc/resolv.conf"
umount "$work/root/proc"
umount -R "$work/root/dev"
trap - EXIT
here=$(cd -- "$(dirname -- "$0")" && pwd)
python3 "$here/install-desktop-apps.py" "$work"
