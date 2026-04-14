from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    text = (REPO_ROOT / "apps" / "lls_web_dashboard.py").read_text(encoding="utf-8")
    assert 'parsed.path != "/run"' in text
    assert 'launch_run_from_yaml(scenario_name, yaml_text, run_tag)' in text
    assert "run_6g_phy_lls_single" in text
    assert dash.DEFAULT_SCENARIO == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot.yaml"


if __name__ == "__main__":
    main()
