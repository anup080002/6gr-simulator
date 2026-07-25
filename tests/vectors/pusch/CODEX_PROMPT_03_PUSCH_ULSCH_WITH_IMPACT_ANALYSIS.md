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


---

# Part B — Mandatory technical impact-analysis extension

This Part B is mandatory. It extends the implementation work above; it does not replace any correctness test, production change, independent vector, CSV, PNG, or completion condition in Part A.

The purpose is to answer two different questions with separate evidence:

1. **Is the implementation correct?** Use exact bit/index/resource/power/state invariants and negative tests.
2. **What technical impact does the implementation have?** Use controlled paired experiments, receiver-derived measurements, confidence intervals, effect sizes, and explicit computational-cost measurements.

Do not use an observed performance gain to excuse a failed exact invariant. Do not use a passing exact invariant to claim that a feature improves BLER, throughput, latency, EVM, PAPR, power, or receiver robustness. Both evidence layers are required.

## B1. Supplied impact-analysis assets

Use these files without changing expected relationships merely to make production code pass:

- `pusch_impact_analysis_families.csv` — **52** technical impact families.
- `pusch_impact_experiment_matrix.csv` — **705** reproducible experiment definitions.
- `pusch_impact_pairing_contract.csv` — **52** family-specific baseline/treatment/oracle matching contracts.
- `pusch_impact_acceptance_rules.csv` — **70** hard, statistical, and diagnostic rules.
- `expected_pusch_impact_analytical_floor.csv` — **59** independent exact/relationship floor rows.
- `pusch_impact_implementation_map.csv` — finding-to-code-to-impact mapping.
- `pusch_impact_dependency_waves.csv` — one execution wave for each family.
- `pusch_impact_implementability_summary.csv` — 28 core-now, 10 internal-dependency, and 14 cross-area families.
- `desired_pusch_impact_csv_contract.csv` — **16** additional required production CSVs.
- `desired_pusch_impact_image_contract.csv` — **26** additional required production PNGs.
- `verify_pusch_impact_pack.py` — pack integrity verifier.
- `verify_pusch_impact_artifacts.py` — fail-closed result and image verifier.

Run before editing production code:

```bash
python tests/vectors/pusch/verify_pusch_impact_pack.py
```

It must return exit code 0.

## B2. Production analysis architecture

Add or consolidate the following production package. Do not put scientific logic only in tests or ad-hoc scripts.

```text
+sixgr/+phy/+ul/+pusch/+analysis/
    PUSCHImpactExperiment.m
    PUSCHImpactExperimentFactory.m
    PUSCHImpactRunner.m
    PUSCHImpactPairing.m
    PUSCHImpactAggregator.m
    PUSCHImpactStatistics.m
    PUSCHImpactRuleEvaluator.m
    PUSCHImpactPlotter.m
    PUSCHImpactArtifactExporter.m
    PUSCHRuntimeProfiler.m
    PairedRNGStreams.m
    computeWilsonInterval.m
    computeClopperPearsonInterval.m
    computePairedBootstrapCI.m
    computeMcNemarTest.m
    computeEffectSize.m
    adjustPValuesHolm.m
    fitFactorialEffects.m
    runPUSCHImpactValidation.m
```

### B2.1 Mandatory data lineage

Every trial row must carry:

```text
RunID
ExperimentID
FamilyID
PairID
DesignCell
Variant
Seed
ChannelRNGStreamID
NoiseRNGStreamID
PayloadRNGStreamID
OperatingPointID
AssignmentID
ResourcePlanDigest
CodingPlanDigest
DMRSPlanDigest
PTRSPlanDigest
PrecoderDecisionDigest
AppliedPrecoderDigest
PowerLedgerDigest
HARQContextDigest
ReceiverConfigurationDigest
```

Baseline and treatment rows selected by `pusch_impact_pairing_contract.csv`, with the same `PairID`, `Seed`, `OperatingPointID`, TB index, and all nonswept control fields must reuse the same underlying payload, propagation channel realization and noise realization unless the treatment specifically changes that process. Record all deliberate exceptions.

Never obtain paired effects by comparing unrelated random runs. `DesignCell` identifies a sweep cell; it is not by itself a pairing key. Reject missing, duplicate, or control-mismatched pairs rather than silently falling back to unpaired analysis.

### B2.2 Statistics

Implement these minimum methods:

- Wilson intervals for ordinary BLER/BER proportions;
- exact Clopper-Pearson upper bounds for zero-error/rare false-decode studies;
- McNemar tests for paired block-error outcomes;
- paired bootstrap confidence intervals for EVM, SINR, PAPR, CPE, NMSE, power, latency and goodput effects;
- standardized effect sizes with sign convention `treatment - baseline`;
- Holm family-wise correction across related tests;
- factorial main/two-way interaction models for F51;
- explicit `inconclusive` status when the CI does not establish the configured direction or sample size is insufficient.

Do not convert `inconclusive` into `PASS` or `FAIL` for a diagnostic performance hypothesis. Hard correctness rules remain fail-closed.

### B2.3 Campaign stopping

Use one canonical point status and stop-reason enumeration. At minimum:

```text
complete_ci_and_min_errors
complete_fixed_trials
complete_zero_error_upper_bound
incomplete_max_trials
invalid_configuration
blocked_dependency
failed_runtime
```

A mandatory impact operating point with an `incomplete_*`, `blocked_*`, or `failed_*` status prevents phase completion. A zero-error point is complete only when its one-sided upper confidence bound meets the configured requirement.

## B2.4 Implementability and execution waves

Use `pusch_impact_dependency_waves.csv` as the execution order. Do not remove experiments because a dependency is not yet ready.

### Wave A — core PUSCH now: 28 families

Implement and execute these directly while correcting the PUSCH/UL-SCH chain:

```text
F01 F02 F03 F04 F05 F06 F07 F08
F12 F13 F15 F17 F18 F19 F20 F21 F22 F23
F25 F26 F33 F34 F35 F40 F43 F44 F49 F50
```

They cover exact UCI capacity/decoding, DCI ownership, coding boundaries, modulation/rank/two-codeword behavior, DM-RS/PT-RS, transform precoding, hopping, power control, HARQ combining, measured SINR, false decode, runtime, and deterministic replay.

### Wave B — internal PUSCH prerequisites: 10 families

Implement these in the same phase after the named internal state is functional:

```text
F09 F10        configured-grant assignment/state
F16            measured-SRS precoder authority
F27            hopping-aware HARQ
F28 F29 F30 F31 measured SRS quality/age/coverage/oracle comparison
F38 F39        receiver covariance and strict IRC
```

A Wave-B row may temporarily use `blocked_dependency` during development, but the final PUSCH phase cannot pass while it remains blocked.

### Wave C — cross-area dependencies: 14 families

The experiment and artifact definitions are supplied now, while execution requires the corresponding production dependency:

```text
F11  random-access Msg3/MsgA
F14  spatially correlated channel/high-rank environment
F24  RF PA nonlinearity
F32  RF calibration/reciprocity error
F36  pathloss measurement/filtering
F37  multi-user/inter-cell channel
F41  central K2/HARQ timing and packet deadlines
F42  multi-user shared-PRB receiver
F45  waveform CFO and estimator
F46  timing acquisition/tracking
F47  phase-noise model
F48  canonical frame/numerology engine
F51  completed core-feature factorial study
F52  all-prerequisite end-to-end scenarios
```

Do not fake these with configured SINR, scalar interference, perfect timing, perfect covariance, ideal PA, or true-channel receiver inputs. Keep them blocked until the real dependency exists, then execute them. The final all-impact status requires every Wave-C family to run.

## B3. Impact analyses, one by one

### F01 — UCI composition and UL-SCH capacity

**Findings addressed:** `UL-001|UL-003|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Exact TS 38.212 UCI chain

**Technical question.** Quantify how HARQ-ACK, CSI Part 1, CSI Part 2, CG-UCI and UTO-UCI consume coded-bit and RE capacity and alter effective UL-SCH code rate.

**Baseline.** No UCI on an otherwise identical grant.

**Treatment.** Add one exact UCI composition at a time.

**Hold constant.** Same decoded grant, TB, modulation, rank, channel realization and noise samples.

**Sweep.** OACK, OCSI1, OCSI2, OCGUCI, beta offsets, alpha, one/two codewords.

**Primary metrics.** `G|GULSCH|GACK|GCSI1|GCSI2|effective_code_rate|ULSCH_goodput|BLER`

**Secondary metrics.** `decoder_time_ms|memory_bytes|UCI_CRC`

**Required analysis.** Exact bit-budget reconciliation; no overlap; decoded UCI equals payload; paired Wilson/McNemar for BLER.

**Hard acceptance.** At fixed G, added UCI cannot increase GULSCH. Every coded-bit position has exactly one owner.

**Interpretation.** Measure data-throughput penalty and control-reliability benefit; do not impose a universal BLER direction when TBS adaptation is enabled.

**Minimum campaign floor.** `8` seeds and `2000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_uci_capacity.png|pusch_impact_uci_bler.png`

### F02 — UCI beta-offset sensitivity

**Findings addressed:** `UL-001|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F01

**Technical question.** Measure reliability/capacity trade-offs produced by beta-offset and alpha choices.

**Baseline.** Nominal beta offsets from active configuration.

**Treatment.** Sweep valid lower and higher beta offsets.

**Hold constant.** Same payload, grant, codeword owner, channel/noise and TB.

**Sweep.** betaOffsetACK, betaOffsetCSI1, betaOffsetCSI2, alpha.

**Primary metrics.** `ACK_BLER|CSI1_BLER|CSI2_BLER|ULSCH_BLER|GULSCH|UCI_energy_fraction`

**Secondary metrics.** `EVM|decoder_time_ms`

**Required analysis.** Exact Q-prime/E calculation and valid-range checks; invalid values fail before waveform generation.

**Hard acceptance.** Higher UCI protection must be reflected in exact coded-bit/energy allocation; invalid values create no waveform.

**Interpretation.** Report Pareto frontier between UCI reliability and UL-SCH goodput.

**Minimum campaign floor.** `8` seeds and `3000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_uci_beta_tradeoff.png`

### F03 — CSI Part 2 payload-size and dependency impact

**Findings addressed:** `UL-001|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F01

**Technical question.** Exercise zero, small, boundary and large CSI Part 2 payloads and their dependency on CSI Part 1.

**Baseline.** CSI Part 1 only.

**Treatment.** Add configured CSI Part 2 payloads.

**Hold constant.** Same report configuration and decoded grant.

**Sweep.** OCSI2, report type, rank, modulation, UCI capacity.

**Primary metrics.** `CSI2_CRC|CSI2_BER|ULSCH_goodput|capacity_margin_bits`

**Secondary metrics.** `decode_latency_ms`

**Required analysis.** CSI Part 2 without required Part 1 is rejected; exact payload length is never guessed.

**Hard acceptance.** Payload recovery is bit exact in no-noise tests; insufficient capacity fails with typed error.

**Interpretation.** Quantify threshold where extra CSI payload materially raises UL-SCH code rate or forces TBS reduction.

**Minimum campaign floor.** `8` seeds and `3000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_csi2_size.png`

### F04 — UCI-only PUSCH

**Findings addressed:** `UL-001|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F01

**Technical question.** Validate PUSCH carrying UCI with zero UL-SCH TB and quantify detection/reliability.

**Baseline.** Small UL-SCH plus identical UCI.

**Treatment.** TBS=0 with UCI present.

**Hold constant.** Same grant resources and UCI payload.

**Sweep.** UCI composition, modulation, DMRS, SNR.

**Primary metrics.** `UCI_BLER|false_alarm_rate|missed_detection_rate|occupied_RE`

**Secondary metrics.** `EVM|runtime_ms`

**Required analysis.** TBS=0 is handled without fabricated data bits; no-signal false-alarm test included.

**Hard acceptance.** No-noise UCI recovery is exact; no-signal false decode is below configured bound.

**Interpretation.** Compare robustness and resource use against mixed data+UCI.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_uci_only_detection.png`

### F05 — Two-codeword UCI owner selection

**Findings addressed:** `UL-001|UL-003|UL-010|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F01|high-rank support

**Technical question.** Verify and quantify UCI placement for two UL-SCH transport blocks.

**Baseline.** One-codeword PUSCH with equivalent total layers.

**Treatment.** Two codewords with unequal/equal initial I_MCS.

**Hold constant.** Same total rank, channel and total grant.

**Sweep.** I_MCS_CW0, I_MCS_CW1, rank 5-8, UCI load.

**Primary metrics.** `owner_codeword|CW0_BLER|CW1_BLER|UCI_BLER|goodput`

**Secondary metrics.** `per_CW_decoder_time`

**Required analysis.** UCI owner is higher initial I_MCS; tie selects CW0; all owner positions reconcile.

**Hard acceptance.** Wrong owner injection must be detected by independent position oracle.

**Interpretation.** Quantify asymmetric codeword impact and whether owner choice changes total goodput.

**Minimum campaign floor.** `8` seeds and `3000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_two_codeword_uci.png`

### F06 — TBS, base-graph and segmentation boundaries

**Findings addressed:** `UL-003|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** UL-SCH coding plan

**Technical question.** Measure discontinuities and correctness at TBS, base-graph, code-block and lifting-size boundaries.

**Baseline.** Point immediately below each boundary.

**Treatment.** Point at and above each boundary.

**Hold constant.** Same resource allocation and target code rate where possible.

**Sweep.** TBS, target code rate, modulation, rank, limited-buffer rate matching.

**Primary metrics.** `base_graph|C|Zc|filler_bits|G|BLER|decoder_iterations`

**Secondary metrics.** `runtime_ms|memory_bytes`

**Required analysis.** Pure-spec boundary oracle exactly matches production metadata and bit positions.

**Hard acceptance.** No off-by-one, negative filler, or unaccounted bit; no-noise TB recovery exact.

**Interpretation.** Identify performance/complexity steps caused by segmentation changes.

**Minimum campaign floor.** `8` seeds and `3000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_ldpc_boundaries.png`

### F07 — LDPC iterations and LLR scaling

**Findings addressed:** `UL-003|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** UL-SCH decoder instrumentation

**Technical question.** Quantify decoder complexity and robustness to iteration limit and LLR scaling.

**Baseline.** Validated nominal LLR scale and iteration limit.

**Treatment.** Sweep iteration limit and controlled LLR scale errors.

**Hold constant.** Same received samples and rate-recovery output.

**Sweep.** max_iterations, llr_scale, early_termination.

**Primary metrics.** `BLER|mean_iterations|p95_iterations|decoder_time_ms`

**Secondary metrics.** `energy_per_decoded_bit_proxy`

**Required analysis.** No-noise decode must pass at nominal settings; NaN/Inf LLR rejected.

**Hard acceptance.** Iteration increase cannot change decoded result when CRC already passes; output records convergence.

**Interpretation.** Report complexity/BLER knee; do not tune hidden defaults per operating point.

**Minimum campaign floor.** `8` seeds and `3000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_decoder_complexity.png`

### F08 — Decoded DCI ownership and stale-state rejection

**Findings addressed:** `UL-006|UL-008|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Decoded DCI interface

**Technical question.** Measure technical consequences of valid versus corrupted/stale scheduling state while enforcing no-waveform behavior for invalid state.

**Baseline.** CRC-valid DCI 0_x bound to current BWP/RRC epoch.

**Treatment.** Single-field corruption: CRC, RNTI, BWP, K2, MCS, HARQ, TPMI, epoch.

**Hold constant.** Same underlying intended grant.

**Sweep.** DCI format 0_0/0_1/0_2/0_3 and fault type.

**Primary metrics.** `assignment_created|waveform_generated|typed_error|resource_digest`

**Secondary metrics.** `planning_time_ms`

**Required analysis.** Every invalid state creates no waveform and no HARQ mutation.

**Hard acceptance.** Valid DCI field changes alter actual production resource/coding digest exactly.

**Interpretation.** Impact is reported as prevented collision/misdecode risk, not as simulated conformance wording.

**Minimum campaign floor.** `1` seeds and `1` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_grant_ownership.png`

### F09 — Configured-grant latency and control overhead

**Findings addressed:** `UL-006|UL-008`  
**Implementability:** `implement_now_after_assignment_state`  
**Dependencies:** MAC event source and F08

**Technical question.** Compare dynamic scheduling, Type-1 CG and Type-2 CG for periodic and bursty traffic.

**Baseline.** Dynamic DCI scheduling.

**Treatment.** Configured-grant Type 1 or activated Type 2.

**Hold constant.** Same traffic arrivals, channel, power and resources.

**Sweep.** periodicity, offset, traffic burstiness, activation latency.

**Primary metrics.** `packet_access_latency_slots|PDCCH_bits|grant_utilization|goodput`

**Secondary metrics.** `collision_rate|energy_per_packet`

**Required analysis.** CG state machine and exact occasion ownership are hard gates.

**Hard acceptance.** No transmission outside active occasion; release/activation behavior exact.

**Interpretation.** Quantify latency/control-overhead benefit and unused-resource cost.

**Minimum campaign floor.** `20` seeds and `10000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_configured_grant_latency.png`

### F10 — Configured-grant collision, repetition and retransmission

**Findings addressed:** `UL-008|UL-012`  
**Implementability:** `implement_now_after_assignment_state`  
**Dependencies:** F09|HARQ

**Technical question.** Analyze collision handling and reliability for CG repetitions and competing dynamic grants.

**Baseline.** Single CG occasion without collision.

**Treatment.** Collision, repetition, dynamic override, retransmission and release cases.

**Hold constant.** Same UE/channel/traffic sequence.

**Sweep.** CG type, repetition count, collision policy, RV sequence.

**Primary metrics.** `collision_detected|successful_repetitions|BLER|latency|resource_waste`

**Secondary metrics.** `HARQ_state_digest`

**Required analysis.** No double ownership; deterministic policy; HARQ TB identity preserved.

**Hard acceptance.** Every repeated transmission maps to the correct occasion and RV.

**Interpretation.** Quantify reliability/latency/resource trade-off.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_configured_grant_collisions.png`

### F11 — RAR Msg3 and MsgA uplink coverage

**Findings addressed:** `UL-006|UL-008|UL-012`  
**Implementability:** `implement_after_RA_dependency`  
**Dependencies:** RAR/MsgA production path

**Technical question.** Validate random-access PUSCH ownership and quantify coverage/power/latency.

**Baseline.** RAR Msg3 under nominal pathloss.

**Treatment.** Pathloss, power ramping, timing error and MsgA variants.

**Hold constant.** Same random-access identity and channel seed.

**Sweep.** RA procedure, pathloss, power ramp step, timing offset.

**Primary metrics.** `success_probability|BLER|tx_power_dBm|access_latency_slots`

**Secondary metrics.** `false_detection|resource_collision`

**Required analysis.** RAR/MsgA grant fields and identities must be preserved; wrong identity creates no decode.

**Hard acceptance.** No-noise exact recovery and typed negative cases pass.

**Interpretation.** Quantify cell-edge access robustness and power cost.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_random_access_uplink.png`

### F12 — Modulation-order impact

**Findings addressed:** `UL-003|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Complete modulation matrix

**Technical question.** Compare pi/2-BPSK, QPSK, 16QAM, 64QAM and 256QAM across exact declared profiles.

**Baseline.** QPSK at matched target BLER.

**Treatment.** Other supported modulations with valid MCS/TBS.

**Hold constant.** Same rank, grant, channel and power normalization.

**Sweep.** modulation, MCS, code rate, SNR.

**Primary metrics.** `BLER|goodput|EVM|required_SNR_at_target_BLER`

**Secondary metrics.** `PAPR|decoder_time_ms`

**Required analysis.** Independent constellation and no-noise bit recovery are exact.

**Hard acceptance.** Unsupported 1024QAM/4096QAM fail before waveform generation in this profile.

**Interpretation.** Produce SNR gap and spectral-efficiency curves with confidence intervals.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_modulation_bler.png`

### F13 — Rank scaling in low-correlation channels

**Findings addressed:** `UL-003|UL-010|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Eight-layer/two-codeword support

**Technical question.** Measure throughput and reliability from rank 1 through 8 in i.i.d./low-correlation MIMO.

**Baseline.** Rank 1 with same antenna array.

**Treatment.** Ranks 2-8, valid one/two-codeword mapping.

**Hold constant.** Same total transmit power, bandwidth and channel seeds.

**Sweep.** rank, antenna ports, receiver, modulation.

**Primary metrics.** `sum_goodput|BLER|per_layer_SINR|condition_number`

**Secondary metrics.** `runtime_ms|memory_bytes`

**Required analysis.** No-noise rank 1-8 exact recovery; power conservation; layer mapping exact.

**Hard acceptance.** No universal monotonic rank gain is a hard gate; report the rank maximizing goodput.

**Interpretation.** Quantify multiplexing gain and receiver/complexity cost.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_rank_scaling.png`

### F14 — Rank scaling under spatial correlation

**Findings addressed:** `UL-003|UL-010`  
**Implementability:** `implement_after_channel_covariance`  
**Dependencies:** F13|channel model

**Technical question.** Measure rank collapse and precoder sensitivity as antenna correlation increases.

**Baseline.** Low-correlation channel.

**Treatment.** Medium/high correlation with same average path gain.

**Hold constant.** Same rank request, SNR and channel seeds paired by underlying paths.

**Sweep.** rank, correlation coefficient/model, receiver.

**Primary metrics.** `effective_rank|BLER|goodput|per_layer_SINR`

**Secondary metrics.** `condition_number|TPMI_stability`

**Required analysis.** Channel covariance and applied precoder are exported.

**Hard acceptance.** No fake rank success through configured SINR; measured per-layer SINR required.

**Interpretation.** Identify safe rank-selection thresholds.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_rank_correlation.png`

### F15 — One- versus two-codeword PUSCH

**Findings addressed:** `UL-003|UL-010|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F05|F13

**Technical question.** Measure coding/decoder and failure asymmetry when ranks 5-8 use two codewords.

**Baseline.** Equivalent rank with one-codeword profile where valid, or lower-rank matched baseline.

**Treatment.** Release-valid two-codeword transmission.

**Hold constant.** Same total G, power and channel.

**Sweep.** rank 5-8, per-codeword MCS/TBS/RV.

**Primary metrics.** `CW_BLER|TB_goodput|sum_goodput|decoder_time_ms`

**Secondary metrics.** `UCI_owner|HARQ_rounds`

**Required analysis.** Codeword split and layer mapping exact; TB identities independent.

**Hard acceptance.** No codeword may be silently dropped or duplicated.

**Interpretation.** Quantify unequal-MCS and unequal-channel impact per codeword.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_two_codeword.png`

### F16 — Codebook versus non-codebook transmission

**Findings addressed:** `UL-003|UL-007|UL-010|UL-012`  
**Implementability:** `implement_now_after_SRS_authority`  
**Dependencies:** F28-F31

**Technical question.** Compare SRS-driven codebook and non-codebook PUSCH under matched channel information.

**Baseline.** Codebook transmission using valid SRI/TPMI.

**Treatment.** Non-codebook transmission using valid SRS resource indicators.

**Hold constant.** Same channel, rank, power and SRS observation.

**Sweep.** scheme, rank, SRS SNR, mobility.

**Primary metrics.** `effective_SINR|BLER|goodput|precoder_gain_dB`

**Secondary metrics.** `selection_runtime_ms|feedback_bits`

**Required analysis.** Applied matrix digest must originate from measured SRS decision and match TX.

**Hard acceptance.** Stale/mismatched SRS creates no strict transmission when required.

**Interpretation.** Quantify robustness and overhead differences.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_codebook_noncodebook.png`

### F17 — DM-RS additional positions versus Doppler

**Findings addressed:** `UL-002|UL-003|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Complete DM-RS

**Technical question.** Measure channel-tracking benefit and RE overhead of additional DM-RS positions.

**Baseline.** Minimum valid DM-RS density.

**Treatment.** Higher additional-position configurations.

**Hold constant.** Same mapping type, rank, ports, channel paths and SNR.

**Sweep.** Doppler, additionalPosition, mapping type.

**Primary metrics.** `channel_estimation_NMSE|BLER|DMRS_overhead_RE|goodput`

**Secondary metrics.** `interpolation_error|runtime_ms`

**Required analysis.** DM-RS positions/ports exactly match independent table vectors.

**Hard acceptance.** No-noise recovery exact for every valid tuple.

**Interpretation.** At high Doppler, report NMSE/BLER improvement versus overhead; direction is statistical.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_dmrs_doppler.png`

### F18 — DM-RS configuration type versus delay spread

**Findings addressed:** `UL-002|UL-003|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Complete DM-RS

**Technical question.** Compare configuration type 1 and 2 under frequency selectivity.

**Baseline.** Type 1 at matched port/rank.

**Treatment.** Type 2 where valid.

**Hold constant.** Same channel realization, rank, total power and symbol positions.

**Sweep.** delay profile, RMS delay spread, config type.

**Primary metrics.** `channel_estimation_NMSE|BLER|DMRS_RE|goodput`

**Secondary metrics.** `frequency_interpolation_error`

**Required analysis.** Exact RE/port/OCC mapping; no port overwrite.

**Hard acceptance.** Invalid type/rank/port combinations fail before waveform.

**Interpretation.** Quantify frequency-domain estimation trade-off.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_dmrs_delay_spread.png`

### F19 — DM-RS length, OCC and high-rank port support

**Findings addressed:** `UL-002|UL-003|UL-010|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Rel-18 DM-RS tables

**Technical question.** Exercise length-1/2 DM-RS, OCC and logical ports for high-rank PUSCH.

**Baseline.** Length 1 and low rank.

**Treatment.** Length 2 and ranks/ports up to 8 where valid.

**Hold constant.** Same channel and resource allocation.

**Sweep.** DMRSLength, CDM groups, port set, rank.

**Primary metrics.** `port_leakage_dB|channel_estimation_NMSE|BLER|overhead_RE`

**Secondary metrics.** `condition_number`

**Required analysis.** Requested and applied logical port sets must be identical and valid.

**Hard acceptance.** Cross-port correlation meets independent sequence/OCC expectations.

**Interpretation.** Quantify high-rank estimation robustness and overhead.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_dmrs_high_rank.png`

### F20 — DM-RS port orthogonality and leakage

**Findings addressed:** `UL-002|UL-010|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F19|MU receiver

**Technical question.** Directly measure inter-port leakage under ideal and impaired synchronization.

**Baseline.** Ideal timing/CFO.

**Treatment.** Controlled timing/CFO and multi-UE shared-resource cases.

**Hold constant.** Same DM-RS sequences and power.

**Sweep.** port pairs, CFO, timing offset, UE identities.

**Primary metrics.** `cross_correlation|leakage_dB|channel_estimation_bias|BLER`

**Secondary metrics.** `false_UE_association`

**Required analysis.** Ideal independent vectors must match exact correlations.

**Hard acceptance.** Wrong port/identity must not decode another UE payload.

**Interpretation.** Quantify orthogonality loss with impairments.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_dmrs_port_leakage.png`

### F21 — PT-RS density versus phase noise

**Findings addressed:** `UL-003|UL-009|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Complete PT-RS

**Technical question.** Measure CPE tracking, EVM and BLER for valid PT-RS densities under phase noise.

**Baseline.** PT-RS disabled.

**Treatment.** Valid time/frequency density and port association.

**Hold constant.** Same phase-noise realization and received samples.

**Sweep.** phase-noise profile, SCS, modulation, density.

**Primary metrics.** `CPE_RMSE_deg|EVM_percent|BLER|goodput`

**Secondary metrics.** `PTRS_overhead_RE`

**Required analysis.** Exact PT-RS indices/sequence/port association; before/after CPE recorded.

**Hard acceptance.** Under selected nonzero phase-noise stress, correction must reduce paired CPE RMSE and EVM.

**Interpretation.** Quantify overhead versus robustness and optimum density.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_ptrs_phase_noise.png`

### F22 — PT-RS overhead with negligible phase noise

**Findings addressed:** `UL-009`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F21

**Technical question.** Measure whether unnecessary PT-RS reduces data capacity without receiver benefit.

**Baseline.** PT-RS disabled, phase noise off.

**Treatment.** PT-RS enabled, phase noise off.

**Hold constant.** Same grant, TB adaptation policy and noise samples.

**Sweep.** density, modulation, rank.

**Primary metrics.** `goodput|GULSCH|EVM|BLER`

**Secondary metrics.** `runtime_ms`

**Required analysis.** CPE estimate remains near zero; exact overhead accounting.

**Hard acceptance.** No claim that PT-RS always improves performance.

**Interpretation.** Report pure overhead and any estimation noise penalty.

**Minimum campaign floor.** `8` seeds and `3000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_ptrs_overhead.png`

### F23 — CP-OFDM versus DFT-s-OFDM PAPR

**Findings addressed:** `UL-003|UL-004|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Exact DFT-s-OFDM

**Technical question.** Quantify PAPR and spectral behavior of exact single-layer transform precoding.

**Baseline.** Transform precoding disabled.

**Treatment.** Transform precoding enabled for valid single-layer tuples.

**Hold constant.** Same data symbols, allocation and total energy.

**Sweep.** modulation, NPRB, hopping.

**Primary metrics.** `PAPR_CCDF|mean_power|roundtrip_NMSE|BLER`

**Secondary metrics.** `occupied_bandwidth|runtime_ms`

**Required analysis.** Unitary DFT energy and no-noise round trip are exact.

**Hard acceptance.** Multi-layer transform precoding is rejected.

**Interpretation.** Report PAPR distribution; selected configurations should show expected DFT-s-OFDM reduction without hardcoding a universal dB gain.

**Minimum campaign floor.** `20` seeds and `1` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_transform_papr.png`

### F24 — Transform precoding under PA backoff/clipping

**Findings addressed:** `UL-004`  
**Implementability:** `implement_after_RF_PA_model`  
**Dependencies:** F23|RF phase

**Technical question.** Measure how lower PAPR changes EVM/BLER at finite PA backoff.

**Baseline.** CP-OFDM through the same normalized PA model.

**Treatment.** DFT-s-OFDM through the same PA model.

**Hold constant.** Same input average power, symbols, channel and noise.

**Sweep.** PA backoff, clipping level, modulation, NPRB.

**Primary metrics.** `EVM|BLER|ACLR_proxy|clipping_probability|goodput`

**Secondary metrics.** `PAPR|mean_output_power`

**Required analysis.** PA model and scaling reference points identical; linear-PA baseline reconciles.

**Hard acceptance.** No-noise linear PA gives identical decoded bits.

**Interpretation.** Quantify backoff saving and nonlinear robustness.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_pa_backoff.png`

### F25 — Frequency hopping null test in AWGN

**Findings addressed:** `UL-005|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Complete hopping

**Technical question.** Prove that hopping only remaps resources and does not create artificial gain in flat AWGN.

**Baseline.** No hopping.

**Treatment.** Intra-slot or inter-slot hopping.

**Hold constant.** Same total resources, data, noise samples and channel gain.

**Sweep.** hopping mode, offset, modulation.

**Primary metrics.** `BLER_difference|EVM_difference|energy_error|resource_digest`

**Secondary metrics.** `runtime_ms`

**Required analysis.** Exact hop maps match independent oracle; paired performance difference is within numerical/statistical tolerance.

**Hard acceptance.** Any large AWGN gain indicates scaling or noise inconsistency.

**Interpretation.** Use as a null experiment before diversity claims.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_hopping_awgn_null.png`

### F26 — Frequency-hopping diversity in selective fading

**Findings addressed:** `UL-005`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F25|channel models

**Technical question.** Quantify frequency diversity under TDL/CDL channels.

**Baseline.** No hopping.

**Treatment.** Intra-slot/inter-slot hopping.

**Hold constant.** Paired channel paths/noise and same total resources.

**Sweep.** delay profile, hop offset, allocation width, SNR.

**Primary metrics.** `BLER|effective_SINR|frequency_diversity_gain_dB|goodput`

**Secondary metrics.** `channel_estimation_NMSE`

**Required analysis.** Hop-specific DM-RS/PT-RS and receiver extraction exact.

**Hard acceptance.** Performance effects use paired confidence intervals, not single-seed curves.

**Interpretation.** Report when hopping helps, is neutral, or hurts due to estimation/overhead.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_hopping_diversity.png`

### F27 — Hopping, repetition and HARQ interaction

**Findings addressed:** `UL-005|UL-008`  
**Implementability:** `implement_now_after_HARQ`  
**Dependencies:** F26|F40

**Technical question.** Analyze whether repeated transmissions sample independent frequency regions and combine correctly.

**Baseline.** Repetition/HARQ without hopping.

**Treatment.** Repetition/HARQ with valid hopping.

**Hold constant.** Same TB identity, RV sequence and channel process.

**Sweep.** repetition type/count, hop mode, RV sequence.

**Primary metrics.** `post_combining_BLER|latency|diversity_order|goodput`

**Secondary metrics.** `softbuffer_digest`

**Required analysis.** Each retransmission’s bit positions and resource digest are preserved.

**Hard acceptance.** Combining never mixes different TB identities or codeword layouts.

**Interpretation.** Quantify latency/reliability gain.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_hopping_harq.png`

### F28 — SRS SNR versus RI/SRI/TPMI accuracy

**Findings addressed:** `UL-007|UL-010|UL-012`  
**Implementability:** `implement_now_after_SRS_authority`  
**Dependencies:** SRS estimator and PUSCH decision object

**Technical question.** Measure decision accuracy and PUSCH loss as SRS quality varies.

**Baseline.** Perfect channel decision.

**Treatment.** Measured SRS at swept SNR.

**Hold constant.** Same underlying channel and candidate codebook.

**Sweep.** SRS SNR, rank, codebook, antenna count.

**Primary metrics.** `RI_accuracy|TPMI_accuracy|precoder_loss_dB|PUSCH_BLER`

**Secondary metrics.** `SRS_detection_probability|runtime_ms`

**Required analysis.** Decision and application digests match; configured TPMI fallback forbidden in strict path.

**Hard acceptance.** Stale/undetected SRS is explicit, not replaced by ideal CSI.

**Interpretation.** Generate accuracy and downstream BLER curves.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_srs_snr_tpmi.png`

### F29 — SRS age versus mobility

**Findings addressed:** `UL-007|UL-010`  
**Implementability:** `implement_now_after_SRS_authority`  
**Dependencies:** F28|mobility channel

**Technical question.** Quantify precoder aging at different Doppler/mobility.

**Baseline.** Fresh SRS decision.

**Treatment.** Reuse decision after increasing age.

**Hold constant.** Same channel trajectory and noise seed.

**Sweep.** age slots, Doppler, SRS periodicity.

**Primary metrics.** `precoder_loss_dB|effective_SINR|BLER|goodput`

**Secondary metrics.** `decision_invalid_rate`

**Required analysis.** Age and configuration epoch exported; hard max-age enforced.

**Hard acceptance.** Decisions beyond validity create no strict transmission or trigger re-sounding policy.

**Interpretation.** Estimate safe sounding periodicity.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_srs_age_mobility.png`

### F30 — SRS bandwidth/resource coverage impact

**Findings addressed:** `UL-007`  
**Implementability:** `implement_now_after_SRS_authority`  
**Dependencies:** SRS coverage functions

**Technical question.** Measure precoding and link-adaptation loss when SRS samples only part of the scheduled PUSCH band.

**Baseline.** Full-band sounding.

**Treatment.** Partial-band/narrow sounding with valid association.

**Hold constant.** Same channel and PUSCH allocation.

**Sweep.** SRS bandwidth, comb, hopping, PUSCH bandwidth.

**Primary metrics.** `channel_extrapolation_NMSE|precoder_loss_dB|BLER|goodput`

**Secondary metrics.** `SRS_overhead_RE`

**Required analysis.** Coverage and association are exact and exported.

**Hard acceptance.** No full-band claim from partial-band observations.

**Interpretation.** Quantify bandwidth/overhead versus accuracy.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_srs_bandwidth.png`

### F31 — Perfect CSI, measured SRS and stale/configured precoder comparison

**Findings addressed:** `UL-007|UL-012`  
**Implementability:** `implement_now_after_SRS_authority`  
**Dependencies:** F28-F30

**Technical question.** Create a bounded upper/lower benchmark for precoding.

**Baseline.** Perfect-CSI oracle precoder.

**Treatment.** Fresh measured SRS, stale SRS and fixed configured matrix.

**Hold constant.** Same channel/noise and TX power.

**Sweep.** decision source, SRS quality, age.

**Primary metrics.** `effective_SINR|BLER|goodput|precoder_loss_dB`

**Secondary metrics.** `selection_runtime_ms`

**Required analysis.** Only perfect CSI is labelled oracle; fixed configured matrix is an ablation, never strict evidence.

**Hard acceptance.** Applied source and digest recorded.

**Interpretation.** Measure implementation gap to oracle and harm from shortcuts.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_precoder_source.png`

### F32 — Reciprocity/calibration-error sensitivity

**Findings addressed:** `UL-007|UL-010`  
**Implementability:** `implement_after_RF_calibration_model`  
**Dependencies:** F28|RF phase

**Technical question.** Measure impact of UL antenna-chain calibration error on SRS-derived precoding.

**Baseline.** Perfectly calibrated channel observation.

**Treatment.** Amplitude/phase calibration errors.

**Hold constant.** Same propagation channel and SRS noise.

**Sweep.** phase error, gain error, antenna count.

**Primary metrics.** `precoder_loss_dB|BLER|EVM|TPMI_change_rate`

**Secondary metrics.** `effective_SINR`

**Required analysis.** Calibration error is an explicit impairment with provenance.

**Hard acceptance.** No hidden ideal reciprocity when impairment enabled.

**Interpretation.** Quantify calibration accuracy requirement.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_reciprocity_error.png`

### F33 — Open-loop PUSCH power-control impact

**Findings addressed:** `UL-011|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Exact power ledger

**Technical question.** Verify exact power equation and pathloss compensation across bandwidth/numerology/pathloss.

**Baseline.** Reference P0/alpha configuration.

**Treatment.** Sweep P0, alpha, M_PUSCH, numerology and pathloss.

**Hold constant.** Same waveform symbols and channel pathloss.

**Sweep.** P0, alpha, pathloss, mu, MRB, DeltaTF.

**Primary metrics.** `requested_power_dBm|applied_power_dBm|received_power_dBm|power_error_dB`

**Secondary metrics.** `BLER|energy_per_bit`

**Required analysis.** Independent power equation matches before clipping and actual waveform RMS power.

**Hard acceptance.** Configured SNR cannot substitute for measured pathloss.

**Interpretation.** Quantify cell-center/edge power and BLER.

**Minimum campaign floor.** `1` seeds and `1` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_open_loop_power.png`

### F34 — Closed-loop TPC convergence

**Findings addressed:** `UL-011|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Power-control state machine

**Technical question.** Measure convergence and stability of accumulated/absolute TPC loops.

**Baseline.** Open-loop only.

**Treatment.** Closed-loop TPC with known command sequence and gNB target error.

**Hold constant.** Same pathloss trajectory and waveform.

**Sweep.** TPC mode, command delay, step sequence, measurement noise.

**Primary metrics.** `target_error_dB|convergence_slots|overshoot_dB|steady_state_RMSE`

**Secondary metrics.** `BLER|tx_energy`

**Required analysis.** State transition matches independent recurrence exactly.

**Hard acceptance.** No per-point reset or hidden clipping except P_CMAX.

**Interpretation.** Report stability and convergence speed.

**Minimum campaign floor.** `20` seeds and `200` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_power_control_convergence.png`

### F35 — P_CMAX clipping and saturation

**Findings addressed:** `UL-011`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** F33-F34

**Technical question.** Quantify cell-edge behavior when requested power exceeds UE limit.

**Baseline.** Unsaturated pathloss.

**Treatment.** Pathloss/PRB/rank causing P_CMAX clipping.

**Hold constant.** Same P0/alpha and target received power.

**Sweep.** P_CMAX, pathloss, MRB, rank.

**Primary metrics.** `clipping_probability|power_deficit_dB|BLER|goodput`

**Secondary metrics.** `tx_energy|TPC_windup`

**Required analysis.** Applied power equals min(requested, P_CMAX) with exact waveform reconciliation.

**Hard acceptance.** TPC state must not fabricate achieved power.

**Interpretation.** Show coverage loss and saturation region.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_power_clipping.png`

### F36 — Pathloss-measurement noise in power control

**Findings addressed:** `UL-011`  
**Implementability:** `implement_after_measurement_filter`  
**Dependencies:** F33-F34

**Technical question.** Measure sensitivity to noisy/stale reference-signal pathloss estimates.

**Baseline.** Exact measured pathloss.

**Treatment.** Noisy or aged pathloss estimate.

**Hold constant.** Same actual pathloss trajectory.

**Sweep.** measurement error, age, filtering.

**Primary metrics.** `power_error_dB|BLER|interference_power|tx_energy`

**Secondary metrics.** `convergence_slots`

**Required analysis.** Estimate provenance/age exported; configured SNR fallback forbidden.

**Hard acceptance.** Filter behavior deterministic for fixed observations.

**Interpretation.** Quantify required measurement quality.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_pathloss_error.png`

### F37 — Near-far and inter-cell power externality

**Findings addressed:** `UL-010|UL-011`  
**Implementability:** `implement_after_multiuser_channel`  
**Dependencies:** F33-F36|MU

**Technical question.** Analyze whether power control balances desired reception without excessive interference.

**Baseline.** Single UE or equal pathloss.

**Treatment.** Near/far UEs and inter-cell interferer.

**Hold constant.** Same traffic and scheduler allocation.

**Sweep.** pathloss imbalance, alpha, TPC target, power cap.

**Primary metrics.** `per_UE_BLER|per_UE_SINR|Jain_fairness|interference_power`

**Secondary metrics.** `sum_goodput|tx_energy`

**Required analysis.** Per-UE waveform powers and channel gains independently reconciled.

**Hard acceptance.** No shared scalar noise/interference shortcut.

**Interpretation.** Quantify fairness and interference trade-off.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_near_far.png`

### F38 — ZF, MMSE and IRC receiver impact

**Findings addressed:** `UL-010|UL-011|UL-012`  
**Implementability:** `implement_now_after_covariance`  
**Dependencies:** Complete receiver

**Technical question.** Compare receiver algorithms under noise, spatial correlation and interference.

**Baseline.** MMSE with valid noise estimate.

**Treatment.** ZF and IRC with valid covariance.

**Hold constant.** Same received grid/channel estimate/noise samples.

**Sweep.** receiver, rank, condition number, interferers.

**Primary metrics.** `per_layer_SINR|BLER|EVM|goodput`

**Secondary metrics.** `runtime_ms|memory_bytes`

**Required analysis.** IRC requires finite PSD covariance and may not silently fall back.

**Hard acceptance.** No-interference IRC/MMSE equivalence is a null check; ZF instability is reported.

**Interpretation.** Quantify receiver gain and complexity.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_receiver_comparison.png`

### F39 — Interference-covariance quality and age

**Findings addressed:** `UL-010|UL-011`  
**Implementability:** `implement_now_after_covariance`  
**Dependencies:** F38

**Technical question.** Measure IRC degradation from stale, undersampled or biased covariance.

**Baseline.** Fresh covariance from correct resources.

**Treatment.** Aged, low-sample or mismatched covariance.

**Hold constant.** Same received waveform.

**Sweep.** age, sample count, diagonal loading, mismatch.

**Primary metrics.** `SINR_loss_dB|BLER|PSD_min_eigenvalue|condition_number`

**Secondary metrics.** `runtime_ms`

**Required analysis.** Invalid covariance is rejected; no MMSE fallback in strict IRC.

**Hard acceptance.** Covariance source, sample count and age recorded.

**Interpretation.** Determine minimum covariance quality.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_covariance_quality.png`

### F40 — HARQ RV and soft-combining gain

**Findings addressed:** `UL-003|UL-010|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** HARQ context

**Technical question.** Verify bit-position-aware combining and quantify reliability over RV sequences.

**Baseline.** Single transmission RV0.

**Treatment.** RV sequences such as 0-2-3-1 with exact rate recovery.

**Hold constant.** Same TB identity, channel process and noise seeds.

**Sweep.** RV sequence, rounds, codeword, SNR.

**Primary metrics.** `BLER_by_round|combining_gain_dB|success_round|softbuffer_digest`

**Secondary metrics.** `latency|decoder_iterations`

**Required analysis.** Independent rate-matching positions match; no combining across TB/layout mismatch.

**Hard acceptance.** No-noise retransmission identity exact; injected wrong RV detected.

**Interpretation.** Quantify reliability and latency gain.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_harq_combining.png`

### F41 — HARQ latency-throughput trade-off

**Findings addressed:** `UL-008|UL-010`  
**Implementability:** `implement_after_timing_engine`  
**Dependencies:** F40|MAC timing

**Technical question.** Measure retransmission budget, deadline misses and goodput.

**Baseline.** No retransmissions.

**Treatment.** 1-3 allowed retransmissions with selected RV policy.

**Hold constant.** Same arrivals, channel traces and scheduler resources.

**Sweep.** max rounds, RTT/K2, deadline, MCS.

**Primary metrics.** `goodput|packet_latency|deadline_miss_rate|mean_rounds`

**Secondary metrics.** `energy_per_delivered_bit`

**Required analysis.** HARQ timing and process ownership exact.

**Hard acceptance.** No duplicate delivery after late success.

**Interpretation.** Identify operating point for reliability versus latency.

**Minimum campaign floor.** `20` seeds and `10000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_harq_latency.png`

### F42 — Two-UE MU-PUSCH on shared PRBs

**Findings addressed:** `UL-010|UL-011|UL-012`  
**Implementability:** `implement_after_multiuser_channel`  
**Dependencies:** F20|F37-F39

**Technical question.** Validate UE identity separation, DM-RS orthogonality, covariance and multi-user detection.

**Baseline.** Orthogonal PRB allocation.

**Treatment.** Shared PRBs with valid separate DM-RS resources and spatial channels.

**Hold constant.** Same total bandwidth and per-UE offered load.

**Sweep.** power imbalance, spatial correlation, rank, receiver.

**Primary metrics.** `per_UE_BLER|per_UE_SINR|sum_goodput|fairness`

**Secondary metrics.** `cross_talk|runtime_ms`

**Required analysis.** Wrong UE/DM-RS identity does not decode; per-UE resource/power ledger exact.

**Hard acceptance.** No oracle separation labels in receiver.

**Interpretation.** Quantify MU gain and degradation regions.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_mu_pusch.png`

### F43 — Receiver-measured SINR calibration

**Findings addressed:** `UL-011|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Receiver instrumentation

**Technical question.** Validate reported post-equalization SINR against analytical AWGN and empirical EVM/BLER.

**Baseline.** Analytical AWGN SNR at receiver reference point.

**Treatment.** Receiver-derived per-layer SINR.

**Hold constant.** Same waveform/noise realization and known channel.

**Sweep.** SNR, rank, receiver, modulation.

**Primary metrics.** `SINR_error_dB|EVM_predicted_SINR_error_dB|BLER_prediction_error`

**Secondary metrics.** `sample_count|confidence_interval`

**Required analysis.** Every strict result has finite receiver-derived SINR and sample count.

**Hard acceptance.** Removing measured SINR must fail the run.

**Interpretation.** Quantify estimator bias across channels and receivers.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_sinr_calibration.png`

### F44 — No-signal, wrong-identity and false-decode robustness

**Findings addressed:** `UL-001|UL-002|UL-006|UL-010|UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Negative matrix

**Technical question.** Measure false alarm and reject behavior for absent or mismatched PUSCH.

**Baseline.** Valid signal.

**Treatment.** No signal, wrong RNTI/scrambling ID, wrong DM-RS port, wrong slot, wrong BWP.

**Hold constant.** Same receiver search space and noise.

**Sweep.** fault type, SNR/noise power, repetitions.

**Primary metrics.** `false_decode_rate|false_CRC_pass|assignment_reject_rate`

**Secondary metrics.** `runtime_ms`

**Required analysis.** Invalid assignment generates no TX; no-signal false-decoding campaign meets configured bound.

**Hard acceptance.** Receiver never uses transmitted bits or oracle indices not available in procedure.

**Interpretation.** Quantify detection integrity.

**Minimum campaign floor.** `50` seeds and `20000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_false_decode.png`

### F45 — CFO sensitivity

**Findings addressed:** `UL-003|UL-009|UL-011`  
**Implementability:** `implement_after_RF_CFO`  
**Dependencies:** RF phase dependency

**Technical question.** Measure timing/channel/phase tracking under carrier-frequency offset.

**Baseline.** CFO=0.

**Treatment.** Swept CFO normalized by SCS.

**Hold constant.** Same channel, noise, synchronization policy.

**Sweep.** CFO Hz, SCS, PTRS state, modulation.

**Primary metrics.** `EVM|BLER|CPE_RMSE|channel_estimation_NMSE`

**Secondary metrics.** `residual_CFO_Hz`

**Required analysis.** CFO is applied in waveform time domain and receiver estimate has provenance.

**Hard acceptance.** No hidden perfect correction unless oracle profile.

**Interpretation.** Report tolerable CFO and PT-RS interaction.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_cfo.png`

### F46 — Timing-offset sensitivity

**Findings addressed:** `UL-002|UL-003|UL-011`  
**Implementability:** `implement_after_sync_receiver`  
**Dependencies:** Timing estimator

**Technical question.** Measure acquisition and residual timing error effects.

**Baseline.** Zero timing offset.

**Treatment.** Offsets within/outside CP and residual estimator errors.

**Hold constant.** Same channel/noise and synchronization method.

**Sweep.** offset samples, delay spread, SCS.

**Primary metrics.** `timing_estimate_error|EVM|BLER|DMRS_leakage`

**Secondary metrics.** `false_peak_rate`

**Required analysis.** Offset is applied to waveform; receiver may not consume true offset in strict mode.

**Hard acceptance.** No-noise within-CP cases recover after valid estimation.

**Interpretation.** Quantify timing margin.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_timing_offset.png`

### F47 — Phase-noise and PT-RS interaction across SCS

**Findings addressed:** `UL-009`  
**Implementability:** `implement_after_RF_phase_noise`  
**Dependencies:** F21|F45

**Technical question.** Measure phase-noise robustness jointly over SCS, modulation and PT-RS density.

**Baseline.** No/low phase noise without PT-RS.

**Treatment.** Phase noise with PT-RS off/on and density sweep.

**Hold constant.** Same oscillator realization scaled per profile.

**Sweep.** SCS, phase-noise profile, modulation, density.

**Primary metrics.** `CPE_RMSE|EVM|BLER|goodput`

**Secondary metrics.** `PTRS_overhead_RE`

**Required analysis.** Phase-noise model and PT-RS correction reference points explicit.

**Hard acceptance.** Selected stress cases must show paired CPE/EVM improvement with valid PT-RS.

**Interpretation.** Build operating-region map.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_ptrs_scs_phase_noise.png`

### F48 — Numerology and mobility interaction

**Findings addressed:** `UL-003|UL-005|UL-009`  
**Implementability:** `implement_after_frame_phase`  
**Dependencies:** Frame/grid dependency

**Technical question.** Measure PUSCH performance as SCS and Doppler change.

**Baseline.** 30 kHz SCS at low mobility.

**Treatment.** 15/60/120 kHz valid profiles and mobility sweep.

**Hold constant.** Matched occupied bandwidth and channel path powers where feasible.

**Sweep.** SCS, Doppler, DMRS density, PTRS, hopping.

**Primary metrics.** `BLER|channel_estimation_NMSE|CPE_RMSE|latency`

**Secondary metrics.** `goodput|overhead_fraction`

**Required analysis.** Uses canonical frame/grid engine; no local numerology assumptions.

**Hard acceptance.** All selected tuples pass no-noise mapping first.

**Interpretation.** Quantify robustness/latency/overhead trade-offs.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_numerology_mobility.png`

### F49 — Runtime and memory scaling

**Findings addressed:** `UL-003|UL-010`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** Instrumentation only

**Technical question.** Measure computational cost of exact implementation.

**Baseline.** Rank-1 small grant.

**Treatment.** Sweep PRBs, rank, codewords, UCI load, receiver and LDPC iterations.

**Hold constant.** Same hardware/toolchain, warm-up and measurement protocol.

**Sweep.** NPRB, rank, codewords, receiver, UCI.

**Primary metrics.** `tx_time_ms|rx_time_ms|peak_memory_bytes|symbols_per_second`

**Secondary metrics.** `decoder_iterations|artifact_size_bytes`

**Required analysis.** Timing excludes first-run JIT warm-up and records MATLAB/toolbox version.

**Hard acceptance.** No performance pass/fail hides functional failure.

**Interpretation.** Identify bottlenecks and regression thresholds.

**Minimum campaign floor.** `5` seeds and `100` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_runtime_scaling.png`

### F50 — Seed sensitivity and reproducibility

**Findings addressed:** `UL-012`  
**Implementability:** `implement_now_in_pusch_phase`  
**Dependencies:** RNG stream discipline

**Technical question.** Prove deterministic replay and quantify uncertainty across random seeds.

**Baseline.** Same seed repeated.

**Treatment.** Independent seed set.

**Hold constant.** Identical configuration and toolchain.

**Sweep.** seed, parallel/serial execution, channel/noise RNG stream.

**Primary metrics.** `artifact_digest_match|BLER_variance|effect_CI_width`

**Secondary metrics.** `runtime_variance`

**Required analysis.** Same-seed raw artifacts and metrics must match exactly within documented floating tolerance.

**Hard acceptance.** Parallel merge order cannot change counts or random streams.

**Interpretation.** Report required seed count for stable conclusions.

**Minimum campaign floor.** `12` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_seed_reproducibility.png`

### F51 — Feature-interaction factorial study

**Findings addressed:** `UL-001|UL-002|UL-004|UL-005|UL-009`  
**Implementability:** `implement_after_core_features`  
**Dependencies:** F01|F17|F21|F23|F26

**Technical question.** Detect interactions among UCI load, DM-RS density, PT-RS, transform precoding and hopping.

**Baseline.** All selected features off/minimal where valid.

**Treatment.** 2-level fractional/full factorial combinations.

**Hold constant.** Same base grant, channel paths and paired seeds.

**Sweep.** UCI, DMRS, PTRS, transform precoding, hopping, phase noise, Doppler.

**Primary metrics.** `BLER|goodput|EVM|PAPR|overhead_fraction`

**Secondary metrics.** `interaction_effects|runtime_ms`

**Required analysis.** Every combination is validated for normative compatibility before run.

**Hard acceptance.** Invalid combinations are negative tests, not silently altered.

**Interpretation.** Fit main effects and two-way interactions with confidence intervals.

**Minimum campaign floor.** `20` seeds and `5000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_feature_interactions.png`

### F52 — End-to-end technical deployment scenarios

**Findings addressed:** `UL-001|UL-002|UL-003|UL-004|UL-005|UL-007|UL-008|UL-009|UL-010|UL-011|UL-012`  
**Implementability:** `implement_after_all_core_items`  
**Dependencies:** All prior families

**Technical question.** Exercise coherent PUSCH profiles rather than isolated kernels.

**Baseline.** Ideal AWGN calibration profile.

**Treatment.** Cell-center, cell-edge, high-mobility, phase-noise, high-rank, CG and MU profiles.

**Hold constant.** Pinned scenario definitions and seed lists.

**Sweep.** scenario profile.

**Primary metrics.** `BLER|goodput|latency|tx_power|per_layer_SINR|EVM`

**Secondary metrics.** `PAPR|runtime|artifact completeness`

**Required analysis.** All profile prerequisites pass and every metric is production-derived.

**Hard acceptance.** No aggregate pass if a required scenario is blocked or incomplete.

**Interpretation.** Provide final technical capability/impact summary without marketing claims.

**Minimum campaign floor.** `20` seeds and `10000` trials per operating point, unless the experiment row has a stricter setting.

**Required figures.** `pusch_impact_scenario_summary.png|pusch_impact_effect_forest.png`


## B4. Required implementation instrumentation

Modify the real production path so each trial can export, at minimum:

1. exact decoded assignment source and applied field digests;
2. exact RE ownership and coded-bit ownership;
3. UL-SCH and each UCI coded-bit budget;
4. per-codeword TBS, base graph, code blocks, lifting size, filler bits, rate-matching positions and RV;
5. requested and applied DM-RS/PT-RS ports, symbols, RE indices and sequence digests;
6. transform-precoding DFT block sizes, energy and round-trip metrics;
7. hop-specific PRB/RE maps and channel estimates;
8. SRS measurement age, SNR, bandwidth, covariance, RI/SRI/TPMI and selection/application digests;
9. requested/applied/measured transmit power at named reference points;
10. receiver algorithm, channel/noise/covariance provenance, per-layer SINR, EVM, CPE and channel-estimation NMSE;
11. HARQ TB identity, codeword layout, RV, rate-recovery positions and soft-buffer digest;
12. TX/RX runtime and peak memory under a recorded hardware/toolchain context.

A metric that cannot be traced to production samples must be omitted and must cause the corresponding experiment to fail or be explicitly blocked. Do not fill it from configuration or an expected model value.

## B5. Required impact CSVs

Generate every CSV listed in `desired_pusch_impact_csv_contract.csv`. The most important are:

```text
pusch_impact_raw_trials.csv
pusch_impact_operating_points.csv
pusch_impact_pairwise_effects.csv
pusch_impact_rule_evaluation.csv
pusch_impact_uci.csv
pusch_impact_dmrs_ptrs.csv
pusch_impact_transform_hopping.csv
pusch_impact_srs_precoding.csv
pusch_impact_power_control.csv
pusch_impact_harq_receiver.csv
pusch_impact_grant_cg_ra.csv
pusch_impact_runtime.csv
pusch_impact_interactions.csv
pusch_impact_summary.csv
pusch_impact_image_semantic_audit.csv
```

The phase runner must verify:

- all `705` mandatory experiment IDs have output rows;
- every hard rule in `pusch_impact_acceptance_rules.csv` has an evaluation row and passes;
- statistical rows include finite sample count, confidence interval, raw/adjusted p-value and effect size where applicable;
- no mandatory point is incomplete or blocked;
- source hashes tie every summary and figure to the underlying CSVs;
- expected input/vector files are not copied into the production result directory.

## B6. Required impact images

Generate all `26` images listed in `desired_pusch_impact_image_contract.csv`. Every figure must be created from production CSVs and audited from the MATLAB figure object before saving.

The image audit must record:

```text
actual title
actual x/y labels
axes count
series count
finite-point count
source CSV names and combined SHA-256
PNG SHA-256
width and height
```

Do not mark an image correct merely because Pillow can decode it. The semantic audit and source hash must also pass.

## B7. Required MATLAB entry point

Implement:

```matlab
summary = sixgr.phy.ul.pusch.analysis.runPUSCHImpactValidation( ...
    'ExperimentMatrix', fullfile(vectorRoot,'pusch_impact_experiment_matrix.csv'), ...
    'PairingContract', fullfile(vectorRoot,'pusch_impact_pairing_contract.csv'), ...
    'AcceptanceRules', fullfile(vectorRoot,'pusch_impact_acceptance_rules.csv'), ...
    'AnalyticalFloor', fullfile(vectorRoot,'expected_pusch_impact_analytical_floor.csv'), ...
    'OutputDir', outputDir, ...
    'Tier', 'full', ...
    'Strict', true);
```

The runner must:

1. validate the complete matrix and all dependencies;
2. execute smoke cases first;
3. execute full cases only after smoke passes;
4. preserve paired RNG streams;
5. export raw trials incrementally without changing scientific state;
6. aggregate operating points and effects;
7. evaluate every rule;
8. generate and semantically audit all figures;
9. write a manifest with source/toolchain/input/output hashes;
10. return `Passed=true` only when every mandatory correctness and impact condition is satisfied.

## B8. Commands Codex must execute

```bash
python tests/vectors/pusch/verify_pusch_vector_pack.py
python tests/vectors/pusch/verify_pusch_impact_pack.py
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PUSCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.ul.pusch.runPUSCHPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','pusch'),'OutputDir',fullfile(pwd,'artifacts','pusch_ulsch_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.ul.pusch.analysis.runPUSCHImpactValidation('ExperimentMatrix',fullfile(pwd,'tests','vectors','pusch','pusch_impact_experiment_matrix.csv'),'PairingContract',fullfile(pwd,'tests','vectors','pusch','pusch_impact_pairing_contract.csv'),'AcceptanceRules',fullfile(pwd,'tests','vectors','pusch','pusch_impact_acceptance_rules.csv'),'AnalyticalFloor',fullfile(pwd,'tests','vectors','pusch','expected_pusch_impact_analytical_floor.csv'),'OutputDir',fullfile(pwd,'artifacts','pusch_ulsch_impact'),'Tier','full','Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/pusch/verify_pusch_artifacts.py artifacts/pusch_ulsch_phase
python tests/vectors/pusch/verify_pusch_impact_artifacts.py artifacts/pusch_ulsch_impact
```

## B9. Additional prohibited shortcuts

Do not:

1. calculate a treatment effect from unpaired seeds when a paired design is specified;
2. replace receiver-derived SINR, EVM, CPE, NMSE, power or covariance with configured/expected values;
3. cherry-pick an SNR, seed or channel point after seeing results;
4. drop failed or incomplete points from plots or summary statistics;
5. treat a non-significant result as proof of equality without an equivalence margin;
6. treat a statistically significant but negligible effect as technically important without effect size;
7. tune MCS/TBS, decoder iterations, beta offsets, DM-RS density, PT-RS density or receiver per seed;
8. compare different payloads, channel realizations or noise samples while labelling the result paired;
9. use perfect CSI except in the explicitly labelled oracle benchmark;
10. use transmitted bits, exact channel or true impairment values in a strict receiver path;
11. use a fixed configured TPMI as measured-SRS evidence;
12. allow an invalid configuration to be silently converted into a nearby valid treatment;
13. copy analytical-floor or expected-vector CSVs into actual result artifacts;
14. generate plots from synthetic/example values while production experiments are blocked;
15. report `COMPLETE` when any hard rule, mandatory experiment, required CSV, required PNG or verifier is missing/failed/blocked.

## B10. Expanded definition of done

Part B is complete only when:

- all `52` impact families are represented;
- all `705` experiment definitions execute successfully;
- all `70` rule definitions have result rows;
- every hard rule passes;
- every statistical or diagnostic rule has sufficient samples and a valid conclusion, including `inconclusive` where scientifically appropriate;
- all `16` impact CSVs and `26` impact PNGs pass the fail-closed verifier;
- the exact PUSCH correctness phase still passes;
- no current regression test is weakened;
- Codex reports exact commands, test counts, experiment counts, incomplete counts, failed rules, effect summaries, CSV row counts, image dimensions/hashes, runtime and remaining dependencies.

Do not return only code. Execute the full workflow on the pinned MATLAB/5G Toolbox release and keep repairing until the conditions above are met.
