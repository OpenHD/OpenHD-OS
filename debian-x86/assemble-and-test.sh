#!/usr/bin/env bash
# Resume from successfully built packages/root; all test disks are regular files.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(realpath "${1:?Usage: assemble-and-test.sh WORKDIR [--test]}")
builder="$work/builder"
[[ $EUID == 0 && -d "$builder" && -s "$work/packages.tsv" ]] || exit 1
mkdir -p "$builder/work" "$builder/output" "$work/output"
mounts=()
cleanup() {
    for ((i=${#mounts[@]}-1; i>=0; i--)); do umount -R "${mounts[i]}"; done
}
trap cleanup EXIT
for path in dev proc; do
    if ! mountpoint -q "$builder/$path"; then
        mount --rbind "/$path" "$builder/$path"
        mount --make-rslave "$builder/$path"
        mounts+=("$builder/$path")
    fi
done
for path in work output; do
    if ! mountpoint -q "$builder/$path"; then
        source="$work"
        [[ "$path" != output ]] || source="$work/output"
        mount --bind "$source" "$builder/$path"
        mounts+=("$builder/$path")
    fi
done
install -m755 "$here/assemble.sh" "$builder/assemble.sh"
install -m755 "$here/compact-root.py" "$builder/compact-root.py"
if [[ ${2:-} != --test-only ]]; then chroot "$builder" /bin/bash /assemble.sh /work; fi
if [[ ${2:-} == --test || ${2:-} == --test-only ]]; then
    chroot "$builder" apt-get install -y --no-install-recommends qemu-system-x86 qemu-utils ovmf
    python3 "$here/smoke-test.py" --builder "$builder" --root "$work/root" --output "$work/output"
fi
