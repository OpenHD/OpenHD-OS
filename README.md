# OpenHD-OS

Debian 13 amd64 image with APT, OpenHD, QOpenHD, GPU decode/KMS integration,
the OpenHD boot animation, and a graphical disk installer.

GRUB waits **one second** and starts QOpenHD directly by default:

1. Start QOpenHD in minimal mode
2. Start OpenHD-OS
3. Install OpenHD minimal
4. Install OpenHD-OS
5. Advanced

The minimal image is 1 GiB including the FAT configuration partition, EFI and
BIOS boot support. The unified image includes the small XFCE desktop and minimal
QOpenHD mode, aiming for 1 GB with a hard limit of 1.5 GB (1,499,987,968 bytes).
If a minimal-only image is built, desktop entries explain that desktop packages
are unavailable.
The installer works without a terminal and requires explicit erase confirmation.

## Build

On an amd64 Linux host as root, install `mmdebstrap`, `curl`, `gnupg`, `git`,
`python3` and `rsync`. Export sources from the OpenHD, QOpenHD and SysUtils repos
with `debian-x86/export-sources.py`, then:

```sh
bash debian-x86/build.sh /opt/openhd-os-work sources.tar.gz
bash debian-x86/assemble-and-test.sh /opt/openhd-os-work --test
```

The build chroot contains the compiler and development packages; they are not
installed into the image. See [the image build notes](debian-x86/README.md).

To produce the unified image, add the desktop packages to the cached root, then:

```sh
bash debian-x86/add-desktop.sh /opt/openhd-os-desktop-work
IMAGE_BYTES=1499987968 bash debian-x86/assemble-and-test.sh /opt/openhd-os-desktop-work --test
```

## Update packages without rebuilding the base

Keep the work directory (builder + native root). Supply only new **Debian 13
amd64** `.deb` packages; APT resolves their changed dependencies. Ubuntu packages
are not interchangeable with these Debian ABI builds.

```sh
bash debian-x86/update-packages.sh /opt/openhd-os-work /path/to/new-debs --test
```

This does not compile OpenHD/QOpenHD or bootstrap Debian. It refreshes the cached
root and rebuilds the raw image, checksum, package manifest and filesystem checks.
The one-GiB size gate remains enforced. It never flashes a physical disk.
ImageBuilder can invoke the same entry point through its `scripts/openhd-os.sh`
integration, pinned to a revision of this repository.

`openhd-os.deb` carries the distribution's service files, installer backend,
session launcher and GRUB generator. `openhd-installer.deb` carries the GUI;
`qopenhd.deb`, `openhd.deb` and `openhd-sys-utils.deb` carry the components.
Supply only the changed packages. The manual GitHub Actions workflow can build
packages alone or a complete minimal/desktop image.

## Validation boundary

BIOS, x64 UEFI Secure Boot, IA32 UEFI, graphical installation to a disposable
virtual disk and installed boot without USB have been tested under KVM/QEMU.
Physical Intel/AMD hardware decode, KMS video planes, radio and tablet touch
still need target-hardware validation. Desktop profile testing is separate.

GPL-3.0; existing OpenHD boot assets and Devourer preparation policy originate
from OpenHD-ImageBuilder. Component sources retain their upstream licenses.
