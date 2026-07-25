# PDCCH/DCI limited execution and current-source report

## Scope

This report validates the source-specific audit, deterministic vectors, Type-0 table transcriptions, controlled impact matrix, CSV/PNG contracts, and Python verifiers supplied with the Codex pack. It does **not** claim that the uploaded MATLAB PDCCH/DCI implementation passes the phase.

## Current production-source audit

- Static checks: **55**
- Targeted defect checks: **48**
- Defect signatures detected: **42**
- Useful implementation foundations checked: **7**
- Foundations detected: **7**
- Current technical result: **FAIL**

The strongest foundations are existing CRC/Polar wrapper use, a strict configuration entry point, bounded DCI 0_0/1_0 support, and some receiver metric plumbing. The principal failures are contextual DCI sizing, padding/truncation, exact RNTI/CRC procedures, candidate generation, CCE/REG interleaving, Type-0 breadth, true blind monitoring, and decoded-DCI grant authority.

See `current_pdcch_static_audit.csv` for every matched file, line, technical impact, and required correction.

## Deterministic independent floor

- Manifested files: **24**
- Manifested rows: **1,369**
- Missing files: **0**
- Row-count mismatches: **0**
- SHA-256 mismatches: **0**
- Generated without MATLAB/5G Toolbox: **true**

Coverage includes:

- contextual DCI input matrices and a bounded independent size/alignment floor;
- CRC24C and RNTI masking;
- PDCCH physical scrambling and QPSK;
- pure-spec PDCCH DM-RS sequence and RE-index vectors;
- exact non-interleaved/interleaved REG-to-CCE mapping floors;
- CSS/USS candidate enumeration;
- monitoring-occasion arithmetic;
- complete Release-18 Type-0 CORESET table family represented by Tables 13-0 through 13-10A, including reserved and conditional-offset rows;
- Tables 13-11, 13-12, and 13-12A monitoring parameters;
- pattern-2/3 Tables 13-13 through 13-15A;
- GSCN-offset Tables 13-16 and 13-17;
- blind-search, BWP, cross-carrier, beam, grant-authority, and declared-coverage inputs.

The floor deliberately does not pretend to replace a complete independent Polar encoder/decoder, every optional 0_1/1_1 field combination, or an external full-stack reference. Codex must add or freeze those references before reporting final completion.

## Controlled impact analysis

- Impact families: **50**
- Experiments: **600**
- Controlled baseline/treatment pairs: **300**
- Pairing contracts: **50**
- Acceptance rules: **75**
  - hard correctness rules: **55**
  - statistical rules: **12**
  - diagnostic rules: **8**

The matrix was checked so that both members of each pair share all common context and random-stream identifiers, while only `FactorValue` changes.

## Required production outputs

- Base CSVs: **21**
- Base PNGs: **13**
- Impact CSVs: **16**
- Impact PNGs: **28**
- Combined artifacts: **78**
- Existing contracted artifacts present: **0/78**

The uploaded simulator contains 40 bundled PNGs. All 40 decode and are structurally nonblank, but none is a contracted PDCCH/DCI figure. Nine PDCCH-related CSV candidates are rectangular, but none satisfies the production output contract.

## Verifier results

### Base verifier

```text
Valid synthetic set:
    required CSVs: 21/21
    required PNGs: 13/13
    failures:       0
    exit code:      0

Injected corruption:
    detected: png_hash_mismatch:pdcch_coreset_reg_cce_map.png
    exit code: 2
```

### Impact verifier

```text
Valid synthetic set:
    experiments: 600/600
    rules:        75/75
    CSVs:         16/16
    PNGs:         28/28
    failures:      0
    exit code:     0

Injected corruption:
    detected: png_hash_mismatch:pdcch_impact_payload_size.png
    exit code: 2
```

## Limited test summary

```text
Total checks:  17
PASS:          14
FAIL:           2
BLOCKED:        1
```

The two failures are expected pre-remediation results: the uploaded source still contains 42 targeted defect signatures, and none of the 78 contracted production artifacts exists. The blocked item is actual MATLAB execution.

## Runtime limitation

- MATLAB executable: **not found**
- Octave executable: **not found**

Consequently, this environment did not execute the current or corrected production waveform, Polar encode/decode, blind candidate search, Type-0 acquisition, BLER/detection/false-alarm campaigns, or MATLAB figure-object semantic checks. Codex must execute every mandatory MATLAB command on the pinned MATLAB/5G Toolbox release and must report `BLOCKED`, not `COMPLETE`, when that toolchain is unavailable.
