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


if __name__ == "__main__":
    unittest.main()
