"""Build an offline exhibit from completed research-run evidence, never live KPIs.

No PHY execution, resampling, instrument control or synthetic measurements.
Only Python's standard library is required; the HTML has no network dependencies.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path, PureWindowsPath


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    result = float(value)
    require(math.isfinite(result), f"Non-finite measurement: {value}")
    return result


def integer(value):
    result = number(value)
    require(result == int(result), f"Non-integer count: {value}")
    return int(result)


def flag(value):
    require(str(value).lower() in ("0", "1", "true", "false"), "Invalid boolean")
    return str(value).lower() in ("1", "true")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        result = list(csv.DictReader(stream))
    require(bool(result), f"Missing/empty evidence: {path}")
    return result


def iq_path(root, recorded):
    # Relocate a copied run without trusting absolute paths from another PC.
    parts = PureWindowsPath(recorded).parts
    require(parts.count("waveform") == 1, "IQ path must identify waveform/ exactly once")
    tail = parts[parts.index("waveform"):]
    require(".." not in tail, "IQ path traversal")
    path = root.joinpath(*tail).resolve()
    require(path.is_relative_to(root), "IQ path escapes run folder")
    return path


def collect(root):
    root = Path(root).resolve()
    audited = {}

    def audit(path, expected=None):
        actual = digest(path)
        if expected is not None:
            require(actual == expected.lower(), f"SHA256 mismatch: {path}")
        audited[path.relative_to(root).as_posix()] = actual

    def read_json(relative):
        path = root / relative
        audit(path)
        return json.loads(path.read_text(encoding="utf-8-sig"))

    def read_rows(relative):
        path = root / relative
        audit(path)
        return rows(path)

    manifest = read_json("meta/manifest.json")
    require(manifest["Status"] == "completed" and manifest["ResultOk"] is True,
            "Exhibit requires a completed payload-accepted recording; preserve failed evidence separately")
    require(manifest["ExecutionBackend"] == "actual_coded_research_TDD_waveform",
            "Unsupported execution backend: no proxy or live-measurement relabeling")
    require(manifest["StandardNR"] is False, "This exhibit adapter is for explicitly labeled research runs")
    require(manifest["ChannelModel"] == "identity_awgn" and
            manifest["HARQFeedbackMode"] == "ideal_error_free_delayed_receiver_CRC_no_control_waveform",
            "This exhibit adapter requires the labeled identity-AWGN/ideal-feedback benchmark")
    cfg = read_json("meta/resolved_config.json")
    sources = read_json("meta/executed_source_hashes.json")
    for source in sources:
        audit(root / "meta/executed_sources" / PureWindowsPath(source["Path"]).name,
              source["SHA256"])
    fs = number(manifest["SampleRateHz"])
    samples = integer(manifest["SampleCount"])
    horizon = number(manifest["HorizonSeconds"])
    require(fs > 0 and samples > 0 and math.isclose(samples / fs, horizon), "Invalid sample clock")
    timeline = read_rows("air_interface/csv/timeline.csv")
    cursor = 0
    ticks = []
    for index, row in enumerate(timeline):
        start, stop = integer(row["StartSample"]), integer(row["StopSampleExclusive"])
        require(integer(row["AbsoluteSlot"]) == index and start == cursor and stop > start,
                "Non-contiguous timeline")
        require(not (flag(row["DLActive"]) and flag(row["ULActive"])), "TDD direction overlap")
        ticks.append({"slot": index, "startMs": start / fs * 1000,
                      "endMs": stop / fs * 1000, "dl": flag(row["DLActive"]),
                      "ul": flag(row["ULActive"]), "drain": flag(row["FeedbackDrainSlot"])})
        cursor = stop
    require(cursor == samples, "Timeline and IQ horizon differ")
    trials = read_rows("reports/csv/trials.csv")
    summaries = read_rows("reports/csv/summary.csv")
    require(len(summaries) == 2 and {s["Direction"] for s in summaries} == {"DL", "UL"},
            "Expected one actual summary per direction")
    require(all(t["Direction"] in ("DL", "UL") for t in trials), "Unknown trial direction")
    layer_rows = read_rows("reports/csv/layer_measurements.csv")
    events = []
    keys = set()
    for t in trials:
        direction, slot = t["Direction"], integer(t["AbsoluteSlot"])
        require(t["Source"] == "actual_coded_research_waveform", "Non-waveform trial")
        require(flag(t["PerfectCSI"]), "Dashboard perfect-CSI label does not match trial")
        require(0 <= slot < len(ticks) and ticks[slot][direction.lower()], "Trial outside active slot")
        require((direction, slot) not in keys, "Duplicate transmission slot")
        keys.add((direction, slot))
        require(integer(t["StartSample"]) == integer(timeline[slot]["StartSample"]) and
                integer(t["StopSampleExclusive"]) == integer(timeline[slot]["StopSampleExclusive"]),
                "Trial clock mismatch")
        crc, exact = flag(t["CRCPass"]), flag(t["TBExact"])
        require(not crc or exact, "CRC pass with incorrect payload")
        layers = integer(t["Layers"])
        lr = [r for r in layer_rows if r["Direction"] == direction and integer(r["AbsoluteSlot"]) == slot]
        require(len(lr) == layers and {integer(r["Layer"]) for r in lr} == set(range(1, layers + 1)),
                "Missing/duplicate layer measurements")
        require(all(r["Source"] == "decoded_waveform_equalized_symbols_against_transmitted_reference"
                    for r in lr), "Unverified layer measurement source")
        events.append({"direction": direction, "slot": slot, "tb": t["TBID"],
                       "bits": integer(t["TBSBits"]), "codedBits": integer(t["CodedBits"]),
                       "qam": 2 ** integer(t["Qm"]), "rank": layers,
                       "rate": number(t["TargetCodeRate"]), "crc": crc, "exact": exact,
                       "retx": flag(t["IsRetransmission"]), "attempt": integer(t["HARQAttemptIndex"]),
                       "rv": integer(t["RV"]), "evm": number(t["EVMRMS"]) * 100,
                       "sinr": number(t["ReferenceErrorSINRdB"]),
                       "layerSinr": [number(r["ReferenceErrorSINRdB"]) for r in sorted(lr, key=lambda r: integer(r["Layer"]))]})
    require(len(layer_rows) == sum(e["rank"] for e in events), "Unmatched layer rows")
    by_direction, deliveries = {}, []
    for direction in ("DL", "UL"):
        s = next(s for s in summaries if s["Direction"] == direction)
        require(s["Source"] == "actual_coded_research_waveform", "Non-waveform summary")
        selected = [e for e in events if e["direction"] == direction]
        initial = [e for e in selected if not e["retx"]]
        require(initial and len({e["tb"] for e in initial}) == len(initial), "Duplicate/missing new TBs")
        ledger = read_rows(f"harq/csv/{direction.lower()}_delivery_ledger.csv")
        feedback = read_rows(f"harq/csv/{direction.lower()}_feedback.csv")
        require(len(ledger) == len(selected) == len(feedback), "Unmatched HARQ attempt/feedback population")
        attempt_map = {(e["tb"], e["attempt"]): e for e in selected}
        require(len(attempt_map) == len(selected), "Duplicate HARQ attempt")
        feedback_map = {(f["TBID"], integer(f["AttemptIndex"])): f for f in feedback}
        require(len(feedback_map) == len(feedback) and set(feedback_map) == set(attempt_map),
                "Duplicate or missing feedback")
        for key, f in feedback_map.items():
            e = attempt_map[key]
            require(flag(f["CRCPass"]) == e["crc"] and integer(f["SourceSlot"]) == e["slot"] and
                    e["slot"] <= integer(f["AvailableSlot"]) <= integer(f["DeliveredAtSlot"]) < len(ticks),
                    "Noncausal or mismatched feedback")
        seen_attempts, delivered = set(), set()
        total = 0
        for row in ledger:
            key = (row["TransportBlockId"], integer(row["AttemptIndex"]))
            require(key in attempt_map and key not in seen_attempts, "Unmatched/duplicate ledger attempt")
            seen_attempts.add(key)
            event = attempt_map[key]
            require(integer(row["AttemptSlot"]) == event["slot"] and flag(row["CrcPass"]) == event["crc"]
                    and integer(row["TBSBits"]) == event["bits"], "Ledger differs from decoder")
            counted = integer(row["CountedGoodputBits"])
            if flag(row["FirstSuccessDelivery"]):
                require(event["crc"] and event["tb"] not in delivered and counted == event["bits"],
                        "Duplicate or unsupported successful payload")
                delivered.add(event["tb"])
                delivery_slot = integer(row["FirstSuccessSlot"])
                require(event["slot"] <= delivery_slot < len(ticks), "Delivery outside recorded clock")
                matches = [f for f in feedback if f["TBID"] == event["tb"] and integer(f["AttemptIndex"]) == event["attempt"]]
                require(len(matches) == 1 and flag(matches[0]["CRCPass"]) and
                        integer(matches[0]["DeliveredAtSlot"]) == delivery_slot and
                        integer(matches[0]["SourceSlot"]) == event["slot"], "Delivery feedback mismatch")
                deliveries.append({"direction": direction, "slot": delivery_slot, "bits": counted})
            else:
                require(counted == 0, "Unsuccessful/repeated attempt counted as goodput")
            total += counted
        first_bler = sum(not e["crc"] for e in initial) / len(initial)
        residual = 1 - len(delivered) / len(initial)
        require(integer(s["TransportBlocks"]) == len(initial) and
                integer(s["TransmissionAttempts"]) == len(selected) and
                integer(s["SuccessfulUniqueTBs"]) == len(delivered) and
                integer(s["DeliveredUniqueBits"]) == total, "Summary populations disagree")
        for field, expected in (("FirstTransmissionBLER", first_bler), ("BLER", residual),
                                ("HorizonSeconds", horizon), ("GoodputBitsPerSecond", total / horizon)):
            require(math.isclose(number(s[field]), expected, rel_tol=1e-10, abs_tol=1e-12), f"Summary mismatch: {field}")
        require(integer(s["PendingTransportBlocks"]) == 0 and integer(s["DroppedTransportBlocks"]) == 0,
                "Pending or dropped payloads in accepted recording")
        by_direction[direction] = {"gbps": total / horizon / 1e9, "firstBLER": first_bler * 100,
                                   "residualBLER": residual * 100, "unique": len(initial),
                                   "attempts": len(selected), "retransmissions": len(selected) - len(initial),
                                   "meanEVM": sum(e["evm"] for e in selected) / len(selected),
                                   "meanSINR": sum(e["sinr"] for e in selected) / len(selected)}
    iq = read_rows("waveform/iq_manifest.csv")
    endpoints = {}
    for r in iq:
        key = (r["Direction"], r["CapturePoint"])
        require(key[0] in ("DL", "UL") and key[1] in ("TX", "RX"), "Unknown IQ endpoint")
        endpoints.setdefault(key, []).append(r)
        require(integer(r["SampleCount"]) == samples and number(r["SampleRateHz"]) == fs and
                number(r["CenterFrequencyHz"]) == number(cfg["frequency"]["center_frequency_hz"]),
                "IQ timing/frequency mismatch")
        require(integer(r["ClippedComponents"]) == 0 and 0 <= number(r["QuantizationMaxError"]) <= .5 / 32767 + 1e-14,
                "IQ clipping/quantization failure")
        for file_field, hash_field in (("RawMAT", "RawSHA256"), ("WIQFile", "WIQSHA256"), ("VSAMATFile", "VSAMATSHA256")):
            path = iq_path(root, r[file_field])
            relative = path.relative_to(root).as_posix()
            if relative not in audited:
                audit(path, r[hash_field])
            require(audited[relative] == r[hash_field].lower(), "Conflicting IQ hashes")
            r[file_field] = relative
        require(iq_path(root, r["WIQFile"]).stat().st_size == samples * 4, "Wrong WIQ byte count")
    ports = integer(cfg["research_awgn_mimo"]["physical_ports"])
    require(set(endpoints) == {(d, p) for d in ("DL", "UL") for p in ("TX", "RX")}, "Missing endpoint")
    for group in endpoints.values():
        require(len(group) == ports and {integer(r["Port"]) for r in group} == set(range(1, ports + 1)),
                "Missing or duplicate physical port")
        require(len({number(r["CommonEndpointFullScale"]) for r in group}) == 1 and
                number(group[0]["CommonEndpointFullScale"]) > 0, "Inconsistent endpoint scaling")
    return {"kind": "recorded_simulator_replay_not_live_RF", "manifest": manifest,
            "scenario": cfg["meta"]["scenario_id"], "frequency": cfg["frequency"],
            "ports": ports, "horizonMs": horizon * 1000, "sampleRate": fs, "samples": samples,
            "summary": by_direction, "timeline": ticks, "events": events, "deliveries": deliveries,
            "iq": iq, "sourceHashes": audited}


def build(run_folder, output_folder):
    output = Path(output_folder).resolve()
    require(not output.exists(), "Use a new output folder; never overwrite an exhibit")
    data = collect(run_folder)
    template = Path(__file__).with_name("recorded_demo.html").read_text(encoding="utf-8")
    encoded = json.dumps(data, ensure_ascii=True, allow_nan=False)
    embedded = encoded.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    output.mkdir(parents=True)
    (output / "index.html").write_text(template.replace("__RECORDED_DATA__", embedded), encoding="utf-8")
    (output / "replay_data.json").write_text(encoded, encoding="utf-8")
    (output / "artifact_audit.json").write_text(json.dumps({"Status": "passed", "LiveRFVerified": False,
        "KeysightImportVerifiedByThisBuilder": False, "SourceFolder": str(Path(run_folder).resolve()),
        "SourceHashes": data["sourceHashes"], "HTMLSHA256": digest(output / "index.html")}, indent=2), encoding="utf-8")
    with (output / "instrument_handoff.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(data["iq"][0]))
        writer.writeheader()
        writer.writerows(data["iq"])
    return output / "index.html"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_folder", type=Path)
    parser.add_argument("output_folder", type=Path)
    args = parser.parse_args()
    print(build(args.run_folder, args.output_folder))
