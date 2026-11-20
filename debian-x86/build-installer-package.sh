#!/usr/bin/env bash
# Run inside the Debian builder; builds only the small Qt installer.
set -euo pipefail
source=${1:?Usage: build-installer-package.sh SOURCE OUTPUT_DEB}
output=$(realpath -m "${2:?Supply output package}")
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cmake -S "$source" -B "$build/binary" -G Ninja -DCMAKE_BUILD_TYPE=MinSizeRel
cmake --build "$build/binary" -j2
mkdir -p "$build/stage/DEBIAN" "$build/stage/usr/local/bin" "$build/debian"
chmod 755 "$build/stage" "$build/stage/DEBIAN"
install -s "$build/binary/openhd-installer" "$build/stage/usr/local/bin/openhd-installer"
printf 'Source: openhd-installer\nSection: misc\nPriority: optional\nMaintainer: OpenHD <developers@openhd.org>\n\nPackage: openhd-installer\nArchitecture: amd64\nDescription: OpenHD graphical installer\n' >"$build/debian/control"
cd "$build"
dependencies=$(dpkg-shlibdeps -O -e"$build/stage/usr/local/bin/openhd-installer" | sed -n 's/^shlibs:Depends=//p')
printf 'Package: openhd-installer\nVersion: 0.2+%s\nArchitecture: amd64\nMaintainer: OpenHD <developers@openhd.org>\nDepends: %s, openhd, openhd-sys-utils\nDescription: OpenHD OS graphical installation wizard\n' "$(date -u +%Y%m%d%H%M%S)" "$dependencies" >"$build/stage/DEBIAN/control"
dpkg-deb --root-owner-group --build "$build/stage" "$output"
