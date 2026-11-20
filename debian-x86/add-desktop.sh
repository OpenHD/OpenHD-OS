#!/usr/bin/env bash
# Optional larger desktop image; the minimal image remains capped at 1 GiB.
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
chroot "$work/root" apt-get install -y --no-install-recommends \
    xserver-xorg-core xserver-xorg-input-libinput xinit xauth \
    xfce4-session xfce4-panel xfwm4 xfdesktop4 xfce4-settings thunar \
    network-manager-gnome dbus-x11 xterm
chroot "$work/root" apt-get clean
# shellcheck disable=SC2016
chroot "$work/root" dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' >"$work/packages.tsv"
ln -sfn /run/NetworkManager/resolv.conf "$work/root/etc/resolv.conf"
