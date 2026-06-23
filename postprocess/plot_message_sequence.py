#!/usr/bin/env python3
"""Generate a simple message sequence HTML from live or derived control rows."""
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


def write_html(path: Path, title: str, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "<html><head><meta charset='utf-8'><title>" + html.escape(title) + "</title>"
        "<style>body{font-family:Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}"
        "td,th{border:1px solid #ddd;padding:6px;font-size:12px}th{background:#f2f2f2}</style></head><body>" + body + "</body></html>",
        encoding="utf-8",
    )


def main() -> int:
    run_dir = Path(sys.argv[1])
    out = run_dir / "reports" / "html" / "message_sequence_diagram.html"
    live = read_csv(run_dir / "reports" / "csv" / "message_sequence_trace.csv")
    derived = read_csv(run_dir / "reports" / "csv" / "control_plane_timeline.csv")
    rows = live if live else derived
    source = "message_sequence_trace.csv" if live else "control_plane_timeline.csv"
    if not rows:
        write_html(out, "Message Sequence Unavailable", "<h1>Message Sequence Unavailable</h1><p>No live or derived message rows found.</p>")
        return 0
    body = [f"<h1>Message Sequence</h1><p>Source: {html.escape(source)}. {'Direct runtime trace' if live else 'Derived post-run control timeline'}.</p>",
            "<table><tr><th>Index</th><th>Frame</th><th>Slot</th><th>Source</th><th>Destination</th><th>Type/Event</th><th>UE</th><th>RNTI</th><th>Status</th></tr>"]
    for i, row in enumerate(rows[:1000], 1):
        body.append(
            "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>".format(
                i,
                html.escape(row.get("Frame", "")),
                html.escape(row.get("Slot", "")),
                html.escape(row.get("SourceEntity", row.get("Direction", ""))),
                html.escape(row.get("DestinationEntity", "")),
                html.escape(row.get("MessageType", row.get("EventType", ""))),
                html.escape(row.get("UEIndex", row.get("UEId", ""))),
                html.escape(row.get("RNTI", "")),
                html.escape(row.get("Status", "")),
            )
        )
    body.append("</table>")
    write_html(out, "Message Sequence", "\n".join(body))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
