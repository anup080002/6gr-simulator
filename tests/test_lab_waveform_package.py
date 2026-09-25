"""Small explicit unit fixtures, never promoted to primary campaign evidence."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
import numpy as np
from scipy.io import loadmat
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"apps"))
from build_lab_waveform_package import export_port, iq_stats, read_iq, truth, verify_native_cp
from vxg_vsa_demo_dashboard import validate_physical, load_physical_files, build_dashboard
from seal_lab_waveform_package import verify
from build_lab_waveform_package import digest
import pandas as pd


class LabPackageTests(unittest.TestCase):
    def test_sealed_inventory_detects_changed_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); data=root/"unit.txt"; data.write_bytes(b"UNIT FIXTURE ONLY")
            manifest={"Status":"digital_package_complete","Artifacts":[
                {"Path":data.name,"Bytes":data.stat().st_size,"SHA256":digest(data)}]}
            (root/"manifest.json").write_text(json.dumps(manifest),encoding="utf-8")
            self.assertEqual(verify(root),manifest)
            data.write_bytes(b"CHANGED BYTE DATA")
            with self.assertRaisesRegex(ValueError,"Changed artifact"): verify(root)

    def test_sealed_inventory_detects_unlisted_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/"manifest.json").write_text(json.dumps({"Status":"digital_package_complete","Artifacts":[]}),encoding="utf-8")
            (root/"unlisted.txt").write_bytes(b"UNIT FIXTURE ONLY")
            with self.assertRaisesRegex(ValueError,"unlisted"): verify(root)

    def test_sealed_dashboard_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); (root/"manifest.json").write_text("{}",encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"immutable"): build_dashboard(root)

    def test_exact_exports_and_common_scale(self):
        rng=np.random.default_rng(41)
        a=(rng.standard_normal(512)+1j*rng.standard_normal(512))*.1
        b=.21*np.exp(.37j)*a
        scale=max(abs(a.real).max(),abs(a.imag).max(),abs(b.real).max(),abs(b.imag).max())
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            for i,x in enumerate((a,b),1):
                receipts=export_port(x,folder,f"p{i}",scale,491520000,7e9,384e6)
                self.assertEqual(len(receipts),4)
                self.assertTrue(all(r["ExactReadback"] and not r["Resampled"] for r in receipts))
                self.assertTrue(all(r["Samples"]==512 for r in receipts))
                v=loadmat(folder/f"p{i}_vsa.mat")
                self.assertEqual(v["XDelta"].item(),1/491520000)
                self.assertEqual(v["InputSpan"].item(),384e6)
                self.assertTrue(np.array_equal(v["Y"].ravel(),(x/scale).astype(np.complex64)))
            va=loadmat(folder/"p1_vsa.mat")["Y"].ravel()
            vb=loadmat(folder/"p2_vsa.mat")["Y"].ravel()
            self.assertTrue(np.allclose(vb/va,.21*np.exp(.37j),rtol=2e-6))

    def test_reject_clipping(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError,"Playback clipping"):
                export_port(np.ones(512,dtype=complex),Path(temp),"bad",.5,491520000,7e9,384e6)

    def test_binary_truncation(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"unit.iq64"; path.write_bytes(b"x"*17)
            with self.assertRaisesRegex(ValueError,"Truncated"): read_iq(path)

    def test_papr_full_and_active_populations(self):
        x=np.r_[np.zeros(512),np.ones(512)].astype(complex)
        s=iq_stats(x,np.arange(1024)>=512)
        self.assertAlmostEqual(s["PAPRFullFrame_dB"],10*np.log10(2))
        self.assertEqual(s["PAPRActiveSlots_dB"],0)

    def test_nonfinite_rejected(self):
        with self.assertRaises(ValueError): iq_stats(np.array([1,np.nan],complex))

    def test_exact_cp_from_samples(self):
        rng=np.random.default_rng(7); blocks=[]
        for length in (20,12,12):
            x=rng.standard_normal(128)+1j*rng.standard_normal(128)
            blocks.append(np.r_[x[-length:],x])
        starts,lengths=verify_native_cp(np.concatenate(blocks),128,3)
        self.assertEqual(lengths.tolist(),[20,12,12])
        self.assertEqual(starts.tolist(),[0,148,288])
        corrupted=np.concatenate(blocks); corrupted[0]+=1
        with self.assertRaises(ValueError): verify_native_cp(corrupted,128,3)

    def test_boolean_population(self):
        self.assertEqual(truth(pd.Series([True,False,1,0,"true","false"])).tolist(),[True,False,True,False,True,False])

    def fixture(self):
        expected={"profiles":{"mcs26":{}},"config":{"frequency":{"center_frequency_hz":7e9,"bandwidth_hz":400e6},"mimo":{"n_layers":2}}}
        data={"schema_version":1,"evidence_mode":"physical_rf","instrument_idn":"UNIT TEST ONLY",
              "captured_utc":"2026-09-25T00:00:00Z","direction":"DL","profile":"mcs26","carrier_hz":7e9,
              "bandwidth_hz":400e6,"rank":2,"measurement_scope":"per_layer_data_re",
              "metrics":{"evm_rms":{"value":1.2,"unit":"percent","definition":"sqrt_sum_error_energy_over_sum_reference_energy"}}}
        return data,expected

    def test_physical_valid_scope(self):
        d,e=self.fixture(); self.assertEqual(validate_physical(d,e),d)

    def test_physical_reject_wrong_units(self):
        d,e=self.fixture(); d["metrics"]["evm_rms"]["unit"]="dB"
        with self.assertRaises(ValueError): validate_physical(d,e)

    def test_physical_reject_other_carrier(self):
        d,e=self.fixture(); d["carrier_hz"]=6e9
        with self.assertRaises(ValueError): validate_physical(d,e)

    def test_physical_reject_simulation(self):
        d,e=self.fixture(); d["evidence_mode"]="simulated_awgn"
        with self.assertRaises(ValueError): validate_physical(d,e)

    def test_physical_reject_missing_identity(self):
        d,e=self.fixture(); del d["instrument_idn"]
        with self.assertRaises(ValueError): validate_physical(d,e)

    def test_physical_reject_nonfinite(self):
        d,e=self.fixture(); d["metrics"]["evm_rms"]["value"]=float("nan")
        with self.assertRaises(ValueError): validate_physical(d,e)

    def test_physical_requires_timezone(self):
        d,e=self.fixture(); d["captured_utc"]="2026-09-25T00:00:00"
        with self.assertRaises(ValueError): validate_physical(d,e)

    def test_physical_trace_hash_and_units(self):
        import hashlib
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"constellation.csv"; path.write_text("I,Q\n0.1,0.2\n0.3,-0.4\n",encoding="ascii")
            entry={"path":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"unit":"normalized_reference_symbol"}
            d={"files":{"constellation":entry}}
            self.assertEqual(load_physical_files(temp,d)["constellation"]["total"],2)
            entry["unit"]="dBm"
            with self.assertRaises(ValueError): load_physical_files(temp,d)
            entry["unit"]="normalized_reference_symbol"; entry["sha256"]="0"*64
            with self.assertRaises(ValueError): load_physical_files(temp,d)


if __name__=="__main__": unittest.main()
