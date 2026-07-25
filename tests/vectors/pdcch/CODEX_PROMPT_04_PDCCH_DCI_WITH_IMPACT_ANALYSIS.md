# Codex implementation prompt 04 — PDCCH and DCI complete MATLAB PHY chain with impact analysis

You are working directly in the root of the **6GR MATLAB simulator** repository.

This is an **implementation and execution task**. It is not an audit-only task, a plan, a documentation exercise, a claim-contract exercise, or a request to add metadata around the existing shortcuts.

Your job is to modify the real MATLAB source and deliver a release-pinned, waveform-executed PDCCH/DCI chain that:

1. constructs every selected DCI payload from a complete contextual schema rather than fixed widths;
2. performs exact DCI size alignment for the monitored format set;
3. attaches CRC24C, applies the correct RNTI mask, Polar-encodes and rate-matches the payload;
4. performs PDCCH physical scrambling, QPSK modulation, DM-RS generation, CORESET REG/CCE mapping and waveform mapping;
5. derives every search-space monitoring occasion and every configured candidate at AL 1, 2, 4, 8 and 16;
6. performs actual blind candidate monitoring without oracle CCE indices or a known-location fallback;
7. supports exact Type0-PDCCH CSS derivation across the selected Release-18 table matrix;
8. carries serving-cell, component-carrier, BWP, CORESET, search-space, RNTI, TCI/QCL and configuration-epoch identity end to end;
9. emits a typed decoded-DCI event only after CRC, RNTI, search-space, candidate, format, size and semantic checks pass;
10. makes that decoded event plus installed RRC/MAC state the sole dynamic connected-mode authority for PDSCH/PUSCH assignments;
11. executes the mandatory MATLAB tests and controlled impact experiments;
12. generates every contracted CSV and PNG from the production path and passes the supplied Python verifiers.

Do not return only a plan. Do not stop after creating classes, schemas, wrappers, test stubs or exporters. Do not report `COMPLETE` while any mandatory MATLAB test is unexecuted, failed, skipped or blocked; while any strict blind run uses a known location; while any required artifact is missing; or while either verifier returns nonzero.

---

## 1. Exact scope

Implement the complete selected PDCCH/DCI technical area:

- exact contextual DCI formats 0_0, 0_1, 1_0 and 1_1;
- a schema architecture capable of adding 0_2, 0_3, 1_2 and 1_3 without another hard-coded layout;
- DCI field presence, width, ordering, value range and semantic interpretation;
- DCI size alignment over the actual monitored format-size set;
- CRC24C and RNTI masking;
- Polar coding and PDCCH rate matching;
- physical scrambling and QPSK;
- PDCCH DM-RS sequence and RE mapping;
- CORESET frequency resources, duration, REG numbering, REG bundles, CCE mapping, interleaving, shift index and precoder granularity;
- CSS and USS search-space configuration, monitoring occasions and candidate enumeration;
- blind monitoring across configured formats, sizes, RNTIs, aggregation levels and candidates;
- Type0/Type0A/Type1/Type2/Type3 and USS ownership required by the selected format/RNTI matrix;
- Type0 CORESET0/SearchSpace0 derivation from MIB `pdcch-ConfigSIB1` and the selected-release tables;
- synchronized calibration as a separate profile, never as a fallback for blind strict mode;
- BWP switching, cross-carrier scheduling and carrier-indicator context for selected 0_1/1_1 procedures;
- PDCCH TCI/QCL/beam monitoring state and bounded beam switch/failure/recovery tests;
- immutable decoded-DCI events and downstream grant materialization;
- statistical missed-detection and false-alarm campaigns;
- deterministic CSV/PNG evidence and impact analysis.

Do not spend this phase implementing broad PDSCH/PUSCH coding again. Integrate with their decoded-assignment interfaces. Do not implement WebGUI, authentication, protocol marketing claims or generic truth-contract machinery.

---

## 2. Mandatory standards baseline

Pin the implementation and every emitted artifact to:

- **3GPP TS 38.211 V18.8.0**: PDCCH CCE/CORESET definition, REG numbering, interleaved/non-interleaved mapping, scrambling, QPSK, PDCCH DM-RS and RE mapping.
- **3GPP TS 38.212 V18.8.0**: DCI size alignment, formats 0_0/0_1/1_0/1_1, CRC24C attachment and RNTI masking, Polar coding and rate matching.
- **3GPP TS 38.213 V18.8.0**: CSS/USS search spaces, monitoring occasions, candidate enumeration, monitoring limits, Type0-PDCCH CSS and cross-carrier/BWP control procedures.
- **3GPP TS 38.214 V18.8.0**: interpretation of decoded scheduling fields and data-channel resource procedures.
- **3GPP TS 38.331 V18.8.0**: `ControlResourceSet`, `SearchSpace`, `PDCCH-Config`, `PDCCH-ConfigCommon`, `BWP-Downlink`, `BWP-Uplink`, `CrossCarrierSchedulingConfig`, TCI and MIB/SIB state.
- **3GPP TS 38.321 V18.8.0** only for the minimum RNTI, activation, BWP and control-state transitions needed by this phase.

Record exact MATLAB and 5G Toolbox versions. A Toolbox call is the DUT implementation or a self-consistency cross-check, not an independent oracle. Where Toolbox behavior is release-mismatched, add a release adapter or pure implementation; do not silently alter the requested configuration.

Mandatory physical invariants:

- PDCCH aggregation levels are exactly `1, 2, 4, 8, 16`.
- One CCE contains six REGs.
- One REG is one resource block during one OFDM symbol and REGs are numbered time-first.
- Each REG has three PDCCH DM-RS REs and nine PDCCH data REs, so the rate-matched PDCCH bit count is `E = 108 * aggregationLevel`.
- PDCCH modulation is QPSK only.
- DCI CRC length is 24 bits using CRC24C. The first eight CRC bits remain unmasked; the last sixteen are XORed with the RNTI bits MSB first.
- Strict blind monitoring must not receive candidate CCE indices, candidate timing, decoded format, decoded size or transmitted RNTI as an oracle.

---

## 3. Execution profiles — never silently fall back

### 3.1 `connected_blind_strict`

Input is the received waveform plus allowed synchronization state, active cell/BWP/RRC/search-space configuration, and the UE's list of RNTI procedures. The receiver must derive monitoring occasions and enumerate all legal candidates. No known-location fallback is allowed.

### 3.2 `initial_access_type0_strict`

Input is decoded MIB/PBCH state, SSB timing/frequency state and the received waveform. Derive CORESET0, SearchSpace0, monitoring occasions, SI-RNTI DCI 1_0 size and candidates from the pinned tables. No fixed 30-kHz/index-zero/AL4/32-bit anchor is allowed.

### 3.3 `beam_aware_control_strict`

The CORESET is bound to active TCI/QCL state and measured beam/RS provenance. Inactive, stale or blocked control beams must not be replaced by an omniscient perfect beam.

### 3.4 `multi_bwp_cross_carrier_strict`

Control cell/carrier/BWP and scheduled cell/carrier/BWP are separate immutable identities. Carrier indicator and BWP indicator fields must be sized, decoded and applied in the correct context.

### 3.5 `synchronized_phy_calibration`

Known candidate location and perfect slot boundary may be used only here. Every output must carry this profile tag. Calibration evidence cannot satisfy blind-search acceptance rules.

---

## 4. Supplied pack

Place this pack under `tests/vectors/pdcch/`. Run:

```bash
python tests/vectors/pdcch/verify_pdcch_vector_pack.py
```

before MATLAB. It must return exit code 0. The expected files are bounded independent floors; they are not permission to skip full generated boundary tests. PDCCH DM-RS now has a pure-spec sequence/index floor; independent Polar construction and rate-matching vectors remain mandatory.

### Supplied input and expected files

- `pdcch_dci_context_test_vectors.csv` — 94 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_dci_size_alignment_floor.csv` — 28 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_rnti_procedure_test_vectors.csv` — 27 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_crc_vectors.csv` — 40 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_scrambling_vectors.csv` — 15 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_qpsk_vectors.csv` — 4 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_dmrs_test_vectors.csv` — 29 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_dmrs_vectors.csv` — 24 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_coreset_mapping_test_vectors.csv` — 19 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_coreset_reg_cce_mapping.csv` — 176 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_candidate_enumeration_test_vectors.csv` — 55 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_candidate_enumeration.csv` — 48 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_monitoring_occasion_test_vectors.csv` — 11 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_monitoring_occasions.csv` — 7 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_type0_css_test_vectors.csv` — 268 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_type0_monitoring_tables.csv` — 64 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_type0_pattern23_monitoring_test_vectors.csv` — 80 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_type0_gscn_offset_vectors.csv` — 40 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_blind_detection_test_vectors.csv` — 151 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_bwp_crosscarrier_beam_test_vectors.csv` — 24 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_grant_authority_test_vectors.csv` — 32 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_grant_authority.csv` — 32 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `pdcch_declared_coverage_matrix.csv` — 60 rows; SHA-256 pinned in `independent_vector_manifest.json`.
- `expected_pdcch_impact_analytical_floor.csv` — 41 rows; SHA-256 pinned in `independent_vector_manifest.json`.

Never copy an expected CSV into the production artifact directory. MATLAB tests must call the production functions and compare the actual values field by field. Reserved Type-0 table indices are explicit negative vectors and must fail before waveform generation.
---

## 5. Mandatory closure map — all 14 findings

| ID | Priority | Finding | Required production correction | Mandatory acceptance |
|---|---|---|---|---|
| CTRL-001 | P1 | The strict PDCCH validator supports only DCI formats 0_0 and 1_0. | Implement release-pinned DCI 0_1 and 1_1 layouts, field sizing, BWP/carrier/antenna-port/CSI requests, CRC scrambling, and grant reconstruction before enabling them. | Bit-exact encode/decode vectors and blind-search tests cover every supported format and contextual size. |
| CTRL-002 | P1 | Partial DCI 0_1/1_1 payload structures exist without complete contextual sizing and end-to-end ownership. | Delete or fence partial layouts from strict execution; rebuild sizing from canonical RRC/BWP/resource-allocation context and decoded field semantics. | Strict mode cannot select partial formats; completed formats round-trip independent vectors and drive actual grants. |
| CTRL-003 | P1 | Type-0 PDCCH derivation is constrained to a 30-kHz, CORESET0 index 0, SearchSpace0 index 0 mini anchor. | Implement complete selected-release CORESET0/SearchSpace0 lookup tables by frequency, SSB SCS, common SCS, and pdcch-ConfigSIB1. | Every pdcch-ConfigSIB1 index is exercised across Tables 13-0 through 13-10A and 13-11/12/12A; pattern-2/3 Tables 13-13 through 13-15A and GSCN-offset Tables 13-16/17 are also covered. Reserved and context-invalid combinations fail. |
| CTRL-004 | P1 | The Type-0 helper hard-codes aggregation level 4, one candidate, 32 DCI payload bits, and fixed timing assumptions. | Derive candidate counts, aggregation levels, monitoring occasion, payload size, and timing from the pinned tables and actual DCI context. | Table/vector tests validate candidate sets and payload sizes over the supported Type-0 matrix. |
| CTRL-005 | P2 | SI-RNTI, RA-RNTI, TC-RNTI, P-RNTI, CS-RNTI and other RNTI-specific search/CRC/procedure combinations are not broadly integrated. | Add explicit RNTI types, search-space ownership, CRC mask, DCI applicability, procedure state, and negative wrong-RNTI tests. | Each supported RNTI decodes only in the correct search space/procedure and wrong masks produce no false grant. |
| CTRL-006 | P2 | PDCCH BWP switching, cross-carrier scheduling, carrier indicators, and search-space association are not end-to-end. | Carry serving-cell/BWP/search-space/CORESET identity through DCI encode, monitoring, blind search, grant reconstruction, scheduler, and evidence. | Two-BWP/two-CC tests prove the DCI is monitored and applied only on the intended control/data resources. |
| CTRL-007 | P2 | Beam-specific PDCCH monitoring, QCL/TCI association, beam failure detection, and recovery are incomplete. | Implement control-resource-set TCI state, SSB/CSI-RS QCL sources, beam-switch timing, monitoring occasions, and failure/recovery procedures. | Beam switch and blocked-beam scenarios show correct monitoring/decoding and recovery with observed beam provenance. |
| CTRL-008 | P1 | Some blind-search execution depends on externally supplied candidate timing or disables timing estimation rather than performing complete monitoring. | Build monitoring occasions and candidates entirely from decoded/configured state; perform timing/CFO acquisition within the declared strict profile or require a separately named synchronized calibration profile. | Blind-search test starts from waveform plus allowed synchronization state only and finds the correct candidate without oracle indices. |
| CTRL-009 | P1 | Legacy study control modules and nontransparent stubs remain close to production paths and can be confused with strict PDCCH behavior. | Physically isolate study/stub packages, add runtime prohibition in strict profiles, and label every output from a stub as unavailable/non-conformant. | Dependency scan shows strict packages cannot import stub modules; a deliberate stub selection fails before run. |
| CTRL-010 | P2 | A PDCCH detector contains undefined “6G SCS” placeholder behavior. | Remove it from NR strict paths; define an explicit experimental waveform numerology interface and research-only tests if retained. | NR profile never executes placeholder code; research profile labels it non-normative and requires explicit parameters. |
| CTRL-011 | P1 | CORESET REG/CCE mapping, interleaving, bundle sizes, shift index, precoder granularity, and candidate enumeration lack a complete independent matrix. | Add table-driven mapping tests and pure-math expected RE/REG/CCE indices for every supported combination. | Independent maps match TX/RX, and one-bit/mapping perturbations are detected. |
| CTRL-012 | P1 | False-alarm, missed-detection, wrong-RNTI, wrong-aggregation, no-signal, and low-SNR tests exist but are not a statistically complete campaign across the supported control matrix. | Create a multi-seed detection campaign with declared probability bounds per format/AL/channel/impairment and enforce confidence intervals. | Campaign meets configured false-alarm and detection bounds with no incomplete points. |
| CTRL-013 | P1 | Decoded DCI is not the sole authority for all data grants and scheduler state. | Make decoded DCI plus installed RRC/MAC state the only strict connected-mode grant source; expose configured grants only in calibration profiles. | Oracle-grant mutation no longer changes strict execution; decoded-bit mutation does. |
| CTRL-014 | P1 | DCI field sizing and payload packing are not covered by an independent release/versioned vector catalog. | Create spec-derived vectors for each supported format under multiple BWP/resource/context sizes and verify both pack and parse. | All vectors round-trip bit-exactly; wrong context produces a controlled size/semantic failure. |

---

## 6. Confirmed current-source defects to remove

The following checks were executed against the uploaded source. Search by behavior, not only by current line number. Deleting a matching string without correcting the production path is not closure.

### PDCSRC-001 — +sixgr/+phy/+pdcch/validatePDCCHConfigStrict.m

**Mapped finding:** `CTRL-001`  
**Confirmed behavior:** Strict validator is concentrated on DCI 0_0 and 1_0.  
**Why it is technically wrong:** 0_1/1_1 cannot be claimed as complete strict control.  
**Required production correction:** Replace format whitelist with release-pinned contextual schema registry.  
**Current matching line(s):** `37`.

### PDCSRC-002 — +sixgr/+phy/+pdcch/dciPayloadSizeBits.m

**Mapped finding:** `CTRL-002`  
**Confirmed behavior:** DCI 0_1/1_1 sizes are hard-coded sums.  
**Why it is technically wrong:** Conditional fields, BWP sizes, carrier indicators, antenna ports, CSI/SRS/CBG state and alignment are wrong for many contexts.  
**Required production correction:** Implement context-driven field presence, width and alignment engine.  
**Current matching line(s):** `25|26`.

### PDCSRC-003 — +sixgr/+phy/+pdcch/dciPayloadSizeBits.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** One scalar NSizeGrid drives all frequency-domain widths.  
**Why it is technically wrong:** Initial/active UL/DL BWPs and resource-allocation types are conflated.  
**Required production correction:** Use separate initial/active UL/DL BWP and procedure context.  
**Current matching line(s):** `21`.

### PDCSRC-004 — +sixgr/+phy/+pdcch/dciPayloadSizeBits.m

**Mapped finding:** `CTRL-002`  
**Confirmed behavior:** Payload length becomes the maximum selected format size.  
**Why it is technically wrong:** Different monitored DCI sizes and alignment classes are collapsed.  
**Required production correction:** Return one exact size per format/context and explicit monitored-size alignment groups.  
**Current matching line(s):** `43`.

### PDCSRC-005 — +sixgr/+phy/+pdcch/dciPayloadLayout.m

**Mapped finding:** `CTRL-002`  
**Confirmed behavior:** Field layouts use fixed numeric widths.  
**Why it is technically wrong:** Optional and RNTI-specific fields are packed even when absent or omitted when required.  
**Required production correction:** Generate field definitions from DCIContext and pinned 38.212 clauses.  
**Current matching line(s):** `23|28|36|44`.

### PDCSRC-006 — +sixgr/+phy/+pdcch/encodeDCIPayload.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** Missing DCI fields silently default to zero.  
**Why it is technically wrong:** Malformed scheduler state can generate a valid-looking DCI.  
**Required production correction:** Require every present field and reject unexpected or missing fields.  
**Current matching line(s):** `12`.

### PDCSRC-007 — +sixgr/+phy/+pdcch/encodeDCIPayload.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** Payload writing silently truncates fields at K.  
**Why it is technically wrong:** Bit loss can pass unnoticed.  
**Required production correction:** Assert exact layout sum equals K before packing; no min/truncation.  
**Current matching line(s):** `14`.

### PDCSRC-008 — +sixgr/+phy/+pdcch/encodeDCIPayload.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** Field values are floored/clamped to unsigned values.  
**Why it is technically wrong:** Negative, fractional and out-of-range values are not rejected.  
**Required production correction:** Typed range validation per field before serialization.  
**Current matching line(s):** `51`.

### PDCSRC-009 — +sixgr/+phy/+pdcch/decodeDCIPayload.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** Short payloads are zero-padded.  
**Why it is technically wrong:** Wrong DCI size can decode as a different valid assignment.  
**Required production correction:** Reject any length mismatch before parsing.  
**Current matching line(s):** `8`.

### PDCSRC-010 — +sixgr/+phy/+pdcch/decodeDCIPayload.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** Long payloads are truncated.  
**Why it is technically wrong:** Wrong size/context is hidden.  
**Required production correction:** Reject any length mismatch before parsing.  
**Current matching line(s):** `10`.

### PDCSRC-011 — +sixgr/+phy/+pdcch/decodeDCIPayload.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** DCI parser owns a local time-domain allocation table.  
**Why it is technically wrong:** RRC time-domain allocation lists and K0/K2 state are bypassed.  
**Required production correction:** Resolve indices through active RRC/BWP timing context.  
**Current matching line(s):** `40|44|70`.

### PDCSRC-012 — +sixgr/+phy/+pdcch/decodeDCIPayload.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** Invalid time-domain rows can fall back to the first row.  
**Why it is technically wrong:** Invalid control fields become legal grants.  
**Required production correction:** Fail with typed semantic error.  
**Current matching line(s):** `not found in this delivery`.

### PDCSRC-013 — +sixgr/+phy/+pdcch/buildDCI10DownlinkAssignment.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** DCI 1_0 grant builder contains fixed symbol assumptions.  
**Why it is technically wrong:** PDSCH resources are not solely determined by decoded field plus RRC table.  
**Required production correction:** Materialize from decoded field and active PDSCH time-domain allocation list.  
**Current matching line(s):** `28`.

### PDCSRC-014 — +sixgr/+phy/+pdcch/buildDCI10DownlinkAssignment.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** HARQ feedback timing is fixed/defaulted.  
**Why it is technically wrong:** K1 is not decoded/contextual.  
**Required production correction:** Resolve PDSCH-to-HARQ timing from DCI and active list.  
**Current matching line(s):** `25`.

### PDCSRC-015 — +sixgr/+phy/+pdcch/buildDCI01UplinkGrant.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** DCI 0_1 grant builder clamps decoded values.  
**Why it is technically wrong:** Invalid SRI/TPMI/rank/ports can become another legal grant.  
**Required production correction:** Validate exact contextual range and reject.  
**Current matching line(s):** `7|27|28|29|30`.

### PDCSRC-016 — +sixgr/+phy/+pdcch/buildDCI01UplinkGrant.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** DCI 0_1 path contains local K2 assumptions.  
**Why it is technically wrong:** PUSCH timing can differ from decoded/RRC state.  
**Required production correction:** Use central timing engine and active PUSCH allocation list.  
**Current matching line(s):** `33`.

### PDCSRC-017 — +sixgr/+phy/+pdcch/validatePDCCHConfigStrict.m

**Mapped finding:** `CTRL-005`  
**Confirmed behavior:** Strict RNTI support is a short whitelist.  
**Why it is technically wrong:** Paging, configured scheduling, TPC and other control procedures are not integrated.  
**Required production correction:** Implement RNTIProcedureRegistry with search-space/DCI applicability.  
**Current matching line(s):** `43`.

### PDCSRC-018 — +sixgr/+phy/+pdcch/validatePDCCHConfigStrict.m

**Mapped finding:** `CTRL-005`  
**Confirmed behavior:** RNTI validity is treated as one generic numeric interval.  
**Why it is technically wrong:** Special and procedure-specific RNTI semantics are wrong.  
**Required production correction:** Validate by RNTI type/procedure rather than one range.  
**Current matching line(s):** `47`.

### PDCSRC-019 — +sixgr/+phy/+pdcch/buildPDCCHConfigFromScenario.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** Scenario configuration can be treated as control binding authority.  
**Why it is technically wrong:** Connected data grants can bypass decoded control.  
**Required production correction:** Separate transmission intention from decoded control event.  
**Current matching line(s):** `135`.

### PDCSRC-020 — +sixgr/+phy/+pdcch/buildPDCCHConfigFromScenario.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** Scenario builder derives size from grid only.  
**Why it is technically wrong:** Contextual DCI size alignment is bypassed.  
**Required production correction:** Require full DCIContext.  
**Current matching line(s):** `not found in this delivery`.

### PDCSRC-021 — +sixgr/+phy/+dl/PDCCH_Tx.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** TX accepts random/zero/direct configured payload paths near production.  
**Why it is technically wrong:** Synthetic control can leak into connected mode.  
**Required production correction:** Keep direct bits only in isolated calibration factory.  
**Current matching line(s):** `18|28|33|43|51|126|144|152|153|154|158|172|173|179|183`.

### PDCSRC-022 — +sixgr/+phy/+dl/PDCCH_Tx.m

**Mapped finding:** `CTRL-014`  
**Confirmed behavior:** PDCCH payload defaults to 64 bits.  
**Why it is technically wrong:** Payload size is not derived from DCI context.  
**Required production correction:** Require exact K from schema engine.  
**Current matching line(s):** `not found in this delivery`.

### PDCSRC-023 — +sixgr/+phy/+dl/PDCCH_Tx.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Default CORESET frequency bitmap is synthesized.  
**Why it is technically wrong:** Control resources can differ from RRC/Type0 state.  
**Required production correction:** Require explicit CORESET definition.  
**Current matching line(s):** `239`.

### PDCSRC-024 — +sixgr/+phy/+dl/PDCCH_Tx.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Invalid/missing aggregation level can become AL4.  
**Why it is technically wrong:** Candidate location and code rate silently change.  
**Required production correction:** Validate AL in {1,2,4,8,16}; no default in strict profile.  
**Current matching line(s):** `not found in this delivery`.

### PDCSRC-025 — +sixgr/+phy/+dl/PDCCH_Tx.m

**Mapped finding:** `CTRL-005`  
**Confirmed behavior:** SI-RNTI/toolbox workaround changes physical RNTI state.  
**Why it is technically wrong:** CRC masking/scrambling provenance is ambiguous.  
**Required production correction:** Use explicit RNTI mask and toolbox adapter without changing semantic RNTI.  
**Current matching line(s):** `24|103|104|205|212`.

### PDCSRC-026 — +sixgr/+phy/+dl/PDCCH_Rx.m

**Mapped finding:** `CTRL-008`  
**Confirmed behavior:** Receiver contains a known-location path near blind strict operation.  
**Why it is technically wrong:** Oracle candidate indices can be mistaken for blind monitoring.  
**Required production correction:** Isolate synchronized calibration and prohibit its use in blind strict profile.  
**Current matching line(s):** `8`.

### PDCSRC-027 — +sixgr/+phy/+dl/PDCCH_Rx.m

**Mapped finding:** `CTRL-008`  
**Confirmed behavior:** Blind flow can fall back to configured resource indices.  
**Why it is technically wrong:** Blind detection becomes known-location decoding.  
**Required production correction:** No fallback; fail if candidate enumeration/extraction fails.  
**Current matching line(s):** `99|105`.

### PDCSRC-028 — +sixgr/+phy/+dl/PDCCH_Rx.m

**Mapped finding:** `CTRL-008`  
**Confirmed behavior:** Blind timing may be disabled or externally supplied.  
**Why it is technically wrong:** Waveform-only detection is not proven.  
**Required production correction:** Implement declared synchronization acquisition or use separately named synchronized profile.  
**Current matching line(s):** `not found in this delivery`.

### PDCSRC-029 — +sixgr/+phy/+dl/PDCCH_Rx.m

**Mapped finding:** `CTRL-012`  
**Confirmed behavior:** Receiver can stop after first CRC pass.  
**Why it is technically wrong:** Multiple valid candidates/formats/RNTIs are not resolved deterministically.  
**Required production correction:** Collect all passes, apply exact ambiguity/procedure rules, then select.  
**Current matching line(s):** `359`.

### PDCSRC-030 — +sixgr/+phy/+pdcch/blindDecodePDCCH.m

**Mapped finding:** `CTRL-012`  
**Confirmed behavior:** Blind helper receives one RNTI and one format.  
**Why it is technically wrong:** It does not perform a configured search across monitored hypotheses.  
**Required production correction:** Enumerate all legal format-size-RNTI hypotheses per search space.  
**Current matching line(s):** `9|10|18|22|40|47|54|55|56|78|79|80|105|106`.

### PDCSRC-031 — +sixgr/+phy/+pdcch/blindDecodePDCCH.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Candidate table invents CCE index from loop position.  
**Why it is technically wrong:** Reported resource provenance is wrong.  
**Required production correction:** Propagate actual candidate first CCE and full CCE set.  
**Current matching line(s):** `75`.

### PDCSRC-032 — +sixgr/+phy/+pdcch/blindDecodePDCCH.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Blind helper uses one configured aggregation level.  
**Why it is technically wrong:** Full AL/candidate matrix is not monitored.  
**Required production correction:** Enumerate configured candidates at AL 1,2,4,8,16.  
**Current matching line(s):** `19|74|104`.

### PDCSRC-033 — +sixgr/+phy/+broadcast/deriveType0PDCCHFromMIB.m

**Mapped finding:** `CTRL-003`  
**Confirmed behavior:** Type0 resolver is a fixed mini profile.  
**Why it is technically wrong:** Most valid pdcch-ConfigSIB1 combinations cannot execute.  
**Required production correction:** Implement complete selected-release Type0 table resolver.  
**Current matching line(s):** `5|31`.

### PDCSRC-034 — +sixgr/+phy/+broadcast/deriveType0PDCCHFromMIB.m

**Mapped finding:** `CTRL-004`  
**Confirmed behavior:** Type0 AL, candidates and payload are hard-coded.  
**Why it is technically wrong:** Initial access is not table/context driven.  
**Required production correction:** Derive all from Tables 13-x, search-space state and DCI 1_0 SI-RNTI context.  
**Current matching line(s):** `58|72|110|128`.

### PDCSRC-035 — +sixgr/+phy/+broadcast/deriveType0PDCCHFromMIB.m

**Mapped finding:** `CTRL-004`  
**Confirmed behavior:** Type0 duration/bitmap assumptions are fixed.  
**Why it is technically wrong:** CORESET0 physical location can be wrong.  
**Required production correction:** Use table values including puncturing/special cases.  
**Current matching line(s):** `42|43|140`.

### PDCSRC-036 — +sixgr/+ctrl/SearchSpaceConfig.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Study search-space code accepts aggregation level 32.  
**Why it is technically wrong:** Non-NR AL can leak into tests.  
**Required production correction:** Restrict NR strict to 1,2,4,8,16; move experiments to research profile.  
**Current matching line(s):** `32|34|36|44|47`.

### PDCSRC-037 — +sixgr/+ctrl/PDCCHCandidateGenerator.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Candidate generation uses a custom hash.  
**Why it is technically wrong:** USS CCE candidates differ from TS 38.213.  
**Required production correction:** Implement Y recursion and candidate equation exactly.  
**Current matching line(s):** `41`.

### PDCSRC-038 — +sixgr/+ctrl/CCEToREGMapper.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Study CCE-to-REG interleaving is approximate/custom.  
**Why it is technically wrong:** REG/CCE resources are wrong.  
**Required production correction:** Replace with TS 38.211 interleaver.  
**Current matching line(s):** `not found in this delivery`.

### PDCSRC-039 — +sixgr/+ctrl/REGBundleMapper.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** REG bundle indexing uses 1-based ceil arithmetic.  
**Why it is technically wrong:** Bundle boundaries can be off by one.  
**Required production correction:** Use zero-based bundle=floor(REG/L), then convert only at API boundary.  
**Current matching line(s):** `11`.

### PDCSRC-040 — +sixgr/+ctrl/REGIndexer.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** REG is treated as an arbitrary RE chunk.  
**Why it is technically wrong:** NR REG definition one RB x one symbol is violated.  
**Required production correction:** Represent explicit RB/symbol REG coordinates and DM-RS/data REs.  
**Current matching line(s):** `7`.

### PDCSRC-041 — +sixgr/+ctrl/PDCCHBlindDetector.m

**Mapped finding:** `CTRL-012`  
**Confirmed behavior:** Detector prunes candidates/ALs using heuristic SINR.  
**Why it is technically wrong:** Configured/measured truth can reduce blind hypotheses.  
**Required production correction:** Monitor all required candidates; complexity shortcuts only in labelled study profile.  
**Current matching line(s):** `67|171|180|181|192|196|197|198|199`.

### PDCSRC-042 — +sixgr/+ctrl/PDCCHBlindDetector.m

**Mapped finding:** `CTRL-010`  
**Confirmed behavior:** Detector contains undefined high-SCS/6G placeholder behavior.  
**Why it is technically wrong:** NR strict can execute non-normative assumptions.  
**Required production correction:** Remove from NR strict; use explicit research numerology interface.  
**Current matching line(s):** `347|348|349|350|352|357`.

### PDCSRC-043 — +sixgr/+ctrl/PDCCHDecoder.m

**Mapped finding:** `CTRL-011`  
**Confirmed behavior:** Study decoder allows non-QPSK PDCCH modulation.  
**Why it is technically wrong:** PDCCH waveform is non-NR.  
**Required production correction:** Strict PDCCH modulation is QPSK only.  
**Current matching line(s):** `64|66|68|70|72`.

### PDCSRC-044 — +sixgr/+phy/+pdcch/runStrictPDCCHValidation.m

**Mapped finding:** `CTRL-012`  
**Confirmed behavior:** False-alarm campaign is tiny by default.  
**Why it is technically wrong:** No-signal upper bound is statistically meaningless.  
**Required production correction:** Use target-driven trials and exact one-sided confidence bound.  
**Current matching line(s):** `255`.

### PDCSRC-045 — +sixgr/+phy/+pdcch/runStrictPDCCHValidation.m

**Mapped finding:** `CTRL-012`  
**Confirmed behavior:** Strict validation is focused on 1_0/0_0 anchors.  
**Why it is technically wrong:** 0_1/1_1 and contextual matrices lack runtime evidence.  
**Required production correction:** Execute complete declared format/context/AL/RNTI matrix.  
**Current matching line(s):** `38|44|50|55|60|65|70|76|98|263|298`.

### PDCSRC-046 — +sixgr/+phy/+pdcch/validateDecodedDCIGrant.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** Grant validator uses coarse MCS bands.  
**Why it is technically wrong:** Decoded DCI semantics do not match active MCS tables.  
**Required production correction:** Delegate to PDSCH/PUSCH MCS resolver with active table and capability.  
**Current matching line(s):** `65|67|69`.

### PDCSRC-047 — +sixgr/+phy/+pdcch/validateDecodedDCIGrant.m

**Mapped finding:** `CTRL-013`  
**Confirmed behavior:** Grant validation assumes pre-expanded scalar fields.  
**Why it is technically wrong:** Resource-allocation type, interlace and RRC list context are bypassed.  
**Required production correction:** Validate decoded field semantics in context, then materialize immutable assignment.  
**Current matching line(s):** `6|7|8|9|16|19`.

### PDCSRC-048 — +sixgr/+ctrl/PDCCHBlindDetector.m

**Mapped finding:** `CTRL-009`  
**Confirmed behavior:** Legacy study detector remains in adjacent production namespace.  
**Why it is technically wrong:** Strict code may import a study implementation.  
**Required production correction:** Move under +sixgr/+research/+pdcch and add strict dependency guard.  
**Current matching line(s):** `1|152|177|192|217|240|261|268|281|306|316|331`.


---

## 7. Canonical production architecture

Consolidate the two current stacks. Use `+sixgr/+phy/+pdcch/` as the canonical strict package and move experimental material from `+sixgr/+ctrl/` under a clearly named research package. Do not add a third independent stack.

Create or refactor the following production components:

```text
+sixgr/+phy/+pdcch/
    PDCCHSpecificationProfile.m
    DCIContext.m
    DCIFieldDefinition.m
    DCISchemaEngine.m
    DCISizeAlignmentEngine.m
    DCIPacker.m
    DCIParser.m
    DecodedDCIEvent.m

    RNTIProcedure.m
    RNTIProcedureRegistry.m
    DCICRC24C.m
    PDCCHPolarCodec.m
    PDCCHScrambler.m
    PDCCHQPSK.m

    CORESETDefinition.m
    CORESETMapper.m
    PDCCHDMRS.m
    PDCCHResourceOwnershipMap.m

    SearchSpaceDefinition.m
    MonitoringOccasionResolver.m
    PDCCHCandidateEnumerator.m
    PDCCHMonitoringBudget.m

    Type0PDCCHResolver.m
    Type0MonitoringOccasionResolver.m

    ControlBeamState.m
    ControlBWPContext.m
    CrossCarrierControlContext.m

    PDCCHTransmitter.m
    PDCCHBlindSearchEngine.m
    PDCCHReceiver.m
    DecodedGrantMaterializer.m

    PDCCHArtifactExporter.m
    runPDCCHPhaseValidation.m

    +oracle/
        CRC24CSpec.m
        GoldSequenceSpec.m
        QPSKSpec.m
        PolarConstructionSpec.m
        PolarRateMatchingSpec.m
        DCISchemaSpec.m
        DCISizeAlignmentSpec.m
        CORESETMappingSpec.m
        PDCCHDMRSSpec.m
        MonitoringOccasionSpec.m
        CandidateEnumerationSpec.m
        Type0TablesSpec.m
```

`PDCCH_Tx.m` and `PDCCH_Rx.m` may remain as compatibility façades, but they must delegate to the canonical chain and must not retain hidden defaults, direct connected grants, local candidates or known-location fallbacks.

Add a dependency test that fails if a strict production package imports `+sixgr/+ctrl`, `HashFunction6GR`, an AL32 implementation, a non-QPSK PDCCH modulator, or an undefined high-SCS placeholder.

---

## 8. `DCIContext` — complete immutable sizing and semantics input

Every schema operation must receive one immutable context containing at least:

```text
SpecRelease and exact version
DCI format
RNTI type and value
search-space type and ID
CORESET ID and pool
control serving cell/carrier/BWP
scheduled serving cell/carrier/BWP
initial DL BWP size/start
active DL BWP size/start
initial UL BWP size/start
active UL BWP size/start
resource-allocation type and interlace state
configured time-domain allocation lists
carrier-indicator presence/width and nCI
BWP-indicator presence/width
SUL indicator state
frequency-hopping state
transform-precoder state
HARQ process count
DAI and HARQ-ACK codebook state
antenna-port and layer capabilities
TCI field presence and active TCI state
SRS request/CSI request field sizes
rate-match and ZP-CSI-RS trigger state
CBG fields and code-block-group state
PTRS/DM-RS sequence initialization fields
shared-spectrum, RedCap, NTN or other selected conditional profile flags
configuration epoch
```

The context object must validate cross-field consistency and expose a stable SHA-256 digest. No schema method may read unrelated global/scenario state or silently infer a missing field from a convenient default.

---

## 9. DCI schema and size alignment engine

### 9.1 Contextual field definitions

Implement each selected format from the pinned TS 38.212 clause. A field definition contains:

```text
name
presence predicate
width function
value domain
enumeration/semantic decoder
bit order
RNTI/search-space applicability
release clause
```

Missing present fields, unexpected absent fields, noninteger values and values outside the contextual domain must fail before packing. Parsing must require exactly K bits. Delete zero padding of short input, truncation of long input, default-zero field insertion and `floor/max/min` coercions.

### 9.2 Size alignment

Implement the actual monitored-size procedure, not `max(sizes)`:

- determine raw sizes for every monitored DCI format in its own initial/active UL/DL BWP context;
- apply the common/UE-specific 0_0/1_0 alignment steps;
- apply truncation of the 0_0 frequency-domain assignment only where the specification explicitly requires it;
- add padding bits only at the specified position and only for the specified alignment step;
- size 0_1/1_1 using complete active-context fields and apply the equal-size disambiguation rule where applicable;
- enforce the maximum number of monitored DCI sizes and C-RNTI sizes for the active serving cell;
- preserve an explicit alignment-group ID and raw/aligned size for every hypothesis.

Tests must cover initial BWP != active BWP, UL != DL BWP, CSS and USS, multiple formats in one search space, carrier indicator, BWP indicator, TCI, CSI/SRS/CBG fields and wrong-context parsing.

### 9.3 Pack/parse round trip

For every vector:

```text
fields -> exact payload bits -> parse using same context -> identical fields
```

Then parse using a deliberately wrong context and require a controlled size or semantic error. A bit-exact round trip must not be established by comparing a function to itself only; compare field boundaries and payload bits to pure/frozen vectors.

---

## 10. CRC, Polar coding, rate matching, scrambling and QPSK

### 10.1 CRC24C and RNTI mask

Implement TS 38.212 DCI CRC exactly:

- prepend the specified 24 ones for CRC computation;
- use CRC24C;
- attach 24 parity bits to the original payload;
- leave the first eight CRC bits unchanged;
- XOR the final sixteen CRC bits with the 16 RNTI bits MSB first;
- recover and check the mask at the receiver without replacing the semantic RNTI.

Test every supplied vector and wrong-RNTI mutations. No wrong mask may create a downstream assignment.

### 10.2 Polar coding/rate matching

Implement or use a release-pinned adapter for DCI Polar coding with the required parameters. Export K, K+24, mother length N, reliability/frozen set identity, interleaver identity, rate-matching mode, E and hashes of every intermediate bit vector.

For each AL, verify `E = 108*AL`. Add independent or externally frozen vectors for construction, input interleaving, encoding and rate matching. A same-Toolbox encode/decode round trip is useful regression coverage but not the independent oracle.

### 10.3 Physical scrambling and QPSK

Implement `c_init = (n_RNTI*2^16 + n_ID) mod 2^31` with the exact search-space rules for `n_ID` and physical scrambling `n_RNTI`. Do not confuse this physical scrambling identity with the CRC-mask RNTI.

PDCCH modulation is QPSK only. Delete or isolate 16QAM/64QAM/256QAM/1024QAM/4096QAM control-channel paths from strict code.

---

## 11. CORESET, REG, CCE, DM-RS and RE ownership

### 11.1 Explicit coordinates

Represent each REG by `(slot, symbol, PRB)` and each RE by `(slot, symbol, PRB, subcarrier)`. REG numbering is zero-based time-first. Convert to MATLAB one-based indices only at the final array boundary.

### 11.2 Mapping

Implement:

- one CCE = six REGs;
- non-interleaved mapping with bundle size six;
- interleaved mapping with release-valid bundle size L, interleaver size R and shift index;
- exact interleaver `f(x)` and all validity conditions;
- CORESET0 special parameters and puncturing cases;
- `sameAsREG-bundle` and `allContiguousRBs` precoder granularity;
- no duplicate or missing REGs;
- exact data versus DM-RS RE ownership.

Compare every production CCE map to `expected_coreset_reg_cce_mapping.csv`. Add generated boundaries for every selected duration/L/R/shift tuple.

### 11.3 PDCCH DM-RS

Generate sequence initialization from slot, symbol and scrambling ID exactly. Map the three DM-RS REs in each REG and the nine QPSK data REs without collision. Export sequence and index hashes and compare to an independent oracle.

---

## 12. Search spaces, monitoring occasions and candidate enumeration

### 12.1 Search-space definitions

Materialize CSS/USS configuration from RRC/Type0 state:

```text
searchSpaceId
controlResourceSetId
monitoringSlotPeriodicityAndOffset
monitoringSymbolsWithinSlot
duration
nrofCandidates for AL1/2/4/8/16
monitored DCI format set
allowed RNTI procedures
searchSpaceLinkingId where selected
```

Invalid periodicity/offset/duration/symbol bitmaps fail. Warnings are not sufficient.

### 12.2 Candidate equation

For CSS use Y=0. For USS implement the Release-18 Y recursion with constants 39827, 39829, 39839 and modulus 65537, and then the exact candidate first-CCE equation including `n_CI`. Compare every candidate against the supplied independent vectors.

Never use `HashFunction6GR`, random hashing, `mod(hash,maxStartCount)` or loop index as CCE index.

### 12.3 Monitoring limits and candidate deduplication

Implement candidate and non-overlapping-CCE monitoring limits for the selected SCS/capability profile. Apply deterministic priority and deduplication rules for overlapping search spaces/candidates with identical CCEs, scrambling and DCI size. Export raw and counted candidate sets.

---

## 13. Blind-search engine

For every monitoring occasion:

1. enumerate all monitored search spaces;
2. enumerate all configured AL/candidates;
3. enumerate only the format-size-RNTI hypotheses legal for that search space/procedure;
4. extract candidate REs using the exact CORESET map;
5. perform candidate-specific PDCCH DM-RS channel estimation;
6. equalize and generate soft QPSK LLRs;
7. rate recover and Polar-decode for each legal K/E pair;
8. test CRC/RNTI mask;
9. parse with the exact DCIContext;
10. reject semantically inconsistent DCI;
11. collect every valid hypothesis before applying ambiguity/priority rules;
12. emit one or more typed `DecodedDCIEvent` objects according to the procedure.

Strict blind input must not include transmitted CCE, transmitted format, transmitted RNTI, exact candidate timing or grant fields. If synchronization acquisition is outside this phase, the profile may receive a declared cell/slot boundary estimate, but it must still enumerate candidates. Perfect candidate location is calibration only.

No candidate found, multiple ambiguous candidates, wrong size, wrong RNTI and inconsistent fields are explicit outcomes, not exceptions converted to a configured grant.

---

## 14. Complete Type0-PDCCH CSS

Replace the mini anchor in `deriveType0PDCCHFromMIB.m` with a release-pinned table resolver.

Inputs include:

```text
frequency range and band/channel-bandwidth class
SS/PBCH SCS
PDCCH SCS from common numerology
shared-spectrum state
kSSB and applicable raster state
controlResourceSetZero index
searchSpaceZero index
SSB index and timing
MIB/pdcch-ConfigSIB1 bits
```

Implement all selected valid entries of Tables 13-0 through the applicable CORESET tables and monitoring-occasion tables, including multiplexing patterns 1/2/3, O, M, first-symbol rule, slot/SFN determination and special puncturing cases. Reserved or impossible combinations fail before waveform generation.

DCI 1_0 SI-RNTI payload size is derived from the actual initial DL BWP and RNTI-specific schema; it is never fixed at 32 bits. Candidate AL/count comes from the appropriate search-space definition, not a fixed AL4/one-candidate value.

---

## 15. RNTI/procedure registry

Create one registry that determines:

```text
semantic RNTI value rule
allowed CSS/USS types
allowed DCI formats
CRC mask
physical scrambling nRNTI/nID rule
procedure state required
whether a decoded event can create a grant or only an indication/TPC action
wrong-procedure behavior
```

The core phase must execute C-RNTI, CS-RNTI, MCS-C-RNTI, TC-RNTI, SI-RNTI, RA-RNTI and P-RNTI cases relevant to formats 0_0/0_1/1_0/1_1. Other Release-18 RNTIs in the supplied registry must either be implemented with their corresponding DCI format or explicitly remain outside the selected core profile; they must never be interpreted as a C-RNTI grant.

---

## 16. BWP, cross-carrier and beam-aware control

### BWP and cross-carrier

Carry separate control and scheduled resource identities. Validate carrier indicator, BWP indicator, nCI, search-space association and configuration epoch before creating an assignment. A stale BWP or invalid CIF creates no assignment.

### Beam/QCL/TCI

Bind each CORESET to active TCI/QCL state and observed RS/beam provenance. Implement bounded tests for:

- correct active TCI;
- stale/inactive TCI;
- beam mismatch;
- control beam switch;
- blocked beam;
- recovery to another configured control beam.

Do not substitute the strongest true channel beam or omniscient perfect CSI.

---

## 17. Decoded DCI as sole dynamic grant authority

Create immutable `DecodedDCIEvent` with:

```text
waveform/run ID
absolute slot and symbol monitoring occasion
serving cell/carrier/BWP
search-space and CORESET ID
aggregation level, candidate index and first CCE
DCI format and aligned payload size
RNTI type/value and CRC result
raw payload bits/hash
parsed fields and schema/context digest
configuration epoch
beam/TCI/QCL state
```

The downstream `DecodedGrantMaterializer` consumes this event plus installed RRC/MAC/HARQ state. Dynamic strict PDSCH/PUSCH must not consume the scheduler's original intention or a configured oracle grant.

Causal mutation tests are mandatory:

- mutate only configured/oracle grant: strict assignment and waveform digest remain unchanged;
- mutate a decoded resource/MCS/timing bit: assignment changes exactly as expected;
- fail CRC, RNTI or context epoch: no assignment, no waveform and no HARQ/scheduler state change.

---

## 18. Mandatory MATLAB tests

Add and execute at least:

```text
testDCIContextValidation
testDCISchema00
testDCISchema01
testDCISchema10
testDCISchema11
testDCISizeAlignment
testDCIPackParseRoundTrip
testDCIWrongContextRejection
testDCICRC24CAndRNTIMask
testPDCCHPhysicalScrambling
testPDCCHQPSK
testPDCCHPolarCodingAndRateMatching
testCORESETNonInterleavedMapping
testCORESETInterleavedMapping
testPDCCHDMRS
testPDCCHResourceOwnership
testSearchSpaceMonitoringOccasions
testPDCCHCandidateEnumerationCSS
testPDCCHCandidateEnumerationUSS
testPDCCHMonitoringBudget
testType0CORESETTables
testType0MonitoringOccasions
testPDCCHRNTIProcedureMatrix
testPDCCHBlindSearchNoOracle
testPDCCHBlindSearchAllAL
testPDCCHBlindSearchFormats001011
testPDCCHWrongRNTI
testPDCCHWrongFormatAndSize
testPDCCHNoSignalFalseAlarm
testPDCCHLowSNRDetection
testPDCCHTDLAndCDL
testPDCCHCFOAndTiming
testPDCCHBWPAndCrossCarrier
testPDCCHBeamMonitoring
testDecodedDCIGrantAuthority
testStrictPDCCHCannotImportStudyModules
testPDCCHArtifactGeneration
```

Tests must include positive, negative, boundary, wrong-identity, wrong-resource, wrong-context, no-signal, multi-candidate and reproducibility cases. A test that calls the same function on DUT and expected sides is self-consistency only.

---

## 19. Required production artifacts

Generate all 21 base CSVs and 13 base PNGs defined in:

```text
desired_pdcch_csv_contract.csv
desired_pdcch_image_contract.csv
```

The CSVs must come from actual production execution. The image semantic audit must be generated from MATLAB figure objects before saving and must record actual title, labels, axes count, series count, finite point count, source CSV hash and PNG hash.

Run:

```bash
python tests/vectors/pdcch/verify_pdcch_artifacts.py artifacts/pdcch_dci_phase
```

and require exit code 0.

---

## 20. Impact analysis

Execute the 50 families and 600 controlled experiments supplied in `pdcch_impact_experiment_matrix.csv`.

| Family | Analysis | Wave | Dependency | Metrics |
|---|---|---|---|---|
| F01 | DCI payload size versus BWP and context | A | direct | PayloadBits|FieldCount|CodeRate |
| F02 | DCI 0_0/1_0 size alignment | A | direct | RawBits|AlignedBits|PaddingBits |
| F03 | DCI 0_1/1_1 optional field breadth | A | direct | PayloadBits|PackRuntime|DecodeErrors |
| F04 | RNTI-specific CRC masking | A | direct | WrongRNTIFalseDecode|CorrectDecode |
| F05 | PDCCH physical scrambling identity | A | direct | SequenceCorrelation|WrongIDDecode |
| F06 | Polar code rate versus aggregation level | A | direct | CodeRate|BLER|Runtime |
| F07 | Polar list size and LLR scaling | A | direct | BLER|Runtime|Memory |
| F08 | Aggregation level detection tradeoff | A | direct | DetectionProbability|ResourceOverhead|Latency |
| F09 | Candidate count complexity and false alarm | A | direct | CandidatesTested|Runtime|FalseAlarm |
| F10 | CORESET duration | A | direct | DetectionProbability|Latency|ResourceOverhead |
| F11 | CORESET frequency span | A | direct | FrequencyDiversity|DetectionProbability|Overhead |
| F12 | Interleaved versus non-interleaved mapping | A | direct | BLER|ChannelEstimationNMSE|Diversity |
| F13 | REG bundle size | A | direct | BLER|MappingMismatch|Runtime |
| F14 | Interleaver size | A | direct | BLER|FrequencyDispersion |
| F15 | Shift index | A | direct | REGDistribution|Collision|BLER |
| F16 | Precoder granularity | B | beam_state | BeamRobustness|BLER |
| F17 | Search-space periodicity | A | direct | ControlLatency|MonitoringLoad |
| F18 | Search-space duration and symbol bitmap | A | direct | MonitoringLoad|MissedOccasions |
| F19 | CSS versus USS candidate generation | A | direct | CandidateDistribution|CollisionRate |
| F20 | Candidate collision and deduplication | A | direct | UniqueCandidates|MonitoringCount |
| F21 | UE monitoring capability caps | B | multi_cell_monitoring | DroppedCandidates|DetectionProbability |
| F22 | Type0 CORESET0 index | B | type0_tables | CORESETRBs|Symbols|Offset|DetectionProbability |
| F23 | Type0 SearchSpace0 index | B | type0_tables | MonitoringLatency|Candidates |
| F24 | Type0 SSB/PDCCH SCS pair | B | type0_tables | MonitoringTiming|DetectionProbability |
| F25 | Type0 multiplexing pattern | B | type0_tables | Offset|Timing|DetectionProbability |
| F26 | Type0 kSSB and channel-bandwidth edge cases | B | type0_tables | CORESETPlacement|InvalidCombinationRate |
| F27 | Common versus UE-specific RNTI procedures | A | direct | CorrectDecode|WrongProcedureRejection |
| F28 | Wrong-RNTI false alarm | A | direct | FalseAlarmProbability|UpperBound |
| F29 | Wrong DCI size and format confusion | A | direct | FalseDecode|ControlledRejection |
| F30 | No-signal false alarm | A | direct | FalseAlarmProbability|UpperBound |
| F31 | Low-SNR missed detection | A | direct | DetectionProbability|LowerBound |
| F32 | Delay spread and frequency selectivity | A | channel_model | DetectionProbability|ChannelEstimationNMSE |
| F33 | Doppler and channel ageing | A | channel_model | DetectionProbability|TrackingError |
| F34 | Carrier-frequency offset | A | sync_receiver | DetectionProbability|CFOEstimateError |
| F35 | Timing offset and acquisition | A | sync_receiver | DetectionProbability|TimingEstimateError |
| F36 | Phase noise | C | rf_phase_noise | DetectionProbability|EVM |
| F37 | PDCCH DM-RS ID mismatch | A | direct | FalseDecode|ChannelEstimationNMSE |
| F38 | Beam mismatch | B | beam_state | DetectionProbability|BeamGainLoss |
| F39 | TCI/beam switch timing | B | beam_state | OutageSlots|RecoveryLatency |
| F40 | Beam blockage and recovery | C | beam_failure_recovery | OutageProbability|RecoveryLatency |
| F41 | BWP switching | B | multi_bwp | CorrectBWPApplication|SwitchLatency |
| F42 | Cross-carrier scheduling | B | carrier_aggregation | CorrectCarrierApplication|WrongCarrierRejection |
| F43 | Overlapping CORESETs and RE conflicts | B | multi_coreset | CollisionCount|DetectionProbability |
| F44 | Multi-UE search-space load | B | multi_ue | Runtime|FalseAlarm|DetectionProbability |
| F45 | Decoded-DCI scheduler authority | A | direct | AssignmentDigestChange|OracleMutationImmunity |
| F46 | Downstream PDSCH/PUSCH resource fidelity | B | data_channel_integration | ResourceDigestMatch|DecodeSuccess |
| F47 | Blind versus known-location calibration gap | A | direct | SNRPenalty|RuntimePenalty |
| F48 | Runtime and memory scaling | A | direct | Runtime|Memory|CandidatesPerSecond |
| F49 | Serial/parallel reproducibility | A | direct | ArtifactHashEquality|MetricDifference |
| F50 | End-to-end Type0 SIB1 acquisition | C | ssb_sib1_chain | AcquisitionProbability|Latency |

Wave A is directly implementable in this PDCCH phase. Wave B requires internal multi-BWP/CA/beam/control-state work and remains mandatory for the corresponding selected profile. Wave C is fully specified but may be reported `blocked_dependency` until the adjacent real implementation exists; it must never be simulated with a scalar/proxy shortcut.

### Statistical requirements

- Wilson intervals for ordinary detection probability.
- Exact one-sided Clopper-Pearson upper bounds for zero-event no-signal/wrong-RNTI false alarms.
- McNemar tests for paired detection outcomes.
- Paired bootstrap confidence intervals for SINR penalty, estimation error, runtime, memory and continuous effects.
- Holm adjustment for related hypothesis families.
- Signed treatment-minus-baseline effects and predefined practical/equivalence margins.
- `inconclusive` when the stopping target is not met; no incomplete point may pass.

Generate all 16 impact CSVs and 28 impact PNGs, then run:

```bash
python tests/vectors/pdcch/verify_pdcch_impact_artifacts.py artifacts/pdcch_dci_impact
```

---


## 20A. Controlled-pair integrity for the 600 impact experiments

The supplied impact matrix contains 50 families, six baseline/treatment pairs per family, and exactly two rows per pair. Codex must preserve this structure.

For every pair:

```text
same seed
same trial index
same payload bits
same channel realization
same noise realization
same cell/BWP/CORESET/search-space context
same DCI format, aggregation level and SNR unless that exact item is FactorName
exactly one target factor differs
```

At runtime, materialize `ChannelRealizationID`, `NoiseRealizationID` and `PayloadID` before executing either member of a pair. Store them in both raw rows. Reject a pair if more than `FactorName` differs after canonicalizing the two configurations. Do not compare separately generated channel/noise draws and call the result paired.

`pdcch_impact_pairing_contract.csv` is executable. Add a MATLAB validator that joins every pair, removes the declared factor columns, and asserts equality of all remaining controlled columns. The Python impact verifier independently checks input/output factor identity and complete baseline/treatment coverage.

## 20B. Typed error catalogue — strict fail-closed behavior

Use stable error identifiers. Add or preserve these exact categories; a nearby generic warning is not sufficient:

```text
sixgr:phy:pdcch:unsupported_dci_format
sixgr:phy:pdcch:missing_dci_context
sixgr:phy:pdcch:missing_required_field
sixgr:phy:pdcch:unexpected_field
sixgr:phy:pdcch:field_not_integer
sixgr:phy:pdcch:field_out_of_range
sixgr:phy:pdcch:payload_length_mismatch
sixgr:phy:pdcch:dci_size_alignment_failure
sixgr:phy:pdcch:too_many_monitored_dci_sizes
sixgr:phy:pdcch:invalid_rnti_procedure
sixgr:phy:pdcch:crc_rnti_mismatch
sixgr:phy:pdcch:invalid_aggregation_level
sixgr:phy:pdcch:invalid_coreset_frequency_resources
sixgr:phy:pdcch:invalid_coreset_duration
sixgr:phy:pdcch:invalid_reg_bundle_size
sixgr:phy:pdcch:invalid_interleaver_size
sixgr:phy:pdcch:invalid_shift_index
sixgr:phy:pdcch:coreset_reg_collision
sixgr:phy:pdcch:invalid_search_space_periodicity
sixgr:phy:pdcch:invalid_monitoring_symbol_bitmap
sixgr:phy:pdcch:invalid_candidate_count
sixgr:phy:pdcch:candidate_count_exceeds_cce_groups
sixgr:phy:pdcch:monitoring_budget_exceeded
sixgr:phy:pdcch:type0_reserved_index
sixgr:phy:pdcch:type0_context_not_supported
sixgr:phy:pdcch:type0_searchspace_reserved_index
sixgr:phy:pdcch:no_type0_coreset_in_gscn_range
sixgr:phy:pdcch:known_location_forbidden_in_blind_profile
sixgr:phy:pdcch:oracle_timing_forbidden_in_blind_profile
sixgr:phy:pdcch:ambiguous_valid_hypotheses
sixgr:phy:pdcch:stale_bwp_context
sixgr:phy:pdcch:wrong_scheduled_carrier
sixgr:phy:pdcch:inactive_tci_state
sixgr:phy:pdcch:stale_beam_measurement
sixgr:phy:pdcch:decoded_event_required
sixgr:phy:pdcch:legacy_study_dependency_forbidden
```

For every typed negative test assert all of the following:

```text
ObservedError == ExpectedError
WaveformGenerated == false when failure precedes TX
DecodedDCIEventCreated == false
GrantCreated == false
SchedulerStateChanged == false
HARQStateChanged == false
```

## 20C. Exact full Type-0 implementation sequence

Implement Type-0 in this order:

1. Parse `pdcch-ConfigSIB1` into `controlResourceSetZero` and `searchSpaceZero` without coercion.
2. Select exactly one CORESET table from 13-0 through 13-10A using frequency range, SSB SCS, PDCCH SCS, minimum/channel bandwidth, shared-spectrum state and selected release.
3. Resolve multiplexing pattern, RB count, symbol count and offset, including `k_SSB` conditional negative offsets.
4. Reject every reserved index and every table/context mismatch.
5. For pattern 1, resolve O, M, number of search-space sets per slot and first symbol using Tables 13-11, 13-12 or 13-12A.
6. For patterns 2 and 3, use Tables 13-13 through 13-15A and the actual SS/PBCH block index/timing.
7. Apply Tables 13-16/17 only for the specified absent-CORESET indication procedure; never use those offsets for an ordinary valid CORESET0 row.
8. Derive all monitoring occasions over at least two radio frames and compare every slot/symbol to the independent vectors.
9. Build the SI-RNTI DCI 1_0 context from the initial DL BWP and monitored Type-0 format set; do not use 32 fixed bits.
10. Enumerate the configured candidate set and execute the same blind receiver used by connected mode.

## 20D. Independent-oracle completion matrix

The supplied pure-spec floor covers CRC24C/RNTI masking, Gold scrambling, QPSK, PDCCH DM-RS, basic 0_0/1_0 sizing, CORESET mapping, candidate enumeration, monitoring arithmetic, Type-0 tables, GSCN offsets and causal grant authority.

Before completion add versioned independent or frozen vectors for:

```text
full contextual DCI 0_1 field layout and size
full contextual DCI 1_1 field layout and size
0_0/1_0 alignment edge cases with different initial/active UL/DL BWPs
Polar reliability/frozen-bit construction
DCI input interleaving
Polar mother-code output
sub-block interleaving
puncturing, shortening and repetition rate matching
soft rate recovery
PDCCH candidate DM-RS extraction under both precoder granularities
monitoring-capability counting and overlapping-candidate deduplication
BWP indicator and carrier-indicator semantic reconstruction
TCI/QCL activation timing
```

Each oracle row must identify `OracleClass`, implementation or generator version, artifact SHA-256 and mismatch count. A wrapper around the same MATLAB function used by the DUT is `self_consistency`, not `independent`.

## 20E. Required image semantics

Do not create decorative figures. Every required image must answer a technical question and be generated from the contracted CSV named in the image contract. In addition to decoding and nonblank checks, the semantic audit must record MATLAB figure-object properties before `exportgraphics`:

```text
actual title
actual x label
actual y label
axes count
line/scatter/image-series count
finite plotted point count
source CSV SHA-256
PNG SHA-256
image width and height
```

The added `pdcch_dmrs_sequence_correlation.png` must show correct-identity autocorrelation and wrong-ID/slot/symbol cross-correlation from production DM-RS sequences. It cannot be generated from the expected vector CSV alone.

## 21. Required execution commands

At minimum:

```bash
python tests/vectors/pdcch/verify_pdcch_vector_pack.py
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PDCCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*DCI*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.pdcch.runPDCCHPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','pdcch'),'OutputDir',fullfile(pwd,'artifacts','pdcch_dci_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/pdcch/verify_pdcch_artifacts.py artifacts/pdcch_dci_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.pdcch.runPDCCHImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','pdcch','pdcch_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','pdcch_dci_impact'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/pdcch/verify_pdcch_impact_artifacts.py artifacts/pdcch_dci_impact
```

Run the full repository regression suite after the focused suites.

---

## 22. Prohibited completion shortcuts

Codex must not report `COMPLETE` if any of these occurs:

- DCI size is derived from one `NSizeGrid` scalar or a fixed sum;
- missing fields default to zero;
- payloads are padded/truncated to fit K;
- invalid values are clamped/floored;
- connected PDSCH/PUSCH uses configured/oracle grants;
- strict blind monitoring receives the transmitted CCE or falls back to `nrPDCCHResources` known-location indices;
- only one RNTI, format, AL or candidate is attempted;
- candidate CCE is reported as loop index;
- `HashFunction6GR` or approximate interleaving remains in strict dependencies;
- AL32 or non-QPSK PDCCH is accepted;
- Type0 remains fixed to 30 kHz/index zero/AL4/one candidate/32 bits;
- wrong RNTI, no signal or CRC failure creates an assignment or state change;
- a same-Toolbox comparison is labelled independent;
- a mandatory statistical point is incomplete;
- any required CSV/PNG is absent or fails semantic/hash checks;
- MATLAB/5G Toolbox is unavailable or a mandatory test is blocked.

---

## 23. Definition of done

This phase is complete only when:

1. all 14 findings are technically closed for the selected profile;
2. all confirmed source shortcuts are removed from the production path;
3. exact 0_0/0_1/1_0/1_1 contextual schemas and size alignment pass;
4. CRC, Polar, scrambling, QPSK, DM-RS and RE mapping pass independent vectors;
5. every selected CORESET/search-space/AL/candidate/RNTI tuple executes through one production TX/RX chain;
6. blind strict tests use no oracle location/timing;
7. Type0 table and monitoring tests pass;
8. BWP/cross-carrier/beam selected-profile tests pass;
9. decoded DCI is the sole dynamic grant authority;
10. no-signal/wrong-RNTI/low-SNR campaigns meet confidence targets with no incomplete points;
11. all 37 CSVs and 41 PNGs pass both verifiers;
12. the full MATLAB regression suite passes on the pinned toolchain.

At the end of every Codex response report:

```text
phase and finding IDs
files changed
canonical stack and removed/isolated legacy paths
DCI formats and contexts implemented
RNTI/search-space matrix implemented
exact commands executed
MATLAB and Toolbox versions
test pass/fail/skip/block counts
blind trials and incomplete-point count
independent vector families and mismatch counts
CSV row counts and SHA-256 values
PNG dimensions and SHA-256 values
verifier exit codes
open technical dependencies
COMPLETE / FAIL / BLOCKED
```
