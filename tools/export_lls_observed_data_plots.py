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


def export_observed_plots(run_root: Path, output_root: Path) -> dict:
    run_root, output_root = run_root.resolve(strict=True), output_root.resolve()
    if not run_root.is_dir():
        raise ValueError("The source run must be a directory.")
    if output_root == run_root or run_root in output_root.parents or output_root in run_root.parents:
        raise ValueError("The review directory must be separate from the retained run tree.")
    if output_root.exists():
        raise FileExistsError("Use a new review directory; existing artifacts are never overwritten.")
    existing, payloads, source_hashes = {}, {}, {}
    for index, logical_path in enumerate(SOURCES, 1):
        path = run_root / logical_path
        if not path.is_file():
            continue
        payloads[index] = path.read_bytes()
        existing[logical_path] = {"artifact_id": index, "logical_path": logical_path}
        source_hashes[logical_path] = hashlib.sha256(payloads[index]).hexdigest()
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
            generated[f"{stem}.png"] = materializer._rasterize_contract_png(
                result["img_bytes"], source_mime_type="image/svg+xml",
                source_logical_path=f"internal://runtime-observation/{stem}.svg",
            )
            entry["artifacts"] = {f"{stem}.{suffix}": hashlib.sha256(generated[f"{stem}.{suffix}"]).hexdigest()
                                  for suffix in ("csv", "png")}
        outputs.append(entry)
    manifest = {
        "source_run_directory": str(run_root), "source_run_tag": run_root.name,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "artifact_kind": "post_run_measured_observation_review_not_new_phy_execution",
        "materializer_version": materializer.MATERIALIZER_VERSION,
        "producer_sha256": hashlib.sha256((REPO_ROOT / "apps/lls_contract_materializer.py").read_bytes()).hexdigest(),
        "producer_files_sha256": {name: hashlib.sha256((REPO_ROOT / name).read_bytes()).hexdigest()
            for name in ("apps/lls_contract_materializer.py", "apps/lls_radio_measurement_plots.py")},
        "source_sha256": source_hashes, "outputs": outputs,
    }
    output_root.mkdir(parents=True, exist_ok=False)
    for name, payload in generated.items():
        (output_root / name).write_bytes(payload)
    (output_root / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("output_root", type=Path, help="New directory outside the retained run tree")
    arguments = parser.parse_args()
    print(json.dumps(export_observed_plots(arguments.run_root, arguments.output_root), indent=2))
