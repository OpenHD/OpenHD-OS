#!/usr/bin/env bash
# Exercise ImageWriter's real FAT writer against a disposable config image.
set -euo pipefail
work=$(realpath "${1:?Usage: verify-imagewriter.sh WORKDIR IMAGEWRITER_SOURCE}")
writer=$(realpath "${2:?ImageWriter source checkout}")
builder="$work/builder"
testdir="$builder/build/imagewriter-contract"
mkdir -p "$testdir/dependencies/fatfs" "$testdir/staging/openhd"
cp "$writer/src/"{fatimagewriter,archivepathvalidator}.{cpp,h} "$testdir/"
cp "$writer/src/dependencies/fatfs/"{ff.c,ff.h,ffconf.h,ffunicode.c,diskio.h} "$testdir/dependencies/fatfs/"
cat >"$testdir/main.cpp" <<'EOF'
#include <QCoreApplication>
#include <QDebug>
#include "fatimagewriter.h"
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (argc != 3) return 2;
    QString error;
    if (!FatImageWriter::install(app.arguments()[1], app.arguments()[2], &error)) {
        qCritical().noquote() << error;
        return 1;
    }
    qInfo() << "PASS: ImageWriter wrote and read back configuration on the real FAT image";
}
EOF
cat >"$testdir/verify.pro" <<'EOF'
QT += core
QT -= gui
CONFIG += console c++17
CONFIG -= app_bundle
TARGET = imagewriter-fat-check
SOURCES += main.cpp fatimagewriter.cpp archivepathvalidator.cpp dependencies/fatfs/ff.c dependencies/fatfs/ffunicode.c
HEADERS += fatimagewriter.h archivepathvalidator.h
EOF
printf '{"role":"ground","debug":true,"language":"en"}\n' >"$testdir/staging/openhd/settings.json"
cp "$work/output/config.img" "$testdir/partition.img"
chroot "$builder" /bin/bash -c 'cd /build/imagewriter-contract && qmake verify.pro && make -j2 && ./imagewriter-fat-check /build/imagewriter-contract/partition.img /build/imagewriter-contract/staging'
chroot "$builder" mtype -i /build/imagewriter-contract/partition.img ::/openhd/settings.json >"$testdir/readback.json"
cmp "$testdir/staging/openhd/settings.json" "$testdir/readback.json"
cat "$testdir/readback.json"
cp "$testdir/partition.img" "$work/output/imagewriter-provisioned-config.img"
