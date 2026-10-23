"""Declared renderer/CSV fixtures only; no simulated receiver performance."""
import csv
import io
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


PATH = "air_interface/csv/ul_constellation_samples.csv"
DFT = "pre_transform_qam_positions"
KEY_DOMAIN = "native_pre_transform_allocation_position_key"
CHARTS = ["post-equalization constellation", "pre-equalization constellation",
          "constellation per layer", "constellation per codeword", "constellation per modulation order"]


def declared_row(domain="dft"):
    row = dict(Direction="UL", UEIndex="1", Frame="1", Slot="5", TBId="declared-tb",
               SampleIndex="1", LayerIndex="1", CodewordIndex="0", Modulation="256QAM",
               SourceRunID="declared-run", ExecutionID="declared-execution", Seed="41",
               SweepPointIndex="2", ConfiguredSNR_dB="10", RawEqualizedReal="0.2", RawEqualizedImag="0.3",
               ReceivedReal="0.4", ReceivedImag="0.6", ReferenceSymbolReal="0.1", ReferenceSymbolImag="0.1",
               CaptureScope="full_allocation_paired_symbols", CapturedSymbolCount="1", ObservationSymbolCount="1")
    if domain != "legacy":
        row.update(OFDMSymbolIndex="3", SubcarrierIndex="NaN" if domain == "dft" else "7",
                   SymbolCoordinateDomain=DFT if domain == "dft" else "layer_resource_elements",
                   SymbolOrderLinearIndex="135",
                   SymbolOrderLinearIndexDomain=KEY_DOMAIN if domain == "dft" else "layer_grid_linear_index")
    return row


def render(rows, chart="post-equalization constellation"):
    fields = list(dict.fromkeys(field for row in rows for field in row))
    payload = m._encode_dict_rows(fields, rows)
    return m._specialized_chart_materialization(chart, {PATH: {"artifact_id": 1}}, lambda _: payload, 17)


def output(result):
    return list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))


def panels(result):
    return [element for element in ET.fromstring(result["img_bytes"]).findall("{http://www.w3.org/2000/svg}rect")
            if element.attrib.get("width") == "320"]


@pytest.mark.parametrize("chart", CHARTS)
@pytest.mark.parametrize("domain", ["cp", "dft", "legacy"])
def test_scatter_keeps_native_coordinate_tokens_without_inventing_legacy_map(chart, domain):
    row = declared_row(domain)
    original = dict(row)
    result = render([row], chart)
    actual = output(result)[0]
    for source, target in (("SymbolCoordinateDomain", "symbol_coordinate_domain"),
                           ("SymbolOrderLinearIndex", "symbol_order_linear_index"),
                           ("SymbolOrderLinearIndexDomain", "symbol_order_linear_index_domain"),
                           ("OFDMSymbolIndex", "ofdm_symbol_index"), ("SubcarrierIndex", "subcarrier_index"),
                           ("ObservationSymbolCount", "observation_symbol_count"),
                           ("CapturedSymbolCount", "captured_symbol_count")):
        assert actual[target] == row.get(source, "")
    assert row == original and result["source_row_count"] == 1
    assert actual["source_row_index"] == "1" and actual["source_table_logical_path"] == PATH
    assert float(actual.get("x_value", actual.get("EqualizedReal"))) == (0.4 if chart.startswith("pre-") else 0.2)
    assert b"coordinate domain not retained" in result["img_bytes"] if domain == "legacy" else True
    assert "not scatter-reader completeness qualification" in result["note"]


@pytest.mark.parametrize("change", [
    {"SymbolCoordinateDomain": ""}, {"SymbolCoordinateDomain": "unknown"},
    {"SymbolCoordinateDomain": "layer_resource_elements"},
    {"SymbolOrderLinearIndexDomain": ""}, {"SymbolOrderLinearIndexDomain": "layer_grid_linear_index"},
    {"SymbolOrderLinearIndex": ""}, {"SymbolOrderLinearIndex": "NaN"},
    {"SubcarrierIndex": "1"}, {"SubcarrierIndex": "garbage"},
    {"OFDMSymbolIndex": "NaN"}, {"LayerIndex": "0"},
])
def test_scatter_refuses_mislabeled_native_coordinate_evidence(change):
    with pytest.raises(ValueError, match="coordinate|position"):
        render([{**declared_row(), **change}])


@pytest.mark.parametrize("field,exported", [
    ("SourceRunID", "source_run_id"), ("RunID", "input_run_id"),
    ("ExecutionID", "execution_id"), ("ConfigHash", "config_hash"),
    ("Seed", "seed"), ("RandomSeed", "random_seed"), ("ChannelSeed", "channel_seed"),
    ("SourceRandomSeed", "source_random_seed"), ("PreparedRandomSeed", "prepared_random_seed"),
    ("SweepPointIndex", "sweep_point_index"), ("DropIndex", "drop_index"),
    ("RealizationIndex", "realization_index"),
    ("SweepAggregatePointIndex", "sweep_aggregate_point_index"),
])
def test_same_snr_coordinates_in_distinct_supplied_cohorts_have_distinct_panels(field, exported):
    rows = [{**declared_row(), field: value, "RawEqualizedReal": str(index / 10)}
            for index, value in enumerate(("1", "2"), 1)]
    result = render(rows)
    actual = output(result)
    assert len(actual) == 2 and len(panels(result)) == 2
    assert {row[exported] for row in actual} == {"1", "2"}
    assert [float(row["x_value"]) for row in actual] == [0.1, 0.2]
    assert len({row["cohort_domain_scope_identity"] for row in actual}) == 2


def test_wrapper_scope_never_becomes_missing_physical_population():
    rows = []
    for point in (1, 2):
        row = declared_row()
        for field in ("SourceRunID", "ExecutionID", "Seed", "SweepPointIndex", "ConfiguredSNR_dB"):
            row.pop(field)
        row.update(SweepAggregatePointIndex=str(point), SweepAggregateConfiguredSNR_dB=str(point * 10),
                   SweepAggregateSourceCSV=f"sweeps/declared-{point}/samples.csv")
        rows.append(row)
    result = render(rows)
    assert len(panels(result)) == 2
    for row in output(result):
        assert all(row[field] == "" for field in ("source_run_id", "execution_id", "seed", "sweep_point_index", "configured_snr_db"))
        assert row["sweep_aggregate_source_csv"].startswith("sweeps/declared-")
    assert "wrapper provenance" in result["note"]


def test_public_container_run_does_not_overwrite_explicit_missing_source_run():
    result = render([{**declared_row(), "SourceRunID": "", "RunID": "container-123"}])
    row = output(result)[0]
    assert row["run_id"] == "17" and row["input_run_id"] == "container-123"
    assert row["source_run_id"] == ""


def test_mixed_cp_dft_legacy_and_capture_scopes_keep_all_rows_and_panels():
    rows = [declared_row(domain) for domain in ("cp", "dft", "legacy")]
    rows += [{**declared_row(), "CaptureScope": scope} for scope in ("paired_sample_preview", "")]
    result = render(rows)
    assert result["source_row_count"] == 5 and len(output(result)) == 5 and len(panels(result)) == 5
    assert {row["symbol_coordinate_domain"] for row in output(result)} == {"", DFT, "layer_resource_elements"}
    assert b"coordinate domain not retained" in result["img_bytes"]
    visible_text = " ".join(ET.fromstring(result["img_bytes"]).itertext())
    assert "capture scope not retained" in visible_text  # Labels wrap across SVG text nodes.
    png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
    assert png.startswith(b"\x89PNG\r\n\x1a\n")


def test_all_samples_stay_in_csv_with_only_explicit_image_preview():
    rows = [{**declared_row(), "SampleIndex": str(index), "SymbolOrderLinearIndex": str(100 + index),
             "ObservationSymbolCount": "601", "CapturedSymbolCount": "601"}
            for index in range(1, 602)]
    result = render(rows)
    actual = output(result)
    assert len(actual) == 601 and result["source_row_count"] == 601
    assert [row["symbol_order_linear_index"] for row in actual] == [str(100 + index) for index in range(1, 602)]
    assert result["img_bytes"].count(b'fill-opacity="0.72"') == 450
    assert b"Preview: up to 450 samples/panel" in result["img_bytes"]


@pytest.mark.parametrize("field,values", [
    ("ExecutionID", ["execution-A", "execution-B"]),
    ("Seed", ["41", "42"]),
    ("CaptureScope", ["full_allocation_paired_symbols", "paired_sample_preview"]),
])
def test_symbol_error_histogram_uses_the_exact_scatter_cohort_without_changing_errors(field, values):
    rows = [{**declared_row(), field: value, "RawEqualizedReal": str(0.2 + index / 10)}
            for index, value in enumerate(values)]
    result = render(rows, "symbol decision error histogram")
    actual = output(result)
    assert len(actual) == 2
    assert {int(row["population_sample_count"]) for row in actual} == {1}
    assert len({row["cohort_domain_scope_identity"] for row in actual}) == 2
    assert [float(row["decision_error_magnitude"]) for row in actual] == pytest.approx([5**0.5 / 10, 8**0.5 / 10])


def test_retained_capture_and_clock_identity_is_not_derived_from_plot_row_index():
    row = {**declared_row(), "ObservationID": "obs-actual-token", "ReceiverWindowID": "window-7",
           "ReceiverClockDomain": "declared-clock", "ReceiverClockEpoch": "5",
           "ObservationStartSample": "111", "ObservationEndSampleExclusive": "222",
           "ObservationSampleRateHz": "15360000", "ReceiverObservationSHA256": "a" * 64}
    actual = output(render([row]))[0]
    assert actual["observation_id"] == "obs-actual-token" and actual["receiver_window_id"] == "window-7"
    assert actual["observation_start_sample"] == "111" and actual["receiver_clock_epoch"] == "5"
    assert actual["receiver_observation_sha256"] == "a" * 64
    assert json.loads(actual["cohort_domain_scope_identity"])["execution_id"] == row["ExecutionID"]
