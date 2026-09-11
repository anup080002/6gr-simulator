"""Arithmetic/metadata fixtures only: these are not simulated RF measurements."""
import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "ssb_audit", Path(__file__).parents[1] / "tools/audit_lls_ssb_occasion_evidence.py")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class SSBOccasionAuditTest(unittest.TestCase):
    def row(self):
        data = dict(Scope="ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI",
                    AmplitudeUnit="sqrt_W", CPIncluded=False, NumReceiveAntennas=1, NumRB=20,
                    SymbolPowerPerAntenna_W=[1e-10] * 4, RSSIPerAntenna_dBm=-70,
                    ReferenceRSRPPerAntenna_dBm=-90,
                    ReferenceRSRQPerAntenna_dB=10 * AUDIT.math.log10(20) - 20)
        return dict(MeasurementSource="actual_shared_ssb_occasion_pre_rx_rf_measurement",
                    TargetId="1", ServingCell="1", BurstSlot="21", ResourceId="0",
                    ObservationStartSample="20000", ObservationEndSampleExclusive="20500",
                    ObservationSampleRateHz="1000000", ProducerSlot="21", AvailableSlot="22",
                    Valid="1", MeasuredNCellID="1", ExpectedNCellID="1", RSRP_dBm="-88",
                    SSBWindowRSSIPerReceiveAntenna_dBm="-70",
                    SSBWindowPowerMeasurementJSON=json.dumps(data))

    def failures(self, row):
        return [item["Check"] for item in AUDIT.audit_rows([row], .001)["Checks"] if not item["Passed"]]

    def test_consistent_arithmetic(self):
        self.assertEqual([], self.failures(self.row()))

    def test_future_sample(self):
        row = self.row()
        row["ObservationEndSampleExclusive"] = "21001"
        self.assertIn("no_future_observation", self.failures(row))

    def test_early_delivery(self):
        row = self.row()
        row["AvailableSlot"] = "21"
        self.assertIn("no_future_observation", self.failures(row))

    def test_duplicate_filter_input(self):
        result = AUDIT.audit_rows([self.row(), self.row()], .001)
        self.assertEqual(1, result["FailedChecks"])

    def test_corrupt_power_scale(self):
        row = self.row()
        data = json.loads(row["SSBWindowPowerMeasurementJSON"])
        data["SymbolPowerPerAntenna_W"] = [1e-7] * 4
        row["SSBWindowPowerMeasurementJSON"] = json.dumps(data)
        self.assertIn("antenna_0_rssi_power_closure", self.failures(row))

    def test_wrong_csv_token(self):
        row = self.row()
        row["SSBWindowRSSIPerReceiveAntenna_dBm"] = "-100"
        self.assertIn("antenna_0_rssi_csv_closure", self.failures(row))

    def test_empty_json_array_is_not_valid(self):
        row = self.row()
        row["SSBWindowPowerMeasurementJSON"] = "[]"
        self.assertIn("window_power_payload_schema", self.failures(row))

    def test_bch_failure_does_not_redefine_sss_measurement(self):
        row = self.row()
        row["SSBOccasionBCHCRCPass"] = "0"
        self.assertEqual([], self.failures(row))

    def test_unobserved_is_not_synthetic_coverage(self):
        result = AUDIT.audit_rows([dict(MeasurementSource="other")], .001)
        self.assertEqual(0, result["ObservedOccasions"])
        self.assertEqual([], result["Checks"])


if __name__ == "__main__":
    unittest.main()
