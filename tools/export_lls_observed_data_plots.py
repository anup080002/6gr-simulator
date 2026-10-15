"""Export a bounded, provenance-backed plot review without modifying a saved run.

The same chart producers are used by the WebGUI output contract. This command
is for inspecting saved measurements; it never launches a PHY run or replaces
historical artifacts. Missing observations remain unavailable.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))
import lls_contract_materializer as materializer
from lls_radio_measurement_plots import CHARTS as RADIO_CHARTS, SOURCE_PATHS as RADIO_SOURCES

CHARTS = (
    "PDSCH EVM per symbol", "PUSCH EVM per symbol", "EVM per symbol",
    "EVM per subcarrier", "EVM per layer", "throughput vs SINR",
) + RADIO_CHARTS
SOURCES = tuple(dict.fromkeys((
    "air_interface/csv/dl_constellation_samples.csv",
    "air_interface/csv/ul_constellation_samples.csv",
    "air_interface/csv/dl_constellation_preview.csv",
    "air_interface/csv/ul_constellation_preview.csv",
    "reports/csv/equalized_constellations.csv",
    "air_interface/csv/dl_pdsch_trials.csv",
    "air_interface/csv/ul_pusch_trials.csv",
) + RADIO_SOURCES))


def export_observed_plots(run_root: Path, output_root: Path, *, source_map: dict | None = None) -> dict:
    run_root, output_root = run_root.resolve(strict=True), output_root.resolve()
    if not run_root.is_dir():
        raise ValueError("The source run must be a directory.")
    if output_root == run_root or run_root in output_root.parents or output_root in run_root.parents:
        raise ValueError("The review directory must be separate from the retained run tree.")
    if output_root.exists():
        raise FileExistsError("Use a new review directory; existing artifacts are never overwritten.")
    source_map = source_map or {}
    overrides = source_map.get("sources", {})
    scope = source_map.get("evidence_scope", "retained_measurements_not_scenario_acceptance")
    if not isinstance(overrides, dict) or set(overrides) - set(SOURCES):
        raise ValueError("Source mappings must name registered measurement CSV roles.")
    if overrides and not str(source_map.get("evidence_scope", "")).strip():
        raise ValueError("Explicit source mappings require their actual evidence scope.")
    existing, payloads, source_hashes, source_files = {}, {}, {}, {}
    for index, logical_path in enumerate(SOURCES, 1):
        relative = Path(overrides.get(logical_path, logical_path))
        path = (run_root / relative).resolve()
        if relative.is_absolute() or not path.is_relative_to(run_root):
            raise ValueError("A source mapping must remain inside the retained run directory.")
        if not path.is_file():
            if logical_path in overrides:
                raise FileNotFoundError(f"Explicit measurement source is absent: {path}")
            continue
        payloads[index] = path.read_bytes()
        existing[logical_path] = {"artifact_id": index, "logical_path": logical_path}
        source_hashes[logical_path] = hashlib.sha256(payloads[index]).hexdigest()
        source_files[logical_path] = path.relative_to(run_root).as_posix()
    if not existing:
        raise ValueError("No persisted trial or paired-constellation CSV source exists.")
    # Calculate before creating the destination, so a producer failure does
    # not create a misleading partially populated review directory.
    generated, outputs = {}, []
    for chart_name in CHARTS:
        result = materializer._specialized_chart_materialization(
            chart_name, existing, payloads.__getitem__, run_root.name
        )
        if result is None:
            raise ValueError(f"No registered chart producer for {chart_name}.")
        entry = {"chart_name": chart_name, "status": result["csv_status"],
                 "source_rows": result["source_row_count"], "note": result["note"],
                 "source_paths": result["source_table_path"].split("|"), "artifacts": {}}
        if result["csv_status"] != "unavailable_exact_reason":
            stem = chart_name.lower().replace(" ", "_").replace("/", "_")
            generated[f"{stem}.csv"] = result["csv_bytes"]
            svg = result["img_bytes"].decode("utf-8").replace("</svg>",
                '<text x="12" y="18" font-size="11" fill="#222">'
                'MEASURED OUTPUT REVIEW — not full scenario acceptance</text></svg>')
            generated[f"{stem}.png"] = materializer._rasterize_contract_png(
                svg.encode("utf-8"), source_mime_type="image/svg+xml",
                source_logical_path=f"internal://runtime-observation/{stem}.svg",
            )
            entry["artifacts"] = {f"{stem}.{suffix}": hashlib.sha256(generated[f"{stem}.{suffix}"]).hexdigest()
                                  for suffix in ("csv", "png")}
        outputs.append(entry)
    manifest = {
        "source_run_directory": str(run_root), "source_run_tag": run_root.name,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "artifact_kind": "post_run_measured_observation_review_not_new_phy_execution",
        "evidence_scope": scope, "terminal_qualification": False,
        "materializer_version": materializer.MATERIALIZER_VERSION,
        "producer_sha256": hashlib.sha256((REPO_ROOT / "apps/lls_contract_materializer.py").read_bytes()).hexdigest(),
        "producer_files_sha256": {name: hashlib.sha256((REPO_ROOT / name).read_bytes()).hexdigest()
            for name in ("apps/lls_contract_materializer.py", "apps/lls_radio_measurement_plots.py",
                         "tools/export_lls_observed_data_plots.py")},
        "source_sha256": source_hashes, "source_files": source_files, "outputs": outputs,
    }
    output_root.mkdir(parents=True, exist_ok=False)
    for name, payload in generated.items():
        (output_root / name).write_bytes(payload)
    # Keep the precise input bytes as well as hashes. A live component may
    # later replace its CSV after the second report; that must not change
    # the meaning or reproducibility of this first-report review.
    for logical, artifact in existing.items():
        snapshot = output_root / "source_snapshot" / source_files[logical]
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        snapshot.write_bytes(payloads[artifact["artifact_id"]])
    (output_root / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("output_root", type=Path, help="New directory outside the retained run tree")
    parser.add_argument("--source-map", type=Path,
                        help="Explicit JSON CSV-role mappings and evidence_scope for a component capture")
    arguments = parser.parse_args()
    mappings = json.loads(arguments.source_map.read_text(encoding="utf-8")) if arguments.source_map else None
    print(json.dumps(export_observed_plots(arguments.run_root, arguments.output_root,
                                         source_map=mappings), indent=2))
