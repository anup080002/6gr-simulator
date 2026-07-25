#!/usr/bin/env python3
"""Generate the pinned external PDSCH LDPC parity fixtures with py3gpp."""
from __future__ import annotations

import argparse
import csv
import hashlib
from importlib.metadata import version
from pathlib import Path

import numpy as np
import py3gpp

IMPLEMENTATION = "py3gpp"
PINNED_VERSION = "0.6.0"
SOURCE_URL = "https://pypi.org/project/py3gpp/0.6.0/"
WHEEL_SHA256 = "1182b03eed6aa44e1af49df827d2712206189a620fd85985e7b795bef11c9aa9"
CASES = [
    ("EXT-LDPC-BG1-Z15", 293, 0.8, 2, "16QAM", 800),
    ("EXT-LDPC-BG2-Z104", 1000, 0.5, 1, "QPSK", 3000),
]
FIELDS = [
    "CaseID", "Implementation", "Version", "Algorithm", "SourceURL",
    "SourceArtifactSHA256", "A", "R", "TBCRCType", "BGN", "Zc",
    "InputBits", "InputSHA256", "CodeBlockSHA256",
    "ExpectedEncodedSHA256", "Modulation", "RV", "NumLayers", "G",
    "ExpectedRateMatchedSHA256",
]


def digest_int8(values: np.ndarray) -> str:
    raw = np.asarray(values, dtype=np.int8).tobytes(order="F")
    return hashlib.sha256(raw).hexdigest()


def payload(a: int) -> np.ndarray:
    return np.array(
        [bin(i * 13 + a).count("1") & 1 for i in range(a)],
        dtype=np.int8,
    )


def build_row(case: tuple[str, int, float, int, str, int]) -> dict:
    case_id, a, rate, rv, modulation, g = case
    info = py3gpp.nrDLSCHInfo(a, rate)
    bits = payload(a)
    tb_crc = py3gpp.nrCRCEncode(bits, info["CRC"])
    code_blocks = py3gpp.nrCodeBlockSegmentLDPC(tb_crc, info["BGN"])
    encoded = py3gpp.nrLDPCEncode(code_blocks, info["BGN"], algo="sionna")
    rate_matched = py3gpp.nrRateMatchLDPC(
        encoded, g, rv, modulation, 1
    )
    return {
        "CaseID": case_id,
        "Implementation": IMPLEMENTATION,
        "Version": PINNED_VERSION,
        "Algorithm": "sionna",
        "SourceURL": SOURCE_URL,
        "SourceArtifactSHA256": WHEEL_SHA256,
        "A": a,
        "R": format(rate, ".15g"),
        "TBCRCType": info["CRC"],
        "BGN": int(info["BGN"]),
        "Zc": int(info["Zc"]),
        "InputBits": "".join(str(int(v)) for v in bits),
        "InputSHA256": digest_int8(bits),
        "CodeBlockSHA256": digest_int8(code_blocks),
        "ExpectedEncodedSHA256": digest_int8(encoded),
        "Modulation": modulation,
        "RV": rv,
        "NumLayers": 1,
        "G": g,
        "ExpectedRateMatchedSHA256": digest_int8(rate_matched),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).with_name(
            "expected_pdsch_ldpc_external_vectors.csv"
        ),
    )
    args = parser.parse_args()
    actual_version = version(IMPLEMENTATION)
    if actual_version != PINNED_VERSION:
        raise RuntimeError(
            f"Expected {IMPLEMENTATION} {PINNED_VERSION}, got {actual_version}"
        )
    rows = [build_row(case) for case in CASES]
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} external LDPC fixtures to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
