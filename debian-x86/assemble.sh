#!/usr/bin/env bash
# Runs in the Debian builder. Builds regular files only, never a physical disk.
set -euo pipefail
work=${1:?Usage: assemble.sh WORKDIR}
root="$work/root"
out=${OUTPUT_DIR:-$work/output}
mkdir -p "$out" "$root/boot/grub" "$root/boot/efi"
bytes=${IMAGE_BYTES:-2147483648}
root_start=266240 # Config 64 MiB, BIOS 1 MiB, ESP 64 MiB, root last.
root_sectors=$((bytes / 512 - root_start - 33))
root_uuid=$(cat /proc/sys/kernel/random/uuid)
efi_id=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ' | tr 'a-f' 'A-F')
efi_uuid="${efi_id:0:4}-${efi_id:4:4}"
config_id=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ' | tr 'a-f' 'A-F')
config_uuid="${config_id:0:4}-${config_id:4:4}"
printf 'UUID=%s / btrfs defaults,compress-force=zstd:6,noatime 0 0\nUUID=%s /boot/efi vfat umask=0077 0 2\nUUID=%s /Config vfat defaults,umask=0077 0 2\n' \
    "$root_uuid" "$efi_uuid" "$config_uuid" >"$root/etc/fstab"
kernel=$(basename "$(find "$root/boot" -maxdepth 1 -name 'vmlinuz-*' | sort -V | tail -1)")
version=${kernel#vmlinuz-}
{
    printf 'set timeout_style=hidden\nset timeout=0\nset default=openhd\n'
    sh "$root/usr/local/sbin/openhd-grub-menu" "$root_uuid" "$kernel"
} >"$root/boot/grub/grub.cfg"
# GRUB expands these variables, not the builder shell.
# shellcheck disable=SC2016
printf 'search --no-floppy --fs-uuid --set=root %s\nset prefix=($root)/boot/grub\nconfigfile $prefix/grub.cfg\n' \
    "$root_uuid" >"$out/early.cfg"
for platform in x86_64-efi i386-efi; do
    grub-mkstandalone -O "$platform" --locales='' --fonts='' \
        --modules='part_gpt btrfs normal linux search search_fs_uuid configfile all_video gfxterm gfxmenu png font' \
        -o "$out/$platform.efi" "boot/grub/grub.cfg=$out/early.cfg"
done
rm -f "$out/efi.img"
rm -f "$out/config.img"
truncate -s 64M "$out/config.img"
mkfs.vfat -F32 -n OPENHD -i "$config_id" "$out/config.img"
mcopy -s -i "$out/config.img" "$root/usr/share/openhd/config-defaults/"* ::/
truncate -s 64M "$out/efi.img"
mkfs.vfat -F32 -i "$efi_id" "$out/efi.img"
mmd -i "$out/efi.img" ::/EFI ::/EFI/BOOT ::/EFI/debian
# Use Debian's signed shim/GRUB for x64; keep the standalone IA32 loader for tablets.
mcopy -i "$out/efi.img" "$root/usr/lib/shim/shimx64.efi.signed" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$out/efi.img" "$root/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ::/EFI/BOOT/grubx64.efi
mcopy -i "$out/efi.img" "$root/usr/lib/shim/mmx64.efi.signed" ::/EFI/BOOT/mmx64.efi
mcopy -i "$out/efi.img" "$out/early.cfg" ::/EFI/BOOT/grub.cfg
mcopy -i "$out/efi.img" "$out/early.cfg" ::/EFI/debian/grub.cfg
mcopy -i "$out/efi.img" "$out/i386-efi.efi" ::/EFI/BOOT/BOOTIA32.EFI
mkfs.btrfs --help 2>&1 | grep -- --compress >/dev/null || {
    echo 'Requires btrfs-progs with mkfs --rootdir --compress support.' >&2; exit 1;
}
rm -f "$out/root.btrfs"
truncate -s "$((root_sectors * 512))" "$out/root.btrfs"
mkfs.btrfs -f -M -n 4096 -d single -m single -U "$root_uuid" --rootdir "$root" \
    --compress zstd:9 "$out/root.btrfs" >"$out/btrfs-build.txt"
root_bytes=$(stat -c %s "$out/root.btrfs")
if ((root_bytes > root_sectors * 512)); then
    # mkfs --rootdir sizes its initial workspace from uncompressed inputs.
    # A real Btrfs kernel relocates its extents into the final size. QEMU also
    # works on builders such as WSL whose host kernel lacks Btrfs support.
    python3 /compact-root.py "$out/root.btrfs" "$root/boot/$kernel" \
        "$root/boot/initrd.img-$version" "$((root_sectors * 512))"
    root_bytes=$(stat -c %s "$out/root.btrfs")
fi
used_bytes=$(btrfs inspect-internal dump-super "$out/root.btrfs" | awk '$1 == "bytes_used" {print $2}')
# Leave room for first-boot state, settings, and small apt operations at the target size.
if ((root_bytes > root_sectors * 512 || used_bytes + 64 * 1024 * 1024 > root_bytes)); then
    echo "Root data needs $used_bytes bytes plus 64 MiB free; exceeds $bytes-byte image." >&2
    exit 1
fi
image="$out/openhd-os-x86.img"
rm -f "$image"
truncate -s "$bytes" "$image"
sgdisk --clear --new=1:2048:133119 --typecode=1:0700 --change-name=1:OPENHD \
    --new=2:133120:135167 --typecode=2:ef02 \
    --new=3:135168:266239 --typecode=3:ef00 \
    --new=4:$root_start:0 --typecode=4:8300 "$image"
dd if="$out/config.img" of="$image" bs=512 seek=2048 conv=notrunc status=none
dd if="$out/efi.img" of="$image" bs=512 seek=135168 conv=notrunc status=none
dd if="$out/root.btrfs" of="$image" bs=512 seek="$root_start" conv=notrunc status=none
mkdir -p "$out/bios"
cp /usr/lib/grub/i386-pc/boot.img "$out/bios/"
grub-mkimage -O i386-pc -o "$out/bios/core.img" -p /boot/grub -c "$out/early.cfg" \
    biosdisk part_gpt btrfs normal linux search search_fs_uuid configfile all_video gfxterm gfxmenu png font
loop=$(losetup --find --show --partscan "$image")
trap 'losetup -d "$loop"' EXIT
/usr/lib/grub/i386-pc/grub-bios-setup --skip-fs-probe -d "$out/bios" "$loop"
losetup -d "$loop"
trap - EXIT
btrfs check --readonly "$out/root.btrfs" >"$out/btrfs-check.txt" 2>&1
sgdisk --verify "$image" >"$out/partition-check.txt"
cp "$work/packages.tsv" "$out/"
printf 'image_bytes=%s\nroot_filesystem_bytes=%s\nroot_used_bytes=%s\nminimum_free_bytes=%s\nroot_uuid=%s\nkernel=%s\n' \
    "$bytes" "$root_bytes" "$used_bytes" "$((root_bytes - used_bytes))" "$root_uuid" "$version" >"$out/size-report.txt"
(cd "$out" && sha256sum openhd-os-x86.img >SHA256SUMS)
echo "Built $image"
