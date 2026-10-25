"""Declared original selection publication contracts; no PHY/candidate accuracy."""
import csv
import hashlib
import json
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_sweep_report as report


def row(field, value, source_row, point):
    unit = "layers" if field == "RI" else "index"
    text = str(value)
    identity = dict(ContractVersion="sixgr.report.discrete_selection_observation/v1",
                    SourceArtifact="air_interface/csv/csi_rs_trials.csv", SourceRowIndex=source_row,
                    SourceField=field, Unit=unit, OriginalValueText=text,
                    ProvenanceScope="retained_source_row_not_independent_reception_verification",
                    ConfiguredSNR_dB=point, UEIndex=source_row, Slot=6 + source_row,
                    ResourceID=(17, 29)[source_row - 1], RI=(1, 4)[source_row - 1],
                    CodebookType=f"declared-book-{source_row}")
    result = {key: "" for key in report.STANDARD_MEASUREMENT_FIELDS + report.MEASUREMENT_POPULATION_FIELDS}
    result.update(CategoryCode="fixture", CategoryKey="csi", CategoryName="CSI",
                  MetricKey=field.lower(), MetricName=field,
                  Entity=f"CSI-selection-{field}@source_row={source_row}", Statistic="observation",
                  Availability="observed", CountsTowardCoverage="1", ValueNumeric=text, ValueText=text,
                  Unit=unit, SourceArtifact=identity["SourceArtifact"], Notes="declared metadata fixture")
    seal(result, identity)
    return result


def seal(value, identity):
    value["PopulationJSON"] = json.dumps(identity, ensure_ascii=False, separators=(",", ":"))
    value["PopulationID"] = hashlib.sha256(value["PopulationJSON"].encode()).hexdigest()


def campaign(tmp_path):
    points, originals = [], []
    for index, operating_point in enumerate((-10, 0, 10, 20, 30, 40), 1):
        child = tmp_path / "sweeps" / str(index)
        path = child / "reports/csv/csi_outputs.csv"
        path.parent.mkdir(parents=True)
        rows = [row(field, values[source_row - 1], source_row, operating_point)
                for field, values in {"PMI": (0, 1), "CRI": (17, 29), "RI": (1, 4), "CQI": (3, 14)}.items()
                for source_row in (1, 2)]
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)
        originals.append((path, path.read_bytes()))
        points.append(dict(index=index, label=f"declared-{index}", configured_snr_db=999,
                           status="passed", run_folder=str(child)))
    return dict(points=points), originals


def test_actual_joint_consumer_preserves_all_discrete_observations(tmp_path):
    progress, originals = campaign(tmp_path)
    availability, observations = report.standardized_measurement_rows(progress)
    assert len(availability) == len(observations) == 48
    assert {r["EvidenceClass"] for r in observations} == {"original_discrete_selection_observation_not_selection_accuracy"}
    assert {float(r["PublishedOperatingPoint_dB"]) for r in observations} == {-10, 0, 10, 20, 30, 40}
    assert len({report._measurement_series_key(r) for r in observations}) == 48
    for field, values in {"pmi": {0, 1}, "cri": {17, 29}, "ri": {1, 4}, "cqi": {3, 14}}.items():
        assert {float(r["ValueNumeric"]) for r in observations if r["MetricKey"] == field} == values
    manifest = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    assert len(manifest) == 4 and all(r["ObservedRowCount"] == 12 for r in manifest)
    assert all(path.read_bytes() == original for path, original in originals)


def test_plot_keeps_indices_as_unconnected_original_markers(tmp_path):
    import matplotlib.pyplot as plt
    progress, _ = campaign(tmp_path)
    _, values = report.standardized_measurement_rows(progress)
    selected = [r for r in values if r["MetricKey"] == "cri"]
    fig, ax = plt.subplots()
    try:
        with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
            report._plot_standardized_metric(tmp_path / "cri.png", progress, selected, "Original CRI", "index")
        assert len(ax.lines) == 12
        assert all(line.get_linestyle() == "None" and len(line.get_ydata()) == 1 for line in ax.lines)
        assert {float(line.get_ydata()[0]) for line in ax.lines} == {17, 29}
    finally:
        plt.close(fig)


@pytest.mark.parametrize("field,value", [("ValueNumeric", .5), ("Entity", "CSI-selection-PMI@source_row=2"),
                                         ("MetricKey", "cri"), ("Unit", "layers"), ("PopulationID", "0" * 64)])
def test_corrupted_aliases_fail_before_plot_coordinate(field, value):
    original = row("PMI", 0, 1, 30)
    original[field] = value
    with pytest.raises(ValueError):
        report._source_operating_point(original)
    with pytest.raises(ValueError):
        report._plot_operating_point(original)


def test_components_not_coerced_into_scalar_and_legacy_not_given_coordinate_authority():
    original = row("PMI", 0, 1, 30)
    identity = json.loads(original["PopulationJSON"])
    identity["OriginalValueText"] = "[0,1]"
    original.update(ValueText="[0,1]", ValueNumeric="NaN")
    seal(original, identity)
    assert report._source_operating_point(original)["PublishedOperatingPoint_dB"] == 30
    original["ValueNumeric"] = .5
    with pytest.raises(ValueError):
        report._source_operating_point(original)
    legacy = row("PMI", 0, 1, 30)
    legacy.update(Entity="CSI-RS", Statistic="mean", PopulationID="", PopulationJSON='{"ConfiguredSNR_dB":30}')
    assert report._source_operating_point(legacy)["PublishedOperatingPoint_dB"] == ""
