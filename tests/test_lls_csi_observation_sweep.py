"""Declared CSI report observations through real consumers; no PHY qualification."""

import csv
import hashlib
import json
import math
from pathlib import Path
import sys
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_sweep_report as report


METRICS = {
    "csi_rsrp": ("CSI-RSRP", "dBm", "MeasurementRSRP_dBm"),
    "csi_rsrq": ("CSI-RSRQ", "dB", "MeasurementRSRQ_dB"),
    "csi_sinr": ("CSI-SINR", "dB", "ReferenceMeasuredSINR_dB"),
}


def _row(metric, point, observation, source_snr):
    entity, unit, field = METRICS[metric]
    rsrp = (-80.0, -100.0)[observation - 1] - 3 * (point - 1)
    rssi = (-60.0, -75.0)[observation - 1]
    values = {
        "csi_rsrp": rsrp,
        "csi_rsrq": 10 * math.log10(24) + rsrp - rssi,
        "csi_sinr": (10.0, 20.0)[observation - 1] - (point - 1),
    }
    identity = {
        "RunID": f"declared_run_{point}",
        "ExecutionID": f"declared_execution_{point}",
        "ConfigHash": f"declared_config_{point}",
        "SweepPointIndex": point,
        "ConfiguredSNR_dB": source_snr,
        "Slot": 10 * point + observation,
        "ResourceID": (17, 29)[observation - 1],
        "ResourceSetID": (3, 5)[observation - 1],
        "BeamID": (4, 8)[observation - 1],
        "UEIndex": observation,
        "CellID": observation,
        "ReceiverID": f"declared_ue_{observation}",
        "ReceiverWindowID": f"declared_window_{point}_{observation}",
        "ReceiverClockDomain": "shared_receiver_sample_clock/v1",
        "ReceiverClockEpoch": point,
        "MeasurementClockEpoch": point,
        "ObservationStartSample": 1000 * point + 100 * observation,
        "ObservationEndSampleExclusive": 1000 * point + 100 * observation + 100,
        "ObservationSampleRateHz": 7.68e6,
        "MeasurementReceiveAntennaIndex1Based": observation,
        "MeasurementRSRQReceiveAntennaIndex1Based": observation,
        "ReferenceSINRMeasurementJSON": json.dumps(
            {"ReceiveBranch1Based": 3 - observation}, separators=(",", ":")
        ),
        "PhysicalMeasurementReferencePlane": (
            "supplied_received_grid_columns",
            "original_pre_RX_RF_physical_element_columns",
        )[observation - 1],
        "PhysicalMeasurementStandardizedReferencePointQualified": False,
        "PhysicalMeasurementHardwareQualified": False,
    }
    # Deliberately preserve original whitespace/UTF-8 bytes, not a re-encoded
    # substitute identity. These are declared metadata, never owner receipts.
    identity["DeclaredFixtureLabel"] = "metadata-only α"
    identity.update(
        SourceArtifact="air_interface/csv/csi_rs_trials.csv",
        SourceRowIndex=observation, SourceField=field, Unit=unit,
        OriginalValueText=repr(values[metric]),
        ProvenanceScope="retained_source_row_not_independent_reception_verification",
    )
    token = json.dumps(identity, ensure_ascii=False, indent=1)
    return {
        "CategoryCode": "A",
        "CategoryKey": "channel",
        "CategoryName": "Channel",
        "MetricKey": metric,
        "MetricName": entity,
        "Entity": f"{entity + '_absolute' if metric == 'csi_rsrp' else entity}@source_row={observation}",
        "Statistic": "observation",
        "Availability": "observed",
        "CountsTowardCoverage": "1",
        "ValueNumeric": repr(values[metric]),
        "ValueText": repr(values[metric]),
        "Unit": unit,
        "SourceArtifact": "air_interface/csv/csi_rs_trials.csv",
        "Notes": f"Declared source-row fixture; original {field}; no PHY or accuracy claim.",
        "PopulationID": hashlib.sha256(token.encode("utf-8")).hexdigest(),
        "PopulationJSON": token,
        "SupportConfigurationJSON": "",
        "PopulationSeriesID": "",
        "PopulationSeriesJSON": "",
    }


def _source(tmp_path, point_pairs=None):
    points, expected, originals = [], [], []
    point_pairs = point_pairs or [(-20, -10), (20, 10)]
    for point, (wrapper_snr, source_snr) in enumerate(point_pairs, 1):
        child = tmp_path / f"child_{point}"
        path = child / "reports/csv/channel_outputs.csv"
        path.parent.mkdir(parents=True)
        rows = [_row(metric, point, observation, source_snr)
                for observation in (1, 2) for metric in METRICS]
        fields = [*report.STANDARD_MEASUREMENT_FIELDS, *report.MEASUREMENT_POPULATION_FIELDS]
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        originals.append((path, path.read_bytes()))
        status = "passed" if point == 1 else "failed"
        points.append(dict(index=point, label=f"declared_{point}",
                           configured_snr_db=wrapper_snr, status=status,
                           run_folder=str(child)))
        expected.extend((point, wrapper_snr, source_snr, status, row_index, row)
                        for row_index, row in enumerate(rows, 1))
    return dict(points=points), expected, originals


def _assert_original_rows(values, expected):
    assert len(values) == len(expected)
    for actual, (point, wrapper_snr, source_snr, status, row_index, original) in zip(values, expected):
        for field in report.STANDARD_MEASUREMENT_FIELDS + report.MEASUREMENT_POPULATION_FIELDS:
            if field == "ValueNumeric":
                assert float(actual[field]) == float(original[field])
            else:
                assert actual[field] == original[field]
        assert int(actual["PointIndex"]) == point
        assert float(actual["ConfiguredSNR_dB"]) == wrapper_snr
        assert float(actual["PublishedOperatingPoint_dB"]) == source_snr
        assert actual["PublishedOperatingPointField"] == "ConfiguredSNR_dB"
        assert actual["PublishedOperatingPointRole"] == "source_configured_operating_point_metadata"
        assert actual["PointStatus"] == status
        assert int(actual["SourceOutputRow"]) == row_index
        assert actual["SourceOutputTable"] == f"sweeps/child_{point}/reports/csv/channel_outputs.csv"
        assert actual["PopulationSeriesID"] == actual["PopulationSeriesJSON"] == ""
        assert not report._validated_measurement_series(actual)


def test_csi_observations_preserve_original_rows_and_joint_csv(tmp_path):
    progress, expected, originals = _source(tmp_path)
    availability, values = report.standardized_measurement_rows(progress)
    _assert_original_rows(availability, expected)
    _assert_original_rows(values, expected)
    manifest = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    assert {entry["MetricKey"] for entry in manifest} == set(METRICS)
    for entry in manifest:
        selected = [item for item in expected if item[-1]["MetricKey"] == entry["MetricKey"]]
        _assert_original_rows(report.read_rows(tmp_path / entry["CampaignCSV"]), selected)
        assert entry["ObservedRowCount"] == entry["SeriesCount"] == 4
        assert entry["ObservedPointIndices"] == "1|2"
        assert entry["MissingTerminalPointIndices"] == ""
        assert entry["CampaignPNG"] == ""
    assert all(path.read_bytes() == original for path, original in originals)


@pytest.mark.parametrize("metric", list(METRICS))
def test_csi_observation_plot_keeps_resource_branch_plane_markers(tmp_path, metric):
    import matplotlib.pyplot as plt

    progress, expected, originals = _source(tmp_path)
    _, values = report.standardized_measurement_rows(progress)
    selected = [row for row in values if row["MetricKey"] == metric]
    original_pairs = sorted((source_snr, float(row["ValueNumeric"]))
                            for _, _, source_snr, _, _, row in expected
                            if row["MetricKey"] == metric)
    fig, ax = plt.subplots(figsize=(10, 5.8))
    image = tmp_path / f"{metric}.png"
    try:
        with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
            report._plot_standardized_metric(image, progress, selected, METRICS[metric][0], METRICS[metric][1])
        assert len(ax.lines) == 4
        assert all(line.get_linestyle() == "None" and line.get_marker() == "o" for line in ax.lines)
        assert all(len(line.get_xdata()) == len(line.get_ydata()) == 1 for line in ax.lines)
        plotted = sorted((float(line.get_xdata()[0]), float(line.get_ydata()[0])) for line in ax.lines)
        assert plotted == original_pairs
        assert list(ax.get_xticks()) == [-10, 10]  # Original source coordinate, not wrapper relabeling.
        assert not ax.collections  # No pooled min/max ribbon or replacement population.
        assert image.is_file() and image.stat().st_size > 0
        assert all(path.read_bytes() == original for path, original in originals)
    finally:
        plt.close(fig)


def _seal(row, population):
    token = json.dumps(population, ensure_ascii=False, indent=1)
    row["PopulationJSON"] = token
    row["PopulationID"] = hashlib.sha256(token.encode("utf-8")).hexdigest()


@pytest.mark.parametrize("mutation", [
    "stale_coordinate", "duplicate_key", "wrong_field", "wrong_unit", "wrong_value",
    "wrong_source_row", "missing_hash", "wrong_scope", "string_coordinate", "boolean_coordinate",
    "wrong_metric",
])
def test_current_csi_contract_rejects_corruption_at_import_and_direct_plot(tmp_path, mutation):
    progress, _, originals = _source(tmp_path)
    path = originals[0][0]
    rows = report.read_rows(path)
    row = rows[-1]  # Last original SINR observation, not merely the first row.
    population = json.loads(row["PopulationJSON"])
    if mutation == "stale_coordinate":
        population["ConfiguredSNR_dB"] = 999
        row["PopulationJSON"] = json.dumps(population)
    elif mutation == "duplicate_key":
        token = row["PopulationJSON"][:-1] + ',"ConfiguredSNR_dB":999}'
        row["PopulationJSON"] = token
        row["PopulationID"] = hashlib.sha256(token.encode("utf-8")).hexdigest()
    elif mutation == "missing_hash":
        row["PopulationID"] = ""
    elif mutation == "wrong_value":
        row["ValueNumeric"] = "999"
    elif mutation == "wrong_source_row":
        row["Entity"] = "CSI-SINR@source_row=999"
    elif mutation == "wrong_metric":
        row["MetricKey"] = "cqi"
    else:
        key, value = {
            "wrong_field": ("SourceField", "MeasurementRSRQ_dB"),
            "wrong_unit": ("Unit", "dBm"),
            "wrong_scope": ("ProvenanceScope", "unverified_copied_scope"),
            "string_coordinate": ("ConfiguredSNR_dB", "10"),
            "boolean_coordinate": ("ConfiguredSNR_dB", True),
        }[mutation]
        population[key] = value
        _seal(row, population)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    corrupted_bytes = path.read_bytes()
    with pytest.raises(ValueError):
        report.standardized_measurement_rows(progress)
    # A caller bypassing import must not quietly fall back to a valid wrapper
    # point when the current original contract is malformed.
    row.update(ConfiguredSNR_dB=0, PublishedOperatingPoint_dB=0)
    with pytest.raises(ValueError):
        report._plot_operating_point(row)
    assert path.read_bytes() == corrupted_bytes


def test_current_coordinate_alias_and_legacy_opaque_identity_are_distinct():
    row = _row("csi_sinr", 1, 1, -10)
    row.update(ConfiguredSNR_dB=20, **report._source_operating_point(row))
    assert report._plot_operating_point(row) == -10
    row["PublishedOperatingPoint_dB"] = 999
    with pytest.raises(ValueError, match="coordinate"):
        report._plot_operating_point(row)
    legacy = dict(row)
    legacy["Entity"] = "CSI-SINR"
    _seal(legacy, {"ConfiguredSNR_dB": 999, "ReceiverID": "legacy_opaque"})
    for name in report.MEASUREMENT_OPERATING_POINT_FIELDS:
        legacy.pop(name, None)
    assert all(value == "" for value in report._source_operating_point(legacy).values())
    assert report._plot_operating_point(legacy) == 20
    assert not report._validated_measurement_series(legacy)


def test_normalized_and_signed_infinite_original_aliases_are_not_replaced():
    row = _row("csi_rsrp", 1, 1, 0)
    population = json.loads(row["PopulationJSON"])
    unit = "dB_re_UnitOccupiedRE_Es"
    population.update(SourceField="MeasurementRSRP_dB_re_UnitOccupiedRE_Es", Unit=unit)
    row.update(Unit=unit, Entity="CSI-RSRP_normalized@source_row=1")
    _seal(row, population)
    assert report._source_operating_point(row)["PublishedOperatingPoint_dB"] == 0
    # Identity validation preserves signed limits; it does not change the
    # separate consumer eligibility policy or invent a finite plot floor.
    for value in ("Inf", "-Inf"):
        population["OriginalValueText"] = value
        row.update(ValueNumeric=value, ValueText=value)
        _seal(row, population)
        assert report._validated_csi_observation_population(row)["OriginalValueText"] == value
        assert row["ValueNumeric"] == value
    row["ValueText"] = "Inf"
    with pytest.raises(ValueError, match="scalar aliases"):
        report._source_operating_point(row)


def test_six_declared_points_keep_all_resource_receiver_populations(tmp_path):
    # Six declared metadata points, NOT six completed waveform simulations.
    pairs = [(x + 1, x) for x in (-10, -5, 0, 5, 10, 15)]
    progress, expected, originals = _source(tmp_path, pairs)
    availability, values = report.standardized_measurement_rows(progress)
    _assert_original_rows(availability, expected)
    _assert_original_rows(values, expected)
    manifest = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    for entry in manifest:
        assert entry["ObservedPointIndices"] == "1|2|3|4|5|6"
        assert entry["ObservedRowCount"] == entry["SeriesCount"] == 12
        assert entry["MissingTerminalPointIndices"] == ""
        selected = [item for item in expected if item[-1]["MetricKey"] == entry["MetricKey"]]
        _assert_original_rows(report.read_rows(tmp_path / entry["CampaignCSV"]), selected)
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(10, 5.8))
    selected = [row for row in values if row["MetricKey"] == "csi_sinr"]
    try:
        with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
            report._plot_standardized_metric(tmp_path / "six_declared_points.png", progress, selected,
                                            "Declared metadata only", "dB")
        assert len(ax.lines) == 12
        assert all(line.get_linestyle() == "None" and len(line.get_ydata()) == 1 for line in ax.lines)
        assert list(ax.get_xticks()) == [pair[1] for pair in pairs]
        assert not ax.collections
    finally:
        plt.close(fig)
    assert all(path.read_bytes() == original for path, original in originals)
