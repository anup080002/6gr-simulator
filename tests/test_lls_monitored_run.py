from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    script = REPO_ROOT / "scripts" / "run_monitored_lls_scenario.ps1"
    assert script.is_file()

    text = script.read_text(encoding="utf-8")
    assert "run_6g_phy_lls_single" in text
    assert "monitor_lls_run.ps1" in text
    assert "RUNNING.status.json" in text
    assert "live_stage_progress.csv" in text
    assert "runtime_issue_trace.csv" in text
    assert "runtime_artifact_generation_trace.csv" in text
    assert "live_dl_scheduler_grants.csv" in text
    assert "live_ul_scheduler_grants.csv" in text
    assert "slot_trace.csv" in text
    assert "live_tx_rx_stage_trace.csv" in text
    assert "live_channel_estimation_tti.csv" in text
    assert "live_channel_state_tti.csv" in text
    assert "live_modulation_demodulation_trace.csv" in text
    assert "Start-Process" in text
    assert "CodexMonitoredRunFolder" in text
    assert "Get-SixGRMonitoredTerminalVerdict" in text
    assert "scenario_summary.csv" in (REPO_ROOT / "scripts" / "lib" / "monitored_run_verdict.ps1").read_text(encoding="utf-8")
    assert "$processFailed -or -not $terminalVerdict.Ok" in text


if __name__ == "__main__":
    main()
