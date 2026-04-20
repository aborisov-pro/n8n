from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

# Пользователь попросил "всё, кроме первого шага" — в репо есть намеренно пустые
# JSON-заглушки. Их не валим, но явно подсвечиваем.
IGNORE_EMPTY = {
    Path("pisec/Pisec_Log_Workflows.json"),
    Path("voron/Voron_Check_RSS.json"),
    Path("pozdravlyator/Pozdravlyator_Generate_Greeting.json"),
}


def iter_json_files() -> list[Path]:
    files: list[Path] = []
    for path in REPO_ROOT.rglob("*.json"):
        if ".git" in path.parts:
            continue
        files.append(path)
    return sorted(files)


def validate_workflow_shape(data: object, relpath: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return [f"{relpath}: root JSON must be an object"]

    name = data.get("name")
    if not isinstance(name, str) or not name.strip():
        errors.append(f"{relpath}: missing/invalid 'name' (expected non-empty string)")

    nodes = data.get("nodes")
    if not isinstance(nodes, list):
        errors.append(f"{relpath}: missing/invalid 'nodes' (expected array)")

    connections = data.get("connections")
    if not isinstance(connections, dict):
        errors.append(f"{relpath}: missing/invalid 'connections' (expected object)")

    return errors


def validate_sanitized(data: dict, relpath: str) -> list[str]:
    errors: list[str] = []

    if data.get("active") is True:
        errors.append(f"{relpath}: 'active' must be false in repo exports")

    for forbidden in ("id", "versionId"):
        if forbidden in data:
            errors.append(f"{relpath}: remove top-level '{forbidden}' (instance-specific)")

    meta = data.get("meta")
    if isinstance(meta, dict):
        if "instanceId" in meta:
            errors.append(f"{relpath}: remove meta.instanceId (instance-specific)")

    settings = data.get("settings")
    if isinstance(settings, dict):
        if "errorWorkflow" in settings:
            errors.append(f"{relpath}: remove settings.errorWorkflow (instance-specific)")

    nodes = data.get("nodes")
    if isinstance(nodes, list):
        for idx, node in enumerate(nodes):
            if not isinstance(node, dict):
                continue
            node_name = node.get("name")
            label = f"{relpath}: node[{idx}]"
            if isinstance(node_name, str) and node_name.strip():
                label = f"{relpath}: node[{idx}] ({node_name})"

            if "webhookId" in node:
                errors.append(f"{label}: remove webhookId (instance-specific)")
            if "id" in node:
                errors.append(f"{label}: remove node.id (instance-specific)")

            creds = node.get("credentials")
            if isinstance(creds, dict):
                for cred_type, cred_val in creds.items():
                    if isinstance(cred_val, dict) and "id" in cred_val:
                        errors.append(f"{label}: remove credentials.{cred_type}.id (instance-specific)")

    return errors


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []

    json_files = iter_json_files()
    if not json_files:
        warnings.append("No *.json files found.")

    for path in json_files:
        rel = path.relative_to(REPO_ROOT)
        rel_str = rel.as_posix()

        size = path.stat().st_size
        if size == 0:
            if rel in IGNORE_EMPTY:
                warnings.append(f"{rel_str}: empty placeholder (skipped)")
                continue
            errors.append(f"{rel_str}: file is empty")
            continue

        try:
            raw = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            raw = path.read_text(encoding="utf-8-sig")

        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            errors.append(f"{rel_str}: invalid JSON ({e})")
            continue

        errors.extend(validate_workflow_shape(data, rel_str))
        if isinstance(data, dict):
            errors.extend(validate_sanitized(data, rel_str))

    if warnings:
        print("Warnings:")
        for w in warnings:
            print(f"  - {w}")
        print()

    if errors:
        print("Errors:")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("OK: workflows look valid and sanitized.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
