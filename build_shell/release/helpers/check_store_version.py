#!/usr/bin/env python3
"""Refuses to start a release build whose version the store already holds. Both stores reject a
version they have seen, but only at the upload — twenty minutes of build time after the point it
was knowable."""

import argparse
import os
import sys
import time
from pathlib import Path

import jwt
import requests

PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(PROJECT_ROOT / "build_shell" / "helpers"))

from play_upload import Edit, Play
from game_project import load_config, read_value

APPSTORE_API = "https://api.appstoreconnect.apple.com"
CALL_TIMEOUT = 60


class AppStore:
    """App Store Connect caps a JWT at twenty minutes; a single check never outlives one."""

    def __init__(self, key_id, issuer_id, private_key):
        now = int(time.time())
        self.token = jwt.encode(
            {"iss": issuer_id, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
            private_key,
            algorithm="ES256",
            headers={"kid": key_id, "typ": "JWT"},
        )

    def get(self, path, **params):
        response = requests.get(
            APPSTORE_API + path,
            headers={"Authorization": f"Bearer {self.token}"},
            params=params,
            timeout=CALL_TIMEOUT,
        )
        if response.status_code >= 400:
            raise SystemExit(f"GET {path} -> {response.status_code}\n{response.text}")
        return response.json()


def check_android(config):
    version_code = int(read_value(config, "android", "version_code"))
    play = Play(
        os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_FILE"], read_value(config, "android", "package")
    )
    with Edit(play) as edit:
        published = [int(bundle["versionCode"]) for bundle in play.call("GET", edit.path("/bundles")).get("bundles", [])]
    if version_code in published:
        raise SystemExit(
            f"Google Play already holds versionCode {version_code}; bump android.version_code, "
            f"or release the other platform alone"
        )
    print(f"android.version_code {version_code} is free (Play holds {sorted(published)})")


def check_ios(config):
    bundle_version = read_value(config, "ios", "bundle_version")
    store = AppStore(
        os.environ["APPSTORE_API_KEY_ID"],
        os.environ["APPSTORE_API_ISSUER_ID"],
        os.environ["APPSTORE_API_PRIVATE_KEY"],
    )
    app_id = store.get("/v1/apps", **{"filter[bundleId]": read_value(config, "ios", "bundle_identifier")})["data"][0]["id"]
    builds = store.get(
        "/v1/builds",
        **{"filter[app]": app_id, "limit": "200", "sort": "-version", "fields[builds]": "version"},
    )["data"]
    versions = [build["attributes"]["version"] for build in builds]
    if bundle_version in versions:
        raise SystemExit(
            f"App Store Connect already holds build {bundle_version}; bump ios.bundle_version, "
            f"or release the other platform alone"
        )
    highest = max((int(version) for version in versions if version.isdigit()), default=0)
    if int(bundle_version) <= highest:
        raise SystemExit(
            f"App Store Connect requires a build higher than {highest}, ios.bundle_version is {bundle_version}"
        )
    print(f"ios.bundle_version {bundle_version} is free (the highest build is {highest})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=("android", "ios"))
    args = parser.parse_args()

    config = load_config(PROJECT_ROOT / "game.project")
    if args.platform == "android":
        check_android(config)
    else:
        check_ios(config)


if __name__ == "__main__":
    main()
