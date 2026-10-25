"""Declared receiver/lifecycle CSV contracts, not new PHY or confidence intervals."""
import copy
import csv
import io
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_web_dashboard as dash


def attempt(identity="a1", *, direction="DL", retry=0, crc=0, tb="tb1", slot=1):
    row = dict(RunID="declared_fixture", ConfigHash="c" * 64, Direction=direction,
               SweepPointIndex=1, ConfiguredSNR_dB=20, UEIndex=1, RNTI=4660, ServingCell=1,
               TransmissionAttemptID=identity, TBId=tb, Slot=slot, HarqID=0,
               FinalizedFlag=1, PartialRowFlag=0, Crash=0, IsWarmupFrame=0,
               DecodeAttempted=1, DecodeUsable=1, CRCApplicable=1, CRCPass=crc,
               Status="PASS" if crc else "FAIL", ApproximationMode="none",
               ExecutionBackend="scheduler_shared_stream_receiver")
    row[("DLSCH" if direction == "DL" else "ULSCH") + "DecodeAttempted"] = 1
    row[("DLSCH" if direction == "DL" else "ULSCH") + "DecodeAvailable"] = 1
    if retry is not None:
        row.update(IsRetransmission=retry, HARQIsRetransmission=retry)
    return row


def feedback(row, outcome="ACK"):
    return dict(ObservationID="rx_" + row["TransmissionAttemptID"], BitIndex=1,
                FeedbackForDirection=row["Direction"], SweepPointIndex=row["SweepPointIndex"],
                UEIndex=1, RNTI=4660, PHYGrantContextId=row["TransmissionAttemptID"],
                SourceSlot=row["Slot"], HarqID=0, FeedbackOutcome=outcome,
                ObservationEndSampleExclusive=100, AvailableAtSample=101, ObservationSampleRateHz=30720000,
                UCITransport="PUCCH", ReceiverUsable=int(outcome != "DTX"), ObservedAck=int(outcome == "ACK"),
                HARQFeedbackApplied=1, StaleFeedbackIgnored=0)


def packet(row, ordinal=1, total=1, terminal=1, reason="observed_ack_release"):
    return dict(Direction=row["Direction"], SweepPointIndex=row["SweepPointIndex"], UEIndex=1, RNTI=4660,
                TBId=row["TBId"], PHYGrantContextId=row["TransmissionAttemptID"], Slot=row["Slot"],
                ProbeMode="canonical_slot_runtime_truth", Source="canonical_slot_runtime_harq_timeline",
                ApproximationMode="none", CombinedDecodeOK=row["CRCPass"], IsRetransmission=row["IsRetransmission"],
                TransmitterLifecycleBound=1, HARQPacketReceiverPopulationComplete=1, LifecycleAttemptCount=total,
                Attempt=ordinal, TransmitterTerminal=terminal, TransmitterTerminalReason=reason if terminal else "",
                TerminalAtSlot=row["Slot"] + 3 if terminal else "NaN")


def csv_rows(rows):
    if not rows:
        return []
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fieldnames=sorted({key for row in rows for key in row}))
    writer.writeheader()
    writer.writerows(rows)
    stream.seek(0)
    return list(csv.DictReader(stream))


def summarize(**sources):
    return dash.build_realtime_error_statistics({key: csv_rows(rows) for key, rows in sources.items()})


def direction(result, name="DL"):
    return next(row for row in result["sch"] if row["Direction"] == name)


def test_first_retry_unknown_pending_and_ra_separation():
    first = attempt()
    retry = attempt("a2", retry=1, crc=1, slot=2)
    unknown = attempt("a3", retry=None, crc=1, tb="tb2", slot=3)
    pending = attempt("a4", tb="tb3", slot=4)
    pending.update(FinalizedFlag=0, DecodeAttempted=0)
    crash = attempt("a5", tb="tb4", slot=5)
    crash.update(Crash=1, Status="CRASH")
    result = summarize(dl=[first, retry, unknown, pending, crash], ul=[attempt("u1", direction="UL", crc=1)],
                       msg3=[attempt("ra1", direction="UL", crc=0)])
    dl, ul = direction(result), direction(result, "UL")
    assert (dl["First TX errors"], dl["First TX completed"], dl["First TX BLER"]) == (1, 1, 1)
    assert (dl["Attempt errors"], dl["Completed attempts"], dl["All-attempt failure ratio"]) == (1, 3, 1/3)
    assert dl["Completed retries"] == dl["Unknown attempt class"] == dl["Unfinalized rows"] == 1
    assert dl["Excluded rows"] == 2
    assert dl["Feedback pending/unavailable"] == 3 and dl["Received DTX dispositions"] == 0
    assert dl["Residual final-TB BLER"] is None and dl["Open/censored TBs"] == 2
    assert ul["Completed attempts"] == 1 and ul["First TX BLER"] == 0
    assert ul["Feedback pending/unavailable"] is None


def test_dedupe_exact_attempts_conflict_excluded_and_sweep_points_separate():
    a = attempt()
    b = attempt("a2", slot=2)
    changed = dict(b, CRCPass=1, Status="PASS")
    other = dict(a, SweepPointIndex=2, ConfiguredSNR_dB=0)
    result = summarize(dl=[a, copy.deepcopy(a), b, changed, other])
    assert result["identical_duplicates_removed"] == 1
    assert len([r for r in result["sch"] if r["Direction"] == "DL"]) == 2
    assert all(r["Completed attempts"] == 1 for r in result["sch"] if r["Direction"] == "DL")
    assert any(r["Reason"] == "conflicting_duplicate_identity" for r in result["audit"])


@pytest.mark.parametrize("change", [dict(IsRetransmission="NaN", HARQIsRetransmission="NaN"),
                                   dict(IsRetransmission="", HARQIsRetransmission="")])
def test_unknown_retry_never_initial(change):
    result = direction(summarize(dl=[dict(attempt(), **change)]))
    assert result["Completed attempts"] == 1 and result["Unknown attempt class"] == 1
    assert result["First TX completed"] == 0 and result["First TX BLER"] is None


@pytest.mark.parametrize("change", [dict(HARQIsRetransmission=1), dict(DLSCHDecodeAvailable=0),
                                   dict(CRCPass=2), dict(TransmissionAttemptID=""), dict(ApproximationMode="fast_proxy")])
def test_incompatible_rows_do_not_supply_bler(change):
    result = summarize(dl=[dict(attempt(), **change)])
    assert direction(result)["Completed attempts"] == 0
    assert direction(result)["First TX BLER"] is None and result["audit"]


def test_actual_feedback_bit_population_not_crc_and_not_pending_defaults():
    rows = [attempt("a1", crc=0), attempt("a2", slot=2, tb="tb2", crc=1), attempt("a3", slot=3, tb="tb3")]
    f = [feedback(rows[0], "ACK"), feedback(rows[1], "NACK"), feedback(rows[2], "DTX")]
    result = direction(summarize(dl=rows, feedback=f + [dict(f[0])]))
    assert (result["Received ACK bits"], result["Received NACK bits"], result["Received DTX dispositions"]) == (1, 1, 1)
    assert result["Feedback pending/unavailable"] == 0
    # Positive ACK does not turn failed receiver CRC into a successful TB.
    assert result["Attempt errors"] == 2 and result["Residual final-TB BLER"] is None


@pytest.mark.parametrize("change", [dict(ReceiverUsable=1), dict(AvailableAtSample=99), dict(BitIndex=0),
                                   dict(UCITransport="model"), dict(PHYGrantContextId="wrong"), dict(SweepPointIndex=2)])
def test_malformed_unjoined_dtx_is_not_observed(change):
    row = attempt()
    result = direction(summarize(dl=[row], feedback=[dict(feedback(row, "DTX"), **change)]))
    assert result["Received DTX dispositions"] == 0 and result["Feedback pending/unavailable"] == 1


def test_terminal_false_ack_failure_and_false_nack_success_not_transmitter_labels():
    a = attempt()
    result = direction(summarize(dl=[a], packets=[packet(a)]))
    assert result["Residual final-TB BLER"] == 1  # False ACK release, receiver still failed.
    b = attempt("a2", slot=2, retry=1, crc=1)
    packets = [packet(a, total=2, terminal=0), packet(b, ordinal=2, total=2, reason="retry_limit_release")]
    result = direction(summarize(dl=[a, b], packets=packets))
    assert result["Residual final-TB BLER"] == 0 and result["Qualified terminal TBs"] == 1
    c = attempt("c", tb="open", slot=3)
    result = direction(summarize(dl=[a, b, c], packets=packets))
    assert result["Residual final-TB BLER"] is None and result["Open/censored TBs"] == 1


@pytest.mark.parametrize("change", [dict(ProbeMode="closed_loop"), dict(CombinedDecodeOK=1),
                                   dict(TransmitterLifecycleBound=0), dict(LifecycleAttemptCount=2),
                                   dict(HARQPacketReceiverPopulationComplete=0), dict(Attempt=2),
                                   dict(TransmitterTerminalReason="run_end"), dict(TerminalAtSlot=0)])
def test_incomplete_or_probe_terminal_cannot_close_runtime_tb(change):
    a = attempt()
    result = direction(summarize(dl=[a], packets=[dict(packet(a), **change)]))
    assert result["Residual final-TB BLER"] is None and result["Qualified terminal TBs"] == 0


def test_pucch_dtx_requires_actual_completed_detector_and_keeps_crc_failure_distinct():
    base = dict(ObservationID="o1", FinalizedFlag=1, ControlObservationAvailable=1,
                DetectionAttempted=1, DetectionMetricValid=1, ObservationStartSample=0,
                ObservationEndSampleExclusive=100, ObservationSampleRateHz=30720000,
                DetectionOutcome="detected", CRCPass=0, Status="FAIL")
    rows = [base, dict(base, ObservationID="o2", DetectionOutcome="dtx"),
            dict(base, ObservationID="pending", FinalizedFlag=0, ControlObservationAvailable=0, DTXFlag=1),
            dict(base, ObservationID="withheld", UETransmissionPrepared=0, ControlObservationAvailable=0),
            dict(base, ObservationID="crash", Status="CRASH", DetectionAttempted=0),
            dict(base, ObservationID="no_outcome", DetectionOutcome="", DTXFlag=1)]
    result = summarize(pucch=rows)
    assert result["control"][0]["DTX decisions"] == 1
    assert result["control"][0]["Completed detector decisions"] == 2
    assert result["control"][0]["DTX fraction"] == .5


def test_visible_ui_tables_consume_actual_statistics_and_loader_not_preview(monkeypatch):
    paths = []
    def load(artifacts, path, **kwargs):
        paths.append((path, kwargs))
        return [attempt()] if path.endswith("dl_pdsch_trials.csv") else []
    monkeypatch.setattr(dash, "load_small_csv_rows", load)
    result = dash.load_realtime_error_statistics([])
    assert len(paths) == 5 and all(k["max_rows"] is None for _, k in paths)
    source = (ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
    lines = [line.strip() for line in source.splitlines() if line.strip().startswith(("{id:'sch_bler_counts'", "{id:'harq_feedback_counts'", "{id:'pucch_dtx_counts'", "{id:'error_population_exclusions'"))]
    assert len(lines) == 4
    node = shutil.which("node") or "C:/ProgramData/anaconda3/Lib/site-packages/playwright/driver/node.exe"
    code = "const errorStats=" + json.dumps(result) + ";const specs=[" + "\n".join(lines) + "];console.log(JSON.stringify(specs));"
    parsed = json.loads(subprocess.run([node, "-e", code], text=True, capture_output=True, check=True, timeout=15).stdout)
    assert parsed[0]["rows"][0]["First TX BLER"] == 1
    assert parsed[1]["rows"][0]["Feedback pending/unavailable"] == 1
    assert parsed[2]["rows"][0]["DTX fraction"] is None
    assert "complete currently published canonical records" in source
    assert "fullPopulationViews.has(spec.id) ? 'population/audit rows' : 'preview rows'" in source


def test_ambiguous_cross_run_identity_and_missing_clocks_do_not_join_feedback_or_terminal():
    a = attempt()
    b = dict(a, RunID="different_original_run")
    result = summarize(dl=[a, b], packets=[packet(a)], feedback=[feedback(a)])
    assert all(r["Residual final-TB BLER"] is None and r["Received ACK bits"] == 0 for r in result["sch"])
    a["Slot"] = "NaN"
    result = summarize(dl=[a], packets=[dict(packet(attempt()), Slot="NaN")])
    assert direction(result)["Residual final-TB BLER"] is None


def test_conflicted_other_tb_prevents_uncensored_residual_probability():
    a = attempt()
    b = attempt("b", tb="b", slot=2)
    result = summarize(dl=[a, b, dict(b, CRCPass=1)], packets=[packet(a)])
    assert direction(result)["Qualified terminal TBs"] == 1
    assert direction(result)["Residual final-TB BLER"] is None


def presence_row():
    receipt = dict(Schema="shared_PUCCH_presence_receipts/v1", ObservationID="pucch_observation_185",
                   ConfigurationEpoch=1, PhysicalOccasionID="original_occasion",
                   ReceiverAssignmentDigest="a" * 64, ReceiverContextDigest="b" * 64,
                   RXStartSample=659772, RXEndSampleExclusive=675782, SampleRateHz=30720000)
    raw = json.dumps(receipt, separators=(",", ":"))
    return dict(RunID="declared_actual_shaped", ConfigHash="c" * 64, UEIndex=1, RNTI=4660, BaseStationID=1,
                PresenceUEIndex=1, PresenceRNTI=4660, PresenceServingCell=1, SweepPointIndex=1,
                PresenceObservationID=receipt["ObservationID"], TransmitOccupancyObservationID=receipt["ObservationID"],
                PresenceEvidenceJSON=raw, PresenceEvidenceSHA256=hashlib.sha256(raw.encode()).hexdigest(),
                PresenceScoringSource="post_receiver_executed_components_and_link_contributions/v1",
                PresencePhysicalOccasionID=receipt["PhysicalOccasionID"], PresenceConfigurationEpoch=1,
                PresenceReceiverAssignmentDigest="a" * 64, PresenceReceiverContextDigest="b" * 64,
                PresenceRXStartSample=659772, PresenceRXEndSampleExclusive=675782, PresenceSampleRateHz=30720000,
                ObservationStartSample=659772, ObservationEndSampleExclusive=675782, ObservationSampleRateHz=30720000,
                ReceiverObservationSHA256="d" * 64, ReceiverObservationHashPlane="actual_receiver_input_before_synchronization",
                ReceiverObservationHashSerialization="WaveformHash.runtimeArray_class_dimensions_real_imag_double",
                DetectionAttempted=1, DetectionMetricValid=1, DetectionOutcome="detected", DTXFlag=0,
                FinalizedFlag=1, ControlObservationAvailable=1)


def test_original_presence_alias_csv_roundtrip_and_duplicate_integrity():
    row = presence_row()
    before = copy.deepcopy(row)
    result = summarize(pucch=[row, copy.deepcopy(row)])
    assert result["control"][0]["Completed detector decisions"] == 1
    assert result["control"][0]["DTX fraction"] == 0
    assert result["identical_duplicates_removed"] == 1 and row == before
    conflicting = dict(row, DetectionOutcome="dtx", DTXFlag=1)
    assert summarize(pucch=[row, conflicting])["control"][0]["Completed detector decisions"] == 0
    canonical = dict(row, ObservationID=row["PresenceObservationID"])
    assert summarize(pucch=[canonical])["control"][0]["Completed detector decisions"] == 1


@pytest.mark.parametrize("change", [
    dict(PresenceEvidenceSHA256="0"*64), dict(PresenceEvidenceJSON="{}"),
    dict(ObservationID="different"), dict(TransmitOccupancyObservationID="different"),
    dict(ObservationStartSample=659773), dict(ObservationSampleRateHz=15360000),
    dict(PresenceConfigurationEpoch=2), dict(ReceiverObservationSHA256="invalid"),
    dict(PresenceReceiverContextDigest="f"*64), dict(PresenceScoringSource="unknown"),
    dict(ReceiverObservationHashPlane="tx"), dict(PresenceServingCell=2), dict(ServingCell=2),
    dict(PresenceObservationID=""), dict(PresenceRNTI=123),
])
def test_presence_alias_does_not_invent_or_coerce_identity(change):
    result = summarize(pucch=[dict(presence_row(), **change)])
    assert result["control"][0]["Completed detector decisions"] == 0
    assert any(a["Reason"] == "invalid_original_PUCCH_observation_receipt" for a in result["audit"])


@pytest.mark.parametrize("field,value", [("RXStartSample", "659772"), ("ConfigurationEpoch", True),
                                         ("Schema", "unknown"), ("ObservationID", "different")])
def test_resealed_presence_corruption_stays_excluded(field, value):
    row = presence_row()
    receipt = json.loads(row["PresenceEvidenceJSON"])
    receipt[field] = value
    row["PresenceEvidenceJSON"] = json.dumps(receipt)
    row["PresenceEvidenceSHA256"] = hashlib.sha256(row["PresenceEvidenceJSON"].encode()).hexdigest()
    assert summarize(pucch=[row])["control"][0]["Completed detector decisions"] == 0


def test_stale_receiver_terminal_protocol_disposition_not_measured_dtx_or_pending():
    row = attempt()
    flags = dict(ReceiverExecutionStatus="unavailable_before_synchronization",
                 FeedbackDisposition="receiver_unavailable_stale_ul_timing",
                 ReceiverUnavailableReason="stale_received_ul_timing", DetectionAttempted=0,
                 DecodeAttempted=0, DTXDecisionAvailable=0)
    f = dict(feedback(row, "DTX"), **flags)
    result = summarize(dl=[row], feedback=[f], pucch=[dict(presence_row(), **flags, DetectionOutcome="unavailable")])
    dl = direction(result)
    assert dl["Received DTX dispositions"] == 0 and dl["Feedback pending/unavailable"] == 0
    assert dl["Terminal unavailable feedback dispositions"] == 1
    assert result["control"][0]["Completed detector decisions"] == 0
    assert any(a["Reason"] == "terminal_receiver_unavailable_not_observed_DTX" for a in result["audit"])
    # Missing actual terminal clocks cannot establish a completed disposition.
    f["AvailableAtSample"] = "NaN"
    dl = direction(summarize(dl=[row], feedback=[f]))
    assert dl["Terminal unavailable feedback dispositions"] == 0 and dl["Feedback pending/unavailable"] == 1


def test_presence_identity_isolated_between_cells_and_sweep_points():
    first = presence_row()
    second = dict(first, BaseStationID=2, PresenceServingCell=2)
    third = dict(first, SweepPointIndex=2)
    assert summarize(pucch=[first, second, third])["control"][0]["Completed detector decisions"] == 3
