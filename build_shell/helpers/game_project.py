#!/usr/bin/env python3
"""Reads and bumps values of game.project for the build scripts.

usage: game_project.py get <section.key> [default]   (default: the value bob uses when game.project has none)
       game_project.py bump   (android.version_code, ios.bundle_version, the last number of project.version)
       game_project.py bump-game-version <file> <pattern>   (the number the first group of <pattern> matches in <file>)
"""
from __future__ import annotations

import configparser
import re
import sys
from pathlib import Path

PROJECT_FILE = Path(__file__).resolve().parents[2] / "game.project"


def load_config(project_file: Path = PROJECT_FILE) -> configparser.ConfigParser:
    config = configparser.ConfigParser(
        interpolation=None,
        delimiters=("=",),
        comment_prefixes=(),
        inline_comment_prefixes=(),
        strict=False,
    )
    with project_file.open("r", encoding="utf-8") as handle:
        config.read_file(handle)
    return config


def read_value(config: configparser.ConfigParser, section: str, key: str, default: str | None = None) -> str:
    sections = {name.lower(): name for name in config.sections()}
    options = {name.lower(): name for name in config.options(sections[section.lower()])} if section.lower() in sections else {}
    if key.lower() not in options and default is not None:
        return default
    return config.get(sections[section.lower()], options[key.lower()], raw=True).strip()


def bump_last_number(version: str) -> str:
    parts = version.split(".")
    parts[-1] = str(int(parts[-1]) + 1)
    return ".".join(parts)


def update_values(text: str, updates: dict[tuple[str, str], str]) -> str:
    lines = text.splitlines()
    section = ""
    updated = set()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1].strip().lower()
            continue
        for (target_section, key), value in updates.items():
            if section == target_section and re.match(rf"{re.escape(key)}\s*=", stripped, flags=re.IGNORECASE):
                lines[index] = f"{key} = {value}"
                updated.add((target_section, key))
    missing = set(updates) - updated
    if missing:
        raise SystemExit(f"error: game.project has no {', '.join(f'{s}.{k}' for s, k in sorted(missing))}")
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def read_game_version(path: Path, pattern: str) -> int:
    match = re.search(pattern, path.read_text(encoding="utf-8"))
    if not match:
        raise SystemExit(f"error: {pattern} not found in {path}")
    return int(match.group(1))


def bump_game_version(path: Path, pattern: str) -> None:
    text = path.read_text(encoding="utf-8")
    match = re.search(pattern, text)
    if not match:
        raise SystemExit(f"error: {pattern} not found in {path}")
    version = int(match.group(1))
    path.write_text(text[: match.start(1)] + str(version + 1) + text[match.end(1) :], encoding="utf-8")
    print(f"{path.name} game version: {version} -> {version + 1}")


def bump() -> None:
    config = load_config()
    current = {
        ("android", "version_code"): read_value(config, "android", "version_code"),
        ("ios", "bundle_version"): read_value(config, "ios", "bundle_version"),
        ("project", "version"): read_value(config, "project", "version"),
    }
    bumped = {
        ("android", "version_code"): str(int(current[("android", "version_code")]) + 1),
        ("ios", "bundle_version"): str(int(current[("ios", "bundle_version")]) + 1),
        ("project", "version"): bump_last_number(current[("project", "version")]),
    }
    PROJECT_FILE.write_text(update_values(PROJECT_FILE.read_text(encoding="utf-8"), bumped), encoding="utf-8")
    for (section, key), value in bumped.items():
        print(f"{section}.{key}: {current[(section, key)]} -> {value}")


def main() -> None:
    if sys.argv[1:2] == ["get"] and len(sys.argv) in (3, 4):
        section, key = sys.argv[2].split(".", 1)
        print(read_value(load_config(), section, key, sys.argv[3] if len(sys.argv) == 4 else None))
    elif sys.argv[1:] == ["bump"]:
        bump()
    elif sys.argv[1:2] == ["bump-game-version"] and len(sys.argv) == 4:
        bump_game_version(PROJECT_FILE.parent / sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
