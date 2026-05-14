from __future__ import annotations

import csv
import html
import io
import json
import math
import os
import re
from collections import Counter, defaultdict
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Callable

import lls_output_contract as output_contract
from lls_contract_aliases import (
    CONTRACT_CHART_ALIAS_PATHS,
    CONTRACT_TABLE_ALIAS_PATHS,
    OPTIONAL_6G_CHARTS,
    OPTIONAL_6G_TABLES,
)


MATERIALIZER_VERSION = "2026-04-22-contract-v15"
MAX_PREVIEW_ROWS = 180


def slugify(value: str) -> str:
    token = re.sub(r"[^a-z0-9]+", "-", str(value or "").strip().lower()).strip("-")
    return token or "contract"


def table_contract_path(table_spec: dict[str, Any]) -> str:
    return str(table_spec.get("logical_path") or "").strip()


def chart_contract_csv_path(chart_spec: dict[str, Any]) -> str:
    kind = str(chart_spec.get("kind") or "reports").strip().lower() or "reports"
    section_slug = str(chart_spec.get("section_slug") or "section").strip().lower() or "section"
    chart_slug = slugify(str(chart_spec.get("chart_name") or "chart"))
    return f"{kind}/csv/contract__{section_slug}__{chart_slug}.csv"


def chart_contract_image_path(chart_spec: dict[str, Any]) -> str:
    kind = str(chart_spec.get("kind") or "reports").strip().lower() or "reports"
    section_slug = str(chart_spec.get("section_slug") or "section").strip().lower() or "section"
    chart_slug = slugify(str(chart_spec.get("chart_name") or "chart"))
    return f"{kind}/image/contract__{section_slug}__{chart_slug}.svg"


def manifest_logical_path() -> str:
    return "reports/csv/contract_materialization_manifest.csv"


def coverage_logical_path() -> str:
    return "reports/csv/contract_materialization_coverage.csv"


def _decode_csv(data: bytes) -> tuple[list[str], list[list[str]]]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("utf-8", "ignore")
    rows = list(csv.reader(io.StringIO(text)))
    if not rows:
        return [], []
    return [str(item) for item in rows[0]], [[str(cell) for cell in row] for row in rows[1:]]


def _encode_csv(header: list[str], rows: list[list[Any]]) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(header)
    for row in rows:
        writer.writerow(list(row))
    return buf.getvalue().encode("utf-8")


def _coerce_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        number = float(value)
    except Exception:
        return None
    if not math.isfinite(number):
        return None
    return number


def _column_values(rows: list[list[str]], idx: int) -> list[str]:
    return [row[idx] if idx < len(row) else "" for row in rows]


def _numeric_columns(header: list[str], rows: list[list[str]]) -> list[tuple[int, str]]:
    out: list[tuple[int, str]] = []
    if not rows:
        return out
    for idx, name in enumerate(header):
        values = _column_values(rows, idx)
        numeric = [_coerce_float(value) for value in values]
        valid = [value for value in numeric if value is not None]
        if len(valid) >= max(3, len(values) // 5):
            out.append((idx, str(name)))
    return out


def _best_x_index(numeric_cols: list[tuple[int, str]]) -> int | None:
    for idx, name in numeric_cols:
        if re.search(r"(time|slot|frame|tti|trial|sample|index|step|ue|cell|beam|rank|cqi|mcs)", str(name), re.IGNORECASE):
            return idx
    return numeric_cols[0][0] if numeric_cols else None


def _column_variation_score(rows: list[list[str]], idx: int) -> tuple[int, int]:
    values = [_coerce_float(row[idx]) for row in rows if idx < len(row)]
    values = [value for value in values if value is not None]
    if not values:
        return (0, 0)
    unique_values = {round(float(value), 9) for value in values}
    return (len(unique_values), len(values))


def _preferred_generic_x_index(chart_name: str, header: list[str], rows: list[list[str]], numeric_cols: list[tuple[int, str]]) -> int | None:
    if not numeric_cols:
        return None
    chart = str(chart_name or "").lower()
    preferred_patterns = [
        (r"^time_s$", 0),
        (r"^sampleindex$", 1),
        (r"^slot_or_sample$", 2),
        (r"^slot$", 3),
        (r"^frame$", 4),
        (r"^tti$", 5),
        (r"^trial$", 6),
        (r"^ue_rank$|^percentile$", 7),
        (r"sample|time|slot|frame|trial|index", 8),
        (r"user|ue|cell|beam|rank", 20),
        (r"snr|sinr|rsrp|cqi|mcs", 40),
        (r"value|count", 80),
    ]
    ranked: list[tuple[int, int, int, int]] = []
    for idx, name in numeric_cols:
        token = str(name or "").strip().lower()
        if token in {"run_id", "source_row_count", "point_index"}:
            continue
        unique_count, total_count = _column_variation_score(rows, idx)
        if unique_count <= 1:
            continue
        pattern_rank = 99
        for pattern, rank in preferred_patterns:
            if re.search(pattern, token, re.IGNORECASE):
                pattern_rank = rank
                break
        ranked.append((pattern_rank, -unique_count, -total_count, idx))
    if ranked:
        ranked.sort()
        return ranked[0][3]
    return _best_x_index(numeric_cols)


def _score_column(chart_name: str, column_name: str) -> int:
    chart = str(chart_name or "").lower()
    col = str(column_name or "").lower()
    score = 0
    if col in chart or chart in col:
        score += 8
    keyword_groups = {
        "throughput": ("throughput", "goodput", "served", "rate"),
        "goodput": ("goodput", "throughput", "served"),
        "sinr": ("sinr", "snr", "rsrp", "quality"),
        "bler": ("bler", "ber", "fer", "crc", "error"),
        "queue": ("queue", "buffer", "hol", "delay"),
        "latency": ("latency", "delay", "tti", "compute"),
        "beam": ("beam", "pmi", "cri", "ri", "rank"),
        "power": ("power", "energy", "papr", "dbm"),
        "channel": ("channel", "nmse", "pathloss", "shadow", "doppler", "cfo", "timing"),
        "prach": ("prach", "peak", "noise", "preamble"),
        "control": ("aggregation", "cce", "dci", "decode", "control"),
        "resource": ("prb", "rb", "re", "symbol", "resource"),
    }
    for token, aliases in keyword_groups.items():
        if token in chart:
            for alias in aliases:
                if alias in col:
                    score += 4
    if any(alias in col for alias in re.findall(r"[a-z0-9]+", chart)):
        score += 1
    return score


def _dataset_from_rows(chart_name: str, header: list[str], rows: list[list[str]]) -> dict[str, Any] | None:
    lowered = [str(name or "").strip().lower() for name in header]
    if not rows or not header:
        return None
    if "metric" in lowered and ("meanvalue" in lowered or "value" in lowered):
        metric_idx = lowered.index("metric")
        value_idx = lowered.index("meanvalue") if "meanvalue" in lowered else lowered.index("value")
        direction_idx = lowered.index("direction") if "direction" in lowered else None
        named_values: list[tuple[str, float]] = []
        for row in rows[:64]:
            if metric_idx >= len(row) or value_idx >= len(row):
                continue
            metric_name = str(row[metric_idx] or "").strip()
            metric_val = _coerce_float(row[value_idx])
            if not metric_name or metric_val is None:
                continue
            direction = str(row[direction_idx] or "").strip() if direction_idx is not None and direction_idx < len(row) else ""
            label = f"{direction}:{metric_name}" if direction else metric_name
            named_values.append((label[:48], float(metric_val)))
        if named_values:
            dataset, summary = _bar_dataset_from_named_values("Metric bucket", header[value_idx], named_values[:18])
            dataset["tick_labels"] = [name for name, _value in named_values[:18]]
            dataset["summary_lines"] = summary
            return dataset
    if "metrickey" in lowered and ("value" in lowered or "valuenumeric" in lowered):
        key_idx = lowered.index("metricname") if "metricname" in lowered else lowered.index("metrickey")
        raw_key_idx = lowered.index("metrickey")
        value_idx = lowered.index("valuenumeric") if "valuenumeric" in lowered else lowered.index("value")
        entity_idx = lowered.index("entity") if "entity" in lowered else None
        stat_idx = lowered.index("statistic") if "statistic" in lowered else None
        availability_idx = lowered.index("availability") if "availability" in lowered else None
        named_values: list[tuple[str, float]] = []
        for row in rows[:96]:
            availability = str(row[availability_idx] or "").strip().lower() if availability_idx is not None and availability_idx < len(row) else ""
            if availability.startswith("not_") or availability in {"missing", "unavailable"}:
                continue
            key_name = str(row[key_idx] or "").strip() if key_idx < len(row) else ""
            raw_key = str(row[raw_key_idx] or "").strip() if raw_key_idx < len(row) else ""
            value = _coerce_float(row[value_idx] if value_idx < len(row) else "")
            if not key_name and raw_key:
                key_name = raw_key
            if not key_name or value is None:
                continue
            entity = str(row[entity_idx] or "").strip() if entity_idx is not None and entity_idx < len(row) else ""
            statistic = str(row[stat_idx] or "").strip() if stat_idx is not None and stat_idx < len(row) else ""
            label_parts = [part for part in (key_name, entity, statistic) if part]
            named_values.append(("/".join(label_parts)[:48], float(value)))
        if named_values:
            dataset, summary = _bar_dataset_from_named_values("Metric bucket", header[value_idx], named_values[:18])
            dataset["tick_labels"] = [name for name, _value in named_values[:18]]
            dataset["summary_lines"] = summary
            return dataset
    if "availability" in lowered and ("measuredrowcount" in lowered or "rowcount" in lowered):
        availability_idx = lowered.index("availability")
        value_idx = lowered.index("measuredrowcount") if "measuredrowcount" in lowered else lowered.index("rowcount")
        direction_idx = lowered.index("direction") if "direction" in lowered else None
        named_values: list[tuple[str, float]] = []
        for row in rows[:24]:
            availability = str(row[availability_idx] or "").strip() if availability_idx < len(row) else ""
            value = _coerce_float(row[value_idx] if value_idx < len(row) else "")
            if not availability or value is None:
                continue
            direction = str(row[direction_idx] or "").strip() if direction_idx is not None and direction_idx < len(row) else ""
            label = f"{direction}:{availability}" if direction else availability
            named_values.append((label[:48], float(value)))
        if named_values:
            dataset, summary = _bar_dataset_from_named_values("Availability bucket", header[value_idx], named_values[:18])
            dataset["tick_labels"] = [name for name, _value in named_values[:18]]
            dataset["summary_lines"] = summary
            return dataset
    numeric_cols = _numeric_columns(header, rows)
    if not numeric_cols:
        return None
    numeric_cols = [(idx, name) for idx, name in numeric_cols if str(name or "").strip().lower() not in {"run_id", "source_row_count", "point_index"}] or numeric_cols
    x_idx = _preferred_generic_x_index(chart_name, header, rows, numeric_cols)
    y_candidates = sorted(
        [item for item in numeric_cols if item[0] != x_idx and str(item[1] or "").strip().lower() not in {"run_id", "source_row_count", "point_index"}],
        key=lambda item: (_score_column(chart_name, item[1]), str(item[1])),
        reverse=True,
    )
    if not y_candidates:
        return None
    name_l = str(chart_name or "").lower()
    best_idx, best_name = y_candidates[0]
    values = [_coerce_float(row[best_idx] if best_idx < len(row) else "") for row in rows]
    values = [value for value in values if value is not None]
    if not values:
        return None
    if "cdf" in name_l:
        sorted_vals = sorted(values)
        points = [[value, (i + 1) / len(sorted_vals)] for i, value in enumerate(sorted_vals)]
        return {"mode": "cdf", "x_label": best_name, "y_label": "CDF", "points": points}
    if "hist" in name_l or "distribution" in name_l:
        bins = 10 if len(values) >= 10 else max(3, len(values))
        min_v = min(values)
        max_v = max(values)
        if math.isclose(min_v, max_v):
            points = [[min_v, len(values)]]
        else:
            width = (max_v - min_v) / max(bins, 1)
            counts = [0] * bins
            for value in values:
                idx = min(bins - 1, max(0, int((value - min_v) / max(width, 1e-12))))
                counts[idx] += 1
            points = [[min_v + width * (i + 0.5), counts[i]] for i in range(bins)]
        return {"mode": "bar", "x_label": best_name, "y_label": "Count", "points": points}
    x_values: list[float] = []
    y_values: list[float] = []
    for row_idx, row in enumerate(rows):
        y_val = _coerce_float(row[best_idx] if best_idx < len(row) else "")
        if y_val is None:
            continue
        if x_idx is None:
            x_val = float(row_idx + 1)
        else:
            x_val = _coerce_float(row[x_idx] if x_idx < len(row) else row_idx + 1)
            if x_val is None:
                x_val = float(row_idx + 1)
        x_values.append(float(x_val))
        y_values.append(float(y_val))
    if not x_values or not y_values:
        return None
    points = [[x, y] for x, y in zip(x_values[:MAX_PREVIEW_ROWS], y_values[:MAX_PREVIEW_ROWS])]
    return {
        "mode": "line",
        "x_label": header[x_idx] if x_idx is not None and x_idx < len(header) else "Index",
        "y_label": best_name,
        "points": points,
    }


def _downsample_points(points: list[list[float]], max_points: int = MAX_PREVIEW_ROWS) -> list[list[float]]:
    if len(points) <= max_points:
        return points
    step = max(1, math.ceil(len(points) / max_points))
    sampled = points[::step]
    if sampled and sampled[-1] != points[-1]:
        sampled.append(points[-1])
    return sampled[:max_points]


def _bin_mean_points(pairs: list[tuple[float, float]], max_bins: int = 18) -> list[list[float]]:
    filtered = [(float(x), float(y)) for x, y in pairs if math.isfinite(float(x)) and math.isfinite(float(y))]
    if not filtered:
        return []
    filtered.sort(key=lambda item: item[0])
    unique_x = sorted({round(item[0], 9) for item in filtered})
    if len(unique_x) <= max_bins:
        grouped: dict[float, list[float]] = defaultdict(list)
        for x_val, y_val in filtered:
            grouped[round(x_val, 9)].append(y_val)
        return [[float(x_val), sum(values) / max(len(values), 1)] for x_val, values in sorted(grouped.items())]
    min_x = min(item[0] for item in filtered)
    max_x = max(item[0] for item in filtered)
    if math.isclose(min_x, max_x):
        return [[min_x, sum(item[1] for item in filtered) / len(filtered)]]
    width = (max_x - min_x) / max(max_bins, 1)
    buckets: list[list[float]] = [[] for _ in range(max_bins)]
    for x_val, y_val in filtered:
        idx = min(max_bins - 1, max(0, int((x_val - min_x) / max(width, 1e-12))))
        buckets[idx].append(y_val)
    points: list[list[float]] = []
    for idx, values in enumerate(buckets):
        if not values:
            continue
        center = min_x + width * (idx + 0.5)
        points.append([center, sum(values) / len(values)])
    return points


def _bar_dataset_from_named_values(
    x_label: str,
    y_label: str,
    named_values: list[tuple[str, float]],
) -> tuple[dict[str, Any], list[str]]:
    points = [[float(idx + 1), float(value)] for idx, (_name, value) in enumerate(named_values)]
    summary = [f"bucket_{idx + 1}={name}" for idx, (name, _value) in enumerate(named_values)]
    return {"mode": "bar", "x_label": x_label, "y_label": y_label, "points": points}, summary


def _render_multi_series_svg(
    title: str,
    subtitle: str,
    series: list[dict[str, Any]],
    summary_lines: list[str],
    *,
    x_label: str,
    y_label: str,
    mode: str = "line",
) -> bytes:
    width = 1180
    height = 700
    left = 78
    top = 92
    plot_w = 700
    plot_h = 420
    info_x = 820
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<text x="42" y="50" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="42" y="76" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(subtitle)}</text>',
        f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
        f'<rect x="{info_x}" y="{top}" width="316" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
    ]
    prepared: list[dict[str, Any]] = []
    palette = ["#0f766e", "#2563eb", "#dc2626", "#7c3aed", "#d97706", "#0891b2"]
    all_points: list[tuple[float, float]] = []
    for idx, item in enumerate(series):
        raw_points = [
            (float(point[0]), float(point[1]))
            for point in (item.get("points") or [])
            if isinstance(point, (list, tuple))
            and len(point) >= 2
            and _coerce_float(point[0]) is not None
            and _coerce_float(point[1]) is not None
        ]
        if not raw_points:
            continue
        sampled = _downsample_points([[x_val, y_val] for x_val, y_val in raw_points], MAX_PREVIEW_ROWS)
        sampled_pairs = [(float(point[0]), float(point[1])) for point in sampled]
        prepared.append(
            {
                "name": str(item.get("name") or f"Series {idx + 1}"),
                "color": str(item.get("color") or palette[idx % len(palette)]),
                "points": sampled_pairs,
            }
        )
        all_points.extend(sampled_pairs)
    if not prepared or not all_points:
        return _render_reason_svg(title, subtitle, summary_lines + ["No numeric multi-series rows were available for this chart."])
    xs = [point[0] for point in all_points]
    ys = [point[1] for point in all_points]
    min_x = min(xs)
    max_x = max(xs)
    min_y = min(ys)
    max_y = max(ys)
    if math.isclose(min_x, max_x):
        max_x = min_x + 1.0
    if math.isclose(min_y, max_y):
        max_y = min_y + 1.0
    axis_left = left + 54
    axis_bottom = top + plot_h - 42
    axis_top = top + 26
    axis_right = left + plot_w - 24
    parts.append(f'<line x1="{axis_left}" y1="{axis_bottom}" x2="{axis_right}" y2="{axis_bottom}" stroke="#94a3b8" stroke-width="1.2"/>')
    parts.append(f'<line x1="{axis_left}" y1="{axis_top}" x2="{axis_left}" y2="{axis_bottom}" stroke="#94a3b8" stroke-width="1.2"/>')
    for prepared_series in prepared:
        coords: list[tuple[float, float]] = []
        for x_val, y_val in prepared_series["points"]:
            x_px = axis_left + ((x_val - min_x) / (max_x - min_x)) * (axis_right - axis_left)
            y_px = axis_bottom - ((y_val - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
            coords.append((x_px, y_px))
        if mode == "scatter":
            for x_px, y_px in coords:
                parts.append(
                    f'<circle cx="{x_px:.2f}" cy="{y_px:.2f}" r="2.6" fill="{prepared_series["color"]}" fill-opacity="0.7" />'
                )
        else:
            poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in coords)
            parts.append(
                f'<polyline fill="none" stroke="{prepared_series["color"]}" stroke-width="2.2" points="{poly}"/>'
            )
            for x_px, y_px in coords[:: max(1, len(coords) // 16)]:
                parts.append(f'<circle cx="{x_px:.2f}" cy="{y_px:.2f}" r="2.6" fill="{prepared_series["color"]}" />')
    parts.append(
        f'<text x="{left + plot_w / 2:.1f}" y="{top + plot_h + 24}" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(x_label)}</text>'
    )
    parts.append(
        f'<text x="{left + 6}" y="{top + 14}" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(y_label)}</text>'
    )
    parts.append(f'<text x="{info_x + 18}" y="{top + 30}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Run Summary</text>')
    y_cursor = top + 58
    for line in summary_lines[:14]:
        parts.append(f'<text x="{info_x + 18}" y="{y_cursor}" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#334155">{html.escape(line)}</text>')
        y_cursor += 22
    y_cursor += 12
    for prepared_series in prepared[:8]:
        parts.append(f'<line x1="{info_x + 18}" y1="{y_cursor}" x2="{info_x + 36}" y2="{y_cursor}" stroke="{prepared_series["color"]}" stroke-width="3"/>')
        parts.append(f'<text x="{info_x + 46}" y="{y_cursor + 4}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">{html.escape(prepared_series["name"])}</text>')
        y_cursor += 22
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _render_svg_plot(title: str, subtitle: str, dataset: dict[str, Any] | None, summary_lines: list[str]) -> bytes:
    width = 1100
    height = 620
    left = 70
    top = 80
    plot_w = 660
    plot_h = 360
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<text x="40" y="46" font-family="Segoe UI,Arial,sans-serif" font-size="26" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="40" y="72" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(subtitle)}</text>',
        f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
    ]
    if dataset and dataset.get("points"):
        points = [[float(row[0]), float(row[1])] for row in dataset.get("points", []) if len(row) >= 2]
        xs = [row[0] for row in points]
        ys = [row[1] for row in points]
        min_x = min(xs)
        max_x = max(xs)
        min_y = min(ys)
        max_y = max(ys)
        if math.isclose(min_x, max_x):
            max_x = min_x + 1.0
        if math.isclose(min_y, max_y):
            max_y = min_y + 1.0
        parts.append(f'<line x1="{left + 45}" y1="{top + plot_h - 38}" x2="{left + plot_w - 24}" y2="{top + plot_h - 38}" stroke="#94a3b8" stroke-width="1.2"/>')
        parts.append(f'<line x1="{left + 45}" y1="{top + 24}" x2="{left + 45}" y2="{top + plot_h - 38}" stroke="#94a3b8" stroke-width="1.2"/>')
        if dataset.get("mode") == "bar":
            bar_w = max(8.0, (plot_w - 100) / max(len(points), 1) * 0.7)
            for idx, (x_val, y_val) in enumerate(points):
                x_px = left + 55 + idx * max(bar_w + 4, (plot_w - 100) / max(len(points), 1))
                y_px = top + plot_h - 38 - ((y_val - min_y) / (max_y - min_y)) * (plot_h - 80)
                parts.append(f'<rect x="{x_px:.1f}" y="{y_px:.1f}" width="{bar_w:.1f}" height="{(top + plot_h - 38 - y_px):.1f}" fill="#0f766e" opacity="0.88"/>')
                tick_labels = dataset.get("tick_labels") or []
                if idx < len(tick_labels):
                    label = str(tick_labels[idx])[:14]
                    parts.append(f'<text x="{x_px + bar_w/2:.1f}" y="{top + plot_h - 18}" text-anchor="middle" font-family="Consolas,Segoe UI Mono,monospace" font-size="10" fill="#475569">{html.escape(label)}</text>')
        elif dataset.get("mode") == "scatter":
            for x_val, y_val in points:
                x_px = left + 45 + ((x_val - min_x) / (max_x - min_x)) * (plot_w - 70)
                y_px = top + plot_h - 38 - ((y_val - min_y) / (max_y - min_y)) * (plot_h - 62)
                parts.append(f'<circle cx="{x_px:.1f}" cy="{y_px:.1f}" r="3.0" fill="#0f766e" fill-opacity="0.72"/>')
        else:
            coords = []
            for x_val, y_val in points:
                x_px = left + 45 + ((x_val - min_x) / (max_x - min_x)) * (plot_w - 70)
                y_px = top + plot_h - 38 - ((y_val - min_y) / (max_y - min_y)) * (plot_h - 62)
                coords.append((x_px, y_px))
            poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in coords)
            parts.append(f'<polyline fill="none" stroke="#0f766e" stroke-width="3" points="{poly}"/>')
            for x_px, y_px in coords[:: max(1, len(coords) // 24)]:
                parts.append(f'<circle cx="{x_px:.1f}" cy="{y_px:.1f}" r="3.5" fill="#0f766e"/>')
        parts.append(f'<text x="{left + plot_w / 2:.1f}" y="{top + plot_h + 18}" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(str(dataset.get("x_label") or "X"))}</text>')
        parts.append(f'<text x="{left - 10}" y="{top + 12}" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(str(dataset.get("y_label") or "Y"))}</text>')
    else:
        parts.append(f'<text x="{left + 45}" y="{top + 50}" font-family="Segoe UI,Arial,sans-serif" font-size="18" fill="#334155">No numeric series could be derived for this chart family.</text>')
    info_x = 780
    parts.append(f'<rect x="{info_x}" y="{top}" width="280" height="430" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>')
    parts.append(f'<text x="{info_x + 18}" y="{top + 32}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Run Summary</text>')
    y = top + 60
    for line in summary_lines[:16]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#334155">{html.escape(line)}</text>')
        y += 22
    extra_lines = dataset.get("summary_lines", []) if isinstance(dataset, dict) else []
    for line in extra_lines[: max(0, 16 - len(summary_lines))]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#334155">{html.escape(str(line))}</text>')
        y += 22
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _chart_dataset_csv(
    run_id: int,
    chart_name: str,
    dataset: dict[str, Any] | None,
    source_table_path: str,
    source_row_count: int,
    materialization_status: str,
    note: str,
) -> bytes:
    header = [
        "run_id",
        "chart_name",
        "chart_mode",
        "x_label",
        "y_label",
        "point_index",
        "x_value",
        "y_value",
        "source_table_logical_path",
        "source_row_count",
        "materialization_status",
        "lineage_note",
    ]
    rows: list[list[Any]] = []
    if dataset and dataset.get("points"):
        for idx, point in enumerate(dataset.get("points", []), start=1):
            x_val = point[0] if len(point) > 0 else ""
            y_val = point[1] if len(point) > 1 else ""
            rows.append(
                [
                    run_id,
                    chart_name,
                    str(dataset.get("mode") or ""),
                    str(dataset.get("x_label") or ""),
                    str(dataset.get("y_label") or ""),
                    idx,
                    x_val,
                    y_val,
                    source_table_path,
                    source_row_count,
                    materialization_status,
                    note,
                ]
            )
    else:
        rows.append(
            [
                run_id,
                chart_name,
                str(dataset.get("mode") or "unavailable_reason_summary") if isinstance(dataset, dict) else "unavailable_reason_summary",
                str(dataset.get("x_label") or "not_available") if isinstance(dataset, dict) else "not_available",
                str(dataset.get("y_label") or "not_available") if isinstance(dataset, dict) else "not_available",
                0,
                "not_available",
                "not_available",
                source_table_path or "not_published_by_runtime",
                source_row_count,
                materialization_status,
                note,
            ]
        )
    return _encode_csv(header, rows)


def _decode_csv_dicts(data: bytes) -> tuple[list[str], list[dict[str, str]]]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("utf-8", "ignore")
    reader = csv.DictReader(io.StringIO(text))
    rows = [{str(k): str(v) for k, v in row.items()} for row in reader]
    return list(reader.fieldnames or []), rows


def _scope_token_for_logical_path(logical_path: str) -> str:
    token = str(logical_path or "").strip().lower()
    mapping = {
        "air_interface/csv/pdcch_trials.csv": "pdcch",
        "air_interface/csv/pbch_trials.csv": "pbch",
        "air_interface/csv/prach_trials.csv": "prach",
        "air_interface/csv/pucch_trials.csv": "pucch",
        "air_interface/csv/srs_trials.csv": "srs",
        "air_interface/csv/trs_trials.csv": "trs",
        "air_interface/csv/dl_pdsch_trials.csv": "dl_pdsch_trials",
        "air_interface/csv/ul_pusch_trials.csv": "ul_pusch_trials",
        "reports/csv/live_modulation_demodulation_trace.csv": "modulation_demodulation",
        "reports/csv/live_channel_estimation_tti.csv": "channel_estimation",
        "reports/csv/live_channel_state_tti.csv": "channel_state",
        "reports/csv/live_tx_rx_stage_trace.csv": "tx_rx_stage_trace",
    }
    if token in mapping:
        return mapping[token]
    basename = Path(token).name
    generic_patterns = [
        (r"pdcch", "pdcch"),
        (r"(pbch|ssb|sync_signal)", "pbch"),
        (r"prach", "prach"),
        (r"pucch", "pucch"),
        (r"csi[_-]?rs|csirs", "csirs"),
        (r"\bsrs\b", "srs"),
        (r"\btrs\b|receiver_tracking", "trs"),
        (r"pdsch|dl_scheduler|scheduler_cycle|queue|buffer|hol_delay|mac_ce|bsr|qos", "dl_pdsch_trials"),
        (r"pusch|ul_scheduler|llr|decoder", "ul_pusch_trials"),
        (r"rf_|power_|energy_|sleep_state|bb_power", "rf_runtime"),
        (r"beam|precoder|mimo", "beam_runtime"),
        (r"channel|interference|measurement|link_adaptation", "channel_runtime"),
    ]
    for pattern, scope in generic_patterns:
        if re.search(pattern, basename):
            return scope
    if basename:
        cleaned = re.sub(r"[^a-z0-9]+", "_", basename.replace(".csv", "")).strip("_")
        if cleaned:
            return cleaned
    return "runtime"


def _nonblank_text(value: Any) -> bool:
    text = str(value or "").strip()
    return text not in {"", "NaN", "nan", "<missing>", "missing"}


def _semantic_companion_mask(rows: list[dict[str, str]], field_name: str) -> list[bool]:
    base = re.sub(r"(source|valuerole|valuestatus|nareason|definition)$", "", field_name.lower())
    if not base:
        return [False] * len(rows)
    masks: list[bool] = []
    for row in rows:
        present = False
        for candidate, raw_value in row.items():
            cand = str(candidate or "").lower()
            if cand == field_name.lower():
                continue
            if cand != base and not cand.startswith(base):
                continue
            if re.search(r"(source|valuerole|valuestatus|nareason|definition)$", cand):
                continue
            if _nonblank_text(raw_value):
                present = True
                break
        masks.append(present)
    return masks


def _semantic_fill_value(field_name: str, scope_token: str, companion_present: bool) -> str:
    field = field_name.lower()
    scope = scope_token or "runtime"
    direct_string_fields = {
        "mcs",
        "fixedmcsindex",
        "prbs",
        "layers",
        "targetcoderate",
        "tbsize_bits",
        "tbsizebits",
        "decoderiterations",
        "evm_rms",
        "nmse_db",
        "measuredsinr_db",
        "receiverhestsinr_db",
        "decodertruthproxysinr_db",
        "widebandcqi",
        "cqiderivedmcs",
        "cqiderivedtargetcoderate",
        "rankindicator",
        "pmi",
        "cri",
        "meancri",
        "csipayloadbitlength",
        "precodingnumports",
        "precodingnumlayers",
        "precodingmatrixrows",
        "precodingmatrixcols",
        "falsealarmflag",
        "blockingflag",
        "blinddecodecount",
        "availableccecount",
        "usedccecount",
        "nonoverlappedcceusage",
        "aggregationlevel",
        "dcisize_bits",
        "dcisizebits",
        "controlcapacitybits",
        "controlcapacityutilization",
        "coresetutilization",
        "controllatency_ms",
        "configuredcri",
        "proceduredelay_ms",
        "airinterfaceobservation_ms",
        "latency_ms",
        "estimatedcfo_precorrection_hz",
        "residualcfo_postcorrection_hz",
        "estimatedcfo_hz",
        "cfoerror_hz",
        "acquisitiontime_ms",
        "trackingfailureprobability",
        "airinterfacetti_ms",
        "modulation",
        "cqiderivedmodulation",
        "linkadaptationmode",
        "configuredlinkadaptationmode",
        "actualmcsselectionmode",
        "configuredmcsselectionpolicy",
        "schedulergrantmcsselectionmode",
        "requestedoperatingpointsource",
        "cqitable",
        "mcstable",
        "pmitype",
        "pmicodebookmode",
        "csireportmode",
        "csipayloadhex",
        "configuredbeamselectionstrategy",
        "precodersource",
        "precodingmode",
        "precodingapplicationstage",
        "appliedbeamindexset",
        "appliedprecoderpmitype",
        "appliedprecodercodebookmode",
        "requestedvsappliedprecoderpmimatchstatus",
        "iqimbalancemodel",
        "iqimbalancemeasurementsource",
        "iqimbalancemeasurementstatus",
        "trackingestimatesource",
        "measuredtrialsinrsource",
        "largescalesinrsource",
        "servingrsrpsource",
        "csi_rsrpsource",
        "appliedlargescalegainsource",
        "interferencemode",
        "interfererprecodersourceset",
        "interfererprecodingmodeset",
        "interfererbeamindexsetsummary",
        "mcsauthority",
        "modulationauthority",
        "grantoperatingpointsource",
        "appliedoperatingpointsource",
        "trsreceiverintegrationstatus",
        "trsreceiverintegrationblocker",
        "trsstatesource",
        "trsruntimeconsumer",
        "trsupdateoutcome",
        "trsruntimeevidencesource",
        "trsvaliditystate",
        "trsreceiverconsumertype",
        "trstrackingstatebefore",
        "trstrackingstateafter",
        "trschanneltrackingfreshnessstate",
        "trsfrequencytrackingstate",
        "trstimingtrackingstate",
        "cfoestimateavailability",
        "grantcontextid",
        "grantsharedstatecommitmode",
        "interferencepowersource",
        "nareason",
        "unavailablereason",
    }
    if field.endswith("source"):
        return f"active_{scope}_runtime_table" if companion_present else f"not_emitted_by_active_{scope}_runtime"
    if field.endswith("valuerole"):
        return "runtime_observation" if companion_present else "not_available"
    if field.endswith("valuestatus"):
        return "available" if companion_present else f"not_emitted_by_active_{scope}_runtime"
    if field.endswith("nareason") or field == "nareason" or field == "unavailablereason":
        return "not_required_when_metric_present" if companion_present else f"field_not_emitted_by_active_{scope}_runtime"
    if field.endswith("definition"):
        return f"derived_from_active_{scope}_runtime_table" if companion_present else f"not_emitted_by_active_{scope}_runtime"
    if "blocker" in field:
        return f"not_blocked_in_active_{scope}_runtime"
    if "limitation" in field:
        return f"no_additional_{scope}_limitation_recorded"
    if (
        field in direct_string_fields
        or "beam" in field
        or "precoder" in field
        or "interferer" in field
        or "antenna" in field
        or "channelarray" in field
        or "geometryadapter" in field
        or "authority" in field
        or "interference" in field
    ):
        return f"not_recorded_by_active_{scope}_runtime"
    return ""


def _fill_numeric_text_companions(dict_rows: list[dict[str, str]], header: list[str]) -> None:
    header_lookup = {str(col).lower(): str(col) for col in header}
    companion_pairs = [
        ("value", "textvalue"),
        ("valuenumeric", "valuetext"),
        ("metric_value", "metric_text"),
    ]
    for numeric_key, text_key in companion_pairs:
        numeric_col = header_lookup.get(numeric_key)
        text_col = header_lookup.get(text_key)
        if not numeric_col or not text_col:
            continue
        for row in dict_rows:
            text_value = str(row.get(text_col, "") or "").strip()
            numeric_value = str(row.get(numeric_col, "") or "").strip()
            if text_value not in {"", "NaN", "nan", "<missing>", "missing"}:
                continue
            number = _coerce_float(numeric_value)
            if number is None:
                continue
            row[text_col] = numeric_value or f"{number:.12g}"


def _drop_all_blank_columns(header: list[str], rows: list[list[str]]) -> tuple[list[str], list[list[str]]]:
    if not header or not rows:
        return header, rows
    keep_indices: list[int] = []
    for idx, _name in enumerate(header):
        values = _column_values(rows, idx)
        if all(str(value or "").strip() in {"", "NaN", "nan", "<missing>", "missing"} for value in values):
            continue
        keep_indices.append(idx)
    if not keep_indices:
        return header, rows
    trimmed_header = [header[idx] for idx in keep_indices]
    trimmed_rows = [[row[idx] if idx < len(row) else "" for idx in keep_indices] for row in rows]
    return trimmed_header, trimmed_rows


def _canonicalize_contract_source_rows(logical_path: str, header: list[str], rows: list[list[str]]) -> tuple[bytes, list[str], list[list[str]]]:
    scope = _scope_token_for_logical_path(logical_path)
    if not header:
        return _encode_csv(header, rows), header, rows
    if not rows:
        trimmed_header, trimmed_rows = _drop_all_blank_columns(header, rows)
        return _encode_csv(trimmed_header, trimmed_rows), trimmed_header, trimmed_rows
    dict_rows = [{str(header[idx]): str(row[idx]) if idx < len(row) else "" for idx in range(len(header))} for row in rows]
    _fill_numeric_text_companions(dict_rows, header)
    for field_name in header:
        lower_name = str(field_name or "").lower()
        companion_mask = _semantic_companion_mask(dict_rows, lower_name)
        for row_idx, row in enumerate(dict_rows):
            current = str(row.get(field_name, "") or "").strip()
            if current not in {"", "NaN", "nan", "<missing>", "missing"}:
                continue
            fill_value = _semantic_fill_value(lower_name, scope, companion_mask[row_idx])
            if fill_value:
                row[field_name] = fill_value
    normalized_rows = [[row.get(col, "") for col in header] for row in dict_rows]
    trimmed_header, trimmed_rows = _drop_all_blank_columns(header, normalized_rows)
    return _encode_csv(trimmed_header, trimmed_rows), trimmed_header, trimmed_rows


def _row_float(row: dict[str, str], *names: str) -> float | None:
    for name in names:
        if name in row:
            value = _coerce_float(row.get(name))
            if value is not None:
                return value
    return None


def _percentile(sorted_vals: list[float], fraction: float) -> float:
    if not sorted_vals:
        return float("nan")
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    pos = max(0.0, min(1.0, float(fraction))) * (len(sorted_vals) - 1)
    low = int(math.floor(pos))
    high = int(math.ceil(pos))
    if low == high:
        return float(sorted_vals[low])
    weight = pos - low
    return float(sorted_vals[low] * (1.0 - weight) + sorted_vals[high] * weight)


def _row_text(row: dict[str, str], *names: str) -> str:
    for name in names:
        value = str(row.get(name) or "").strip()
        if value:
            return value
    return ""


def _row_flag(row: dict[str, str], *names: str) -> bool | None:
    truthy = {"1", "true", "pass", "passed", "ok", "success", "detected", "observed", "yes", "available"}
    falsy = {"0", "false", "fail", "failed", "error", "miss", "missed", "no", "unavailable", "not_detected"}
    for name in names:
        raw_value = row.get(name)
        if raw_value is None:
            continue
        text = str(raw_value).strip().lower()
        if not text or text in {"nan", "<missing>", "missing"}:
            continue
        if text in truthy:
            return True
        if text in falsy:
            return False
        number = _coerce_float(raw_value)
        if number is not None:
            return not math.isclose(float(number), 0.0)
    return None


def _parse_index_tokens(value: Any) -> list[int]:
    text = str(value or "").strip()
    if not text or text.lower() in {"nan", "<missing>", "missing"}:
        return []
    tokens = []
    for match in re.findall(r"-?\d+", text):
        try:
            tokens.append(int(match))
        except Exception:
            continue
    return tokens


def _render_reason_svg(title: str, subtitle: str, lines: list[str]) -> bytes:
    width = 1100
    height = 520
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        '<rect x="40" y="40" width="1020" height="440" rx="18" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
        f'<text x="72" y="96" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="72" y="126" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(subtitle)}</text>',
        '<text x="72" y="176" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#7c2d12">Unavailable Without Faking</text>',
    ]
    y = 214
    for line in lines[:12]:
        parts.append(
            f'<text x="72" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="14" fill="#334155">{html.escape(line)}</text>'
        )
        y += 28
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _heat_color(value: float, max_value: float) -> str:
    if max_value <= 0:
        return "#e2e8f0"
    ratio = max(0.0, min(1.0, value / max_value))
    r = int(230 - 170 * ratio)
    g = int(244 - 70 * ratio)
    b = int(255 - 165 * ratio)
    return f"rgb({r},{g},{b})"


def _render_heatmap_svg(
    title: str,
    subtitle: str,
    x_labels: list[str],
    y_labels: list[str],
    matrix: list[list[float]],
    summary_lines: list[str],
    x_axis_title: str,
    y_axis_title: str,
) -> bytes:
    width = 1180
    height = 760
    left = 90
    top = 96
    plot_w = 710
    plot_h = 560
    info_x = 840
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<text x="44" y="50" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="44" y="76" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(subtitle)}</text>',
        f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
        f'<rect x="{info_x}" y="{top}" width="300" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
    ]
    if not x_labels or not y_labels or not matrix:
        return _render_reason_svg(title, subtitle, summary_lines + ["No heatmap cells were derived from the persisted runtime source rows."])
    max_value = max((value for row in matrix for value in row), default=0.0)
    n_x = max(len(x_labels), 1)
    n_y = max(len(y_labels), 1)
    cell_w = (plot_w - 80) / n_x
    cell_h = (plot_h - 70) / n_y
    base_x = left + 56
    base_y = top + 24
    for y_idx, row in enumerate(matrix):
        for x_idx, value in enumerate(row):
            x = base_x + x_idx * cell_w
            y = base_y + y_idx * cell_h
            parts.append(
                f'<rect x="{x:.2f}" y="{y:.2f}" width="{cell_w + 0.2:.2f}" height="{cell_h + 0.2:.2f}" fill="{_heat_color(value, max_value)}" />'
            )
    parts.append(f'<text x="{left + plot_w / 2:.1f}" y="{top + plot_h + 28}" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(x_axis_title)}</text>')
    parts.append(f'<text x="{left + 8}" y="{top + 14}" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(y_axis_title)}</text>')
    x_tick_count = min(8, len(x_labels))
    for idx in range(x_tick_count):
        pos = round(idx * (len(x_labels) - 1) / max(x_tick_count - 1, 1))
        x = base_x + pos * cell_w + cell_w / 2
        parts.append(f'<text x="{x:.1f}" y="{top + plot_h + 10}" text-anchor="middle" font-family="Consolas,Segoe UI Mono,monospace" font-size="11" fill="#475569">{html.escape(str(x_labels[pos]))}</text>')
    y_tick_count = min(10, len(y_labels))
    for idx in range(y_tick_count):
        pos = round(idx * (len(y_labels) - 1) / max(y_tick_count - 1, 1))
        y = base_y + pos * cell_h + 4
        parts.append(f'<text x="{left + 46}" y="{y:.1f}" text-anchor="end" font-family="Consolas,Segoe UI Mono,monospace" font-size="11" fill="#475569">{html.escape(str(y_labels[pos]))}</text>')
    parts.append(f'<text x="{info_x + 18}" y="{top + 30}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Run Summary</text>')
    y = top + 60
    for line in summary_lines[:18]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#334155">{html.escape(line)}</text>')
        y += 22
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _render_scatter_panels_svg(
    title: str,
    subtitle: str,
    panels: list[tuple[str, list[tuple[float, float, str]], list[tuple[float, float]]]],
    summary_lines: list[str],
) -> bytes:
    width = 1180
    height = 760
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<text x="40" y="48" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="40" y="74" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(subtitle)}</text>',
    ]
    if not panels:
        return _render_reason_svg(title, subtitle, summary_lines + ["No constellation preview samples were available for this chart."])
    panel_w = 320
    panel_h = 250
    base_x = 44
    base_y = 110
    colors = {"DL": "#0f766e", "UL": "#1d4ed8"}
    for idx, (panel_title, points, ideal_points) in enumerate(panels[:3]):
        row = idx // 2
        col = idx % 2
        x0 = base_x + col * (panel_w + 28)
        y0 = base_y + row * (panel_h + 28)
        parts.append(f'<rect x="{x0}" y="{y0}" width="{panel_w}" height="{panel_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>')
        parts.append(f'<text x="{x0 + 16}" y="{y0 + 26}" font-family="Segoe UI,Arial,sans-serif" font-size="16" font-weight="700" fill="#0f172a">{html.escape(panel_title)}</text>')
        cx = x0 + panel_w / 2
        cy = y0 + panel_h / 2 + 12
        radius = 86
        parts.append(f'<line x1="{cx - radius}" y1="{cy}" x2="{cx + radius}" y2="{cy}" stroke="#94a3b8" stroke-width="1.1"/>')
        parts.append(f'<line x1="{cx}" y1="{cy - radius}" x2="{cx}" y2="{cy + radius}" stroke="#94a3b8" stroke-width="1.1"/>')
        for ix, iy in ideal_points[:64]:
            px = cx + ix * radius * 0.9
            py = cy - iy * radius * 0.9
            parts.append(f'<circle cx="{px:.2f}" cy="{py:.2f}" r="4.0" fill="#cbd5e1" />')
        for x_val, y_val, direction in points[:420]:
            px = cx + x_val * radius * 0.75
            py = cy - y_val * radius * 0.75
            color = colors.get(direction, "#475569")
            parts.append(f'<circle cx="{px:.2f}" cy="{py:.2f}" r="2.0" fill="{color}" fill-opacity="0.72" />')
    info_x = 740
    parts.append(f'<rect x="{info_x}" y="{base_y}" width="396" height="548" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>')
    parts.append(f'<text x="{info_x + 18}" y="{base_y + 30}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Run Summary</text>')
    y = base_y + 60
    for line in summary_lines[:20]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#334155">{html.escape(line)}</text>')
        y += 22
    parts.append(f'<circle cx="{info_x + 24}" cy="{y + 16}" r="5" fill="#0f766e"/><text x="{info_x + 38}" y="{y + 20}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">DL equalized symbols</text>')
    parts.append(f'<circle cx="{info_x + 24}" cy="{y + 42}" r="5" fill="#1d4ed8"/><text x="{info_x + 38}" y="{y + 46}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">UL equalized symbols</text>')
    parts.append(f'<circle cx="{info_x + 24}" cy="{y + 68}" r="5" fill="#cbd5e1"/><text x="{info_x + 38}" y="{y + 72}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">Ideal constellation points</text>')
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _summary_csv_rows(
    run_id: int,
    section_title: str,
    label_name: str,
    status: str,
    source_artifact: str,
    source_row_count: int,
    note: str,
) -> tuple[list[str], list[list[Any]]]:
    header = [
        "run_id",
        "section_title",
        "label_name",
        "contract_materialization_status",
        "source_artifact",
        "source_row_count",
        "lineage_note",
    ]
    rows = [[run_id, section_title, label_name, status, source_artifact or "not_published_by_runtime", source_row_count, note]]
    return header, rows


def _contract_artifact_paths() -> set[str]:
    paths = {manifest_logical_path(), coverage_logical_path()}
    for table_spec in _table_specs():
        target = table_contract_path(table_spec)
        if target:
            paths.add(target)
    for chart_spec in _chart_specs():
        paths.add(chart_contract_csv_path(chart_spec))
        paths.add(chart_contract_image_path(chart_spec))
    return paths


def _artifact_is_contract_owned(
    artifact: dict[str, Any] | None,
    db_connection_factory: Callable[[], Any],
) -> bool:
    if not artifact:
        return False
    logical_path = str(artifact.get("logical_path") or "").strip()
    if not logical_path:
        return False
    if logical_path in {manifest_logical_path(), coverage_logical_path()}:
        return True
    # All chart contract artifacts live in a dedicated contract__ namespace and
    # can be safely treated as materializer-owned even if their metadata is old.
    if "/contract__" in logical_path:
        return True
    payload = _artifact_metadata_json(artifact, db_connection_factory)
    if not payload:
        return False
    lower_payload = payload.lower()
    return (
        '"materializer_version"' in lower_payload
        or '"contract_table"' in lower_payload
        or '"chart_name"' in lower_payload
    )


def _contract_owned_paths(
    artifacts: list[dict[str, Any]],
    db_connection_factory: Callable[[], Any],
) -> set[str]:
    owned: set[str] = set()
    for artifact in artifacts:
        if _artifact_is_contract_owned(artifact, db_connection_factory):
            logical_path = str(artifact.get("logical_path") or "").strip()
            if logical_path:
                owned.add(logical_path)
    return owned


def _source_artifact_high_watermark(
    artifacts: list[dict[str, Any]],
    db_connection_factory: Callable[[], Any],
) -> int:
    contract_paths = _contract_owned_paths(artifacts, db_connection_factory)
    return max(
        (
            int(art.get("artifact_id") or 0)
            for art in artifacts
            if str(art.get("logical_path") or "") not in contract_paths
        ),
        default=0,
    )


def _specialized_table_materialization(
    table_name: str,
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
    section_title: str,
    run_row: dict[str, Any] | None = None,
    feature_policy: dict[str, bool] | None = None,
) -> dict[str, Any] | None:
    generic = _specialized_live_report_table(
        table_name,
        source_lookup,
        fetch_artifact_bytes,
        run_id,
        run_row,
        feature_policy,
    )
    if generic is not None:
        return generic
    if str(table_name or "").strip() == "fairness_analytics":
        source_path = ""
        for candidate in (
            "reports/csv/live_user_performance_snapshot.csv",
            "system/csv/system_ue_summary.csv",
            "system/summaries/system_kpi_summary.csv",
        ):
            if candidate in source_lookup:
                source_path = candidate
                break
        if not source_path:
            return None
        _, rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, source_path)
        if not rows:
            return None
        fairness_rows: list[dict[str, Any]] = []
        for metric_name, direction in (
            ("DL_Throughput_Mbps", "DL"),
            ("UL_Throughput_Mbps", "UL"),
            ("UserThroughput_Mbps", "Combined"),
        ):
            values: list[float] = []
            for row in rows:
                value = _row_float(row, metric_name)
                if value is not None and math.isfinite(value):
                    values.append(float(value))
            if not values:
                continue
            sorted_vals = sorted(values)
            count = len(sorted_vals)
            total = sum(sorted_vals)
            total_sq = sum(v * v for v in sorted_vals)
            fairness = (total * total) / (count * total_sq) if count > 0 and total_sq > 0 else 0.0
            fairness_rows.append({
                "run_id": run_id,
                "direction": direction,
                "metric_name": metric_name,
                "sample_count": count,
                "mean_mbps": total / count,
                "p05_mbps": _percentile(sorted_vals, 0.05),
                "p50_mbps": _percentile(sorted_vals, 0.50),
                "p95_mbps": _percentile(sorted_vals, 0.95),
                "min_mbps": sorted_vals[0],
                "max_mbps": sorted_vals[-1],
                "jain_fairness_index": fairness,
                "zero_throughput_user_count": sum(1 for value in sorted_vals if math.isclose(value, 0.0, abs_tol=1e-12)),
                "source_artifact": source_path,
            })
        if not fairness_rows:
            return None
        header = list(fairness_rows[0].keys())
        return {
            "data": _encode_dict_rows(header, fairness_rows),
            "status": "specialized_runtime_fairness_summary",
            "note": "Fairness analytics derived from truthful per-UE throughput evidence.",
            "source_logical_path": source_path,
            "source_row_count": len(rows),
        }
    match = re.fullmatch(r"live_pucch_f([0-4])_table", str(table_name or "").strip())
    if not match:
        return None
    target_format = match.group(1)
    source_path = "control/csv/pucch_table.csv" if "control/csv/pucch_table.csv" in source_lookup else ""
    if not source_path:
        return None
    header, rows = _decode_csv_dicts(fetch_artifact_bytes(int(source_lookup[source_path]["artifact_id"])))
    if not rows:
        summary_header, summary_rows = _summary_csv_rows(
            run_id,
            section_title,
            table_name,
            "source_artifact_present_but_empty",
            source_path,
            0,
            "The canonical PUCCH control table exists for this run, but it has no real rows.",
        )
        return {
            "data": _encode_csv(summary_header, summary_rows),
            "status": "empty_source_summary",
            "note": "Canonical contract table summarizes an empty PUCCH control source artifact.",
            "source_logical_path": source_path,
            "source_row_count": 0,
        }
    filtered_rows = [
        row for row in rows
        if _row_text(row, "ResolvedFormat", "RequestedFormat") == target_format
    ]
    if not filtered_rows:
        summary_header, summary_rows = _summary_csv_rows(
            run_id,
            section_title,
            table_name,
            "source_artifact_present_but_empty",
            source_path,
            0,
            f"No runtime PUCCH rows resolved to format {target_format} in this bounded run.",
        )
        return {
            "data": _encode_csv(summary_header, summary_rows),
            "status": "empty_source_summary",
            "note": f"Canonical contract table records that no PUCCH format {target_format} rows were observed for this run.",
            "source_logical_path": source_path,
            "source_row_count": 0,
        }
    encoded_rows = [[row.get(col, "") for col in header] for row in filtered_rows]
    return {
        "data": _encode_csv(header, encoded_rows),
        "status": "specialized_runtime_pucch_format_table",
        "note": f"Canonical contract table filtered the runtime PUCCH control rows to resolved format {target_format}.",
        "source_logical_path": source_path,
        "source_row_count": len(filtered_rows),
    }


def _artifact_rows_by_path(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    logical_path: str,
) -> tuple[list[str], list[dict[str, str]]]:
    art = existing.get(logical_path)
    if not art:
        return [], []
    return _decode_csv_dicts(fetch_artifact_bytes(int(art["artifact_id"])))


def _json_object(payload: Any) -> dict[str, Any]:
    if isinstance(payload, dict):
        return payload
    text = str(payload or "").strip()
    if not text:
        return {}
    try:
        decoded = json.loads(text)
    except Exception:
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _first_available_rows(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    candidates: list[str] | tuple[str, ...],
) -> tuple[str, list[dict[str, str]]]:
    for logical_path in candidates:
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, logical_path)
        if rows:
            return str(logical_path), rows
    return "", []


def _all_available_rows(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    candidates: list[str] | tuple[str, ...],
) -> list[tuple[str, list[dict[str, str]]]]:
    out: list[tuple[str, list[dict[str, str]]]] = []
    for logical_path in candidates:
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, logical_path)
        if rows:
            out.append((str(logical_path), rows))
    return out


def _count_trueish(rows: list[dict[str, str]], *names: str) -> int:
    true_tokens = {"1", "true", "yes", "ok", "pass", "passed", "succeeded", "success"}
    count = 0
    for row in rows:
        value = _row_text(row, *names).lower()
        if value in true_tokens:
            count += 1
    return count


def _count_nonempty(rows: list[dict[str, str]], *names: str) -> int:
    return sum(1 for row in rows if _row_text(row, *names))


def _mean_numeric(rows: list[dict[str, str]], *names: str) -> float | None:
    vals = [value for value in (_row_float(row, *names) for row in rows) if value is not None]
    if not vals:
        return None
    return float(sum(vals) / len(vals))


def _sum_numeric(rows: list[dict[str, str]], *names: str) -> float | None:
    vals = [value for value in (_row_float(row, *names) for row in rows) if value is not None]
    if not vals:
        return None
    return float(sum(vals))


def _distinct_join(rows: list[dict[str, str]], *names: str, limit: int = 8) -> str:
    seen: list[str] = []
    for row in rows:
        token = _row_text(row, *names)
        if token and token not in seen:
            seen.append(token)
        if len(seen) >= limit:
            break
    return "|".join(seen)


def _encode_rows_from_dicts(rows: list[dict[str, Any]]) -> bytes:
    if not rows:
        return _encode_csv([], [])
    header = list(rows[0].keys())
    return _encode_dict_rows(header, rows)


def _artifact_inventory_rows(
    source_lookup: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for art in sorted(source_lookup.values(), key=lambda item: int(item.get("artifact_id") or 0)):
        logical_path = str(art.get("logical_path") or "")
        rows.append(
            {
                "artifact_id": int(art.get("artifact_id") or 0),
                "logical_path": logical_path,
                "artifact_kind": str(art.get("artifact_kind") or ""),
                "mime_type": str(art.get("mime_type") or ""),
                "scope": logical_path.split("/", 1)[0] if "/" in logical_path else logical_path,
                "family": logical_path.split("/", 2)[1] if logical_path.count("/") >= 1 else "",
            }
        )
    return rows


def _table_source_health(
    table_name: str,
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for logical_path in _table_sources(table_name):
        _header, source_rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, logical_path)
        rows.append(
            {
                "contract_table": table_name,
                "source_logical_path": logical_path,
                "source_present": int(logical_path in source_lookup),
                "source_row_count": len(source_rows),
            }
        )
    return rows


def _table_placeholder_summary_status(rows: list[dict[str, str]]) -> str:
    if len(rows) != 1:
        return ""
    return _row_text(rows[0], "contract_materialization_status")


def _specialized_live_report_table(
    table_name: str,
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
    run_row: dict[str, Any] | None,
    feature_policy: dict[str, bool] | None,
) -> dict[str, Any] | None:
    run_row = dict(run_row or {})
    feature_policy = dict(feature_policy or {})
    status_payload = _json_object(run_row.get("status_json"))
    config_payload = _json_object(run_row.get("config_json"))
    raw_sources = {
        "dl_pdsch": "air_interface/csv/dl_pdsch_trials.csv",
        "ul_pusch": "air_interface/csv/ul_pusch_trials.csv",
        "pdcch": "air_interface/csv/pdcch_trials.csv",
        "pbch": "air_interface/csv/pbch_trials.csv",
        "prach": "air_interface/csv/prach_trials.csv",
        "pucch": "air_interface/csv/pucch_trials.csv",
        "srs": "air_interface/csv/srs_trials.csv",
        "trs": "air_interface/csv/trs_trials.csv",
    }
    raw_rows = {
        key: _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, logical_path)[1]
        for key, logical_path in raw_sources.items()
    }
    dl_grants = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/live_dl_scheduler_grants.csv")[1]
    ul_grants = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/live_ul_scheduler_grants.csv")[1]
    pucch_grants = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/live_pucch_grants.csv")[1]
    slot_trace = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/slot_trace.csv")[1]
    beam_probe = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "beamforming/csv/probe_beam_mimo.csv")[1]
    energy_rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "rf/csv/energy_timeline_trace.csv")[1]
    artifact_rows = _artifact_inventory_rows(source_lookup)

    if table_name == "live_run_overview":
        rows = [{
            "run_id": run_id,
            "run_uuid": str(run_row.get("run_uuid") or ""),
            "scenario_id": str(run_row.get("scenario_id") or ""),
            "run_tag": str(run_row.get("run_tag") or ""),
            "backend": str(run_row.get("backend") or ""),
            "profile_name": str(run_row.get("profile_name") or ""),
            "status_text": str(run_row.get("status_text") or ""),
            "stage": str(status_payload.get("stage") or ""),
            "current_direction": str(status_payload.get("current_direction") or ""),
            "current_frame": status_payload.get("current_frame", ""),
            "total_frames": status_payload.get("total_frames", ""),
            "current_slot": status_payload.get("current_slot", ""),
            "total_slots": status_payload.get("total_slots", ""),
            "run_completion": status_payload.get("run_completion", ""),
            "active_ue_count": status_payload.get("active_ue_count", ""),
            "total_users": status_payload.get("total_users", ""),
            "dl_trial_rows": status_payload.get("dl_trial_rows", len(raw_rows["dl_pdsch"])),
            "ul_trial_rows": status_payload.get("ul_trial_rows", len(raw_rows["ul_pusch"])),
            "notes": str(status_payload.get("notes") or ""),
            "source_artifact": "sim_runs.status_json",
        }]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_run_overview",
            "note": "Run overview derived from sim_runs metadata and live raw trial counters.",
            "source_logical_path": "sim_runs.status_json",
            "source_row_count": 1,
        }
    if table_name == "live_scenario_overview":
        scenario_cfg = _json_object(config_payload.get("scenario"))
        layout_cfg = _json_object(scenario_cfg.get("layout"))
        ue_cfg = _json_object(scenario_cfg.get("ue"))
        carrier_cfg = _json_object(config_payload.get("carrier"))
        run_cfg = _json_object(config_payload.get("run"))
        rows = [{
            "run_id": run_id,
            "scenario_id": str(run_row.get("scenario_id") or ""),
            "layout_type": str(layout_cfg.get("type") or ""),
            "num_sites": layout_cfg.get("nSites", ""),
            "sectors_per_site": layout_cfg.get("nSectorsPerSite", ""),
            "intersite_distance_m": layout_cfg.get("interSiteDistance_m", ""),
            "wrap_around": layout_cfg.get("wrapAround", ""),
            "configured_ue_count": ue_cfg.get("nUE", ""),
            "center_frequency_hz": carrier_cfg.get("centerFrequencyHz", ""),
            "bandwidth_hz": carrier_cfg.get("bandwidthHz", ""),
            "scs_khz": carrier_cfg.get("scsKHz", ""),
            "n_rb": carrier_cfg.get("nRB", ""),
            "duplex_mode": carrier_cfg.get("duplexMode", ""),
            "num_frames": run_cfg.get("numFrames", ""),
            "total_slots": run_cfg.get("totalSlots", ""),
            "strict_mode": run_cfg.get("strictMode", ""),
            "honesty_mode": run_cfg.get("honestyMode", ""),
            "source_artifact": "sim_runs.config_json",
        }]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_scenario_overview",
            "note": "Scenario overview derived from the resolved run configuration stored in sim_runs.",
            "source_logical_path": "sim_runs.config_json",
            "source_row_count": 1,
        }
    if table_name == "live_trial_overview":
        rows: list[dict[str, Any]] = []
        for family, logical_path in raw_sources.items():
            family_rows = raw_rows.get(family, [])
            if not family_rows:
                continue
            rows.append({
                "run_id": run_id,
                "trial_family": family,
                "source_artifact": logical_path,
                "observed_rows": len(family_rows),
                "success_count": _count_trueish(family_rows, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK", "Detected", "DetectedFlag"),
                "failure_count": len(family_rows) - _count_trueish(family_rows, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK", "Detected", "DetectedFlag"),
                "mean_measured_sinr_db": _mean_numeric(family_rows, "MeasuredSINR_dB", "ReceiverHestSINR_dB"),
                "mean_cqi": _mean_numeric(family_rows, "WidebandCQI"),
                "mean_mcs": _mean_numeric(family_rows, "MCS", "CQIDerivedMCS"),
                "modulation_set": _distinct_join(family_rows, "Modulation"),
            })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_trial_overview",
                "note": "Trial-family overview aggregated from persisted waveform/control trial artifacts.",
                "source_logical_path": "|".join(logical_path for logical_path, family_rows in ((raw_sources[key], raw_rows[key]) for key in raw_sources) if family_rows),
                "source_row_count": sum(int(row["observed_rows"]) for row in rows),
            }
    if table_name in {"live_case_status", "live_required_vs_optional_case_status", "live_truth_policy_status"}:
        block_paths = {
            "pdcch": raw_sources["pdcch"],
            "ssb_pbch": raw_sources["pbch"],
            "prach": raw_sources["prach"],
            "pdsch": raw_sources["dl_pdsch"],
            "pusch": raw_sources["ul_pusch"],
            "pucch": raw_sources["pucch"],
            "srs": raw_sources["srs"],
            "trs": raw_sources["trs"],
            "beamforming": "beamforming/csv/probe_beam_mimo.csv",
            "energy": "rf/csv/probe_rf_energy.csv",
        }
        rows: list[dict[str, Any]] = []
        for block_name, logical_path in block_paths.items():
            _header, block_rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, logical_path)
            rows.append({
                "run_id": run_id,
                "block_name": block_name,
                "required_flag": 1,
                "policy_state": "required",
                "status": "generated" if block_rows else "missing",
                "observed_rows": len(block_rows),
                "source_artifact": logical_path,
                "placeholder_rows": _count_trueish(block_rows, "PlaceholderFlag"),
                "fallback_rows": _count_trueish(block_rows, "FallbackFlag"),
            })
        if table_name == "live_required_vs_optional_case_status":
            for feature_name, enabled in sorted(feature_policy.items()):
                rows.append({
                    "run_id": run_id,
                    "block_name": feature_name,
                    "required_flag": 0,
                    "policy_state": "enabled" if enabled else "policy_disabled",
                    "status": "policy_disabled" if not enabled else "not_observed",
                    "observed_rows": 0,
                    "source_artifact": "feature_policy",
                    "placeholder_rows": 0,
                    "fallback_rows": 0,
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_case_status",
                "note": "Case and truth-policy rows derived from direct artifact presence plus runtime placeholder/fallback flags.",
                "source_logical_path": "sim_runs.status_json",
                "source_row_count": len(rows),
            }
    if table_name in {"live_cell_table", "live_per_cell_context"}:
        rows_by_cell: dict[tuple[str, str], dict[str, Any]] = {}
        for direction, grant_rows in (("DL", dl_grants), ("UL", ul_grants)):
            for row in grant_rows:
                cell_id = _row_text(row, "ServingCell", "CellID") or "unknown"
                bs_id = _row_text(row, "BaseStationID", "BSID") or "unknown"
                key = (cell_id, bs_id)
                entry = rows_by_cell.setdefault(key, {"run_id": run_id, "cell_id": cell_id, "bs_id": bs_id, "dl_grant_count": 0, "ul_grant_count": 0, "ue_set": set(), "cqi_sum": 0.0, "cqi_count": 0, "tbs_sum": 0.0, "tbs_count": 0})
                entry["ue_set"].add(_row_text(row, "UEID", "UEIndex", "RNTI"))
                if direction == "DL":
                    entry["dl_grant_count"] += 1
                else:
                    entry["ul_grant_count"] += 1
                cqi = _row_float(row, "CQIUsed")
                if cqi is not None:
                    entry["cqi_sum"] += cqi
                    entry["cqi_count"] += 1
                tbs = _row_float(row, "TBSBits")
                if tbs is not None:
                    entry["tbs_sum"] += tbs
                    entry["tbs_count"] += 1
        rows = [{
            "run_id": entry["run_id"],
            "cell_id": entry["cell_id"],
            "bs_id": entry["bs_id"],
            "dl_grant_count": entry["dl_grant_count"],
            "ul_grant_count": entry["ul_grant_count"],
            "unique_ue_count": len(entry["ue_set"]),
            "mean_cqi": (entry["cqi_sum"] / entry["cqi_count"]) if entry["cqi_count"] else "",
            "mean_tbs_bits": (entry["tbs_sum"] / entry["tbs_count"]) if entry["tbs_count"] else "",
            "source_artifact": "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv",
        } for entry in rows_by_cell.values()]
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_cell_summary",
                "note": "Per-cell context derived from persisted DL and UL scheduler grants.",
                "source_logical_path": "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv",
                "source_row_count": len(dl_grants) + len(ul_grants),
            }
    if table_name == "live_link_table":
        rows: list[dict[str, Any]] = []
        for family in ("dl_pdsch", "ul_pusch", "pdcch", "pbch"):
            logical_path = raw_sources[family]
            for row in raw_rows.get(family, [])[:512]:
                rows.append({
                    "run_id": run_id,
                    "direction": _row_text(row, "Direction"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "cell_id": _row_text(row, "ServingCell", "CellID", "BaseStationID"),
                    "frame": _row_text(row, "Frame"),
                    "slot": _row_text(row, "Slot"),
                    "measured_sinr_db": _row_text(row, "MeasuredSINR_dB", "ReceiverHestSINR_dB"),
                    "wideband_cqi": _row_text(row, "WidebandCQI"),
                    "mcs": _row_text(row, "MCS", "CQIDerivedMCS"),
                    "tb_size_bits": _row_text(row, "TBSize_bits"),
                    "channel_gain_db": _row_text(row, "ChannelGain_dB"),
                    "source_artifact": logical_path,
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_link_table",
                "note": "Per-link rows emitted directly from truthful trial artifacts.",
                "source_logical_path": "|".join(raw_sources[family] for family in ("dl_pdsch", "ul_pusch", "pdcch", "pbch")),
                "source_row_count": len(rows),
            }
    if table_name == "live_path_geometry_table":
        scenario_cfg = _json_object(config_payload.get("scenario"))
        layout_cfg = _json_object(scenario_cfg.get("layout"))
        ue_cfg = _json_object(scenario_cfg.get("ue"))
        dist_cfg = _json_object(ue_cfg.get("distribution"))
        rows = [
            {"run_id": run_id, "entity_type": "layout", "layout_type": str(layout_cfg.get("type") or ""), "n_sites": layout_cfg.get("nSites", ""), "sectors_per_site": layout_cfg.get("nSectorsPerSite", ""), "intersite_distance_m": layout_cfg.get("interSiteDistance_m", ""), "wrap_around": layout_cfg.get("wrapAround", ""), "source_artifact": "sim_runs.config_json"},
            {"run_id": run_id, "entity_type": "ue_distribution", "layout_type": str(dist_cfg.get("type") or ""), "n_sites": ue_cfg.get("nUE", ""), "sectors_per_site": dist_cfg.get("indoorFraction", ""), "intersite_distance_m": dist_cfg.get("minBSdist_m", ""), "wrap_around": dist_cfg.get("maxBSdist_m", ""), "source_artifact": "sim_runs.config_json"},
        ]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_geometry_summary",
            "note": "Geometry summary derived from the resolved scenario configuration because explicit topology coordinate tables were not published for this running web launch.",
            "source_logical_path": "sim_runs.config_json",
            "source_row_count": len(rows),
        }
    if table_name in {"live_prb_allocation_snapshot", "live_re_allocation_snapshot"}:
        rows: list[dict[str, Any]] = []
        for direction, grant_rows in (("DL", dl_grants), ("UL", ul_grants)):
            for row in grant_rows:
                prb_count = _row_float(row, "PRBCount", "AllocatedPRBCount")
                num_symbols = _row_float(row, "NumSymbols")
                rows.append({
                    "run_id": run_id,
                    "direction": direction,
                    "frame": _row_text(row, "Frame", "SFN"),
                    "slot": _row_text(row, "Slot"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "cell_id": _row_text(row, "ServingCell"),
                    "prb_start": _row_text(row, "PRBStart"),
                    "prb_count": prb_count if prb_count is not None else "",
                    "symbol_start": _row_text(row, "SymbolStart"),
                    "num_symbols": num_symbols if num_symbols is not None else "",
                    "derived_re_count": (prb_count * num_symbols * 12.0) if prb_count is not None and num_symbols is not None else "",
                    "source_artifact": "packet_flow/csv/live_dl_scheduler_grants.csv" if direction == "DL" else "packet_flow/csv/live_ul_scheduler_grants.csv",
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_allocation_snapshot",
                "note": "Allocation snapshots derived from truthful scheduler grant rows.",
                "source_logical_path": "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv",
                "source_row_count": len(rows),
            }
    if table_name in {"live_mac_pdu_summary", "live_mac_ce_state", "live_pusch_rx_summary", "live_llr_summary", "live_decoder_summary", "live_channel_realization_table", "live_interference_table", "live_tracking_table"}:
        if table_name == "live_mac_ce_state":
            rows = [{
                "run_id": run_id,
                "direction": _row_text(row, "Direction", "FeedbackForDirection"),
                "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                "frame": _row_text(row, "Frame"),
                "slot": _row_text(row, "Slot"),
                "uci_type": _row_text(row, "UCIType"),
                "expected_ack": _row_text(row, "ExpectedAck"),
                "observed_ack": _row_text(row, "ObservedAck"),
                "pucch_decode_ok": _row_text(row, "PUCCHDecodeOk"),
                "source_artifact": "packet_flow/csv/live_pucch_grants.csv",
            } for row in pucch_grants]
            if rows:
                return {
                    "data": _encode_rows_from_dicts(rows),
                    "status": "specialized_runtime_mac_ce_state",
                    "note": "MAC control-element state derived from persisted PUCCH grant and UCI observations.",
                    "source_logical_path": "packet_flow/csv/live_pucch_grants.csv",
                    "source_row_count": len(rows),
                }
        selected_sources: list[tuple[str, list[dict[str, str]]]] = []
        if table_name == "live_mac_pdu_summary":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"])]
        elif table_name == "live_pusch_rx_summary":
            selected_sources = [(raw_sources["ul_pusch"], raw_rows["ul_pusch"])]
        elif table_name == "live_llr_summary":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"])]
        elif table_name == "live_decoder_summary":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"]), (raw_sources["pdcch"], raw_rows["pdcch"]), (raw_sources["pbch"], raw_rows["pbch"])]
        elif table_name == "live_channel_realization_table":
            selected_sources = [(logical_path, raw_rows[key]) for key, logical_path in raw_sources.items()]
        elif table_name == "live_interference_table":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"]), (raw_sources["pdcch"], raw_rows["pdcch"]), (raw_sources["pbch"], raw_rows["pbch"])]
        elif table_name == "live_tracking_table":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"]), (raw_sources["trs"], raw_rows["trs"])]
        rows: list[dict[str, Any]] = []
        for logical_path, source_rows in selected_sources:
            for row in source_rows[:512]:
                out_row = {
                    "run_id": run_id,
                    "direction": _row_text(row, "Direction"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "frame": _row_text(row, "Frame"),
                    "slot": _row_text(row, "Slot"),
                    "source_artifact": logical_path,
                }
                if table_name in {"live_mac_pdu_summary", "live_pusch_rx_summary"}:
                    out_row.update({
                        "tb_size_bits": _row_text(row, "TBSize_bits"),
                        "mcs": _row_text(row, "MCS", "CQIDerivedMCS"),
                        "modulation": _row_text(row, "Modulation", "CQIDerivedModulation"),
                        "crc_pass": _row_text(row, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK"),
                        "goodput_mbps": _row_text(row, "Goodput_Mbps"),
                    })
                elif table_name == "live_llr_summary":
                    out_row.update({
                        "llr_mean_abs": _row_text(row, "LLRMeanAbs"),
                        "llr_std_abs": _row_text(row, "LLRStdAbs"),
                        "llr_imbalance": _row_text(row, "LLRImbalance"),
                        "decoder_iterations": _row_text(row, "DecoderIterations"),
                    })
                elif table_name == "live_decoder_summary":
                    out_row.update({
                        "decoder_iterations": _row_text(row, "DecoderIterations"),
                        "crc_pass": _row_text(row, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK"),
                        "codeblock_bler": _row_text(row, "CodeBlockBLER"),
                        "cbg_bler": _row_text(row, "CBGBLER"),
                    })
                elif table_name == "live_channel_realization_table":
                    out_row.update({
                        "channel_model": _row_text(row, "ChannelModel"),
                        "channel_gain_db": _row_text(row, "ChannelGain_dB"),
                        "applied_pathloss_db": _row_text(row, "AppliedPathloss_dB"),
                        "applied_shadow_fading_db": _row_text(row, "AppliedShadowFading_dB"),
                        "doppler_hz": _row_text(row, "DopplerHz"),
                    })
                elif table_name == "live_interference_table":
                    out_row.update({
                        "interference_mode": _row_text(row, "InterferenceMode"),
                        "interference_contributor_count": _row_text(row, "InterferenceContributorCount"),
                        "interference_rx_power_dbm": _row_text(row, "InterferenceAggregatedRxPower_dBm"),
                        "residual_interference_power_db": _row_text(row, "ResidualInterferencePower_dB"),
                        "interference_power_source": _row_text(row, "InterferencePowerSource"),
                    })
                elif table_name == "live_tracking_table":
                    out_row.update({
                        "estimated_cfo_hz": _row_text(row, "EstimatedCFO_Hz"),
                        "residual_cfo_post_correction_hz": _row_text(row, "ResidualCFO_PostCorrection_Hz"),
                        "true_cfo_hz": _row_text(row, "TrueCFO_Hz"),
                        "estimated_timing_offset_samples": _row_text(row, "EstimatedTimingOffset_PreCorrection_samples", "TimingOffset_samples"),
                        "residual_timing_error_samples": _row_text(row, "ResidualTimingError_PostCorrection_samples"),
                        "true_timing_offset_samples": _row_text(row, "TrueTimingOffset_samples"),
                    })
                rows.append(out_row)
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_signal_summary",
                "note": "Signal and decoder summaries derived directly from persisted truthful waveform trial exports.",
                "source_logical_path": "|".join(logical_path for logical_path, source_rows in selected_sources if source_rows),
                "source_row_count": len(rows),
            }
    if table_name in {"live_precoder_table", "live_combiner_table", "live_mimo_state_table", "live_user_grouping_table"} and beam_probe:
        rows: list[dict[str, Any]] = []
        for row in beam_probe[:1027]:
            out_row = {
                "run_id": run_id,
                "direction": _row_text(row, "Direction"),
                "ue_id": _row_text(row, "UEIndex", "RNTI"),
                "frame": _row_text(row, "Frame"),
                "slot": _row_text(row, "Slot"),
                "source_artifact": "beamforming/csv/probe_beam_mimo.csv",
            }
            if table_name == "live_precoder_table":
                out_row.update({
                    "precoder_source": _row_text(row, "PrecoderSource"),
                    "precoding_mode": _row_text(row, "PrecodingMode"),
                    "application_stage": _row_text(row, "PrecodingApplicationStage"),
                    "applied_precoder_pmi": _row_text(row, "AppliedPrecoderPMI"),
                    "codebook_mode": _row_text(row, "AppliedPrecoderCodebookMode"),
                    "num_ports": _row_text(row, "PrecodingNumPorts"),
                    "num_layers": _row_text(row, "PrecodingNumLayers"),
                })
            elif table_name == "live_combiner_table":
                out_row.update({
                    "num_rx_antennas": _row_text(row, "NumRxAntennas", "ConfiguredRxAntennas"),
                    "condition_number_db": _row_text(row, "ConditionNumber_dB"),
                    "selected_beam_index": _row_text(row, "SelectedBeamIndex"),
                    "best_beam_index": _row_text(row, "BestBeamIndex"),
                })
            elif table_name == "live_mimo_state_table":
                out_row.update({
                    "configured_layers": _row_text(row, "ConfiguredLayers", "Layers"),
                    "rank_indicator": _row_text(row, "RankIndicator"),
                    "rank_estimate": _row_text(row, "RankEstimate"),
                    "num_tx_ports": _row_text(row, "NumTxPorts", "PrecodingNumPorts"),
                    "beamforming_applied": _row_text(row, "BeamformingApplied"),
                })
            else:
                out_row.update({
                    "beam_selection_strategy": _row_text(row, "BeamSelectionStrategy"),
                    "selected_beam_index": _row_text(row, "SelectedBeamIndex"),
                    "beam_hit": _row_text(row, "BeamHit"),
                    "topk_beam_hit": _row_text(row, "TopKBeamHit"),
                    "beam_candidate_count": _row_text(row, "BeamCandidateCount"),
                })
            rows.append(out_row)
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_beam_table",
            "note": "Beamforming and MIMO report tables derived from persisted runtime beam-management evidence.",
            "source_logical_path": "beamforming/csv/probe_beam_mimo.csv",
            "source_row_count": len(rows),
        }
    if table_name == "live_drx_state" and energy_rows:
        grouped: dict[str, Counter[str]] = defaultdict(Counter)
        for row in energy_rows:
            ue_id = _row_text(row, "UEID", "EntityID") or "unknown"
            grouped[ue_id][_row_text(row, "State") or "unknown"] += 1
        rows = [{
            "run_id": run_id,
            "ue_id": ue_id,
            "dominant_state": counter.most_common(1)[0][0] if counter else "",
            "state_sample_count": sum(counter.values()),
            "active_samples": counter.get("ACTIVE", 0) + counter.get("active", 0),
            "sleep_samples": counter.get("SLEEP", 0) + counter.get("sleep", 0),
            "idle_samples": counter.get("IDLE", 0) + counter.get("idle", 0),
            "source_artifact": "rf/csv/energy_timeline_trace.csv",
        } for ue_id, counter in list(grouped.items())[:1024]]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_drx_state",
            "note": "UE DRX-like occupancy derived from the persisted runtime energy-state trace.",
            "source_logical_path": "rf/csv/energy_timeline_trace.csv",
            "source_row_count": len(rows),
        }
    if table_name == "live_phy_mac_api_table" and slot_trace:
        rows = [{
            "run_id": run_id,
            "canonical_slot": _row_text(row, "CanonicalSlot", "Slot"),
            "frame": _row_text(row, "Frame"),
            "dl_grant_count": _row_text(row, "DLGrantCount"),
            "ul_grant_count": _row_text(row, "ULGrantCount"),
            "dl_trial_rows": _row_text(row, "DLTrialRows"),
            "ul_trial_rows": _row_text(row, "ULTrialRows"),
            "scheduler_source": _row_text(row, "SchedulerSource"),
            "phy_source": _row_text(row, "PHYSource"),
            "report_source": _row_text(row, "ReportSource"),
            "trace_status": _row_text(row, "TraceStatus"),
            "source_artifact": "packet_flow/csv/slot_trace.csv",
        } for row in slot_trace]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_phy_mac_api_table",
            "note": "gNB-side orchestration view derived from the persisted slot trace.",
            "source_logical_path": "packet_flow/csv/slot_trace.csv",
            "source_row_count": len(rows),
        }
    if table_name in {"live_db_write_table", "live_csv_write_table", "live_artifact_write_table", "reports_all_artifacts_v"}:
        rows: list[dict[str, Any]] = []
        for art in artifact_rows:
            logical_path = str(art.get("logical_path") or "")
            if table_name == "live_csv_write_table" and not logical_path.startswith(("reports/", "analytics/")):
                continue
            rows.append({
                "run_id": run_id,
                "artifact_id": art["artifact_id"],
                "logical_path": logical_path,
                "artifact_kind": art["artifact_kind"],
                "mime_type": art["mime_type"],
                "sink_type": "db_artifact" if table_name != "live_csv_write_table" else "filesystem_projection",
                "target_table": logical_path if table_name == "live_db_write_table" else "",
                "target_file": logical_path if table_name != "live_db_write_table" else "",
            })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_artifact_inventory",
                "note": "Artifact inventory derived from the DB-backed artifact store visible to the browser.",
                "source_logical_path": "sim_artifacts",
                "source_row_count": len(rows),
            }
    if table_name in {"live_browser_surface_integrity_table", "live_consistency_check_table", "reports_partial_or_missing_v", "reports_truth_violations_v", "reports_status_rollup_explanations_v"}:
        rows = []
        for spec in output_contract.iter_table_specs("reports"):
            source_rows = _table_source_health(str(spec.get("table_name") or ""), source_lookup, fetch_artifact_bytes)
            present_rows = sum(int(item["source_row_count"]) for item in source_rows)
            rows.append({
                "run_id": run_id,
                "section_slug": str(spec.get("section_slug") or ""),
                "contract_table": str(spec.get("table_name") or ""),
                "status": "generated" if present_rows > 0 else "missing_source_evidence",
                "source_paths_checked": "|".join(item["source_logical_path"] for item in source_rows),
                "present_source_count": sum(int(item["source_present"]) for item in source_rows),
                "source_row_count": present_rows,
                "rollup_explanation": "At least one truthful source artifact exists for this contract table." if present_rows > 0 else "No direct aliased source artifact was published for this run.",
            })
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_integrity_table",
            "note": "Integrity and partial/missing investigator views derived from direct alias-health checks.",
            "source_logical_path": "sim_artifacts",
            "source_row_count": len(rows),
        }
    if table_name == "reports_all_scalars_v":
        rows = [
            {"run_id": run_id, "metric_name": "run_completion", "metric_value": status_payload.get("run_completion", ""), "metric_unit": "ratio", "source_artifact": "sim_runs.status_json"},
            {"run_id": run_id, "metric_name": "dl_trial_rows", "metric_value": len(raw_rows["dl_pdsch"]), "metric_unit": "rows", "source_artifact": raw_sources["dl_pdsch"]},
            {"run_id": run_id, "metric_name": "ul_trial_rows", "metric_value": len(raw_rows["ul_pusch"]), "metric_unit": "rows", "source_artifact": raw_sources["ul_pusch"]},
            {"run_id": run_id, "metric_name": "dl_mean_measured_sinr_db", "metric_value": _mean_numeric(raw_rows["dl_pdsch"], "MeasuredSINR_dB"), "metric_unit": "dB", "source_artifact": raw_sources["dl_pdsch"]},
            {"run_id": run_id, "metric_name": "ul_mean_measured_sinr_db", "metric_value": _mean_numeric(raw_rows["ul_pusch"], "MeasuredSINR_dB"), "metric_unit": "dB", "source_artifact": raw_sources["ul_pusch"]},
            {"run_id": run_id, "metric_name": "energy_rows", "metric_value": len(energy_rows), "metric_unit": "rows", "source_artifact": "rf/csv/energy_timeline_trace.csv"},
        ]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_scalar_view",
            "note": "Scalar investigator view derived from run status and raw artifact summaries.",
            "source_logical_path": "sim_runs.status_json",
            "source_row_count": len(rows),
        }
    if table_name in {"reports_all_enums_v", "reports_value_semantics_coverage_v"}:
        counts: Counter[tuple[str, str, str]] = Counter()
        field_names = ("Direction", "Modulation", "GrantReason", "ValueSource", "ValueRole", "ValueStatus", "SINRSource", "SINRValueRole", "SINRValueStatus")
        for family, source_rows in raw_rows.items():
            for row in source_rows:
                for field_name in field_names:
                    token = _row_text(row, field_name)
                    if token:
                        counts[(family, field_name, token)] += 1
        rows = [{
            "run_id": run_id,
            "artifact_family": family,
            "field_name": field_name,
            "enum_value": token,
            "observation_count": count,
        } for (family, field_name, token), count in counts.most_common(1024)]
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_enum_view",
                "note": "Enum and value-semantics coverage views derived from distinct categorical values in raw runtime artifacts.",
                "source_logical_path": "|".join(raw_sources.values()),
                "source_row_count": len(rows),
            }
    if table_name == "reports_config_vs_measured_conflicts_v":
        configured_snr = _coerce_float(status_payload.get("ConfiguredSNR_dB") or "")
        rows = []
        for family in ("dl_pdsch", "ul_pusch", "pdcch"):
            source_rows = raw_rows[family]
            if not source_rows:
                continue
            rows.append({
                "run_id": run_id,
                "artifact_family": family,
                "source_artifact": raw_sources[family],
                "configured_snr_db": configured_snr if configured_snr is not None else "",
                "mean_measured_sinr_db": _mean_numeric(source_rows, "MeasuredSINR_dB", "ReceiverHestSINR_dB"),
                "mean_serving_rsrp_dbm": _mean_numeric(source_rows, "ServingRSRP_dBm"),
                "mean_csi_rsrp_db": _mean_numeric(source_rows, "CSI_RSRP_dB"),
                "lineage_note": "Comparison surfaces keep configured launch values separate from measured air-interface runtime values.",
            })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_config_measured_view",
                "note": "Configured-vs-measured comparison derived from persisted trial artifacts.",
                "source_logical_path": "|".join(raw_sources[family] for family in ("dl_pdsch", "ul_pusch", "pdcch")),
                "source_row_count": len(rows),
            }
    return None


def _select_source_table_artifact(
    source_paths: list[str],
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
) -> tuple[dict[str, Any] | None, bytes, list[str], list[list[str]]]:
    fallback: tuple[dict[str, Any] | None, bytes, list[str], list[list[str]]] = (None, b"", [], [])
    for path in source_paths:
        art = source_lookup.get(path)
        if not art or str(art.get("artifact_kind") or "") != "table_csv":
            continue
        source_data = fetch_artifact_bytes(int(art["artifact_id"]))
        header, rows = _decode_csv(source_data)
        source_data, header, rows = _canonicalize_contract_source_rows(path, header, rows)
        if not fallback[0]:
            fallback = (art, source_data, header, rows)
        if not rows:
            continue
        _, dict_rows = _decode_csv_dicts(source_data)
        if _table_placeholder_summary_status(dict_rows) in {"source_artifact_missing", "source_artifact_present_but_empty"}:
            continue
        return art, source_data, header, rows
    return fallback


def _selected_cell(records: list[dict[str, str]], *cell_names: str) -> str:
    counts: dict[str, int] = {}
    for row in records:
        token = _row_text(row, *cell_names)
        if token:
            counts[token] = counts.get(token, 0) + 1
    if not counts:
        return ""
    return max(counts.items(), key=lambda item: (item[1], item[0]))[0]


def _build_grid_heatmap_records(
    records: list[dict[str, str]],
    *,
    cell_names: tuple[str, ...],
    slot_names: tuple[str, ...],
    rb_names: tuple[str, ...],
    occ_names: tuple[str, ...],
) -> tuple[list[dict[str, Any]], str]:
    chosen_cell = _selected_cell(records, *cell_names)
    filtered = [row for row in records if _row_text(row, *cell_names) == chosen_cell] if chosen_cell else list(records)
    points: dict[tuple[int, int], float] = {}
    out_rows: list[dict[str, Any]] = []
    for row in filtered:
        slot_v = _row_float(row, *slot_names)
        rb_v = _row_float(row, *rb_names)
        occ_v = _row_float(row, *occ_names)
        if slot_v is None or rb_v is None:
            continue
        value = occ_v if occ_v is not None else 1.0
        slot_i = int(round(slot_v))
        rb_i = int(round(rb_v))
        points[(slot_i, rb_i)] = points.get((slot_i, rb_i), 0.0) + float(value)
        out_rows.append({"cell_id": chosen_cell, "slot": slot_i, "rb_index": rb_i, "occupancy_value": float(value)})
    return out_rows, chosen_cell


def _grid_rows_to_heatmap(
    rows: list[dict[str, Any]],
    x_name: str,
    y_name: str,
    value_name: str,
) -> tuple[list[str], list[str], list[list[float]]]:
    def _token_sort_key(token: str) -> tuple[int, Any, str]:
        numeric = _coerce_float(token)
        if numeric is not None:
            return (0, float(numeric), token)
        return (1, token.lower(), token)

    x_values = sorted({int(round(float(row[x_name]))) for row in rows if row.get(x_name) is not None})
    y_values = sorted({str(row[y_name]) for row in rows if str(row.get(y_name, "")).strip()}, key=_token_sort_key)
    if not x_values or not y_values:
        return [], [], []
    x_index = {value: idx for idx, value in enumerate(x_values)}
    y_index = {value: idx for idx, value in enumerate(y_values)}
    matrix = [[0.0 for _ in x_values] for _ in y_values]
    for row in rows:
        try:
            x_val = int(round(float(row[x_name])))
            y_val = str(row[y_name])
            v = float(row.get(value_name) or 0.0)
        except Exception:
            continue
        matrix[y_index[y_val]][x_index[x_val]] += v
    return [str(value) for value in x_values], y_values, matrix


def _encode_dict_rows(header: list[str], rows: list[dict[str, Any]]) -> bytes:
    return _encode_csv(header, [[row.get(col, "") for col in header] for row in rows])


def _trial_row_bler(row: dict[str, str]) -> float | None:
    crc_pass = _row_text(row, "CRCPass")
    if crc_pass:
        return 0.0 if crc_pass.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 1.0
    codeblock_bler = _row_float(row, "CodeBlockBLER")
    if codeblock_bler is not None:
        return float(codeblock_bler)
    return None


def _trial_row_ber(row: dict[str, str]) -> float | None:
    bit_errors = _row_float(row, "BitErrors")
    bits_compared = _row_float(row, "BitsCompared")
    if bit_errors is None or bits_compared is None or bits_compared <= 0:
        return None
    return float(bit_errors) / float(bits_compared)


def _trial_rows_with_paths(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    candidates: list[str] | tuple[str, ...],
) -> list[tuple[str, dict[str, str]]]:
    out: list[tuple[str, dict[str, str]]] = []
    for logical_path in candidates:
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, logical_path)
        for row in rows:
            out.append((str(logical_path), row))
    return out


def _prach_rate_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = str(chart_name or "").strip().lower()
    metric_specs = {
        "detection rate": {
            "metric_label": "Detection rate",
            "metric_keys": {"prach_detection_probability"},
            "trial_flag": lambda row: _row_flag(row, "DecodeSuccess", "SuccessFlag")
            if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
            else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
            if _row_text(row, "Status")
            else (_row_float(row, "DetectionMetric") or 0.0) > 0.0,
        },
        "p_d": {
            "metric_label": "Detection probability",
            "metric_keys": {"prach_detection_probability"},
            "trial_flag": lambda row: _row_flag(row, "DecodeSuccess", "SuccessFlag")
            if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
            else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
            if _row_text(row, "Status")
            else (_row_float(row, "DetectionMetric") or 0.0) > 0.0,
        },
        "false alarm rate": {
            "metric_label": "False alarm rate",
            "metric_keys": {"prach_false_alarm"},
            "trial_flag": lambda row: _row_flag(row, "FalseAlarmFlag"),
        },
        "far": {
            "metric_label": "False alarm rate",
            "metric_keys": {"prach_false_alarm"},
            "trial_flag": lambda row: _row_flag(row, "FalseAlarmFlag"),
        },
        "p_fa": {
            "metric_label": "False alarm probability",
            "metric_keys": {"prach_false_alarm"},
            "trial_flag": lambda row: _row_flag(row, "FalseAlarmFlag"),
        },
        "missed detection rate": {
            "metric_label": "Missed detection rate",
            "metric_keys": {"prach_missed_detection"},
            "trial_flag": lambda row: (
                _row_flag(row, "MissedDetectionFlag")
                if _row_flag(row, "MissedDetectionFlag") is not None
                else (
                    not bool(
                        _row_flag(row, "DecodeSuccess", "SuccessFlag")
                        if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
                        else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
                        if _row_text(row, "Status")
                        else (_row_float(row, "DetectionMetric") or 0.0) > 0.0
                    )
                    and not bool(_row_flag(row, "FalseAlarmFlag"))
                )
            ),
        },
        "p_md": {
            "metric_label": "Missed detection probability",
            "metric_keys": {"prach_missed_detection"},
            "trial_flag": lambda row: (
                _row_flag(row, "MissedDetectionFlag")
                if _row_flag(row, "MissedDetectionFlag") is not None
                else (
                    not bool(
                        _row_flag(row, "DecodeSuccess", "SuccessFlag")
                        if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
                        else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
                        if _row_text(row, "Status")
                        else (_row_float(row, "DetectionMetric") or 0.0) > 0.0
                    )
                    and not bool(_row_flag(row, "FalseAlarmFlag"))
                )
            ),
        },
    }
    spec = metric_specs.get(chart_key)
    if spec is None:
        return None

    trial_path, trial_rows = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["air_interface/csv/prach_trials.csv", "control/csv/prach_trials.csv", "control/csv/prach_detection_trials.csv"],
    )
    grouped: dict[float | None, list[float]] = defaultdict(list)
    if trial_rows:
        for row in trial_rows:
            flag_value = spec["trial_flag"](row)
            if flag_value is None:
                continue
            snr_value = _row_float(row, "SNR_dB", "ConfiguredSNR_dB", "AppliedAWGNSNR_dB")
            bucket = float(snr_value) if snr_value is not None and math.isfinite(float(snr_value)) else None
            grouped[bucket].append(1.0 if bool(flag_value) else 0.0)
    if grouped:
        ordered = sorted(grouped.items(), key=lambda item: (-9999.0 if item[0] is None else float(item[0])))
        points: list[list[float]] = []
        tick_labels: list[str] = []
        csv_rows: list[dict[str, Any]] = []
        total_samples = 0
        total_positive = 0.0
        for idx, (snr_bucket, values) in enumerate(ordered, start=1):
            if not values:
                continue
            rate_value = sum(values) / len(values)
            point_x = float(idx) if snr_bucket is None else float(snr_bucket)
            tick_label = "Observed PRACH" if snr_bucket is None else f"{snr_bucket:.3g} dB"
            points.append([point_x, float(rate_value)])
            tick_labels.append(tick_label)
            total_samples += len(values)
            total_positive += sum(values)
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "bucket_name": tick_label,
                    "snr_db": "" if snr_bucket is None else snr_bucket,
                    "metric_value": rate_value,
                    "sample_count": len(values),
                    "source_table_logical_path": trial_path,
                }
            )
        if points:
            dataset = {
                "mode": "bar" if len(points) <= 8 else "line",
                "x_label": "PRACH SNR (dB)" if any(item[0] is not None for item in ordered) else "Observation bucket",
                "y_label": str(spec["metric_label"]),
                "points": points,
            }
            if dataset["mode"] == "bar":
                dataset["tick_labels"] = tick_labels
            summary = [
                f"source={trial_path}",
                f"trial_rows={len(trial_rows)}",
                f"samples_used={total_samples}",
                f"mean_rate={total_positive / max(total_samples, 1):.6f}",
            ]
            return {
                "csv_bytes": _encode_dict_rows(
                    ["run_id", "chart_name", "bucket_name", "snr_db", "metric_value", "sample_count", "source_table_logical_path"],
                    csv_rows,
                ),
                "img_bytes": _render_svg_plot(
                    chart_name,
                    "PRACH detection statistics aggregated directly from persisted PRACH trial outcomes.",
                    dataset,
                    summary,
                ),
                "csv_status": "specialized_runtime_detection_dataset",
                "image_status": "generated_specialized_runtime_summary_svg",
                "source_table_path": trial_path,
                "source_row_count": len(trial_rows),
                "note": "Detection-rate chart derived from truthful PRACH trial flags grouped by observed SNR.",
            }

    summary_path, summary_rows = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["reports/csv/initial_access_random_access_outputs.csv", "analytics/csv/random_access_analytics.csv"],
    )
    if not summary_rows:
        return None
    rate_value = None
    count_value = None
    for row in summary_rows:
        metric_key = _row_text(row, "MetricKey").strip().lower()
        metric_name = _row_text(row, "MetricName").strip().lower()
        statistic = _row_text(row, "Statistic").strip().lower()
        if metric_key not in spec["metric_keys"] and not any(token in metric_name for token in chart_key.split()):
            continue
        if statistic == "rate":
            rate_value = _row_float(row, "ValueNumeric", "Value")
        elif statistic == "count":
            count_value = _row_float(row, "ValueNumeric", "Value")
    if rate_value is None:
        return None
    dataset = {
        "mode": "bar",
        "x_label": "Observation bucket",
        "y_label": str(spec["metric_label"]),
        "points": [[1.0, float(rate_value)]],
        "tick_labels": ["Observed PRACH"],
    }
    csv_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            "bucket_name": "Observed PRACH",
            "snr_db": "",
            "metric_value": float(rate_value),
            "sample_count": "" if count_value is None else count_value,
            "source_table_logical_path": summary_path,
        }
    ]
    summary = [f"source={summary_path}", f"observed_rate={float(rate_value):.6f}"]
    if count_value is not None:
        summary.append(f"sample_count={int(round(count_value))}")
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "bucket_name", "snr_db", "metric_value", "sample_count", "source_table_logical_path"],
            csv_rows,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            "PRACH detection summary taken from the persisted random-access metrics artifact.",
            dataset,
            summary,
        ),
        "csv_status": "specialized_summary_detection_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": summary_path,
        "source_row_count": len(summary_rows),
        "note": "Detection-rate chart derived from the persisted PRACH summary metrics artifact.",
    }


def _csirs_map_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    source_path = "air_interface/csv/csi_rs_trials.csv"
    _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
    if not records:
        return None
    chosen_cell = _selected_cell(records, "CellID", "BaseStationID", "ServingCell")
    filtered = [row for row in records if not chosen_cell or _row_text(row, "CellID", "BaseStationID", "ServingCell") == chosen_cell]
    slot_counts: Counter[int] = Counter()
    for row in filtered:
        slot_v = _row_float(row, "Slot")
        if slot_v is None:
            continue
        slot_counts[int(round(slot_v))] += 1
    if not slot_counts:
        return None
    selected_slot = max(slot_counts.items(), key=lambda item: (item[1], -item[0]))[0]
    seen_resources: set[tuple[Any, ...]] = set()
    grid_rows: list[dict[str, Any]] = []
    rsrp_values: list[float] = []
    for row in filtered:
        slot_v = _row_float(row, "Slot")
        if slot_v is None or int(round(slot_v)) != selected_slot:
            continue
        rb_start = _row_float(row, "RBOffset", "PRBStart")
        num_rb = _row_float(row, "NumRB", "AllocatedPRBCount", "PRBs")
        if rb_start is None or num_rb is None or num_rb <= 0:
            continue
        symbols = _parse_index_tokens(_row_text(row, "SymbolLocations")) or [0]
        resource_key = (
            _row_text(row, "CellID", "BaseStationID", "ServingCell"),
            int(round(slot_v)),
            _row_text(row, "ResourceSetID"),
            _row_text(row, "ResourceID"),
            int(round(rb_start)),
            int(round(num_rb)),
            tuple(symbols),
        )
        if resource_key in seen_resources:
            continue
        seen_resources.add(resource_key)
        nre_value = _row_float(row, "NRE")
        tile_value = float(nre_value) / max(int(round(num_rb)) * max(len(symbols), 1) * 12, 1) if nre_value is not None else 1.0
        rsrp_value = _row_float(row, "MeasurementRSRP_dB")
        if rsrp_value is not None:
            rsrp_values.append(float(rsrp_value))
        for symbol_index in symbols:
            for rb_index in range(int(round(rb_start)), int(round(rb_start + num_rb))):
                grid_rows.append(
                    {
                        "cell_id": chosen_cell,
                        "slot": selected_slot,
                        "symbol_index": int(symbol_index),
                        "rb_index": rb_index,
                        "occupancy_value": tile_value,
                        "resource_id": _row_text(row, "ResourceID"),
                        "resource_set_id": _row_text(row, "ResourceSetID"),
                        "source_table_logical_path": source_path,
                    }
                )
    if not grid_rows:
        return None
    x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "symbol_index", "rb_index", "occupancy_value")
    summary = [
        f"source={source_path}",
        f"selected_cell={chosen_cell or 'all'}",
        f"selected_slot={selected_slot}",
        f"unique_resources={len(seen_resources)}",
    ]
    if rsrp_values:
        summary.append(f"mean_measurement_rsrp_db={sum(rsrp_values) / len(rsrp_values):.3f}")
    summary.append("exact_subcarrier_pattern=normalized_from_exported_nre_per_rb_symbol")
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id",
                "chart_name",
                "cell_id",
                "slot",
                "symbol_index",
                "rb_index",
                "occupancy_value",
                "resource_id",
                "resource_set_id",
                "source_table_logical_path",
            ],
            [{**row, "run_id": run_id, "chart_name": chart_name} for row in grid_rows],
        ),
        "img_bytes": _render_heatmap_svg(
            chart_name,
            "CSI-RS resource occupancy for the most active cell/slot, normalized from the exported runtime mapping evidence.",
            x_labels,
            y_labels,
            matrix,
            summary,
            "OFDM symbol",
            "RB index",
        ),
        "csv_status": "specialized_runtime_grid_dataset",
        "image_status": "generated_specialized_runtime_heatmap_svg",
        "source_table_path": source_path,
        "source_row_count": len(grid_rows),
        "note": "CSI-RS map derived from exported CSI-RS runtime rows without fabricating RE-level detail beyond the exported RB/symbol span.",
    }


def _srs_map_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    source_path = "air_interface/csv/srs_trials.csv"
    _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
    if not records:
        return None
    chosen_cell = _selected_cell(records, "BaseStationID", "TRSAssociatedCell", "ServingCell")
    grid_rows: list[dict[str, Any]] = []
    nmse_values: list[float] = []
    for row in records:
        cell_value = _row_text(row, "BaseStationID", "TRSAssociatedCell", "ServingCell")
        if chosen_cell and cell_value and cell_value != chosen_cell:
            continue
        slot_v = _row_float(row, "Slot")
        ue_v = _row_float(row, "UEIndex", "UEID", "RNTI")
        if slot_v is None or ue_v is None:
            continue
        success_flag = _row_flag(row, "SuccessFlag", "DecodeSuccess")
        if success_flag is None:
            status_text = _row_text(row, "Status").strip().lower()
            success_flag = status_text in {"pass", "detected", "success"} if status_text else True
        nmse_db = _row_float(row, "NMSE_dB")
        if nmse_db is not None:
            nmse_values.append(float(nmse_db))
        grid_rows.append(
            {
                "slot": int(round(slot_v)),
                "ue_index": int(round(ue_v)),
                "occupancy_value": 1.0 if success_flag else 0.0,
                "nmse_db": "" if nmse_db is None else nmse_db,
                "success_flag": 1 if success_flag else 0,
                "source_table_logical_path": source_path,
            }
        )
    if not grid_rows:
        return None
    x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "slot", "ue_index", "occupancy_value")
    summary = [
        f"source={source_path}",
        f"selected_cell={chosen_cell or 'all'}",
        f"runtime_rows={len(grid_rows)}",
        f"successful_rows={sum(int(row['success_flag']) for row in grid_rows)}",
    ]
    if nmse_values:
        summary.append(f"mean_nmse_db={sum(nmse_values) / len(nmse_values):.3f}")
    summary.append("exact_srs_rb_symbol_map=not_exported_by_runtime")
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "slot", "ue_index", "occupancy_value", "nmse_db", "success_flag", "source_table_logical_path"],
            [{**row, "run_id": run_id, "chart_name": chart_name} for row in grid_rows],
        ),
        "img_bytes": _render_heatmap_svg(
            chart_name,
            "Exact SRS RE placement is not exported for this run, so the map shows truthful per-UE SRS observation success by slot.",
            x_labels,
            y_labels,
            matrix,
            summary,
            "Slot",
            "UE index",
        ),
        "csv_status": "specialized_runtime_srs_dataset",
        "image_status": "generated_specialized_runtime_heatmap_svg",
        "source_table_path": source_path,
        "source_row_count": len(grid_rows),
        "note": "SRS map derived from truthful per-UE/per-slot SRS runtime observations without inventing absent RE-level coordinates.",
    }


def _metric_rows_by_exact_x(
    rows: list[tuple[float, float]],
    *,
    x_label: str,
    y_label: str,
    chart_name: str,
    run_id: int,
    source_path: str,
) -> tuple[bytes, dict[str, Any]]:
    grouped: dict[float, list[float]] = defaultdict(list)
    for x_val, y_val in rows:
        grouped[round(float(x_val), 6)].append(float(y_val))
    points = [[float(x_val), sum(values) / max(len(values), 1)] for x_val, values in sorted(grouped.items())]
    csv_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            x_label: point[0],
            y_label: point[1],
            "source_table_logical_path": source_path,
        }
        for point in points
    ]
    dataset = {"mode": "scatter" if len(points) > 18 else "line", "x_label": x_label, "y_label": y_label, "points": points}
    return _encode_dict_rows(["run_id", "chart_name", x_label, y_label, "source_table_logical_path"], csv_rows), dataset


def _specialized_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_name = str(chart_name or "")
    prach_rate_chart = _prach_rate_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
    if prach_rate_chart is not None:
        return prach_rate_chart
    if chart_name in {"CSI-RS map", "CSI-RS resource occupancy"}:
        csirs_chart = _csirs_map_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
        if csirs_chart is not None:
            return csirs_chart
    if chart_name == "SRS map":
        srs_chart = _srs_map_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
        if srs_chart is not None:
            return srs_chart
    scheduler_chart_names = {
        "MCS over time",
        "CQI vs selected MCS",
        "queue depth over time",
        "SR/BSR event timeline",
        "power control command timeline",
        "PHR distribution",
        "grant reason distribution",
    }
    harq_chart_names = {
        "RV usage distribution",
        "retransmission count histogram",
        "ACK/NACK timeline",
        "residual BLER by HARQ process",
        "combining gain histogram",
    }
    if chart_name in scheduler_chart_names:
        source_path, records = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            ["reports/csv/live_scheduler_cycle.csv", "packet_flow/csv/live_dl_scheduler_grants.csv", "packet_flow/csv/live_ul_scheduler_grants.csv"],
        )
        if records:
            dataset = None
            note = "Scheduler chart derived from persisted scheduler-cycle or grant runtime rows."
            if chart_name == "MCS over time":
                points = [[idx + 1, float(_row_float(row, "MCSIndex") or 0.0)] for idx, row in enumerate(records[:MAX_PREVIEW_ROWS]) if _row_float(row, "MCSIndex") is not None]
                dataset = {"mode": "line", "x_label": "Grant sample", "y_label": "MCSIndex", "points": points}
            elif chart_name == "CQI vs selected MCS":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    cqi = _row_float(row, "CQIUsed", "WidebandCQI")
                    mcs = _row_float(row, "MCSIndex")
                    if cqi is None or mcs is None:
                        continue
                    grouped[int(round(cqi))].append(float(mcs))
                points = [[float(cqi), sum(vals) / len(vals)] for cqi, vals in sorted(grouped.items())]
                dataset = {"mode": "line", "x_label": "CQI", "y_label": "Mean selected MCS", "points": points}
            elif chart_name == "queue depth over time":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    slot = _row_float(row, "Slot")
                    q_bytes = _row_float(row, "QueueBytesBefore", "QueueBytesAfter")
                    if slot is None or q_bytes is None:
                        continue
                    grouped[int(round(slot))].append(float(q_bytes))
                points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items())]
                dataset = {"mode": "line", "x_label": "Slot", "y_label": "Queue bytes", "points": points}
            elif chart_name == "SR/BSR event timeline":
                grouped: Counter[int] = Counter()
                for row in records:
                    slot = _row_float(row, "Slot")
                    if slot is None:
                        continue
                    if _row_text(row, "sr_state") or (_row_float(row, "bsr_amount") or 0.0) > 0.0:
                        grouped[int(round(slot))] += 1
                points = [[float(slot), float(count)] for slot, count in sorted(grouped.items())]
                dataset = {"mode": "line", "x_label": "Slot", "y_label": "SR/BSR events", "points": points}
            elif chart_name == "power control command timeline":
                grouped: Counter[int] = Counter()
                for row in records:
                    slot = _row_float(row, "Slot")
                    if slot is None:
                        continue
                    if _row_text(row, "power_control_command"):
                        grouped[int(round(slot))] += 1
                points = [[float(slot), float(count)] for slot, count in sorted(grouped.items())]
                dataset = {"mode": "line", "x_label": "Slot", "y_label": "Power-control commands", "points": points}
            elif chart_name == "PHR distribution":
                values = [float(value) for value in (_row_float(row, "phr_db") for row in records) if value is not None]
                if values:
                    bins = min(12, max(3, len(values)))
                    lo = min(values)
                    hi = max(values)
                    width = ((hi - lo) / bins) if not math.isclose(lo, hi) else 1.0
                    points = []
                    for bin_idx in range(bins):
                        center = lo + width * (bin_idx + 0.5)
                        count = sum(1 for value in values if (bin_idx == bins - 1 and value <= hi) or (lo + width * bin_idx <= value < lo + width * (bin_idx + 1)))
                        points.append([center, float(count)])
                    dataset = {"mode": "bar", "x_label": "PHR dB", "y_label": "Count", "points": points}
            elif chart_name == "grant reason distribution":
                counts = Counter(_row_text(row, "GrantReason") for row in records if _row_text(row, "GrantReason"))
                ordered = counts.most_common(16)
                points = [[float(idx + 1), float(count)] for idx, (_label, count) in enumerate(ordered)]
                note += " x-axis buckets correspond to the listed grant-reason order in the SVG summary."
                dataset = {"mode": "bar", "x_label": "Grant-reason bucket", "y_label": "Count", "points": points}
            if dataset and dataset.get("points"):
                summary = [f"source_table={source_path}", f"source_rows={len(records)}", f"chart={chart_name}"]
                if chart_name == "grant reason distribution":
                    counts = Counter(_row_text(row, "GrantReason") for row in records if _row_text(row, "GrantReason"))
                    summary.extend([f"bucket_{idx+1}={label}" for idx, (label, _count) in enumerate(counts.most_common(8))])
                csv_bytes = _chart_dataset_csv(run_id, chart_name, dataset, source_path, len(records), "derived_chart_dataset", note)
                img_bytes = _render_svg_plot(chart_name, "Runtime scheduler evidence rendered from persisted truthful rows.", dataset, summary)
                return {
                    "csv_bytes": csv_bytes,
                    "img_bytes": img_bytes,
                    "csv_status": "derived_chart_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": source_path,
                    "source_row_count": len(records),
                    "note": note,
                }
    if chart_name in harq_chart_names:
        source_path, records = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            ["harq/csv/live_harq_observation_timeline.csv", "reports/csv/live_harq_process_table.csv", "harq/csv/live_harq_observation_summary.csv"],
        )
        if records:
            dataset = None
            note = "HARQ chart derived from persisted runtime HARQ observation rows."
            if chart_name == "RV usage distribution":
                counts = Counter(int(round(_row_float(row, "RV") or -1)) for row in records if _row_float(row, "RV") is not None)
                points = [[float(rv), float(count)] for rv, count in sorted((rv, count) for rv, count in counts.items() if rv >= 0)]
                dataset = {"mode": "bar", "x_label": "RV", "y_label": "Count", "points": points}
            elif chart_name == "retransmission count histogram":
                per_process: Counter[str] = Counter()
                for row in records:
                    if _row_text(row, "IsRetransmission", "new_tx_or_retx").lower() in {"1", "true", "retx", "retransmission"}:
                        key = f"{_row_text(row, 'UEIndex', 'RNTI')}|{_row_text(row, 'HarqID', 'HARQProcess')}"
                        per_process[key] += 1
                counts = Counter(per_process.values())
                points = [[float(count_value), float(bucket_count)] for count_value, bucket_count in sorted(counts.items())]
                dataset = {"mode": "bar", "x_label": "Retransmissions per HARQ context", "y_label": "Count", "points": points}
            elif chart_name == "ACK/NACK timeline":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    slot = _row_float(row, "Slot")
                    decode_ok = _row_text(row, "CombinedDecodeOK", "CurrentDecodeOK", "ack_nack")
                    if slot is None or not decode_ok:
                        continue
                    grouped[int(round(slot))].append(1.0 if decode_ok.lower() in {"1", "true", "ack", "ok"} else 0.0)
                points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items())]
                dataset = {"mode": "line", "x_label": "Slot", "y_label": "ACK ratio", "points": points}
            elif chart_name == "residual BLER by HARQ process":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    harq_id = _row_float(row, "HarqID", "HARQProcess")
                    decode_ok = _row_text(row, "CombinedDecodeOK", "CurrentDecodeOK", "crc_result")
                    if harq_id is None or not decode_ok:
                        continue
                    grouped[int(round(harq_id))].append(0.0 if decode_ok.lower() in {"1", "true", "ack", "ok", "pass"} else 1.0)
                points = [[float(harq_id), sum(vals) / len(vals)] for harq_id, vals in sorted(grouped.items())]
                dataset = {"mode": "bar", "x_label": "HARQ process", "y_label": "Residual BLER", "points": points}
            elif chart_name == "combining gain histogram":
                improvements: list[float] = []
                for row in records:
                    current_ok = _row_text(row, "CurrentDecodeOK")
                    combined_ok = _row_text(row, "CombinedDecodeOK")
                    if not current_ok or not combined_ok:
                        continue
                    current_flag = 1.0 if current_ok.lower() in {"1", "true", "ack", "ok"} else 0.0
                    combined_flag = 1.0 if combined_ok.lower() in {"1", "true", "ack", "ok"} else 0.0
                    improvements.append(combined_flag - current_flag)
                counts = Counter(improvements)
                points = [[float(value), float(count)] for value, count in sorted(counts.items())]
                note = "Combining-gain histogram uses binary decode-improvement outcome from current-vs-combined HARQ decode states because this run does not persist a dB-valued combining gain field."
                dataset = {"mode": "bar", "x_label": "Combined decode improvement flag", "y_label": "Count", "points": points}
            if dataset and dataset.get("points"):
                summary = [f"source_table={source_path}", f"source_rows={len(records)}", f"chart={chart_name}"]
                csv_bytes = _chart_dataset_csv(run_id, chart_name, dataset, source_path, len(records), "derived_chart_dataset", note)
                img_bytes = _render_svg_plot(chart_name, "Runtime HARQ evidence rendered from persisted truthful rows.", dataset, summary)
                return {
                    "csv_bytes": csv_bytes,
                    "img_bytes": img_bytes,
                    "csv_status": "derived_chart_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": source_path,
                    "source_row_count": len(records),
                    "note": note,
                }
    if chart_name in {"scheduler fairness over time", "fairness index trend"}:
        source_path = ""
        for candidate in (
            "reports/csv/live_user_performance_snapshot.csv",
            "system/csv/system_ue_summary.csv",
        ):
            if candidate in existing:
                source_path = candidate
                break
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path) if source_path else ([], [])
        if records:
            csv_rows: list[dict[str, Any]] = []
            summary_lines: list[str] = []
            point_rows: list[dict[str, Any]] = []
            for metric_name, direction in (
                ("DL_Throughput_Mbps", "DL"),
                ("UL_Throughput_Mbps", "UL"),
                ("UserThroughput_Mbps", "Combined"),
            ):
                values: list[float] = []
                for row in records:
                    value = _row_float(row, metric_name)
                    if value is not None and math.isfinite(value):
                        values.append(float(value))
                if not values:
                    continue
                sorted_vals = sorted(values)
                total = sum(sorted_vals)
                total_sq = sum(v * v for v in sorted_vals)
                fairness = (total * total) / (len(sorted_vals) * total_sq) if sorted_vals and total_sq > 0 else 0.0
                summary_lines.append(
                    f"{direction}: Jain fairness={fairness:.4f}, mean={total/len(sorted_vals):.3f} Mbps, p95={_percentile(sorted_vals, 0.95):.3f} Mbps"
                )
                for idx, value in enumerate(sorted_vals, start=1):
                    row = {
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "direction": direction,
                        "ue_rank": idx,
                        "throughput_mbps": value,
                        "jain_fairness_index": fairness,
                        "source_table_logical_path": source_path,
                    }
                    csv_rows.append(row)
                    if direction == "Combined":
                        point_rows.append(row)
            plot_rows = point_rows or csv_rows
            if plot_rows:
                subtitle = "Per-UE throughput distribution from the runtime fairness source. This run exports a final user snapshot, not a slot-by-slot fairness timeline."
                dataset = {
                    "mode": "line",
                    "x_label": "UE rank (sorted by throughput)",
                    "y_label": "Throughput (Mbps)",
                    "points": [[float(row["ue_rank"]), float(row["throughput_mbps"])] for row in plot_rows[:MAX_PREVIEW_ROWS]],
                }
                return {
                    "csv_bytes": _encode_dict_rows(
                        ["run_id", "chart_name", "direction", "ue_rank", "throughput_mbps", "jain_fairness_index", "source_table_logical_path"],
                        csv_rows,
                    ),
                    "img_bytes": _render_svg_plot(chart_name, subtitle, dataset, summary_lines),
                    "csv_status": "specialized_runtime_fairness_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": source_path,
                    "source_row_count": len(records),
                    "note": "Fairness visualization derived from truthful per-UE runtime throughput evidence.",
                }
    if chart_name == "IQ imbalance summary":
        timeline_path = "rf/csv/iq_imbalance_timeline_trace.csv"
        summary_path = "rf/csv/probe_rf_iq_imbalance.csv"
        _, timeline_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, timeline_path)
        _, summary_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, summary_path)
        if not timeline_records and not summary_records:
            reason = "No dedicated RF IQ-imbalance runtime artifacts were persisted for this run."
            return {
                "csv_bytes": _encode_csv(
                    ["run_id", "chart_name", "status", "reason", "checked_sources"],
                    [[run_id, chart_name, "unavailable_exact_reason", reason, f"{timeline_path}|{summary_path}"]],
                ),
                "img_bytes": _render_reason_svg(chart_name, "The browser is preserving honesty for this RF impairment chart.", [reason]),
                "csv_status": "missing_source_summary",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": f"{timeline_path}|{summary_path}",
                "source_row_count": 0,
                "note": reason,
            }
        grouped: dict[tuple[str, int, int], dict[str, Any]] = {}
        measured_rows = 0
        for idx, row in enumerate(timeline_records, start=1):
            mirror = _row_float(row, "IQImbalanceMirrorPowerRatio_dB")
            image_rej = _row_float(row, "IQImbalanceImageRejection_dB")
            corr = _row_float(row, "IQImbalanceIQCorrelation")
            alpha = _row_float(row, "IQImbalanceEstimatedAlphaAbs")
            beta = _row_float(row, "IQImbalanceEstimatedBetaAbs")
            has_measurement = any(value is not None for value in (mirror, image_rej, corr, alpha, beta))
            if not has_measurement:
                continue
            direction = _row_text(row, "Direction") or "NA"
            frame_v = _row_float(row, "Frame")
            slot_v = _row_float(row, "Slot")
            frame_i = int(round(frame_v or 0.0))
            slot_i = int(round(slot_v or idx))
            key = (direction, frame_i, slot_i)
            bucket = grouped.setdefault(
                key,
                {
                    "direction": direction,
                    "frame": frame_i,
                    "slot": slot_i,
                    "sample_count": 0,
                    "image_rejection_sum": 0.0,
                    "image_rejection_count": 0,
                    "mirror_sum": 0.0,
                    "mirror_count": 0,
                    "corr_abs_sum": 0.0,
                    "corr_abs_count": 0,
                    "source_table_logical_path": timeline_path,
                },
            )
            bucket["sample_count"] += 1
            measured_rows += 1
            if image_rej is not None:
                bucket["image_rejection_sum"] += image_rej
                bucket["image_rejection_count"] += 1
            if mirror is not None:
                bucket["mirror_sum"] += mirror
                bucket["mirror_count"] += 1
            if corr is not None:
                bucket["corr_abs_sum"] += abs(corr)
                bucket["corr_abs_count"] += 1
        summary_lines = [f"timeline_source={timeline_path}", f"summary_source={summary_path}", f"timeline_rows={len(timeline_records)}", f"measured_rows={measured_rows}"]
        for row in summary_records[:4]:
            direction = _row_text(row, "Direction") or "ALL"
            availability = _row_text(row, "Availability") or "unknown"
            measured = int(round(_row_float(row, "MeasuredRowCount") or 0.0))
            applied = int(round(_row_float(row, "AppliedRowCount") or 0.0))
            mean_ir = _row_float(row, "MeanImageRejection_dB")
            model_set = _row_text(row, "ModelSet")
            line = f"{direction}: availability={availability} measured={measured} applied={applied}"
            if mean_ir is not None:
                line += f" mean_ir={mean_ir:.3f}dB"
            if model_set:
                line += f" model={model_set}"
            summary_lines.append(line)
        if not grouped:
            reason = "The dedicated IQ timeline exists, but it contains no finite sample-domain IQ-imbalance measurements."
            return {
                "csv_bytes": _encode_csv(
                    ["run_id", "chart_name", "status", "reason", "checked_sources"],
                    [[run_id, chart_name, "unavailable_exact_reason", reason, f"{timeline_path}|{summary_path}"]],
                ),
                "img_bytes": _render_reason_svg(chart_name, "The browser is preserving honesty for this RF impairment chart.", summary_lines + [reason]),
                "csv_status": "unavailable_exact_reason",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": f"{timeline_path}|{summary_path}",
                "source_row_count": len(timeline_records),
                "note": reason,
            }
        grouped_rows = sorted(grouped.values(), key=lambda row: (row["frame"], row["slot"], row["direction"]))
        csv_rows: list[dict[str, Any]] = []
        dataset_points: list[list[float]] = []
        for event_index, row in enumerate(grouped_rows, start=1):
            mean_image_rej = (
                row["image_rejection_sum"] / row["image_rejection_count"] if row["image_rejection_count"] else None
            )
            mean_mirror = row["mirror_sum"] / row["mirror_count"] if row["mirror_count"] else None
            mean_abs_corr = row["corr_abs_sum"] / row["corr_abs_count"] if row["corr_abs_count"] else None
            if mean_image_rej is not None:
                dataset_points.append([float(event_index), float(mean_image_rej)])
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "event_index": event_index,
                    "direction": row["direction"],
                    "frame": row["frame"],
                    "slot": row["slot"],
                    "sample_count": row["sample_count"],
                    "mean_image_rejection_db": mean_image_rej if mean_image_rej is not None else "",
                    "mean_mirror_power_ratio_db": mean_mirror if mean_mirror is not None else "",
                    "mean_abs_iq_correlation": mean_abs_corr if mean_abs_corr is not None else "",
                    "source_table_logical_path": timeline_path,
                }
            )
        dataset = {
            "mode": "line",
            "x_label": "Measured event index",
            "y_label": "Mean Image Rejection (dB)",
            "points": dataset_points,
        }
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id",
                    "chart_name",
                    "event_index",
                    "direction",
                    "frame",
                    "slot",
                    "sample_count",
                    "mean_image_rejection_db",
                    "mean_mirror_power_ratio_db",
                    "mean_abs_iq_correlation",
                    "source_table_logical_path",
                ],
                csv_rows,
            ),
            "img_bytes": _render_svg_plot(chart_name, "Sample-domain IQ-imbalance measurements aggregated from the persisted waveform TX/RX impairment runtime.", dataset, summary_lines),
            "csv_status": "specialized_runtime_iq_imbalance_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": f"{timeline_path}|{summary_path}",
            "source_row_count": len(grouped_rows),
            "note": "IQ-imbalance chart derived from dedicated runtime RF impairment artifacts.",
        }
    if chart_name in {"DL resource-grid heatmap", "PDSCH map", "PUSCH map", "PUCCH map"}:
        if chart_name in {"DL resource-grid heatmap", "PDSCH map"}:
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/dl_resource_grid_heatmap.csv")
            source_path = "reports/csv/dl_resource_grid_heatmap.csv"
            if not records:
                _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "packet_flow/csv/live_dl_scheduler_grants.csv")
                source_path = "packet_flow/csv/live_dl_scheduler_grants.csv"
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("CellID", "ServingCell", "BaseStationID"),
                    slot_names=("Slot", "Frame"),
                    rb_names=("PRBStart",),
                    occ_names=("AllocatedPRBCount", "PRBCount"),
                )
            else:
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("cell_id",),
                    slot_names=("slot",),
                    rb_names=("rb_index",),
                    occ_names=("occupancy_fraction", "occupancy_count"),
                )
        elif chart_name == "PUSCH map":
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/ul_resource_grid_heatmap.csv")
            source_path = "reports/csv/ul_resource_grid_heatmap.csv"
            if not records:
                _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "packet_flow/csv/live_ul_scheduler_grants.csv")
                source_path = "packet_flow/csv/live_ul_scheduler_grants.csv"
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("CellID", "ServingCell", "BaseStationID"),
                    slot_names=("Slot", "Frame"),
                    rb_names=("PRBStart",),
                    occ_names=("AllocatedPRBCount", "PRBCount"),
                )
            else:
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("cell_id",),
                    slot_names=("slot",),
                    rb_names=("rb_index",),
                    occ_names=("occupancy_fraction", "occupancy_count"),
                )
        else:
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "packet_flow/csv/live_pucch_grants.csv")
            source_path = "packet_flow/csv/live_pucch_grants.csv"
            chosen_cell = _selected_cell(records, "ServingCell", "BaseStationID")
            grid_rows = []
            for row in records:
                if chosen_cell and _row_text(row, "ServingCell", "BaseStationID") != chosen_cell:
                    continue
                slot_v = _row_float(row, "Slot")
                start_v = _row_float(row, "PUCCHPRBStart")
                count_v = _row_float(row, "PUCCHPRBCount")
                if slot_v is None or start_v is None or count_v is None:
                    continue
                for rb_idx in range(int(round(start_v)), int(round(start_v + count_v))):
                    grid_rows.append(
                        {
                            "cell_id": chosen_cell,
                            "slot": int(round(slot_v)),
                            "rb_index": rb_idx,
                            "occupancy_value": 1.0,
                        }
                    )
        if not grid_rows:
            return {
                "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason"], [[run_id, chart_name, "unavailable", "no_runtime_grid_rows"]]),
                "img_bytes": _render_reason_svg(chart_name, "No real grid rows were available for this run.", [f"source={source_path}", "The requested map was not rendered because no slot/PRB occupancy rows were found."]),
                "csv_status": "unavailable_exact_reason",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": source_path,
                "source_row_count": 0,
                "note": "No truthful grid occupancy rows were available.",
            }
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "slot", "rb_index", "occupancy_value")
        summary = [f"source={source_path}", f"selected_cell={chosen_cell or 'all'}", f"points={len(grid_rows)}"]
        if chart_name == "PUCCH map":
            summary.append("mode=scheduled_pending_execution_from_runtime_pucch_grants")
        csv_header = ["run_id", "chart_name", "cell_id", "slot", "rb_index", "occupancy_value", "source_table_logical_path"]
        csv_rows = [
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "cell_id": row.get("cell_id", ""),
                "slot": row.get("slot", ""),
                "rb_index": row.get("rb_index", ""),
                "occupancy_value": row.get("occupancy_value", ""),
                "source_table_logical_path": source_path,
            }
            for row in grid_rows
        ]
        return {
            "csv_bytes": _encode_dict_rows(csv_header, csv_rows),
            "img_bytes": _render_heatmap_svg(chart_name, "Runtime slot/RB occupancy derived from persisted waveform scheduler evidence.", x_labels, y_labels, matrix, summary, "Slot", "RB index"),
            "csv_status": "specialized_runtime_grid_dataset",
            "image_status": "generated_specialized_runtime_heatmap_svg",
            "source_table_path": source_path,
            "source_row_count": len(grid_rows),
            "note": "Heatmap built from truthful slot/RB occupancy evidence.",
        }
    if chart_name == "candidate cell rank heatmap":
        source_path = "reports/csv/live_candidate_cell_runtime.csv"
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
        if not records:
            source_path = "reports/csv/live_cell_measurement_trace.csv"
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
        rows = []
        for row in records:
            rank_v = _row_float(row, "candidate_rank", "CandidateRank")
            cell_v = _row_text(row, "cell_id", "CellID")
            if rank_v is None or not cell_v:
                continue
            rows.append(
                {
                    "candidate_rank": int(round(rank_v)),
                    "cell_id": cell_v,
                    "observation_count": float(_row_float(row, "candidate_observation_count") or 1.0),
                }
            )
        if not rows:
            return {
                "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason"], [[run_id, chart_name, "unavailable", "no_candidate_rank_rows"]]),
                "img_bytes": _render_reason_svg(chart_name, "No candidate-rank rows were persisted for this run.", [f"source={source_path}", "The candidate-cell heatmap was not rendered because no runtime rank observations were found."]),
                "csv_status": "unavailable_exact_reason",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": source_path,
                "source_row_count": 0,
                "note": "No truthful candidate-cell rank rows were available.",
            }
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(rows, "candidate_rank", "cell_id", "observation_count")
        summary = [f"source={source_path}", f"rows={len(rows)}", "note=matrix counts candidate-rank observations per cell from persisted runtime measurements."]
        csv_rows = [
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "candidate_rank": row["candidate_rank"],
                "cell_id": row["cell_id"],
                "observation_count": row["observation_count"],
                "source_table_logical_path": source_path,
            }
            for row in rows
        ]
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "candidate_rank", "cell_id", "observation_count", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_heatmap_svg(chart_name, "Runtime candidate-cell ranking density derived from persisted measurement-trace observations.", x_labels, y_labels, matrix, summary, "Candidate rank", "Cell"),
            "csv_status": "specialized_runtime_candidate_rank_dataset",
            "image_status": "generated_specialized_runtime_heatmap_svg",
            "source_table_path": source_path,
            "source_row_count": len(rows),
            "note": "Candidate-cell heatmap derived from real per-UE measurement-trace ranking rows.",
        }
    if chart_name in {"PDCCH map", "CCE usage heatmap"}:
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/pdcch_trials.csv")
        rows = []
        for row in records:
            slot_v = _row_float(row, "Slot")
            cell_v = _row_text(row, "BaseStationID", "CellID", "ServingCell")
            used_v = _row_float(row, "UsedCCECount")
            util_v = _row_float(row, "CORESETUtilization", "ControlCapacityUtilization")
            if slot_v is None or not cell_v:
                continue
            rows.append({"slot": int(round(slot_v)), "cell_id": cell_v, "occupancy_value": util_v if util_v is not None else float(used_v or 0.0), "UsedCCECount": used_v or 0.0})
        if not rows:
            return None
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(rows, "slot", "cell_id", "occupancy_value")
        summary = ["source=air_interface/csv/pdcch_trials.csv", f"rows={len(rows)}", "note=exact CCE-to-REG placement is not exported; this view uses runtime used-CCE / control utilization."]
        csv_header = ["run_id", "chart_name", "cell_id", "slot", "occupancy_value", "UsedCCECount", "source_table_logical_path"]
        csv_rows = [{**row, "run_id": run_id, "chart_name": chart_name, "source_table_logical_path": "air_interface/csv/pdcch_trials.csv"} for row in rows]
        return {
            "csv_bytes": _encode_dict_rows(csv_header, csv_rows),
            "img_bytes": _render_heatmap_svg(chart_name, "Runtime PDCCH control occupancy by slot and serving cell.", x_labels, y_labels, matrix, summary, "Slot", "Cell"),
            "csv_status": "specialized_runtime_control_dataset",
            "image_status": "generated_specialized_runtime_heatmap_svg",
            "source_table_path": "air_interface/csv/pdcch_trials.csv",
            "source_row_count": len(rows),
            "note": "Control-region occupancy derived from PDCCH runtime trials.",
        }
    if chart_name == "PBCH/SSB map":
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/pbch_trials.csv")
        rows = []
        for row in records:
            slot_v = _row_float(row, "Slot")
            cell_v = _row_text(row, "BaseStationID", "CellID", "ServingCell")
            note_text = _row_text(row, "Notes")
            if not cell_v or cell_v.lower() == "not_applicable":
                note_match = re.search(r"NCellID=(\d+)", note_text)
                if note_match:
                    cell_v = note_match.group(1)
            success_v = _row_float(row, "DecodeSuccess", "CRCPass")
            beam_v = _row_text(row, "SelectedBeamIndex")
            if not beam_v or beam_v.lower() == "not_applicable":
                ssb_match = re.search(r"SSBIdx=(\d+)", note_text)
                if ssb_match:
                    beam_v = ssb_match.group(1)
            if slot_v is None or not cell_v:
                continue
            rows.append({"slot": int(round(slot_v)), "cell_id": cell_v, "occupancy_value": float(success_v or 0.0), "SelectedBeamIndex": beam_v})
        if not rows:
            return None
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(rows, "slot", "cell_id", "occupancy_value")
        summary = ["source=air_interface/csv/pbch_trials.csv", f"rows={len(rows)}", "note=exact SSB RE mapping is not exported; this view shows runtime PBCH/SSB observation density and decode success."]
        csv_header = ["run_id", "chart_name", "cell_id", "slot", "occupancy_value", "SelectedBeamIndex", "source_table_logical_path"]
        csv_rows = [{**row, "run_id": run_id, "chart_name": chart_name, "source_table_logical_path": "air_interface/csv/pbch_trials.csv"} for row in rows]
        return {
            "csv_bytes": _encode_dict_rows(csv_header, csv_rows),
            "img_bytes": _render_heatmap_svg(chart_name, "Runtime PBCH/SSB observations by slot and cell.", x_labels, y_labels, matrix, summary, "Slot", "Cell"),
            "csv_status": "specialized_runtime_control_dataset",
            "image_status": "generated_specialized_runtime_heatmap_svg",
            "source_table_path": "air_interface/csv/pbch_trials.csv",
            "source_row_count": len(rows),
            "note": "PBCH/SSB occupancy summary derived from runtime PBCH observations.",
        }
    if chart_name == "UL resource-grid / equalized symbol summaries":
        _, grid_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/ul_resource_grid_heatmap.csv")
        _, preview_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/ul_constellation_preview.csv")
        _, trial_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/ul_pusch_trials.csv")
        grid_rows, chosen_cell = _build_grid_heatmap_records(
            grid_records,
            cell_names=("cell_id",),
            slot_names=("slot",),
            rb_names=("rb_index",),
            occ_names=("occupancy_fraction", "occupancy_count"),
        )
        if not grid_rows:
            return None
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "slot", "rb_index", "occupancy_value")
        mean_evm = [row for row in trial_records if _row_float(row, "EVM_rms") is not None]
        mean_evm_value = sum(_row_float(row, "EVM_rms") or 0.0 for row in mean_evm) / max(len(mean_evm), 1)
        panels = [("UL equalized symbols", [((_row_float(r, "EqualizedReal") or 0.0), (_row_float(r, "EqualizedImag") or 0.0), "UL") for r in preview_records[:600]], [((_row_float(r, "ReferenceSymbolReal") or 0.0), (_row_float(r, "ReferenceSymbolImag") or 0.0)) for r in preview_records[:64]])]
        summary = ["grid_source=reports/csv/ul_resource_grid_heatmap.csv", "preview_source=air_interface/csv/ul_constellation_preview.csv", f"selected_cell={chosen_cell or 'all'}", f"trial_rows={len(trial_records)}", f"mean_evm_rms={mean_evm_value:.6f}"]
        image = _render_scatter_panels_svg(chart_name, "UL resource occupancy plus equalized-symbol preview from real waveform runtime exports.", panels, summary)
        csv_rows = []
        for row in trial_records:
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "frame": _row_float(row, "Frame"),
                    "slot": _row_float(row, "Slot"),
                    "MeasuredSINR_dB": _row_float(row, "MeasuredSINR_dB"),
                    "EVM_rms": _row_float(row, "EVM_rms"),
                    "DecoderIterations": _row_float(row, "DecoderIterations"),
                    "Modulation": _row_text(row, "Modulation"),
                    "source_table_logical_path": "air_interface/csv/ul_pusch_trials.csv",
                }
            )
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "frame", "slot", "MeasuredSINR_dB", "EVM_rms", "DecoderIterations", "Modulation", "source_table_logical_path"], csv_rows),
            "img_bytes": image,
            "csv_status": "specialized_runtime_summary_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "air_interface/csv/ul_pusch_trials.csv|air_interface/csv/ul_constellation_preview.csv",
            "source_row_count": len(csv_rows),
            "note": "UL summary built from real PUSCH trials and equalized-symbol preview samples.",
        }
    if chart_name == "constellation per modulation order":
        _, dl_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/dl_constellation_preview.csv")
        _, ul_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/ul_constellation_preview.csv")
        all_records = [("DL", row) for row in dl_records] + [("UL", row) for row in ul_records]
        panels: list[tuple[str, list[tuple[float, float, str]], list[tuple[float, float]]]] = []
        csv_rows: list[dict[str, Any]] = []
        for modulation in ("QPSK", "16QAM", "64QAM"):
            points: list[tuple[float, float, str]] = []
            ideal: list[tuple[float, float]] = []
            for direction, row in all_records:
                if _row_text(row, "Modulation") != modulation:
                    continue
                eq_r = _row_float(row, "EqualizedReal")
                eq_i = _row_float(row, "EqualizedImag")
                ref_r = _row_float(row, "ReferenceSymbolReal")
                ref_i = _row_float(row, "ReferenceSymbolImag")
                if eq_r is None or eq_i is None:
                    continue
                points.append((eq_r, eq_i, direction))
                if ref_r is not None and ref_i is not None:
                    ideal.append((ref_r, ref_i))
                csv_rows.append(
                    {
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "direction": direction,
                        "modulation": modulation,
                        "EqualizedReal": eq_r,
                        "EqualizedImag": eq_i,
                        "ReferenceSymbolReal": ref_r,
                        "ReferenceSymbolImag": ref_i,
                        "source_table_logical_path": f"air_interface/csv/{direction.lower()}_constellation_preview.csv",
                    }
                )
            if points:
                panels.append((modulation, points[:500], ideal[:64]))
        if not panels:
            return None
        summary = ["source=air_interface/csv/dl_constellation_preview.csv|air_interface/csv/ul_constellation_preview.csv", f"points={len(csv_rows)}"]
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "modulation", "EqualizedReal", "EqualizedImag", "ReferenceSymbolReal", "ReferenceSymbolImag", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_scatter_panels_svg(chart_name, "Equalized runtime constellation samples grouped by modulation order.", panels, summary),
            "csv_status": "specialized_runtime_constellation_dataset",
            "image_status": "generated_specialized_runtime_constellation_svg",
            "source_table_path": "air_interface/csv/dl_constellation_preview.csv|air_interface/csv/ul_constellation_preview.csv",
            "source_row_count": len(csv_rows),
            "note": "Constellation grouped by modulation order using runtime equalized samples.",
        }
    if chart_name in {
        "Tx waveform",
        "Rx waveform",
        "magnitude vs sample",
        "phase vs sample",
        "power vs sample",
        "pre-channel waveform",
        "post-channel waveform",
        "post-impairment waveform",
        "stage overlay plots",
        "UE-wise / link-wise waveform comparison",
    }:
        source_path, records = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            ["analytics/csv/waveform_analytics.csv", "reports/csv/live_waveform_preview.csv", "reports/csv/live_tx_rx_stage_trace.csv"],
        )
        if records:
            csv_rows: list[dict[str, Any]] = []
            use_time_axis = any(_row_float(row, "Time_s") is not None for row in records)
            x_label = "Time_s" if use_time_axis else "SampleIndex"
            series: list[dict[str, Any]] = []
            summary = [f"source={source_path}", f"rows={len(records)}"]
            if chart_name in {"Tx waveform", "Rx waveform", "magnitude vs sample", "phase vs sample", "power vs sample"}:
                metric_specs: list[tuple[str, str, Callable[[dict[str, str]], float | None]]] = []
                if chart_name == "Tx waveform":
                    metric_specs = [
                        ("Tx real", "TxReal", lambda row: _row_float(row, "TxReal")),
                        ("Tx imag", "TxImag", lambda row: _row_float(row, "TxImag")),
                    ]
                elif chart_name == "Rx waveform":
                    metric_specs = [
                        ("Rx real", "RxReal", lambda row: _row_float(row, "RxReal")),
                        ("Rx imag", "RxImag", lambda row: _row_float(row, "RxImag")),
                    ]
                elif chart_name == "magnitude vs sample":
                    metric_specs = [
                        ("Tx magnitude", "TxMagnitude", lambda row: _row_float(row, "TxMagnitude")),
                        ("Rx magnitude", "RxMagnitude", lambda row: _row_float(row, "RxMagnitude")),
                    ]
                elif chart_name == "phase vs sample":
                    metric_specs = [
                        ("Tx phase", "TxPhase_rad", lambda row: math.atan2(_row_float(row, "TxImag") or 0.0, _row_float(row, "TxReal") or 0.0) if _row_float(row, "TxReal", "TxImag") is not None else None),
                        ("Rx phase", "RxPhase_rad", lambda row: math.atan2(_row_float(row, "RxImag") or 0.0, _row_float(row, "RxReal") or 0.0) if _row_float(row, "RxReal", "RxImag") is not None else None),
                    ]
                else:
                    metric_specs = [
                        ("Tx power", "TxPower", lambda row: (_row_float(row, "TxMagnitude") or 0.0) ** 2 if _row_float(row, "TxMagnitude") is not None else None),
                        ("Rx power", "RxPower", lambda row: (_row_float(row, "RxMagnitude") or 0.0) ** 2 if _row_float(row, "RxMagnitude") is not None else None),
                    ]
                for series_name, metric_name, resolver in metric_specs:
                    points: list[list[float]] = []
                    for row in records:
                        x_val = _row_float(row, x_label) if use_time_axis else _row_float(row, "SampleIndex")
                        if x_val is None:
                            continue
                        y_val = resolver(row)
                        if y_val is None or not math.isfinite(y_val):
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append(
                            {
                                "run_id": run_id,
                                "chart_name": chart_name,
                                x_label: x_val,
                                "series_name": series_name,
                                "metric_name": metric_name,
                                "metric_value": y_val,
                                "source_table_logical_path": source_path,
                            }
                        )
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 256)})
                if series:
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", x_label, "series_name", "metric_name", "metric_value", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_multi_series_svg(chart_name, "Sample-domain waveform traces rendered from persisted runtime preview samples.", series, summary, x_label=x_label, y_label="Amplitude / derived value"),
                        "csv_status": "specialized_runtime_waveform_dataset",
                        "image_status": "generated_specialized_runtime_waveform_svg",
                        "source_table_path": source_path,
                        "source_row_count": len(csv_rows),
                        "note": "Waveform chart derived from actual exported TX/RX preview samples.",
                    }
            if chart_name in {"pre-channel waveform", "post-channel waveform", "post-impairment waveform", "stage overlay plots", "UE-wise / link-wise waveform comparison"}:
                stage_rows = [row for row in records if _row_text(row, "Stage", "stage_name", "TraceStage")]
                if stage_rows:
                    wanted_stage_tokens = {
                        "pre-channel waveform": ("prechannel", "tx"),
                        "post-channel waveform": ("postchannel", "channel"),
                        "post-impairment waveform": ("postimpairment", "impairment"),
                    }
                    grouped: dict[str, list[list[float]]] = defaultdict(list)
                    for row in stage_rows:
                        stage_name = _row_text(row, "Stage", "stage_name", "TraceStage")
                        stage_token = re.sub(r"[^a-z0-9]+", "", stage_name.lower())
                        if chart_name in wanted_stage_tokens and not any(token in stage_token for token in wanted_stage_tokens[chart_name]):
                            continue
                        x_val = _row_float(row, "Time_s", "SampleIndex", "Slot", "Frame")
                        y_val = _row_float(row, "Magnitude", "Value", "Amplitude", "SignalValue")
                        if x_val is None or y_val is None:
                            continue
                        grouped[stage_name].append([float(x_val), float(y_val)])
                    if grouped:
                        stage_series = [{"name": name, "points": _downsample_points(points, 180)} for name, points in list(grouped.items())[:5] if points]
                        csv_rows = []
                        for name, points in grouped.items():
                            for x_val, y_val in points[:MAX_PREVIEW_ROWS]:
                                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "stage_name": name, "x_value": x_val, "metric_value": y_val, "source_table_logical_path": source_path})
                        return {
                            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "stage_name", "x_value", "metric_value", "source_table_logical_path"], csv_rows),
                            "img_bytes": _render_multi_series_svg(chart_name, "Stage-wise waveform evidence derived only from persisted stage-trace samples.", stage_series, summary, x_label="Time / sample", y_label="Magnitude"),
                            "csv_status": "specialized_runtime_stage_waveform_dataset",
                            "image_status": "generated_specialized_runtime_waveform_svg",
                            "source_table_path": source_path,
                            "source_row_count": len(csv_rows),
                            "note": "Stage waveform chart derived from persisted stage-trace samples when exported by runtime.",
                        }
    if chart_name in {"pre-equalization constellation", "post-equalization constellation", "EVM RMS", "symbol decision error histogram"}:
        dl_preview_path = "air_interface/csv/dl_constellation_preview.csv"
        ul_preview_path = "air_interface/csv/ul_constellation_preview.csv"
        _, dl_preview = _artifact_rows_by_path(existing, fetch_artifact_bytes, dl_preview_path)
        _, ul_preview = _artifact_rows_by_path(existing, fetch_artifact_bytes, ul_preview_path)
        preview_rows = [("DL", row, dl_preview_path) for row in dl_preview] + [("UL", row, ul_preview_path) for row in ul_preview]
        if chart_name in {"pre-equalization constellation", "post-equalization constellation"} and preview_rows:
            panels: list[tuple[str, list[tuple[float, float, str]], list[tuple[float, float]]]] = []
            csv_rows: list[dict[str, Any]] = []
            for direction in ("DL", "UL"):
                points: list[tuple[float, float, str]] = []
                ideal: list[tuple[float, float]] = []
                for row_direction, row, source_path in preview_rows:
                    if row_direction != direction:
                        continue
                    if chart_name == "pre-equalization constellation":
                        x_val = _row_float(row, "ReceivedReal", "RxReal")
                        y_val = _row_float(row, "ReceivedImag", "RxImag")
                    else:
                        x_val = _row_float(row, "EqualizedReal")
                        y_val = _row_float(row, "EqualizedImag")
                    if x_val is None or y_val is None:
                        continue
                    ref_r = _row_float(row, "ReferenceSymbolReal")
                    ref_i = _row_float(row, "ReferenceSymbolImag")
                    points.append((float(x_val), float(y_val), direction))
                    if ref_r is not None and ref_i is not None:
                        ideal.append((float(ref_r), float(ref_i)))
                    csv_rows.append(
                        {
                            "run_id": run_id,
                            "chart_name": chart_name,
                            "direction": direction,
                            "x_value": x_val,
                            "y_value": y_val,
                            "reference_x": ref_r if ref_r is not None else "",
                            "reference_y": ref_i if ref_i is not None else "",
                            "source_table_logical_path": source_path,
                        }
                    )
                if points:
                    panels.append((f"{direction} {chart_name.replace(' constellation', '')}", points[:450], ideal[:64]))
            if panels:
                return {
                    "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "x_value", "y_value", "reference_x", "reference_y", "source_table_logical_path"], csv_rows),
                    "img_bytes": _render_scatter_panels_svg(chart_name, "Constellation cloud from real runtime preview samples. Grey markers show ideal reference symbols when exported.", panels, [f"dl_rows={len(dl_preview)}", f"ul_rows={len(ul_preview)}"]),
                    "csv_status": "specialized_runtime_constellation_dataset",
                    "image_status": "generated_specialized_runtime_constellation_svg",
                    "source_table_path": f"{dl_preview_path}|{ul_preview_path}",
                    "source_row_count": len(csv_rows),
                    "note": "Constellation chart derived directly from persisted preview samples.",
                }
        if chart_name == "EVM RMS":
            trial_sources = _all_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"])
            named_values: list[tuple[str, float]] = []
            csv_rows: list[dict[str, Any]] = []
            for source_path, rows in trial_sources:
                direction = "DL" if "dl_pdsch" in source_path else "UL"
                evm_values = [float(value) for value in (_row_float(row, "EVM_rms") for row in rows) if value is not None]
                if not evm_values:
                    continue
                mean_evm = sum(evm_values) / len(evm_values)
                named_values.append((direction, mean_evm))
                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "direction": direction, "mean_evm_rms": mean_evm, "sample_count": len(evm_values), "source_table_logical_path": source_path})
            if named_values:
                dataset, summary = _bar_dataset_from_named_values("Direction bucket", "Mean EVM RMS", named_values)
                return {
                    "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "mean_evm_rms", "sample_count", "source_table_logical_path"], csv_rows),
                    "img_bytes": _render_svg_plot(chart_name, "Mean trial-level EVM from persisted waveform trials.", dataset, summary),
                    "csv_status": "specialized_runtime_evm_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": "|".join(source_path for source_path, _rows in trial_sources),
                    "source_row_count": len(csv_rows),
                    "note": "EVM RMS chart derived from trial-level runtime EVM fields.",
                }
        if chart_name == "symbol decision error histogram" and preview_rows:
            values: list[float] = []
            csv_rows: list[dict[str, Any]] = []
            for direction, row, source_path in preview_rows:
                eq_r = _row_float(row, "EqualizedReal")
                eq_i = _row_float(row, "EqualizedImag")
                ref_r = _row_float(row, "ReferenceSymbolReal")
                ref_i = _row_float(row, "ReferenceSymbolImag")
                if None in {eq_r, eq_i, ref_r, ref_i}:
                    continue
                error_mag = math.sqrt((float(eq_r) - float(ref_r)) ** 2 + (float(eq_i) - float(ref_i)) ** 2)
                values.append(error_mag)
                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "direction": direction, "decision_error_magnitude": error_mag, "source_table_logical_path": source_path})
            if values:
                bins = _bin_mean_points([(value, 1.0) for value in values], 16)
                dataset = {"mode": "bar", "x_label": "Decision error magnitude", "y_label": "Mean count per bin", "points": bins}
                return {
                    "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "decision_error_magnitude", "source_table_logical_path"], csv_rows),
                    "img_bytes": _render_svg_plot(chart_name, "Histogram of equalized-symbol distance to the nearest exported reference symbol.", dataset, [f"samples={len(values)}"]),
                    "csv_status": "specialized_runtime_symbol_error_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": f"{dl_preview_path}|{ul_preview_path}",
                    "source_row_count": len(csv_rows),
                    "note": "Decision-error histogram derived from preview equalized and reference symbols.",
                }
    if chart_name in {"BER", "BLER", "FER", "BLER vs SNR", "BLER vs SINR", "BER vs SNR", "FER vs SNR", "CRC pass/fail rates", "decoder iteration distributions", "per-UE and per-cell reliability"}:
        trial_rows = _trial_rows_with_paths(
            existing,
            fetch_artifact_bytes,
            ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/pdcch_trials.csv", "air_interface/csv/pucch_trials.csv", "air_interface/csv/pbch_trials.csv"],
        )
        if trial_rows:
            if chart_name in {"BLER vs SNR", "BLER vs SINR", "BER vs SNR", "FER vs SNR"}:
                pairs: list[tuple[float, float]] = []
                used_source_path = ""
                x_field = "ConfiguredSNR_dB" if "SNR" in chart_name and "SINR" not in chart_name else "MeasuredTrialSINR_dB"
                x_label = "ConfiguredSNR_dB" if "SNR" in chart_name and "SINR" not in chart_name else "MeasuredTrialSINR_dB"
                y_label = "BLER" if "BLER" in chart_name else ("FER" if "FER" in chart_name else "BER")
                for source_path, row in trial_rows:
                    x_val = _row_float(row, x_field, "AppliedAWGNSNR_dB", "MeasuredSINR_dB", "ReceiverHestSINR_dB")
                    if x_val is None:
                        continue
                    if y_label == "BER":
                        y_val = _trial_row_ber(row)
                    elif y_label == "FER":
                        y_val = 0.0 if _row_text(row, "CRCPass", "DecodeSuccess", "CombinedDecodeOK").lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 1.0
                    else:
                        y_val = _trial_row_bler(row)
                    if y_val is None:
                        continue
                    pairs.append((float(x_val), float(y_val)))
                    used_source_path = used_source_path or source_path
                if pairs:
                    csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label=x_label, y_label=y_label, chart_name=chart_name, run_id=run_id, source_path=used_source_path or "multiple_runtime_trials")
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, "Reliability metric aggregated from truthful trial rows.", dataset, [f"samples={len(pairs)}", f"x_axis={x_label}", f"y_axis={y_label}"]),
                        "csv_status": "specialized_runtime_reliability_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": used_source_path or "multiple_runtime_trials",
                        "source_row_count": len(pairs),
                        "note": "Reliability-vs-quality curve derived from actual trial BER/BLER/FER outcomes.",
                    }
            if chart_name in {"BER", "BLER", "FER", "CRC pass/fail rates"}:
                counts: Counter[str] = Counter()
                for _source_path, row in trial_rows:
                    if chart_name == "BER":
                        value = _trial_row_ber(row)
                        if value is not None:
                            counts["Mean BER"] += value
                            counts["BER samples"] += 1
                    elif chart_name == "BLER":
                        value = _trial_row_bler(row)
                        if value is not None:
                            counts["Mean BLER"] += value
                            counts["BLER samples"] += 1
                    elif chart_name == "FER":
                        token = _row_text(row, "CRCPass", "DecodeSuccess", "CombinedDecodeOK")
                        if token:
                            counts["Mean FER"] += 0.0 if token.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 1.0
                            counts["FER samples"] += 1
                    else:
                        token = _row_text(row, "CRCPass", "DecodeSuccess", "CombinedDecodeOK")
                        if token:
                            counts["Pass"] += 1 if token.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 0
                            counts["Fail"] += 0 if token.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 1
                named_values: list[tuple[str, float]] = []
                if chart_name == "CRC pass/fail rates":
                    named_values = [(key, float(value)) for key, value in counts.items() if key in {"Pass", "Fail"}]
                else:
                    sample_key = f"{chart_name} samples"
                    mean_key = f"Mean {chart_name}"
                    if counts.get(sample_key, 0) > 0:
                        named_values = [(chart_name, float(counts[mean_key]) / float(counts[sample_key]))]
                if named_values:
                    dataset, summary = _bar_dataset_from_named_values("Metric bucket", "Value", named_values)
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "metric_name": name, "metric_value": value, "source_table_logical_path": "multiple_runtime_trials"} for name, value in named_values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "metric_name", "metric_value", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Summary reliability metric from persisted waveform/control trials.", dataset, summary),
                        "csv_status": "specialized_runtime_reliability_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "multiple_runtime_trials",
                        "source_row_count": len(csv_rows),
                        "note": "Reliability summary built from persisted trial rows.",
                    }
            if chart_name == "decoder iteration distributions":
                values = [float(value) for _source_path, row in trial_rows for value in [_row_float(row, "DecoderIterations")] if value is not None]
                if values:
                    dataset = {"mode": "bar", "x_label": "Decoder iterations", "y_label": "Mean count per bin", "points": _bin_mean_points([(value, 1.0) for value in values], 14)}
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "decoder_iterations": value, "source_table_logical_path": "multiple_runtime_trials"} for value in values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "decoder_iterations", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Decoder-iteration distribution from persisted waveform trial rows.", dataset, [f"samples={len(values)}"]),
                        "csv_status": "specialized_runtime_decoder_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "multiple_runtime_trials",
                        "source_row_count": len(csv_rows),
                        "note": "Decoder iteration histogram derived from runtime decoder-trial rows.",
                    }
            if chart_name == "per-UE and per-cell reliability":
                reliability_rows: list[dict[str, Any]] = []
                grouped: dict[str, list[float]] = defaultdict(list)
                for source_path, row in trial_rows:
                    key = _row_text(row, "UEID", "UEIndex", "RNTI", "BaseStationID", "CellID", "ServingCell")
                    value = _trial_row_bler(row)
                    if not key or value is None:
                        continue
                    grouped[key].append(float(value))
                named_values = [(name, sum(values) / len(values)) for name, values in sorted(grouped.items(), key=lambda item: item[0])[:12] if values]
                if named_values:
                    dataset, summary = _bar_dataset_from_named_values("Entity bucket", "Mean BLER", named_values)
                    reliability_rows = [{"run_id": run_id, "chart_name": chart_name, "entity_name": name, "mean_bler": value, "source_table_logical_path": "multiple_runtime_trials"} for name, value in named_values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "entity_name", "mean_bler", "source_table_logical_path"], reliability_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Mean BLER by UE or serving-cell identifier from persisted trial rows.", dataset, summary),
                        "csv_status": "specialized_runtime_reliability_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "multiple_runtime_trials",
                        "source_row_count": len(reliability_rows),
                        "note": "Per-entity reliability summary derived from runtime trial outcomes.",
                    }
    if chart_name in {
        "throughput",
        "offered throughput",
        "goodput",
        "spectral efficiency",
        "throughput vs SNR",
        "throughput vs SINR",
        "throughput vs load",
        "goodput vs retransmissions",
        "per-UE throughput",
        "per-cell throughput",
        "throughput percentile plots",
        "throughput CDF",
    }:
        trial_sources = _all_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"])
        _, user_rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/live_user_performance_snapshot.csv")
        if trial_sources or user_rows:
            if chart_name in {"throughput", "offered throughput", "goodput", "spectral efficiency"}:
                named_values: list[tuple[str, float]] = []
                csv_rows: list[dict[str, Any]] = []
                for source_path, rows in trial_sources:
                    direction = "DL" if "dl_pdsch" in source_path else "UL"
                    if chart_name == "throughput":
                        values = [float(value) for value in (_row_float(row, "Throughput_Mbps", "MeasuredThroughput_Mbps", "OfferedThroughput_Mbps") for row in rows) if value is not None]
                    elif chart_name == "offered throughput":
                        values = [float(value) for value in (_row_float(row, "OfferedThroughput_Mbps") for row in rows) if value is not None]
                    elif chart_name == "goodput":
                        values = [float(value) for value in (_row_float(row, "Goodput_Mbps") for row in rows) if value is not None]
                    else:
                        values = [float(value) / 100.0 for value in (_row_float(row, "Goodput_Mbps", "Throughput_Mbps") for row in rows) if value is not None]
                    if not values:
                        continue
                    metric_value = sum(values) / len(values)
                    named_values.append((direction, metric_value))
                    csv_rows.append({"run_id": run_id, "chart_name": chart_name, "direction": direction, "metric_value": metric_value, "sample_count": len(values), "source_table_logical_path": source_path})
                if named_values:
                    y_label = "Mean spectral efficiency (b/s/Hz)" if chart_name == "spectral efficiency" else f"Mean {chart_name} (Mbps)"
                    dataset, summary = _bar_dataset_from_named_values("Direction bucket", y_label, named_values)
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "metric_value", "sample_count", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Direction-wise summary derived from persisted throughput/goodput trial rows.", dataset, summary),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "|".join(source_path for source_path, _rows in trial_sources),
                        "source_row_count": len(csv_rows),
                        "note": "Summary derived from truthful trial throughput/goodput fields.",
                    }
            if chart_name in {"throughput vs SNR", "throughput vs SINR", "throughput vs load", "goodput vs retransmissions"}:
                pairs: list[tuple[float, float]] = []
                source_token = ""
                if chart_name == "throughput vs SNR":
                    x_label = "ConfiguredSNR_dB"
                    y_label = "Throughput_Mbps"
                elif chart_name == "throughput vs SINR":
                    x_label = "MeasuredTrialSINR_dB"
                    y_label = "Throughput_Mbps"
                elif chart_name == "throughput vs load":
                    x_label = "AllocatedPRBCount"
                    y_label = "Throughput_Mbps"
                else:
                    x_label = "HARQRetxCount"
                    y_label = "Goodput_Mbps"
                for source_path, rows in trial_sources:
                    for row in rows:
                        if chart_name == "throughput vs SNR":
                            x_val = _row_float(row, "ConfiguredSNR_dB", "AppliedAWGNSNR_dB")
                        elif chart_name == "throughput vs SINR":
                            x_val = _row_float(row, "MeasuredTrialSINR_dB", "MeasuredSINR_dB", "ReceiverHestSINR_dB", "LargeScaleSINR_dB")
                        elif chart_name == "throughput vs load":
                            x_val = _row_float(row, "AllocatedPRBCount", "PRBCount", "NumPRB", "ScheduledPRBs")
                        else:
                            x_val = _row_float(row, "HARQRetxCount", "RetxCount", "RetransmissionCount")
                        if x_val is None:
                            continue
                        y_val = _row_float(row, y_label, "Goodput_Mbps", "Throughput_Mbps")
                        if y_val is None:
                            continue
                        pairs.append((float(x_val), float(y_val)))
                        source_token = source_token or source_path
                if pairs:
                    csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label=x_label, y_label=y_label, chart_name=chart_name, run_id=run_id, source_path=source_token or "multiple_runtime_trials")
                    subtitle = "Correlation view derived directly from persisted runtime throughput/goodput trials."
                    if chart_name == "throughput vs load":
                        subtitle = "Load view uses scheduled PRB count as the honest load proxy because this run exports one high-load operating point, not a sweep campaign."
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, subtitle, dataset, [f"samples={len(pairs)}"]),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": source_token or "multiple_runtime_trials",
                        "source_row_count": len(pairs),
                        "note": "Throughput relationship chart derived from truthful trial fields.",
                    }
            if chart_name in {"per-UE throughput", "throughput percentile plots", "throughput CDF"} and user_rows:
                values: list[float] = []
                csv_rows: list[dict[str, Any]] = []
                for row in user_rows:
                    ue_name = _row_text(row, "UEID", "UEIndex", "RNTI")
                    throughput = _row_float(row, "UserThroughput_Mbps", "DL_Throughput_Mbps", "UL_Throughput_Mbps")
                    if throughput is None:
                        continue
                    values.append(float(throughput))
                    csv_rows.append({"run_id": run_id, "chart_name": chart_name, "ue_name": ue_name or f"UE{len(csv_rows)+1}", "throughput_mbps": throughput, "source_table_logical_path": "reports/csv/live_user_performance_snapshot.csv"})
                if values:
                    sorted_values = sorted(values)
                    if chart_name == "per-UE throughput":
                        dataset = {"mode": "bar", "x_label": "UE rank", "y_label": "Throughput (Mbps)", "points": [[float(idx + 1), value] for idx, value in enumerate(sorted_values[:MAX_PREVIEW_ROWS])]}
                    elif chart_name == "throughput percentile plots":
                        percentiles = [(5, _percentile(sorted_values, 0.05)), (25, _percentile(sorted_values, 0.25)), (50, _percentile(sorted_values, 0.50)), (75, _percentile(sorted_values, 0.75)), (95, _percentile(sorted_values, 0.95))]
                        dataset = {"mode": "bar", "x_label": "Percentile", "y_label": "Throughput (Mbps)", "points": [[float(p), float(v)] for p, v in percentiles]}
                    else:
                        dataset = {"mode": "cdf", "x_label": "Throughput (Mbps)", "y_label": "CDF", "points": [[value, (idx + 1) / len(sorted_values)] for idx, value in enumerate(sorted_values[:MAX_PREVIEW_ROWS])]}
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "ue_name", "throughput_mbps", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Per-UE throughput distribution derived from the exported runtime user snapshot.", dataset, [f"ue_samples={len(values)}"]),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "reports/csv/live_user_performance_snapshot.csv",
                        "source_row_count": len(csv_rows),
                        "note": "User distribution view derived from truthful user-performance snapshot rows.",
                    }
            if chart_name == "per-cell throughput":
                grouped: dict[str, list[float]] = defaultdict(list)
                for source_path, rows in trial_sources:
                    for row in rows:
                        cell_name = _row_text(row, "BaseStationID", "ServingCell", "CellID")
                        throughput = _row_float(row, "Throughput_Mbps", "Goodput_Mbps", "MeasuredThroughput_Mbps")
                        if not cell_name or throughput is None:
                            continue
                        grouped[cell_name].append(float(throughput))
                named_values = [(cell_name, sum(values) / len(values)) for cell_name, values in sorted(grouped.items())[:12] if values]
                if named_values:
                    dataset, summary = _bar_dataset_from_named_values("Cell bucket", "Mean throughput (Mbps)", named_values)
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "cell_name": name, "throughput_mbps": value, "source_table_logical_path": "multiple_runtime_trials"} for name, value in named_values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "cell_name", "throughput_mbps", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Per-cell throughput derived from persisted runtime trials.", dataset, summary),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "multiple_runtime_trials",
                        "source_row_count": len(csv_rows),
                        "note": "Cell aggregation derived from truthful trial throughput rows.",
                    }
    if chart_name in {
        "configured SNR vs applied AWGN SNR vs measured SINR vs large-scale SINR",
        "configured vs applied vs measured SNR/SINR comparison",
        "ServingRSRP / RSRP / CSI-RSRP trends",
        "CQI / PMI / RI / CRI / SSBRI trends",
        "CQI-to-MCS mapping plot",
        "selected MCS distribution",
        "selected vs derived MCS confusion matrix",
        "quality-vs-selected-MCS mismatch plot",
        "per-beam quality plot",
        "per-layer quality plot",
    }:
        la_path, la_rows = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            ["reports/csv/live_link_adaptation_input_table.csv", "reports/csv/table_cqi_pmi_ri.csv", "reports/csv/live_rsrp_serving_trace.csv"],
        )
        if la_rows:
            if chart_name in {"configured SNR vs applied AWGN SNR vs measured SINR vs large-scale SINR", "configured vs applied vs measured SNR/SINR comparison"}:
                series_specs = [
                    ("Configured SNR", "ConfiguredSNR_dB"),
                    ("Applied AWGN SNR", "AppliedAWGNSNR_dB"),
                    ("Measured SINR", "MeasuredTrialSINR_dB"),
                    ("Measured wideband SINR", "MeasuredWidebandSINR_dB"),
                    ("Large-scale SINR", "LargeScaleSINR_dB"),
                ]
                series: list[dict[str, Any]] = []
                csv_rows: list[dict[str, Any]] = []
                for series_name, field_name in series_specs:
                    points: list[list[float]] = []
                    for idx, row in enumerate(la_rows, start=1):
                        x_val = _row_float(row, "Slot", "Frame")
                        if x_val is None:
                            x_val = float(idx)
                        y_val = _row_float(row, field_name)
                        if y_val is None:
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append({"run_id": run_id, "chart_name": chart_name, "slot_or_sample": x_val, "series_name": series_name, "metric_value_db": y_val, "source_table_logical_path": la_path})
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 160)})
                if series:
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot_or_sample", "series_name", "metric_value_db", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_multi_series_svg(chart_name, "Configured, applied, and measured quality metrics are kept separate and plotted directly from runtime export fields.", series, [f"rows={len(la_rows)}"], x_label="Slot / sample", y_label="dB"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "Comparison chart derived from truthful configured/applied/measured quality fields.",
                    }
            if chart_name == "ServingRSRP / RSRP / CSI-RSRP trends":
                rsrp_rows = la_rows
                series_specs = [("Serving RSRP", "ServingRSRP_dBm"), ("RSRP", "RSRP_dBm"), ("CSI-RSRP", "CSI_RSRP_dB")]
                series: list[dict[str, Any]] = []
                csv_rows: list[dict[str, Any]] = []
                for series_name, field_name in series_specs:
                    points: list[list[float]] = []
                    for idx, row in enumerate(rsrp_rows, start=1):
                        x_val = _row_float(row, "Slot", "Frame")
                        if x_val is None:
                            x_val = float(idx)
                        y_val = _row_float(row, field_name)
                        if y_val is None:
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append({"run_id": run_id, "chart_name": chart_name, "slot_or_sample": x_val, "series_name": series_name, "metric_value": y_val, "source_table_logical_path": la_path})
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 160)})
                if series:
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot_or_sample", "series_name", "metric_value", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_multi_series_svg(chart_name, "Serving RSRP, generic RSRP, and CSI-RSRP trends from runtime measurement exports.", series, [f"rows={len(rsrp_rows)}"], x_label="Slot / sample", y_label="dB / dBm"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "RSRP trend chart derived from runtime measurement rows.",
                    }
            if chart_name == "CQI / PMI / RI / CRI / SSBRI trends":
                series_specs = [("CQI", "WidebandCQI"), ("PMI", "PMI"), ("RI", "RI"), ("CRI", "CRI"), ("SSBRI", "SSBRI")]
                series: list[dict[str, Any]] = []
                csv_rows: list[dict[str, Any]] = []
                for series_name, field_name in series_specs:
                    points: list[list[float]] = []
                    for idx, row in enumerate(la_rows, start=1):
                        x_val = _row_float(row, "Slot", "Frame")
                        if x_val is None:
                            x_val = float(idx)
                        y_val = _row_float(row, field_name)
                        if y_val is None:
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append({"run_id": run_id, "chart_name": chart_name, "slot_or_sample": x_val, "series_name": series_name, "metric_value": y_val, "source_table_logical_path": la_path})
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 160)})
                if series:
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot_or_sample", "series_name", "metric_value", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_multi_series_svg(chart_name, "CQI/PMI/RI/CRI/SSBRI trends from runtime link-adaptation inputs.", series, [f"rows={len(la_rows)}"], x_label="Slot / sample", y_label="Index / reported value"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "CSI feedback trend chart derived from runtime measurement rows.",
                    }
            if chart_name == "CQI-to-MCS mapping plot":
                pairs = [(float(cqi), float(mcs)) for row in la_rows for cqi, mcs in [(_row_float(row, "WidebandCQI"), _row_float(row, "CQIDerivedMCS", "MCSIndex"))] if cqi is not None and mcs is not None]
                if pairs:
                    csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label="WidebandCQI", y_label="DerivedOrSelectedMCS", chart_name=chart_name, run_id=run_id, source_path=la_path)
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, "CQI-to-MCS mapping observed in runtime link-adaptation rows.", dataset, [f"samples={len(pairs)}"]),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(pairs),
                        "note": "CQI-to-MCS mapping derived from runtime CQI and MCS fields.",
                    }
            if chart_name == "selected MCS distribution":
                values = [float(value) for value in (_row_float(row, "MCSIndex", "CQIDerivedMCS") for row in la_rows) if value is not None]
                if values:
                    dataset = {"mode": "bar", "x_label": "MCS", "y_label": "Mean count per bin", "points": _bin_mean_points([(value, 1.0) for value in values], 18)}
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "mcs_index": value, "source_table_logical_path": la_path} for value in values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "mcs_index", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Distribution of selected runtime MCS values.", dataset, [f"samples={len(values)}"]),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "MCS distribution derived from runtime link-adaptation rows.",
                    }
            if chart_name == "selected vs derived MCS confusion matrix":
                matrix_rows: list[dict[str, Any]] = []
                raw_rows: list[dict[str, Any]] = []
                for row in la_rows:
                    selected = _row_float(row, "MCSIndex")
                    derived = _row_float(row, "CQIDerivedMCS")
                    if selected is None or derived is None:
                        continue
                    raw_rows.append({"selected_mcs": int(round(selected)), "derived_mcs": int(round(derived)), "count": 1.0})
                if raw_rows:
                    x_labels, y_labels, matrix = _grid_rows_to_heatmap(raw_rows, "derived_mcs", "selected_mcs", "count")
                    matrix_rows = [{"run_id": run_id, "chart_name": chart_name, "selected_mcs": row["selected_mcs"], "derived_mcs": row["derived_mcs"], "count": row["count"], "source_table_logical_path": la_path} for row in raw_rows]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "selected_mcs", "derived_mcs", "count", "source_table_logical_path"], matrix_rows),
                        "img_bytes": _render_heatmap_svg(chart_name, "Confusion matrix between applied MCS and CQI-derived MCS from runtime rows.", x_labels, y_labels, matrix, [f"samples={len(raw_rows)}"], "Derived MCS", "Selected MCS"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_heatmap_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(matrix_rows),
                        "note": "Selected-versus-derived MCS matrix derived from runtime link-adaptation rows.",
                    }
            if chart_name == "quality-vs-selected-MCS mismatch plot":
                pairs = [(float(quality), float(mcs)) for row in la_rows for quality, mcs in [(_row_float(row, "MeasuredTrialSINR_dB", "MeasuredWidebandSINR_dB", "ReceiverHestSINR_dB"), _row_float(row, "MCSIndex"))] if quality is not None and mcs is not None]
                if pairs:
                    csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label="MeasuredQuality_dB", y_label="SelectedMCS", chart_name=chart_name, run_id=run_id, source_path=la_path)
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, "Quality-to-selected-MCS trend from runtime adaptation rows.", dataset, [f"samples={len(pairs)}"]),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(pairs),
                        "note": "Mismatch/trend plot derived from measured quality and selected MCS.",
                    }
            if chart_name in {"per-beam quality plot", "per-layer quality plot"}:
                field_name = "BeamIndex" if chart_name == "per-beam quality plot" else "LayerIndex"
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in la_rows:
                    group_value = _row_float(row, field_name, "SelectedBeamIndex" if field_name == "BeamIndex" else "Layers")
                    quality = _row_float(row, "MeasuredTrialSINR_dB", "MeasuredWidebandSINR_dB", "ReceiverHestSINR_dB")
                    if group_value is None or quality is None:
                        continue
                    grouped[int(round(group_value))].append(float(quality))
                named_values = [(str(name), sum(values) / len(values)) for name, values in sorted(grouped.items()) if values]
                if named_values:
                    dataset, summary = _bar_dataset_from_named_values("Bucket", "Mean quality (dB)", named_values[:16])
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "bucket_name": name, "mean_quality_db": value, "source_table_logical_path": la_path} for name, value in named_values[:16]]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "bucket_name", "mean_quality_db", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Mean quality grouped by exported beam or layer identifier.", dataset, summary),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "Grouped quality chart derived from runtime beam/layer identifiers when exported.",
                    }
    if chart_name in {"BS/sector/UE topology scatter plot", "serving cell map"}:
        site_path, site_rows = _first_available_rows(existing, fetch_artifact_bytes, ["reports/csv/sites.csv"])
        ue_path, ue_rows = _first_available_rows(existing, fetch_artifact_bytes, ["reports/csv/live_rsrp_serving_trace.csv", "reports/csv/live_ue_table.csv"])
        if site_rows or ue_rows:
            use_geo = any(_row_float(row, "Lon") is not None and _row_float(row, "Lat") is not None for row in ue_rows[:8] + site_rows[:8])
            x_names = ("Lon", "X_m") if use_geo else ("X_m", "Lon")
            y_names = ("Lat", "Y_m") if use_geo else ("Y_m", "Lat")
            x_label = "Longitude" if use_geo else "X (m)"
            y_label = "Latitude" if use_geo else "Y (m)"
            series: list[dict[str, Any]] = []
            csv_rows: list[dict[str, Any]] = []
            site_points: list[list[float]] = []
            for row in site_rows:
                x_val = _row_float(row, *x_names)
                y_val = _row_float(row, *y_names)
                if x_val is None or y_val is None:
                    continue
                site_points.append([float(x_val), float(y_val)])
                csv_rows.append({
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "series_name": "Sites",
                    "x_value": x_val,
                    "y_value": y_val,
                    "label": _row_text(row, "SiteID", "MapAnchorLabel"),
                    "source_table_logical_path": site_path,
                })
            if site_points:
                series.append({"name": "Sites", "points": site_points[:32]})
            latest_ue: dict[str, dict[str, str]] = {}
            for row in ue_rows:
                ue_key = _row_text(row, "UEID", "UEIndex", "RNTI")
                if ue_key:
                    latest_ue[ue_key] = row
            if chart_name == "BS/sector/UE topology scatter plot":
                ue_points: list[list[float]] = []
                for row in latest_ue.values():
                    x_val = _row_float(row, *x_names)
                    y_val = _row_float(row, *y_names)
                    if x_val is None or y_val is None:
                        continue
                    ue_points.append([float(x_val), float(y_val)])
                    csv_rows.append({
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "series_name": "UEs",
                        "x_value": x_val,
                        "y_value": y_val,
                        "label": _row_text(row, "UEID", "UEIndex"),
                        "source_table_logical_path": ue_path,
                    })
                if ue_points:
                    series.append({"name": "UEs", "points": _downsample_points(ue_points, 220), "color": "#2563eb"})
            else:
                grouped_points: dict[str, list[list[float]]] = defaultdict(list)
                for row in latest_ue.values():
                    x_val = _row_float(row, *x_names)
                    y_val = _row_float(row, *y_names)
                    if x_val is None or y_val is None:
                        continue
                    cell_name = _row_text(row, "ServingCell", "ServingSector", "ServingSite") or "Unknown cell"
                    grouped_points[cell_name].append([float(x_val), float(y_val)])
                    csv_rows.append({
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "series_name": cell_name,
                        "x_value": x_val,
                        "y_value": y_val,
                        "label": _row_text(row, "UEID", "UEIndex"),
                        "source_table_logical_path": ue_path,
                    })
                for idx, (cell_name, points) in enumerate(sorted(grouped_points.items())[:8]):
                    series.append({"name": f"Cell {cell_name}", "points": _downsample_points(points, 70)})
            if series:
                summary = [
                    f"sites={len(site_points)}",
                    f"ue_points={max(0, len(csv_rows) - len(site_points))}",
                    f"coordinate_mode={'geo' if use_geo else 'projected'}",
                ]
                return {
                    "csv_bytes": _encode_dict_rows(
                        ["run_id", "chart_name", "series_name", "x_value", "y_value", "label", "source_table_logical_path"],
                        csv_rows,
                    ),
                    "img_bytes": _render_multi_series_svg(
                        chart_name,
                        "Topology and serving-cell placement derived from persisted runtime geometry and measurement rows.",
                        series,
                        summary,
                        x_label=x_label,
                        y_label=y_label,
                        mode="scatter",
                    ),
                    "csv_status": "specialized_runtime_geometry_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": "|".join(path for path in [site_path, ue_path] if path),
                    "source_row_count": len(csv_rows),
                    "note": "Scatter/map view derived from persisted site geometry and UE placement rows.",
                }
    if chart_name == "requested vs resolved format confusion matrix":
        pucch_path, pucch_rows = _first_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/pucch_trials.csv"])
        if pucch_rows:
            raw_rows: list[dict[str, Any]] = []
            csv_rows: list[dict[str, Any]] = []
            for row in pucch_rows:
                requested = _row_float(row, "RequestedFormat")
                resolved = _row_text(row, "ResolvedFormat")
                if requested is None or not resolved:
                    continue
                raw_rows.append({"requested_format": int(round(requested)), "resolved_format": resolved, "count": 1.0})
                csv_rows.append({
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "requested_format": int(round(requested)),
                    "resolved_format": resolved,
                    "count": 1,
                    "source_table_logical_path": pucch_path,
                })
            if raw_rows:
                x_labels, y_labels, matrix = _grid_rows_to_heatmap(raw_rows, "requested_format", "resolved_format", "count")
                return {
                    "csv_bytes": _encode_dict_rows(
                        ["run_id", "chart_name", "requested_format", "resolved_format", "count", "source_table_logical_path"],
                        csv_rows,
                    ),
                    "img_bytes": _render_heatmap_svg(
                        chart_name,
                        "Requested-vs-resolved PUCCH format usage from persisted runtime trials.",
                        x_labels,
                        y_labels,
                        matrix,
                        [f"samples={len(raw_rows)}"],
                        "Requested format",
                        "Resolved format",
                    ),
                    "csv_status": "specialized_runtime_pucch_dataset",
                    "image_status": "generated_specialized_runtime_heatmap_svg",
                    "source_table_path": pucch_path,
                    "source_row_count": len(csv_rows),
                    "note": "PUCCH format confusion matrix derived from truthful runtime trial rows.",
                }
    unavailable_reasons = {
        "pre-equalization constellation": "The run does not export raw pre-equalization I/Q sample clouds, so a pre-equalization constellation plot cannot be reconstructed honestly.",
        "pre-channel waveform": "The run does not export stage-resolved pre-channel sample traces, so this stage-specific waveform view cannot be reconstructed honestly.",
        "post-channel waveform": "The run does not export stage-resolved post-channel sample traces, so this stage-specific waveform view cannot be reconstructed honestly.",
        "post-impairment waveform": "The run does not export stage-resolved post-impairment sample traces, so this stage-specific waveform view cannot be reconstructed honestly.",
        "stage overlay plots": "The run does not export enough stage-resolved sample traces to build an honest overlay of internal waveform stages.",
        "UE-wise / link-wise waveform comparison": "The run exports a single runtime waveform preview, not a full UE-by-UE waveform sample bank suitable for an honest comparison chart.",
        "constellation per codeword": "No codeword identifier is exported in the runtime constellation preview rows for this run.",
        "constellation per layer": "No per-layer equalized constellation samples are exported in the runtime preview rows for this run.",
        "EVM per symbol": "The run exports only trial-level EVM_rms plus raw sample previews; it does not export OFDM-symbol-indexed EVM rows.",
        "EVM per subcarrier": "The run does not export subcarrier-indexed EVM rows for DL or UL previews.",
        "EVM per layer": "The run does not export layer-indexed EVM rows in the persisted waveform previews.",
    }
    if chart_name in unavailable_reasons:
        reason = unavailable_reasons[chart_name]
        csv_bytes = _encode_csv(
            ["run_id", "chart_name", "status", "reason", "checked_sources"],
            [[run_id, chart_name, "unavailable_exact_reason", reason, "air_interface/csv/dl_constellation_preview.csv|air_interface/csv/ul_constellation_preview.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv"]],
        )
        return {
            "csv_bytes": csv_bytes,
            "img_bytes": _render_reason_svg(chart_name, "The browser is preserving honesty for this chart family.", [reason, "No synthetic per-layer/per-codeword/per-symbol/per-subcarrier values were generated."]),
            "csv_status": "unavailable_exact_reason",
            "image_status": "generated_unavailable_reason_svg",
            "source_table_path": "air_interface/csv/dl_constellation_preview.csv|air_interface/csv/ul_constellation_preview.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv",
            "source_row_count": 0,
            "note": reason,
        }
    return None


def _write_file_if_possible(run_folder: str | None, logical_path: str, data: bytes) -> None:
    root = str(run_folder or "").strip()
    if not root:
        return
    try:
        target = Path(root) / Path(*str(logical_path).split("/"))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    except OSError:
        return


def _store_artifact(
    db_connection_factory: Callable[[], Any],
    run_id: int,
    logical_path: str,
    artifact_kind: str,
    mime_type: str,
    data: bytes,
    metadata: dict[str, Any],
) -> int:
    payload = json.dumps(metadata, ensure_ascii=False, default=str)
    with db_connection_factory() as conn:
        with conn.cursor(buffered=True) as cur:
            cur.execute(
                "SELECT artifact_id FROM sim_artifacts WHERE run_id=%s AND logical_path=%s",
                (run_id, logical_path),
            )
            rows = cur.fetchall()
            for row in rows:
                artifact_id = int(row[0] if isinstance(row, (tuple, list)) else row.get("artifact_id"))
                cur.execute("DELETE FROM sim_artifact_chunks WHERE artifact_id=%s", (artifact_id,))
                cur.execute("DELETE FROM sim_artifacts WHERE artifact_id=%s", (artifact_id,))
            cur.execute(
                """
                INSERT INTO sim_artifacts
                (run_id, logical_path, artifact_kind, mime_type, byte_size, metadata_json, created_utc)
                VALUES (%s, %s, %s, %s, %s, %s, UTC_TIMESTAMP())
                """,
                (run_id, logical_path, artifact_kind, mime_type, len(data), payload),
            )
            artifact_id = int(cur.lastrowid)
            chunk_size = 512 * 1024
            for chunk_index, start in enumerate(range(0, len(data), chunk_size), start=1):
                cur.execute(
                    """
                    INSERT INTO sim_artifact_chunks (artifact_id, chunk_index, chunk_data)
                    VALUES (%s, %s, %s)
                    """,
                    (artifact_id, chunk_index, data[start : start + chunk_size]),
                )
        conn.commit()
    return artifact_id


def _table_specs() -> list[dict[str, Any]]:
    return output_contract.iter_table_specs("reports") + output_contract.iter_table_specs("analytics")


def _chart_specs() -> list[dict[str, Any]]:
    return output_contract.iter_chart_specs("reports") + output_contract.iter_chart_specs("analytics")


def _table_sources(table_name: str) -> list[str]:
    return list(CONTRACT_TABLE_ALIAS_PATHS.get(str(table_name or "").strip(), []))


def _chart_sources(chart_name: str) -> list[str]:
    return list(CONTRACT_CHART_ALIAS_PATHS.get(str(chart_name or "").strip(), []))


def _artifact_metadata_json(
    artifact: dict[str, Any] | None,
    db_connection_factory: Callable[[], Any],
) -> str:
    if not artifact:
        return ""
    inline = str(artifact.get("metadata_json") or "").strip()
    if inline:
        return inline
    artifact_id = int(artifact.get("artifact_id") or 0)
    if artifact_id <= 0:
        return ""
    with db_connection_factory() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT metadata_json FROM sim_artifacts WHERE artifact_id=%s", (artifact_id,))
            row = cur.fetchone()
    if row is None:
        return ""
    return str(row[0] if isinstance(row, (tuple, list)) else row.get("metadata_json") or "").strip()


def _fetch_run_artifacts(
    run_id: int,
    db_connection_factory: Callable[[], Any],
) -> list[dict[str, Any]]:
    with db_connection_factory() as conn:
        with conn.cursor(dictionary=True) as cur:
            cur.execute(
                """
                SELECT artifact_id, run_id, logical_path, artifact_kind, mime_type,
                       byte_size, created_utc
                FROM sim_artifacts
                WHERE run_id = %s
                ORDER BY artifact_id ASC
                """,
                (run_id,),
            )
            return [dict(row or {}) for row in cur.fetchall()]


@contextmanager
def _materialization_lock(
    run_id: int,
    db_connection_factory: Callable[[], Any],
    timeout_seconds: int,
):
    lock_name = f"sixgr_contract_materialize_run_{int(run_id)}"
    acquired = False
    conn = db_connection_factory()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT GET_LOCK(%s, %s)", (lock_name, max(0, int(timeout_seconds))))
            row = cur.fetchone()
            acquired = bool(row) and int((row[0] if isinstance(row, (tuple, list)) else row.get("GET_LOCK(%s, %s)")) or 0) == 1
        yield acquired
    finally:
        if acquired:
            try:
                with conn.cursor() as cur:
                    cur.execute("DO RELEASE_LOCK(%s)", (lock_name,))
            except Exception:
                pass
        try:
            conn.close()
        except Exception:
            pass


def _artifact_has_current_materializer_version(
    artifact: dict[str, Any] | None,
    db_connection_factory: Callable[[], Any],
) -> bool:
    payload = _artifact_metadata_json(artifact, db_connection_factory)
    return bool(payload) and payload.find(MATERIALIZER_VERSION) >= 0


def _existing_contract_artifacts_current(
    existing: dict[str, dict[str, Any]],
    db_connection_factory: Callable[[], Any],
    feature_policy: dict[str, bool] | None = None,
) -> bool:
    feature_policy = dict(feature_policy or {})
    for table_spec in _table_specs():
        table_name = str(table_spec.get("table_name") or "")
        if table_name in OPTIONAL_6G_TABLES and not any(feature_policy.values()):
            continue
        artifact = existing.get(table_contract_path(table_spec))
        if artifact is None or not _artifact_has_current_materializer_version(artifact, db_connection_factory):
            return False
    for chart_spec in _chart_specs():
        chart_name = str(chart_spec.get("chart_name") or "")
        if chart_name in OPTIONAL_6G_CHARTS and not any(feature_policy.values()):
            continue
        csv_artifact = existing.get(chart_contract_csv_path(chart_spec))
        image_artifact = existing.get(chart_contract_image_path(chart_spec))
        if csv_artifact is None or image_artifact is None:
            return False
        if not _artifact_has_current_materializer_version(csv_artifact, db_connection_factory):
            return False
        if not _artifact_has_current_materializer_version(image_artifact, db_connection_factory):
            return False
    return True


def coverage_summary(
    artifacts: list[dict[str, Any]],
    feature_policy: dict[str, bool] | None = None,
) -> dict[str, Any]:
    feature_policy = dict(feature_policy or {})
    logical_paths = {str(art.get("logical_path") or "").strip() for art in artifacts if str(art.get("logical_path") or "").strip()}
    table_specs = _table_specs()
    chart_specs = _chart_specs()
    missing_tables: list[str] = []
    missing_charts: list[str] = []
    policy_disabled_tables = 0
    policy_disabled_charts = 0
    for table_spec in table_specs:
        table_name = str(table_spec.get("table_name") or "")
        if table_name in OPTIONAL_6G_TABLES and not any(feature_policy.values()):
            policy_disabled_tables += 1
            continue
        target_path = table_contract_path(table_spec)
        if target_path not in logical_paths:
            missing_tables.append(target_path)
    for chart_spec in chart_specs:
        chart_name = str(chart_spec.get("chart_name") or "")
        if chart_name in OPTIONAL_6G_CHARTS and not any(feature_policy.values()):
            policy_disabled_charts += 1
            continue
        csv_path = chart_contract_csv_path(chart_spec)
        img_path = chart_contract_image_path(chart_spec)
        if csv_path not in logical_paths or img_path not in logical_paths:
            missing_charts.append(chart_name)
    return {
        "tables_total": len(table_specs),
        "tables_policy_disabled": policy_disabled_tables,
        "tables_available": len(table_specs) - policy_disabled_tables - len(missing_tables),
        "charts_total": len(chart_specs),
        "charts_policy_disabled": policy_disabled_charts,
        "charts_available": len(chart_specs) - policy_disabled_charts - len(missing_charts),
        "missing_table_paths": missing_tables,
        "missing_chart_names": missing_charts,
    }


def materialize_run_contract_artifacts(
    run_row: dict[str, Any],
    artifacts: list[dict[str, Any]],
    *,
    fetch_artifact_bytes: Callable[[int], bytes],
    db_connection_factory: Callable[[], Any],
    feature_policy: dict[str, bool] | None = None,
    force: bool = False,
    lock_timeout_seconds: int = 0,
) -> dict[str, Any]:
    run_id = int(run_row.get("run_id") or 0)
    run_folder = str(run_row.get("run_folder") or "")
    created: list[dict[str, Any]] = []
    manifest_rows: list[list[Any]] = []
    feature_policy = dict(feature_policy or {})
    with _materialization_lock(run_id, db_connection_factory, int(lock_timeout_seconds)) as lock_acquired:
        if not lock_acquired:
            return {
                "created": created,
                "manifest_path": manifest_logical_path(),
                "coverage_path": coverage_logical_path(),
                "coverage": coverage_summary(artifacts, feature_policy),
                "skipped": True,
                "lock_busy": True,
            }
        artifacts = _fetch_run_artifacts(run_id, db_connection_factory)
        existing = {str(art.get("logical_path") or ""): art for art in artifacts}
        source_lookup = dict(existing)
        contract_owned_paths = _contract_owned_paths(artifacts, db_connection_factory)

        manifest_art = existing.get(manifest_logical_path())
        manifest_meta_json = _artifact_metadata_json(manifest_art, db_connection_factory)
        try:
            manifest_meta = json.loads(manifest_meta_json) if manifest_meta_json else {}
        except Exception:
            manifest_meta = {}
        run_status = str(run_row.get("status_text") or "").strip().lower()
        current_source_watermark = _source_artifact_high_watermark(artifacts, db_connection_factory)
        manifest_current = (
            manifest_art
            and manifest_meta_json.find(MATERIALIZER_VERSION) >= 0
            and (
                run_status not in {"running"}
                or int(manifest_meta.get("source_artifact_high_watermark") or 0) >= current_source_watermark
            )
        )
        coverage_snapshot = coverage_summary(list(existing.values()), feature_policy)
        contract_paths_current = not coverage_snapshot.get("missing_table_paths") and not coverage_snapshot.get("missing_chart_names")
        if manifest_current and contract_paths_current and not force:
            return {
                "created": created,
                "manifest_path": manifest_logical_path(),
                "coverage_path": coverage_logical_path(),
                "coverage": coverage_snapshot,
                "skipped": True,
            }
        if manifest_art is not None:
            for path in list(contract_owned_paths):
                existing.pop(path, None)
            source_lookup = dict(existing)

        for table_spec in _table_specs():
            table_name = str(table_spec.get("table_name") or "")
            if table_name in OPTIONAL_6G_TABLES and not any(feature_policy.values()):
                continue
            target_path = table_contract_path(table_spec)
            if not target_path or target_path in existing:
                continue
            source_art = None
            special = _specialized_table_materialization(
                table_name,
                source_lookup,
                fetch_artifact_bytes,
                run_id,
                str(table_spec.get("section_title") or ""),
                run_row=run_row,
                feature_policy=feature_policy,
            )
            if special is not None:
                data = bytes(special["data"])
                status = str(special.get("status") or "specialized_runtime_table")
                note = str(special.get("note") or "")
                source_row_count = int(special.get("source_row_count") or 0)
                source_logical_path = str(special.get("source_logical_path") or "")
            else:
                source_paths = _table_sources(table_name)
                source_art, source_data, header, rows = _select_source_table_artifact(source_paths, source_lookup, fetch_artifact_bytes)
                source_logical_path = str(source_art.get("logical_path") or "") if source_art else ""
                if source_art and str(source_art.get("artifact_kind") or "") == "table_csv":
                    if rows:
                        data = source_data
                        status = "copied_source_table"
                        note = f"Canonical contract table copied from {source_art['logical_path']}."
                        source_row_count = len(rows)
                    else:
                        header, summary_rows = _summary_csv_rows(
                            run_id,
                            str(table_spec.get("section_title") or ""),
                            table_name,
                            "source_artifact_present_but_empty",
                            source_logical_path,
                            0,
                            "The source artifact exists for this run, but it has no real rows.",
                        )
                        data = _encode_csv(header, summary_rows)
                        status = "empty_source_summary"
                        note = "Canonical contract table summarizes an empty source artifact."
                        source_row_count = 0
                else:
                    header, summary_rows = _summary_csv_rows(
                        run_id,
                        str(table_spec.get("section_title") or ""),
                        table_name,
                        "source_artifact_missing",
                        "",
                        0,
                        "No direct aliased source artifact was published for this run, so this contract table records the absence explicitly.",
                    )
                    data = _encode_csv(header, summary_rows)
                    status = "missing_source_summary"
                    note = "Canonical contract table records missing source evidence."
                    source_row_count = 0
            metadata = {
                "materializer_version": MATERIALIZER_VERSION,
                "contract_table": table_name,
                "section_slug": table_spec.get("section_slug"),
                "source_logical_path": source_logical_path,
                "source_row_count": source_row_count,
                "materialization_status": status,
            }
            _write_file_if_possible(run_folder, target_path, data)
            artifact_id = _store_artifact(
                db_connection_factory,
                run_id,
                target_path,
                "table_csv",
                "text/csv; charset=UTF-8",
                data,
                metadata,
            )
            created.append({"logical_path": target_path, "artifact_id": artifact_id, "status": status})
            manifest_rows.append([target_path, "table_csv", status, metadata.get("source_logical_path", ""), note])
            new_artifact = {
                "artifact_id": artifact_id,
                "logical_path": target_path,
                "artifact_kind": "table_csv",
                "mime_type": "text/csv; charset=UTF-8",
            }
            existing[target_path] = new_artifact
            source_lookup[target_path] = new_artifact

        section_tables: dict[str, list[str]] = {}
        for table_spec in _table_specs():
            section_tables.setdefault(str(table_spec.get("section_slug") or ""), []).append(table_contract_path(table_spec))

        for chart_spec in _chart_specs():
            chart_name = str(chart_spec.get("chart_name") or "")
            if chart_name in OPTIONAL_6G_CHARTS and not any(feature_policy.values()):
                continue
            target_csv = chart_contract_csv_path(chart_spec)
            target_img = chart_contract_image_path(chart_spec)
            if target_csv in existing and target_img in existing:
                continue
            special = _specialized_chart_materialization(chart_name, source_lookup, fetch_artifact_bytes, run_id)
            if special is not None:
                chart_csv_bytes = bytes(special["csv_bytes"])
                image_bytes = bytes(special["img_bytes"])
                csv_status = str(special.get("csv_status") or "specialized_contract_dataset")
                image_status = str(special.get("image_status") or "generated_specialized_contract_image")
                source_table_path = str(special.get("source_table_path") or "")
                source_row_count = int(special.get("source_row_count") or 0)
                chart_csv_note = str(special.get("note") or "")
                image_kind = "image_svg"
                image_mime = "image/svg+xml"
                source_image = None
                source_table = source_lookup.get(source_table_path)
                csv_meta = {
                    "materializer_version": MATERIALIZER_VERSION,
                    "chart_name": chart_name,
                    "section_slug": chart_spec.get("section_slug"),
                    "source_table_logical_path": source_table_path,
                    "source_row_count": source_row_count,
                    "materialization_status": csv_status,
                }
                img_meta = {
                    "materializer_version": MATERIALIZER_VERSION,
                    "chart_name": chart_name,
                    "section_slug": chart_spec.get("section_slug"),
                    "source_image_logical_path": "",
                    "source_table_logical_path": source_table_path,
                    "materialization_status": image_status,
                }
                _write_file_if_possible(run_folder, target_csv, chart_csv_bytes)
                csv_artifact_id = _store_artifact(
                    db_connection_factory,
                    run_id,
                    target_csv,
                    "table_csv",
                    "text/csv; charset=UTF-8",
                    chart_csv_bytes,
                    csv_meta,
                )
                _write_file_if_possible(run_folder, target_img, image_bytes)
                img_artifact_id = _store_artifact(
                    db_connection_factory,
                    run_id,
                    target_img,
                    image_kind,
                    image_mime,
                    image_bytes,
                    img_meta,
                )
                created.append({"logical_path": target_csv, "artifact_id": csv_artifact_id, "status": csv_status})
                created.append({"logical_path": target_img, "artifact_id": img_artifact_id, "status": image_status})
                manifest_rows.append([target_csv, "table_csv", csv_status, source_table_path, chart_name])
                manifest_rows.append([target_img, image_kind, image_status, source_table_path, chart_name])
                csv_artifact = {
                    "artifact_id": csv_artifact_id,
                    "logical_path": target_csv,
                    "artifact_kind": "table_csv",
                    "mime_type": "text/csv; charset=UTF-8",
                }
                img_artifact = {
                    "artifact_id": img_artifact_id,
                    "logical_path": target_img,
                    "artifact_kind": image_kind,
                    "mime_type": image_mime,
                }
                existing[target_csv] = csv_artifact
                existing[target_img] = img_artifact
                source_lookup[target_csv] = csv_artifact
                source_lookup[target_img] = img_artifact
                continue
            source_image = next(
                (
                    source_lookup[path]
                    for path in _chart_sources(chart_name)
                    if path in source_lookup and str(source_lookup[path].get("mime_type") or "").startswith("image/")
                ),
                None,
            )
            source_table = next(
                (
                    source_lookup[path]
                    for path in _chart_sources(chart_name)
                    if path in source_lookup and str(source_lookup[path].get("artifact_kind") or "") == "table_csv"
                ),
                None,
            )
            if source_table is None:
                for logical_path in section_tables.get(str(chart_spec.get("section_slug") or ""), []):
                    art = source_lookup.get(logical_path)
                    if art and str(art.get("artifact_kind") or "") == "table_csv":
                        source_table = art
                        break
            summary_lines = [
                f"chart={chart_name}",
                f"section={chart_spec.get('section_title') or ''}",
                f"kind={chart_spec.get('kind') or ''}",
                f"source_image={source_image.get('logical_path') if source_image else ''}",
                f"source_table={source_table.get('logical_path') if source_table else ''}",
            ]
            dataset = None
            chart_csv_bytes: bytes
            csv_status = "lineage_summary"
            source_table_path = str(source_table.get("logical_path") or "") if source_table else ""
            source_row_count = 0
            chart_csv_note = "No direct source table was published for this chart family in the selected run."
            if source_table:
                source_table_bytes = fetch_artifact_bytes(int(source_table["artifact_id"]))
                header, rows = _decode_csv(source_table_bytes)
                if rows:
                    source_row_count = len(rows)
                    summary_lines.append(f"source_rows={source_row_count}")
                    dict_rows = [{str(header[idx]): str(row[idx]) if idx < len(row) else "" for idx in range(len(header))} for row in rows]
                    placeholder_status = _table_placeholder_summary_status(dict_rows)
                    if placeholder_status in {"source_artifact_missing", "source_artifact_present_but_empty"}:
                        dataset = None
                        csv_status = placeholder_status
                        chart_csv_note = _row_text(dict_rows[0], "lineage_note", "reason") or (
                            "The aliased source table is itself a placeholder summary, so no truthful numeric chart was materialized."
                        )
                        summary_lines.append(f"placeholder_status={placeholder_status}")
                    else:
                        dataset = _dataset_from_rows(chart_name, header, rows)
                        csv_status = "derived_chart_dataset"
                        chart_csv_note = (
                            "Canonical chart CSV derived from the selected run's persisted source table. "
                            "The full raw source table remains stored separately."
                        )
                else:
                    chart_csv_note = "The source chart table exists but has no rows for this run."
                    summary_lines.append("source_rows=0")
                    csv_status = "empty_source_summary"
            else:
                summary_lines.append("source_rows=0")
                csv_status = "missing_source_summary"
            chart_csv_bytes = _chart_dataset_csv(
                run_id,
                chart_name,
                dataset,
                source_table_path,
                source_row_count,
                csv_status,
                chart_csv_note,
            )
            if source_image:
                image_bytes = fetch_artifact_bytes(int(source_image["artifact_id"]))
                image_kind = str(source_image.get("artifact_kind") or "image")
                image_mime = str(source_image.get("mime_type") or "image/png")
                image_status = "copied_source_image"
            elif csv_status in {
                "source_artifact_missing",
                "source_artifact_present_but_empty",
                "empty_source_summary",
                "missing_source_summary",
            }:
                image_bytes = _render_reason_svg(
                    chart_name,
                    "No truthful numeric chart was materialized from the selected source table for this run.",
                    summary_lines + [chart_csv_note],
                )
                image_kind = "image_svg"
                image_mime = "image/svg+xml"
                image_status = "generated_unavailable_reason_svg"
            else:
                image_bytes = _render_svg_plot(
                    chart_name,
                    "Canonical post-run chart materialized from the selected run's persisted source artifacts.",
                    dataset,
                    summary_lines,
                )
                image_kind = "image_svg"
                image_mime = "image/svg+xml"
                image_status = "generated_contract_summary_svg"

            csv_meta = {
                "materializer_version": MATERIALIZER_VERSION,
                "chart_name": chart_name,
                "section_slug": chart_spec.get("section_slug"),
                "source_table_logical_path": source_table_path,
                "source_row_count": source_row_count,
                "materialization_status": csv_status,
            }
            img_meta = {
                "materializer_version": MATERIALIZER_VERSION,
                "chart_name": chart_name,
                "section_slug": chart_spec.get("section_slug"),
                "source_image_logical_path": str(source_image.get("logical_path") or "") if source_image else "",
                "source_table_logical_path": str(source_table.get("logical_path") or "") if source_table else "",
                "materialization_status": image_status,
            }
            _write_file_if_possible(run_folder, target_csv, chart_csv_bytes)
            csv_artifact_id = _store_artifact(
                db_connection_factory,
                run_id,
                target_csv,
                "table_csv",
                "text/csv; charset=UTF-8",
                chart_csv_bytes,
                csv_meta,
            )
            _write_file_if_possible(run_folder, target_img, image_bytes)
            img_artifact_id = _store_artifact(
                db_connection_factory,
                run_id,
                target_img,
                image_kind,
                image_mime,
                image_bytes,
                img_meta,
            )
            created.append({"logical_path": target_csv, "artifact_id": csv_artifact_id, "status": csv_status})
            created.append({"logical_path": target_img, "artifact_id": img_artifact_id, "status": image_status})
            manifest_rows.append([target_csv, "table_csv", csv_status, csv_meta.get("source_table_logical_path", ""), chart_name])
            manifest_rows.append([target_img, image_kind, image_status, img_meta.get("source_image_logical_path", "") or img_meta.get("source_table_logical_path", ""), chart_name])
            csv_artifact = {
                "artifact_id": csv_artifact_id,
                "logical_path": target_csv,
                "artifact_kind": "table_csv",
                "mime_type": "text/csv; charset=UTF-8",
            }
            img_artifact = {
                "artifact_id": img_artifact_id,
                "logical_path": target_img,
                "artifact_kind": image_kind,
                "mime_type": image_mime,
            }
            existing[target_csv] = csv_artifact
            existing[target_img] = img_artifact
            source_lookup[target_csv] = csv_artifact
            source_lookup[target_img] = img_artifact

    manifest_header = ["logical_path", "artifact_kind", "materialization_status", "source_logical_path", "note"]
    manifest_bytes = _encode_csv(manifest_header, manifest_rows or [[manifest_logical_path(), "table_csv", "no_changes", "", "All canonical contract artifacts already existed for this run."]])
    manifest_meta = {
        "materializer_version": MATERIALIZER_VERSION,
        "created_count": len(created),
        "source_artifact_high_watermark": current_source_watermark,
    }
    _write_file_if_possible(run_folder, manifest_logical_path(), manifest_bytes)
    _store_artifact(
        db_connection_factory,
        run_id,
        manifest_logical_path(),
        "table_csv",
        "text/csv; charset=UTF-8",
        manifest_bytes,
        manifest_meta,
    )
    final_artifacts = list(existing.values())
    coverage = coverage_summary(final_artifacts, feature_policy)
    coverage_bytes = _encode_csv(
        [
            "run_id",
            "materializer_version",
            "tables_total",
            "tables_available",
            "tables_policy_disabled",
            "tables_missing",
            "charts_total",
            "charts_available",
            "charts_policy_disabled",
            "charts_missing",
            "missing_table_paths",
            "missing_chart_names",
        ],
        [[
            run_id,
            MATERIALIZER_VERSION,
            coverage["tables_total"],
            coverage["tables_available"],
            coverage["tables_policy_disabled"],
            len(coverage["missing_table_paths"]),
            coverage["charts_total"],
            coverage["charts_available"],
            coverage["charts_policy_disabled"],
            len(coverage["missing_chart_names"]),
            "; ".join(coverage["missing_table_paths"]) or "[]",
            "; ".join(coverage["missing_chart_names"]) or "[]",
        ]],
    )
    coverage_meta = {
        "materializer_version": MATERIALIZER_VERSION,
        "tables_missing_count": len(coverage["missing_table_paths"]),
        "charts_missing_count": len(coverage["missing_chart_names"]),
    }
    _write_file_if_possible(run_folder, coverage_logical_path(), coverage_bytes)
    _store_artifact(
        db_connection_factory,
        run_id,
        coverage_logical_path(),
        "table_csv",
        "text/csv; charset=UTF-8",
        coverage_bytes,
        coverage_meta,
    )
    return {
        "created": created,
        "manifest_path": manifest_logical_path(),
        "coverage_path": coverage_logical_path(),
        "coverage": coverage,
        "skipped": False,
    }
