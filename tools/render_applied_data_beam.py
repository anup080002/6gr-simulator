#!/usr/bin/env python3
"""Render one traceable data-beam view; never reinterpret PMI as weights."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from lls_applied_beam import validate_samples, render_surface
from lls_contract_materializer import _rasterize_contract_png


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_csv_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("Use a new output directory; earlier evidence is preserved.")
    sources = {}
    rows = {}
    for name in ("weights", "patterns"):
        path = args.source_csv_dir / f"applied_data_precoder_{name}.csv"
        payload = path.read_bytes()
        rows[name] = list(csv.DictReader(payload.decode("utf-8-sig").splitlines()))
        sources[name] = {"path": str(path.resolve()), "sha256": hashlib.sha256(payload).hexdigest(), "rows": len(rows[name])}
    grid, source, selected = validate_samples(rows["weights"], rows["patterns"])
    svg = render_surface(grid, source, selected, "Applied data precoder: 3D directivity")
    png = _rasterize_contract_png(svg, source_mime_type="image/svg+xml")
    receipt = {
        "source_artifacts": sources,
        "selected_transmission_prg_group_layer": selected,
        "matrix_sha256": source["MatrixSHA256"],
        "png_sha256": hashlib.sha256(png).hexdigest(),
        "reference_plane": "physical_element_data_grid_before_node_rf",
        "coordinate_frame": "local_array_before_runtime_orientation",
        "over_the_air_measurement": False,
        "full_run_qualification": False,
    }
    args.output_dir.mkdir(parents=True)
    (args.output_dir / "applied_data_beam.png").write_bytes(png)
    (args.output_dir / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
