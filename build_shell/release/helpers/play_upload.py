#!/usr/bin/env python3
"""Uploads a release bundle to Google Play through the Android Publisher API, the same API the
project already drives its store listings with, and leaves the release in the requested track."""

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import jwt
import requests

PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "build_shell" / "helpers"))

from game_project import load_config, read_value

API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
UPLOAD_API = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
UPLOAD_TIMEOUT = 1800
CALL_TIMEOUT = 120
RETRY_STATUS = (429, 500, 502, 503, 504)


class PlayError(RuntimeError):
    pass


class Play:
    def __init__(self, service_account_path, package_name):
        self.service_account = json.loads(Path(service_account_path).read_text(encoding="utf-8"))
        self.package_name = package_name
        self.token = None
        self.token_expires = 0.0

    # A bundle upload outlives the hour a Google access token is good for, so it is minted again
    # instead of being cached for the life of the process.
    def access_token(self):
        if self.token and time.time() < self.token_expires:
            return self.token
        now = int(time.time())
        assertion = jwt.encode(
            {
                "iss": self.service_account["client_email"],
                "scope": SCOPE,
                "aud": self.service_account["token_uri"],
                "iat": now,
                "exp": now + 3600,
            },
            self.service_account["private_key"],
            algorithm="RS256",
        )
        response = requests.post(
            self.service_account["token_uri"],
            data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            },
            timeout=CALL_TIMEOUT,
        )
        response.raise_for_status()
        payload = response.json()
        self.token = payload["access_token"]
        self.token_expires = time.time() + payload["expires_in"] - 300
        return self.token

    def request(self, method, url, attempts, **kwargs):
        headers = {"Authorization": "Bearer " + self.access_token()}
        headers.update(kwargs.pop("headers", {}))
        for attempt in range(attempts):
            try:
                response = requests.request(method, url, headers=headers, **kwargs)
            except (requests.ConnectionError, requests.Timeout):
                if attempt == attempts - 1:
                    raise
                time.sleep(2**attempt)
                continue
            if response.status_code < 400:
                return response.json() if response.text else {}
            if response.status_code in RETRY_STATUS and attempt < attempts - 1:
                time.sleep(2**attempt)
                continue
            raise PlayError(f"{method} {url} -> {response.status_code}\n{response.text}")

    def call(self, method, path, body=None):
        return self.request(
            method,
            f"{API}/applications/{self.package_name}{path}",
            attempts=5,
            json=body,
            timeout=CALL_TIMEOUT,
            headers={"Content-Type": "application/json"},
        )

    def upload(self, path, file_path):
        return self.request(
            "POST",
            f"{UPLOAD_API}/applications/{self.package_name}{path}",
            attempts=4,
            data=Path(file_path).read_bytes(),
            params={"uploadType": "media"},
            timeout=UPLOAD_TIMEOUT,
            headers={"Content-Type": "application/octet-stream"},
        )


class Edit:
    def __init__(self, play):
        self.play = play

    def __enter__(self):
        self.id = self.play.call("POST", "/edits", body={})["id"]
        self.committed = False
        return self

    def __exit__(self, exception_type, *_):
        if not self.committed:
            self.play.call("DELETE", self.path())
        return False

    def path(self, sub=""):
        return f"/edits/{self.id}{sub}"

    def commit(self):
        result = self.play.call("POST", self.path(":commit"))
        self.committed = True
        return result


def read_project_values():
    config = load_config(PROJECT_ROOT / "game.project")
    return (
        read_value(config, "android", "package"),
        int(read_value(config, "android", "version_code")),
        read_value(config, "project", "version"),
    )


def sha256_of(file_path):
    digest = hashlib.sha256()
    with open(file_path, "rb") as payload:
        for chunk in iter(lambda: payload.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def upload_bundle(play, edit, aab_path, expected_version_code):
    """Play refuses a version code it already holds, so a re-run of a release reuses the bundle that
    is already there — but only after proving it is the very same file."""
    published = {
        int(bundle["versionCode"]): bundle["sha256"]
        for bundle in play.call("GET", edit.path("/bundles")).get("bundles", [])
    }
    digest = sha256_of(aab_path)
    if expected_version_code in published:
        if published[expected_version_code] != digest:
            raise PlayError(
                f"Play already holds versionCode {expected_version_code} with a different bundle "
                f"({published[expected_version_code]} against {digest}); bump android.version_code"
            )
        print(f"versionCode {expected_version_code} is already uploaded as this exact bundle, reusing it")
        return expected_version_code

    bundle = play.upload(edit.path("/bundles"), aab_path)
    version_code = int(bundle["versionCode"])
    print(f"uploaded {Path(aab_path).name}: versionCode {version_code}, sha256 {bundle['sha256']}")
    if version_code != expected_version_code:
        raise PlayError(
            f"the bundle carries versionCode {version_code}, game.project says {expected_version_code}"
        )
    if bundle["sha256"] != digest:
        raise PlayError(f"Play stored sha256 {bundle['sha256']}, the file is {digest}")
    return version_code


def carried_release_notes(replaced, release):
    """Play keeps only what the PUT carries, and release notes are written by hand in the console or
    pushed by the store toolkit rather than by this script, so the ones on the release being replaced
    are carried over: the same version code first, then the draft this release cycle was written for."""
    with_notes = [other for other in replaced if other.get("releaseNotes")]
    same_version = [other for other in with_notes if other.get("versionCodes") == release["versionCodes"]]
    drafts = [other for other in with_notes if other.get("status") == "draft"]
    for candidates in (same_version, drafts, with_notes):
        if candidates:
            return candidates[0]
    return None


def merge_releases(existing, release):
    """Replaces the release of this status instead of adding one next to it: a track holds one draft
    at a time, and a second release of the same status is not what a repeated upload should produce.
    Releases of every other status — the live one, a staged rollout — are carried over untouched."""
    kept = []
    replaced = []
    for other in existing:
        if other.get("status") in ("draft", release["status"]):
            replaced.append(other)
            print(f"replacing {other.get('status')} release {other.get('name')}")
            continue
        kept.append(other)

    source = carried_release_notes(replaced, release)
    if source:
        release = {**release, "releaseNotes": source["releaseNotes"]}
        print(f"keeping the release notes of {source['name']} ({len(source['releaseNotes'])} locales)")
    return kept + [release]


def track_releases(play, edit, track, release):
    existing = play.call("GET", edit.path(f"/tracks/{track}")).get("releases", [])
    return merge_releases(existing, release)


def publish(play, args, expected_version_code, project_version):
    with Edit(play) as edit:
        version_code = upload_bundle(play, edit, args.aab, expected_version_code)

        if args.symbols:
            # Play documents this endpoint for apks only. It takes a bundle version code in
            # practice, and symbols are never worth failing a release over.
            try:
                play.upload(
                    edit.path(f"/apks/{version_code}/deobfuscationFiles/nativeCode"), args.symbols
                )
                print(f"uploaded {Path(args.symbols).name}")
            except PlayError as error:
                print(f"native symbols were rejected, continuing without them:\n{error}")

        release = {
            "name": f"{version_code} ({project_version})",
            "versionCodes": [str(version_code)],
            "status": args.status,
        }
        play.call(
            "PUT",
            edit.path(f"/tracks/{args.track}"),
            body={"track": args.track, "releases": track_releases(play, edit, args.track, release)},
        )
        edit.commit()
        print(f"committed edit {edit.id}: {args.track} track, release {release['name']} as {args.status}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aab", required=True)
    parser.add_argument("--symbols", default="")
    parser.add_argument(
        "--service-account", default=os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE", "")
    )
    parser.add_argument("--track", default="production")
    parser.add_argument("--status", default="draft", choices=("draft", "completed"))
    args = parser.parse_args()

    if not args.service_account:
        raise SystemExit("pass --service-account or set GOOGLE_PLAY_SERVICE_ACCOUNT_FILE")

    package_name, expected_version_code, project_version = read_project_values()
    play = Play(args.service_account, package_name)
    try:
        publish(play, args, expected_version_code, project_version)
    except PlayError as error:
        raise SystemExit(str(error))


if __name__ == "__main__":
    main()
