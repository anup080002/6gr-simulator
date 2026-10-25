"""Declared original-shaped CSV receipts; no PHY or pathloss qualification."""
import copy
import csv
import hashlib
import io
import json
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


def sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def fixture():
    powers = [-97.0 - i for i in range(8)]
    measured = [{"ResourceID": i, "Available": True, "PowerUnit": "W_resource_grid",
                 "RSRPPerAntenna_dBm": [power - 3, power],
                 "SINR": {"DesiredPowerPerReceiveAntenna": [10 ** ((power - 33) / 10), 10 ** ((power - 30) / 10)]}}
                for i, power in enumerate(powers)]
    resources_token = json.dumps(measured, separators=(",", ":"))
    flags = dict(ReceiverUsesReference=False, UniqueNonlinearPortAttributionQualified=False,
                 StandardizedPathlossQualified=False, IndependentAccuracyQualified=False)
    parts = [{**flags, "ContractVersion": "sixgr.csirs.post_tx_rf_projected_attenuation/v1",
              "ResourceID": i, "ResourceOrdinal0": i, "ResourceSetID": 0, "ReferencePort": 3000,
              "Available": True, "Status": "available_projected_effective_attenuation_not_isolated_port_pathloss",
              "TransmitProjectedPower_dBm": 2.0, "SelectedReceivedPower_dBm": power,
              "EffectiveAttenuation_dB": 2.0 - power, "TransmitProjectedPower_W": 10 ** (-28 / 10),
              "SelectedReceivedPower_W": 10 ** ((power - 30) / 10), "SelectedReceiveColumn1": 2}
             for i, power in enumerate(powers)]
    receipt = {**flags, "ContractVersion": "sixgr.csirs.shared_projected_attenuation/v1",
               "Scope": "post_TX_RF_to_pre_RX_RF_CDM_projected_effective_attenuation",
               "WaveformAmplitudeUnit": "sqrt_mW", "ResourceIDs": list(range(8)), "ResourceSetID": 0,
               "ReceiverWindowID": "original-window", "RXObservationSHA256": "a" * 64,
               "RXStartSample": 100, "RXEndSampleExclusive": 200, "SampleRateHz": 30720000,
               "OriginalMeasurementResourcesSHA256": sha(resources_token), "ResourceComparisons": parts}
    row = {"Slot": 6, "UEID": 1, "ServingCell": 1, "ResourceSetID": 0, "ResourceID": 1,
           "ReceiverWindowID": "original-window", "PhysicalMeasurementObservationSHA256": "a" * 64,
           "ObservationStartSample": 100, "ObservationEndSampleExclusive": 200, "ObservationSampleRateHz": 30720000,
           "MeasurementResourceIDs": json.dumps(list(range(8))), "MeasurementRSRPPerResource_dBm": json.dumps(powers),
           "MeasurementPhysicalResourcesJSON": resources_token}
    seal(row, receipt)
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=list(row)); writer.writeheader(); writer.writerow(row)
    output.seek(0)
    return next(csv.DictReader(output)), receipt


def seal(row, receipt):
    token = json.dumps(receipt, separators=(",", ":"))
    row["CSIRSTransmitProjectedAttenuationJSON"] = token
    row["CSIRSTransmitProjectedAttenuationSHA256"] = sha(token)


def test_original_csv_full_population_projects_only_named_diagnostic():
    row, _ = fixture()
    saved = copy.deepcopy(row)
    result = dash.csi_resource_power_preview(row)
    assert len(result) == 8
    assert [r["Projected effective attenuation (dB)"] for r in result] == list(range(99, 107))
    assert all(r["Projected TX power (dBm)"] == 2 and r["Projection RX branch (1-based)"] == 2 for r in result)
    assert all(r["Pathloss (dB)"] is None for r in result)
    assert row == saved
    assert "post_TX_RF_to_pre_RX_RF" in result[0]["Projection scope"]


@pytest.mark.parametrize("mutation", [
    lambda r: r["ResourceComparisons"][-1].update(EffectiveAttenuation_dB=1),
    lambda r: r["ResourceComparisons"][-1].update(SelectedReceiveColumn1=1),
    lambda r: r["ResourceComparisons"][-1].update(SelectedReceiveColumn1=True),
    lambda r: r["ResourceComparisons"][-1].update(ResourceID=0),
    lambda r: r["ResourceComparisons"][-1].update(TransmitProjectedPower_W=0),
    lambda r: r["ResourceComparisons"][-1].update(IndependentAccuracyQualified=True),
    lambda r: r.update(RXObservationSHA256="b" * 64),
    lambda r: r.update(RXStartSample=101),
    lambda r: r.update(ResourceIDs=list(reversed(range(8)))),
    lambda r: r.update(WaveformAmplitudeUnit="unknown"),
    lambda r: r.update(ReceiverUsesReference=0),
])
def test_resealed_corruption_cannot_display_a_diagnostic_or_hide_original_rsrp(mutation):
    row, receipt = fixture()
    mutation(receipt); seal(row, receipt)
    result = dash.csi_resource_power_preview(row)
    assert len(result) == 8 and [r["RSRP"] for r in result] == [-97 - i for i in range(8)]
    assert all("Projected effective attenuation (dB)" not in r for r in result)
    assert all("malformed" in r["Projection status"] for r in result)


def test_changed_hash_missing_receipt_and_unavailable_resource_never_get_proxy():
    row, receipt = fixture()
    row["CSIRSTransmitProjectedAttenuationSHA256"] = "0" * 64
    assert "malformed" in dash.csi_resource_power_preview(row)[0]["Projection status"]
    row.pop("CSIRSTransmitProjectedAttenuationJSON")
    assert "unavailable_original" in dash.csi_resource_power_preview(row)[0]["Projection status"]
    receipt["ResourceComparisons"][3].update(Available=False, Status="unavailable_nonpositive_original_projected_or_received_power",
                                           EffectiveAttenuation_dB=None, SelectedReceivedPower_W=-1)
    seal(row, receipt)
    result = dash.csi_resource_power_preview(row)
    assert result[3]["Projected effective attenuation (dB)"] is None
    assert result[2]["Projected effective attenuation (dB)"] == 101
    receipt["WaveformAmplitudeUnit"] = "normalized_complex_baseband"
    seal(row, receipt)
    normalized = dash.csi_resource_power_preview(row)
    assert all("normalized_units" in r["Projection status"] for r in normalized)
    assert all("Projected effective attenuation (dB)" not in r for r in normalized)


def test_actual_ui_table_exposes_diagnostic_not_model_pathloss():
    source = (Path(__file__).resolve().parents[1] / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
    table = next(line for line in source.splitlines() if "{id:'csi_resource_power'" in line)
    assert "Projected effective attenuation (dB)" in table and "Projection RX branch (1-based)" in table
    assert "not UMa/model pathloss" in table
