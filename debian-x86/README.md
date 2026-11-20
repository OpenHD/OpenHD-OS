# OpenHD Debian x86 minimal

This builds a normal writable Debian 13 (trixie) installation for an amd64 PC.
It boots directly into the production QOpenHD interface and runs the OpenHD ground
receiver and SysUtils. The optional desktop adds XFCE while retaining minimal
mode. There is no live system, compressed read-only root,
or RAM overlay. Btrfs compresses ordinary files on the writable root filesystem.

The distribution is presented as **OpenHD OS**: its own boot menu, console identity,
OpenHD Plymouth theme, and the existing QOpenHD boot-animation video. The animation
plays once before the flight HUD loads. Machine-readable `ID=debian` and the real
Debian codename/version remain available to package installers. Standard Debian
repositories, `.deb` packages and `apt` are retained.

The default disk-image budget is **1 GiB (1,073,741,824 bytes)**, including a BIOS
boot partition, 64 MiB configuration partition and 64 MiB EFI partition. The build fails if the compressed root
does not fit with at least 64 MiB of initial headroom. `size-report.txt` records
the actual result; the image is not silently enlarged to meet dependencies.

The first partition is a separate 64 MiB FAT32 volume labelled `OPENHD`, mounted
at `/Config`. It contains ImageWriter's `config.txt` discovery marker and the
standard `openhd/settings.json` input. `/boot/openhd` points to `/Config/openhd`
for QOpenHD settings import/export. The installer preserves this configuration
partition and its contents. EFI files use their own separate partition.
ImageWriter's optional `openhd/QOpenHD.conf` is imported before QOpenHD starts.
The launcher tracks the file's hash, so an unchanged backup does not overwrite
settings subsequently changed in the flight UI.

On first boot the last partition and Btrfs filesystem expand to the available
drive capacity. Settings, updates and additional apt packages persist directly
on that filesystem. A small drive has limited update/install headroom; an ordinary
larger USB stick or internal SSD provides additional writable capacity.

## Included

- APT, the stock Debian amd64 kernel, systemd, OpenHD, QOpenHD and SysUtils.
- Intel/AMD Mesa graphics, Intel/AMD VAAPI video decoding and software fallback.
- Intel, AMD, Realtek, Atheros and Broadcom firmware; laptop networking via
  NetworkManager, `nmtui` and `nmcli`.
- ADB **host tools**, available from the root maintenance console. An ADB gadget daemon is not
  configured: ordinary laptop USB ports cannot act as USB gadget controllers.
- Keyboard, mouse and touchscreen input through Qt/libinput.
- UEFI x64, UEFI IA32 for 64-bit Atom tablets with 32-bit firmware, and legacy BIOS.
  The CPU must support x86-64. The x64 boot path uses Debian's signed shim/GRUB
  and signed stock kernel; the IA32 bootloader is unsigned.

Ground mode explicitly enables Devourer, and packages SysUtils' device ownership
rules. There are no replacement legacy broadcast Wi-Fi kernel drivers. Ordinary
onboard Wi-Fi drivers remain available for management networking.

## Display

The appliance uses Qt EGLFS directly on DRM/KMS, with no window manager. With a
compatible NV12 primary plane and an ARGB overlay above it, QOpenHD puts the HUD
on the overlay and imports VAAPI DMA-BUF surfaces into the video plane beneath
it. It uses EGLFS' DRM file descriptor and retains decoder surfaces until a
blocking flip completes. An unsupported layout, format or atomic commit falls
back to the existing OpenGL video renderer. No fixed card, connector or plane ID
is assumed. Direct scanout remains hardware-dependent and requires real GPU tests.

Run `openhd-gpu-info` on the target to inspect DRM devices, VAAPI H.264/HEVC decode
profiles and QOpenHD's actual decoder selection. Older GPUs may lack HEVC decode
even though they render the HUD. Software decoding is a compatibility fallback;
it does not satisfy the H.265 performance target. Intel/AMD VAAPI is included;
proprietary NVIDIA drivers are not included in this minimal size budget.

The boot menu includes Compatible Video (disable the video-plane path) and a
maintenance console. USB boot offers a graphical welcome and installer before QOpenHD; no first-boot
password dialog interrupts the display.

## Build

Use a Linux amd64 builder with root privileges and about 15 GiB of free workspace.
Host tools: `mmdebstrap curl gnupg git rsync util-linux python3`, with access to
`/dev/kvm` for filesystem compaction using the image's own kernel. The build creates
its own Debian compiler environment; Ubuntu OpenHD packages are not installed
into Debian. Source checkouts must have their required submodules initialized.

For a Windows source checkout, export sources using native Git before entering
WSL. This avoids copying thousands of headers individually over the Windows/WSL
filesystem bridge:

```powershell
python debian-x86/export-sources.py C:/path/to/source-parent C:/Temp/openhd-sources.tar.gz
```

The source parent contains `OpenHD` (the directory containing its CMakeLists.txt),
`QOpenHD`, and `OpenHD-SysUtils`. Changes to tracked files and the new x86 KMS
sources are included. On Linux:

```sh
sudo bash debian-x86/build.sh /opt/openhd-x86-work /mnt/c/Temp/openhd-sources.tar.gz
```

A directory containing those source trees can also be supplied directly. Use a
persistent workspace, particularly in WSL, where `/mnt/wsl` disappears when the VM
stops. Set `JOBS` for the compiler parallelism; the default is four. An explicit
`IMAGE_BYTES` can build a larger variant without changing the default size gate.

Outputs are in `WORKDIR/output`: the raw `.img`, SHA256SUMS, installed-package
manifest, size report, GPT verification and read-only Btrfs check.

After a successful root build, run the following to rebuild the image and boot-test
it with KVM/QEMU:

```sh
sudo bash debian-x86/assemble-and-test.sh /opt/openhd-x86-work --test
```

The test installs onto a disposable virtual disk and then boots that disk without
the USB source. Its serial login overrides exist only in test disk overlays.
Virtual graphics cannot establish Intel/AMD H.265 hardware-decode performance.

## Boot from USB and install

Write the raw image to a USB drive using an image writer and boot the drive. This
is already a persistent installation; unplugging it does not discard its changes.
No internal disk is selected or modified during boot.

GRUB waits one second and defaults directly to **Start QOpenHD in minimal mode**.
Choose **Start OpenHD-OS** for the desktop, **Install OpenHD minimal** or
**Install OpenHD-OS** for the graphical installer, or **Advanced** for compatible
video and maintenance. The unified image includes both modes and is capped at
1.5 GB; a minimal-only build remains 1 GiB.
No terminal commands are required. The wizard lists disk model, size and serial,
disables disks in use, and shows the selected disk again before erasing it.
Two explicit acknowledgements enable the final **Erase disk and install** button.
Progress, errors and restart/shutdown controls stay in the GUI.

Installation works offline and copies the current OpenHD configuration. Minimal
installation defaults to QOpenHD; desktop installation defaults to OpenHD-OS.
Both modes remain accessible from the boot menu. The GUI uses the existing Qt
runtime, so it can also run in a minimal-only image.

Use Ctrl+Alt+F2 for the local root maintenance console, and Ctrl+Alt+F1 to return
to QOpenHD. Getty and automatic login activation are masked on tty1, and kernel
messages use tty3, keeping QOpenHD free of console text.
Remote root access is not enabled. For maintenance and automated validation, the
same guarded installation backend remains available from this console:

```sh
openhd-install --list
openhd-install --target /dev/nvme0n1 --dry-run
openhd-install --target /dev/nvme0n1
```

Choose the actual target shown in the list. The installer displays its model and
serial and requires the exact typed confirmation `ERASE /dev/nvme0n1`. It rejects
the running USB disk, mounted partitions, active swap/storage holders, read-only
disks and partition paths. It rechecks disk identity before writing, creates a new
filesystem UUID, copies the native installation and installs both EFI loaders and
BIOS GRUB. Shut down and remove the USB drive to boot the internal installation.

APT remains ordinary APT: `apt-get update`, then `apt-get install PACKAGE`.
QGroundControl, ArduDeck, INAV and Betaflight belong to a later desktop variant;
they are not part of this minimal image or its size budget.
