from __future__ import annotations

import csv
import hashlib
import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AUDIT_TOOL = REPO_ROOT / "tools" / "audit_lls_visual_artifacts.py"
PNG_BYTES = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"


def windows_extended_path(path: Path) -> Path:
    if os.name != "nt":
        return path
    text = str(path.resolve())
    if text.startswith("\\\\?\\"):
        return Path(text)
    return Path("\\\\?\\" + text)


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


def test_visual_artifact_audit_accepts_component_owned_lineage(tmp_path: Path) -> None:
    run = tmp_path / "run"
    report_csv = run / "reports" / "csv"
    component_root = run / "component_anchors" / "prach"
    lineage_dir = component_root / "control" / "csv"
    figure_dir = component_root / "reports" / "figures"
    report_csv.mkdir(parents=True)
    lineage_dir.mkdir(parents=True)
    figure_dir.mkdir(parents=True)

    # An existing (possibly empty) canonical manifest is required, while
    # component lineage owns component-specific visuals.
    write_csv(report_csv / "plot_manifest.csv", ["PlotId", "ImagePath"], [])
    source_path = lineage_dir / "correlation.csv"
    write_csv(
        source_path,
        ["LagSamples", "CorrelationAbs", "TruthStatus"],
        [
            {"LagSamples": index, "CorrelationAbs": index / 8, "TruthStatus": "real_lls_evidence"}
            for index in range(8)
        ],
    )
    image_path = figure_dir / "correlation.png"
    image_path.write_bytes(PNG_BYTES)
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    image_hash = hashlib.sha256(image_path.read_bytes()).hexdigest()
    write_csv(
        lineage_dir / "prach_plot_lineage.csv",
        ["PlotId", "ImagePath", "SourceCSV", "SourceCSV_SHA256", "ImageSHA256", "Status"],
        [
            {
                "PlotId": "prach_correlation",
                "ImagePath": "reports/figures/correlation.png",
                "SourceCSV": "control/csv/correlation.csv",
                "SourceCSV_SHA256": source_hash,
                "ImageSHA256": image_hash,
                "Status": "PASS",
            }
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
    with (report_csv / "visual_artifact_audit.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        rows = list(csv.DictReader(handle))
    component_rows = [
        row for row in rows if row.get("artifact_kind") == "component_lineage_plot"
    ]
    assert len(component_rows) == 1
    assert component_rows[0]["audit_ok"] == "True"
    assert not any(
        row.get("failure_code") == "unmanifested_visual_artifact" for row in rows
    )


def test_visual_artifact_audit_excludes_nested_sweep_execution(tmp_path: Path) -> None:
    run = tmp_path / "run"
    report_csv = run / "reports" / "csv"
    child_image = run / "sweeps" / "point_1" / "reports" / "image" / "orphan.png"
    report_csv.mkdir(parents=True)
    child_image.parent.mkdir(parents=True)
    write_csv(report_csv / "plot_manifest.csv", ["PlotId", "ImagePath"], [])
    child_image.write_bytes(PNG_BYTES)

    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (report_csv / "visual_artifact_audit.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        rows = list(csv.DictReader(handle))
    assert not any(str(row.get("artifact_path", "")).startswith("sweeps/") for row in rows)


def test_visual_artifact_audit_accepts_only_exact_component_image_mirror(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    report_csv = run / "reports" / "csv"
    report_image = run / "reports" / "image"
    mirror_image = run / "channel" / "image"
    report_csv.mkdir(parents=True)
    report_image.mkdir(parents=True)
    mirror_image.mkdir(parents=True)

    source_path = report_csv / "metric.csv"
    write_csv(
        source_path,
        ["x", "y"],
        [{"x": 1, "y": 2}, {"x": 2, "y": 3}, {"x": 3, "y": 5}],
    )
    canonical_path = report_image / "metric.png"
    canonical_path.write_bytes(PNG_BYTES)
    mirror_path = mirror_image / "metric.png"
    mirror_path.write_bytes(canonical_path.read_bytes())
    image_hash = hashlib.sha256(canonical_path.read_bytes()).hexdigest()
    write_csv(
        report_csv / "plot_manifest.csv",
        [
            "PlotId",
            "ImagePath",
            "SourceCSV",
            "XVariable",
            "YVariables",
            "PlotType",
            "PlotRenderStatus",
            "VisualValidity",
        ],
        [
            {
                "PlotId": "metric",
                "ImagePath": "reports/image/metric.png",
                "SourceCSV": "reports/csv/metric.csv",
                "XVariable": "x",
                "YVariables": "y",
                "PlotType": "line",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
            }
        ],
    )
    write_csv(
        report_csv / "component_artifact_publication_manifest.csv",
        [
            "Component",
            "ArtifactType",
            "CanonicalRelativePath",
            "PublishedRelativePath",
            "CanonicalSHA256",
            "PublishedSHA256",
            "MirrorOnly",
            "PublishStatus",
        ],
        [
            {
                "Component": "channel",
                "ArtifactType": "image",
                "CanonicalRelativePath": "reports/image/metric.png",
                "PublishedRelativePath": "channel/image/metric.png",
                "CanonicalSHA256": image_hash,
                "PublishedSHA256": image_hash,
                "MirrorOnly": True,
                "PublishStatus": "PUBLISHED_HASH_VERIFIED",
            }
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
    with (report_csv / "visual_artifact_audit.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        rows = list(csv.DictReader(handle))
    mirrors = [row for row in rows if row["artifact_kind"] == "component_mirror_plot"]
    assert len(mirrors) == 1
    assert mirrors[0]["audit_ok"] == "True"

    mirror_path.write_bytes(PNG_BYTES + b"mutated")
    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run), "--non-strict"],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr + proc.stdout
    codes = read_audit_codes(report_csv / "visual_artifact_audit.csv")
    assert "component_mirror_hash_mismatch" in codes


def test_visual_artifact_audit_supports_windows_extended_run_paths(tmp_path: Path) -> None:
    if os.name != "nt":
        return
    normal_run = tmp_path
    while len(str(normal_run.resolve())) < 245:
        normal_run = normal_run / "deep_result_component_1234567890"
    run = windows_extended_path(normal_run)
    report_csv = run / "reports" / "csv"
    report_image = run / "reports" / "image"
    report_csv.mkdir(parents=True)
    report_image.mkdir(parents=True)
    write_csv(
        report_csv / "metric.csv",
        ["x", "y"],
        [{"x": 1, "y": 2}, {"x": 2, "y": 3}],
    )
    (report_image / "metric.png").write_bytes(PNG_BYTES)
    write_csv(
        report_csv / "plot_manifest.csv",
        ["PlotId", "ImagePath", "SourceCSV", "XVariable", "YVariables", "PlotType", "PlotRenderStatus", "VisualValidity"],
        [{
            "PlotId": "metric",
            "ImagePath": "reports/image/metric.png",
            "SourceCSV": "reports/csv/metric.csv",
            "XVariable": "x",
            "YVariables": "y",
            "PlotType": "scatter",
            "PlotRenderStatus": "rendered_real_plot",
            "VisualValidity": "real_lls_evidence",
        }],
    )
    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(normal_run.resolve())],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr + proc.stdout
    assert not read_audit_codes(report_csv / "visual_artifact_audit.csv")


def test_visual_artifact_audit_rejects_unavailable_raster_cards(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "reports" / "image"
    csv_dir = run / "reports" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)

    (image_dir / "prach_correlation_traces_unavailable.png").write_bytes(PNG_BYTES)

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
                "ImagePath": "reports/image/prach_correlation_traces_unavailable.png",
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

    assert proc.returncode == 1, proc.stderr + proc.stdout
    codes = read_audit_codes(csv_dir / "visual_artifact_audit.csv")
    assert "unavailable_raster_forbidden" in codes
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


def test_visual_artifact_audit_accepts_multisource_union_and_tied_measured_cdf(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "reports" / "image"
    report_csv_dir = run / "reports" / "csv"
    air_csv_dir = run / "air_interface" / "csv"
    control_csv_dir = run / "control" / "csv"
    image_dir.mkdir(parents=True)
    report_csv_dir.mkdir(parents=True)
    air_csv_dir.mkdir(parents=True)
    control_csv_dir.mkdir(parents=True)
    (image_dir / "bler_vs_measured_sinr.png").write_bytes(PNG_BYTES)
    (image_dir / "access_delay_cdf.png").write_bytes(PNG_BYTES)

    write_csv(
        report_csv_dir / "plot_manifest.csv",
        [
            "PlotId", "ImagePath", "SourceCSV", "XVariable", "YVariables",
            "PlotType", "PlotRenderStatus", "VisualValidity", "IsUnavailableCard",
        ],
        [
            {
                "PlotId": "bler_vs_measured_sinr",
                "ImagePath": "reports/image/bler_vs_measured_sinr.png",
                "SourceCSV": "air_interface/csv/dl_curve.csv|air_interface/csv/ul_curve.csv",
                "XVariable": "PostEqSINR_dB_BinCenter",
                "YVariables": "BLER",
                "PlotType": "relation",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
            {
                "PlotId": "access_delay_cdf",
                "ImagePath": "reports/image/access_delay_cdf.png",
                "SourceCSV": "control/csv/initial_access_lifecycle_trace.csv",
                "XVariable": "ProcedureDelay_ms",
                "YVariables": "ProcedureDelay_ms",
                "PlotType": "cdf",
                "PlotRenderStatus": "rendered_real_plot",
                "VisualValidity": "real_lls_evidence",
                "IsUnavailableCard": "false",
            },
        ],
    )
    # UL is intentionally absent: a direction-specific run may satisfy the
    # declared union with only its existing canonical member.
    write_csv(
        air_csv_dir / "dl_curve.csv",
        ["PostEqSINR_dB_BinCenter", "BLER", "TruthStatus"],
        [
            {"PostEqSINR_dB_BinCenter": -5, "BLER": 1.0, "TruthStatus": "real_lls_evidence"},
            {"PostEqSINR_dB_BinCenter": 0, "BLER": 0.4, "TruthStatus": "real_lls_evidence"},
            {"PostEqSINR_dB_BinCenter": 5, "BLER": 0.0, "TruthStatus": "real_lls_evidence"},
        ],
    )
    write_csv(
        control_csv_dir / "initial_access_lifecycle_trace.csv",
        ["ProcedureDelay_ms", "ValueRole", "Notes"],
        [
            {
                "ProcedureDelay_ms": 5,
                "ValueRole": "measured_runtime_procedure_delay",
                "Notes": "contention-resolution waveform evidence",
            }
            for _ in range(4)
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
    codes = read_audit_codes(report_csv_dir / "visual_artifact_audit.csv")
    assert "rendered_plot_source_csv_missing" not in codes
    assert "low_information_visual_without_explanation" not in codes
    assert "plot_source_forbidden_truth_status" not in codes


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


def test_visual_artifact_audit_requires_low_information_explanation_for_contract_pngs(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "analytics" / "image"
    csv_dir = run / "analytics" / "csv"
    report_csv_dir = run / "reports" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    report_csv_dir.mkdir(parents=True)

    image_path = image_dir / "contract__beamforming__beam-gain-gap-histogram.png"
    image_path.write_bytes(PNG_BYTES)
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

    image_path.write_bytes(PNG_BYTES + b"visual_gate=constant_chart_source")
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


def test_visual_artifact_audit_rejects_valid_but_unmanifested_png(tmp_path: Path) -> None:
    run = tmp_path / "run"
    image_dir = run / "reports" / "image"
    csv_dir = run / "reports" / "csv"
    image_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    (image_dir / "orphan.png").write_bytes(PNG_BYTES)
    write_csv(
        csv_dir / "plot_manifest.csv",
        ["PlotId", "ImagePath", "SourceCSV", "XVariable", "YVariables", "PlotType", "PlotRenderStatus", "VisualValidity", "IsUnavailableCard"],
        [],
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
    assert "unmanifested_visual_artifact" in codes


def test_visual_artifact_audit_does_not_classify_html_reports_as_images(tmp_path: Path) -> None:
    run = tmp_path / "run"
    csv_dir = run / "reports" / "csv"
    html_dir = run / "reports" / "html"
    final_dir = run / "reports" / "final"
    csv_dir.mkdir(parents=True)
    html_dir.mkdir(parents=True)
    final_dir.mkdir(parents=True)
    (html_dir / "actual_lls_implementation_validation_report.html").write_text(
        "<html><body>validation report</body></html>", encoding="utf-8"
    )
    (final_dir / "final_scientific_audit.html").write_text(
        "<html><body>scientific audit report</body></html>", encoding="utf-8"
    )
    write_csv(
        csv_dir / "plot_manifest.csv",
        ["PlotId", "ImagePath", "SourceCSV", "XVariable", "YVariables", "PlotType", "PlotRenderStatus", "VisualValidity", "IsUnavailableCard"],
        [],
    )

    proc = subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (csv_dir / "visual_artifact_audit.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        audited_paths = {row["artifact_path"] for row in csv.DictReader(handle)}
    assert "reports/html/actual_lls_implementation_validation_report.html" not in audited_paths
    assert "reports/final/final_scientific_audit.html" not in audited_paths
