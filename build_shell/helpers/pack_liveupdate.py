#!/usr/bin/env python3
"""Splits the bob liveupdate zip into content-versioned archives (liveupdate_pack.py), publishes them into
<target>/<game version> and mirrors them into the bundle resource folders of the project, so the next
bundling pass ships them. Shared by every project; build_helpers.sh passes the values of project.conf."""

import argparse
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from game_project import read_game_version

PACKER = Path(__file__).resolve().parent / "liveupdate_pack.py"
BUNDLE_ARCHIVE_EXTENSION = ".zip"


def unpack_bob_zip(zip_path, dist_path):
    if dist_path.exists():
        shutil.rmtree(dist_path)
    dist_path.mkdir(parents=True)
    with zipfile.ZipFile(zip_path) as zip_file:
        zip_file.extractall(dist_path)


def run_packer(graph_path, dist_path, pack_path):
    if pack_path.exists():
        shutil.rmtree(pack_path)
    subprocess.run(
        [
            sys.executable,
            str(PACKER),
            "--graph",
            str(graph_path),
            "--resources",
            str(dist_path),
            "--output",
            str(pack_path),
        ],
        check=True,
    )


def read_manifest(manifest_path):
    if not manifest_path.exists():
        return {"files": {}}
    with manifest_path.open("r", encoding="utf-8") as manifest_file:
        return json.load(manifest_file)


def read_baseline_manifest(target_root, game_version):
    """The manifest the client of this game version currently sees: the one already published in
    its folder, or the one of the newest older game version when this folder is published for the
    first time. Archive names and versions are content derived, so the folder a client downloads
    from does not change what it has to download."""
    current_manifest_path = target_root / str(game_version) / "manifest.json"
    if current_manifest_path.exists():
        return read_manifest(current_manifest_path)
    if not target_root.exists():
        return read_manifest(current_manifest_path)
    previous_versions = [
        int(entry.name)
        for entry in target_root.iterdir()
        if entry.is_dir() and entry.name.isdigit() and int(entry.name) < game_version
        and (entry / "manifest.json").exists()
    ]
    if not previous_versions:
        return read_manifest(target_root / "manifest.json")
    return read_manifest(target_root / str(max(previous_versions)) / "manifest.json")


def archive_file_name(archive_name, version):
    return f"{archive_name}_{version}.arcd0"


def bundle_archive_file_name(archive_name, version):
    return f"{archive_name}_{version}{BUNDLE_ARCHIVE_EXTENSION}"


def clear_bundle_resources(project_root, bundle_resource_dirs):
    for relative_dir in bundle_resource_dirs:
        target_dir = project_root / relative_dir
        if target_dir.exists():
            shutil.rmtree(target_dir)


def sync_bundle_resources(project_root, bundle_resource_dirs, pack_path, new_manifest):
    """Mirrors the packed archives into the bundle resource folders so that a freshly installed
    package already carries them and only downloads what the server manifest changed afterwards."""
    wanted = {
        bundle_archive_file_name(archive_name, entry[0]): archive_file_name(archive_name, entry[0])
        for archive_name, entry in new_manifest["files"].items()
    }
    for relative_dir in bundle_resource_dirs:
        target_dir = project_root / relative_dir
        target_dir.mkdir(parents=True, exist_ok=True)
        for existing in target_dir.iterdir():
            if existing.name not in wanted:
                existing.unlink()
        for bundle_name, pack_name in wanted.items():
            target = target_dir / bundle_name
            if not target.exists():
                shutil.copy2(pack_path / pack_name, target)
    return len(wanted)


def publish(pack_path, target_path, new_manifest, published_manifest):
    target_path.mkdir(parents=True, exist_ok=True)
    changed = []
    for archive_name, entry in sorted(new_manifest["files"].items()):
        if published_manifest["files"].get(archive_name, [None])[0] != entry[0]:
            changed.append(archive_name)
        file_name = archive_file_name(archive_name, entry[0])
        if not (target_path / file_name).exists():
            shutil.copy2(pack_path / file_name, target_path / file_name)
    for index_name in ("archive_sizes.json", "manifest.json"):
        shutil.copy2(pack_path / index_name, target_path / index_name)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", help="liveupdate.zip produced by bob")
    parser.add_argument("--target", help="liveupdate folder of the CDN content; archives are published into its <game_version> subfolder")
    parser.add_argument("--bundle-resource-dir", action="append", default=[], help="bundle resource folder the archives are mirrored into, relative to the project root")
    parser.add_argument("--game-version-file", help="file that holds the game version, relative to the project root")
    parser.add_argument("--game-version-pattern", help="regular expression whose first group is the game version")
    parser.add_argument("--graph", default="build/default/game.graph.json")
    parser.add_argument("--work-dir", default="build/liveupdate")
    parser.add_argument(
        "--clear-bundle-resources",
        action="store_true",
        help="empty the bundle resource folders and exit, so the first bundling pass does not package stale archives",
    )
    args = parser.parse_args()

    project_root = Path.cwd()
    if args.clear_bundle_resources:
        clear_bundle_resources(project_root, args.bundle_resource_dir)
        return

    game_version = read_game_version(project_root / args.game_version_file, args.game_version_pattern)
    work_path = Path(args.work_dir).resolve()
    dist_path = work_path / "dist"
    pack_path = work_path / "pack"
    target_root = Path(args.target).resolve()
    target_path = target_root / str(game_version)

    unpack_bob_zip(Path(args.zip).resolve(), dist_path)
    run_packer(Path(args.graph).resolve(), dist_path, pack_path)
    shutil.rmtree(dist_path)

    new_manifest = read_manifest(pack_path / "manifest.json")
    published_manifest = read_baseline_manifest(target_root, game_version)
    changed = publish(pack_path, target_path, new_manifest, published_manifest)
    bundled = sync_bundle_resources(project_root, args.bundle_resource_dir, pack_path, new_manifest)

    with (pack_path / "archive_sizes.json").open("r", encoding="utf-8") as sizes_file:
        sizes = json.load(sizes_file)["files"]
    total_bytes = sum(sizes.values())
    changed_bytes = sum(sizes[name] for name in changed)

    print(f"LIVEUPDATE_GAME_VERSION={game_version}")
    print(f"LIVEUPDATE_MANIFEST_VERSION={new_manifest['version']}")
    print(f"LIVEUPDATE_ARCHIVES_TOTAL={len(new_manifest['files'])}")
    print(f"LIVEUPDATE_ARCHIVES_CHANGED={len(changed)}")
    print(f"LIVEUPDATE_ARCHIVES_BUNDLED={bundled}")
    print(f"LIVEUPDATE_TOTAL_MB={total_bytes / 1048576:.1f}")
    print(f"LIVEUPDATE_CHANGED_MB={changed_bytes / 1048576:.1f}")
    for archive_name in changed:
        print(f"Changed archive: {archive_name}")


if __name__ == "__main__":
    main()
