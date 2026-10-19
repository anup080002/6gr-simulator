"""Audit requested output coverage, never certify physics from artifact presence.

The output is an audit table, not primary measurement data. Existing files are
read only; no missing measurement is filled, inferred, plotted or marked zero.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import hashlib
import os
from pathlib import Path, PureWindowsPath


def _io_path(path: Path) -> Path:
    """Read real Windows archives even when their names exceed MAX_PATH."""
    absolute = str(path.resolve())
    if os.name != "nt" or absolute.startswith("\\\\?\\"):
        return Path(absolute)
    return Path("\\\\?\\UNC\\" + absolute[2:] if absolute.startswith("\\\\") else "\\\\?\\" + absolute)


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with _io_path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def audit_channel_resources(run: Path) -> list[dict]:
    """Recompute the executed DL/UL channel score from complex CSV samples.

    Hash, observation and receiver-plane checks precede numerical comparison.
    This checks archived evidence, not estimator accuracy or NR qualification.
    It never writes back into the run or supplies the reference to a receiver.
    """
    csv.field_size_limit(64 * 1024 * 1024)
    output = []
    for name in ("dl_pdsch_trials.csv", "ul_pusch_trials.csv"):
        primary = run / "air_interface" / "csv" / name
        if not _io_path(primary).is_file():
            continue
        primary_hash = _file_sha256(primary)
        with _io_path(primary).open(encoding="utf-8-sig", newline="") as stream:
            for index, trial in enumerate(csv.DictReader(stream), 1):
                relative = str(trial.get("ChannelEstimateResourcesCSV") or "").replace("\\", "/")
                result = dict(SourceCSV=primary.relative_to(run).as_posix(),
                              SourceSHA256=primary_hash, DataRow=index, Slot=trial.get("Slot", ""),
                              ResourceCSV=relative, ResourceSHA256="", ComparedComplexValues=0,
                              ReportedNMSE_dB=trial.get("NMSE_dB", ""), RecomputedNMSE_dB=None,
                              CheckStatus="NOT_EVALUATED_no_resource_binding", Reasons="",
                              Scope="archived_complex_sample_reconciliation_not_statistical_or_standards_qualification")
                output.append(result)
                if not relative:
                    continue
                target = run / relative
                if (Path(relative).is_absolute() or PureWindowsPath(relative).is_absolute()
                        or not target.resolve().is_relative_to(run.resolve())):
                    result.update(CheckStatus="FAIL_resource_path", Reasons="resource_outside_selected_run")
                    continue
                if not _io_path(target).is_file():
                    result.update(CheckStatus="FAIL_missing_resource", Reasons="bound_channel_resource_missing")
                    continue
                result["ResourceSHA256"] = _file_sha256(target)
                issues = set()
                if result["ResourceSHA256"] != trial.get("ChannelEstimateResourcesCSVSHA256"):
                    issues.add("resource_sha256_mismatch_or_missing")
                error_energy = reference_energy = 0.0
                count = 0
                with _io_path(target).open(encoding="utf-8-sig", newline="") as resource_stream:
                    reader = csv.DictReader(resource_stream)
                    if len(set(reader.fieldnames or [])) != len(reader.fieldnames or []):
                        issues.add("duplicate_resource_columns")
                    for count, row in enumerate(reader, 1):
                        if None in row or any(value is None for value in row.values()):
                            issues.add("malformed_resource_row")
                            continue
                        values = [_finite(row.get(key)) for key in (
                            "HReal", "HImag", "ReferenceHReal", "ReferenceHImag",
                            "ChannelErrorEnergy", "ReferenceChannelEnergy")]
                        if any(value is None for value in values):
                            issues.add("missing_or_nonfinite_complex_samples_or_energies")
                            continue
                        hr, hi, rr, ri, stored_error, stored_reference = values
                        error = (hr - rr) ** 2 + (hi - ri) ** 2
                        reference = rr ** 2 + ri ** 2
                        if not math.isclose(error, stored_error, rel_tol=1e-10, abs_tol=1e-14):
                            issues.add("resource_error_energy_mismatch")
                        if not math.isclose(reference, stored_reference, rel_tol=1e-10, abs_tol=1e-14):
                            issues.add("resource_reference_energy_mismatch")
                        error_energy += error
                        reference_energy += reference
                        for field in ("Slot", "UEIndex", "ConfiguredSNR_dB"):
                            if _finite(row.get(field)) is None or _finite(row.get(field)) != _finite(trial.get(field)):
                                issues.add("resource_trial_identity_mismatch:" + field)
                        if not trial.get("ChannelObservationID") or row.get("ChannelObservationID") != trial.get("ChannelObservationID"):
                            issues.add("resource_observation_mismatch")
                        if not trial.get("ChannelEstimateReferencePlane") or row.get("ChannelReferencePlane") != trial.get("ChannelEstimateReferencePlane"):
                            issues.add("resource_reference_plane_mismatch")
                        if str(row.get("ReferenceUsedByReceiver")).lower() not in {"0", "false"}:
                            issues.add("reference_not_independent_of_receiver")
                        if str(row.get("GainOrPhaseFitted")).lower() not in {"0", "false"}:
                            issues.add("unexpected_gain_or_phase_fit_in_data_channel_archive")
                result["ComparedComplexValues"] = count
                if count == 0 or reference_energy <= 0:
                    issues.add("empty_or_zero_energy_reference_population")
                else:
                    expected = 10 * math.log10(error_energy / reference_energy) if error_energy > 0 else -math.inf
                    result["RecomputedNMSE_dB"] = expected
                    try:
                        actual = float(trial.get("NMSE_dB", ""))
                    except (TypeError, ValueError):
                        actual = math.nan
                    if not (actual == expected or math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10)):
                        issues.add("trial_nmse_mismatch_or_missing")
                    if _finite(trial.get("ChannelEstimateComparedValues")) != count:
                        issues.add("trial_compared_population_mismatch_or_missing")
                result.update(CheckStatus="FAIL_resource_reconciliation" if issues else "PASS_resource_reconciliation_only",
                              Reasons="|".join(sorted(issues)))
    return output


def audit_trial_values(run: Path, *, arithmetic: bool = False) -> list[dict]:
    """Inventory every primary trial field or reconcile retained operands.

    This does not declare applicability from a missing cell or qualify PHY
    correctness from consistent arithmetic. Source CSVs remain read-only.
    """
    csv.field_size_limit(64 * 1024 * 1024)
    output = []
    # Enumerate using the same long-path convention as resource audits, but
    # retain the ordinary logical path in provenance fields.
    folder = run / "air_interface" / "csv"
    paths = sorted(folder / path.name for path in _io_path(folder).glob("*_trials.csv"))
    for path in paths:
        digest = hashlib.sha256()
        with _io_path(path).open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        identity = dict(SourceCSV=path.relative_to(run).as_posix(), SourceSHA256=digest.hexdigest())
        with _io_path(path).open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            fields = reader.fieldnames or []
            if len(set(fields)) != len(fields):
                raise ValueError(f"Duplicate measurement column in {path}")
            counts = {field: dict(Empty=0, Placeholder=0, Finite=0, Examples=[]) for field in fields}
            count = 0
            for count, row in enumerate(reader, 1):
                if None in row or any(value is None for value in row.values()):
                    raise ValueError(f"Malformed CSV row {count} in {path}")
                if arithmetic:
                    output.extend(_audit_trial_arithmetic(identity, count, row))
                    continue
                for field, raw in row.items():
                    value = raw.strip()
                    stat = counts[field]
                    if value.lower() in {"", "nan", "<missing>", "null"}:
                        stat["Empty"] += 1
                    elif value.startswith(("not_recorded_by_active_", "not_emitted_by_active_",
                                           "not_applicable_for_active_", "field_not_emitted_by_active_")):
                        stat["Placeholder"] += 1
                    if _finite(value) is not None:
                        stat["Finite"] += 1
                    if value and value not in stat["Examples"] and len(stat["Examples"]) < 3:
                        stat["Examples"].append(value[:500])
            if not arithmetic:
                for field, stat in counts.items():
                    absent = stat["Empty"] + stat["Placeholder"]
                    status = "no_trial_rows" if count == 0 else (
                        "all_values_absent_or_placeholder" if absent == count else (
                            "some_values_absent_or_placeholder" if absent else "values_present_not_qualified"))
                    output.append({**identity, "Field": field, "TrialRows": count,
                                   "EmptyValues": stat["Empty"], "PlaceholderValues": stat["Placeholder"],
                                   "FiniteNumericValues": stat["Finite"], "InventoryStatus": status,
                                   "ExamplesJSON": json.dumps(stat["Examples"]),
                                   "Applicability": "requires_channel_configuration_and_execution_review"})
    return output


def _finite(value):
    try:
        number = float(value)
        return number if math.isfinite(number) else None
    except (TypeError, ValueError):
        return None


def audit_packet_conservation(run: Path) -> list[dict]:
    """Reconcile retained packet counters without promoting mapped CRCs to bytes.

    This is a read-only audit, not a reconstructed primary delivery table.
    Unique executed grants, not callback/fragment counts, own attempt counts.
    Missing HARQ evidence is not a measured population of zero attempts.
    """
    paths = {
        "packets": "packet_flow/csv/live_application_packet_delivery_ledger.csv",
        "segments": "packet_flow/csv/live_packet_sdu_delivery_ledger.csv",
        "attempts": "harq/csv/runtime_harq_process_timeline.csv",
    }
    tables, hashes = {}, {}
    csv.field_size_limit(64 * 1024 * 1024)
    for role, relative in paths.items():
        path = run / relative
        if not _io_path(path).is_file():
            tables[role] = None
            hashes[role] = ""
            continue
        hashes[role] = _file_sha256(path)
        with _io_path(path).open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            if len(set(reader.fieldnames or [])) != len(reader.fieldnames or []):
                raise ValueError(f"Duplicate packet/attempt columns in {path}")
            tables[role] = list(reader)
        if any(None in row or any(v is None for v in row.values()) for row in tables[role]):
            raise ValueError(f"Malformed packet/attempt rows in {path}")

    def owner(row):
        direction = str(row.get("Direction", "")).upper()
        ue = _finite(row.get("UEIndex"))
        packet, application = (str(row.get(k, "")).strip() for k in ("PacketId", "ApplicationPacketId"))
        if direction not in {"DL", "UL"} or ue is None or ue < 1 or ue != int(ue) or not packet or not application:
            return None
        return direction, ue, packet, application

    def bit_count(value):
        value = _finite(value)
        return value if value is not None and value >= 0 and value == int(value) else None

    packets = tables["packets"] or []
    segment_rows = tables["segments"]
    attempts = tables["attempts"]
    keys = [owner(row) for row in packets]
    if any(key is None for key in keys) or len(set(keys)) != len(keys):
        raise ValueError("Missing or duplicate application owner identity; do not join by mutable RNTI.")
    segments = {}
    for row in segment_rows or []:
        key = owner(row)
        if key is None or key not in keys:
            raise ValueError("SDU has missing/unmatched stable application ownership.")
        segments.setdefault(key, []).append(row)
    output = []
    for index, (packet, key) in enumerate(zip(packets, keys), 1):
        owned = segments.get(key, [])
        base = dict(SourceCSV=paths["packets"], SourceSHA256=hashes["packets"],
                    SDUSourceSHA256=hashes["segments"], HARQSourceSHA256=hashes["attempts"],
                    DataRow=index, Direction=key[0], UEIndex=key[1], PacketId=key[2], ApplicationPacketId=key[3],
                    Scope="retained_packet_identity_and_counter_audit_not_byte_reassembly_or_phy_qualification")

        def emit(metric, actual, expected, reason=""):
            status = "NOT_EVALUATED_missing_or_ambiguous_evidence"
            if actual is not None and expected is not None:
                status = "PASS_counter_reconciliation_only" if actual == expected else "FAIL_counter_reconciliation"
            output.append({**base, "Metric": metric, "Actual": actual, "Recomputed": expected,
                           "CheckStatus": status, "Reasons": reason})

        offered, scheduled, remaining = (bit_count(packet.get(k)) for k in ("OfferedBits", "ScheduledBits", "RemainingBits"))
        expected = scheduled + remaining if scheduled is not None and remaining is not None else None
        emit("OfferedBits_vs_scheduled_plus_unscheduled", offered, expected,
             "RemainingBits_is_unscheduled_not_total_undelivered")
        segment_ids = [bit_count(row.get("SegmentIndex")) for row in owned]
        payloads = [bit_count(row.get("PayloadBits")) for row in owned]
        complete = (segment_rows is not None and all(v is not None and v > 0 for v in segment_ids + payloads)
                    and len(set(segment_ids)) == len(segment_ids))
        emit("ScheduledBits_vs_unique_SDU_payload", scheduled, sum(payloads) if complete else None,
             "" if complete else "missing_SDU_table_or_invalid_duplicate_segment_identity")
        tb_ids = {str(row.get("TransportBlockId", "")).strip() for row in owned}
        selected = [row for row in (attempts or []) if str(row.get("Direction", "")).upper() == key[0]
                    and _finite(row.get("UEIndex")) == key[1] and row.get("TBId") in tb_ids]
        attempt_ids = [(row.get("TBId"), str(row.get("PHYGrantContextId", "")).strip()) for row in selected]
        identified = (attempts is not None and segment_rows is not None and "" not in tb_ids
                      and all(grant for _, grant in attempt_ids) and len(set(attempt_ids)) == len(attempt_ids))
        emit("HARQAttemptCount_vs_unique_executed_grants", bit_count(packet.get("HARQAttemptCount")),
             len(attempt_ids) if identified else None,
             "" if identified else "missing_attempt_evidence_or_missing_duplicate_attempt_identity")
        # A metadata-only run has no application-byte delivery authority.
        # Do NOT set expected application delivery to the sum of good TBs.
        modes = {str(row.get("DeliveryEvidenceMode", "")) for row in owned}
        if owned and modes == {"CRC_CONFIRMED_PACKET_MAPPING"}:
            emit("ApplicationDeliveredBits_metadata_only_boundary", bit_count(packet.get("DeliveredBits")), 0,
                 "CRC_mapped_payload_is_not_reassembled_application_delivery")
        if packet.get("BitConservationSchema") == "packet_bit_ranges/v1":
            partitions = ("UnscheduledBits", "ReservedInFlightBits", "CRCConfirmedMappedBits",
                          "BitVerifiedPendingReassemblyBits", "CompletedApplicationBits",
                          "HARQReleasedUndeliveredBits", "UnresolvedReservedBits")
            values = [bit_count(packet.get(name)) for name in partitions]
            total = sum(values) if all(value is not None for value in values) else None
            emit("OfferedBits_vs_disjoint_bit_states", offered, total,
                 "HARQ_release_is_not_application_drop;unresolved_is_not_a_passed_receiver_outcome")
            emit("UnscheduledBits_vs_remaining_alias", values[0], remaining)
            emit("CompletedApplicationBits_vs_delivered", values[4], bit_count(packet.get("DeliveredBits")))
            ordered = sorted(owned, key=lambda row: bit_count(row.get("SegmentIndex")) or 0)
            cursor, ranges_known, ranges_valid = 0, complete, complete
            for number, row in enumerate(ordered, 1):
                start = bit_count(row.get("ApplicationRangeStartBit"))
                end = bit_count(row.get("ApplicationRangeEndBitExclusive"))
                length = bit_count(row.get("PayloadBits"))
                known = all(value is not None for value in (start, end, length))
                ranges_known = ranges_known and known
                ranges_valid = (ranges_valid and known and start == cursor and end - start == length
                                and bit_count(row.get("SegmentIndex")) == number)
                if known:
                    cursor = end
            emit("Application_ranges_disjoint_scheduled_prefix", 1,
                 int(ranges_valid and cursor == scheduled) if ranges_known else None)
            states_known = (ranges_known and all(row.get("PacketBitState") in partitions[1:] for row in owned))
            for name in partitions[1:]:
                expected = sum(bit_count(row["PayloadBits"]) for row in owned if row["PacketBitState"] == name) if states_known else None
                emit(f"{name}_vs_owned_segment_ranges", bit_count(packet.get(name)), expected)
            emit("BitConservationErrorBits", _finite(packet.get("BitConservationErrorBits")),
                 offered - total if offered is not None and total is not None else None)
    return output


def _audit_trial_arithmetic(identity: dict, index: int, row: dict) -> list[dict]:
    rules = [("EVM_rms", "EVMErrorEnergy", "EVMReferenceEnergy", "sqrt_ratio"),
             ("NMSE_dB", "ChannelNMSEErrorEnergy", "ChannelNMSEReferenceEnergy", "db_ratio")]
    for converter in ("ADC", "DAC"):
        rules.append((converter + "ClippingRatio", converter + "ClippedSampleCount",
                      converter + "ClippingSampleCount", "ratio"))
        rules.append((converter + "ErrorMeanSquare", converter + "ErrorEnergy",
                      converter + "ErrorSampleCount", "ratio"))
    checks = []
    for metric, numerator, denominator, operation in rules:
        if not any(name in row for name in (metric, numerator, denominator)):
            continue
        actual, a, b = (_finite(row.get(name)) for name in (metric, numerator, denominator))
        expected = None
        if a is not None and a >= 0 and b is not None and b > 0:
            ratio = a / b
            if operation == "ratio":
                expected = ratio
            elif operation == "sqrt_ratio":
                expected = math.sqrt(ratio)
            elif ratio > 0:
                expected = 10 * math.log10(ratio)
        result = "NOT_EVALUATED_missing_or_nonfinite_operands"
        if actual is not None and expected is not None:
            result = "PASS_arithmetic_only" if math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-12) else "FAIL_arithmetic"
        checks.append({**identity, "DataRow": index, "Slot": row.get("Slot", ""),
                       "Metric": metric, "Actual": actual, "Recomputed": expected,
                       "Operands": f"{numerator}|{denominator}", "CheckStatus": result,
                       "Scope": "same_row_operand_reconciliation_not_statistical_or_standards_qualification"})
    # Only reconcile a declared transform/branch. Receiver-estimated grid
    # noise is not equal to injected AWGN after fading and RF impairments.
    extra = [
        ("ReplayGridNoiseVariance", ("ReplaySampleNoiseVariance", "SampleToGridNoiseVarianceGain"), "product"),
        ("ReferenceAWGNGridNoiseVariance", ("ReferenceAWGNSampleNoiseVariance", "SampleToGridNoiseVarianceGain"), "product"),
        ("MeasurementRSRQ_dB", ("MeasurementNumRB",
          "MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es",
          "MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es"), "rsrq"),
    ]
    for metric, operands, operation in extra:
        if not all(name in row for name in (metric, *operands)):
            continue
        actual = _finite(row[metric])
        values = [_finite(row[name]) for name in operands]
        expected = None
        if all(value is not None for value in values) and values[0] > 0:
            if operation == "product" and values[1] > 0:
                expected = values[0] * values[1]
            elif operation == "rsrq":
                # RSRQ must use RSRP and RSSI from the SAME selected branch,
                # not an independently maximized RSRP from another antenna.
                expected = 10 * math.log10(values[0]) + values[1] - values[2]
        status = "NOT_EVALUATED_missing_or_nonfinite_operands"
        if actual is not None and expected is not None:
            status = "PASS_arithmetic_only" if math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-12) else "FAIL_arithmetic"
        checks.append({**identity, "DataRow": index, "Slot": row.get("Slot", ""),
                       "Metric": metric, "Actual": actual, "Recomputed": expected,
                       "Operands": "|".join(operands), "CheckStatus": status,
                       "Scope": "same_row_operand_reconciliation_not_statistical_or_standards_qualification"})
    checks.extend(_audit_csi_synchronization(identity, index, row))
    checks.extend(_audit_pucch_timing(identity, index, row))
    return checks


def _audit_pucch_timing(identity: dict, index: int, row: dict) -> list[dict]:
    """Audit PUCCH's executed timing contract, not CSI's unrelated CFO schema."""
    key = "ReceiverTimingEvidenceJSON"
    if key not in row:
        return []
    failures, missing = [], []
    raw = str(row.get(key, "")).strip()
    evidence = {}
    if not raw:
        missing.append(key)
    else:
        try:
            evidence = json.loads(raw)
            if not isinstance(evidence, dict):
                raise ValueError("Timing must be an object")
        except (ValueError, TypeError):
            failures.append("malformed_timing_json")
            evidence = {}
    if evidence:
        aliases = {"EstimatedTimingOffsetSamples": "TimingOffsetSamples",
                   "AppliedTimingCorrectionSamples": "AppliedTimingCorrectionSamples",
                   "ReceiverInputSampleCount": "InputSampleCount",
                   "ReceiverDemodulatedSampleCount": "DemodulatedSampleCount"}
        for column, field in aliases.items():
            actual, expected = _finite(row.get(column)), _finite(evidence.get(field))
            if actual is None or expected is None:
                missing.append(column)
            elif actual != expected:
                failures.append(column + "_mismatch")
        source = evidence.get("TimingSource")
        if not isinstance(source, str) or not source or not row.get("TimingEstimateSource"):
            missing.append("TimingSource")
        elif source != row["TimingEstimateSource"]:
            failures.append("TimingSource_mismatch")
        for column, field in (("ReceiverTimingOracleUsed", "OracleTimingUsed"),
                              ("ReceiverZeroPaddingUsed", "ReceiverZeroPaddingUsed")):
            actual = {"0": False, "false": False, "1": True, "true": True}.get(
                str(row.get(column, "")).strip().lower())
            expected = evidence.get(field)
            if actual is None or not isinstance(expected, bool):
                missing.append(column)
            elif actual != expected or expected:
                failures.append(column + "_invalid_or_mismatched")
        start, end, offset, count, size = [_finite(value) for value in (
            row.get("ObservationStartSample"), row.get("ObservationEndSampleExclusive"),
            evidence.get("AppliedTimingCorrectionSamples"), evidence.get("DemodulatedSampleCount"),
            evidence.get("InputSampleCount"))]
        if any(value is None for value in (start, end, offset, count, size)):
            missing.append("capture_bounds_or_demodulated_extent")
        elif (any(value != int(value) for value in (start, end, offset, count, size)) or
              start < 0 or end <= start or offset < 0 or count <= 0 or
              offset + count > end - start or size != end - start):
            failures.append("demodulated_extent_outside_actual_capture")
        if source == "completed_same_slot_received_UL_pilot_alignment":
            available = _finite(evidence.get("ReferenceAvailableAtSample"))
            source_slot = _finite(evidence.get("ReferenceSourceAbsoluteSlot0"))
            target_slot = _finite(evidence.get("TargetAbsoluteSlot0"))
            if any(value is None for value in (available, end, source_slot, target_slot)):
                missing.append("received_reference_causality")
            elif available > end or source_slot != target_slot or evidence.get("ReferenceAgeSlots") != 0:
                failures.append("noncausal_or_other_slot_reference")
    status = ("FAIL_source_reconciliation" if failures else
              "NOT_EVALUATED_missing_source_evidence" if missing else "PASS_source_reconciliation_only")
    return [{**identity, "DataRow": index, "Slot": row.get("Slot", ""),
             "Metric": "PUCCHReceiverTimingEvidence", "Actual": json.dumps({"mismatches": failures, "missing": missing}),
             "Recomputed": "own_received_timing_and_capture_bounds", "Operands": key,
             "CheckStatus": status,
             "Scope": "same_execution_timing_metadata_reconciliation_not_CFO_or_receiver_accuracy_qualification"}]


def _audit_csi_synchronization(identity: dict, index: int, row: dict) -> list[dict]:
    """Reconcile each actual receive plane with its own serialized metadata.

    This cannot qualify the estimator: both representations have one producer.
    In particular, never compare pre-RF timing/CFO to the post-RF estimate or
    use injected impairments as an expected receiver value.
    """
    checks = []
    numeric = {
        "TimingOffset_samples": ("Timing", "TimingOffsetSamples"),
        "TimingCorrection_samples": ("Timing", "AppliedTimingCorrectionSamples"),
        "DemodulatedSampleCount": ("Timing", "DemodulatedSampleCount"),
        "EstimatedCFO_Hz": ("Frequency", "EstimatedCFO_Hz"),
        "AppliedCFO_Hz": ("Frequency", "CFOCorrectionApplied_Hz"),
    }
    text = {"TimingSource": ("Timing", "TimingSource"),
            "CFOSource": ("Frequency", "Source"),
            "CFOStatus": ("Frequency", "Status")}

    def flag(value):
        if isinstance(value, bool):
            return value
        return {"0": False, "false": False, "1": True, "true": True}.get(str(value).strip().lower())

    for prefix in ("Receiver", "PhysicalMeasurement"):
        key = prefix + "SynchronizationJSON"
        if prefix == "Receiver" and "ReceiverTimingEvidenceJSON" in row and key not in row:
            continue  # Dedicated PUCCH timing is audited separately; no CSI CFO fields are invented.
        if not any(prefix + field in row for field in (*numeric, "SynchronizationJSON")):
            continue  # Do not invent synchronization fields in older schemas.
        failures, missing = [], []
        raw = str(row.get(key, "")).strip()
        evidence = {}
        if not raw:
            missing.append(key)
        else:
            try:
                evidence = json.loads(raw)
                if (not isinstance(evidence, dict) or
                        any(not isinstance(evidence.get(name), dict) for name in ("Timing", "Frequency"))):
                    raise ValueError("Timing and Frequency must be objects")
            except (ValueError, TypeError):
                failures.append("malformed_synchronization_json")
                evidence = {}
        if evidence:
            for suffix, (section, field) in numeric.items():
                actual = _finite(row.get(prefix + suffix))
                expected = _finite(evidence[section].get(field))
                if actual is None and expected is None:
                    missing.append(suffix)
                elif actual is None or expected is None or not math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-12):
                    failures.append(suffix + "_mismatch")
            for suffix, (section, field) in text.items():
                actual, expected = row.get(prefix + suffix), evidence[section].get(field)
                if not isinstance(actual, str) or not actual or not isinstance(expected, str) or not expected:
                    missing.append(suffix)
                elif actual != expected:
                    failures.append(suffix + "_mismatch")
            for suffix in ("CFOEstimateAvailable", "CFOCorrectionApplied"):
                actual, expected = flag(row.get(prefix + suffix)), flag(evidence["Frequency"].get(suffix))
                if actual is None or expected is None:
                    failures.append(suffix + "_invalid_boolean")
                elif actual != expected:
                    failures.append(suffix + "_mismatch")
            frequency = evidence["Frequency"]
            for availability, value_field in (("CFOEstimateAvailable", "EstimatedCFO_Hz"),
                                               ("CFOCorrectionApplied", "CFOCorrectionApplied_Hz")):
                available = flag(frequency.get(availability))
                measured = _finite(frequency.get(value_field)) is not None
                if available is not None and available != measured:
                    failures.append(availability + "_contradicts_numeric_evidence")
            if flag(frequency.get("CFOCorrectionApplied")) is True:
                estimate = _finite(frequency.get("EstimatedCFO_Hz"))
                applied = _finite(frequency.get("CFOCorrectionApplied_Hz"))
                if estimate is None or applied is None or not math.isclose(estimate, applied, rel_tol=1e-10, abs_tol=1e-12):
                    failures.append("applied_cfo_not_own_received_estimate")
            for name in ("OracleTimingUsed", "ReceiverZeroPaddingUsed"):
                value = flag(evidence["Timing"].get(name))
                if value is None:
                    missing.append(name)
                elif value:
                    failures.append(name + "_violates_received_sample_contract")
            if not str(row.get(prefix + "SynchronizationSource", "")).strip():
                missing.append("SynchronizationSource")
            if row.get(prefix + "SynchronizationSampleDomain") != "relative_to_observation_capture_start_zero_based":
                failures.append("incorrect_or_missing_sample_domain")
            start, end = (_finite(row.get(name)) for name in ("ObservationStartSample", "ObservationEndSampleExclusive"))
            offset, count = (_finite(evidence["Timing"].get(name)) for name in
                             ("AppliedTimingCorrectionSamples", "DemodulatedSampleCount"))
            if any(value is None for value in (start, end, offset, count)):
                missing.append("capture_bounds_or_demodulated_extent")
            elif (any(value != int(value) for value in (start, end, offset, count)) or
                  start < 0 or end <= start or offset < 0 or count <= 0 or offset + count > end - start):
                failures.append("demodulated_extent_outside_actual_capture")
            if "InputSampleCount" in evidence["Timing"]:
                size = _finite(evidence["Timing"]["InputSampleCount"])
                if size is None or start is None or end is None:
                    missing.append("InputSampleCount")
                elif size != end - start:
                    failures.append("InputSampleCount_capture_mismatch")
        status = ("FAIL_source_reconciliation" if failures else
                  "NOT_EVALUATED_missing_source_evidence" if missing else "PASS_source_reconciliation_only")
        checks.append({**identity, "DataRow": index, "Slot": row.get("Slot", ""),
                       "Metric": prefix + "SynchronizationEvidence",
                       "Actual": json.dumps({"mismatches": failures, "missing": missing}),
                       "Recomputed": "own_plane_metadata_and_capture_bounds",
                       "Operands": key, "CheckStatus": status,
                       "Scope": "same_execution_synchronization_metadata_reconciliation_not_receiver_accuracy_or_standards_qualification"})
    return checks


def audit(catalog: Path, mapping: Path, run: Path) -> list[dict]:
    if not run.is_dir():
        raise ValueError(f"Run folder does not exist: {run}")
    with catalog.open(encoding="utf-8-sig", newline="") as stream:
        records = list(csv.DictReader(stream, delimiter="\t"))
    rules = {}
    for group in json.loads(mapping.read_text(encoding="utf-8-sig"))["groups"]:
        for metric in group["metrics"]:
            if metric in rules:
                raise ValueError(f"Duplicate mapping for {metric}")
            rules[metric] = group
    files = {}
    for path in run.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".csv", ".png"}:
            files.setdefault(path.name, []).append(path)
    cache = {}

    def describe(path):
        if path not in cache:
            if not path.is_file():
                cache[path] = {"rows": 0, "columns": [], "state": "missing"}
            else:
                try:
                    with path.open(encoding="utf-8-sig", newline="") as stream:
                        reader = csv.DictReader(stream)
                        columns = reader.fieldnames or []
                        count = sum(1 for _ in reader)
                    cache[path] = {"rows": count, "columns": columns,
                                   "state": "nonempty" if count else "empty"}
                except (UnicodeError, csv.Error) as exc:
                    cache[path] = {"rows": 0, "columns": [], "state": f"unreadable: {exc}"}
        return {"path": path.relative_to(run).as_posix(), **cache[path]}

    rows, seen = [], set()
    for record in records:
        record_id = record["Record ID"]
        if not record_id or record_id in seen:
            raise ValueError(f"Missing/duplicate record identity: {record_id}")
        seen.add(record_id)
        group = rules.get(record["Standard abbreviation or field name"], {})
        candidates = [describe(run / name) for name in group.get("sources", [])]
        named = [describe(p) for p in files.get(record["Supporting CSV file name"], [])]
        pngs = files.get(record["Expected PNG file name"], [])
        required = [f.strip() for f in record["Proposed raw CSV fields - not 3GPP field names"].split(";") if f.strip()]
        for table in named:
            table["missing_proposed_fields"] = sorted(set(required) - set(table["columns"]))
        has_candidate = any(t["rows"] > 0 for t in candidates)
        status = "named_export_present_unverified" if any(t["rows"] > 0 for t in named) else (
            "candidate_evidence_requires_mapping" if has_candidate else "requested_evidence_not_established")
        rows.append({"RecordID": record_id, "Agenda": record["Agenda item"],
            "Measurement": record["Measurement or parameter name in English"],
            "StandardStatusAsSupplied": record["3GPP status and applicability"],
            "DefinitionAsSupplied": record["Definition or calculation"],
            "CoverageStatus": status, "ScientificValidation": "not_verified_by_presence_audit",
            "Applicability": "requires_scenario_and_agenda_review",
            "RequestedCSV": record["Supporting CSV file name"],
            "RequestedPNG": record["Expected PNG file name"],
            "NamedCSVDetailsJSON": json.dumps(named),
            "NamedPNGPathsJSON": json.dumps([p.relative_to(run).as_posix() for p in pngs]),
            "CandidateEvidenceJSON": json.dumps(candidates),
            "ProducerFiles": "|".join(group.get("producers", [])),
            "RequiredCheck": group.get("check", "Bind common metadata to actual run/config/seeds and statistical populations; filename presence is insufficient."),
            "RunFolder": str(run.resolve())})
    return rows


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("output", type=Path, help="New audit CSV outside retained run evidence")
    parser.add_argument("--catalog", type=Path, default=root / "simulator/configs/validation/lls_evaluation_measurements.tsv")
    parser.add_argument("--mapping", type=Path, default=root / "simulator/configs/validation/lls_evaluation_evidence_map.json")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--trial-fields", action="store_true", help="Inventory every primary trial column, including empty tables")
    mode.add_argument("--trial-arithmetic", action="store_true", help="Reconcile retained EVM/NMSE/converter/noise/RSRQ and per-plane synchronization evidence without filling missing values")
    mode.add_argument("--channel-resources", action="store_true", help="Verify DL/UL channel archive hashes/identities and recompute NMSE from complex samples")
    mode.add_argument("--packet-conservation", action="store_true", help="Audit stable packet/SDU ownership, unique transport attempts and metadata-only delivery boundaries")
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(args.run.resolve()):
        parser.error("Write the audit outside the retained run; do not modify its evidence.")
    rows = audit_packet_conservation(args.run) if args.packet_conservation else audit_channel_resources(args.run) if args.channel_resources else (
        audit_trial_values(args.run, arithmetic=args.trial_arithmetic) if (
            args.trial_fields or args.trial_arithmetic) else audit(args.catalog, args.mapping, args.run))
    if not rows:
        parser.error("No audit rows; check the run folder and requested evidence scope.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    scope = ("retained packet counters and identities only" if args.packet_conservation else
             "archived complex channel sample reconciliation only" if args.channel_resources else
             "retained operand arithmetic only" if args.trial_arithmetic else
             "trial field inventory only" if args.trial_fields else "coverage audit only")
    print(json.dumps({"records": len(rows), "output": str(args.output),
        "scientifically_certified_records": 0, "scope": scope}))


if __name__ == "__main__":
    main()
