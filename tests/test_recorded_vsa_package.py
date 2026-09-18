import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from test_recorded_demo import fixture, save_csv
import build_recorded_demo as demo

AVAILABLE = importlib.util.find_spec("scipy") is not None
if AVAILABLE:
    import numpy as np
    from scipy.io import loadmat, savemat
    import package_recorded_vsa as pack


@unittest.skipUnless(AVAILABLE, "Optional SciPy packaging dependency not installed")
class VSAPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "run"
        fixture(self.root)
        receipts = demo.rows(self.root / "waveform/iq_manifest.csv")
        for r in receipts:
            path = demo.iq_path(self.root.resolve(), r["VSAMATFile"])
            savemat(path, {"Y": np.full((5, 1), .1 + .2j * int(r["Port"]), dtype=np.complex64),
                          "XDelta": .001, "InputCenter": 7e9, "InputZoom": 1, "XDomain": 2})
            r["VSAMATSHA256"] = demo.digest(path)
        save_csv(self.root / "waveform/iq_manifest.csv", receipts)
        self.output = Path(self.temp.name) / "package"

    def test_exact_two_port_headers_and_values(self):
        pack.package(self.root, self.output)
        joint = loadmat(self.output / "dl_tx_2ch_vsa.mat")
        source = loadmat(self.root / "waveform/dl_tx/port_1.mat")
        self.assertTrue(np.array_equal(joint["Y1"], source["Y"]))
        receipt = json.loads((self.output / "vsa_recordings.json").read_text())
        self.assertFalse(receipt["InstrumentImportVerified"])
        with self.assertRaisesRegex(ValueError, "preserve"):
            pack.package(self.root, self.output)

    def test_header_mismatch_even_with_matching_file_hash(self):
        file = self.root / "waveform/dl_tx/port_1.mat"
        data = {k: v for k, v in loadmat(file).items() if not k.startswith("_")}
        data["XDelta"] = .002
        savemat(file, data)
        receipts = demo.rows(self.root / "waveform/iq_manifest.csv")
        receipts[0]["VSAMATSHA256"] = demo.digest(file)
        save_csv(self.root / "waveform/iq_manifest.csv", receipts)
        with self.assertRaisesRegex(ValueError, "header"):
            pack.package(self.root, self.output)


if __name__ == "__main__":
    unittest.main()
