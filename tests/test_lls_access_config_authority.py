"""Access YAML serialization authority; these checks do not execute NR PHY."""
import copy
import sys
import unittest
from unittest.mock import patch
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))
import lls_web_dashboard as dash


class AccessConfigurationAuthority(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.authored = yaml.safe_load((REPO_ROOT / "simulator/configs/scenarios/"
                                      "master_geometry_based.yaml").read_text(encoding="utf-8"))

    def test_common_control_and_msg4_survive_repeated_serialization(self):
        control = self.authored["canonical_control"]
        for legacy in (False, True):
            with self.subTest(legacy=legacy):
                payload = copy.deepcopy(self.authored)
                for _ in range(3):
                    payload = dash.canonicalize_browser_config_payload(payload, keep_legacy_aliases=legacy)
                    self.assertEqual(payload["initial_access"], control["initial_access"])
                    self.assertEqual(payload["random_access"]["msg4_dci"], control["random_access"]["msg4_dci"])
                    self.assertEqual(payload["canonical_control"]["initial_access"], control["initial_access"])
                    self.assertEqual(payload["canonical_control"]["random_access"]["msg4_dci"],
                                     control["random_access"]["msg4_dci"])

    def test_access_runtime_mirrors_match_matlab_mapping(self):
        control = self.authored["canonical_control"]["initial_access"]
        resolved = dash.canonicalize_browser_config_payload(self.authored, keep_legacy_aliases=True)
        mapping = [
            ("ssb.enabled", "reference_signals.ssb_enabled"),
            ("mib.enabled", "reference_signals.pbch_enabled"),
            ("ssb.case", "reference_signals.ssb_case"),
            ("ssb.scs_khz", "reference_signals.ssb_scs_khz"),
            ("ssb.lmax", "reference_signals.ssb_lmax"),
            ("ssb.beam_count", "reference_signals.ssb_beam_count"),
            ("ssb.periodicity_ms", "reference_signals.ssb_periodicity_ms"),
            ("sib1.coreset0_from_mib_required", "sib1_and_initial_access.coreset0_from_mib_required"),
            ("sib1.searchspace0_from_mib_required", "sib1_and_initial_access.searchspace0_from_mib_required"),
            ("sib1.decode_from_waveform_required", "sib1_and_initial_access.sib1_decode_from_waveform_required"),
            ("sib1.enabled", "sib1_and_initial_access.sib1_required"),
            ("ssb.enabled", "sib1_and_initial_access.ssb_required"),
            ("mib.enabled", "sib1_and_initial_access.mib_required"),
        ]
        for source, target in mapping:
            with self.subTest(source=source, target=target):
                expected = dash.path_get(control, source)
                self.assertIsNot(expected, dash.PATH_MISSING)
                self.assertEqual(dash.path_get(resolved, target), expected)

    def test_input_and_canonical_mirror_are_not_aliased(self):
        original = copy.deepcopy(self.authored)
        resolved = dash.canonicalize_browser_config_payload(self.authored, keep_legacy_aliases=True)
        resolved["initial_access"]["sib1"]["pdcch_config_common"]["ra_SearchSpace"] = -1
        resolved["random_access"]["msg4_dci"]["ndi"] = -1
        self.assertEqual(self.authored, original)
        self.assertEqual(resolved["canonical_control"]["initial_access"],
                         original["canonical_control"]["initial_access"])
        self.assertEqual(resolved["canonical_control"]["random_access"]["msg4_dci"],
                         original["canonical_control"]["random_access"]["msg4_dci"])

    def test_false_zero_and_empty_are_preserved_not_replaced(self):
        # Transport fidelity only: invalid RA ID 0 must reach runtime validation,
        # not be silently replaced with a usable configured search space.
        payload = copy.deepcopy(self.authored)
        access = payload["canonical_control"]["initial_access"]
        access["ssb"]["enabled"] = False
        access["mib"]["enabled"] = False
        access["sib1"]["pdcch_config_common"]["ra_SearchSpace"] = 0
        access["sib1"]["pdcch_config_common"]["commonSearchSpaceList"] = []
        dci = payload["canonical_control"]["random_access"]["msg4_dci"]
        dci["ndi"] = 0
        dci["harq_ack_repetitions_configured"] = False
        resolved = dash.canonicalize_browser_config_payload(payload, keep_legacy_aliases=True)
        self.assertEqual(resolved["initial_access"], access)
        self.assertEqual(resolved["random_access"]["msg4_dci"], dci)
        self.assertIs(resolved["reference_signals"]["ssb_enabled"], False)
        self.assertIs(resolved["reference_signals"]["pbch_enabled"], False)

    def test_absent_authority_does_not_invent_common_control(self):
        payload = copy.deepcopy(self.authored)
        del payload["canonical_control"]["initial_access"]["sib1"]["pdcch_config_common"]
        del payload["canonical_control"]["random_access"]["msg4_dci"]
        # Also remove the explicit global-YAML Msg4 default in this declared
        # fixture. Removing only the scenario override leaves real authority.
        defaults = copy.deepcopy(dash.load_browser_alias_defaults())
        for default in defaults:
            default.get("random_access", {}).pop("msg4_dci", None)
        with patch.object(dash, "load_browser_alias_defaults", return_value=defaults):
            resolved = dash.canonicalize_browser_config_payload(payload, keep_legacy_aliases=True)
        self.assertNotIn("pdcch_config_common", resolved["initial_access"]["sib1"])
        self.assertNotIn("msg4_dci", resolved["random_access"])

    def test_explicit_msg4_overrides_global_yaml_default(self):
        payload = copy.deepcopy(self.authored)
        dci = payload["canonical_control"]["random_access"]["msg4_dci"]
        # Serializer test values deliberately differ from every catalog default.
        for key, value in dci.items():
            dci[key] = not value if isinstance(value, bool) else value + 1
        resolved = dash.canonicalize_browser_config_payload(payload, keep_legacy_aliases=True)
        self.assertEqual(resolved["random_access"]["msg4_dci"], dci)

    def test_absent_msg4_override_retains_explicit_yaml_default(self):
        payload = copy.deepcopy(self.authored)
        del payload["canonical_control"]["random_access"]["msg4_dci"]
        _, legacy_defaults = dash.load_browser_alias_defaults()
        expected = legacy_defaults["random_access"]["msg4_dci"]
        resolved = dash.canonicalize_browser_config_payload(payload, keep_legacy_aliases=True)
        self.assertEqual(resolved["random_access"]["msg4_dci"], expected)


if __name__ == "__main__":
    unittest.main()
