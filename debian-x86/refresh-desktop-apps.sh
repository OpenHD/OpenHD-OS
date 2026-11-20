#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=${1:?Usage: refresh-desktop-apps.sh WORKDIR [--test]}
python3 "$here/install-desktop-apps.py" "$work"
export IMAGE_BYTES=${IMAGE_BYTES:-2000000000}
bash "$here/assemble-and-test.sh" "$work" "${2:---test}"
