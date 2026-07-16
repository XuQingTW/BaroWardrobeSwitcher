#!/usr/bin/env python3
"""Source-only package and metadata verification for BaroWardrobeSwitcher."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
EXPECTED_METADATA = {
    "modVersion": "0.5.0",
    "protocolVersion": 2,
    "persistenceVersion": 2,
    "barotraumaGameVersion": "1.13.4.0",
    "barotraumaSourceCommit": "a589d2cee3ff2214c99a7ea30c46f16a5406a01d",
    "luaCsCommit": "0d380afcd1feeb842c0c86290d46bcaf198cd5e4",
}
EXPECTED_CANDIDATE_DECLARED_VERSION = "1.12.7.0"


def fail(message: str) -> None:
    ERRORS.append(message)


def mod_path(raw: str) -> Path:
    return ROOT / raw.replace("%ModDir%/", "").replace("%ModDir%\\", "")


def parse_xml(path: Path) -> ET.Element:
    try:
        return ET.parse(path).getroot()
    except (ET.ParseError, OSError) as exc:
        fail(f"Invalid XML {path.relative_to(ROOT)}: {exc}")
        return ET.Element("invalid")


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, check=True, text=True, capture_output=True
    )
    return [line.replace("\\", "/") for line in result.stdout.splitlines()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--release",
        action="store_true",
        help="require the in-game compatibility matrix to be marked verified",
    )
    args = parser.parse_args()

    version = json.loads((ROOT / "version.json").read_text(encoding="utf-8"))
    for key, expected in EXPECTED_METADATA.items():
        if version.get(key) != expected:
            fail(f"version.json {key} must be {expected!r}")
    filelist_root = parse_xml(ROOT / "filelist.xml")
    modconfig_root = parse_xml(ROOT / "ModConfig.xml")
    parse_xml(ROOT / "Texts.xml")
    parse_xml(ROOT / "MultiplayerSyncMarker.xml")

    if filelist_root.attrib.get("modversion") != version["modVersion"]:
        fail("filelist.xml modversion does not match version.json")
    declared_game_version = version.get("declaredGameVersion")
    target_game_version = version.get("barotraumaGameVersion")
    compatibility_status = version.get("compatibilityStatus")
    if filelist_root.attrib.get("gameversion") != declared_game_version:
        fail("filelist.xml gameversion does not match version.json declaredGameVersion")
    if compatibility_status not in {"release-candidate", "verified"}:
        fail("version.json compatibilityStatus must be release-candidate or verified")
    if compatibility_status == "verified" and declared_game_version != target_game_version:
        fail("verified compatibility must declare the tested target game version")
    if compatibility_status == "release-candidate" and declared_game_version != EXPECTED_CANDIDATE_DECLARED_VERSION:
        fail(
            "release-candidate must retain the previously declared game version "
            f"{EXPECTED_CANDIDATE_DECLARED_VERSION}"
        )
    if args.release and compatibility_status != "verified":
        fail("release verification requires the in-game matrix to be marked verified")

    csproj = (ROOT / "CSharp" / "BaroWardrobeSwitcher.csproj").read_text(encoding="utf-8")
    match = re.search(r"<Version>([^<]+)</Version>", csproj)
    if match is None or match.group(1) != version["modVersion"]:
        fail("C# Version does not match version.json")

    client_plugin = (ROOT / "CSharp" / "Client" / "WardrobeVisualOverridePlugin.cs").read_text(encoding="utf-8")
    persistence_match = re.search(r"private const int PersistenceVersion\s*=\s*(\d+)\s*;", client_plugin)
    plugin_version_match = re.search(r'public const string Version\s*=\s*"([^"]+)"\s*;', client_plugin)
    if persistence_match is None or int(persistence_match.group(1)) != version["persistenceVersion"]:
        fail("C# WardrobePersistence version does not match version.json")
    if plugin_version_match is None or plugin_version_match.group(1) != version["modVersion"]:
        fail("C# WardrobePluginInfo version does not match version.json")

    listed: set[str] = set()
    for element in filelist_root:
        raw = element.attrib.get("file")
        if not raw:
            continue
        path = mod_path(raw)
        relative = path.relative_to(ROOT).as_posix()
        listed.add(relative.casefold())
        if not path.is_file():
            fail(f"filelist.xml references missing file: {relative}")
        if path.suffix.casefold() in {".dll", ".pdb"} or path.name.casefold().endswith(".deps.json"):
            fail(f"Binary build output must not be packaged: {relative}")

    for element in modconfig_root:
        raw = element.attrib.get("File") or element.attrib.get("Folder")
        if raw and not mod_path(raw).exists():
            fail(f"ModConfig.xml references missing path: {raw}")

    runtime_sources = list((ROOT / "CSharp" / "Client").rglob("*.cs"))
    runtime_sources += [
        path
        for path in (ROOT / "Lua").rglob("*.lua")
        if "Tests" not in path.relative_to(ROOT / "Lua").parts
    ]
    for path in runtime_sources:
        relative = path.relative_to(ROOT).as_posix()
        if relative.casefold() not in listed:
            fail(f"Runtime source is not in filelist.xml: {relative}")

    forbidden_parts = {"bin", "obj", "artifacts", "testresults"}
    all_tracked = tracked_files()
    existing_tracked = [tracked for tracked in all_tracked if (ROOT / tracked).exists()]
    pending_tracked_deletions = [tracked for tracked in all_tracked if not (ROOT / tracked).exists()]
    for tracked in all_tracked:
        if tracked not in existing_tracked:
            continue
        parts = {part.casefold() for part in Path(tracked).parts}
        generated_or_disabled = any(
            part in forbidden_parts
            or part.startswith("bin.")
            or part.startswith("obj.")
            or ".disabled" in part
            for part in parts
        )
        if generated_or_disabled:
            fail(f"Generated artifact is tracked: {tracked}")
        if Path(tracked).name.casefold() == "runconfig.xml":
            fail(f"Obsolete RunConfig.xml is tracked: {tracked}")

    core_path = ROOT / "Lua" / "WardrobeCore.lua"
    if core_path.exists():
        core = core_path.read_text(encoding="utf-8")
        protocol = re.search(r"PROTOCOL_VERSION\s*=\s*(\d+)\b", core)
        schema = re.search(r"(?:SCHEMA|LOOK_SCHEMA)_VERSION\s*=\s*(\d+)\b", core)
        persistence = re.search(r"PERSISTENCE_VERSION\s*=\s*(\d+)\b", core)
        mod_version = re.search(r'MOD_VERSION\s*=\s*"([^"]+)"', core)
        if protocol is None or int(protocol.group(1)) != version["protocolVersion"]:
            fail("WardrobeCore.lua protocol version does not match version.json")
        if schema is None or int(schema.group(1)) != version["persistenceVersion"]:
            fail("WardrobeCore.lua look schema version does not match version.json")
        if persistence is None or int(persistence.group(1)) != version["persistenceVersion"]:
            fail("WardrobeCore.lua persistence version does not match version.json")
        if mod_version is None or mod_version.group(1) != version["modVersion"]:
            fail("WardrobeCore.lua mod version does not match version.json")

    if ERRORS:
        for error in ERRORS:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(
        "Package verification passed "
        f"({len(existing_tracked)} present tracked files, "
        f"{len(pending_tracked_deletions)} pending tracked deletions, "
        f"compatibility={compatibility_status}, target={target_game_version}, "
        f"declared={declared_game_version})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
