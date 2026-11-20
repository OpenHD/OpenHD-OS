#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=${1:?Usage: build.sh WORKDIR SOURCE_PARENT_OR_TAR_GZ}
sources=${2:?Source directory or export-sources.py archive}
[[ $EUID == 0 ]] || { echo 'Run on a Linux amd64 builder as root.' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || exit 1
bash "$here/bootstrap-builder.sh" "$work" "$sources"
bash "$here/make-root.sh" "$work"
bash "$here/assemble-and-test.sh" "$work"
