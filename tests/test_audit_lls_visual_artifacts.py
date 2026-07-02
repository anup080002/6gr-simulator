from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AUDIT_TOOL = REPO_ROOT / "tools" / "audit_lls_visual_artifacts.py"
PNG_BYTES = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def read_audit_codes(path: Path) -> set[str]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    codes: set[str] = set()
    for row in rows:
        for code in str(row.get("failure_code", "")).split("|"):
            code = code.strip()
            if code:
                codes.add(code)
    return codes


def test_visual_artifact_audit_accepts_unavailable_cards_without_source_semantics(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "reports" / "image"
    csv_dir = run / "reports" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)

    unavailable_svg = "<svg xmlns='http://www.w3.org/2000/svg'><text>Unavailable</text></svg>"
    (image_dir / "prach_correlation_traces_unavailable.svg").write_text(unavailable_svg, encoding="utf-8")

    write_csv(
        csv_dir / "plot_manifest.csv",
        [
            "PlotId",
            "ImagePath",
            "SourceCSV",
            "XVariable",
            "YVariables",
            "PlotType",
            "PlotRenderStatus",
            "VisualValidity",
            "IsUnavailableCard",
        ],
        [
            {
                "PlotId": "prach_correlation_traces",
                "ImagePath": "reports/image/prach_correlation_traces_unavailable.svg",
                "SourceCSV": "reports/csv/prach_correlation_trace.csv",
                "XVariable": "lag_samples",
                "YVariables": "correlation_abs",
                "PlotType": "trace",
                "PlotRenderStatus": "rendered_unavailable_card",
                "VisualValidity": "unavailable",
                "IsUnavailableCard": "true",
            },
        ],
    )
    write_csv(
        csv_dir / "prach_correlation_trace.csv",
        ["truth_status", "Reason"],
        [{"truth_status": "unavailable", "Reason": "PRACH trace not produced by this run"}],
    )

    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert proc.returncode == 0, proc.stderr + proc.stdout
    codes = read_audit_codes(csv_dir / "visual_artifact_audit.csv")
    assert "plot_source_x_column_missing" not in codes
    assert "plot_source_y_column_missing" not in codes
    assert "plot_source_forbidden_truth_status" not in codes


def test_visual_artifact_audit_ignores_unrelated_unavailable_source_tokens(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "reports" / "image"
    csv_dir = run / "reports" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    (image_dir / "papr_ccdf.png").write_bytes(PNG_BYTES)

    write_csv(
        csv_dir / "plot_manifest.csv",
        [
            "PlotId",
            "ImagePath",
            "SourceCSV",
            "XVariable",
            "YVariables",
            "PlotType",
            "PlotRenderStatus",
            "VisualValidity",
            "IsUnavailableCard",
        ],
        [
            {
                "PlotId": "papr_ccdf",
                "ImagePath": "reports/image/papr_ccdf.png",
                "SourceCSV": "reports/csv/ul_pusch_trials.csv",
                "XVariable": "PAPR_dB",
                "YVariables": "PAPR_dB",
                "PlotType": "cdf",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
        ],
    )
    write_csv(
        csv_dir / "ul_pusch_trials.csv",
        ["PAPR_dB", "PAPRValueStatus", "TruthStatus", "PostEqSINRValueStatus", "Notes"],
        [
            {
                "PAPR_dB": 7.5,
                "PAPRValueStatus": "measured",
                "TruthStatus": "strict_receiver_evidence_failed",
                "PostEqSINRValueStatus": "unavailable",
                "Notes": "PUSCH decode unavailable: posteq_sinr_unavailable",
            },
            {
                "PAPR_dB": 8.1,
                "PAPRValueStatus": "measured",
                "TruthStatus": "real_lls_evidence",
                "PostEqSINRValueStatus": "available",
                "Notes": "",
            },
        ],
    )

    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert proc.returncode == 0, proc.stderr + proc.stdout
    codes = read_audit_codes(csv_dir / "visual_artifact_audit.csv")
    assert "plot_source_forbidden_truth_status" not in codes


def test_visual_artifact_audit_rejects_unavailable_plotted_metric_status(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "reports" / "image"
    csv_dir = run / "reports" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    (image_dir / "posteq_sinr.png").write_bytes(PNG_BYTES)

    write_csv(
        csv_dir / "plot_manifest.csv",
        [
            "PlotId",
            "ImagePath",
            "SourceCSV",
            "XVariable",
            "YVariables",
            "PlotType",
            "PlotRenderStatus",
            "VisualValidity",
            "IsUnavailableCard",
        ],
        [
            {
                "PlotId": "posteq_sinr",
                "ImagePath": "reports/image/posteq_sinr.png",
                "SourceCSV": "reports/csv/dl_pdsch_trials.csv",
                "XVariable": "Slot",
                "YVariables": "PostEqSINR_dB",
                "PlotType": "line",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
        ],
    )
    write_csv(
        csv_dir / "dl_pdsch_trials.csv",
        ["Slot", "PostEqSINR_dB", "PostEqSINRValueStatus"],
        [
            {"Slot": 1, "PostEqSINR_dB": 5.0, "PostEqSINRValueStatus": "unavailable"},
            {"Slot": 2, "PostEqSINR_dB": 6.0, "PostEqSINRValueStatus": "unavailable"},
            {"Slot": 3, "PostEqSINR_dB": 7.0, "PostEqSINRValueStatus": "unavailable"},
        ],
    )

    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert proc.returncode != 0
    codes = read_audit_codes(csv_dir / "visual_artifact_audit.csv")
    assert "plot_source_forbidden_truth_status" in codes


def test_visual_artifact_audit_rejects_negative_fixture(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "reports" / "image"
    csv_dir = run / "reports" / "csv"
    analytics_csv_dir = run / "analytics" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    analytics_csv_dir.mkdir(parents=True)

    (image_dir / "stale_plot.png").write_bytes(PNG_BYTES)
    (image_dir / "png_bytes.svg").write_bytes(PNG_BYTES)
    (image_dir / "bler_vs_snr.png").write_bytes(PNG_BYTES)
    (image_dir / "short_line.png").write_bytes(PNG_BYTES)
    (image_dir / "heatmap_bad.png").write_bytes(PNG_BYTES)
    (image_dir / "fallback_plot.png").write_bytes(PNG_BYTES)

    manifest_fields = [
        "PlotId",
        "ImagePath",
        "SourceCSV",
        "XVariable",
        "YVariables",
        "PlotType",
        "PlotRenderStatus",
        "VisualValidity",
        "IsUnavailableCard",
    ]
    write_csv(
        csv_dir / "plot_manifest.csv",
        manifest_fields,
        [
            {
                "PlotId": "stale_plot",
                "ImagePath": "reports/image/stale_plot.png",
                "SourceCSV": "reports/csv/stale_source.csv",
                "XVariable": "x",
                "YVariables": "y",
                "PlotType": "line",
                "PlotRenderStatus": "suppressed",
                "VisualValidity": "unavailable",
                "IsUnavailableCard": "false",
            },
            {
                "PlotId": "png_bytes_svg",
                "ImagePath": "reports/image/png_bytes.svg",
                "SourceCSV": "reports/csv/svg_source.csv",
                "XVariable": "x",
                "YVariables": "y",
                "PlotType": "scatter",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
            {
                "PlotId": "bler_vs_snr",
                "ImagePath": "reports/image/bler_vs_snr.png",
                "SourceCSV": "reports/csv/bler_vs_snr.csv",
                "XVariable": "snr_db",
                "YVariables": "bler",
                "PlotType": "line",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
            {
                "PlotId": "short_line",
                "ImagePath": "reports/image/short_line.png",
                "SourceCSV": "reports/csv/short_line.csv",
                "XVariable": "Frame",
                "YVariables": "Value",
                "PlotType": "line",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
            {
                "PlotId": "bad_heatmap",
                "ImagePath": "reports/image/heatmap_bad.png",
                "SourceCSV": "reports/csv/heatmap_bad.csv",
                "XVariable": "x_value",
                "YVariables": "z_value",
                "PlotType": "heatmap",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
            {
                "PlotId": "contract__fake-heatmap",
                "ImagePath": "analytics/image/contract__fake-heatmap.svg",
                "SourceCSV": "analytics/csv/contract__fake-heatmap.csv",
                "XVariable": "x_value",
                "YVariables": "y_value",
                "PlotType": "line",
                "PlotRenderStatus": "rendered_diagnostic_plot",
                "VisualValidity": "diagnostic_only",
                "IsUnavailableCard": "false",
            },
            {
                "PlotId": "fallback_plot",
                "ImagePath": "reports/image/fallback_plot.png",
                "SourceCSV": "reports/csv/fallback_source.csv",
                "XVariable": "x",
                "YVariables": "y",
                "PlotType": "scatter",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
        ],
    )

    write_csv(csv_dir / "stale_source.csv", ["x", "y", "truth_status"], [{"x": 1, "y": 2, "truth_status": "real_lls_evidence"}])
    write_csv(csv_dir / "svg_source.csv", ["x", "y", "truth_status"], [{"x": 1, "y": 2, "truth_status": "real_lls_evidence"}])
    write_csv(
        csv_dir / "bler_vs_snr.csv",
        ["snr_db", "bler", "CurveConstruction", "truth_status"],
        [
            {"snr_db": 0, "bler": 0.8, "CurveConstruction": "measured_quality_binning", "truth_status": "real_lls_evidence"},
            {"snr_db": 5, "bler": 0.4, "CurveConstruction": "measured_quality_binning", "truth_status": "real_lls_evidence"},
            {"snr_db": 10, "bler": 0.1, "CurveConstruction": "measured_quality_binning", "truth_status": "real_lls_evidence"},
        ],
    )
    write_csv(
        csv_dir / "short_line.csv",
        ["Frame", "Value", "truth_status"],
        [
            {"Frame": 1, "Value": 10, "truth_status": "real_lls_evidence"},
            {"Frame": 2, "Value": 11, "truth_status": "real_lls_evidence"},
        ],
    )
    write_csv(
        csv_dir / "heatmap_bad.csv",
        ["x_value", "y_value", "z_value", "units", "truth_status"],
        [
            {"x_value": "band_a", "y_value": "kpi_a", "z_value": 10, "units": "Mbps", "truth_status": "real_lls_evidence"},
            {"x_value": "band_b", "y_value": "kpi_b", "z_value": 4, "units": "ms", "truth_status": "real_lls_evidence"},
        ],
    )
    write_csv(
        analytics_csv_dir / "contract__fake-heatmap.csv",
        ["chart_name", "chart_mode", "x_value", "y_value", "source_mapping_status"],
        [{"chart_name": "fake heatmap", "chart_mode": "line", "x_value": 1, "y_value": 2, "source_mapping_status": "unavailable"}],
    )
    write_csv(csv_dir / "fallback_source.csv", ["x", "y", "truth_status"], [{"x": 1, "y": 2, "truth_status": "fallback"}])

    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert proc.returncode != 0
    audit_csv = csv_dir / "visual_artifact_audit.csv"
    audit_md = run / "reports" / "visual_artifact_audit.md"
    assert audit_csv.exists()
    assert audit_md.exists()

    codes = read_audit_codes(audit_csv)
    assert "stale_suppressed_normal_artifact" in codes
    assert "png_bytes_in_svg" in codes
    assert "snr_sweep_from_measured_quality_bins" in codes
    assert "line_plot_insufficient_unique_x" in codes
    assert "heatmap_mixed_units" in codes
    assert "chart_source_mapping_not_exact" in codes
    assert "generic_chart_materializer_output" in codes
    assert "plot_source_forbidden_truth_status" in codes


def test_visual_artifact_audit_requires_low_information_explanation_for_contract_svgs(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "analytics" / "image"
    csv_dir = run / "analytics" / "csv"
    report_csv_dir = run / "reports" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    report_csv_dir.mkdir(parents=True)

    (image_dir / "contract__beamforming__beam-gain-gap-histogram.svg").write_text(
        "<svg xmlns='http://www.w3.org/2000/svg'><text>Beam gain gap histogram</text></svg>",
        encoding="utf-8",
    )
    write_csv(
        csv_dir / "contract__beamforming__beam-gain-gap-histogram.csv",
        ["run_id", "chart_name", "beam_gap_value", "source_mapping_status"],
        [
            {"run_id": 119, "chart_name": "beam gain gap histogram", "beam_gap_value": 0.0, "source_mapping_status": "exact"},
            {"run_id": 119, "chart_name": "beam gain gap histogram", "beam_gap_value": 0.0, "source_mapping_status": "exact"},
            {"run_id": 119, "chart_name": "beam gain gap histogram", "beam_gap_value": 0.0, "source_mapping_status": "exact"},
        ],
    )

    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run), "--non-strict"],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert proc.returncode == 0, proc.stderr + proc.stdout
    codes = read_audit_codes(report_csv_dir / "visual_artifact_audit.csv")
    assert "low_information_visual_without_explanation" in codes

    (image_dir / "contract__beamforming__beam-gain-gap-histogram.svg").write_text(
        "<svg xmlns='http://www.w3.org/2000/svg'><text>visual_gate=constant_chart_source</text></svg>",
        encoding="utf-8",
    )
    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run), "--non-strict"],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr + proc.stdout
    codes = read_audit_codes(report_csv_dir / "visual_artifact_audit.csv")
    assert "low_information_visual_without_explanation" not in codes
