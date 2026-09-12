#!/usr/bin/env python3
"""Render a hash-bound post-equalization constellation from actual capture CSV."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_csv", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("Use a new output directory; preserve previous evidence.")
    payload = args.capture_csv.read_bytes()
    rows = list(csv.DictReader(payload.decode("utf-8-sig").splitlines()))
    directions = {row.get("Direction") for row in rows}
    if len(directions) != 1 or not directions <= {"DL", "UL"}:
        parser.error("One explicitly identified direction is required per capture CSV.")
    direction = next(iter(directions))
    path = f"air_interface/csv/{direction.lower()}_constellation_samples.csv"
    result = m._specialized_chart_materialization("post-equalization constellation",
        {path: {"artifact_id": 1}}, lambda _: payload, 0)
    if result is None or result["source_row_count"] != len(rows):
        parser.error("Every captured row must contribute to the exported constellation dataset.")
    png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
    receipt = {
        "input_path": str(args.capture_csv.resolve()),
        "input_sha256": hashlib.sha256(payload).hexdigest(),
        "input_rows": len(rows), "exported_rows": result["source_row_count"],
        "display_limit_per_direction": 450,
        "display_sampling": "uniform_row_index_includes_first_and_last",
        "chart_csv_sha256": hashlib.sha256(result["csv_bytes"]).hexdigest(),
        "png_sha256": hashlib.sha256(png).hexdigest(),
        "note": result["note"], "full_run_qualification": False,
    }
    args.output_dir.mkdir(parents=True)
    (args.output_dir / "post_equalization_constellation.csv").write_bytes(result["csv_bytes"])
    (args.output_dir / "post_equalization_constellation.png").write_bytes(png)
    (args.output_dir / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
