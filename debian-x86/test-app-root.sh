#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(realpath "${1:?Usage: test-app-root.sh WORKDIR}")
builder="$work/builder"
mounts=()
cleanup() {
    for ((i=${#mounts[@]}-1; i>=0; i--)); do umount -R "${mounts[i]}"; done
}
trap cleanup EXIT
for path in dev proc work output; do
    if ! mountpoint -q "$builder/$path"; then
        case "$path" in
            dev|proc) source="/$path" ;;
            work) source="$work" ;;
            output) source="$work/output" ;;
        esac
        mount --rbind "$source" "$builder/$path"
        mount --make-rslave "$builder/$path"
        mounts+=("$builder/$path")
    fi
done
python3 "$here/test-desktop-apps.py" "$work"
