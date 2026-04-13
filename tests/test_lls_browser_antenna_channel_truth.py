from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    artifacts = [
        {"logical_path": "reports/csv/runtime_operating_mode.csv", "artifact_id": 1, "byte_size": 256, "artifact_kind": "table_csv"},
        {"logical_path": "reports/csv/channel_array_consistency.csv", "artifact_id": 2, "byte_size": 256, "artifact_kind": "table_csv"},
        {"logical_path": "reports/csv/antenna_runtime_evidence.csv", "artifact_id": 3, "byte_size": 256, "artifact_kind": "table_csv"},
    ]
    runtime_rows = [
        {
            "Direction": "DL",
            "ChannelArrayModel": "nrtdl_runtime_geometry_correlation_channel",
            "AntennaRuntimeObjectSource": "CoupledTruthRuntime.initialize:AntennaArrayFactory.build",
            "ChannelObjectSource": "sixgr.channel.ChannelFactory.localCreateTDL",
            "ChannelObjectClass": "nrTDLChannel",
            "ChannelArrayHandlingStatus": "adapted_geometry_backed_reduced_representation",
            "ChannelArrayHandlingBlocker": "nrtdlchannel_consumes_custom_spatial_correlation_matrices_not_runtime_array_objects",
            "ChannelUsesSameRuntimeAntennaAssumptions": "0",
            "InterferenceChannelObjectSource": "sixgr.channel.ChannelFactory.localCreateTDL",
            "InterferenceChannelObjectClass": "nrTDLChannel",
            "InterferenceChannelArrayHandlingStatus": "adapted_geometry_backed_reduced_representation",
            "InterferenceChannelArrayHandlingBlocker": "nrtdlchannel_consumes_custom_spatial_correlation_matrices_not_runtime_array_objects",
            "InterferenceUsesSameRuntimeAntennaAssumptions": "0",
            "InterferencePathUsesSameArrayAssumptions": "1",
        }
    ]
    consistency_rows = [
        {
            "Direction": "DL",
            "ChannelArrayModel": "nrtdl_runtime_geometry_correlation_channel",
            "ChannelObjectSource": "sixgr.channel.ChannelFactory.localCreateTDL",
            "ChannelArrayHandlingStatus": "adapted_geometry_backed_reduced_representation",
            "InterferenceChannelArrayHandlingStatus": "adapted_geometry_backed_reduced_representation",
            "Notes": "DL uses a runtime-geometry-backed reduced TDL representation: runtime BS/UE antenna objects still feed beam/precoding context, but the active nrTDLChannel consumes custom Tx/Rx spatial correlation matrices rather than full runtime array objects, pose, element patterns, polarization, or per-path angles. Blocker: nrtdlchannel_consumes_custom_spatial_correlation_matrices_not_runtime_array_objects.",
        }
    ]
    antenna_rows = [
        {
            "Direction": "DL",
            "RuntimeAntennaObjectSource": "CoupledTruthRuntime.initialize:AntennaArrayFactory.build",
            "ChannelObjectSource": "sixgr.channel.ChannelFactory.localCreateTDL",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    try:
        def fake_load_small(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "reports/csv/runtime_operating_mode.csv":
                return runtime_rows
            if logical_path == "reports/csv/channel_array_consistency.csv":
                return consistency_rows
            if logical_path == "reports/csv/antenna_runtime_evidence.csv":
                return antenna_rows
            return []

        dash.load_small_csv_rows = fake_load_small
        run_row = {"run_id": 777, "status_text": "completed", "config_json": "{}"}
        runtime_context = dash.extract_runtime_context(run_row, artifacts)
        truth_modes = runtime_context["truth_modes"]
        assert truth_modes["channel_array_handling_status"] == "adapted_geometry_backed_reduced_representation", (
            "browser truth modes must surface the serving channel array-handling status from runtime_operating_mode.csv"
        )
        assert truth_modes["channel_array_handling_status"] != "count_only_spatial_dims_no_runtime_geometry", (
            "runtime-backed TDL evidence must not regress to the legacy count-only browser status"
        )
        assert truth_modes["channel_array_handling_blocker"] == "nrtdlchannel_consumes_custom_spatial_correlation_matrices_not_runtime_array_objects", (
            "browser truth modes must surface the exact channel-array blocker"
        )
        assert truth_modes["interference_path_uses_same_array_assumptions"] is True, (
            "browser truth modes must preserve whether the interferer channel used the same channel-array handling level"
        )
        assert truth_modes["channel_uses_same_runtime_antenna_assumptions"] is False, (
            "browser truth modes must keep serving runtime-antenna-object mismatch explicit"
        )
        assert runtime_context["channel_array_consistency_preview"][0]["ChannelArrayHandlingStatus"] == (
            "adapted_geometry_backed_reduced_representation"
        ), "browser runtime context must include the canonical channel-array consistency preview"
        assert runtime_context["channel_array_consistency_preview"][0]["ChannelArrayHandlingStatus"] != (
            "count_only_spatial_dims_no_runtime_geometry"
        ), "browser channel-array preview must stay aligned with the reduced runtime-geometry adapter"
        assert runtime_context["antenna_runtime_evidence_preview"][0]["RuntimeAntennaObjectSource"] == (
            "CoupledTruthRuntime.initialize:AntennaArrayFactory.build"
        ), "browser runtime context must include the canonical antenna runtime evidence preview"
        assert any("reduced" in note.lower() and "correlation" in note.lower() for note in runtime_context["notes"]), (
            "browser notes must explain the reduced TDL correlation boundary"
        )
        assert any("nrtdlchannel_consumes_custom_spatial_correlation_matrices_not_runtime_array_objects" in note for note in runtime_context["notes"]), (
            "browser notes must include the exact TDL array-handling blocker"
        )
        assert any("Serving and interferer channel paths used the same channel-array handling level." in note for note in runtime_context["notes"]), (
            "browser notes must explain the serving-versus-interferer channel-array relationship"
        )
    finally:
        dash.load_small_csv_rows = orig_load_small


if __name__ == "__main__":
    main()
