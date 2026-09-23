"""Exact source preservation for single-occasion PRACH and discrete SSB plots."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def chart(name, path, fields, values):
    payload = m._encode_csv(fields, values)
    result = m._specialized_chart_materialization(name, {path: {"artifact_id": 1}}, lambda _: payload, 1)
    return result, m._decode_csv_dicts(result["csv_bytes"])[1]


class SparseSignalEvidence(unittest.TestCase):
    @staticmethod
    def observation_rows():
        fields = ["UEID", "BaseStationID", "ObservationStartSample",
                  "ObservationEndSampleExclusive", "ObservationSampleRateHz",
                  "ObservationCompletionTime_s", "ObservationCoverageSource",
                  "PSSDetected", "SSSDetected", "BCHCrcPass", "Crash",
                  "ProxyUsed", "FallbackFlag", "PlaceholderFlag"]
        values = [[1, 1, start, start + 38400, 7680000, (start + 38400) / 7680000,
                   "complete_contiguous_received_sample_buffer", 0, 0, 0, 0, 0, 0, 0]
                  for start in (0, 0, 153600)]
        return fields, values

    def test_ssb_occasion_chart_uses_received_windows_without_decoded_beam(self):
        fields, values = self.observation_rows()
        result, rows = chart("SSB occasion timeline", "air_interface/csv/pbch_trials.csv", fields, values)
        self.assertEqual(result["source_row_count"], 3)
        self.assertEqual([float(row["start_time_ms"]) for row in rows], [0, 0, 20])
        self.assertEqual([float(row["end_time_ms"]) for row in rows], [5, 5, 25])
        self.assertEqual([int(row["capture_ordinal"]) for row in rows], [1, 1, 2])
        self.assertTrue(all(row["bch_crc_pass"] == "0.0" for row in rows))
        self.assertTrue(all("ssb_index" not in row for row in rows))
        self.assertIn(b"not decoded beam", result["img_bytes"])
        self.assertFalse(m._is_placeholder_materialization_status(result["image_status"]))

    def test_ssb_occasion_chart_rejects_unmeasured_or_corrupt_capture_clock(self):
        for field, value in (("ObservationStartSample", -1), ("ObservationEndSampleExclusive", 0),
                             ("ObservationSampleRateHz", 0), ("ObservationCompletionTime_s", .010),
                             ("ObservationCoverageSource", "planned_capture"), ("ProxyUsed", 1),
                             ("PSSDetected", "NaN"), ("UEID", "NaN")):
            fields, values = self.observation_rows()
            values[0][fields.index(field)] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "SSB reception"):
                chart("SSB occasion timeline", "air_interface/csv/pbch_trials.csv", fields, values)

    def test_ssb_capture_identity_keeps_sweep_points_separate(self):
        fields, values = self.observation_rows()
        fields.append("ConfiguredSNR_dB")
        for row, snr in zip(values, [-30, -20, -20]):
            row.append(snr)
        _, rows = chart("SSB occasion timeline", "air_interface/csv/pbch_trials.csv", fields, values)
        self.assertEqual([int(row["capture_ordinal"]) for row in rows], [1, 2, 3])
        self.assertEqual([float(row["configured_snr_db"]) for row in rows], [-30, -20, -20])

    def test_one_prach_occasion_is_not_a_time_trend(self):
        result, rows = chart("PRACH peak search timeline", "air_interface/csv/prach_trials.csv",
                             ["Slot", "DetectionMetric"], [[5, .87], [5, .89]])
        self.assertIn(b"sparse_prach_peak_evidence", result["img_bytes"])
        self.assertEqual([float(row["correlation_peak"]) for row in rows], [.87, .89])
        self.assertEqual([float(row["occasion_slot"]) for row in rows], [5, 5])
        self.assertTrue(all(row["detection_threshold"] == "" for row in rows))

    def test_actual_single_prach_peak_threshold_comparison_retained(self):
        result, rows = chart("PRACH peak search timeline", "air_interface/csv/prach_trials.csv",
                             ["Slot", "DetectionMetric", "DetectionThreshold"], [[5, .87, .3]])
        self.assertNotIn(b"sparse_prach_peak_evidence", result["img_bytes"])
        self.assertEqual(float(rows[0]["detection_threshold"]), .3)

    def test_ssb_same_slot_remains_same_slot(self):
        result, rows = chart("SSB index timeline", "reports/csv/live_ssb_stage_table.csv",
                             ["Slot", "SSBIndex"], [[1, 0], [1, 1]])
        self.assertIn(b"sparse_ssb_index_events", result["img_bytes"])
        self.assertEqual([float(row["slot"]) for row in rows], [1, 1])
        self.assertEqual([float(row["ssb_index"]) for row in rows], [0, 1])

    def test_missing_ssb_slot_not_replaced_by_row_number(self):
        _, rows = chart("SSB index timeline", "reports/csv/live_ssb_stage_table.csv",
                        ["SSBIndex"], [[0], [1]])
        self.assertTrue(all(row["slot"] == "" for row in rows))

    def test_unmapped_beam_is_not_an_ssb_index(self):
        with self.assertRaisesRegex(ValueError, "actual SSBIndex/SSBIdx"):
            chart("SSB index timeline", "air_interface/csv/pbch_trials.csv",
                  ["Slot", "SelectedBeamIndex"], [[1, 3]])

    def test_fractional_ssb_index_rejected(self):
        with self.assertRaisesRegex(ValueError, "integer identities"):
            chart("SSB index timeline", "reports/csv/live_ssb_stage_table.csv",
                  ["Slot", "SSBIndex"], [[1, .5]])

    def test_failed_acquisition_has_no_ssb_index_timeline(self):
        result, rows = chart("SSB index timeline", "reports/csv/live_ssb_stage_table.csv",
                             ["Slot", "SSBIdentityVerified", "CRCPass", "Notes", "SelectedBeamIndex"],
                             [[1, 0, 0, "configured SSBIdx=3", 3], [2, 0, 0, "", 0]])
        self.assertEqual(result["csv_status"], "unavailable_exact_reason")
        self.assertEqual(result["source_row_count"], 0)
        self.assertNotIn("ssb_index", rows[0])
        self.assertIn("No configured or beam index was substituted", rows[0]["reason"])
        self.assertTrue(m._is_placeholder_materialization_status(result["image_status"]))

    def test_failed_candidate_does_not_join_verified_ssb_timeline(self):
        result, rows = chart("SSB index timeline", "air_interface/csv/pbch_trials.csv",
                             ["Slot", "SSBIndex", "SSBIdentityVerified", "CRCPass"],
                             [[1, 3, 0, 0], [2, 1, 1, 1]])
        self.assertEqual(len(rows), 1)
        self.assertEqual(float(rows[0]["ssb_index"]), 1)
        self.assertEqual(float(rows[0]["slot"]), 2)

    def test_unknown_crc_is_not_proven_acquisition_failure(self):
        with self.assertRaisesRegex(ValueError, "actual SSBIndex/SSBIdx"):
            chart("SSB index timeline", "air_interface/csv/pbch_trials.csv",
                  ["Slot", "SSBIndex", "SSBIdentityVerified", "CRCPass"],
                  [[1, "NaN", 0, "NaN"]])

    def test_acquisition_failure_does_not_hide_invalid_index_encoding(self):
        with self.assertRaisesRegex(ValueError, "integer identities"):
            chart("SSB index timeline", "air_interface/csv/pbch_trials.csv",
                  ["Slot", "SSBIndex", "SSBIdentityVerified", "CRCPass"],
                  [[1, .5, 0, 0]])


if __name__ == "__main__":
    unittest.main()
