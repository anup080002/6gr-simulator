import csv
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_contract_materializer as m


class FullConstellationSource(unittest.TestCase):
    def setUp(self):
        capture = ROOT / "docs/lls/evidence_20260913/ul_constellation_handoff_01/air_interface/csv/ul_constellation_samples.csv"
        self.payload = capture.read_bytes()
        self.rows = list(csv.DictReader(self.payload.decode().splitlines()))
        self.path = "air_interface/csv/ul_constellation_samples.csv"

    def test_full_capture_wins_over_duplicate_aliases(self):
        existing = {name: {"artifact_id": i} for i, name in enumerate((self.path,
            "air_interface/csv/ul_constellation_preview.csv", "reports/csv/equalized_constellations.csv"), 1)}
        result = m._specialized_chart_materialization("post-equalization constellation", existing, lambda _: self.payload, 1)
        _, rows = m._decode_csv_dicts(result["csv_bytes"])
        self.assertEqual(len(rows), 3522)
        self.assertEqual(result["source_row_count"], len(self.rows))
        self.assertEqual(result["source_table_path"], self.path)
        self.assertEqual(result["img_bytes"].count(b'fill-opacity="0.72"'), 450)
        for actual, source in zip(rows, self.rows):
            self.assertEqual(float(actual["x_value"]), float(source["RawEqualizedReal"]))
            self.assertEqual(float(actual["y_value"]), float(source["RawEqualizedImag"]))

    def test_posteq_cannot_be_labeled_preeq(self):
        with self.assertRaisesRegex(ValueError, "different receiver plane"):
            m._specialized_chart_materialization("pre-equalization constellation",
                {self.path: {"artifact_id": 1}}, lambda _: self.payload, 1)

    def test_full_materializer_preserves_missing_preeq_as_explicit_unavailable(self):
        result = m._materialize_specialized_chart_or_unavailable(
            "pre-equalization constellation",
            {self.path: {"artifact_id": 1}}, lambda _: self.payload, 1)
        self.assertEqual(result["csv_status"], "unavailable_exact_reason")
        self.assertEqual(result["source_row_count"], 0)
        self.assertEqual(result["source_mapping_status"],
                         "unavailable_exact_plane_not_captured")
        self.assertIn("were not substituted", result["note"])

        result = m._materialize_specialized_chart_or_unavailable(
            "post-equalization constellation",
            {self.path: {"artifact_id": 1}}, lambda _: self.payload, 1)
        self.assertEqual(result["csv_status"],
                         "specialized_runtime_constellation_dataset")
        self.assertEqual(result["source_row_count"], len(self.rows))

    def test_unlabeled_fitted_samples_rejected(self):
        payload = m._encode_csv(["Direction", "EqualizedReal", "EqualizedImag"], [["UL", 1, 1]])
        with self.assertRaisesRegex(ValueError, "no-payload-fit provenance"):
            m._specialized_chart_materialization("post-equalization constellation",
                {self.path: {"artifact_id": 1}}, lambda _: payload, 1)

    def test_reference_preview_limit_matches_published_256(self):
        refs = [(float(i % 16), float(i // 16)) for i in range(256)]
        svg = m._render_scatter_panels_svg("reference limit", "test fixture only",
            [("UL", [(0., 0., "UL")], refs)], [])
        self.assertEqual(svg.count(b'r="4.0" fill="#cbd5e1"'), 256)


if __name__ == "__main__":
    unittest.main()
