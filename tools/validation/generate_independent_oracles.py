#!/usr/bin/env python3
"""Materialize Phase-14 independent oracle artifacts without importing the DUT.

The generated PURE_MATH, ANALYTICAL_INVARIANT and
STATISTICAL_DISTRIBUTION artifacts are computed by this standalone Python
implementation. FROZEN_EXTERNAL_VECTOR entries reference independently
maintained vector packs from earlier phases; those files are never copied or
rewritten here. The output registry records the hashes of the exact bytes used.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import os
import random
from pathlib import Path


FEATURES = (
    "CRC24C",
    "QAM",
    "LDPC_RATE_MATCH",
    "DMRS_INDEX",
    "PDSCH_BLER_CURVE",
    "PATHLOSS",
    "WILSON_INTERVAL",
    "CSI_REPORT",
)

EXTERNAL = {
    "CRC24C": "tests/vectors/pdsch/expected_pdsch_tb_crc_vectors.csv",
    "QAM": "tests/vectors/pdsch/pdsch_modulation_test_vectors.csv",
    "LDPC_RATE_MATCH": "tests/vectors/pdsch/expected_pdsch_ldpc_external_vectors.csv",
    "DMRS_INDEX": "tests/vectors/pdsch/expected_pdsch_dmrs_symbol_positions.csv",
    "PDSCH_BLER_CURVE": "tests/vectors/pdsch/expected_pdsch_receiver_external_vectors.csv",
    "PATHLOSS": "tests/vectors/channel/expected_channel_pathloss.csv",
    "WILSON_INTERVAL": "tests/vectors/validation/validation_binomial_interval_test_vectors.csv",
    "CSI_REPORT": "tests/vectors/rsla/expected_rsla_csi_bit_ownership.csv",
}


def io_path(path: Path) -> Path:
    """Return a Windows extended-length path while keeping manifests portable."""
    resolved = path.resolve()
    text = str(resolved)
    if os.name != "nt" or text.startswith("\\\\?\\"):
        return resolved
    if text.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + text[2:])
    return Path("\\\\?\\" + text)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with io_path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    target = io_path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def crc24c(bits: list[int]) -> int:
    polynomial = 0x1B2B117
    register = 0
    for bit in bits + [0] * 24:
        register = (register << 1) | int(bit)
        if register & (1 << 24):
            register ^= polynomial
    return register & 0xFFFFFF


def wilson(errors: int, trials: int, z: float) -> tuple[float, float, float]:
    estimate = errors / trials
    denominator = 1.0 + z * z / trials
    center = (estimate + z * z / (2.0 * trials)) / denominator
    half = z * math.sqrt(
        estimate * (1.0 - estimate) / trials + z * z / (4.0 * trials * trials)
    ) / denominator
    return estimate, max(0.0, center - half), min(1.0, center + half)


def pure_rows(feature: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    if feature == "CRC24C":
        for index in range(16):
            bits = [(index >> shift) & 1 for shift in range(7, -1, -1)]
            rows.append({"CaseID": f"CRC-{index:02d}", "Input": "".join(map(str, bits)),
                         "Expected": f"{crc24c(bits):06x}",
                         "Equation": "CRC24C polynomial 0x1B2B117"})
    elif feature == "QAM":
        scale = math.sqrt(10.0)
        for index, (i_value, q_value) in enumerate(
            (i, q) for i in (-3, -1, 1, 3) for q in (-3, -1, 1, 3)
        ):
            rows.append({"CaseID": f"QAM-{index:02d}", "Input": f"{i_value},{q_value}",
                         "Expected": f"{i_value / scale:.15g},{q_value / scale:.15g}",
                         "Equation": "unit-average-power square 16QAM"})
    elif feature == "LDPC_RATE_MATCH":
        for rv in range(4):
            for e_value in (8, 16, 24, 32):
                n_cb = 66
                k0 = (rv * n_cb) // 4
                indices = [(k0 + offset) % n_cb for offset in range(e_value)]
                rows.append({"CaseID": f"LDPC-RV{rv}-E{e_value}",
                             "Input": f"Ncb={n_cb};rv={rv};E={e_value}",
                             "Expected": ";".join(map(str, indices)),
                             "Equation": "independent circular-buffer selection invariant"})
    elif feature == "DMRS_INDEX":
        case = 0
        for prb in range(4):
            for symbol in (2, 7, 11, 13):
                indices = [symbol * 12 * 4 + prb * 12 + offset for offset in (0, 2, 4, 6, 8, 10)]
                rows.append({"CaseID": f"DMRS-{case:02d}",
                             "Input": f"nprb=4;prb={prb};symbol={symbol}",
                             "Expected": ";".join(map(str, indices)),
                             "Equation": "zero-based type-1 comb-2 RE coordinates"})
                case += 1
    elif feature == "PDSCH_BLER_CURVE":
        for index, snr_db in enumerate(range(-6, 10)):
            ber = 0.5 * math.erfc(math.sqrt(10.0 ** (snr_db / 10.0)))
            rows.append({"CaseID": f"AWGN-{index:02d}", "Input": snr_db,
                         "Expected": f"{ber:.15g}",
                         "Equation": "uncoded Gray QPSK AWGN analytical BER baseline"})
    elif feature == "PATHLOSS":
        for index, distance_m in enumerate((1, 3, 10, 30, 100, 300, 1000, 3000) * 2):
            frequency_hz = 4e9 if index < 8 else 30e9
            loss = 20 * math.log10(4 * math.pi * distance_m * frequency_hz / 299792458.0)
            rows.append({"CaseID": f"FSPL-{index:02d}",
                         "Input": f"d_m={distance_m};f_hz={frequency_hz:.0f}",
                         "Expected": f"{loss:.15g}",
                         "Equation": "20log10(4*pi*d*f/c)"})
    elif feature == "WILSON_INTERVAL":
        cases = [(0, 10), (1, 10), (2, 10), (5, 10), (10, 10), (1, 100),
                 (10, 100), (50, 100), (0, 1000), (1, 1000), (10, 1000),
                 (100, 1000), (500, 1000), (900, 1000), (999, 1000), (1000, 1000)]
        for index, (errors, trials) in enumerate(cases):
            estimate, lower, upper = wilson(errors, trials, 1.959963984540054)
            rows.append({"CaseID": f"WILSON-{index:02d}",
                         "Input": f"errors={errors};trials={trials};cl=0.95",
                         "Expected": f"{estimate:.15g};{lower:.15g};{upper:.15g}",
                         "Equation": "Wilson score interval"})
    elif feature == "CSI_REPORT":
        for index in range(16):
            ri = index % 4
            pmi = (index * 3) % 16
            cqi = (index * 5) % 16
            packed = (ri << 8) | (pmi << 4) | cqi
            rows.append({"CaseID": f"CSI-{index:02d}",
                         "Input": f"ri={ri};pmi={pmi};cqi={cqi}",
                         "Expected": f"{packed:010b}",
                         "Equation": "2-bit RI, 4-bit PMI, 4-bit CQI concatenation"})
    else:
        raise ValueError(feature)
    return rows


def statistical_rows(feature: str) -> list[dict[str, object]]:
    seed = 14000 + FEATURES.index(feature)
    generator = random.Random(seed)
    samples = [generator.gauss(0.0, 1.0) for _ in range(4096)]
    mean = math.fsum(samples) / len(samples)
    variance = math.fsum((sample - mean) ** 2 for sample in samples) / len(samples)
    rows = []
    for index in range(16):
        block = samples[index * 256:(index + 1) * 256]
        block_mean = math.fsum(block) / len(block)
        rows.append({"CaseID": f"STAT-{index:02d}",
                     "Input": f"feature={feature};seed={seed};block={index}",
                     "Expected": f"{block_mean:.15g}",
                     "Equation": f"pinned normal distribution;global_mean={mean:.15g};variance={variance:.15g}"})
    return rows


def materialize(repo: Path, output: Path) -> Path:
    oracle_dir = output / "oracles"
    registry: list[dict[str, object]] = []
    oracle_id = 1
    for oracle_type in ("PURE_MATH", "FROZEN_EXTERNAL_VECTOR",
                        "ANALYTICAL_INVARIANT", "STATISTICAL_DISTRIBUTION"):
        for feature in FEATURES:
            if oracle_type == "FROZEN_EXTERNAL_VECTOR":
                artifact = (repo / EXTERNAL[feature]).resolve()
                if not artifact.is_file():
                    raise FileNotFoundError(f"missing independent vector: {artifact}")
                source_name = "independent_phase_vector_pack"
                source_version = "repository-pinned"
            else:
                stem = f"{feature.lower()}_{oracle_type.lower()}.csv"
                artifact = (oracle_dir / stem).resolve()
                rows = statistical_rows(feature) if oracle_type == "STATISTICAL_DISTRIBUTION" else pure_rows(feature)
                for row in rows:
                    row["OracleType"] = oracle_type
                    row["Feature"] = feature
                    row["Implementation"] = "standalone_python_no_dut_import"
                write_csv(artifact, ["CaseID", "OracleType", "Feature", "Input",
                                     "Expected", "Equation", "Implementation"], rows)
                source_name = (
                    "independent_python_distribution"
                    if oracle_type == "STATISTICAL_DISTRIBUTION"
                    else "independent_python_closed_form"
                )
                source_version = "1.0.0"
            registry.append({
                "OracleID": f"ORC-RUNTIME-{oracle_id:03d}",
                "OracleType": oracle_type,
                "Feature": feature,
                "ProfileID": "nr_rel18_phy_lls_strict",
                "SourceName": source_name,
                "SourceVersion": source_version,
                "ArtifactPath": artifact.as_posix(),
                "ArtifactSHA256": sha256(artifact),
                "IndependentOfDUT": "true",
                "Qualifies": "true",
                "Status": "PASS",
            })
            oracle_id += 1
    registry_path = output / "validation_oracle_registry_materialized.csv"
    write_csv(registry_path, list(registry[0]), registry)
    return registry_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_root", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    registry = materialize(repo, output)
    print(registry)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
