"""Declared SRS publication metadata through real consumers; no PHY claim."""

import csv
import hashlib
import json
from pathlib import Path
import sys
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_sweep_report as report


TARGETS = [30, 20, 10, 0, -10, -20]
ARTIFACT = "air_interface/csv/srs_trials.csv"
CONTRACTS = {
    "absolute": ("SRS_RSRP_dBm", "dBm", "SRS-RSRP_absolute"),
    "normalized": ("SRS_RSRP_dB_re_UnitOccupiedRE_Es", "dB_re_UnitOccupiedRE_Es",
                   "SRS-reference-power_normalized"),
}


def _seal(row, population):
    # Exact whitespace and UTF-8 bytes deliberately differ from compact JSON.
    token = json.dumps(population, ensure_ascii=False, indent=1)
    row.update(PopulationJSON=token,
               PopulationID=hashlib.sha256(token.encode("utf-8")).hexdigest())


def _row(kind, point=1, source_row=1, source_snr=30):
    field, unit, entity = CONTRACTS[kind]
    receiver = (source_row - 1) % 2 + 1
    value = (-108.0 if kind == "absolute" else -7.0) - point - receiver / 4
    identity = dict(
        RunID=f"declared_α_run_{point}", ExecutionID=f"declared_execution_{point}",
        ConfigHash=f"declared_not_executed_config_{point}", SweepPointIndex=point,
        ConfiguredSNR_dB=source_snr, Slot=source_row, Frame=point,
        SFN=(1023 + receiver - 1) % 1024, SRSResourceID=receiver - 1,
        UEIndex=receiver, ServingCell=receiver, RNTI=receiver,
        ReceiverID="", ReceiverWindowID=f"declared_window_{point}_{source_row}",
        ObservationStartSample=point * 1000 + source_row * 100,
        ObservationEndSampleExclusive=point * 1000 + source_row * 100 + 100,
        ObservationSampleRateHz=30.72e6,
        SRSRSRPSource="received_srs_channel_estimate_times_known_reference_symbols",
        SRSRSRPStatus="observed", SRSOccupiedPRBCount=48, SRSCarrierPRBCount=51,
        SourceArtifact=ARTIFACT, SourceRowIndex=source_row, SourceField=field,
        Unit=unit, OriginalValueText=format(value, ".17g"),
        ProvenanceScope="retained_source_row_not_independent_reception_verification",
    )
    if kind == "absolute":
        plane = ("modeled_receiver_branch_after_identity_combining_before_RX_front_end"
                 if receiver == 1 else "internal_physical_receive_element_before_RX_front_end")
        identity.update(
            SRSAbsolutePowerSelectedBranch0=31 if receiver == 1 else 1,
            SRSAbsolutePowerResourceID=receiver - 1,
            SRSAbsolutePowerSource="independent_preRF_nrChannelEstimate_per_symbol_known_SRS_reconstruction",
            SRSAbsolutePowerReferencePlane=plane,
            PowerMeasurementReceiverID=f"declared_gnb_{receiver}_rx",
            PowerMeasurementObservationID=f"declared_SRS_{point}_{source_row}",
            PowerMeasurementReferencePlane=plane,
            PowerMeasurementSelectedBranch0=31 if receiver == 1 else 1,
            PowerMeasurementResource={"ResourceID": receiver - 1, "AbsoluteSlot0": source_row + 3},
        )
    row = dict(
        CategoryCode="A", CategoryKey="channel", CategoryName="Channel",
        MetricKey="srs_rsrp", MetricName="SRS received reference power",
        Entity=f"{entity}@source_row={source_row}", Statistic="observation",
        Availability="observed", CountsTowardCoverage="1",
        ValueNumeric=format(value, ".17g"), ValueText=format(value, ".17g"),
        Unit=unit, SourceArtifact=ARTIFACT,
        Notes="Declared publication fixture, not PHY, calibrated hardware or a compatible curve.",
        SupportConfigurationJSON=json.dumps({"FixtureOnly": True, "PowerDefinition": kind}),
        PopulationSeriesID="", PopulationSeriesJSON="",
    )
    _seal(row, identity)
    return row


def _write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [*report.STANDARD_MEASUREMENT_FIELDS, *report.MEASUREMENT_POPULATION_FIELDS]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def _source(tmp_path):
    points, expected, originals = [], [], []
    for point, target in enumerate(TARGETS, 1):
        child = tmp_path / f"child_{point}"
        path = child / "reports/csv/channel_outputs.csv"
        rows = [_row(kind, point, index, target) for index in (1, 2) for kind in CONTRACTS]
        _write(path, rows)
        originals.append((path, path.read_bytes()))
        # The wrapper label intentionally differs: only the validated original
        # row may supply a published source operating-point coordinate.
        status = "failed" if point == 6 else "passed"
        points.append(dict(index=point, label=f"declared_{target}", configured_snr_db=target + 1,
                           status=status, run_folder=str(child)))
        expected.extend((point, target, status, output_index, row)
                        for output_index, row in enumerate(rows, 1))
    return dict(points=points), expected, originals


def _assert_original(actual_rows, expected):
    assert len(actual_rows) == len(expected)
    for actual, (point, target, status, output_index, original) in zip(actual_rows, expected):
        for field in report.STANDARD_MEASUREMENT_FIELDS + report.MEASUREMENT_POPULATION_FIELDS:
            if field == "ValueNumeric":
                assert float(actual[field]) == float(original[field])
            else:
                assert actual[field] == original[field]
        assert int(actual["PointIndex"]) == point
        assert actual["PointStatus"] == status
        assert float(actual["ConfiguredSNR_dB"]) == target + 1
        assert float(actual["PublishedOperatingPoint_dB"]) == target
        assert actual["PublishedOperatingPointField"] == "ConfiguredSNR_dB"
        assert actual["PublishedOperatingPointRole"] == "source_configured_operating_point_metadata"
        assert int(actual["SourceOutputRow"]) == output_index
        assert actual["SourceOutputTable"] == f"sweeps/child_{point}/reports/csv/channel_outputs.csv"
        assert not report._validated_measurement_series(actual)
        assert actual["PopulationSeriesID"] == actual["PopulationSeriesJSON"] == ""


def test_six_points_keep_every_srs_observation_in_joint_csv(tmp_path):
    progress, expected, originals = _source(tmp_path)
    availability, measured = report.standardized_measurement_rows(progress)
    _assert_original(availability, expected)
    _assert_original(measured, expected)
    manifest = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    assert len(manifest) == 2  # One file per original unit, never mix absolute/normalized values.
    for entry in manifest:
        selected = [item for item in expected if item[-1]["Unit"] == entry["Unit"]]
        _assert_original(report.read_rows(tmp_path / entry["CampaignCSV"]), selected)
        assert entry["MetricKey"] == "srs_rsrp"
        assert entry["ObservedRowCount"] == entry["SeriesCount"] == 12
        assert entry["ObservedPointIndices"] == "1|2|3|4|5|6"
        assert entry["MissingTerminalPointIndices"] == entry["CampaignPNG"] == ""
    assert all(path.read_bytes() == original for path, original in originals)


@pytest.mark.parametrize("kind", list(CONTRACTS))
def test_actual_plot_consumer_keeps_separate_resource_branch_plane_markers(tmp_path, kind):
    import matplotlib.pyplot as plt

    progress, expected, originals = _source(tmp_path)
    _, measured = report.standardized_measurement_rows(progress)
    unit = CONTRACTS[kind][1]
    selected = [row for row in measured if row["Unit"] == unit]
    expected_pairs = sorted((target, float(row["ValueNumeric"]))
                            for _, target, _, _, row in expected if row["Unit"] == unit)
    fig, ax = plt.subplots(figsize=(10, 5.8))
    image = tmp_path / f"srs_{kind}.png"
    try:
        with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
            report._plot_standardized_metric(image, progress, selected, "Declared SRS metadata only", unit)
        assert len(ax.lines) == 12
        assert all(line.get_linestyle() == "None" and line.get_marker() == "o" for line in ax.lines)
        assert all(len(line.get_xdata()) == len(line.get_ydata()) == 1 for line in ax.lines)
        assert sorted((float(line.get_xdata()[0]), float(line.get_ydata()[0])) for line in ax.lines) == expected_pairs
        assert list(ax.get_xticks()) == sorted(TARGETS)
        assert not ax.collections  # No population pooling or uncertainty ribbon.
        assert image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
    finally:
        plt.close(fig)
    assert all(path.read_bytes() == original for path, original in originals)


@pytest.mark.parametrize("mutation", [
    "stale_hash", "duplicate_key", "nonfinite_json", "missing_hash", "missing_json", "wrong_scope",
    "wrong_field", "wrong_unit", "wrong_metric", "wrong_artifact", "wrong_source_row", "boolean_row",
    "unsafe_row", "wrong_value", "string_coordinate", "boolean_coordinate",
])
def test_late_row_257_corruption_rejected_by_import_and_direct_plot(tmp_path, mutation):
    rows = [_row("absolute", source_row=index) for index in range(1, 258)]
    row = rows[-1]
    population = json.loads(row["PopulationJSON"])
    if mutation == "stale_hash":
        population["ConfiguredSNR_dB"] = 999
        row["PopulationJSON"] = json.dumps(population)
    elif mutation in {"duplicate_key", "nonfinite_json"}:
        suffix = ',"ConfiguredSNR_dB":999}' if mutation == "duplicate_key" else ',"Unknown":NaN}'
        row["PopulationJSON"] = row["PopulationJSON"][:-1] + suffix
        row["PopulationID"] = hashlib.sha256(row["PopulationJSON"].encode("utf-8")).hexdigest()
    elif mutation == "missing_hash":
        row["PopulationID"] = ""
    elif mutation == "missing_json":
        row["PopulationJSON"] = ""
    elif mutation == "wrong_value":
        row["ValueNumeric"] = "999"
    elif mutation == "wrong_source_row":
        row["Entity"] = "SRS-RSRP_absolute@source_row=256"
    elif mutation == "wrong_metric":
        row["MetricKey"] = "cqi"
    elif mutation == "wrong_artifact":
        row["SourceArtifact"] = "air_interface/csv/csi_rs_trials.csv"
    else:
        key, value = {
            "wrong_scope": ("ProvenanceScope", "unverified_legacy_scope"),
            "wrong_field": ("SourceField", "SRS_RSRP_dB_re_UnitOccupiedRE_Es"),
            "wrong_unit": ("Unit", "dB"),
            "boolean_row": ("SourceRowIndex", True),
            "unsafe_row": ("SourceRowIndex", 2**53),
            "string_coordinate": ("ConfiguredSNR_dB", "30"),
            "boolean_coordinate": ("ConfiguredSNR_dB", True),
        }[mutation]
        population[key] = value
        _seal(row, population)
    child = tmp_path / "child"
    path = child / "reports/csv/channel_outputs.csv"
    _write(path, rows)
    original = path.read_bytes()
    progress = dict(points=[dict(index=1, label="declared", configured_snr_db=30,
                                status="passed", run_folder=str(child))])
    with pytest.raises(ValueError):
        report.standardized_measurement_rows(progress)
    row.update(ConfiguredSNR_dB=30, PublishedOperatingPoint_dB=30)
    with pytest.raises(ValueError):
        report._plot_operating_point(row)
    assert path.read_bytes() == original


def test_source_coordinate_roles_and_opaque_legacy_remain_distinct():
    row = _row("absolute", source_snr=20)
    row.update(ConfiguredSNR_dB=30, **report._source_operating_point(row))
    assert report._plot_operating_point(row) == 20
    for field, value in (("PublishedOperatingPoint_dB", 21),
                         ("PublishedOperatingPointField", "SNR_dB"),
                         ("PublishedOperatingPointRole", "measured_SINR")):
        broken = {**row, field: value}
        with pytest.raises(ValueError, match="coordinate"):
            report._plot_operating_point(broken)
    legacy = {**row, "Entity": "SRS-RSRP_absolute"}
    _seal(legacy, {"ConfiguredSNR_dB": 999, "ReceiverID": "legacy_opaque"})
    for field in report.MEASUREMENT_OPERATING_POINT_FIELDS:
        legacy.pop(field, None)
    assert all(value == "" for value in report._source_operating_point(legacy).values())
    assert report._plot_operating_point(legacy) == 30
    assert not report._validated_measurement_series(legacy)
    legacy["PopulationID"] = "a" * 64
    with pytest.raises(ValueError, match="PopulationID"):
        report._source_operating_point(legacy)


def test_null_coordinate_and_unavailable_observation_never_acquire_coverage(tmp_path):
    row = _row("normalized")
    population = json.loads(row["PopulationJSON"])
    population["ConfiguredSNR_dB"] = None
    _seal(row, population)
    assert all(value == "" for value in report._source_operating_point(row).values())
    assert report._plot_operating_point({**row, "ConfiguredSNR_dB": -10}) == -10
    row.update(Availability="not_available", CountsTowardCoverage="0")
    child = tmp_path / "child"
    _write(child / "reports/csv/channel_outputs.csv", [row])
    progress = dict(points=[dict(index=1, label="declared", configured_snr_db=-10,
                                status="failed", run_folder=str(child))])
    availability, measured = report.standardized_measurement_rows(progress)
    assert len(availability) == 1 and not measured
    assert availability[0]["ValueText"] == row["ValueText"]
    assert availability[0]["PopulationJSON"] == row["PopulationJSON"]
