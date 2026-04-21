from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    resolved, _ = dash.load_resolved_config_payload(dash.DEFAULT_SCENARIO)
    assert int(dash.path_get(resolved, "deployment_topology.num_ues", 0)) == 200
    assert int(dash.path_get(resolved, "users.n_users", 0)) == 200
    assert str(dash.path_get(resolved, "traffic.model", "")) == "fullBuffer"
    assert str(dash.path_get(resolved, "traffic.transport", "")) == "UDP"
    assert int(dash.path_get(resolved, "run_control.total_slots", 0)) == 20
    assert int(dash.path_get(resolved, "run_control.warmup_slots", 0)) == 10
    assert int(dash.path_get(resolved, "run_control.measurement_slots", 0)) == 1
    assert str(dash.path_get(resolved, "channel_model.scenario_label", "")) == "CDL-D"


if __name__ == "__main__":
    main()
