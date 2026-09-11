"""Verify/render MATLAB-produced CSVs. No synthetic input or PHY inference."""
import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def verify(root):
    cases = [("live_prach_native_allocation_snapshot.csv", "PRACH native resource grid"),
             ("live_re_allocation_snapshot.csv", "frame/slot/symbol occupancy timeline")]
    observed = 0
    for filename, chart in cases:
        source = root / filename
        if not source.is_file():
            continue
        raw = source.read_bytes()
        result = m._specialized_chart_materialization(chart,
            {"reports/csv/" + filename: {"artifact_id": 1}}, lambda _: raw, 1)
        assert result["source_row_count"] > 0
        assert result["csv_status"].startswith("executed_")
        output = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
        assert output
        if chart == "PRACH native resource grid":
            rows = list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))
            assert len(output) == len(rows), "This component fixture supplies one complete occasion"
            assert sum(int(float(r["native_mapped_re_count"])) for r in output) == sum(
                int(float(r["native_subcarrier_count"])) for r in rows)
            assert "Native PRACH subcarrier index" in result["img_bytes"].decode()
        png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
        target = root / (source.stem + ".png")
        target.write_bytes(png)
        (root / (source.stem + "_chart.csv")).write_bytes(result["csv_bytes"])
        print(f"ACTUAL_GRID_PRODUCER_CSV_PNG_PASS: {chart}: {target}")
        observed += 1
    assert observed, "No actual producer CSV was supplied"


if __name__ == "__main__":
    verify(Path(sys.argv[1]).resolve())
