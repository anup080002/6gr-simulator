# PUSCH and UL-SCH limited execution report

## Scope and result

This report validates the supplied Codex implementation pack and performs every non-MATLAB check available in the current environment against the uploaded 6GR simulator source. It does **not** claim that the corrected PUSCH/UL-SCH waveform chain has run: MATLAB and Octave are not installed, and Codex has not yet applied the production changes.

```text
Pack infrastructure checks: 21 PASS, 0 FAIL
Current simulator checks:     0 PASS, 2 FAIL
Current-output inventory:     1 PASS
Mandatory MATLAB runtime:     BLOCKED
Overall current phase status: FAIL
```

The two current-simulator failures are expected pre-remediation results: 38 targeted shortcut signatures remain, and none of the 31 phase-specific artifacts exists. The blocked MATLAB row remains blocked rather than being converted to a pass.

## Important technical corrections built into this pack

- **Scheduling Request is not encoded as generic UCI on PUSCH.** The supplied nonzero-SR inputs are typed negative cases and must be routed to the PUCCH procedure. The PUSCH payload covers HARQ-ACK, CSI Part 1, CSI Part 2, CG-UCI/UTO-UCI where configured, and standards-valid UCI-only PUSCH cases.

- **Transform-precoded strict PUSCH is rank 1 in the pinned profile.** High-rank PUSCH applies to release-valid transform-disabled codebook/non-codebook tuples. Every transform-enabled rank greater than one is a negative test.

- **The strict UL modulation ceiling in this pack is 256QAM.** 1024QAM and 4096QAM are typed PUSCH negatives.

- **Two UL-SCH transport blocks are implemented as two real codewords.** UCI ownership uses the higher initial `I_MCS`, with a tie to the first transport block.

## Supplied deterministic vectors

| Input file | Rows |
| --- | ---: |
| `pusch_scrambling_test_vectors.csv` | 15 |
| `pusch_modulation_test_vectors.csv` | 26 |
| `pusch_layer_mapping_test_vectors.csv` | 12 |
| `pusch_coding_tbs_test_vectors.csv` | 23 |
| `pusch_tb_crc_test_vectors.csv` | 18 |
| `pusch_scheduling_assignment_test_vectors.csv` | 26 |
| `pusch_uci_multiplex_test_vectors.csv` | 34 |
| `pusch_dmrs_test_vectors.csv` | 84 |
| `pusch_ptrs_test_vectors.csv` | 60 |
| `pusch_transform_precoding_test_vectors.csv` | 14 |
| `pusch_frequency_hopping_test_vectors.csv` | 27 |
| `pusch_srs_precoder_test_vectors.csv` | 20 |
| `pusch_precoding_application_test_vectors.csv` | 39 |
| `pusch_power_control_test_vectors.csv` | 33 |
| `pusch_harq_test_vectors.csv` | 21 |
| `pusch_declared_coverage_matrix.csv` | 35 |
| **Total** | **487** |

| Bounded expected file | Rows |
| --- | ---: |
| `expected_pusch_scrambling_vectors.csv` | 15 |
| `expected_pusch_modulation_vectors.csv` | 26 |
| `expected_pusch_layer_mapping.csv` | 40 |
| `expected_pusch_tbs_basegraph.csv` | 23 |
| `expected_pusch_tb_crc_vectors.csv` | 18 |
| `expected_pusch_assignment_resolution.csv` | 26 |
| `expected_pusch_uci_owner_and_budget.csv` | 34 |
| `expected_pusch_dmrs_validation_floor.csv` | 84 |
| `expected_pusch_ptrs_presence.csv` | 60 |
| `expected_pusch_transform_dft_vectors.csv` | 14 |
| `expected_pusch_hop_plans.csv` | 27 |
| `expected_pusch_srs_precoder_decisions.csv` | 20 |
| `expected_pusch_precoding_application.csv` | 39 |
| `expected_pusch_power_control.csv` | 33 |
| `expected_pusch_harq_transitions.csv` | 21 |
| **Total** | **480** |

The bounded expected vectors were regenerated without MATLAB and verified against a 31-file SHA-256/row-count manifest. They are a floor, not complete independent DM-RS/PT-RS/UCI/LDPC/codebook references; the Codex prompt requires the missing full table/frozen-vector families before completion.

## The 12 production findings

| ID | Priority | Required implementation | Acceptance |
| --- | --- | --- | --- |
| UL-001 | P1 | Complete TS 38.212 UCI-on-PUSCH encode/multiplex/demultiplex/decode chain | Positive and negative vectors recover HARQ-ACK/CSI/CG-UCI payloads over all supported PUSCH UCI combinations, detect length/configuration mismatches, and reject any attempt to encode SR on PUSCH. |
| UL-002 | P1 | Exact PUSCH DM-RS port/mapping/sequence ownership | Non-default valid port sets are applied and reported; invalid layer/port combinations fail. |
| UL-003 | P1 | Executable release-pinned PUSCH capability matrix | All declared combinations meet BLER/BER/SINR evidence requirements over multiple seeds; unsupported combinations fail before run. |
| UL-004 | P1 | Normative rank-constrained DFT-s-OFDM/transform precoding | Single-layer pi/2-BPSK/QPSK/16QAM/64QAM/256QAM cases pass exact DFT, energy, round-trip, DM-RS/PT-RS, hopping and BLER tests; every rank greater than one with transform precoding enabled fails with the typed layer-count error and produces no waveform. |
| UL-005 | P2 | End-to-end PUSCH frequency hopping | Hopping RE maps match independent expected maps and decode over frequency-selective channels. |
| UL-006 | P1 | Decoded DCI 0_x / configured-grant / random-access assignment factories | Changing decoded DCI changes actual PUSCH resources; absent/failed DCI prevents strict transmission. |
| UL-007 | P1 | SRS-derived rank/SRI/TPMI/precoder authority | Scheduler decisions change with SRS channel/age, stale reports are rejected or penalized, and applied TPMI equals the reported decision. |
| UL-008 | P2 | Configured-grant Type 1/Type 2 state machines | Activation, periodic transmission, collision, retransmission, and release scenarios pass with slot-accurate evidence. |
| UL-009 | P1 | Complete PUSCH PT-RS and receiver phase tracking | PTRS-enabled runs show expected tracked phase and performance benefit; wrong association fails. |
| UL-010 | P2 | High-rank, non-codebook and bounded MU-PUSCH | Two-UE shared-PRB waveform decodes both users with controlled interference and correct resource/identity isolation. |
| UL-011 | P0 | Mandatory receiver-derived post-equalization SINR | The real catalog scenario fails when measured SINR is removed and passes only with receiver-derived measurements within tolerance. |
| UL-012 | P1 | Independent bit/index/matrix/power/reference vectors | DUT passes independent vectors and catches injected bit, RV, port, and resource errors. |

## Current source-specific static result

```text
Static checks executed:       47
Defect signatures detected:   38 / 38
Useful foundations detected:   9 / 9
Current production result:    FAIL
```

The useful foundations include centralized PUSCH resource accounting, receiver-derived post-equalization SINR, an SRS RI/TPMI estimator, transform pre/deprecoding wrappers, position-aware HARQ combining, PT-RS CPE correction, and bounded DCI 0_0/0_1 encoders. The implementation prompt preserves and integrates them rather than replacing them blindly.

| Check | Source | Current defect |
| --- | --- | --- |
| ULSRC-001 | `+sixgr/+phy/+ul/PUSCH_Tx.m:49` | TX exposes an ACK-only UCI input rather than typed HARQ-ACK/CSI1/CSI2/SR/CG-UCI payloads. |
| ULSRC-002 | `+sixgr/+phy/+ul/PUSCH_Tx.m:183` | UL-SCH multiplexing passes empty CSI Part 1 and CSI Part 2 streams. |
| ULSRC-003 | `+sixgr/+phy/+ul/PUSCH_Tx.m:623` | TX UCI allocation hard-codes O_CSI1=0 and O_CSI2=0. |
| ULSRC-004 | `+sixgr/+phy/+ul/PUSCH_Rx.m:51` | RX exposes an ACK-only expected-UCI interface. |
| ULSRC-005 | `+sixgr/+phy/+ul/PUSCH_Rx.m:2499` | RX demultiplexing hard-codes CSI Part 1 and CSI Part 2 lengths to zero. |
| ULSRC-006 | `+sixgr/+phy/+ul/PUSCH_Tx.m:728` | Production TX explicitly rejects more than one UL-SCH transport block/codeword. |
| ULSRC-007 | `+sixgr/+phy/+ul/PUSCH_Tx.m:747` | TX declares only a one-codeword rank-1-to-4 scope. |
| ULSRC-008 | `+sixgr/+phy/+ul/PUSCH_Rx.m:918` | RX declares only a one-codeword rank-1-to-4 scope. |
| ULSRC-009 | `+sixgr/+phy/+grid/allocREsPUSCH.m:126` | Missing PUSCH modulation silently defaults to 16QAM. |
| ULSRC-010 | `+sixgr/+phy/+grid/allocREsPUSCH.m:132` | Missing PUSCH time allocation silently becomes a full normal-CP slot. |
| ULSRC-011 | `+sixgr/+phy/+grant/freezePHYGrant.m:389` | Frozen UL grant silently defaults to a full normal-CP slot. |
| ULSRC-012 | `+sixgr/+phy/+grant/freezePHYGrant.m:364` | Missing PRB allocation silently becomes the complete BWP/grid. |
| ULSRC-013 | `+sixgr/+phy/+grid/allocREsPUSCH.m:238` | Explicit DM-RS port ownership is overwritten from layer count. |
| ULSRC-014 | `+sixgr/+phy/+grid/allocREsPUSCH.m:307` | DM-RS type-A position is silently clamped. |
| ULSRC-015 | `+sixgr/+phy/+grid/allocREsPUSCH.m:317` | DM-RS configuration type is silently clamped. |
| ULSRC-016 | `+sixgr/+phy/+grid/allocREsPUSCH.m:327` | DM-RS additional position is silently clamped. |
| ULSRC-017 | `+sixgr/+phy/+grid/allocREsPUSCH.m:337` | DM-RS length is silently clamped. |
| ULSRC-018 | `+sixgr/+phy/+grid/allocREsPUSCH.m:345` | DM-RS CDM-group count is silently clamped. |
| ULSRC-019 | `+sixgr/+phy/+grid/allocREsPUSCH.m:276` | An invalid mapping-type-A request may be silently converted to mapping type B. |
| ULSRC-020 | `+sixgr/+phy/+grid/allocREsPUSCH.m:365` | PT-RS time density has a hidden fallback of 2. |
| ULSRC-021 | `+sixgr/+phy/+grid/allocREsPUSCH.m:369` | PT-RS frequency density has a hidden fallback of 2. |
| ULSRC-022 | `+sixgr/+phy/+grid/allocREsPUSCH.m:372` | PT-RS RE offset has a hidden fallback of 00. |
| ULSRC-023 | `+sixgr/+phy/+grid/allocREsPUSCH.m:388` | PT-RS port has a hidden fallback of port 0. |
| ULSRC-024 | `+sixgr/+phy/+grid/allocREsPUSCH.m:379` | PT-RS time density is rounded/clamped rather than table-validated. |
| ULSRC-025 | `+sixgr/+phy/+grid/allocREsPUSCH.m:382` | PT-RS frequency density is rounded/clamped rather than table-validated. |
| ULSRC-026 | `+sixgr/+phy/+grid/allocREsPUSCH.m:170` | pi/2-BPSK mutates transform-precoding state instead of validating procedure ownership. |
| ULSRC-027 | `+sixgr/+phy/+ul/PUSCH_Tx.m:1264` | TX can auto-enable transform precoding after configuration materialization. |
| ULSRC-028 | `+sixgr/+phy/+ul/PUSCH_Tx.m:464` | TX can resolve TPMI directly from configuration. |
| ULSRC-029 | `+sixgr/+link/runULPUSCHThroughput.m:4601` | UL scheduling/throughput path can select a configured TPMI rather than a current SRS decision. |
| ULSRC-030 | `+sixgr/+link/runULPUSCHThroughput.m:2806` | PUSCH power control can derive pathloss from configured SNR instead of an RS measurement. |
| ULSRC-031 | `+sixgr/+link/runULPUSCHThroughput.m:2832` | Power-control alpha is silently clamped. |
| ULSRC-032 | `+sixgr/+link/runULPUSCHThroughput.m:2852` | PUSCH power formula omits the 2^mu bandwidth factor. |
| ULSRC-033 | `+sixgr/+phy/+ul/PUSCH_Tx.m:834` | PUSCH element expansion delegates to a PDSCH-named helper instead of an explicit UL precoder application path. |
| ULSRC-034 | `+sixgr/+phy/+ul/puschCodebookCatalog.m:54` | Current codebook catalog visibly centers on 1/2/4-port cases; release-valid 8-port tables are not complete. |
| ULSRC-035 | `+sixgr/+phy/+grid/allocREsPUSCH.m:n/a` | No explicit end-to-end frequency-hop-plan owner is present in the canonical PUSCH allocator. |
| ULSRC-036 | `+sixgr/+phy/+ul/PUSCH_Rx.m:2494` | Strict UCI receive processing can return an unavailable status instead of failing the transmission. |
| ULSRC-037 | `+sixgr/+control/isPDCCHGrantBindingRequired.m:44` | Decoded-PDCCH binding is policy/configuration dependent rather than inherent to dynamic connected PUSCH ownership. |
| ULSRC-038 | `+sixgr/+link/resolveWaveformGrant.m:55` | Waveform grant resolution can freeze scheduler/configuration state before decoded DCI becomes the immutable PUSCH assignment. |

## Existing CSV and image inventory

```text
Bundled CSV files inspected:      225
Rectangular/parse-valid CSVs:     224
Malformed CSVs:                   1
Bundled PNG files decoded:        40 / 40
Structurally nonblank PNGs:       40 / 40
Required PUSCH CSVs present:      0 / 20
Required PUSCH PNGs present:      0 / 11
Required phase artifacts present: 0 / 31
```

The one malformed bundled CSV is `tmp_geom_cfg_export_manual/run/reports/csv/phase7_truth_gates.csv`: nonrectangular_row_2_columns_109_expected_69. This is outside the PUSCH artifact set but is recorded rather than hidden.

The 40 existing PNGs are largely geometry, throughput, SINR, queue, and layout plots. They do not prove PUSCH UCI multiplexing, DM-RS/PT-RS/hopping, transform precoding, SRS-derived TPMI, power control, codeword/layer mapping, or PUSCH BLER. Therefore current PUSCH-specific image correctness evidence is **0/11**.

## Artifact-verifier self-test

```text
Complete synthetic artifact set: 42 passed, 0 failed, exit 0
Injected PNG hash corruption:    41 passed, 1 failed, exit 2
Detected failure:                png_hash_mismatch
```

The verifier checks all 20 CSVs, all 11 PNGs, required columns, primary-key uniqueness, mandatory status, finite/nonnegative fields, cross-file semantics, image decoding, dimensions, nonblank content, labels/titles, source linkage, and SHA-256 integrity. This validates the verifier, not the simulator waveform.

## Limited executable check table

| Check | Class | Status | Observed |
| --- | --- | --- | --- |
| PY-COMPILE | PACK_INFRASTRUCTURE | PASS | scripts=6 errors=0 |
| VECTOR-MANIFEST | PACK_INFRASTRUCTURE | PASS | files=31 failures=0 |
| VECTOR-IDEMPOTENCE | PACK_INFRASTRUCTURE | PASS | files=31 changed=0 |
| VECTOR-SCOPE | PACK_INFRASTRUCTURE | PASS | inputs=16 input_rows=487 expected=15 expected_rows=480 |
| SCRAMBLING | PACK_INFRASTRUCTURE | PASS | rows=15 placeholders_ok=True |
| MODULATION | PACK_INFRASTRUCTURE | PASS | legal=['16QAM', '256QAM', '64QAM', 'PI/2-BPSK', 'QPSK'] unsupported=['1024QAM', '4096QAM'] constellation_normalized=True finite_vectors=True |
| LAYER-MAPPING | PACK_INFRASTRUCTURE | PASS | ranks=[1, 2, 3, 4, 5, 6, 7, 8] layers=[0, 1, 2, 3, 4, 5, 6, 7] high_rank_two_cw=True |
| TRANSFORM-PRECODING | PACK_INFRASTRUCTURE | PASS | positive=9 multilayer_negative=2 |
| ASSIGNMENT-PROFILES | PACK_INFRASTRUCTURE | PASS | profiles=['configured_grant_type1_strict', 'configured_grant_type2_strict', 'connected_dynamic_strict', 'phy_calibration', 'random_access_ul_strict'] negative_errors=16 |
| UCI-OWNER | PACK_INFRASTRUCTURE | PASS | two_tb_cases=6 exact=True |
| UCI-SR-ROUTING | PACK_INFRASTRUCTURE | PASS | nonzero_osr_rows=6 rejected=6 |
| DMRS-FLOOR | PACK_INFRASTRUCTURE | PASS | rows=84 |
| PTRS-FLOOR | PACK_INFRASTRUCTURE | PASS | rows=60 |
| FREQUENCY-HOPPING | PACK_INFRASTRUCTURE | PASS | modes=['inter_slot', 'intra_slot', 'none'] type2_reject=True rows=27 |
| SRS-PRECODER | PACK_INFRASTRUCTURE | PASS | rows=20 |
| PRECODER-APPLICATION | PACK_INFRASTRUCTURE | PASS | rows=39 positives=34 |
| POWER-CONTROL | PACK_INFRASTRUCTURE | PASS | loops=['0', '1'] modes=['absolute', 'accumulated'] clipped=6 |
| HARQ | PACK_INFRASTRUCTURE | PASS | actions=['NEW_DATA', 'RETRANSMISSION'] rows=21 |
| ULSCH-CODING-FLOOR | PACK_INFRASTRUCTURE | PASS | tbs_rows=23 tbs_status={'PASS': 18, 'ERROR': 5} crc_rows=18 crc_status={'PASS': 18} |
| ARTIFACT-CONTRACT | PACK_INFRASTRUCTURE | PASS | csv=20 png=11 |
| ARTIFACT-VERIFIER | PACK_INFRASTRUCTURE | PASS | PUSCH artifact verification: 42 passed, 0 failed PUSCH artifact verification: 41 passed, 1 failed FAIL SEMANTIC pusch_resource_grid_ownership.png: png_hash_mismatch self-test valid exit=0 checks=42 failures=0 self-test corrupt exit=2 failures=1 detected=True |
| EXISTING-PNG-INTEGRITY | CURRENT_OUTPUT_INVENTORY | PASS | decoded=40/40 |
| CURRENT-SOURCE-REMEDIATION | CURRENT_SIMULATOR | FAIL | defects_detected=38/38 foundations_present=9 |
| CURRENT-REQUIRED-ARTIFACTS | CURRENT_SIMULATOR | FAIL | present=0/31 csv=0/20 png=0/11 |
| MATLAB-PRODUCTION-RUNTIME | MANDATORY_RUNTIME | BLOCKED | matlab=not_found; octave=not_found |

## Required MATLAB execution still blocked here

MATLAB and Octave are absent from this environment. Consequently these mandatory operations were not executed:

- production PUSCH/UL-SCH TX/RX through MATLAB 5G Toolbox;
- exact DCI/CG/RAR/MsgA assignment materialization;
- full UL-SCH LDPC/rate-matching and UCI coding/multiplexing;
- exact DM-RS/PT-RS table and sequence comparisons;
- no-noise rank/codeword waveform round trips;
- AWGN/TDL/CDL and frequency-hopping campaigns;
- SRS-driven precoder application;
- closed-loop waveform power scaling;
- HARQ combining gain;
- bounded MU-PUSCH;
- generation and semantic validation of the 20 production CSVs and 11 production PNGs.

Codex is explicitly prohibited from reporting `COMPLETE` when these tests are unavailable, skipped, or blocked.

## Commands to execute after Codex remediation

```bash
python tests/vectors/pusch/verify_pusch_vector_pack.py
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PUSCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*ULSCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.ul.pusch.runPUSCHPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','pusch'),'OutputDir',fullfile(pwd,'artifacts','pusch_ulsch_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/pusch/verify_pusch_artifacts.py artifacts/pusch_ulsch_phase
```

## Current conclusion

The pack infrastructure and bounded independent-vector floor pass all available checks. The current simulator remains **FAIL** for this phase because all 38 targeted source behaviors remain and all 31 PUSCH-specific production artifacts are absent. The actual MATLAB waveform result is **BLOCKED** in this environment, not assumed.

