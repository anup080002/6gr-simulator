from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    runner = REPO_ROOT / "scripts" / "run_lls_from_web_gui_equivalent.ps1"
    monitor = REPO_ROOT / "scripts" / "monitor_lls_run.ps1"
    validator = REPO_ROOT / "scripts" / "validate_lls_run_outputs.py"
    assert runner.is_file()
    assert monitor.is_file()
    assert validator.is_file()

    text = runner.read_text(encoding="utf-8")
    assert "/login" in text
    assert "/run" in text
    assert "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame.yaml" in text
    assert "Invoke-WebRequest" in text
    assert "MaxAttempts = 10" in text
    assert "LookupTimeoutSec = 180" in text
    assert "/api/runs?run_tag=" in text
    assert "Resolved run_id" in text

    monitor_text = monitor.read_text(encoding="utf-8")
    assert "dashboard_listener.json" in monitor_text
    assert "SIXGR_DASHBOARD_BASE_URL" in monitor_text
    assert "http://127.0.0.1:62906" in monitor_text
    assert "/api/run/$rid/live" in monitor_text
    assert "[string]$RunTag = \"\"" in monitor_text
    assert "RequestTimeoutSec = 180" in monitor_text
    assert "/api/runs?run_tag=" in monitor_text
    assert "limit=25" in monitor_text

    validator_text = validator.read_text(encoding="utf-8")
    assert "placeholder artifact exposed" in validator_text
    assert "smoke artifact exposed" in validator_text
    assert "output_coverage_registry.csv" in validator_text


if __name__ == "__main__":
    main()
