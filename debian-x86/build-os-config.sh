#!/usr/bin/env bash
# Build the small distribution configuration package without component compilers.
set -euo pipefail
version="0.2+$(date -u +%Y%m%d%H%M%S)"
if [[ ${OPENHD_SNAPSHOT_NUMBER:-} =~ ^[1-9][0-9]*$ ]]; then
    version="1:0.0.$OPENHD_SNAPSHOT_NUMBER"
fi
overlay=${1:?Usage: build-os-config.sh OVERLAY OUTPUT_DEB}
output=$(realpath -m "${2:?Supply output .deb path}")
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/DEBIAN"
chmod 755 "$stage" "$stage/DEBIAN"
cp -a "$overlay/." "$stage/"
find "$stage/etc" "$stage/usr" -type f ! -name '*.png' ! -name '*.pf2' -exec sed -i 's/\r$//' {} +
find "$stage/etc" "$stage/usr" -type f -exec chmod 644 {} +
find "$stage/etc" "$stage/usr" -type d -exec chmod 755 {} +
find "$stage/usr/local/sbin" -type f -exec chmod 755 {} +
chmod 755 "$stage/etc/grub.d/09_openhd"
chmod 0440 "$stage/etc/sudoers.d/openhd-display-switch"
grub-mkfont -s 20 -o "$stage/usr/share/grub/themes/openhd/openhd.pf2" /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
grub-mkfont -s 12 -o "$stage/usr/share/grub/themes/openhd/console.pf2" /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf
printf '/etc/default/grub\n' >"$stage/DEBIAN/conffiles"
cat >"$stage/DEBIAN/preinst" <<'PREINST'
#!/bin/sh
set -e
dpkg-divert --package openhd-os --add --rename --divert /etc/issue.debian /etc/issue
PREINST
cat >"$stage/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ -d /run/systemd/system ]; then systemctl daemon-reload; fi
systemctl disable getty@tty2.service openhd-installer.service
systemctl mask getty@tty1.service autovt@tty1.service getty@tty2.service autovt@tty2.service
systemctl mask ctrl-alt-del.target openhd-grow-root.service
systemctl enable getty@tty3.service qopenhd.service
if id openhd >/dev/null 2>&1; then
    usermod -a -G audio openhd
    install -Dm644 /dev/null /var/lib/systemd/linger/openhd
fi
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
rm -f /etc/grub.d/41_openhd_install /etc/openhd/usb-welcome
chmod -x /etc/grub.d/10_linux /etc/grub.d/20_linux_xen /etc/grub.d/30_uefi-firmware 2>/dev/null || true
if mountpoint -q /boot/efi; then update-grub; fi
POSTINST
chmod 755 "$stage/DEBIAN/preinst" "$stage/DEBIAN/postinst"
cat >"$stage/DEBIAN/control" <<EOF
Package: openhd-os
Version: $version
Architecture: amd64
Maintainer: OpenHD <developers@openhd.org>
Depends: qopenhd, openhd, openhd-sys-utils, openhd-installer, init-system-helpers, grub2-common, rsync, btrfs-progs, dosfstools, gdisk, parted, librsvg2-common, python3-minimal, kbd, sudo, dbus-user-session, pipewire, pipewire-pulse, wireplumber, alsa-ucm-conf, firmware-sof-signed
Description: OpenHD OS boot menu, sessions and graphical installation backend
EOF
mkdir -p "$(dirname -- "$output")"
dpkg-deb --root-owner-group --build "$stage" "$output"
