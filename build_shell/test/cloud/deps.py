#!/usr/bin/env python3
"""deps.py - fills the bob library cache (.internal/lib) of a checkout in a cloud session.

    build_shell/test/cloud/deps.py [<checkout root>]

The cloud GitHub proxy refuses archive downloads of repositories that are not attached to the session
(github.com/<owner>/<repo>/archive/...zip answers 403), while `git clone` of a public repository works.
So every dependency of game.project on GitHub is cloned (cached in ~/.cache/defold_cloud_deps) and packed
with `git archive` into the file bob itself would have written: <sha1 of the url>-<base64url etag>.zip.
Other dependency URLs are downloaded with curl. bob then builds without `resolve`
(build_shell/test/cloud/instance.sh sets TEST_RESOLVE=0). Python 3.9+, standard library only.
Shared by every Defold project and synced by sync_defold_docs.py.
"""

import base64
import configparser
import hashlib
import re
import subprocess
import sys
from pathlib import Path

CACHE = Path.home() / ".cache" / "defold_cloud_deps"
GITHUB_ARCHIVE = re.compile(r"^https://github\.com/([^/]+)/([^/]+)/archive/(?:refs/(?:tags|heads)/)?(.+)\.zip$")


def dependency_urls(root):
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(root / "game.project")
    project = config["project"]
    keys = sorted((key for key in project if key.startswith("dependencies#")), key=lambda key: int(key.split("#")[1]))
    return [project[key].strip() for key in keys if project[key].strip()]


def archive_name(url, etag):
    digest = hashlib.sha1(url.encode()).hexdigest()
    return digest, f"{digest}-{base64.urlsafe_b64encode(etag.encode()).decode()}.zip"


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def github_zip(owner, repo, ref, target_dir, url):
    clone = CACHE / owner / repo / ref
    if not (clone / ".git").exists():
        clone.parent.mkdir(parents=True, exist_ok=True)
        git("clone", "--quiet", "--depth", "1", "--branch", ref, f"https://github.com/{owner}/{repo}.git", str(clone))
    commit = git("rev-parse", "HEAD", cwd=clone)
    digest, name = archive_name(url, f"git-{commit}")
    write(target_dir, digest, name, ["git", "-C", str(clone), "archive", "--format=zip", f"--prefix={repo}-{ref}/", "HEAD"])
    return name


def plain_zip(target_dir, url):
    digest, name = archive_name(url, "curl")
    write(target_dir, digest, name, ["curl", "-fsSL", url])
    return name


def write(target_dir, digest, name, command):
    target = target_dir / name
    if target.exists():
        return
    for old in target_dir.glob(f"{digest}-*.zip"):
        old.unlink()
    with open(target, "wb") as out:
        subprocess.run(command, check=True, stdout=out)


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]).resolve()
    target_dir = root / ".internal" / "lib"
    target_dir.mkdir(parents=True, exist_ok=True)
    for url in dependency_urls(root):
        match = GITHUB_ARCHIVE.match(url)
        name = github_zip(*match.groups(), target_dir, url) if match else plain_zip(target_dir, url)
        print(f"DEP {url} -> .internal/lib/{name}")


main()
