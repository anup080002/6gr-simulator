"""Original published-row contracts; plotting checks are not PHY qualification."""
import hashlib
import json
import math
from unittest.mock import patch

import matplotlib.pyplot as plt
import pytest

import test_lls_nmse_population_sweep as fixtures

report = fixtures.report


def plot(tmp_path, progress, values):
    fig, ax = plt.subplots(figsize=(10, 5.8))
    with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
        report._plot_standardized_metric(tmp_path / "declared.png", progress, values, "Declared", "dB")
    return fig, ax


@pytest.mark.parametrize("count", [2, 15])
def test_legacy_resource_plane_values_never_averaged_or_connected(tmp_path, count):
    rows = []
    for index in range(count):
        item = fixtures.row(-80-index)
        item.update(MetricKey="csi_rsrp", Entity="CSI-RSRP", Availability="observed",
                    SourceArtifact=f"air_interface/csv/resource_{index}.csv",
                    Notes=f"original plane/resource {index}")
        rows.append(item)
    path, progress = fixtures.source(tmp_path, rows)
    original = path.read_bytes()
    _, values = report.standardized_measurement_rows(progress)
    fig, ax = plot(tmp_path, progress, values)
    assert len(ax.lines) == count
    assert sorted(float(line.get_ydata()[0]) for line in ax.lines) == sorted(-80-index for index in range(count))
    assert all(line.get_linestyle() == "None" for line in ax.lines)
    assert not ax.collections  # No pooled min/max band or population scatter.
    assert path.read_bytes() == original
    plt.close(fig)


def test_valid_exact_original_series_breaks_missing_planned_point(tmp_path):
    points = []
    original_files = []
    for index, snr in enumerate([0, 10, 20], 1):
        item = fixtures.with_series(fixtures.row(-10-index, metadata=json.dumps({"RandomSeed": 7, "ConfiguredSNR_dB": snr})))
        if index == 2:
            item.update(Availability="not_available", CountsTowardCoverage="0", ValueNumeric="")
        path, progress = fixtures.source(tmp_path / f"p{index}", [item])
        original_files.append((path, path.read_bytes()))
        progress["points"][0].update(index=index, configured_snr_db=snr)
        points.extend(progress["points"])
    progress = dict(points=points)
    availability, values = report.standardized_measurement_rows(progress)
    assert len(availability) == 3 and len(values) == 2
    assert all(report._validated_measurement_series(value) for value in values)
    fig, ax = plot(tmp_path, progress, values)
    assert len(ax.lines) == 1
    assert list(ax.lines[0].get_xdata())[::2] == [0, 20]
    assert math.isnan(ax.lines[0].get_xdata()[1]) and math.isnan(ax.lines[0].get_ydata()[1])
    assert [value["ValueNumeric"] for value in values] == [-11, -13]
    assert all(path.read_bytes() == original for path, original in original_files)
    plt.close(fig)


@pytest.mark.parametrize("mutation", ["digest", "json", "scope", "support", "count", "source", "duplicate_json"])
def test_untrusted_explicit_series_remains_original_markers(tmp_path, mutation):
    points = []
    for index in (1, 2):
        item = fixtures.with_series(fixtures.row(-index, metadata=json.dumps({"RandomSeed": 7, "ConfiguredSNR_dB": index})))
        key = json.loads(item["PopulationSeriesJSON"])
        if mutation == "digest":
            item["PopulationSeriesID"] = "0" * 64
        elif mutation == "json":
            item["PopulationSeriesJSON"] = "not JSON"
        elif mutation == "scope":
            key["PopulationJSON"] = '{"RandomSeed":999}'
        elif mutation == "support":
            key["SupportConfigurationJSON"] = '{"Layers":4}'
        elif mutation == "count":
            key["ComparedValues"] = "48"
        elif mutation == "source":
            item["SourceArtifact"] = "unknown.csv"
            item["Availability"] = "observed"
        elif mutation == "duplicate_json":
            item["PopulationSeriesJSON"] = item["PopulationSeriesJSON"][:-1] + ',"Signal":"TRS"}'
        if mutation in {"scope", "support", "count"}:
            item["PopulationSeriesJSON"] = json.dumps(key, separators=(",", ":"))
        if mutation != "digest":
            item["PopulationSeriesID"] = hashlib.sha256(item["PopulationSeriesJSON"].encode()).hexdigest()
        path, progress = fixtures.source(tmp_path / str(index), [item])
        progress["points"][0].update(index=index, configured_snr_db=index)
        points.extend(progress["points"])
    progress = dict(points=points)
    _, values = report.standardized_measurement_rows(progress)
    assert len(values) == 2 and not any(report._validated_measurement_series(value) for value in values)
    fig, ax = plot(tmp_path, progress, values)
    assert len(ax.lines) == 2 and all(line.get_linestyle() == "None" for line in ax.lines)
    assert sorted(float(line.get_ydata()[0]) for line in ax.lines) == [-2, -1]
    plt.close(fig)


def test_exact_series_hash_uses_original_utf8_not_reserialized_definition(tmp_path):
    item = fixtures.with_series(fixtures.row(-3, metadata='{"RandomSeed":7,"Label":"α"}'))
    key = json.loads(item["PopulationSeriesJSON"])
    item["PopulationSeriesJSON"] = json.dumps(key, ensure_ascii=False, indent=2)
    item["PopulationSeriesID"] = hashlib.sha256(item["PopulationSeriesJSON"].encode("utf-8")).hexdigest()
    _, progress = fixtures.source(tmp_path, [item])
    _, values = report.standardized_measurement_rows(progress)
    assert report._validated_measurement_series(values[0])
    altered = dict(values[0], PopulationSeriesJSON=json.dumps(key, ensure_ascii=False))
    assert not report._validated_measurement_series(altered)


def test_measurement_csv_duplicate_header_rejected(tmp_path):
    path, progress = fixtures.source(tmp_path, [fixtures.row(-3)])
    original = path.read_text()
    path.write_text(original.replace("CategoryCode,", "MetricKey,", 1))
    with pytest.raises(ValueError, match="Duplicate original"):
        report.standardized_measurement_rows(progress)
