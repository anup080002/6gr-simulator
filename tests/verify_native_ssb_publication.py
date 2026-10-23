"""Validate/render retained MATLAB SSB evidence; no new PHY samples."""
import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def verify(root):
    source = root / "live_ssb_native_allocation_snapshot.csv"
    raw = source.read_bytes()
    records = list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))
    result = m._specialized_chart_materialization("SSB/PBCH occupancy map",
        {"reports/csv/" + source.name: {"artifact_id": 1}}, lambda _: raw, 1)
    assert result["csv_status"] == "executed_native_ssb_grid_dataset"
    plotted = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert sum(int(row["mapped_port_count"]) for row in plotted) == sum(
        int(float(row["native_mapped_re_count"])) for row in records)
    assert {row["allocation_id"] for row in plotted} == {row["allocation_id"] for row in records}
    assert {row["ssb_index0"] for row in plotted} == {row["ssb_index0"] for row in records}
    assert "visual_gate=" not in result["img_bytes"].decode()
    png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
    assert png.startswith(b"\x89PNG\r\n\x1a\n")
    target = root / "native_ssb_occupancy_verified.png"
    target.write_bytes(png)
    (root / "native_ssb_occupancy_verified_chart.csv").write_bytes(result["csv_bytes"])
    print(f"ACTUAL_SSB_GRID_CSV_PNG_PASS: source_rows={len(records)} plotted_bins={len(plotted)} PNG={target}")


if __name__ == "__main__":
    verify(Path(sys.argv[1]).resolve())
