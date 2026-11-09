#!/usr/bin/env python3
"""Install and verify one open-format agent setup through declared adapters."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SKILLS_ROOT = ROOT / "skills"
AGENTS_ROOT = ROOT / "agents"
CATALOG_PATH = ROOT / "catalog.json"
ADAPTERS_PATH = ROOT / "adapters.json"
INSTRUCTIONS_PATH = ROOT / "AGENTS.md"
BACKUPS_ROOT = Path(
    os.environ.get("AGENT_SETUP_BACKUPS_ROOT", ROOT / "backups")
).expanduser()
ADAPTER_PREFIX = os.environ.get("AGENT_SETUP_ADAPTER_PREFIX")


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def selected_names() -> list[str]:
    return [entry["name"] for entry in load_json(CATALOG_PATH)["skills"]]


def agent_names() -> list[str]:
    if not AGENTS_ROOT.is_dir():
        return []
    return sorted(path.name for path in AGENTS_ROOT.glob("*.md"))


def adapters() -> list[dict[str, Any]]:
    loaded = load_json(ADAPTERS_PATH)
    return loaded["adapters"]


def adapter_path(adapter: dict[str, Any], key: str) -> Path:
    resolved = Path(adapter[key]).expanduser()
    if ADAPTER_PREFIX:
        return Path(ADAPTER_PREFIX) / resolved.as_posix().lstrip("/")
    return resolved


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def copy_path(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        destination.symlink_to(os.readlink(source))
    elif source.is_file():
        shutil.copy2(source, destination)
    else:
        shutil.copytree(source, destination, symlinks=True)


def tree_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(relative)
        digest.update(b"\0")
        if path.is_symlink():
            digest.update(b"L\0")
            digest.update(os.readlink(path).encode())
        elif path.is_file():
            digest.update(b"F\0")
            with path.open("rb") as handle:
                for block in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(block)
        elif path.is_dir():
            digest.update(b"D\0")
    return digest.hexdigest()


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def validate_skill(skill_dir: Path) -> list[str]:
    skill_file = skill_dir / "SKILL.md"
    if not skill_file.is_file():
        return ["missing SKILL.md"]

    lines = skill_file.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        return ["SKILL.md does not start with YAML frontmatter"]
    try:
        closing = lines.index("---", 1)
    except ValueError:
        return ["SKILL.md frontmatter has no closing delimiter"]

    values: dict[str, str] = {}
    for line in lines[1:closing]:
        match = re.match(r"^([a-zA-Z0-9_-]+):\s*(.*)$", line)
        if match:
            key, value = match.groups()
            values[key] = value.strip().strip("'\"")

    errors: list[str] = []
    name = values.get("name", "")
    description = values.get("description", "")
    if name != skill_dir.name:
        errors.append("frontmatter name does not match folder name")
    if not re.fullmatch(r"[a-z0-9-]{1,64}", name):
        errors.append("frontmatter name is not portable")
    if not description:
        errors.append("frontmatter description is missing")
    if len(description) > 1024:
        errors.append("frontmatter description exceeds 1024 characters")

    for path in skill_dir.rglob("*"):
        if not path.is_symlink():
            continue
        try:
            path.resolve().relative_to(skill_dir.resolve())
        except ValueError:
            errors.append(
                f"symlink escapes skill directory: {path.relative_to(skill_dir)}"
            )
    return errors


def validate_all() -> dict[str, list[str]]:
    results: dict[str, list[str]] = {}
    for name in selected_names():
        errors = validate_skill(SKILLS_ROOT / name)
        if errors:
            results[name] = errors
    return results


def import_reference(path: Path) -> str:
    """Path for a CLAUDE.md-style @import: ~-relative when under $HOME, spaces escaped."""
    home = Path.home()
    try:
        text = "~/" + path.relative_to(home).as_posix()
    except ValueError:
        text = path.as_posix()
    return text.replace(" ", "\\ ")


def render_instructions(adapter: dict[str, Any]) -> str:
    """Render AGENTS.md for one adapter, plus that adapter's optional notes file.

    "import" writes a thin file that loads AGENTS.md in place through an @path
    import (Claude Code supports these in ~/.claude/CLAUDE.md), so edits to
    AGENTS.md apply without a reinstall. "markdown" writes a full copy.
    """
    format_name = adapter["instructions_format"]
    body = INSTRUCTIONS_PATH.read_text(encoding="utf-8")
    renderers = {
        "markdown": lambda text: text,
        "import": lambda _text: (
            "<!-- Written by agent-bakery tools/manage.py. Edit AGENTS.md and"
            f" adapters.json, not this file. -->\n@{import_reference(INSTRUCTIONS_PATH)}\n"
        ),
    }
    if format_name not in renderers:
        raise ValueError(f"unsupported instructions format: {format_name}")
    rendered = renderers[format_name](body)
    if "notes" in adapter:
        notes = (ROOT / adapter["notes"]).read_text(encoding="utf-8")
        rendered = rendered.rstrip("\n") + "\n\n" + notes
    return rendered


def backup_item(
    source: Path, backup_dir: Path, adapter_name: str, category: str, name: str
) -> bool:
    existed = source.exists() or source.is_symlink()
    if existed:
        copy_path(source, backup_dir / adapter_name / category / name)
    return existed


def install() -> int:
    validation = validate_all()
    if validation:
        print(json.dumps({"status": "validation_failed", "errors": validation}, indent=2))
        return 2

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    BACKUPS_ROOT.mkdir(parents=True, exist_ok=True)
    backup_id, suffix = stamp, 1
    while (BACKUPS_ROOT / backup_id).exists():  # two installs in one second
        suffix += 1
        backup_id = f"{stamp}-{suffix}"
    backup_dir = BACKUPS_ROOT / backup_id
    backup_dir.mkdir(exist_ok=False)
    state: dict[str, Any] = {
        "backup_id": backup_id,
        "skills": selected_names(),
        "agents": agent_names(),
        "adapters": {},
    }

    try:
        for adapter in adapters():
            adapter_name = adapter["name"]
            adapter_state: dict[str, Any] = {}
            state["adapters"][adapter_name] = adapter_state

            # skills_path is optional: a tool that already reads this repo's
            # skills/ folder (for example from ~/.agents/skills) needs no copy.
            if "skills_path" in adapter:
                skill_root = adapter_path(adapter, "skills_path")
                skill_root.mkdir(parents=True, exist_ok=True)
                adapter_state["skills_path"] = str(skill_root)
                adapter_state["skills"] = {}
                for name in selected_names():
                    source = SKILLS_ROOT / name
                    destination = skill_root / name
                    existed = backup_item(
                        destination, backup_dir, adapter_name, "skills", name
                    )
                    adapter_state["skills"][name] = {"existed": existed}
                    staged = skill_root / f".{name}.agent-stage-{os.getpid()}"
                    remove_path(staged)
                    copy_path(source, staged)
                    remove_path(destination)
                    staged.rename(destination)

            if "agents_path" in adapter:
                agent_root = adapter_path(adapter, "agents_path")
                agent_root.mkdir(parents=True, exist_ok=True)
                adapter_state["agents_path"] = str(agent_root)
                adapter_state["agents"] = {}
                for name in agent_names():
                    destination = agent_root / name
                    existed = backup_item(
                        destination, backup_dir, adapter_name, "agents", name
                    )
                    adapter_state["agents"][name] = {"existed": existed}
                    staged = agent_root / f".{name}.agent-stage-{os.getpid()}"
                    remove_path(staged)
                    copy_path(AGENTS_ROOT / name, staged)
                    remove_path(destination)
                    staged.rename(destination)

            if "instructions_path" in adapter:
                instruction_target = adapter_path(adapter, "instructions_path")
                instruction_existed = backup_item(
                    instruction_target,
                    backup_dir,
                    adapter_name,
                    "instructions",
                    instruction_target.name,
                )
                # Record the target only after its backup exists: restore_state
                # deletes every recorded target, and a target whose backup
                # failed must be left alone.
                adapter_state["instructions_path"] = str(instruction_target)
                adapter_state["instructions_existed"] = instruction_existed
                instruction_target.parent.mkdir(parents=True, exist_ok=True)
                staged_instruction = instruction_target.parent / (
                    f".{instruction_target.name}.agent-stage-{os.getpid()}"
                )
                remove_path(staged_instruction)
                staged_instruction.write_text(
                    render_instructions(adapter),
                    encoding="utf-8",
                )
                remove_path(instruction_target)
                staged_instruction.rename(instruction_target)
    except Exception:
        restore_state(state, backup_dir)
        raise

    with (backup_dir / "state.json").open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")

    verification = verify(quiet=True)
    output = {
        "status": "installed" if verification["ok"] else "verification_failed",
        "backup_id": backup_id,
        "backup_path": str(backup_dir),
        "verification": verification,
    }
    print(json.dumps(output, indent=2, sort_keys=True))
    return 0 if verification["ok"] else 3


def verify(quiet: bool = False) -> dict[str, Any]:
    validation = validate_all()
    skill_checks: list[dict[str, Any]] = []
    instruction_checks: list[dict[str, Any]] = []
    agent_checks: list[dict[str, Any]] = []

    for adapter in adapters():
        adapter_name = adapter["name"]
        skill_root = (
            adapter_path(adapter, "skills_path") if "skills_path" in adapter else None
        )
        for name in selected_names() if skill_root else []:
            source = SKILLS_ROOT / name
            destination = skill_root / name
            canonical_hash = tree_hash(source) if source.is_dir() else None
            installed_hash = tree_hash(destination) if destination.is_dir() else None
            skill_checks.append(
                {
                    "adapter": adapter_name,
                    "skill": name,
                    "exists": destination.is_dir(),
                    "canonical_sha256": canonical_hash,
                    "installed_sha256": installed_hash,
                    "hash_match": canonical_hash == installed_hash
                    and canonical_hash is not None,
                }
            )

        if "agents_path" in adapter:
            agent_root = adapter_path(adapter, "agents_path")
            for name in agent_names():
                destination = agent_root / name
                canonical = (AGENTS_ROOT / name).read_text(encoding="utf-8")
                installed = (
                    destination.read_text(encoding="utf-8")
                    if destination.is_file()
                    else None
                )
                agent_checks.append(
                    {
                        "adapter": adapter_name,
                        "agent": name,
                        "exists": destination.is_file(),
                        "canonical_sha256": text_hash(canonical),
                        "installed_sha256": (
                            text_hash(installed) if installed is not None else None
                        ),
                        "hash_match": installed == canonical,
                    }
                )

        if "instructions_path" not in adapter:
            continue
        instruction_target = adapter_path(adapter, "instructions_path")
        expected = render_instructions(adapter)
        actual = (
            instruction_target.read_text(encoding="utf-8")
            if instruction_target.is_file()
            else None
        )
        instruction_checks.append(
            {
                "adapter": adapter_name,
                "path": str(instruction_target),
                "exists": instruction_target.is_file(),
                "canonical_sha256": text_hash(expected),
                "installed_sha256": text_hash(actual) if actual is not None else None,
                "hash_match": actual == expected,
            }
        )

    result = {
        "ok": (
            not validation
            and all(check["hash_match"] for check in skill_checks)
            and all(check["hash_match"] for check in instruction_checks)
            and all(check["hash_match"] for check in agent_checks)
        ),
        "adapter_count": len(adapters()),
        "skill_count": len(selected_names()),
        "skill_copy_count": len(skill_checks),
        "instruction_copy_count": len(instruction_checks),
        "agent_copy_count": len(agent_checks),
        "validation_errors": validation,
        "skill_checks": skill_checks,
        "instruction_checks": instruction_checks,
        "agent_checks": agent_checks,
    }
    if not quiet:
        print(json.dumps(result, indent=2, sort_keys=True))
    return result


def plan() -> int:
    """Show what install would write, without writing anything."""
    result = verify(quiet=True)
    if result["validation_errors"]:
        print(json.dumps({"status": "validation_failed", "errors": result["validation_errors"]}, indent=2))
        return 2
    rows = []
    for check in result["skill_checks"]:
        target = Path(adapter_path(next(a for a in adapters() if a["name"] == check["adapter"]), "skills_path")) / check["skill"]
        rows.append((check, str(target)))
    for check in result["agent_checks"]:
        target = Path(adapter_path(next(a for a in adapters() if a["name"] == check["adapter"]), "agents_path")) / check["agent"]
        rows.append((check, str(target)))
    for check in result["instruction_checks"]:
        rows.append((check, check["path"]))
    for check, target in rows:
        status = "unchanged" if check["hash_match"] else "replace" if check["exists"] else "new"
        print(f"{status:9}  {check['adapter']:12}  {target}")
    changes = sum(1 for check, _ in rows if not check["hash_match"])
    print(f"{changes} of {len(rows)} targets would change. Replaced files are backed up first.")
    return 0


def restore_state(state: dict[str, Any], backup_dir: Path) -> None:
    for adapter_name, adapter_state in reversed(list(state.get("adapters", {}).items())):
        for name, skill_state in reversed(list(adapter_state.get("skills", {}).items())):
            destination = Path(adapter_state["skills_path"]) / name
            remove_path(destination)
            if skill_state["existed"]:
                copy_path(
                    backup_dir / adapter_name / "skills" / name, destination
                )

        for name, agent_state in reversed(list(adapter_state.get("agents", {}).items())):
            destination = Path(adapter_state["agents_path"]) / name
            remove_path(destination)
            if agent_state["existed"]:
                copy_path(backup_dir / adapter_name / "agents" / name, destination)

        if "instructions_path" not in adapter_state:
            continue
        instruction_target = Path(adapter_state["instructions_path"])
        remove_path(instruction_target)
        if adapter_state.get("instructions_existed", False):
            copy_path(
                backup_dir
                / adapter_name
                / "instructions"
                / instruction_target.name,
                instruction_target,
            )


def rollback(backup_id: str) -> int:
    backup_dir = BACKUPS_ROOT / backup_id
    state_path = backup_dir / "state.json"
    if not state_path.is_file():
        print(f"Backup state not found: {state_path}", file=sys.stderr)
        return 2
    state = load_json(state_path)
    restore_state(state, backup_dir)
    print(json.dumps({"status": "rolled_back", "backup_id": backup_id}, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("install", help="Back up and install all declared adapters.")
    subparsers.add_parser("verify", help="Validate and compare canonical hashes.")
    subparsers.add_parser("plan", help="Show what install would write, without writing.")
    rollback_parser = subparsers.add_parser("rollback", help="Restore one backup.")
    rollback_parser.add_argument("backup_id")
    args = parser.parse_args()

    if args.command == "install":
        return install()
    if args.command == "verify":
        return 0 if verify()["ok"] else 1
    if args.command == "plan":
        return plan()
    if args.command == "rollback":
        return rollback(args.backup_id)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
