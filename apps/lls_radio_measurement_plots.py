"""Source-bound control-signal and CSI/precoder plots.

This module deliberately does not reconstruct codebooks from a scalar PMI,
turn a pilot-fit residual into channel-estimation NMSE/EVM, or join CSI to a
grant just because their values happen to agree.
"""
from __future__ import annotations

import csv
import html
import hashlib
import io
import json
import math
import re
import sqlite3
from collections import defaultdict
from contextlib import contextmanager

TRIALS = ("air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv")
FEEDBACK = "air_interface/csv/csi_feedback_reports.csv"
RECEIVED_CSI = "air_interface/csv/received_csi_reports.csv"
CSI_OBLIGATIONS = "control/csv/configured_csi_report_obligations.csv"
CSI_TRIALS = "air_interface/csv/csi_rs_trials.csv"
TRS_TRIALS = "air_interface/csv/trs_trials.csv"
TRS_NMSE_CHART = "TRS channel NMSE timeline"
TRS_FREQUENCY_CHART = "TRS post-correction common frequency"
CONTROL_EVM = {
    "PRACH EVM": ("PRACH", "air_interface/csv/prach_evm_samples.csv"),
    "SSB EVM": ("SSB", "air_interface/csv/ssb_evm_samples.csv"),
    "CSI-RS EVM": ("CSI-RS", "air_interface/csv/csi_rs_evm_samples.csv"),
    "TRS received-pilot EVM": ("TRS", "air_interface/csv/trs_evm_samples.csv"),
    "SRS received-pilot EVM": ("SRS", "air_interface/csv/srs_evm_samples.csv"),
}
CSI_FIELDS = {"CSI CQI timeline": "CQI", "CSI RI timeline": "RI", "CSI CRI timeline": "CRI",
              "CSI PMI components timeline": "PMI", "CSI SINR timeline": "SINR_dB"}
CSI_POWER_FIELDS = {"CSI-RS RSRP timeline": ("RSRPPerAntenna_dBm", "RSRP (dBm)"),
                    "CSI-RS RSRP by resource": ("RSRPPerAntenna_dBm", "RSRP (dBm)"),
                    "CSI-RS RSSI timeline": ("RSSIPerAntenna_dBm", "RSSI (dBm)"),
                    "CSI-RS RSRQ timeline": ("RSRQPerAntenna_dB", "RSRQ (dB)")}
SSB_POWER_CHART = "SSB-window RSSI timeline"
DATA_POWER_CHARTS = {"PDSCH-window carrier RSSI timeline": TRIALS[:1],
                     "PUSCH-window carrier RSSI timeline": TRIALS[1:]}
PRECODER_CHARTS = {"reported versus applied PMI", "precoder ports and layers", "precoder matrix integrity"}
CHARTS = tuple(CONTROL_EVM) + tuple(CSI_FIELDS) + tuple(CSI_POWER_FIELDS) + tuple(DATA_POWER_CHARTS) + (SSB_POWER_CHART,) + tuple(sorted(PRECODER_CHARTS)) + (
    "measured_sinr_vs_slot", "clipping event histogram",
    "throughput vs SNR", "PDSCH BLER vs measured SINR", "PUSCH BLER vs measured SINR",
    "PUCCH BLER vs measured SINR", "CSI-RS pilot residual", "NMSE vs SNR / SINR", TRS_NMSE_CHART, TRS_FREQUENCY_CHART,
)
CHART_SOURCES = {name: (path, "air_interface/csv/control_evm_samples.csv")
                 for name, (_, path) in CONTROL_EVM.items()}
CHART_SOURCES.update({name: (RECEIVED_CSI, CSI_OBLIGATIONS, FEEDBACK) for name in CSI_FIELDS})
CHART_SOURCES["CSI SINR timeline"] = (RECEIVED_CSI, CSI_OBLIGATIONS, FEEDBACK, CSI_TRIALS)
CHART_SOURCES.update({name: ("air_interface/csv/csi_rs_trials.csv",) for name in CSI_POWER_FIELDS})
CHART_SOURCES[SSB_POWER_CHART] = ("air_interface/csv/pbch_trials.csv",)
CHART_SOURCES.update(DATA_POWER_CHARTS)
CHART_SOURCES.update({name: TRIALS + (RECEIVED_CSI, CSI_OBLIGATIONS, FEEDBACK) for name in PRECODER_CHARTS})
CHART_SOURCES["measured_sinr_vs_slot"] = TRIALS
CHART_SOURCES["clipping event histogram"] = TRIALS
CHART_SOURCES[TRS_NMSE_CHART] = (TRS_TRIALS,)
CHART_SOURCES[TRS_FREQUENCY_CHART] = (TRS_TRIALS,)
CHART_SOURCES.update({"throughput vs SNR": TRIALS, "NMSE vs SNR / SINR": TRIALS + ("air_interface/csv/srs_trials.csv", CSI_TRIALS),
    "PDSCH BLER vs measured SINR": TRIALS[:1], "PUSCH BLER vs measured SINR": TRIALS[1:],
    "PUCCH BLER vs measured SINR": ("air_interface/csv/pucch_trials.csv",),
    "CSI-RS pilot residual": ("air_interface/csv/csi_rs_trials.csv",)})
SOURCE_PATHS = TRIALS + (RECEIVED_CSI, CSI_OBLIGATIONS, FEEDBACK, "air_interface/csv/pucch_trials.csv",
    "air_interface/csv/csi_rs_trials.csv", "air_interface/csv/pbch_trials.csv",
    "air_interface/csv/prach_trials.csv", TRS_TRIALS, "air_interface/csv/control_evm_samples.csv",
    "beamforming/csv/precoder_evidence.csv") + tuple(path for _, path in CONTROL_EVM.values())


def _delivered(status):
    # Substring matching also accepts "not_delivered" and failed-decode states.
    return str(status).strip().lower() in {"delivered", "delivered_to_runtime_scheduler"}


def _feedback_rows(m, existing, fetch):
    """Prefer independent DL reception, including an empty/failed receive table.

    The legacy table also contains UL SRS-derived feedback, which is not a
    decoded DL CSI report. Keep it separately; never use its DL producer rows
    to fill missing fields/rows in the independently received table.
    """
    _, legacy = m._artifact_rows_by_path(existing, fetch, FEEDBACK)
    # The shared runtime publishes obligations before any receive result,
    # but writes the received-report CSV only after its first completion.
    # A missing receive CSV in that interval must not enable legacy UE-side
    # producer substitution. The calendar proves scope, not reception.
    if RECEIVED_CSI not in existing and CSI_OBLIGATIONS not in existing:
        return [(FEEDBACK, i, row) for i, row in enumerate(legacy, 1)]
    _, received = m._artifact_rows_by_path(existing, fetch, RECEIVED_CSI)
    for row in received:
        if (m._row_text(row, "Direction").upper() != "DL" or
                m._row_text(row, "SourceSignal") != "received_CSI_UCI"):
            raise ValueError("Independent CSI export must contain received DL UCI evidence.")
        if _delivered(m._row_text(row, "DeliveryStatus")) and m._row_text(row, "CSIUCIDecodeOk").lower() not in {"1", "true"}:
            raise ValueError("Delivered CSI requires an actual successful UCI decode.")
    return ([(RECEIVED_CSI, i, row) for i, row in enumerate(received, 1)] +
            [(FEEDBACK, i, row) for i, row in enumerate(legacy, 1)
             if m._row_text(row, "Direction").upper() == "UL"])


def _converter_clipping(m, name, existing, fetch, run_id):
    rows, histograms, sources = [], defaultdict(lambda: defaultdict(int)), []
    for path in TRIALS:
        _, measured = m._artifact_rows_by_path(existing, fetch, path)
        if not measured:
            continue
        sources.append(path)
        for index, raw in enumerate(measured, 1):
            identity = _identity(m, raw, path, index)
            for converter, endpoint in (("DAC", "TX"), ("ADC", "RX")):
                status = m._row_text(raw, converter + "ClippingStatus")
                if status != "measured":
                    continue
                count = m._row_float(raw, converter + "ClippedSampleCount")
                population = m._row_float(raw, converter + "ClippingSampleCount")
                ratio = m._row_float(raw, converter + "ClippingRatio")
                if (count is None or population is None or ratio is None or
                        count != int(count) or population != int(population) or
                        not 0 <= count <= population or population <= 0 or
                        not math.isclose(ratio, count / population, abs_tol=1e-12)):
                    raise ValueError("Converter clipping needs exact count/population/ratio closure.")
                source = m._row_text(raw, converter + "ClippingSource")
                definition = m._row_text(raw, converter + "ClippingPopulation")
                if not source or not definition:
                    raise ValueError("Converter clipping requires its executed source and sample population.")
                rows.append({**identity, "converter": converter, "endpoint": endpoint,
                             "clipped_complex_samples": int(count), "population_complex_samples": int(population),
                             "clipping_ratio": ratio, "population_definition": definition, "measurement_source": source})
                label = f"{identity['direction']} {endpoint} {converter} U{identity['ue_index']} {_point_label(identity)}"
                histograms[label][count] += 1
    series = {label: [[count, occurrences] for count, occurrences in sorted(hist.items())]
              for label, hist in histograms.items()}
    return _finish(m, name, run_id, rows, series, "Clipped complex samples per capture",
                   "Observed captures", "Measured TX DAC and RX ADC populations remain separate; no CFR-policy inference.", sources)


def _same_sweep_point(m, left, right):
    for fields in (("SweepPointIndex",), ("ConfiguredSNR_dB", "SNR_dB")):
        a, b = m._row_float(left, *fields), m._row_float(right, *fields)
        if a != b:  # Missing on one side is not evidence of matching identity.
            return False
    return True


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
            "sweep_point_index": m._row_text(row, "SweepPointIndex"),
            "configured_snr_db": m._row_float(row, "ConfiguredSNR_dB", "SNR_dB"),
            "source_table_logical_path": path, "source_row_index": index}


def _point_key(identity):
    return (identity["sweep_point_index"], identity["configured_snr_db"],
            identity["direction"], identity["ue_index"], identity["cell_id"])


def _point_label(identity):
    label = f"C{identity['cell_id'] or '?'}"
    if identity["sweep_point_index"]:
        label += f" point={identity['sweep_point_index']}"
    if identity["configured_snr_db"] is not None:
        label += f" ({identity['configured_snr_db']:g} dB reference)"
    return label


def _finish(m, name, run_id, rows, series, x_label, y_label, note, sources, *, display_title=None, extra_summary=()):
    if not rows or not series:
        return _unavailable(m, name, run_id, note, sources)
    records = [{"run_id": run_id, "chart_name": name, **row} for row in rows]
    return {"csv_bytes": m._encode_dict_rows(list(records[0]), records),
            "img_bytes": m._render_multi_series_svg(display_title or name, note,
                [{"name": label, "points": points} for label, points in series.items()],
                [f"source_records={len(rows)}", "Observed points; no sweep/fit claim", "See CSV for source and timing", *extra_summary],
                x_label=x_label, y_label=y_label, mode="scatter", evidence_shape_policy="operating_point",
                pad_constant_axes=True, max_points_per_series=None,
                wrap_legend=True, wrap_subtitle=True),
            "csv_status": "specialized_runtime_radio_measurement_dataset",
            "image_status": "generated_specialized_runtime_summary_svg", "source_table_path": "|".join(sources),
            "source_row_count": len(rows), "note": note}


def _measured_sinr(m, row):
    return m._measured_sinr_evidence(row)


def _trs_frequency_timeline(m, name, existing, fetch, run_id):
    rows, series = [], defaultdict(list)
    for path, trials in m._all_available_rows(existing, fetch, (TRS_TRIALS,)):
        for index, raw in enumerate(trials, 1):
            if m._row_flag(raw, "ResidualCFOEstimateAvailable") is not True:
                continue
            identity = _identity(m, raw, path, index)
            value = m._row_float(raw, "ResidualCFO_EstimatedPostCorrection_Hz")
            role = m._row_text(raw, "ResidualCFOEstimateRole")
            source = m._row_text(raw, "ResidualCFOEstimateSource")
            evidence = m._row_text(raw, "TRSResidualFrequencyEvidenceJSON")
            if (value is None or identity["slot"] is None or not source or not evidence or
                    m._row_flag(raw, "ResidualFrequencyUsesDifferentObservable") is not True or
                    role != "received_common_frequency_not_separated_oscillator"):
                raise ValueError("Post-correction TRS frequency needs its independently measured observable and explicit domain.")
            record = {**identity, "post_correction_common_frequency_hz": value,
                      "measurement_role": role, "estimator_source": source,
                      "correction_applied": m._row_flag(raw, "CFOCorrectionApplied"),
                      "applied_correction_hz": m._row_float(raw, "CFOCorrectionApplied_Hz"),
                      "estimator_evidence_json": evidence}
            rows.append(record)
            series[f"TRS U{identity['ue_index']} {_point_label(identity)} {source}"].append([identity["slot"], value])
    return _finish(m, name, run_id, rows, series, "TRS resource slot (one-based runtime)",
                   "Post-correction common frequency (Hz)",
                   "Different received observable from acquisition, on the same capture. Includes channel phase evolution; not separated oscillator CFO or estimate minus applied correction.", [TRS_TRIALS])


def _trs_nmse_timeline(m, name, existing, fetch, run_id):
    """Publish actual scored TRS observations without inventing a SINR axis.

    This reconciles retained aggregate operands, not the underlying complex
    samples. It neither qualifies tracking statistically nor substitutes the
    different CSI-RS reference plane for TRS.
    """
    rows, series = [], defaultdict(list)
    seen = set()
    for path, trials in m._all_available_rows(existing, fetch, (TRS_TRIALS,)):
        for index, raw in enumerate(trials, 1):
            identity = _identity(m, raw, path, index)
            if m._row_flag(raw, "NMSEScoringAvailable") is not True:
                continue
            source = m._row_text(raw, "NMSEReferenceSource")
            plane = m._row_text(raw, "ChannelNMSEReferencePlane")
            error = m._row_float(raw, "ChannelNMSEErrorEnergy")
            energy = m._row_float(raw, "ChannelNMSEReferenceEnergy")
            count = m._row_float(raw, "ChannelNMSEComparedComplexValues")
            pilots = m._row_float(raw, "ChannelNMSEPilotResourceCount")
            nmse = m._row_float(raw, "NMSE_dB")
            if (not source or not plane or any(token in (source + plane).lower()
                    for token in ("proxy", "fallback", "synthetic", "unavailable"))
                    or m._row_flag(raw, "ChannelNMSEReferenceUsedByReceiver") is not False
                    or m._row_flag(raw, "ChannelNMSEGainOrPhaseFitted") is not False
                    or error is None or error < 0 or energy is None or energy <= 0
                    or count is None or count <= 0 or count != int(count)
                    or pilots is None or pilots <= 0 or pilots != int(pilots) or pilots > count
                    or identity["slot"] is None):
                raise ValueError("TRS NMSE requires actual independent scoring source, plane and populations.")
            expected = 10 * math.log10(error / energy) if error else -math.inf
            # _row_float intentionally excludes nonfinite values; zero NMSE
            # is represented as -Inf dB, never an artificial finite floor.
            if expected == -math.inf and m._row_text(raw, "NMSE_dB").lower() in {"-inf", "-infinity"}:
                nmse = -math.inf
            if nmse is None or not math.isclose(nmse, expected, rel_tol=1e-10, abs_tol=1e-10):
                raise ValueError("TRS NMSE disagrees with retained independent scoring energies.")
            key = (_point_key(identity), identity["slot"], plane)
            if key in seen:
                raise ValueError("Duplicate TRS scoring identity in one sweep point.")
            seen.add(key)
            rows.append({**identity, "nmse_db": nmse, "nmse_linear": error / energy,
                "error_energy": error, "reference_energy": energy,
                "compared_complex_values": int(count), "pilot_resource_count": int(pilots),
                "reference_source": source, "reference_plane": plane,
                "qualification_mode": m._row_text(raw, "ChannelNMSEQualificationMode"),
                "scheduler_usable": m._row_flag(raw, "TRSRuntimeEvidenceUsable"),
                "strict_qualification_pass": m._row_flag(raw, "StrictOk"),
                "verification_scope": "retained_aggregate_arithmetic_not_complex_sample_or_statistical_qualification"})
    linear = any(row["nmse_db"] == -math.inf for row in rows)
    for row in rows:
        label = f"TRS U{row['ue_index']} {_point_label(row)} {row['reference_plane']}"
        series[label].append([row["slot"], row["nmse_linear"] if linear else row["nmse_db"]])
    return _finish(m, name, run_id, rows, series, "TRS resource slot (one-based runtime)",
        "Channel NMSE (linear ratio)" if linear else "Channel NMSE (dB)",
        "Measured TRS channel scores with retained energy/count reconciliation. Each sweep point and reference plane is separate. Scheduler usability is not qualification PASS; no SINR or residual CFO is inferred.",
        [TRS_TRIALS])


def _data_sinr_timeline(m, name, existing, fetch, run_id):
    """Preserve receiver observations across directions and sweep restarts."""
    rows, series, sources = [], defaultdict(list), []
    blocked = ("proxy", "synthetic", "fallback", "configured", "sweep", "oracle",
               "true_channel", "true-channel", "diagnostic", "not_scheduling",
               "not_for_scheduling", "unavailable", "failed", "rejected", "receiver_hest",
               "reference_signal_measurement", "pilot_sinr", "reference_signal_quality",
               "not_post_equalization", "not_applicable", "estimated", "conservative_min",
               "predicted", "prediction")
    for path, trials in m._all_available_rows(existing, fetch, TRIALS):
        sources.append(path)
        for index, row in enumerate(trials, 1):
            identity = _identity(m, row, path, index)
            evidence = _measured_sinr(m, row)
            status = evidence["status"].strip().lower()
            provenance = (evidence["source"] + " " + evidence["role"]).lower()
            valid = (evidence["value"] is not None and identity["slot"] is not None
                     and bool(evidence["source"].strip()) and bool(evidence["role"].strip())
                     and (status in {"ok", "pass", "measured"} or status.startswith("ok_"))
                     and "post_equalization" in provenance
                     and not any(token in provenance + " " + status for token in blocked))
            point = m._row_text(row, "SweepPointIndex")
            configured_snr = m._row_float(row, "ConfiguredSNR_dB")
            rows.append({**identity, "sweep_point_index": point,
                "configured_snr_db": configured_snr,
                "configured_snr_value_role": "configured_operating_point_metadata" if configured_snr is not None else "unavailable",
                "measured_sinr_db": evidence["value"] if valid else None,
                "sinr_source_field": evidence["field"], "sinr_source": evidence["source"],
                "sinr_value_role": evidence["role"], "sinr_value_status": evidence["status"],
                "value_status": "available" if valid else "receiver_sinr_or_slot_unavailable_or_ineligible"})
            if valid:
                label = (f'{identity["direction"]} UE {identity["ue_index"] or "?"} '
                         f'cell {identity["cell_id"] or "?"} point {point or "?"}')
                if configured_snr is not None:
                    label += f" ({configured_snr:g} dB reference)"
                series[label].append([identity["slot"], evidence["value"]])
    return _finish(m, name, run_id, rows, series, "Canonical slot",
        "Measured post-equalization SINR (dB)",
        "Individual receiver samples; direction, UE, cell and sweep points are never averaged together.", sources)


class _ExactControlSampleIdentities:
    """Disk-backed exact duplicate check; memory scales with observations.

    SQLite's empty filename creates a private temporary on-disk database,
    removed on close. This is scratch indexing, not primary measurement data.
    Full keys are preserved: no Bloom filter, digest collision or row cap.
    """

    def __enter__(self):
        self.groups = {}
        self.db = sqlite3.connect("")
        self.db.execute("PRAGMA cache_size=-2048")
        self.db.execute("PRAGMA journal_mode=OFF")
        self.db.execute("CREATE TABLE samples (g INTEGER, i TEXT, PRIMARY KEY(g,i)) WITHOUT ROWID")
        return self

    def add(self, key):
        group = self.groups.setdefault(key[:-1], len(self.groups))
        try:
            self.db.execute("INSERT INTO samples VALUES (?,?)", (group, str(key[-1])))
            return True
        except sqlite3.IntegrityError:
            return False

    def __exit__(self, *_):
        self.db.close()


def _control_evm(m, name, existing, fetch, run_id):
    _, canonical = CONTROL_EVM[name]
    sources = [canonical, "air_interface/csv/control_evm_samples.csv"]
    with m._first_available_csv_stream(existing, fetch, sources) as (path, samples):
        with _ExactControlSampleIdentities() as seen:
            return _control_evm_rows(m, name, run_id, path, samples, seen)


def _control_evm_rows(m, name, run_id, path, samples, seen):
    family, canonical = CONTROL_EVM[name]
    sources = [canonical, "air_interface/csv/control_evm_samples.csv"]
    buckets = {}
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
        if family in {"TRS", "SRS"}:
            expected_domain = "received_resource_elements"
        tx_domain = domain == "transmitter_resource_elements"
        if ((domain != expected_domain and not tx_domain) or definition != "reference_normalized_paired_symbol_evm"):
            return _unavailable(m, name, run_id, f"Control EVM requires {expected_domain} and the reference_normalized_paired_symbol_evm definition.", sources)
        if tx_domain and (reference_source != "actual_pre_TX_RF_waveform_on_declared_resource_clock" or
                alignment != "frozen_transmitter_OFDM_clock_no_gain_phase_or_timing_fit" or
                m._row_text(row, "PortRole") != "physical_TX_antenna_not_equalized_RX_stream"):
            return _unavailable(m, name, run_id, "Transmitter EVM requires actual pre/post-RF samples on the frozen TX clock, not a receiver estimate.", sources)
        isolated_srs = (family == "SRS" and
            reference_source == "same_executed_isolated_emitted_SRS_received_pilot_grid" and
            m._row_text(row, "IsolatedComponentProved").strip().lower() in {"true", "1"} and
            re.fullmatch(r"[0-9a-fA-F]{64}", m._row_text(row, "OriginalPairRecordSHA256")) is not None)
        if family in {"TRS", "SRS"} and (domain != expected_domain or
                not m._row_text(row, "ReferencePlane") or
                (reference_source != "same_executed_desired_link_received_pilot_grid" and not isolated_srs) or
                alignment != "recorded_receiver_timing_and_frequency_clock_no_fit" or
                m._row_text(row, "PortRole") != "physical_RX_branch_not_equalized_layer" or
                any(m._row_text(row, flag).strip().lower() in {"true", "1"}
                    for flag in ("GainOrPhaseFitted", "ReceiverUsesScoringReference"))):
            return _unavailable(m, name, run_id, f"{family} pilot error requires independently retained same-execution desired/received REs, with no fitted gain or phase.", sources)
        if identity["direction"] != ("UL" if family in {"PRACH", "SRS"} else "DL") or not identity["ue_index"]:
            return _unavailable(m, name, run_id, "Control signal direction or UE identity is missing/inconsistent.", sources)
        if "decision" in reference_source.lower() or "same_sample" in reference_source.lower():
            return _unavailable(m, name, run_id, "Decision-derived or same-sample fitted references cannot establish independent control EVM.", sources)
        sample_key = _point_key(identity) + (signal, domain, identity["frame"], identity["slot"],
                                           observation, port, int(sample_index))
        key = sample_key[:-1] + (definition, alignment, reference_source)
        if not seen.add(sample_key):
            return _unavailable(m, name, run_id, "Duplicate paired control-sample identity; refusing double-counted EVM.", sources)
        bucket = buckets.setdefault(key, {**identity, "signal_name": signal, "observation_id": observation,
            "port_index": port, "evm_definition": definition, "alignment_source": alignment,
            "reference_source": reference_source, "measurement_domain": domain,
            "reference_plane": m._row_text(row, "ReferencePlane"),
            "isolated_component_proved": bool(isolated_srs),
            "original_pair_record_sha256": m._row_text(row, "OriginalPairRecordSHA256"),
            "standardized_modulation_evm_qualified": False,
            "amplitude_reference_treatment": "pre_TX_RF_amplitude_no_PA_backoff_or_gain_removal" if tx_domain else ("same_execution_desired_pilot_grid_no_gain_phase_fit" if family in {"TRS", "SRS"} else "retained_reference_and_receiver_equalization"),
            "measurement_claim": "raw_gain_inclusive_TX_pair_error_not_standardized_modulation_EVM" if tx_domain else ("received_pilot_grid_pair_error_not_equalized_or_RF_conformance" if family in {"TRS", "SRS"} else "receiver_paired_symbol_error_not_RF_conformance"),
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
            plane = "TX RF raw gain-inclusive" if row["measurement_domain"] == "transmitter_resource_elements" else "RX equalized"
            if row["measurement_domain"] == "received_resource_elements":
                plane = "RX received pilots (not equalized)"
            series[f"{row['signal_name']} observation={row['observation_id']} {plane} {metric} P{row['port_index']} U{row['ue_index']} {_point_label(row)}"].append([row["slot"], row[f"{metric}_evm_pct"]])
    return _finish(m, name, run_id, rows, series, "Executed slot", "EVM (%)",
        "Independent paired control samples. TX raw error includes configured PA backoff/gain. TRS/SRS use actual received/desired pilot grids without a fitted gain/phase; other RX samples use their declared equalization. No conversion from SINR or pilot-fit residual. Not RF conformance EVM.", sources)


def _csi(m, name, existing, fetch, run_id):
    source = _feedback_rows(m, existing, fetch)
    field = CSI_FIELDS[name]
    rows, series = [], defaultdict(list)
    for path, index, row in source:
        identity = _identity(m, row, path, index)
        source_slot = m._row_float(row, "SourceSlot")
        reference_slot = m._row_float(row, "CSIReferenceSlot")
        authority = m._row_text(row, "SourceSlotAuthority")
        timing_role = "configured reference" if reference_slot is not None or "not_UE_measurement_slot" in authority else "source"
        plot_slot = reference_slot if reference_slot is not None else source_slot
        delivered_slot = m._row_float(row, "DeliveredSlot")
        decoded = path != RECEIVED_CSI or m._row_flag(row, "CSIUCIDecodeOk") is True
        # Retain failed reception/clock rows in a mixed-population CSV, but
        # never plot stale/default numeric fields as independently decoded
        # CSI when the receiver explicitly failed (or has no decode outcome).
        values = _numbers(m._row_text(row, field), integers=field != "SINR_dB") if decoded else []
        components = {f"{field}[{i}]" if len(values) > 1 else field: value for i, value in enumerate(values)}
        if field == "PMI" and decoded:
            named = {key: _numbers(m._row_text(row, key), integers=True)
                     for key in ("PMI_I11", "PMI_I12", "PMI_I13", "PMI_I2")}
            # Names come from explicit decoded columns, not packed-index arithmetic.
            if any(named.values()):
                if any(len(v) > 1 for v in named.values()):
                    raise ValueError("Named PMI component must be scalar")
                components = {key: v[0] for key, v in named.items() if v}
                values = list(components.values())
        sinr_source = m._row_text(row, "SINRSource") if field == "SINR_dB" else ""
        sinr_domain = m._row_text(row, "SINRMeasurementDomain") if field == "SINR_dB" else ""
        if sinr_source == "measured_csi_state_receiver_objective":
            sinr_domain = "csi_rs_selected_pmi_receiver_objective"
        record = {**identity, "source_slot": source_slot, "due_slot": m._row_float(row, "DueSlot"),
            "csi_reference_slot": reference_slot, "measurement_slot": None,
            "measurement_available_slot": None, "timing_role": timing_role,
            "source_slot_authority": authority, "measurement_identity": "", "snr_db": m._row_float(row, "ConfiguredSNR_dB", "SNR_dB"),
            "sweep_point_index": m._row_text(row, "SweepPointIndex"),
            "resource_id": m._row_text(row, "ResourceID"),
            "delivered_slot": delivered_slot, "delivery_status": m._row_text(row, "DeliveryStatus"),
            "report_identity": m._row_text(row, "ReportIdentity"), "source_signal": m._row_text(row, "SourceSignal"),
            "measurement_source": m._row_text(row, "MeasurementSource"), "metric_field": field,
            "sinr_source": sinr_source, "sinr_measurement_domain": sinr_domain,
            "sinr_value_role": m._row_text(row, "SINRValueRole") if field == "SINR_dB" else "",
            "sinr_value_status": m._row_text(row, "SINRValueStatus") if field == "SINR_dB" else "",
            "decoded_csi_fields_json": m._row_text(row, "DecodedCSIFieldsJSON"),
            "uci_decode_ok": m._row_text(row, "CSIUCIDecodeOk"),
            "uci_transport": m._row_text(row, "CSIUCITransport"),
            "scheduler_accepted_rank": m._row_float(row, "SchedulerAcceptedRank"),
            "scheduler_spatial_decision_deferred": m._row_text(row, "SchedulerSpatialDecisionDeferred"),
            "rank_confirmation_count": m._row_float(row, "RankIncreaseConfirmationCount"),
            "rank_confirmation_required": m._row_float(row, "RankIncreaseRequiredCount"),
            "component_fields": json.dumps(list(components)),
            "reported_value_token": m._row_text(row, field), "component_values": json.dumps(values),
            "value_status": "unavailable_uci_not_decoded" if not decoded else
                "available" if values and plot_slot is not None else "unavailable_in_source"}
        rows.append(record)
        if plot_slot is None:
            continue
        scope = f"{identity['direction']} U{identity['ue_index']} C{identity['cell_id']}"
        if record["snr_db"] is not None:
            scope += f" SNR{record['snr_db']:g}"
        if record["sweep_point_index"]:
            scope += f" point={record['sweep_point_index']}"
        for component, value in components.items():
            clock = "report ref" if timing_role == "configured reference" else timing_role
            series[f"{component} {clock}: {scope}"].append([plot_slot, value])
            if delivered_slot is not None and _delivered(record["delivery_status"]):
                if delivered_slot < plot_slot:
                    raise ValueError(f"CSI delivery precedes its source/reference in {path} row {index}")
                series[f"{component} delivered: {scope}"].append([delivered_slot, value])
        if (field == "RI" and record["scheduler_accepted_rank"] is not None and
                delivered_slot is not None and _delivered(record["delivery_status"])):
            label = f"Accepted rank (not TX): {scope}"
            series[label].append([delivered_slot, record["scheduler_accepted_rank"]])
    sources = list(dict.fromkeys(path for path, _, _ in source)) or [RECEIVED_CSI, FEEDBACK]
    if CSI_OBLIGATIONS in existing:
        sources.append(CSI_OBLIGATIONS)
    if field == "SINR_dB":
        _, measurements = m._artifact_rows_by_path(existing, fetch, CSI_TRIALS)
        sources.append(CSI_TRIALS)
        for index, row in enumerate(measurements, 1):
            identity = _identity(m, row, CSI_TRIALS, index)
            measured_slot = m._row_float(row, "CSIMeasurementSlot", "Slot")
            for metric, label, source_field, domain_field, status_field in (
                ("SINR_dB", "selected-PMI objective", "SINRSource", "SINRMeasurementDomain", "SINRValueStatus"),
                ("ReferenceMeasuredSINR_dB", "reference-RE SINR", "ReferenceMeasuredSINRSource",
                 "ReferenceMeasuredSINRDomain", "ReferenceMeasuredSINRStatus"),
            ):
                value = m._row_float(row, metric)
                if value is None or measured_slot is None:
                    continue
                metric_source = m._row_text(row, source_field)
                if not metric_source:
                    raise ValueError(f"CSI measurement {metric} has no source in row {index}")
                record = {**identity, "source_slot": None, "due_slot": None, "csi_reference_slot": None,
                    "measurement_slot": measured_slot, "measurement_available_slot": m._row_float(row, "ObservationDeliverySlot"),
                    "timing_role": "UE CSI-RS measurement", "source_slot_authority": "executed_CSI_RS_observation",
                    "measurement_identity": m._row_text(row, "CSIMeasurementID"), "snr_db": m._row_float(row, "ConfiguredSNR_dB", "SNR_dB"),
                    "sweep_point_index": m._row_text(row, "SweepPointIndex"),
                    "resource_id": m._row_text(row, "ResourceID"),
                    "delivered_slot": None, "delivery_status": "not_a_received_feedback_payload",
                    "report_identity": "", "source_signal": "CSI-RS", "measurement_source": m._row_text(row, "MeasurementSource"),
                    "metric_field": metric, "sinr_source": metric_source,
                    "sinr_measurement_domain": m._row_text(row, domain_field),
                    "sinr_value_role": m._row_text(row, "SINRValueRole") if metric == "SINR_dB" else "reference_RE_measurement",
                    "sinr_value_status": m._row_text(row, status_field), "decoded_csi_fields_json": "",
                    "uci_decode_ok": "", "uci_transport": "", "scheduler_accepted_rank": None,
                    "scheduler_spatial_decision_deferred": "", "rank_confirmation_count": None,
                    "rank_confirmation_required": None,
                    "component_fields": json.dumps([metric]), "reported_value_token": "",
                    "component_values": json.dumps([value]), "value_status": "available"}
                rows.append(record)
                scope = (f"DL U{identity['ue_index']} {label} C{identity['cell_id']}"
                         f" SNR{record['snr_db']} point={record['sweep_point_index']} resource={m._row_text(row, 'ResourceID')}")
                series[scope].append([measured_slot, value])
    note = "UE CSI-RS observations, configured report-reference slots and gNB delivery events remain distinct. Selected-PMI objective and reference-RE SINR are different measurements; neither is inserted into decoded CSI payloads. Pending reports are not delivered. Named PMI fields are used only when explicitly exported."
    if field == "CRI":
        note = ("Decoded CSI resource indicator (CRI), not a measured angle, applied data beam or active TCI state. "
                "Configured report-reference and received delivery slots remain distinct; no CRI is inferred from PMI, power or geometry.")
    elif field == "RI":
        note = "Reported RI and scheduler-accepted rank (not transmitted layers); report-reference and delivery clocks are distinct."
    return _finish(m, name, run_id, rows, series, "Runtime slot (UE observation / report reference / delivery)",
        "CSI SINR (dB; distinct measurement domains)" if field == "SINR_dB" else
        "Reported RI / accepted rank (not transmitted layers)" if field == "RI" else f"Reported {field} index",
        note, sources)


def _precoding(m, name, existing, fetch, run_id):
    reports = _feedback_rows(m, existing, fetch)
    rows, series, sources = [], defaultdict(list), []
    for path, trials in m._all_available_rows(existing, fetch, TRIALS):
        sources.append(path)
        for index, trial in enumerate(trials, 1):
            record = _identity(m, trial, path, index)
            slot = record["slot"]
            applied = _numbers(m._row_text(trial, "AppliedPrecoderPMI"), integers=True)
            requested = _numbers(m._row_text(trial, "RequestedPrecoderPMI"), integers=True)
            source_slot = m._row_float(trial, "LinkAdaptationAppliedFeedbackSourceSlot")
            eligible = [(p, r) for p, _, r in reports
                if m._row_text(r, "Direction").upper() == record["direction"]
                and m._row_text(r, "UEIndex", "UEID") == record["ue_index"]
                and (not record["cell_id"] or m._row_text(r, "ServingCell", "CellID") == record["cell_id"])
                and source_slot is not None and m._row_float(r, "SourceSlot") == source_slot
                and _same_sweep_point(m, trial, r)
                and _delivered(m._row_text(r, "DeliveryStatus"))
                and m._row_float(r, "DeliveredSlot") is not None and slot is not None
                and m._row_float(r, "DeliveredSlot") <= slot]
            feedback_path, feedback = eligible[0] if len(eligible) == 1 else ("", {})
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
                "feedback_source_table": feedback_path,
                "snr_db": m._row_float(trial, "ConfiguredSNR_dB", "SNR_dB"),
                "sweep_point_index": m._row_text(trial, "SweepPointIndex"),
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
            prefix = (f"{record['direction']} U{record['ue_index']} C{record['cell_id']}"
                      f" SNR{record['snr_db']} point={record['sweep_point_index']}")
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
        "Requested and executed precoders stay separate. Feedback is linked by sweep identity, an explicit applied source slot and prior delivery. Hash equality is not matrix-coefficient or optimality validation.", sources + list(dict.fromkeys(p for p, _, _ in reports)),
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


class _ChannelCSVHashReader(io.RawIOBase):
    """Hash the exact bounded byte chunks consumed by the CSV decoder."""

    def __init__(self, source):
        super().__init__()
        self.source = source
        self.digest = hashlib.sha256()
        self.eof = False

    def readable(self):
        return True

    def readinto(self, buffer):
        chunk = self.source.read(len(buffer))
        if not chunk:
            self.eof = True
            return 0
        self.digest.update(chunk)
        buffer[:len(chunk)] = chunk
        return len(chunk)


@contextmanager
def _verified_channel_csv_rows(fetch, artifact_id, expected_hash):
    """One source handle for both arithmetic and content-hash validation.

    Local callers stream; legacy/remote byte callbacks are fetched once.
    A result cannot leave this context before every parsed byte is hashed.
    """
    opener = getattr(fetch, "open_artifact_binary", None)
    source = opener(artifact_id) if callable(opener) else io.BytesIO(fetch(artifact_id))
    with source:
        source.seek(0, io.SEEK_END)
        size = source.tell()
        source.seek(0)
        previous_limit = csv.field_size_limit()
        csv.field_size_limit(max(previous_limit, size + 1))
        try:
            hashed = _ChannelCSVHashReader(source)
            with io.TextIOWrapper(io.BufferedReader(hashed), encoding="utf-8-sig", newline="") as text:
                reader = csv.DictReader(text, strict=True)
                names = reader.fieldnames or []
                if not names or len(names) != len(set(names)):
                    raise ValueError("Invalid channel NMSE resource CSV header")

                def rows():
                    for sample in reader:
                        if None in sample or any(value is None for value in sample.values()):
                            raise ValueError("Invalid channel NMSE resource CSV row width")
                        yield sample

                yield rows()
                if not hashed.eof:
                    raise ValueError("Channel NMSE resource stream was not fully consumed")
                if hashed.digest.hexdigest() != expected_hash:
                    raise ValueError("Channel NMSE resource hash mismatch")
        finally:
            csv.field_size_limit(previous_limit)


def _scored_data_channel_nmse(m, row, existing, fetch):
    """Reconcile the displayed value to independently scored pilot resources."""
    path = m._row_text(row, "ChannelEstimateResourcesCSV").replace("\\", "/")
    if not path:
        return None
    if not path.startswith("channel_estimation/csv/") or ".." in path.split("/"):
        raise ValueError("Invalid channel NMSE resource path")
    csi = m._row_text(row, "SignalFamily") == "CSI-RS"
    source = m._row_text(row, "ChannelNMSESource" if csi else "NMSESource")
    plane = m._row_text(row, "ChannelNMSEReferencePlane" if csi else "ChannelEstimateReferencePlane")
    # An isolated post-decode score is not a shared physical-channel/path-gain
    # archive. Retain its own identity; do not invent a ChannelObservationID
    # that would falsely assert the stronger shared-channel evidence contract.
    identity_field = ("ChannelEstimateObservationID" if m._row_text(row, "ChannelEstimateObservationID")
                      else "ChannelObservationID")
    if csi:
        identity_field = "CSIChannelEstimateObservationID"
    observation = m._row_text(row, identity_field)
    count = m._row_float(row, "ChannelNMSEComparedComplexValues" if csi else "ChannelEstimateComparedValues")
    value = m._row_float(row, "NMSE_dB")
    if m._row_text(row, "NMSE_dB").lower() == "-inf":
        value = -math.inf
    if (not source or not plane or not observation or count is None or count < 1
            or count != int(count) or value is None
            or m._row_flag(row, "ChannelNMSEReferenceUsedByReceiver" if csi else "ChannelEstimateReferenceUsedByReceiver") is not False
            or (csi and m._row_flag(row, "NMSEScoringAvailable") is not True)):
        raise ValueError("Incomplete independently scored channel NMSE identity")
    artifact = existing.get(path)
    if artifact is None:
        raise ValueError("Missing scored channel NMSE resources")
    error_energy = reference_energy = 0.0
    actual_count = 0
    with _verified_channel_csv_rows(fetch, int(artifact["artifact_id"]),
            m._row_text(row, "ChannelEstimateResourcesCSVSHA256")) as samples, \
            _ExactControlSampleIdentities() as coordinates:
        for sample in samples:
            actual_count += 1
            if (m._row_text(sample, identity_field) != observation
                    or m._row_text(sample, "ChannelReferenceSource") != source
                    or m._row_text(sample, "ChannelReferencePlane") != plane
                    or m._row_flag(sample, "ReferenceUsedByReceiver") is not False
                    or m._row_flag(sample, "GainOrPhaseFitted") is not False):
                raise ValueError("Channel NMSE reference identity mismatch")
            coordinate = tuple(m._row_float(sample, key) for key in
                ("SubcarrierIndex0", "SymbolIndex0", "RxBranchIndex0", "ReferencePortIndex0"))
            if csi:
                coordinate = (m._row_float(sample, "ResourceID"),) + coordinate
            if any(v is None or v < 0 or int(v) != v for v in coordinate):
                raise ValueError("Invalid or repeated channel NMSE resource coordinate")
            # One fixed group keeps the index's in-memory group dictionary
            # constant-sized; complete integer tuples live in scratch SQLite.
            if not coordinates.add(("channel_nmse", tuple(int(v) for v in coordinate))):
                raise ValueError("Invalid or repeated channel NMSE resource coordinate")
            values = [m._row_float(sample, key) for key in
                ("HReal", "HImag", "ReferenceHReal", "ReferenceHImag", "ChannelErrorEnergy", "ReferenceChannelEnergy")]
            if any(v is None for v in values):
                raise ValueError("Missing channel NMSE complex values")
            hr, hi, rr, ri, err, ref = values
            if not math.isclose(err, (hr-rr)**2+(hi-ri)**2, rel_tol=1e-10, abs_tol=1e-25) or not math.isclose(
                    ref, rr**2+ri**2, rel_tol=1e-10, abs_tol=1e-25):
                raise ValueError("Channel NMSE energy disagrees with retained complex channels")
            error_energy += err
            reference_energy += ref
    if actual_count != int(count):
        raise ValueError("Channel NMSE resource count mismatch")
    if error_energy < 0 or reference_energy <= 0:
        raise ValueError("Channel NMSE requires nonnegative error and positive reference energy")
    independently_reduced = -math.inf if error_energy == 0 else 10*math.log10(error_energy/reference_energy)
    if not math.isclose(value, independently_reduced, rel_tol=1e-10, abs_tol=1e-9):
        raise ValueError("Channel NMSE value disagrees with independent pilot energies")
    return value


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
        paths = TRIALS + ("air_interface/csv/srs_trials.csv", CSI_TRIALS)
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
                    count = m._row_float(row, "ExpectedBitCount", "PUCCHExpectedBitCount")
                    # Presence is a binary producer fact, not a generic
                    # PASS/FAIL display status. "unavailable" is unknown;
                    # arbitrary nonzero numbers must not become true.
                    presence_number = m._row_float(row, "PUCCHTransmissionPrepared")
                    presence_text = m._row_text(row, "PUCCHTransmissionPrepared").lower()
                    prepared, invalid_presence = None, False
                    if presence_number in (0, 1):
                        prepared = bool(presence_number)
                    elif presence_text in ("true", "yes", "false", "no"):
                        prepared = presence_text in ("true", "yes")
                    elif presence_text not in ("", "nan", "<missing>", "missing", "unavailable"):
                        invalid_presence = True
                    population = "decode_outcome_unavailable" if decoded is None else "observed_payload_decode"
                    if invalid_presence or (count is not None and (count < 0 or count != int(count))):
                        population = "invalid_transmission_evidence"
                    elif prepared is True and count == 0:
                        population = "conflicting_transmission_evidence"
                    elif prepared is False or count == 0:
                        # Receiver-only false-alarm/DTX trials and quiet SR
                        # occasions belong to a different population. An
                        # expected RX layout does not prove UE transmission.
                        population = "not_a_transmitted_payload_block"
                    elif prepared is not True and count is None:
                        # Missing is not zero. Decoder acceptance alone can
                        # be a false alarm and must not establish TX presence.
                        population = "transmission_evidence_unavailable"
                    if population != "observed_payload_decode":
                        y = None
                    record["block_error_population_status"] = population
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
                if m._row_text(row, "ChannelEstimateResourcesCSV"):
                    y = _scored_data_channel_nmse(m, row, existing, fetch)
                    y_field = "NMSE_dB_independently_reconciled_to_complex_pilot_resources"
            record.update({"x_value": x, "x_source_field": x_field, "x_source": x_source,
                "metric_value": y, "metric_source_field": y_field,
                "metric_reference_source": m._row_text(row, "NMSEReferenceSource", "NMSESource", "ChannelNMSESource") if name == "NMSE vs SNR / SINR" else "",
                "metric_reference_plane": m._row_text(row, "ChannelEstimateReferencePlane", "ChannelNMSEReferencePlane") if name == "NMSE vs SNR / SINR" else "",
                "signal_family": m._row_text(row, "SignalFamily") or path.rsplit("/", 1)[-1].removesuffix("_trials.csv"),
                "mcs": m._row_text(row, "MCS", "MCSIndex"), "layers": m._row_text(row, "Layers"),
                "format": m._row_text(row, "Format", "PUCCHFormat"),
                "crc_pass": m._row_text(row, "CRCPass"),
                "noise_operating_mode": m._row_text(row, "NoiseOperatingMode"),
                "value_status": "available" if x is not None and y is not None else "required_measurement_unavailable"})
            if record.get("block_error_population_status") == "not_a_transmitted_payload_block":
                # An observed empty/SR-negative occasion is not missing a
                # required block measurement. Do not manufacture a BLER value
                # or promote this applicability label into a decode PASS.
                record["value_status"] = "not_applicable_no_transmitted_payload"
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
                reference_label = f" {record['signal_family']} {record['metric_reference_plane']}" if name == "NMSE vs SNR / SINR" else ""
                series[f"{limit_label}{record['direction']} U{record['ue_index']}{reference_label} {y_field}"].append([x, y])
    linear_nmse_axis = name == "NMSE vs SNR / SINR" and any(r["metric_value"] == -math.inf for r in rows)
    if linear_nmse_axis:
        # Show an exact zero in linear units, retaining the original -Inf dB
        # measurement in CSV. A finite dB floor would invent measurement data.
        series = defaultdict(list)
        for r in rows:
            value = r["metric_value"]
            r["plotted_nmse_linear"] = None if value is None else 10**(value/10)
            if r["x_value"] is not None and value is not None:
                series[f"{r['direction']} U{r['ue_index']} {r['signal_family']} {r['metric_reference_plane']} independent channel NMSE"].append(
                    [r["x_value"], r["plotted_nmse_linear"]])
    notes = {"throughput vs SNR": "Scheduled TB bitrate and Delivered goodput are separate measured series. Actual noise-calibration SNR; no configured-SNR substitution or controlled sweep is claimed.",
             "CSI-RS pilot residual": "Measured residual on channel-estimation pilots. This is neither independent channel NMSE nor CSI-RS EVM.",
             "NMSE vs SNR / SINR": "Independent channel-reference scoring, not pilot-fit residual or noise/gain. Data-channel and CSI-RS values reconcile to hashed complex pilot resources. Different signals/reference planes remain separate series; CSI nominal-channel scores include RF-induced estimate error. Exact zero uses a linear plot axis."}
    note = notes.get(name, "Individual measured block-error outcomes (0/1), not a fitted BLER curve or an independent Monte Carlo sweep. MCS/rank/format retained per trial.")
    if name == "PUCCH BLER vs measured SINR" and rows and not series:
        populations = defaultdict(int)
        for row in rows:
            populations[row["block_error_population_status"]] += 1
        note += " No plottable UCI-block/SINR pairs. Observed population states: " + "; ".join(
            f"{state}={count}" for state, count in sorted(populations.items())) + "."
    limited_count = sum(row.get("x_is_limited", False) and row["value_status"] == "available" for row in rows)
    limit_summary = [f"Limited SINR values: {limited_count}", "Limited values are not raw estimates"] if limited_count else []
    return _finish(m, name, run_id, rows, series,
        "Executed CSI-RS slot" if name == "CSI-RS pilot residual" else "Applied noise-calibration SNR (dB)" if name == "throughput vs SNR" else "Receiver SINR (dB); includes limited values" if limited_count else "Measured SINR (dB)",
        "Scheduled TB bitrate / delivered goodput (Mbit/s)" if name == "throughput vs SNR" else "Pilot-fit residual (dB)" if name == "CSI-RS pilot residual" else "Channel NMSE (linear ratio)" if linear_nmse_axis else "Channel NMSE (dB); declared reference plane" if name == "NMSE vs SNR / SINR" else "Observed block error (0/1)", note, list(paths), extra_summary=limit_summary)


def _operand_present(m, row, field):
    token = m._row_text(row, field).strip().lower()
    return bool(token and token not in {"nan", "<missing>", "not_applicable"} and
                not token.startswith(("not_recorded_by_active_", "not_emitted_by_active_", "not_applicable_for_active_")))


def _internal_element_binding(m, row, csi=False):
    """Validate retained internal column execution without promoting RF authority."""
    field = "PhysicalMeasurementPlaneBindingJSON" if csi else "SSBReceiveElementBindingEvidenceJSON"
    token = m._row_text(row, field)
    evidence = json.loads(token)
    if csi:
        if hashlib.sha256(token.encode()).hexdigest() != m._row_text(row, "PhysicalMeasurementPlaneBindingSHA256"):
            raise ValueError("CSI internal measurement binding digest mismatch.")
        demod = m._row_text(row, "PhysicalMeasurementDemodulationReceiptJSON")
        digest = hashlib.sha256(demod.encode()).hexdigest()
        if (digest != evidence.get("OriginalDemodulationReceiptSHA256") or
                digest != m._row_text(row, "PhysicalMeasurementDemodulationReceiptSHA256") or
                json.loads(demod).get("InputSHA256") != evidence.get("OriginalInputSHA256")):
            raise ValueError("CSI internal measurement lacks its original demodulation binding.")
        evidence = evidence.get("ReceiveElementBinding", {})
    if (evidence.get("Available") is not True or
            evidence.get("ReferencePlane") != "internal_physical_receive_element_before_RX_front_end" or
            any(evidence.get(k) is not False for k in ("RFReferenceQualified", "PowerUnitQualified",
                "StandardizedReferencePointQualified", "HardwareConformanceVerified", "AccuracyQualified"))):
        raise ValueError("Internal element observations require explicit limited qualification.")
    layout = evidence.get("Layout", {})
    receipts = evidence.get("IntervalReceipts", [])
    if isinstance(receipts, dict):
        receipts = [receipts]
    if (not re.fullmatch(r"[0-9a-fA-F]{64}", str(layout.get("LayoutSHA256", ""))) or not receipts or
            any(r.get("ExecutionVerified") is not True or r.get("OriginalSampleOrderingPreserved") is not True or
                r.get("LayoutSHA256") != layout["LayoutSHA256"] or
                not re.fullmatch(r"[0-9a-fA-F]{64}", str(r.get("ReceiptSHA256", ""))) or
                r.get("ElementInputSHA256") != r.get("RFInputSHA256") for r in receipts)):
        raise ValueError("Internal element measurements lack original layout/execution receipts.")


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
        identity.update(snr_db=m._row_float(row, "ConfiguredSNR_dB", "SNR_dB"),
                        sweep_point_index=m._row_text(row, "SweepPointIndex"))
        point = (identity["sweep_point_index"], identity["snr_db"])
        scope = f"U{identity['ue_index']} C{identity['cell_id']}"
        if identity["snr_db"] is not None:
            scope += f" SNR{identity['snr_db']:g}"
        if identity["sweep_point_index"]:
            scope += f" p{identity['sweep_point_index']}"
        relative = physical_status == "available_normalized_fixed_esn0_not_absolute_dbm"
        if relative and not m._row_text(row, "MeasurementPhysicalResourcesJSON"):
            # Legacy rows retain only the selected resource's branch vector.
            # Current producers retain every measured resource in JSON below.
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
                metric, metric_field = {
                    "RSRPPerAntenna_dBm": (rsrp, "MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"),
                    "RSSIPerAntenna_dBm": (rssi, "MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"),
                    "RSRQPerAntenna_dB": (rsrq, "MeasurementRSRQPerReceiveAntenna_dB"),
                }[field]
                rid = m._row_text(row, "ResourceID")
                key = (identity["ue_index"], identity["cell_id"], m._row_text(row, "BWPID"),
                       identity["frame"], identity["slot"], m._row_text(row, "CSIMeasurementID"),
                       rid, branch, *point)
                if key in seen:
                    raise ValueError("Duplicate CSI-RS physical measurement identity; refusing double-counting.")
                seen.add(key)
                rows.append({**identity, "bwp_id": m._row_text(row, "BWPID"),
                    "measurement_id": m._row_text(row, "CSIMeasurementID"),
                    "resource_id": m._row_text(row, "ResourceID"),
                    "receive_antenna_index_1based": branch, "metric_value": metric,
                    "metric_source_field": metric_field,
                    "power_reference_plane": plane, "measurement_scope": "selected_resource_vector_only", "num_rb": int(n_rb),
                    "first_prb_0based": int(first_prb), "subcarrier_spacing_khz": scs,
                    "bandwidth_hz": bandwidth, "symbol_indices_0based": json.dumps(symbols),
                    "rsrp_db_re_unit_occupied_re_es": rsrp,
                    "rssi_db_re_unit_occupied_re_es": rssi, "rsrq_db": rsrq})
                if identity["slot"] is not None:
                    series[f"Rx{branch} R{rid} {scope}"].append([identity["slot"], metric])
            continue
        if relative:
            if (plane != "normalized_fixed_esn0_unit_occupied_re_es" or
                    m._row_text(row, "MeasurementSource") != "actual_csirs_re_measurement_relative_to_unit_occupied_re_es"):
                raise ValueError("Normalized CSI-RS power requires its actual unit-RE measurement source and plane.")
        else:
            internal = plane == "internal_physical_receive_element_before_RX_front_end"
            if internal:
                _internal_element_binding(m, row, csi=True)
            if plane not in {"receiver_antenna_connector_pre_composite_front_end",
                             "receiver_antenna_connector_no_composite_front_end", "internal_physical_receive_element_before_RX_front_end"}:
                raise ValueError("CSI-RS physical power requires an explicit antenna-connector measurement plane.")
            if m._row_text(row, "MeasurementSource") not in {
                    "nrCSIRSMeasurements_runtime_pre_front_end_antenna_plane_grid",
                    "received_port3000_linear_RSRP_and_native_RSSI_pre_front_end_grid"}:
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
            accepted_sources = ({"received_port3000_linear_RSRP_and_native_RSSI_normalized_unit_RE_grid"}
                if relative else {"nrCSIRSMeasurements_actual_physical_grid",
                                  "received_port3000_linear_RSRP_and_nrCSIRSMeasurements_RSSI"})
            if resource.get("Source") not in accepted_sources:
                raise ValueError("CSI-RS resource has no supported physical-grid source.")
            if relative and resource.get("PowerUnit") != "relative_to_unit_occupied_RE_Es":
                raise ValueError("Normalized CSI-RS resource has inconsistent power units.")
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
            suffix = "_dB_re_UnitOccupiedRE_Es" if relative else "_dBm"
            metric_fields = ("RSRPPerAntenna"+suffix, "RSSIPerAntenna"+suffix, "RSRQPerAntenna_dB")
            measured_field = field.replace("_dBm", suffix)
            vectors = {}
            for metric in metric_fields + ("SymbolIndices0Based",):
                token = resource.get(metric)
                vectors[metric] = _numbers(json.dumps(token), integers=metric == "SymbolIndices0Based")
            if any(len(vectors[v]) != n_rx for v in metric_fields) or not vectors["SymbolIndices0Based"]:
                raise ValueError("CSI-RS physical measurement vectors or measurement-symbol window are missing.")
            for branch in range(int(n_rx)):
                rsrp, rssi, rsrq = (vectors[v][branch] for v in metric_fields)
                if abs(rsrq - (10*math.log10(n_rb)+rsrp-rssi)) > 1e-6:
                    raise ValueError("CSI-RS same-branch RSRP/RSSI/RSRQ closure fails.")
                bwp = m._row_text(row, "BWPID")
                measurement_id = m._row_text(row, "CSIMeasurementID")
                key = (identity["ue_index"], identity["cell_id"], bwp, identity["frame"], identity["slot"], measurement_id, rid, branch, *point)
                if key in seen:
                    raise ValueError("Duplicate CSI-RS physical measurement identity; refusing double-counting.")
                seen.add(key)
                value = vectors[measured_field][branch]
                power_values = ({"rsrp_db_re_unit_occupied_re_es": rsrp,
                                 "rssi_db_re_unit_occupied_re_es": rssi} if relative else
                                {"rsrp_dbm": rsrp, "rssi_dbm": rssi})
                rows.append({**identity, "bwp_id": bwp, "measurement_id": measurement_id,
                    "resource_id": rid, "receive_antenna_index_1based": branch+1,
                    "metric_value": value, "metric_source_field": measured_field, "power_reference_plane": plane,
                    "measurement_scope": "all_retained_resource_records",
                    "num_rb": n_rb, "first_prb_0based": first_prb, "subcarrier_spacing_khz": scs,
                    "bandwidth_hz": bandwidth, "symbol_indices_0based": json.dumps(vectors["SymbolIndices0Based"]),
                    **power_values, "rsrq_db": rsrq})
                if identity["slot"] is not None:
                    series[f"Rx{branch+1} R{rid} {scope}"].append([identity["slot"], value])
    normalized = any(row.get("power_reference_plane") == "normalized_fixed_esn0_unit_occupied_re_es" for row in rows)
    if normalized and any(row.get("power_reference_plane") != "normalized_fixed_esn0_unit_occupied_re_es" for row in rows):
        raise ValueError("Absolute and normalized power cannot share one numeric measurement axis.")
    display_units = units.replace("(dBm)", "(dB re unit occupied-RE Es)") if normalized else units
    internal = any(r.get("power_reference_plane") == "internal_physical_receive_element_before_RX_front_end" for r in rows)
    if internal and any(r.get("power_reference_plane") != "internal_physical_receive_element_before_RX_front_end" for r in rows):
        raise ValueError("Internal element and connector powers require separate plots.")
    if internal:
        display_units += " at internal pre-RX element plane (simulated units)"
        for r in rows:
            r.update(standardized_reference_point_qualified=False, hardware_qualified=False, rf_reference_qualified=False, power_unit_qualified=False, accuracy_qualified=False)
    note = ("Actual CSI-RS waveform measurements in the fixed-Es/N0 normalized power plane, not dBm. All retained resource records and receive branches are plotted; legacy selected-resource-only rows are explicitly scoped in CSV."
            if normalized else "Actual CSI-RS antenna-plane measurements; all retained receive branches and resources. RSSI uses only the recorded bandwidth and CSI-RS symbol window.")
    if internal:
        note = "Original internal physical receive-element measurements before RX front end; simulated dBm operands, not an antenna-connector reference or standardized/hardware qualification. All original resource and branch values retained."
    by_resource = name == "CSI-RS RSRP by resource"
    for record in rows:
        resource_ids = _numbers(str(record["resource_id"]), integers=True)
        if by_resource and len(resource_ids) != 1:
            raise ValueError("A per-resource power plot requires an explicit nonnegative CSI resource ID.")
        record["plot_x_value"] = resource_ids[0] if by_resource else record["slot"]
        record["plot_x_semantics"] = "configured_resource_id_not_angle" if by_resource else "measurement_slot"
    if by_resource:
        series = defaultdict(list)
        for record in rows:
            label = f"Rx{record['receive_antenna_index_1based']} U{record['ue_index']} C{record['cell_id']}"
            if record["slot"] is not None:
                label += f" slot{record['slot']:g}"
            if record["snr_db"] is not None:
                label += f" SNR{record['snr_db']:g}"
            if record["sweep_point_index"]:
                label += f" p{record['sweep_point_index']}"
            series[label].append([record["plot_x_value"], record["metric_value"]])
        note = "Measured RSRP by configured CSI resource and receive branch; resource ID is not an angle or active TCI state. " + note
    return _finish(m, name, run_id, rows, series,
                   "CSI resource ID (not physical angle)" if by_resource else "Measurement slot",
                   display_units, note, sources)


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
            try:
                evidence = json.loads(m._row_text(row, "SSBWindowRelativePowerMeasurementJSON"))
            except (ValueError, TypeError) as exc:
                raise ValueError("Normalized SSB RSSI requires retained linear symbol-power evidence.") from exc
            if not isinstance(evidence, dict):
                raise ValueError("Normalized SSB RSSI requires one measurement object.")
            required = {"Available": True, "Source": "nrSSBMeasurements_actual_antenna_plane_ssb_grid",
                "Scope": "ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI",
                "AmplitudeUnit": "sqrt_UnitOccupiedRE_Es", "CPIncluded": False,
                "NumRB": 20, "NumSubcarriers": 240, "SymbolIndicesWithinSSB0Based": [0, 1, 2, 3]}
            if any(evidence.get(k) != v for k, v in required.items()):
                raise ValueError("Normalized SSB RSSI has incorrect scope, units or symbol window.")
            n_rx = evidence.get("NumReceiveAntennas")
            scs, bandwidth = evidence.get("SubcarrierSpacing_kHz"), evidence.get("Bandwidth_Hz")
            if (not isinstance(n_rx, (int, float)) or isinstance(n_rx, bool) or n_rx != len(rssis) or
                    not isinstance(scs, (int, float)) or isinstance(scs, bool) or not math.isfinite(scs) or scs <= 0 or
                    not isinstance(bandwidth, (int, float)) or isinstance(bandwidth, bool) or
                    not math.isclose(bandwidth, 240*scs*1000, rel_tol=1e-12)):
                raise ValueError("Normalized SSB RSSI has inconsistent receive branches or bandwidth.")
            powers = evidence.get("SymbolPowerPerAntenna_UnitOccupiedRE_Es")
            mirrors = _numbers(json.dumps(evidence.get("RSSIPerAntenna_dB_re_UnitOccupiedRE_Es")))
            if n_rx == 1 and isinstance(powers, list) and all(isinstance(v, (int, float)) for v in powers):
                powers = [[v] for v in powers]
            if (len(mirrors) != n_rx or not isinstance(powers, list) or len(powers) != 4 or
                    any(not isinstance(p, list) or len(p) != n_rx for p in powers) or
                    "SymbolPowerPerAntenna_W" in evidence or "RSSIPerAntenna_dBm" in evidence):
                raise ValueError("Normalized SSB RSSI lacks four-symbol branch powers or claims absolute units.")
            ssb = m._row_float(row, "SSBIndex")
            first, stop, fs = (m._row_float(row, f) for f in
                              ("ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz"))
            if (not rssis or identity["direction"] != "DL" or not identity["ue_index"] or ssb is None or
                    ssb < 0 or ssb != int(ssb) or any(v is None for v in (first, stop, fs)) or
                    first < 0 or first != int(first) or stop <= first or stop != int(stop) or fs <= 0):
                raise ValueError("Normalized SSB-window RSSI lacks branch, beam, or received-burst identity.")
            for branch, rssi in enumerate(rssis, 1):
                values = [p[branch-1] for p in powers]
                if any(not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v) or v < 0 for v in values) or sum(values) <= 0:
                    raise ValueError("Normalized SSB symbol powers must have finite positive window energy.")
                expected = 10*math.log10(sum(values)/4)
                if abs(rssi-expected) > 1e-7 or abs(mirrors[branch-1]-expected) > 1e-7:
                    raise ValueError("Normalized SSB RSSI fails same-branch linear symbol-power closure.")
                key = _point_key(identity) + (first, stop, int(ssb), branch)
                if key in seen:
                    raise ValueError("Duplicate normalized received SSB/branch RSSI identity.")
                seen.add(key)
                rows.append({**identity, "ssb_index_0based": int(ssb),
                    "receive_antenna_index_1based": branch,
                    "rssi_db_re_unit_occupied_re_es": rssi,
                    "bandwidth_hz": bandwidth, "subcarrier_spacing_khz": scs,
                    "symbol_indices_within_ssb_0based": "[0, 1, 2, 3]",
                    "symbol_powers_unit_occupied_re_es": json.dumps(values),
                    "burst_observation_start_sample": int(first),
                    "burst_observation_end_sample_exclusive": int(stop),
                    "sample_rate_hz": fs, "power_reference_plane": plane,
                    "measurement_scope": "received_ssb_240_subcarrier_four_symbol_window_normalized_fixed_esn0"})
                if identity["slot"] is not None:
                    series[f"U{identity['ue_index']} SSB{int(ssb)} Rx{branch} {_point_label(identity)}"].append([identity["slot"], rssi])
            continue
        identity = _identity(m, row, path, index)
        plane = m._row_text(row, "PowerReferencePlane")
        internal = plane == "actual_post_tx_rf_sss_epre_to_internal_physical_receive_element_before_RX_front_end"
        if internal:
            _internal_element_binding(m, row)
        if plane not in {"receiver_antenna_connector_pre_composite_front_end",
                         "receiver_antenna_connector_no_composite_front_end", "actual_post_tx_rf_sss_epre_to_internal_physical_receive_element_before_RX_front_end"}:
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
            key = _point_key(identity) + (first, stop, ssb, branch)
            if key in seen:
                raise ValueError("Duplicate received SSB/branch RSSI identity.")
            seen.add(key)
            rows.append({**identity, "ssb_index_0based": int(ssb), "receive_antenna_index_1based": branch+1,
                "rssi_dbm": rssis[branch], "bandwidth_hz": bandwidth, "subcarrier_spacing_khz": scs,
                "symbol_indices_within_ssb_0based": "[0, 1, 2, 3]", "symbol_powers_w": json.dumps(values),
                "burst_observation_start_sample": first, "burst_observation_end_sample_exclusive": stop,
                "sample_rate_hz": fs, "power_reference_plane": plane, "measurement_scope": evidence["Scope"]})
            if identity["slot"] is not None:
                series[f"U{identity['ue_index']} SSB{int(ssb)} Rx{branch+1} {_point_label(identity)}"].append([identity["slot"], rssis[branch]])
    normalized = any(row.get("power_reference_plane") == "normalized_fixed_esn0_unit_occupied_re_es" for row in rows)
    if normalized and any(row.get("power_reference_plane") != "normalized_fixed_esn0_unit_occupied_re_es" for row in rows):
        raise ValueError("Absolute and normalized SSB power cannot share one numeric measurement axis.")
    units = "SSB-window RSSI (dB re unit occupied-RE Es)" if normalized else "SSB-window RSSI (dBm)"
    internal = any(r.get("power_reference_plane") == "actual_post_tx_rf_sss_epre_to_internal_physical_receive_element_before_RX_front_end" for r in rows)
    if internal and any(r.get("power_reference_plane") != "actual_post_tx_rf_sss_epre_to_internal_physical_receive_element_before_RX_front_end" for r in rows):
        raise ValueError("Internal element and connector SSB powers require separate plots.")
    if internal:
        units += " at internal pre-RX element plane (simulated units)"
        for r in rows:
            r.update(standardized_reference_point_qualified=False, hardware_qualified=False, rf_reference_qualified=False, power_unit_qualified=False, accuracy_qualified=False)
    note = ("Actual received SSB-window power per branch in the fixed-Es/N0 normalized plane. It is deliberately not labeled dBm; it is not a full-carrier/SMTC RSSI report."
            if normalized else "Actual 20-PRB/four-symbol SSB received power, including observed noise/interference, per receive branch. Not full carrier/SMTC RSSI or a UE carrier-RSSI report.")
    if internal:
        note = "Original internal physical receive-element SSB-window power before RX front end; simulated dBm operands, not an antenna-connector reference or standardized/hardware qualification. Four received symbols, 20 PRBs per branch."
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
                        _operand_present(m, row, "AllocationCarrierRSSIPerReceiveAntenna_dBm")):
                    raise ValueError("Normalized carrier power must not claim absolute watts/dBm.")
                rssi_field, power_field = "RSSIPerAntenna_dB_re_UnitOccupiedRE_Es", "SymbolPowerPerAntenna_UnitOccupiedRE_Es"
                mirror_field = "AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"
            else:
                if ("RSSIPerAntenna_dB_re_UnitOccupiedRE_Es" in e or "SymbolPowerPerAntenna_UnitOccupiedRE_Es" in e or
                        _operand_present(m, row, "AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es")):
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
                key = _point_key(identity) + (grant, first, stop, branch)
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
                series[f"{identity['direction']} U{identity['ue_index']} Rx{branch+1} {_point_label(identity)}"].append([identity["slot"], value])
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
        if name == TRS_FREQUENCY_CHART:
            return _trs_frequency_timeline(m, name, existing, fetch, run_id)
        if name == TRS_NMSE_CHART:
            return _trs_nmse_timeline(m, name, existing, fetch, run_id)
        if name == "measured_sinr_vs_slot":
            return _data_sinr_timeline(m, name, existing, fetch, run_id)
        if name in CONTROL_EVM:
            return _control_evm(m, name, existing, fetch, run_id)
        if name == "clipping event histogram":
            return _converter_clipping(m, name, existing, fetch, run_id)
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
