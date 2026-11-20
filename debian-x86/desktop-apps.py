#!/usr/bin/env python3
"""Resolve current upstream stable Linux releases, download and verify their assets.

Builds resolve once into a lock: downstream steps never query 'latest' again.
An explicit lock supports exact rebuilds. Cache entries are content addressed.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import time
import urllib.error
import urllib.request


def request(url, api=False):
    headers = {"User-Agent": "OpenHD-OS-desktop-image-builder"}
    if api:
        headers["Accept"] = "application/vnd.github+json"
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        if token:
            headers["Authorization"] = "Bearer " + token
    return urllib.request.Request(url, headers=headers)


def resolve(catalog):
    apps = []
    for spec in catalog:
        with urllib.request.urlopen(request("https://api.github.com/repos/" + spec["repo"] + "/releases/latest", True), timeout=60) as response:
            release = json.load(response)
        if release.get("draft") or release.get("prerelease"):
            raise RuntimeError("Expected a published stable release for " + spec["id"])
        matches = [asset for asset in release["assets"] if re.fullmatch(spec["asset"], asset["name"])]
        if len(matches) != 1:
            raise RuntimeError(f"Expected one amd64 asset for {spec['id']}; found {len(matches)}. Update the selector explicitly.")
        asset = matches[0]
        url = asset["browser_download_url"]
        prefix = "https://github.com/" + spec["repo"] + "/releases/download/"
        if not url.startswith(prefix):
            raise RuntimeError("Unexpected release download location: " + url)
        apps.append({**spec, "version": release["tag_name"], "release_url": release["html_url"],
                     "asset_name": asset["name"], "url": url, "size": asset["size"],
                     "upstream_digest": asset.get("digest")})
    return {"schema": 1, "channel": "latest-stable", "apps": apps}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(app, cache):
    upstream = app.get("upstream_digest")
    if upstream and not re.fullmatch(r"sha256:[a-f0-9]{64}", upstream):
        raise RuntimeError("Unsupported release digest for " + app["id"])
    expected = app.get("sha256") or (upstream.removeprefix("sha256:") if upstream else None)
    key = expected or hashlib.sha256(app["url"].encode()).hexdigest()
    suffix = ".deb" if app["format"] == "deb" else ".AppImage"
    target = cache / (key + suffix)
    if target.exists() and target.stat().st_size == app["size"]:
        digest = sha256(target)
        if not expected or digest == expected:
            app["sha256"] = digest
            app["cache_file"] = target.name
            return
    temporary = target.with_suffix(suffix + ".partial")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request(app["url"]), timeout=120) as response, temporary.open("wb") as output:
                while block := response.read(1024 * 1024):
                    output.write(block)
            if temporary.stat().st_size != app["size"]:
                raise RuntimeError("Incomplete download for " + app["id"])
            digest = sha256(temporary)
            if expected and digest != expected:
                raise RuntimeError("Checksum mismatch for " + app["id"])
            temporary.replace(target)
            app["sha256"] = digest
            app["cache_file"] = target.name
            print(f"Downloaded {app['name']} {app['version']} ({app['size']} bytes)", flush=True)
            return
        except (OSError, urllib.error.URLError, RuntimeError):
            temporary.unlink(missing_ok=True)
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=pathlib.Path, default=pathlib.Path(__file__).with_name("desktop-apps.json"))
    parser.add_argument("--lock", type=pathlib.Path, required=True)
    parser.add_argument("--use-lock", action="store_true")
    parser.add_argument("--cache", type=pathlib.Path)
    args = parser.parse_args()
    document = json.loads(args.lock.read_text()) if args.use_lock else resolve(json.loads(args.catalog.read_text()))
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)
        for app in document["apps"]:
            download(app, args.cache)
    args.lock.parent.mkdir(parents=True, exist_ok=True)
    args.lock.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
    for app in document["apps"]:
        print(f"{app['name']}: {app['version']} / {app['asset_name']}")


if __name__ == "__main__":
    main()
