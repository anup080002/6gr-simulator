"""Independent analysis of retained receiver symbols, NOT a new PHY execution.

Coding basis: TS 38.212 v15.11.0, Table 5.3.3.3-1; circular small-block rate
matching in 5.4.3. PUCCH scrambling/QPSK: TS 38.211 6.3.2.5.1/6.3.2.5.2.
https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/15.11.00_60/ts_138212v151100p.pdf
Only receiver symbols, installed identities and receiver variance enter the
likelihood. Transmitted bits are read afterward for independent error scoring.
No threshold fitting, waveform regeneration, run mutation or qualification.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path

import h5py
import numpy as np
import yaml

# Mathematical basis entries, row i and columns k=0..10 of the cited table.
BASIS = np.array([[int(bit) for bit in row] for row in (
    "11000000001", "11100000011", "10010010111", "10110000101",
    "11110001001", "11001011101", "10101010111", "10011001101",
    "11011001011", "10111010011", "10100111011", "11100110101",
    "10010101111", "11010101011", "10001101001", "11001111011",
    "11101110010", "10011100100", "11011111000", "10000110000",
    "10100010001", "11010000011", "10001001101", "11101000111",
    "11111011110", "11000111001", "10110100110", "11110101110",
    "10101110100", "10111111100", "11111111111", "10000000000",
)], dtype=np.int64)


def long_path(path: Path) -> Path:
    absolute = str(path.resolve())
    if os.name == "nt" and not absolute.startswith("\\\\?\\"):
        absolute = "\\\\?\\" + absolute
    return Path(absolute)


def sha256(path: Path) -> str:
    with long_path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def scrambling(nid: int, rnti: int, length: int) -> np.ndarray:
    if not (0 <= nid <= 1023 and 0 <= rnti <= 65535 and length > 0):
        raise ValueError("Invalid configured PUCCH scrambling identity/length")
    init = (rnti << 15) + nid
    x1 = np.zeros(length + 1631, dtype=np.int64)
    x2 = np.zeros_like(x1)
    x1[0] = 1
    x2[:31] = (init >> np.arange(31)) & 1
    for n in range(length + 1600):
        x1[n + 31] = x1[n + 3] ^ x1[n]
        x2[n + 31] = x2[n + 3] ^ x2[n + 2] ^ x2[n + 1] ^ x2[n]
    return x1[1600:1600 + length] ^ x2[1600:1600 + length]


def references(count: int, symbols: int, nid: int, rnti: int):
    if not (3 <= count <= 11 and symbols > 0):
        raise ValueError("Only 3--11 bit format-2 QPSK observations are supported")
    words = (np.arange(2**count)[:, None] >> np.arange(count)) & 1
    mother = (BASIS[:, :count] @ words.T) % 2
    code = mother[np.arange(2 * symbols) % 32]
    scrambled = code ^ scrambling(nid, rnti, 2 * symbols)[:, None]
    ref = ((1 - 2 * scrambled[0::2]) + 1j * (1 - 2 * scrambled[1::2])) / np.sqrt(2)
    return words, ref


def decode_symbols(received, variance: float, count: int, nid: int, rnti: int):
    received = np.asarray(received).reshape(-1)
    if not np.all(np.isfinite(received)) or not np.isfinite(variance) or variance <= 0:
        raise ValueError("Finite symbols and positive receiver variance are required")
    words, ref = references(count, received.size, nid, rnti)
    logp = -np.sum(np.abs(received[:, None] - ref)**2, axis=0) / variance
    weights = np.exp(logp - logp.max())
    probabilities = weights / weights.sum()
    winner = int(np.argmax(logp))
    norm = np.linalg.norm(received) * np.sqrt(received.size)
    metric = float(np.max(np.abs(received.conj() @ ref)) / norm) if norm else 0.0
    return words[winner], float(probabilities[winner]), metric, int(np.sum(logp == logp.max()))


def decode_with_response(received, response, covariance, count, nid, rnti):
    """Exact conditional QPSK likelihood y=g*s+z using retained MMSE evidence."""
    received, response, covariance = [np.asarray(x).reshape(-1) for x in (received, response, covariance)]
    if received.shape != response.shape or received.shape != covariance.shape:
        raise ValueError("Every symbol needs its own response and output variance")
    if not all(np.all(np.isfinite(x)) for x in (received, response, covariance)) or np.any(covariance <= 0):
        raise ValueError("Finite MMSE response and positive covariance required")
    words, ref = references(count, received.size, nid, rnti)
    logp = -np.sum(np.abs(received[:, None] - response[:, None] * ref)**2 / covariance[:, None], axis=0)
    weights = np.exp(logp - logp.max())
    winner = int(np.argmax(logp))
    return words[winner], float(weights[winner] / weights.sum()), int(np.sum(logp == logp.max()))


def number(group, name):
    value = np.asarray(group[name][()])
    if value.size != 1:
        raise ValueError(f"Expected scalar evidence: {name}")
    return float(value.item())


def complex_array(dataset):
    value = dataset[()]
    return value["real"] + 1j * value["imag"] if value.dtype.names else value


def resource_value(file, name, index):
    dataset = file[f"capture/Config/phy/pucch/resources/{name}"]
    if dataset.dtype.kind == "O":
        return float(file[dataset[()].ravel()[index]][()].item())
    return float(dataset[()].ravel()[index])


def analyze(run_folder: Path, output: Path, policy_file: Path):
    root = long_path(run_folder)
    output = long_path(output)
    if output.exists():
        raise FileExistsError("Retain earlier diagnostics; use a new output directory")
    policy = yaml.safe_load(policy_file.read_text(encoding="utf-8"))
    gate = float(policy["candidate_word_minimum_posterior"])
    if not .5 < gate < 1:
        raise ValueError("Frozen conditional-word threshold must be between .5 and 1")
    trial_path = root / "air_interface/csv/pucch_trials.csv"
    with trial_path.open(encoding="utf-8-sig", newline="") as stream:
        trials = list(csv.DictReader(stream))
    captures = list(root.rglob("pucch_rx_*.mat"))
    rows = []
    for trial in trials:
        digest = trial["ReceiverContextDigest"]
        matches = [p for p in captures if p.name.endswith("_" + digest + ".mat")]
        if len(matches) != 1 or int(trial["ReceiverPUCCHFormat"]) != 2:
            raise ValueError("Require one exact format-2 capture per receive-context digest")
        capture = matches[0]
        with h5py.File(capture, "r") as file:
            rx = file["capture/ReceivedResult"]
            count = int(number(rx, "ExpectedPayloadBitCount"))
            rnti = int(trial["RNTI"])
            resource_id = int(trial["ReceiverPUCCHResourceId"])
            ids = file["capture/Config/phy/pucch/resources/id"]
            indices = [i for i in range(ids.size) if resource_value(file, "id", i) == resource_id]
            if len(indices) != 1 or resource_value(file, "format", indices[0]) != 2:
                raise ValueError("Installed resource must match the recorded receiver allocation")
            nid = int(resource_value(file, "nid", indices[0]))
            eq = rx["EqualizerInfo/EqualizerResult"]
            symbols = complex_array(eq["EqualizedSymbols"]).ravel()
            variance = number(rx, "DecodeNoiseInterferenceVariance")
            bits, posterior, metric, maxima = decode_symbols(symbols, variance, count, nid, rnti)
            recorded = rx["DecodedSequence1"][()].ravel().astype(int)
            if not np.array_equal(bits, recorded):
                raise AssertionError("Independent ML word differs from retained MATLAB decoder")
            if abs(metric - number(rx, "DetectionMetric")) > 1e-12:
                raise AssertionError("Independent normalized correlation differs from retained MATLAB")
            word = "".join(map(str, bits))
            if word != trial["UCIDecodedBitVector"]:
                raise AssertionError("Capture/CSV decoded-word identity mismatch")
            # Transmitted audit first enters here, after independent receiver results.
            expected = trial["UCIExpectedBitVector"]
            if len(expected) != count or set(expected) - {"0", "1"}:
                raise ValueError("Retained transmitted-bit scoring evidence is malformed")
            bit_errors = sum(a != b for a, b in zip(word, expected))
            covariance = complex_array(eq["OutputNoiseInterferenceCovariance"]).real.ravel()
            response = complex_array(eq["EffectiveResponseWH"]).ravel()
            aware_bits, aware_posterior, aware_maxima = decode_with_response(
                symbols, response, covariance, count, nid, rnti)
            aware_word = "".join(map(str, aware_bits))
            aware_errors = sum(a != b for a, b in zip(aware_word, expected))
            capture_hash = sha256(capture)
            rows.append(dict(Slot=int(trial["Slot"]), SymbolCount=symbols.size,
                PayloadBits=count, IndependentDecodedBits=word, BitErrors=bit_errors,
                DecoderAndMetricReplayMatch=True, DetectionMetric=metric,
                DetectionThreshold=number(rx, "DetectionThreshold"),
                ConditionalWordPosterior=posterior, CandidateMinimumPosterior=gate,
                CandidateWordAccepted=bool(maxima == 1 and posterior >= gate),
                ReceiverScalarVariance=variance, PerREVarianceMin=float(covariance.min()),
                PerREVarianceMax=float(covariance.max()),
                MMSEGainMin=float(np.abs(response).min()), MMSEGainMax=float(np.abs(response).max()),
                EqualizerAwareDecodedBits=aware_word, EqualizerAwareBitErrors=aware_errors,
                EqualizerAwareConditionalWordPosterior=aware_posterior,
                EqualizerAwareCandidateWordAccepted=bool(aware_maxima == 1 and aware_posterior >= gate),
                CaptureSHA256=capture_hash))
    if not rows:
        raise ValueError("No physical PUCCH trials to analyze")
    output.mkdir(parents=True)
    with (output / "receiver_symbol_analysis.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    scope = dict(Scope="independent_retained_receiver_symbol_analysis_not_new_waveform_execution",
        SourceRun=str(run_folder), PolicyFile=str(policy_file),
        AnalysisScriptSHA256=sha256(Path(__file__)), PolicySHA256=sha256(policy_file),
        SourceTrialCSV_SHA256=sha256(trial_path),
        CandidatePolicyInstalled=False, DetectorQualified=False, ThresholdTuned=False,
        TrialCount=len(rows), BitCorruptTrials=sum(r["BitErrors"] > 0 for r in rows),
        CandidateAcceptedTrials=sum(r["CandidateWordAccepted"] for r in rows),
        CandidateAcceptedCorruptTrials=sum(r["CandidateWordAccepted"] and r["BitErrors"] > 0 for r in rows),
        EqualizerAwareCandidateAcceptedTrials=sum(r["EqualizerAwareCandidateWordAccepted"] for r in rows),
        EqualizerAwareCandidateAcceptedCorruptTrials=sum(r["EqualizerAwareCandidateWordAccepted"] and r["EqualizerAwareBitErrors"] > 0 for r in rows))
    (output / "scope.json").write_text(json.dumps(scope, indent=2), encoding="utf-8")
    print(json.dumps(scope, indent=2))
    for row in rows:
        print(row["Slot"], row["BitErrors"], row["ConditionalWordPosterior"], row["CandidateWordAccepted"],
              row["EqualizerAwareConditionalWordPosterior"], row["EqualizerAwareCandidateWordAccepted"])
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_folder", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--policy", type=Path, default=Path("simulator/configs/validation/pucch_short_uci_null_math.yaml"))
    args = parser.parse_args()
    analyze(args.run_folder, args.output, args.policy)
