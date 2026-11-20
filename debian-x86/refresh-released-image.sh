#!/usr/bin/env bash
# Reuse the released Debian root; no OpenHD/QOpenHD compilation is required.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(realpath -m "${1:?Usage: refresh-released-image.sh WORKDIR [BASE_TAG]}")
tag=${2:-v0.1.0-preview}
mkdir -p "$work/base" "$work/root" "$work/builder" "$work/keys" "$work/new-debs"
gh release download "$tag" --repo OpenHD/OpenHD-OS --pattern openhd-os-x86.img --pattern SHA256SUMS --dir "$work/base" --clobber
(cd "$work/base"; awk '$2 == "openhd-os-x86.img" {print}' SHA256SUMS | sha256sum -c -)
loop=$(losetup --find --show --read-only --partscan "$work/base/openhd-os-x86.img")
source_mount=$(mktemp -d)
cleanup_source() { umount "$source_mount" 2>/dev/null || true; losetup -d "$loop"; rmdir "$source_mount"; }
trap cleanup_source EXIT
udevadm settle
file -s "${loop}p4"
btrfs inspect-internal dump-super -f "${loop}p4" | head -n 24
btrfs check --readonly "${loop}p4" >"$work/base/btrfs-check.txt" 2>&1 || {
    cat "$work/base/btrfs-check.txt"
    exit 1
}
mount -t btrfs -o ro,rescue=nologreplay "${loop}p4" "$source_mount" || {
    dmesg | tail -n 80
    exit 1
}
rsync -aHAXx --numeric-ids "$source_mount/" "$work/root/"
cleanup_source
trap - EXIT
rm -f "$work/base/openhd-os-x86.img"

# A small, separate Debian tool environment supplies image/VM tools and the GUI
# compiler. These development packages never enter the installed system.
curl -fsSL https://ftp-master.debian.org/keys/archive-key-13.asc | gpg --dearmor >"$work/keys/trixie.gpg"
mmdebstrap --architectures=amd64 --variant=minbase --keyring="$work/keys/trixie.gpg" \
    --include=ca-certificates,file,build-essential,cmake,ninja-build,qtbase5-dev,btrfs-progs,dosfstools,mtools,gdisk,grub-pc-bin,grub-efi-amd64-bin,grub-efi-ia32-bin,grub2-common,qemu-system-x86,qemu-utils,ovmf,fonts-dejavu-core \
    trixie "$work/builder" "deb [signed-by=$work/keys/trixie.gpg] https://deb.debian.org/debian trixie main"
mkdir -p "$work/builder/src/installer" "$work/builder/packages"
cp "$here/installer/"* "$work/builder/src/installer/"
cp "$here/build-installer-package.sh" "$work/builder/build-installer-package.sh"
chroot "$work/builder" bash /build-installer-package.sh /src/installer /packages/openhd-installer.deb
cp "$work/builder/packages/openhd-installer.deb" "$work/new-debs/"
bash "$here/build-os-config.sh" "$here/overlay" "$work/new-debs/openhd-os.deb"

mkdir -p "$work/root/tmp/openhd-config"
cp "$work/new-debs/"*.deb "$work/root/tmp/openhd-config/"
mount --rbind /dev "$work/root/dev"
mount --make-rslave "$work/root/dev"
mount -t proc proc "$work/root/proc"
trap 'umount "$work/root/proc"; umount -R "$work/root/dev"' EXIT
rm -f "$work/root/etc/resolv.conf"
cp --dereference /etc/resolv.conf "$work/root/etc/resolv.conf"
chroot "$work/root" apt-get update
chroot "$work/root" /bin/sh -c 'apt-get -o Dpkg::Options::=--force-confnew install -y --no-install-recommends /tmp/openhd-config/*.deb'
rm -f "$work/root/tmp/openhd-config/"*.deb
umount "$work/root/proc"
umount -R "$work/root/dev"
trap - EXIT
bash "$here/add-desktop.sh" "$work"
export IMAGE_BYTES=${IMAGE_BYTES:-2147483648}
bash "$here/assemble-and-test.sh" "$work" --test
bash "$here/test-app-root.sh" "$work"
cp "$work/desktop-apps.lock.json" "$work/output/"
