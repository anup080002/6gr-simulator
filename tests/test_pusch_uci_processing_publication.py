"""Declared CSV/UI fixtures only; no PHY execution or presence qualification."""
from __future__ import annotations

import copy
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_aliases as aliases
import lls_contract_materializer as materializer
import lls_output_contract as contract
import lls_web_dashboard as dashboard


PUBLIC = "reports/csv/pusch_runtime_event_table.csv"
RAW = "air_interface/csv/ul_pusch_trials.csv"
LEGACY = "reports/csv/pusch_pucch_outputs.csv"
DEFINITION = "receiver_uci_processing_applied_not_presence_or_decode_success"
SOURCE = "nrULSCHDemultiplex_nrUCIDecode_independent_receive_schema"
PUBLIC_FIELDS = ("UCIOnPUSCHFlag", "UCIOnPUSCHFlagDefinition",
                 "UCIOnPUSCHFlagSource", "UCIOnPUSCHFlagStatus")
RAW_FIELDS = ("UCIOnPUSCHApplied", "UCIOnPUSCHSource", "UCIOnPUSCHEvidenceSource")
INPUT_FIELDS = ("InputUCIOnPUSCHFlag", "InputUCIOnPUSCHFlagDefinition",
                "InputUCIOnPUSCHFlagSource", "InputUCIOnPUSCHFlagStatus")


def _roundtrip(header, rows, path=PUBLIC):
    before = copy.deepcopy((header, rows))
    data, result_header, result_rows = materializer._canonicalize_contract_source_rows(path, header, rows)
    assert (header, rows) == before
    decoded_header, decoded_rows = materializer._decode_csv(data)
    assert decoded_header == result_header and decoded_rows == result_rows
    return result_header, result_rows


@pytest.mark.parametrize("table", ["live_pusch_stage_table", "live_pusch_rx_summary"])
def test_contract_prefers_public_runtime_rows_not_legacy_descriptor(table):
    paths = aliases.CONTRACT_TABLE_ALIAS_PATHS[table]
    assert paths[0] == PUBLIC
    assert RAW in paths and paths.index(PUBLIC) < paths.index(RAW)
    lookup = {path: dict(artifact_id=index, logical_path=path, artifact_kind="table_csv")
              for index, path in enumerate((PUBLIC, RAW, LEGACY), 1)}
    payloads = {
        1: materializer._encode_csv(["Slot", *PUBLIC_FIELDS],
                                   [["9", "1", DEFINITION, SOURCE, "declared_receiver_processing"]]),
        2: materializer._encode_csv(["Slot", *RAW_FIELDS], [["9", "0", "", ""]]),
        3: materializer._encode_csv(["Descriptor"], [["declared_legacy_summary_not_receiver_proof"]]),
    }
    original = dict(payloads)
    art, data, header, rows = materializer._select_source_table_artifact(paths, lookup, payloads.__getitem__)
    assert art["logical_path"] == PUBLIC and rows[0][header.index("UCIOnPUSCHFlag")] == "1"
    assert payloads == original and len(materializer._decode_csv(data)[1]) == 1


@pytest.mark.parametrize("table", ["live_pusch_stage_table", "live_pusch_rx_summary"])
def test_present_empty_public_population_does_not_fall_through_to_historical_rows(table):
    lookup = {path: dict(artifact_id=index, logical_path=path, artifact_kind="table_csv")
              for index, path in enumerate((PUBLIC, RAW), 1)}
    payloads = {1: materializer._encode_csv(list(PUBLIC_FIELDS), []),
                2: materializer._encode_csv(["Slot", "UCIOnPUSCHApplied"], [["9", "1"]])}
    art, _, header, rows = materializer._select_source_table_artifact(
        aliases.CONTRACT_TABLE_ALIAS_PATHS[table], lookup, payloads.__getitem__)
    assert art["logical_path"] == PUBLIC and header == list(PUBLIC_FIELDS) and rows == []


@pytest.mark.parametrize("payload", [b"", b",\n", b"Slot,\n9,\n"])
def test_present_invalid_public_header_is_not_hidden_by_a_raw_fallback(payload):
    lookup = {path: dict(artifact_id=index, logical_path=path, artifact_kind="table_csv")
              for index, path in enumerate((PUBLIC, RAW), 1)}
    payloads = {1: payload, 2: b"Slot,UCIOnPUSCHApplied\n9,1\n"}
    with pytest.raises(ValueError, match="PUSCH public runtime table has no valid declared header"):
        materializer._select_source_table_artifact(
            aliases.CONTRACT_TABLE_ALIAS_PATHS["live_pusch_stage_table"], lookup, payloads.__getitem__)


@pytest.mark.parametrize("table", ["live_pusch_stage_table", "live_pusch_rx_summary"])
def test_missing_public_source_keeps_raw_source_without_manufacturing_qualified_flag(table):
    lookup = {RAW: dict(artifact_id=1, logical_path=RAW, artifact_kind="table_csv")}
    payload = materializer._encode_csv(["Slot", *RAW_FIELDS], [["9", "0", "", ""]])
    art, _, header, rows = materializer._select_source_table_artifact(
        aliases.CONTRACT_TABLE_ALIAS_PATHS[table], lookup, lambda _: payload)
    assert art["logical_path"] == RAW and rows == [["9", "0", "", ""]]
    assert header == ["Slot", *RAW_FIELDS]
    assert not set(PUBLIC_FIELDS).intersection(header)


@pytest.mark.parametrize("path", [PUBLIC, RAW, "reports/csv/live_pusch_stage_table.csv"])
@pytest.mark.parametrize("unknown", ["NaN", "", "<missing>"])
def test_unknown_flags_blank_provenance_and_legacy_plane_survive_csv(path, unknown):
    header = ["Slot", *PUBLIC_FIELDS, *RAW_FIELDS, *INPUT_FIELDS,
              "RuntimeEvidenceSource", "RuntimeMaterializationStatus"]
    row = ["9", unknown, DEFINITION, "", "unknown_receiver_processing", "0", "", "",
           unknown, "", "", "", "", ""]
    result_header, rows = _roundtrip(header, [row], path)
    assert result_header == header and rows == [row]
    assert "uci_on_pusch_present" not in result_header


def test_known_zero_and_one_unknown_mixed_rows_and_distinct_outcomes_are_lossless():
    header = ["Slot", *PUBLIC_FIELDS, *RAW_FIELDS, "CRCPass", "CSIReportDetected"]
    rows = [["19", "1", DEFINITION, SOURCE, "declared_processing", "1", SOURCE,
             "same_waveform_pusch_rx_uci_demultiplexer", "0", "0"],
            ["3", "0", DEFINITION, "no_uci_payload_requested", "declared_no_processing",
             "0", "no_uci_payload_requested", "", "1", "NaN"],
            ["11", "NaN", DEFINITION, "", "unknown_receiver_processing", "0", "", "", "NaN", "NaN"]]
    result_header, result = _roundtrip(header, rows)
    assert result_header == header and result == rows


def test_narrow_preservation_does_not_keep_unrelated_empty_measurements_or_invent_columns():
    header = ["Slot", "UCIOnPUSCHFlag", "UCIOnPUSCHFlagStatus", "UnrelatedMeasurement"]
    result_header, rows = _roundtrip(header, [["9", "NaN", "unknown_receiver_processing", "NaN"]])
    assert result_header == header[:-1] and rows == [["9", "NaN", "unknown_receiver_processing"]]
    assert not set(RAW_FIELDS).intersection(result_header)
    result_header, rows = _roundtrip(["Slot", "UnrelatedMeasurement"], [["9", "NaN"]], RAW)
    assert result_header == ["Slot"] and rows == [["9"]]


def test_contract_names_processing_separately_from_unavailable_presence_and_decode():
    specs = {item["table_name"]: item for item in contract.iter_table_specs("reports")}
    for table in ("live_pusch_stage_table", "live_pusch_rx_summary"):
        assert set(PUBLIC_FIELDS + RAW_FIELDS + INPUT_FIELDS).issubset(specs[table]["required_columns"])
    # These older vocabulary entries are NOT aliases for processing and may
    # only have values if an independent producer actually supplies them.
    assert "uci_on_pusch_present" not in materializer._ROW_FIELD_ALIASES
    assert "uci_on_pusch_decode_status" not in materializer._ROW_FIELD_ALIASES


@pytest.mark.parametrize("unknown", [float("nan"), "NaN", "", None])
def test_preview_retains_unknown_column_and_status_without_false_or_presence_claim(unknown):
    row = dict(Slot=9, UCIOnPUSCHFlag=unknown, UCIOnPUSCHFlagDefinition=DEFINITION,
               UCIOnPUSCHFlagSource="", UCIOnPUSCHFlagStatus="unknown_receiver_processing")
    out = dashboard.summarize_data_trial_preview_rows("ul_trials", [row])[0]
    labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["ul_trials"])
    assert "not presence/success" in labels["UCIOnPUSCHFlag"]
    assert out[labels["UCIOnPUSCHFlag"]] == "N/A"
    assert out[labels["UCIOnPUSCHFlagStatus"]] == "unknown_receiver_processing"
    assert out[labels["UCIOnPUSCHFlagSource"]] == "N/A"
    if isinstance(unknown, float):
        assert math.isnan(row["UCIOnPUSCHFlag"])
    else:
        assert row["UCIOnPUSCHFlag"] == unknown


def test_raw_live_preview_route_is_unchanged_and_raw_applied_never_becomes_qualified_flag():
    assert dashboard.CANONICAL_RUNTIME_ARTIFACT_OWNERS["ul_trials"] == {
        "canonical_path": RAW, "legacy_paths": [], "owner_kind": "raw_ul_trials"}
    rows = [dict(Slot=9, UCIOnPUSCHApplied=1, UCIOnPUSCHSource=SOURCE,
                 UCIOnPUSCHEvidenceSource="same_waveform_pusch_rx_uci_demultiplexer",
                 CRCPass=0, CSIReportDetected=0),
            dict(Slot=10, UCIOnPUSCHApplied=0, UCIOnPUSCHSource="", UCIOnPUSCHEvidenceSource="")]
    before = copy.deepcopy(rows)
    result = dashboard.summarize_data_trial_preview_rows("ul_trials", rows)
    labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["ul_trials"])
    assert "source required" in labels["UCIOnPUSCHApplied"]
    assert "not presence/success" in labels["UCIOnPUSCHApplied"]
    assert [row[labels["UCIOnPUSCHApplied"]] for row in result] == [1, 0]
    assert all(labels["UCIOnPUSCHFlag"] not in row for row in result)
    assert result[0]["CRC pass"] == 0 and result[0][labels["CSIReportDetected"]] == 0
    assert result[1][labels["UCIOnPUSCHSource"]] == "N/A" and rows == before


def test_scoped_legacy_fields_remain_visible_without_reinterpreting_different_plane():
    row = dict(Slot=9, UCIOnPUSCHFlag=0, UCIOnPUSCHFlagDefinition=DEFINITION,
               UCIOnPUSCHFlagSource="no_uci_payload_requested", UCIOnPUSCHFlagStatus="declared_no_processing",
               InputUCIOnPUSCHFlag=1, InputUCIOnPUSCHFlagDefinition="scheduled_reservation_not_receiver_processing",
               InputUCIOnPUSCHFlagSource="pending_dl_harq_and_or_csi_nrULSCHMultiplex")
    out = dashboard.summarize_data_trial_preview_rows("ul_trials", [row])[0]
    labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["ul_trials"])
    assert out[labels["UCIOnPUSCHFlag"]] == 0
    assert out[labels["InputUCIOnPUSCHFlag"]] == 1
    assert out[labels["InputUCIOnPUSCHFlagDefinition"]] == row["InputUCIOnPUSCHFlagDefinition"]


def test_empty_source_and_empty_preview_stay_empty():
    header, rows = _roundtrip(list(PUBLIC_FIELDS + RAW_FIELDS), [])
    assert header == list(PUBLIC_FIELDS + RAW_FIELDS) and rows == []
    assert dashboard.summarize_data_trial_preview_rows("ul_trials", []) == []


def test_version_invalidates_old_derived_aliases_not_primary_source_evidence():
    assert materializer.MATERIALIZER_VERSION != "2026-10-23-contract-v117-constellation-snr-source-roles"


@pytest.mark.parametrize("table", ["live_pusch_stage_table", "live_pusch_rx_summary"])
@pytest.mark.parametrize("population", ["public", "empty_public", "raw_only"])
def test_materialize_entry_preserves_owner_population_and_all_source_rows(tmp_path, monkeypatch, table, population):
    """Declared file fixtures through the real dispatcher; no PHY qualification."""
    raw_header = ["Slot", "ExecutionID", "SweepPointIndex", *RAW_FIELDS]
    raw_rows = [[str(index), "declared-execution", "2", "0", "", ""] for index in range(600)]
    payloads = {RAW: materializer._encode_csv(raw_header, raw_rows)}
    public_header = ["Slot", *PUBLIC_FIELDS]
    public_rows = [["9", "1", DEFINITION, SOURCE, "declared_processing"],
                   ["8", "NaN", DEFINITION, "", "unknown_receiver_processing"]]
    if population != "raw_only":
        payloads[PUBLIC] = materializer._encode_csv(public_header, public_rows if population == "public" else [])
    artifacts = []
    by_id = {}
    for index, (path, payload) in enumerate(payloads.items(), 1):
        source = tmp_path / path
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_bytes(payload)
        artifacts.append(dict(artifact_id=index, logical_path=path, artifact_kind="table_csv",
                              mime_type="text/csv", byte_size=len(payload), filesystem_path=str(source), metadata_json="{}"))
        by_id[index] = payload
    target = f"reports/csv/{table}.csv"
    monkeypatch.setattr(materializer, "_table_specs", lambda: [dict(
        table_name=table, logical_path=target, section_title="PUSCH receiver", section_slug="pusch-receiver")])
    monkeypatch.setattr(materializer, "_chart_specs", lambda: [])
    result = materializer.materialize_run_contract_artifacts(
        dict(run_id=1, run_folder=str(tmp_path), status_text="failed"), artifacts,
        fetch_artifact_bytes=by_id.__getitem__, db_connection_factory=None, feature_policy={},
        force=True, filesystem_only=True)
    header, rows = materializer._decode_csv((tmp_path / target).read_bytes())
    expected = (raw_header, raw_rows) if population == "raw_only" else (public_header, public_rows if population == "public" else [])
    assert (header, rows) == expected
    assert target not in result["coverage"]["missing_table_paths"]
    for path, payload in payloads.items():
        assert (tmp_path / path).read_bytes() == payload
