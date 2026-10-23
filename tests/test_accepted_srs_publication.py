"""UI projection tests; authored rows are not waveform qualification."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dashboard


def render_admission(record):
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    renderer = source[source.index("  function realtimeSchedulerAdmission("):
                      source.index("  function realtimeULPlanningPanel(")]
    script = "const esc=x=>String(x).replaceAll('<','&lt;');\n" + renderer
    script += "\nconsole.log(realtimeSchedulerAdmission(" + json.dumps({"scheduler_admission": {"UL": record}}) + "));"
    return subprocess.run([node, "-e", script], capture_output=True, text=True,
                          encoding="utf-8", check=True, timeout=15).stdout


def test_accepted_A_raw_B_and_scheduled_SRI_have_separate_UI_identity_and_age():
    row = dict(SweepPointIndex=2, ConfiguredSNR_dB=10, ControlSlot=30,
               ScheduledDataSlot=35, SchedulingKnowledgeSlot=30,
               SRSCausalUsable=1, SRSCausalStatus="available", RawSRSMeasurementID="raw-B",
               AcceptedSRSMeasurementID="accepted-A", AcceptedSRSProducerSlot=10,
               AcceptedSRSAvailableSlot=11, AcceptedSRSRI=1, AcceptedSRSTPMI=0,
               AcceptedSRSCausalUsable=0, AcceptedSRSCausalAgeSlots=20,
               AcceptedSRSCausalStatus="stale", ScheduledSRI=9, CandidateRank=1)
    html = render_admission(row)
    for label, value in (("Newest raw SRS measurement", "raw-B"),
                         ("Accepted spatial source measurement", "accepted-A"),
                         ("Accepted source TPMI", "0"),
                         ("Accepted source usable at decision", "0"),
                         ("Accepted source age (slots)", "20"),
                         ("Accepted source status", "stale"),
                         ("Scheduled SRI (separate association)", "9")):
        assert f"{label}</th><td>{value}</td>" in html
    assert "Fresh raw sounding does not refresh an older accepted decision" in html
    assert "not current queue state or proof of received DCI/data" in html


def test_missing_accepted_history_is_not_replaced_by_fresh_raw_source():
    html = render_admission(dict(SRSCausalUsable=1, RawSRSMeasurementID="raw-B", CandidateRank=1))
    assert "Accepted spatial source measurement</th><td>—</td>" in html
    assert "Accepted source usable at decision</th><td>—</td>" in html
    assert "Accepted source TPMI</th><td>—</td>" in html


def test_UL_preview_preserves_accepted_source_and_raw_receiver_scope():
    # The live route uses the data-preview registry for PUSCH, not the
    # separate control/reference registry used by the raw SRS preview.
    columns = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["ul_trials"])
    assert columns["AcceptedSRSMeasurementID"] == "Accepted spatial source measurement ID"
    assert columns["RawSRSMeasurementID"] == "Newest raw SRS measurement ID"
    assert columns["AcceptedSRSTPMI"] == "Accepted source TPMI"
    assert columns["ScheduledSRI"] == "Scheduled SRI (separate resource association)"
    assert "AcceptedSRSSpatialDecisionSHA256" in columns and "FrozenGrantContextId" in columns
    preview = dashboard.summarize_data_trial_preview_rows("ul_trials", [dict(
        AcceptedSRSMeasurementID="accepted-A", RawSRSMeasurementID="raw-B",
        AcceptedSRSTPMI=0, AcceptedSRSCausalUsable=0, ScheduledSRI=9,
        FrozenGrantContextId="grant-A")])[0]
    assert preview["Accepted spatial source measurement ID"] == "accepted-A"
    assert preview["Newest raw SRS measurement ID"] == "raw-B"
    assert preview["Accepted source TPMI"] == 0
    assert preview["Accepted source usable at decision"] == 0
    assert preview["Scheduled SRI (separate resource association)"] == 9
    raw_columns = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["srs_trials"])
    assert raw_columns["MeasurementId"] == "Raw SRS measurement ID"
    assert "AcceptedSRSMeasurementID" not in raw_columns
