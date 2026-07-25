# Codex implementation prompt 03 — PUSCH and UL-SCH complete MATLAB PHY chain

You are working directly in the root of the **6GR MATLAB simulator** repository.

This is an **implementation and execution task**. It is not an audit, review, design memo, documentation-only task, standards-claim exercise, truth-contract exercise, publication-wording task, schema-only task, or request for a plan.

Your job is to:

1. modify the production MATLAB source;
2. replace every PUSCH/UL-SCH shortcut listed in this prompt with an explicit executable PHY procedure;
3. migrate every production caller to the corrected chain;
4. implement complete HARQ-ACK, CSI Part 1, CSI Part 2, CG-UCI/UTO-UCI where selected, and UCI-only processing on PUSCH;
5. make dynamic PUSCH ownership originate from decoded DCI 0_x plus current UE/RRC/BWP state;
6. implement separate standards-valid factories for configured grants, RAR Msg3, MsgA, and laboratory calibration;
7. make measured SRS state authoritative for rank/SRI/TPMI/precoder decisions where the selected transmission scheme requires it;
8. implement exact PUSCH power control and apply it to the actual waveform;
9. add independent bit-, symbol-, index-, matrix-, power-, HARQ-, and receiver-level tests;
10. run the tests on the pinned MATLAB/5G Toolbox release;
11. generate every required CSV and PNG artifact from actual production execution;
12. run the supplied Python verifiers;
13. continue correcting production code until every mandatory check passes.

Do not return only a plan. Do not stop after adding classes, interfaces, metadata, test stubs, or CSV writers. Do not report `COMPLETE` unless all mandatory MATLAB tests execute and pass, all required artifacts are produced from the real chain, and both supplied Python verifiers return exit code 0.

---

## 1. Scope

Fix the complete PUSCH and UL-SCH chain and only the minimum adjacent interfaces required to make it real and executable:

1. dynamic DCI 0_0/0_1/0_2/0_3 scheduling ownership;
2. Type-1 and Type-2 configured-grant state and occasion ownership;
3. RAR Msg3 and MsgA PUSCH assignment ownership;
4. DCI/RRC/BWP/SRS/HARQ/power-state materialization;
5. exact frequency- and time-domain resource allocation;
6. PUSCH data and UCI scrambling, including TS 38.211 `x` and `y` placeholder behavior;
7. pi/2-BPSK, QPSK, 16QAM, 64QAM, and 256QAM modulation/demodulation;
8. one- and two-UL-SCH-transport-block codeword-to-layer mapping over every release-valid declared rank;
9. exact UL-SCH transport-block sizing, CRC, segmentation, LDPC encoding, rate matching, and inverse receive processing;
10. complete UCI-on-PUSCH coding, bit budgeting, multiplexing, demultiplexing, and decoding;
11. PUSCH DM-RS configuration, logical ports, sequences, indices, hopping, and channel-estimation use;
12. PUSCH PT-RS configuration, sequences, indices, port association, and receiver phase tracking;
13. exact single-layer transform precoding and inverse transform for the selected strict profile;
14. intra-slot, inter-slot, and selected repetition frequency hopping;
15. codebook and non-codebook PUSCH precoding over all declared release-valid tuples;
16. measured-SRS-derived channel/rank/SRI/TPMI/precoder state;
17. open- and closed-loop PUSCH transmit-power control with actual waveform scaling;
18. receiver extraction, hop-aware channel estimation, equalization, deprecoding, LLR generation, UCI/UL-SCH separation, and decoding;
19. codeword-specific HARQ process state and position-aware soft combining;
20. bounded two-UE MU-PUSCH interference and identity isolation;
21. deterministic CSV and PNG diagnostics generated from the production execution path.

Do not spend this phase implementing WebGUI, authentication, security, marketing claims, release-claim text, generic truth contracts, RLC/PDCP/RRC breadth, broad PUCCH, broad PDCCH blind search, channel-model statistics, or RF-device conformance. Adjacent modules may be changed only to expose exact technical state required by PUSCH.

The frame/grid/numerology/duplexing phase and the decoded-DCI interface are dependencies. Reuse their canonical carrier, BWP, absolute-slot, symbol-direction, timing, and decoded-control objects. Do not create local full-slot, 14-symbol, full-band, scalar-BWP, configured-grant, or configured-TPMI fallbacks inside PUSCH.

---

## 2. Mandatory standards baseline

Pin this phase to one exact Release-18 maintenance baseline. If the repository does not already pin exact versions, use and record:

- **3GPP TS 38.211 V18.8.0**
  - modulation mapping and pseudo-random sequence generation;
  - clause 6.3.1 PUSCH scrambling, modulation, layer mapping, transform precoding, precoding, and mapping;
  - PUSCH DM-RS and PT-RS clauses, including hopping-specific behavior.
- **3GPP TS 38.212 V18.8.0**
  - UL-SCH TB CRC, code-block segmentation, LDPC encoding, rate matching, and concatenation;
  - UCI channel coding and rate matching;
  - clause 6.2.7 data/control multiplexing on PUSCH;
  - DCI 0_x field definitions used by the assignment materializer.
- **3GPP TS 38.213 V18.8.0**
  - K2 and PUSCH timing legality;
  - PUSCH open-/closed-loop power-control procedures and TPC commands;
  - relevant UCI/PUSCH timing and simultaneous-transmission restrictions.
- **3GPP TS 38.214 V18.8.0**
  - PUSCH MCS tables and TBS determination;
  - frequency- and time-domain resource allocation;
  - codebook/non-codebook transmission, SRS/SRI/TPMI/rank procedures;
  - transform-precoding, frequency-hopping, repetition, PT-RS, and configured-grant procedures.
- **3GPP TS 38.331 V18.8.0**
  - `PUSCH-Config`, `PUSCH-ConfigCommon`, `DMRS-UplinkConfig`, `PTRS-UplinkConfig`;
  - `ConfiguredGrantConfig`, SRS resources/resource sets, power-control, BWP, serving-cell, and capability state.
- **3GPP TS 38.321 V18.8.0** only for the minimum configured-grant/HARQ/MAC state ownership needed by this phase.

The pinned 3GPP profile is authoritative when a MATLAB 5G Toolbox release is broader, narrower, or interprets a newer table. Add a version adapter or a pure implementation rather than silently modifying requested behavior.

Technical constraints for this strict profile:

- PUSCH supports up to two codewords/UL-SCH transport blocks where the selected release tuple permits it.
- With two UL-SCH transport blocks, UCI is multiplexed only on the transport block with the higher initial `I_MCS`; a tie uses the first transport block.
- Release-valid eight-port codebooks may support up to eight layers when transform precoding is disabled.
- The selected transform-precoded strict profile supports one transmitted layer. Reject `NumLayers > 1` before waveform generation.
- The strict PUSCH modulation set is pi/2-BPSK, QPSK, 16QAM, 64QAM, and 256QAM. Reject 1024QAM and 4096QAM for PUSCH in this profile.
- pi/2-BPSK requires a valid transform-precoded PUSCH procedure, but the modulation string must never auto-enable transform precoding.
- Scheduling Request is not a generic UCI payload carried by PUSCH. Route SR to the PUCCH procedure or reject it at the PUSCH UCI factory. Do not invent PUSCH SR coding.

---

## 3. Execution profiles and assignment ownership

Implement five technically distinct entry paths. They must not silently fall back into one another.

### 3.1 `connected_dynamic_strict`

A dynamic PUSCH transmission is legal only when derived from:

- one decoded DCI 0_x event with passed CRC;
- the correct decoded RNTI and procedure;
- the active serving-cell, component-carrier, and UL-BWP state for the same configuration epoch;
- the canonical frame/timing state and exact K2 target slot;
- UE capability and active PUSCH/RRC configuration;
- current HARQ process state;
- a valid measured SRS decision when the selected codebook/non-codebook procedure requires it;
- a valid power-control state and measured pathloss reference;
- an available UL symbol allocation after TDD resolution.

A nested configuration struct, scheduler intention, configured MCS, configured PRBs, configured TPMI, or frozen grant without decoded-control provenance must not directly create a connected strict PUSCH waveform.

### 3.2 `configured_grant_type1_strict`

A Type-1 configured grant is legal only when:

- a valid `ConfiguredGrantConfig` is installed by the active RRC context;
- the serving-cell/BWP/configuration epoch matches;
- the absolute slot is an exact configured-grant occasion;
- repetition, HARQ, RV, UCI, collision, transform-precoding, hopping, and power state are valid;
- the grant has not been released or invalidated.

Do not synthesize Type-1 installation from a generic PUSCH configuration.

### 3.3 `configured_grant_type2_strict`

A Type-2 configured grant additionally requires:

- a prior CRC-valid activation DCI decoded for the correct CS-RNTI procedure;
- an active, not released Type-2 context;
- an exact periodic occasion at the current configuration epoch.

Bare RRC configuration is not activation. A failed or wrong-RNTI activation DCI must create no active context and no waveform.

### 3.4 `random_access_ul_strict`

Use separate factories for:

- RAR-derived Msg3 PUSCH;
- MsgA PUSCH derived from the active two-step-random-access configuration.

Preserve RAPID/RA-RNTI/TC-RNTI identity, RAR grant fields, MsgA resource identity, scrambling initialization, timing, transform-precoding state, and power-ramping context. Do not reinterpret random-access grants as C-RNTI dynamic grants.

### 3.5 `phy_calibration`

A direct deterministic assignment may be created only by an explicit calibration factory. Every required field must be present and validated. This factory may be used by no-noise/AWGN unit tests and link calibration, but its output must be rejected by connected, configured-grant, and random-access strict entry points.

Do not implement a boolean such as `allowConfiguredGrantInStrictMode`. Use separate factories, immutable source tags, and separate state types.

---

## 4. Supplied implementation and test pack

Place this pack under `tests/vectors/pusch/` without editing expected values merely to make production code pass.

### 4.1 Generator and integrity tools

- `generate_pusch_independent_vectors.py`
- `verify_pusch_vector_pack.py`
- `verify_pusch_artifacts.py`
- `independent_vector_manifest.json`
- `expected_output_integrity_audit.csv`

Before MATLAB execution run:

```bash
python tests/vectors/pusch/verify_pusch_vector_pack.py
```

It must return exit code 0.

### 4.2 Supplied input vectors
- `pusch_scrambling_test_vectors.csv` — 15 rows
- `pusch_modulation_test_vectors.csv` — 26 rows
- `pusch_layer_mapping_test_vectors.csv` — 12 rows
- `pusch_coding_tbs_test_vectors.csv` — 23 rows
- `pusch_tb_crc_test_vectors.csv` — 18 rows
- `pusch_scheduling_assignment_test_vectors.csv` — 26 rows
- `pusch_uci_multiplex_test_vectors.csv` — 34 rows
- `pusch_dmrs_test_vectors.csv` — 84 rows
- `pusch_ptrs_test_vectors.csv` — 60 rows
- `pusch_transform_precoding_test_vectors.csv` — 14 rows
- `pusch_frequency_hopping_test_vectors.csv` — 27 rows
- `pusch_srs_precoder_test_vectors.csv` — 20 rows
- `pusch_precoding_application_test_vectors.csv` — 39 rows
- `pusch_power_control_test_vectors.csv` — 33 rows
- `pusch_harq_test_vectors.csv` — 21 rows
- `pusch_declared_coverage_matrix.csv` — 35 rows

The supplied pack contains **487 input rows** in 16 input files. These rows are a mandatory floor, not complete conformance coverage. Add exact table-driven and generated boundary cases required by the work items below.

### 4.3 Bounded independent expected results
- `expected_pusch_scrambling_vectors.csv` — 15 rows
- `expected_pusch_modulation_vectors.csv` — 26 rows
- `expected_pusch_layer_mapping.csv` — 40 rows
- `expected_pusch_tbs_basegraph.csv` — 23 rows
- `expected_pusch_tb_crc_vectors.csv` — 18 rows
- `expected_pusch_assignment_resolution.csv` — 26 rows
- `expected_pusch_uci_owner_and_budget.csv` — 34 rows
- `expected_pusch_dmrs_validation_floor.csv` — 84 rows
- `expected_pusch_ptrs_presence.csv` — 60 rows
- `expected_pusch_transform_dft_vectors.csv` — 14 rows
- `expected_pusch_hop_plans.csv` — 27 rows
- `expected_pusch_srs_precoder_decisions.csv` — 20 rows
- `expected_pusch_precoding_application.csv` — 39 rows
- `expected_pusch_power_control.csv` — 33 rows
- `expected_pusch_harq_transitions.csv` — 21 rows

The supplied bounded floor contains **480 expected rows**, generated without MATLAB or 5G Toolbox. It deliberately marks broad DM-RS/PT-RS/UCI/LDPC/codebook cases as requiring stronger table or frozen-vector oracles. Codex must add those missing independent references; it must not relabel a same-Toolbox comparison as independent.

MATLAB tests must invoke production functions and compare actual values field by field. Never copy expected CSVs into the output directory.

### 4.4 Required output contracts

- `desired_pusch_csv_contract.csv`
- `desired_pusch_image_contract.csv`

The phase runner must generate every contracted file from actual production execution. The Python artifact verifier is fail-closed.

## 4.5 Mandatory closure map for all 12 findings

| ID | Priority | Implementation element | Production correction | Acceptance |
| --- | --- | --- | --- | --- |
| UL-001 | P1 | Complete TS 38.212 UCI-on-PUSCH encode/multiplex/demultiplex/decode chain | Replace the ACK-only HARQACKBits interface with typed HARQ-ACK, CSI Part 1, CSI Part 2, CG-UCI, UTO-UCI where selected by the pinned profile, and UCI-only payload objects; compute O_ACK/O_CSI1/O_CSI2, beta offsets, alpha, coded lengths, placeholders and bit positions from the active PUSCH assignment. Implement two-UL-SCH-TB UCI ownership. Scheduling Request is not a generic PUSCH UCI payload: route it to PUCCH or reject it at the PUSCH payload factory. | Positive and negative vectors recover HARQ-ACK/CSI/CG-UCI payloads over all supported PUSCH UCI combinations, detect length/configuration mismatches, and reject any attempt to encode SR on PUSCH. |
| UL-002 | P1 | Exact PUSCH DM-RS port/mapping/sequence ownership | Remove DMRSPortSet=0:(NumLayers-1) and every clamp. Resolve logical DM-RS ports from decoded antenna-port information plus active RRC DMRS-UplinkConfig; validate port/CDM/OCC/layer/codebook/transform-precoding combinations without mutating input. | Non-default valid port sets are applied and reported; invalid layer/port combinations fail. |
| UL-003 | P1 | Executable release-pinned PUSCH capability matrix | Drive the same production TX/RX chain across every declared modulation, rank, codeword count, DM-RS, PT-RS, transform-precoding, hopping, codebook/non-codebook, UCI and channel tuple. Reject unsupported tuples before waveform generation. | All declared combinations meet BLER/BER/SINR evidence requirements over multiple seeds; unsupported combinations fail before run. |
| UL-004 | P1 | Normative rank-constrained DFT-s-OFDM/transform precoding | Resolve transformPrecoder from the valid DCI/RRC/configured-grant/random-access procedure. Apply a unitary M_SC^PUSCH-point DFT to each eligible OFDM-symbol block for the single transmitted layer, including the transform-precoded PT-RS insertion rules. Implement inverse transform after equalization. Never auto-enable transform precoding from modulation, and reject NumLayers>1 for transform-precoded strict PUSCH unless the pinned release explicitly permits the selected tuple. | Single-layer pi/2-BPSK/QPSK/16QAM/64QAM/256QAM cases pass exact DFT, energy, round-trip, DM-RS/PT-RS, hopping and BLER tests; every rank greater than one with transform precoding enabled fails with the typed layer-count error and produces no waveform. |
| UL-005 | P2 | End-to-end PUSCH frequency hopping | Materialize intra-slot, inter-slot and repetition-Type-B hop plans from decoded DCI/RAR/configured-grant state; map data/DM-RS/PT-RS per hop; perform hop-aware channel estimation/equalization and reject hopping for incompatible resource-allocation modes. | Hopping RE maps match independent expected maps and decode over frequency-selective channels. |
| UL-006 | P1 | Decoded DCI 0_x / configured-grant / random-access assignment factories | Create immutable PUSCHSchedulingAssignment objects. Dynamic connected assignments require CRC-valid decoded DCI 0_0/0_1/0_2/0_3 and current UE/RRC/BWP/HARQ/SRS/power state. Implement separate Type-1 CG, activated Type-2 CG, RAR Msg3, MsgA and calibration factories. | Changing decoded DCI changes actual PUSCH resources; absent/failed DCI prevents strict transmission. |
| UL-007 | P1 | SRS-derived rank/SRI/TPMI/precoder authority | Create timestamped ULChannelSoundingState with resource identity, H estimate, noise/covariance, RI/SRI/TPMI/beam/precoder and validity epoch. Scheduler and PUSCH assignment must consume this state; stale or mismatched SRS cannot silently fall back to configured TPMI. | Scheduler decisions change with SRS channel/age, stale reports are rejected or penalized, and applied TPMI equals the reported decision. |
| UL-008 | P2 | Configured-grant Type 1/Type 2 state machines | Implement installation, activation, periodic occasion resolution, repetition, UCI, collision handling, retransmission and release with slot-accurate state. Type 2 requires CRC-valid CS-RNTI activation; Type 1 requires installed RRC state. | Activation, periodic transmission, collision, retransmission, and release scenarios pass with slot-accurate evidence. |
| UL-009 | P1 | Complete PUSCH PT-RS and receiver phase tracking | Validate exact CP-OFDM/DFT-s-OFDM PT-RS parameters, generate exact indices/sequences per hop, associate the correct DM-RS/antenna port, estimate and correct CPE before demodulation, and quantify EVM/BLER improvement under calibrated phase noise. | PTRS-enabled runs show expected tracked phase and performance benefit; wrong association fails. |
| UL-010 | P2 | High-rank, non-codebook and bounded MU-PUSCH | Implement every release-valid declared rank/codeword/port tuple, non-codebook SRI/TPMI ownership, and a bounded two-UE shared-PRB profile with orthogonal DM-RS identity/ports, per-UE power, covariance-aware detection and resource isolation. | Two-UE shared-PRB waveform decodes both users with controlled interference and correct resource/identity isolation. |
| UL-011 | P0 | Mandatory receiver-derived post-equalization SINR | Export finite measured per-layer and wideband post-equalization SINR from actual H estimates, equalizer coefficients, noise/interference covariance and PUSCH REs. Strict runs fail when this evidence is absent or substituted by configured SNR. | The real catalog scenario fails when measured SINR is removed and passes only with receiver-derived measurements within tolerance. |
| UL-012 | P1 | Independent bit/index/matrix/power/reference vectors | Add pure-spec or frozen independent vectors for scrambling, pi/2-BPSK/QAM, layer mapping, DFT, UL-SCH coding/rate matching, UCI coding/multiplexing, DM-RS/PT-RS, hopping, codebooks, SRS decisions, power control and HARQ. Same-nr-function comparisons remain self-consistency only. | DUT passes independent vectors and catches injected bit, RV, port, and resource errors. |

Codex must reference these IDs in commits, tests, artifact rows where practical, and its final closure report. A feature is not closed by metadata or a test stub; the production path and mandatory runtime tests must pass.

---

## 5. Current production defects that must be removed

The uploaded repository contains the following source-visible behaviors. Line numbers can move; search by behavior and source path. Removing a text signature without removing the behavior is not a fix.

### ULSRC-001 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** TX exposes an ACK-only UCI input rather than typed HARQ-ACK/CSI1/CSI2/SR/CG-UCI payloads.

Current source evidence near line 49:

```matlab
r('NumTxAnt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1)); ip.addParameter('HARQACKBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x)); ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x)); ip.addParameter('CompactOutput',
```

### ULSRC-002 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** UL-SCH multiplexing passes empty CSI Part 1 and CSI Part 2 streams.

Current source evidence near line 183:

```matlab
harqAckBits, double(uciInfo.GACK), pusch.Modulation); [codeword, muxInfo] = nrULSCHMultiplex(pusch, targetCodeRate, trBlkSize, ulSchCodeword(:), codedAck(:), [], []); codeword = int8(codeword(:)); uciInfo.UCIOnPUSCHApplied = true; uciInfo.MultiplexInfo = muxInfo; uciInfo.Source = "nrULSCHMultiplex_ts38212_6_
```

### ULSRC-003 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** TX UCI allocation hard-codes O_CSI1=0 and O_CSI2=0.

Current source evidence near line 623:

```matlab
'HARQ-ACK on PUSCH requires nrULSCHMultiplex from 5G Toolbox.'); end rmInfo = nrULSCHInfo(pusch, targetCodeRate, trBlkSize, oack, 0, 0); gULSCH = double(rmInfo.GULSCH); gACK = double(rmInfo.GACK); if ~(isfinite(gULSCH) && gULSCH > 0 && isfinite(gACK) && gACK > 0) error('sixgr:phy:ul:PUSCHUC
```

### ULSRC-004 — `+sixgr/+phy/+ul/PUSCH_Rx.m`

**Defect:** RX exposes an ACK-only expected-UCI interface.

Current source evidence near line 51:

```matlab
.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x)); ip.addParameter('ExpectedHARQACKBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x)); ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x)); ip.addParameter('HARQSoftBufferLL
```

### ULSRC-005 — `+sixgr/+phy/+ul/PUSCH_Rx.m`

**Defect:** RX demultiplexing hard-codes CSI Part 1 and CSI Part 2 lengths to zero.

Current source evidence near line 2499:

```matlab
iplex_or_nrUCIDecode_unavailable"; return; end try [ulschLLR, ackLLR] = nrULSCHDemultiplex( ... pusch, targetCodeRate, trBlkSize, oack, 0, 0, double(cwLLR(:))); decoded = int8(logical(nrUCIDecode(ackLLR, oack))); info.Applied = true; info.Source = "nrULSCHDemultiplex_ts38212_6_2_7_harq_ac
```

### ULSRC-006 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** Production TX explicitly rejects more than one UL-SCH transport block/codeword.

Current source evidence near line 728:

```matlab
end nCodewords = round(nCodewords); if nCodewords ~= 1 error("sixgr:phy:ul:PUSCHMultiCodewordUnsupported", ... "PUSCH truth TX supports one UL-SCH codeword only. Requested NumCodewords=%d.", nCodewords); end if ~iscell(codewords) codewords = {codewords
```

### ULSRC-007 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** TX declares only a one-codeword rank-1-to-4 scope.

Current source evidence near line 747:

```matlab
nverseEngine = "nrPUSCHDecode_internal_nrLayerDemap"; mapping.SupportedScope = "single_ulsch_codeword_ranks_1_to_4"; mapping.NumCodewords = 1; mapping.NumLayers = double(nLayers); mapping.CodewordIndexByLayer = ones(1, nLayers); mapping.LayerIndexWithinCodeword = double(1:n
```

### ULSRC-008 — `+sixgr/+phy/+ul/PUSCH_Rx.m`

**Defect:** RX declares only a one-codeword rank-1-to-4 scope.

Current source evidence near line 918:

```matlab
nverseEngine = "nrPUSCHDecode_internal_nrLayerDemap"; mapping.SupportedScope = "single_ulsch_codeword_ranks_1_to_4"; mapping.NumCodewords = 1; mapping.ActualNumCodewords = 1; mapping.NumLayers = double(nLayers); mapping.CodewordIndexByLayer = ones(1, nLayers); mapping.Layer
```

### ULSRC-009 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** Missing PUSCH modulation silently defaults to 16QAM.

Current source evidence near line 126:

```matlab
lts. pusch = nrPUSCHConfig; % Basic PHY settings mod = char(string(sixgr.util.structGet(cfg, 'phy.pusch.modulation', '16QAM'))); nl = double(sixgr.util.structGet(cfg, 'phy.pusch.numLayers', 1)); rnti = double(sixgr.util.structGet(cfg, 'phy.pusch.RNTI', 1)); nid = sixgr.util.structGet
```

### ULSRC-010 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** Missing PUSCH time allocation silently becomes a full normal-CP slot.

Current source evidence near line 132:

```matlab
prb = sixgr.util.structGet(cfg, 'phy.pusch.prbSet', []); symAlloc = sixgr.util.structGet(cfg, 'phy.pusch.symbolAllocation', [0 14]); tp = logical(sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', false)); tpmi = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.tp
```

### ULSRC-011 — `+sixgr/+phy/+grant/freezePHYGrant.m`

**Defect:** Frozen UL grant silently defaults to a full normal-CP slot.

Current source evidence near line 389:

```matlab
; if isempty(symbolAllocation) symbolAllocation = sixgr.util.structGet(cfg, root + ".symbolAllocation", [0 14]); end symbolAllocation = double(symbolAllocation(:).'); if numel(symbolAllocation) < 2 || ~all(isfinite(symbolAllocation(1:2))) error("sixgr:phy:grant:BadS
```

### ULSRC-012 — `+sixgr/+phy/+grant/freezePHYGrant.m`

**Defect:** Missing PRB allocation silently becomes the complete BWP/grid.

Current source evidence near line 364:

```matlab
rstFiniteScalar(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", []), 1); prbSet = 0:(max(1, round(nSizeGrid)) - 1); end prbSet = localExpandPRBSet(prbSet); if isempty(prbSet) error("sixgr:phy:grant:EmptyPRBSet", "PHYGrant requires a non-empty PRBSet."); end end functio
```

### ULSRC-013 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** Explicit DM-RS port ownership is overwritten from layer count.

Current source evidence near line 238:

```matlab
h end % DMRS ports to match layers (avoid default mismatch) try pusch.DMRS.DMRSPortSet = 0:(pusch.NumLayers-1); catch end end function pusch = localNormalizePUSCHMapping(pusch, mapType, explicitMapType, fixedReferenceMode) if nargin < 2 || strlength(string(mapType)) =
```

### ULSRC-014 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** DM-RS type-A position is silently clamped.

Current source evidence near line 307:

```matlab
pos', [])); if isfinite(typeAPos) && isprop(dmrs, 'DMRSTypeAPosition') dmrs.DMRSTypeAPosition = max(2, min(3, round(double(typeAPos)))); end configType = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.dmrs.configurationType', []), ... sixgr.
```

### ULSRC-015 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** DM-RS configuration type is silently clamped.

Current source evidence near line 317:

```matlab
[])); if isfinite(configType) && isprop(dmrs, 'DMRSConfigurationType') dmrs.DMRSConfigurationType = max(1, min(2, round(double(configType)))); end addPos = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.dmrs.additionalPositions', []), ... sixgr.
```

### ULSRC-016 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** DM-RS additional position is silently clamped.

Current source evidence near line 327:

```matlab
', [])); if isfinite(addPos) && isprop(dmrs, 'DMRSAdditionalPosition') dmrs.DMRSAdditionalPosition = max(0, min(3, round(double(addPos)))); end dmrsLength = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.dmrs.maxLength', []), ... sixgr.util.struc
```

### ULSRC-017 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** DM-RS length is silently clamped.

Current source evidence near line 337:

```matlab
RSLength', [])); if isfinite(dmrsLength) && isprop(dmrs, 'DMRSLength') dmrs.DMRSLength = max(1, min(2, round(double(dmrsLength)))); end numCDM = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.dmrs.numCDMGroupsWithoutData', []), ... si
```

### ULSRC-018 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** DM-RS CDM-group count is silently clamped.

Current source evidence near line 345:

```matlab
, [])); if isfinite(numCDM) && isprop(dmrs, 'NumCDMGroupsWithoutData') dmrs.NumCDMGroupsWithoutData = max(1, min(3, round(double(numCDM)))); end pusch.DMRS = dmrs; end function pusch = localApplyPUSCHPTRSConfig(pusch, cfg) if ~(isstruct(cfg) && isprop(pusch, 'EnablePTRS')
```

### ULSRC-019 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** An invalid mapping-type-A request may be silently converted to mapping type B.

Current source evidence near line 276:

```matlab
sition)); end catch end typeAPos = max(2, min(3, round(double(typeAPos)))); if startSym > typeAPos && strcmp(mapType, "A") if logical(explicitMapType) || logical(fixedReferenceMode) error("sixgr:phy:grid:allocREsPUSCH:InvalidTypeADMRSSymbol", ... "PUSCH MappingType A starts at symbol %d after configured DMRSTypeAPosition=%d. Configure DMRSTypeAPosition=3 when legal, choose MappingType B, or move PUSCH earlier.", ... 
```

### ULSRC-020 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** PT-RS time density has a hidden fallback of 2.

Current source evidence near line 365:

```matlab
eDensity = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.ptrs.timeDensity', []), ... sixgr.util.structGet(cfg, 'phy.ptrs.timeDensity', []), ... 2); freqDensity = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.ptrs.frequencyDensity', []), ... sixgr.util.structGet(cfg, 'phy.ptrs.fr
```

### ULSRC-021 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** PT-RS frequency density has a hidden fallback of 2.

Current source evidence near line 369:

```matlab
qDensity = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, 'phy.pusch.ptrs.frequencyDensity', []), ... sixgr.util.structGet(cfg, 'phy.ptrs.frequencyDensity', []), ... 2); reOffset = string(sixgr.util.structGet(cfg, 'phy.pusch.ptrs.reOffset', ... sixgr.util.structGet(cfg, 'phy.ptrs.reOffset', '00'))); portSet = sixgr.util.st
```

### ULSRC-022 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** PT-RS RE offset has a hidden fallback of 00.

Current source evidence near line 372:

```matlab
nsity', []), ... 2); reOffset = string(sixgr.util.structGet(cfg, 'phy.pusch.ptrs.reOffset', ... sixgr.util.structGet(cfg, 'phy.ptrs.reOffset', '00'))); portSet = sixgr.util.structGet(cfg, 'phy.pusch.ptrs.portSet', ... sixgr.util.structGet(cfg, 'phy.ptrs.portSet', [])); try if isprop(ptrs, 'TimeDen
```

### ULSRC-023 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** PT-RS port has a hidden fallback of port 0.

Current source evidence near line 388:

```matlab
s.REOffset = char(reOffset); end if isprop(ptrs, 'PTRSPortSet') if isempty(portSet) ptrs.PTRSPortSet = 0; else ptrs.PTRSPortSet = max(0, round(double(portSet(:).'))); end end pusch.PTRS = ptrs; catch ME error("sixgr:phy:grid
```

### ULSRC-024 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** PT-RS time density is rounded/clamped rather than table-validated.

Current source evidence near line 379:

```matlab
'phy.ptrs.portSet', [])); try if isprop(ptrs, 'TimeDensity') ptrs.TimeDensity = max(1, round(double(timeDensity))); end if isprop(ptrs, 'FrequencyDensity') ptrs.FrequencyDensity = max(1, round(double(freqDensity))); end if ispro
```

### ULSRC-025 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** PT-RS frequency density is rounded/clamped rather than table-validated.

Current source evidence near line 382:

```matlab
le(timeDensity))); end if isprop(ptrs, 'FrequencyDensity') ptrs.FrequencyDensity = max(1, round(double(freqDensity))); end if isprop(ptrs, 'REOffset') ptrs.REOffset = char(reOffset); end if isprop(ptrs, 'PTRSPortSet') if is
```

### ULSRC-026 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** pi/2-BPSK mutates transform-precoding state instead of validating procedure ownership.

Current source evidence near line 170:

```matlab
) numAntennaPorts = nl; end if strcmpi(strrep(char(string(mod)), ' ', ''), 'PI/2-BPSK') || strcmpi(strrep(char(string(mod)), ' ', ''), 'PI2-BPSK') % TS 38.211 6.3.1.4 / TS 38.214 6.1.3: pi/2-BPSK PUSCH is DFT-s-OFDM. tp = true; end pusch.Modulation = mod; pusch.NumLayers = nl; pusch.RNTI = rnti; pusch.TransformPrecoding = tp; if isempty(strtrim(transmissionScheme)) && ~tp && isfini
```

### ULSRC-027 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** TX can auto-enable transform precoding after configuration materialization.

Current source evidence near line 1264:

```matlab
tch return; end if ~isempty(raw) value = raw; end end function pusch = localEnsureTransformPrecodingOwnership(pusch, cfg) try modToken = upper(strrep(char(string(pusch.Modulation)), ' ', '')); catch modToken = upper(strrep(char(string(sixgr.util.structGet(cfg, 'phy.pusch.modulation', ''))), ' ', '')); end required = strcmp(modToken, 'PI/2-BPSK') || strcmp(modToken, 'PI2-BPSK') || ... logical(sixgr.util.structGet(cfg,
```

### ULSRC-028 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** TX can resolve TPMI directly from configuration.

Current source evidence near line 464:

```matlab
xgr.util.structGet(phyGrant, "LegacyGrantSnapshot.PMI", []), ... sixgr.util.structGet(cfg, "phy.pusch.TPMI", []), ... sixgr.util.structGet(cfg, "phy.pusch.PMI", []), NaN); end function mappingType = localResolveGrantMappingType(cfg, phyGrant) mappingType = strin
```

### ULSRC-029 — `+sixgr/+link/runULPUSCHThroughput.m`

**Defect:** UL scheduling/throughput path can select a configured TPMI rather than a current SRS decision.

Current source evidence near line 4601:

```matlab
; end configuredPMI = double(sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN)); configuredTPMI = double(sixgr.util.structGet(cfg, "phy.pusch.TPMI", NaN)); if isfinite(configuredTPMI) configuredPMI = configuredTPMI; end if isfinite(configuredPMI) selectedSet = localResolveBeamSetFromPMI(cfg, struct
```

### ULSRC-030 — `+sixgr/+link/runULPUSCHThroughput.m`

**Defect:** PUSCH power control can derive pathloss from configured SNR instead of an RS measurement.

Current source evidence near line 2806:

```matlab
~(isfinite(pathloss_dB) && pathloss_dB >= 0) [pathloss_dB, derivedSource] = localDeriveULPathlossFromConfiguredSNR(cfg); pc.Pathloss_dB = double(pathloss_dB); if ~(isfinite(pathloss_dB) && pathloss_dB >= 0) pc.Status = "pathloss_unavailable_no_power_control_
```

### ULSRC-031 — `+sixgr/+link/runULPUSCHThroughput.m`

**Defect:** Power-control alpha is silently clamped.

Current source evidence near line 2832:

```matlab
sixgr.util.structGet(cfg, "phy.pusch.power_control.alpha", []), ... 0.8); alpha = min(max(double(alpha), 0), 1); pcmax = localFirstFiniteScalar( ... sixgr.util.structGet(cfg, "phy.pusch.powerControl.pcmax_dBm", []), ... sixgr.util.structGet(cfg, "phy.pusch.powerC
```

### ULSRC-032 — `+sixgr/+link/runULPUSCHThroughput.m`

**Defect:** PUSCH power formula omits the 2^mu bandwidth factor.

Current source evidence near line 2852:

```matlab
sixgr.util.structGet(cfg, "powerAndRF.referenceTxPower_dBm", []), ... 0); requestedPower = double(p0) + double(alpha) * double(pathloss_dB) + 10 * log10(double(mRB)) + ... double(deltaTF) + double(closedLoop); txPower = min(double(pcmax), requestedPower); scale = 10 .^ ((double(txPower) - double(refPower)) / 20); if ~(i
```

### ULSRC-033 — `+sixgr/+phy/+ul/PUSCH_Tx.m`

**Defect:** PUSCH element expansion delegates to a PDSCH-named helper instead of an explicit UL precoder application path.

Current source evidence near line 834:

```matlab
nd = portInd; if isempty(portSym) || isempty(portInd) return; end if exist("nrPDSCHPrecode", "file") ~= 2 error("sixgr:phy:ul:PUSCHHybridPrecode:Missing5G", ... "nrPDSCHPrecode is required to expand %s logical ports onto hybrid RF element
```

### ULSRC-034 — `+sixgr/+phy/+ul/puschCodebookCatalog.m`

**Defect:** Current codebook catalog visibly centers on 1/2/4-port cases; release-valid 8-port tables are not complete.

Current source evidence near line 54:

```matlab
validSet = 0:2; else validSet = []; end case 4 switch nLayers case 1 validSet = 0:27; case 2 validSet = 0:21; case 3
```

### ULSRC-035 — `+sixgr/+phy/+grid/allocREsPUSCH.m`

**Defect:** No explicit end-to-end frequency-hop-plan owner is present in the canonical PUSCH allocator.

Current source evidence near line n/a:

```matlab

```

### ULSRC-036 — `+sixgr/+phy/+ul/PUSCH_Rx.m`

**Defect:** Strict UCI receive processing can return an unavailable status instead of failing the transmission.

Current source evidence near line 2494:

```matlab
ist("nrULSCHDemultiplex", "file") ~= 2 || exist("nrUCIDecode", "file") ~= 2 info.Status = "unavailable"; info.Reason = "nrULSCHDemultiplex_or_nrUCIDecode_unavailable"; return; end try [ulschLLR, ackLLR] = nrULSCHDemultiplex( ... pusch, targetCodeRate, trBlkSize, oack, 0, 0, double(cwLLR(:))); decoded = int8(logical(n
```

### ULSRC-037 — `+sixgr/+control/isPDCCHGrantBindingRequired.m`

**Defect:** Decoded-PDCCH binding is policy/configuration dependent rather than inherent to dynamic connected PUSCH ownership.

Current source evidence near line 44:

```matlab
y(cfg, ulPaths) || ... (lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pusch.grantSource", "")))) == "decoded_pdcch"); end end function tf = localAnyTruthy(cfg, paths) tf = false; for ii = 1:numel(paths) value = sixgr.util.structGet(cfg, paths
```

### ULSRC-038 — `+sixgr/+link/resolveWaveformGrant.m`

**Defect:** Waveform grant resolution can freeze scheduler/configuration state before decoded DCI becomes the immutable PUSCH assignment.

Current source evidence near line 55:

```matlab
sixgr.l2.mac.SchedulerPF(cfg, "Direction", char(direction)); grant = scheduler.freezePHYGrantForGrant(grant); grant.DCI = scheduler.buildDCIBitfield(grant); end function value = ternary(cond, a, b) if cond value = a; else value = b; end end function v
```

### Existing foundations to preserve and strengthen

- **ULSRC-039** `+sixgr/+phy/+ul/PUSCH_Tx.m`: TX already uses a centralized resource-accounting helper.
- **ULSRC-040** `+sixgr/+phy/+ul/PUSCH_Rx.m`: RX already computes post-equalization SINR from receiver processing.
- **ULSRC-041** `+sixgr/+phy/+ul/estimateSRSRITPMI.m`: A measured-SRS RI/TPMI estimator exists and should be made authoritative rather than replaced.
- **ULSRC-042** `+sixgr/+phy/+waveform/transformPrecode.m`: A production transform-precoding wrapper exists.
- **ULSRC-043** `+sixgr/+phy/+waveform/transformDeprecode.m`: A production inverse-transform wrapper exists.
- **ULSRC-044** `+sixgr/+phy/+ul/PUSCH_Rx.m`: Receiver has position-aware HARQ soft-combining infrastructure.
- **ULSRC-045** `+sixgr/+phy/+ul/PUSCH_Rx.m`: Receiver has a PT-RS common-phase-error correction path.
- **ULSRC-046** `+sixgr/+phy/+pdcch/buildDCI00UplinkGrant.m`: A bounded DCI 0_0 uplink-grant encoder exists.
- **ULSRC-047** `+sixgr/+phy/+pdcch/buildDCI01UplinkGrant.m`: A bounded DCI 0_1 uplink-grant encoder exists.

Do not delete useful foundations merely to satisfy a static checker. Integrate them into the canonical chain and add stronger tests.

---

## 6. Required target architecture

Do not create another disconnected PUSCH implementation. Consolidate the existing UL production code under a canonical package. Keep `+sixgr/+phy/+ul/PUSCH_Tx.m` and `PUSCH_Rx.m` as compatibility façades that delegate to this implementation.

Recommended structure:

```text
+sixgr/+phy/+ul/+pusch/
    PUSCHSchedulingAssignment.m
    PUSCHAssignmentFactory.m
    PUSCHUEContext.m
    ConfiguredGrantType1State.m
    ConfiguredGrantType2State.m
    RandomAccessULState.m
    PUSCHResourcePlan.m
    PUSCHResourceOwnershipMap.m
    PUSCHConfigMaterializer.m
    PUSCHMCSResolver.m
    PUSCHDMRS.m
    PUSCHPTRS.m
    PUSCHScrambler.m
    PUSCHModulator.m
    PUSCHLayerMapper.m
    ULSCHCodingPlan.m
    ULSCHEncoder.m
    ULSCHDecoder.m
    PUSCHUCIPayload.m
    PUSCHUCIEncoder.m
    PUSCHUCIMultiplexer.m
    PUSCHUCIDemultiplexer.m
    PUSCHUCIDecoder.m
    PUSCHTransformPrecoder.m
    PUSCHFrequencyHopPlan.m
    ULChannelSoundingState.m
    SRSPrecoderDecision.m
    PUSCHPrecoderBundle.m
    PUSCHPowerControlState.m
    PUSCHPowerController.m
    PUSCHGridMapper.m
    PUSCHTransmitter.m
    PUSCHReceiver.m
    PUSCHHARQContext.m
    PUSCHHARQManager.m
    PUSCHArtifactExporter.m
    runPUSCHPhaseValidation.m
    +oracle/
        GoldSequenceSpec.m
        PUSCHQAMMapperSpec.m
        PUSCHLayerMapperSpec.m
        CRCSpec.m
        TBSAndBaseGraphSpec.m
        LDPCSegmentationSpec.m
        LDPCRateMatchingIndexSpec.m
        UCIEncoderSpec.m
        UCIMultiplexPositionSpec.m
        DMRSTableSpec.m
        DMRSSequenceSpec.m
        PTRSIndexSpec.m
        TransformDFTSpec.m
        FrequencyHopSpec.m
        UplinkCodebookSpec.m
        PrecodingMultiplySpec.m
        PowerControlSpec.m
        HARQPositionSpec.m
```

Exact filenames may follow repository conventions, but these separations are mandatory:

- decoded scheduling state is not configuration state;
- dynamic DCI, Type-1 CG, Type-2 CG, Msg3, MsgA, and calibration have separate factories;
- resource ownership is resolved before coding or waveform generation;
- UL-SCH coding state is separate for transport block/codeword 0 and 1;
- UCI payloads are typed and not represented by a single `HARQACKBits` array;
- Scheduling Request never enters the PUSCH UCI encoder;
- logical DM-RS ports are distinct from physical antenna ports;
- transform precoding is procedure-owned, not inferred from modulation;
- hopping is an immutable plan consumed by data, DM-RS, PT-RS, TX, and RX;
- SRS decisions are immutable measured state with age and epoch;
- a resolved precoding matrix is explicit and applied exactly once;
- power control computes dBm and applies a verified amplitude scale to the actual waveform;
- transmitter and receiver consume the same immutable assignment/resource plan;
- HARQ buffers are keyed by UE/cell/BWP/process/codeword/configuration epoch;
- independent oracle code calls neither production code nor `nr*` functions.

Use zero-based NR indices in PHY-facing objects and CSVs. Convert to one-based MATLAB indices only at array-access or Toolbox boundaries. Never mix index bases silently.

---

## 7. Canonical `PUSCHSchedulingAssignment`

Implement an immutable value object containing at least:

```text
AssignmentId
Profile
Source
UEId
RNTI
RNTIType
ServingCellId
SchedulingCellId
CCId
BWPId
ConfigurationEpoch
PDCCHAbsoluteSlot
PUSCHAbsoluteSlot
DecodedDCIId
DCIFormat
DCICRCPass
DecodedRNTI
DCIRNTIMatch
SearchSpaceId
CORESETId
K2
TDRAListId
TDRARowIndex
SLIV
SymbolAllocation
MappingType
ResourceAllocationType
FrequencyDomainAssignmentRaw
RBGSize
VRBToPRBMapping
PRBSetBWPRelative
PRBSetCarrierRelative
FrequencyHoppingMode
SecondHopStartPRB
RepetitionType
RepetitionIndex
MCSTablePerCodeword
InitialMCSIndexPerCodeword
MCSIndexPerCodeword
ModulationPerCodeword
QmPerCodeword
TargetCodeRatePerCodeword
NumLayers
NumCodewords
LayerCountPerCodeword
TransmissionScheme
TransformPrecoding
AntennaPortField
DMRSConfigId
DMRSPortSet
PTRSConfigId
PTRSPortSet
SRSResourceSetId
SRSResourceIndicator
TPMI
SRSDecisionId
SRSDecisionConfigurationEpoch
SRSMeasurementSlot
NDIPerCodeword
RVPerCodeword
HARQProcessId
ConfiguredGrantId
ConfiguredGrantType
ConfiguredGrantActivationDCIId
ConfiguredGrantOccasionIndex
RARGrantId
RAPID
MsgAResourceId
PowerControlStateId
PowerControlLoopId
PathlossReferenceRS
UCIProfileId
UCIOnPUSCHEnabled
CreatedAtAbsoluteSlot
```

### Construction functions

```matlab
assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory.fromDecodedDCI( ...
    decodedDCI, ueContext, frameState, harqState, soundingState, powerState)

assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory.fromConfiguredGrantType1( ...
    cgState, ueContext, frameState, harqState, soundingState, powerState)

assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory.fromConfiguredGrantType2( ...
    cgState, activationDCI, ueContext, frameState, harqState, soundingState, powerState)

assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory.fromRARMsg3( ...
    rarGrant, randomAccessState, ueContext, frameState, powerState)

assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory.fromMsgA( ...
    msgAConfig, randomAccessState, ueContext, frameState, powerState)

assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory.forCalibration( ...
    explicitCalibrationRequest, frameState)
```

No factory may silently call another profile as fallback.

### Required typed errors

Use stable identifiers. At minimum:

```text
sixgr:pusch:MissingDecodedDCI
sixgr:pusch:DCICRCFailed
sixgr:pusch:DCIRNTIMismatch
sixgr:pusch:InvalidDCIRNTIProcedure
sixgr:pusch:UnsupportedDCIFormat
sixgr:pusch:StaleBWPContext
sixgr:pusch:InactiveULBWP
sixgr:pusch:K2TargetSlotUnavailable
sixgr:pusch:ULSymbolsUnavailable
sixgr:pusch:MissingFrequencyAllocation
sixgr:pusch:MissingTimeAllocation
sixgr:pusch:InvalidMCSContext
sixgr:pusch:ConfiguredGrantNotInstalled
sixgr:pusch:ConfiguredGrantNotActivated
sixgr:pusch:ConfiguredGrantWrongOccasion
sixgr:pusch:ConfiguredGrantReleased
sixgr:pusch:ConfiguredGrantCollision
sixgr:pusch:RARGrantInvalid
sixgr:pusch:RAPIDMismatch
sixgr:pusch:MsgAResourceInvalid
sixgr:pusch:MissingUCIPayload
sixgr:pusch:InvalidUCIBitBudget
sixgr:pusch:SchedulingRequestNotCarriedOnPUSCH
sixgr:pusch:InvalidDMRSPortSet
sixgr:pusch:InvalidDMRSConfiguration
sixgr:pusch:InvalidPTRSAssociation
sixgr:pusch:InvalidPTRSConfiguration
sixgr:pusch:InvalidFrequencyHopping
sixgr:pusch:FrequencyHoppingResourceTypeConflict
sixgr:pusch:StaleSRSMeasurement
sixgr:pusch:SRSConfigurationEpochMismatch
sixgr:pusch:MissingSRSDecision
sixgr:pusch:PrecoderDecisionMismatch
sixgr:pusch:PowerControlStateMissing
sixgr:pusch:PathlossMeasurementMissing
sixgr:pusch:UnsupportedModulation
sixgr:pusch:TransformPrecodingRequired
sixgr:pusch:TransformPrecodingMismatch
sixgr:pusch:UnsupportedTransformPrecodingLayerCount
sixgr:pusch:UnsupportedLayerCodewordTuple
sixgr:pusch:HARQContextMismatch
sixgr:pusch:UCIProcessingUnavailable
```

Every rejected assignment must create no resource plan, no encoded bits, no grid, and no waveform.

---

# Work item 1 — Dynamic, configured-grant, random-access, and calibration ownership

## Implement

1. Make `PUSCH_Tx` and the production scheduler consume `PUSCHSchedulingAssignment` rather than a generic configuration/frozen-grant struct.
2. Make decoded-control binding intrinsic for `connected_dynamic_strict`; remove policy-optional binding.
3. Materialize DCI 0_0, 0_1, 0_2, and 0_3 through a version-pinned field resolver. Do not read missing fields from `phy.pusch.*`.
4. Implement Type-1 configured-grant installation and exact periodic occasion resolution.
5. Implement Type-2 installation, CS-RNTI activation, exact occasions, deactivation/release, and stale-epoch rejection.
6. Implement Msg3 from the actual RAR UL grant and current random-access state.
7. Implement MsgA from the active MsgA PUSCH resource configuration and random-access identity.
8. Keep `forCalibration` isolated and explicit.
9. Change `resolveWaveformGrant` so an immutable assignment produces the waveform request. Never freeze scheduler intent first and attach DCI afterward.
10. Preserve assignment ID, decoded DCI ID, CG activation DCI ID, RAR grant ID, and configuration epoch through TX and RX.

## Required tests

Create at least:

```text
tests/testPUSCHSchedulingAssignmentVectors.m
tests/testPUSCHDynamicDCIOwnership.m
tests/testPUSCHConfiguredGrantType1State.m
tests/testPUSCHConfiguredGrantType2State.m
tests/testPUSCHRARMsg3Assignment.m
tests/testPUSCHMsgAAssignment.m
tests/testPUSCHCalibrationIsolation.m
```

Load all 26 supplied assignment rows. For each row:

- construct the specified decoded event/state;
- invoke the production factory;
- compare all resolved fields to `expected_pusch_assignment_resolution.csv`;
- snapshot every input and prove zero mutation;
- prove an error creates no resource plan, codeword, grid, or waveform;
- alter one decoded DCI field and prove the actual PUSCH resource/MCS/HARQ field changes;
- remove or CRC-fail the DCI and prove connected transmission is impossible;
- prove Type-1 does not require a fake activation DCI;
- prove Type-2 does require a valid activation DCI;
- prove release and wrong occasion prevent waveform generation;
- prove random-access grants do not inherit C-RNTI-only state.

---

# Work item 2 — Exact DCI/RRC/BWP materialization and resource ownership

## Frequency-domain allocation

Implement every selected-profile frequency-allocation procedure from decoded fields and active UL-BWP context:

- type-0 RBG bitmap where applicable;
- type-1 RIV allocation;
- selected type-2/interlace procedures only when explicitly included in the pinned profile;
- BWP-relative allocation followed by carrier-relative materialization;
- contiguous-allocation constraints for transform precoding;
- exact compatibility checks for frequency hopping;
- cross-carrier scheduling through explicit scheduling/scheduled-cell identities.

Never substitute all PRBs for a missing allocation. Never sort, clip, wrap, or deduplicate an invalid decoded allocation into a valid allocation.

## Time-domain allocation

Resolve:

- the correct PUSCH time-domain allocation list;
- selected row and K2;
- SLIV or explicit start/length;
- mapping type A/B;
- normal/extended-CP symbol count;
- TDD UL/flexible-symbol availability through the canonical frame engine;
- repetition Type A/B time-domain segmentation where selected;
- processing-time legality.

Never default to `[0 14]`. Never change mapping type A to B to make indices work.

## One immutable resource map

Before coding, build one `PUSCHResourceOwnershipMap` that resolves:

```text
PUSCH allocation
DM-RS REs per logical port and hop
PT-RS REs per port and hop
UL-SCH/UCI-capable data REs
reserved/collision REs from SRS, PUCCH, PRACH, guard symbols, and other configured UL resources
per-codeword/per-layer mapping ownership
```

The map must produce exact zero-based indices. Resource collisions must fail or be resolved by the exact selected procedure before encoding. Do not generate PUSCH and remove collisions afterward.

Derive `N_RE`, `G`, UCI-capable REs, per-codeword coded lengths, and transform-precoding DFT sizes only from this final map.

## Tests

Add:

```text
testPUSCHFDRAResolution.m
testPUSCHTDRAK2Resolution.m
testPUSCHTDDULAvailability.m
testPUSCHResourceOwnership.m
testPUSCHResourceCollisionNegatives.m
testPUSCHNoFullBandFallback.m
testPUSCHNoFullSlotFallback.m
```

Test missing, reserved, out-of-range, non-contiguous, wrong-BWP, wrong-epoch, TDD-unavailable, hopping-incompatible, and transform-incompatible allocations. No invalid input may produce a partial waveform.

---

# Work item 3 — Complete UL-SCH coding and rank/codeword/modulation chain

## Modulation

Implement exact mapping/demapping for:

```text
pi/2-BPSK — only with a valid transform-precoded assignment
QPSK
16QAM
64QAM
256QAM
```

Rules:

- no default modulation;
- no modulation-list repetition or truncation;
- modulation, `Qm`, MCS table, target code rate, and TB size are per codeword;
- reject 1024QAM, 4096QAM, unknown strings, nonbinary input, and bit counts not divisible by `Qm`;
- use the exact TS 38.211 bit ordering and unit-average-power normalization;
- implement inverse soft demapping with one documented LLR-sign and noise-variance convention.

## Layer mapping

Implement one- and two-codeword mapping for every declared release-valid rank. Use a table-driven tuple resolver keyed by:

```text
release profile
transmission scheme
number of antenna ports
transform-precoding state
rank
number of codewords
codebook identifier
UE capability
```

Do not assume rank 1–4/single codeword. Do not advertise rank 5–8 unless the exact eight-port/codebook/capability tuple is implemented and tested. Keep codeword 0 and codeword 1 lengths, MCS, RV, NDI, and HARQ buffers separate.

## UL-SCH coding

For each transport block/codeword implement and expose:

1. exact TBS determination from the final data/UCI resource budget;
2. TB CRC selection and attachment;
3. code-block segmentation and filler positions;
4. CB CRC attachment where required;
5. LDPC base-graph selection;
6. lifting-size selection;
7. LDPC encoding;
8. RV-specific circular-buffer rate matching to exact `G_ULSCH`;
9. concatenation;
10. inverse rate recovery;
11. position-aware HARQ combining;
12. LDPC decoding and CRC processing.

Do not reconstruct `G` from an estimated `NRE`. Do not floor a negative bit budget. Fail with `InvalidUCIBitBudget` or a precise coding error before coding.

## Tests

Add:

```text
testPUSCHModulationIndependent.m
testPUSCHLayerMappingIndependent.m
testULSCHTBSBaseGraphIndependent.m
testULSCHTBCRCIndependent.m
testULSCHSegmentationIndependent.m
testULSCHLDPCRateMatchingIndependent.m
testULSCHTwoTransportBlocks.m
testPUSCHRank1To8NoNoise.m
```

Use all supplied modulation, layer, TBS, and CRC vectors. Add full-constellation vectors, exact small-TB boundary cases, base-graph boundaries, lifting-size boundaries, filler-bit cases, all RV values, limited-buffer cases, and injected one-bit/index errors.

---

# Work item 4 — Exact TS 38.212 UCI-on-PUSCH chain

Replace ACK-only interfaces in both TX and RX.

## Typed payload

Implement `PUSCHUCIPayload` with explicit fields and provenance:

```text
PayloadId
HARQACKBitsByPriority
CSIReportId
CSIPart1Bits
CSIPart2Bits
CGUCIBitsByPriority
UTOUCIBits where selected by the pinned profile
O_ACK
O_CSI1
O_CSI2
O_CG_UCI
BetaOffsetACK
BetaOffsetCSI1
BetaOffsetCSI2
ScalingAlpha
Codebook/priority metadata
ConfigurationEpoch
```

Do not include a generic SR field. A scheduling request presented to this factory must raise `sixgr:pusch:SchedulingRequestNotCarriedOnPUSCH` and be routed to the PUCCH procedure by the caller.

## UCI coding

Implement exact payload-dependent coding:

- one-/two-bit HARQ-ACK behavior;
- small-block UCI coding where applicable;
- polar coding, segmentation, CRC, interleaving, and rate matching where applicable;
- CSI Part 2 size determined from the decoded/configured CSI Part 1/report context, not an arbitrary configured number;
- CG-UCI and UTO-UCI substitutions only under their exact configured procedures;
- priority-index handling selected by the pinned profile.

Use MATLAB Toolbox functions where useful, but add independent bit-level vectors for each declared branch. A call to the same `nrUCIEncode` on both sides is self-consistency only.

## UCI bit budgeting and multiplexing

Compute exact:

```text
G_ACK
G_CSI1
G_CSI2
G_CG_UCI
G_ULSCH
Q'_ACK
Q'_CSI1
Q'_CSI2
placeholder x/y locations
per-symbol/per-hop multiplex positions
```

using the final PUSCH resource map, modulation order, layers, beta offsets, scaling alpha, DM-RS symbols, hopping plan, and UCI-only/UL-SCH-present state.

With two UL-SCH transport blocks:

- select the UCI owner using the highest initial `I_MCS`;
- use codeword 0 when the initial indices tie;
- place no UCI on the other transport block;
- preserve the owner through retransmissions even when later MCS differs, according to the pinned procedure state.

Support at least:

- UL-SCH only;
- HARQ-ACK only with UL-SCH;
- CSI Part 1 with UL-SCH;
- CSI Part 1 and Part 2 with UL-SCH;
- HARQ-ACK plus CSI Part 1/2 with UL-SCH;
- configured-grant UCI combinations selected by the profile;
- UCI-only PUSCH combinations permitted by the pinned release;
- one- and two-UL-SCH-TB ownership.

The RX must exactly reverse scrambling, demultiplexing, rate recovery, and UCI decoding and report per-payload CRC/match status.

If required Toolbox primitives are unavailable, strict processing must fail with `sixgr:pusch:UCIProcessingUnavailable`; do not return `Status="unavailable"` and continue the transmission.

## Tests

Add:

```text
testPUSCHUCIPayloadValidation.m
testPUSCHUCIEncodingIndependent.m
testPUSCHUCIMultiplexPositionsIndependent.m
testPUSCHUCITwoTBSourceSelection.m
testPUSCHUCIOnly.m
testPUSCHCSI1CSI2RoundTrip.m
testPUSCHCGUCIRoundTrip.m
testPUSCHUCIPlaceholderScrambling.m
testPUSCHRejectsSchedulingRequest.m
```

Load all 34 supplied rows. Positive rows must recover exact payloads. Negative rows must raise the specified error, mutate no input, and generate no waveform. Add injected errors in payload length, beta offset, CSI Part 2 dependency, owner codeword, placeholder position, and demultiplex length.

---

# Work item 5 — Complete PUSCH DM-RS

Implement a table-driven `PUSCHDMRS` resolver. Inputs must include:

```text
mapping type A/B
DM-RS configuration type 1/2
max length and actual length 1/2
additional position
DMRS type-A position
PUSCH start and length
transform-precoding state
transmission scheme
number of layers and codewords
number of antenna ports
antenna-port indication field
logical DM-RS port set
number of CDM groups without data
N_ID^0/N_ID^1 or configured identity
n_SCID
sequence/group hopping state
frequency-hop index
slot/symbol state
```

Requirements:

1. Resolve the logical port set from decoded antenna-port information plus active `DMRS-UplinkConfig`.
2. Preserve valid non-default/non-consecutive port sets exactly.
3. Never overwrite ports as `0:(NumLayers-1)`.
4. Never clamp type-A position, configuration type, additional position, length, or CDM groups.
5. Never change mapping type A to B.
6. Implement basic/enhanced and selected multi-panel tables when declared by the profile.
7. Generate exact sequences and indices per port, symbol, and frequency hop.
8. Apply correct OCC/CDM and port orthogonality.
9. Feed the same resolved ports/indices into channel estimation and effective-channel construction.
10. Reject invalid port/layer/codebook/transform/hopping combinations before waveform generation.

## Tests

Add:

```text
testPUSCHDMRSVectorMatrix.m
testPUSCHDMRSPortTableIndependent.m
testPUSCHDMRSSymbolPositionsIndependent.m
testPUSCHDMRSSequenceIndependent.m
testPUSCHDMRSHopping.m
testPUSCHDMRSInputImmutability.m
testPUSCHDMRSNegativeTuples.m
```

Run all 84 supplied rows. Replace every `RESOLVE_BY_PINNED_TABLE` floor with a real expected table result generated independently or from a frozen external vector. For every valid row require exact symbols, ports, CDM groups, deltas/OCC weights, sequence digest, and zero-based indices. Every invalid row must raise a typed error and produce no waveform.

---

# Work item 6 — Complete PUSCH PT-RS and phase tracking

Implement separate exact paths for:

- CP-OFDM PUSCH PT-RS;
- transform-precoded/DFT-s-OFDM PUSCH PT-RS.

Resolve from active RRC/DCI/procedure state rather than defaults:

```text
enablement threshold
MCS/table conditions
time density
frequency density or transform-precoded sample density
RE offset
number of PT-RS ports
PT-RS-to-DM-RS port association
hop-specific allocation
sequence initialization
```

Requirements:

- no hidden default density 2;
- no hidden RE offset `00`;
- no hidden port 0;
- no rounding/clamping of an invalid value;
- exact per-hop indices and sequences;
- exact PT-RS insertion location relative to transform precoding for DFT-s-OFDM;
- reject association with an absent/incompatible DM-RS port;
- estimate CPE from received PT-RS without TX truth;
- correct the corresponding data symbols before demodulation;
- expose CPE and EVM before/after correction.

## Tests

Add:

```text
testPUSCHPTRSVectorMatrix.m
testPUSCHPTRSIndicesIndependent.m
testPUSCHPTRSSequenceIndependent.m
testPUSCHPTRSPortAssociation.m
testPUSCHPTRSHopping.m
testPUSCHPTRSPhaseNoiseBenefit.m
testPUSCHPTRSNoTruthLeakage.m
```

Run all 60 supplied rows, then add exact table boundaries and multiple calibrated phase-noise severities. A valid PT-RS case must have zero index mismatch. A wrong port, density, offset, or hop must fail. Under nonzero phase noise, the selected operating points must show reduced residual CPE/EVM and a statistically supported BLER improvement or non-degradation.

---

# Work item 7 — Normative transform precoding / DFT-s-OFDM

Transform precoding is owned by DCI/RRC/CG/random-access procedure state. Remove every path that sets it merely because modulation is pi/2-BPSK.

For the selected strict profile:

- transform-precoded PUSCH has exactly one transmitted layer;
- pi/2-BPSK requires transform precoding;
- transform precoding requires a compatible contiguous allocation and valid hopping/procedure state;
- rank greater than one with transform precoding raises `UnsupportedTransformPrecodingLayerCount` and creates no waveform.

## TX

For each OFDM symbol and frequency hop:

1. form the exact input block after UCI multiplexing, scrambling, and modulation;
2. insert transform-precoded PT-RS according to the selected procedure;
3. apply the exact `M_SC^PUSCH`-point normalized transform;
4. map transformed samples to the exact allocated subcarriers;
5. apply only the release-valid one-layer precoding/port mapping;
6. record input/output dimensions, energy, and digest.

## RX

1. perform hop-aware extraction/channel estimation/equalization;
2. apply the exact inverse transform on each eligible symbol/hop;
3. remove/consume PT-RS according to the inverse procedure;
4. demodulate and continue UCI/UL-SCH decoding.

Do not call a transform wrapper on an array whose dimensions happen to be divisible. Validate exact symbol/hop segmentation and allocation continuity first.

## Tests

Use all 14 supplied vectors and add:

```text
testPUSCHTransformPrecodeIndependentDFT.m
testPUSCHTransformDeprecodeRoundTrip.m
testPUSCHTransformEnergy.m
testPUSCHTransformRankConstraint.m
testPUSCHTransformWithDMRSPTRS.m
testPUSCHTransformWithHopping.m
testPUSCHTransformPAPR.m
```

Require round-trip NMSE <= `1e-12`, relative energy error <= `1e-12`, exact output lengths, and no waveform for every invalid multi-layer/non-contiguous/procedure-mismatch case. Produce PAPR CCDFs from enough deterministic blocks to be meaningful; do not infer PAPR benefit from one symbol.

---

# Work item 8 — Exact frequency hopping and repetition

Create immutable `PUSCHFrequencyHopPlan` objects. Resolve from decoded DCI/RAR/CG and active BWP state:

```text
mode: none / intra-slot / inter-slot
first-hop PRBs
second-hop PRBs
hop symbol boundary
absolute slots
repetition type and index
DM-RS symbols per hop
PT-RS indices per hop
data/UCI positions per hop
```

Requirements:

- exact second-hop derivation and BWP bounds;
- no half-slot heuristic unless it is exactly the selected table result;
- no hopping with incompatible resource-allocation or transform-precoding state;
- DM-RS/PT-RS/data/UCI all consume the same hop plan;
- receiver performs independent or procedure-correct channel estimation/equalization per hop;
- inter-slot/repetition state preserves TB/HARQ identity and correct RV/occasion behavior;
- selected repetition Type-B segmentation uses the canonical symbol/timing engine.

## Tests

Run all 27 supplied hopping rows and add exact independent maps for:

- short and long allocations;
- odd/even symbol lengths;
- both mapping types;
- transform disabled/enabled compatible cases;
- PT-RS present/absent;
- BWP-edge conditions;
- intra-slot frequency-selective channels;
- inter-slot channel variation;
- repetition Type-B segmentation;
- incompatible resource type and out-of-BWP second hop.

Require zero PRB/symbol/index mismatches and exact no-noise decode for valid cases.

---

# Work item 9 — SRS-derived channel, rank, SRI, TPMI, and precoder authority

Preserve and strengthen `estimateSRSRITPMI.m`. Create immutable `ULChannelSoundingState` containing:

```text
DecisionId
UEId
ServingCellId
CCId
BWPId
ConfigurationEpoch
SRSResourceSetId
SRSResourceId
SRSUsage
MeasurementAbsoluteSlot
MaximumAgeSlots
H estimate by subcarrier/port
noise variance
interference covariance
measurement uncertainty/quality
selected RI
selected SRI
selected TPMI or non-codebook resource set
resolved precoder tensor/digest
beam/spatial relation state where applicable
```

## Authority rules

- `connected_dynamic_strict` may use only a valid measured decision whose UE/cell/BWP/resource/epoch matches.
- A configured TPMI/PMI is not a fallback.
- A stale or mismatched SRS decision fails the assignment or invokes an explicitly specified scheduler no-transmission policy; it must not silently reuse the last/configured value.
- For codebook transmission, resolve rank/TPMI through the pinned codebook tables and measured metric.
- For non-codebook transmission, resolve SRI/layer/resource ownership through the selected SRS resources and measured state.
- Record decision ID and applied matrix digest at scheduler, assignment, TX, and RX.
- Apply the matrix exactly once. Replace the PDSCH-named helper with an explicit UL precoder application path.

## High-rank and bounded MU-PUSCH

Implement every declared release-valid rank/codeword/8-port tuple. Unsupported tuples must be rejected during planning.

Add one bounded two-UE shared-PRB profile with:

- independent UE/RNTI/HARQ/power identities;
- compatible orthogonal DM-RS ports/scrambling identities;
- explicit per-UE precoders and power;
- an actual composite waveform/channel;
- covariance-aware linear detection or a documented SIC order;
- no transmitted-bit or ideal-channel leakage;
- per-UE measured SINR/BLER and resource isolation.

## Tests

Run all 20 SRS-decision rows and all 39 precoding-application rows. Add:

```text
testPUSCHSRSDecisionAge.m
testPUSCHSRSConfigurationEpoch.m
testPUSCHSRSCodebookSelection.m
testPUSCHSRSNonCodebookSelection.m
testPUSCHNoConfiguredTPMIFallback.m
testPUSCHPrecoderApplicationIndependent.m
testPUSCHPrecoderDigestPropagation.m
testPUSCHHighRankCodebooks.m
testPUSCHTwoUserSharedPRB.m
```

For each valid case, applied decision ID and matrix digest must exactly match the measured SRS decision. For invalid/stale cases, no waveform is allowed.

---

# Work item 10 — Closed-loop PUSCH power control and actual waveform scaling

Create `PUSCHPowerControlState` keyed by:

```text
UE ID
serving cell / CC / UL BWP
configuration epoch
PUSCH power-control loop index
closed-loop adjustment-state index
pathloss-reference-RS identity
```

Implement the selected TS 38.213 branches rather than one universal approximation. At minimum resolve:

```text
P0 nominal and UE-specific terms for the active grant/procedure
alpha
measured pathloss from the configured reference RS
10*log10(2^mu * M_RB)
Delta_TF where applicable
closed-loop f(i,l)
TPC command mapping
accumulated and absolute adjustment modes
one or two PUSCH power-control adjustment states when configured
P_CMAX and selected MPR/A-MPR constraints
power headroom
```

The core requested-power calculation for the applicable branch must retain the `2^mu * M_RB` bandwidth factor. Do not derive pathloss from configured SNR. Do not clamp alpha or any enum into range; validate against the exact allowed set.

## Actual waveform scaling

1. Define one reference point for unscaled PUSCH waveform power.
2. Account for layer-to-port precoder normalization and OFDM scaling.
3. Convert requested dBm to a linear amplitude scale exactly once.
4. Apply it to the actual transmit waveform/port samples.
5. Measure resulting average power at the same reference point.
6. Export requested, limited, applied, measured power and error.
7. Derive PHR from the same power state.
8. Preserve per-UE power in MU-PUSCH.

A computed dBm value that is not applied to the waveform is not an implementation.

## Tests

Run all 33 supplied power rows and add:

```text
testPUSCHPowerControlIndependent.m
testPUSCHPowerControlTPCAccumulation.m
testPUSCHPowerControlAbsoluteMode.m
testPUSCHPowerControlTwoStates.m
testPUSCHPowerControlPathlossReference.m
testPUSCHPowerControlMuFactor.m
testPUSCHPowerControlPCMAXClipping.m
testPUSCHWaveformPowerApplication.m
testPUSCHPowerHeadroom.m
testPUSCHPowerControlClosedLoopConvergence.m
```

Require deterministic analytical agreement and waveform measured-power error <= `0.05 dB` for controlled no-channel tests. Missing/non-measured pathloss, stale power state, invalid alpha, and unknown TPC command must fail closed.

---

# Work item 11 — Complete receiver, measured SINR, and HARQ

Implement one production receiver that consumes the immutable assignment/resource plan, received waveform/grid, and receiver configuration.

## Required RX stages

1. timing/CFO-corrected grid input from the receiver front end;
2. exact per-hop/per-port DM-RS extraction;
3. channel and noise/interference covariance estimation;
4. PT-RS CPE estimation and correction;
5. exact data/UCI RE extraction from the ownership map;
6. effective-channel construction including the applied UL precoder;
7. covariance-aware equalization or selected multiuser detection;
8. inverse transform precoding for transform-enabled rank-1 PUSCH;
9. codeword layer demapping;
10. soft demodulation with documented LLR convention;
11. PUSCH descrambling with exact RNTI/codeword/identity and x/y behavior;
12. exact UCI/UL-SCH demultiplexing;
13. UCI decoding and payload validation;
14. UL-SCH rate recovery and HARQ combining;
15. LDPC decoding and CRC processing;
16. per-layer/per-codeword/per-hop measurements.

The receiver must not use transmitted bits, configured CRC outcomes, configured SNR, configured pathloss, ideal channel estimates, transmitted UCI payloads, or TX coding buffers unless an explicitly separate ideal-oracle unit test is selected. Campaigns must use the real receiver.

## Measured post-equalization SINR

Export finite receiver-derived SINR from actual:

- estimated effective channel;
- equalizer weights;
- measured/supplied receiver noise variance;
- interference covariance when applicable;
- actual scheduled data REs.

Provide per-RE/per-layer values and a documented wideband aggregation. `MeasuredSINRSource` must identify the receiver calculation. Configured SNR is not an acceptable substitute. Strict campaign rows without receiver-derived SINR fail.

## HARQ context

Create `PUSCHHARQContext` keyed by:

```text
UE/cell/CC/BWP/configuration epoch
HARQ process ID
codeword index
```

Store NDI, TB identity, TBS, coding-plan digest, base graph, lifting size, code-block/filler layout, Ncb/Nref, received RV positions, valid-position mask, soft circular-buffer LLRs, transmission count, and decode outcome.

Rules:

- NDI toggle/new TB resets only the corresponding codeword;
- retransmission combines only with matching TB identity/TBS/layout/epoch;
- rate recover to exact circular-buffer positions before addition;
- never concatenate raw rate-matched LLR vectors;
- keep codeword buffers separate;
- preserve configured-grant repetition semantics;
- flush/reset deterministically on ACK/release/stale context;
- reject invalid RV and mismatched context.

## Tests

Run all 21 HARQ rows and add:

```text
testPUSCHReceiverNoNoiseExact.m
testPUSCHReceiverAWGN.m
testPUSCHReceiverTDL.m
testPUSCHReceiverCDL.m
testPUSCHReceiverHopping.m
testPUSCHReceiverWrongRNTI.m
testPUSCHReceiverWrongDMRSPort.m
testPUSCHReceiverWrongSRSPrecoder.m
testPUSCHReceiverNoSignal.m
testPUSCHMeasuredSINRMandatory.m
testPUSCHHARQTransitionVectors.m
testPUSCHHARQPositionAwareCombining.m
testPUSCHHARQTwoCodewords.m
testPUSCHHARQNDIReset.m
testPUSCHHARQConfiguredGrantRepetition.m
```

No-signal/wrong-state tests must produce controlled detection/CRC failure, never a fabricated passing TB.

---

# Work item 12 — Executable coverage matrix, independent evidence, campaigns, CSVs, and PNGs

## Mandatory matrix

Run every row of `pusch_declared_coverage_matrix.csv` through the actual production TX/RX chain. Do not mock coding, UCI, DM-RS/PT-RS, transform, power, channel, or receiver stages.

The production capability resolver must classify each tuple before waveform generation as:

```text
SUPPORTED_AND_RUN
UNSUPPORTED_WITH_TYPED_ERROR
```

It must never classify an unsupported tuple as a skipped pass.

Add deterministic generated pairwise/boundary coverage across at least:

- dynamic DCI, Type-1 CG, Type-2 CG, Msg3, MsgA, and calibration;
- one/two UL-SCH transport blocks;
- rank 1–8 only for release-valid non-transform tuples;
- transform-precoded rank 1 and negative rank >1 cases;
- pi/2-BPSK/QPSK/16QAM/64QAM/256QAM;
- mapping A/B;
- DM-RS types 1/2, lengths 1/2, additional positions, port tables, and hopping;
- PT-RS CP-OFDM/DFT-s-OFDM present/absent;
- UCI profiles including ACK, CSI1, CSI1+CSI2, CG-UCI, UCI-only, and two-TB owner selection;
- RV 0/1/2/3 and NDI transitions;
- codebook/non-codebook and selected eight-port tuples;
- none/intra-slot/inter-slot hopping and selected repetition;
- SRS fresh/stale/epoch-mismatched decisions;
- accumulated/absolute power control and PCMAX clipping;
- AWGN, one TDL profile, and one CDL profile;
- bounded two-UE MU-PUSCH;
- at least 15, 30, 60, and 120 kHz numerologies supported by the frame phase.

Write the generated matrix to the phase output directory.

## No-noise exact tests

For every supported rank/modulation/codeword combination:

- deterministic TB and UCI bits;
- full TX grid/waveform and RX chain;
- identity or exactly known channel;
- exact TB and UCI payload recovery;
- zero resource/index mismatches;
- zero input mutation;
- finite measured receiver metrics;
- requested/applied waveform power agreement.

## BLER and impairment campaigns

Run bounded campaigns including:

1. rank-1 QPSK low-rate AWGN;
2. rank-1 64QAM medium-rate AWGN;
3. rank-2 16QAM TDL-A, transform disabled;
4. rank-4 64QAM CDL-C, transform disabled;
5. one release-valid high-rank/eight-port case;
6. one transform-precoded pi/2-BPSK/QPSK case;
7. one intra-slot hopping frequency-selective case;
8. one complete CSI Part 1/Part 2 UCI case;
9. one HARQ RV sequence;
10. one PT-RS phase-noise case;
11. one power-control convergence case;
12. one bounded two-UE MU-PUSCH case.

Use deterministic seeds `[11 23 47 89]` at minimum, configurable confidence level, minimum trials, minimum errors, and one canonical stop-reason enumeration. Do not accept incomplete points as complete. Export receiver-derived SINR for every operating point.

## Independent evidence

For each mandatory family use a pure-spec implementation, frozen external vector, or analytical invariant independent of the DUT:

```text
scrambling and x/y placeholders
pi/2-BPSK/QAM mapping
layer mapping
TBS/base graph/CRC
segmentation/lifting/rate matching
UCI coding and multiplex positions
DM-RS tables/sequences/indices
PT-RS tables/sequences/indices
unitary transform/inverse transform
frequency-hop plans
UL codebooks and matrix multiplication
SRS decision fixtures
power-control equations
HARQ circular-buffer positions
```

Same-Toolbox checks remain useful self-consistency regressions but must be labelled `same_implementation_self_consistency` and cannot satisfy `IndependenceClass` for a mandatory vector.

---

## 8. Explicit production TX pipeline

The strict transmitter must execute this order and record dimensions/digests at each stage:

```text
Decoded DCI / CG / RAR / MsgA event + current UE state
    -> immutable PUSCHSchedulingAssignment
    -> immutable PUSCHFrequencyHopPlan
    -> exact PUSCHResourceOwnershipMap
    -> measured SRS decision / explicit valid precoder bundle
    -> exact PUSCH power-control decision
    -> per-codeword TBS and ULSCHCodingPlan
    -> TB CRC
    -> code-block segmentation and CB CRC
    -> LDPC encode
    -> RV-specific rate matching
    -> typed UCI payload validation
    -> UCI coding and exact bit-budget calculation
    -> TS 38.212 UL-SCH/UCI multiplexing on selected owner codeword
    -> PUSCH scrambling with x/y behavior
    -> per-codeword modulation
    -> codeword-to-layer mapping
    -> transform precoding for valid rank-1 procedure only
    -> explicit UL precoder application exactly once
    -> exact data/DM-RS/PT-RS/hop mapping
    -> OFDM modulation
    -> exact transmit-power amplitude scaling
    -> waveform + immutable stage evidence
```

At every stage assert expected lengths. Do not catch an error and emit a zero waveform. Do not replace a failed configuration with a simpler one.

---

## 9. Explicit production RX pipeline

```text
Received waveform
    -> front-end timing/CFO correction
    -> OFDM demodulation
    -> exact hop/DM-RS extraction
    -> channel/noise/interference covariance estimation
    -> PT-RS CPE estimation/correction
    -> exact data/UCI RE extraction
    -> effective-channel construction with applied UL precoder
    -> equalization / selected multiuser detection
    -> inverse transform for valid transform-precoded case
    -> layer-to-codeword demapping
    -> soft demodulation
    -> descrambling with exact x/y handling
    -> UCI/UL-SCH demultiplexing
    -> UCI rate recovery/decoding/payload validation
    -> UL-SCH rate recovery
    -> position-aware HARQ combining
    -> LDPC decode
    -> CB/TB CRC
    -> receiver-derived SINR/EVM/BER/BLER evidence
```

TX truth may be used only after decoding to calculate BER for test reporting. It must not affect estimation, equalization, LLRs, UCI decoding, HARQ combining, or CRC.

---

## 10. Mandatory negative behavior

For every family add explicit negative tests. At minimum:

- missing/failed/wrong-RNTI DCI;
- stale/inactive/wrong UL BWP;
- K2 target slot unavailable;
- TDD symbols not available for UL;
- missing PRBs/symbol allocation/MCS/modulation;
- invalid DCI/RRC field combination;
- Type-1 CG not installed/released/wrong occasion;
- Type-2 CG not activated/failed activation/wrong occasion/released;
- invalid RAR/RAPID/MsgA resource;
- 1024QAM and 4096QAM;
- pi/2-BPSK without transform precoding;
- transform precoding rank >1;
- non-contiguous transform allocation;
- invalid rank/codeword/port tuple;
- invalid/mutated DM-RS fields or ports;
- invalid PT-RS density/offset/association/hop;
- incompatible frequency hopping/resource allocation;
- stale/mismatched SRS state;
- configured TPMI fallback attempt;
- missing measured pathloss/power state;
- invalid alpha/TPC/PCMAX state;
- UCI bit-budget overflow;
- CSI Part 2 without valid Part 1/report dependency;
- attempt to encode Scheduling Request on PUSCH;
- wrong UCI owner for two TBs;
- UCI processing primitive unavailable;
- HARQ TB/layout/epoch mismatch;
- wrong RNTI/scrambling identity/DM-RS port at RX;
- no-signal input.

Every negative row must record:

```text
expected error identifier
actual error identifier
assignment created flag
waveform generated flag
configuration mutated flag
status
```

Expected behavior is no assignment/waveform and no input mutation unless the negative test is receiver-only.

---

## 11. Required MATLAB test suites

Create focused suites and integrate them into repository-wide tests. At minimum:

```text
tests/testPUSCHSchedulingAssignmentVectors.m
tests/testPUSCHConfiguredGrantState.m
tests/testPUSCHRandomAccessAssignments.m
tests/testPUSCHResourcePlan.m
tests/testPUSCHModulationIndependent.m
tests/testPUSCHLayerMappingIndependent.m
tests/testULSCHCodingIndependent.m
tests/testPUSCHUCIIndependent.m
tests/testPUSCHDMRSIndependent.m
tests/testPUSCHPTRSIndependent.m
tests/testPUSCHTransformPrecodingIndependent.m
tests/testPUSCHFrequencyHopping.m
tests/testPUSCHSRSPrecoderAuthority.m
tests/testPUSCHPowerControl.m
tests/testPUSCHHARQ.m
tests/testPUSCHReceiverNoNoise.m
tests/testPUSCHReceiverChannels.m
tests/testPUSCHHighRank.m
tests/testPUSCHMUPUSCH.m
tests/testPUSCHPhaseArtifacts.m
```

Each suite must include positive, boundary, negative, no-signal, wrong-resource, wrong-identity, mutation, and deterministic-repeat checks where applicable.

No mandatory test may be converted to skipped because a feature is missing. A selected-profile missing feature is a failure. If MATLAB/5G Toolbox is unavailable, report the phase `BLOCKED`, not passed or complete.

---

## 12. Required CSV artifacts

Generate every file below from actual production execution. Use the exact column contract in `desired_pusch_csv_contract.csv`.

### `pusch_assignment_resolution.csv`

Primary key: `CaseID`. Required columns (48):

```text
CaseID
Profile
UEID
ServingCellID
CCID
BWPId
AbsoluteSlot
ConfigurationEpoch
AssignmentSource
DecodedDCIId
DCIFormat
DCICRCPass
DCIRNTIMatch
RNTIType
ConfiguredGrantID
CGType
CGInstalled
CGActivated
CGReleased
CGOccasionMatch
RARGrantID
K2
ULSymbolAvailable
ResourceAllocationType
FrequencyHopping
SecondHopStartPRB
PRBSet
SymbolAllocation
MappingType
MCSTable
MCSIndex
Modulation
TargetCodeRate
TransformPrecoding
NumLayers
NumCodewords
TransmissionScheme
SRI
TPMI
NDI
RV
HARQProcessID
SRSDecisionID
PowerControlStateID
AssignmentCreated
WaveformAllowed
ErrorIdentifier
Status
```

### `pusch_resource_ownership.csv`

Primary key: `CaseID|Slot|Hop|PRB|Symbol|Subcarrier|Owner|UEID`. Required columns (14):

```text
CaseID
Slot
Hop
PRB
Symbol
Subcarrier
Owner
UEID
Codeword
Layer
Port
SourceResourceId
CollisionCount
Status
```

### `pusch_re_mapping.csv`

Primary key: `CaseID|Domain|Hop|Codeword|Layer|Port|PRB|Symbol|Subcarrier`. Required columns (11):

```text
CaseID
Domain
Hop
Codeword
Layer
Port
PRB
Symbol
Subcarrier
LinearIndex0Based
Status
```

### `pusch_dmrs_matrix.csv`

Primary key: `CaseID`. Required columns (22):

```text
CaseID
MappingType
TransformPrecoding
DMRSConfigurationType
DMRSLength
DMRSAdditionalPosition
DMRSTypeAPosition
NumCDMGroupsWithoutData
NIDNSCID
NSCID
GroupHopping
SequenceHopping
RequestedDMRSPortSet
AppliedDMRSPortSet
AntennaPortField
DMRSSymbols
DMRSRECount
SequenceDigest
SequenceNMSE
IndexMismatchCount
InputMutationCount
Status
```

### `pusch_ptrs_matrix.csv`

Primary key: `CaseID|Hop`. Required columns (19):

```text
CaseID
TransformPrecoding
TimeDensity
FrequencyDensity
REOffset
PTRSPortSet
AssociatedDMRSPort
Hop
PTRSRECount
ExpectedPresent
PresenceReason
CPEBeforeDeg
CPEAfterDeg
EVMBeforePercent
EVMAfterPercent
SequenceDigest
IndexMismatchCount
InputMutationCount
Status
```

### `pusch_uci_multiplexing.csv`

Primary key: `CaseID|Codeword`. Required columns (31):

```text
CaseID
Codeword
NumULSCHTB
UCIOnly
OACK
OCSI1
OCSI2
OCGUCI
BetaOffsetACK
BetaOffsetCSI1
BetaOffsetCSI2
ScalingAlpha
UCIOwnerCodeword
G
ULSCHBitCount
ACKCodedBitCount
CSI1CodedBitCount
CSI2CodedBitCount
CGUCICodedBitCount
PlaceholderXCount
PlaceholderYCount
MuxedBitCount
DemuxedACKBits
DemuxedCSI1Bits
DemuxedCSI2Bits
DemuxedCGUCIBits
ACKCRCOK
CSI1CRCOK
CSI2CRCOK
PayloadMatch
Status
```

### `pusch_coding_chain.csv`

Primary key: `CaseID|Codeword`. Required columns (21):

```text
CaseID
Codeword
TBS
TBCRCType
TBCRCLength
BaseGraph
NumCodeBlocks
CodeBlockCRCType
LiftingSize
K
N
Ncb
FillerBits
RV
K0
EPerCodeBlock
G
RateMatchedBits
RateRecoveredBits
CRCOK
Status
```

### `pusch_independent_vector_results.csv`

Primary key: `VectorFamily|CaseID|ComparedField`. Required columns (13):

```text
VectorFamily
CaseID
ComparedField
OracleImplementation
OracleVersion
OracleArtifactSHA256
ExpectedDigest
ActualDigest
MismatchCount
MaxAbsError
Tolerance
IndependenceClass
Status
```

### `pusch_codeword_layer_map.csv`

Primary key: `CaseID|Codeword|Layer`. Required columns (9):

```text
CaseID
Rank
NumCodewords
Codeword
Layer
SourceSymbolCount
MappedSymbolCount
MismatchCount
Status
```

### `pusch_transform_precoding.csv`

Primary key: `CaseID|Hop|Layer`. Required columns (15):

```text
CaseID
Hop
Layer
DFTSize
MRB
InputSymbolCount
OutputSymbolCount
InputEnergy
OutputEnergy
EnergyRelativeError
RoundTripNMSE
InputPAPR_dB
OutputPAPR_dB
NormalizationConvention
Status
```

### `pusch_frequency_hopping.csv`

Primary key: `CaseID|AbsoluteSlot|RepetitionIndex|Hop`. Required columns (15):

```text
CaseID
Mode
ResourceAllocationType
AbsoluteSlot
RepetitionType
RepetitionIndex
Hop
PRBSet
SymbolSet
DMRSRECount
PTRSRECount
DataRECount
ExpectedPRBSet
PRBMismatchCount
Status
```

### `pusch_srs_precoder_selection.csv`

Primary key: `CaseID`. Required columns (29):

```text
CaseID
UEID
ServingCellID
CCID
BWPId
SRSResourceSetID
SRSResourceID
SRSUsage
MeasurementSlot
CurrentSlot
AgeSlots
MaxAgeSlots
MeasurementConfigurationEpoch
CurrentConfigurationEpoch
HEstimateDigest
NoiseVariance
CovarianceDigest
SelectedRI
SelectedSRI
SelectedTPMI
SelectionMetric
DecisionID
DecisionSource
DecisionValid
AppliedDecisionID
AppliedTPMI
AppliedPrecoderDigest
ConfiguredTPMIFallbackUsed
Status
```

### `pusch_precoding_application.csv`

Primary key: `CaseID|Hop|PRG|SymbolGroup`. Required columns (14):

```text
CaseID
Hop
PRG
SymbolGroup
NPorts
NLayers
SRSDecisionID
MatrixDigest
AppliedMatrixDigest
InputEnergy
OutputEnergy
PowerRelativeError
MatrixApplicationCount
Status
```

### `pusch_power_control.csv`

Primary key: `CaseID`. Required columns (27):

```text
CaseID
UEID
AbsoluteSlot
LoopId
AdjustmentMode
Mu
MRB
P0Nominal_dBm
P0UE_dB
Alpha
PathlossReferenceRS
MeasuredPathloss_dB
DeltaTF_dB
PreviousF_dB
TPCCommandBits
TPCDelta_dB
UpdatedF_dB
RequestedPower_dBm
PCMAX_dBm
AppliedPower_dBm
PowerHeadroom_dB
ReferenceWaveformPower_dBm
AppliedAmplitudeScale
MeasuredWaveformPower_dBm
PowerError_dB
Clipped
Status
```

### `pusch_harq_trials.csv`

Primary key: `CaseID|Codeword|TransmissionIndex`. Required columns (16):

```text
CaseID
HARQProcessID
Codeword
TransmissionIndex
NDI
RV
TBIdentity
TBS
CodeBlockLayoutDigest
SoftBufferInputDigest
SoftBufferOutputDigest
HARQAction
Combined
TBCRCOK
ACKState
Status
```

### `pusch_receiver_metrics.csv`

Primary key: `CaseID|Codeword|Layer|Hop`. Required columns (22):

```text
CaseID
SNRdB
ChannelModel
UEID
Rank
Codeword
Layer
Hop
DataRECount
LLRCount
RateRecoveredBitCount
MeasuredSINRdB
MeasuredSINRSource
ReceiverDerived
EVMPercent
BER
BLER
TBCRCOK
ChannelEstimateNMSEdB
LDPCIterations
InterferenceCovarianceUsed
Status
```

### `pusch_bler_curve.csv`

Primary key: `CampaignID|OperatingPointID`. Required columns (20):

```text
CampaignID
OperatingPointID
SNRdB
ChannelModel
Rank
MCSIndex
Modulation
TransformPrecoding
FrequencyHopping
Trials
TBErrors
BLER
ConfidenceLevel
CILower
CIUpper
CIHalfWidth
MinErrorsRequired
StopReason
Incomplete
Status
```

### `pusch_negative_tests.csv`

Primary key: `CaseID`. Required columns (8):

```text
CaseID
TestKind
ExpectedErrorIdentifier
ActualErrorIdentifier
AssignmentCreated
WaveformGenerated
ConfigurationMutated
Status
```

### `pusch_test_summary.csv`

Primary key: `TestSuite`. Required columns (8):

```text
TestSuite
Mandatory
Total
Passed
Failed
Skipped
Blocked
Status
```

### `pusch_image_semantic_audit.csv`

Primary key: `ImageFile`. Required columns (16):

```text
ImageFile
SourceCSV
Width
Height
AxesCount
SeriesCount
FinitePointCount
ExpectedXLabel
ActualXLabel
ExpectedYLabel
ActualYLabel
ExpectedTitleToken
ActualTitle
SourceCSV_SHA256
PNG_SHA256
Status
```


Global CSV rules:

- UTF-8, comma-separated, one header row;
- no duplicate primary keys;
- no NaN/Inf in mandatory numeric evidence;
- zero-based PHY indices;
- every mandatory result row has `Status=PASS`;
- negative cases appear in the negative-test file with the expected typed failure;
- `pusch_test_summary.csv` must have zero failed, skipped, or blocked mandatory tests;
- result CSVs must be created by the phase runner, not copied from `expected_*` files;
- all source/configuration/assignment identifiers must be traceable across files.

---

## 13. Required PNG artifacts

Generate all images from the corresponding production CSVs. Do not create decorative placeholders.

### `pusch_resource_grid_ownership.png`

- Source CSV: `pusch_resource_ownership.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 1
- Minimum finite points: 100
- X label: `PRB / subcarrier`
- Y label: `OFDM symbol`
- Title must contain: `PUSCH resource ownership`

### `pusch_dmrs_ptrs_hop_map.png`

- Source CSV: `pusch_dmrs_matrix.csv|pusch_ptrs_matrix.csv|pusch_frequency_hopping.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 3
- Minimum finite points: 30
- X label: `Subcarrier / PRB`
- Y label: `OFDM symbol`
- Title must contain: `PUSCH DM-RS PT-RS hopping`

### `pusch_uci_bit_allocation.png`

- Source CSV: `pusch_uci_multiplexing.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 3
- Minimum finite points: 20
- X label: `Coded-bit position`
- Y label: `Payload owner`
- Title must contain: `UCI multiplexing`

### `pusch_codeword_layer_mapping.png`

- Source CSV: `pusch_codeword_layer_map.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 1
- Minimum finite points: 8
- X label: `Layer`
- Y label: `Mapped symbols`
- Title must contain: `PUSCH codeword-to-layer mapping`

### `pusch_transform_precoding_spectrum.png`

- Source CSV: `pusch_transform_precoding.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 2
- Minimum finite points: 24
- X label: `Subcarrier`
- Y label: `Magnitude / power`
- Title must contain: `Transform precoding spectrum`

### `pusch_papr_ccdf.png`

- Source CSV: `pusch_transform_precoding.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 2
- Minimum finite points: 20
- X label: `PAPR (dB)`
- Y label: `CCDF`
- Title must contain: `PUSCH PAPR`

### `pusch_frequency_hop_timeline.png`

- Source CSV: `pusch_frequency_hopping.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 2
- Minimum finite points: 8
- X label: `Slot / OFDM symbol`
- Y label: `PRB / hop`
- Title must contain: `PUSCH frequency hopping`

### `pusch_srs_tpmi_selection.png`

- Source CSV: `pusch_srs_precoder_selection.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 2
- Minimum finite points: 8
- X label: `SRS measurement / case`
- Y label: `RI SRI TPMI metric`
- Title must contain: `SRS-derived uplink precoding`

### `pusch_power_control_convergence.png`

- Source CSV: `pusch_power_control.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 2
- Minimum finite points: 8
- X label: `Slot / TPC command`
- Y label: `Transmit power (dBm)`
- Title must contain: `PUSCH power control`

### `pusch_bler_vs_snr.png`

- Source CSV: `pusch_bler_curve.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 1
- Minimum finite points: 4
- X label: `SNR (dB)`
- Y label: `BLER`
- Title must contain: `PUSCH BLER`

### `pusch_per_layer_sinr.png`

- Source CSV: `pusch_receiver_metrics.csv`
- Minimum dimensions: 900 × 600
- Minimum axes: 1
- Minimum series: 1
- Minimum finite points: 8
- X label: `Layer / operating point`
- Y label: `Measured SINR (dB)`
- Title must contain: `PUSCH per-layer SINR`


For every image write one row to `pusch_image_semantic_audit.csv` containing actual dimensions, axes count, series count, finite-point count, labels, title, source CSV SHA-256, PNG SHA-256, and status.

The Python verifier checks decoding, nonblank content, dimensions, hashes, labels/titles, source linkage, and semantic minimums. Do not hard-code a PASS row without inspecting the actual MATLAB figure and written PNG.

---

## 14. Required phase runner

Implement:

```matlab
summary = sixgr.phy.ul.pusch.runPUSCHPhaseValidation( ...
    'VectorRoot', fullfile(pwd,'tests','vectors','pusch'), ...
    'OutputDir', fullfile(pwd,'artifacts','pusch_ulsch_phase'), ...
    'SeedList', [11 23 47 89], ...
    'ConfidenceLevel', 0.95, ...
    'Strict', true)
```

The runner must:

1. validate the vector manifest and hashes;
2. run every supplied vector through production functions;
3. run independent-oracle comparisons;
4. run all negative tests;
5. run no-noise exact rank/codeword/modulation cases;
6. run SRS/precoder, power-control, hopping, HARQ, PTRS, channel, and MU cases;
7. run BLER campaigns;
8. generate all 20 CSVs;
9. generate all 11 PNGs;
10. inspect MATLAB figure semantics and write the image audit;
11. calculate hashes after files are closed;
12. return `Passed=true` only when all mandatory tests and artifact checks pass.

The runner must never catch a mandatory failure and continue with `Passed=true`.

---

## 15. Commands Codex must run

### Vector integrity

```bash
python tests/vectors/pusch/verify_pusch_vector_pack.py
```

### Focused MATLAB suites

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PUSCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*ULSCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*UCI*PUSCH*'); assertSuccess(r);"
```

### Phase execution

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.ul.pusch.runPUSCHPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','pusch'),'OutputDir',fullfile(pwd,'artifacts','pusch_ulsch_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

### Artifact verification

```bash
python tests/vectors/pusch/verify_pusch_artifacts.py artifacts/pusch_ulsch_phase
```

### Existing regressions

Run all existing UL/PUSCH/PDCCH-grant/SRS/HARQ/power-control tests touched by the change, followed by the complete repository test suite on the pinned MATLAB release.

Record exact commands, MATLAB release, 5G Toolbox release, test counts, runtime, and failures.

---

## 16. Acceptance tolerances

Use exact comparison where the standard defines bits, enum values, table selections, ports, or indices.

Mandatory deterministic limits:

```text
bit mismatch count                         = 0
index mismatch count                       = 0
port mismatch count                        = 0
input mutation count                       = 0
no-noise decoded TB/UCI mismatch            = 0
transform round-trip NMSE                  <= 1e-12
transform relative energy error            <= 1e-12
independent matrix multiplication max error <= 1e-12
DM-RS sequence NMSE                        <= 1e-12
power application error in controlled test <= 0.05 dB
finite LLR fraction                        = 1.0
mandatory measured SINR present            = true
configured-SNR substitution                = false
```

For stochastic campaigns:

- use deterministic multiple seeds;
- export confidence intervals;
- enforce configured minimum trials and errors;
- mark cap-hit/incomplete points as incomplete failures unless an explicit one-sided censored policy is selected;
- require directionally sensible BLER versus SNR with confidence-aware checks;
- compare to external curves only when independently versioned and hashed;
- never create a reference curve by copying DUT output.

For PT-RS impairment tests, require measured CPE/EVM improvement at selected nonzero phase-noise operating points and confidence-aware BLER non-degradation/improvement. Do not require improvement when PT-RS is correctly disabled.

---

## 17. Prohibited shortcuts

Do not:

1. keep ACK-only UCI and add CSI metadata without coding/multiplexing it;
2. pass empty CSI arrays to `nrULSCHMultiplex`/`nrULSCHDemultiplex` for a CSI-enabled case;
3. hard-code `O_CSI1=0` or `O_CSI2=0`;
4. encode Scheduling Request on PUSCH;
5. use configured PRBs, symbols, MCS, TPMI, pathloss, or SNR as decoded/measured strict state;
6. default to full BWP or full slot;
7. overwrite DM-RS ports from layer count;
8. clamp or round invalid DM-RS/PT-RS values;
9. change mapping type A to B;
10. auto-enable transform precoding from pi/2-BPSK;
11. allow transform-precoded rank >1 in this profile;
12. collapse a two-codeword/high-rank case to one codeword;
13. reject high rank while still claiming it supported;
14. use a PDSCH-named helper as an opaque PUSCH precoder without exact UL tests;
15. choose configured TPMI when measured SRS state is absent/stale;
16. derive pathloss from configured SNR;
17. omit the `2^mu` factor from power control;
18. compute power without applying it to the waveform;
19. generate DM-RS/PT-RS/data before resolving collisions/hops;
20. split intra-slot hops at half allocation without exact table ownership;
21. concatenate HARQ LLR vectors instead of position-aware combining;
22. return `Status="unavailable"` for mandatory UCI processing and continue;
23. catch an error and emit a zero grid/waveform;
24. use transmitted bits/channel/CRC outcome in the real receiver;
25. call the same `nr*` primitive on DUT and oracle sides and label it independent;
26. copy expected vectors into production outputs;
27. create blank/placeholder images;
28. mark unavailable/skipped MATLAB tests as passing;
29. edit expected vectors merely to match current production shortcuts;
30. report `COMPLETE` while any mandatory CSV/PNG is absent or verifier exits nonzero.

---

## 18. Definition of done

This phase is complete only when all conditions are true:

1. all 12 findings in `pusch_ulsch_12_findings.csv` are implemented for the selected profile;
2. all 38 current defect behaviors are removed from production paths;
3. the nine useful current foundations are preserved or strengthened;
4. all 487 supplied input rows execute through the intended production or negative path;
5. all bounded expected rows and all additional full independent vectors pass;
6. dynamic DCI, Type-1/Type-2 CG, Msg3, MsgA, and calibration ownership are separate and correct;
7. complete HARQ-ACK/CSI1/CSI2/CG-UCI/UCI-only PUSCH processing passes;
8. Scheduling Request is rejected from PUSCH UCI and routed to PUCCH;
9. DM-RS/PT-RS ports, tables, sequences, and indices pass independent checks;
10. transform precoding is exact and rank-constrained;
11. hopping, SRS-derived precoding, power control, HARQ, high-rank, and bounded MU tests pass;
12. receiver-derived SINR is present for every strict campaign row;
13. no mandatory MATLAB test is failed, skipped, blocked, or unavailable;
14. all 20 required CSVs exist and pass schema/semantic checks;
15. all 11 required PNGs exist and pass decode/hash/semantic checks;
16. the phase runner returns `Passed=true`;
17. `verify_pusch_vector_pack.py` returns 0;
18. `verify_pusch_artifacts.py artifacts/pusch_ulsch_phase` returns 0;
19. the complete affected and repository-wide MATLAB regression suites pass on the pinned toolchain.

MATLAB or 5G Toolbox unavailable means `BLOCKED`, not complete.

---

## 19. Required Codex final response

At the end, report exactly:

1. files added, modified, and deleted;
2. the canonical architecture implemented;
3. each finding ID `UL-001` through `UL-012` and its closure evidence;
4. exact MATLAB/5G Toolbox versions;
5. exact commands executed;
6. test totals: passed, failed, skipped, blocked;
7. input-vector and independent-vector counts;
8. no-noise rank/modulation/codeword cases executed;
9. BLER campaign operating points, trials, errors, and stopping reasons;
10. all 20 CSV row counts and SHA-256 values;
11. all 11 PNG dimensions and SHA-256 values;
12. artifact-verifier output and exit code;
13. residual unsupported tuples, if any, with typed rejection evidence;
14. final status: `COMPLETE`, `FAIL`, or `BLOCKED`.

Do not use `COMPLETE` unless the definition of done is fully satisfied.
