from __future__ import annotations

"""Render a campaign-only fixed-SNR result from its persisted CSV evidence.

This command is intentionally narrower than the full LLS contract
materializer.  It accepts only the finalized fixed-sweep curve table, writes
PNG (never SVG) products, and binds every image to an exact plotted dataset
CSV.  It does not manufacture scenario summaries or lifecycle tables and
therefore cannot promote a campaign-only folder to a complete WebGUI run.
"""

import argparse
import csv
import hashlib
import io
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


REPO_ROOT = Path(__file__).resolve().parents[1]
APPS_ROOT = REPO_ROOT / "apps"
sys.path.insert(0, str(APPS_ROOT))

import lls_contract_materializer as materializer  # noqa: E402


LINEAGE_HEADER = [
    "PlotId", "ImagePath", "SourceCSV", "SourceCSV_SHA256",
    "ImageSHA256", "Width", "Height", "MimeType", "ImageExists",
    "SourceExists", "ProducerModule", "Status", "FailureReason",
]

CURVE_SOURCE = "reports/csv/fixed_snr_sweep_curve_summary.csv"


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def _encode_rows(rows: list[dict[str, Any]], fields: list[str]) -> bytes:
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def _write_bytes(run_root: Path, logical_path: str, data: bytes) -> None:
    target = (run_root / logical_path).resolve()
    target.relative_to(run_root)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)


def _finite(row: dict[str, str], name: str) -> float | None:
    try:
        value = float(row.get(name, ""))
    except (TypeError, ValueError):
        return None
    return value if value == value and abs(value) != float("inf") else None


def _lineage_row(
    plot_id: str,
    image_path: str,
    dataset_path: str,
    png: bytes,
    dataset: bytes,
) -> list[Any]:
    row = materializer._contract_plot_lineage_row(  # noqa: SLF001
        plot_id, image_path, dataset_path, png, dataset
    )
    row[10] = "scripts.render_fixed_snr_campaign_from_csv"
    return row


def _render_specialized(
    run_root: Path,
    existing: dict[str, dict[str, Any]],
    payloads: dict[int, bytes],
    chart_name: str,
    dataset_path: str,
    image_path: str,
) -> tuple[list[Any], bytes]:
    result = materializer._persisted_fixed_sweep_curve_chart(  # noqa: SLF001
        chart_name, existing, lambda artifact_id: payloads[artifact_id], 0
    )
    if not result or result.get("source_mapping_status") != "exact":
        raise RuntimeError(f"No exact fixed-sweep source mapping for {chart_name}.")
    dataset = bytes(result["csv_bytes"])
    png = materializer._rasterize_contract_png(  # noqa: SLF001
        bytes(result["img_bytes"]),
        source_mime_type="image/svg+xml",
        source_logical_path=image_path,
    )
    _write_bytes(run_root, dataset_path, dataset)
    _write_bytes(run_root, image_path, png)
    return _lineage_row(chart_name, image_path, dataset_path, png, dataset), png


def _render_statistic(
    run_root: Path,
    rows: list[dict[str, str]],
    chart_name: str,
    metric: str,
    y_label: str,
    dataset_path: str,
    image_path: str,
) -> tuple[list[Any], bytes]:
    normalized: list[dict[str, Any]] = []
    grouped: dict[str, list[list[float]]] = defaultdict(list)
    for row in rows:
        direction = str(row.get("Direction", "")).strip().upper()
        snr = _finite(row, "AppliedAWGNSNR_dB")
        if snr is None:
            snr = _finite(row, "ConfiguredSNR_dB")
        value = _finite(row, metric)
        if direction not in {"DL", "UL"} or snr is None or value is None:
            continue
        grouped[direction].append([snr, value])
        normalized.append(
            {
                "direction": direction,
                "applied_awgn_snr_db": snr,
                "metric": metric,
                "metric_value": value,
                "trial_count": row.get("TrialCount", ""),
                "point_status": row.get("Status", ""),
                "source_table_logical_path": CURVE_SOURCE,
            }
        )
    if not normalized or set(grouped) != {"DL", "UL"}:
        raise RuntimeError(f"{chart_name} requires finite DL and UL fixed-sweep rows.")
    for values in grouped.values():
        values.sort(key=lambda point: point[0])
    fields = list(normalized[0])
    dataset = _encode_rows(normalized, fields)
    svg = materializer._render_multi_series_svg(  # noqa: SLF001
        chart_name,
        "Measured fixed-link operating points from finalized campaign rows.",
        [{"name": key, "points": value} for key, value in sorted(grouped.items())],
        [f"Source CSV: {CURVE_SOURCE}", f"Plotted rows: {len(normalized)}"],
        x_label="Applied AWGN SNR (dB)",
        y_label=y_label,
        mode="line",
    )
    png = materializer._rasterize_contract_png(  # noqa: SLF001
        svg, source_mime_type="image/svg+xml", source_logical_path=image_path
    )
    _write_bytes(run_root, dataset_path, dataset)
    _write_bytes(run_root, image_path, png)
    return _lineage_row(chart_name, image_path, dataset_path, png, dataset), png


def _dashboard_png(panels: list[tuple[str, bytes]]) -> bytes:
    decoded: list[tuple[str, Image.Image]] = []
    for title, payload in panels:
        image = Image.open(io.BytesIO(payload)).convert("RGB")
        decoded.append((title, image))
    width = max(image.width for _title, image in decoded)
    height = max(image.height for _title, image in decoded)
    header = 54
    canvas = Image.new("RGB", (2 * width, 2 * (height + header)), "white")
    draw = ImageDraw.Draw(canvas)
    for index, (title, image) in enumerate(decoded[:4]):
        x = (index % 2) * width
        y = (index // 2) * (height + header)
        draw.text((x + 18, y + 16), title, fill="#13213a")
        canvas.paste(image, (x, y + header))
    output = io.BytesIO()
    canvas.save(output, format="PNG", compress_level=6)
    return output.getvalue()


def _renderer_provenance(source_bytes: bytes) -> bytes:
    def git(*args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(REPO_ROOT), *args],
            check=False,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip() if result.returncode == 0 else "unavailable"

    status = git("status", "--porcelain", "--untracked-files=no")
    rows = [
        {
            "RendererModule": "scripts.render_fixed_snr_campaign_from_csv",
            "RendererGitCommit": git("rev-parse", "HEAD"),
            "RendererGitDirty": int(bool(status and status != "unavailable")),
            "RendererScriptSHA256": _sha256(Path(__file__).resolve().read_bytes()),
            "MaterializerModuleSHA256": _sha256(Path(materializer.__file__).resolve().read_bytes()),
            "SourceCSV": CURVE_SOURCE,
            "SourceCSV_SHA256": _sha256(source_bytes),
            "PersistentImageFormat": "PNG",
            "SVGFilesPersisted": 0,
        }
    ]
    return _encode_rows(rows, list(rows[0]))


def render(run_folder: str | Path) -> dict[str, Any]:
    run_root = Path(run_folder).resolve()
    if not run_root.is_dir():
        raise RuntimeError(f"Run folder does not exist: {run_root}")
    curve_path = run_root / CURVE_SOURCE
    if not curve_path.is_file():
        raise RuntimeError(f"Missing finalized fixed-sweep curve CSV: {curve_path}")
    rows = _read_rows(curve_path)
    if not rows:
        raise RuntimeError("Finalized fixed-sweep curve CSV has no runtime rows.")

    source_paths = [
        CURVE_SOURCE,
        "reports/csv/dl_fixed_snr_bler_curve.csv",
        "reports/csv/ul_fixed_snr_bler_curve.csv",
        "reports/csv/dl_fixed_snr_ber_curve.csv",
        "reports/csv/ul_fixed_snr_ber_curve.csv",
    ]
    existing: dict[str, dict[str, Any]] = {}
    payloads: dict[int, bytes] = {}
    for artifact_id, logical_path in enumerate(source_paths, start=1):
        path = run_root / logical_path
        if path.is_file():
            payloads[artifact_id] = path.read_bytes()
            existing[logical_path] = {
                "artifact_id": artifact_id,
                "logical_path": logical_path,
            }

    specs = [
        ("dl_bler_vs_snr", "reports/csv/plot_dl_bler_vs_snr.csv", "reports/image/dl_bler_vs_snr.png"),
        ("ul_bler_vs_snr", "reports/csv/plot_ul_bler_vs_snr.csv", "reports/image/ul_bler_vs_snr.png"),
        ("dl_ber_vs_snr", "reports/csv/plot_dl_ber_vs_snr.csv", "reports/image/dl_ber_vs_snr.png"),
        ("ul_ber_vs_snr", "reports/csv/plot_ul_ber_vs_snr.csv", "reports/image/ul_ber_vs_snr.png"),
        ("dl_throughput_vs_snr", "reports/csv/plot_dl_throughput_vs_snr.csv", "reports/image/dl_throughput_vs_snr.png"),
        ("ul_throughput_vs_snr", "reports/csv/plot_ul_throughput_vs_snr.csv", "reports/image/ul_throughput_vs_snr.png"),
        ("measured_sinr_vs_configured_snr", "reports/csv/plot_measured_sinr_vs_configured_snr.csv", "reports/image/measured_sinr_vs_configured_snr.png"),
    ]
    lineage: list[list[Any]] = []
    images: dict[str, bytes] = {}
    for chart_name, dataset_path, image_path in specs:
        row, png = _render_specialized(
            run_root, existing, payloads, chart_name, dataset_path, image_path
        )
        lineage.append(row)
        images[chart_name] = png

    for chart_name, metric, y_label, dataset_path, image_path in [
        ("fixed_snr_trials_per_point", "TrialCount", "Transport blocks", "reports/csv/plot_fixed_snr_trials_per_point.csv", "reports/image/fixed_snr_trials_per_point.png"),
        ("fixed_snr_ci_width_vs_snr", "BLER_CI_Width", "BLER 95% CI width", "reports/csv/plot_fixed_snr_ci_width_vs_snr.csv", "reports/image/fixed_snr_ci_width_vs_snr.png"),
    ]:
        row, png = _render_statistic(
            run_root, rows, chart_name, metric, y_label, dataset_path, image_path
        )
        lineage.append(row)
        images[chart_name] = png

    dashboard_dataset_path = "reports/csv/plot_fixed_snr_curve_dashboard.csv"
    dashboard_image_path = "reports/image/fixed_snr_curve_dashboard.png"
    dashboard_dataset = curve_path.read_bytes()
    _write_bytes(run_root, dashboard_dataset_path, dashboard_dataset)
    dashboard = _dashboard_png(
        [
            ("DL BLER", images["dl_bler_vs_snr"]),
            ("UL BLER", images["ul_bler_vs_snr"]),
            ("DL throughput", images["dl_throughput_vs_snr"]),
            ("UL throughput", images["ul_throughput_vs_snr"]),
        ]
    )
    _write_bytes(run_root, dashboard_image_path, dashboard)
    lineage.append(
        _lineage_row(
            "fixed_snr_curve_dashboard",
            dashboard_image_path,
            dashboard_dataset_path,
            dashboard,
            dashboard_dataset,
        )
    )

    contract = _encode_rows(
        [dict(zip(LINEAGE_HEADER, row, strict=True)) for row in lineage],
        LINEAGE_HEADER,
    )
    _write_bytes(run_root, "reports/csv/contract_plot_lineage.csv", contract)
    fixed_rows = [list(row) for row in lineage]
    for row in fixed_rows:
        row[11] = "rendered"
    fixed = _encode_rows(
        [dict(zip(LINEAGE_HEADER, row, strict=True)) for row in fixed_rows],
        LINEAGE_HEADER,
    )
    _write_bytes(run_root, "reports/csv/fixed_snr_plot_lineage.csv", fixed)
    _write_bytes(
        run_root,
        "reports/csv/fixed_snr_renderer_provenance.csv",
        _renderer_provenance(curve_path.read_bytes()),
    )
    return {
        "run_folder": str(run_root),
        "plot_count": len(lineage),
        "source_sha256": _sha256(curve_path.read_bytes()),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render finalized fixed-SNR campaign CSVs as lineage-bound PNGs."
    )
    parser.add_argument("--run-folder", required=True)
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Required acknowledgement before replacing the ten fixed-SNR PNG targets.",
    )
    args = parser.parse_args()
    if not args.execute:
        parser.error("--execute is required")
    result = render(args.run_folder)
    print(
        f"Rendered {result['plot_count']} fixed-SNR PNGs from "
        f"{result['source_sha256']} into {result['run_folder']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
