#!/usr/bin/env bash
# Build the compositor plugin against the exact Hyprland version in the image.
set -euo pipefail
work=$(realpath "${1:?Usage: build-window-titlebars.sh WORKDIR}")
root="$work/root"
builder="$work/builder"
version=$(chroot "$root" dpkg-query -W -f='${Version}' hyprland)
plugin_commit=90e66baf99c9025b1d5e9c9e58dd3c80d0911ea2 # v0.55.0
source_dir=$(mktemp -d "$builder/tmp/openhd-hyprbars.XXXXXX")
trap 'rm -rf "$source_dir"' EXIT
guest_dir=${source_dir#"$builder"}
printf 'deb https://deb.debian.org/debian trixie-backports main\n' >"$builder/etc/apt/sources.list.d/openhd-backports.list"
chroot "$builder" apt-get update
chroot "$builder" apt-get -t trixie-backports install -y --no-install-recommends \
    "hyprland-dev=$version" g++ make pkg-config libpango1.0-dev libpixman-1-dev \
    libdrm-dev libinput-dev libudev-dev libwayland-dev libxkbcommon-dev
curl -fsSL --retry 3 "https://codeload.github.com/hyprwm/hyprland-plugins/tar.gz/$plugin_commit" |
    tar -xz --strip-components=1 -C "$source_dir"
chroot "$builder" make -j2 -C "$guest_dir/hyprbars" CXX=g++
chroot "$builder" strip --strip-unneeded "$guest_dir/hyprbars/hyprbars.so"
package="$source_dir/package"
install -Dm644 "$source_dir/hyprbars/hyprbars.so" "$package/usr/lib/openhd/hyprbars.so"
install -Dm644 "$source_dir/LICENSE" "$package/usr/share/doc/openhd-window-titlebars/copyright"
mkdir -p "$package/DEBIAN"
cat >"$package/DEBIAN/control" <<EOF
Package: openhd-window-titlebars
Version: $version
Architecture: amd64
Maintainer: OpenHD <developers@openhd.org>
Depends: hyprland (= $version)
Description: OpenHD desktop window title bars
EOF
dpkg-deb --root-owner-group --build "$package" "$root/tmp/openhd-window-titlebars.deb"
chroot "$root" dpkg -i /tmp/openhd-window-titlebars.deb
rm -f "$root/tmp/openhd-window-titlebars.deb"
