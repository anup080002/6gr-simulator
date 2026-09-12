"""Focused beam provenance/rendering checks using a captured shared-TX fixture."""
from __future__ import annotations

import copy
import csv
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
from lls_applied_beam import validate_samples, render_surface
from lls_contract_materializer import _runtime_beam_pattern_chart
sys.path.insert(0, str(ROOT / "tools"))
from lls_csv_semantics import _audit_applied_data_precoder, audit_run


class AppliedBeamTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = ROOT / "docs/lls/evidence_20260913/applied_data_precoder_03"
        cls.payloads = {}
        cls.existing = {}
        for i, name in enumerate(("weights", "patterns"), 1):
            path = f"beamforming/csv/applied_data_precoder_{name}.csv"
            payload = (cls.folder / Path(path).name).read_bytes()
            cls.payloads[i] = payload
            cls.existing[path] = {"artifact_id": i}
            setattr(cls, name, list(csv.DictReader(payload.decode("utf-8-sig").splitlines())))

    def test_actual_capture_roundtrip_and_surface(self):
        grid, source, selected = validate_samples(self.weights, self.patterns)
        self.assertEqual(len(grid), 2701)
        self.assertEqual(float(source["StartSample"]), 7680)
        surface = render_surface(grid, source, selected, "Applied data beam")
        self.assertIn(b"<polygon", surface)
        self.assertIn(b"not an OTA measurement", surface)
        chart = _runtime_beam_pattern_chart("beam pattern 3d", self.existing, self.payloads.__getitem__, 1)
        self.assertEqual(chart["csv_bytes"], self.payloads[2])
        self.assertEqual(chart["source_row_count"], len(self.patterns))

    def test_pmi_only_cannot_be_a_pattern(self):
        with self.assertRaisesRegex(ValueError, "exact executed weights"):
            _runtime_beam_pattern_chart("beam pattern 3d", {}, lambda _: b"PMI\n0\n", 1)

    def test_tampered_coefficient_rejected(self):
        rows = copy.deepcopy(self.weights)
        rows[0]["WeightReal"] = "0.5"
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            validate_samples(rows, self.patterns)

    def test_original_truncated_decimal_capture_is_not_hash_exact(self):
        folder = self.folder.parent / "applied_data_precoder_01"
        weights = list(csv.DictReader((folder / "applied_data_precoder_weights.csv").read_text().splitlines()))
        patterns = list(csv.DictReader((folder / "applied_data_precoder_patterns.csv").read_text().splitlines()))
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            validate_samples(weights, patterns)

    def test_invalid_sample_rate_rejected(self):
        rows = copy.deepcopy(self.weights)
        rows[0]["SampleRate_Hz"] = "0"
        with self.assertRaisesRegex(ValueError, "time/frequency coordinates"):
            validate_samples(rows, self.patterns)

    def test_missing_element_rejected(self):
        with self.assertRaises(ValueError):
            validate_samples(self.weights[1:], self.patterns)

    def test_missing_angular_cell_rejected(self):
        with self.assertRaisesRegex(ValueError, "Incomplete applied beam angular grid"):
            validate_samples(self.weights, self.patterns[1:])

    def test_wrong_pattern_identity_rejected(self):
        rows = copy.deepcopy(self.patterns)
        rows[0]["StartSample"] = "999"
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            validate_samples(self.weights, rows)

    def test_requested_pmi_has_no_effect(self):
        rows = copy.deepcopy(self.weights)
        for row in rows:
            row["RequestedPrecoderPMI"] = "999"
        self.assertEqual(validate_samples(rows, self.patterns)[0], validate_samples(self.weights, self.patterns)[0])

    def test_semantic_audit_requires_both_matching_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / "beamforming/csv"
            folder.mkdir(parents=True)
            (folder / "applied_data_precoder_weights.csv").write_bytes(self.payloads[1])
            checks = _audit_applied_data_precoder(root)
            self.assertEqual(len(checks), 2)
            self.assertTrue(all(not check.passed for check in checks))
            self.assertFalse(audit_run(root)["summary"][0]["ok"])
            (folder / "applied_data_precoder_patterns.csv").write_bytes(self.payloads[2])
            self.assertTrue(all(check.passed for check in _audit_applied_data_precoder(root)))
            self.assertTrue(audit_run(root)["summary"][0]["ok"])


if __name__ == "__main__":
    unittest.main()
