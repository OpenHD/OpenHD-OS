#!/usr/bin/env bash
# Refresh an existing native root using new Debian packages, without recompiling
# components or recreating Debian. Reassembly always enforces the image size gate.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(realpath "${1:?Usage: update-packages.sh WORKDIR DEB_DIRECTORY [--test]}")
packages=$(realpath "${2:?Supply the new amd64 Debian package directory}")
[[ $EUID == 0 && -f "$work/root/etc/debian_version" ]] || exit 1
shopt -s nullglob
debs=("$packages/"*.deb)
((${#debs[@]})) || { echo 'No Debian packages supplied.' >&2; exit 1; }
mkdir -p "$work/root/tmp/openhd-update" "$work/builder/packages"
for deb in "${debs[@]}"; do
    arch=$(dpkg-deb -f "$deb" Architecture)
    [[ "$arch" == amd64 || "$arch" == all ]] || { echo "Wrong package architecture: $arch" >&2; exit 1; }
    cp "$deb" "$work/root/tmp/openhd-update/"
done
mount --rbind /dev "$work/root/dev"
mount --make-rslave "$work/root/dev"
mount -t proc proc "$work/root/proc"
cleanup() {
    umount "$work/root/proc"
    umount -R "$work/root/dev"
    rm -f "$work/root/tmp/openhd-update/"*.deb
}
trap cleanup EXIT
rm -f "$work/root/etc/resolv.conf"
cp --dereference /etc/resolv.conf "$work/root/etc/resolv.conf"
chroot "$work/root" apt-get update
# APT determines which supplied packages and ABI dependencies actually change.
chroot "$work/root" /bin/sh -c 'apt-get -o Dpkg::Options::=--force-confold install -y --no-install-recommends /tmp/openhd-update/*.deb'
chroot "$work/root" apt-get clean
# shellcheck disable=SC2016
chroot "$work/root" dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' >"$work/packages.tsv"
for deb in "${debs[@]}"; do
    package=$(dpkg-deb -f "$deb" Package)
    cp "$deb" "$work/builder/packages/$package.deb"
done
cleanup
trap - EXIT
ln -sfn /run/NetworkManager/resolv.conf "$work/root/etc/resolv.conf"
bash "$here/assemble-and-test.sh" "$work" "${3:-}"
