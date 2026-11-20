#!/usr/bin/env python3
"""Export current tracked sources and initialized submodules, efficiently on Windows."""
import argparse
import hashlib
import io
import json
import pathlib
import subprocess
import tarfile


def git(repo, *args):
    return subprocess.check_output(["git", "-c", "safe.directory=*", "-C", str(repo), *args])


def export_repo(archive, repo, prefix, manifest):
    changes = git(repo, "diff", "--name-only", "--relative", "-z", "HEAD", "--", ".").decode().split("\0")
    modified = {name for name in changes if name}
    manifest[prefix] = {
        "commit": git(repo, "rev-parse", "HEAD").decode().strip(),
        "modified_tracked_files": sorted(modified),
        "tracked_diff_sha256": hashlib.sha256(git(repo, "diff", "--binary", "HEAD", "--", ".")).hexdigest(),
    }
    subtree = git(repo, "rev-parse", "--show-prefix").decode().strip().rstrip("/")
    repository_root = git(repo, "rev-parse", "--show-toplevel").decode().strip()
    tree = "HEAD:" + subtree if subtree else "HEAD"
    # Read Git's packfiles instead of doing tens of thousands of Windows/9P stat calls.
    process = subprocess.Popen(["git", "-c", "safe.directory=*", "-C", repository_root,
                                "archive", "--format=tar", tree], stdout=subprocess.PIPE)
    with tarfile.open(fileobj=process.stdout, mode="r|") as source:
        for member in source:
            if member.name.rstrip("/") in modified:
                continue
            stream = source.extractfile(member) if member.isfile() else None
            member.name = prefix + "/" + member.name
            archive.addfile(member, stream)
    if process.wait():
        raise RuntimeError(f"Cannot archive {repo}")
    records = git(repo, "ls-files", "--stage", "-z").decode().split("\0")
    for record in records:
        if record.startswith("160000 "):
            relative = record.split("\t", 1)[1]
            child = repo / relative
            if (child / ".git").exists():
                export_repo(archive, child, prefix + "/" + relative, manifest)
    for relative in modified:
        source = repo / relative
        if relative and (source.is_file() or source.is_symlink()):
            archive.add(source, arcname=prefix + "/" + relative, recursive=False)


def export(parent, output):
    manifest = {}
    with tarfile.open(output, "w:gz", compresslevel=1, dereference=False) as archive:
        for name in ("OpenHD", "QOpenHD", "OpenHD-SysUtils"):
            export_repo(archive, parent / name, name, manifest)
        repo = parent / "QOpenHD"
        for source in (repo / "app/videostreaming/avcodec/drm_kms").glob("x86_kms.*"):
            archive.add(source, arcname="QOpenHD/" + source.relative_to(repo).as_posix())
            manifest.setdefault("additional_sources", {})[source.relative_to(repo).as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
        data = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
        member = tarfile.TarInfo("source-manifest.json")
        member.size = len(data)
        archive.addfile(member, io.BytesIO(data))
    output.with_suffix(".manifest.json").write_bytes(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_parent", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    export(args.source_parent, args.output)
