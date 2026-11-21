#!/usr/bin/env python3
"""Install upstream stable desktop apps into an existing Debian image root."""
import argparse
import configparser
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=pathlib.Path)
    parser.add_argument("--use-lock", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    root = work / "root"
    if os.geteuid() != 0 or not (root / "etc/debian_version").is_file() or not (root / "usr/bin/Hyprland").is_file():
        raise RuntimeError("Run as root on an existing Debian desktop image work directory")
    here = pathlib.Path(__file__).resolve().parent
    cache, lock = work / "desktop-app-cache", work / "desktop-apps.lock.json"
    command = [sys.executable, str(here / "desktop-apps.py"), "--lock", str(lock), "--cache", str(cache)]
    if args.use_lock:
        command.append("--use-lock")
    run(*command)
    document = json.loads(lock.read_text())
    old_manifest = root / "usr/share/openhd/desktop-apps.json"
    previous = {app["id"]: app for app in json.loads(old_manifest.read_text())["apps"]} if old_manifest.exists() else {}
    mounts = []
    staging = root / "tmp/openhd-desktop-apps"
    staging.mkdir(exist_ok=True)
    policy = root / "usr/sbin/policy-rc.d"
    policy_original = policy.read_bytes() if policy.exists() else None
    policy_mode = policy.stat().st_mode if policy.exists() else None
    policy.write_text("#!/bin/sh\nexit 101\n")
    policy.chmod(0o755)
    try:
        for source in ("dev", "proc", "sys"):
            target = root / source
            if subprocess.run(["mountpoint", "-q", str(target)]).returncode:
                if source == "proc":
                    run("mount", "-t", "proc", "proc", str(target))
                else:
                    run("mount", "--rbind", "/" + source, str(target))
                    run("mount", "--make-rslave", str(target))
                mounts.append(target)
        (root / "etc/resolv.conf").unlink(missing_ok=True)
        shutil.copyfile("/etc/resolv.conf", root / "etc/resolv.conf")
        debs = []
        for app in document["apps"]:
            if app["format"] != "deb":
                continue
            asset = cache / app["cache_file"]
            arch = subprocess.check_output(["dpkg-deb", "-f", str(asset), "Architecture"], text=True).strip()
            if arch not in ("amd64", "all"):
                raise RuntimeError("Wrong architecture for " + app["id"])
            app["package"] = subprocess.check_output(["dpkg-deb", "-f", str(asset), "Package"], text=True).strip()
            target = staging / (app["id"] + ".deb")
            target.unlink(missing_ok=True)
            try:
                os.link(asset, target)
            except OSError:
                shutil.copyfile(asset, target)
            debs.append("/tmp/openhd-desktop-apps/" + target.name)
        environment = {**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
        run("chroot", str(root), "apt-get", "update", env=environment)
        run("chroot", str(root), "apt-get", "-o", "Dpkg::Options::=--force-confold", "install", "-y", "--no-install-recommends", "dbus", "python3-minimal", "libglib2.0-bin", "qt6-svg-plugins", *debs, env=environment)
        run("chroot", str(root), "usermod", "-a", "-G", "dialout,video,render,input,plugdev,audio", "openhd")
        for app in document["apps"]:
            if app["format"] == "appimage":
                existing = root / "opt/openhd-apps" / app["id"] / "AppRun"
                if existing.exists() and previous.get(app["id"], {}).get("sha256") == app["sha256"]:
                    app["exec"] = previous[app["id"]]["exec"]
                    app["icon"] = previous[app["id"]]["icon"]
                    continue
                image = cache / app["cache_file"]
                image.chmod(0o755)
                with tempfile.TemporaryDirectory(prefix="qgc-extract-", dir=work) as temporary:
                    run(str(image), "--appimage-extract", cwd=temporary, stdout=subprocess.DEVNULL)
                    extracted = pathlib.Path(temporary) / "squashfs-root"
                    if not (extracted / "AppRun").exists():
                        raise RuntimeError("QGroundControl AppImage has no AppRun")
                    # AppImage's extraction runtime creates private directories;
                    # installed applications must be traversable by openhd.
                    for path in (extracted, *extracted.rglob("*")):
                        if path.is_symlink():
                            continue
                        path.chmod(0o755 if path.is_dir() else 0o644 | (path.stat().st_mode & 0o111))
                    target = root / "opt/openhd-apps" / app["id"]
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists():
                        shutil.rmtree(target)
                    shutil.move(str(extracted), target)
                app["exec"] = ["/opt/openhd-apps/" + app["id"] + "/AppRun"]
                app["icon"] = "applications-science"
            else:
                installed = subprocess.check_output(["chroot", str(root), "dpkg-query", "-L", app["package"]], text=True).splitlines()
                candidates = [root / path.lstrip("/") for path in installed if path.endswith(".desktop") and "/applications/" in path]
                candidates.sort()
                desktop = None
                for candidate in candidates:
                    config = configparser.ConfigParser(interpolation=None, strict=False)
                    config.read(candidate)
                    if config.has_section("Desktop Entry") and config.has_option("Desktop Entry", "Exec") and not config.getboolean("Desktop Entry", "NoDisplay", fallback=False) and not config["Desktop Entry"]["Exec"].startswith("/usr/local/sbin/openhd-desktop-app "):
                        desktop = config["Desktop Entry"]
                        break
                if desktop is None:
                    if app["id"] not in previous:
                        raise RuntimeError("No upstream desktop launcher for " + app["id"])
                    app["exec"] = previous[app["id"]]["exec"]
                    app["icon"] = previous[app["id"]]["icon"]
                else:
                    app["exec"] = [part for part in shlex.split(desktop["Exec"]) if part not in ("%U", "%u", "%F", "%f", "%i", "%c", "%k")]
                    app["icon"] = desktop.get("Icon", "applications-science")
            # Stable launchers work across upstream changes to binary names.
            launcher = root / "usr/share/applications" / ("openhd-" + app["id"] + ".desktop")
            launcher.write_text("[Desktop Entry]\nType=Application\nName=" + app["name"] + "\nExec=/usr/local/sbin/openhd-desktop-app " + app["id"] + "\nIcon=" + app["icon"] + "\nCategories=Science;Education;\nTerminal=false\nStartupNotify=true\n")
            # Keep upstream launchers from bypassing the unprivileged launcher.
            if app["format"] == "deb":
                for candidate in candidates:
                    text = candidate.read_text()
                    text = "\n".join("Exec=/usr/local/sbin/openhd-desktop-app " + app["id"] if line.startswith("Exec=") else line for line in text.splitlines() if not line.startswith("NoDisplay=")) + "\n"
                    candidate.write_text(text.replace("[Desktop Entry]\n", "[Desktop Entry]\nNoDisplay=true\n", 1))
        # Keep the launcher model tied to real installed desktop entries. QOpenHD
        # is not one of the separately versioned flight-app downloads.
        qopenhd_entry = root / "usr/share/applications/qopenhd.desktop"
        qopenhd = configparser.ConfigParser(interpolation=None, strict=False)
        qopenhd.read(qopenhd_entry)
        if not qopenhd.has_section("Desktop Entry") or not qopenhd.has_option("Desktop Entry", "Exec"):
            raise RuntimeError("QOpenHD desktop entry is missing its launch command")
        qexec = [part for part in shlex.split(qopenhd["Desktop Entry"]["Exec"]) if part not in ("%U", "%u", "%F", "%f", "%i", "%c", "%k")]
        launcher_names = {"kite-gc": "Kite GCS", "ardudeck": "ArduDeck", "inav-configurator": "INAV", "betaflight": "Betaflight", "qgroundcontrol": "QGroundControl"}
        installed_by_id = {app["id"]: app for app in document["apps"]}
        brand_icons = {
            "qopenhd": "/usr/share/openhd/brand/apps/qopenhd-wordmark.png",
            "ardudeck": "/usr/share/openhd/brand/apps/ardudeck.png",
            "kite-gc": "/usr/share/openhd/brand/apps/kitegc.svg",
            "inav-configurator": "/usr/share/openhd/brand/apps/inav.png",
            "betaflight": "/usr/share/openhd/brand/apps/betaflight.svg",
            "terminal": "/usr/share/openhd/brand/apps/terminal.svg",
        }
        for icon in brand_icons.values():
            relative = icon.lstrip("/")
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(here / "overlay" / relative, destination)
        launcher_apps = [{"id": "qopenhd", "name": "QOpenHD", "exec": qexec, "icon": brand_icons["qopenhd"]}]
        for app_id in ("ardudeck", "kite-gc", "inav-configurator", "betaflight"):
            app = installed_by_id.get(app_id)
            if app:
                launcher_apps.append({"id": app_id, "name": launcher_names[app_id], "exec": ["/usr/local/sbin/openhd-desktop-app", app_id], "icon": brand_icons[app_id]})
        qgc = installed_by_id.get("qgroundcontrol")
        if qgc:
            launcher_apps.append({"id": "qgroundcontrol", "name": launcher_names["qgroundcontrol"], "exec": ["/usr/local/sbin/openhd-desktop-app", "qgroundcontrol"], "icon": qgc["icon"]})
        required_launchers = ["qopenhd", "ardudeck", "kite-gc", "inav-configurator", "betaflight"]
        launcher_ids = [app["id"] for app in launcher_apps]
        if launcher_ids[:len(required_launchers)] != required_launchers or launcher_ids[len(required_launchers):] not in ([], ["qgroundcontrol"]):
            raise RuntimeError("OpenHD launcher catalog mismatch; expected " + repr(required_launchers) + ", generated " + repr(launcher_ids) + "; available app IDs: " + repr(sorted(installed_by_id)))
        launcher_apps.append({
            "id": "terminal",
            "name": "Terminal",
            "icon": brand_icons["terminal"],
            "exec": ["foot", "--config", "/usr/share/openhd/desktop-config/foot/foot.ini"],
            "searchOnly": True,
        })
        manifest = root / "usr/share/openhd/desktop-apps.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
        (manifest.parent / "launcher-apps.json").write_text(json.dumps(launcher_apps, indent=2) + "\n")
        launcher_source = here / "overlay/usr/local/sbin/openhd-desktop-app"
        shutil.copyfile(launcher_source, root / "usr/local/sbin/openhd-desktop-app")
        (root / "usr/local/sbin/openhd-desktop-app").chmod(0o755)
        run("chroot", str(root), "apt-get", "clean")
        with (work / "packages.tsv").open("w") as output:
            run("chroot", str(root), "dpkg-query", "-W", "-f=${Package}\t${Version}\t${Installed-Size}\n", stdout=output)
        shutil.copyfile(manifest, lock)
    finally:
        for target in reversed(mounts):
            run("umount", "-R", str(target))
        if policy_original is None:
            policy.unlink(missing_ok=True)
        else:
            policy.write_bytes(policy_original)
            policy.chmod(policy_mode)
        for path in staging.glob("*.deb"):
            path.unlink()
        (root / "etc/resolv.conf").unlink(missing_ok=True)
        (root / "etc/resolv.conf").symlink_to("/run/NetworkManager/resolv.conf")


if __name__ == "__main__":
    main()
