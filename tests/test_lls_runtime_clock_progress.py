"""Execute the production browser clock projection, not a Python replica."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
JS = SOURCE.split("  function runtimeClockProgress(stage) {", 1)[1].split(
    "  function liveWorkspace() {", 1
)[0]
JS = "function runtimeClockProgress(stage) {" + JS


def project(stage):
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    script = JS + "\nconsole.log(JSON.stringify(runtimeClockProgress(" + json.dumps(stage) + ")));"
    result = subprocess.run([node, "-e", script], check=True, capture_output=True,
                            text=True, timeout=15)
    return json.loads(result.stdout)


def test_active_slot_is_not_completed_or_data_coverage():
    stage = dict(CurrentSlot=46, TotalSlots=100, CompletedSlots=45,
                 CompletedFrames=2, DLCompletedFrames=3, ULCompletedFrames=0,
                 DLTrialRows=4, ULTrialRows=0)
    assert project(stage) == dict(current=46, total=100, completed=45, percent=45)
    stage.update(DLCompletedFrames=999, ULCompletedFrames=999, DLTrialRows=999)
    assert project(stage)["percent"] == 45


@pytest.mark.parametrize("stage", [
    {}, {"CompletedFrames": 46, "RequestedFrames": 100},
    {"CurrentSlot": 46, "TotalSlots": 100},
    {"CurrentSlot": "NaN", "TotalSlots": "NaN"},
    {"CurrentSlot": 46, "TotalSlots": 100, "CompletedSlots": ""},
    {"CurrentSlot": 46, "TotalSlots": 100, "CompletedSlots": None},
    {"CurrentSlot": 46, "TotalSlots": 100, "CompletedSlots": True},
    {"CurrentSlot": 46, "TotalSlots": 100, "CompletedSlots": [45]},
    {"CurrentSlot": 46, "TotalSlots": 100, "CompletedSlots": 45.5},
    {"CurrentSlot": 46, "TotalSlots": 100, "CompletedSlots": 47},
    {"CurrentSlot": 101, "TotalSlots": 100, "CompletedSlots": 100},
    {"CurrentSlot": 0, "TotalSlots": 0, "CompletedSlots": 0},
])
def test_missing_or_inconsistent_evidence_is_not_a_progress_percentage(stage):
    assert project(stage)["percent"] is None


@pytest.mark.parametrize("done,percent", [(0, 0), (45, 45), (100, 100)])
def test_csv_numeric_strings_are_supported(done, percent):
    assert project(dict(CurrentSlot="100", TotalSlots="100", CompletedSlots=str(done)))["percent"] == percent


def test_browser_labels_separate_clock_trials_and_acceptance():
    ui = SOURCE.split("  function liveWorkspace() {", 1)[1].split("  function sweepProgressPanel", 1)[0]
    assert "runtimeClockProgress(stage)" in ui
    assert "clock.completed !== null ? (stageValue('CompletedFrames')" in ui
    assert "stageValue('CurrentSlot','SlotIndex','CompletedFrames')" not in ui
    assert "Radio slots processed" in ui and "DL / UL trial rows" in ui
    assert "saved restart checkpoint" in ui and "final scenario acceptance" in ui
    assert "scheduled slots reached" not in ui
