"""Read-only checks of observed UL evidence, not PHY qualification.

Accepts complete CSV bytes atomically published by the running simulator.
Receipts record those bytes; observations from different files need not be
from the same live checkpoint. No missing waveform/measurement is invented.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path


def number(row: dict, name: str) -> float | None:
    try:
        value = float(row.get(name, ""))
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def flag(row: dict, name: str) -> bool | None:
    value = str(row.get(name, "")).strip().lower()
    return {"1": True, "true": True, "0": False, "false": False}.get(value)


def audit_rows(channel: str, rows: list[dict]) -> list[dict]:
    checks = []

    def check(index, row, name, passed, detail):
        checks.append(dict(Channel=channel, CSVRow=index + 2,
                           Slot=row.get("Slot", ""), Check=name,
                           Passed=bool(passed), Detail=detail))

    for index, row in enumerate(rows):
        if (channel == "PUSCH" and
                row.get("LLRNoiseVarianceSource") == "configured_pre_equalization_noise_variance"):
            # This branch feeds channel-estimator noise to nrPUSCHDecode,
            # then applies equalizer CSI once. The scalar itself has not
            # become a post-equalization unit-constellation variance.
            check(index, row, "pusch_pre_equalization_llr_variance_domain",
                  row.get("LLRNoiseVarianceDomain") ==
                  "pre_equalization_channel_estimator_noise_variance_for_nrPUSCHDecode",
                  "Retain the executed decoder-noise resolver's domain, not a hardcoded post-EQ/demapper label.")
            llr, pre = number(row, "LLRNoiseVariance"), number(row, "PreEqualizationNoiseVariance")
            check(index, row, "pusch_pre_equalization_llr_variance_value",
                  llr is not None and pre is not None and pre > 0 and
                  math.isclose(llr, pre, rel_tol=1e-12, abs_tol=0),
                  "Pre-equalization decoding must retain its actual estimator variance; no post-hoc value conversion.")
        if channel == "SRS" and row.get("PredictedPUSCHPostEqSINRValueStatus") == "PASS":
            # Metadata closure of the measured-power prediction contract,
            # not a replacement for independent H/codebook/MMSE tests.
            signal = number(row, "PredictedPUSCHReferenceSignalPower")
            disturbance = number(row, "PredictedPUSCHDisturbancePower")
            anchor = number(row, "PredictedPUSCHPostEqSINRAnchor_dB")
            positive_power = (signal is not None and signal > 0 and
                              disturbance is not None and disturbance > 0)
            provenance = (
                positive_power and
                row.get("PredictedPUSCHPostEqSINRSource") ==
                "receiver_measured_srs_reference_power_selected_ri_tpmi_mmse_layer_prediction" and
                row.get("PredictedPUSCHPostEqSINRValueRole") ==
                "power_plane_calibrated_predicted_pusch_data_channel_scheduling_input" and
                row.get("PredictedPUSCHPostEqSINRAnchorSource") ==
                "measured_ul_srs_pilot_reconstruction_sinr" and
                row.get("PredictedPUSCHPostEqSINRPowerReferencePlane") ==
                "receiver_srs_resource_elements_after_ofdm_demodulation" and
                number(row, "PUSCHToSRSReferenceEnergyRatio") == 1 and
                row.get("PUSCHToSRSReferenceEnergySource") ==
                "normalized_fixed_snr_unit_grid_reference_no_device_power_scaling")
            check(index, row, "srs_prediction_power_provenance", provenance,
                  "Authorized PUSCH prediction requires measured reference power/disturbance and an explicit supported energy conversion.")
            check(index, row, "srs_prediction_no_post_mmse_shift",
                  number(row, "PredictedPUSCHPostEqSINRCalibrationOffset_dB") == 0,
                  "Do not erase native precoder rank power by shifting post-MMSE layer SINRs to a pilot average.")
            # Difference of logs avoids overflow for valid tiny/large powers.
            closure = (positive_power and anchor is not None and math.isclose(
                10 * (math.log10(signal) - math.log10(disturbance)), anchor,
                rel_tol=0, abs_tol=1e-8))
            check(index, row, "srs_prediction_reference_power_closure", closure,
                  "The measured SRS anchor must close from exported signal/disturbance power; it need not equal PUSCH layer SINR.")
            try:
                layers = [float(value) for value in str(row.get(
                    "PredictedPUSCHPostEqSINRPerLayer_dB", "")).split("|")]
            except (ValueError, TypeError):
                layers = []
            rank = number(row, "RankEstimate")
            layers_ok = (bool(layers) and all(math.isfinite(value) for value in layers) and
                         rank is not None and rank > 0 and rank == int(rank) and len(layers) == rank)
            check(index, row, "srs_prediction_layer_count", layers_ok,
                  "Selected rank requires one finite prediction per layer; missing values must not be dropped or repeated.")
            minimum = number(row, "PredictedPUSCHMinimumLayerSINR_dB")
            mean = number(row, "PredictedPUSCHWidebandMeanSINR_dB")
            minimum_ok = mean_ok = False
            if layers_ok:
                # localFormatNumericVector writes %.6g, whereas scalar CSV
                # cells retain full precision. This is serialization error,
                # not a configurable PHY acceptance tolerance. A linear-
                # power mean in dB changes by no more than max input error.
                rounding = max(1e-10, max(0.5001 * 10 ** (math.floor(math.log10(abs(v))) - 5)
                                        if v else 0 for v in layers))
                minimum_ok = minimum is not None and abs(minimum - min(layers)) <= rounding
                peak = max(layers)
                expected_mean = peak + 10 * math.log10(math.fsum(
                    10 ** ((value - peak) / 10) for value in layers) / len(layers))
                mean_ok = mean is not None and abs(mean - expected_mean) <= rounding
            check(index, row, "srs_prediction_minimum_layer_closure", minimum_ok,
                  "Scheduler-facing minimum must be the weakest predicted PUSCH layer, not the SRS pilot average.")
            check(index, row, "srs_prediction_mean_layer_closure", mean_ok,
                  "Wideband layer mean is computed in linear power, allowing only exported-vector rounding.")
        if channel == "SRS" and flag(row, "SRSRuntimeEvidenceUsable") is True:
            provenance = str(row.get("RuntimeEvidenceSource", "")).strip().lower()
            available_source = provenance not in ("", "nan", "unavailable") and not provenance.startswith(
                ("not_emitted_by_active_", "not_recorded_by_active_", "field_not_emitted_by_active_"))
            check(index, row, "usable_srs_runtime_provenance", available_source,
                  "Usable runtime SRS requires its actual producer provenance, not a missing-field token.")
        if channel == "SRS" and row.get("RuntimeTransportMode") == "shared_physical_stream_SRS_received_completion":
            start, end, fs, completion = [number(row, name) for name in (
                "ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz",
                "ObservationCompletionTime_s")]
            clock_ok = all(value is not None for value in (start, end, fs, completion))
            clock_ok = clock_ok and fs > 0 and 0 <= start < end and start == int(start) and end == int(end)
            check(index, row, "shared_srs_observation_clock", clock_ok and
                  math.isclose(completion, end / fs, rel_tol=0, abs_tol=1e-12),
                  "Actual completed capture must retain integral sample bounds and its exact completion time.")
            if flag(row, "RuntimeStateUpdated") is True:
                delivery = number(row, "ObservationDeliveryTime_s")
                check(index, row, "shared_srs_no_future_delivery", clock_ok and delivery is not None and
                      completion <= delivery + 1e-12,
                      "Scheduler consumption cannot precede completed actual SRS observation.")
        expected = str(row.get("UCIExpectedBitVector", "")).strip()
        decoded = str(row.get("UCIDecodedBitVector", "")).strip()
        errors = str(row.get("UCIBitErrorVector", "")).strip()
        # Recognize only exact exporter tokens; malformed bit strings must
        # still fail. An unavailable token never satisfies a success claim.
        absent = {"nan", "not_applicable_for_active_pucch_runtime"}
        expected = "" if expected.lower() in absent else expected
        decoded = "" if decoded.lower() in absent else decoded
        errors = "" if errors.lower() in absent else errors
        receiver_only = (channel == "PUCCH" and flag(row, "ReceiverOnlyAssignment") is True
                         and flag(row, "PUCCHTransmissionPrepared") is False)
        widths = [number(row, name) for name in (
            "ReceiverExpectedHARQBitCount", "ReceiverExpectedSRBitCount",
            "ReceiverExpectedCSIPart1BitCount", "ReceiverExpectedCSIPart2BitCount")]
        widths_valid = all(v is not None and v >= 0 and v == int(v) for v in widths)
        context_claimed = ("ReceiverExpectedBitCount" in row and
                           (receiver_only or str(row["ReceiverExpectedBitCount"]).strip().lower()
                            not in ("", "nan")))
        if channel == "PUCCH" and (context_claimed or
                row.get("ExecutionBackend") == "pucch_shared_gnb_receive_only"):
            check(index, row, "receiver_context_width_closure",
                  widths_valid and number(row, "ReceiverExpectedBitCount") == sum(widths),
                  "Frozen receiver total must equal HARQ + SR + CSI Part 1 + CSI Part 2, even for DTX.")
            digest = str(row.get("ReceiverContextDigest", "")).strip()
            check(index, row, "receiver_context_provenance",
                  row.get("ReceiverExpectedBitCountSource") == "receiver_length_context" and
                  digest.lower() not in ("", "nan", "unavailable"),
                  "Independent receive width requires its context source and retained digest; not TX payload authority.")
        if receiver_only:
            check(index, row, "receiver_only_no_transmission_claim",
                  not expected and not errors and flag(row, "SuccessFlag") is not True,
                  "No UE producer means no transmitted reference bits, bit-error truth, or transmission success.")
        if expected or decoded or errors:
            binary = all(set(bits) <= {"0", "1"} for bits in (expected, decoded, errors))
            check(index, row, "uci_binary_vectors", binary,
                  "Expected/decoded/error evidence must be literal binary strings.")
            for field, bits in (("ExpectedBitCount", expected), ("DecodedBitCount", decoded),
                                ("PUCCHExpectedBitCount", expected), ("PUCCHDecodedBitCount", decoded)):
                # Union-schema NaN/empty cells make no numeric count claim.
                # Completeness is checked below, using independent layout
                # widths for a receiver-only row. Malformed counts still fail.
                if field in row and str(row[field]).strip().lower() not in ("", "nan"):
                    check(index, row, field + "_closure", number(row, field) == len(bits),
                          f"Published count={row[field]}; vector length={len(bits)}.")
            if expected and decoded and binary:
                match = expected == decoded
                if "UCIContentMatch" in row:
                    check(index, row, "uci_content_match_closure", flag(row, "UCIContentMatch") == match,
                          "Content equality is checked independently of CRC applicability.")
                if errors:
                    xor = "".join(str(int(a) ^ int(b)) for a, b in zip(expected, decoded))
                    check(index, row, "uci_error_vector_closure",
                          len(expected) == len(decoded) and errors == xor,
                          "Published error vector must match bit-by-bit XOR, including leading zeroes.")
            if channel == "PUCCH" and flag(row, "PUCCHDecodeOk") is True:
                complete = bool(expected) and len(expected) == len(decoded)
                if receiver_only:
                    complete = widths_valid and bool(decoded) and len(decoded) == sum(widths)
                check(index, row, "successful_pucch_has_complete_payload",
                      complete,
                      "Require complete decoded bits; receiver-only width comes from every independent layout field, not invented TX bits.")
        elif channel == "PUCCH" and flag(row, "PUCCHDecodeOk") is True:
            check(index, row, "successful_pucch_has_complete_payload", False,
                  "Successful PUCCH has no retained UCI bit vectors.")

        if channel == "PUCCH" and flag(row, "PUCCHDecodeOk") is True:
            if receiver_only or "ReceiverUsable" in row or "DTXFlag" in row:
                check(index, row, "successful_pucch_receiver_flags",
                      flag(row, "ReceiverUsable") is True and flag(row, "DTXFlag") is False,
                      "Decode success cannot contradict receiver usability or DTX; preserve raw receiver evidence separately from export acceptance.")

        if "UCICRCBitCount" in row and number(row, "UCICRCBitCount") is not None:
            crc_bits = number(row, "UCICRCBitCount")
            check(index, row, "uci_crc_applicability", flag(row, "UCICRCApplicable") == (crc_bits > 0),
                  f"Published UCI CRC length={crc_bits}; applicability must agree.")
        # PUSCH TB CRC is independent of UCI CRC and must not be conflated.
        if channel == "PUCCH" and flag(row, "CRCApplicable") is False:
            check(index, row, "nonapplicable_pucch_crc_not_passed", number(row, "CRCPass") is None,
                  "Nonapplicable CRC must remain unavailable, not a numeric pass/fail.")
        # Union-schema exports contain empty generic fields alongside the
        # populated channel-specific source. Empty/NaN is not authoritative.
        source = next((str(row.get(name, "")).strip() for name in
                       ("TimingEstimateSource", "SRSReceiveTimingSource")
                       if str(row.get(name, "")).strip().lower() not in ("", "nan")), "")
        correction = number(row, "AppliedTimingCorrectionSamples")
        if correction is None:
            correction = number(row, "AppliedTimingCorrection_samples")
        if source.startswith("received_") and correction is not None and correction != 0:
            check(index, row, "measured_timing_application_flag", flag(row, "TimingEstimateUsed") is True,
                  f"Received-reference timing applied {correction} samples; application flag must agree.")
    return checks


def audit_srs_grant_binding(srs_rows: list[dict], grants: list[dict]) -> list[dict]:
    """Reconcile retained scheduling inputs, not CQI calibration or decoding.

    An ambiguous source is never selected by SINR similarity or row order.
    The live CSV files are not a transactional snapshot; missing sources in
    a live receipt require re-observation, not invented receiver evidence.
    """
    checks = []
    identity_fields = ("UEIndex", "RNTI", "ServingCell", "ConfiguredSNR_dB")
    source_name = "ul_srs_power_plane_calibrated_selected_ri_tpmi_minimum_layer_post_equalization"
    for index, grant in enumerate(grants):
        if grant.get("SchedulerCQISource") != source_name:
            continue

        def check(name, passed, detail):
            checks.append(dict(Channel="PUSCH", CSVRow=index + 2,
                               Slot=grant.get("Slot", ""), Check=name,
                               Passed=bool(passed), Detail=detail))

        source_slot = number(grant, "LinkAdaptationAppliedFeedbackSourceSlot")
        slot = number(grant, "Slot")
        age = number(grant, "LinkAdaptationAppliedFeedbackAgeSlots")
        clock_ok = (all(v is not None and v == int(v) for v in (source_slot, slot, age))
                    and 0 <= source_slot <= slot and age == slot - source_slot)
        check("srs_grant_source_age", clock_ok,
              "Cited SRS slot and reported age must precede or equal the executed PUSCH slot; this is not a sample-clock causality proof.")
        identity = tuple(number(grant, field) for field in identity_fields)
        matches = [row for row in srs_rows
                   if source_slot is not None and all(v is not None for v in identity)
                   and number(row, "Slot") == source_slot
                   and tuple(number(row, field) for field in identity_fields) == identity]
        check("srs_grant_unique_source", len(matches) == 1,
              f"Require exactly one SRS row for cited slot, UE, RNTI, serving cell and sweep SNR; found {len(matches)}.")
        if len(matches) != 1:
            continue
        srs = matches[0]
        predicted = number(srs, "PredictedPUSCHMinimumLayerSINR_dB")
        adjusted = number(grant, "SchedulerAdjustedSINR_dB")
        backoff = number(grant, "SchedulerSINRBackoff_dB")
        prediction_checks = [c for c in audit_rows("SRS", [srs])
                             if c["Check"].startswith("srs_prediction_")]
        trusted = (srs.get("PredictedPUSCHPostEqSINRValueStatus") == "PASS"
                   and bool(prediction_checks) and all(c["Passed"] for c in prediction_checks))
        closure = (trusted and all(v is not None for v in (predicted, adjusted, backoff))
                   and backoff >= 0 and math.isclose(adjusted, predicted - backoff,
                                                   rel_tol=0, abs_tol=1e-8))
        check("srs_grant_prediction_binding", closure,
              "Grant scheduling SINR must equal its trusted SRS weakest-layer prediction minus the explicit scheduling backoff, not pilot SINR or a later PUSCH measurement.")
    return checks


def audit_data_feedback_binding(grants: list[dict], reports: list[dict]) -> list[dict]:
    """Check UL data -> local CSI publication -> cited grant, not CQI calibration.

    This path deliberately excludes DL quantized UCI and SRS predictions.
    Missing/ambiguous identities fail; matching by value or row order is forbidden.
    Slot-level ordering is not proof of sample-level receiver causality.
    """
    checks = []
    identity_fields = ("UEIndex", "RNTI", "ServingCell")
    data_reports = [r for r in reports if r.get("Direction") == "UL"
                    and r.get("SourceSignal") == "PUSCH-DMRS"]

    def matches(left, right):
        identity = tuple(number(left, f) for f in identity_fields)
        return (all(v is not None for v in identity)
                and identity == tuple(number(right, f) for f in identity_fields))

    def equal(left, right):
        return (left is not None and right is not None
                and math.isclose(left, right, rel_tol=0, abs_tol=1e-8))

    def check(channel, index, row, name, passed, detail):
        checks.append(dict(Channel=channel, CSVRow=index + 2,
                           Slot=row.get("Slot", row.get("SourceSlot", "")),
                           Check=name, Passed=bool(passed), Detail=detail))

    for index, report in enumerate(reports):
        if report.get("Direction") != "UL" or report.get("SourceSignal") != "PUSCH-DMRS":
            continue
        source_slot = number(report, "SourceSlot")
        sources = [r for r in grants if source_slot is not None
                   and number(r, "Slot") == source_slot and matches(report, r)]
        check("CSIFeedback", index, report, "data_feedback_unique_receiver_source", len(sources) == 1,
              f"Require one PUSCH source at cited slot/UE/RNTI/cell; found {len(sources)}.")
        if len(sources) != 1:
            continue
        raw = sources[0]
        provenance = " ".join(str(raw.get("PostEqSINR" + suffix, "")).lower()
                              for suffix in ("Source", "ValueRole", "ValueStatus"))
        status = str(raw.get("PostEqSINRValueStatus", "")).lower()
        trusted = (all(str(raw.get("PostEqSINR" + suffix, "")).strip()
                       for suffix in ("Source", "ValueRole", "ValueStatus"))
                   and "post_equalization" in provenance
                   and (status in {"ok", "pass", "measured"} or status.startswith("ok_"))
                   and not any(t in provenance for t in (
                       "proxy", "fallback", "oracle", "configured", "conservative_min",
                       "reference_signal", "receiver_hest", "prediction", "predicted", "unavailable",
                       "estimated", "diagnostic", "sweep", "not_post_equalization", "pilot")))
        binding = (trusted and equal(number(report, "SINR_dB"), number(raw, "PostEqSINR_dB"))
                   and all(report.get("SINR" + suffix) == raw.get("PostEqSINR" + suffix)
                           for suffix in ("Source", "ValueRole", "ValueStatus")))
        check("CSIFeedback", index, report, "data_feedback_receiver_plane_binding", binding,
              "Published scalar and original provenance must equal the cited receiver's data post-equalization evidence, not pilot SINR.")

    for index, grant in enumerate(grants):
        if grant.get("SchedulerCQISource") != "runtime_reported_cqi":
            continue
        source, slot, age = (number(grant, f) for f in (
            "LinkAdaptationAppliedFeedbackSourceSlot", "Slot", "LinkAdaptationAppliedFeedbackAgeSlots"))
        clock = (all(v is not None and v == int(v) for v in (source, slot, age))
                 and 0 <= source < slot and age == slot - source)
        check("PUSCH", index, grant, "data_grant_source_age", clock,
              "Reported source and age must identify a strictly earlier data occasion.")
        selected = [r for r in data_reports if source is not None
                    and number(r, "SourceSlot") == source and matches(grant, r)]
        check("PUSCH", index, grant, "data_grant_unique_feedback_source", len(selected) == 1,
              f"Require one receiver-derived UL report for the cited source identity; found {len(selected)}.")
        if len(selected) != 1:
            continue
        report = selected[0]
        delivered = number(report, "DeliveredSlot")
        check("PUSCH", index, grant, "data_grant_report_delivery_clock",
              clock and delivered is not None and delivered == int(delivered) and source <= delivered <= slot,
              "The cited report must have been delivered by the grant's execution slot; no sample-clock claim.")
        check("PUSCH", index, grant, "data_grant_decision_binding",
              all(equal(number(grant, f), number(report, f)) for f in (
                  "SchedulerAdjustedSINR_dB", "SchedulerSINRBackoff_dB")),
              "Grant must retain the report's frozen adjusted SINR and recorded backoff; do not recompute or erase directional policy.")
    return checks


def audit_received_csi_binding(pucch_rows: list[dict], reports: list[dict]) -> list[dict]:
    """Check delivered CSI ownership/state evidence, never decide detector validity.

    A receiver-only false detection can genuinely update scheduler state. Its
    exported state transition must remain visible without inventing a UE TX.
    Context identity, UE identity and due occasion perform the join, not decoded
    CQI values or row order. Live cross-file snapshots may be incomplete.
    """
    checks = []

    def serving_cell(row):
        # Prepared PUCCH rows export their cell as BaseStationID; independent
        # receiver-only rows use ServingCell. These are existing cell-ID
        # authorities, not permission to infer identity from CQI or ordering.
        serving, base = number(row, "ServingCell"), number(row, "BaseStationID")
        if serving is not None and base is not None and serving != base:
            return None
        return serving if serving is not None else base

    for index, report in enumerate(reports):
        if report.get("CSIUCIChannel") != "PUCCH":
            continue
        digest = str(report.get("ReceiverContextDigest", "")).strip()
        due = number(report, "DueSlot")
        identity = ("UEIndex", "RNTI")
        valid_identity = (digest.lower() not in ("", "nan", "unavailable") and
                          due is not None and due >= 1 and due == int(due) and
                          serving_cell(report) is not None and
                          all(number(report, key) is not None for key in identity))
        matches = [row for row in pucch_rows if valid_identity and
                   row.get("ReceiverContextDigest") == digest and
                   number(row, "Slot") == due and
                   serving_cell(row) == serving_cell(report) and
                   all(number(row, key) == number(report, key) for key in identity)]

        def check(name, passed, detail):
            checks.append(dict(Channel="ReceivedCSI", CSVRow=index + 2,
                               Slot=report.get("DueSlot", ""), Check=name,
                               Passed=bool(passed), Detail=detail))

        check("received_csi_unique_pucch_context", len(matches) == 1,
              "A physical CSI report must join one independent PUCCH receiver context and occasion.")
        if len(matches) != 1:
            continue
        trial = matches[0]
        delivered = report.get("DeliveryStatus") == "delivered_to_runtime_scheduler"
        if delivered:
            check("received_csi_delivery_requires_decode",
                  flag(report, "CSIUCIDecodeOk") is True and
                  flag(trial, "PUCCHDecodeOk") is True and
                  flag(trial, "ReceiverUsable") is True and flag(trial, "DTXFlag") is False,
                  "Delivery must retain an actual usable decode, independently of whether a UE transmitted.")
            check("received_csi_delivery_state_change_visible",
                  all(flag(trial, key) is True for key in
                      ("RuntimeStateUpdated", "ControlStateChanged", "StateChangeApplied")),
                  "Actual CSI delivery must not be exported as no state change, including false detections.")
        # A failed CSI decode does not forbid a HARQ/SR state change on the
        # same occasion; do not equate CSI availability with whole-UCI success.
    return checks


def audit_received_sr_binding(pucch_rows: list[dict], reports: list[dict]) -> list[dict]:
    """Audit SR outcome/export ownership, not detector statistical qualification."""
    checks = []
    identity = ("UEIndex", "RNTI", "ServingCell", "Slot")
    digests = ("ReceiverAssignmentDigest", "ReceiverContextDigest")
    for index, trial in enumerate(pucch_rows):
        if trial.get("UCIType") != "standalone_sr":
            continue
        matches = [row for row in reports if all(number(row, key) == number(trial, key)
                   for key in identity) and all(row.get(key) == trial.get(key) for key in digests)]
        checks.append(dict(Channel="PUCCH", CSVRow=index + 2, Slot=trial.get("Slot", ""),
                           Check="standalone_sr_has_one_received_observation", Passed=len(matches) == 1,
                           Detail="Every standalone SR monitor needs one retained received-SR outcome row."))
    for index, report in enumerate(reports):
        def check(name, passed, detail):
            checks.append(dict(Channel="ReceivedSR", CSVRow=index + 2,
                               Slot=report.get("Slot", ""), Check=name,
                               Passed=bool(passed), Detail=detail))

        valid = all(number(report, key) is not None and number(report, key) >= 1
                    and number(report, key).is_integer() for key in identity)
        valid = valid and all(str(report.get(key, "")).strip().lower() not in
                              ("", "nan", "unavailable") for key in digests)
        matches = [row for row in pucch_rows if valid
                   and all(number(row, key) == number(report, key) for key in identity)
                   and all(row.get(key) == report.get(key) for key in digests)]
        check("received_sr_unique_pucch_context", len(matches) == 1,
              "SR must join one actual receiver assignment/context, cell, UE and occasion.")
        if len(matches) != 1:
            continue
        trial = matches[0]
        start, end, rate = (number(report, key) for key in
                            ("ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz"))
        check("received_sr_completed_clock", start is not None and start >= 0 and
              end is not None and end > start and rate is not None and rate > 0 and
              number(report, "AvailableAtSample") == end and all(
                  number(trial, key) == number(report, key) for key in
                  ("ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz")),
              "SR publication must retain the same completed actual receiver sample interval.")
        tx, detected = flag(report, "UETransmissionExecuted"), flag(report, "PositiveSRDetected")
        widths = tuple(number(trial, key) for key in ("ReceiverExpectedHARQBitCount",
                       "ReceiverExpectedSRBitCount", "ReceiverExpectedCSIPart1BitCount", "ReceiverExpectedCSIPart2BitCount"))
        check("received_sr_field_ownership", trial.get("UCIType") == "standalone_sr" and widths == (0, 1, 0, 0),
              "Standalone SR evidence cannot own HARQ or CSI fields.")
        check("received_sr_receiver_decision", detected is not None and
              flag(trial, "PositiveSRDetected") == detected and flag(trial, "PUCCHDecodeOk") == detected and
              flag(trial, "DTXFlag") == flag(report, "DTXFlag") and
              flag(trial, "ReceiverUsable") == flag(report, "ReceiverUsable") and
              (not detected or (flag(report, "ReceiverUsable") is True and flag(report, "DTXFlag") is False)),
              "Preserve actual receiver decisions, including false detections; never derive them from UE TX.")
        if tx is None or detected is None:
            check("received_sr_outcome_scoring", False, "Missing TX or received-decision audit flag.")
            continue
        expected_status = "PASS" if tx and detected else "NA" if not tx and not detected else "FAIL"
        expected_match = int(detected) if tx else None
        check("received_sr_outcome_scoring", flag(trial, "PUCCHTransmissionPrepared") == tx and
              flag(trial, "ReceiverOnlyAssignment") == (not tx) and
              all(flag(row, "FalseSRDetection") == (not tx and detected) and
                  flag(row, "MissedSRDetection") == (tx and not detected) for row in (trial, report)) and
              trial.get("Status") == expected_status and flag(trial, "FailureFlag") == (tx != detected) and
              flag(trial, "SuccessFlag") == (tx and detected) and number(trial, "UCIContentMatch") == expected_match,
              "Quiet SR is not a decoded payload; false/missed SR remain failures without rewriting received bits.")
    return checks


def audit_pucch_harq_binding(pucch_rows: list[dict], reports: list[dict]) -> list[dict]:
    """Reconcile PUCCH decisions with retained RX, not TX bits or desired outcomes.

    PUSCH has a different independent UCI completion schema and is not checked
    here. Live cross-file publication can be incomplete; retain that failure.
    """
    checks = []
    matched = {}
    for index, report in enumerate(reports):
        if report.get("UCITransport") != "PUCCH":
            continue

        def check(name, passed):
            checks.append(dict(Channel="ReceivedHARQ", CSVRow=index + 2,
                               Slot=report.get("TargetSlot", ""), Check=name,
                               Passed=bool(passed), Detail="PUCCH receive-to-HARQ disposition consistency, not PHY qualification."))

        digest = str(report.get("MappingDigest", ""))
        identities = [number(report, field) for field in ("UEIndex", "RNTI", "TargetSlot")]
        valid = (len(digest) == 64 and all(c in "0123456789abcdef" for c in digest.lower())
                 and all(v is not None and v > 0 and v == int(v) for v in identities))
        matches = [(i, row) for i, row in enumerate(pucch_rows) if valid
                   and row.get("GNBHARQMappingDigest") == digest
                   and [number(row, f) for f in ("UEIndex", "RNTI", "Slot")] == identities]
        check("harq_unique_pucch_binding", len(matches) == 1)
        if len(matches) != 1:
            continue
        trial_index, trial = matches[0]
        matched.setdefault(trial_index, []).append(report)
        start, end, fs, available = [number(report, f) for f in (
            "ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz", "AvailableAtSample")]
        clock = (all(v is not None for v in (start, end, fs, available)) and
                 0 <= start < end <= available and fs > 0 and
                 all(v == int(v) for v in (start, end, available)))
        check("harq_completed_pucch_clock", clock and all(number(report, f) == number(trial, f)
              for f in ("ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz")))
        bit_index, width = number(report, "BitIndex"), number(trial, "ReceiverExpectedHARQBitCount")
        bit_valid = (bit_index is not None and width is not None and
                     1 <= bit_index <= width and bit_index == int(bit_index))
        usable = flag(report, "ReceiverUsable")
        length_matches = flag(report, "ReceiverVectorLengthMatches")
        trial_flags = [flag(trial, f) for f in ("PUCCHDecodeOk", "ReceiverUsable", "DTXFlag")]
        check("harq_receiver_usability_binding", usable is not None and length_matches is not None and
              all(value is not None for value in trial_flags) and
              usable == (trial_flags[0] and trial_flags[1] and not trial_flags[2] and length_matches))
        decoded = str(trial.get("UCIDecodedBitVector", ""))
        if usable is True:
            payload = (bit_valid and flag(trial, "PUCCHDecodeOk") is True and
                       flag(trial, "DTXFlag") is False and flag(trial, "ReceiverUsable") is True and
                       flag(report, "ReceiverVectorLengthMatches") is True and
                       set(decoded) <= {"0", "1"} and len(decoded) == number(trial, "ReceiverExpectedBitCount"))
            outcome = "ACK" if payload and decoded[int(bit_index) - 1] == "1" else "NACK"
            check("harq_decoded_bit_outcome", payload and report.get("FeedbackOutcome") == outcome and
                  flag(report, "ObservedAck") == (outcome == "ACK"))
        else:
            check("harq_unusable_is_dtx", usable is False and report.get("FeedbackOutcome") == "DTX" and
                  flag(report, "ObservedAck") is False)
        stale, applied, changed = [flag(report, f) for f in (
            "StaleFeedbackIgnored", "HARQFeedbackApplied", "StateChangeApplied")]
        check("harq_stale_application_consistency", stale is not None and applied == (not stale) and changed == applied)
    for index, trial in enumerate(pucch_rows):
        width = number(trial, "ReceiverExpectedHARQBitCount")
        if width is None or width <= 0:
            continue
        rows = matched.get(index, [])
        indices = [number(row, "BitIndex") for row in rows]
        complete = (width == int(width) and len(rows) == width and
                    all(v is not None for v in indices) and sorted(indices) == list(range(1, int(width) + 1)))
        checks.append(dict(Channel="PUCCH", CSVRow=index + 2, Slot=trial.get("Slot", ""),
                           Check="harq_complete_unique_dispositions", Passed=complete,
                           Detail="Every scheduled HARQ bit must have exactly one independently bound disposition."))
        for field, flag_field in (("HARQFeedbackAppliedCount", "HARQFeedbackApplied"),
                                  ("StaleHARQFeedbackCount", "StaleFeedbackIgnored")):
            checks.append(dict(Channel="PUCCH", CSVRow=index + 2, Slot=trial.get("Slot", ""),
                               Check="harq_" + field + "_closure",
                               Passed=complete and number(trial, field) == sum(flag(row, flag_field) is True for row in rows),
                               Detail="Trial counts must equal actual associated dispositions, not payload width or TX scoring."))
    return checks


def audit_run(run_root: Path) -> dict:
    checks, sources, coverage, no_producer = [], [], {}, []
    channel_rows = {}
    for channel, stem in (("PRACH", "prach"), ("PUCCH", "pucch"),
                          ("PUSCH", "ul_pusch"), ("SRS", "srs"),
                          ("CSIFeedback", "csi_feedback"), ("ReceivedCSI", "received_csi"),
                          ("ReceivedSR", "received_sr"), ("ReceivedHARQ", "gnb_harq_feedback")):
        suffix = "_reports.csv" if channel in ("CSIFeedback", "ReceivedCSI") else "_trials.csv"
        relative = Path("air_interface/csv") / (stem + suffix)
        if channel == "ReceivedSR":
            relative = Path("control/csv/received_sr_observations.csv")
        if channel == "ReceivedHARQ":
            relative = Path("control/csv/gnb_harq_feedback_observations.csv")
        path = run_root / relative
        if not path.is_file():
            coverage[channel] = dict(State="not_observed", Rows=0)
            continue
        content = path.read_bytes()
        reader = csv.DictReader(io.StringIO(content.decode("utf-8-sig")))
        if not reader.fieldnames or not any(reader.fieldnames):
            coverage[channel] = dict(State="missing_schema", Rows=0)
            checks.append(dict(Channel=channel, CSVRow=1, Slot="", Check="csv_schema",
                               Passed=False, Detail="Published CSV has no header."))
            rows = []
        else:
            rows = list(reader)
            coverage[channel] = dict(State="observed" if rows else "not_observed", Rows=len(rows))
            checks.extend(audit_rows(channel, rows))
            if channel == "PUCCH":
                for index, row in enumerate(rows):
                    if (flag(row, "ReceiverOnlyAssignment") is True
                            and flag(row, "PUCCHTransmissionPrepared") is False
                            and flag(row, "PUCCHDecodeOk") is True):
                        no_producer.append(dict(CSVRow=index + 2, Slot=row.get("Slot", ""),
                                                DecodedBits=row.get("UCIDecodedBitVector", ""),
                                                Meaning="reported_detection_without_prepared_PUCCH_not_a_transmission_success_or_detector_qualification"))
        sources.append(dict(Path=relative.as_posix(), SHA256=hashlib.sha256(content).hexdigest(),
                            Bytes=len(content), Rows=len(rows)))
        channel_rows[channel] = rows
    checks.extend(audit_srs_grant_binding(channel_rows.get("SRS", []), channel_rows.get("PUSCH", [])))
    checks.extend(audit_data_feedback_binding(channel_rows.get("PUSCH", []), channel_rows.get("CSIFeedback", [])))
    checks.extend(audit_received_csi_binding(channel_rows.get("PUCCH", []), channel_rows.get("ReceivedCSI", [])))
    checks.extend(audit_received_sr_binding(channel_rows.get("PUCCH", []), channel_rows.get("ReceivedSR", [])))
    checks.extend(audit_pucch_harq_binding(channel_rows.get("PUCCH", []), channel_rows.get("ReceivedHARQ", [])))
    return dict(Scope="observed_uplink_evidence_consistency_not_phy_qualification",
                CrossFileAtomicCheckpoint=False, HARQBindingScope="PUCCH_only_PUSCH_not_checked",
                RunRoot=str(run_root.resolve()),
                Coverage=coverage, Sources=sources, Checks=checks,
                ReceiverOnlyNoProducerDetections=no_producer,
                FailedChecks=sum(not item["Passed"] for item in checks),
                UnobservedChannels=[key for key, value in coverage.items() if value["State"] != "observed"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit_run(args.run_root)
    # Immutable audit receipt: never overwrite an earlier observed checkpoint.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, allow_nan=False)
        handle.write("\n")
    print(json.dumps({key: result[key] for key in (
        "Coverage", "FailedChecks", "UnobservedChannels", "ReceiverOnlyNoProducerDetections")}))
    return 1 if result["FailedChecks"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
