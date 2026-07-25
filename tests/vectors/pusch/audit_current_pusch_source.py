#!/usr/bin/env python3
"""Static source-visible PUSCH/UL-SCH audit for the uploaded simulator.

This detector is intentionally narrow: it records concrete production shortcuts
that the implementation prompt must remove and useful foundations to preserve.
It does not claim waveform correctness and never substitutes for MATLAB tests.
"""
from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

# id, kind, source file, regex, finding, optional expectation
CHECKS = [
    ("ULSRC-001", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"addParameter\(\s*['\"]HARQACKBits['\"]", "TX exposes an ACK-only UCI input rather than typed HARQ-ACK/CSI1/CSI2/SR/CG-UCI payloads."),
    ("ULSRC-002", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"nrULSCHMultiplex\([\s\S]{0,500}?codedAck\(:\)\s*,\s*\[\]\s*,\s*\[\]\s*\)", "UL-SCH multiplexing passes empty CSI Part 1 and CSI Part 2 streams."),
    ("ULSRC-003", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"nrULSCHInfo\([\s\S]{0,300}?oack\s*,\s*0\s*,\s*0\s*\)", "TX UCI allocation hard-codes O_CSI1=0 and O_CSI2=0."),
    ("ULSRC-004", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Rx.m", r"addParameter\(\s*['\"]ExpectedHARQACKBits['\"]", "RX exposes an ACK-only expected-UCI interface."),
    ("ULSRC-005", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Rx.m", r"nrULSCHDemultiplex\([\s\S]{0,500}?oack\s*,\s*0\s*,\s*0\s*,", "RX demultiplexing hard-codes CSI Part 1 and CSI Part 2 lengths to zero."),
    ("ULSRC-006", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"PUSCHMultiCodewordUnsupported", "Production TX explicitly rejects more than one UL-SCH transport block/codeword."),
    ("ULSRC-007", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"single_ulsch_codeword_ranks_1_to_4", "TX declares only a one-codeword rank-1-to-4 scope."),
    ("ULSRC-008", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Rx.m", r"single_ulsch_codeword_ranks_1_to_4", "RX declares only a one-codeword rank-1-to-4 scope."),
    ("ULSRC-009", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"structGet\(\s*cfg\s*,\s*['\"]phy\.pusch\.modulation['\"]\s*,\s*['\"]16QAM['\"]\s*\)", "Missing PUSCH modulation silently defaults to 16QAM."),
    ("ULSRC-010", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"structGet\(\s*cfg\s*,\s*['\"]phy\.pusch\.symbolAllocation['\"]\s*,\s*\[\s*0\s+14\s*\]\s*\)", "Missing PUSCH time allocation silently becomes a full normal-CP slot."),
    ("ULSRC-011", "DEFECT", "+sixgr/+phy/+grant/freezePHYGrant.m", r"root\s*\+\s*['\"]\.symbolAllocation['\"]\s*,\s*\[\s*0\s+14\s*\]", "Frozen UL grant silently defaults to a full normal-CP slot."),
    ("ULSRC-012", "DEFECT", "+sixgr/+phy/+grant/freezePHYGrant.m", r"prbSet\s*=\s*0\s*:\s*\(\s*max\(\s*1\s*,\s*round\(\s*nSizeGrid\s*\)\s*\)\s*-\s*1\s*\)", "Missing PRB allocation silently becomes the complete BWP/grid."),
    ("ULSRC-013", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"DMRSPortSet\s*=\s*0\s*:\s*\(\s*pusch\.NumLayers\s*-\s*1\s*\)", "Explicit DM-RS port ownership is overwritten from layer count."),
    ("ULSRC-014", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"DMRSTypeAPosition\s*=\s*max\(\s*2\s*,\s*min\(\s*3", "DM-RS type-A position is silently clamped."),
    ("ULSRC-015", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"DMRSConfigurationType\s*=\s*max\(\s*1\s*,\s*min\(\s*2", "DM-RS configuration type is silently clamped."),
    ("ULSRC-016", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"DMRSAdditionalPosition\s*=\s*max\(\s*0\s*,\s*min\(\s*3", "DM-RS additional position is silently clamped."),
    ("ULSRC-017", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"DMRSLength\s*=\s*max\(\s*1\s*,\s*min\(\s*2", "DM-RS length is silently clamped."),
    ("ULSRC-018", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"NumCDMGroupsWithoutData\s*=\s*max\(\s*1\s*,\s*min\(\s*3", "DM-RS CDM-group count is silently clamped."),
    ("ULSRC-019", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"if\s+startSym\s*>\s*typeAPos[\s\S]{0,800}?mapType\s*=\s*['\"]B['\"]", "An invalid mapping-type-A request may be silently converted to mapping type B."),
    ("ULSRC-020", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"ptrs\.timeDensity['\"]\s*,\s*\[\]\s*\)[\s\S]{0,180}?\n\s*2\s*\)", "PT-RS time density has a hidden fallback of 2."),
    ("ULSRC-021", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"ptrs\.frequencyDensity['\"]\s*,\s*\[\]\s*\)[\s\S]{0,180}?\n\s*2\s*\)", "PT-RS frequency density has a hidden fallback of 2."),
    ("ULSRC-022", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"ptrs\.reOffset['\"][\s\S]{0,160}?['\"]00['\"]", "PT-RS RE offset has a hidden fallback of 00."),
    ("ULSRC-023", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"if\s+isempty\(\s*portSet\s*\)[\s\S]{0,180}?PTRSPortSet\s*=\s*0", "PT-RS port has a hidden fallback of port 0."),
    ("ULSRC-024", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"TimeDensity\s*=\s*max\(\s*1\s*,\s*round", "PT-RS time density is rounded/clamped rather than table-validated."),
    ("ULSRC-025", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"FrequencyDensity\s*=\s*max\(\s*1\s*,\s*round", "PT-RS frequency density is rounded/clamped rather than table-validated."),
    ("ULSRC-026", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"PI/2-BPSK[\s\S]{0,260}?tp\s*=\s*true", "pi/2-BPSK mutates transform-precoding state instead of validating procedure ownership."),
    ("ULSRC-027", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"localEnsureTransformPrecodingOwnership[\s\S]{0,1200}?pusch\.TransformPrecoding\s*=\s*true", "TX can auto-enable transform precoding after configuration materialization."),
    ("ULSRC-028", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"structGet\(\s*cfg\s*,\s*['\"]phy\.pusch\.TPMI['\"]", "TX can resolve TPMI directly from configuration."),
    ("ULSRC-029", "DEFECT", "+sixgr/+link/runULPUSCHThroughput.m", r"configuredTPMI\s*=\s*double\(\s*sixgr\.util\.structGet\(\s*cfg\s*,\s*['\"]phy\.pusch\.TPMI['\"]", "UL scheduling/throughput path can select a configured TPMI rather than a current SRS decision."),
    ("ULSRC-030", "DEFECT", "+sixgr/+link/runULPUSCHThroughput.m", r"localDeriveULPathlossFromConfiguredSNR", "PUSCH power control can derive pathloss from configured SNR instead of an RS measurement."),
    ("ULSRC-031", "DEFECT", "+sixgr/+link/runULPUSCHThroughput.m", r"alpha\s*=\s*min\(\s*max\(\s*double\(\s*alpha\s*\)\s*,\s*0\s*\)\s*,\s*1\s*\)", "Power-control alpha is silently clamped."),
    ("ULSRC-032", "DEFECT", "+sixgr/+link/runULPUSCHThroughput.m", r"requestedPower\s*=\s*[\s\S]{0,300}?10\s*\*\s*log10\(\s*double\(\s*mRB\s*\)\s*\)", "PUSCH power formula omits the 2^mu bandwidth factor."),
    ("ULSRC-033", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"nrPDSCHPrecode", "PUSCH element expansion delegates to a PDSCH-named helper instead of an explicit UL precoder application path."),
    ("ULSRC-034", "DEFECT", "+sixgr/+phy/+ul/puschCodebookCatalog.m", r"case\s+4", "Current codebook catalog visibly centers on 1/2/4-port cases; release-valid 8-port tables are not complete."),
    ("ULSRC-035", "DEFECT", "+sixgr/+phy/+grid/allocREsPUSCH.m", r"FrequencyHopping", "No explicit end-to-end frequency-hop-plan owner is present in the canonical PUSCH allocator.", "EXPECT_ABSENT"),
    ("ULSRC-036", "DEFECT", "+sixgr/+phy/+ul/PUSCH_Rx.m", r"info\.Status\s*=\s*['\"]unavailable['\"][\s\S]{0,120}?return", "Strict UCI receive processing can return an unavailable status instead of failing the transmission."),
    ("ULSRC-037", "DEFECT", "+sixgr/+control/isPDCCHGrantBindingRequired.m", r"phy\.pusch\.grantSource", "Decoded-PDCCH binding is policy/configuration dependent rather than inherent to dynamic connected PUSCH ownership."),
    ("ULSRC-038", "DEFECT", "+sixgr/+link/resolveWaveformGrant.m", r"freezePHYGrantForGrant", "Waveform grant resolution can freeze scheduler/configuration state before decoded DCI becomes the immutable PUSCH assignment."),
    # Useful foundations to preserve.
    ("ULSRC-039", "FOUNDATION", "+sixgr/+phy/+ul/PUSCH_Tx.m", r"computeResourceAccounting", "TX already uses a centralized resource-accounting helper."),
    ("ULSRC-040", "FOUNDATION", "+sixgr/+phy/+ul/PUSCH_Rx.m", r"computePostEqSINR", "RX already computes post-equalization SINR from receiver processing."),
    ("ULSRC-041", "FOUNDATION", "+sixgr/+phy/+ul/estimateSRSRITPMI.m", r"Hest", "A measured-SRS RI/TPMI estimator exists and should be made authoritative rather than replaced."),
    ("ULSRC-042", "FOUNDATION", "+sixgr/+phy/+waveform/transformPrecode.m", r"nrTransformPrecode", "A production transform-precoding wrapper exists."),
    ("ULSRC-043", "FOUNDATION", "+sixgr/+phy/+waveform/transformDeprecode.m", r"nrTransformDeprecode", "A production inverse-transform wrapper exists."),
    ("ULSRC-044", "FOUNDATION", "+sixgr/+phy/+ul/PUSCH_Rx.m", r"combineSoftLLR", "Receiver has position-aware HARQ soft-combining infrastructure."),
    ("ULSRC-045", "FOUNDATION", "+sixgr/+phy/+ul/PUSCH_Rx.m", r"localCorrectEqualizedPUSCHCPEFromPTRS", "Receiver has a PT-RS common-phase-error correction path."),
    ("ULSRC-046", "FOUNDATION", "+sixgr/+phy/+pdcch/buildDCI00UplinkGrant.m", r"encodeDCIPayload", "A bounded DCI 0_0 uplink-grant encoder exists."),
    ("ULSRC-047", "FOUNDATION", "+sixgr/+phy/+pdcch/buildDCI01UplinkGrant.m", r"encodeDCIPayload", "A bounded DCI 0_1 uplink-grant encoder exists."),
]


def scan(root: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for item in CHECKS:
        if len(item) == 5:
            cid, kind, rel, pattern, finding = item
            expectation = "EXPECT_PRESENT"
        else:
            cid, kind, rel, pattern, finding, expectation = item
        path = root / rel
        text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
        matches = list(re.finditer(pattern, text, re.MULTILINE | re.DOTALL))
        present = bool(matches)
        triggered = (not present) if expectation == "EXPECT_ABSENT" else present
        status = ("FAIL" if triggered else "PASS") if kind == "DEFECT" else ("PASS" if triggered else "FAIL")
        line = ""
        snippet = ""
        if matches:
            m = matches[0]
            line_no = text.count("\n", 0, m.start()) + 1
            line = str(line_no)
            start = max(0, m.start() - 80)
            end = min(len(text), m.end() + 160)
            snippet = " ".join(text[start:end].split())[:420]
        rows.append({
            "CheckID": cid,
            "Kind": kind,
            "SourceFile": rel,
            "Expectation": expectation,
            "PatternPresent": int(present),
            "Line": line,
            "Snippet": snippet,
            "Finding": finding,
            "Status": status,
        })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repository_root", type=Path)
    ap.add_argument("--output", type=Path, default=Path("current_pusch_static_audit.csv"))
    args = ap.parse_args()
    rows = scan(args.repository_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    defects = [r for r in rows if r["Kind"] == "DEFECT"]
    foundations = [r for r in rows if r["Kind"] == "FOUNDATION"]
    print(
        f"checks={len(rows)} defects_detected={sum(r['Status']=='FAIL' for r in defects)} "
        f"defect_signatures_absent={sum(r['Status']=='PASS' for r in defects)} "
        f"foundations_present={sum(r['Status']=='PASS' for r in foundations)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
