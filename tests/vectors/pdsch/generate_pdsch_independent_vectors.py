#!/usr/bin/env python3
"""Generate independent, specification-derived PDSCH/DL-SCH phase vectors.

This script intentionally does not call MATLAB or 5G Toolbox.  It creates
small deterministic oracles for PDSCH scrambling, square-QAM modulation,
codeword-to-layer mapping, TB CRC/base-graph selection, TBS determination,
DM-RS table cases, and resource-ownership unions.  The MATLAB DUT must load
these files and compare its production results field by field.
"""
from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Iterable, Sequence

ROOT = Path(__file__).resolve().parent


def write_csv(name: str, fieldnames: Sequence[str], rows: Iterable[dict]) -> Path:
    path = ROOT / name
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for row in rows:
            w.writerow(row)
    return path


def bit_text(bits: Sequence[int]) -> str:
    return "".join(str(int(b)) for b in bits)


def num_text(values: Sequence[int | float], sep: str = "|") -> str:
    out = []
    for value in values:
        if isinstance(value, float):
            out.append(format(value, ".15g"))
        else:
            out.append(str(value))
    return sep.join(out)


def round_half_up(value: float) -> int:
    """3GPP-style nearest-integer rounding for non-negative quantities.

    Python's built-in round() uses ties-to-even.  The transport-block-size
    procedure uses ordinary nearest-integer rounding, so use floor(x+0.5)
    explicitly to avoid a silent half-way disagreement.
    """
    if value < 0:
        raise ValueError("round_half_up expects a non-negative value")
    return math.floor(value + 0.5)


def complex_text(values: Sequence[complex]) -> str:
    return "|".join(f"{z.real:.15g}{z.imag:+.15g}j" for z in values)


# ---------------------------------------------------------------------------
# TS 38.211 clause 5.2.1 Gold sequence and clause 7.3.1.1 PDSCH scrambling.
# ---------------------------------------------------------------------------
def gold_sequence(c_init: int, length: int, nc: int = 1600) -> list[int]:
    if not 0 <= c_init < 2**31:
        raise ValueError("c_init out of 31-bit range")
    if length < 0:
        raise ValueError("negative sequence length")
    total = nc + length + 31
    x1 = [0] * total
    x2 = [0] * total
    x1[0] = 1
    for i in range(31):
        x2[i] = (c_init >> i) & 1
    for n in range(total - 31):
        x1[n + 31] = (x1[n + 3] + x1[n]) & 1
        x2[n + 31] = (x2[n + 3] + x2[n + 2] + x2[n + 1] + x2[n]) & 1
    return [(x1[n + nc] + x2[n + nc]) & 1 for n in range(length)]


def pdsch_c_init(rnti: int, q: int, nid: int) -> int:
    if not 0 <= rnti <= 65535:
        raise ValueError("RNTI out of range")
    if q not in (0, 1):
        raise ValueError("codeword index q must be 0 or 1")
    if not 0 <= nid <= 1023:
        raise ValueError("PDSCH data scrambling identity out of range")
    return rnti * 2**15 + q * 2**14 + nid


def build_scrambling_vectors() -> tuple[list[dict], list[dict]]:
    cases = [
        ("SCR-001", 1, 0, 0, 32, "zeros"),
        ("SCR-002", 0x1234, 0, 42, 64, "alternating01"),
        ("SCR-003", 0x1234, 1, 42, 64, "alternating10"),
        ("SCR-004", 0xFFFF, 0, 1007, 96, "prbs9"),
        ("SCR-005", 0x4601, 0, 321, 128, "ones"),
        ("SCR-006", 0x4601, 1, 321, 128, "indexparity"),
        ("SCR-007", 0x0001, 0, 1023, 31, "alternating01"),
        ("SCR-008", 0xBEEF, 1, 0, 127, "prbs9"),
        ("SCR-009", 0x1001, 0, 512, 160, "zeros"),
        ("SCR-010", 0x1001, 1, 512, 160, "ones"),
        ("SCR-011", 0x0000, 0, 0, 48, "indexparity"),
        ("SCR-012", 0xABCD, 0, 77, 72, "alternating10"),
    ]

    def pattern(kind: str, n: int) -> list[int]:
        if kind == "zeros":
            return [0] * n
        if kind == "ones":
            return [1] * n
        if kind == "alternating01":
            return [i & 1 for i in range(n)]
        if kind == "alternating10":
            return [1 - (i & 1) for i in range(n)]
        if kind == "indexparity":
            return [bin(i).count("1") & 1 for i in range(n)]
        if kind == "prbs9":
            state = 0x1FF
            result = []
            for _ in range(n):
                result.append(state & 1)
                fb = ((state >> 4) ^ (state >> 8)) & 1
                state = (state >> 1) | (fb << 8)
            return result
        raise ValueError(kind)

    inputs: list[dict] = []
    expected: list[dict] = []
    for cid, rnti, q, nid, length, kind in cases:
        bits = pattern(kind, length)
        init = pdsch_c_init(rnti, q, nid)
        seq = gold_sequence(init, length)
        scrambled = [a ^ b for a, b in zip(bits, seq)]
        inputs.append({
            "CaseID": cid,
            "RNTI": rnti,
            "CodewordIndexQ": q,
            "DataScramblingIdentityNID": nid,
            "Length": length,
            "InputPattern": kind,
            "InputBits": bit_text(bits),
            "ExpectedStatus": "PASS",
        })
        expected.append({
            "CaseID": cid,
            "CInit": init,
            "GoldBits": bit_text(seq),
            "ScrambledBits": bit_text(scrambled),
            "GoldOnes": sum(seq),
            "ScrambledOnes": sum(scrambled),
            "Status": "PASS",
        })
    return inputs, expected


# ---------------------------------------------------------------------------
# TS 38.211 clause 5.1 square-QAM mapping.
# ---------------------------------------------------------------------------
QAM_INFO = {
    "QPSK": (2, 2.0),
    "16QAM": (4, 10.0),
    "64QAM": (6, 42.0),
    "256QAM": (8, 170.0),
    "1024QAM": (10, 682.0),
}


def axis_amplitude(axis_bits: Sequence[int]) -> int:
    """Nested 3GPP Gray-PAM amplitude for one I/Q axis."""
    m = len(axis_bits)
    if m == 1:
        return 1 - 2 * int(axis_bits[0])
    inner = 2 - (1 - 2 * int(axis_bits[-1]))
    for idx in range(m - 2, 0, -1):
        weight = 2 ** (m - idx)
        inner = weight - (1 - 2 * int(axis_bits[idx])) * inner
    return (1 - 2 * int(axis_bits[0])) * inner


def qam_modulate(bits: Sequence[int], modulation: str) -> list[complex]:
    qm, norm2 = QAM_INFO[modulation]
    if len(bits) % qm:
        raise ValueError("bit length not divisible by Qm")
    out: list[complex] = []
    norm = math.sqrt(norm2)
    for i in range(0, len(bits), qm):
        group = [int(v) for v in bits[i:i + qm]]
        i_bits = group[0::2]
        q_bits = group[1::2]
        out.append(complex(axis_amplitude(i_bits), axis_amplitude(q_bits)) / norm)
    return out


def build_modulation_vectors() -> tuple[list[dict], list[dict]]:
    rows_in: list[dict] = []
    rows_out: list[dict] = []
    cid = 1
    for mod, (qm, norm2) in QAM_INFO.items():
        patterns = [
            [0] * (qm * 4),
            [1] * (qm * 4),
            [(i + 1) & 1 for i in range(qm * 6)],
            [bin(i * 7 + qm).count("1") & 1 for i in range(qm * 8)],
        ]
        for pidx, bits in enumerate(patterns):
            case = f"MOD-{cid:03d}"
            cid += 1
            sym = qam_modulate(bits, mod)
            rows_in.append({
                "CaseID": case,
                "Modulation": mod,
                "Qm": qm,
                "BitCount": len(bits),
                "InputPatternIndex": pidx,
                "InputBits": bit_text(bits),
                "ExpectedStatus": "PASS",
            })
            mean_power = sum(abs(v) ** 2 for v in sym) / len(sym)
            rows_out.append({
                "CaseID": case,
                "NormalizationDenominatorSquared": norm2,
                "SymbolCount": len(sym),
                "ExpectedSymbols": complex_text(sym),
                "MeanPowerForVector": format(mean_power, ".15g"),
                "Status": "PASS",
            })
    # Negative cases exercise strict input validation.
    neg = [
        ("MOD-NEG-001", "4096QAM", 12, "000000000000", "UnsupportedNRModulation"),
        ("MOD-NEG-002", "64QAM", 6, "01010", "BitCountNotDivisibleByQm"),
        ("MOD-NEG-003", "16QAM", 4, "0102", "NonBinaryInput"),
        ("MOD-NEG-004", "", 0, "0101", "MissingModulation"),
    ]
    for case, mod, qm, bits, err in neg:
        rows_in.append({
            "CaseID": case,
            "Modulation": mod,
            "Qm": qm,
            "BitCount": len(bits),
            "InputPatternIndex": -1,
            "InputBits": bits,
            "ExpectedStatus": "ERROR",
            "ExpectedError": err,
        })
        rows_out.append({"CaseID": case, "Status": "ERROR", "ExpectedError": err})
    return rows_in, rows_out


# ---------------------------------------------------------------------------
# TS 38.211 clause 7.3.1.3 codeword-to-layer mapping.
# ---------------------------------------------------------------------------
def layer_counts(rank: int) -> list[int]:
    if 1 <= rank <= 4:
        return [rank]
    return {5: [2, 3], 6: [3, 3], 7: [3, 4], 8: [4, 4]}[rank]


def build_layer_vectors() -> tuple[list[dict], list[dict]]:
    inputs: list[dict] = []
    outputs: list[dict] = []
    for rank in range(1, 9):
        counts = layer_counts(rank)
        cw_symbols: list[list[int]] = []
        for q, count in enumerate(counts):
            # Six symbols per layer, with visibly separate CW ranges.
            cw_symbols.append([q * 1000 + i for i in range(count * 6)])
        case = f"LAYER-R{rank}"
        inputs.append({
            "CaseID": case,
            "Rank": rank,
            "NumCodewords": len(counts),
            "LayerCountPerCodeword": num_text(counts),
            "Codeword0Symbols": num_text(cw_symbols[0]),
            "Codeword1Symbols": num_text(cw_symbols[1]) if len(cw_symbols) > 1 else "",
            "ExpectedStatus": "PASS",
        })
        layer_id = 0
        for q, count in enumerate(counts):
            d = cw_symbols[q]
            for local_layer in range(count):
                seq = d[local_layer::count]
                outputs.append({
                    "CaseID": case,
                    "Rank": rank,
                    "LayerIndex": layer_id,
                    "SourceCodeword": q,
                    "LayerIndexWithinCodeword": local_layer,
                    "ExpectedSymbols": num_text(seq),
                    "SymbolCount": len(seq),
                    "Status": "PASS",
                })
                layer_id += 1
    for case, rank, ncw, err in [
        ("LAYER-NEG-001", 0, 1, "RankOutOfRange"),
        ("LAYER-NEG-002", 9, 2, "RankOutOfRange"),
        ("LAYER-NEG-003", 4, 2, "CodewordCountMismatch"),
        ("LAYER-NEG-004", 5, 1, "CodewordCountMismatch"),
    ]:
        inputs.append({
            "CaseID": case,
            "Rank": rank,
            "NumCodewords": ncw,
            "ExpectedStatus": "ERROR",
            "ExpectedError": err,
        })
        outputs.append({"CaseID": case, "Rank": rank, "Status": "ERROR", "ExpectedError": err})
    return inputs, outputs


# ---------------------------------------------------------------------------
# TS 38.212 CRC and LDPC base graph selection.
# ---------------------------------------------------------------------------
CRC_POLY_EXPONENTS = {
    "16": [16, 12, 5, 0],
    "24A": [24, 23, 18, 17, 14, 11, 10, 7, 6, 5, 4, 3, 1, 0],
}


def crc_remainder(bits: Sequence[int], poly_name: str) -> list[int]:
    exps = CRC_POLY_EXPONENTS[poly_name]
    degree = max(exps)
    poly = [1 if power in exps else 0 for power in range(degree, -1, -1)]
    work = [int(v) for v in bits] + [0] * degree
    for i in range(len(bits)):
        if work[i]:
            for j, value in enumerate(poly):
                work[i + j] ^= value
    return work[-degree:]


def select_tb_crc(a: int) -> str:
    return "24A" if a > 3824 else "16"


def select_base_graph(a: int, rate: float) -> int:
    if a <= 292 or (a <= 3824 and rate <= 0.67) or rate <= 0.25:
        return 2
    return 1


TBS_TABLE_SMALL = [
    24,32,40,48,56,64,72,80,88,96,104,112,120,128,136,144,152,160,168,176,
    184,192,208,224,240,256,272,288,304,320,336,352,368,384,408,432,456,480,
    504,528,552,576,608,640,672,704,736,768,808,848,888,928,984,1032,1064,
    1128,1160,1192,1224,1256,1288,1320,1352,1416,1480,1544,1608,1672,1736,
    1800,1864,1928,2024,2088,2152,2216,2280,2408,2472,2536,2600,2664,2728,
    2792,2856,2976,3104,3240,3368,3496,3624,3752,3824,
]


def tbs_from_inputs(n_prb: int, n_symb: int, n_dmrs_prb: int, n_oh_prb: int,
                    qm: int, rate: float, layers: int, tb_scaling: float = 1.0) -> dict:
    n_re_prime = 12 * n_symb - n_dmrs_prb - n_oh_prb
    n_re = min(156, n_re_prime) * n_prb
    n_info = tb_scaling * n_re * rate * qm * layers
    if n_info <= 3824:
        n = max(3, math.floor(math.log2(n_info)) - 6)
        n_info_prime = max(24, (2 ** n) * math.floor(n_info / (2 ** n)))
        tbs = next(v for v in TBS_TABLE_SMALL if v >= n_info_prime)
        c = 1
    else:
        n = math.floor(math.log2(n_info - 24)) - 5
        n_info_prime = max(3840, (2 ** n) * round_half_up((n_info - 24) / (2 ** n)))
        if rate <= 0.25:
            c = math.ceil((n_info_prime + 24) / 3816)
        elif n_info_prime > 8424:
            c = math.ceil((n_info_prime + 24) / 8424)
        else:
            c = 1
        tbs = 8 * c * math.ceil((n_info_prime + 24) / (8 * c)) - 24
    return {
        "NREPrimePerPRB": n_re_prime,
        "NRE": n_re,
        "NInfo": n_info,
        "NInfoPrime": n_info_prime,
        "CForTBS": c,
        "TBS": int(tbs),
    }


def build_coding_vectors() -> tuple[list[dict], list[dict], list[dict]]:
    tbs_cases = [
        # ID, nPRB, nSym, dmrs/PRB, oh, Qm, R, layers, scaling
        ("TBS-001", 1, 2, 6, 0, 2, 120/1024, 1, 1.0),
        ("TBS-002", 4, 4, 6, 0, 2, 308/1024, 1, 1.0),
        ("TBS-003", 10, 7, 12, 0, 4, 490/1024, 1, 1.0),
        ("TBS-004", 25, 10, 12, 0, 6, 616/1024, 2, 1.0),
        ("TBS-005", 52, 12, 18, 0, 8, 772/1024, 4, 1.0),
        ("TBS-006", 106, 14, 12, 0, 10, 805.5/1024, 2, 1.0),
        ("TBS-007", 273, 14, 24, 0, 8, 948/1024, 8, 1.0),
        ("TBS-008", 20, 12, 12, 6, 4, 0.25, 1, 1.0),
        ("TBS-009", 20, 12, 12, 12, 4, 0.26, 1, 1.0),
        ("TBS-010", 50, 10, 12, 0, 6, 0.67, 1, 1.0),
        ("TBS-011", 50, 10, 12, 0, 6, 0.671, 1, 1.0),
        ("TBS-012", 8, 8, 6, 0, 2, 0.5, 1, 0.5),
        ("TBS-013", 8, 8, 6, 0, 2, 0.5, 1, 0.25),
        ("TBS-014", 100, 14, 18, 0, 6, 0.2, 4, 1.0),
        ("TBS-015", 100, 14, 18, 0, 6, 0.8, 4, 1.0),
        ("TBS-016", 2, 14, 12, 0, 2, 0.9, 1, 1.0),
        ("TBS-017", 30, 3, 6, 0, 4, 0.4, 2, 1.0),
        ("TBS-018", 30, 13, 12, 0, 8, 0.9, 4, 1.0),
    ]
    inputs: list[dict] = []
    expected: list[dict] = []
    crc_vectors: list[dict] = []
    for idx, case in enumerate(tbs_cases):
        cid, nprb, nsym, ndmrs, noh, qm, rate, layers, scaling = case
        result = tbs_from_inputs(nprb, nsym, ndmrs, noh, qm, rate, layers, scaling)
        a = result["TBS"]
        crc_type = select_tb_crc(a)
        bg = select_base_graph(a, rate)
        inputs.append({
            "CaseID": cid,
            "NPRB": nprb,
            "NScheduledSymbols": nsym,
            "NDMRSREPerPRB": ndmrs,
            "NOverheadREPerPRB": noh,
            "Qm": qm,
            "TargetCodeRate": format(rate, ".15g"),
            "NumLayers": layers,
            "TBScaling": scaling,
            "ExpectedStatus": "PASS",
        })
        expected.append({
            "CaseID": cid,
            **{k: format(v, ".15g") if isinstance(v, float) else v for k, v in result.items()},
            "TBCRCType": crc_type,
            "TBCRCLength": 24 if crc_type == "24A" else 16,
            "BaseGraph": bg,
            "Status": "PASS",
        })
        # Deterministic small independent CRC vectors; do not generate huge TB payloads.
        payload_len = [24, 56, 288, 292, 293, 1000, 3824, 3825, 4096][idx % 9]
        payload = [bin(i * 13 + idx).count("1") & 1 for i in range(payload_len)]
        ctype = select_tb_crc(payload_len)
        rem = crc_remainder(payload, ctype)
        crc_vectors.append({
            "CaseID": f"CRC-{idx+1:03d}",
            "PayloadLength": payload_len,
            "CRCType": ctype,
            "InputBits": bit_text(payload),
            "ExpectedCRCBits": bit_text(rem),
            "ExpectedBlockWithCRC": bit_text(payload + rem),
            "Status": "PASS",
        })
    neg = [
        ("TBS-NEG-001", 0, 14, 12, 0, 2, .5, 1, "NPRBOutOfRange"),
        ("TBS-NEG-002", 10, 0, 12, 0, 2, .5, 1, "SymbolAllocationEmpty"),
        ("TBS-NEG-003", 10, 4, 60, 0, 2, .5, 1, "NegativeDataRE"),
        ("TBS-NEG-004", 10, 4, 6, 0, 12, .5, 1, "UnsupportedQm"),
        ("TBS-NEG-005", 10, 4, 6, 0, 2, 1.1, 1, "TargetCodeRateOutOfRange"),
    ]
    for cid, nprb, nsym, ndmrs, noh, qm, rate, layers, err in neg:
        inputs.append({
            "CaseID": cid, "NPRB": nprb, "NScheduledSymbols": nsym,
            "NDMRSREPerPRB": ndmrs, "NOverheadREPerPRB": noh,
            "Qm": qm, "TargetCodeRate": rate, "NumLayers": layers,
            "TBScaling": 1.0, "ExpectedStatus": "ERROR", "ExpectedError": err,
        })
        expected.append({"CaseID": cid, "Status": "ERROR", "ExpectedError": err})
    return inputs, expected, crc_vectors


# ---------------------------------------------------------------------------
# TS 38.211 Tables 7.4.1.1.2-1 through -5: selected table-derived DM-RS.
# ---------------------------------------------------------------------------
A_SINGLE = {
    3: [["l0"], ["l0"], ["l0"], ["l0"]],
    4: [["l0"], ["l0"], ["l0"], ["l0"]],
    5: [["l0"], ["l0"], ["l0"], ["l0"]],
    6: [["l0"], ["l0"], ["l0"], ["l0"]],
    7: [["l0"], ["l0"], ["l0"], ["l0"]],
    8: [["l0"], ["l0", 7], ["l0", 7], ["l0", 7]],
    9: [["l0"], ["l0", 7], ["l0", 7], ["l0", 7]],
    10: [["l0"], ["l0", 9], ["l0", 6, 9], ["l0", 6, 9]],
    11: [["l0"], ["l0", 9], ["l0", 6, 9], ["l0", 6, 9]],
    12: [["l0"], ["l0", 9], ["l0", 6, 9], ["l0", 5, 8, 11]],
    13: [["l0"], ["l0", "l1"], ["l0", 7, 11], ["l0", 5, 8, 11]],
    14: [["l0"], ["l0", "l1"], ["l0", 7, 11], ["l0", 5, 8, 11]],
}
B_SINGLE = {
    2: [["l0"], ["l0"], ["l0"], ["l0"]],
    3: [["l0"], ["l0"], ["l0"], ["l0"]],
    4: [["l0"], ["l0"], ["l0"], ["l0"]],
    5: [["l0"], ["l0", 4], ["l0", 4], ["l0", 4]],
    6: [["l0"], ["l0", 4], ["l0", 4], ["l0", 4]],
    7: [["l0"], ["l0", 4], ["l0", 4], ["l0", 4]],
    8: [["l0"], ["l0", 6], ["l0", 3, 6], ["l0", 3, 6]],
    9: [["l0"], ["l0", 7], ["l0", 4, 7], ["l0", 4, 7]],
    10: [["l0"], ["l0", 7], ["l0", 4, 7], ["l0", 4, 7]],
    11: [["l0"], ["l0", 8], ["l0", 4, 8], ["l0", 3, 6, 9]],
    12: [["l0"], ["l0", 9], ["l0", 5, 9], ["l0", 3, 6, 9]],
    13: [["l0"], ["l0", 9], ["l0", 5, 9], ["l0", 3, 6, 9]],
}
A_DOUBLE = {
    4: [["l0"], ["l0"], None],
    5: [["l0"], ["l0"], None],
    6: [["l0"], ["l0"], None],
    7: [["l0"], ["l0"], None],
    8: [["l0"], ["l0"], None],
    9: [["l0"], ["l0"], None],
    10: [["l0"], ["l0", 8], None],
    11: [["l0"], ["l0", 8], None],
    12: [["l0"], ["l0", 8], None],
    13: [["l0"], ["l0", 10], None],
    14: [["l0"], ["l0", 10], None],
}
B_DOUBLE = {
    5: [["l0"], ["l0"], None],
    6: [["l0"], ["l0"], None],
    7: [["l0"], ["l0"], None],
    8: [["l0"], ["l0", 5], None],
    9: [["l0"], ["l0", 5], None],
    10: [["l0"], ["l0", 7], None],
    11: [["l0"], ["l0", 7], None],
    12: [["l0"], ["l0", 8], None],
    13: [["l0"], ["l0", 8], None],
}


def resolve_dmrs_positions(mapping: str, length: int, ld: int, add_pos: int,
                           type_a_pos: int, start_symbol: int) -> list[int] | None:
    table = {("A", 1): A_SINGLE, ("B", 1): B_SINGLE,
             ("A", 2): A_DOUBLE, ("B", 2): B_DOUBLE}[(mapping, length)]
    if ld not in table or add_pos >= len(table[ld]):
        return None
    raw = table[ld][add_pos]
    if raw is None:
        return None
    positions = []
    for item in raw:
        if item == "l0":
            positions.append(type_a_pos if mapping == "A" else start_symbol)
        elif item == "l1":
            positions.append(11)  # baseline capability without additionalDMRS-DL-Alt exception
        elif mapping == "A":
            positions.append(int(item))
        else:
            positions.append(start_symbol + int(item))
    # For double-symbol DM-RS each listed front symbol has l'=0,1.
    if length == 2:
        expanded: list[int] = []
        for p in positions:
            expanded.extend([p, p + 1])
        positions = expanded
    return positions


def valid_dmrs_port_indices(config_type: int, length: int, enhanced: bool) -> list[int]:
    """Logical PDSCH DM-RS port indices p-1000 from Table 7.4.1.1.2-5.

    Enhanced single-symbol DM-RS has a non-contiguous port set.  Treating the
    maximum port as a contiguous range is a common implementation shortcut and
    is deliberately prohibited by these vectors.
    """
    if config_type not in (1, 2):
        raise ValueError("DM-RS configuration type must be 1 or 2")
    if length not in (1, 2):
        raise ValueError("DM-RS length must be 1 or 2")
    if not enhanced and length == 1:
        return list(range(4 if config_type == 1 else 6))
    if not enhanced and length == 2:
        return list(range(8 if config_type == 1 else 12))
    if enhanced and length == 1:
        return ([0, 1, 2, 3, 8, 9, 10, 11]
                if config_type == 1
                else [0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 16, 17])
    return list(range(16 if config_type == 1 else 24))


def max_port_index(config_type: int, length: int, enhanced: bool) -> int:
    """Highest logical port index, retained for coverage calculations."""
    return max(valid_dmrs_port_indices(config_type, length, enhanced))


def dmrs_group_delta(config_type: int, port: int) -> tuple[int, int]:
    if config_type == 1:
        return (port % 4) // 2, (port % 4) // 2
    return (port % 6) // 2, 2 * ((port % 6) // 2)


def dmrs_port_weights(config_type: int, port: int) -> tuple[list[int], list[int]]:
    """Return [wf(0)..wf(3)] and [wt(0),wt(1)] from Tables -1 and -2."""
    if config_type == 1:
        if port < 8:
            wf = [1, 1, 1, 1] if port % 2 == 0 else [1, -1, 1, -1]
        else:
            wf = [1, 1, -1, -1] if port % 2 == 0 else [1, -1, -1, 1]
        wt = [1, 1] if (port // 4) % 2 == 0 else [1, -1]
        return wf, wt
    block = port // 6
    if block == 0:
        wf = [1, 1, 1, 1] if port % 2 == 0 else [1, -1, 1, -1]
    else:
        wf = [1, 1, -1, -1] if port % 2 == 0 else [1, -1, -1, 1]
    wt = [1, 1] if block % 2 == 0 else [1, -1]
    return wf, wt


def build_dmrs_vectors() -> tuple[list[dict], list[dict], list[dict]]:
    inputs: list[dict] = []
    expected: list[dict] = []
    case_num = 1
    for mapping, length, table in [
        ("A", 1, A_SINGLE), ("B", 1, B_SINGLE),
        ("A", 2, A_DOUBLE), ("B", 2, B_DOUBLE),
    ]:
        ld_range = range(2, 15) if mapping == "A" else range(2, 14)
        max_add = 3 if length == 1 else 2
        for ld in ld_range:
            for add_pos in range(max_add + 1):
                start = 0 if mapping == "A" else (14 - ld)
                type_a = 2 if case_num % 2 else 3
                positions = resolve_dmrs_positions(mapping, length, ld, add_pos, type_a, start)
                valid = positions is not None and all(start <= p < start + ld for p in positions)
                cid = f"DMRS-{case_num:03d}"
                case_num += 1
                inputs.append({
                    "CaseID": cid,
                    "MappingType": mapping,
                    "DMRSLength": length,
                    "PDSCHStartSymbol": start,
                    "PDSCHDurationLd": ld,
                    "DMRSTypeAPosition": type_a,
                    "DMRSAdditionalPosition": add_pos,
                    "DMRSConfigurationType": 1 if case_num % 2 else 2,
                    "DMRSMultiplexing": "basic",
                    "DMRSPortSet": "0",
                    "ExpectedStatus": "PASS" if valid else "ERROR",
                    "ExpectedError": "" if valid else "UnsupportedDMRSPositionCombination",
                })
                expected.append({
                    "CaseID": cid,
                    "ExpectedDMRSSymbols": num_text(positions or []),
                    "ExpectedDMRSSymbolCount": len(positions or []),
                    "Status": "PASS" if valid else "ERROR",
                    "ExpectedError": "" if valid else "UnsupportedDMRSPositionCombination",
                })
    # Port capability matrix and table-derived CDM group/delta/orthogonal
    # cover codes.  Keep exactly 108 rows: 90 valid table ports and 18
    # intentionally invalid gap/above-range ports.
    ports: list[dict] = []
    pcase = 1
    for config_type in (1, 2):
        for length in (1, 2):
            for enhanced in (False, True):
                valid_ports = valid_dmrs_port_indices(config_type, length, enhanced)
                for port in valid_ports:
                    group, delta = dmrs_group_delta(config_type, port)
                    wf, wt = dmrs_port_weights(config_type, port)
                    ports.append({
                        "CaseID": f"DMRSPORT-{pcase:03d}",
                        "DMRSConfigurationType": config_type,
                        "DMRSLength": length,
                        "DMRSMultiplexing": "enhanced" if enhanced else "basic",
                        "DMRSPortSetValue": port,
                        "PhysicalAntennaPort": 1000 + port,
                        "SupportedLPrime": "0|1" if length == 2 else "0",
                        "CDMGroupLambda": group,
                        "Delta": delta,
                        "WF": num_text(wf),
                        "WT": num_text(wt),
                        "ExpectedStatus": "PASS",
                    })
                    pcase += 1
                if enhanced and length == 1:
                    # Exercise both ends of the non-contiguous hole and one
                    # value immediately above the highest supported port.
                    if config_type == 1:
                        invalid_ports = [4, 7, 12]
                    else:
                        invalid_ports = [6, 11, 18]
                else:
                    top = max(valid_ports)
                    invalid_ports = [top + 1, top + 2]
                for port in invalid_ports:
                    ports.append({
                        "CaseID": f"DMRSPORT-{pcase:03d}",
                        "DMRSConfigurationType": config_type,
                        "DMRSLength": length,
                        "DMRSMultiplexing": "enhanced" if enhanced else "basic",
                        "DMRSPortSetValue": port,
                        "PhysicalAntennaPort": 1000 + port,
                        "ExpectedStatus": "ERROR",
                        "ExpectedError": "DMRSPortUnsupportedForConfiguration",
                    })
                    pcase += 1
    assert len(ports) == 108, len(ports)
    return inputs, expected, ports


# ---------------------------------------------------------------------------
# PDSCH scheduling-assignment, PTRS, reserved-RE, precoding and HARQ inputs.
# These are executable behavioral vectors; expected outcomes are deterministic.
# ---------------------------------------------------------------------------
def build_assignment_vectors() -> tuple[list[dict], list[dict]]:
    """Exercise dynamic DCI, activated SPS, and isolated calibration ownership."""
    rows = [
        # CaseID, profile, DCI present, CRC, RNTI, BWP, epoch, cell, TCI,
        # resources, MCS context, HARQ context, fields, format, RNTI type,
        # expected status, expected error.
        ("ASSIGN-001", "connected_strict", 1,1,1,1,1,1,1,1,1,1,1, "1_0", "C-RNTI", "PASS", ""),
        ("ASSIGN-002", "connected_strict", 0,0,1,1,1,1,1,1,1,1,1, "",    "C-RNTI", "ERROR", "MissingDecodedDCI"),
        ("ASSIGN-003", "connected_strict", 1,0,1,1,1,1,1,1,1,1,1, "1_0", "SI-RNTI", "ERROR", "DCICRCFailed"),
        ("ASSIGN-004", "connected_strict", 1,1,0,1,1,1,1,1,1,1,1, "1_0", "RA-RNTI", "ERROR", "DCIRNTIMismatch"),
        ("ASSIGN-005", "connected_strict", 1,1,1,0,1,1,1,1,1,1,1, "1_1", "C-RNTI", "ERROR", "MissingActiveBWPContext"),
        ("ASSIGN-006", "connected_strict", 1,1,1,1,0,1,1,1,1,1,1, "1_1", "C-RNTI", "ERROR", "StaleUEConfigurationEpoch"),
        ("ASSIGN-007", "phy_calibration", 0,0,0,1,1,1,1,1,1,1,1, "",    "C-RNTI", "PASS", ""),
        ("ASSIGN-008", "phy_calibration", 1,1,1,1,1,1,1,1,1,1,1, "1_0", "RA-RNTI", "PASS", ""),
        ("ASSIGN-009", "connected_strict", 1,1,1,1,1,1,1,1,1,1,1, "1_1", "C-RNTI", "PASS", ""),
        ("ASSIGN-010", "connected_strict", 1,1,1,1,1,1,1,1,1,1,1, "1_2", "C-RNTI", "PASS", ""),
        ("ASSIGN-011", "connected_strict", 1,1,1,1,1,1,1,1,1,1,0, "1_1", "C-RNTI", "ERROR", "DCIFieldOutOfRange"),
        ("ASSIGN-012", "connected_strict", 1,1,1,1,1,1,1,0,1,1,1, "1_1", "C-RNTI", "ERROR", "ScheduledResourceUnavailable"),
        ("ASSIGN-013", "connected_strict", 1,1,1,1,1,1,1,1,1,0,1, "1_1", "C-RNTI", "ERROR", "HARQContextMismatch"),
        ("ASSIGN-014", "connected_strict", 1,1,1,1,1,1,1,1,0,1,1, "1_1", "C-RNTI", "ERROR", "UnsupportedMCSContext"),
        ("ASSIGN-015", "connected_strict", 1,1,1,1,1,0,1,1,1,1,1, "1_1", "C-RNTI", "ERROR", "InactiveServingCell"),
        ("ASSIGN-016", "connected_strict", 1,1,1,1,1,1,0,1,1,1,1, "1_1", "C-RNTI", "ERROR", "TCIStateNotActivated"),
    ]
    inputs: list[dict] = []
    expected: list[dict] = []
    for idx, row in enumerate(rows):
        (cid, profile, dci, crc, rnti, bwp, epoch, cell_active, tci_active,
         resource_ok, mcs_ok, harq_ok, fields_ok, dci_format, rnti_type,
         status, err) = row
        source = "calibration_assignment" if profile == "phy_calibration" else "decoded_dci+ue_context"
        inputs.append({
            "CaseID": cid,
            "Profile": profile,
            "DecodedDCIPresent": dci,
            "DecodedDCIId": f"DCI-{idx+1:03d}" if dci else "",
            "DCICRCPass": crc,
            "DCIRNTIMatch": rnti,
            "ActiveBWPContextPresent": bwp,
            "UEContextEpochCurrent": epoch,
            "ServingCellActive": cell_active,
            "TCIStateActive": tci_active,
            "ResourceAvailable": resource_ok,
            "MCSContextSupported": mcs_ok,
            "HARQContextConsistent": harq_ok,
            "DCIFieldsInRange": fields_ok,
            "DCIFormat": dci_format,
            "RNTIType": rnti_type,
            "ServingCellID": 1 + idx % 2,
            "CCID": idx % 2,
            "BWPId": idx % 3,
            "AbsoluteSlot": 100 + idx,
            "ConfigurationEpoch": 7,
            "FDRAType": "type1_riv" if idx % 2 == 0 else "type0_rbg",
            "PRBStart": (idx * 3) % 20,
            "PRBLength": 4 + idx % 12,
            "VRBToPRBMapping": "noninterleaved" if idx % 2 == 0 else "interleaved",
            "K0": idx % 3,
            "StartSymbol": idx % 4,
            "SymbolLength": 14 - idx % 4,
            "MappingType": "A" if idx % 2 == 0 else "B",
            "MCSTable": ["qam64", "qam256", "qam1024"][idx % 3],
            "MCSIndex": idx % 28,
            "NDI": idx % 2,
            "RV": [0, 2, 3, 1][idx % 4],
            "HARQProcessID": idx % 16,
            "AntennaPortField": idx % 12,
            "TCIStateId": idx % 4,
            "SPSActivationDCIId": "",
            "SPSActivationDCICRCPass": 0,
            "SPSActivationDCIRNTIMatch": 0,
            "SPSConfigPresent": 0,
            "SPSActivated": 0,
            "SPSReleased": 0,
            "SPSOccasionMatch": 0,
            "ExpectedStatus": status,
            "ExpectedError": err,
        })
        expected.append({
            "CaseID": cid,
            "ExpectedStatus": "PASS" if status == "PASS" else "ERROR",
            "ExpectedError": err,
            "ExpectedAssignmentSource": source if status == "PASS" else "",
            "ExpectedWaveformAllowed": 1 if status == "PASS" else 0,
            "ExpectedConfigurationMutation": 0,
        })

    # Downlink SPS is the standards-valid exception to requiring a freshly
    # decoded scheduling DCI on every PDSCH occasion.  The occasion must still
    # be owned by an RRC SPS configuration and a prior CRC-valid activation DCI.
    sps_cases = [
        # case, config, activated, released, occasion, activation CRC,
        # activation RNTI match, status, error
        ("ASSIGN-017", 1, 1, 0, 1, 1, 1, "PASS", ""),
        ("ASSIGN-018", 1, 0, 0, 1, 1, 1, "ERROR", "SPSNotActivated"),
        ("ASSIGN-019", 1, 1, 1, 1, 1, 1, "ERROR", "SPSReleased"),
        ("ASSIGN-020", 1, 1, 0, 0, 1, 1, "ERROR", "NotSPSOccasion"),
        ("ASSIGN-021", 1, 1, 0, 1, 0, 1, "ERROR", "SPSActivationDCICRCFailed"),
        ("ASSIGN-022", 1, 1, 0, 1, 1, 0, "ERROR", "SPSActivationDCIRNTIMismatch"),
    ]
    for offset, (cid, cfg_present, activated, released, occasion, act_crc, act_rnti, status, err) in enumerate(sps_cases):
        idx = len(inputs)
        inputs.append({
            "CaseID": cid,
            "Profile": "sps_strict",
            "DecodedDCIPresent": 0,
            "DecodedDCIId": "",
            "DCICRCPass": 0,
            "DCIRNTIMatch": 0,
            "ActiveBWPContextPresent": 1,
            "UEContextEpochCurrent": 1,
            "ServingCellActive": 1,
            "TCIStateActive": 1,
            "ResourceAvailable": 1,
            "MCSContextSupported": 1,
            "HARQContextConsistent": 1,
            "DCIFieldsInRange": 1,
            "DCIFormat": "1_1",
            "RNTIType": "CS-RNTI",
            "ServingCellID": 1,
            "CCID": 0,
            "BWPId": 1,
            "AbsoluteSlot": 200 + offset * 10,
            "ConfigurationEpoch": 9,
            "FDRAType": "type1_riv",
            "PRBStart": 12,
            "PRBLength": 16,
            "VRBToPRBMapping": "noninterleaved",
            "K0": 0,
            "StartSymbol": 2,
            "SymbolLength": 12,
            "MappingType": "A",
            "MCSTable": "qam256",
            "MCSIndex": 18,
            "NDI": 1,
            "RV": 0,
            "HARQProcessID": 4,
            "AntennaPortField": 0,
            "TCIStateId": 1,
            "SPSActivationDCIId": "DCI-SPS-ACT-001",
            "SPSActivationDCICRCPass": act_crc,
            "SPSActivationDCIRNTIMatch": act_rnti,
            "SPSConfigPresent": cfg_present,
            "SPSActivated": activated,
            "SPSReleased": released,
            "SPSOccasionMatch": occasion,
            "ExpectedStatus": status,
            "ExpectedError": err,
        })
        expected.append({
            "CaseID": cid,
            "ExpectedStatus": "PASS" if status == "PASS" else "ERROR",
            "ExpectedError": err,
            "ExpectedAssignmentSource": "sps_activation_dci+rrc_context" if status == "PASS" else "",
            "ExpectedWaveformAllowed": 1 if status == "PASS" else 0,
            "ExpectedConfigurationMutation": 0,
        })
    return inputs, expected


def build_ptrs_vectors() -> tuple[list[dict], list[dict]]:
    rows: list[dict] = []
    expected: list[dict] = []
    cid = 1
    for mapping in ("A", "B"):
        for td in (1, 2, 4):
            for fd in (2, 4):
                for offset in ("00", "01", "10", "11"):
                    case = f"PTRS-{cid:03d}"
                    rows.append({
                        "CaseID": case,
                        "MappingType": mapping,
                        "TimeDensity": td,
                        "FrequencyDensity": fd,
                        "REOffset": offset,
                        "PDSCHDuration": 12 if mapping == "A" else 8,
                        "NPRB": 24,
                        "MCSIndex": 20,
                        "MCSTable": "qam256",
                        "RNTIType": "C-RNTI",
                        "PTRSPortSet": "0",
                        "DMRSPortSet": "0",
                        "ExpectedPTRSPresent": 1,
                        "ExpectedStatus": "PASS",
                        "ExpectedReason": "PTRSPresent",
                    })
                    expected.append({"CaseID":case,"ExpectedPresent":1,"ExpectedStatus":"PASS","ExpectedReason":"PTRSPresent"})
                    cid += 1
    negative = [
        ("A", 3, 2, "00", 12, 24, 20, "qam256", "C-RNTI", "InvalidPTRSTimeDensity"),
        ("A", 2, 3, "00", 12, 24, 20, "qam256", "C-RNTI", "InvalidPTRSFrequencyDensity"),
        ("A", 2, 2, "12", 12, 24, 20, "qam256", "C-RNTI", "InvalidPTRSREOffset"),
        # A two-symbol type-B allocation can legally carry front-loaded DM-RS
        # but has no remaining PT-RS time occasion for the supplied density.
        ("B", 2, 2, "00", 2, 24, 20, "qam256", "C-RNTI", "PTRSNotPresentForTwoSymbolAllocation"),
        ("A", 1, 2, "00", 12, 2, 20, "qam256", "C-RNTI", "PTRSNotPresentBelowBandwidthThreshold"),
        ("A", 1, 2, "00", 12, 24, 20, "qam256", "RA-RNTI", "PTRSNotPresentForRNTIType"),
        ("A", 1, 2, "00", 12, 24, 20, "qam256", "SI-RNTI", "PTRSNotPresentForRNTIType"),
        ("A", 1, 2, "00", 12, 24, 20, "qam256", "P-RNTI", "PTRSNotPresentForRNTIType"),
    ]
    for mapping, td, fd, offset, dur, nprb, mcs, table, rnti, reason in negative:
        case = f"PTRS-{cid:03d}"
        status = "ERROR" if reason.startswith("Invalid") else "PASS"
        rows.append({
            "CaseID": case, "MappingType": mapping,
            "TimeDensity": td, "FrequencyDensity": fd, "REOffset": offset,
            "PDSCHDuration": dur, "NPRB": nprb, "MCSIndex": mcs,
            "MCSTable": table, "RNTIType": rnti, "PTRSPortSet": "0",
            "DMRSPortSet": "0", "ExpectedPTRSPresent": 0,
            "ExpectedStatus": status, "ExpectedReason": reason,
        })
        expected.append({"CaseID":case,"ExpectedPresent":0,"ExpectedStatus":status,"ExpectedReason":reason})
        cid += 1
    return rows, expected


def parse_set(text: str) -> set[int]:
    if not text:
        return set()
    out: set[int] = set()
    for token in text.split("|"):
        if "-" in token:
            a, b = token.split("-", 1)
            out.update(range(int(a), int(b) + 1))
        else:
            out.add(int(token))
    return out


def build_reserved_vectors() -> tuple[list[dict], list[dict]]:
    raw = [
        # allocation, SSB, CORESET, NZP-CSI-RS, ZP-CSI-RS, LTE-CRS,
        # explicit rateMatchPattern, expected status
        ("RES-001", "0-167", "", "", "", "", "", "", "PASS"),
        ("RES-002", "0-167", "0-23", "", "", "", "", "", "PASS"),
        ("RES-003", "0-167", "", "24-35", "", "", "", "", "PASS"),
        ("RES-004", "0-167", "0-11", "12-23", "24-35", "", "", "36-47", "PASS"),
        ("RES-005", "0-167", "0-11", "6-17", "12-23", "", "", "18-29", "PASS"),
        ("RES-006", "0-167", "", "", "0|2|4|6|8|10", "", "", "", "PASS"),
        ("RES-007", "0-167", "", "", "", "1|3|5|7|9|11", "", "", "PASS"),
        ("RES-008", "0-167", "", "", "", "", "", "48-59", "PASS"),
        ("RES-009", "0-167", "0-23", "18-35", "30-47", "42-59", "54-71", "66-83", "PASS"),
        ("RES-010", "0-167", "0-83", "84-167", "", "", "", "", "ERROR"),
        ("RES-011", "0-167", "200-210", "", "", "", "", "", "ERROR"),
        ("RES-012", "0-167", "24-35", "24-35", "", "", "", "24-35", "PASS"),
        ("RES-013", "0-167", "", "", "", "", "", "0-167", "ERROR"),
        ("RES-014", "0-335", "0-23", "24-47", "48-71", "72-95", "96-119", "120-143", "PASS"),
    ]
    inputs = []
    expected = []
    names = ["SSB", "CORESET", "NZPCSIRS", "ZPCSIRS", "LTECRS", "RateMatchPattern"]
    for row in raw:
        cid, alloc_text, *rest = row
        status = rest[-1]
        src_texts = rest[:-1]
        alloc = parse_set(alloc_text)
        sources = [parse_set(t) for t in src_texts]
        union = set().union(*sources)
        outside = union - alloc
        data = alloc - union
        overlap_pairs = 0
        for i in range(len(sources)):
            for j in range(i + 1, len(sources)):
                overlap_pairs += len(sources[i] & sources[j])
        expected_status = status
        err = ""
        if outside:
            expected_status, err = "ERROR", "ReservedREOutsideAllocation"
        elif not data:
            expected_status, err = "ERROR", "NoPDSCHDataREAfterReservation"
        inputs.append({
            "CaseID": cid,
            "AllocationRE": alloc_text,
            **{f"{names[i]}RE": src_texts[i] for i in range(len(names))},
            "ExpectedStatus": expected_status,
            "ExpectedError": err,
        })
        expected.append({
            "CaseID": cid,
            "AllocationRECount": len(alloc),
            "ReservedUnionCount": len(union & alloc),
            "DataRECount": len(data),
            "ReservedOutsideAllocationCount": len(outside),
            "PairwiseOverlapMultiplicity": overlap_pairs,
            "ExpectedReservedUnion": num_text(sorted(union & alloc)),
            "ExpectedDataRE": num_text(sorted(data)),
            "Status": expected_status,
            "ExpectedError": err,
        })
    return inputs, expected


def build_precoding_vectors() -> list[dict]:
    return [
        {"CaseID":"PREC-001","Mode":"siso_identity","NPorts":1,"NLayers":1,"NPRG":1,"NSymbolGroups":1,"PRGSize":0,"PRBSet":"0-23","MatrixShape":"1x1x1x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-002","Mode":"wideband_codebook","NPorts":2,"NLayers":1,"NPRG":1,"NSymbolGroups":1,"PRGSize":0,"PRBSet":"0-23","MatrixShape":"2x1x1x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-003","Mode":"wideband_codebook","NPorts":2,"NLayers":2,"NPRG":1,"NSymbolGroups":1,"PRGSize":0,"PRBSet":"0-23","MatrixShape":"2x2x1x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-004","Mode":"wideband_noncodebook","NPorts":4,"NLayers":2,"NPRG":1,"NSymbolGroups":1,"PRGSize":0,"PRBSet":"0-23","MatrixShape":"4x2x1x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-005","Mode":"prg_codebook","NPorts":4,"NLayers":2,"NPRG":4,"NSymbolGroups":1,"PRGSize":2,"PRBSet":"0-7","MatrixShape":"4x2x4x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-006","Mode":"prg_noncodebook","NPorts":8,"NLayers":4,"NPRG":3,"NSymbolGroups":1,"PRGSize":4,"PRBSet":"4-15","MatrixShape":"8x4x3x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-007","Mode":"prb_explicit","NPorts":4,"NLayers":2,"NPRG":6,"NSymbolGroups":1,"PRGSize":1,"PRBSet":"0|2|4|6|8|10","MatrixShape":"4x2x6x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-008","Mode":"prg_symbol_selective","NPorts":4,"NLayers":2,"NPRG":4,"NSymbolGroups":3,"PRGSize":2,"PRBSet":"0-7","MatrixShape":"4x2x4x3","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-009","Mode":"wideband_fixed_matrix","NPorts":8,"NLayers":8,"NPRG":1,"NSymbolGroups":1,"PRGSize":0,"PRBSet":"0-51","MatrixShape":"8x8x1x1","ExpectedStatus":"PASS"},
        {"CaseID":"PREC-NEG-001","Mode":"prg_codebook","NPorts":2,"NLayers":4,"NPRG":2,"NSymbolGroups":1,"PRGSize":4,"PRBSet":"0-7","MatrixShape":"2x4x2x1","ExpectedStatus":"ERROR","ExpectedError":"TooFewPortsForLayers"},
        {"CaseID":"PREC-NEG-002","Mode":"prg_codebook","NPorts":4,"NLayers":2,"NPRG":1,"NSymbolGroups":1,"PRGSize":2,"PRBSet":"0-7","MatrixShape":"4x2x1x1","ExpectedStatus":"ERROR","ExpectedError":"IncompletePRGCoverage"},
        {"CaseID":"PREC-NEG-003","Mode":"prg_codebook","NPorts":4,"NLayers":2,"NPRG":5,"NSymbolGroups":1,"PRGSize":2,"PRBSet":"0-7","MatrixShape":"4x2x5x1","ExpectedStatus":"ERROR","ExpectedError":"ExcessPRGPages"},
        {"CaseID":"PREC-NEG-004","Mode":"wideband_fixed_matrix","NPorts":4,"NLayers":2,"NPRG":1,"NSymbolGroups":1,"PRGSize":0,"PRBSet":"0-7","MatrixShape":"4x3x1x1","ExpectedStatus":"ERROR","ExpectedError":"PrecoderLayerDimensionMismatch"},
        {"CaseID":"PREC-NEG-005","Mode":"prg_symbol_selective","NPorts":4,"NLayers":2,"NPRG":4,"NSymbolGroups":2,"PRGSize":2,"PRBSet":"0-7","MatrixShape":"4x2x4x1","ExpectedStatus":"ERROR","ExpectedError":"IncompleteSymbolGroupCoverage"},
        {"CaseID":"PREC-NEG-006","Mode":"scalar_pmi_called_complete","NPorts":4,"NLayers":2,"NPRG":4,"NSymbolGroups":1,"PRGSize":2,"PRBSet":"0-7","MatrixShape":"scalar","ExpectedStatus":"ERROR","ExpectedError":"ScalarPMINotPrecoderBundle"},
    ]


def build_harq_vectors() -> list[dict]:
    rows = []
    rv_order = [0, 2, 3, 1]
    for i, rv in enumerate(rv_order):
        rows.append({
            "CaseID": f"HARQ-RV-{i+1}", "HARQProcessID": 3, "TransmissionIndex": i,
            # NDI remains unchanged for retransmissions of the same TB.
            "NDI": 1, "RV": rv, "NewData": 1 if i == 0 else 0,
            "SameTBIdentity": 1, "SameTBS": 1, "SameCodeBlockLayout": 1,
            "ExpectedCombine": 0 if i == 0 else 1, "ExpectedStatus": "PASS",
        })
    rows.extend([
        {"CaseID":"HARQ-NEG-001","HARQProcessID":3,"TransmissionIndex":1,"NDI":1,"RV":2,"NewData":0,"SameTBIdentity":0,"SameTBS":1,"SameCodeBlockLayout":1,"ExpectedCombine":0,"ExpectedStatus":"ERROR","ExpectedError":"HARQTBIdentityMismatch"},
        {"CaseID":"HARQ-NEG-002","HARQProcessID":3,"TransmissionIndex":1,"NDI":1,"RV":2,"NewData":0,"SameTBIdentity":1,"SameTBS":0,"SameCodeBlockLayout":1,"ExpectedCombine":0,"ExpectedStatus":"ERROR","ExpectedError":"HARQTBSMismatch"},
        {"CaseID":"HARQ-NEG-003","HARQProcessID":3,"TransmissionIndex":1,"NDI":1,"RV":2,"NewData":0,"SameTBIdentity":1,"SameTBS":1,"SameCodeBlockLayout":0,"ExpectedCombine":0,"ExpectedStatus":"ERROR","ExpectedError":"HARQCodingLayoutMismatch"},
        {"CaseID":"HARQ-NEG-004","HARQProcessID":17,"TransmissionIndex":0,"NDI":1,"RV":0,"NewData":1,"SameTBIdentity":1,"SameTBS":1,"SameCodeBlockLayout":1,"ExpectedCombine":0,"ExpectedStatus":"ERROR","ExpectedError":"HARQProcessIDOutOfRange"},
        {"CaseID":"HARQ-NEG-005","HARQProcessID":3,"TransmissionIndex":1,"NDI":1,"RV":4,"NewData":0,"SameTBIdentity":1,"SameTBS":1,"SameCodeBlockLayout":1,"ExpectedCombine":0,"ExpectedStatus":"ERROR","ExpectedError":"RVOutOfRange"},
        # New data toggles NDI relative to the prior TB.
        {"CaseID":"HARQ-NEW-001","HARQProcessID":3,"TransmissionIndex":4,"NDI":0,"RV":0,"NewData":1,"SameTBIdentity":0,"SameTBS":1,"SameCodeBlockLayout":1,"ExpectedCombine":0,"ExpectedStatus":"PASS"},
        {"CaseID":"HARQ-CW2-001","HARQProcessID":7,"TransmissionIndex":1,"NDI":"1|1","RV":"2|3","NewData":0,"SameTBIdentity":1,"SameTBS":1,"SameCodeBlockLayout":1,"ExpectedCombine":1,"ExpectedStatus":"PASS"},
    ])
    return rows


def build_coverage_matrix() -> list[dict]:
    """Broad executable matrix spanning rank, codeword, RS and channel cases."""
    rows = []
    case = 1
    mods = ["QPSK", "16QAM", "64QAM", "256QAM", "1024QAM"]
    channels = ["AWGN", "TDL-A", "CDL-C"]
    for rank in range(1, 9):
        for mapping in ("A", "B"):
            mod = mods[(rank + (0 if mapping == "A" else 2)) % len(mods)]
            channel = channels[(rank - 1) % len(channels)]
            config_type = 1 if rank % 2 else 2
            dmrs_length = 1 if mapping == "A" else (1 if rank % 3 else 2)
            basic_ports = valid_dmrs_port_indices(config_type, dmrs_length, False)
            multiplexing = "basic" if rank <= len(basic_ports) else "enhanced"
            selected_ports = valid_dmrs_port_indices(config_type, dmrs_length, multiplexing == "enhanced")[:rank]
            add_pos = rank % 4 if dmrs_length == 1 and mapping == "A" else (rank % 3 if dmrs_length == 1 else rank % 2)
            rows.append({
                "CaseID": f"COV-{case:03d}", "Rank": rank,
                "NumCodewords": 1 if rank <= 4 else 2,
                "MappingType": mapping, "DMRSConfigurationType": config_type,
                "DMRSLength": dmrs_length,
                "DMRSAdditionalPosition": add_pos,
                "DMRSMultiplexing": multiplexing,
                "DMRSPortSet": num_text(selected_ports),
                "PTRSEnabled": 1 if mod in ("256QAM", "1024QAM") else 0,
                "Modulation": mod, "RVSequence": "0|2|3|1",
                "PrecodingMode": "wideband_codebook" if rank <= 2 else ("prg_codebook" if rank <= 4 else "prg_noncodebook"),
                "ChannelModel": channel, "NumerologyKHz": [15,30,60,120][(rank-1)%4],
                "RequiredTestKinds": "positive|no_signal|wrong_rnti|wrong_dmrs|wrong_rv|reserved_re|impairment",
                "ExpectedStatus": "PASS",
            })
            case += 1
    return rows


def build_contracts() -> tuple[list[dict], list[dict]]:
    csv_contract = [
        ("pdsch_assignment_resolution.csv", "CaseID|Profile|UEID|ServingCellID|CCID|BWPId|AbsoluteSlot|ConfigurationEpoch|DecodedDCIId|DCIFormat|DCICRCPass|DCIRNTIMatch|RNTIType|FDRAType|VRBToPRBMapping|K0|PRBSet|SymbolAllocation|MappingType|MCSTable|MCSIndex|Modulation|TargetCodeRate|TBScaling|XOverhead|NumLayers|NDI|RV|HARQProcessID|DMRSPortSet|TCIStateId|RateMatchPatternIDs|SPSConfigID|SPSActivationDCIId|SPSActivationDCICRCPass|SPSActivationDCIRNTIMatch|SPSConfigurationEpoch|SPSActivated|SPSReleased|SPSOccasionIndex|Source|AssignmentCreated|WaveformAllowed|ErrorIdentifier|Status", "CaseID"),
        ("pdsch_resource_ownership.csv", "CaseID|Slot|PRB|Symbol|Subcarrier|Owner|SourceResourceId|OwnerPriority|CollisionCount|Status", "CaseID|Slot|PRB|Symbol|Subcarrier"),
        ("pdsch_re_mapping.csv", "CaseID|Domain|Codeword|Layer|Port|PRB|Symbol|Subcarrier|LinearIndex0Based|Status", "CaseID|Domain|Codeword|Layer|Port|PRB|Symbol|Subcarrier"),
        ("pdsch_dmrs_matrix.csv", "CaseID|MappingType|DMRSConfigurationType|DMRSLength|DMRSAdditionalPosition|DMRSTypeAPosition|DMRSMultiplexing|NumCDMGroupsWithoutData|NIDNSCID|NSCID|DMRSPortSet|DMRSSymbols|DMRSRECount|SequenceDigest|SequenceNMSE|IndexMismatchCount|Status", "CaseID"),
        ("pdsch_ptrs_matrix.csv", "CaseID|TimeDensity|FrequencyDensity|REOffset|PTRSPortSet|AssociatedDMRSPort|PTRSRECount|ExpectedPresent|PresenceReason|CPEBeforeDeg|CPEAfterDeg|EVMBeforePercent|EVMAfterPercent|Status", "CaseID"),
        ("pdsch_coding_chain.csv", "CaseID|Codeword|TBS|TBCRCType|TBCRCLength|BaseGraph|NumCodeBlocks|CodeBlockCRCType|LiftingSize|K|N|Ncb|FillerBits|RV|K0|EPerCodeBlock|G|RateMatchedBits|CRCOK|Status", "CaseID|Codeword"),
        ("pdsch_independent_vector_results.csv", "VectorFamily|CaseID|ComparedField|OracleImplementation|OracleVersion|OracleArtifactSHA256|ExpectedDigest|ActualDigest|MismatchCount|MaxAbsError|Tolerance|Status", "VectorFamily|CaseID|ComparedField"),
        ("pdsch_layer_codeword_map.csv", "CaseID|Rank|Codeword|Layer|SourceSymbolCount|MappedSymbolCount|MismatchCount|Status", "CaseID|Codeword|Layer"),
        ("pdsch_precoding_application.csv", "CaseID|Mode|PRG|SymbolGroup|PRBStart|PRBEnd|NPorts|NLayers|MatrixDigest|AppliedMatrixDigest|NormalizationConvention|TXApplicationCount|RXApplicationCount|PowerRelativeError|Status", "CaseID|PRG|SymbolGroup"),
        ("pdsch_harq_trials.csv", "CaseID|HARQProcessID|Codeword|TransmissionIndex|NDI|RV|TBIdentity|TBS|CodeBlockLayoutDigest|SoftBufferInputDigest|SoftBufferOutputDigest|HARQAction|Combined|TBCRCOK|Status", "CaseID|Codeword|TransmissionIndex"),
        ("pdsch_receiver_metrics.csv", "CaseID|SNRdB|ChannelModel|Rank|Codeword|Layer|DataRECount|LLRCount|RateRecoveredBitCount|MeasuredSINRdB|EVMPercent|BER|BLER|TBCRCOK|ChannelEstimateNMSEdB|LDPCIterations|Status", "CaseID|Codeword|Layer"),
        ("pdsch_bler_curve.csv", "CampaignID|OperatingPointID|SNRdB|ChannelModel|Rank|MCSIndex|Modulation|Trials|TBErrors|BLER|ConfidenceLevel|CILower|CIUpper|CIHalfWidth|MinErrorsRequired|StopReason|Status", "CampaignID|OperatingPointID"),
        ("pdsch_negative_tests.csv", "CaseID|TestKind|ExpectedErrorIdentifier|ActualErrorIdentifier|WaveformGenerated|Status", "CaseID"),
        ("pdsch_test_summary.csv", "TestSuite|Total|Passed|Failed|Skipped|Blocked|Status", "TestSuite"),
        ("pdsch_image_semantic_audit.csv", "ImageFile|SourceCSV|Width|Height|AxesCount|SeriesCount|FinitePointCount|ExpectedXLabel|ActualXLabel|ExpectedYLabel|ActualYLabel|ExpectedTitleToken|ActualTitle|SourceCSV_SHA256|PNG_SHA256|Status", "ImageFile"),
    ]
    csv_rows = [{"FileName": f, "RequiredColumns": c, "PrimaryKey": k, "Required": 1} for f,c,k in csv_contract]
    images = [
        ("pdsch_resource_grid_ownership.png", "pdsch_resource_ownership.csv", "PRB / subcarrier", "OFDM symbol", "PDSCH resource ownership", 1, 1, 100),
        ("pdsch_dmrs_ptrs_map.png", "pdsch_dmrs_matrix.csv|pdsch_ptrs_matrix.csv", "Subcarrier / PRB", "OFDM symbol", "DM-RS and PT-RS", 1, 2, 20),
        ("pdsch_codeword_layer_mapping.png", "pdsch_layer_codeword_map.csv", "Layer", "Mapped symbols", "Codeword-to-layer mapping", 1, 1, 8),
        ("pdsch_prg_precoding_map.png", "pdsch_precoding_application.csv", "PRB / PRG", "Precoder index or gain", "PRG precoding", 1, 2, 4),
        ("pdsch_harq_rv_timeline.png", "pdsch_harq_trials.csv", "Transmission index", "RV / decode state", "HARQ RV timeline", 1, 2, 4),
        ("pdsch_bler_vs_snr.png", "pdsch_bler_curve.csv", "SNR (dB)", "BLER", "PDSCH BLER", 1, 1, 4),
        ("pdsch_ptrs_phase_noise_evm.png", "pdsch_ptrs_matrix.csv", "Phase-noise severity", "EVM (%)", "PT-RS phase tracking", 1, 2, 4),
        ("pdsch_per_layer_sinr.png", "pdsch_receiver_metrics.csv", "Layer", "Measured SINR (dB)", "Per-layer SINR", 1, 1, 8),
        ("pdsch_reserved_re_impact.png", "pdsch_resource_ownership.csv|pdsch_coding_chain.csv", "Reserved RE count", "G / TBS", "Reserved-resource impact", 1, 2, 4),
    ]
    image_rows = [{
        "ImageFile": f, "SourceCSV": src, "ExpectedXLabel": x, "ExpectedYLabel": y,
        "ExpectedTitleToken": title, "MinAxesCount": axes, "MinSeriesCount": series,
        "MinFinitePointCount": pts, "MinWidth": 900, "MinHeight": 600,
    } for f,src,x,y,title,axes,series,pts in images]
    return csv_rows, image_rows


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    produced: list[Path] = []
    scr_in, scr_out = build_scrambling_vectors()
    produced += [
        write_csv("pdsch_scrambling_test_vectors.csv", list(scr_in[0].keys()), scr_in),
        write_csv("expected_pdsch_scrambling_vectors.csv", list(scr_out[0].keys()), scr_out),
    ]
    mod_in, mod_out = build_modulation_vectors()
    mod_fields = ["CaseID","Modulation","Qm","BitCount","InputPatternIndex","InputBits","ExpectedStatus","ExpectedError"]
    mod_out_fields = ["CaseID","NormalizationDenominatorSquared","SymbolCount","ExpectedSymbols","MeanPowerForVector","Status","ExpectedError"]
    produced += [
        write_csv("pdsch_modulation_test_vectors.csv", mod_fields, mod_in),
        write_csv("expected_pdsch_modulation_vectors.csv", mod_out_fields, mod_out),
    ]
    layer_in, layer_out = build_layer_vectors()
    layer_in_fields = ["CaseID","Rank","NumCodewords","LayerCountPerCodeword","Codeword0Symbols","Codeword1Symbols","ExpectedStatus","ExpectedError"]
    layer_out_fields = ["CaseID","Rank","LayerIndex","SourceCodeword","LayerIndexWithinCodeword","ExpectedSymbols","SymbolCount","Status","ExpectedError"]
    produced += [
        write_csv("pdsch_layer_mapping_test_vectors.csv", layer_in_fields, layer_in),
        write_csv("expected_pdsch_layer_mapping.csv", layer_out_fields, layer_out),
    ]
    tbs_in, tbs_out, crc_out = build_coding_vectors()
    tbs_fields = ["CaseID","NPRB","NScheduledSymbols","NDMRSREPerPRB","NOverheadREPerPRB","Qm","TargetCodeRate","NumLayers","TBScaling","ExpectedStatus","ExpectedError"]
    tbs_out_fields = ["CaseID","NREPrimePerPRB","NRE","NInfo","NInfoPrime","CForTBS","TBS","TBCRCType","TBCRCLength","BaseGraph","Status","ExpectedError"]
    crc_fields = ["CaseID","PayloadLength","CRCType","InputBits","ExpectedCRCBits","ExpectedBlockWithCRC","Status"]
    produced += [
        write_csv("pdsch_coding_tbs_test_vectors.csv", tbs_fields, tbs_in),
        write_csv("expected_pdsch_tbs_basegraph.csv", tbs_out_fields, tbs_out),
        write_csv("expected_pdsch_tb_crc_vectors.csv", crc_fields, crc_out),
    ]
    external_ldpc_fixture = ROOT / "expected_pdsch_ldpc_external_vectors.csv"
    external_ldpc_generator = ROOT / "generate_external_ldpc_fixture.py"
    external_ldpc_readme = ROOT / "README_ldpc_external_vectors.md"
    for required_external in (
            external_ldpc_fixture,
            external_ldpc_generator,
            external_ldpc_readme):
        if not required_external.is_file():
            raise FileNotFoundError(
                f"Missing pinned external LDPC provenance: {required_external}")
    produced.append(external_ldpc_fixture)
    external_receiver_fixture = (
        ROOT / "expected_pdsch_receiver_external_vectors.csv"
    )
    external_receiver_generator = (
        ROOT / "generate_external_pdsch_receiver_fixture.py"
    )
    external_receiver_readme = (
        ROOT / "README_pdsch_receiver_external_vectors.md"
    )
    for required_external in (
            external_receiver_fixture,
            external_receiver_generator,
            external_receiver_readme):
        if not required_external.is_file():
            raise FileNotFoundError(
                "Missing pinned external receiver provenance: "
                f"{required_external}"
            )
    produced.append(external_receiver_fixture)
    dmrs_in, dmrs_out, dmrs_ports = build_dmrs_vectors()
    dmrs_fields = ["CaseID","MappingType","DMRSLength","PDSCHStartSymbol","PDSCHDurationLd","DMRSTypeAPosition","DMRSAdditionalPosition","DMRSConfigurationType","DMRSMultiplexing","DMRSPortSet","ExpectedStatus","ExpectedError"]
    dmrs_out_fields = ["CaseID","ExpectedDMRSSymbols","ExpectedDMRSSymbolCount","Status","ExpectedError"]
    dmrs_port_fields = ["CaseID","DMRSConfigurationType","DMRSLength","DMRSMultiplexing","DMRSPortSetValue","PhysicalAntennaPort","SupportedLPrime","CDMGroupLambda","Delta","WF","WT","ExpectedStatus","ExpectedError"]
    produced += [
        write_csv("pdsch_dmrs_test_vectors.csv", dmrs_fields, dmrs_in),
        write_csv("expected_pdsch_dmrs_symbol_positions.csv", dmrs_out_fields, dmrs_out),
        write_csv("expected_pdsch_dmrs_port_table.csv", dmrs_port_fields, dmrs_ports),
    ]
    assignment, assignment_expected = build_assignment_vectors()
    assignment_fields = ["CaseID","Profile","DecodedDCIPresent","DecodedDCIId","DCICRCPass","DCIRNTIMatch","ActiveBWPContextPresent","UEContextEpochCurrent","ServingCellActive","TCIStateActive","ResourceAvailable","MCSContextSupported","HARQContextConsistent","DCIFieldsInRange","DCIFormat","RNTIType","ServingCellID","CCID","BWPId","AbsoluteSlot","ConfigurationEpoch","FDRAType","PRBStart","PRBLength","VRBToPRBMapping","K0","StartSymbol","SymbolLength","MappingType","MCSTable","MCSIndex","NDI","RV","HARQProcessID","AntennaPortField","TCIStateId","SPSActivationDCIId","SPSActivationDCICRCPass","SPSActivationDCIRNTIMatch","SPSConfigPresent","SPSActivated","SPSReleased","SPSOccasionMatch","ExpectedStatus","ExpectedError"]
    assignment_expected_fields = ["CaseID","ExpectedStatus","ExpectedError","ExpectedAssignmentSource","ExpectedWaveformAllowed","ExpectedConfigurationMutation"]
    produced += [
        write_csv("pdsch_scheduling_assignment_test_vectors.csv", assignment_fields, assignment),
        write_csv("expected_pdsch_assignment_resolution.csv", assignment_expected_fields, assignment_expected),
    ]
    ptrs, ptrs_expected = build_ptrs_vectors()
    ptrs_fields = ["CaseID","MappingType","TimeDensity","FrequencyDensity","REOffset","PDSCHDuration","NPRB","MCSIndex","MCSTable","RNTIType","PTRSPortSet","DMRSPortSet","ExpectedPTRSPresent","ExpectedStatus","ExpectedReason"]
    ptrs_expected_fields = ["CaseID","ExpectedPresent","ExpectedStatus","ExpectedReason"]
    produced += [
        write_csv("pdsch_ptrs_test_vectors.csv", ptrs_fields, ptrs),
        write_csv("expected_pdsch_ptrs_presence.csv", ptrs_expected_fields, ptrs_expected),
    ]
    reserved_in, reserved_out = build_reserved_vectors()
    reserved_fields = ["CaseID","AllocationRE","SSBRE","CORESETRE","NZPCSIRSRE","ZPCSIRSRE","LTECRSRE","RateMatchPatternRE","ExpectedStatus","ExpectedError"]
    reserved_out_fields = ["CaseID","AllocationRECount","ReservedUnionCount","DataRECount","ReservedOutsideAllocationCount","PairwiseOverlapMultiplicity","ExpectedReservedUnion","ExpectedDataRE","Status","ExpectedError"]
    produced += [
        write_csv("pdsch_reserved_re_test_vectors.csv", reserved_fields, reserved_in),
        write_csv("expected_pdsch_reserved_re_union.csv", reserved_out_fields, reserved_out),
    ]
    prec = build_precoding_vectors()
    prec_fields = ["CaseID","Mode","NPorts","NLayers","NPRG","NSymbolGroups","PRGSize","PRBSet","MatrixShape","ExpectedStatus","ExpectedError"]
    prec_expected = []
    for row in prec:
        slices = int(row["NPRG"]) * int(row["NSymbolGroups"]) if row["ExpectedStatus"] == "PASS" else 0
        prec_expected.append({
            "CaseID": row["CaseID"], "ExpectedStatus": row["ExpectedStatus"],
            "ExpectedError": row.get("ExpectedError", ""),
            "ExpectedMatrixRank": 4 if row["ExpectedStatus"] == "PASS" else 0,
            "ExpectedAppliedSlices": slices,
            "ExpectedTXApplication": 1 if row["ExpectedStatus"] == "PASS" else 0,
            "ExpectedRXApplication": 1 if row["ExpectedStatus"] == "PASS" else 0,
        })
    produced += [
        write_csv("pdsch_precoding_prg_test_vectors.csv", prec_fields, prec),
        write_csv("expected_pdsch_precoding_behavior.csv", ["CaseID","ExpectedStatus","ExpectedError","ExpectedMatrixRank","ExpectedAppliedSlices","ExpectedTXApplication","ExpectedRXApplication"], prec_expected),
    ]
    harq = build_harq_vectors()
    harq_fields = ["CaseID","HARQProcessID","TransmissionIndex","NDI","RV","NewData","SameTBIdentity","SameTBS","SameCodeBlockLayout","ExpectedCombine","ExpectedStatus","ExpectedError"]
    harq_expected = []
    for row in harq:
        if row["ExpectedStatus"] == "ERROR":
            action = "reject"
        elif int(row["NewData"]) == 1:
            action = "reset_and_load_new_tb"
        elif int(row["ExpectedCombine"]) == 1:
            action = "position_aware_soft_combine"
        else:
            action = "decode_without_combine"
        harq_expected.append({
            "CaseID": row["CaseID"], "ExpectedStatus": row["ExpectedStatus"],
            "ExpectedError": row.get("ExpectedError", ""),
            "ExpectedCombine": row["ExpectedCombine"], "ExpectedHARQAction": action,
        })
    produced += [
        write_csv("pdsch_harq_test_vectors.csv", harq_fields, harq),
        write_csv("expected_pdsch_harq_transitions.csv", ["CaseID","ExpectedStatus","ExpectedError","ExpectedCombine","ExpectedHARQAction"], harq_expected),
    ]
    cov = build_coverage_matrix()
    produced.append(write_csv("pdsch_declared_coverage_matrix.csv", list(cov[0].keys()), cov))
    csv_contract, image_contract = build_contracts()
    produced += [
        write_csv("desired_pdsch_csv_contract.csv", list(csv_contract[0].keys()), csv_contract),
        write_csv("desired_pdsch_image_contract.csv", list(image_contract[0].keys()), image_contract),
    ]

    audit_rows = []
    for path in produced:
        with path.open(newline="", encoding="utf-8") as f:
            row_count = sum(1 for _ in csv.DictReader(f))
        audit_rows.append({
            "FileName": path.name,
            "RowCount": row_count,
            "ByteCount": path.stat().st_size,
            "SHA256": sha256(path),
            "Status": "PASS" if row_count > 0 else "FAIL",
        })
    audit = write_csv("expected_output_integrity_audit.csv", ["FileName","RowCount","ByteCount","SHA256","Status"], audit_rows)
    manifest = {
        "generator": Path(__file__).name,
        "generator_sha256": sha256(Path(__file__)),
        "external_ldpc": {
            "fixture": external_ldpc_fixture.name,
            "generator": external_ldpc_generator.name,
            "generator_sha256": sha256(external_ldpc_generator),
            "readme": external_ldpc_readme.name,
            "readme_sha256": sha256(external_ldpc_readme),
            "implementation": "py3gpp",
            "version": "0.6.0",
            "source_artifact_sha256":
                "1182b03eed6aa44e1af49df827d2712206189a620fd85985e7b795bef11c9aa9",
        },
        "external_receiver": {
            "fixture": external_receiver_fixture.name,
            "generator": external_receiver_generator.name,
            "generator_sha256": sha256(external_receiver_generator),
            "readme": external_receiver_readme.name,
            "readme_sha256": sha256(external_receiver_readme),
            "implementation": "py3gpp",
            "version": "0.6.0",
            "source_artifact_sha256":
                "1182b03eed6aa44e1af49df827d2712206189a620fd85985e7b795bef11c9aa9",
            "fixture_schema_version": "external_pdsch_receiver/v1",
        },
        "files": [{"name": r["FileName"], "rows": r["RowCount"], "sha256": r["SHA256"]} for r in audit_rows],
        "integrity_audit_sha256": sha256(audit),
    }
    (ROOT / "independent_vector_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"generated_files": len(produced) + 2, "csv_files": len(produced) + 1, "manifest": "independent_vector_manifest.json"}, indent=2))


if __name__ == "__main__":
    main()
