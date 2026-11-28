#!/usr/bin/env bash
# Run inside a Debian trixie amd64 build chroot; sources are under /src.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
jobs=${JOBS:-4}
package_version="0.1+$(date -u +%Y%m%d%H%M%S)"
if [[ ${OPENHD_SNAPSHOT_NUMBER:-} =~ ^[1-9][0-9]*$ ]]; then
    package_version="1:4.2.$OPENHD_SNAPSHOT_NUMBER"
fi
apt-get update
apt-get install -y --no-install-recommends build-essential cmake ninja-build pkg-config \
    python3 git rsync qtbase5-dev qtbase5-private-dev qtdeclarative5-dev \
    libqt5charts5-dev libqt5opengl5-dev libqt5texttospeech5-dev qtmultimedia5-dev \
    qttools5-dev-tools libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libdrm-dev libegl-dev libgles-dev libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev libpoco-dev libusb-1.0-0-dev libpcap-dev \
    libsodium-dev libnl-3-dev libnl-genl-3-dev libnl-route-3-dev libncurses-dev libsdl2-dev librtlsdr-dev \
    btrfs-progs dosfstools mtools gdisk grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin qemu-system-x86 qemu-utils
mkdir -p /build/qopenhd /packages
if [[ ${SKIP_ALL_BUILDS:-0} != 1 ]]; then
if [[ ${SKIP_QOPENHD_BUILD:-0} != 1 ]]; then
    cd /build/qopenhd
    qmake /src/QOpenHD/QOpenHD.pro CONFIG+=release CONFIG-=debug
    make -j"$jobs"
fi
openhd_source=/src/OpenHD
# The OpenHD 3.0 source branch is the distribution superproject; its CMake
# application lives one directory below the checkout root. Older source exports
# already place the CMake project at /src/OpenHD.
if [[ ! -f "$openhd_source/CMakeLists.txt" && -f "$openhd_source/OpenHD/CMakeLists.txt" ]]; then
    openhd_source="$openhd_source/OpenHD"
fi
cmake -S "$openhd_source" -B /build/openhd -G Ninja -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DENABLE_AIR=OFF -DENABLE_USB_CAMERAS=OFF -DENABLE_GSTREAMER=OFF \
    -DWB_ENABLE_SIMD_OPTIMIZATIONS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build /build/openhd --target openhd -j "$jobs"
cmake -S /src/OpenHD-SysUtils -B /build/sysutils -G Ninja \
    -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_TESTING=OFF
cmake --build /build/sysutils -j "$jobs"
cmake -S /src/openhd-installer -B /build/installer -G Ninja -DCMAKE_BUILD_TYPE=MinSizeRel
cmake --build /build/installer -j "$jobs"
fi
for component in ${PACKAGE_COMPONENTS:-qopenhd openhd openhd-sys-utils openhd-installer openhd-os}; do
    stage=/packages/$component
    mkdir -p "$stage/DEBIAN" "$stage/usr/local/bin"
    chmod 0755 "$stage/DEBIAN"
    case "$component" in
        openhd-os)
            bash /src/build-os-config.sh /src/openhd-os-overlay /packages/openhd-os.deb
            continue ;;
        openhd-installer)
            install -s /build/installer/openhd-installer "$stage/usr/local/bin/openhd-installer"
            extra='openhd, openhd-sys-utils';;
        qopenhd)
            install -s /build/qopenhd/release/QOpenHD "$stage/usr/local/bin/QOpenHD"
            extra='qml-module-qtquick2, qml-module-qtqml, qml-module-qtmultimedia, libqt5multimedia5-plugins, qml-module-qtquick-controls, qml-module-qtquick-controls2, qml-module-qtquick-layouts, qml-module-qtquick-dialogs, qml-module-qtquick-window2, qml-module-qtquick-extras, qml-module-qtquick-shapes, qml-module-qt-labs-settings, qml-module-qt-labs-platform, qml-module-qtgraphicaleffects, qml-module-qtlocation, qml-module-qtpositioning, qml-module-qtcharts, libqt5sql5-sqlite, libqt5svg5, gstreamer1.0-plugins-good, gstreamer1.0-gl, gstreamer1.0-qt5';;
        openhd)
            install -s /build/openhd/openhd "$stage/usr/local/bin/openhd"
            mkdir -p "$stage/usr/local/share/openhd/settings"
            cp "$openhd_source"/settings/generated/*.json "$stage/usr/local/share/openhd/settings/"
            extra='network-manager, iw, iproute2, iptables';;
        openhd-sys-utils)
            DESTDIR="$stage" cmake --install /build/sysutils --strip
            extra='init-system-helpers, dosfstools, util-linux, parted, wireguard-tools, curl, usb-modeswitch';;
    esac
    # Resolve the actual Debian ABI names rather than carrying Ubuntu dependencies.
    mkdir -p /build/deps/debian
    printf 'Source: openhd-local\nSection: misc\nPriority: optional\nMaintainer: OpenHD <developers@openhd.org>\n\nPackage: openhd-local\nArchitecture: any\nDescription: local dependency scan\n' >/build/deps/debian/control
    cd /build/deps
    find "$stage/usr/local" -type f -executable -exec sh -c 'file -b "$1" | grep -q ELF && printf "%s\n" "$1"' sh {} \; > /build/deps/binaries.txt
    mapfile -t binaries < /build/deps/binaries.txt
    args=()
    for binary in "${binaries[@]}"; do args+=("-e$binary"); done
    dependencies=init-system-helpers
    if ((${#args[@]})); then dependencies=$(dpkg-shlibdeps -O "${args[@]}" | sed -n 's/^shlibs:Depends=//p'); fi
    printf 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: OpenHD <developers@openhd.org>\nDepends: %s, %s\nDescription: OpenHD Debian x86 minimal %s\n' \
        "$component" "$package_version" "$dependencies" "$extra" "$component" >"$stage/DEBIAN/control"
    dpkg-deb --root-owner-group --build "$stage" "/packages/$component.deb"
done
