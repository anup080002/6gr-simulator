"""Metadata-only audit fixtures, not simulated radio measurements."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("ul_audit", Path(__file__).parents[1] / "tools/audit_lls_uplink_evidence.py")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class UplinkEvidenceAuditTest(unittest.TestCase):
    def row(self):
        return dict(Slot="3", UCIExpectedBitVector="00101", UCIDecodedBitVector="00101",
                    UCIBitErrorVector="00000", ExpectedBitCount="5", DecodedBitCount="5",
                    UCIContentMatch="1", PUCCHDecodeOk="1", UCICRCBitCount="0",
                    UCICRCApplicable="0", CRCApplicable="0", CRCPass="NaN",
                    TimingEstimateSource="received_reference_correlation_bounded_search",
                    AppliedTimingCorrectionSamples="84", TimingEstimateUsed="1")

    def failures(self, row, channel="PUCCH"):
        return [item["Check"] for item in AUDIT.audit_rows(channel, [row]) if not item["Passed"]]

    def test_consistent_metadata(self):
        self.assertEqual([], self.failures(self.row()))

    def test_leading_zero_corruption(self):
        row = self.row()
        row["UCIDecodedBitVector"] = "101"
        self.assertIn("DecodedBitCount_closure", self.failures(row))
        self.assertIn("uci_error_vector_closure", self.failures(row))

    def test_wrong_xor(self):
        row = self.row()
        row["UCIBitErrorVector"] = "00001"
        self.assertIn("uci_error_vector_closure", self.failures(row))

    def test_actual_decode_failure_is_not_synthetic_audit_failure(self):
        row = self.row()
        row.update(UCIDecodedBitVector="00100", UCIBitErrorVector="00001", UCIContentMatch="0", PUCCHDecodeOk="0")
        self.assertEqual([], self.failures(row))

    def test_false_timing_flag(self):
        row = self.row()
        row["TimingEstimateUsed"] = "0"
        self.assertIn("measured_timing_application_flag", self.failures(row))

    def test_empty_generic_source_does_not_hide_srs_timing(self):
        row = dict(TimingEstimateSource="", SRSReceiveTimingSource="received_reference_correlation_bounded_search",
                   AppliedTimingCorrection_samples="84", TimingEstimateUsed="0")
        self.assertIn("measured_timing_application_flag", self.failures(row, "SRS"))
        row["TimingEstimateUsed"] = "1"
        self.assertEqual([], self.failures(row, "SRS"))

    def test_usable_srs_missing_producer_provenance(self):
        row = dict(SRSRuntimeEvidenceUsable="1", RuntimeEvidenceSource="not_emitted_by_active_srs_runtime")
        self.assertIn("usable_srs_runtime_provenance", self.failures(row, "SRS"))
        row["RuntimeEvidenceSource"] = "metadata_test_named_producer_not_rf_evidence"
        self.assertEqual([], self.failures(row, "SRS"))

    def test_shared_srs_clock_and_pending_delivery(self):
        row = dict(RuntimeTransportMode="shared_physical_stream_SRS_received_completion",
                   ObservationStartSample="1000", ObservationEndSampleExclusive="1500",
                   ObservationSampleRateHz="1000000", ObservationCompletionTime_s="0.0015",
                   RuntimeStateUpdated="0", ObservationDeliveryTime_s="NaN")
        self.assertEqual([], self.failures(row, "SRS"))
        row.update(RuntimeStateUpdated="1", ObservationDeliveryTime_s="0.001")
        self.assertIn("shared_srs_no_future_delivery", self.failures(row, "SRS"))
        row["ObservationDeliveryTime_s"] = "0.002"
        self.assertEqual([], self.failures(row, "SRS"))
        row["ObservationEndSampleExclusive"] = "1501"
        self.assertIn("shared_srs_observation_clock", self.failures(row, "SRS"))

    def test_fake_nonapplicable_crc_pass(self):
        row = self.row()
        row["CRCPass"] = "1"
        self.assertIn("nonapplicable_pucch_crc_not_passed", self.failures(row))
        self.assertNotIn("nonapplicable_pucch_crc_not_passed", self.failures(row, "PUSCH"))

    def test_missing_decoded_payload(self):
        row = self.row()
        row["UCIDecodedBitVector"] = ""
        self.assertIn("successful_pucch_has_complete_payload", self.failures(row))


if __name__ == "__main__":
    unittest.main()
