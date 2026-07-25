# CODEX IMPLEMENTATION PROMPT 05 — PUCCH AND UCI WITH IMPACT ANALYSIS

You are the lead MATLAB 5G PHY implementation engineer for this repository. This is an implementation task. Do not return a review, plan-only response, pseudo-code-only response, or a list of recommendations. Inspect the repository, modify the production MATLAB chain, add tests, run all mandatory commands, generate the contracted CSV/PNG artifacts, run both Python artifact verifiers, and continue fixing the code until the selected phase is complete or a real external dependency is demonstrated with exact evidence.

## Mission

Replace the current raw-bit, default-length, heuristic-resource PUCCH implementation with a release-pinned NR PUCCH/UCI chain that:

1. constructs typed UCI reports from decoded procedure state;
2. serializes HARQ-ACK, SR, CSI Part 1 and CSI Part 2 exactly;
3. performs the selected TS 38.212 coding/rate-matching procedures;
4. selects PUCCH resources from active RRC, decoded DCI timing/PRI, SPS, SR and CSI state;
5. executes formats 0, 1, 2, 3 and 4 through one production TX/RX chain;
6. implements exact K1/TDD timing, hopping, repetition, DM-RS, OCC/cyclic shift, collision, power and spatial-relation behavior;
7. provides negative and statistical evidence without passing transmitted payload bits to the receiver;
8. executes all 600 controlled impact experiments and all 75 acceptance rules.

## Pinned baseline

Use these exact baselines unless the repository already pins a newer internally consistent Release-18 maintenance version and all vectors are regenerated against that one version:

- 3GPP TS 38.211 V18.8.0: PUCCH physical formats, sequences, modulation, spreading, transform precoding, DM-RS and RE mapping.
- 3GPP TS 38.212 V18.8.0: UCI sequence generation, code-block segmentation, CRC attachment, coding and rate matching.
- 3GPP TS 38.213 V18.8.0: HARQ-ACK codebooks, K1 timing, PUCCH resource sets/resources, PRI, SR/CSI multiplexing, repetitions, collision procedures and PUCCH power control.
- 3GPP TS 38.214 V18.8.0 where CSI report interpretation or scheduling procedure is required.
- 3GPP TS 38.331 V18.8.0 or the repository-pinned Release-18 maintenance version for PUCCH-Config, PUCCH-ResourceSet, PUCCH-Resource, SchedulingRequestResourceConfig, CSI-ReportConfig, PUCCH-PowerControl and PUCCH-SpatialRelationInfo.

Record exact specification versions in every validation manifest.

## Non-negotiable rules

1. Do not change a test merely to accept an existing shortcut.
2. Do not keep `ExpectedUCIBits` or any transmitted payload bit vector in a production receiver API.
3. The receiver may know the expected report schema and lengths from decoded/configured procedure state; it may not know the transmitted bit values.
4. Do not invent a default UCI length. Remove the 20-bit default and one-bit default.
5. Do not auto-promote or auto-demote a PUCCH format from payload length.
6. Do not round, clamp, modulo-wrap or replace an invalid cyclic shift, OCC, spreading factor, PRB, symbol, hopping or RNTI value.
7. Do not shift a requested PUCCH slot or symbol to make it fit TDD. Resolve exact K1 and reject an illegal configured resource.
8. Do not hash RNTI/cell identity into a PUCCH resource in connected strict mode.
9. Do not use rectangular PRB/symbol overlap as the final collision decision. Use exact RE, sequence, cyclic-shift, OCC and port ownership.
10. Do not convert a DM-RS generation failure or UCI decode failure into an empty vector and continue.
11. Do not call a comparison independent when both sides invoke the same `nr*` implementation.
12. Do not mark a mandatory test passed when MATLAB, 5G Toolbox, a required adjacent subsystem, or an experiment is unavailable.
13. Do not generate a waveform after any strict configuration, report, resource, timing, power or spatial-state rejection.
14. Do not copy supplied expected CSVs into the production result folder. Invoke production MATLAB code and compare actual results.
15. Preserve useful Toolbox-backed kernels unless an independent failing vector proves the kernel itself is wrong; replace the ownership/configuration/evidence shortcuts around them.

## Required input pack

Place this pack under `tests/vectors/pucch/`. Treat `independent_vector_manifest.json` as immutable input. Run:

```bash
python tests/vectors/pucch/verify_pucch_vector_pack.py
```

before editing and after every vector change. A vector change requires a written reason, regenerated hashes and proof that it corrects the independent oracle rather than accommodating the DUT.

## The ten source-specific findings

### PUCCH-001 — Raw bit vectors are used as the production UCI interface; HARQ-ACK, SR, CSI Part 1, CSI Part 2, report priority, codebook identity, and report provenance are not represented by an exact typed report object.

**Required implementation**: Create immutable UCIReport/UCISequence objects and a release-pinned TS 38.212 serializer. Build HARQ-ACK, SR, CSI Part 1 and CSI Part 2 from decoded procedure state, then serialize in the normative order. Prohibit arbitrary connected-mode uciBits injection.

**Acceptance**: Every report field and serialized bit position has one owner and provenance. Multiple-report and two-part CSI vectors round-trip bit-exactly. Deleting or reordering one field is detected.

### PUCCH-002 — The receiver derives payload length from ExpectedUCIBits or invents 20 bits; expected transmitted payload bits are passed into the production receiver.

**Required implementation**: Derive expected report structure and payload lengths from installed HARQ/SR/CSI/RRC context. Never pass transmitted payload bits to the production receiver. Missing, inconsistent, or stale report context fails before decode.

**Acceptance**: No production receiver API contains ExpectedUCIBits. Strict tests fail when report context is removed, when lengths are wrong, or when a payload bit oracle is injected.

### PUCCH-003 — PUCCH resource selection is deterministic/hard-coded rather than derived from PUCCH-ResourceSet, PUCCH-Resource, DCI PUCCH resource indicator, SR configuration, CSI report configuration, and active BWP state.

**Required implementation**: Implement immutable RRC PUCCH configuration state, exact resource-set selection, PRI mapping, set-0 CCE formula, SR-only and CSI-only resources, SPS resources, active-BWP binding, and configuration epochs.

**Acceptance**: Changing decoded PRI, CCE location, resource set, BWP, or report source changes the actual mapped resource. Configured hash/default resources cannot create a connected PUCCH.

### PUCCH-004 — HARQ-ACK codebook construction is effectively one ACK bit and does not cover declared Type-1/Type-2/Type-3, DAI, SPS, multi-PDSCH, multi-cell, priority, or multi-TRP procedures.

**Required implementation**: Create a HARQACKCodebookBuilder driven by decoded DCI/PDSCH/SPS events and release-pinned TS 38.213 procedures. Preserve DTX, ACK/NACK ordering, DAI, serving-cell and priority provenance.

**Acceptance**: Independent bounded codebook vectors pass. Missing PDSCH occasions produce the correct DTX/placeholder behavior. Wrong DAI, event order, cell, or priority is rejected.

### PUCCH-005 — SR generation, periodicity/offset, positive/negative behavior, multiple SR identities, and simultaneous HARQ-ACK/SR/CSI multiplexing are incomplete.

**Required implementation**: Implement SchedulingRequestState for periodic/event-triggered SR, SR resource identity, priority, pending/cancel state, positive/negative encoding, multiple SRs and exact simultaneous-UCI rules.

**Acceptance**: All configured SR occasions and non-occasions match independent arithmetic. Simultaneous HARQ/SR/CSI cases select the correct sequence/resource or collision procedure.

### PUCCH-006 — CSI Part 1 and Part 2 are represented as arbitrary bit counts instead of report-dependent fields, priorities, widths, report order, and two-sequence serialization.

**Required implementation**: Create CSIReportBuilder objects from active CSI-ReportConfig, measured CSI state and report quantity. Compute exact field widths/order, report priority, Part 1/Part 2 separation and padding rules.

**Acceptance**: Multiple CSI reports and two-part reports serialize and decode bit-exactly. Wrong configuration epoch, field width, report priority or Part-2 length fails closed.

### PUCCH-007 — Formats 0-4 are not covered over a complete matrix and invalid parameters are silently defaulted, rounded, clamped, modulo-wrapped, or auto-promoted/demoted to another format.

**Required implementation**: Implement one exact PUCCH format/resource validator and mapper for all declared format, symbol, PRB, DM-RS, cyclic-shift, OCC, hopping, interlace, repetition and modulation combinations. Invalid tuples fail with typed errors before waveform generation.

**Acceptance**: Every declared tuple executes through the same TX/RX chain. Every invalid tuple produces no waveform, no state change and the expected error identifier. No format adaptation or parameter clamp remains.

### PUCCH-008 — HARQ feedback timing uses a default delay, scans for a later UL-capable slot, and shifts PUCCH symbols to fit the TDD UL partition instead of resolving exact K1 and resource legality.

**Required implementation**: Resolve K1 from decoded DCI or configured dl-DataToUL-ACK, bind it to the correct numerology/cell/BWP, and validate the configured PUCCH symbols against the resolved TDD slot. Never scan or shift to another slot/symbol.

**Acceptance**: Due slot/symbol matches independent K1/TDD vectors. Illegal timing is rejected or handled by the exact procedure; requested resource coordinates are never mutated to force success.

### PUCCH-009 — Frequency hopping, inter-slot repetition, interlaced mapping, DM-RS, cyclic-shift/OCC orthogonality, exact RE-level collision detection, and multi-UE separation are incomplete.

**Required implementation**: Create exact zero-based RE ownership maps per hop/slot/port/sequence/OCC; implement intra-slot/inter-slot hopping, repetition, interlace, format-specific DM-RS and multi-UE orthogonality/collision evaluation.

**Acceptance**: Independent index/sequence vectors pass. Same rectangle but orthogonal resources are separated; colliding cyclic shifts/OCC/DM-RS are detected. Hopping/repetition round trips pass over selective channels.

### PUCCH-010 — PUCCH power control, pathloss-reference selection, closed-loop TPC state, spatial relation/beam state, waveform-power application, and statistical false-alarm/wrong-context validation are incomplete.

**Required implementation**: Implement P0, pathloss reference RS, deltaF, deltaTF, closed-loop index/TPC, P_CMAX, spatial relation/TCI state, waveform scaling, receiver metrics and multi-seed negative campaigns.

**Acceptance**: Requested/applied/measured power reconcile; beam/pathloss/TPC state is current and causal; no-signal, wrong-RNTI, wrong-length, wrong-resource and collision confidence bounds pass with no incomplete points.


## Required canonical production architecture

Consolidate the strict production implementation under `+sixgr/+phy/+pucch/`. Existing `+sixgr/+phy/+ul/PUCCH_Tx.m` and `PUCCH_Rx.m` may remain as compatibility facades only; they must delegate to the canonical objects and must not retain local defaults, clamping, report construction or resource resolution.

Create or refactor at least these coherent components:

```text
+sixgr/+phy/+pucch/
    PUCCHSpecificationProfile.m

    UCIReport.m
    UCIReportContext.m
    UCISequence.m
    UCIReportSerializer.m
    UCIEncodingPlan.m
    UCIEncoder.m
    UCIDecoder.m

    HARQACKEvent.m
    HARQACKCodebookState.m
    HARQACKCodebookBuilder.m
    SchedulingRequestState.m
    CSIReportState.m
    CSIReportBuilder.m

    PUCCHUEContext.m
    PUCCHRRCContext.m
    PUCCHResourceSet.m
    PUCCHResource.m
    PUCCHResourceSetResolver.m
    PUCCHResourceIndicatorResolver.m
    PUCCHTimingResolver.m
    PUCCHTransmissionAssignment.m

    PUCCHFormatValidator.m
    PUCCHResourceOwnershipMap.m
    PUCCHDMRS.m
    PUCCHHoppingPlan.m
    PUCCHRepetitionPlan.m
    PUCCHGridMapper.m

    PUCCHCollisionResolver.m
    PUCCHPowerControlState.m
    PUCCHPowerController.m
    PUCCHSpatialRelationState.m

    PUCCHTransmitter.m
    PUCCHReceiver.m
    PUCCHDetector.m

    PUCCHArtifactExporter.m
    runPUCCHPhaseValidation.m
    runPUCCHImpactAnalysis.m

    +oracle/
        UCISequenceSpec.m
        UCICodingPlanSpec.m
        HARQACKCodebookSpec.m
        SROccasionSpec.m
        CSIReportSpec.m
        PUCCHResourceSetSpec.m
        PUCCHResourceIndicatorSpec.m
        PUCCHFormatSpec.m
        PUCCHSequenceSpec.m
        PUCCHDMRSSpec.m
        PUCCHHoppingSpec.m
        PUCCHTimingSpec.m
        PUCCHCollisionSpec.m
        PUCCHPowerControlSpec.m
        PUCCHSpatialRelationSpec.m
```

Do not create a parallel package that is unused by the scheduler/runtime. Migrate every connected-mode caller to the new `PUCCHTransmissionAssignment` and canonical TX/RX chain.

## Exact UCI report model

`UCIReport` must be immutable after construction and contain explicit subreports rather than a flat bit vector:

```text
ReportID
UE/RNTI
ServingCell/CC/UL-BWP
ConfigurationEpoch
TargetSlot
PriorityIndex
HARQACKReport
SchedulingRequestReport(s)
CSIReport(s)
ReportSource and triggering event IDs
Expected sequence count
Expected information-bit counts by owner
```

### HARQ-ACK subreport

Carry at least:

```text
codebook type
PDSCH/DCI/SPS event IDs
serving-cell index
PDSCH group
priority index
DAI / total DAI / counter DAI where applicable
HARQ process and TB/codeword identity
ACK, NACK or DTX state
K1 source and due slot
```

The codebook builder, not the scheduler's original intention, owns the bit ordering. Preserve DTX as a distinct state until the relevant mapping procedure.

### SR subreport

Carry:

```text
SchedulingRequestID
SR resource ID
periodicity and offset
trigger/pending/cancel state
positive/negative value
priority and prohibit timer state
occasion identity
```

A negative SR-only occasion does not automatically create a PUCCH waveform. Implement the exact simultaneous HARQ/SR and SR/CSI procedures.

### CSI subreport

Carry:

```text
CSI-ReportConfig ID and epoch
report quantity
trigger type and report priority
measured CSI state ID
ordered Part-1 fields and widths
ordered Part-2 fields and widths
subband/reportConfig ordering
```

Do not accept a connected-mode arbitrary 20-bit CSI vector as a complete CSI report.

## TS 38.212 serialization and coding

Implement the report serializer so that, for the ordinary single-priority case:

```text
sequence 1 = HARQ-ACK || SR || CSI Part 1
sequence 2 = CSI Part 2, when a two-part CSI report exists
```

Respect multiple-report priority and field order. Apply the specified minimum padding for a short CSI Part-2 sequence. Implement the separate priority-index procedure when configured.

Create an explicit `UCIEncodingPlan` before calling any Toolbox kernel. It records:

```text
A per sequence
E/G per sequence
coding family
CRC polynomial and length
segmentation decision
code-block count
rate-matching indexes/digest
```

At minimum, independently verify these boundaries:

```text
A <= 11: small-block coding procedure
12 <= A <= 19: Polar with CRC6
A >= 20: Polar with CRC11
segmentation when the release-pinned A/E conditions require it
maximum selected-profile payload 1706 bits
```

Formats 0 and 1 follow their short-UCI physical mapping procedure; formats 2, 3 and 4 use the selected UCI coding/rate-matching procedure. Do not use one generic helper that hides report sequence identity, priority or Part 2.

## Resource ownership and timing

Create an immutable `PUCCHTransmissionAssignment` with:

```text
assignment ID and source
UE/RNTI
serving cell, PUCCH cell, CC and active UL BWP
RRC configuration epoch
UCI report ID
K1 and K1 source
absolute due slot
PUCCH resource-set ID
PUCCH resource ID
decoded PRI value and DCI/CCE provenance
format and every format-specific parameter
power-control and spatial-relation state IDs
collision-resolution result
```

Supported assignment sources are separate factories:

```matlab
fromDynamicHARQ(decodedDCI, pdschEvents, ueContext, frameState)
fromSPSHARQ(spsContext, pdschEvents, ueContext, frameState)
fromSR(schedulingRequestState, ueContext, frameState)
fromCSI(csiReportState, ueContext, frameState)
fromCombinedUCI(report, ueContext, frameState)
forCalibration(explicitCalibrationRequest, frameState)
```

A connected dynamic assignment requires valid decoded DCI/PDSCH provenance. SR-only and periodic CSI use their configured resources. SPS uses its installed/activated context. Calibration is isolated and cannot create connected-mode evidence.

### Resource-set selection

Implement all configured sets and payload thresholds. Set 0 carries the short resources and the higher sets carry long resources according to the pinned release. Select the first configured set supporting `O_UCI`; do not skip a missing intermediate set by inventing a resource. Handle SPS-PUCCH-AN lists separately.

### Resource indicator

For sets with at most eight resources, apply the exact PRI table and field width. For set 0 with more than eight resources, implement the release-defined CCE/PRI formula using the decoded PDCCH first CCE and CORESET CCE count. Record every operand.

### K1 and TDD

Resolve K1 from the decoded timing indicator or the correct configured list. Bind numerology, feedback cell and BWP. The due slot is exact. Validate the configured PUCCH symbols against the resolved slot's D/U/F ownership after explicit flexible-symbol allocation. Never scan to a later UL slot and never move the configured start symbol.

## Format-complete implementation

Use one validator and one ownership-map engine for formats 0-4.

### Format 0

Implement all selected-profile legal one/two-symbol cases, 1/2 HARQ-ACK/SR bits, initial cyclic shift, hopping, sequence/group identity, multi-UE cyclic-shift separation, no-signal detection and wrong-sequence tests.

### Format 1

Implement all selected-profile legal 4-14 symbol cases, time-domain OCC, cyclic shift, hopping, multi-slot repetition, DM-RS/data symbol positions, ACK/SR mapping and orthogonality tests.

### Format 2

Implement one/two-symbol allocations, exact PRB count, DM-RS positions/sequences, UCI coding/rate matching, scrambling/RNTI, hopping/interlace extensions selected by the profile, and capacity checks.

### Format 3

Implement 4-14 symbols, variable PRBs, QPSK/pi/2-BPSK, transform precoding, additional DM-RS, hopping, repetition, interlaced mapping where selected, and exact receiver inverse processing.

### Format 4

Implement 4-14 symbols, format-specific one-PRB behavior outside applicable extensions, OCC length 2/4, OCC index, block-wise spreading, QPSK/pi/2-BPSK, additional DM-RS, hopping and repetition.

All format-specific values must come from the selected `PUCCHResource` and format configuration. Missing values do not become generic defaults.

## Exact resource ownership and collision handling

Build a zero-based ownership table before waveform generation with one row per actual RE and fields for:

```text
slot, symbol, PRB, subcarrier
format, hop, repetition
UCI/data or DM-RS owner
sequence/group/hopping identity
cyclic shift
OCC index and length
port/beam/spatial state
resource and report IDs
```

Use this map for:

```text
PUCCH vs PUCCH
PUCCH vs PUSCH
PUCCH vs SRS
PUCCH vs PRACH
PUCCH vs reserved/guard/flexible symbols
```

Apply the release-pinned simultaneous-transmission and UCI-multiplexing rules. A same PRB/symbol rectangle can still be orthogonal; a different rectangle can still conflict through an invalid hop or timing state. Record the exact decision and state transition.

## Power control and spatial relation

Implement the complete selected-profile PUCCH power ledger:

```text
P0 PUCCH state
pathloss-reference RS and measured/filter state
10log10(2^mu * M_RB)
format-dependent DeltaF
payload/resource-dependent DeltaTF
two closed-loop adjustment states where configured
TPC command source, delay and accumulation/absolute mode
P_CMAX clipping
requested, applied and measured waveform power
```

Reconcile applied and measured waveform power within 0.05 dB in strict tests.

Implement `PUCCHSpatialRelationState` using the configured SSB, NZP-CSI-RS or SRS reference, pathloss-reference ID, P0 ID, closed-loop index, serving cell and active MAC/TCI state. Reject stale or inactive state. Apply the selected spatial-domain filter to the actual waveform.

## Receiver and detection

The production receiver input may include:

```text
received waveform
carrier/frame synchronization state permitted by the profile
installed RRC/UE/report context
resolved expected resource/timing context
noise/covariance estimates derived or explicitly supplied by the test profile
```

It may not include:

```text
transmitted payload bits
transmitted decoded ACK/NACK/SR/CSI values
an invented payload length
an oracle resource different from the assignment known to the gNB
```

Derive payload lengths from the report/codebook configuration. Implement DTX/no-signal behavior for every declared format, wrong RNTI/scrambling identity, wrong resource, wrong sequence, wrong length and collision cases. Preserve decode failure reasons; do not return an empty payload as success.

## Independent validation

The supplied vector pack is a bounded floor, not permission to leave uncovered procedures. Add pure-spec MATLAB/Python implementations or frozen external vectors for at least:

```text
uci_report_serialization
uci_coding
harq_ack_codebook
sr_state
csi_report
resource_set_selection
resource_indicator including set0 >8
format_mapping 0-4
format-specific sequences and modulation
dmrs indices and sequence
hopping and repetition
k1/tdd timing
collision procedure
power control
spatial relation
```

A wrapper around the same MATLAB `nr*` function is self-consistency only. Record oracle implementation, version, source, command and SHA-256.

## Mandatory negative behavior and error identifiers

Use stable typed errors, including at least:

```text
sixgr:phy:pucch:MissingUCIReportContext
sixgr:phy:pucch:UCILengthMismatch
sixgr:phy:pucch:OracleInputForbidden
sixgr:phy:pucch:InvalidFormatPayload
sixgr:phy:pucch:InvalidSymbolAllocation
sixgr:phy:pucch:InvalidPRBAllocation
sixgr:phy:pucch:InvalidCyclicShift
sixgr:phy:pucch:InvalidOCC
sixgr:phy:pucch:InvalidHopping
sixgr:phy:pucch:DMRSGenerationFailed
sixgr:phy:pucch:NoSupportingResourceSet
sixgr:phy:pucch:InvalidResourceIndicator
sixgr:phy:pucch:InvalidK1
sixgr:phy:pucch:IllegalTDDResource
sixgr:phy:pucch:WrongRNTI
sixgr:phy:pucch:WrongResource
sixgr:phy:pucch:StaleBWP
sixgr:phy:pucch:StaleConfiguration
sixgr:phy:pucch:UnsupportedHARQCodebook
sixgr:phy:pucch:MissingSRConfiguration
sixgr:phy:pucch:MissingCSIReportConfiguration
sixgr:phy:pucch:CollisionUnresolved
sixgr:phy:pucch:InvalidPowerControlState
sixgr:phy:pucch:InactiveSpatialRelation
sixgr:phy:pucch:StaleSpatialRelation
```

Every rejected case must prove:

```text
WaveformGenerated = false
StateChanged = false
GrantCreated = false
ObservedErrorID = ExpectedErrorID
```

The no-signal case is different: execute the receiver and demonstrate DTX with a confidence-bounded false-alarm result.

## Mandatory MATLAB test suites

Add and execute at least:

```text
testUCIReportObject
testUCIReportSerialization
testUCICodingBoundaries
testUCIPrioritySerialization
testHARQACKCodebookType1
testHARQACKCodebookType2
testHARQACKCodebookType3
testSchedulingRequestState
testSchedulingRequestMultiplexing
testCSIReportBuilder
testCSIPart2Serialization
testPUCCHResourceSetSelection
testPUCCHResourceIndicator
testPUCCHSet0LargeResourceList
testPUCCHDynamicHARQAssignment
testPUCCHSPSAssignment
testPUCCHSRAndCSIAssignments
testPUCCHFormat0Complete
testPUCCHFormat1Complete
testPUCCHFormat2Complete
testPUCCHFormat3Complete
testPUCCHFormat4Complete
testPUCCHDMRSComplete
testPUCCHHoppingAndRepetition
testPUCCHInterlacedMapping
testPUCCHK1TDDTiming
testPUCCHCollisionResolution
testPUCCHPUSCHMultiplexing
testPUCCHPowerControl
testPUCCHSpatialRelation
testPUCCHNoNoiseRoundTrip
testPUCCHAWGNCampaign
testPUCCHTDLAndCDL
testPUCCHNoSignalFalseAlarm
testPUCCHWrongRNTI
testPUCCHWrongLength
testPUCCHWrongResource
testPUCCHNegativeMatrix
testPUCCHArtifactGeneration
```

For every positive resource/mapping test, add at least one one-bit/one-index perturbation that must fail. For every strict negative test, assert zero waveform/state mutation.

## Required base CSV artifacts

Generate these 23 CSVs from actual production MATLAB execution:

- pucch_uci_report_resolution.csv
- pucch_uci_serialization.csv
- pucch_uci_coding.csv
- pucch_harq_codebook.csv
- pucch_sr_events.csv
- pucch_csi_reports.csv
- pucch_resource_set_selection.csv
- pucch_resource_indicator_selection.csv
- pucch_resource_mapping.csv
- pucch_format_matrix.csv
- pucch_dmrs_sequence.csv
- pucch_hopping_repetition.csv
- pucch_timing_k1_tdd.csv
- pucch_collision_resolution.csv
- pucch_power_control.csv
- pucch_spatial_relation.csv
- pucch_receiver_metrics.csv
- pucch_bler_curve.csv
- pucch_false_alarm_trials.csv
- pucch_negative_tests.csv
- pucch_independent_vector_results.csv
- pucch_test_summary.csv
- pucch_image_semantic_audit.csv

Use `desired_pucch_csv_contract.csv` as the minimum schema. Do not emit a PASS row before all values are finite, provenance is present, and the actual comparison has executed.

## Required base technical figures

Generate these 15 PNGs from the corresponding production CSVs:

- pucch_resource_grid_ownership.png
- pucch_uci_bit_layout.png
- pucch_format_resource_matrix.png
- pucch_harq_codebook_timeline.png
- pucch_sr_csi_multiplexing.png
- pucch_k1_tdd_timeline.png
- pucch_resource_set_pri_map.png
- pucch_dmrs_hopping_map.png
- pucch_format1_occ_correlation.png
- pucch_format4_occ_spreading.png
- pucch_power_control_convergence.png
- pucch_spatial_relation_beam_timeline.png
- pucch_bler_vs_snr.png
- pucch_false_alarm_bounds.png
- pucch_collision_resolution.png

Each plot must be at least 900 x 600, nonblank, generated by MATLAB from production CSV values, and recorded in `pucch_image_semantic_audit.csv` with title, labels, axes/series/point counts and SHA-256 for both the source CSV set and the PNG.

## Impact-analysis execution

Execute all 600 rows in `pucch_impact_experiment_matrix.csv`. Each family contains six baseline/treatment pairs. Within a pair, preserve identical:

```text
seed
trial index
payload identity
channel realization
noise realization
UE/context state not named as the factor
```

Only the declared factor may change.

Impact families:

- F01: UCI report composition and serialization [Wave A; dependency: none; primary metric: BitMismatchCount]
- F02: UCI coding and CRC boundary behavior [Wave A; dependency: none; primary metric: BLER]
- F03: HARQ-ACK codebook type and size [Wave A; dependency: decoded PDSCH/DCI event state; primary metric: HARQBitErrors]
- F04: HARQ priority-index multiplexing [Wave A; dependency: none; primary metric: HARQBitErrors]
- F05: SR periodicity and offset [Wave A; dependency: none; primary metric: SRLatencySlots]
- F06: HARQ-ACK and SR multiplexing [Wave A; dependency: none; primary metric: BLER]
- F07: SR and CSI multiplexing [Wave A; dependency: none; primary metric: BLER]
- F08: CSI Part 1 payload size [Wave A; dependency: CSI report builder; primary metric: BLER]
- F09: CSI Part 2 payload size [Wave A; dependency: CSI report builder; primary metric: BLER]
- F10: Multiple CSI report ordering [Wave A; dependency: CSI report builder; primary metric: BitMismatchCount]
- F11: PUCCH resource-set selection [Wave A; dependency: RRC PUCCH state; primary metric: ResourceSelectionError]
- F12: Format selection by symbol length and payload [Wave A; dependency: RRC PUCCH state; primary metric: BLER]
- F13: Format-0 cyclic-shift orthogonality [Wave A; dependency: none; primary metric: CrossCorrelation]
- F14: Format-1 OCC orthogonality [Wave A; dependency: none; primary metric: CrossCorrelation]
- F15: Format-2 PRB and symbol efficiency [Wave A; dependency: none; primary metric: SpectralEfficiency]
- F16: Format-3 DMRS density and pi/2-BPSK [Wave A; dependency: none; primary metric: BLER]
- F17: Format-4 spreading factor and OCC [Wave A; dependency: none; primary metric: BLER]
- F18: Intra-slot frequency hopping [Wave A; dependency: none; primary metric: BLER]
- F19: Inter-slot hopping and repetition [Wave B; dependency: central timing/repetition state; primary metric: BLER]
- F20: Group and sequence hopping [Wave A; dependency: none; primary metric: CrossCorrelation]
- F21: Interlaced PUCCH shared-spectrum mapping [Wave B; dependency: shared-spectrum/interlace engine; primary metric: Occupancy]
- F22: K1 feedback timing [Wave A; dependency: decoded DCI timing state; primary metric: LatencySlots]
- F23: TDD UL-symbol availability [Wave A; dependency: central frame/TDD engine; primary metric: AvailabilityProbability]
- F24: PUCCH resource indicator mapping [Wave A; dependency: decoded DCI PRI; primary metric: ResourceSelectionError]
- F25: Set-0 resource list larger than eight [Wave A; dependency: PDCCH CCE provenance; primary metric: ResourceSelectionError]
- F26: Active UL BWP switching [Wave B; dependency: multi-BWP state; primary metric: GrantSuccess]
- F27: Cross-carrier PUCCH cell selection [Wave B; dependency: multi-carrier state; primary metric: GrantSuccess]
- F28: PUCCH and PUSCH simultaneous-UCI procedure [Wave B; dependency: PUSCH UCI integration; primary metric: UCIRecoveryRate]
- F29: PUCCH and SRS collision resolution [Wave B; dependency: SRS resource engine; primary metric: CollisionRate]
- F30: PUCCH and PRACH collision resolution [Wave C; dependency: PRACH occasion engine; primary metric: CollisionRate]
- F31: Multiple-PUCCH priority/collision resolution [Wave A; dependency: none; primary metric: CollisionRate]
- F32: Open-loop PUCCH power control [Wave A; dependency: pathloss measurement state; primary metric: PowerError_dB]
- F33: Closed-loop PUCCH TPC convergence [Wave A; dependency: decoded TPC state; primary metric: PowerError_dB]
- F34: Format-dependent deltaF and deltaTF [Wave A; dependency: none; primary metric: PowerError_dB]
- F35: P_CMAX clipping [Wave A; dependency: none; primary metric: EVM]
- F36: Spatial relation and beam selection [Wave B; dependency: beam/TCI state; primary metric: BLER]
- F37: Pathloss-reference RS ageing [Wave B; dependency: measurement filtering state; primary metric: PowerError_dB]
- F38: Beam switching and blockage [Wave C; dependency: beam failure/recovery engine; primary metric: BLER]
- F39: Format-0-to-4 AWGN performance [Wave A; dependency: none; primary metric: BLER]
- F40: Delay-spread sensitivity [Wave A; dependency: TDL/CDL channel; primary metric: BLER]
- F41: Doppler sensitivity [Wave A; dependency: TDL/CDL channel; primary metric: BLER]
- F42: CFO sensitivity [Wave C; dependency: RF CFO estimator; primary metric: BLER]
- F43: Timing-offset sensitivity [Wave C; dependency: timing acquisition/tracking; primary metric: BLER]
- F44: Phase-noise sensitivity [Wave C; dependency: phase-noise process; primary metric: BLER]
- F45: No-signal false-alarm and DTX [Wave A; dependency: none; primary metric: FalseAlarmProbability]
- F46: Wrong-RNTI rejection [Wave A; dependency: none; primary metric: FalseGrantProbability]
- F47: Wrong-length rejection [Wave A; dependency: none; primary metric: FalseDecodeProbability]
- F48: Wrong-resource/PRI rejection [Wave A; dependency: none; primary metric: FalseDecodeProbability]
- F49: Multi-UE near-far and orthogonality [Wave B; dependency: multi-user waveform channel; primary metric: BLER]
- F50: Runtime, memory, reproducibility and end-to-end [Wave A; dependency: all selected core features; primary metric: RuntimeMs]

Wave A is direct PUCCH/UCI work. Wave B requires coherent integration with internal multi-BWP, multi-carrier, PUSCH/SRS or beam state and remains mandatory for final completion. Wave C requires the real adjacent PRACH/beam-failure/RF subsystem. Do not replace a missing adjacent subsystem with a scalar proxy and call the experiment complete.

## Statistical analysis

Implement:

```text
Wilson intervals for ordinary BLER/BER/detection estimates
exact one-sided Clopper-Pearson upper bounds for zero false alarms/false grants
McNemar tests for paired decode outcomes
paired bootstrap confidence intervals for SINR, EVM, power, latency and runtime
Holm adjustment within related hypothesis families
signed effect = treatment - baseline
engineering effect-size thresholds declared before execution
explicit inconclusive/incomplete status when evidence is insufficient
```

No mandatory operating point may be incomplete. A nonsignificant result is not equality; equivalence requires a predefined margin.

## Required impact figures

Generate all 28 impact PNGs:

- pucch_impact_uci_composition.png
- pucch_impact_coding_boundaries.png
- pucch_impact_harq_codebook.png
- pucch_impact_sr_periodicity.png
- pucch_impact_csi_size.png
- pucch_impact_resource_set.png
- pucch_impact_format_selection.png
- pucch_impact_format0_cyclic_shift.png
- pucch_impact_format1_occ.png
- pucch_impact_format2_efficiency.png
- pucch_impact_format3_dmrs.png
- pucch_impact_format4_spreading.png
- pucch_impact_hopping_diversity.png
- pucch_impact_repetition.png
- pucch_impact_interlace.png
- pucch_impact_k1_latency.png
- pucch_impact_tdd_availability.png
- pucch_impact_pri_mapping.png
- pucch_impact_collision_matrix.png
- pucch_impact_power_control.png
- pucch_impact_power_clipping.png
- pucch_impact_spatial_relation.png
- pucch_impact_bler_formats.png
- pucch_impact_delay_doppler.png
- pucch_impact_cfo_timing.png
- pucch_impact_false_alarm.png
- pucch_impact_near_far.png
- pucch_impact_effect_forest.png

Also generate every CSV in `desired_pucch_impact_csv_contract.csv` and run the impact artifact verifier.

## Required commands

Run from repository root, adapting only paths required by the actual project layout:

```bash
python tests/vectors/pucch/verify_pucch_vector_pack.py
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PUCCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*UCI*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.pucch.runPUCCHPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','pucch'),'OutputDir',fullfile(pwd,'artifacts','pucch_uci_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/pucch/verify_pucch_artifacts.py artifacts/pucch_uci_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.pucch.runPUCCHImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','pucch','pucch_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','pucch_uci_impact'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/pucch/verify_pucch_impact_artifacts.py artifacts/pucch_uci_impact
```

Then run the complete repository MATLAB regression suite on the pinned MATLAB and 5G Toolbox release.

## Definition of done

You may report `COMPLETE` only when all conditions are true:

1. all ten findings are closed in production code;
2. no connected receiver receives expected payload bits or an invented length;
3. all selected UCI report/codebook fields are built from decoded/configured procedure state;
4. exact resource set, resource indicator, K1, TDD, BWP and report-source ownership is active;
5. formats 0-4 pass every declared positive and negative tuple;
6. hopping, repetition, DM-RS, OCC/cyclic shift and exact collision procedures pass;
7. requested/applied/measured power and spatial relation evidence reconcile;
8. all mandatory MATLAB tests executed with zero failures, skips or blocks;
9. all 23 base CSVs and 15 base PNGs pass;
10. all 600 impact experiments and 75 rules execute;
11. all 16 impact CSVs and 28 impact PNGs pass;
12. both Python artifact verifiers return exit code 0;
13. same-Toolbox tests are labelled self-consistency and independent oracle families have zero mismatches;
14. the complete repository regression suite passes.

`BLOCKED` is allowed only with the exact missing external dependency, command, error, affected test IDs and affected impact families. It is not `COMPLETE`.

## Required Codex final response

Report:

```text
phase and finding IDs
files changed
production architecture implemented
legacy paths removed or delegated
tests added/changed
exact commands executed
MATLAB and 5G Toolbox versions
test pass/fail/skip/block counts
vector mismatch counts
base CSV row counts and SHA-256
base PNG dimensions and SHA-256
impact experiment completion count
rule pass/fail/inconclusive counts
impact CSV/PNG hashes
artifact-verifier exit codes
remaining real technical dependencies
final COMPLETE / FAIL / BLOCKED status
```

Begin by adding failing tests for PUCCH-002, PUCCH-003, PUCCH-007 and PUCCH-008. Remove receiver oracle/default-length behavior and runtime resource/timing mutation before expanding breadth.


# Appendix A — source-by-source migration requirements

This appendix is mandatory. Do not leave the old behavior behind a second code path.

## A.1 `+sixgr/+phy/+ul/PUCCH_Tx.m`

Convert this file to a compatibility facade. Its connected-mode path shall accept a `PUCCHTransmissionAssignment` and a typed `UCIReport`; it shall not read ad-hoc `phy.pucch.*` defaults. Delete or delegate every local behavior that currently:

```text
selects format 2 when no format is supplied
uses RNTI 1 when no RNTI is supplied
accepts an arbitrary flat uciBits vector for connected operation
chooses [0 2] symbols to make G large enough
falls back from PUCCH NID to carrier cell ID without procedure context
rounds or clamps SecondHopStartPRB
modulo-wraps InitialCyclicShift
rounds or clamps OCCI
rounds or clamps SpreadingFactor
rounds or clamps HoppingID
swallows DM-RS generation failure
```

The facade may expose a clearly named calibration-only API that accepts an explicit synthetic payload and complete explicit resource, but that path must set:

```text
ExecutionProfile = calibration
ConnectedModeEvidenceEligible = false
```

The canonical transmitter shall return:

```text
assignment digest
report digest
serialization digest
coding-plan digest
resource-ownership digest
DM-RS sequence/index digests
hopping/repetition digests
power/spatial-state digests
waveform SHA-256
```

## A.2 `+sixgr/+phy/+ul/PUCCH_Rx.m`

Remove `ExpectedUCIBits` from the production signature. Replace `NumUCIBits` with a typed `UCIReportContext` containing only expected report schema, field widths, codebook state, priority and resource context. Add an explicit guard that rejects any field containing transmitted payload values.

Delete the following behavior:

```text
ouci = numel(ExpectedUCIBits)
ouci = 20
catch nrUCIDecode and return []
format/resource defaults duplicated from TX
parameter clamp/modulo logic duplicated from TX
comparison against transmitted bits inside the receiver
```

The receiver shall return decoded report fields and confidence/detection state. Test comparison against transmitted bits belongs in the validation harness after the receiver returns.

Required output fields include:

```text
ReceiverUsable
DetectionAttempted
DTX
DetectionMetric and threshold
DecodedSequence1 and DecodedSequence2
Decoded HARQ-ACK/SR/CSI field objects
Coding/CRC result per sequence
WrongRNTI / WrongResource / WrongSequence indicators
MeasuredSINR and EVM
FailureReason and typed error
OraclePayloadBitsUsed = false
```

## A.3 `+sixgr/+link/runPUCCHWaveformTrial.m`

Replace the `ExpectedUCIBits`-driven execution contract with:

```matlab
trial = runPUCCHWaveformTrial(cfg, ...
    "Assignment", assignment, ...
    "Report", report, ...
    "ChannelProfile", channelProfile, ...
    "ReceiverContext", receiverContext, ...
    "Seed", seed);
```

The validation harness may retain transmitted report bits outside the receiver to calculate errors after decode. Remove:

```text
default ExpectedUCIBits=int8(1)
random payload extension using uciPayloadBits
format promotion/demotion based on payload size
fallback to format 2 for an invalid request
six-bit CRC assumption for all A >= 12
```

The trial must expose separate statuses for:

```text
assignment rejection
report construction rejection
resource mapping rejection
waveform generation failure
receiver DTX
receiver decode failure
CRC failure
content mismatch
```

Do not collapse all failures to `Ok=false` without provenance.

## A.4 `+sixgr/+phy/+pucch/runStrictPUCCHValidation.m`

Replace the five-case fixture with a vector-driven runner that executes every row in:

```text
pucch_uci_report_test_vectors.csv
pucch_uci_coding_test_vectors.csv
pucch_format_matrix_test_vectors.csv
pucch_resource_set_test_vectors.csv
pucch_resource_indicator_test_vectors.csv
pucch_harq_codebook_test_vectors.csv
pucch_sr_test_vectors.csv
pucch_csi_report_test_vectors.csv
pucch_k1_tdd_test_vectors.csv
pucch_collision_test_vectors.csv
pucch_power_control_test_vectors.csv
pucch_spatial_relation_test_vectors.csv
pucch_negative_test_vectors.csv
pucch_declared_coverage_matrix.csv
```

Do not generate local resource defaults. Every positive test must construct a complete RRC/UE/DCI/report context and invoke production factories. Every negative test must fail at its declared layer.

## A.5 `+sixgr/+phy/+pucch/exportStrictPUCCHArtifacts.m`

Expand this exporter to all base CSVs and technical PNGs in the contracts. The exporter shall compute hashes after final write, then reopen and validate every CSV and PNG. No artifact row may claim PASS before the file exists and its hash is recorded.

Use source CSVs—not hidden workspace arrays—as the only input to final plotting. This guarantees that a figure can be regenerated from its auditable data.

## A.6 `+sixgr/+truth/CoupledTruthRuntime.m`

Replace the following runtime functions or delegate them to canonical PUCCH services:

```text
resolveHARQFeedbackDueSlot
fitPUCCHSymbolsToULPartition
resolvePUCCHResourceAssignment
resolveCompatiblePUCCHFormat
resolvePUCCHFormatAdaptationReason
pucchResourcesOverlap
buildPUCCHInterferenceBundle payload construction
```

Mandatory behavior changes:

```text
HARQFeedbackSlots default 4 -> removed from strict connected mode
scan for a later UL slot -> prohibited
shift symbols to fit -> prohibited
minimum one UCI bit -> prohibited
requested format default 2 -> prohibited
2/1 PRB heuristic -> prohibited
2/4 symbol heuristic -> prohibited
RNTI/cell PRB hash -> prohibited
UCIType="harq_ack" -> replaced by typed report
rectangular overlap -> replaced by exact ownership/collision result
single expected ACK interferer -> replaced by complete typed report/waveform
```

The runtime must store immutable event links:

```text
PDSCH/DCI event -> HARQ codebook entry
HARQ/SR/CSI state -> UCI report
UCI report + RRC/PRI/K1 -> PUCCH assignment
assignment -> resource ownership map
ownership map + power/spatial state -> waveform
waveform -> receiver report
receiver report -> MAC/HARQ state transition
```

## A.7 configuration migration

Replace `config/phy/pucch.json` with a schema representing actual RRC/procedure state. Do not retain global defaults such as `format: 2`, `numUCIBits: 20`, or `type: ACK+CSI` as connected-mode truth.

A bounded example configuration may include:

```yaml
pucch:
  profile: nr_rel18_pucch_strict
  configuration_epoch: 1
  resource_sets:
    - id: 0
      resource_ids: [0, 1, 2, 3]
    - id: 1
      max_payload_size: 20
      resource_ids: [10, 11, 12, 13]
    - id: 2
      max_payload_size: 100
      resource_ids: [20, 21]
    - id: 3
      resource_ids: [30]
  resources:
    - id: 0
      format: 0
      starting_prb: 0
      starting_symbol: 12
      nrof_symbols: 2
      initial_cyclic_shift: 0
    - id: 10
      format: 2
      starting_prb: 4
      nrof_prbs: 2
      starting_symbol: 12
      nrof_symbols: 2
  dl_data_to_ul_ack: [1, 2, 3, 4, 5, 6, 7, 8]
  power_control: ...
  spatial_relations: ...
```

Validate all cross-references, duplicate IDs, payload thresholds, BWP bounds and format-specific fields at load time.

# Appendix B — implementation order and required checkpoints

Use the following dependency order. Commit phase-sized changes; do not create one uncontrolled patch.

## B.1 Checkpoint 1: receiver oracle removal

1. Add a failing test proving the current receiver accepts `ExpectedUCIBits`.
2. Add `UCIReportContext` and derive lengths without payload values.
3. Remove `ExpectedUCIBits` and `ouci=20` from production.
4. Add reflection/static dependency tests proving those symbols are absent from production receiver code.
5. Run format-2 no-noise and wrong-length cases.

Checkpoint passes only when the receiver decodes without knowing transmitted values.

## B.2 Checkpoint 2: report serialization/coding

1. Implement typed HARQ, SR and CSI subreports.
2. Implement sequence serialization, including two-part CSI and priority-index cases.
3. Implement explicit coding plans and CRC/segmentation boundaries.
4. Compare against all supplied serialization/coding vectors.
5. Add one-bit perturbation tests at each boundary.

## B.3 Checkpoint 3: resource and timing ownership

1. Materialize PUCCH RRC context.
2. Implement resource-set selection.
3. Implement PRI including set 0 larger than eight resources.
4. Implement exact K1 and due slot.
5. Bind TDD symbol legality without shifts.
6. Replace runtime deterministic resource assignment.

## B.4 Checkpoint 4: short formats

Complete formats 0 and 1 over all declared lengths, cyclic shifts, OCC values, hopping and repetition combinations. Add multi-UE orthogonality and near-far tests.

## B.5 Checkpoint 5: long formats

Complete formats 2, 3 and 4 over payload, PRB, symbol, coding, modulation, DM-RS, hopping, interlace, spreading and repetition combinations.

## B.6 Checkpoint 6: codebooks, SR and CSI procedures

Complete Type-1/2/3 HARQ codebooks for the selected profile, SR state machines, multiple CSI reports, Part 2 and priority multiplexing. Link every bit to its event/configuration source.

## B.7 Checkpoint 7: collisions and PUSCH integration

Implement exact simultaneous-UCI/collision procedures. Integrate with the canonical PUSCH UCI path rather than duplicating coding or report objects.

## B.8 Checkpoint 8: power and spatial relation

Implement the full power ledger and spatial-domain filter state. Verify requested/applied/measured power and beam identity.

## B.9 Checkpoint 9: statistical campaigns and artifacts

Run multi-seed BLER, false-alarm and wrong-context campaigns. Generate all CSVs/PNGs, run verifiers and then execute the complete repository regression suite.

# Appendix C — mandatory scenario matrix

At minimum, the final runtime campaign shall include all of the following classes. Add cases when the selected capability matrix is broader.

## C.1 UCI content

```text
1 HARQ-ACK bit
2 HARQ-ACK bits
4+ HARQ-ACK codebook bits
positive and negative SR
multiple simultaneous SR identities where configured
CSI Part 1 only
CSI Part 1 + Part 2
multiple CSI reports with different priority
HARQ + SR
HARQ + CSI
SR + CSI
HARQ + SR + CSI
mixed priority-index UCI
```

## C.2 Format/resource matrix

```text
Format 0: 1 and 2 symbols; every legal selected cyclic shift; hopping on/off
Format 1: 4 through 14 symbols; legal OCC indices; hopping on/off; repetition
Format 2: 1 and 2 symbols; multiple PRB counts; payload/coding boundaries
Format 3: 4 through 14 symbols; QPSK/pi/2-BPSK; additional DM-RS; hopping/repetition
Format 4: 4 through 14 symbols; OCC length 2 and 4; every legal OCC index
```

## C.3 Timing and ownership

```text
DCI 1_0 default K1 mappings
configured dl-DataToUL-ACK mappings
SPS activation timing
FDD and TDD
full UL slot
special slot with legal UL symbols
illegal DL-owned symbols
explicitly allocated flexible symbols
multi-BWP switch before feedback
cross-carrier feedback cell
PRI field widths 0/1/2/3
set 0 with <=8 and >8 resources
sets 1-3 payload thresholds
SR-only resource
CSI-only resource
SPS-PUCCH-AN resource
```

## C.4 Channel and receiver

```text
no-noise round trip
AWGN sweep
TDL-C low/high delay spread
CDL-C low/high Doppler
1 and 2 receive antennas where supported
CFO positive/negative
residual timing within/outside CP
phase-noise profiles
no signal
wrong RNTI/scrambling identity
wrong resource, cyclic shift, OCC and DM-RS identity
near-far multi-UE interference
```

## C.5 Collision matrix

```text
non-overlapping PUCCH resources
same rectangle but orthogonal cyclic shifts
same rectangle but orthogonal OCC
actual RE/sequence collision
PUCCH HARQ + PUCCH SR
PUCCH HARQ + PUCCH CSI
PUCCH + PUSCH
PUCCH + SRS
PUCCH + PRACH
multiple priorities
repetition/hopping collision in only one slot or hop
```

# Appendix D — cross-artifact invariants

The following invariants must be checked after every run:

1. Sum of serialized bit owners equals the report's information-bit count plus declared padding.
2. Coding-plan A equals serialized sequence length; E equals the exact mapped coded-bit capacity.
3. Every mapped UCI/DM-RS RE has one owner; every waveform nonzero RE is represented in the ownership table.
4. Selected resource ID exists in the selected resource set and active configuration epoch.
5. K1 due slot equals the decoded/configured mapping and never a searched alternative.
6. Resource symbols in `pucch_resource_mapping.csv` equal the symbols in `pucch_timing_k1_tdd.csv`.
7. HARQ codebook bits equal the HARQ portion of serialized UCI in order.
8. SR and CSI field widths equal the serialized offsets in the UCI table.
9. Requested/applied/measured power reconcile and use the same power/spatial-state IDs.
10. Receiver format/resource/report context digests equal the transmitter assignment digest but contain no transmitted payload values.
11. BLER numerator/denominator reconcile with raw trial rows.
12. False-alarm counts reconcile with no-signal raw trials and confidence bounds.
13. Every plot source CSV hash matches the actual CSV file.
14. Every mandatory test and experiment appears exactly once in summaries.
15. A failed or blocked required row makes the phase summary fail.

# Appendix E — performance and engineering constraints

Correctness has priority over speed, but implement the chain efficiently:

```text
cache immutable RRC/schema tables by configuration epoch
cache sequence tables only when their full keys match
vectorize RE map construction without hiding ownership
preallocate raw-trial/artifact tables
make serial and parallel runs seed-identical
avoid copying full waveforms into every trace row; store hashes and explicit artifact paths
```

Measure runtime and memory versus format, payload bits, PRBs, symbols, report count, number of UEs and receiver antennas. A performance optimization is acceptable only after bit/index/power artifacts remain identical.

# Appendix F — forbidden completion shortcuts

The following are explicit phase failures:

```text
keeping ExpectedUCIBits under a renamed field
passing a payload digest that can be inverted or directly compared inside RX
using payload length from the transmitted vector rather than report context
using one hard-coded CSI report layout
using one ACK bit for all codebooks
using configured ACK/NACK truth instead of decoded PDSCH/HARQ events
format promotion or demotion
clamping or modulo-wrapping invalid resource parameters
searching for a later UL slot
moving the PUCCH symbol start
hashing RNTI into a resource
declaring orthogonality from rectangles alone
using ideal beam/pathloss state without provenance in strict tests
using configured SNR in place of measured receiver SINR
one no-signal trial presented as a false-alarm campaign
same-Toolbox outputs presented as independent references
copying expected CSVs into output
creating placeholder PNGs not sourced from production CSVs
marking Wave B/C experiments complete with scalar proxies
reporting COMPLETE while any mandatory point is blocked, skipped or incomplete
```
