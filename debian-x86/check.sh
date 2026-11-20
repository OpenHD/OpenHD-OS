#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
find "$here" -name '*.sh' -print0 | xargs -0 shellcheck
shellcheck "$here/overlay/usr/local/sbin/"* "$here/overlay/etc/grub.d/09_openhd"
python3 -m py_compile "$here/"*.py
menu=$(mktemp)
trap 'rm -f "$menu"' EXIT
sh "$here/overlay/usr/local/sbin/openhd-grub-menu" test-root vmlinuz-test >"$menu"
[[ $(grep -c '^menuentry\|^submenu' "$menu") == 7 ]]
[[ $(grep -c '^submenu' "$menu") == 1 ]]
grep -q "menuentry 'Start QOpenHD in minimal mode'" "$menu"
grep -q "menuentry 'Start OpenHD-OS'" "$menu"
grep -q "menuentry 'Install OpenHD minimal'" "$menu"
grep -q "menuentry 'Install OpenHD-OS'" "$menu"
grep -q "submenu 'Advanced'" "$menu"
echo 'PASS: shell, Python and GRUB menu checks'
