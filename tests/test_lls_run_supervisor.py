from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    runner = REPO_ROOT / "scripts" / "run_lls_3gpp_4ghz_100mhz_longrun.ps1"
    monitor = REPO_ROOT / "scripts" / "monitor_lls_run.ps1"
    validator = REPO_ROOT / "scripts" / "validate_lls_run_outputs.py"
    assert runner.is_file()
    assert monitor.is_file()
    assert validator.is_file()

    text = runner.read_text(encoding="utf-8")
    assert r"C:\Program Files\MATLAB\R2023b\bin\matlab.exe" in text
    assert "run_6g_phy_lls_single" in text
    assert "lls_3gpp_4ghz_100mhz_longrun.yaml" in text
    assert "testAll" not in text
    assert "SkipReplay" in text
    assert "MaxAttempts = 10" in text

    monitor_text = monitor.read_text(encoding="utf-8")
    assert "http://127.0.0.1:62906" in monitor_text
    assert "/api/run/$rid/live" in monitor_text

    validator_text = validator.read_text(encoding="utf-8")
    assert "placeholder artifact exposed" in validator_text
    assert "smoke artifact exposed" in validator_text
    assert "output_coverage_registry.csv" in validator_text


if __name__ == "__main__":
    main()
