#!/usr/bin/env python3
"""Generate call-flow HTML from live call_flow_trace or profiler fallback."""
from __future__ import annotations

import csv
import html
import sys
from pathlib import Path


STAGE_COLORS = {
    "dl_pdsch_rx": "#1f77b4",
    "ul_pusch_rx": "#ff7f0e",
    "mimo_detection": "#2ca02c",
    "post_equalization_sinr": "#d62728",
    "rf_impairments": "#9467bd",
    "prach_detection": "#8c564b",
    "ldpc_decode": "#e377c2",
    "scheduler": "#98df8a",
    "export": "#ff9896",
    "default": "#c5b0d5",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def infer_stage(name: str) -> str:
    text = str(name).lower()
    if "pdsch_rx" in text:
        return "dl_pdsch_rx"
    if "pusch_rx" in text:
        return "ul_pusch_rx"
    if "mimodetect" in text:
        return "mimo_detection"
    if "posteq" in text or "post_equal" in text:
        return "post_equalization_sinr"
    if "impair" in text:
        return "rf_impairments"
    if "prach" in text:
        return "prach_detection"
    if "ldpc" in text:
        return "ldpc_decode"
    if "sched" in text:
        return "scheduler"
    if "export" in text or "build" in text:
        return "export"
    return "default"


def num(row: dict[str, str], *names: str, default: float = 0.0) -> float:
    for name in names:
        if name in row and str(row[name]).strip() != "":
            try:
                return float(row[name])
            except ValueError:
                pass
    return default


def load(run_dir: Path) -> tuple[list[dict[str, str]], str]:
    trace = run_dir / "reports" / "csv" / "call_flow_trace.csv"
    fallback = run_dir / "reports" / "csv" / "runtime_function_call_edges.csv"
    rows = read_csv(trace)
    if rows:
        for row in rows:
            row.setdefault("FunctionName", row.get("FunctionName", ""))
            row.setdefault("ElapsedTime_s", row.get("ElapsedTime_s", "0"))
            row.setdefault("EntryTime_s", row.get("EntryTime_s", "0"))
            row.setdefault("ExitTime_s", row.get("ExitTime_s", row.get("ElapsedTime_s", "0")))
            row.setdefault("Depth", row.get("Depth", "1"))
            row["Stage"] = row.get("Stage") or infer_stage(row.get("FunctionName", ""))
        return rows, "call_flow_trace.csv"
    rows = read_csv(fallback)
    for idx, row in enumerate(rows, 1):
        fname = row.get("CalleeFunctionName") or row.get("FunctionName") or row.get("Callee") or f"edge_{idx}"
        elapsed = row.get("TotalTime_s") or row.get("TotalTimeSeconds") or row.get("ElapsedTime_s") or "0"
        row["FunctionName"] = fname
        row["ElapsedTime_s"] = elapsed
        row["EntryTime_s"] = "0"
        row["ExitTime_s"] = elapsed
        row["Depth"] = str(min(idx, 10))
        row["Stage"] = infer_stage(fname)
    return rows, "runtime_function_call_edges.csv_fallback"


def write_html(path: Path, title: str, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "<html><head><meta charset='utf-8'><title>" + html.escape(title) + "</title>"
        "<style>body{font-family:Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}"
        "td,th{border:1px solid #ddd;padding:6px;font-size:12px}th{background:#f2f2f2}"
        ".bar{height:18px;color:white;padding-left:4px;white-space:nowrap}</style></head><body>" + body + "</body></html>",
        encoding="utf-8",
    )


def gantt(rows: list[dict[str, str]], source: str, out: Path) -> None:
    top = sorted(rows, key=lambda r: num(r, "ElapsedTime_s"), reverse=True)[:40]
    max_elapsed = max([num(r, "ElapsedTime_s") for r in top] + [1.0])
    lines = [f"<h1>Call Flow Gantt</h1><p>Source: {html.escape(source)}</p>"]
    for row in top:
        elapsed = num(row, "ElapsedTime_s")
        stage = row.get("Stage", "default")
        color = STAGE_COLORS.get(stage, STAGE_COLORS["default"])
        width = max(1, int(100 * elapsed / max_elapsed))
        lines.append(
            f"<div><b>{html.escape(row.get('FunctionName',''))}</b> "
            f"({elapsed:.3f}s, {html.escape(stage)})</div>"
            f"<div class='bar' style='width:{width}%;background:{color}'>{elapsed:.3f}s</div>"
        )
    write_html(out / "call_flow_gantt.html", "Call Flow Gantt", "\n".join(lines))


def sunburst(rows: list[dict[str, str]], source: str, out: Path) -> None:
    by_stage: dict[str, float] = {}
    for row in rows:
        by_stage[row.get("Stage", "default")] = by_stage.get(row.get("Stage", "default"), 0.0) + num(row, "ElapsedTime_s")
    body = [f"<h1>Call Flow Sunburst Substitute</h1><p>Source: {html.escape(source)}. Stage-level time breakdown.</p><table><tr><th>Stage</th><th>TotalTime_s</th></tr>"]
    for stage, total in sorted(by_stage.items(), key=lambda x: x[1], reverse=True):
        body.append(f"<tr><td>{html.escape(stage)}</td><td>{total:.6g}</td></tr>")
    body.append("</table>")
    write_html(out / "call_flow_sunburst.html", "Call Flow Sunburst", "\n".join(body))


def flame(rows: list[dict[str, str]], source: str, out: Path) -> None:
    top = sorted(rows, key=lambda r: (num(r, "Depth", default=1), -num(r, "ElapsedTime_s")))[:120]
    body = [f"<h1>Call Flow Flame Graph Substitute</h1><p>Source: {html.escape(source)}</p><table><tr><th>Depth</th><th>Function</th><th>ElapsedTime_s</th><th>Stage</th></tr>"]
    for row in top:
        body.append(f"<tr><td>{html.escape(str(row.get('Depth','')))}</td><td>{html.escape(row.get('FunctionName',''))}</td><td>{num(row,'ElapsedTime_s'):.6g}</td><td>{html.escape(row.get('Stage',''))}</td></tr>")
    body.append("</table>")
    write_html(out / "call_flow_flamegraph.html", "Call Flow Flame Graph", "\n".join(body))


def main() -> int:
    run_dir = Path(sys.argv[1])
    out = run_dir / "reports" / "html"
    rows, source = load(run_dir)
    if not rows:
        write_html(out / "call_flow_gantt.html", "Call Flow Unavailable", "<h1>Call Flow Unavailable</h1><p>No call_flow_trace.csv or runtime_function_call_edges.csv found.</p>")
        write_html(out / "call_flow_sunburst.html", "Call Flow Unavailable", "<h1>Call Flow Unavailable</h1>")
        write_html(out / "call_flow_flamegraph.html", "Call Flow Unavailable", "<h1>Call Flow Unavailable</h1>")
        return 0
    gantt(rows, source, out)
    sunburst(rows, source, out)
    flame(rows, source, out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
