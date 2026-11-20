#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=${1:?Usage: bootstrap-builder.sh WORKDIR SOURCE_PARENT}
sources=${2:?Source parent containing OpenHD, QOpenHD and OpenHD-SysUtils}
mkdir -p "$work/keys"
work=$(realpath "$work")
if [[ ! -f "$work/keys/trixie.gpg" ]]; then
    curl -fsSL https://ftp-master.debian.org/keys/archive-key-13.asc |
        gpg --dearmor >"$work/keys/trixie.gpg"
fi
if [[ ! -e "$work/builder/etc/debian_version" ]]; then
    mmdebstrap --architectures=amd64 --variant=minbase \
        --keyring="$work/keys/trixie.gpg" \
        --include=ca-certificates,file,debian-archive-keyring trixie "$work/builder" \
        "deb [signed-by=$work/keys/trixie.gpg] https://deb.debian.org/debian trixie main"
    printf 'deb https://deb.debian.org/debian trixie main\ndeb https://deb.debian.org/debian-security trixie-security main\ndeb https://deb.debian.org/debian trixie-updates main\n' >"$work/builder/etc/apt/sources.list"
fi
mkdir -p "$work/builder/src"
if [[ -f "$sources" ]]; then
    tar -xzf "$sources" -C "$work/builder/src"
else
for repo in OpenHD QOpenHD OpenHD-SysUtils; do
    # Include current tracked changes and initialized submodules, excluding bench captures.
    git -c safe.directory='*' -C "$sources/$repo" ls-files --recurse-submodules -z |
        rsync -a --from0 --files-from=- "$sources/$repo/" "$work/builder/src/$repo/"
done
# New files being developed locally are not in ls-files until staged.
rsync -a "$sources/QOpenHD/app/videostreaming/avcodec/drm_kms/" \
    "$work/builder/src/QOpenHD/app/videostreaming/avcodec/drm_kms/"
fi
# Windows checkouts may contain CRLF scripts. Normalize only the isolated copy.
find "$work/builder/src" -type f \( -name '*.sh' -o -name '*.py' \) \
    -exec sed -i 's/\r$//' {} +
install -m755 "$here/build-packages.sh" "$work/builder/build-packages.sh"
install -m755 "$here/build-os-config.sh" "$work/builder/src/build-os-config.sh"
mkdir -p "$work/builder/src/openhd-installer"
cp "$here/installer/"* "$work/builder/src/openhd-installer/"
mkdir -p "$work/builder/src/openhd-os-overlay"
cp -a "$here/overlay/." "$work/builder/src/openhd-os-overlay/"
find "$work/builder/src/openhd-os-overlay" -type f ! -name '*.png' ! -name '*.pf2' -exec sed -i 's/\r$//' {} +
chroot "$work/builder" /bin/bash /build-packages.sh
