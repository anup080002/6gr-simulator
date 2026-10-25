"""Original applied-layer groups: descriptive diagnostics, not rank-gain studies."""
from __future__ import annotations

import hashlib
import json
import math
import xml.etree.ElementTree as ET

CHART = "Applied rank KPI diagnostics"
SOURCE = "reports/csv/applied_rank_kpi_diagnostics.csv"
TRIALS = {"DL": "air_interface/csv/dl_pdsch_trials.csv",
          "UL": "air_interface/csv/ul_pusch_trials.csv"}
SCOPE = "actual_applied_Layers_groups_mixed_MCS_channel_attempts_diagnostic_not_controlled_rank_gain"
IDENTITY_FIELDS = (
    "RunID RunTag ExecutionID ConfigHash ScenarioID RandomSeed ChannelSeed SweepPointIndex "
    "ConfiguredSNR_dB SNR_dB Direction UEIndex UEID ServingCell CellID Frame Slot SFN "
    "ReceiverID ReceiverWindowID ReceiverObservationSHA256 GrantContextId FrozenGrantContextId "
    "TransportBlockId HARQProcessID HARQRound IsRetransmission RV MCSIndex MCS MCSTable "
    "Layers ObservationStartSample ObservationEndSampleExclusive ObservationSampleRateHz"
).split()


def _number(row, field, *, missing=False):
    text = str(row.get(field, "")).strip()
    if text.lower() in {"", "nan", "<missing>"}:
        if missing:
            return None
        raise ValueError(f"Missing original applied-rank {field}")
    try:
        value = float(text)
    except ValueError as cause:
        raise ValueError(f"Invalid applied-rank {field}") from cause
    if not math.isfinite(value):
        raise ValueError(f"Nonfinite applied-rank {field}")
    return value


def _integer(row, field, *, positive=False, missing=False):
    value = _number(row, field, missing=missing)
    if value is None:
        return None
    if value != int(value) or value >= 2**53 or value < int(positive):
        raise ValueError(f"Invalid original integer {field}")
    return int(value)


def _membership(text):
    try:
        value = json.loads(text)
    except (TypeError, ValueError) as cause:
        raise ValueError("Invalid original SourceRowsJSON") from cause
    values = value if isinstance(value, list) else [value]
    if not values or any(isinstance(x, bool) or not isinstance(x, (int, float)) or
                         not math.isfinite(x) or x != int(x) or x < 1 or x >= 2**53 for x in values):
        raise ValueError("SourceRowsJSON must retain original positive row indices")
    values = [int(x) for x in values]
    if values != sorted(set(values)):
        raise ValueError("Original rank membership must be ordered and unique")
    return values


def _equal(actual, expected, field):
    if actual is None or expected is None:
        if actual is not expected:
            raise ValueError(f"Applied-rank {field} availability changed")
    elif abs(actual - expected) > 128 * math.ulp(max(1.0, abs(actual), abs(expected))):
        raise ValueError(f"Applied-rank {field} does not match original operands")


def _load(m, existing, fetch, path):
    artifact = existing.get(path)
    if artifact is None:
        return [], ""
    payload = fetch(int(artifact["artifact_id"]))
    _, rows = m._decode_csv_dicts(payload)
    return rows, hashlib.sha256(payload).hexdigest()


def _unavailable(m, reason):
    # An unavailable diagnostic is not a numeric rank population or success.
    return {"csv_bytes": m._encode_csv(["status", "reason"], [["unavailable", reason]]),
            "img_bytes": m._render_reason_svg(CHART, "No qualified source groups to plot.", [reason]),
            "csv_status": "unavailable_exact_reason", "image_status": "generated_unavailable_reason_svg",
            "source_table_path": SOURCE, "source_row_count": 0, "note": reason}


def applied_rank_chart(m, name, existing, fetch, run_id):
    if name != CHART:
        return None
    from lls_sweep_report import _sch_acceptance, _sch_flag

    groups, group_sha = _load(m, existing, fetch, SOURCE)
    if not groups:
        return _unavailable(m, "Original applied-rank group CSV has no observations.")
    sources = {d: _load(m, existing, fetch, path) for d, path in TRIALS.items()}
    expected = {}
    for direction, (trials, _) in sources.items():
        for index, row in enumerate(trials, 1):
            if str(row.get("Direction", "")).upper() != direction:
                raise ValueError("Original trial direction differs from its applied-rank source")
            rank = _integer(row, "Layers", positive=True, missing=True)
            expected.setdefault((direction, rank), []).append(index)
    seen = set()
    plotted, throughput, bler = [], [], []
    for index, group in enumerate(groups, 1):
        direction = str(group.get("Direction", "")).upper()
        rank = _integer(group, "AppliedLayers", positive=True, missing=True)
        key = (direction, rank)
        members = _membership(group.get("SourceRowsJSON", ""))
        if key in seen or expected.get(key) != members:
            raise ValueError("Applied-rank group differs from exact original trial membership")
        seen.add(key)
        if group.get("Scope") != SCOPE or _sch_flag(group, "StatisticalIndependenceClaimed") != 0:
            raise ValueError("Applied-rank diagnostic scope/independence claim changed")
        trials, trial_sha = sources[direction]
        selected = [trials[i-1] for i in members]
        errors, audit = [], []
        for source_index, row in zip(members, selected):
            accepted, reason = _sch_acceptance(row, direction)
            if accepted:
                errors.append(1 - _sch_flag(row, "CRCPass"))
            audit.append({"SourceRowIndex": source_index,
                          **{field: row[field] for field in IDENTITY_FIELDS if field in row},
                          "CompletedSCHOutcomeCounted": accepted, "OutcomeExclusionReason": reason})
        count, failures = len(errors), sum(errors)
        mean_rate = None
        rate_field = ""
        # Match the source writer's per-group first-available metric rule;
        # this is NOT whole-run goodput or a pooled throughput campaign.
        for field in ("Goodput_Mbps", "OfferedThroughput_Mbps", "Throughput_Mbps"):
            values = [_number(row, field, missing=True) for row in selected]
            values = [x for x in values if x is not None]
            if values:
                mean_rate, rate_field = math.fsum(values) / len(values), field
                break
        for field, expected_count in (("SourceObservationCount", len(members)),
                                      ("CompletedDecodeAttemptCount", count), ("CRCErrorCount", failures)):
            if _integer(group, field) != expected_count:
                raise ValueError(f"Applied-rank {field} does not match original population")
        _equal(_number(group, "CompletedAttemptBLER", missing=True), failures/count if count else None, "BLER")
        _equal(_number(group, "MeanTrialThroughput_Mbps", missing=True), mean_rate, "mean trial throughput")
        points = sorted({(row.get("SweepPointIndex", ""), row.get("ConfiguredSNR_dB", "")) for row in selected})
        if len(points) > 1:
            point_label = f"mixed operating points ({len(points)})"
        elif points[0] != ("", ""):
            point_label = f"point={points[0][0] or '?'} configured SNR={points[0][1] or '?'} dB"
        else:
            point_label = "operating point unspecified"
        label = f"{direction} layers={'unknown' if rank is None else rank}; {point_label}"
        if mean_rate is not None:
            throughput.append({"name": f"{label}; {rate_field}", "points": [[index, mean_rate]]})
        if count:
            bler.append({"name": f"{label}; completed={count}", "points": [[index, failures/count]]})
        plotted.append({"run_id": run_id, "group_index": index, "direction": direction,
                        "applied_layers": "" if rank is None else rank, "group_label": label,
                        "source_rows_json": group["SourceRowsJSON"],
                        "source_observation_count": len(members), "completed_decode_attempt_count": count,
                        "crc_error_count": failures, "completed_attempt_bler": "" if not count else failures/count,
                        "mean_trial_throughput_mbps": "" if mean_rate is None else mean_rate,
                        "throughput_source_field": rate_field,
                        "source_group_row_index": index, "source_group_csv": SOURCE,
                        "source_group_csv_sha256": group_sha, "source_trial_csv": TRIALS[direction],
                        "source_trial_csv_sha256": trial_sha,
                        "source_observation_identity_json": json.dumps(audit, separators=(",", ":")),
                        "original_operating_points_json": json.dumps(points, separators=(",", ":")),
                        "statistical_independence_claimed": False, "controlled_rank_gain_qualified": False,
                        "scope": SCOPE})
    if seen != set(expected):
        raise ValueError("Applied-rank diagnostic omits original trial groups")
    # Two separate units/panels. Unknown rank remains a labelled category,
    # never rank zero; no interpolation or cross-rank line is drawn.
    panels = []
    for title, series, unit in (("Mean per-trial throughput diagnostic", throughput, "Mean trial rate (Mbps)"),
                                ("Completed-attempt CRC failure fraction", bler, "Completed-attempt BLER")):
        if series:
            payload = m._render_multi_series_svg(title,
                "Actual transmitted-layer groups; mixed MCS/channel/attempts. Not controlled rank gain or whole-run goodput.",
                series, ["No statistical independence claim", "Original groups and source hashes in plotted CSV"],
                x_label="Original group index (see layer labels)", y_label=unit,
                mode="scatter", evidence_shape_policy="operating_point", pad_constant_axes=True,
                max_points_per_series=None, wrap_legend=True, wrap_subtitle=True)
        else:
            payload = m._render_reason_svg(title, "Unavailable original metric operands.",
                ["Groups retained in CSV; no zero-valued sample substituted."])
        panels.append(ET.fromstring(payload))
    namespace = "http://www.w3.org/2000/svg"
    height = sum(float(panel.attrib["height"]) for panel in panels)
    image = ET.Element(f"{{{namespace}}}svg", width="1280", height=str(height), viewBox=f"0 0 1280 {height}")
    offset = 0.0
    for panel in panels:
        panel.set("x", "0"); panel.set("y", str(offset))
        offset += float(panel.attrib["height"])
        image.append(panel)
    return {"csv_bytes": m._encode_dict_rows(list(plotted[0]), plotted),
            "img_bytes": ET.tostring(image, encoding="utf-8"),
            "csv_status": "specialized_original_applied_rank_diagnostic",
            "image_status": "generated_original_applied_rank_diagnostic_svg",
            "source_table_path": "|".join([SOURCE] + [TRIALS[d] for d in TRIALS if sources[d][0]]),
            "source_row_count": len(plotted), "source_mapping_status": "exact",
            "note": "Original layer groups, not optimal-rank or controlled rank-gain evidence. Mean trial rates are not whole-run goodput; attempts are not asserted independent."}
