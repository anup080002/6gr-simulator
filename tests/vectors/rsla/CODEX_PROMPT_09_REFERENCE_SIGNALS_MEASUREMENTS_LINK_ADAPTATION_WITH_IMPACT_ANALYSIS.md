# CODEX IMPLEMENTATION PROMPT 09 — REFERENCE SIGNALS, MEASUREMENTS AND LINK ADAPTATION

## Mission

You are the lead MATLAB 5G PHY implementation engineer for this repository. This task is **not a review** and is **not a truth-contract/documentation exercise**. Modify the live simulator and execute the corrected chain. Close all 18 RSM findings for the selected bounded Release-18 profiles, while rejecting every unsupported tuple before waveform generation.

Implement and prove the following causal chain:

```text
RRC-owned DM-RS / CSI-RS / CSI-IM / SRS / TRS / PT-RS configuration
    ↓
exact zero-based resource and sequence generation
    ↓
one collision/orthogonality ownership map
    ↓
actual OFDM waveform and channel
    ↓
receiver-derived channel, interference, timing, CFO, CPE and measurement state
    ↓
typed CSI report configuration and exact Part 1 / Part 2 fields
    ↓
TS 38.212 UCI coding and PUCCH/PUSCH transport
    ↓
decoded, semantically valid, non-stale CSI report
    ↓
profile-calibrated effective SINR and CQI/MCS mapping
    ↓
per-UE OLLA
    ↓
actual decoded DCI and PDSCH/PUSCH assignment
    ↓
ACK/NACK/DTX feedback and next measured adaptation decision
```

## Repository inputs

Use the files placed under `tests/vectors/rsla/` as immutable test inputs and bounded independent analytical floors. The authoritative work list is `reference_signals_measurements_link_adaptation_18_findings.csv`. The capability matrix is `rsla_capability_profile_matrix.csv`.

Do not copy expected CSVs into production output. Production CSVs must be serialized from the corrected MATLAB objects and actual runtime results.

## Pinned baseline

Pin exact specification versions in code and artifacts: TS 38.211 V18.8.0, TS 38.212 V18.8.0, TS 38.213 V18.8.0, TS 38.214 V18.9.0, TS 38.215 V18.8.0, TS 38.331 V18.9.0, and the selected TR 38.901 channel profile. RF EVM pass/fail claims require a separately pinned TS 38.101/38.104 device profile; otherwise export EVM as a receiver/waveform implementation metric only.

CQI thresholds, EESM beta, MIESM mapping curves, smoothing constants and OLLA are implementation/calibration policies. Do not label them universal 3GPP thresholds. The strict requirement is that their dataset, profile key, confidence, holdout performance and hash are explicit.

## Non-negotiable implementation rules

- Edit production MATLAB source and migrate all live callers. Do not return a plan-only response.
- Do not create a second unused reference-signal stack. Existing public wrappers may remain only as façades over the canonical package.
- No strict function may clamp, modulo-wrap, crop, pad, retry, substitute a default, or silently change an invalid RS/measurement configuration.
- No connected steady-state CSI or MCS decision may use configured SNR, configured CQI, configured MCS, true channel, true Doppler, true timing, scheduler intention, transmitted payload bits or an oracle resource identity.
- No emitted measurement may be called observed unless it is computed from received samples or an explicitly allowed decoded receiver state.
- No strict CSI report may use the current compact RI/PMI/CQI container.
- No strict EESM/MIESM operation may use a fallback beta or a dataset that does not exactly match the profile key.
- No strict OLLA state may be shared across UEs, directions, cells, BWPs or MCS tables.
- No same-MATLAB-Toolbox comparison may be called independent validation. Label it self-consistency and add a pure-math or frozen independent vector.
- Unsupported advanced CSI-RS, SRS, measurement or report combinations must fail in planning and generate no waveform or scheduler/HARQ mutation.
- A missing mandatory MATLAB test, incomplete campaign point, absent CSV/PNG or nonzero verifier exit code means the phase is not complete.

## The 18 findings to implement

| ID | Priority | Production implementation | Mandatory acceptance |
|---|---:|---|---|
| **RSM-001** | P1 | Implement one release-pinned PDSCH/PUSCH DM-RS resource, sequence and port engine. It must own mapping A/B, type-A position, configuration types 1/2, length 1/2, additional positions, scrambling identities, logical ports, CDM groups, OCC, hopping, exact zero-based REs and receiver estimation. | Every enabled tuple must match an independent index/sequence vector and pass no-noise plus frequency-selective fading round trips. |
| **RSM-002** | P2 | Implement immutable RRC-owned NZP-CSI-RS, ZP-CSI-RS and CSI-IM resources/resource sets with exact row, density, CDM, ports, symbols, subcarrier offsets, periodic/semi-persistent/aperiodic triggering, muting, QCL and report associations. | Every declared row/type must have exact RE ownership and measured report tests. Unsupported rows fail before grid generation. |
| **RSM-003** | P1 | Keep the current anchor explicitly named, then implement selected one/two/four-port periodic, semi-persistent and aperiodic SRS resource sets with exact comb, cyclic shift, sequence ID, bandwidth, repetition, symbol placement and usage. | All declared resources map and decode exactly; unsupported tuples return typed planning errors and generate no waveform. |
| **RSM-004** | P2 | Implement SRS antenna switching, codebook and non-codebook usage, intra-resource hopping, full/partial-BWP sounding, resource-set trigger ownership, DCI/RRC activation and receiver channel/covariance estimation. | Independent maps and closed-loop SRS-to-RI/SRI/TPMI decisions pass for fresh, stale, wrong-UE and wrong-resource cases. |
| **RSM-005** | P1 | Create timestamped ULChannelSoundingState with UE/cell/BWP/resource/beam identity, channel and covariance digests, calibration state, age and validity. The scheduler may consume only a valid measured state. | Changing measured SRS changes the selected rank/precoder. Configured TPMI and stale/wrong-resource estimates cannot drive a strict grant. |
| **RSM-006** | P1 | Model TRS as the selected NZP-CSI-RS tracking resource set with exact resources, periodicity, QCL association and receiver measurement state rather than as a generic one-port two-slot token. | Exact TRS maps and no-oracle timing/frequency/channel estimates pass for every declared profile. |
| **RSM-007** | P1 | Add a stateful timing/CFO tracker with acquisition, loop update, age, confidence, correction application to later samples and residual-error lineage. No configured Doppler/CFO may substitute for an estimate. | Impairment sweeps demonstrate reduced residual timing/CFO and improved downstream EVM/BLER without true-value receiver inputs. |
| **RSM-008** | P1 | Implement exact DL and UL PT-RS density, offset, port association, sequence and mapping together with joint DM-RS/PT-RS common-phase-error estimation and correction. | Independent PT-RS maps pass and measured phase/EVM/BLER before/after curves demonstrate benefit and failure boundaries. |
| **RSM-009** | P0 | Replace custom compact RI/PMI/CQI packing with typed report-configuration-dependent CSI fields, exact Part 1/Part 2 ownership, TS 38.212 UCI serialization and canonical PUCCH/PUSCH transport. | Every enabled report configuration packs, transmits, decodes and reconstructs bit-exactly; the decoded report updates scheduler state. |
| **RSM-010** | P1 | Strict CSI generation requires receiver-derived channel, interference/noise and reference-signal measurements with resource identity, timestamp, age and confidence. Remove configured-SNR and rough-CQI fallbacks. | Deleting measured inputs or replacing them with configured SNR fails closed. All strict CSI decisions carry observed provenance. |
| **RSM-011** | P1 | Create versioned calibration datasets keyed by direction, waveform, MCS/CQI table, receiver, channel, rank, numerology, DM-RS/PT-RS profile and target BLER. Do not call laboratory thresholds normative. | Per-MCS calibration and held-out validation reproduce the target BLER within declared confidence and error bounds. |
| **RSM-012** | P1 | Implement linear-domain EESM and selected MIESM mapping with calibration parameters keyed by the complete operating profile. Missing calibration is a strict error; 1.5 dB fallback is removed. | Independent formulas pass and held-out frequency-selective drops predict BLER within configured bounds. |
| **RSM-013** | P1 | Implement event-sourced per-UE/per-direction/per-table OLLA with separate ACK/NACK steps, target-BLER-consistent drift, saturation, reset, ageing, DTX policy and state provenance. | Multi-seed campaigns converge to target BLER, remain bounded, reset correctly and show no cross-UE/cell leakage. |
| **RSM-014** | P1 | Create an explicit bounded acquisition state. Bootstrap CQI/MCS may be used only before valid measurement/report acquisition and must be separately labelled and excluded from measured steady-state results. | After transition, every MCS decision is caused by a decoded valid report or measured SRS state; bootstrap never reappears silently. |
| **RSM-015** | P2 | Parameterize filtering, prediction and ageing by report periodicity, processing/feedback latency, measured mobility/coherence and calibration data. Treat this as receiver policy, not a normative constant. | Held-out mobility sweeps bound stale-report error and maintain target-BLER stability without simulator-truth mobility inputs. |
| **RSM-016** | P1 | Create a versioned registry for selected SS-RSRP, CSI-RSRP, SS-RSRQ, CSI-RSRQ, SS-SINR, CSI-SINR, RSSI and SRS-RSRP profiles, including exact reference signal, RE set, averaging, units, beam/antenna association and validity. | Analytical grids produce exact expected values and wrong/empty/muted/stale resources fail with typed errors. |
| **RSM-017** | P2 | Implement selected L1/L3 filtering, measurement-gap scheduling, cell/beam report configuration, event A1/A2/A3/A4/A5/A6 entry/leave conditions, hysteresis and time-to-trigger from installed RRC state. | Synthetic trajectories trigger only the expected events at exact times and never measure outside allowed gaps/resources. |
| **RSM-018** | P1 | Implement modulation/reference-point-specific EVM over intended data/reference REs, normalization, equalization and residual-error components. Keep RF mask claims separate from receiver implementation metrics. | Ideal and injected-impairment waveforms hit analytical EVM values and deterministic threshold-boundary tests. |

## Existing production source to refactor, preserve and integrate

Inspect and migrate at least these live entry points:

- `+sixgr/+phy/+refsig/csirs.m` — remove best-effort row/port/default/index-base behavior; delegate to exact CSI-RS engine.
- `+sixgr/+phy/+refsig/trs.m` — remove generic comb-based TRS construction; delegate to selected NZP-CSI-RS tracking resource set.
- `+sixgr/+phy/+refsig/ptrsPDSCH.m` — delegate exact PT-RS configuration and ownership to canonical PT-RS engine.
- `+sixgr/+phy/+refsig/causalMeasurementState.m` — replace infinite-age and weak-identity defaults with typed measurement state and profile validity.
- `+sixgr/+phy/+srs/*.m` — consolidate strict SRS resource/resource-set, triggering, mapping, detection and channel-estimation state.
- `+sixgr/+phy/+trs/*.m` — retain useful measured estimators but make the correction loop causal and applied.
- `+sixgr/+phy/+dl/CSI_Feedback.m` — retain measured channel/SINR calculations; replace payload and report ownership.
- `+sixgr/+phy/+dl/packCSIFeedbackPayload.m` — remove from strict path; keep only under an explicit research namespace if still needed.
- `+sixgr/+link/cqiRequiredSINRTable.m` — replace laboratory defaults with versioned calibration lookup.
- `+sixgr/+link/mcsRequiredSINRTable.m` — derive only from a matching calibrated dataset, not interpolation over lab defaults.
- `+sixgr/+link/resolveWidebandCQI.m` — remove configured-SNR, lab-LUT and beta fallback paths.
- `+sixgr/+link/applyOLLADeltaDbToMCSIndex.m` — remove invalid-base coercion and bind to profile calibration/state.
- `+sixgr/+scheduler/SchedulerBase.m or actual scheduler base` — consume decoded report events and per-UE OLLA only.
- `+sixgr/+phy/+rx/correctCPEFromPTRS.m` — fail typed invalid configurations and prove correction application rather than swallowing exceptions.
- `+sixgr/+link/runTRSTracking.m` — remove configured Doppler/SNR as receiver evidence and apply the measured state downstream.

Preserve useful Toolbox-backed kernels only when their inputs and outputs are correct. Do not duplicate `nrCSIRS*`, `nrSRS*`, `nrPDSCHDMRS*`, `nrPUSCHDMRS*`, `nrPDSCHPTRS*` or `nrPUSCHPTRS*` wrappers merely to rename them. Fix ownership, validation, state and coverage around them, and add independent index/sequence floors.

## Canonical MATLAB architecture

Create or consolidate the following production package:

```text
+sixgr/+phy/+rsla/
    RSLASpecificationProfile.m
    RSLACapabilityProfile.m
    RSLAPlanningResult.m
    ResourceElementCoordinate.m
    ResourceOwnershipEntry.m
    ReferenceSignalOwnershipMap.m
    ReferenceSignalCollisionResolver.m
    DMRSConfiguration.m
    DMRSResourcePlan.m
    SharedDMRSEngine.m
    DMRSChannelEstimator.m
    CSIRSResource.m
    CSIRSResourceSet.m
    CSIIMResource.m
    CSIRSConfigurationState.m
    CSIRSResourceEngine.m
    SRSResource.m
    SRSResourceSet.m
    SRSConfigurationState.m
    SRSResourceEngine.m
    SRSReceiver.m
    ULChannelSoundingState.m
    TRSConfigurationState.m
    TRSResourceEngine.m
    TrackingMeasurementState.m
    TimingFrequencyTracker.m
    PTRSConfigurationState.m
    PTRSResourceEngine.m
    CommonPhaseErrorTracker.m
    MeasurementDefinition.m
    MeasurementRegistryR18.m
    MeasurementRequest.m
    MeasurementResult.m
    MeasurementStateStore.m
    MeasurementValidityChecker.m
    CSIReportConfigurationState.m
    CSIReport.m
    CSIPart1.m
    CSIPart2.m
    CSIReportBuilder.m
    CSIReportSerializer.m
    CSIReportDecoder.m
    CalibrationProfileKey.m
    CQIMCSCalibrationDataset.m
    CalibrationDatasetRegistry.m
    EESMMapper.m
    MIESMMapper.m
    LinkAdaptationState.m
    DecodedCSIReportEvent.m
    LinkAdaptationDecisionEngine.m
    BootstrapAcquisitionState.m
    OLLAState.m
    OLLAController.m
    L1MeasurementFilter.m
    L3MeasurementFilter.m
    MeasurementGapState.m
    RRMEventState.m
    RRMEventEngine.m
    EVMMeasurementEngine.m
    RSLAArtifactExporter.m
    runRSLAPhaseValidation.m
    runRSLAImpactAnalysis.m
    +oracle/DMRSSpec.m
    +oracle/CSIRSSpec.m
    +oracle/SRSSpec.m
    +oracle/MeasurementSpec.m
    +oracle/CSIReportSpec.m
    +oracle/EESMSpec.m
    +oracle/OLLASpec.m
    +oracle/RRMEventSpec.m
    +oracle/EVMSpec.m
```

All objects are immutable after construction except explicitly event-sourced state machines. Every state object carries `UEID`, serving/scheduled cell, component carrier, BWP, resource ID, beam/port association, producer absolute time, available absolute time, configuration epoch, source digest and validity result.

## 1. Capability planning and strict validation

Load `rsla_capability_profile_matrix.csv`. Implement `RSLACapabilityProfile.resolve(request)` before any grid/waveform allocation. The result must be one of `EXECUTE` or `REJECT`; no implicit downgrade is allowed. A supported row must be exercised by the declared coverage matrix. An unsupported row must return `RSLA:UnsupportedCapabilityTuple` and prove that no waveform, measurement, scheduler, HARQ or CSI state changed.

## 2. One exact resource-ownership map

Represent every RE using zero-based `(absoluteSlot, symbol, PRB, subcarrier, logicalPort, physicalPort, resourceType, resourceID, UEID, orthogonalityID)`. Build the complete map before modulation/coding. The owner map must include data/control allocations so that DM-RS, PT-RS, CSI-RS, CSI-IM, SRS and TRS collisions are resolved before waveform generation.

Two resources sharing time/frequency are allowed only when the exact sequence/OCC/CDM/port procedure proves orthogonality. A rectangular overlap alone is neither sufficient to declare a collision nor sufficient to prove separation. Export every ownership decision to `rsla_resource_ownership.csv`.

## 3. Shared DL/UL DM-RS engine

Implement table-driven mapping for every enabled tuple in `rsla_dmrs_test_vectors.csv`. The engine owns mapping type, type-A position, configuration type, single/double-symbol length, additional positions, logical ports, CDM groups, frequency/time OCC, scrambling identity, `n_SCID`, hopping where applicable and exact RE indices.

Never overwrite a requested logical port set from `NumLayers`. Validate the layer/port mapping at the scheduling boundary. Use the same selected DM-RS state for data mapping, channel estimation and evidence. The selected resource/sequence hash must equal the applied hash.

For every supported tuple run: pure index/sequence comparison, no-channel round trip, AWGN, TDL-C and selected CDL-C. Include wrong-port, wrong-scrambling-ID, collision and missing-resource negatives.

## 4. CSI-RS and CSI-IM

Implement exact RRC-owned resources/resource sets. Resolve row, port count, density, CDM type, symbol/subcarrier locations, RB range, periodicity/offset, resource type, muting, QCL state and report association from installed configuration. Do not infer a row only from `nPorts`, round unsupported ports, modulo the scrambling ID or continue after a failed CDM assignment.

Selected profiles must include bounded NZP-CSI-RS, ZP-CSI-RS and CSI-IM-associated measurement resources. Aperiodic resources require the decoded trigger and correct configuration epoch. Muted or unavailable resources cannot produce a valid measurement.

## 5. SRS

Build canonical SRS resources and resource sets for the selected one/two/four-port periodic, semi-persistent and aperiodic profiles. Implement exact transmission comb, comb offset, cyclic shift, sequence ID, start position, symbol count, repetition, `C_SRS`, `B_SRS`, `b_hop`, frequency position, resource-set usage, trigger state and BWP ownership.

No `max`, `min`, rounding or default can coerce an invalid requested value. Full-BWP or partial-BWP sounding must be an explicit resource decision, not a crop/search heuristic. The receiver produces a timestamped `ULChannelSoundingState`; configured TPMI is never a substitute for it.

## 6. TRS and measured timing/frequency tracking

Represent TRS through the selected NZP-CSI-RS tracking resource-set profile. Preserve its exact resource identity, periodicity, QCL state and observed sample times. The receiver may know the installed resource configuration and coarse synchronization allowed by the profile, but may not receive true CFO, true Doppler, true timing or transmitted correction values.

Implement a stateful loop: measured estimate → confidence/age validation → loop update → correction applied to later samples → residual measured from later reference/data symbols. Export both estimate and applied-correction identity. A reported estimate without downstream application is a failure.

## 7. PT-RS

Implement exact DL and UL PT-RS enablement, time density, frequency density, RE offset, associated DM-RS port, sequence and per-hop/resource mapping. For transform-precoded PUSCH apply the applicable selected profile rather than a CP-OFDM map.

Estimate common phase error only from received PT-RS and the known reference sequence. Apply correction before data demodulation. Export CPE, residual CPE, EVM and BLER before/after. Do not swallow a PT-RS error and return an uncorrected grid as if the profile succeeded.

## 8. TS 38.215 measurement registry

Implement the selected measurement definitions in a registry. Each entry states the exact reference signal, RE set, measurement bandwidth, antenna/beam association, averaging/combining rule, units, validity, version and allowed consumer.

The bounded strict registry contains SS-RSRP, CSI-RSRP, SS-RSRQ, CSI-RSRQ, SS-SINR, CSI-SINR, RSSI and SRS-RSRP. Post-equalization SINR and EVM are separate receiver metrics and must not be mislabeled as a TS 38.215 quantity unless the selected definition supports it.

Use the analytical vectors in `expected_rsla_measurement_analytical_vectors.csv`. Core formulas for the bounded analytical floor are:

```text
RSRP = mean power of the declared reference-signal REs at the declared reference point
RSRQ = N_RB × RSRP / RSSI
SINR = desired reference-signal power / (interference power + noise power)
EVM_rms = sqrt(Σ|x_hat - x_ref|² / Σ|x_ref|²)
```

A measurement from an empty, muted, wrong-beam, wrong-cell, wrong-BWP, colliding, future or stale resource is invalid. Do not backfill it from geometry, configured SNR, true channel coefficients or another resource.

## 9. Measurement state, identity and age

Replace weak table selection and `MaxAgeSlots=Inf` defaults with `MeasurementStateStore` and `MeasurementValidityChecker`. A measurement key contains UE, serving cell, scheduled cell, CC, BWP, resource ID/set, beam/port association, measurement quantity, producer time, available time, configuration epoch and source hash.

The consumer states its maximum age and identity requirements. Missing maximum age is invalid in strict mode. Select the newest valid measurement only after filtering by the complete key; never select a row first and validate identity later.

## 10. CSI report configuration and Part 1/Part 2

Construct `CSIReport` only from an installed `CSI-ReportConfig`, valid measurement resource state, valid interference resource state and the selected codebook/quantity profile. Field presence, width, order and Part 1/Part 2 partition are report dependent. Do not clamp CRI/RI/PMI/CQI values, infer widths from candidate counts, pad missing fields or truncate a payload.

Export one row per information bit to `rsla_csi_bit_ownership.csv`. Encode the typed sequences through the canonical TS 38.212 UCI chain and transport them on the selected PUCCH/PUSCH procedure. The scheduler may update only from a CRC-valid, semantically valid decoded report with the correct configuration epoch.

## 11. Measured-only scheduler authority

The steady-state link-adaptation decision accepts only:

```text
decoded CSI report event with valid age/identity/calibration
or
valid measured SRS state for the enabled UL procedure
```

Configured CQI/MCS/SNR may be used only in the explicitly bounded bootstrap acquisition state. Once a valid decoded report is available, bootstrap ends. It cannot silently reappear because a later report is inconvenient or stale. In that case use the selected robust/no-grant policy and record the reason.

## 12. CQI/MCS calibration

38.214 tables determine modulation/order/rate semantics, not universal channel-independent SINR thresholds. Build calibration campaigns using `rsla_cqi_mcs_calibration_matrix.csv`. A calibration profile key includes at least direction, MCS/CQI table, MCS, rank, waveform, receiver, channel, SCS, bandwidth, DM-RS, PT-RS, target BLER and implementation version.

Each dataset must contain the training and held-out operating points, TB/error counts, confidence intervals, interpolation rule, threshold estimate, prediction error, generator command, implementation version and SHA-256. Missing or mismatched datasets fail with `RSLA:MissingCQICalibration`.

## 13. EESM and MIESM

Implement EESM in linear SINR units:

```text
gamma_eff = -beta * ln( mean_n( exp(-gamma_n / beta) ) )
```

`beta` is not a global constant. Resolve it by the complete calibration profile key. For MIESM, use modulation/coding-specific calibrated mutual-information mappings and inverse mappings. The `MIESM_ANALYTICAL_SURROGATE` rows are only unit-test floors for transform/inversion mechanics and must not be used as strict calibration data.

Cross-validate on held-out frequency-selective channel drops. Export predicted effective SINR, reference link-curve outcome, BLER-prediction error and dataset identity. Missing calibration fails; never use 1.5 dB or any hard-coded fallback.

## 14. OLLA

Define `MarginDb` as a margin subtracted from measured SINR before MCS selection. For this convention:

```text
ACK  -> MarginDb := clip(MarginDb - muAck, low, high)
NACK -> MarginDb := clip(MarginDb + muNack, low, high)
```

For target BLER `p`, zero expected drift requires:

```text
muNack = muAck * (1 - p) / p
```

If an existing sign convention is retained, prove the equivalent drift equation and update all artifacts consistently. State is keyed by UE, direction, serving/scheduled cell, BWP, MCS table and configuration epoch. Define DTX policy, reset, inactivity age, saturation and reconfiguration behavior. Run multi-seed stationary and mobility campaigns and prove target-BLER convergence and no cross-UE leakage.

## 15. Filtering, gaps and RRM events

Implement selected L1 processing and the RRC-configured L3 filter. For the bounded independent floor:

```text
a = 2^(-k/4)
F_n = (1-a) F_(n-1) + a M_n
```

Implement configured measurement-gap opportunity, resource availability and report timing. A measurement may not be synthesized outside the gap.

Implement selected event A1/A2/A3/A4/A5/A6 entry and leave conditions, offsets, hysteresis and time-to-trigger using installed RRC state. Store the complete condition trace so a transition can be reproduced. Geometry can drive the waveform/channel but cannot directly set an event true.

## 16. EVM

Measure RMS EVM only over the intended data/reference RE set and declared equalization/reference point. Export desired-signal normalization, excluded REs, residual common phase, residual CFO/timing, channel-estimation error and noise/interference components. Use `expected_rsla_evm_vectors.csv` for analytical unit tests.

A baseband LLS EVM result is not automatically an RF-device conformance result. Device-mask pass/fail requires a separately enabled RF profile with exact specification/version/test conditions.

## Execution order

1. **T01 — Capability profile and planning rejection**. Dependency: `none`. Deliverable: MIMOSpecificationProfile-style explicit support matrix for RSLA.
1. **T02 — Canonical resource ownership engine**. Dependency: `T01`. Deliverable: one zero-based RE ledger for DM-RS, CSI-RS, CSI-IM, SRS, TRS, PT-RS and data/control.
1. **T03 — Shared DM-RS engine**. Dependency: `T02`. Deliverable: DL/UL exact sequence, mapping, ports, OCC and receiver estimator.
1. **T04 — CSI-RS/CSI-IM engine**. Dependency: `T02`. Deliverable: RRC-owned resources/resource sets, triggering, muting and measurement association.
1. **T05 — SRS resource/resource-set engine**. Dependency: `T02`. Deliverable: periodic/SP/AP, multi-port, hopping, triggers and receiver state.
1. **T06 — TRS tracking resources**. Dependency: `T04`. Deliverable: selected NZP-CSI-RS tracking profile and QCL state.
1. **T07 — PT-RS joint tracker**. Dependency: `T03`. Deliverable: DL/UL exact mapping and CPE correction.
1. **T08 — Measurement registry**. Dependency: `T03;T04;T05`. Deliverable: selected TS 38.215 definitions and analytical tests.
1. **T09 — Measured-state store**. Dependency: `T08`. Deliverable: timestamped UE/cell/BWP/resource/beam measurement state and validity.
1. **T10 — CSI report configuration objects**. Dependency: `T04;T09`. Deliverable: RRC-owned report quantities and resource associations.
1. **T11 — CSI Part1/Part2 serializer**. Dependency: `T10`. Deliverable: exact report-dependent ownership and TS 38.212 UCI integration.
1. **T12 — SRS scheduler consumption**. Dependency: `T05;T09`. Deliverable: measured RI/SRI/TPMI and covariance authority.
1. **T13 — CQI/MCS calibration registry**. Dependency: `T09`. Deliverable: versioned link curves, confidence and held-out validation.
1. **T14 — EESM/MIESM calibration**. Dependency: `T13`. Deliverable: profile-keyed parameters and no fallback.
1. **T15 — Decoded-report link adaptation**. Dependency: `T11;T13;T14`. Deliverable: MCS only from valid decoded reports or measured SRS state.
1. **T16 — OLLA state machine**. Dependency: `T15`. Deliverable: per-UE isolation, target-balanced steps, reset/age/saturation.
1. **T17 — Bootstrap transition state**. Dependency: `T15`. Deliverable: bounded acquisition and measured steady-state separation.
1. **T18 — L1/L3 filtering and gaps**. Dependency: `T08`. Deliverable: selected filter/gap procedures.
1. **T19 — RRM event engine**. Dependency: `T18`. Deliverable: selected A1-A6 entry/leave, hysteresis and TTT.
1. **T20 — Tracking correction lineage**. Dependency: `T06;T07`. Deliverable: apply measured timing/CFO/CPE to later samples and export residuals.
1. **T21 — EVM engine**. Dependency: `T03;T07`. Deliverable: reference-point and RE-specific RMS EVM.
1. **T22 — Base validation/artifacts**. Dependency: `T01-T21`. Deliverable: all vectors, waveform campaigns, 32 CSVs and 22 figures.
1. **T23 — Impact runner**. Dependency: `T22`. Deliverable: 768 controlled experiments and 96 rules.
1. **T24 — Full regression**. Dependency: `T23`. Deliverable: all repository MATLAB tests and canonical scenarios.

For each task: add a failing test, implement production code, migrate callers, run task tests, run all previously completed tests, generate the affected CSV/PNG, and record exact commands/results. Do not postpone integration until the end.

## Mandatory independent validation

At minimum, use these independent forms:

- pure-math zero-based collision/set arithmetic.
- analytical RSRP/RSRQ/RSSI/SINR/EVM vectors.
- pure EESM linear-domain formula.
- analytical OLLA drift and state traces.
- analytical L3 filtering traces.
- bounded RRM-event condition traces.
- frozen external or pure-spec DM-RS, CSI-RS, SRS, TRS and PT-RS index/sequence vectors for every enabled tuple.
- frozen CSI report bit-layout vectors for every enabled report configuration.
- held-out calibration drops that were not used to fit CQI/MCS or effective-SINR parameters.

A wrapper around the same `nr*` function on both DUT and reference sides is self-consistency only.

## Mandatory MATLAB tests

1. `testRSLACapabilityPlanning`
2. `testRSLAUnsupportedTupleRejection`
3. `testRSLAResourceOwnership`
4. `testRSLACollisionResolution`
5. `testSharedDMRSDL`
6. `testSharedDMRSUL`
7. `testDMRSSequences`
8. `testDMRSPortsOCC`
9. `testDMRSFrequencySelectiveRoundTrip`
10. `testCSIRSResourceRows`
11. `testCSIRSNZPZP`
12. `testCSIRSCSIIM`
13. `testCSIRSTriggering`
14. `testCSIRSMuting`
15. `testCSIRSMeasurementAssociation`
16. `testSRSPeriodic`
17. `testSRSSemiPersistent`
18. `testSRSAperiodic`
19. `testSRSMultiPort`
20. `testSRSCombCyclicShift`
21. `testSRSFrequencyHopping`
22. `testSRSChannelEstimation`
23. `testSRSSchedulerAuthority`
24. `testTRSResourceMapping`
25. `testTRSNoOracleDetection`
26. `testTRSCFOTracking`
27. `testTRSTimingTracking`
28. `testTRSCorrectionApplication`
29. `testPTRSDL`
30. `testPTRSUL`
31. `testPTRSIndexVectors`
32. `testPTRSPhaseCorrection`
33. `testPTRSBenefitBoundaries`
34. `testMeasurementRegistry`
35. `testRSRPAnalytical`
36. `testRSRQAnalytical`
37. `testSINRAnalytical`
38. `testRSSIAnalytical`
39. `testSRSRSRPAnalytical`
40. `testMeasurementInvalidResources`
41. `testCSIReportConfiguration`
42. `testCSIPart1Serialization`
43. `testCSIPart2Serialization`
44. `testCSIReportPUCCH`
45. `testCSIReportPUSCH`
46. `testCSIWrongLength`
47. `testCSIDecodedSchedulerAuthority`
48. `testMeasuredOnlyGuard`
49. `testMeasurementAgeIdentity`
50. `testBootstrapTransition`
51. `testCQIMCSCalibrationSchema`
52. `testCQIMCSCalibrationCampaign`
53. `testCQIMCSHoldoutValidation`
54. `testEESMFormula`
55. `testMIESMMapping`
56. `testEffectiveSINRCalibrationMissing`
57. `testEffectiveSINRHoldoutValidation`
58. `testOLLAStepBalance`
59. `testOLLAConvergence`
60. `testOLLASaturationReset`
61. `testOLLAMultiUEIsolation`
62. `testL3Filtering`
63. `testMeasurementGaps`
64. `testRRMEventA1A2`
65. `testRRMEventA3A4`
66. `testRRMEventA5A6`
67. `testEVMAnalytical`
68. `testEVMPTRSDMRSContext`
69. `testRSLAArtifactGeneration`
70. `testRSLAImpactAnalysis`

Every mandatory test must execute on the pinned MATLAB/5G Toolbox release. `Skipped`, `AssumptionFailed`, unavailable Toolbox or missing MATLAB counts as BLOCKED, not PASS.

## Production CSVs

- `rsla_capability_resolution.csv` — at least 180 rows; required columns: `CapabilityID, ProfileID, Family, ExpectedSupported, ActualSupported, PlanningDisposition, Status`.
- `rsla_resource_ownership.csv` — at least 500 rows; required columns: `RunID, Slot, Symbol, PRB, Subcarrier, ResourceType, ResourceID, OwnerUE, Port, OrthogonalityID, CollisionStatus, Status`.
- `rsla_collision_resolution.csv` — at least 120 rows; required columns: `CaseID, ResourceA, ResourceB, OverlapCount, OrthogonalityProven, ExpectedDisposition, ActualDisposition, Status`.
- `rsla_dmrs_matrix.csv` — at least 192 rows; required columns: `CaseID, Direction, MappingType, ConfigurationType, Length, AdditionalPosition, LogicalPorts, REIndexSHA256, SequenceSHA256, MismatchCount, Status`.
- `rsla_csirs_matrix.csv` — at least 100 rows; required columns: `CaseID, Row, Ports, Density, CDMType, ResourceType, TriggerType, REIndexSHA256, SequenceSHA256, MismatchCount, Status`.
- `rsla_srs_matrix.csv` — at least 162 rows; required columns: `CaseID, Ports, ResourceType, Usage, Comb, CyclicShift, HoppingMode, REIndexSHA256, SequenceSHA256, MismatchCount, Status`.
- `rsla_trs_tracking.csv` — at least 100 rows; required columns: `CaseID, UpdateIndex, MeasuredCFOHz, EstimatedCFOHz, ResidualCFOHz, MeasuredTimingSamples, EstimatedTimingSamples, ResidualTimingSamples, CorrectionApplied, Status`.
- `rsla_ptrs_tracking.csv` — at least 96 rows; required columns: `CaseID, Direction, TimeDensity, FrequencyDensity, CPEBeforeRad, CPEAfterRad, EVMBeforePercent, EVMAfterPercent, BLER, Status`.
- `rsla_measurement_registry.csv` — at least 8 rows; required columns: `MeasurementID, Quantity, ReferenceSignal, DefinitionVersion, Units, AveragingRule, BeamAssociation, ValidityRule, Status`.
- `rsla_measurement_results.csv` — at least 120 rows; required columns: `CaseID, Quantity, MeasuredValue, ExpectedValue, AbsoluteError, Tolerance, ResourceID, BeamID, AgeSlots, Provenance, Status`.
- `rsla_measurement_filter_trace.csv` — at least 100 rows; required columns: `CaseID, Quantity, SampleIndex, RawValueDb, FilteredValueDb, ExpectedValueDb, FilterK, Status`.
- `rsla_measurement_gap_trace.csv` — at least 100 rows; required columns: `CaseID, AbsoluteSlot, GapActive, ResourceAvailable, MeasurementAttempted, ExpectedAllowed, Status`.
- `rsla_rrm_event_trace.csv` — at least 100 rows; required columns: `CaseID, EventID, SampleIndex, Condition, TTTState, Entered, Left, ExpectedState, Status`.
- `rsla_srs_scheduler_consumption.csv` — at least 100 rows; required columns: `CaseID, UEID, MeasurementID, AgeSlots, Valid, SelectedRI, SelectedSRI, SelectedTPMI, SelectedPrecoderSHA256, AppliedPrecoderSHA256, Status`.
- `rsla_csi_report_resolution.csv` — at least 48 rows; required columns: `CaseID, ReportProfileID, ReportQuantity, Transport, TriggerType, Part1Bits, Part2Bits, ConfigurationEpoch, Status`.
- `rsla_csi_bit_ownership.csv` — at least 200 rows; required columns: `CaseID, Part, BitIndex, FieldName, DecodedBit, ExpectedBit, ConfigurationEpoch, Status`.
- `rsla_csi_uci_roundtrip.csv` — at least 48 rows; required columns: `CaseID, Transport, InformationBits, EncodedBits, DecodedBits, CRCStatus, SemanticStatus, Status`.
- `rsla_measured_state_validity.csv` — at least 100 rows; required columns: `CaseID, MeasurementID, UEID, CellID, BWPID, ResourceID, AgeSlots, MaxAgeSlots, IdentityValid, ExpectedValid, ActualValid, Status`.
- `rsla_link_adaptation_decisions.csv` — at least 100 rows; required columns: `CaseID, UEID, Direction, DecisionSlot, DecisionSource, DecodedReportID, CalibrationDatasetID, CQI, MCS, OLLAOffsetDb, BootstrapUsed, ReportAgeSlots, Status`.
- `rsla_bootstrap_transition.csv` — at least 100 rows; required columns: `CaseID, DecisionSlot, AcquisitionLimitSlots, FirstValidReportSlot, DecisionSource, BootstrapUsed, TransitionedToMeasured, Status`.
- `rsla_cqi_mcs_calibration.csv` — at least 100 rows; required columns: `DatasetID, ProfileKey, Direction, MCSTable, MCSIndex, Rank, Channel, TargetBLER, ThresholdDb, CILowDb, CIHighDb, TrainingSHA256, HoldoutError, DatasetSHA256, Status`.
- `rsla_effective_sinr_calibration.csv` — at least 50 rows; required columns: `DatasetID, ProfileKey, Method, MCSIndex, Rank, Channel, ParameterValue, TrainingRMSE, HoldoutRMSE, DatasetSHA256, Status`.
- `rsla_effective_sinr_trials.csv` — at least 100 rows; required columns: `CaseID, Method, SINRPerRESHA256, EffectiveSINRDb, ExpectedSINRDb, AbsoluteErrorDb, CalibrationDatasetID, Status`.
- `rsla_olla_state.csv` — at least 200 rows; required columns: `UEID, Direction, MCSTable, EventIndex, Outcome, MarginBeforeDb, MarginAfterDb, TargetBLER, MuAckDb, MuNackDb, ResetReason, Status`.
- `rsla_olla_convergence.csv` — at least 50 rows; required columns: `CampaignID, UEID, Seed, TargetBLER, AchievedBLER, CILow, CIHigh, MeanMarginDb, SaturationFraction, Converged, Status`.
- `rsla_evm_measurements.csv` — at least 100 rows; required columns: `CaseID, Direction, Channel, Modulation, ReferencePoint, EVMRMSPercent, ExpectedPercent, AbsoluteErrorPercent, PTRSEnabled, Status`.
- `rsla_independent_vector_results.csv` — at least 500 rows; required columns: `Family, CaseID, OracleType, OracleVersion, OracleSHA256, ComparedFields, MismatchCount, Status`.
- `rsla_negative_tests.csv` — at least 192 rows; required columns: `CaseID, Condition, ExpectedError, ActualError, WaveformGenerated, SchedulerStateChanged, MeasurementStateChanged, Status`.
- `rsla_receiver_metrics.csv` — at least 100 rows; required columns: `RunID, UEID, Direction, SNRDb, MeasuredSINRDb, EVMPercent, BLER, ThroughputMbps, MeasurementAgeSlots, Status`.
- `rsla_test_summary.csv` — at least 10 rows; required columns: `Suite, TestsRun, Passed, Failed, Skipped, Blocked, IncompletePoints, Status`.
- `rsla_image_semantic_audit.csv` — at least 22 rows; required columns: `ImageFile, SourceCSV, SourceCSVSHA256, PNGSHA256, Width, Height, Title, XLabel, YLabel, AxesCount, SeriesCount, FinitePointCount, Status`.
- `rsla_run_manifest.csv` — at least 1 rows; required columns: `RunID, ProfileID, MATLABVersion, ToolboxVersion, GitCommit, VectorManifestSHA256, ConfigurationSHA256, SeedList, StartTime, EndTime, Status`.

## Production figures

- `rsla_resource_ownership_map.png` from `rsla_resource_ownership.csv` — title `Reference-signal resource ownership`, x-axis `slot/symbol/PRB`, y-axis `resource type`.
- `rsla_dmrs_port_symbol_map.png` from `rsla_dmrs_matrix.csv` — title `DM-RS ports and symbols`, x-axis `configuration case`, y-axis `logical port / symbol`.
- `rsla_csirs_resource_map.png` from `rsla_csirs_matrix.csv` — title `CSI-RS and CSI-IM resource map`, x-axis `resource case`, y-axis `RE ownership`.
- `rsla_srs_resource_hopping_map.png` from `rsla_srs_matrix.csv` — title `SRS resource, comb and hopping map`, x-axis `slot / frequency`, y-axis `SRS resource`.
- `rsla_trs_tracking_convergence.png` from `rsla_trs_tracking.csv` — title `TRS timing and frequency tracking`, x-axis `update index`, y-axis `residual error`.
- `rsla_ptrs_cpe_evm.png` from `rsla_ptrs_tracking.csv` — title `PT-RS common phase error and EVM`, x-axis `phase-noise case`, y-axis `CPE / EVM`.
- `rsla_measurement_accuracy.png` from `rsla_measurement_results.csv` — title `TS 38.215 measurement accuracy`, x-axis `expected value`, y-axis `measured value`.
- `rsla_measurement_filter_trace.png` from `rsla_measurement_filter_trace.csv` — title `Measurement filtering trace`, x-axis `sample index`, y-axis `measurement (dB)`.
- `rsla_measurement_gap_timeline.png` from `rsla_measurement_gap_trace.csv` — title `Measurement-gap timeline`, x-axis `absolute slot`, y-axis `gap / measurement state`.
- `rsla_rrm_event_timeline.png` from `rsla_rrm_event_trace.csv` — title `RRM event entry and leave timeline`, x-axis `sample index`, y-axis `event state`.
- `rsla_srs_scheduler_authority.png` from `rsla_srs_scheduler_consumption.csv` — title `Measured SRS scheduler authority`, x-axis `measurement age`, y-axis `selection validity`.
- `rsla_csi_part1_part2_layout.png` from `rsla_csi_bit_ownership.csv` — title `CSI Part 1 and Part 2 bit ownership`, x-axis `bit index`, y-axis `field owner`.
- `rsla_csi_roundtrip.png` from `rsla_csi_uci_roundtrip.csv` — title `CSI UCI encode/decode round trip`, x-axis `case`, y-axis `bit / CRC result`.
- `rsla_link_adaptation_timeline.png` from `rsla_link_adaptation_decisions.csv` — title `Decoded-report link-adaptation timeline`, x-axis `decision slot`, y-axis `CQI / MCS`.
- `rsla_bootstrap_transition.png` from `rsla_bootstrap_transition.csv` — title `Bootstrap to measured transition`, x-axis `slot`, y-axis `decision source`.
- `rsla_cqi_mcs_calibration_curves.png` from `rsla_cqi_mcs_calibration.csv` — title `CQI/MCS calibration curves`, x-axis `SNR (dB)`, y-axis `BLER`.
- `rsla_effective_sinr_prediction.png` from `rsla_effective_sinr_trials.csv` — title `Effective-SINR prediction accuracy`, x-axis `predicted SINR (dB)`, y-axis `reference SINR (dB)`.
- `rsla_olla_convergence.png` from `rsla_olla_convergence.csv` — title `OLLA convergence to target BLER`, x-axis `transmission index`, y-axis `BLER / margin`.
- `rsla_olla_multiue_isolation.png` from `rsla_olla_state.csv` — title `Per-UE OLLA isolation`, x-axis `event index`, y-axis `OLLA margin (dB)`.
- `rsla_evm_by_modulation.png` from `rsla_evm_measurements.csv` — title `EVM by modulation and impairment`, x-axis `case`, y-axis `EVM (%)`.
- `rsla_bler_vs_measured_sinr.png` from `rsla_receiver_metrics.csv` — title `BLER versus measured SINR`, x-axis `measured SINR (dB)`, y-axis `BLER`.
- `rsla_test_status.png` from `rsla_test_summary.csv` — title `RSLA mandatory test status`, x-axis `test suite`, y-axis `count`.

Each figure must be at least 900×600, nonblank, regenerated from the named CSV, and audited by `rsla_image_semantic_audit.csv` with source CSV hash, PNG hash, actual title/labels, axes, series and finite-point count.

## Impact analysis

After the base phase passes, execute all rows in `rsla_impact_experiment_matrix.csv`. There are 64 families, 768 experiments and 384 matched baseline/treatment pairs. For a pair, preserve seed, payload, channel, noise, traffic, initial state and all non-factor configuration hashes. Only the declared factor may change.

- **F01 — DM-RS mapping type**: `A` versus `B`; metrics: DMRS index accuracy;BLER; wave A; dependency: shared DM-RS engine.
- **F02 — DM-RS configuration type**: `1` versus `2`; metrics: RE overhead;channel NMSE;BLER; wave A; dependency: shared DM-RS engine.
- **F03 — DM-RS additional positions**: `0` versus `2`; metrics: overhead;NMSE;BLER; wave A; dependency: shared DM-RS engine.
- **F04 — DM-RS single/double symbol**: `1` versus `2`; metrics: overhead;tracking;BLER; wave A; dependency: shared DM-RS engine.
- **F05 — DM-RS logical ports and OCC**: `single` versus `multiPort`; metrics: cross-port leakage;rank BLER; wave A; dependency: shared DM-RS engine.
- **F06 — DM-RS density versus Doppler**: `30` versus `500`; metrics: NMSE;BLER;goodput; wave A; dependency: channel + DM-RS engine.
- **F07 — CSI-RS row and port count**: `2` versus `8`; metrics: measurement NMSE;runtime; wave A; dependency: CSI-RS engine.
- **F08 — CSI-RS density**: `dot5` versus `one`; metrics: overhead;RSRP variance; wave A; dependency: CSI-RS engine.
- **F09 — NZP/ZP/CSI-IM association**: `none` versus `CSI-IM`; metrics: SINR bias;CQI error; wave A; dependency: CSI-RS/CSI-IM engine.
- **F10 — CSI-RS periodicity**: `80` versus `10`; metrics: CSI age;goodput;overhead; wave A; dependency: CSI-RS engine.
- **F11 — CSI-RS muting**: `off` versus `on`; metrics: interference estimate bias; wave A; dependency: CSI-RS engine.
- **F12 — Reference-signal collision resolution**: `unchecked` versus `exactOwnership`; metrics: collision count;decode success; wave A; dependency: resource ownership engine.
- **F13 — SRS port count**: `1` versus `4`; metrics: UL channel NMSE;rank accuracy; wave A; dependency: SRS engine.
- **F14 — SRS transmission comb**: `2` versus `4`; metrics: overhead;estimation error; wave A; dependency: SRS engine.
- **F15 — SRS cyclic shift orthogonality**: `colliding` versus `orthogonal`; metrics: cross-user leakage; wave A; dependency: SRS engine.
- **F16 — SRS periodicity**: `80` versus `10`; metrics: state age;UL goodput;overhead; wave A; dependency: SRS engine.
- **F17 — SRS frequency hopping**: `off` versus `on`; metrics: frequency coverage;NMSE; wave A; dependency: SRS engine.
- **F18 — SRS resource type**: `periodic` versus `aperiodic`; metrics: latency;overhead;freshness; wave A; dependency: SRS trigger engine.
- **F19 — SRS sounded bandwidth**: `partialBWP` versus `fullBWP`; metrics: precoder loss;runtime; wave A; dependency: SRS engine.
- **F20 — TRS periodicity**: `80` versus `10`; metrics: residual CFO/timing;overhead; wave A; dependency: TRS engine.
- **F21 — TRS tracking loop gain**: `0.1` versus `0.5`; metrics: settling;noise;residual error; wave A; dependency: tracking loop.
- **F22 — TRS CFO correction**: `off` versus `measuredOn`; metrics: residual CFO;EVM;BLER; wave A; dependency: tracking loop.
- **F23 — TRS timing correction**: `off` versus `measuredOn`; metrics: residual timing;EVM;BLER; wave A; dependency: tracking loop.
- **F24 — PT-RS time density**: `4` versus `1`; metrics: overhead;CPE;BLER; wave A; dependency: PT-RS engine.
- **F25 — PT-RS frequency density**: `4` versus `2`; metrics: overhead;CPE;BLER; wave A; dependency: PT-RS engine.
- **F26 — PT-RS phase-noise severity**: `low` versus `high`; metrics: CPE;EVM;BLER; wave A; dependency: PT-RS engine.
- **F27 — DL versus UL PT-RS**: `DL` versus `UL`; metrics: tracking error;runtime; wave A; dependency: DL/UL PT-RS engine.
- **F28 — RSRP analytical accuracy**: `0.5` versus `2.0`; metrics: measurement error; wave A; dependency: measurement registry.
- **F29 — RSRQ analytical accuracy**: `low` versus `high`; metrics: measurement error; wave A; dependency: measurement registry.
- **F30 — SINR analytical accuracy**: `low` versus `high`; metrics: measurement error; wave A; dependency: measurement registry.
- **F31 — RSSI measurement bandwidth**: `24` versus `96`; metrics: RSSI scaling error; wave A; dependency: measurement registry.
- **F32 — Beam/antenna association**: `wrongBeam` versus `correctBeam`; metrics: measurement bias;report validity; wave A; dependency: measurement registry.
- **F33 — CSI Part 2 inclusion**: `omitted` versus `present`; metrics: payload;PMI accuracy;goodput; wave A; dependency: CSI report engine.
- **F34 — CSI transport**: `PUCCH` versus `PUSCH`; metrics: latency;overhead;decode success; wave A; dependency: UCI integration.
- **F35 — CSI report age**: `1` versus `16`; metrics: CQI error;BLER;goodput; wave A; dependency: CSI state.
- **F36 — Configured-SNR fallback rejection**: `configuredSNR` versus `measuredCSI`; metrics: grant validity;false adaptation; wave A; dependency: measured-only guard.
- **F37 — CQI/MCS calibration target**: `0.01` versus `0.1`; metrics: threshold;throughput;BLER; wave A; dependency: calibration engine.
- **F38 — EESM beta calibration**: `fallback1p5dB` versus `profileCalibrated`; metrics: prediction error; wave A; dependency: effective SINR engine.
- **F39 — EESM versus MIESM**: `EESM` versus `MIESM`; metrics: BLER prediction RMSE; wave A; dependency: effective SINR engine.
- **F40 — MCS table selection**: `qam64` versus `qam256`; metrics: goodput;BLER; wave A; dependency: decoded report + calibration.
- **F41 — OLLA target BLER**: `0.01` versus `0.1`; metrics: steady BLER;goodput; wave A; dependency: OLLA engine.
- **F42 — OLLA step-ratio correctness**: `incorrect` versus `targetBalanced`; metrics: drift;convergence; wave A; dependency: OLLA engine.
- **F43 — OLLA saturation bounds**: `unbounded` versus `bounded`; metrics: stability;recovery; wave A; dependency: OLLA engine.
- **F44 — Bootstrap-to-measured transition**: `persistent` versus `bounded`; metrics: post-acquisition provenance; wave A; dependency: link adaptation state.
- **F45 — L3 filter coefficient**: `0` versus `8`; metrics: noise;lag;event timing; wave B; dependency: measurement filtering.
- **F46 — Measurement-gap pattern**: `80` versus `20`; metrics: measurement availability;overhead; wave B; dependency: gap scheduler.
- **F47 — A3 hysteresis**: `0` versus `3`; metrics: ping-pong;trigger delay; wave B; dependency: RRC event engine.
- **F48 — Time-to-trigger**: `0` versus `320`; metrics: trigger reliability;latency; wave B; dependency: RRC event engine.
- **F49 — SRS scheduler age**: `fresh` versus `stale`; metrics: rank/TPMI error;UL BLER; wave B; dependency: SRS scheduler integration.
- **F50 — TDD reciprocity calibration**: `off` versus `measuredOn`; metrics: precoder loss;UL/DL mismatch; wave B; dependency: RF calibration state.
- **F51 — Interference covariance age**: `fresh` versus `stale`; metrics: IRC SINR;BLER; wave B; dependency: covariance-qualified receiver.
- **F52 — Mobility-aware smoothing**: `fixed` versus `calibrated`; metrics: stale error;target BLER; wave B; dependency: mobility measurement model.
- **F53 — CSI feedback delay**: `1` versus `8`; metrics: goodput;BLER; wave B; dependency: PUCCH/PUSCH timing.
- **F54 — CSI report periodicity**: `80` versus `10`; metrics: overhead;freshness;goodput; wave B; dependency: CSI report scheduler.
- **F55 — Multi-BWP resource association**: `stale` versus `active`; metrics: wrong-resource rejection; wave B; dependency: BWP state.
- **F56 — Cross-carrier CSI association**: `wrong` versus `correct`; metrics: grant validity;CQI error; wave B; dependency: multi-CC state.
- **F57 — Multi-cell measurement isolation**: `leaking` versus `isolated`; metrics: event/CSI leakage; wave B; dependency: multi-cell measurement state.
- **F58 — Per-UE OLLA isolation**: `shared` versus `perUE`; metrics: cross-UE leakage;BLER; wave B; dependency: multi-UE scheduler.
- **F59 — Waveform CFO estimator**: `oracle` versus `measured`; metrics: residual CFO;EVM; wave C; dependency: RF impairment model.
- **F60 — Waveform timing estimator**: `oracle` versus `measured`; metrics: residual timing;EVM; wave C; dependency: timing acquisition.
- **F61 — Waveform phase-noise process**: `scalarPenalty` versus `waveformProcess`; metrics: CPE;EVM;BLER; wave C; dependency: RF phase-noise model.
- **F62 — Closed-loop handover measurement events**: `offline` versus `live`; metrics: event accuracy;handover failures; wave C; dependency: mobility/RRC/handover.
- **F63 — RF-profile EVM thresholds**: `generic` versus `pinnedRFProfile`; metrics: boundary accuracy; wave C; dependency: RF profile.
- **F64 — End-to-end mobility link adaptation**: `heuristic` versus `measuredCalibrated`; metrics: goodput;BLER;latency; wave C; dependency: all preceding technical areas.

Statistical treatment: Wilson intervals for ordinary rates; one-sided exact Clopper-Pearson bounds for zero-event false alarms; McNemar tests for paired binary outcomes; paired bootstrap intervals for continuous metrics; Holm adjustment within related families; signed treatment-minus-baseline effect and a predefined practical margin. Insufficient trials/errors must be `INCOMPLETE` or `INCONCLUSIVE`, never PASS.

## Impact CSVs and figures

- `rsla_impact_run_manifest.csv` — at least 1 rows; required columns: `RunID, ExperimentCount, CompletedCount, IncompleteCount, SeedList, ConfidenceLevel, Status`.
- `rsla_impact_raw_trials.csv` — at least 768 rows; required columns: `ExperimentID, FamilyID, PairID, Arm, Seed, Trial, PrimaryMetric, MetricValue, Outcome, PayloadHash, ChannelHash, NoiseHash, Status`.
- `rsla_impact_operating_points.csv` — at least 128 rows; required columns: `FamilyID, Arm, FactorValue, Trials, Errors, Rate, CILow, CIHigh, Incomplete, Status`.
- `rsla_impact_pairwise_effects.csv` — at least 384 rows; required columns: `FamilyID, PairID, Metric, BaselineValue, TreatmentValue, Effect, CILow, CIHigh, PValue, AdjustedPValue, EffectSize, Status`.
- `rsla_impact_rule_evaluation.csv` — at least 96 rows; required columns: `RuleID, FamilyID, RuleType, Metric, Observed, Threshold, Result, EvidenceRows, Status`.
- `rsla_impact_reference_signals.csv` — at least 100 rows; required columns: `FamilyID, ResourceFamily, BaselineOverhead, TreatmentOverhead, BaselineNMSE, TreatmentNMSE, BaselineBLER, TreatmentBLER, Status`.
- `rsla_impact_measurements.csv` — at least 100 rows; required columns: `FamilyID, Quantity, BaselineError, TreatmentError, BaselineVariance, TreatmentVariance, BaselineAge, TreatmentAge, Status`.
- `rsla_impact_csi_reports.csv` — at least 80 rows; required columns: `FamilyID, ReportProfile, BaselineBits, TreatmentBits, BaselineLatency, TreatmentLatency, BaselineDecodeRate, TreatmentDecodeRate, Status`.
- `rsla_impact_calibration.csv` — at least 80 rows; required columns: `FamilyID, Method, BaselinePredictionRMSE, TreatmentPredictionRMSE, BaselineBLERError, TreatmentBLERError, Status`.
- `rsla_impact_olla.csv` — at least 80 rows; required columns: `FamilyID, UEID, TargetBLER, BaselineAchievedBLER, TreatmentAchievedBLER, BaselineConvergenceSlots, TreatmentConvergenceSlots, Leakage, Status`.
- `rsla_impact_tracking.csv` — at least 80 rows; required columns: `FamilyID, BaselineResidualCFO, TreatmentResidualCFO, BaselineResidualTiming, TreatmentResidualTiming, BaselineEVM, TreatmentEVM, Status`.
- `rsla_impact_rrm.csv` — at least 80 rows; required columns: `FamilyID, EventID, BaselineFalseTriggers, TreatmentFalseTriggers, BaselineDelay, TreatmentDelay, Status`.
- `rsla_impact_runtime.csv` — at least 128 rows; required columns: `FamilyID, Arm, RuntimeSeconds, PeakMemoryMB, SerialSHA256, ParallelSHA256, Reproducible, Status`.
- `rsla_impact_interactions.csv` — at least 50 rows; required columns: `ModelID, Response, Term, Coefficient, CILow, CIHigh, PValue, AdjustedPValue, Status`.
- `rsla_impact_summary.csv` — at least 64 rows; required columns: `FamilyID, FamilyName, Wave, CompletionStatus, HardRulesPassed, StatisticalConclusion, PrimaryEffect, PracticalImportance, Status`.
- `rsla_impact_image_semantic_audit.csv` — at least 30 rows; required columns: `ImageFile, SourceCSV, SourceCSVSHA256, PNGSHA256, Width, Height, Title, XLabel, YLabel, AxesCount, SeriesCount, FinitePointCount, Status`.

- `rsla_impact_dmrs_doppler.png` from `rsla_impact_reference_signals.csv` — title `DM-RS density versus Doppler`, x-axis `Doppler / profile`, y-axis `BLER / NMSE`.
- `rsla_impact_csirs_overhead.png` from `rsla_impact_reference_signals.csv` — title `CSI-RS overhead and accuracy`, x-axis `CSI-RS profile`, y-axis `overhead / error`.
- `rsla_impact_csirs_periodicity.png` from `rsla_impact_reference_signals.csv` — title `CSI-RS periodicity impact`, x-axis `periodicity`, y-axis `age / goodput`.
- `rsla_impact_srs_ports.png` from `rsla_impact_reference_signals.csv` — title `SRS port-count impact`, x-axis `ports`, y-axis `NMSE / rank accuracy`.
- `rsla_impact_srs_hopping.png` from `rsla_impact_reference_signals.csv` — title `SRS hopping impact`, x-axis `hopping profile`, y-axis `coverage / NMSE`.
- `rsla_impact_srs_periodicity.png` from `rsla_impact_reference_signals.csv` — title `SRS periodicity impact`, x-axis `periodicity`, y-axis `age / overhead`.
- `rsla_impact_trs_cfo.png` from `rsla_impact_tracking.csv` — title `TRS CFO tracking impact`, x-axis `CFO case`, y-axis `residual CFO / EVM`.
- `rsla_impact_trs_timing.png` from `rsla_impact_tracking.csv` — title `TRS timing tracking impact`, x-axis `timing case`, y-axis `residual timing / EVM`.
- `rsla_impact_ptrs_phase_noise.png` from `rsla_impact_tracking.csv` — title `PT-RS phase-noise impact`, x-axis `phase noise`, y-axis `CPE / EVM / BLER`.
- `rsla_impact_measurement_rsrp.png` from `rsla_impact_measurements.csv` — title `RSRP measurement impact`, x-axis `case`, y-axis `measurement error`.
- `rsla_impact_measurement_rsrq.png` from `rsla_impact_measurements.csv` — title `RSRQ measurement impact`, x-axis `case`, y-axis `measurement error`.
- `rsla_impact_measurement_sinr.png` from `rsla_impact_measurements.csv` — title `SINR measurement impact`, x-axis `case`, y-axis `measurement error`.
- `rsla_impact_filter_lag_noise.png` from `rsla_impact_measurements.csv` — title `Filter lag-noise trade-off`, x-axis `filter coefficient`, y-axis `lag / variance`.
- `rsla_impact_gap_availability.png` from `rsla_impact_measurements.csv` — title `Measurement-gap availability`, x-axis `gap profile`, y-axis `measurement availability`.
- `rsla_impact_rrm_hysteresis.png` from `rsla_impact_rrm.csv` — title `RRM hysteresis impact`, x-axis `hysteresis`, y-axis `false triggers / delay`.
- `rsla_impact_rrm_ttt.png` from `rsla_impact_rrm.csv` — title `Time-to-trigger impact`, x-axis `TTT`, y-axis `false triggers / delay`.
- `rsla_impact_csi_part2.png` from `rsla_impact_csi_reports.csv` — title `CSI Part-2 impact`, x-axis `report profile`, y-axis `bits / goodput`.
- `rsla_impact_csi_transport.png` from `rsla_impact_csi_reports.csv` — title `PUCCH versus PUSCH CSI`, x-axis `transport`, y-axis `latency / decode rate`.
- `rsla_impact_csi_age.png` from `rsla_impact_csi_reports.csv` — title `CSI age impact`, x-axis `report age`, y-axis `BLER / goodput`.
- `rsla_impact_cqi_calibration.png` from `rsla_impact_calibration.csv` — title `CQI/MCS calibration accuracy`, x-axis `MCS`, y-axis `BLER prediction error`.
- `rsla_impact_eesm_beta.png` from `rsla_impact_calibration.csv` — title `EESM beta calibration impact`, x-axis `beta source`, y-axis `prediction RMSE`.
- `rsla_impact_eesm_miesm.png` from `rsla_impact_calibration.csv` — title `EESM versus MIESM`, x-axis `method`, y-axis `prediction RMSE`.
- `rsla_impact_olla_target.png` from `rsla_impact_olla.csv` — title `OLLA target-BLER impact`, x-axis `target BLER`, y-axis `achieved BLER / goodput`.
- `rsla_impact_olla_steps.png` from `rsla_impact_olla.csv` — title `OLLA step-ratio impact`, x-axis `step profile`, y-axis `drift / convergence`.
- `rsla_impact_olla_multiue.png` from `rsla_impact_olla.csv` — title `OLLA multi-UE isolation`, x-axis `UE`, y-axis `margin / BLER`.
- `rsla_impact_bootstrap.png` from `rsla_impact_summary.csv` — title `Bootstrap policy impact`, x-axis `policy`, y-axis `measured decision fraction`.
- `rsla_impact_runtime_scaling.png` from `rsla_impact_runtime.csv` — title `RSLA runtime scaling`, x-axis `family`, y-axis `runtime / memory`.
- `rsla_impact_effect_forest.png` from `rsla_impact_pairwise_effects.csv` — title `Paired impact effect forest`, x-axis `effect`, y-axis `confidence interval`.
- `rsla_impact_interactions.png` from `rsla_impact_interactions.csv` — title `RSLA factor interactions`, x-axis `term`, y-axis `coefficient`.
- `rsla_impact_family_status.png` from `rsla_impact_summary.csv` — title `RSLA impact-family status`, x-axis `family`, y-axis `completion status`.

## Required commands

Run from the repository root:

```bash
python tests/vectors/rsla/verify_rsla_vector_pack.py tests/vectors/rsla
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*DMRS*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*CSIRS*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*SRS*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*TRS*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PTRS*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*CSI*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Measurement*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*OLLA*'); assertSuccess(r);"
matlab -batch "addpath(pwd); s=sixgr.phy.rsla.runRSLAPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','rsla'),'OutputDir',fullfile(pwd,'artifacts','rsla_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
python tests/vectors/rsla/verify_rsla_artifacts.py artifacts/rsla_phase
matlab -batch "addpath(pwd); s=sixgr.phy.rsla.runRSLAImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','rsla','rsla_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','rsla_impact'),'SeedList',[11 23 47 89 131 197],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
python tests/vectors/rsla/verify_rsla_impact_artifacts.py artifacts/rsla_impact
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

## Codex completion restrictions

You may not report `COMPLETE` while any of the following remains:

- configured SNR/CQI/MCS used as steady-state measured evidence.
- custom compact CSI payload in the strict path.
- missing or guessed CSI Part 1/Part 2 length.
- RS parameter clamping, modulo wrapping, crop, retry or silent default.
- one-port/full-carrier SRS mini-profile presented as broad SRS support.
- true CFO/timing/Doppler/CPE supplied to a strict receiver.
- tracking estimate reported but correction not applied.
- PT-RS failure swallowed and uncorrected data treated as success.
- `MaxAgeSlots=Inf` or unkeyed measurement selection.
- configured TPMI replacing measured SRS state.
- lab-default CQI thresholds.
- 1.5-dB or other fallback EESM beta.
- calibration dataset without exact profile/hash/confidence/holdout provenance.
- OLLA state shared across UEs/cells/directions or inconsistent with target drift.
- bootstrap used after valid measured acquisition.
- measurement outside configured resource/gap.
- RRM event set directly from geometry rather than filtered measurement state.
- EVM measured over the wrong RE set or reference point.
- same-Toolbox output called independent validation.
- mandatory MATLAB test skipped, blocked or unavailable.
- mandatory campaign point incomplete.
- any of the 48 required CSVs or 52 required PNGs absent.
- either artifact verifier returning nonzero.
- complete repository regression failing.

## Required final response from Codex

Report:

680. files changed and production call paths migrated.
681. architecture decisions and compatibility façades retained.
682. exact MATLAB and Toolbox versions.
683. exact commands executed.
684. test run/pass/fail/skip/block counts.
685. capability rows executed/rejected.
686. independent-vector mismatch count.
687. calibration dataset IDs, profile keys and hashes.
688. OLLA convergence results and per-UE isolation result.
689. 768 impact experiment completion and 96-rule result.
690. CSV row counts and SHA-256 values.
691. PNG dimensions and SHA-256 values.
692. artifact-verifier exit codes.
693. open technical dependencies and unsupported tuples.
694. one final status: COMPLETE, FAIL or BLOCKED.

`COMPLETE` is valid only when all 18 findings are closed for the enabled profiles, all 70 mandatory MATLAB tests execute and pass, all 180 capability rows resolve as expected, all 768 experiments execute, all 96 rules have valid evidence, all 48 CSVs and 52 PNGs pass both verifiers, and the full repository regression passes.
