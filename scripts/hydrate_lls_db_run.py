from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import sys
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).absolute().parents[1]
RESULTS_ROOT = (REPO_ROOT / "results" / "lls").resolve()
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def _io_path(path: Path) -> Path:
    """Return a Windows extended-length path without changing its identity."""
    if os.name != "nt":
        return path
    value = str(path)
    if value.startswith("\\\\?\\"):
        return path
    return Path("\\\\?\\" + value)


def _safe_target(run_root: Path, logical_path: str) -> Path:
    normalized = str(logical_path or "").strip().replace("\\", "/")
    relative = PurePosixPath(normalized)
    if not normalized or relative.is_absolute() or ".." in relative.parts:
        raise RuntimeError(f"Unsafe database artifact path: {logical_path!r}")
    target = (run_root / Path(*relative.parts)).resolve()
    target.relative_to(run_root)
    return target


def hydrate(run_id: int, target_folder: Path | None = None) -> dict[str, object]:
    run_row = dash.fetch_run(int(run_id))
    if run_row is None:
        raise RuntimeError(f"Run {run_id} was not found in sim_runs.")

    configured_root = Path(str(run_row.get("run_folder") or "")).resolve()
    run_root = (target_folder or configured_root).resolve()
    run_root.relative_to(RESULTS_ROOT)
    if target_folder is not None and run_root != configured_root:
        raise RuntimeError(
            "Hydration target must equal the canonical run_folder recorded in sim_runs."
        )
    run_root.mkdir(parents=True, exist_ok=True)

    # A materializer can publish a newer revision at the same logical path.
    # Hydration therefore selects the highest artifact_id for each path, exactly
    # matching the dashboard's latest-artifact semantics.
    newest: dict[str, dict[str, object]] = {}
    for artifact in dash.fetch_artifacts(int(run_id)):
        logical_path = str(artifact.get("logical_path") or "").strip()
        if not logical_path:
            continue
        previous = newest.get(logical_path)
        if previous is None or int(artifact.get("artifact_id") or 0) > int(
            previous.get("artifact_id") or 0
        ):
            newest[logical_path] = artifact

    written = 0
    unchanged = 0
    total_bytes = 0
    aggregate = hashlib.sha256()
    for logical_path in sorted(newest):
        artifact = newest[logical_path]
        artifact_id = int(artifact.get("artifact_id") or 0)
        payload = dash.fetch_artifact_bytes(artifact_id)
        expected_size = int(artifact.get("byte_size") or 0)
        if expected_size != len(payload):
            raise RuntimeError(
                f"Artifact {artifact_id} size mismatch for {logical_path}: "
                f"database={expected_size}, fetched={len(payload)}"
            )
        target = _safe_target(run_root, logical_path)
        digest = hashlib.sha256(payload).hexdigest()
        aggregate.update(logical_path.encode("utf-8"))
        aggregate.update(b"\0")
        aggregate.update(digest.encode("ascii"))
        aggregate.update(b"\n")
        total_bytes += len(payload)
        io_target = _io_path(target)
        if io_target.is_file() and io_target.stat().st_size == len(payload):
            if hashlib.sha256(io_target.read_bytes()).hexdigest() == digest:
                unchanged += 1
                continue
        io_target.parent.mkdir(parents=True, exist_ok=True)
        temporary = io_target.with_name(
            f".{io_target.name}.hydrate-{os.getpid()}-{artifact_id}.tmp"
        )
        temporary.write_bytes(payload)
        os.replace(temporary, io_target)
        written += 1

    identity_created = _restore_missing_config_identity(run_root)

    return {
        "run_id": int(run_id),
        "run_folder": str(run_root),
        "database_artifact_rows": len(dash.fetch_artifacts(int(run_id))),
        "unique_logical_paths": len(newest),
        "files_written": written,
        "files_unchanged": unchanged,
        "total_bytes": total_bytes,
        "logical_path_sha256": aggregate.hexdigest(),
        "config_identity_restored": identity_created,
    }


def _restore_missing_config_identity(run_root: Path) -> bool:
    """Rebuild only missing integrity metadata from immutable run artifacts."""
    meta = run_root / "meta"
    identity_path = meta / "scenario_config_identity.json"
    if _io_path(identity_path).is_file():
        return False
    resolved_json = meta / "scenario_config_resolved.json"
    manifest_path = meta / "scenario_manifest.json"
    if not _io_path(resolved_json).is_file() or not _io_path(manifest_path).is_file():
        return False
    manifest = json.loads(_io_path(manifest_path).read_text(encoding="utf-8"))
    scenario_id = str(manifest.get("ScenarioID") or "").strip()
    config_hash = str(manifest.get("ConfigHash") or "").strip()
    if not scenario_id or not config_hash:
        raise RuntimeError(
            "Cannot restore scenario_config_identity.json without the immutable "
            "ScenarioID and ConfigHash in scenario_manifest.json."
        )

    def digest(relative_name: str) -> str:
        path = meta / relative_name
        return (
            hashlib.sha256(_io_path(path).read_bytes()).hexdigest()
            if _io_path(path).is_file()
            else ""
        )

    identity = {
        "SchemaVersion": "sixgr_resolved_config_identity/v1",
        "ScenarioID": scenario_id,
        "ConfigHash": config_hash,
        "ResolvedJSONSHA256": digest("scenario_config_resolved.json"),
        "ResolvedYAMLSHA256": digest("scenario_config_resolved.yaml"),
        "RuntimeViewJSONSHA256": digest("scenario_runtime_view.json"),
        "RuntimeViewYAMLSHA256": digest("scenario_runtime_view.yaml"),
        "GeneratedUTC": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "RecoveryAuthority": "immutable_hydrated_run_artifacts",
    }
    payload = (json.dumps(identity, indent=2) + "\n").encode("utf-8")
    io_identity = _io_path(identity_path)
    io_identity.parent.mkdir(parents=True, exist_ok=True)
    temporary = io_identity.with_name(
        f".{io_identity.name}.hydrate-{os.getpid()}-identity.tmp"
    )
    temporary.write_bytes(payload)
    os.replace(temporary, io_identity)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Hydrate the latest revision of every database-backed LLS artifact "
            "into its canonical results/lls run folder."
        )
    )
    parser.add_argument("--run-id", required=True, type=int)
    args = parser.parse_args()
    print(json.dumps(hydrate(args.run_id), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
