"""Declared CSV-boundary projections; these fixtures do not execute PHY."""
import copy
import csv
import io
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_web_dashboard as dash


def source_row():
    values = [-97.3219856114, -97.4984340408, -106.093599493, -109.527860924,
              -112.045232757, -110.716464374, -110.632782038, -105.101520317]
    row = dict(Slot=6, UEID=1, ServingCell=1, ResourceID=1,
               MeasurementResourceIDs=json.dumps(list(range(8))),
               MeasurementRSRPPerResource_dBm=json.dumps(values),
               MeasurementRSRP_dBm=-97.498434040777994,
               MeasurementRSRP_dB=-44.23352804442429,
               PowerReferencePlane="internal_physical_receive_element_before_RX_front_end",
               DLMeasurementAuthorityStatus="diagnostic_before_installation",
               CSIObservationPopulationSHA256="a" * 64)
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fieldnames=list(row))
    writer.writeheader()
    writer.writerow(row)
    stream.seek(0)
    return next(csv.DictReader(stream))


def test_all_original_resources_and_units_reach_actual_ui_projection():
    row = source_row()
    original = copy.deepcopy(row)
    status = dash.build_realtime_ue_status({}, {}, {"csi": [row]})
    assert len(status) == 1
    assert status[0]["csi_rsrp_dbm"] == float(row["MeasurementRSRP_dBm"])
    result = status[0]["csi_resource_power"]
    assert [r["Resource ID (0-based)"] for r in result] == list(range(8))
    assert [r["RSRP"] for r in result] == json.loads(row["MeasurementRSRPPerResource_dBm"])
    assert all(r["Power unit"] == "dBm" and r["Pathloss (dB)"] is None for r in result)
    assert all(r["Selected resource ID"] == "1" and r["Slot"] == "6" for r in result)
    assert all(r["Original power vector"] == row["MeasurementRSRPPerResource_dBm"] for r in result)
    assert row == original
    source = (ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
    line = next(s.strip() for s in source.splitlines() if s.strip().startswith("const csiResourcePowerRows ="))
    node = shutil.which("node") or "C:/ProgramData/anaconda3/Lib/site-packages/playwright/driver/node.exe"
    executed = subprocess.run([node, "-e", "const dashboard=" + json.dumps({"ue_status": status}) + ";" + line +
                              "console.log(JSON.stringify(csiResourcePowerRows));"], capture_output=True, text=True,
                             check=True, timeout=15)
    assert json.loads(executed.stdout) == result
    assert "rows:csiResourcePowerRows" in source


@pytest.mark.parametrize("field,value", [
    ("MeasurementResourceIDs", "[0,0,2,3,4,5,6,7]"),
    ("MeasurementResourceIDs", '["0",1,2,3,4,5,6,7]'),
    ("MeasurementResourceIDs", "[true,1,2,3,4,5,6,7]"),
    ("MeasurementResourceIDs", "[0,1]"),
    ("MeasurementRSRPPerResource_dBm", '[0,1,2,3,4,5,6,"-97"]'),
    ("MeasurementRSRPPerResource_dBm", "[0,1,2,3,4,5,6,Infinity]"),
])
def test_malformed_original_population_is_unavailable_not_partial_or_renumbered(field, value):
    row = source_row()
    row[field] = value
    result = dash.csi_resource_power_preview(row)
    assert len(result) == 1
    assert result[0]["Status"] == "unavailable_malformed_original_resource_population"
    assert "RSRP" not in result[0]


def test_missing_branch_resource_and_normalized_power_do_not_acquire_absolute_units():
    assert dash.csi_resource_power_preview({"MeasurementRSRP_dB": -44, "ResourceID": 1}) == []
    row = source_row()
    row.pop("MeasurementRSRPPerResource_dBm")
    row["MeasurementRSRPPerResource_dB_re_UnitOccupiedRE_Es"] = "[null,-1,-2,-3,-4,-5,-6,-7]"
    result = dash.csi_resource_power_preview(row)
    assert result[0]["Resource ID (0-based)"] == 0 and result[0]["RSRP"] is None
    assert result[1]["Resource ID (0-based)"] == 1 and result[1]["RSRP"] == -1
    assert all(r["Power unit"] == "dB re unit occupied-RE Es" for r in result)


def test_ssb_original_effective_loss_not_model_loss_or_inferred_from_missing_epre():
    row = dict(SS_RSRP_dBm=-97.3532702609121, ReferenceSignalTxEPRE_dBm=2.20739576295579,
               MeasuredReferenceSignalPathloss_dB=99.5606660238679,
               MeasuredReferenceSignalPathlossSource="actual_post_tx_rf_sss_epre_minus_pre_rx_rf_noise_debiased_ss_rsrp",
               PathlossReferenceRS="SSB-0", AppliedPathloss_dB=96.988098)
    result = dash.summarize_control_trial_preview_rows("pbch_trials", [row])[0]
    assert result["Measured RS effective loss (dB)"] == row["MeasuredReferenceSignalPathloss_dB"]
    assert result["Original SSS TX EPRE (dBm)"] == row["ReferenceSignalTxEPRE_dBm"]
    assert result["Pathloss reference RS"] == "SSB-0"
    row.pop("MeasuredReferenceSignalPathloss_dB")
    missing = dash.summarize_control_trial_preview_rows("pbch_trials", [row])[0]
    assert missing.get("Measured RS effective loss (dB)") is None
