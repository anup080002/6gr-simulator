#!/usr/bin/env python3
"""Generate an algorithm-analysis HTML summary from live or derived CSVs."""
from __future__ import annotations

import csv
import html
import sys
from pathlib import Path


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def table_html(title: str, rows: list[dict[str, str]], max_rows: int = 100) -> str:
    if not rows:
        return f"<h2>{html.escape(title)}</h2><p>No rows.</p>"
    cols = list(rows[0].keys())[:12]
    out = [f"<h2>{html.escape(title)}</h2><table><tr>"]
    out.extend(f"<th>{html.escape(c)}</th>" for c in cols)
    out.append("</tr>")
    for row in rows[:max_rows]:
        out.append("<tr>" + "".join(f"<td>{html.escape(str(row.get(c,'')))}</td>" for c in cols) + "</tr>")
    out.append("</table>")
    return "\n".join(out)


def write_html(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "<html><head><meta charset='utf-8'><title>Algorithm Analysis</title>"
        "<style>body{font-family:Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%;margin-bottom:24px}"
        "td,th{border:1px solid #ddd;padding:6px;font-size:12px}th{background:#f2f2f2}</style></head><body>" + body + "</body></html>",
        encoding="utf-8",
    )


def main() -> int:
    run_dir = Path(sys.argv[1])
    csv_dir = run_dir / "reports" / "csv"
    live = read_csv(csv_dir / "algorithm_audit_trace.csv")
    tbs = read_csv(csv_dir / "tbs_reference_comparison.csv")
    physics = read_csv(csv_dir / "physics_audit_table.csv")
    kpi = read_csv(csv_dir / "per_slot_kpi_table.csv")
    body = ["<h1>Algorithm Analysis Dashboard</h1>"]
    body.append("<p>Rows are direct only when algorithm_audit_trace.csv exists; otherwise this page uses derived analysis tables.</p>")
    body.append(table_html("Live Algorithm Audit Trace", live))
    body.append(table_html("TBS / Rate-Matched Evidence", tbs))
    body.append(table_html("Physics Equations", physics))
    body.append(table_html("Per-Slot KPI Decisions", kpi))
    write_html(run_dir / "reports" / "html" / "algorithm_analysis_dashboard.html", "\n".join(body))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
