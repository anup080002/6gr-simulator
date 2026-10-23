"""Declared serialization/arithmetic fixtures, not waveform or NR qualification."""
import csv
import io
import math
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


PATH = "air_interface/csv/ul_constellation_samples.csv"
DFT = "pre_transform_qam_positions"
KEY_DOMAIN = "native_pre_transform_allocation_position_key"


def declared_rows():
    rows = []
    for layer in (1, 2):
        for symbol in (3, 5):
            for position in (1, 2):
                index = len(rows) + 1
                rows.append({
                    "Direction": "UL", "UEIndex": "1", "Frame": "2", "Slot": "8",
                    "TBId": "declared-format-tb", "LayerIndex": str(layer), "CodewordIndex": "0",
                    "OFDMSymbolIndex": str(symbol), "SubcarrierIndex": "NaN",
                    "SymbolCoordinateDomain": DFT, "SymbolOrderLinearIndexDomain": KEY_DOMAIN,
                    "SymbolOrderLinearIndex": str(100 * layer + 10 * symbol + position),
                    "SampleIndex": str(index), "ObservationSymbolCount": "8", "CapturedSymbolCount": "8",
                    "CaptureScope": "full_allocation_paired_symbols",
                    "RawEqualizedReal": str(1 + index / 10), "RawEqualizedImag": "0",
                    "ReferenceSymbolReal": "1", "ReferenceSymbolImag": "0",
                    "SweepPointIndex": "1", "ConfiguredSNR_dB": "10", "Seed": "41",
                    "SourceRunID": "declared-format-run", "ObservationID": "declared-format-observation",
                })
    return rows


def render(rows, chart="PUSCH EVM per symbol"):
    fields = list(dict.fromkeys(field for row in rows for field in row))
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fields)
    writer.writeheader()
    writer.writerows(rows)
    payload = stream.getvalue().encode()
    return m._specialized_chart_materialization(chart, {PATH: {"artifact_id": 1}}, lambda _: payload, 17)


def plotted(result):
    return list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))


@pytest.mark.parametrize("chart", ["PUSCH EVM per symbol", "EVM per layer"])
@pytest.mark.parametrize("subcarrier", ["NaN", "", None])
def test_full_dft_symbol_and_layer_profiles_keep_exact_counts_and_energy(chart, subcarrier):
    rows = declared_rows()
    for row in rows:
        if subcarrier is None:
            row.pop("SubcarrierIndex")  # Actual CSV pruning may remove an all-NaN column.
        else:
            row["SubcarrierIndex"] = subcarrier
    before = [dict(row) for row in rows]
    result = render(rows, chart)
    assert result["csv_status"] == "specialized_runtime_evm_dataset"
    output = plotted(result)
    assert len(output) == (4 if chart.endswith("symbol") else 2)
    assert sum(int(row["sample_count"]) for row in output) == 8
    assert sum(float(row["error_energy"]) for row in output) == pytest.approx(sum((i / 10)**2 for i in range(1, 9)))
    for row in output:
        selected = [source for source in rows if source["LayerIndex"] == row["layer_index"]
                    and (not chart.endswith("symbol") or source["OFDMSymbolIndex"] == row["OFDMSymbolIndex"])]
        expected = 100 * math.sqrt(sum((float(source["RawEqualizedReal"]) - 1)**2 for source in selected) / len(selected))
        assert float(row["rms_evm_pct"]) == pytest.approx(expected)
        assert row["symbol_coordinate_domain"] == DFT
        assert row["symbol_order_linear_index_domain"] == KEY_DOMAIN
        assert row["measurement_scope"] == "full_allocation_paired_symbols"
    assert rows == before
    assert b"pre-transform QAM positions" in result["img_bytes"]
    assert b"scope=full paired allocation" in result["img_bytes"]


@pytest.mark.parametrize("change", [
    {"SymbolCoordinateDomain": ""}, {"SymbolCoordinateDomain": "made_up"},
    {"SymbolCoordinateDomain": "layer_resource_elements"},
    {"SymbolOrderLinearIndexDomain": ""}, {"SymbolOrderLinearIndexDomain": "layer_grid_linear_index"},
    {"SymbolOrderLinearIndex": ""}, {"SymbolOrderLinearIndex": "NaN"},
    {"SymbolOrderLinearIndex": "0"}, {"SymbolOrderLinearIndex": "1.5"},
    {"SymbolOrderLinearIndex": str(2**53)},
    {"OFDMSymbolIndex": "NaN"}, {"OFDMSymbolIndex": "0"},
    {"LayerIndex": ""}, {"LayerIndex": "1.5"},
    {"SubcarrierIndex": "1"}, {"SubcarrierIndex": "Inf"}, {"SubcarrierIndex": "arbitrary"},
    {"ObservationSymbolCount": "9"}, {"CapturedSymbolCount": "7"},
    {"SampleIndex": "9"}, {"CaptureScope": "paired_sample_preview"},
])
def test_full_dft_rejects_missing_or_mislabeled_domain_position_and_coverage(change):
    rows = declared_rows()
    rows[0].update(change)
    assert render(rows)["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("defect", ["native_duplicate", "sample_duplicate", "missing_row"])
def test_full_dft_rejects_duplicate_or_missing_rows(defect):
    rows = declared_rows()
    if defect == "native_duplicate":
        # Duplicate position must reject even when both accompanying coordinates differ.
        rows[-1]["SymbolOrderLinearIndex"] = rows[0]["SymbolOrderLinearIndex"]
    elif defect == "sample_duplicate":
        rows[-1]["SampleIndex"] = rows[0]["SampleIndex"]
    else:
        rows.pop()
    assert render(rows)["csv_status"] == "unavailable_exact_reason"


def test_full_dft_does_not_become_a_physical_subcarrier_profile():
    assert render(declared_rows(), "EVM per subcarrier")["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("source,exported", [
    ("SweepPointIndex", "sweep_point_index"), ("Seed", "seed"),
    ("ObservationID", "observation_id"), ("ExecutionID", "execution_id"),
    ("ReceiverWindowID", "receiver_window_id"), ("ChannelSeed", "channel_seed"),
])
def test_native_positions_can_repeat_only_across_complete_distinct_observations(source, exported):
    rows = [{**row, source: identity} for identity in ("1", "2") for row in declared_rows()]
    result = render(rows)
    assert result["csv_status"] == "specialized_runtime_evm_dataset"
    output = plotted(result)
    assert sum(int(row["sample_count"]) for row in output) == 16
    assert {row[exported] for row in output} == {"1", "2"}
    assert len(output) == 8


@pytest.mark.parametrize("source", ["SweepPointIndex", "Seed", "ObservationID", "ReceiverWindowID"])
def test_partial_dft_observations_do_not_fill_each_others_coverage(source):
    rows = [{**row, source: str(1 + index % 2)} for index, row in enumerate(declared_rows())]
    assert render(rows)["csv_status"] == "unavailable_exact_reason"


def cp_rows():
    rows = declared_rows()
    for index, row in enumerate(rows):
        row.update(SymbolCoordinateDomain="layer_resource_elements",
                   SymbolOrderLinearIndexDomain="layer_grid_linear_index",
                   SubcarrierIndex=str(1 + index % 2), ObservationID="declared-cp-observation")
    return rows


@pytest.mark.parametrize("subcarrier", ["", "NaN", "Inf", "0", "1.5"])
def test_cp_still_requires_valid_physical_re_coordinates(subcarrier):
    rows = cp_rows()
    rows[0]["SubcarrierIndex"] = subcarrier
    assert render(rows)["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("defect", ["missing_key", "missing_domain", "duplicate_key"])
def test_cp_cannot_contradict_its_optional_retained_native_map(defect):
    rows = cp_rows()
    if defect == "missing_key":
        rows[0]["SymbolOrderLinearIndex"] = ""
    elif defect == "missing_domain":
        rows[0]["SymbolOrderLinearIndexDomain"] = ""
    else:
        rows[-1]["SymbolOrderLinearIndex"] = rows[0]["SymbolOrderLinearIndex"]
    assert render(rows)["csv_status"] == "unavailable_exact_reason"


def test_distinct_cp_and_dft_captures_keep_separate_labels_and_energy_buckets():
    result = render([*declared_rows(), *cp_rows()])
    assert result["csv_status"] == "specialized_runtime_evm_dataset"
    output = plotted(result)
    assert len(output) == 8 and sum(int(row["sample_count"]) for row in output) == 16
    assert {row["symbol_coordinate_domain"] for row in output} == {DFT, "layer_resource_elements"}
    assert b"pre-transform QAM positions" in result["img_bytes"]
    assert b"layer resource elements" in result["img_bytes"]


def test_dft_preview_never_acquires_full_allocation_coverage():
    rows = declared_rows()[:3]
    for row in rows:
        row["CaptureScope"] = "paired_sample_preview"
    result = render(rows)
    assert result["csv_status"] == "specialized_runtime_evm_dataset"
    assert {row["measurement_scope"] for row in plotted(result)} == {"persisted_paired_sample_subset"}
    assert b"scope=full paired allocation" not in result["img_bytes"]
