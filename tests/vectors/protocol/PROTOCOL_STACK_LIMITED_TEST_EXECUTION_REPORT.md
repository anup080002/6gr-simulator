# Limited Execution Report — RLC, PDCP, SDAP, RRC and Traffic

## Scope

This report validates the generated independent vectors, contracts, Python verifiers and current-source signatures. MATLAB/Octave production execution was not available in this environment.

## Pack statistics

```text
Findings:                         15
Static targeted signatures:      44
Detected current defects:        44
Useful foundations detected:     10
Independent manifest files:      27
Independent manifest rows:       3169
Impact families:                 64
Impact experiments:              768
Acceptance rules:                96
Required CSVs:                   50
Required PNGs:                   52
Required artifacts:              102
```

## Current repository status

```text
Existing CSVs inspected:         225
Rectangular existing CSVs:       224
Existing PNGs inspected:         40
Decoded PNGs:                    40
Contracted artifacts present:    0/102
```

The existing outputs do not contain the contracted bit-exact RLC/PDCP/SDAP, ASN.1 RRC, bearer, handover, traffic-session or lineage artifacts.

## Executable checks

| Check | Status | Exit |
|---|---:|---:|
| PY_COMPILE_VECTOR | PASS | 0 |
| PY_COMPILE_BASE | PASS | 0 |
| PY_COMPILE_IMPACT | PASS | 0 |
| VECTOR_VERIFY | PASS | 0 |
| BASE_VERIFIER_SELFTEST | PASS | 0 |
| IMPACT_VERIFIER_SELFTEST | PASS | 0 |
| MATLAB_PRODUCTION_RUNTIME | BLOCKED | 3 |
| CURRENT_SOURCE_REMEDIATION | FAIL | 2 |
| CURRENT_REQUIRED_ARTIFACTS | FAIL | 2 |

## Important boundary

The pack includes exact analytical vectors for bounded RLC headers, PDCP headers/COUNT, NEA2/NIA2, SDAP headers, deterministic traffic and lineage. The RRC message matrix deliberately marks independent frozen Release-18 UPER vectors as required before a message is enabled. It does not fabricate ASN.1 encodings.

## Runtime limitation

MATLAB: `None`

Octave: `None`

Therefore the corrected production stack, existing MATLAB tests and generated production CSV/PNG artifacts remain mandatory Codex execution tasks.
