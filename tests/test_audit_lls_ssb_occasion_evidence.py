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

    def normalized_row(self, antennas=1):
        row = self.row()
        row.update(PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es",
                   RSRP_dBm="NaN", RSRP_dB_re_UnitOccupiedRE_Es="-6",
                   SSBWindowPowerMeasurementJSON="", SSBWindowRSSIPerReceiveAntenna_dBm="")
        powers = [2 * (ant + 1) for ant in range(antennas)]
        rssi = [10 * AUDIT.math.log10(power) for power in powers]
        rsrp = [-10.0] * antennas
        data = dict(Scope="ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI",
                    AmplitudeUnit="sqrt_UnitOccupiedRE_Es", CPIncluded=False,
                    NumReceiveAntennas=antennas, NumRB=20,
                    PowerReferencePlane=row["PowerReferencePlane"],
                    SymbolPowerPerAntenna_UnitOccupiedRE_Es=[powers] * 4,
                    RSSIPerAntenna_dB_re_UnitOccupiedRE_Es=rssi,
                    ReferenceRSRPPerAntenna_dB_re_UnitOccupiedRE_Es=rsrp,
                    ReferenceRSRQPerAntenna_dB=[10 * AUDIT.math.log10(20) + p - i
                                               for p, i in zip(rsrp, rssi)])
        row["SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"] = "|".join(map(str, rssi))
        row["SSBWindowRelativePowerMeasurementJSON"] = json.dumps(data)
        return row

    def test_normalized_singleton_and_multiantenna_arithmetic(self):
        for antennas in (1, 2, 4):
            self.assertEqual([], self.failures(self.normalized_row(antennas)))

    def test_normalized_measurement_cannot_claim_absolute_power(self):
        for field, value in (("RSRP_dBm", "-80"), ("SS_RSRP_dBm", "-80"),
                             ("ReferenceSignalTxEPRE_dBm", "0"),
                             ("SSBWindowPowerMeasurementJSON", "{}"),
                             ("SSBWindowRSSIPerReceiveAntenna_dBm", "-70")):
            row = self.normalized_row()
            row[field] = value
            self.assertIn("normalized_power_no_absolute_claim", self.failures(row))

    def test_normalized_schema_and_units_are_not_inferred(self):
        for field, value in (("AmplitudeUnit", "sqrt_W"),
                             ("PowerReferencePlane", "unknown"),
                             ("SymbolPowerPerAntenna_W", [[2]] * 4),
                             ("CPIncluded", True), ("NumReceiveAntennas", 2)):
            row = self.normalized_row()
            data = json.loads(row["SSBWindowRelativePowerMeasurementJSON"])
            data[field] = value
            row["SSBWindowRelativePowerMeasurementJSON"] = json.dumps(data)
            self.assertTrue(self.failures(row), field)
        row = self.normalized_row()
        del row["PowerReferencePlane"]
        self.assertIn("window_power_evidence", self.failures(row))

    def test_normalized_rssi_and_rsrq_corruptions_fail_without_clamping(self):
        for field in ("RSSIPerAntenna_dB_re_UnitOccupiedRE_Es",
                      "ReferenceRSRQPerAntenna_dB", "SymbolPowerPerAntenna_UnitOccupiedRE_Es"):
            row = self.normalized_row()
            data = json.loads(row["SSBWindowRelativePowerMeasurementJSON"])
            if field.startswith("Symbol"):
                data[field][0][0] *= 10
            else:
                data[field][0] += 30
            row["SSBWindowRelativePowerMeasurementJSON"] = json.dumps(data)
            self.assertTrue(self.failures(row), field)
        row = self.normalized_row()
        row["RSRP_dB_re_UnitOccupiedRE_Es"] = "NaN"
        self.assertIn("valid_rsrp_available", self.failures(row))


if __name__ == "__main__":
    unittest.main()
