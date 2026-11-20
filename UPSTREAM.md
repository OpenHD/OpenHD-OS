# Upstream components

This repository owns the distribution assembly, boot menu, session policy and
graphical installer. OpenHD, QOpenHD and SysUtils remain separate repositories.
Build packages against Debian 13, not the Ubuntu package ABI.

The `patches/` directory records the pending QOpenHD VAAPI/KMS integration and
SysUtils UUID-mount protection used for the initial image. Apply these to the
corresponding upstream checkout before exporting sources. The exporter includes
tracked modifications and the new KMS files in its source manifest. No unrelated
local OpenHD camera-registry changes are part of these patches.
