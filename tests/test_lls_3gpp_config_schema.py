from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    schema_path = REPO_ROOT / "configs" / "schema" / "lls_3gpp_full_config.schema.json"
    payload = json.loads(schema_path.read_text(encoding="utf-8"))
    assert payload["properties"]["scenario"]["properties"]["honesty_mode"]["const"] == "strict"
    assert payload["properties"]["run_control"]["properties"]["mode"]["const"] == "long_run"
    assert payload["properties"]["run_control"]["properties"]["total_slots"]["const"] == 4000
    assert payload["properties"]["run_control"]["properties"]["measurement_slots"]["const"] == 3500
    assert payload["properties"]["seeds"]["properties"]["global_seed"]["const"] == 104729
    assert payload["properties"]["seeds"]["properties"]["ue_placement_seed"]["const"] == 104760
    assert payload["properties"]["frequency"]["properties"]["center_frequency_hz"]["const"] == 4_000_000_000
    assert payload["properties"]["frequency"]["properties"]["bandwidth_hz"]["const"] == 100_000_000
    assert payload["properties"]["frame"]["properties"]["scs_khz"]["const"] == 30
    assert payload["properties"]["deployment_topology"]["properties"]["inter_site_distance"]["const"] == 600
    assert payload["properties"]["deployment_topology"]["properties"]["num_ues"]["const"] == 200
    assert payload["properties"]["output"]["properties"]["emit_placeholder_artifacts"]["const"] is False


if __name__ == "__main__":
    main()
