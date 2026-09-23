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
from lls_contract_materializer import _encode_dict_rows
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

    def test_actual_two_port_ul_matches_pusch_applied_matrix(self):
        folder = self.folder.parent / "applied_data_precoder_ul_04"
        weights = list(csv.DictReader((folder / "applied_data_precoder_weights.csv").read_text().splitlines()))
        patterns = list(csv.DictReader((folder / "applied_data_precoder_patterns.csv").read_text().splitlines()))
        grid, source, _ = validate_samples(weights, patterns)
        trial_path = self.folder.parent / "shared_ul_capsule_handoff_01/received_pusch.csv"
        trials = list(csv.DictReader(trial_path.read_text().splitlines()))
        self.assertEqual(len(trials), 1)
        self.assertEqual(source["MatrixSHA256"], trials[0]["AppliedPrecoderMatrixSHA256"])
        self.assertEqual(source["Signal"], "PUSCH")
        self.assertEqual(float(trials[0]["AppliedPrecoderPMI"]), 3)
        self.assertEqual(len(weights), 2)
        self.assertEqual(len(grid), 2701)
        self.assertEqual(float(trials[0]["CRCPass"]), 1)

    def test_pmi_only_cannot_be_a_pattern(self):
        with self.assertRaisesRegex(ValueError, "exact executed weights"):
            _runtime_beam_pattern_chart("beam pattern 3d", {}, lambda _: b"PMI\n0\n", 1)

    @staticmethod
    def outage_sources():
        # Declared publisher fixture, not a simulated acquisition campaign.
        return {
            "reports/csv/run_state.csv": [dict(CanonicalSlotsPerSweepPoint=2,
                CurrentCanonicalSlot=2, DLGrantRows=0, ULGrantRows=0)],
            "reports/csv/slot_trace.csv": [dict(CanonicalSlot=k, SweepPointIndex=1,
                DLGrantCount=0, ULGrantCount=0, DLExecutedGrantCount=0,
                ULExecutedGrantCount=0, DLTrialRows=0, ULTrialRows=0) for k in (1, 2)],
            "air_interface/csv/pbch_trials.csv": [dict(CRCPass=0, Crash=0,
                SSBIdentityVerified=0, SelectedBeamFlag=0)],
            "air_interface/csv/dl_pdsch_trials.csv": [],
            "air_interface/csv/ul_pusch_trials.csv": [],
        }

    @staticmethod
    def materialize_sources(sources):
        payloads = {index: _encode_dict_rows(list(rows[0]) if rows else ["CRCPass"], rows)
                    for index, rows in enumerate(sources.values())}
        existing = {name: dict(artifact_id=index) for index, name in enumerate(sources)}
        return _runtime_beam_pattern_chart("beam pattern 3d", existing, payloads.__getitem__, 1)

    def test_recorded_no_grant_outage_does_not_invent_applied_beam(self):
        result = self.materialize_sources(self.outage_sources())
        self.assertEqual(result["source_mapping_status"], "unavailable")
        self.assertEqual(result["source_row_count"], 0)
        self.assertEqual(result["csv_status"], "unavailable_exact_reason")
        self.assertNotIn(b"Directivity_dBi", result["csv_bytes"])
        self.assertIn(b"no data precoder", result["csv_bytes"])

    def test_missing_or_contradictory_outage_evidence_cannot_hide_missing_beam(self):
        mutations = [
            lambda s: s.pop("air_interface/csv/ul_pusch_trials.csv"),
            lambda s: s["air_interface/csv/dl_pdsch_trials.csv"].append(dict(CRCPass=0)),
            lambda s: s["reports/csv/slot_trace.csv"][0].update(DLGrantCount=1),
            lambda s: s["reports/csv/slot_trace.csv"][0].update(ULExecutedGrantCount=1),
            lambda s: s["reports/csv/slot_trace.csv"][0].update(ULTrialRows="NaN"),
            lambda s: s["reports/csv/slot_trace.csv"][1].update(CanonicalSlot=1),
            lambda s: s["reports/csv/slot_trace.csv"][1].update(SweepPointIndex=2),
            lambda s: s["reports/csv/run_state.csv"][0].update(CurrentCanonicalSlot=1),
            lambda s: s["reports/csv/run_state.csv"][0].update(DLGrantRows=1),
            lambda s: s["air_interface/csv/pbch_trials.csv"][0].update(CRCPass=1),
            lambda s: s["air_interface/csv/pbch_trials.csv"][0].update(Crash=1),
            lambda s: s["air_interface/csv/pbch_trials.csv"].clear(),
        ]
        for mutate in mutations:
            sources = self.outage_sources()
            mutate(sources)
            with self.subTest(mutation=mutate), self.assertRaisesRegex(ValueError, "exact executed weights"):
                self.materialize_sources(sources)

    def test_partial_applied_matrix_still_requires_angular_evidence(self):
        sources = self.outage_sources()
        sources["beamforming/csv/applied_data_precoder_weights.csv"] = self.weights
        with self.assertRaisesRegex(ValueError, "exact executed weights"):
            self.materialize_sources(sources)

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
