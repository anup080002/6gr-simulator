"""Source-bound control-signal and CSI/precoder plots.

This module deliberately does not reconstruct codebooks from a scalar PMI,
turn a pilot-fit residual into channel-estimation NMSE/EVM, or join CSI to a
grant just because their values happen to agree.
"""
from __future__ import annotations

import html
import json
import math
import re
from collections import defaultdict

TRIALS = ("air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv")
FEEDBACK = "air_interface/csv/csi_feedback_reports.csv"
CONTROL_EVM = {
    "PRACH EVM": ("PRACH", "air_interface/csv/prach_evm_samples.csv"),
    "SSB EVM": ("SSB", "air_interface/csv/ssb_evm_samples.csv"),
    "CSI-RS EVM": ("CSI-RS", "air_interface/csv/csi_rs_evm_samples.csv"),
}
CSI_FIELDS = {"CSI CQI timeline": "CQI", "CSI RI timeline": "RI",
              "CSI PMI components timeline": "PMI", "CSI SINR timeline": "SINR_dB"}
CSI_POWER_FIELDS = {"CSI-RS RSSI timeline": ("RSSIPerAntenna_dBm", "RSSI (dBm)"),
                    "CSI-RS RSRQ timeline": ("RSRQPerAntenna_dB", "RSRQ (dB)")}
SSB_POWER_CHART = "SSB-window RSSI timeline"
DATA_POWER_CHARTS = {"PDSCH-window carrier RSSI timeline": TRIALS[:1],
                     "PUSCH-window carrier RSSI timeline": TRIALS[1:]}
PRECODER_CHARTS = {"reported versus applied PMI", "precoder ports and layers", "precoder matrix integrity"}
CHARTS = tuple(CONTROL_EVM) + tuple(CSI_FIELDS) + tuple(CSI_POWER_FIELDS) + tuple(DATA_POWER_CHARTS) + (SSB_POWER_CHART,) + tuple(sorted(PRECODER_CHARTS)) + (
    "throughput vs SNR", "PDSCH BLER vs measured SINR", "PUSCH BLER vs measured SINR",
    "PUCCH BLER vs measured SINR", "CSI-RS pilot residual", "NMSE vs SNR / SINR",
)
CHART_SOURCES = {name: (path, "air_interface/csv/control_evm_samples.csv")
                 for name, (_, path) in CONTROL_EVM.items()}
CHART_SOURCES.update({name: (FEEDBACK,) for name in CSI_FIELDS})
CHART_SOURCES.update({name: ("air_interface/csv/csi_rs_trials.csv",) for name in CSI_POWER_FIELDS})
CHART_SOURCES[SSB_POWER_CHART] = ("air_interface/csv/pbch_trials.csv",)
CHART_SOURCES.update(DATA_POWER_CHARTS)
CHART_SOURCES.update({name: TRIALS + (FEEDBACK,) for name in PRECODER_CHARTS})
CHART_SOURCES.update({"throughput vs SNR": TRIALS, "NMSE vs SNR / SINR": TRIALS + ("air_interface/csv/srs_trials.csv",),
    "PDSCH BLER vs measured SINR": TRIALS[:1], "PUSCH BLER vs measured SINR": TRIALS[1:],
    "PUCCH BLER vs measured SINR": ("air_interface/csv/pucch_trials.csv",),
    "CSI-RS pilot residual": ("air_interface/csv/csi_rs_trials.csv",)})
SOURCE_PATHS = TRIALS + (FEEDBACK, "air_interface/csv/pucch_trials.csv",
    "air_interface/csv/csi_rs_trials.csv", "air_interface/csv/pbch_trials.csv",
    "air_interface/csv/prach_trials.csv", "air_interface/csv/control_evm_samples.csv",
    "beamforming/csv/precoder_evidence.csv") + tuple(path for _, path in CONTROL_EVM.values())


def _delivered(status):
    # Substring matching also accepts "not_delivered" and failed-decode states.
    return str(status).strip().lower() in {"delivered", "delivered_to_runtime_scheduler"}


def _numbers(token, *, integers=False):
    """Parse numeric scalar/vector notation only, never digits from labels/JSON metadata."""
    text = str(token if token is not None else "").strip()
    if not text or text.lower() in {"nan", "<missing>", "unavailable"}:
        return []
    if text.startswith("["):
        try:
            parsed = json.loads(text)
            if not isinstance(parsed, list) or any(isinstance(x, (list, dict, bool)) for x in parsed):
                return []
            numbers = [float(x) for x in parsed]
        except (ValueError, TypeError):
            text = text[1:-1] if text.endswith("]") else ""
            numbers = None
    else:
        numbers = None
    if numbers is None:
        if not text or not re.fullmatch(r"[\s0-9eE+.,;|\-]+", text):
            return []
        try:
            numbers = [float(x) for x in re.split(r"[\s,;|]+", text) if x]
        except ValueError:
            return []
    if any(not math.isfinite(x) or (integers and (x < 0 or x != int(x))) for x in numbers):
        return []
    return [int(x) for x in numbers] if integers else numbers


def _unavailable(m, name, run_id, reason, sources):
    return {"csv_bytes": m._encode_csv(["run_id", "chart_name", "status", "reason", "checked_sources"],
                [[run_id, name, "unavailable_exact_reason", reason, "|".join(sources)]]),
            "img_bytes": m._render_reason_svg(name, "Required runtime measurement evidence is unavailable.", [reason]),
            "csv_status": "unavailable_exact_reason", "image_status": "generated_unavailable_reason_svg",
            "source_table_path": "|".join(sources), "source_row_count": 0, "note": reason}


def _identity(m, row, path, index):
    declared = m._row_text(row, "RuntimeDirection", "Direction").upper()
    inferred = "DL" if "dl_pdsch" in path else "UL" if "ul_pusch" in path else ""
    if inferred and declared and declared != inferred:
        raise ValueError(f"Direction conflict in {path} row {index}")
    field = m._non_runtime_evidence_field(row)
    if field:
        raise ValueError(f"Non-runtime evidence ({field}) in {path} row {index}")
    return {"direction": declared or inferred, "ue_index": m._row_text(row, "UEIndex", "UEID", "ue_id"),
            "frame": m._row_text(row, "Frame"), "slot": m._row_float(row, "RuntimeSlot", "Slot"),
            "cell_id": m._row_text(row, "CellID", "ServingCell"),
            "source_table_logical_path": path, "source_row_index": index}


def _finish(m, name, run_id, rows, series, x_label, y_label, note, sources, *, display_title=None, extra_summary=()):
    if not rows or not series:
        return _unavailable(m, name, run_id, note, sources)
    records = [{"run_id": run_id, "chart_name": name, **row} for row in rows]
    return {"csv_bytes": m._encode_dict_rows(list(records[0]), records),
            "img_bytes": m._render_multi_series_svg(display_title or name, note,
                [{"name": label, "points": points} for label, points in series.items()],
                [f"source_records={len(rows)}", "Observed points; no sweep/fit claim", "See CSV for source and timing", *extra_summary],
                x_label=x_label, y_label=y_label, mode="scatter", evidence_shape_policy="operating_point"),
            "csv_status": "specialized_runtime_radio_measurement_dataset",
            "image_status": "generated_specialized_runtime_summary_svg", "source_table_path": "|".join(sources),
            "source_row_count": len(rows), "note": note}


def _measured_sinr(m, row):
    return m._measured_sinr_evidence(row)


def _control_evm(m, name, existing, fetch, run_id):
    family, canonical = CONTROL_EVM[name]
    sources = [canonical, "air_interface/csv/control_evm_samples.csv"]
    path, samples = m._first_available_rows(existing, fetch, sources)
    buckets, seen = {}, set()
    for index, row in enumerate(samples, 1):
        signal = m._row_text(row, "SignalName").upper()
        allowed = {family} if family != "SSB" else {"PSS", "SSS", "PBCH", "PBCH-DMRS"}
        if signal not in allowed:
            continue
        identity = _identity(m, row, path, index)
        fields = ("ReferenceReal", "ReferenceImag", "MeasuredReal", "MeasuredImag")
        values = [m._row_float(row, f) for f in fields]
        definition = m._row_text(row, "EVMDefinition")
        alignment = m._row_text(row, "AlignmentSource")
        reference_source = m._row_text(row, "ReferenceSource")
        observation = m._row_text(row, "ObservationID")
        port = m._row_text(row, "PortIndex")
        sample_index = m._row_float(row, "SampleIndex")
        domain = m._row_text(row, "MeasurementDomain")
        if any(x is None for x in values) or not all((definition, alignment, reference_source, observation, port)):
            return _unavailable(m, name, run_id, "Paired samples lack finite values, observation/port identity or explicit EVM/reference/alignment definitions.", sources)
        if sample_index is None or sample_index < 0 or sample_index != int(sample_index) or len(_numbers(port, integers=True)) != 1:
            return _unavailable(m, name, run_id, "A nonnegative sample index and port index are required for each paired sample.", sources)
        expected_domain = "equalized_sequence_symbols" if family == "PRACH" else "equalized_resource_elements"
        if domain != expected_domain or definition != "reference_normalized_paired_symbol_evm":
            return _unavailable(m, name, run_id, f"Control EVM requires {expected_domain} and the reference_normalized_paired_symbol_evm definition.", sources)
        if identity["direction"] != ("UL" if family == "PRACH" else "DL") or not identity["ue_index"]:
            return _unavailable(m, name, run_id, "Control signal direction or UE identity is missing/inconsistent.", sources)
        if "decision" in reference_source.lower() or "same_sample" in reference_source.lower():
            return _unavailable(m, name, run_id, "Decision-derived or same-sample fitted references cannot establish independent control EVM.", sources)
        key = (signal, identity["direction"], identity["ue_index"], identity["frame"], identity["slot"],
               observation, port, definition, alignment, reference_source)
        sample_key = key[:7] + (int(sample_index),)
        if sample_key in seen:
            return _unavailable(m, name, run_id, "Duplicate paired control-sample identity; refusing double-counted EVM.", sources)
        seen.add(sample_key)
        bucket = buckets.setdefault(key, {**identity, "signal_name": signal, "observation_id": observation,
            "port_index": port, "evm_definition": definition, "alignment_source": alignment,
            "reference_source": reference_source, "measurement_domain": domain,
            "sample_count": 0, "reference_energy": 0., "error_energy": 0.,
            "peak_error_power": 0., "measurement_scope": "persisted_independently_paired_control_samples"})
        ref_r, ref_i, rx_r, rx_i = values
        error = (rx_r-ref_r)**2 + (rx_i-ref_i)**2
        bucket["sample_count"] += 1
        bucket["reference_energy"] += ref_r**2 + ref_i**2
        bucket["error_energy"] += error
        bucket["peak_error_power"] = max(bucket["peak_error_power"], error)
    rows, series = [], defaultdict(list)
    for row in buckets.values():
        if row["reference_energy"] <= 0 or row["slot"] is None:
            return _unavailable(m, name, run_id, "Positive reference energy and an executed slot are required.", sources)
        row["rms_evm_pct"] = 100 * math.sqrt(row["error_energy"] / row["reference_energy"])
        row["peak_evm_pct"] = 100 * math.sqrt(row["peak_error_power"] * row["sample_count"] / row["reference_energy"])
        rows.append(row)
        for metric in ("rms", "peak"):
            series[f"{row['signal_name']} {metric} P{row['port_index']} U{row['ue_index']}"].append([row["slot"], row[f"{metric}_evm_pct"]])
    return _finish(m, name, run_id, rows, series, "Executed slot", "EVM (%)",
        "Independent paired control samples with explicit alignment/reference. No conversion from SINR, detection score, or pilot-fit residual. Not RF conformance EVM.", sources)


def _csi(m, name, existing, fetch, run_id):
    _, source = m._artifact_rows_by_path(existing, fetch, FEEDBACK)
    field = CSI_FIELDS[name]
    rows, series = [], defaultdict(list)
    for index, row in enumerate(source, 1):
        identity = _identity(m, row, FEEDBACK, index)
        measured_slot = m._row_float(row, "SourceSlot")
        delivered_slot = m._row_float(row, "DeliveredSlot")
        values = _numbers(m._row_text(row, field), integers=field != "SINR_dB")
        sinr_source = m._row_text(row, "SINRSource") if field == "SINR_dB" else ""
        sinr_domain = m._row_text(row, "SINRMeasurementDomain") if field == "SINR_dB" else ""
        if sinr_source == "measured_csi_state_receiver_objective":
            sinr_domain = "csi_rs_selected_pmi_receiver_objective"
        record = {**identity, "source_slot": measured_slot, "due_slot": m._row_float(row, "DueSlot"),
            "delivered_slot": delivered_slot, "delivery_status": m._row_text(row, "DeliveryStatus"),
            "report_identity": m._row_text(row, "ReportIdentity"), "source_signal": m._row_text(row, "SourceSignal"),
            "measurement_source": m._row_text(row, "MeasurementSource"), "metric_field": field,
            "sinr_source": sinr_source, "sinr_measurement_domain": sinr_domain,
            "sinr_value_role": m._row_text(row, "SINRValueRole") if field == "SINR_dB" else "",
            "reported_value_token": m._row_text(row, field), "component_values": json.dumps(values),
            "value_status": "available" if values and measured_slot is not None else "unavailable_in_source"}
        rows.append(record)
        if measured_slot is None:
            continue
        for ci, value in enumerate(values):
            suffix = f"[{ci}]" if len(values) > 1 else ""
            label = f"{identity['direction']} U{identity['ue_index']} {field}{suffix}"
            series[f"{label} measured"].append([measured_slot, value])
            if delivered_slot is not None and _delivered(record["delivery_status"]):
                if delivered_slot < measured_slot:
                    raise ValueError(f"CSI delivery precedes measurement in {FEEDBACK} row {index}")
                series[f"{label} delivered"].append([delivered_slot, value])
    return _finish(m, name, run_id, rows, series, "Runtime slot (measurement / delivery)",
        "CSI scheduling SINR estimate (dB)" if field == "SINR_dB" else f"Reported {field} index",
        "CSI reports from received reference signals and actual delivery events. Selected-PMI receiver-objective SINR is an estimated scheduling input, not raw CSI-RS SINR or a decoded PDSCH measurement. Pending/censored reports are not scheduler-delivered. PMI vector positions are not invented i1/i2 codebook labels.", [FEEDBACK])


def _precoding(m, name, existing, fetch, run_id):
    _, reports = m._artifact_rows_by_path(existing, fetch, FEEDBACK)
    rows, series, sources = [], defaultdict(list), []
    for path, trials in m._all_available_rows(existing, fetch, TRIALS):
        sources.append(path)
        for index, trial in enumerate(trials, 1):
            record = _identity(m, trial, path, index)
            slot = record["slot"]
            applied = _numbers(m._row_text(trial, "AppliedPrecoderPMI"), integers=True)
            requested = _numbers(m._row_text(trial, "RequestedPrecoderPMI"), integers=True)
            source_slot = m._row_float(trial, "LinkAdaptationAppliedFeedbackSourceSlot")
            eligible = [r for r in reports
                if m._row_text(r, "Direction").upper() == record["direction"]
                and m._row_text(r, "UEIndex", "UEID") == record["ue_index"]
                and (not record["cell_id"] or m._row_text(r, "ServingCell", "CellID") == record["cell_id"])
                and source_slot is not None and m._row_float(r, "SourceSlot") == source_slot
                and _delivered(m._row_text(r, "DeliveryStatus"))
                and m._row_float(r, "DeliveredSlot") is not None and slot is not None
                and m._row_float(r, "DeliveredSlot") <= slot]
            feedback = eligible[0] if len(eligible) == 1 else {}
            reported = _numbers(m._row_text(feedback, "PMI"), integers=True)
            req_hash = m._row_text(trial, "RequestedPrecoderSHA256")
            app_hash = m._row_text(trial, "AppliedPrecoderSHA256", "AppliedPrecoderMatrixSHA256")
            hashes_valid = all(re.fullmatch(r"[a-fA-F0-9]{64}", token) for token in (req_hash, app_hash))
            ports = m._row_float(trial, "PrecodingNumPorts")
            layers = m._row_float(trial, "PrecodingNumLayers")
            matrix_rows = m._row_float(trial, "PrecodingMatrixRows")
            matrix_cols = m._row_float(trial, "PrecodingMatrixCols")
            record.update({"requested_pmi_token": m._row_text(trial, "RequestedPrecoderPMI"),
                "requested_pmi_source": m._row_text(trial, "RequestedPrecoderSource"),
                "applied_pmi_token": m._row_text(trial, "AppliedPrecoderPMI"),
                "applied_pmi_type": m._row_text(trial, "AppliedPrecoderPMIType"),
                "applied_pmi_basis": m._row_text(trial, "AppliedPrecoderPMIBasis"),
                "qcl_status": m._row_text(trial, "QCLStatus"),
                "qcl_type": m._row_text(trial, "QCLType"),
                "qcl_source_resource_id": m._row_float(trial, "QCLSourceResourceID"),
                "qcl_source_slot0": m._row_float(trial, "QCLSourceSlot0"),
                "qcl_timing_prior_samples": m._row_float(trial, "QCLTimingPriorSamples"),
                "qcl_dmrs_delay_residual_samples": m._row_float(trial, "QCLDMRSDelayResidual_samples"),
                "qcl_measurement_status": m._row_text(trial, "QCLMeasurementStatus"),
                "tci_state_id": m._row_float(trial, "TCIStateID"),
                "tci_codepoint": m._row_float(trial, "TCICodepoint"),
                "tci_initialization_source": m._row_text(trial, "TCIInitializationSource"),
                "equivalent_pdsch_port_basis_codebook_index": m._row_float(trial, "EquivalentPDSCHPortBasisCodebookIndex"),
                "applied_csi_resource_index": m._row_float(trial, "AppliedCSIResourceIndex"),
                "csi_port_pmi_matrix_sha256": m._row_text(trial, "PMICodebookMatrixCSIPortsSHA256"),
                "csi_port_to_element_matrix_sha256": m._row_text(trial, "CSIRSPortToElementMatrixSHA256"),
                "composed_element_matrix_sha256": m._row_text(trial, "ComposedElementMatrixSHA256"),
                "applied_codebook_mode": m._row_text(trial, "AppliedPrecoderCodebookMode"),
                "precoder_source": m._row_text(trial, "PrecoderSource"),
                "application_stage": m._row_text(trial, "PrecodingApplicationStage"),
                "feedback_source_slot": source_slot, "feedback_report_identity": m._row_text(feedback, "ReportIdentity"),
                "feedback_binding_status": "unique_delivered_source_slot_match" if len(eligible) == 1 else
                    "ambiguous_feedback_source" if eligible else "no_unique_delivered_feedback_binding",
                "feedback_binding_authority": "applied_link_adaptation_context_not_proof_of_precoder_selection_causality",
                "reported_pmi_token": m._row_text(feedback, "PMI"), "reported_ri": m._row_float(feedback, "RI"),
                "requested_applied_pmi_equal": int(requested == applied) if requested and applied else None,
                "reported_applied_pmi_equal": int(reported == applied) if reported and applied else None,
                "rank_policy": m._row_text(trial, "RankSelectionPolicy"),
                "logical_ports": ports, "applied_layers": layers, "matrix_rows": matrix_rows, "matrix_cols": matrix_cols,
                "matrix_dimension_match": int(ports == matrix_rows and layers == matrix_cols and layers <= ports
                    and all(v > 0 and v == int(v) for v in (ports, layers, matrix_rows, matrix_cols)))
                    if all(v is not None for v in (ports, layers, matrix_rows, matrix_cols)) else None,
                "requested_matrix_sha256": req_hash, "applied_matrix_sha256": app_hash,
                "matrix_digest_domain": m._row_text(trial, "PrecoderDigestDomain"),
                "requested_applied_matrix_hash_equal": int(req_hash.lower() == app_hash.lower()) if hashes_valid else None,
                "matrix_coefficients_available": "not_established_by_hash_only_evidence"})
            rows.append(record)
            if slot is None:
                continue
            prefix = f"{record['direction']} U{record['ue_index']}"
            if name == "reported versus applied PMI":
                for label, values in (("requested", requested), ("applied", applied), ("reported", reported)):
                    for ci, value in enumerate(values):
                        series[f"{prefix} {label} PMI[{ci}]"].append([slot, value])
            else:
                fields = ("logical_ports", "applied_layers", "reported_ri") if name == "precoder ports and layers" else (
                    "matrix_dimension_match", "requested_applied_matrix_hash_equal", "requested_applied_pmi_equal")
                for field in fields:
                    if record[field] is not None:
                        labels = {"logical_ports": "ports", "applied_layers": "layers", "reported_ri": "reported RI",
                                  "matrix_dimension_match": "dimensions match", "requested_applied_matrix_hash_equal": "hashes match",
                                  "requested_applied_pmi_equal": "PMIs match"}
                        series[f"{prefix} {labels[field]}"].append([slot, record[field]])
    title = name
    if name == "reported versus applied PMI" and not any(row["reported_pmi_token"] for row in rows):
        # A bootstrap/configured request is not UE feedback. Keep the stable
        # contract/CSV name, but describe only the evidence actually plotted.
        title = "Requested versus applied PMI (no bound feedback)"
    result = _finish(m, name, run_id, rows, series, "Executed data slot",
        "Index / count" if name != "precoder matrix integrity" else "Recorded-evidence consistency (1=match, 0=mismatch)",
        "Requested and executed precoders stay separate. Feedback is linked only by an explicit applied source slot and prior delivery. Hash equality is not matrix-coefficient or optimality validation.", sources + [FEEDBACK],
        display_title=title)
    if name == "precoder matrix integrity" and result["csv_status"] != "unavailable_exact_reason":
        result["img_bytes"] = _matrix_checks_svg(rows, m.MAX_PREVIEW_ROWS)
    return result


def _matrix_checks_svg(rows, max_rows):
    """One visible cell per check/trial; equal-valued series cannot hide each other."""
    checks = (("matrix_dimension_match", "Ports/layers vs matrix shape"),
              ("requested_applied_matrix_hash_equal", "Requested vs applied hash"),
              ("requested_applied_pmi_equal", "Requested vs applied PMI"))
    mismatch = [i for i, row in enumerate(rows) if any(row[key] == 0 for key, _ in checks)]
    unknown = [i for i, row in enumerate(rows) if any(row[key] is None for key, _ in checks)]
    # Keep full CSV evidence, bound raster memory, and prioritize visible
    # mismatches/missing checks. Any clipping is explicitly counted on-image.
    priority = list(dict.fromkeys(mismatch + unknown + list(range(len(rows)))))
    shown = [rows[i] for i in sorted(priority[:max_rows])]
    width, height = 1180, max(400, 188 + 32 * len(shown))
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
             '<rect width="100%" height="100%" fill="#f8fafc"/>',
             '<text x="32" y="45" font-family="sans-serif" font-size="26" fill="#0f172a">Precoder matrix integrity — recorded consistency</text>',
             '<text x="32" y="76" font-family="sans-serif" font-size="14" fill="#475569">MATCH is not proof of matrix normalization, correct spatial mapping, optimality, or CSI-selection causality.</text>',
             f'<text x="32" y="98" font-family="sans-serif" font-size="13" fill="#475569">Showing {len(shown)}/{len(rows)} trials; total mismatch trials={len(mismatch)}, unavailable-check trials={len(unknown)}. Full evidence in CSV.</text>',
             '<text x="32" y="137" font-family="sans-serif" font-size="14" fill="#0f172a">Direction / UE / frame / slot</text>']
    for ci, (_, label) in enumerate(checks):
        parts.append(f'<text x="{426 + 284*ci}" y="137" text-anchor="middle" font-family="sans-serif" font-size="14" fill="#0f172a">{label}</text>')
    for ri, row in enumerate(shown):
        y = 152 + 32 * ri
        identity = f"{row['direction']} / U{row['ue_index']} / {row['frame'] or '—'} / {row['slot']:g}" if row["slot"] is not None else f"source row {row['source_row_index']} (slot unavailable)"
        parts.append(f'<text x="32" y="{y+19}" font-family="sans-serif" font-size="13" fill="#334155">{html.escape(identity)}</text>')
        for ci, (field, _) in enumerate(checks):
            value = row[field]
            label, fill = ("MATCH", "#ccfbf1") if value == 1 else ("MISMATCH", "#fecaca") if value == 0 else ("UNAVAILABLE", "#e2e8f0")
            x = 288 + 284 * ci
            parts += [f'<rect x="{x}" y="{y}" width="276" height="27" rx="4" fill="{fill}"/>',
                      f'<text x="{x+138}" y="{y+19}" text-anchor="middle" font-family="sans-serif" font-size="13" fill="#0f172a">{label}</text>']
    parts.append('</svg>')
    return ''.join(parts).encode('utf-8')


def _relationships(m, name, existing, fetch, run_id):
    if name == "CSI-RS pilot residual":
        paths = ("air_interface/csv/csi_rs_trials.csv",)
    elif name.startswith("PUCCH"):
        paths = ("air_interface/csv/pucch_trials.csv",)
    elif name.startswith("PDSCH"):
        paths = TRIALS[:1]
    elif name.startswith("PUSCH"):
        paths = TRIALS[1:]
    elif name == "NMSE vs SNR / SINR":
        paths = TRIALS + ("air_interface/csv/srs_trials.csv",)
    else:
        paths = TRIALS
    rows, series = [], defaultdict(list)
    for path, trials in m._all_available_rows(existing, fetch, paths):
        for index, row in enumerate(trials, 1):
            record = _identity(m, row, path, index)
            sinr_evidence = _measured_sinr(m, row)
            x, x_field, x_source = (sinr_evidence[key] for key in ("value", "field", "source"))
            y_field, y = "", None
            if name == "throughput vs SNR":
                x, x_field = None, ""
                for field in ("AppliedAWGNSNR_dB", "AppliedSNR_dB"):
                    value = m._row_float(row, field)
                    if value is not None:
                        x, x_field = value, field
                        break
                x_source = m._row_text(row, "AppliedAWGNSNRSource")
                if any(token in x_source.lower() for token in ("proxy", "fallback", "synthetic", "unavailable")):
                    x = None
                # Keep offered/scheduled transport-block bitrate separate from
                # delivered goodput. A legacy row may contain only the former;
                # it is valid evidence, but must never be relabelled as goodput.
                record.update({"AppliedAWGNSNR_dB": m._row_float(row, "AppliedAWGNSNR_dB"),
                    "Throughput_Mbps": m._row_float(row, "Throughput_Mbps"),
                    "AppliedSNR_dB": m._row_float(row, "AppliedSNR_dB"),
                    "Goodput_Mbps": m._row_float(row, "Goodput_Mbps")})
                y_field = "Goodput_Mbps" if record["Goodput_Mbps"] is not None else "Throughput_Mbps"
                y = record[y_field]
            elif name.endswith("BLER vs measured SINR"):
                crc = m._row_flag(row, "CRCPass")
                y_field, y = "transport_block_error", None if crc is None else int(not crc)
                if name.startswith("PUCCH"):
                    # PUCCH formats 0/1 have no payload CRC; require an actual
                    # decode/comparison outcome, never absent CRC -> failure.
                    decoded = m._row_flag(row, "PUCCHDecodeOk", "DecodeSuccess", "DecodeOK")
                    y_field, y = "uci_block_error", None if decoded is None else int(not decoded)
            elif name == "CSI-RS pilot residual":
                x, x_field, x_source = m._row_float(row, "Slot", "CSIMeasurementSlot"), "Slot", "runtime_csi_rs_observation"
                y_field, y = "PilotResidualNMSE_dB", m._row_float(row, "PilotResidualNMSE_dB")
            elif name == "NMSE vs SNR / SINR":
                y_field = "TrueChannelNMSE_dB"
                y = m._row_float(row, "TrueChannelNMSE_dB")
                if y is None:
                    y_field, y = "OracleNMSE_dB", m._row_float(row, "OracleNMSE_dB")
                reference = m._row_text(row, "NMSEReferenceSource")
                oracle_available = m._row_flag(row, "TrueChannelOracleAvailable")
                if (not reference or oracle_available is False or
                        any(token in reference.lower() for token in ("proxy", "fallback", "synthetic", "unavailable"))):
                    y = None  # Generic NMSE_dB can be a pilot fit or noise/gain proxy.
            record.update({"x_value": x, "x_source_field": x_field, "x_source": x_source,
                "metric_value": y, "metric_source_field": y_field,
                "metric_reference_source": m._row_text(row, "NMSEReferenceSource") if name == "NMSE vs SNR / SINR" else "",
                "mcs": m._row_text(row, "MCS", "MCSIndex"), "layers": m._row_text(row, "Layers"),
                "format": m._row_text(row, "Format", "PUCCHFormat"),
                "crc_pass": m._row_text(row, "CRCPass"),
                "noise_operating_mode": m._row_text(row, "NoiseOperatingMode"),
                "value_status": "available" if x is not None and y is not None else "required_measurement_unavailable"})
            is_sinr_axis = name != "throughput vs SNR" and name != "CSI-RS pilot residual"
            if is_sinr_axis:
                record.update({"x_value_status": sinr_evidence["status"],
                    "x_value_reason": sinr_evidence["reason"], "x_value_role": sinr_evidence["role"],
                    "x_measurement_domain": sinr_evidence["domain"], "x_is_limited": sinr_evidence["limited"],
                    "x_raw_equalizer_db": sinr_evidence["raw_equalizer_db"]})
            rows.append(record)
            if name == "throughput vs SNR" and x is not None:
                for field, label in (("Throughput_Mbps", "scheduled TB rate"), ("Goodput_Mbps", "goodput")):
                    if record[field] is not None:
                        series[f"{record['direction']} U{record['ue_index']} {label}"].append([x, record[field]])
            elif x is not None and y is not None:
                limit_label = "[limited] " if is_sinr_axis and sinr_evidence["limited"] else ""
                series[f"{limit_label}{record['direction']} U{record['ue_index']} {y_field}"].append([x, y])
    notes = {"throughput vs SNR": "Scheduled TB bitrate and Delivered goodput are separate measured series. Actual noise-calibration SNR; no configured-SNR substitution or controlled sweep is claimed.",
             "CSI-RS pilot residual": "Measured residual on channel-estimation pilots. This is neither independent channel NMSE nor CSI-RS EVM.",
             "NMSE vs SNR / SINR": "An explicit executed true-channel reference and TrueChannelNMSE_dB/OracleNMSE_dB are required. Pilot-fit residuals and noise/gain ratios are not channel-estimation NMSE."}
    note = notes.get(name, "Individual measured block-error outcomes (0/1), not a fitted BLER curve or an independent Monte Carlo sweep. MCS/rank/format retained per trial.")
    limited_count = sum(row.get("x_is_limited", False) and row["value_status"] == "available" for row in rows)
    limit_summary = [f"Limited SINR values: {limited_count}", "Limited values are not raw estimates"] if limited_count else []
    return _finish(m, name, run_id, rows, series,
        "Executed CSI-RS slot" if name == "CSI-RS pilot residual" else "Applied noise-calibration SNR (dB)" if name == "throughput vs SNR" else "Receiver SINR (dB); includes limited values" if limited_count else "Measured SINR (dB)",
        "Scheduled TB bitrate / delivered goodput (Mbit/s)" if name == "throughput vs SNR" else "Pilot-fit residual (dB)" if name == "CSI-RS pilot residual" else "True-channel NMSE (dB)" if name == "NMSE vs SNR / SINR" else "Observed block error (0/1)", note, list(paths), extra_summary=limit_summary)


def _csi_physical_power(m, name, existing, fetch, run_id):
    sources = CHART_SOURCES[name]
    path, samples = m._first_available_rows(existing, fetch, sources)
    field, units = CSI_POWER_FIELDS[name]
    rows, series = [], defaultdict(list)
    seen = set()
    for index, row in enumerate(samples, 1):
        physical_status = m._row_text(row, "PhysicalMeasurementStatus")
        if physical_status not in {"available", "available_normalized_fixed_esn0_not_absolute_dbm"}:
            continue
        identity = _identity(m, row, path, index)
        plane = m._row_text(row, "PowerReferencePlane")
        if physical_status == "available_normalized_fixed_esn0_not_absolute_dbm":
            if plane != "normalized_fixed_esn0_unit_occupied_re_es":
                raise ValueError("Normalized CSI-RS power has an inconsistent reference plane.")
            if m._row_text(row, "MeasurementSource") != "actual_csirs_re_measurement_relative_to_unit_occupied_re_es":
                raise ValueError("Normalized CSI-RS power has no supported actual waveform source.")
            n_rb = m._row_float(row, "MeasurementNumRB")
            first_prb = m._row_float(row, "MeasurementFirstPRB0Based")
            scs = m._row_float(row, "MeasurementSubcarrierSpacing_kHz")
            bandwidth = m._row_float(row, "MeasurementBandwidth_Hz")
            symbols = _numbers(m._row_text(row, "MeasurementSymbolIndices0Based"), integers=True)
            rssis = _numbers(m._row_text(row, "MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"))
            rsrps = _numbers(m._row_text(row, "MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"))
            rsrqs = _numbers(m._row_text(row, "MeasurementRSRQPerReceiveAntenna_dB"))
            if (n_rb is None or n_rb < 1 or n_rb != int(n_rb) or first_prb is None or first_prb < 0 or
                    first_prb != int(first_prb) or scs is None or scs <= 0 or bandwidth is None or
                    not math.isclose(bandwidth, 12*n_rb*scs*1000, rel_tol=1e-12) or not symbols or
                    not rssis or len(rssis) != len(rsrps) or len(rssis) != len(rsrqs)):
                raise ValueError("Normalized CSI-RS measurement identity, bandwidth or branch vectors are incomplete.")
            for branch, (rsrp, rssi, rsrq) in enumerate(zip(rsrps, rssis, rsrqs), 1):
                if abs(rsrq - (10*math.log10(n_rb)+rsrp-rssi)) > 1e-6:
                    raise ValueError("Normalized CSI-RS same-branch RSRP/RSSI/RSRQ closure fails.")
                metric = rssi if name == "CSI-RS RSSI timeline" else rsrq
                rows.append({**identity, "bwp_id": m._row_text(row, "BWPID"),
                    "measurement_id": m._row_text(row, "CSIMeasurementID"),
                    "resource_id": m._row_text(row, "ResourceID"),
                    "receive_antenna_index_1based": branch, "metric_value": metric,
                    "metric_source_field": ("MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"
                        if name == "CSI-RS RSSI timeline" else "MeasurementRSRQPerReceiveAntenna_dB"),
                    "power_reference_plane": plane, "num_rb": int(n_rb),
                    "first_prb_0based": int(first_prb), "subcarrier_spacing_khz": scs,
                    "bandwidth_hz": bandwidth, "symbol_indices_0based": json.dumps(symbols),
                    "rsrp_db_re_unit_occupied_re_es": rsrp,
                    "rssi_db_re_unit_occupied_re_es": rssi, "rsrq_db": rsrq})
                if identity["slot"] is not None:
                    series[f"U{identity['ue_index']} C{identity['cell_id']} R{m._row_text(row, 'ResourceID')} Rx{branch}"].append([identity["slot"], metric])
            continue
        if plane not in {"receiver_antenna_connector_pre_composite_front_end",
                         "receiver_antenna_connector_no_composite_front_end"}:
            raise ValueError("CSI-RS physical power requires an explicit antenna-connector measurement plane.")
        if (m._row_text(row, "MeasurementSource") !=
                "nrCSIRSMeasurements_runtime_pre_front_end_antenna_plane_grid"):
            raise ValueError("CSI-RS physical power has no supported actual measurement source.")
        try:
            resources = json.loads(m._row_text(row, "MeasurementPhysicalResourcesJSON"))
        except (ValueError, TypeError) as exc:
            raise ValueError("CSI-RS RSSI requires retained resource and receive-antenna measurements.") from exc
        if not isinstance(resources, list):
            raise ValueError("CSI-RS physical resource evidence must be an explicit resource list.")
        for resource in resources:
            if not resource:
                continue
            if not isinstance(resource, dict):
                raise ValueError("CSI-RS resource evidence must retain named measurement fields.")
            if resource.get("Available") is not True:
                continue
            if resource.get("Source") != "nrCSIRSMeasurements_actual_physical_grid":
                raise ValueError("CSI-RS resource has no supported physical-grid source.")
            rid = resource.get("ResourceID")
            n_rx, n_rb = resource.get("NumReceiveAntennas"), resource.get("NumRB")
            scs, bandwidth = resource.get("SubcarrierSpacing_kHz"), resource.get("Bandwidth_Hz")
            first_prb = resource.get("FirstPRB0Based")
            def integer(value, minimum):
                return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= minimum and value == int(value)
            if not all(integer(v, minimum) for v, minimum in ((rid, 0), (n_rx, 1), (n_rb, 1), (first_prb, 0))):
                raise ValueError("CSI-RS physical resource/branch/bandwidth identity is incomplete.")
            if (not isinstance(scs, (int, float)) or not math.isfinite(scs) or scs <= 0 or
                    not isinstance(bandwidth, (int, float)) or not math.isclose(bandwidth, 12*n_rb*scs*1000, rel_tol=1e-12)):
                raise ValueError("CSI-RS RSSI bandwidth does not match its retained PRBs and subcarrier spacing.")
            vectors = {}
            for metric in ("RSRPPerAntenna_dBm", "RSSIPerAntenna_dBm", "RSRQPerAntenna_dB", "SymbolIndices0Based"):
                token = resource.get(metric)
                vectors[metric] = _numbers(json.dumps(token), integers=metric == "SymbolIndices0Based")
            if any(len(vectors[v]) != n_rx for v in ("RSRPPerAntenna_dBm", "RSSIPerAntenna_dBm", "RSRQPerAntenna_dB")) or not vectors["SymbolIndices0Based"]:
                raise ValueError("CSI-RS physical measurement vectors or measurement-symbol window are missing.")
            for branch in range(int(n_rx)):
                rsrp, rssi, rsrq = (vectors[v][branch] for v in
                    ("RSRPPerAntenna_dBm", "RSSIPerAntenna_dBm", "RSRQPerAntenna_dB"))
                if abs(rsrq - (10*math.log10(n_rb)+rsrp-rssi)) > 1e-6:
                    raise ValueError("CSI-RS same-branch RSRP/RSSI/RSRQ closure fails.")
                bwp = m._row_text(row, "BWPID")
                measurement_id = m._row_text(row, "CSIMeasurementID")
                key = (identity["ue_index"], identity["cell_id"], bwp, identity["frame"], identity["slot"], measurement_id, rid, branch)
                if key in seen:
                    raise ValueError("Duplicate CSI-RS physical measurement identity; refusing double-counting.")
                seen.add(key)
                value = vectors[field][branch]
                rows.append({**identity, "bwp_id": bwp, "measurement_id": measurement_id,
                    "resource_id": rid, "receive_antenna_index_1based": branch+1,
                    "metric_value": value, "metric_source_field": field, "power_reference_plane": plane,
                    "num_rb": n_rb, "first_prb_0based": first_prb, "subcarrier_spacing_khz": scs,
                    "bandwidth_hz": bandwidth, "symbol_indices_0based": json.dumps(vectors["SymbolIndices0Based"]),
                    "rsrp_dbm": rsrp, "rssi_dbm": rssi, "rsrq_db": rsrq})
                if identity["slot"] is not None:
                    series[f"U{identity['ue_index']} C{identity['cell_id']} R{rid} Rx{branch+1}"].append([identity["slot"], value])
    normalized = any(row.get("power_reference_plane") == "normalized_fixed_esn0_unit_occupied_re_es" for row in rows)
    display_units = ("RSSI (dB re unit occupied-RE Es)" if normalized and name == "CSI-RS RSSI timeline" else units)
    note = ("Actual CSI-RS waveform measurements in the fixed-Es/N0 normalized power plane; every receive branch, resource, bandwidth, and measurement-symbol window is retained. Values are deliberately not labeled dBm."
            if normalized else "Actual CSI-RS antenna-plane measurements; every receive branch and resource retained. RSSI uses only the recorded bandwidth and CSI-RS symbol window.")
    return _finish(m, name, run_id, rows, series, "Measurement slot", display_units, note, sources)


def _ssb_window_power(m, name, existing, fetch, run_id):
    sources = CHART_SOURCES[name]
    path, samples = m._first_available_rows(existing, fetch, sources)
    rows, series, seen = [], defaultdict(list), set()
    for index, row in enumerate(samples, 1):
        token = m._row_text(row, "SSBWindowPowerMeasurementJSON")
        if not token:
            if m._row_text(row, "SSPhysicalMeasurementStatus") != "available_normalized_fixed_esn0_not_absolute_dbm":
                continue
            plane = m._row_text(row, "PowerReferencePlane")
            source = m._row_text(row, "SSMeasurementSource")
            if (plane != "normalized_fixed_esn0_unit_occupied_re_es" or
                    source != "noise_debiased_linear_sss_re_power_and_received_reference_disturbance"):
                raise ValueError("Normalized SSB-window RSSI has an unsupported measurement plane or source.")
            identity = _identity(m, row, path, index)
            rssis = _numbers(m._row_text(row, "SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"))
            ssb = m._row_float(row, "SSBIndex")
            first, stop, fs = (m._row_float(row, f) for f in
                              ("ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz"))
            if (not rssis or identity["direction"] != "DL" or not identity["ue_index"] or ssb is None or
                    ssb < 0 or ssb != int(ssb) or any(v is None for v in (first, stop, fs)) or
                    first < 0 or first != int(first) or stop <= first or stop != int(stop) or fs <= 0):
                raise ValueError("Normalized SSB-window RSSI lacks branch, beam, or received-burst identity.")
            for branch, rssi in enumerate(rssis, 1):
                key = (identity["ue_index"], identity["cell_id"], first, stop, int(ssb), branch)
                if key in seen:
                    raise ValueError("Duplicate normalized received SSB/branch RSSI identity.")
                seen.add(key)
                rows.append({**identity, "ssb_index_0based": int(ssb),
                    "receive_antenna_index_1based": branch,
                    "rssi_db_re_unit_occupied_re_es": rssi,
                    "burst_observation_start_sample": int(first),
                    "burst_observation_end_sample_exclusive": int(stop),
                    "sample_rate_hz": fs, "power_reference_plane": plane,
                    "measurement_scope": "received_ssb_240_subcarrier_four_symbol_window_normalized_fixed_esn0"})
                if identity["slot"] is not None:
                    series[f"U{identity['ue_index']} SSB{int(ssb)} Rx{branch}"].append([identity["slot"], rssi])
            continue
        identity = _identity(m, row, path, index)
        plane = m._row_text(row, "PowerReferencePlane")
        if plane not in {"receiver_antenna_connector_pre_composite_front_end",
                         "receiver_antenna_connector_no_composite_front_end"}:
            if plane != "actual_post_tx_rf_sss_epre_to_actual_pre_rx_rf_connector_sss_rsrp":
                raise ValueError("SSB-window RSSI requires the actual antenna-connector plane, not AGC-normalized power.")
        try:
            evidence = json.loads(token)
        except (TypeError, ValueError) as exc:
            raise ValueError("Missing structured SSB received-power evidence.") from exc
        if not isinstance(evidence, dict) or evidence.get("Available") is not True:
            continue
        if (evidence.get("Source") != "nrSSBMeasurements_actual_antenna_plane_ssb_grid" or
                evidence.get("Scope") != "ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI" or
                evidence.get("AmplitudeUnit") != "sqrt_W" or evidence.get("CPIncluded") is not False or
                evidence.get("NumRB") != 20 or evidence.get("NumSubcarriers") != 240 or
                evidence.get("SymbolIndicesWithinSSB0Based") != [0, 1, 2, 3]):
            raise ValueError("SSB RSSI requires its exact received 240-subcarrier/four-symbol scope and physical units.")
        n_rx = evidence.get("NumReceiveAntennas")
        if not isinstance(n_rx, (int, float)) or isinstance(n_rx, bool) or not math.isfinite(n_rx) or n_rx < 1 or n_rx != int(n_rx):
            raise ValueError("SSB RSSI requires exact receive-branch identities.")
        scs, bandwidth = evidence.get("SubcarrierSpacing_kHz"), evidence.get("Bandwidth_Hz")
        if (not isinstance(scs, (int, float)) or not math.isfinite(scs) or scs <= 0 or
                not isinstance(bandwidth, (int, float)) or not math.isclose(bandwidth, 240*scs*1000, rel_tol=1e-12)):
            raise ValueError("SSB RSSI bandwidth disagrees with the received SSB numerology.")
        rssis = _numbers(json.dumps(evidence.get("RSSIPerAntenna_dBm")))
        mirrors = _numbers(m._row_text(row, "SSBWindowRSSIPerReceiveAntenna_dBm"))
        powers = evidence.get("SymbolPowerPerAntenna_W")
        if int(n_rx) == 1 and isinstance(powers, list) and all(isinstance(v, (int, float)) for v in powers):
            powers = [[v] for v in powers]
        if (len(rssis) != n_rx or len(mirrors) != n_rx or
                not isinstance(powers, list) or len(powers) != 4 or
                any(not isinstance(v, list) or len(v) != n_rx for v in powers)):
            raise ValueError("SSB RSSI is missing branch powers or its complete four-symbol window.")
        ssb = m._row_float(row, "SSBIndex")
        first, stop, fs = (m._row_float(row, f) for f in
                          ("ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz"))
        if (identity["direction"] != "DL" or not identity["ue_index"] or ssb is None or ssb < 0 or ssb != int(ssb) or
                any(v is None for v in (first, stop, fs)) or first < 0 or first != int(first) or
                stop <= first or stop != int(stop) or fs <= 0):
            raise ValueError("SSB RSSI requires UE/beam identity and the actual received burst interval.")
        for branch in range(int(n_rx)):
            values = [p[branch] for p in powers]
            if any(not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0 for v in values) or sum(values) <= 0:
                raise ValueError("SSB symbol powers must be finite physical powers with positive window energy.")
            expected = 10*math.log10(sum(values)/4)+30
            if abs(rssis[branch]-expected) > 1e-4 or abs(mirrors[branch]-rssis[branch]) > 1e-4:
                raise ValueError("SSB RSSI fails same-branch linear symbol-power / dBm closure.")
            key = (identity["ue_index"], identity["cell_id"], first, stop, ssb, branch)
            if key in seen:
                raise ValueError("Duplicate received SSB/branch RSSI identity.")
            seen.add(key)
            rows.append({**identity, "ssb_index_0based": int(ssb), "receive_antenna_index_1based": branch+1,
                "rssi_dbm": rssis[branch], "bandwidth_hz": bandwidth, "subcarrier_spacing_khz": scs,
                "symbol_indices_within_ssb_0based": "[0, 1, 2, 3]", "symbol_powers_w": json.dumps(values),
                "burst_observation_start_sample": first, "burst_observation_end_sample_exclusive": stop,
                "sample_rate_hz": fs, "power_reference_plane": plane, "measurement_scope": evidence["Scope"]})
            if identity["slot"] is not None:
                series[f"U{identity['ue_index']} SSB{int(ssb)} Rx{branch+1}"].append([identity["slot"], rssis[branch]])
    normalized = any(row.get("power_reference_plane") == "normalized_fixed_esn0_unit_occupied_re_es" for row in rows)
    units = "SSB-window RSSI (dB re unit occupied-RE Es)" if normalized else "SSB-window RSSI (dBm)"
    note = ("Actual received SSB-window power per branch in the fixed-Es/N0 normalized plane. It is deliberately not labeled dBm; it is not a full-carrier/SMTC RSSI report."
            if normalized else "Actual 20-PRB/four-symbol SSB received power, including observed noise/interference, per receive branch. Not full carrier/SMTC RSSI or a UE carrier-RSSI report.")
    return _finish(m, name, run_id, rows, series, "Burst source slot", units, note, sources)


def _data_carrier_power(m, name, existing, fetch, run_id):
    sources = CHART_SOURCES[name]
    rows, series, seen = [], defaultdict(list), set()
    planes = set()
    for path, samples in m._all_available_rows(existing, fetch, sources):
        for index, row in enumerate(samples, 1):
            token = m._row_text(row, "AllocationCarrierPowerMeasurementJSON")
            if not token:
                continue
            identity = _identity(m, row, path, index)
            try:
                e = json.loads(token)
            except (TypeError, ValueError) as exc:
                raise ValueError("Invalid received carrier-power evidence JSON.") from exc
            if not isinstance(e, dict):
                raise ValueError("Carrier power requires one measurement object.")
            normalized = e.get("PowerReferencePlane") == "normalized_fixed_esn0_unit_occupied_re_es"
            required = {"ContractVersion": "received_data_carrier_power/v2" if normalized else "received_data_carrier_power/v1",
                "Scope": "received_data_symbol_window_full_carrier_not_ue_NR_RSSI_report",
                "PowerReferencePlane": "normalized_fixed_esn0_unit_occupied_re_es" if normalized else "receiver_antenna_connector_pre_composite_front_end",
                "Source": "actual_normalized_received_IQ_OFDM_carrier_energy" if normalized else "actual_physical_received_IQ_OFDM_carrier_energy",
                "InputAmplitudeUnit": "normalized_OFDM_waveform_unit_occupied_re_es" if normalized else "sqrt_mW",
                "GridAmplitudeUnit": "sqrt_UnitOccupiedRE_Es" if normalized else "sqrt_W",
                "FrequencyAlignment": "nominal_carrier_no_oracle_CFO_correction", "CPIncluded": False}
            if any(e.get(k) != v for k, v in required.items()):
                raise ValueError("Carrier-window RSSI requires actual received IQ with explicit scope and units.")
            tx_plane = m._row_text(row, "TransmitPowerReferencePlane")
            if tx_plane and ((tx_plane == "normalized_fixed_esn0_unit_occupied_re_es") != normalized):
                raise ValueError("Carrier-window power units conflict with the executed transmit reference plane.")
            planes.add(normalized)
            if len(planes) > 1:
                raise ValueError("Do not combine absolute dBm and normalized carrier power on one axis.")
            if normalized:
                if ("RSSIPerAntenna_dBm" in e or "SymbolPowerPerAntenna_W" in e or
                        m._row_text(row, "AllocationCarrierRSSIPerReceiveAntenna_dBm")):
                    raise ValueError("Normalized carrier power must not claim absolute watts/dBm.")
                rssi_field, power_field = "RSSIPerAntenna_dB_re_UnitOccupiedRE_Es", "SymbolPowerPerAntenna_UnitOccupiedRE_Es"
                mirror_field = "AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"
            else:
                if ("RSSIPerAntenna_dB_re_UnitOccupiedRE_Es" in e or "SymbolPowerPerAntenna_UnitOccupiedRE_Es" in e or
                        m._row_text(row, "AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es")):
                    raise ValueError("Physical carrier power must not mix normalized power operands.")
                rssi_field, power_field = "RSSIPerAntenna_dBm", "SymbolPowerPerAntenna_W"
                mirror_field = "AllocationCarrierRSSIPerReceiveAntenna_dBm"
            def positive(field, integer=False):
                v = e.get(field)
                if (not isinstance(v, (float, int)) or isinstance(v, bool) or not math.isfinite(v)
                        or v <= 0 or (integer and v != int(v))):
                    raise ValueError(f"Invalid carrier-power {field}.")
                return int(v) if integer else v
            n_rx, n_rb = positive("NumReceiveAntennas", True), positive("NumRB", True)
            scs, bw = positive("SubcarrierSpacing_kHz"), positive("Bandwidth_Hz")
            fs, nfft = positive("SampleRateHz"), positive("Nfft", True)
            symbols = _numbers(json.dumps(e.get("SymbolIndices0Based")), integers=True)
            allocation = _numbers(json.dumps(e.get("SymbolAllocation")), integers=True)
            if (len(allocation) != 2 or allocation[1] < 1 or
                    symbols != list(range(allocation[0], sum(allocation))) or
                    not math.isclose(bw, 12*n_rb*scs*1000, rel_tol=1e-12)):
                raise ValueError("Carrier power must retain the exact data-symbol window and carrier bandwidth.")
            first, stop = e.get("ObservationStartSample"), e.get("ObservationEndSampleExclusive")
            bounds = [first, e.get("ReceivedSymbolStartSample"), e.get("ReceivedSymbolEndSampleExclusive"), stop]
            if (any(not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v)
                    or v < 0 or v != int(v) for v in bounds) or
                    not first <= bounds[1] < bounds[2] <= stop):
                raise ValueError("Carrier power has invalid received sample bounds.")
            grant = e.get("GrantContextId")
            digest = e.get("PhysicalObservationSHA256", "")
            if (not isinstance(grant, str) or not grant or not re.fullmatch(r"[0-9a-fA-F]{64}", str(digest)) or
                    e.get("Direction") != identity["direction"] or not identity["ue_index"] or identity["slot"] is None or
                    e.get("RNTI") != m._row_float(row, "RNTI") or
                    e.get("DataAbsoluteSlot") != identity["slot"]-1):
                raise ValueError("Carrier power lacks exact received grant, UE, slot or waveform identity.")
            rssis = _numbers(json.dumps(e.get(rssi_field)))
            mirrors = _numbers(m._row_text(row, mirror_field))
            powers = e.get(power_field)
            if n_rx == 1 and len(symbols) == 1 and isinstance(powers, (int, float)):
                # MATLAB jsonencode serializes a 1x1 numeric matrix as a scalar.
                powers = [[powers]]
            elif n_rx == 1 and isinstance(powers, list) and all(isinstance(v, (int, float)) for v in powers):
                powers = [[v] for v in powers]
            elif len(symbols) == 1 and isinstance(powers, list) and all(isinstance(v, (int, float)) for v in powers):
                powers = [powers]
            if (len(rssis) != n_rx or len(mirrors) != n_rx or not isinstance(powers, list) or
                    len(powers) != len(symbols) or any(not isinstance(p, list) or len(p) != n_rx for p in powers)):
                raise ValueError("Carrier power must preserve every receive branch and measured symbol.")
            for branch in range(n_rx):
                values = [p[branch] for p in powers]
                if any(not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v) or v < 0 for v in values) or sum(values) <= 0:
                    raise ValueError("Invalid physical symbol energy.")
                value = 10*math.log10(sum(values)/len(values)) + (0 if normalized else 30)
                if abs(value-rssis[branch]) > 1e-7 or abs(value-mirrors[branch]) > 1e-7:
                    raise ValueError("Carrier RSSI fails per-branch linear-energy/reference-unit closure.")
                key = (grant, first, stop, branch)
                if key in seen:
                    raise ValueError("Duplicate received grant/branch carrier-power identity.")
                seen.add(key)
                rows.append({**identity, "grant_context_id": grant, "receive_antenna_index_1based": branch+1,
                    ("rssi_db_re_unit_occupied_re_es" if normalized else "rssi_dbm"): value,
                    "num_rb": n_rb, "bandwidth_hz": bw, "sample_rate_hz": fs, "nfft": nfft,
                    "symbol_indices_0based": json.dumps(symbols),
                    ("symbol_powers_unit_occupied_re_es" if normalized else "symbol_powers_w"): json.dumps(values),
                    "observation_start_sample": first, "observation_end_sample_exclusive": stop,
                    "power_reference_plane": e["PowerReferencePlane"], "measurement_scope": e["Scope"],
                    "physical_observation_sha256": digest})
                series[f"{identity['direction']} U{identity['ue_index']} Rx{branch+1}"].append([identity["slot"], value])
    normalized = planes == {True}
    units = "Carrier-window RSSI (dB re unit occupied-RE Es)" if normalized else "Carrier-window RSSI (dBm)"
    note = ("Actual pre-front-end carrier energy over received data symbols, per branch. "
            + ("Normalized fixed-reference sweep, not absolute dBm. " if normalized else "Absolute antenna-plane power. ")
            + "Includes noise/interference; no oracle CFO correction. Not a UE NR-RSSI report.")
    return _finish(m, name, run_id, rows, series, "Received data slot", units, note, sources)


def radio_measurement_chart(name, existing, fetch, run_id):
    if name not in CHARTS:
        return None
    # Imported at dispatch time: the host's CSV and SVG helpers are fully
    # initialized, and there is one renderer/persistence authority.
    import lls_contract_materializer as m
    try:
        if name in CONTROL_EVM:
            return _control_evm(m, name, existing, fetch, run_id)
        if name in CSI_FIELDS:
            return _csi(m, name, existing, fetch, run_id)
        if name in CSI_POWER_FIELDS:
            return _csi_physical_power(m, name, existing, fetch, run_id)
        if name == SSB_POWER_CHART:
            return _ssb_window_power(m, name, existing, fetch, run_id)
        if name in DATA_POWER_CHARTS:
            return _data_carrier_power(m, name, existing, fetch, run_id)
        if name in PRECODER_CHARTS:
            return _precoding(m, name, existing, fetch, run_id)
        return _relationships(m, name, existing, fetch, run_id)
    except ValueError as exc:
        return _unavailable(m, name, run_id, str(exc), CHART_SOURCES[name])
