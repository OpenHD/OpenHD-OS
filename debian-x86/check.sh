#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
find "$here" -name '*.sh' -print0 | xargs -0 shellcheck
for script in "$here/overlay/usr/local/sbin/"*; do
    if head -1 "$script" | grep -q python; then
        python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); compile(p.read_text(),str(p),"exec")' "$script"
    else
        shellcheck "$script"
    fi
done
shellcheck "$here/overlay/etc/grub.d/09_openhd"
python3 -m py_compile "$here/"*.py
python3 -m unittest discover -s "$here/tests" -p 'test_*.py'
if command -v luac >/dev/null; then luac -p "$here/overlay/usr/share/openhd/desktop-config/hypr/hyprland.lua"; fi
menu=$(mktemp)
trap 'rm -f "$menu"' EXIT
sh "$here/overlay/usr/local/sbin/openhd-grub-menu" test-root vmlinuz-test >"$menu"
[[ $(grep -c '^menuentry\|^submenu' "$menu") == 4 ]]
[[ $(grep -c '^submenu' "$menu") == 1 ]]
grep -q "menuentry 'OpenHD' --id 'openhd'" "$menu"
! grep -Eq 'openhd\.install|openhd\.mode=desktop|terminal_output gfxterm' "$menu"
grep -q "submenu 'Advanced options'" "$menu"
echo 'PASS: shell, Python and GRUB menu checks'
