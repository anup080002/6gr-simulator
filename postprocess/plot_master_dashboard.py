#!/usr/bin/env python3
"""Build the master analysis dashboard and small companion HTML reports.

The generator is intentionally dependency-light. It reads only completed-run
CSV artifacts and writes static HTML. Missing runtime measurements stay visible
as "no rows" or blank cells instead of being replaced with synthetic values.
"""
from __future__ import annotations

import csv
import html
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean


RUN_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
REPORT_CSV = RUN_DIR / "reports" / "csv"
AIR_CSV = RUN_DIR / "air_interface" / "csv"
CONTROL_CSV = RUN_DIR / "control" / "csv"
HTML_DIR = RUN_DIR / "reports" / "html"


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def esc(value: object) -> str:
    return html.escape("" if value is None else str(value))


def fnum(value: object) -> float:
    try:
        x = float(str(value).strip())
    except Exception:
        return math.nan
    return x if math.isfinite(x) else math.nan


def finite(values: list[float]) -> list[float]:
    return [v for v in values if math.isfinite(v)]


def table_html(rows: list[dict[str, str]], max_rows: int = 80) -> str:
    if not rows:
        return "<p class='empty'>No source rows were available for this report.</p>"
    cols = list(rows[0].keys())
    out = ["<div class='table-wrap'><table><thead><tr>"]
    out.extend(f"<th>{esc(c)}</th>" for c in cols)
    out.append("</tr></thead><tbody>")
    for row in rows[:max_rows]:
        out.append("<tr>" + "".join(f"<td>{esc(row.get(c, ''))}</td>" for c in cols) + "</tr>")
    out.append("</tbody></table></div>")
    if len(rows) > max_rows:
        out.append(f"<p class='note'>Showing {max_rows} of {len(rows)} rows.</p>")
    return "\n".join(out)


def card(title: str, value: str, subtitle: str = "") -> str:
    return (
        "<section class='card'>"
        f"<div class='card-title'>{esc(title)}</div>"
        f"<div class='card-value'>{esc(value)}</div>"
        f"<div class='card-subtitle'>{esc(subtitle)}</div>"
        "</section>"
    )


def summary_cards(rows: list[dict[str, str]]) -> str:
    if not rows:
        return card("Rows", "0", "No source data")
    return card("Rows", str(len(rows)), "Source rows read")


def svg_bar(values: dict[str, float], unit: str = "") -> str:
    finite_vals = finite(list(values.values()))
    if not finite_vals:
        return "<p class='empty'>No finite values to plot.</p>"
    max_val = max(max(finite_vals), 1e-12)
    out = ["<svg class='chart' viewBox='0 0 900 260' preserveAspectRatio='none'>"]
    out.append("<line x1='80' y1='220' x2='880' y2='220' stroke='#c8d0d8'/>")
    count = max(len(values), 1)
    width = min(80, 640 / count)
    gap = (760 - count * width) / max(count + 1, 1)
    x = 80 + gap
    for label, val in values.items():
        if not math.isfinite(val):
            x += width + gap
            continue
        h = max(1, 190 * val / max_val)
        y = 220 - h
        out.append(f"<rect x='{x:.1f}' y='{y:.1f}' width='{width:.1f}' height='{h:.1f}' rx='5' fill='#2364aa'/>")
        out.append(f"<text x='{x + width/2:.1f}' y='242' text-anchor='middle' class='axis'>{esc(label)}</text>")
        out.append(f"<text x='{x + width/2:.1f}' y='{max(16, y - 8):.1f}' text-anchor='middle' class='label'>{val:.4g}{esc(unit)}</text>")
        x += width + gap
    out.append("</svg>")
    return "\n".join(out)


def svg_points(rows: list[dict[str, str]], x_col: str, y_col: str, group_col: str | None = None) -> str:
    pts: list[tuple[float, float, str]] = []
    for row in rows:
        x = fnum(row.get(x_col, ""))
        y = fnum(row.get(y_col, ""))
        if math.isfinite(x) and math.isfinite(y):
            group = row.get(group_col, "") if group_col else ""
            pts.append((x, y, group))
    if not pts:
        return "<p class='empty'>No finite x/y pairs to plot.</p>"
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    xmin, xmax = min(xs), max(xs)
    ymin, ymax = min(ys), max(ys)
    if xmin == xmax:
        xmin -= 1
        xmax += 1
    if ymin == ymax:
        ymin -= 1
        ymax += 1
    colors = ["#2364aa", "#f06c4f", "#2a9d8f", "#6f4e9b", "#d99a00"]
    groups = {g: colors[i % len(colors)] for i, g in enumerate(sorted({p[2] for p in pts}))}

    def sx(x: float) -> float:
        return 70 + 790 * (x - xmin) / (xmax - xmin)

    def sy(y: float) -> float:
        return 220 - 180 * (y - ymin) / (ymax - ymin)

    out = ["<svg class='chart' viewBox='0 0 900 270' preserveAspectRatio='none'>"]
    out.append("<line x1='60' y1='220' x2='870' y2='220' stroke='#c8d0d8'/>")
    out.append("<line x1='60' y1='30' x2='60' y2='220' stroke='#c8d0d8'/>")
    out.append(f"<text x='60' y='248' class='axis'>{esc(x_col)}</text>")
    out.append(f"<text x='12' y='32' class='axis'>{esc(y_col)}</text>")
    for x, y, group in pts:
        out.append(f"<circle cx='{sx(x):.1f}' cy='{sy(y):.1f}' r='6' fill='{groups.get(group, colors[0])}'><title>{esc(group)} x={x:.4g} y={y:.4g}</title></circle>")
    if group_col:
        lx = 720
        ly = 30
        for group, color in groups.items():
            out.append(f"<rect x='{lx}' y='{ly}' width='12' height='12' fill='{color}'/>")
            out.append(f"<text x='{lx + 18}' y='{ly + 11}' class='axis'>{esc(group or 'group')}</text>")
            ly += 18
    out.append("</svg>")
    return "\n".join(out)


def write_page(filename: str, title: str, body: str, source: str) -> None:
    HTML_DIR.mkdir(parents=True, exist_ok=True)
    path = HTML_DIR / filename
    path.write_text(
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<title>{esc(title)}</title>"
        "<style>"
        ":root{--ink:#17212f;--muted:#65748b;--line:#d9e1ea;--bg:#f7f9fc;--card:#fff;--accent:#2364aa}"
        "body{margin:0;background:var(--bg);color:var(--ink);font-family:Segoe UI,Arial,sans-serif}"
        "main{padding:24px;max-width:1280px;margin:auto}"
        "h1{margin:0 0 8px;font-size:24px}"
        ".source{color:var(--muted);font-size:13px;margin-bottom:18px}"
        ".cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin:16px 0}"
        ".card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px}"
        ".card-title{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}"
        ".card-value{font-size:26px;font-weight:700;margin-top:6px}"
        ".card-subtitle{color:var(--muted);font-size:12px;margin-top:4px}"
        ".panel{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:16px 0}"
        ".chart{width:100%;height:270px;background:white;border:1px solid var(--line);border-radius:10px}"
        ".axis{font-size:12px;fill:#65748b}.label{font-size:11px;fill:#17212f;font-weight:600}"
        ".table-wrap{overflow:auto;max-height:560px;border:1px solid var(--line);border-radius:10px;background:white}"
        "table{border-collapse:collapse;width:100%;font-size:12px}th,td{border-bottom:1px solid var(--line);padding:7px;text-align:left;white-space:nowrap}"
        "th{position:sticky;top:0;background:#eef3f8;z-index:1}.empty,.note{color:var(--muted);font-size:13px}"
        "</style></head><body><main>"
        f"<h1>{esc(title)}</h1><div class='source'>Source: {esc(source)}. Measurements are displayed only when present in CSV inputs.</div>"
        f"{body}</main></body></html>",
        encoding="utf-8",
    )


def build_overview() -> None:
    summary = read_csv(REPORT_CSV / "scenario_summary.csv")
    generation = read_csv(REPORT_CSV / "analysis_generation_summary.csv")
    per_slot = read_csv(REPORT_CSV / "per_slot_kpi_table.csv")
    dl_trials = read_csv(AIR_CSV / "dl_pdsch_trials.csv")
    ul_trials = read_csv(AIR_CSV / "ul_pusch_trials.csv")
    dl_fail = sum(str(r.get("CRCPass", "")).strip().lower() in {"0", "false", "fail"} for r in dl_trials)
    ul_fail = sum(str(r.get("CRCPass", "")).strip().lower() in {"0", "false", "fail"} for r in ul_trials)
    cards = [
        card("Scenario Summary Rows", str(len(summary)), "scenario_summary.csv"),
        card("DL Trials", str(len(dl_trials)), f"failures={dl_fail}"),
        card("UL Trials", str(len(ul_trials)), f"failures={ul_fail}"),
        card("Analysis Tables", str(len(generation)), "analysis_generation_summary.csv"),
        card("Observed Slots", str(len(per_slot)), "per_slot_kpi_table.csv"),
    ]
    body = "<div class='cards'>" + "".join(cards) + "</div>"
    body += "<section class='panel'><h2>Analysis Generation</h2>" + table_html(generation) + "</section>"
    body += "<section class='panel'><h2>Scenario Summary</h2>" + table_html(summary, 20) + "</section>"
    write_page("kpi_overview.html", "KPI Overview", body, "scenario_summary.csv and generated analysis CSVs")


def build_bler_vs_measured_sinr() -> None:
    rows = read_csv(AIR_CSV / "dl_measured_sinr_bler_curve.csv") + read_csv(AIR_CSV / "ul_measured_sinr_bler_curve.csv")
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>BLER vs Measured SINR</h2>" + svg_points(rows, "PostEqSINR_dB_BinCenter", "BLER", "Direction") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("bler_vs_measured_sinr.html", "BLER vs Measured SINR", body, "air_interface/csv/*_measured_sinr_bler_curve.csv")


def build_throughput_vs_measured_sinr() -> None:
    rows = read_csv(AIR_CSV / "dl_measured_sinr_throughput_curve.csv") + read_csv(AIR_CSV / "ul_measured_sinr_throughput_curve.csv")
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>Goodput vs Measured SINR</h2>" + svg_points(rows, "PostEqSINR_dB_BinCenter", "Goodput_Mbps_mean", "Direction") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("throughput_vs_measured_sinr.html", "Throughput vs Measured SINR", body, "air_interface/csv/*_measured_sinr_throughput_curve.csv")


def build_nmse_vs_measured_sinr() -> None:
    rows = read_csv(REPORT_CSV / "nmse_vs_measured_sinr.csv")
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>NMSE vs Measured SINR</h2>" + svg_points(rows, "PostEqSINR_dB", "MetricValue", "Direction") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("nmse_vs_measured_sinr.html", "NMSE vs Measured SINR", body, "reports/csv/nmse_vs_measured_sinr.csv")


def build_energy_vs_throughput() -> None:
    rows = read_csv(REPORT_CSV / "energy_vs_throughput.csv")
    values = {}
    if rows:
        values = {
            "GoodBits": fnum(rows[0].get("GoodBits", "")),
            "Energy_J": fnum(rows[0].get("Energy_J", "")),
            "EnergyPerBit_J": fnum(rows[0].get("EnergyPerBit_J", "")),
        }
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>Energy Metrics</h2>" + svg_bar(values) + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("energy_vs_throughput.html", "Energy vs Throughput", body, "reports/csv/energy_vs_throughput.csv")


def build_access_delay_cdf() -> None:
    source = "control/csv/initial_access_lifecycle_trace.csv"
    rows = read_csv(CONTROL_CSV / "initial_access_lifecycle_trace.csv")
    points: list[dict[str, str]] = []
    if rows:
        delays = []
        for row in rows:
            for col in ("ProcedureDelay_ms", "AccessDelay_ms", "Latency_ms", "Delay_ms", "Duration_ms"):
                val = fnum(row.get(col, ""))
                if math.isfinite(val):
                    delays.append(val)
                    break
        delays.sort()
        n = len(delays)
        points = [
            {"delay_ms": f"{delay:.9g}", "cdf_probability": f"{(i + 1) / n:.9g}", "source_artifact": source}
            for i, delay in enumerate(delays)
        ]
    if not points:
        source = "reports/csv/latency_cdf_plot.csv"
        latency_cdf = read_csv(REPORT_CSV / "latency_cdf_plot.csv")
        points = [
            {
                "delay_ms": row.get("latency_ms", ""),
                "cdf_probability": row.get("cdf_probability", ""),
                "source_artifact": source,
            }
            for row in latency_cdf
        ]
    body = "<div class='cards'>" + summary_cards(points) + "</div>"
    body += "<section class='panel'><h2>Access Delay CDF</h2>" + svg_points(points, "delay_ms", "cdf_probability", "source_artifact") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows if rows else points) + "</section>"
    write_page("access_delay_cdf.html", "Access Delay CDF", body, source)


def build_harq_combining_gain() -> None:
    rows = read_csv(AIR_CSV / "harq_combining_gain.csv")
    values = {}
    if rows:
        row = rows[0]
        values = {
            "CombiningApplied": fnum(row.get("CombiningAppliedCount", "")),
            "RecoveredByCombining": fnum(row.get("CombinedRecoveryCount", "")),
            "MeanGain_dB": fnum(row.get("MeanLLRCombiningGain_dB", row.get("CombiningGain_dB", ""))),
            "RetxAttempts": fnum(row.get("RetransmissionAttempts", "")),
        }
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>HARQ Combining Evidence</h2>" + svg_bar(values) + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("harq_combining_gain.html", "HARQ Combining Gain", body, "air_interface/csv/harq_combining_gain.csv")


def build_trs_tracking_error() -> None:
    rows = read_csv(REPORT_CSV / "trs_doppler_error_trace.csv")
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>Doppler Error vs Slot</h2>" + svg_points(rows, "Slot", "DopplerError_Hz", "UEIndex") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("trs_tracking_error.html", "TRS Tracking Error", body, "reports/csv/trs_doppler_error_trace.csv")


def build_ul_beam_accuracy() -> None:
    rows = [r for r in read_csv(REPORT_CSV / "per_ue_slot_kpi_table.csv") if str(r.get("Direction", "")).upper() == "UL"]
    hit_count = 0
    comparable = 0
    for row in rows:
        selected = fnum(row.get("SelectedBeamIndex", ""))
        best = fnum(row.get("BestBeamIndex", ""))
        if math.isfinite(selected) and math.isfinite(best):
            comparable += 1
            hit_count += int(selected == best)
    body = "<div class='cards'>"
    body += card("UL Rows", str(len(rows)), "per_ue_slot_kpi_table.csv")
    body += card("Comparable Beam Rows", str(comparable), "selected and best beam finite")
    body += card("Beam Hits", str(hit_count), "selected beam equals best beam")
    body += "</div>"
    body += "<section class='panel'><h2>Beam Gain Gap vs Slot</h2>" + svg_points(rows, "Slot", "BeamGainGap_dB", "UEIndex") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("ul_beam_accuracy.html", "UL Beam Accuracy", body, "reports/csv/per_ue_slot_kpi_table.csv")


def build_shannon_gap() -> None:
    rows = read_csv(REPORT_CSV / "shannon_capacity_gap.csv")
    values = {}
    if rows:
        values = {
            "Capacity_Mbps": fnum(rows[0].get("ShannonCapacity_Mbps", "")),
            "Goodput_Mbps": fnum(rows[0].get("AchievedGoodput_Mbps", "")),
            "Gap_Mbps": fnum(rows[0].get("Gap_Mbps", "")),
        }
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>Reference Capacity Gap</h2>" + svg_bar(values, " Mbps") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("shannon_gap.html", "Shannon Capacity Gap", body, "reports/csv/shannon_capacity_gap.csv")


def build_tbs_mismatch() -> None:
    rows = read_csv(REPORT_CSV / "tbs_reference_comparison.csv")
    deltas = [abs(fnum(r.get("RateMatchedBits_Delta", ""))) for r in rows]
    finite_deltas = finite(deltas)
    body = "<div class='cards'>"
    body += card("Rows", str(len(rows)), "tbs_reference_comparison.csv")
    body += card("Finite RM Deltas", str(len(finite_deltas)), "Rate-matched reference only")
    body += card("Max Abs RM Delta", f"{max(finite_deltas):.4g}" if finite_deltas else "", "bits")
    body += "</div>"
    body += "<section class='panel'><h2>Rate-Matched Bits Delta vs Slot</h2>" + svg_points(rows, "Slot", "RateMatchedBits_Delta", "Direction") + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("tbs_mismatch.html", "TBS / Rate-Matching Reference", body, "reports/csv/tbs_reference_comparison.csv")


def build_pdcch_detection_vs_snr() -> None:
    pdcch = read_csv(CONTROL_CSV / "pdcch_trials.csv")
    control = [r for r in read_csv(REPORT_CSV / "control_plane_timeline.csv") if str(r.get("EventType", "")).upper() == "PDCCH"]
    rows = pdcch if pdcch else control
    pass_count = sum(str(r.get("CRCPass", r.get("Status", ""))).strip().lower() in {"1", "true", "pass"} for r in rows)
    body = "<div class='cards'>"
    body += card("Rows", str(len(rows)), "PDCCH source rows")
    body += card("Pass-Like Rows", str(pass_count), "based on CRCPass/Status")
    body += "</div>"
    body += "<section class='panel'><h2>PDCCH Evidence Rows</h2>" + table_html(rows) + "</section>"
    write_page("pdcch_detection_vs_snr.html", "PDCCH Detection Evidence", body, "pdcch_trials.csv or control_plane_timeline.csv")


def build_rank_distribution() -> None:
    rows = read_csv(REPORT_CSV / "per_ue_slot_kpi_table.csv")
    counter: Counter[str] = Counter()
    for row in rows:
        direction = row.get("Direction", "")
        rank = row.get("Layers", "")
        if rank != "":
            counter[f"{direction} rank {rank}"] += 1
    body = "<div class='cards'>" + summary_cards(rows) + "</div>"
    body += "<section class='panel'><h2>Rank Distribution</h2>" + svg_bar({k: float(v) for k, v in counter.items()}) + "</section>"
    body += "<section class='panel'><h2>Source Rows</h2>" + table_html(rows) + "</section>"
    write_page("rank_distribution.html", "Rank Distribution", body, "reports/csv/per_ue_slot_kpi_table.csv")


def build_physics_audit() -> None:
    rows = read_csv(REPORT_CSV / "physics_audit_table.csv")
    status_counts = Counter(r.get("Status", "") for r in rows)
    body = "<div class='cards'>"
    body += card("Rows", str(len(rows)), "physics_audit_table.csv")
    for status, count in sorted(status_counts.items()):
        body += card(f"Status {status or 'blank'}", str(count), "physics audit rows")
    body += "</div>"
    body += "<section class='panel'><h2>Physics Audit Rows</h2>" + table_html(rows, 200) + "</section>"
    write_page("physics_audit.html", "Physics Audit", body, "reports/csv/physics_audit_table.csv")


def build_nvar_calibration() -> None:
    physics = read_csv(REPORT_CSV / "full_physics_timeline.csv")
    values = [fnum(r.get("NoiseVariance", "")) for r in physics]
    finite_values = finite(values)
    rows = [{"Metric": "FiniteNoiseVarianceRows", "Value": str(len(finite_values))}]
    if finite_values:
        rows.append({"Metric": "MeanNoiseVariance", "Value": f"{mean(finite_values):.6g}"})
        rows.append({"Metric": "MinNoiseVariance", "Value": f"{min(finite_values):.6g}"})
        rows.append({"Metric": "MaxNoiseVariance", "Value": f"{max(finite_values):.6g}"})
    body = "<div class='cards'>" + card("Finite nVar Rows", str(len(finite_values)), "from full_physics_timeline.csv") + "</div>"
    body += "<section class='panel'><h2>Noise Variance Calibration Summary</h2>" + table_html(rows) + "</section>"
    body += "<section class='panel'><h2>Physics Timeline Rows</h2>" + table_html(physics) + "</section>"
    write_page("nvar_calibration.html", "Noise Variance Calibration", body, "reports/csv/full_physics_timeline.csv")


def assemble_dashboard() -> None:
    tab_files = [
        ("Overview", "kpi_overview.html"),
        ("Call Flow Gantt", "call_flow_gantt.html"),
        ("Call Sunburst", "call_flow_sunburst.html"),
        ("Call Flame", "call_flow_flamegraph.html"),
        ("Messages", "message_sequence_diagram.html"),
        ("Algorithms", "algorithm_analysis_dashboard.html"),
        ("BLER vs Measured SINR", "bler_vs_measured_sinr.html"),
        ("Throughput vs Measured SINR", "throughput_vs_measured_sinr.html"),
        ("NMSE vs Measured SINR", "nmse_vs_measured_sinr.html"),
        ("Energy", "energy_vs_throughput.html"),
        ("Access Delay", "access_delay_cdf.html"),
        ("HARQ Gain", "harq_combining_gain.html"),
        ("TRS Tracking", "trs_tracking_error.html"),
        ("UL Beams", "ul_beam_accuracy.html"),
        ("Shannon Gap", "shannon_gap.html"),
        ("TBS Validation", "tbs_mismatch.html"),
        ("PDCCH", "pdcch_detection_vs_snr.html"),
        ("Rank Dist", "rank_distribution.html"),
        ("Physics Audit", "physics_audit.html"),
        ("nVar Calibration", "nvar_calibration.html"),
    ]
    available = [(name, file) for name, file in tab_files if (HTML_DIR / file).exists()]
    buttons = []
    panes = []
    for i, (name, file) in enumerate(available):
        active = " active" if i == 0 else ""
        buttons.append(f"<button class='tab{active}' data-target='{esc(file)}'>{esc(name)}</button>")
        panes.append(f"<section id='{esc(file)}' class='pane{active}'><iframe src='{esc(file)}' title='{esc(name)}'></iframe></section>")
    if not available:
        panes.append("<section class='pane active'><p>No HTML analysis pages were generated.</p></section>")
    out = HTML_DIR / "master_dashboard.html"
    out.write_text(
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>6GR Simulator v2 - Master Analysis Dashboard</title>"
        "<style>"
        "body{margin:0;background:#edf2f7;color:#162033;font-family:Segoe UI,Arial,sans-serif}"
        "header{padding:18px 24px;background:#102a43;color:white}"
        "h1{font-size:22px;margin:0}.sub{font-size:12px;opacity:.8;margin-top:4px}"
        "nav{display:flex;flex-wrap:wrap;gap:4px;padding:8px 14px;background:#1f3b57}"
        ".tab{border:0;border-radius:6px;padding:7px 11px;background:transparent;color:#d9e8f6;cursor:pointer;font-size:12px}"
        ".tab.active{background:white;color:#102a43;font-weight:700}"
        ".pane{display:none;padding:10px}.pane.active{display:block}"
        "iframe{width:100%;height:calc(100vh - 132px);border:1px solid #cbd5e1;border-radius:10px;background:white}"
        "</style></head><body>"
        "<header><h1>6GR Simulator v2 - Master Analysis Dashboard</h1>"
        f"<div class='sub'>Run: {esc(RUN_DIR)} | Tabs generated from available CSV/HTML artifacts only</div></header>"
        "<nav>" + "".join(buttons) + "</nav>" + "".join(panes) +
        "<script>"
        "document.querySelectorAll('.tab').forEach(btn=>btn.addEventListener('click',()=>{"
        "document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));"
        "document.querySelectorAll('.pane').forEach(x=>x.classList.remove('active'));"
        "btn.classList.add('active');"
        "document.getElementById(btn.dataset.target).classList.add('active');"
        "}));"
        "</script></body></html>",
        encoding="utf-8",
    )
    print(f"  [OK] master_dashboard.html - {len(available)} tabs assembled")


def main() -> int:
    HTML_DIR.mkdir(parents=True, exist_ok=True)
    build_overview()
    build_bler_vs_measured_sinr()
    build_throughput_vs_measured_sinr()
    build_nmse_vs_measured_sinr()
    build_energy_vs_throughput()
    build_access_delay_cdf()
    build_harq_combining_gain()
    build_trs_tracking_error()
    build_ul_beam_accuracy()
    build_shannon_gap()
    build_tbs_mismatch()
    build_pdcch_detection_vs_snr()
    build_rank_distribution()
    build_physics_audit()
    build_nvar_calibration()
    assemble_dashboard()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
