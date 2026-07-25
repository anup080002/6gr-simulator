#!/usr/bin/env python3
"""Generate one frozen, externally implemented PDSCH receiver waveform."""
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
WHEEL_SHA256 = (
    "1182b03eed6aa44e1af49df827d2712206189a620fd85985e7b795bef11c9aa9"
)
GENERATION_COMMAND = (
    "python generate_external_pdsch_receiver_fixture.py "
    "--output expected_pdsch_receiver_external_vectors.csv"
)
FIELDS = [
    "CaseID", "FixtureSchemaVersion", "Implementation", "Version",
    "SourceURL", "SourceArtifactSHA256", "Generator",
    "GeneratorSHA256", "GenerationCommand", "NCellID", "NSizeGrid",
    "NStartGrid", "SubcarrierSpacingKHz", "CyclicPrefix", "NSlot",
    "NFrame", "Nfft", "SampleRate", "CyclicPrefixLengths", "RNTI",
    "DataScramblingIdentityNID", "PRBSet", "SymbolAllocation",
    "MappingType", "Modulation", "NumLayers", "TargetCodeRate", "RV",
    "TransportBlockSize", "RateMatchedBitCount", "DMRSConfigurationType",
    "DMRSTypeAPosition", "DMRSAdditionalPosition", "DMRSLength",
    "NumCDMGroupsWithoutData", "NIDNSCID", "NSCID", "DMRSPortSet",
    "ReservedIndices0Based", "DataIndices0Based", "DMRSIndices0Based",
    "TransportBlockBits", "RawRateMatchedBits", "ScrambledBits",
    "QAMReal", "QAMImag", "DMRSReal", "DMRSImag", "GridReal",
    "GridImag", "WaveformReal", "WaveformImag",
    "ExpectedTransportBlockSHA256", "ExpectedRateMatchedSHA256",
    "ExpectedScrambledSHA256", "ExpectedQAMSHA256",
    "ExpectedDMRSSHA256", "ExpectedGridSHA256",
    "ExpectedWaveformSHA256", "ExpectedCRCPass", "ExpectedStageNames",
    "ExpectedStageElementCounts",
]


def payload(length: int) -> np.ndarray:
    return np.array(
        [bin(index * 13 + length).count("1") & 1 for index in range(length)],
        dtype=np.int8,
    )


def digest_int8(values: np.ndarray) -> str:
    return hashlib.sha256(
        np.asarray(values, dtype=np.int8).tobytes(order="F")
    ).hexdigest()


def complex_bytes(values: np.ndarray) -> bytes:
    vector = np.asarray(values, dtype=np.complex128).reshape(-1, order="F")
    interleaved = np.column_stack((vector.real, vector.imag)).astype("<f8")
    return interleaved.tobytes(order="C")


def digest_complex(values: np.ndarray) -> str:
    return hashlib.sha256(complex_bytes(values)).hexdigest()


def int_text(values: np.ndarray | list[int]) -> str:
    return "|".join(str(int(value)) for value in np.asarray(values).reshape(-1))


def float_text(values: np.ndarray) -> str:
    return "|".join(
        format(float(value), ".17g")
        for value in np.asarray(values).reshape(-1, order="F")
    )


def build_row(generator_path: Path) -> dict[str, object]:
    a = 293
    target_rate = 0.8
    rv = 2
    modulation = "16QAM"
    g = 800
    rnti = 4660
    nid = 42

    info = py3gpp.nrDLSCHInfo(a, target_rate)
    transport_block = payload(a)
    tb_crc = py3gpp.nrCRCEncode(transport_block, info["CRC"])
    code_blocks = py3gpp.nrCodeBlockSegmentLDPC(tb_crc, info["BGN"])
    encoded = py3gpp.nrLDPCEncode(code_blocks, info["BGN"], algo="sionna")
    rate_matched = np.asarray(
        py3gpp.nrRateMatchLDPC(
            encoded, g, rv, modulation, 1
        ),
        dtype=np.int8,
    ).reshape(-1)
    cinit = rnti * (2**15) + nid
    scrambling_sequence = np.asarray(
        py3gpp.nrPRBS(cinit, g), dtype=np.int8
    ).reshape(-1)
    scrambled = np.bitwise_xor(rate_matched, scrambling_sequence)
    qam = np.asarray(
        py3gpp.nrPDSCH(
            [rate_matched], [modulation], 1, nid, rnti
        ),
        dtype=np.complex128,
    ).reshape(-1)
    if qam.size != 200:
        raise RuntimeError(f"Expected 200 QAM symbols, got {qam.size}")

    carrier = py3gpp.nrCarrierConfig(
        NCellID=nid, NSizeGrid=2, NStartGrid=0, NSlot=0,
        NFrame=0, SubcarrierSpacing=30,
    )
    pdsch = py3gpp.nrPDSCHConfig()
    pdsch.Nid = nid
    pdsch.NSizeBWP = 2
    pdsch.NStartBWP = 0
    pdsch.PRBSet = [0, 1]
    pdsch.SymbolAllocation = [0, 14]
    pdsch.MappingType = "A"
    pdsch.Modulation = "qam16"
    pdsch.NumLayers = 1
    pdsch.RNTI = rnti
    pdsch.DMRS.DMRSTypeAPosition = 2
    pdsch.DMRS.DMRSAdditionalPosition = 0
    pdsch.DMRS.DMRSLength = 1
    pdsch.DMRS.DMRSConfigurationType = 1
    pdsch.DMRS.NIDNSCID = nid
    pdsch.DMRS.NSCID = 0

    dmrs_indices = np.asarray(
        py3gpp.nrPDSCHDMRSIndices(carrier, pdsch), dtype=np.int64
    ).reshape(-1)
    dmrs = np.asarray(
        py3gpp.nrPDSCHDMRS(pdsch, carrier), dtype=np.complex128
    ).reshape(-1)
    allocation = np.arange(2 * 12 * 14, dtype=np.int64)
    non_dmrs = np.setdiff1d(allocation, dmrs_indices, assume_unique=True)
    reserved = non_dmrs[:124]
    data_indices = non_dmrs[124:]
    if data_indices.size != 200:
        raise RuntimeError(
            f"Expected exactly 200 data RE, got {data_indices.size}"
        )

    grid = np.zeros((24, 14), dtype=np.complex128)
    grid[data_indices % 24, data_indices // 24] = qam
    grid[dmrs_indices % 24, dmrs_indices // 24] = dmrs
    waveform, ofdm_info = py3gpp.nrOFDMModulate(
        carrier=carrier, grid=grid, Nfft=128, SampleRate=3_840_000,
        Windowing=0,
    )
    waveform = np.asarray(waveform, dtype=np.complex128).reshape(-1)

    expected_stages = [
        "ofdm_demodulation", "dmrs_extraction",
        "channel_noise_estimation", "ptrs_correction",
        "data_extraction", "equalization", "layer_demap",
        "soft_demodulation", "llr_descrambling", "dlsch_decoding",
    ]
    expected_counts = [336, 12, 1, 0, 200, 200, 200, 800, 800, a]
    return {
        "CaseID": "EXT-RX-SISO-16QAM-BG1-001",
        "FixtureSchemaVersion": "external_pdsch_receiver/v1",
        "Implementation": IMPLEMENTATION,
        "Version": PINNED_VERSION,
        "SourceURL": SOURCE_URL,
        "SourceArtifactSHA256": WHEEL_SHA256,
        "Generator": generator_path.name,
        "GeneratorSHA256": hashlib.sha256(
            generator_path.read_bytes()
        ).hexdigest(),
        "GenerationCommand": GENERATION_COMMAND,
        "NCellID": nid,
        "NSizeGrid": 2,
        "NStartGrid": 0,
        "SubcarrierSpacingKHz": 30,
        "CyclicPrefix": "normal",
        "NSlot": 0,
        "NFrame": 0,
        "Nfft": 128,
        "SampleRate": 3_840_000,
        "CyclicPrefixLengths": int_text(
            ofdm_info["CyclicPrefixLengths"]
        ),
        "RNTI": rnti,
        "DataScramblingIdentityNID": nid,
        "PRBSet": "0|1",
        "SymbolAllocation": "0|14",
        "MappingType": "A",
        "Modulation": modulation,
        "NumLayers": 1,
        "TargetCodeRate": format(target_rate, ".15g"),
        "RV": rv,
        "TransportBlockSize": a,
        "RateMatchedBitCount": g,
        "DMRSConfigurationType": 1,
        "DMRSTypeAPosition": 2,
        "DMRSAdditionalPosition": 0,
        "DMRSLength": 1,
        "NumCDMGroupsWithoutData": 1,
        "NIDNSCID": nid,
        "NSCID": 0,
        "DMRSPortSet": "0",
        "ReservedIndices0Based": int_text(reserved),
        "DataIndices0Based": int_text(data_indices),
        "DMRSIndices0Based": int_text(dmrs_indices),
        "TransportBlockBits": int_text(transport_block),
        "RawRateMatchedBits": int_text(rate_matched),
        "ScrambledBits": int_text(scrambled),
        "QAMReal": float_text(qam.real),
        "QAMImag": float_text(qam.imag),
        "DMRSReal": float_text(dmrs.real),
        "DMRSImag": float_text(dmrs.imag),
        "GridReal": float_text(grid.real),
        "GridImag": float_text(grid.imag),
        "WaveformReal": float_text(waveform.real),
        "WaveformImag": float_text(waveform.imag),
        "ExpectedTransportBlockSHA256": digest_int8(transport_block),
        "ExpectedRateMatchedSHA256": digest_int8(rate_matched),
        "ExpectedScrambledSHA256": digest_int8(scrambled),
        "ExpectedQAMSHA256": digest_complex(qam),
        "ExpectedDMRSSHA256": digest_complex(dmrs),
        "ExpectedGridSHA256": digest_complex(grid),
        "ExpectedWaveformSHA256": digest_complex(waveform),
        "ExpectedCRCPass": 1,
        "ExpectedStageNames": "|".join(expected_stages),
        "ExpectedStageElementCounts": int_text(expected_counts),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).with_name(
            "expected_pdsch_receiver_external_vectors.csv"
        ),
    )
    args = parser.parse_args()
    actual_version = version(IMPLEMENTATION)
    if actual_version != PINNED_VERSION:
        raise RuntimeError(
            f"Expected {IMPLEMENTATION} {PINNED_VERSION}, got {actual_version}"
        )
    row = build_row(Path(__file__).resolve())
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=FIELDS, lineterminator="\n"
        )
        writer.writeheader()
        writer.writerow(row)
    print(f"Wrote 1 external receiver fixture to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
