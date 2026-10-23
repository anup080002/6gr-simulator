"""Project retained receiver evidence without manufacturing measurements.

This is a display adapter, not a scorer. In particular, a PASS is never used
to infer waveform execution, channel estimation, EVM, or an NMSE reference.
"""
from __future__ import annotations

import math
import json
import re
from typing import Any


def _value(row: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        value = row.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text.lower() in {"", "nan", "none", "null", "n/a", "<missing>"}:
            continue
        if text.startswith(("not_emitted_by_active_", "not_recorded_by_active_")):
            continue
        return value
    return None


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def waveform_quality_fields(key: str, row: dict[str, Any]) -> dict[str, Any]:
    """Return source-labelled fields for this exact trial; never join rows."""
    result: dict[str, Any] = {}
    notes: list[str] = []

    def put(label: str, *keys: str) -> None:
        value = _value(row, *keys)
        if value is not None:
            result[label] = value

    for label, keys in {
        "EVM reference source": ("EVMReferenceSource",),
        "EVM status": ("EVMValueStatus",),
        "NMSE dB": ("NMSE_dB",),
        "NMSE scoring available": ("NMSEScoringAvailable",),
        "NMSE reference source": ("NMSEReferenceSource", "NMSESource", "ChannelNMSESource"),
        "NMSE reference plane": ("ChannelNMSEReferencePlane", "NMSEReferencePlane"),
        "NMSE compared complex values": ("ChannelNMSEComparedComplexValues",),
        "NMSE pilot resource count": ("ChannelNMSEPilotResourceCount",),
        "NMSE qualification mode": ("ChannelNMSEQualificationMode",),
        "NMSE reference includes RF impairments": ("ChannelNMSEReferenceIncludesRFImpairments",),
        "NMSE reference used by receiver": ("ChannelNMSEReferenceUsedByReceiver",),
        "Channel estimate available": ("ChannelEstimateAvailable",),
        "Channel estimate source": ("ChannelEstimateSource", "ChannelEstimator"),
        "Channel estimate applicable": ("ChannelEstimateApplicable",),
        "Equalization available": ("EqualizationAvailable",),
        "Equalization applicable": ("EqualizationApplicable",),
        "Observation start sample": ("ObservationStartSample",),
        "Observation end sample": ("ObservationEndSampleExclusive",),
        "Observation sample rate (Hz)": ("ObservationSampleRateHz",),
        "Observation scope": ("ObservationCoverageSource",),
        "Waveform executed": ("RuntimeStageWaveformsUsed",),
        "Sweep point": ("SweepPointIndex",),
        "Configured SNR (dB)": ("ConfiguredSNR_dB",),
        "Observation ID": ("ObservationID", "PhysicalPUCCHOccasionId"),
        "SSB index": ("SSBIndex",),
    }.items():
        put(label, *keys)

    rms = _number(_value(row, "EVM_rms"))
    percent = _number(_value(row, "ReceiverEVMPercent", "EVMPercent"))
    if rms is not None and rms >= 0:
        result["EVM rms"] = rms
        result["EVM percent"] = 100 * rms
        result["EVM applicable"] = 1
        if percent is not None and not math.isclose(percent, 100 * rms, rel_tol=1e-8, abs_tol=1e-10):
            notes.append("conflicting stored EVM units; percent shown as 100 × retained RMS")
    elif percent is not None and percent >= 0:
        result["EVM percent"] = percent
        result["EVM rms"] = percent / 100
        result["EVM applicable"] = 1
    else:
        put("EVM applicable", "ReceiverEVMApplicable", "EVMApplicable")

    # Complete received-buffer coverage is stronger evidence than an old
    # collector's default false flag. Keep the conflict visible, not hidden.
    coverage = _value(row, "ObservationCoverageSource")
    if coverage == "complete_contiguous_received_sample_buffer":
        result["Waveform executed"] = 1
        if _number(row.get("RuntimeStageWaveformsUsed")) == 0:
            notes.append("complete received capture; legacy waveform-used flag is incorrectly zero")

    if key in {"dl_trials", "ul_trials"}:
        # These describe the receiver-aligned DATA SYMBOL interval, not the
        # wider channel archive or transmitter interval.
        if "Observation start sample" not in result:
            if _value(row, "DataReceiveTimingSource") == (
                "actual_received_reference_alignment_and_executed_OFDM_symbol_lengths"
            ):
                put("Observation start sample", "DataReceiveSymbolStartSample")
                put("Observation end sample", "DataReceiveSymbolEndSampleExclusive")
                put("Observation sample rate (Hz)", "DataReceiveSampleRateHz")
                result["Observation scope"] = "receiver-aligned data symbols (not full capture)"
        if "NMSE reference source" not in result and _number(row.get("NMSEScoringAvailable")) == 1:
            notes.append("NMSE scoring flag present but reference source not retained")

    mode = str(_value(row, "ChannelEstimationMode") or "")
    source = str(_value(row, "ChannelEstimateSource") or "")
    noncoherent = key == "pucch_trials" and (
        mode == "format0_noncoherent_sequence_detection"
        or source == "not_applicable_format0_noncoherent_sequence_detection"
    )
    if noncoherent:
        if any(_number(row.get(name)) == 1 for name in ("ChannelEstimateAvailable", "EqualizationAvailable")):
            notes.append("legacy availability flags conflict with executed noncoherent detector")
        result.update({
            "Channel estimate applicable": 0, "Channel estimate available": 0,
            "Equalization applicable": 0, "Equalization available": 0,
            "EVM applicable": 0,
            "EVM status": "NOT_APPLICABLE_FORMAT0_NONCOHERENT_SEQUENCE_DETECTION",
        })
        if rms is not None or percent is not None:
            notes.append("unexpected modulation EVM on noncoherent format-0 trial")

    # Existing PDCCH/PUCCH hashes identify TX samples, NOT received samples.
    if _value(row, "ReceiverObservationSHA256") is not None:
        put("Waveform hash", "ReceiverObservationSHA256")
        put("Waveform hash plane", "ReceiverObservationHashPlane")
    elif _value(row, "RxRFOutputWaveformSHA256") is not None:
        put("Waveform hash", "RxRFOutputWaveformSHA256")
        result["Waveform hash plane"] = "RX RF output; not necessarily decoder-aligned capture"
    elif key == "pdcch_trials" and _value(row, "PDCCHWaveformHash") is not None:
        put("Waveform hash", "PDCCHWaveformHash")
        result["Waveform hash plane"] = "prepared PDCCH TX waveform"
    elif key == "pucch_trials" and _value(row, "PUCCHWaveformHash") is not None:
        put("Waveform hash", "PUCCHWaveformHash")
        result["Waveform hash plane"] = "prepared PUCCH TX waveform"
    if key == "pdcch_trials":
        put("PDCCH receiver attempted", "PDCCHReceiverTrialExecuted")
        put("Measurement attempted", "MeasurementAttempted")
        if _value(row, "RuntimeMaterializationStatus") == (
            "active_integrated_pdcch_pretransmission_admission_disposition"
        ):
            # This is an actual scheduler disposition, not a failed or
            # missing receiver. Separate it only with explicit no-execution
            # evidence; legacy blanks and real receiver failures stay visible.
            put("Admission blocker", "FailureReason")
            flags = [_number(row.get(name)) for name in (
                "RuntimeStageWaveformsUsed", "PDCCHReceiverTrialExecuted", "MeasurementAttempted")]
            def retained(name: str) -> bool:
                value = _value(row, name)
                return value is not None and not str(value).startswith("not_applicable_for_active_")

            # Even malformed values/hashes must remain visible for review.
            # A nonfinite metric is not permission to hide its receiver row.
            measured = any(retained(name) for name in (
                "EVM_rms", "ReceiverEVMPercent", "EVMPercent", "NMSE_dB"))
            received_hash = any(retained(name) for name in (
                "ReceiverObservationSHA256", "RxRFOutputWaveformSHA256"))
            observed = measured or received_hash or coverage == "complete_contiguous_received_sample_buffer"
            observed = observed or any(_number(row.get(name)) == 1 for name in (
                "NMSEScoringAvailable", "ChannelEstimateAvailable", "EqualizationAvailable"))
            if observed or any(value is not None and value != 0 for value in flags):
                result["Receiver evidence scope"] = "conflicting_pretransmission_and_receiver_evidence"
                notes.append("conflicting admission-only and receiver evidence; retained in receiver tables for review")
            elif all(value == 0 for value in flags):
                result["Receiver evidence scope"] = "pretransmission_admission_no_receiver"
            else:
                result["Receiver evidence scope"] = "pretransmission_disposition_execution_unverified"
                notes.append("admission disposition lacks explicit no-reception flags; not excluded from receiver tables")
    if notes:
        result["Evidence notes"] = "; ".join(notes)
    return result


def precoding_evidence_fields(row: dict[str, Any]) -> dict[str, Any]:
    """Separate executed matrix identity from PMI and post-hoc projections."""
    result = {}
    for label, key in {
        "Bootstrap grant": "LinkAdaptationBootstrap",
        "Precoder domain": "PrecoderDigestDomain",
        "PMI basis": "AppliedPrecoderPMIBasis",
        "CSI resource applied": "AppliedCSIResourceIndex",
        "TCI state ID": "TCIStateID",
        "TCI status": "TCIStatus",
        "Projection candidates": "BeamCandidateCount",
        "Best projection index": "BestBeamIndex",
        "Best projection power (dB)": "BestBeamGain_dB",
        "Selected projection power (dB)": "SelectedBeamGain_dB",
        "Projection gap (dB)": "BeamGainGap_dB",
        "Projection source": "BeamScoreSource",
    }.items():
        value = _value(row, key)
        if value is not None:
            result[label] = value
    requested = str(_value(row, "RequestedPrecoderSHA256") or "")
    applied = str(_value(row, "AppliedPrecoderSHA256") or "")
    if (re.fullmatch(r"[0-9a-fA-F]{64}", requested)
            and re.fullmatch(r"[0-9a-fA-F]{64}", applied)
            and _value(row, "PrecoderDigestDomain")):
        result["Matrix identity match"] = int(requested.lower() == applied.lower())
    # Never turn a requested beam, post-hoc best beam or a TCI ID into an
    # applied CSI resource index. They belong to different namespaces.
    return result


def synchronization_search_fields(row: dict[str, Any], prefix: str) -> dict[str, Any]:
    try:
        evidence = json.loads(str(row.get(prefix + "SynchronizationJSON", "")))
        timing = evidence["Timing"]
        window = timing["SearchWindowSamples"]
        if not isinstance(window, list) or len(window) != 2:
            return {}
        first, last = map(float, window)
        if not (math.isfinite(first) and math.isfinite(last)
                and first >= 0 and last >= first
                and first.is_integer() and last.is_integer()):
            return {}
    except (ValueError, TypeError, KeyError):
        return {}
    # This describes the retained search extent, not whether acquisition
    # was correct or whether the channel actually had a nonzero delay.
    return {"search_window": f"{int(first)}–{int(last)}",
            "timing_hypotheses": int(last - first + 1),
            "timing_search_scope": ("fixed alignment; no timing acquisition"
                                    if first == last else "bounded received-pilot acquisition")}


def qualification_criteria_fields(key: str, row: dict[str, Any]) -> dict[str, Any]:
    """Expose recorded criteria without inventing thresholds or rescoring."""
    result = {}
    mapping = {
        "Detection threshold": "DetectionThreshold",
        "Detection threshold source": "DetectionThresholdSource",
        "NMSE qualification limit (dB)": "ChannelNMSEThreshold_dB",
        "Minimum resource coverage": "MinCoverageRatio",
        "Receiver evidence usable": "StrictReceiverEvidenceOk",
        "Qualification passed": "StrictOk",
        "TRS runtime usable": "TRSRuntimeEvidenceUsable",
        "Qualification criteria": "TRSQualificationCriteriaJSON",
    }
    if key == "pbch_trials":
        mapping.update({"PSS threshold": "PSSDetectionThreshold",
                        "SSS threshold": "SSSDetectionThreshold"})
    if key == "prach_trials":
        mapping.update({"Detection threshold source": "PreambleDetectionThresholdSource",
                        "Detector qualification": "PreambleDetectionThresholdCalibrationStatus",
                        "Target false-alarm probability": "Msg1ConfiguredTargetFalseAlarmProbability"})
    for label, field in mapping.items():
        value = _value(row, field)
        if value is not None:
            result[label] = value
    if key in {"pdcch_trials", "dl_trials", "ul_trials", "pbch_trials"}:
        if _value(row, "CRCPass", "DecodeOk") is not None:
            result["Decode acceptance"] = "decoded CRC and channel-specific context checks; not an EVM limit"
    elif key == "pucch_trials" and _value(row, "CRCApplicable") is not None:
        result["Decode acceptance"] = ("detection and applicable UCI CRC; bit-match audit is separate"
                                       if _number(row["CRCApplicable"]) == 1
                                       else "detection; no UCI CRC for this payload")
    return result


def csi_feedback_evidence_fields(row: dict[str, Any]) -> dict[str, Any]:
    """Classify this report only; a CQI mapping is not an executed data MCS.

    The same retained table contains queued UE measurements, decoded DL
    CSI-UCI, and gNB-local UL measurements. No PHY result or scheduler state
    is created here, and a producer's raw fields remain available for audit.
    """
    if not any(k in row for k in ("Direction", "SourceSignal", "Processed", "MCSIndex")):
        return {}

    def token(key: str) -> str:
        return str(_value(row, key) or "").strip()

    def flag(key: str) -> int | None:
        value = row.get(key)
        if isinstance(value, str) and value.strip().lower() in {"true", "false"}:
            return int(value.strip().lower() == "true")
        number = _number(value)
        return int(number) if number in (0, 1) else None

    direction = token("Direction").upper()
    signal = token("SourceSignal")
    transport = token("CSIUCITransport")
    processed = flag("Processed")
    status = token("DeliveryStatus")
    clocks = [_number(row.get(k)) for k in ("SourceSlot", "DueSlot", "DeliveredSlot")]
    causal = (all(x is not None and x >= 0 and x.is_integer() for x in clocks)
              and clocks[0] <= clocks[1] <= clocks[2])
    delivered = processed == 1 and status == "delivered_to_runtime_scheduler" and causal
    pending = processed == 0 and status.startswith("pending_")
    scope = "feedback_delivery_unverified"
    uci = "transport_evidence_unverified"
    if direction == "UL" and signal in {"SRS", "PUSCH-DMRS"}:
        if transport in {"", "not_scheduled"} and flag("CSIUCIDecodeOk") in (None, 0):
            scope = ("delivered_gnb_local_ul_feedback" if delivered
                     else "pending_gnb_local_ul_feedback" if pending
                     else "gnb_local_ul_feedback_delivery_unverified")
            uci = "not_applicable_gnb_local_ul_feedback"
        else:
            scope = "conflicting_ul_local_feedback_and_uci_transport"
    elif direction == "DL":
        if (delivered and signal == "received_CSI_UCI" and flag("CSIUCIDecodeOk") == 1
                and transport in {"pucch_decoded", "pusch_decoded"}):
            scope = "received_dl_csi_uci"
            uci = "independently_decoded_dl_csi_feedback"
        elif pending and flag("CSIUCIDecodeOk") == 0 and clocks[2] is None:
            scope = "pending_report_not_received"
            uci = "pending_transport_not_decode_failure"
        elif processed == 1 and status in {"pucch_csi_decode_failed_not_delivered",
                                          "pusch_csi_decode_unavailable_not_delivered",
                                          "pucch_csi_omitted_not_delivered"}:
            scope = "dl_csi_uci_not_delivered"
            uci = status

    result = {"Feedback evidence scope": scope, "UCI interpretation": uci,
              "Stored MCS field": _value(row, "MCSIndex"), "Selected MCS": None,
              "MCS decision status": "no_delivered_scheduler_decision"}
    if scope not in {"received_dl_csi_uci", "delivered_gnb_local_ul_feedback"}:
        return result
    if flag("SchedulerSpatialDecisionDeferred") == 1:
        result["MCS decision status"] = "held_spatial_operating_point"
        return result
    resolved_cqi = _number(row.get("SchedulerResolvedCQI"))
    if resolved_cqi == 0:
        result["MCS decision status"] = "measured_cqi_out_of_range"
        return result
    stored = _number(row.get("MCSIndex"))
    adapted = _number(row.get("LinkAdaptationMCSIndex"))
    reported_rank = _number(row.get("RI"))
    accepted_rank = _number(row.get("SchedulerAcceptedRank"))
    if (token("AdaptationDeliveryStatus") == "accepted_new_feedback_delivery"
            and flag("SchedulerSpatialDecisionDeferred") == 0
            and resolved_cqi is not None and resolved_cqi > 0
            and reported_rank is not None and reported_rank >= 1 and reported_rank.is_integer()
            and accepted_rank == reported_rank
            and stored is not None and stored >= 0 and stored.is_integer()
            and adapted == stored):
        result["Selected MCS"] = int(stored)
        result["MCS decision status"] = "accepted_for_future_grants_not_executed_trial"
    else:
        result["MCS decision status"] = "accepted_mcs_evidence_missing_or_conflicting"
    return result
