from __future__ import annotations

import csv
import hashlib
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "render_fixed_snr_campaign_from_csv.py"


def test_campaign_only_renderer_writes_ten_lineage_bound_pngs(tmp_path: Path) -> None:
    report_csv = tmp_path / "reports" / "csv"
    report_csv.mkdir(parents=True)
    fields = [
        "Direction", "AppliedAWGNSNR_dB", "ConfiguredSNR_dB", "MeanMeasuredSINR_dB",
        "MCS", "Modulation", "Rank", "Layers", "ChannelModel", "TrialCount",
        "TBFailCount", "BLER", "BLER_CI_Low", "BLER_CI_High", "BLER_CI_Width",
        "BER", "BER_CI_Low", "BER_CI_High", "Throughput_Mbps", "TargetBLER",
        "Status",
    ]
    rows = []
    for direction in ("DL", "UL"):
        for snr, bler in ((-5, 1.0), (10, 0.8), (20, 0.1)):
            rows.append(
                {
                    "Direction": direction,
                    "AppliedAWGNSNR_dB": snr,
                    "ConfiguredSNR_dB": snr,
                    "MeanMeasuredSINR_dB": snr - 0.2,
                    "MCS": 20,
                    "Modulation": "256QAM",
                    "Rank": 1,
                    "Layers": 1,
                    "ChannelModel": "AWGN",
                    "TrialCount": 100,
                    "TBFailCount": int(100 * bler),
                    "BLER": bler,
                    "BLER_CI_Low": max(0, bler - 0.05),
                    "BLER_CI_High": min(1, bler + 0.05),
                    "BLER_CI_Width": 0.1,
                    "BER": bler / 3,
                    "BER_CI_Low": max(0, bler / 3 - 0.01),
                    "BER_CI_High": bler / 3 + 0.01,
                    "Throughput_Mbps": 70 * (1 - bler),
                    "TargetBLER": 0.1,
                    "Status": "complete",
                }
            )
    summary = report_csv / "fixed_snr_sweep_curve_summary.csv"
    with summary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--run-folder", str(tmp_path), "--execute"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr

    lineage_path = report_csv / "contract_plot_lineage.csv"
    with lineage_path.open("r", encoding="utf-8", newline="") as handle:
        lineage = list(csv.DictReader(handle))
    assert len(lineage) == 10
    assert all(row["Status"] == "pass" for row in lineage)
    assert all(row["MimeType"] == "image/png" for row in lineage)
    assert not list(tmp_path.rglob("*.svg"))
    with (report_csv / "plot_dl_throughput_vs_snr.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        throughput_rows = list(csv.DictReader(handle))
    assert throughput_rows
    assert {
        row["source_table_logical_path"] for row in throughput_rows
    } == {"reports/csv/fixed_snr_sweep_curve_summary.csv"}
    with (report_csv / "fixed_snr_renderer_provenance.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        provenance = list(csv.DictReader(handle))
    assert len(provenance) == 1
    assert provenance[0]["PersistentImageFormat"] == "PNG"
    assert provenance[0]["SVGFilesPersisted"] == "0"
    assert len(provenance[0]["RendererScriptSHA256"]) == 64
    assert len(provenance[0]["MaterializerModuleSHA256"]) == 64
    for row in lineage:
        image_path = tmp_path / row["ImagePath"]
        source_path = tmp_path / row["SourceCSV"]
        assert image_path.is_file() and source_path.is_file()
        assert hashlib.sha256(image_path.read_bytes()).hexdigest() == row["ImageSHA256"]
        assert hashlib.sha256(source_path.read_bytes()).hexdigest() == row["SourceCSV_SHA256"]
        with Image.open(image_path) as image:
            assert image.format == "PNG"
            assert image.width >= 1000 and image.height >= 500
