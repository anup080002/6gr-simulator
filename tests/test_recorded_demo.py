"""Small synthetic *test fixtures* only; never published as exhibit measurements."""
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "apps/build_recorded_demo.py"
spec = importlib.util.spec_from_file_location("recorded_demo", MODULE)
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def save_csv(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(data[0]))
        writer.writeheader()
        writer.writerows(data)


def fixture(root):
    save_json(root / "meta/manifest.json", dict(Status="completed", ResultOk=True, StandardNR=False,
        ExecutionBackend="actual_coded_research_TDD_waveform", SampleRateHz=1000,
        ChannelModel="identity_awgn", HARQFeedbackMode="ideal_error_free_delayed_receiver_CRC_no_control_waveform",
        SampleCount=5, HorizonSeconds=.005, GitCommit="fixture_not_a_real_run"))
    save_json(root / "meta/resolved_config.json", {"meta": {"scenario_id": "TEST_FIXTURE"},
        "frequency": {"center_frequency_hz": 7e9, "bandwidth_hz": 400e6},
        "research_awgn_mimo": {"physical_ports": 2}})
    source = root / "meta/executed_sources/test.m"
    source.parent.mkdir(parents=True)
    source.write_text("% fixture source", encoding="utf-8")
    save_json(root / "meta/executed_source_hashes.json", [{"Path": "C:\\old\\test.m", "SHA256": demo.digest(source)}])
    save_csv(root / "air_interface/csv/timeline.csv", [dict(AbsoluteSlot=i, StartSample=i,
        StopSampleExclusive=i+1, DLActive=int(i in (0, 2)), ULActive=int(i == 1),
        FeedbackDrainSlot=int(i > 2)) for i in range(5)])
    trials, layers = [], []
    for direction, slot, crc, attempt in (("DL", 0, 0, 1), ("UL", 1, 1, 1), ("DL", 2, 1, 2)):
        trials.append(dict(Direction=direction, AbsoluteSlot=slot, TBID=direction+"_tb", TBSBits=80,
            CodedBits=100, Qm=2, Layers=2, TargetCodeRate=.8, CRCPass=crc, TBExact=crc,
            IsRetransmission=int(attempt > 1), HARQAttemptIndex=attempt, RV=2 if attempt > 1 else 0,
            EVMRMS=.03, ReferenceErrorSINRdB=30, Source="actual_coded_research_waveform", PerfectCSI=1,
            StartSample=slot, StopSampleExclusive=slot+1))
        layers.extend(dict(Direction=direction, AbsoluteSlot=slot, Layer=l, ReferenceErrorSINRdB=30,
            Source="decoded_waveform_equalized_symbols_against_transmitted_reference") for l in (1, 2))
    save_csv(root / "reports/csv/trials.csv", trials)
    save_csv(root / "reports/csv/layer_measurements.csv", layers)
    summaries = []
    for direction in ("DL", "UL"):
        events = [t for t in trials if t["Direction"] == direction]
        ledger, feedback = [], []
        for t in events:
            delivered = t["AbsoluteSlot"] + 2
            ledger.append(dict(TransportBlockId=t["TBID"], AttemptIndex=t["HARQAttemptIndex"],
                AttemptSlot=t["AbsoluteSlot"], CrcPass=t["CRCPass"], TBSBits=80,
                CountedGoodputBits=80*t["CRCPass"], FirstSuccessDelivery=t["CRCPass"], FirstSuccessSlot=delivered))
            feedback.append(dict(TBID=t["TBID"], AttemptIndex=t["HARQAttemptIndex"], CRCPass=t["CRCPass"],
                SourceSlot=t["AbsoluteSlot"], AvailableSlot=delivered, DeliveredAtSlot=delivered))
        save_csv(root / f"harq/csv/{direction.lower()}_delivery_ledger.csv", ledger)
        save_csv(root / f"harq/csv/{direction.lower()}_feedback.csv", feedback)
        summaries.append(dict(Direction=direction, Source="actual_coded_research_waveform", TransportBlocks=1,
            TransmissionAttempts=len(events), SuccessfulUniqueTBs=1, DeliveredUniqueBits=80,
            FirstTransmissionBLER=int(direction == "DL"), BLER=0, HorizonSeconds=.005,
            GoodputBitsPerSecond=16000, PendingTransportBlocks=0, DroppedTransportBlocks=0))
    save_csv(root / "reports/csv/summary.csv", summaries)
    receipts = []
    for direction in ("DL", "UL"):
        for point in ("TX", "RX"):
            folder = root / "waveform" / f"{direction.lower()}_{point.lower()}"
            folder.mkdir(parents=True)
            for port in (1, 2):
                row = dict(Direction=direction, CapturePoint=point, Port=port, SampleCount=5,
                    SampleRateHz=1000, CenterFrequencyHz=7e9, ClippedComponents=0,
                    QuantizationMaxError=0, CommonEndpointFullScale=.5)
                for name, hash_name, filename in (("RawMAT", "RawSHA256", "raw.mat"),
                    ("WIQFile", "WIQSHA256", f"port_{port}.wiq"), ("VSAMATFile", "VSAMATSHA256", f"port_{port}.mat")):
                    file = folder / filename
                    file.write_bytes(bytes(20))
                    row[name] = str(Path("old_computer") / file.relative_to(root))
                    row[hash_name] = demo.digest(file)
                receipts.append(row)
    save_csv(root / "waveform/iq_manifest.csv", receipts)


class RecordedDemoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "run"
        fixture(self.root)

    def mutate(self, relative, callback):
        path = self.root / relative
        data = demo.rows(path)
        callback(data)
        save_csv(path, data)

    def test_valid_relocated_evidence_and_delayed_delivery(self):
        data = demo.collect(self.root)
        self.assertEqual(data["summary"]["DL"]["firstBLER"], 100)
        self.assertEqual(data["summary"]["DL"]["residualBLER"], 0)
        self.assertEqual(data["summary"]["DL"]["gbps"], .000016)
        self.assertEqual(next(d["slot"] for d in data["deliveries"] if d["direction"] == "DL"), 4)

    def test_rejects_inflated_goodput(self):
        self.mutate("reports/csv/summary.csv", lambda r: r[0].update(GoodputBitsPerSecond=9e9))
        with self.assertRaisesRegex(ValueError, "Summary mismatch"):
            demo.collect(self.root)

    def test_rejects_duplicate_delivery(self):
        self.mutate("harq/csv/dl_delivery_ledger.csv", lambda r: r.append(r[-1].copy()))
        with self.assertRaises(ValueError):
            demo.collect(self.root)

    def test_rejects_proxy(self):
        self.mutate("reports/csv/trials.csv", lambda r: r[0].update(Source="fast_proxy"))
        with self.assertRaisesRegex(ValueError, "Non-waveform"):
            demo.collect(self.root)

    def test_rejects_false_perfect_csi_label(self):
        self.mutate("reports/csv/trials.csv", lambda r: r[0].update(PerfectCSI=0))
        with self.assertRaisesRegex(ValueError, "perfect-CSI"):
            demo.collect(self.root)

    def test_rejects_corrupt_iq(self):
        (self.root / "waveform/dl_tx/port_1.wiq").write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "SHA256"):
            demo.collect(self.root)

    def test_rejects_nonfinite_measurement(self):
        self.mutate("reports/csv/trials.csv", lambda r: r[0].update(EVMRMS="NaN"))
        with self.assertRaisesRegex(ValueError, "Non-finite"):
            demo.collect(self.root)

    def test_rejects_missing_layer(self):
        self.mutate("reports/csv/layer_measurements.csv", lambda r: r.pop())
        with self.assertRaisesRegex(ValueError, "layer"):
            demo.collect(self.root)

    def test_rejects_noncausal_feedback(self):
        self.mutate("harq/csv/dl_feedback.csv", lambda r: r[-1].update(DeliveredAtSlot=0))
        with self.assertRaisesRegex(ValueError, "Noncausal"):
            demo.collect(self.root)

    def test_rejects_path_traversal(self):
        with self.assertRaisesRegex(ValueError, "traversal"):
            demo.iq_path(self.root.resolve(), "waveform/../../private.mat")

    def test_rejects_incomplete_run(self):
        path = self.root / "meta/manifest.json"
        data = json.loads(path.read_text())
        data["Status"] = "running"
        save_json(path, data)
        with self.assertRaisesRegex(ValueError, "completed"):
            demo.collect(self.root)

    def test_safe_html_and_no_overwrite(self):
        path = self.root / "meta/resolved_config.json"
        data = json.loads(path.read_text())
        data["meta"]["scenario_id"] = "</script><script>alert('untrusted')</script>"
        save_json(path, data)
        output = Path(self.temp.name) / "demo"
        page = demo.build(self.root, output)
        self.assertNotIn(data["meta"]["scenario_id"], page.read_text(encoding="utf-8"))
        with self.assertRaisesRegex(ValueError, "overwrite"):
            demo.build(self.root, output)


if __name__ == "__main__":
    unittest.main()
