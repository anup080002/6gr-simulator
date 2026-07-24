#!/usr/bin/env python3
"""Static source checks for the current PDSCH/DL-SCH implementation.

This is not a conformance test. It only documents source-visible shortcuts that
must disappear from the production strict path before the MATLAB runtime tests
can be meaningful.
"""
from __future__ import annotations
import argparse, csv, re
from pathlib import Path

CHECKS = [
    ("PD-STATIC-001", "+sixgr/+link/resolveWaveformGrant.m", r'grant\.Source\s*=\s*"explicit_waveform_grant"', True, "Grant is materialized from configuration before DCI is built."),
    ("PD-STATIC-002", "+sixgr/+link/resolveWaveformGrant.m", r'prbSet\s*=\s*0:\(round\(nGrid\)\s*-\s*1\)', True, "Missing PDSCH PRB allocation becomes the full carrier grid."),
    ("PD-STATIC-003", "+sixgr/+link/resolveWaveformGrant.m", r'symAlloc\s*=\s*\[0\s+14\]', True, "Missing PDSCH symbol allocation becomes a full normal-CP slot."),
    ("PD-STATIC-004", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'DMRSPortSet\s*=\s*0:\(pdsch\.NumLayers-1\)', True, "Configured DM-RS ports are overwritten by 0:(NumLayers-1)."),
    ("PD-STATIC-005", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'DMRSTypeAPosition\s*=\s*max\(2,\s*min\(3', True, "DMRS type-A position is clamped rather than validated."),
    ("PD-STATIC-006", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'DMRSConfigurationType\s*=\s*max\(1,\s*min\(2', True, "DMRS configuration type is clamped rather than validated."),
    ("PD-STATIC-007", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'DMRSAdditionalPosition\s*=\s*max\(0,\s*min\(3', True, "DMRS additional position is clamped rather than validated."),
    ("PD-STATIC-008", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'DMRSLength\s*=\s*max\(1,\s*min\(2', True, "DMRS length is clamped rather than validated."),
    ("PD-STATIC-009", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'NumCDMGroupsWithoutData\s*=\s*max\(1,\s*min\(3', True, "DMRS CDM groups are clamped rather than validated against the configuration."),
    ("PD-STATIC-010", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'tokens\s*=\s*"QPSK"', True, "Missing PDSCH modulation silently becomes QPSK."),
    ("PD-STATIC-011", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'tokens\(end\+1:nCodewords\)\s*=\s*tokens\(end\)', True, "A short multi-codeword modulation list is silently repeated."),
    ("PD-STATIC-012", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'tokens\s*=\s*tokens\(1:nCodewords\)', True, "An overlong multi-codeword modulation list is silently truncated."),
    ("PD-STATIC-013", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'mapType\s*=\s*"B"', True, "An invalid type-A start can be changed to mapping type B instead of rejected."),
    ("PD-STATIC-014", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'PTRSTimeDensity.*\[\].*\n\s*2\)', True, "PTRS time density has an implicit default."),
    ("PD-STATIC-015", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'PTRSFrequencyDensity.*\[\].*\n\s*2\)', True, "PTRS frequency density has an implicit default."),
    ("PD-STATIC-016", "+sixgr/+phy/+grid/allocREsPDSCH.m", r'ptrs\.PTRSPortSet\s*=\s*0', True, "Missing PTRS port set silently becomes port 0."),
    ("PD-STATIC-017", "+sixgr/+phy/+dl/resolvePDSCHPrecoding.m", r'PRGBundleUnsupported', True, "Three-dimensional/per-PRG PDSCH precoder bundles are rejected."),
    ("PD-STATIC-018", "+sixgr/+phy/+dl/resolvePDSCHPrecoding.m", r'Custom DMRSPortSet is not supported', True, "Valid non-default DM-RS ports are rejected in the precoding path."),
    ("PD-STATIC-019", "+sixgr/+phy/+dl/resolvePDSCHPrecoding.m", r'Wcfg\s*=\s*\[\];', True, "A stale explicit matrix can be discarded and regenerated from scalar PMI."),
    ("PD-STATIC-020", "+sixgr/+phy/+resource/computeResourceAccounting.m", r'nrePerPRB\s*=\s*floor\(quotient\)', True, "NRE/PRB can be reconstructed by flooring instead of using exact index evidence."),
    ("PD-STATIC-021", "+sixgr/+phy/+resource/computeResourceAccounting.m", r'gBitsPerCodeword\s*=\s*double\(layerDataRE\)', True, "G can be reconstructed from layer RE, Qm and layers."),
    ("PD-STATIC-022", "+sixgr/+phy/+dl/PDSCH_Tx.m", r'if isempty\(opt\.PDSCH\).*?allocREsPDSCH', True, "PDSCH_Tx can create a connected transmission directly from configuration without a decoded assignment."),
    ("PD-STATIC-023", "+sixgr/+phy/+dl/PDSCH_Tx.m", r'localCSIRSResourceCollision', True, "CSI-RS collision is checked after PDSCH indices/symbols are generated instead of through one ownership map."),
    ("PD-STATIC-024", "+sixgr/+phy/+dl/PDSCH_Tx.m", r'nrResourceGrid\(carrier, nPages\).*?catch.*?complex\(zeros', True, "Resource-grid creation has a catch-all manual zero-grid fallback."),
    ("PD-STATIC-025", "+sixgr/+control/isPDCCHGrantBindingRequired.m", r'localAnyTruthy\(cfg, commonPaths\)', True, "PDCCH-to-PDSCH grant binding is policy-optional rather than intrinsic to connected strict mode."),
    ("PD-STATIC-026", "+sixgr/+phy/+dl/PDSCH_Tx.m", r'nLayers\s*<\s*1\s*\|\|\s*nLayers\s*>\s*8', False, "Production source includes an explicit rank 1-8 guard."),
    ("PD-STATIC-027", "+sixgr/+phy/+dl/PDSCH_Tx.m", r'case\s+5.*?counts\s*=\s*\[2\s+3\]', False, "Production source includes the rank-5 two-codeword layer split."),
    ("PD-STATIC-028", "+sixgr/+phy/+dl/PDSCH_Tx.m", r'rateMatchLDPC', False, "Production source rate-matches each codeword to a codeword-specific G."),
    ("PD-STATIC-029", "+sixgr/+phy/+dl/PDSCH_Rx.m", r'HARQSoftCombining', False, "Receiver contains a soft-combining path, which still requires broader context tests."),
]


def first_match(text: str, pattern: str):
    m = re.search(pattern, text, flags=re.MULTILINE | re.DOTALL)
    if not m:
        return None
    line = text.count("\n", 0, m.start()) + 1
    snippet = " ".join(m.group(0).strip().split())[:240]
    return line, snippet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("--output", default="current_pdsch_static_audit.csv")
    ns = ap.parse_args()
    root = Path(ns.repo)
    rows = []
    for cid, rel, pattern, finding_when_present, note in CHECKS:
        path = root / rel
        text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
        hit = first_match(text, pattern)
        # For shortcut checks, presence is FAIL. For positive capability checks, presence is PASS.
        if finding_when_present:
            status = "FAIL" if hit else "PASS"
        else:
            status = "PASS" if hit else "FAIL"
        rows.append({
            "CheckID": cid,
            "File": rel,
            "Line": hit[0] if hit else "",
            "PatternPresent": bool(hit),
            "Status": status,
            "Evidence": hit[1] if hit else "pattern not found",
            "RequiredCorrectionOrMeaning": note,
        })
    out = Path(ns.output)
    with out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader(); w.writerows(rows)
    failures = sum(r["Status"] == "FAIL" for r in rows)
    print(f"checks={len(rows)} pass={len(rows)-failures} fail={failures} output={out}")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
