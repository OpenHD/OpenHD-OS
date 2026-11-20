#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(realpath "${1:?Usage: make-root.sh WORKDIR}")
root="$work/root"
if [[ ! -e "$root/etc/debian_version" ]]; then
    packages=$(sed '/^#/d; /^$/d' "$here/runtime.packages" | paste -sd,)
    mmdebstrap --architectures=amd64 --variant=minbase \
        --keyring="$work/keys/trixie.gpg" --include="$packages" \
        --dpkgopt='path-exclude=/usr/share/doc/*' \
        --dpkgopt='path-include=/usr/share/doc/*/copyright' \
        --dpkgopt='path-exclude=/usr/share/man/*' \
        --dpkgopt='path-exclude=/usr/share/locale/*' \
        trixie "$root" \
        "deb [signed-by=$work/keys/trixie.gpg] https://deb.debian.org/debian trixie main contrib non-free-firmware non-free"
fi
printf 'deb https://deb.debian.org/debian trixie main contrib non-free-firmware non-free\ndeb https://deb.debian.org/debian-security trixie-security main contrib non-free-firmware non-free\ndeb https://deb.debian.org/debian trixie-updates main contrib non-free-firmware non-free\n' >"$root/etc/apt/sources.list"
# Rebuilds must not follow the runtime resolver symlink into the build host.
rm -f "$root/etc/resolv.conf"
cp --dereference /etc/resolv.conf "$root/etc/resolv.conf"
mount --rbind /dev "$root/dev"
mount --make-rslave "$root/dev"
mount -t proc proc "$root/proc"
mount --rbind /sys "$root/sys"
mount --make-rslave "$root/sys"
trap 'umount -R "$root/sys"; umount "$root/proc"; umount -R "$root/dev"' EXIT
mkdir -p "$root/tmp/packages"
cp "$work/builder/packages/"*.deb "$root/tmp/packages/"
chroot "$root" apt-get update
chroot "$root" apt-get install -y --no-install-recommends busybox zstd sudo grub-efi-amd64-signed shim-signed plymouth plymouth-themes gstreamer1.0-libav libqt5multimedia5-plugins vainfo cloud-guest-utils
chroot "$root" /bin/sh -c 'apt-get install -y --no-install-recommends /tmp/packages/*.deb'
for binary in QOpenHD openhd openhd_sys_utils openhd-installer; do
    missing=$(chroot "$root" ldd "/usr/local/bin/$binary" | grep 'not found' || true)
    [[ -z "$missing" ]] || { echo "$missing" >&2; exit 1; }
done
cp -a "$here/overlay/." "$root/"
if [[ -f "$work/builder/src/source-manifest.json" ]]; then
    install -Dm644 "$work/builder/src/source-manifest.json" "$root/usr/share/openhd/source-manifest.json"
fi
# Windows source mounts do not preserve Unix modes or text line endings.
while IFS= read -r -d '' source; do
    relative=${source#"$here/overlay/"}
    chmod 644 "$root/$relative"
    case "$relative" in
        *.png|*.pf2) ;;
        *) sed -i 's/\r$//' "$root/$relative" ;;
    esac
done < <(find "$here/overlay" -type f -print0)
while IFS= read -r -d '' source; do
    relative=${source#"$here/overlay"}
    chmod 755 "$root$relative"
done < <(find "$here/overlay" -type d -print0)
# Keep Debian's machine-readable identity for third-party installers, while
# presenting the appliance's own name to people. /etc overrides /usr/lib.
chroot "$root" dpkg-divert --local --add --rename --divert /etc/os-release.debian /etc/os-release
rm -f "$root/etc/os-release"
cat >"$root/etc/os-release" <<'EOF'
PRETTY_NAME="OpenHD OS 0.1 (Debian 13)"
NAME="OpenHD OS"
VERSION_ID="13"
VERSION="13 (trixie)"
VERSION_CODENAME=trixie
ID=debian
OPENHD_VERSION="0.1"
HOME_URL="https://openhd.org/"
EOF
printf 'OpenHD OS 0.1 - QOpenHD\nDebian 13 compatible; use apt for additional packages.\n' >"$root/etc/motd"
install -d "$root/usr/share/plymouth/themes/openhd"
install -m644 "$here/../additionalFiles/openhd-splash/"*.png \
    "$here/../additionalFiles/openhd-splash/"*.script \
    "$here/../additionalFiles/openhd-splash/"*.plymouth "$root/usr/share/plymouth/themes/openhd/"
sed -i 's/\r$//' "$root/usr/share/plymouth/themes/openhd/openhd.plymouth" \
    "$root/usr/share/plymouth/themes/openhd/openhd.script"
chroot "$root" plymouth-set-default-theme openhd
# QOpenHD releases Plymouth immediately before it claims DRM. Do not let a
# display-manager wait service hold up this appliance's multi-user boot.
chroot "$root" systemctl mask plymouth-quit.service plymouth-quit-wait.service
# tty1 belongs exclusively to QOpenHD. Mask both names
# so logind's automatic VT activation cannot start a login prompt underneath it.
chroot "$root" systemctl mask getty@tty1.service autovt@tty1.service
chroot "$root" systemctl enable getty@tty2.service
find "$root/usr/local/sbin" -type f -exec chmod 755 {} +
rm -f "$root/etc/grub.d/41_openhd_install" "$root/etc/openhd/usb-welcome"
chmod 755 "$root/etc/grub.d/09_openhd"
# Keep the menu direct even when Debian regenerates it after a kernel update.
chmod -x "$root/etc/grub.d/10_linux" "$root/etc/grub.d/20_linux_xen" "$root/etc/grub.d/30_uefi-firmware" 2>/dev/null || true
# Preserve Devourer ownership and USB rules provided by SysUtils.
chroot "$root" systemctl enable openhd-sys-utils.service openhd.service qopenhd.service \
    openhd-grow-root.service openhd-installer.service NetworkManager.service
mkdir -p "$root/etc/openhd"
chroot "$root" systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
chroot "$root" systemctl set-default multi-user.target
if ! chroot "$root" id openhd >/dev/null 2>&1; then
    chroot "$root" useradd --create-home --shell /bin/bash --groups video,render,input,plugdev openhd
fi
chroot "$root" passwd -l openhd
chroot "$root" passwd -l root
echo openhd >"$root/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 openhd\n' >"$root/etc/hosts"
printf 'APT::Install-Recommends "false";\nAPT::Install-Suggests "false";\nAcquire::Languages "none";\n' >"$root/etc/apt/apt.conf.d/90openhd-minimal"
mkdir -p "$root/etc/systemd/journald.conf.d"
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=12M\n' >"$root/etc/systemd/journald.conf.d/openhd.conf"
mkdir -p "$root/Config" "$root/etc/openhd" "$root/etc/initramfs-tools/conf.d"
mkdir -p "$root/usr/share/openhd/config-defaults"
cp -r "$here/config-partition/." "$root/usr/share/openhd/config-defaults/"
find "$root/usr/share/openhd/config-defaults" -type f -exec chmod 644 {} + -exec sed -i 's/\r$//' {} +
find "$root/usr/share/openhd/config-defaults" -type d -exec chmod 755 {} +
# These aliases preserve the existing QOpenHD import/export paths.
rm -rf -- "$root/boot/openhd"
ln -s /Config/openhd "$root/boot/openhd"
ln -sfn /Config "$root/config"
ln -sfn /Config "$root/conf"
mkdir -p "$root/usr/local/share/OpenHD/SysUtils"
printf '{"run_mode":"ground","firstboot":true,"debug":false}\n' >"$root/usr/local/share/OpenHD/SysUtils/config.json"
printf 'COMPRESS=zstd\nMODULES=most\n' >"$root/etc/initramfs-tools/conf.d/openhd"
grep -qx btrfs "$root/etc/initramfs-tools/modules" || echo btrfs >>"$root/etc/initramfs-tools/modules"
install -m755 "$here/../additionalFiles/prepare-devourer-image.sh" "$root/tmp/prepare-devourer-image.sh"
sed -i 's/\r$//' "$root/tmp/prepare-devourer-image.sh"
chroot "$root" /bin/bash /tmp/prepare-devourer-image.sh
rm -f "$root/tmp/prepare-devourer-image.sh"
for kernel in "$root/boot/"vmlinuz-*; do
    version=${kernel##*/vmlinuz-}
    if [[ ! -s "$root/boot/initrd.img-$version" ]]; then
        chroot "$root" update-initramfs -c -k "$version"
    fi
done
chroot "$root" apt-get clean
# These paths belong exclusively to the freshly created root, never the host.
rm -rf -- "$root/tmp/packages" "$root/var/lib/apt/lists/"*
find "$root/var/log" -type f -exec truncate -s0 {} +
truncate -s0 "$root/etc/machine-id"
rm -f "$root/var/lib/dbus/machine-id"
ln -sfn /run/NetworkManager/resolv.conf "$root/etc/resolv.conf"
# These are dpkg format tokens, not shell expansions.
# shellcheck disable=SC2016
chroot "$root" dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' >"$work/packages.tsv"
du -sx --block-size=1 "$root" >"$work/root-logical-size.txt"
