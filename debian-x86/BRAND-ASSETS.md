# Desktop launcher artwork

The launcher ships upstream application artwork so its tiles do not depend on
theme lookup or low-resolution desktop-icon variants. These files are snapshots
from the projects' official repositories; the image build does not fetch them.

| Tile | Bundled asset | Upstream source |
| --- | --- | --- |
| QOpenHD | `overlay/usr/share/openhd/brand/apps/qopenhd-wordmark.png` | [OpenHD/QOpenHD](https://github.com/OpenHD/QOpenHD/blob/2.7-evo/icons/_1A-FULL_LLL%26RRR_OpenHDLogo-Modified.png) |
| ArduDeck | `overlay/usr/share/openhd/brand/apps/ardudeck.png` | [rubenCodeforges/ardudeck](https://github.com/rubenCodeforges/ardudeck/blob/master/apps/desktop/src/renderer/assets/logo.png) |
| Kite GCS | `overlay/usr/share/openhd/brand/apps/kitegc.svg` | [b14ckyy/Kite-GC](https://github.com/b14ckyy/Kite-GC/blob/master/static/branding/kitegc-icon-white.svg) |
| INAV | `overlay/usr/share/openhd/brand/apps/inav.png` | [iNavFlight/inav-configurator](https://github.com/iNavFlight/inav-configurator/blob/master/assets/linux/icon/inav_icon_english_128.png) |
| Betaflight | `overlay/usr/share/openhd/brand/apps/betaflight.svg` | [betaflight/betaflight-configurator](https://github.com/betaflight/betaflight-configurator/blob/master/src/images/bf_logo_short_white.svg) |

The artwork remains identifiable to its upstream project; OpenHD-OS only sets
the launcher tile size and does not redraw or recolor the marks.
