# SSB, Initial Access, SIB1 and Random Access — Limited Execution Report

## Scope

This pack is designed to make Codex implement the bounded Release-18 FR1 chain:

```text
PSS/SSS -> PBCH/MIB -> Type-0 CSS -> SI-RNTI DCI 1_0
-> SIB1 PDSCH/DL-SCH -> SIB1 ASN.1
-> PRACH Msg1 -> RAR Msg2 -> Msg3 RRCSetupRequest
-> Msg4 contention resolution/RRCSetup -> SRB1 -> RRCSetupComplete
-> UE and gNB RRC_CONNECTED
```

It is an implementation-and-execution prompt. It does not ask Codex to produce another audit.

## Current source result

The source-visible audit executed **56 checks**:

```text
Targeted defect signatures detected: 46
Useful implementation foundations:   10
Current technical phase result:       FAIL
```

Detected technical shortcuts include:

- SSB grid clamp/retry;
- unsupported `Lmax` coercion and SSB-index clipping;
- one-hot single-SSB transmission;
- multiple inconsistent SSB-case resolvers;
- receiver timing/case/Lmax fallbacks;
- fixed Type-0 30 kHz / index-zero / AL4 / one-candidate / 32-bit profile;
- synthetic one-millisecond SSB-to-SI waveform gap;
- local SIB1 PRB scanning and floored NRE;
- expected SIB1 tree/payload/tree-hash receiver inputs;
- custom `sixgr_sib1_anchor_profile_v1` encoding;
- restricted-set rejection in the strict RA path;
- fixed Msg2/Msg3/Msg4 slot defaults;
- one PRACH occasion in the RA binding;
- one-attempt four-step success ending at Msg4;
- no complete SetupComplete transition;
- no complete two-step, CFRA, BFR, SUL, NTN or RedCap profile.

The useful foundations that should be retained include Toolbox-backed PSS/SSS/PBCH/BCH kernels, waveform-backed Msg1/RAR/Msg3/Msg4 stage kernels, PRACH waveform/detector code, RA-RNTI helpers, event/timer artifact plumbing and several useful test entry points.

See:

- `current_initial_access_static_audit.csv`
- `initial_access_source_change_map.csv`
- `initial_access_error_contract.csv`

## Supplied technical vectors

The independent manifest protects:

```text
Files: 43
Rows:  11307
Hash/row failures: 0
```

Important vector coverage:

| Family | Rows |
|---|---:|
| SSB case/profile inputs | 67 |
| Expected SSB burst candidates | 360 |
| Exact SS/PBCH RE ownership | 3840 |
| MIB semantic inputs | 53 |
| Type-0 table vectors | 452 |
| SIB1 semantic inputs | 83 |
| PRACH config-index sweep | 512 |
| PRACH format/restricted-set matrix | 380 |
| RA-RNTI arithmetic | 128 |
| Generic PRACH occasion arithmetic | 1120 |
| SSB-to-RO arithmetic floor | 120 |
| Preamble power-ramping floor | 320 |
| Timer/backoff floor | 96 |
| RRC transition floor | 32 |
| End-to-end scenarios | 146 |
| Negative cases | 138 |
| Capability tuples | 271 |

### Important independent-reference limit

The pack does **not** pretend that a local SIB1 encode/decode round trip is an independent ASN.1 reference. Codex must add externally generated Release-18 SIB1 UPER vectors satisfying `sib1_frozen_vector_requirements.csv`.

Likewise, `prach_configuration_index_sweep.csv` supplies all 512 FDD/TDD index inputs, but Codex must add a release-pinned independent table/vector source for the complete PRACH configuration-index outputs. The current DUT or a duplicate call to the same Toolbox function cannot be used as that independent source.

## Impact analysis

The pack defines:

```text
Technical families:        60
Controlled experiments:    720
Matched pairs:             360
Acceptance rules:          90
Independent floor rows:    120
```

Dependency waves:

| Wave | Families | Meaning |
|---|---:|---|
| A | 42 | Direct implementation in this phase |
| B | 12 | Requires real integrated PHY/MAC dependency |
| C | 6 | Requires adjacent implementation or explicit extension gate |

No Wave-B/C experiment may substitute configured SINR, perfect timing, perfect beam state, a boolean collision flag or a four-step fallback for the real dependency.

## Output contracts

The corrected production MATLAB chain must generate:

```text
Base CSVs:    31
Base PNGs:    20
Impact CSVs:  16
Impact PNGs:  30
Total:        97
```

Current source archive:

```text
Contracted artifacts found: 0 / 97
```

The archive contains 40 existing PNGs. All 40 decode and are structurally nonblank, but none is one of the contracted initial-access figures.

The archive contains 225 CSVs. 224 are rectangular. One unrelated file is malformed:

```text
tmp_geom_cfg_export_manual/run/reports/csv/phase7_truth_gates.csv
```

## Verifier results

### Vector verifier

```text
43 manifest files
11,307 rows
60 impact families
720 impact experiments
90 acceptance rules
0 failures
exit code 0
```

### Base artifact verifier self-test

```text
Complete synthetic 31-CSV / 20-PNG set: accepted
Injected PNG hash corruption: detected
exit code 0
```

### Impact artifact verifier self-test

```text
Complete synthetic 16-CSV / 30-PNG set: accepted
Injected PNG hash corruption: detected
exit code 0
```

These verifier self-tests establish that the contracts and integrity checks work. They do not establish that the current MATLAB simulator passes.

## Runtime limitation

Neither MATLAB nor Octave is installed in this execution environment.

Therefore, the following were **not executed** here:

- corrected SSB waveform generation;
- true blind PSS/SSS/PBCH acquisition;
- MIB-to-Type-0 control acquisition;
- SIB1 PDCCH/PDSCH decoding;
- independent ASN.1 UPER interoperability;
- PRACH table and waveform matrix;
- multi-attempt four-step RA;
- Msg3 HARQ;
- RRCSetupComplete;
- no-signal and false-alarm campaigns;
- all 52 mandatory phase tests;
- all 720 impact experiments;
- all 97 production artifacts.

The archive contains 109 existing MATLAB test files that reference initial-access-related terms, out of 483 test files. None could be executed here.

## Limited test summary

```text
PASS:    12
WARN:     1
FAIL:     2
BLOCKED:  2
```

The two pre-remediation failures are intentional and factual:

1. the current source still contains 46 targeted technical shortcuts;
2. none of the 97 required production artifacts exists.

The blocked items are production MATLAB execution and relevant MATLAB tests.

## Completion condition for Codex

Codex may report `COMPLETE` only after:

- all 16 findings are closed for the bounded profile;
- all 52 mandatory MATLAB tests execute and pass;
- independent SIB1 UPER and PRACH references are added and pass;
- multi-SSB blind acquisition uses no transmitted truth;
- Type-0 and SIB1 are decoded causally;
- four-step RA supports real retry/power/timer/contention behavior;
- RRCSetupComplete produces synchronized UE/gNB connected state;
- all 720 impact experiments execute;
- all 90 rules have valid evidence;
- all 97 CSV/PNG artifacts pass;
- both artifact verifiers return zero;
- the complete repository regression remains passing.
