# Codex implementation prompt 02 — PDSCH and DL-SCH complete MATLAB PHY chain

You are working directly in the root of the **6GR MATLAB simulator** repository.

This is an **implementation and execution task**. It is not an audit, review, design memo, standards-claim exercise, documentation-only task, schema-only task, or request for a plan.

Your job is to:

1. modify the production MATLAB source;
2. replace the current PDSCH/DL-SCH shortcuts with an explicit executable PHY chain;
3. migrate every production caller to the corrected chain;
4. add independent bit-, symbol-, RE-, coding-, HARQ-, and receiver-level tests;
5. run the tests on the pinned MATLAB/5G Toolbox release;
6. generate the required CSV and PNG artifacts from actual production execution;
7. run the supplied Python verifiers;
8. keep fixing the implementation until every mandatory check passes.

Do not return a plan. Do not stop after adding classes or tests. Do not report `COMPLETE` unless all mandatory MATLAB tests execute and pass, all required artifacts are generated, and both supplied Python verifiers return exit code 0.

---

## 1. Scope

Fix the complete PDSCH and DL-SCH chain and only the minimum adjacent interfaces needed to make it real and executable:

1. dynamic decoded-DCI and activated downlink-SPS scheduling ownership;
2. DCI/RRC/BWP-to-PDSCH configuration resolution;
3. exact PDSCH resource allocation;
4. PDSCH data scrambling;
5. QPSK, 16QAM, 64QAM, 256QAM, and normative Release-18 1024QAM modulation/demodulation;
6. one- and two-codeword codeword-to-layer mapping for rank 1 through rank 8;
7. PDSCH DM-RS configuration, sequence generation, ports, indices, and channel-estimation use;
8. PDSCH PT-RS configuration, sequence generation, indices, and receiver common-phase-error correction;
9. transport-block sizing;
10. TB CRC, code-block segmentation, CB CRC, LDPC encoding, rate matching, and concatenation;
11. inverse DL-SCH receive processing;
12. exact reserved-resource and rate-matching behavior;
13. wideband and frequency-selective PRG precoding application;
14. PDSCH receiver extraction, estimation, equalization, LLR generation, descrambling, and decoding;
15. codeword-specific HARQ process state and position-aware soft combining;
16. active-BWP, component-carrier, TCI/QCL, and bounded multi-TRP PDSCH integration;
17. deterministic CSV and PNG diagnostics generated from the real execution path.

Do not spend this phase implementing broad PDCCH blind search, CSI codebook selection, beam-management policy, channel-model statistics, RF-device conformance, RLC/PDCP/RRC breadth, WebGUI, security, marketing claims, or publication wording. PDCCH decoding, UE context, MIMO selection, channel, and RF modules may be touched only to expose the exact technical interfaces needed by PDSCH.

The frame/grid/numerology/duplexing phase is a dependency. Reuse its canonical carrier, BWP, slot, symbol, and timing objects. Do not recreate local 14-symbol, full-grid, or scalar-BWP assumptions inside PDSCH. If the dependency has not yet been merged, implement a narrow adapter against the current frame API without restoring any shortcut described below.

---

## 2. Mandatory standards baseline

Pin this phase to the repository's declared Release-18 maintenance baseline. If no exact versions are already pinned, use these consistently and record them in the MATLAB test output:

- **3GPP TS 38.211 V18.8.0**
  - clause 5.1 modulation mapping;
  - clause 5.2.1 pseudo-random sequence generation;
  - clause 7.3.1 PDSCH scrambling, modulation, layer mapping, and resource mapping;
  - clause 7.4.1.1 PDSCH DM-RS;
  - clause 7.4.1.2 PDSCH PT-RS.
- **3GPP TS 38.212 V18.8.0**
  - CRC calculation;
  - LDPC base graphs and encoding;
  - LDPC rate matching and rate recovery;
  - DL-SCH transport-block CRC, code-block segmentation, coding, and concatenation.
- **3GPP TS 38.214 V18.8.0**
  - PDSCH MCS table selection;
  - transport-block size determination;
  - frequency-domain and time-domain PDSCH resource allocation;
  - antenna-port/layer/DM-RS procedures;
  - PDSCH PT-RS time and frequency density procedures;
  - HARQ-related scheduling fields used by PDSCH.
- **3GPP TS 38.213 V18.8.0**
  - PDCCH-to-PDSCH timing and PDSCH reception constraints used by the assignment resolver.
- **3GPP TS 38.331 V18.8.0**
  - `PDSCH-Config`;
  - `PDSCH-ConfigCommon`;
  - `DMRS-DownlinkConfig` for mapping types A and B;
  - `PTRS-DownlinkConfig`;
  - BWP, serving-cell, rate-match-pattern, MCS-table, data-scrambling-identity, HARQ-process, and TCI state configuration.

When a MATLAB 5G Toolbox function supports a broader or narrower release than this baseline, the pinned 3GPP profile is authoritative. Add a version adapter or custom implementation rather than silently changing the requested standard behavior.

Do not treat 4096QAM as normative NR PDSCH in this strict profile. Release-18 1024QAM is normative only under the applicable capability, RRC, MCS-table, DCI, frequency-range, and deployment conditions. Implement those conditions explicitly; do not enable 1024QAM merely because a string says `1024QAM`.

---

## 3. Execution profiles and state ownership

Implement three technically distinct entry paths. They must not fall back into one another.

### 3.1 `connected_strict`

A dynamically scheduled PDSCH transmission is legal only when it is derived from:

- a decoded DCI event whose CRC passed;
- the correct decoded RNTI and RNTI type;
- the active serving-cell and BWP context for the same configuration epoch;
- the frame/timing state for the scheduled absolute slot;
- the UE capability state;
- the HARQ process state;
- activated TCI/QCL state where required.

A nested configuration struct, scheduler intent, configured MCS, or precomputed PRB set must not directly create a dynamically scheduled connected PDSCH transmission.

### 3.2 `sps_strict`

Downlink semi-persistent scheduling is the valid exception to requiring a newly decoded DCI on every PDSCH occasion. An SPS PDSCH is legal only when it is derived from all of:

- an RRC-configured SPS resource and periodicity for the active serving cell/BWP;
- a prior CRC-valid SPS activation DCI decoded for the correct CS-RNTI/C-RNTI procedure;
- an active, not released SPS context at the same configuration epoch;
- an absolute slot that is an exact SPS occasion;
- the SPS HARQ, NDI, RV, MCS, resource, TCI/QCL, and timing state applicable to that occasion.

Do not treat the mere presence of an SPS RRC configuration as activation. Do not synthesize an activation event. Deactivation/release must prevent waveform generation. The assignment must preserve the activation DCI event ID and SPS context epoch.

### 3.3 `ra_si_strict`

SI-RNTI, P-RNTI, RA-RNTI, TC-RNTI, and other common-search-space procedures must use their valid DCI/RNTI procedure state. They must not inherit C-RNTI-only fields, PT-RS behavior, MCS-table selection, HARQ semantics, or scrambling identities.

### 3.4 `phy_calibration`

A direct deterministic assignment may be created only by an explicit calibration factory. It must be a typed assignment object with every required field specified. Missing fields must fail. It may be used by AWGN unit tests and link-calibration campaigns, but it must never be accepted by `connected_strict`, `sps_strict`, or emitted as a decoded connected/SPS assignment.

Do not implement a boolean such as `allowConfiguredGrantInStrictMode`. Separate factory functions and separate MATLAB types or immutable source tags are required.

---

## 4. Supplied implementation and test pack

Copy the following files into `tests/vectors/pdsch/` without changing their values merely to make the implementation pass:

### 4.1 Generator and integrity tools

- `generate_pdsch_independent_vectors.py`
- `verify_pdsch_vector_pack.py`
- `verify_pdsch_artifacts.py`
- `independent_vector_manifest.json`
- `expected_output_integrity_audit.csv`

Run:

```bash
python tests/vectors/pdsch/verify_pdsch_vector_pack.py
```

before running MATLAB. It must return exit code 0.

### 4.2 Input vectors

- `pdsch_scrambling_test_vectors.csv` — 12 rows
- `pdsch_modulation_test_vectors.csv` — 24 rows
- `pdsch_layer_mapping_test_vectors.csv` — 12 rows
- `pdsch_coding_tbs_test_vectors.csv` — 23 rows
- `pdsch_dmrs_test_vectors.csv` — 175 rows
- `pdsch_scheduling_assignment_test_vectors.csv` — 22 rows
- `pdsch_ptrs_test_vectors.csv` — 56 rows
- `pdsch_reserved_re_test_vectors.csv` — 14 rows
- `pdsch_precoding_prg_test_vectors.csv` — 15 rows
- `pdsch_harq_test_vectors.csv` — 11 rows
- `pdsch_declared_coverage_matrix.csv` — 16 mandatory end-to-end rows

The supplied rows are a mandatory floor, not the complete test matrix. Add generated pairwise and boundary coverage where required below.

### 4.3 Independent expected results

- `expected_pdsch_scrambling_vectors.csv`
- `expected_pdsch_modulation_vectors.csv`
- `expected_pdsch_layer_mapping.csv`
- `expected_pdsch_tbs_basegraph.csv`
- `expected_pdsch_tb_crc_vectors.csv`
- `expected_pdsch_dmrs_symbol_positions.csv`
- `expected_pdsch_dmrs_port_table.csv`
- `expected_pdsch_assignment_resolution.csv`
- `expected_pdsch_ptrs_presence.csv`
- `expected_pdsch_reserved_re_union.csv`
- `expected_pdsch_precoding_behavior.csv`
- `expected_pdsch_harq_transitions.csv`

These expected files were generated without MATLAB or 5G Toolbox. The MATLAB tests must invoke the production implementation and compare actual results field by field. Do not copy these expected files to the output directory and call the test complete.

### 4.4 Required output contracts

- `desired_pdsch_csv_contract.csv`
- `desired_pdsch_image_contract.csv`

The production phase runner must generate every contracted CSV and PNG. The supplied artifact verifier is fail-closed.

---

## 5. Current production defects that must be removed

The following are source-visible implementation shortcuts in the uploaded repository. Search the current tree before editing because line numbers may move.

### 5.1 Configured grants and missing-allocation defaults

- `+sixgr/+link/resolveWaveformGrant.m`
  - creates a waveform grant from configuration before DCI is materialized;
  - labels it `explicit_waveform_grant`;
  - replaces a missing PRB allocation with the full grid;
  - replaces a missing symbol allocation with `[0 14]`.
- `+sixgr/+control/isPDCCHGrantBindingRequired.m`
  - makes PDCCH-to-PDSCH binding optional through policy flags.
- `+sixgr/+phy/+dl/PDSCH_Tx.m`
  - may build a connected PDSCH directly from a nested config or frozen grant without a decoded assignment.

Remove these paths from dynamic connected strict execution. Do not preserve them behind another default flag. For SPS, replace bare configuration ownership with an activated SPS context whose activation DCI and RRC configuration are both explicit.

### 5.2 DM-RS mutation and clamping

`+sixgr/+phy/+grid/allocREsPDSCH.m` currently:

- overwrites `DMRSPortSet` with `0:(NumLayers-1)`;
- clamps `DMRSTypeAPosition` into 2–3;
- clamps `DMRSConfigurationType` into 1–2;
- clamps `DMRSAdditionalPosition` into 0–3;
- clamps `DMRSLength` into 1–2;
- clamps `NumCDMGroupsWithoutData` into 1–3;
- may change an invalid mapping-type-A allocation into mapping type B.

Replace every clamp or mutation with table-driven validation. Valid non-consecutive DM-RS ports must be preserved. Invalid combinations must raise typed errors before any waveform is generated.

### 5.3 Modulation and codeword shortcuts

`+sixgr/+phy/+grid/allocREsPDSCH.m` currently:

- defaults a missing modulation to QPSK;
- repeats the final modulation entry when a two-codeword list is short;
- truncates an overlong modulation list.

Remove all three behaviors. The MCS resolver must produce the exact modulation and target code rate for each enabled transport block/codeword. A missing or inconsistent list must fail.

### 5.4 PT-RS defaults

`+sixgr/+phy/+grid/allocREsPDSCH.m` currently:

- defaults PT-RS time density to 2;
- defaults PT-RS frequency density to 2;
- defaults RE offset to `00`;
- defaults the PT-RS port to 0;
- rounds and clamps density values.

Remove the defaults from strict paths. Resolve presence and values from higher-layer configuration, MCS table, scheduled bandwidth, allocation duration, RNTI procedure, and associated DM-RS port.

### 5.5 Precoder limitations and mutation

`+sixgr/+phy/+dl/resolvePDSCHPrecoding.m` currently:

- rejects three-dimensional/per-PRG precoder bundles;
- rejects valid custom DM-RS port values because it expects `0:(NumLayers-1)`;
- may discard an explicit matrix and regenerate a wideband matrix from scalar PMI;
- treats a scalar PMI as if it were sufficient evidence of the applied frequency-selective precoder.

Implement a real precoder bundle and preserve the matrix supplied for every PRG and symbol group.

### 5.6 Reconstructed resource accounting

`+sixgr/+phy/+resource/computeResourceAccounting.m` currently:

- reconstructs `NREPerPRB` by dividing and flooring when exact index evidence is absent;
- reconstructs `G` from layer RE, modulation order, and layer counts as a fallback;
- recomputes multi-codeword `G` when a scalar is present.

Replace fallback reconstruction with one authoritative resource plan produced before coding. `G`, per-codeword `E`, DM-RS RE, PT-RS RE, reserved RE, and data RE must come from the exact final ownership/index map. A missing plan is an error.

### 5.7 Post-generation collision handling

`+sixgr/+phy/+dl/PDSCH_Tx.m` currently checks CSI-RS collision after PDSCH indices and symbols have already been generated. It also has a catch-all manual zero-grid fallback if `nrResourceGrid` fails.

Create one pre-transmission ownership map. Remove the catch-all grid fallback. The allocation must be legal before coding begins.

### 5.8 Metadata-only duplicate chain

Several files under `+sixgr/+pdsch/` currently report metadata instead of executing the transform:

- `PDSCHScrambler.m` says scrambling happened inside `nrPDSCH`;
- `PDSCHModulator.m` reports modulation metadata;
- `DLSCHEncoder.m` summarizes another path;
- `CodewordLayerMapper.m` emits a trace table rather than mapping actual symbols.

Promote `+sixgr/+pdsch/` to the canonical production chain. Replace metadata-only functions with actual bit/symbol transforms. Keep `+sixgr/+phy/+dl/PDSCH_Tx.m` and `PDSCH_Rx.m` as compatibility façades that delegate to the canonical chain.

### 5.9 Allocation shortcuts in the study path

- `+sixgr/+pdsch/FDRAAllocator.m` changes the allocation type according to retransmission index parity when configured as `dynamic`.
- `+sixgr/+pdsch/TDRAAllocator.m` assumes a 14-symbol slot and reports cross-slot materialization as disabled.
- `runPDSCHStudyLLS.m` constructs PDSCH state from configuration and may back off MCS to make a queue fit.

These may remain only in an explicitly labelled study/calibration scheduler. They must not own connected strict PHY state. TDRA must use the canonical frame object and cyclic-prefix-dependent symbol count.

### 5.10 Same-implementation tests

Existing tests frequently compare production output with the same MATLAB 5G Toolbox primitive used by production, for example `nrPDSCH`, `nrPDSCHIndices`, `nrPDSCHPrecode`, `nrTBS`, or the same `nrDLSCH` object.

Keep these tests as regression checks, but do not count them as independent bit-exact evidence. Add the independent checks required in section 18.

---

## 6. Required target architecture

Do not add another parallel PDSCH stack. Consolidate the existing `+sixgr/+pdsch/` package into the canonical implementation. A recommended structure is:

```text
+sixgr/+pdsch/
    PDSCHSchedulingAssignment.m
    PDSCHAssignmentFactory.m
    PDSCHUEContext.m
    PDSCHSPSContext.m
    PDSCHResourcePlan.m
    PDSCHResourceOwnershipMap.m
    PDSCHConfigMaterializer.m
    PDSCHMCSResolver.m
    PDSCHDMRS.m
    PDSCHPTRS.m
    PDSCHScrambler.m
    PDSCHModulator.m
    CodewordLayerMapper.m
    DLSCHCodingPlan.m
    DLSCHEncoder.m
    DLSCHDecoder.m
    PDSCHPrecoderBundle.m
    PDSCHGridMapper.m
    PDSCHTransmitter.m
    PDSCHReceiver.m
    PDSCHHARQContext.m
    PDSCHHARQManager.m
    PDSCHArtifactExporter.m
    runPDSCHPhaseValidation.m
    +oracle/
        GoldSequenceSpec.m
        QAMMapperSpec.m
        LayerMapperSpec.m
        CRCSpec.m
        TBSAndBaseGraphSpec.m
        LDPCSegmentationSpec.m
        LDPCRateMatchingIndexSpec.m
        DMRSTableSpec.m
        DMRSSequenceSpec.m
        PTRSIndexSpec.m
        ReservedREUnionSpec.m
        PrecodingMultiplySpec.m
```

Exact names may follow repository conventions, but these separations are mandatory:

- decoded scheduling state is not configuration state;
- resource ownership is resolved before coding;
- TBS and coding are derived from the resolved resource plan;
- codeword state is separate for codeword 0 and codeword 1;
- DM-RS ports are not physical antenna indices;
- precoding is an explicit tensor with a PRG/symbol map;
- transmitter and receiver consume the same immutable assignment and resource plan;
- HARQ state is owned by an explicit process context;
- independent oracle code must not call production functions or `nr*` functions.

Use zero-based NR indices in all PHY-facing objects. Convert to one-based MATLAB indices only at array-access or Toolbox-call boundaries. Every CSV must state or structurally enforce the index convention.

---

## 7. Canonical scheduling-assignment object

Implement an immutable `PDSCHSchedulingAssignment` value object. It must contain at least:

```text
AssignmentId
Profile
UEId
RNTI
RNTIType
ServingCellId
SchedulingCellId
CCId
BWPId
ConfigurationEpoch
PDCCHAbsoluteSlot
PDSCHAbsoluteSlot
DecodedDCIId
DCIFormat
DCICRCPass
DecodedRNTI
DCIRNTIMatch
SearchSpaceId
CORESETId
FDRAType
FrequencyDomainAssignmentRaw
RBGSize
VRBToPRBMapping
InterleaverBundleSize
PRBSetBWPRelative
PRBSetCarrierRelative
TDRAListId
TDRARowIndex
K0
SLIV
SymbolAllocation
MappingType
MCSTablePerCodeword
MCSIndexPerCodeword
ModulationPerCodeword
QmPerCodeword
TargetCodeRatePerCodeword
TBScalingPerCodeword
XOverhead
NumLayers
NumCodewords
LayerCountPerCodeword
AntennaPortField
DMRSConfigId
DMRSPortSet
PTRSConfigId
PTRSPortSet
NDIPerCodeword
RVPerCodeword
HARQProcessId
DAI
TCIStateId
RateMatchPatternIds
ZPCSIRSResourceIds
TransmissionConfigurationIndication
SPSConfigId
SPSActivationDCIId
SPSActivationDCICRCPass
SPSActivationDCIRNTIMatch
SPSConfigurationEpoch
SPSActivated
SPSReleased
SPSOccasionIndex
Source
```

### Construction functions

Implement separate constructors or factories:

```matlab
assignment = sixgr.pdsch.PDSCHAssignmentFactory.fromDecodedDCI( ...
    decodedDCI, ueContext, frameState, harqState)

assignment = sixgr.pdsch.PDSCHAssignmentFactory.fromSPSOccasion( ...
    spsContext, ueContext, frameState, harqState)

assignment = sixgr.pdsch.PDSCHAssignmentFactory.forCalibration( ...
    explicitCalibrationRequest, frameState)
```

`fromDecodedDCI` must reject:

- missing decoded DCI;
- failed DCI CRC;
- RNTI mismatch;
- invalid DCI/RNTI combination;
- stale UE configuration epoch;
- inactive serving cell or BWP;
- invalid or unavailable scheduled resources;
- unsupported MCS-table/capability context;
- invalid HARQ process state;
- inactive TCI state where required;
- out-of-range DCI fields.

`fromSPSOccasion` must reject:

- missing SPS RRC configuration;
- missing or CRC-failed activation DCI evidence;
- an activation DCI decoded for the wrong RNTI procedure;
- an SPS context that was never activated or has been released;
- a stale SPS/UE/BWP configuration epoch;
- an absolute slot that is not an SPS occasion;
- an inconsistent SPS HARQ/NDI/RV/resource/MCS/TCI context.

No error path may produce a waveform.

### Typed errors

Use stable MATLAB identifiers under one namespace. At minimum:

```text
sixgr:pdsch:MissingDecodedDCI
sixgr:pdsch:DCICRCFailed
sixgr:pdsch:DCIRNTIMismatch
sixgr:pdsch:InvalidDCIRNTIProcedure
sixgr:pdsch:MissingActiveBWPContext
sixgr:pdsch:StaleUEConfigurationEpoch
sixgr:pdsch:InactiveServingCell
sixgr:pdsch:ScheduledResourceUnavailable
sixgr:pdsch:UnsupportedMCSContext
sixgr:pdsch:HARQContextMismatch
sixgr:pdsch:TCIStateNotActivated
sixgr:pdsch:DCIFieldOutOfRange
sixgr:pdsch:MissingSPSConfiguration
sixgr:pdsch:MissingSPSActivationDCI
sixgr:pdsch:SPSActivationDCICRCFailed
sixgr:pdsch:SPSActivationDCIRNTIMismatch
sixgr:pdsch:SPSNotActivated
sixgr:pdsch:SPSReleased
sixgr:pdsch:NotSPSOccasion
```

The test vectors contain short error tokens. The MATLAB tests must map them deterministically to the full identifier `sixgr:pdsch:<token>`.

---

# Work item 1 — Replace configured grants with decoded assignment ownership

## Implement

1. Make `PDSCH_Tx` require a `PDSCHSchedulingAssignment` in `connected_strict`, `sps_strict`, and `ra_si_strict`.
2. Remove all connected-path reads of:
   - `phy.pdsch.PRBSet` as a grant;
   - `phy.pdsch.SymbolAllocation` as a grant;
   - configured MCS as a decoded grant;
   - nested frozen-grant structs without a decoded DCI ID.
3. Change `resolveWaveformGrant` so it resolves a waveform request from the assignment, not the reverse.
4. Make PDCCH binding intrinsic in connected strict mode. Delete or bypass `isPDCCHGrantBindingRequired` for this path.
5. Preserve the isolated calibration path through `forCalibration`.
6. Implement `fromSPSOccasion`; it must consume an activated SPS context and must never create SPS ownership from bare RRC configuration.
7. Record the exact decoded-DCI event ID, or SPS activation-DCI event ID, and UE/SPS context epoch in TX and RX output.
8. Make the assignment immutable after construction. No TX function may change PRBs, symbols, mapping type, MCS, DM-RS ports, PT-RS settings, NDI, RV, or TCI.

## Tests

Add `tests/testPDSCHSchedulingAssignment.m` and load all 22 supplied assignment rows.

For every row:

- construct the specified decoded DCI and UE context;
- invoke the production factory;
- compare status, error, source, and waveform permission against `expected_pdsch_assignment_resolution.csv`;
- snapshot the input objects before the call and prove no input field was mutated;
- for errors, prove that no resource plan, codeword, grid, or waveform object was created.

Add a production integration test that sends a decoded DCI event through the real PDCCH-to-PDSCH interface and proves the resulting assignment ID appears unchanged in the PDSCH TX and RX records.

Add `tests/testPDSCHSPSAssignment.m` and prove:

- a valid RRC configuration plus CRC-valid activation DCI creates assignments only on exact SPS occasions;
- bare RRC configuration without activation creates no waveform;
- a CRC-failed activation DCI creates no SPS context and no waveform;
- an activation DCI for the wrong RNTI procedure creates no SPS context and no waveform;
- release/deactivation immediately prevents later SPS occasions;
- activation DCI ID, SPS configuration ID, epoch, NDI, HARQ process, resources, and MCS remain unchanged through TX and RX;
- an SPS assignment can never enter through `forCalibration` or a nested configured-grant struct.

---

# Work item 2 — Exact DCI/RRC/BWP-to-PDSCH configuration resolution

## Implement frequency-domain allocation

Support the frequency-domain allocation schemes declared by the selected profile:

- type-0 RBG bitmap with exact RBG-size determination;
- type-1 RIV decoding;
- BWP-relative VRB allocation;
- interleaved and non-interleaved VRB-to-PRB mapping where applicable;
- carrier-relative PRB materialization after BWP offset;
- cross-carrier scheduling through explicit scheduling-cell/scheduled-cell IDs.

Do not use `0:(NSizeGrid-1)` when a field is missing. Do not alternate allocation type according to retransmission parity. Do not sort or deduplicate an invalid decoded allocation into a different valid allocation.

## Implement time-domain allocation

Resolve:

- the correct PDSCH time-domain allocation list;
- the selected table row;
- K0;
- SLIV or explicit start/length;
- mapping type A or B;
- cyclic-prefix-dependent slot length;
- slot-format and channel-availability legality through the canonical frame engine.

Do not use `[0 14]` as a fallback. Do not change mapping type A to B. Do not assume 14 symbols when extended CP is active.

## Implement MCS resolution

Create one table-driven `PDSCHMCSResolver` that outputs, per codeword:

```text
MCS table identity
MCS index
Qm
modulation name
target code rate
spectral efficiency
capability condition
RRC/DCI selection source
```

Cover all selected-profile MCS tables, including the applicable Release-18 1024QAM table. Enforce reserved MCS entries, DCI format, RNTI procedure, RRC table selection, UE capability, frequency-range/deployment restrictions, and two-codeword fields.

Reject:

- missing MCS table;
- MCS index outside the selected table;
- reserved table entries;
- 1024QAM without all enabling conditions;
- 4096QAM in the strict NR profile;
- one modulation/rate entry for a two-codeword assignment when two are required;
- more entries than enabled codewords.

## Materialize `nrPDSCHConfig`

Create `PDSCHConfigMaterializer.fromAssignment`. It may populate an `nrPDSCHConfig` object for Toolbox kernels, but every property must come from the immutable assignment/resource plan. No property may be corrected through `min`, `max`, rounding, catch/retry, or default substitution.

## Tests

Add:

- `testPDSCHFDRAFromDecodedDCI.m`;
- `testPDSCHTDRAFromDecodedDCI.m`;
- `testPDSCHMCSResolver.m`;
- `testPDSCHConfigMaterializerNoMutation.m`.

Include positive and negative cases for BWP offsets, type-0/type-1, interleaving, invalid RIV, invalid bitmap length, mapping A/B, normal and extended CP, reserved MCS rows, and enabled/disabled 1024QAM.

---

# Work item 3 — Complete PDSCH DM-RS implementation

## Implement configuration validation

Implement the exact selected-release matrix for:

- mapping type A and mapping type B;
- type-A position 2 and 3;
- DM-RS configuration type 1 and 2;
- single-symbol and double-symbol front-loaded DM-RS;
- additional-position combinations as a function of mapping type, `l_d`, length, and type-A position;
- basic and selected-profile enhanced DM-RS multiplexing;
- `NumCDMGroupsWithoutData` legality;
- `NIDNSCID` and `NSCID`;
- antenna-port field to DM-RS port resolution;
- non-consecutive valid port sets;
- the relation between number of layers and number of selected DM-RS ports.

Do not infer ports as `0:(NumLayers-1)` unless that exact set was resolved from the antenna-port field. Preserve configured/decoded port values.

## Implement sequence and mapping

Generate the DM-RS sequence according to TS 38.211, including:

- exact Gold-sequence initialization;
- slot and OFDM-symbol dependence;
- `NIDNSCID`/`NSCID` selection;
- frequency-domain mapping for configuration types 1 and 2;
- `delta`, CDM group, frequency-domain weight, and time-domain weight for each port;
- front-loaded and additional DM-RS symbols;
- zero-based index output.

The production implementation may use `nrPDSCHDMRS` and `nrPDSCHDMRSIndices` as optimized kernels after explicit validation, but an independent oracle under `+oracle/` must compute the selected vector cases without calling either function.

## Tests

Add:

- `testPDSCHDMRSSymbolPositionVectors.m` using all 175 supplied rows;
- `testPDSCHDMRSPortTableVectors.m` using all 108 expected port rows;
- `testPDSCHDMRSSequenceIndependent.m` over multiple cell IDs, slots, symbols, `NSCID`, scrambling IDs, configurations, and ports;
- `testPDSCHDMRSNoMutation.m`;
- `testPDSCHDMRSInvalidCombinations.m`.

For each valid case compare:

- symbol locations;
- zero-based RE indices;
- port number;
- CDM group;
- delta;
- sequence length;
- complex sequence samples or digest;
- exact data/DM-RS disjointness.

For every invalid case require a typed error before waveform generation.

Do not count a comparison between two calls to the same Toolbox function as the independent result.

---

# Work item 4 — Complete PDSCH PT-RS implementation and receiver correction

## Implement PT-RS presence resolution

Resolve presence from the exact selected-release procedure, including:

- higher-layer PT-RS configuration;
- RNTI/procedure restrictions;
- selected MCS table and MCS index thresholds;
- scheduled PRB threshold;
- PDSCH allocation duration;
- time density values allowed by the standard;
- frequency density values allowed by the standard;
- RE offset;
- associated DM-RS port and PT-RS port set;
- collisions with DM-RS and reserved resources.

Do not invent time density, frequency density, RE offset, or port values. A configured but invalid value must fail. A standards-defined not-present condition is a valid result with a reason, not an error.

## Implement sequence and indices

Generate the exact PT-RS sequence and zero-based indices. Add an independent index oracle that does not call `nrPDSCHPTRSIndices`.

## Implement receiver common-phase-error correction

At the receiver:

1. extract PT-RS using the resolved plan;
2. estimate common phase error per supported symbol/port;
3. interpolate or hold the estimate according to the selected receiver design;
4. rotate data and the relevant reference observations consistently;
5. expose pre/post CPE error and EVM.

The PT-RS test must use an actual phase-noise impairment. It is not sufficient to show that PT-RS REs exist.

## Tests

Add:

- `testPDSCHPTRSPresenceVectors.m` using all 56 supplied rows;
- `testPDSCHPTRSIndicesIndependent.m`;
- `testPDSCHPTRSPortAssociation.m`;
- `testPDSCHPTRSPhaseNoiseBenefit.m`.

The phase-noise test must include at least four severity points and prove, for the declared operating points, that enabled PT-RS does not worsen absolute CPE or EVM beyond a stated numerical tolerance and improves both at nonzero impairment severity.

---

# Work item 5 — One exact resource-ownership map and reserved-RE implementation

## Implement one ownership map

Create `PDSCHResourceOwnershipMap` over the scheduled carrier/BWP, slot, symbol, subcarrier, and logical port dimensions. Every RE in or affecting the PDSCH allocation must receive one resolved status, for example:

```text
outside_pdsch_allocation
unavailable_by_frame_direction
reserved_ssb
reserved_coreset_pdcch
reserved_rate_match_pattern
reserved_zp_csi_rs
reserved_nzp_csi_rs
reserved_lte_crs
reserved_other
pdsch_dmrs
pdsch_ptrs
pdsch_data
```

Model the exact release-defined rate-matching behavior for each resource type. Do not solve collisions by arbitrary owner priority. A resource may be excluded from PDSCH data when the standard requires rate matching; an illegal overlap must fail.

Resolve all reservations before TBS and coding. Delete post-generation CSI-RS collision repair.

## Exact resource plan

Create `PDSCHResourcePlan` containing:

```text
PRB set
symbol allocation
data indices per layer
DM-RS indices per port
PT-RS indices per port
reserved-union indices
NRE per PRB used by TBS
exact data RE count
layer counts per codeword
G per codeword
E per code block
all overlap counts
all duplicate-index counts
```

`G` must be calculated from the authoritative final data RE map, modulation order, and codeword layer count. This is not a fallback reconstruction. The plan is the source of truth used by both TX and RX.

Remove `floor(layerDataRE/nPRB)` and every missing-evidence fallback from `computeResourceAccounting` for strict PDSCH.

## Tests

Add:

- `testPDSCHReservedREUnionVectors.m` using all 14 supplied rows;
- `testPDSCHResourceOwnershipMap.m`;
- `testPDSCHRateMatchPatternIntegration.m`;
- `testPDSCHNoDataDMRSPTRSReservedOverlap.m`;
- `testPDSCHExactGFromResourcePlan.m`.

Cover overlapping reservation sources, reservations outside the allocation, all-data-reserved cases, SSB, CORESET, ZP/NZP CSI-RS, LTE CRS rate matching where selected, BWP boundaries, non-contiguous PRBs, mapping A/B, and one/two codewords.

---

# Work item 6 — Explicit DL-SCH coding and decoding chain

The strict chain must expose each stage. Do not hide the entire chain inside one `nrDLSCH` object and report only metadata.

## Transmit chain per codeword

Implement in this order:

1. determine transport-block size `A` from the exact resource plan and MCS context;
2. append TB CRC-16 or CRC-24A according to the pinned specification;
3. select LDPC base graph;
4. segment into code blocks;
5. append code-block CRC-24B where required;
6. determine lifting size and base-graph set index;
7. insert filler bits with explicit null positions;
8. LDPC encode;
9. rate match for the codeword-specific `G`, RV, `Nref`, `Ncb`, `k0`, and per-block `E_r`;
10. concatenate the rate-matched blocks.

Use explicit Toolbox primitives such as `nrCRCEncode`, `nrCodeBlockSegmentLDPC`, `nrLDPCEncode`, and `nrRateMatchLDPC` where appropriate, but keep every stage visible and testable. The production chain must return a `DLSCHCodingPlan` with all dimensions and positions.

## Receive chain per codeword

Implement the exact inverse:

1. descrambled codeword LLR input;
2. codeword-specific rate recovery;
3. position-aware HARQ combining in the recovered circular-buffer domain;
4. LDPC decode;
5. code-block desegmentation and CRC-24B handling;
6. TB CRC removal and result;
7. TB bit output.

Use the same immutable coding plan identifiers at TX and RX. The receiver must not infer missing TBS, code rate, base graph, filler positions, or RV from configured defaults.

## Independent coding oracle

Under `+sixgr/+pdsch/+oracle/`, implement independent, small-vector functions for:

- CRC-16, CRC-24A, and CRC-24B;
- TBS determination;
- base-graph selection;
- code-block segmentation dimensions;
- lifting-size selection;
- filler positions;
- rate-matching circular-buffer start index and selected positions.

The independent functions must not call production classes or `nrCRC*`, `nrTBS`, `nrDLSCH*`, `nrLDPC*`, `nrRateMatchLDPC`, or `nrRateRecoverLDPC`.

For LDPC encoded-bit parity, use either:

- a genuinely independent pure-MATLAB encoder built from the pinned base graph; or
- frozen external vectors with implementation name, version, command, source artifact hash, input bits, and expected encoded/rate-matched bit digest.

A second wrapper around `nrLDPCEncode` is not independent.

## Tests

Add:

- `testPDSCHTBSAndBaseGraphVectors.m` using all 23 supplied TBS rows;
- `testPDSCHTBCRCVectors.m` using all 18 supplied CRC rows;
- `testPDSCHCodeBlockSegmentationIndependent.m`;
- `testPDSCHLDPCEncodingIndependent.m`;
- `testPDSCHRateMatchingIndependent.m` for RV 0, 1, 2, and 3;
- `testPDSCHDLSCHNoNoiseRoundTrip.m`;
- `testPDSCHTwoCodewordCoding.m`.

Cover TB-size boundaries 292, 3824, 3825, base-graph thresholds, one and multiple code blocks, filler bits, limited buffer `Nref`, all RVs, puncturing/repetition, and codeword-specific `G`.

---

# Work item 7 — Real scrambling, modulation, and rank 1–8 layer mapping

## Scrambling

Replace the metadata-only scrambler with an actual bit transform. For codeword `q`, use the PDSCH scrambling initialization defined by TS 38.211:

```text
c_init = n_RNTI * 2^15 + q * 2^14 + n_ID
```

Generate the Gold sequence and XOR it with the rate-matched codeword. Implement the exact inverse operation on receiver LLR signs.

## Modulation

Implement actual mapping and soft demapping for:

- QPSK;
- 16QAM;
- 64QAM;
- 256QAM;
- normative 1024QAM.

Use the exact Gray mapping and normalization constants from TS 38.211. The 1024QAM normalization denominator is not a tunable parameter. Reject nonbinary inputs, bit counts not divisible by `Qm`, missing modulation, and unsupported 4096QAM in strict NR mode.

If the installed Toolbox release lacks 1024QAM support in `nrPDSCH`, use the simulator's explicit mapper/demapper; do not silently downgrade to 256QAM.

## Codeword-to-layer mapping

Map actual complex symbols, not metadata. Support:

```text
rank 1–4: one codeword mapped to 1–4 layers
rank 5:   codeword layer counts [2, 3]
rank 6:   [3, 3]
rank 7:   [3, 4]
rank 8:   [4, 4]
```

Implement the inverse layer-to-codeword demapping at the receiver. Reject rank 0, rank greater than 8, and codeword-count mismatches.

## Tests

Add:

- `testPDSCHScramblingIndependentVectors.m` using all 12 supplied rows;
- `testPDSCHModulationIndependentVectors.m` using all 24 supplied rows;
- `testPDSCHLayerMappingIndependentVectors.m` using all 12 supplied cases and all 40 expected layer rows;
- `testPDSCHSoftDemodulationLLRSign.m`;
- `testPDSCH1024QAMRoundTrip.m`;
- `testPDSCHRank1To8NoNoiseRoundTrip.m`.

Numerical comparisons must use explicit tolerances and record maximum error. Bit comparisons must be exact.

---

# Work item 8 — Wideband and frequency-selective PRG precoding

## Implement a real precoder bundle

Create an immutable `PDSCHPrecoderBundle` with one canonical internal orientation:

```text
W: [NPhysicalTxAntennas, NLayerPorts, NPRG, NSymbolGroups]
```

Include:

```text
mode
PRG size
PRG-to-PRB map
symbol-group map
matrix source
codebook/non-codebook identifier
normalization convention
matrix digest per slice
```

At a Toolbox boundary, transpose or reshape only in one documented adapter if the installed function expects a different orientation.

Support:

- SISO identity;
- wideband codebook matrix;
- wideband non-codebook matrix;
- per-PRG codebook matrix;
- per-PRG non-codebook matrix;
- per-PRB explicit matrix where selected;
- per-PRG/per-symbol-group matrix.

Do not treat scalar PMI as the applied precoder. PMI-to-matrix selection belongs to the MIMO/CSI phase; this PDSCH phase must accept and correctly apply the resolved matrix bundle.

Do not discard an explicit matrix because another PMI field exists. Detect stale or inconsistent matrix/PMI context and fail.

## Apply consistently

Apply the same resolved slice to:

- PDSCH data layers;
- the corresponding DM-RS ports;
- the associated PT-RS ports.

The receiver must consume the same applied bundle through the effective channel or explicit deprecoding/equalization model. It must not assume the wideband matrix for a frequency-selective transmission.

Preserve codebook normalization. For non-codebook matrices, apply only the explicitly configured normalization policy and record it. Do not silently renormalize arbitrary matrices.

## Tests

Add:

- `testPDSCHPrecoderBundleVectors.m` using all 15 supplied rows;
- `testPDSCHPRGMatrixMultiplicationIndependent.m`;
- `testPDSCHPRGDataDMRSPTRSConsistency.m`;
- `testPDSCHFrequencySelectivePrecoderEndToEnd.m`;
- `testPDSCHPrecoderPowerConservation.m`.

For each valid row prove:

- dimensions are exact;
- every scheduled PRB and symbol group selects one matrix slice;
- no unscheduled slice is applied;
- matrix digests at resolution and application match;
- TX application count is nonzero;
- receiver effective-channel consumption is nonzero;
- power error is within the declared convention tolerance.

For each invalid row require the expected typed error.

---

# Work item 9 — Complete PDSCH receiver chain

Implement one receiver that consumes the immutable assignment, resource plan, applied precoder bundle, received waveform/grid, and receiver configuration.

## Required stages

1. timing/frequency-corrected grid input from the front-end;
2. exact DM-RS extraction by resolved port;
3. channel estimation over the scheduled allocation;
4. noise/interference-variance estimation or an explicitly supplied test value;
5. PT-RS CPE estimation and correction when present;
6. PDSCH data extraction from exact data indices;
7. effective-channel construction including the applied PRG precoder;
8. layer separation/equalization;
9. codeword layer demapping;
10. soft QAM demodulation with a documented LLR convention;
11. LLR descrambling with the exact RNTI, codeword index, and data-scrambling identity;
12. rate recovery and HARQ combining;
13. LDPC decode and CRC processing;
14. per-codeword and per-layer metrics.

The receiver must not use transmitted bits, configured CRC outcome, configured SINR, ideal channel estimates, or transmitter coding buffers unless a test explicitly selects an ideal-oracle mode. Ideal-oracle mode must be a separate function and may not be used by BLER campaigns.

## Required metrics

Export at least:

```text
data RE count
DM-RS and PT-RS RE counts
channel-estimate NMSE when a test reference is available
measured post-equalization SINR per layer
EVM per layer/codeword
LLR count
finite LLR count
rate-recovered bit count
LDPC iteration count
BER from compared decoded bits
BLER from TB CRC
```

## Tests

Add:

- `testPDSCHReceiverNoNoiseExact.m` for rank 1–8;
- `testPDSCHReceiverAWGN.m`;
- `testPDSCHReceiverTDL.m`;
- `testPDSCHReceiverCDL.m` for selected declared cases;
- `testPDSCHReceiverWrongRNTI.m`;
- `testPDSCHReceiverWrongScramblingIdentity.m`;
- `testPDSCHReceiverWrongDMRSPort.m`;
- `testPDSCHReceiverWrongPRGMap.m`;
- `testPDSCHReceiverNoSignal.m`;
- `testPDSCHReceiverLLRScalingConvention.m`.

No-signal and wrong-configuration tests must fail the decode or return a controlled not-detected/CRC-failed result. They must not crash, use TX truth, or fabricate a passing TB.

---

# Work item 10 — Codeword-specific HARQ context and position-aware soft combining

## Implement process state

Create `PDSCHHARQContext` keyed by:

```text
UE ID
serving/scheduled cell ID
CC ID
BWP ID
HARQ process ID
codeword index
configuration epoch
```

Store:

```text
NDI state
TB identity digest
TBS
coding-plan digest
base graph
lifting size
code-block layout
filler positions
Ncb/Nref
received RV history
rate-recovery circular-buffer LLRs
valid-position mask
transmission count
last decode outcome
```

## Combining rules

- New data/NDI toggle resets the corresponding codeword buffer before load.
- Retransmission combines only when TB identity, TBS, code-block layout, and configuration epoch match.
- Rate-recover each transmission to exact circular-buffer positions, then add LLRs at matching valid positions.
- Do not concatenate raw rate-matched LLR vectors.
- Keep codeword 0 and codeword 1 buffers separate.
- Preserve the actual RV per codeword.
- Reject RV outside 0–3.
- Reset or reject stale context deterministically.

The process-count limit must come from configured UE/serving-cell HARQ capability, not a hard-coded global constant.

## Tests

Add:

- `testPDSCHHARQTransitionVectors.m` using all 11 supplied rows;
- `testPDSCHHARQRVSequence0231.m`;
- `testPDSCHHARQPositionAwareCombining.m`;
- `testPDSCHHARQTwoCodewords.m`;
- `testPDSCHHARQNDIReset.m`;
- `testPDSCHHARQRejectsWrongTB.m`;
- `testPDSCHHARQCombiningGain.m`.

For combining gain, choose an operating point where individual RV transmissions commonly fail and the valid combined sequence has a materially higher decode probability across deterministic seeds. Record confidence intervals rather than asserting one lucky seed.

---

# Work item 11 — BWP, component-carrier, TCI/QCL, and bounded multi-TRP PDSCH integration

This work item integrates PDSCH with state selected elsewhere. It does not implement CSI codebook selection or beam-management policy.

## BWP and component carriers

- Resolve PRBs relative to the active DL BWP and then to the scheduled component carrier.
- Carry scheduling-cell and scheduled-cell IDs for cross-carrier scheduling.
- Keep HARQ namespaces and assignment IDs unambiguous across cells and carriers.
- Use the canonical absolute-time engine for K0 and PDSCH slot legality.
- Reject an assignment referring to an inactive BWP, inactive carrier, wrong configuration epoch, or invalid carrier indicator.

## TCI/QCL

- Resolve the activated TCI state referenced by the assignment.
- Expose QCL source reference signals and applicable QCL assumptions to the receiver/channel-estimation path.
- Reject inactive or unknown TCI state IDs.
- Do not silently use the previous beam or TCI state.

## Bounded multi-TRP support

Represent a PDSCH transmission as one or more transmission occasions, each with:

```text
TRP ID
TCI state
absolute slot/symbol allocation
PRB allocation
precoder bundle
DM-RS/PTRS plan
power scaling
shared or repeated TB/HARQ identity
```

Implement the selected-profile multi-TRP/repetition cases end to end rather than reporting metadata only. The receiver must combine the occasions according to the implemented standard procedure. Unsupported release combinations must fail during assignment resolution, not degrade to single TRP.

## Tests

Add:

- `testPDSCHActiveBWPBinding.m`;
- `testPDSCHCrossCarrierBinding.m`;
- `testPDSCHTCIStateBinding.m`;
- `testPDSCHQCLStatePropagation.m`;
- `testPDSCHTwoTRPTransmissionOccasions.m`;
- negative cases for stale BWP, wrong carrier indicator, inactive TCI, mismatched TRP HARQ identity, and unsupported multi-TRP scheme.

---

# Work item 12 — Executable conformance matrix, campaigns, CSVs, and images

## Mandatory matrix

Run every row of `pdsch_declared_coverage_matrix.csv`. Each row must invoke the production TX/RX chain. Do not mock or replace channel/reference-signal/coding stages.

For each row execute the listed test kinds:

```text
positive
no_signal
wrong_rnti
wrong_dmrs
wrong_rv
reserved_re
impairment
```

In addition, generate a pairwise matrix covering at least:

- rank 1–8;
- one and two codewords;
- mapping A and B;
- DM-RS configuration type 1 and 2;
- DM-RS length 1 and 2;
- all legal additional-position categories;
- basic and enhanced DM-RS where selected;
- PT-RS present and absent;
- QPSK, 16QAM, 64QAM, 256QAM, and enabled 1024QAM;
- RV 0, 1, 2, and 3;
- wideband and PRG precoding;
- contiguous and non-contiguous PRB allocations;
- no reservations and multiple overlapping reservation sources;
- AWGN, one TDL profile, and one CDL profile;
- at least 15, 30, 60, and 120 kHz numerologies supported by the frame layer.

The pairwise generator must be deterministic and its generated cases must be written to the output directory.

## No-noise exact tests

For each rank 1–8 and every supported modulation:

- generate deterministic TB bits;
- execute the full TX grid/waveform and RX chain with no noise and an identity or exactly known MIMO channel;
- require exact TB recovery and CRC pass;
- require zero bit errors;
- require exact lengths at every stage;
- require no resource collisions;
- require finite receiver metrics.

## BLER campaigns

Run at least these bounded campaigns:

1. SISO QPSK low-rate AWGN;
2. SISO 64QAM medium-rate AWGN;
3. rank-2 16QAM TDL-A;
4. rank-4 64QAM CDL-C;
5. one enabled 1024QAM case;
6. one HARQ RV sequence case;
7. one PT-RS phase-noise case.

Use at least four SNR points per campaign. Use a deterministic seed list, a configurable confidence level, minimum error count, minimum trial count, and a canonical stop-reason enumeration. Do not accept incomplete points as ordinary complete points.

The BLER curves need not match an invented universal threshold, but they must be internally consistent, confidence-bounded, and directionally sensible for the chosen operating points. Any comparison to a reference curve must use an independent frozen source, not a copy of the DUT results.

---

## 8. Explicit production TX pipeline

The strict transmitter must execute the following order and expose stage dimensions:

```text
Decoded DCI + UE context
    -> immutable PDSCHSchedulingAssignment
    -> exact PDSCHResourcePlan
    -> per-codeword TBS and DLSCHCodingPlan
    -> TB CRC
    -> code-block segmentation and CB CRC
    -> LDPC encode
    -> RV-specific rate match to exact G
    -> PDSCH scramble
    -> QAM modulation
    -> codeword-to-layer mapping
    -> per-PRG/per-symbol precoding
    -> data RE mapping
    -> DM-RS generation, precoding, and mapping
    -> PT-RS generation, precoding, and mapping
    -> antenna-port grid
    -> OFDM modulation
```

A production stage must not be skipped merely because `nrPDSCH` can perform multiple hidden sub-stages. Optimized Toolbox calls are allowed only when stage inputs/outputs remain explicit and the independent vectors still test the transform.

---

## 9. Explicit production RX pipeline

The strict receiver must execute:

```text
received waveform
    -> OFDM demodulation
    -> exact DM-RS extraction
    -> channel/noise estimation
    -> PT-RS CPE estimation and correction
    -> exact data RE extraction
    -> effective-channel/equalization using applied PRG matrices
    -> layer-to-codeword demapping
    -> soft QAM demodulation
    -> PDSCH LLR descrambling
    -> RV-specific rate recovery
    -> position-aware HARQ combining
    -> LDPC decode
    -> code-block desegmentation/CRC
    -> TB CRC and decoded TB bits
```

The receiver must not read transmitter intermediate bits except inside explicitly named oracle-only tests.

---

## 10. Mandatory negative behavior

Strict execution must fail before waveform generation for at least:

- no decoded DCI in connected mode;
- failed DCI CRC;
- wrong RNTI;
- inactive BWP or serving cell;
- stale configuration epoch;
- invalid RIV or RBG bitmap;
- resource outside BWP;
- invalid TDRA or slot direction;
- reserved MCS entry;
- unsupported 1024QAM context;
- 4096QAM;
- missing codeword-specific modulation/rate;
- rank outside 1–8;
- codeword-count mismatch;
- invalid DM-RS type-A position;
- invalid DM-RS configuration type;
- invalid DM-RS length/additional-position combination;
- invalid or unsupported DM-RS port set;
- invalid `NumCDMGroupsWithoutData`;
- invalid PT-RS density, RE offset, or port association;
- reservation outside the scheduled allocation;
- no data RE after reservations;
- data/DM-RS/PT-RS collision;
- wrong precoder dimensions;
- incomplete PRG or symbol-group coverage;
- stale matrix/PMI context;
- wrong HARQ TB identity, TBS, or coding layout;
- invalid RV;
- inactive TCI state;
- unsupported multi-TRP combination.

The negative test CSV must contain the exact expected and actual MATLAB identifiers and `WaveformGenerated=0`.

---

## 11. Independent evidence requirements

The file `pdsch_independent_vector_results.csv` must include passing rows for all of these families:

```text
scrambling
modulation
layer_mapping
tbs
tb_crc
ldpc_segmentation
ldpc_encoding
rate_matching
dmrs_positions
dmrs_ports
dmrs_sequence
ptrs_indices
reserved_re
precoding_application
harq_combining
receiver_chain
```

For every row record:

- oracle implementation;
- oracle version;
- oracle artifact SHA-256;
- compared field;
- expected and actual digest where bit-exact;
- mismatch count;
- maximum absolute error and tolerance where numerical.

The oracle code must not call the production implementation. A Toolbox-vs-Toolbox comparison may be retained as regression evidence, but it must use a different `VectorFamily`, such as `toolbox_regression`, and cannot satisfy the mandatory family row.

---

## 12. Required MATLAB tests

Create focused test files rather than one unmaintainable script. The exact filenames may vary, but the executed suites must cover:

```text
testPDSCHSchedulingAssignment
testPDSCHSPSAssignment
testPDSCHFDRAFromDecodedDCI
testPDSCHTDRAFromDecodedDCI
testPDSCHMCSResolver
testPDSCHConfigMaterializerNoMutation
testPDSCHDMRSSymbolPositionVectors
testPDSCHDMRSPortTableVectors
testPDSCHDMRSSequenceIndependent
testPDSCHPTRSPresenceVectors
testPDSCHPTRSIndicesIndependent
testPDSCHPTRSPhaseNoiseBenefit
testPDSCHReservedREUnionVectors
testPDSCHResourceOwnershipMap
testPDSCHTBSAndBaseGraphVectors
testPDSCHTBCRCVectors
testPDSCHCodeBlockSegmentationIndependent
testPDSCHLDPCEncodingIndependent
testPDSCHRateMatchingIndependent
testPDSCHScramblingIndependentVectors
testPDSCHModulationIndependentVectors
testPDSCHLayerMappingIndependentVectors
testPDSCHPrecoderBundleVectors
testPDSCHPRGMatrixMultiplicationIndependent
testPDSCHReceiverNoNoiseExact
testPDSCHReceiverAWGN
testPDSCHReceiverTDL
testPDSCHReceiverCDL
testPDSCHHARQTransitionVectors
testPDSCHHARQPositionAwareCombining
testPDSCHActiveBWPBinding
testPDSCHCrossCarrierBinding
testPDSCHTCIStateBinding
testPDSCHTwoTRPTransmissionOccasions
testPDSCHDeclaredCoverageMatrix
testPDSCHArtifactGeneration
```

Run the existing PDSCH/DL-SCH regression tests as well, including:

```text
testPDSCH6GR
testPDSCH6GRMultiCodewordStudy
testPDSCHCodewordLayerHighRank
testPDSCHGrantDrivenTxExact
testPDSCHLLRScalingConvention
testPDSCHMultiPortPrecoding
testPDSCHSISORegression
testResourceAccountingExact
testHARQTBContextInvariants
testHARQSoftBufferPositionAware
testCodingLayoutContracts
testTransportBlockSizeExactness
```

Update an existing test only when the old assertion explicitly requires one of the shortcuts being removed. Replace it with the correct behavior and add a regression that the shortcut no longer occurs. Do not weaken tolerances or skip tests to obtain green output.

---

## 13. Required CSV artifacts

Generate all CSVs below in one phase output directory. They must come from actual production execution.

### `pdsch_assignment_resolution.csv`

One row per assignment test case. Include decoded DCI ID or SPS activation-DCI ID, profile, serving cell, CC, BWP, absolute slot, configuration epoch, SPS epoch/occasion where applicable, DCI format/CRC/RNTI status, allocation, MCS, layers, HARQ, DM-RS ports, TCI, source, assignment-created flag, waveform-allowed flag, and error.

`Status` is the test-result status and must be `PASS` when the observed behavior matches the expected result, including a correctly rejected negative case. `AssignmentCreated` and `WaveformAllowed` carry the implementation outcome. Dynamic connected passing cases must contain decoded DCI plus UE/RRC context; SPS passing cases must contain SPS RRC configuration plus activation-DCI context; calibration rows must be explicitly distinguishable. A rejected row must have both outcome flags false and a non-empty typed `ErrorIdentifier`.

### `pdsch_resource_ownership.csv`

One row per scheduled or reserved RE in the selected diagnostic cases. `CollisionCount` must be zero for all passing rows. A unique key may not have two owners.

### `pdsch_re_mapping.csv`

Emit zero-based data, DM-RS, PT-RS, and reserved mappings with codeword, layer, port, PRB, symbol, subcarrier, and zero-based linear index.

### `pdsch_dmrs_matrix.csv`

Emit every tested DM-RS configuration, symbol positions, ports, sequence digest, RE count, independent sequence NMSE, and index mismatch count.

### `pdsch_ptrs_matrix.csv`

Emit presence resolution, densities, offset, ports, RE count, reason, and pre/post CPE/EVM metrics.

### `pdsch_coding_chain.csv`

One row per case and codeword. Include TBS, CRC, base graph, code-block count, lifting size, K/N/Ncb, filler bits, RV, k0, E per block, G, rate-matched count, and CRC result.

### `pdsch_independent_vector_results.csv`

Emit all mandatory independent families from section 11.

### `pdsch_layer_codeword_map.csv`

Cover rank 1–8 and every layer. Mismatch count must be zero.

### `pdsch_precoding_application.csv`

One row per PRG and symbol group. Include resolved/applied matrix digests, dimensions, normalization, TX/RX consumption counts, and power error.

### `pdsch_harq_trials.csv`

One row per codeword transmission. Include NDI, RV, TB and layout digests, soft-buffer input/output digests, action, combine flag, and CRC outcome.

### `pdsch_receiver_metrics.csv`

Emit finite receiver-derived metrics for the required cases and ranks 1, 2, 4, and 8 at minimum.

### `pdsch_bler_curve.csv`

Emit trials, TB errors, BLER, confidence level and interval, minimum errors, and canonical stop reason. No required point may be incomplete.

Allowed completion stop reasons are:

```text
CI_AND_MIN_ERRORS_MET
MAX_TB_CENSORED_BOUND_MET
FIXED_TRIAL_BUDGET_COMPLETE
```

Use `MAX_TB_CENSORED_BOUND_MET` only when a documented one-sided bound policy is actually satisfied.

### `pdsch_negative_tests.csv`

Every row must show expected identifier equals actual identifier and `WaveformGenerated=0`.

### `pdsch_test_summary.csv`

Every mandatory suite must have `Failed=0`, `Skipped=0`, `Blocked=0`, and `Passed=Total>0`.

### `pdsch_image_semantic_audit.csv`

One row per required image. Record actual MATLAB figure axes/series/finite-point counts, labels, title, dimensions, source CSV SHA-256, PNG SHA-256, and pass status.

For a single source CSV, `SourceCSV_SHA256` is the raw SHA-256.

For multiple source CSVs, use this exact format in the contract order:

```text
file1.csv=<sha256>|file2.csv=<sha256>
```

---

## 14. Required PNG artifacts

Generate these figures with MATLAB from the corresponding CSV data:

```text
pdsch_resource_grid_ownership.png
pdsch_dmrs_ptrs_map.png
pdsch_codeword_layer_mapping.png
pdsch_prg_precoding_map.png
pdsch_harq_rv_timeline.png
pdsch_bler_vs_snr.png
pdsch_ptrs_phase_noise_evm.png
pdsch_per_layer_sinr.png
pdsch_reserved_re_impact.png
```

Use the exact labels and title tokens in `desired_pdsch_image_contract.csv`.

Requirements:

- minimum 900 by 600 pixels;
- nonblank decoded content;
- required axes, series, and finite-point counts;
- readable legend where multiple series exist;
- no screenshot of a table;
- no decorative figure disconnected from the source CSV;
- source CSV data must be the data plotted;
- no hard-coded “PASS” annotation without the underlying numerical checks.

After saving each figure, inspect the MATLAB figure object and write the observed semantic values to `pdsch_image_semantic_audit.csv`. The Python verifier checks those values and binds them to the exact PNG and CSV hashes.

---

## 15. Required phase runner

Implement a callable runner, for example:

```matlab
summary = sixgr.pdsch.runPDSCHPhaseValidation( ...
    "VectorRoot", fullfile(pwd,"tests","vectors","pdsch"), ...
    "OutputDir", fullfile(pwd,"artifacts","pdsch_dlsch_phase"), ...
    "SeedList", [11 23 47 89], ...
    "ConfidenceLevel", 0.95, ...
    "Strict", true);
```

The runner must:

1. verify the vector pack before MATLAB execution;
2. execute all supplied vector tests through production functions;
3. execute all independent oracle comparisons;
4. execute the declared coverage matrix;
5. execute no-noise and bounded BLER campaigns;
6. generate every required CSV;
7. generate every required PNG;
8. generate the image semantic audit;
9. return a fail-closed summary;
10. throw an error if any mandatory test, artifact, or semantic check fails.

It must not copy any `expected_*.csv` file into the output directory as a result artifact.

---

## 16. Commands Codex must run

Adapt paths only if repository conventions require it. Record the exact commands and unabridged counts.

### Vector integrity

```bash
python tests/vectors/pdsch/verify_pdsch_vector_pack.py
```

### Focused MATLAB suites

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PDSCH*'); assertSuccess(r);"
```

Because MATLAB name filters may not select every DL-SCH/HARQ/resource test, also run an explicit suite list or folder suite covering all files in section 12.

### Phase execution

```bash
matlab -batch "addpath(pwd); s=sixgr.pdsch.runPDSCHPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','pdsch'),'OutputDir',fullfile(pwd,'artifacts','pdsch_dlsch_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

### Artifact verification

```bash
python tests/vectors/pdsch/verify_pdsch_artifacts.py artifacts/pdsch_dlsch_phase
```

### Existing regressions

Run the existing PDSCH, resource-accounting, coding-layout, and HARQ tests listed in section 12. Also run the repository's complete mandatory MATLAB test command if one exists.

If MATLAB or the required Toolbox is unavailable, report `BLOCKED`; do not report `COMPLETE` and do not fabricate CSV/PNG outputs with Python.

---

## 17. Acceptance tolerances

Use exact bit/index comparisons wherever possible.

Recommended upper bounds for deterministic tests, unless a stricter repository threshold exists:

```text
scrambling mismatch count                 0
hard-bit mismatch count                   0
RE-index mismatch count                   0
layer-map mismatch count                  0
reserved-union mismatch count             0
DM-RS/PT-RS index mismatch count          0
QAM symbol max absolute error             <= 1e-12
DM-RS sequence NMSE                       <= 1e-12
precoder matrix application max error     <= 1e-12
no-channel OFDM/grid round-trip NMSE       <= 1e-12
precoding relative power error            <= 1e-8
no-noise decoded TB bit errors             0
no-noise TB CRC failures                   0
```

For channel-estimation, EVM, SINR, BLER, and PT-RS benefit, derive tolerances from deterministic cases and confidence intervals. State them in the tests. Do not choose thresholds after observing the result.

---

## 18. Prohibited shortcuts

Do not:

- create a dynamic connected grant directly from configuration;
- create an SPS PDSCH from bare RRC configuration without a prior valid activation DCI;
- replace missing PRBs with the full grid;
- replace missing symbols with a full slot;
- default modulation to QPSK;
- repeat/truncate a two-codeword modulation list;
- clamp or mutate DM-RS fields;
- overwrite valid DM-RS ports;
- change mapping type A to B;
- invent PT-RS density, offset, or port;
- generate data before reserved-resource resolution;
- repair collisions after symbol generation;
- floor an inferred `NREPerPRB`;
- infer missing `G` as a fallback;
- discard an explicit precoder because PMI exists;
- represent a PRG precoder with one wideband matrix;
- concatenate raw HARQ LLRs instead of position-aware combining;
- use TX bits or CRC state in the receiver;
- call the same Toolbox primitive on both sides and call that independent;
- skip rank 5–8 or two-codeword tests because they are slow;
- downgrade 1024QAM to 256QAM;
- enable 4096QAM in strict NR;
- catch a Toolbox configuration error, change the configuration, and retry;
- generate placeholder CSVs or figures;
- mark unavailable MATLAB tests as passed;
- change supplied expected vectors merely to match current output.

---

## 19. Definition of done

This phase is complete only when all conditions below are true:

1. dynamically scheduled connected PDSCH can be created only from decoded DCI plus current UE/RRC/BWP state;
2. SPS PDSCH can be created only from a valid activated, not released SPS context and an exact SPS occasion;
3. calibration assignments are isolated and typed;
4. no PRB, symbol, modulation, DM-RS, PT-RS, or precoder fallback remains in strict execution;
5. the production TX chain explicitly executes coding, scrambling, modulation, layer mapping, precoding, and RE mapping;
6. the production RX chain explicitly executes reference processing, equalization, LLR generation, descrambling, rate recovery, HARQ combining, LDPC decode, and CRC;
7. all valid supplied vectors pass;
8. all invalid supplied vectors raise the expected error before waveform generation;
9. ranks 1–8 and one/two codewords pass no-noise round trips;
10. DM-RS and PT-RS indices/sequences pass independent checks;
11. wideband and PRG precoding are actually applied to data and reference signals;
12. reserved resources produce exact data indices, TBS inputs, and `G`;
13. HARQ combines only compatible retransmissions at the correct circular-buffer positions;
14. all mandatory independent vector families are present and pass;
15. all selected PDSCH MATLAB tests execute with zero failure, skip, or block;
16. every contracted CSV is present and passes the verifier;
17. every contracted PNG is present, decodes, is nonblank, and passes semantic/hash checks;
18. `verify_pdsch_vector_pack.py` returns 0;
19. `verify_pdsch_artifacts.py` returns 0;
20. existing mandatory PDSCH/DL-SCH/HARQ/resource regression tests pass;
21. no expected output file was copied into the actual output directory.

---

## 20. Required Codex final response

At the end of the implementation, report exactly:

1. **Status:** `COMPLETE`, `INCOMPLETE`, or `BLOCKED`.
2. **Production files changed:** full repository-relative paths.
3. **New production classes/functions:** one-line role for each.
4. **Old shortcuts removed:** map each removal to the source file.
5. **Tests added or changed:** exact filenames and test counts.
6. **Commands run:** exact commands.
7. **MATLAB results:** total, passed, failed, skipped, blocked.
8. **Vector results:** row counts and mismatch counts by family.
9. **Coverage:** ranks, modulations, mapping types, DM-RS/PT-RS combinations, RVs, channels, and precoding modes actually executed.
10. **CSV artifacts:** filename and row count.
11. **PNG artifacts:** filename, dimensions, axes/series/point counts, and SHA-256.
12. **Verifier results:** exit codes and pass/fail check counts.
13. **Remaining technical limitations:** only real unresolved implementation limitations; do not hide them.
14. **Next dependency:** the next domain that should be implemented after PDSCH/DL-SCH.

Do not state `COMPLETE` based on static analysis, compilation, class existence, or a subset of tests.

Begin editing the production code now. First run the vector-pack verifier and the current focused PDSCH tests to establish a failing baseline, then implement work items 1 through 12 in dependency order, rerunning prior tests after each coherent change.
