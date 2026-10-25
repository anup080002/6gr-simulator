"""Original lifecycle values only; no manufactured stage durations."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


def test_lifecycle_terminal_scope_and_original_elapsed_remain_distinct():
    rows = [{"StageName": "Msg1", "CompleteFlag": 0, "ProcedureDelay_ms": "NaN",
             "EventElapsed_ms": 0.5, "PlaceholderFlag": 0, "FallbackFlag": 0},
            {"StageName": "SetupComplete", "CompleteFlag": 1, "ProcedureDelay_ms": 12.5,
             "EventElapsed_ms": 1.0, "PlaceholderFlag": 0, "FallbackFlag": 0}]
    projected = dash.summarize_procedure_preview_rows("initial_access_lifecycle", rows)
    assert projected[0]["Access completion event"] == 0
    assert projected[1]["Access completion event"] == 1
    assert projected[0]["Inclusive access span (ms)"] == "N/A"
    assert projected[1]["Inclusive access span (ms)"] == 12.5
    assert [r["Event-to-event elapsed (ms)"] for r in projected] == [0.5, 1.0]
    assert all(r["Placeholder"] == 0 and r["Fallback"] == 0 for r in projected)
    missing = dash.summarize_procedure_preview_rows("initial_access_lifecycle", [{"StageName": "Msg1"}])[0]
    assert "Event-to-event elapsed (ms)" not in missing or missing["Event-to-event elapsed (ms)"] is None


def test_visible_lifecycle_help_does_not_promise_per_stage_duration():
    source = (Path(__file__).resolve().parents[1] / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
    table = next(line for line in source.splitlines() if "{id:'rrc_attach'" in line)
    assert "Access completion event" in table and "Inclusive access span (ms)" in table
    assert "terminal-only" in table and "not a measured per-stage duration" in table


def test_prach_sync_retains_original_scoring_reference_without_cfo_inference():
    row = {"TimingEstimateSource": "nrPRACHDetect_measured_round_trip_relative_gnb_common_offset_window",
           "RawTimingEstimate_samples": 321, "TimingOffsetSamples": 6,
           "TrueTimingOffset_samples": 3, "TimingReferenceSource": "original_clock_reference",
           "TimingError_samples": 3, "TimingAdvanceCommand": 1,
           "TimingAdvanceRole": "proposed_RAR_command", "Status": "PASS", "CFOApplied": 1}
    projected = dash.summarize_procedure_preview_rows("msg1_detection", [row])[0]
    assert projected["Scoring reference timing (samples)"] == 3
    assert projected["Timing source"] == row["TimingEstimateSource"]
    assert projected["TA role"] == row["TimingAdvanceRole"]
    assert "Detected frequency offset Hz" not in projected
    source = (Path(__file__).resolve().parents[1] / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
    mapping = source.split("const ulSynchronizationRows = [", 1)[1].split("...recent(controlPreviews.srs_trials)", 1)[0]
    assert "row['Scoring reference timing (samples)']" in mapping
    assert "row['Timing reference source']" in mapping and "row['Timing source']" in mapping
    assert "row['TA role']" in mapping and "Status:row.Status" in mapping
    assert "CFOApplied" not in mapping and "400" not in mapping


def test_original_endpoint_cfo_is_not_net_or_inferred_from_applied_flag():
    import json
    row = {"Slot": 30, "UEID": 1, "CFOApplied": 1, "InjectedCFO_Hz": "NaN",
           "TxRFEndpointMetadataJSON": json.dumps({"InjectedCFO_Hz": 0, "CFOApplied": False}),
           "RxRFEndpointMetadataJSON": json.dumps({"InjectedCFO_Hz": 400, "CFOApplied": True})}
    projected = dash.summarize_control_trial_preview_rows("prach_trials", [row])[0]
    assert projected["TX RF injected CFO (Hz)"] == 0
    assert projected["RX RF injected CFO (Hz)"] == 400
    assert "not_net_or_measured" in projected["RX RF CFO evidence"]
    assert not dash.rf_endpoint_cfo_preview({"CFOApplied": 1})
    row["RxRFInjectedCFO_Hz"] = 300
    assert "conflicting" in dash.rf_endpoint_cfo_preview(row)["RX RF CFO evidence"]
    assert "RX RF injected CFO (Hz)" not in dash.rf_endpoint_cfo_preview(row)
    row["RxRFEndpointMetadataJSON"] = '{"InjectedCFO_Hz":true}'
    assert "malformed" in dash.rf_endpoint_cfo_preview(row)["RX RF CFO evidence"]
