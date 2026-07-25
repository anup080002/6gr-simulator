# CODEX IMPLEMENTATION PROMPT 06 — SSB, INITIAL ACCESS, SIB1, RANDOM ACCESS, AND RRC CONNECTION ESTABLISHMENT

## Operating role

You are the lead MATLAB/5G Toolbox PHY, MAC and RRC implementation engineer for this repository.
This task is not a review, planning exercise, truth-contract exercise, GUI task, security task, or documentation-only task.
You must edit the production MATLAB source, migrate every runtime caller, add executable tests, execute them, generate the contracted CSV/PNG artifacts, inspect those artifacts, and continue fixing the implementation until the bounded profile is technically complete.

## Mission

Implement one defensible bounded Release-18 FR1 initial-access profile end to end:

```text
PSS / SSS
    -> SS/PBCH block detection and beam selection
    -> PBCH DM-RS and PBCH/BCH decoding
    -> MIB semantic validation
    -> Type-0 PDCCH common search space
    -> blind DCI 1_0 for SI-RNTI
    -> PDSCH / DL-SCH carrying BCCH-DL-SCH SIB1
    -> independent Release-18 ASN.1 UPER decoding
    -> install serving-cell and RACH common configuration
    -> exact PRACH occasion and SSB-to-RO association
    -> Msg1 PRACH
    -> Msg2 RAR PDCCH/PDSCH/MAC RAR
    -> Msg3 PUSCH/UL-SCH carrying RRCSetupRequest
    -> Msg4 PDCCH/PDSCH carrying contention resolution and RRCSetup
    -> SRB1 activation
    -> UL-DCCH RRCSetupComplete
    -> synchronized UE and gNB transition to RRC_CONNECTED
```

The bounded profile is named:

```text
fr1_four_step_ra_rrc_connection_strict_r18
```

Two-step RA, CFRA, beam-failure-recovery access, SUL access, NTN access, RedCap and eRedCap access are not part of this bounded profile. They must be rejected explicitly and must never fall back to four-step RA.

## Pinned normative baseline

Pin exact repository-visible version identifiers for:

```text
3GPP TS 38.211 V18.8.0 — physical channels/signals, SS/PBCH block and PRACH
3GPP TS 38.212 V18.8.0 — BCH, DCI, DL-SCH, UL-SCH and coding
3GPP TS 38.213 V18.8.0 — Type-0 CSS, monitoring occasions and random-access procedures
3GPP TS 38.214 V18.8.0 — PDSCH/PUSCH scheduling and transport procedures
3GPP TS 38.321 V18.8.0 — MAC random-access procedure, RAR, timers, backoff and contention resolution
3GPP TS 38.331 V18.9.0 — MIB, SIB1, RACH configuration, RRCSetupRequest, RRCSetup and RRCSetupComplete
```

Do not use a generic `Release18` string without exact specification versions. Put these versions in `InitialAccessSpecificationProfile` and in every generated run manifest.

## Scope restriction from the user

Work only on actual technical simulator implementation and technical validation:

```text
waveform generation
resource mapping
synchronization and detection
coding and decoding
ASN.1 serialization
PHY/MAC/RRC state machines
timing, power, retries and contention
independent technical vectors
link-level and multi-UE impact experiments
CSV and plot generation
```

Do not spend this phase on truth-contract naming, repository release hygiene, WebGUI security, authentication, publication wording or unrelated software governance.

## Non-negotiable engineering rules

1. Never change an expected vector merely to accommodate current DUT output. A vector change requires a written standards reason and regenerated hashes.
2. Never clamp NSizeGrid, kSSB, Lmax, SSB index, PRACH index, ZCZ, root index, timer, power or resource coordinates in strict mode.
3. Never catch a waveform-generator error and retry with a different physical configuration.
4. Never default an unknown SSB case to Case B.
5. Never create a one-SSB waveform when the configured burst bitmap activates multiple SSBs.
6. Never pass transmitted NCellID, timing, CFO, SSB index, Lmax, beam index or candidate location into the strict SSB/PBCH receiver.
7. Never pass ExpectedTxTree, ExpectedPayloadHash, ExpectedTreeHash, transmitted SIB1 bits or the scheduler's original grant into the strict SIB1 receiver.
8. Never insert a synthetic time gap between SSB and SIB1. Schedule all waveforms on one absolute frame/slot/symbol/sample timeline.
9. Never use a locally scanned PRB count or reconstructed NRE/G as scheduling authority. The decoded DCI and production PDSCH resource plan own SIB1.
10. Never use configured or frozen grants as a substitute for a CRC-valid decoded DCI in dynamic connected control paths.
11. Never use fixed Msg2/Msg3/Msg4 offsets such as PRACH slot +1/+2/+3 as the general procedure.
12. Never select a random preamble without the configured group, selected SSB, RO association, contention pool and deterministic seed state.
13. Never infer pathloss from configured SNR. Use an actual measurement state with identity, age and provenance.
14. Never mark random access successful at Msg4 alone when this profile requires RRCSetupComplete.
15. Never enter RRC_CONNECTED before a valid SetupComplete is decoded on the configured SRB1 and the transaction/identity state matches.
16. Never implement two-step, CFRA, BFR, SUL, NTN or RedCap as a flag around the four-step path.
17. Never call a MATLAB 5G Toolbox wrapper on both DUT and reference sides and label the result independent.
18. Never treat a skipped, unavailable, blocked or not-run mandatory MATLAB test as PASS.
19. Never report COMPLETE while a mandatory CSV, PNG, vector family, negative test, statistical point or dependency is missing.
20. Preserve useful existing Toolbox-backed kernels when they are correct; replace ownership, fallback, mapping and state-machine shortcuts around them.

## Current source state that must be changed

The supplied source audit contains 46 detected defect signatures and 10 useful implementation foundations.
Read `current_initial_access_static_audit.csv` before editing.

Useful foundations to preserve and integrate include:

```text
Toolbox-backed PSS/SSS/PBCH/BCH calls
existing no-oracle SSB test entry point
fail-closed Type-0 mini-profile entry point
PDSCH/DL-SCH integration for SIB1
waveform-backed Msg1, RAR, Msg3 and Msg4 stage kernels
strict PRACH waveform generator and detector
restricted-set helper code outside the current RA mini-profile
RA-RNTI helper
RA event/timer artifact plumbing
SIB1-to-four-step integration test
```

These foundations do not justify retaining the local defaults, oracle inputs, one-attempt state or constrained custom ASN.1 framing.

## The sixteen source-specific findings

### IA-001 — SSB capability/profile

**Current defect:** The SSB implementation does not execute one release-pinned capability matrix over FR1 bands, SSB cases, common SCS, periodicities, burst positions, kSSB, half-frame and beam counts.

**Source evidence:** +sixgr/+phy/+dl/SSB_Tx.m defaults Case B, 20 ms and a single block; independent SSB case logic also exists in FrameStructureEngine.m and buildInternalConfig.m.

**Technical impact:** A passing 3.5 GHz Case-B anchor does not establish correct Case-A/Case-C timing, burst scheduling, MIB coupling or multi-beam acquisition.

**Required production implementation:** Create SSBSpecificationProfile, SSBCaseResolver and SSBBurstPlan driven by exact band/raster/RRC context. The profile must list every supported FR1 tuple and reject every undeclared tuple before waveform generation.

**Mandatory tests:** Case A/B/C positive and negative band/SCS tuples; 5/10/20/40/80/160 ms periodicities; half-frame; SFN; burst-position bitmap; one/multiple beams; no-noise and AWGN acquisition.

**Impact analysis:** SSB periodicity, beam count, bitmap density, SNR, CFO, timing and mobility versus acquisition probability, latency and complexity.

### IA-002 — SSB grid validation

**Current defect:** SSB_Tx catches waveform-generator errors, parses the maximum grid size, clamps NSizeGrid and retries with a different waveform configuration.

**Source evidence:** +sixgr/+phy/+dl/SSB_Tx.m lines around localWavegenWithClamp and warning sixgr:phy:SSB_Tx:ClampNSizeGrid.

**Technical impact:** The emitted waveform can differ from the requested carrier/BWP while tests and artifacts still describe the original scenario.

**Required production implementation:** Remove clamp/retry from strict execution. Validate channel bandwidth, SCS, NRB, NStartGrid, SSB placement, kSSB and guardband through the canonical frame/grid resolver. Invalid tuples raise typed errors and generate zero samples.

**Mandatory tests:** All valid FR1 bandwidth/SCS/NRB tuples; one-RB overflow; invalid NStartGrid; SSB outside carrier; wrong kSSB; verify zero waveform and unchanged state.

**Impact analysis:** No performance study is permitted for invalid tuples; quantify valid grid-size/runtime scaling only.

### IA-003 — Lmax and SSB index

**Current defect:** Unsupported Lmax is coerced to 8, SSB index is clipped into range, and PBCH recovery warns then continues for unexpected Lmax.

**Source evidence:** +sixgr/+phy/+dl/SSB_Tx.m uses Lmax=8 fallback and min/max index clipping; PBCH_Recovery.m prints an unexpected-Lmax warning and continues.

**Technical impact:** PBCH scrambling, SSB-index bits, candidate set and beam identity can be wrong without a hard failure.

**Required production implementation:** Resolve Lmax and valid candidate indices from exact band/SSB-case context. Preserve the requested SSB index. Invalid Lmax/index combinations fail with typed errors before PBCH generation or decoding.

**Mandatory tests:** Lmax 4 and 8 bounded FR1 positives; invalid 0/1/2/16/32/64-for-bounded-profile; out-of-range SSB index; wrong Lmax at receiver; no silent mutation.

**Impact analysis:** Blind-search complexity and detection probability versus Lmax and active-beam bitmap.

### IA-004 — SS burst transmission

**Current defect:** The transmitter creates a one-hot TransmittedBlocks mask and therefore emits only one SSB by default.

**Source evidence:** +sixgr/+phy/+dl/SSB_Tx.m initializes all blocks to zero and enables only SSBIndex.

**Technical impact:** Beam sweeping, per-beam PBCH/DMRS, burst selection, collision and acquisition latency are not represented.

**Required production implementation:** Accept an exact ssb-PositionsInBurst bitmap and per-beam precoder/power plan. Generate every active SSB at its exact candidate symbol with unique SSB index and consistent PBCH/MIB.

**Mandatory tests:** 1,2,4,8 active beams; sparse bitmaps; per-beam power; independent index digest; received best-beam selection; equal-power tie; blocked best beam.

**Impact analysis:** Beam count and bitmap density versus acquisition probability, latency, overhead and receiver complexity.

### IA-005 — SSB case/timing ownership

**Current defect:** Multiple independent SSB case resolvers use simplified frequency thresholds and can disagree on case, common SCS and candidate symbols.

**Source evidence:** SSB_Tx.m, FrameStructureEngine.m and +sixgr/+lls6g/buildInternalConfig.m each resolve SSB case/timing locally.

**Technical impact:** TX, RX, frame plan and Type-0 CSS can use inconsistent symbol positions for the same scenario.

**Required production implementation:** Introduce one canonical band-aware SSBCaseResolver used by TX, RX, frame engine, MIB, Type-0 CSS and plotting. It returns case, common SCS, Lmax, candidate symbols and half-frame rules.

**Mandatory tests:** Cross-module object identity/digest equality; Case A/B/C candidate symbols; exact half-frame and SFN mapping; invalid band/case mismatch.

**Impact analysis:** Case-A versus Case-C acquisition under equal occupied bandwidth and controlled channel.

### IA-006 — Blind SSB/PBCH receiver

**Current defect:** Timing, block-pattern and received-grid fallbacks can reset offsets, default Case B or pad missing symbols; strict decoding is not uniformly fail-closed.

**Source evidence:** SSB_Rx.m catches timing estimation errors; timingEstimate.m defaults Case B; PBCH_Recovery.m continues after unexpected Lmax.

**Technical impact:** The receiver can consume oracle/default structure and report a decode where blind synchronization evidence is absent.

**Required production implementation:** Build SSBBlindSearchEngine that performs PSS NID2/timing/CFO search, SSS NID1, PBCH-DMRS hypothesis, SSB-index/half-frame hypothesis and BCH CRC without transmitted timing/index inputs. Fail on missing/ambiguous evidence.

**Mandatory tests:** No oracle timing/index/cell ID; ±CFO; timing offsets; wrong NCellID; wrong case; no-signal; second-strongest false peak; truncated waveform; multi-beam burst.

**Impact analysis:** Acquisition probability, CFO/timing error and complexity versus SNR, search range, Lmax and beam count.

### IA-007 — Beam sweeping and selection

**Current defect:** Beam sweeping is not causally connected through per-SSB precoding, receive measurements, beam selection, Type-0 monitoring and PRACH resource association.

**Source evidence:** Single-SSB default in SSB_Tx.m and separate runSSBBeamSweep helper; RA configuration does not own a selected SSB/RO association state.

**Technical impact:** The simulator cannot prove that the UE selects a beam from measured SSBs and uses the corresponding control/PRACH resources.

**Required production implementation:** Create InitialAccessBeamState with per-SSB RSRP/SINR, selected SSB, measurement age, beam/TCI digest and SSB-to-RO association. Every subsequent Type-0 and Msg1 action must reference this state.

**Mandatory tests:** Best-beam, tie, stale measurement, blockage, beam switch, wrong RO association, per-beam pathloss/power, two UEs selecting different beams.

**Impact analysis:** Beam mismatch, blockage, reselection delay and SSB-to-RO mapping versus access success and latency.

### IA-008 — SIB1 ASN.1

**Current defect:** SIB1 uses a constrained custom encoder/decoder and scenario tree rather than a release-pinned BCCH-DL-SCH ASN.1/UPER implementation for the declared profile.

**Source evidence:** +sixgr/+rrc/+asn1/encodeSIB1UPER.m and decodeSIB1UPER.m implement an anchor header/profile; validateSIB1ForScenario.m excludes broad configurations.

**Technical impact:** A local round trip can pass even when the encoded bitstream is not interoperable or field constraints/defaults are wrong.

**Required production implementation:** Use a generated or independently validated Release-18 ASN.1 codec for BCCH-DL-SCH-Message/SIB1. Model only the bounded FR1 profile but encode the normative message tree and reject unsupported IEs explicitly.

**Mandatory tests:** Frozen independent SIB1 UPER vectors; optional/presence bits; constrained integers/enums; extension markers; malformed/truncated payload; unknown extension; semantic install into MAC/RRC.

**Impact analysis:** SIB1 payload size, optional-IE load and MCS/resource demand versus SI acquisition BLER and latency.

### IA-009 — Type-0 CSS and SIB1 scheduling

**Current defect:** Type-0 CSS is fixed to one FR1 30 kHz, CORESET0=0, SearchSpace0=0, AL4, one-candidate and 32-bit DCI mini-profile.

**Source evidence:** +sixgr/+phy/+broadcast/deriveType0PDCCHFromMIB.m explicitly documents and enforces the mini-profile.

**Technical impact:** Most valid MIB pdcch-ConfigSIB1 values and Type-0 monitoring occasions are unsupported; SIB1 is not acquired through a general blind control path.

**Required production implementation:** Reuse the canonical PDCCH/DCI Type0PDCCHResolver and BlindSearchEngine. Derive CORESET0, SearchSpace0, monitoring occasion, SI-RNTI DCI 1_0 size and candidate set from decoded MIB and exact band/SCS tables.

**Mandatory tests:** All applicable Type-0 table rows for the bounded FR1 profile, reserved indices, multiple AL/candidate cases, no-signal/wrong SI-RNTI, wrong monitoring occasion and complete DCI-to-PDSCH causality.

**Impact analysis:** CORESET0 size, SearchSpace0 occasion, AL and SIB1 MCS versus detection, overhead, latency and runtime.

### IA-010 — SIB1 waveform and receiver ownership

**Current defect:** SIB1 allocation is locally scanned, NRE can be floored/reconstructed, a synthetic 1 ms gap is inserted, and the receiver accepts expected tree/hash inputs.

**Source evidence:** generateSSB_MIB_SIB1_Waveform.m scans nRB and concatenates waveforms with a 1 ms gap; recoverSIB1FromWaveform.m accepts ExpectedTxTree/ExpectedPayloadHash/ExpectedTreeHash.

**Technical impact:** SIB1 timing/resource mapping is not tied to the Type-0 schedule, and receiver validation can compare against transmitted oracle metadata.

**Required production implementation:** Schedule SIB1 in the exact Type-0 SI occasion. Derive PDSCH resources and TBS from decoded DCI and the canonical PDSCH chain. Receiver accepts no expected payload/tree/hash; semantic comparison belongs only in test code.

**Mandatory tests:** Exact absolute sample/slot/symbol mapping; DCI mutation changes PDSCH; no synthetic gap; wrong DCI/resource/DMRS; ASN.1 decode from received bits; no-oracle API reflection test.

**Impact analysis:** SIB1 MCS, allocation size, repetitions and payload size versus BLER, latency and overhead.

### IA-011 — RRC connection transition

**Current defect:** The current four-step RA anchor stops at contention-resolution success and does not complete RRCSetupRequest, RRCSetup and RRCSetupComplete with SRB1 and state transition.

**Source evidence:** runFourStepRA.m sets RACompleted after Msg4 identity match; no complete RRCSetupComplete stage is appended.

**Technical impact:** The simulator can claim access success without proving successful RRC connection establishment or UE/gNB state agreement.

**Required production implementation:** Extend the bounded chain: Msg3 carries RRCSetupRequest; Msg4 carries RRCSetup plus contention resolution; configure SRB1; UE transmits UL-DCCH RRCSetupComplete; gNB decodes it; both state machines transition to RRC_CONNECTED only after transaction and identity checks.

**Mandatory tests:** Success; wrong transaction ID; wrong UE identity; Setup CRC failure; SetupComplete CRC failure; duplicate/late SetupComplete; timer expiry; state rollback; SRB1 activation and PDCP/RLC lineage.

**Impact analysis:** RRC message size/MCS, retransmission and transaction failures versus total access latency and success.

### IA-012 — Four-step RA state machine

**Current defect:** The waveform-backed four-step RA path is a single bounded attempt with mostly fixed Msg2/Msg3/Msg4 slots and limited retry/backoff/group/contention behavior.

**Source evidence:** RAConfig.m defaults Msg2/3/4 to PRACH slot +1/+2/+3; runFourStepRA.m has one AttemptId and fault-injection branches.

**Technical impact:** Load, collision, retransmission, backoff and timer behavior cannot be studied as a real multi-attempt access process.

**Required production implementation:** Create UE and gNB RandomAccessStateMachine objects with attempt counter, preamble group/selection, power ramping, response window, backoff, Msg3 HARQ, contention timer and restart logic. Scheduling is event/timing driven, not fixed offsets.

**Mandatory tests:** Success first attempt; missed preamble; RAR miss; RAPID mismatch; Msg3 CRC/HARQ; Msg4 miss; collision/capture; timer expiry; backoff; preambleTransMax; two/many UE contention.

**Impact analysis:** UE load, preamble pool, ramping, backoff, windows and capture versus access probability, attempts, delay and energy.

### IA-013 — PRACH format/restricted-set matrix

**Current defect:** The bounded strict RA path rejects restricted sets and does not execute the complete declared long/short PRACH format, ZCZ, root-sequence and high-speed matrix.

**Source evidence:** RAConfig.m raises RestrictedSetUnsupportedStrict; validateSIB1ForScenario.m rejects non-unrestricted set; PRACH helpers have a broader but separate implementation.

**Technical impact:** PRACH sequence orthogonality, cyclic shifts and detection under delay/Doppler are not validated for many valid configurations.

**Required production implementation:** Consolidate one PRACHSpecificationProfile and table resolver using nrPRACHConfig/indices plus independent table vectors. Implement declared long and short formats, unrestricted/restricted Type A/B where applicable, NCS, root allocation and preamble mapping.

**Mandatory tests:** All 0..255 configuration indices for paired/unpaired context as table-resolution tests; declared waveform formats; restricted-set A/B; invalid set/format; ZCZ boundaries; root exhaustion; independent sequence/cyclic-shift vectors.

**Impact analysis:** Format, SCS, ZCZ, restricted set, delay spread, Doppler and root reuse versus detection/misdetection/false alarm.

### IA-014 — PRACH occasions and SSB association

**Current defect:** RA occasion generation and mapping are sparse/simplified and are not fully tied to PRACH configuration index, frame/slot/symbol/FDM, active UL BWP, SSB-per-RO and contention-based preamble allocation.

**Source evidence:** FrameStructureEngine.m has a sparse PRACH switch with fallback; RAConfig stores one resolved occasion; mapPRACHToOccasion.m is not the sole production owner.

**Technical impact:** UEs may transmit in non-existent occasions or use a different RO than the selected SSB and gNB detector.

**Required production implementation:** Create PRACHOccasionResolver and SSBToROAssociationEngine. Enumerate every valid RO in absolute time/frequency, derive RA-RNTI, map active SSBs to ROs/preambles and bind TX/RX to the same immutable occasion ID.

**Mandatory tests:** FDD/TDD 0..255 table sweep; multiple ROs per slot; multiple FDM; even/odd SFN; SSB-per-RO ratios; CB preambles per SSB; invalid/out-of-window occasion; RA-RNTI arithmetic.

**Impact analysis:** RO density, FDM, SSB/RO ratio and load versus collision, latency and detector runtime.

### IA-015 — RA timers, power and contention

**Current defect:** Response window, contention timer, power ramping, preamble groups, backoff, multi-UE contention and Msg3 HARQ are simplified or incompletely coupled to actual waveform and event timing.

**Source evidence:** RAConfig.m stores scalar windows/fixed slots; legacy RACHProcedure.m uses random preamble and a default UL grant; runFourStepRA.m applies a bounded power state but not a full multi-attempt loop.

**Technical impact:** Access success/latency and energy can be optimistic, and near-far/capture behavior cannot be trusted.

**Required production implementation:** Implement exact configured timers in the central timing engine; measured-pathloss preamble power, counter/ramp state, Pcmax clipping, group A/B selection, uniform/defined preamble selection, BI/backoff, Msg3 HARQ and contention/capture model.

**Mandatory tests:** Power arithmetic and waveform reconciliation; timer boundaries; response-window start/end; BI distribution with deterministic seeds; group A/B thresholds; same/different preamble collisions; near-far capture; maximum attempts.

**Impact analysis:** Ramping step/target, Pcmax, backoff, window, preamble pool, UE load and capture ratio versus delay, energy and success.

### IA-016 — Extended access profiles

**Current defect:** Two-step RA, CFRA, beam-failure recovery, SUL, NTN and RedCap/eRedCap access are not complete end-to-end profiles.

**Source evidence:** The production anchor is named runFourStepRA and the selected RRC/SIB1 profile explicitly excludes broad configurations.

**Technical impact:** The simulator cannot make strict claims for these procedures; shallow flags would create false breadth.

**Required production implementation:** Keep each extension explicitly UNSUPPORTED in the bounded FR1 profile. Define separate capability-gated profiles and dependency contracts. Implement one extension only after its complete RRC/MAC/PHY state, timing, waveform, negative tests and independent vectors exist.

**Mandatory tests:** Planning-time rejection for every unsupported extension; no fallback to four-step. Future extension suites: MsgA/MsgB, CFRA resource ownership, BFR beam/resource state, SUL carrier context, NTN delay/common TA, RedCap access restrictions.

**Impact analysis:** Blocked-dependency experiment definitions only; no synthetic performance result may be generated until the real dependency exists.

## Required canonical production architecture

Create one canonical package used by the actual runtime:

```text
+sixgr/+phy/+ia/
    InitialAccessSpecificationProfile.m
    InitialAccessCapabilityRegistry.m
    InitialAccessCarrierContext.m
    SSBCaseResolver.m
    SSBGridValidator.m
    SSBBurstPlan.m
    SSBBeamSweepPlan.m
    SSBResourceOwnershipMap.m
    SSBTransmitter.m
    SSBBlindSearchEngine.m
    PBCHReceiver.m
    MIBSemanticValidator.m
    InitialAccessBeamState.m
    SIB1SchedulingContext.m
    SIB1Scheduler.m
    SIB1Receiver.m
    PRACHSpecificationProfile.m
    PRACHConfigurationIndexResolver.m
    PRACHFormatValidator.m
    PRACHRootAndCyclicShiftPlan.m
    PRACHOccasionResolver.m
    SSBToROAssociationEngine.m
    PRACHResourceOwnershipMap.m
    PRACHTransmitter.m
    PRACHDetector.m
    RAAttemptContext.m
    RATimingService.m
    RAPowerControlState.m
    RAPowerController.m
    UEFourStepRAStateMachine.m
    GNBRandomAccessStateMachine.m
    RACollisionResolver.m
    RRCConnectionEstablishmentStateMachine.m
    InitialAccessReceiverMetrics.m
    InitialAccessArtifactExporter.m
    runInitialAccessPhaseValidation.m
    runInitialAccessImpactAnalysis.m

    +oracle/
        SSBCaseSpec.m
        SSBResourceMapSpec.m
        PBCHMIBSpec.m
        Type0TableSpec.m
        SIB1FrozenVectorAdapter.m
        PRACHConfigurationTableSpec.m
        PRACHSequenceSpec.m
        PRACHOccasionSpec.m
        RARNTISpec.m
        SSBToROAssociationSpec.m
        RAPowerSpec.m
        RATimerSpec.m
        RAStateTransitionSpec.m
        RRCConnectionTransitionSpec.m
```

Create the normative ASN.1 codec under:

```text
+sixgr/+rrc/+asn1r18/
    BCCHDLSCHCodec.m
    SIB1Codec.m
    ULCCCHCodec.m
    DLCCCHCodec.m
    ULDCCHCodec.m
    RRCSetupRequestCodec.m
    RRCSetupCodec.m
    RRCSetupCompleteCodec.m
    ASN1SchemaRegistry.m
    SIB1SemanticValidator.m
```

Existing `SSB_Tx`, `SSB_Rx`, `PBCH_Recovery`, broadcast helpers, PRACH helpers and `runFourStepRA` may remain only as compatibility façades. They must delegate to the canonical package and must not retain local case resolution, clamping, fixed timing, custom bit packing, report or state construction.

## Immutable state and causality model

Use immutable IDs and configuration epochs. At minimum create these state objects:

### `InitialAccessCarrierContext`

- band/ARFCN and spectrum mode
- carrier frequency and channel bandwidth
- carrier/common SCS and CP
- active DL/UL BWP IDs/start/size
- absolute frame/slot/symbol/sample clock
- duplex pattern
- configuration epoch

### `SSBBurstPlan`

- resolved case and SCS
- Lmax and candidate symbols
- periodicity and half-frame
- active bitmap
- per-SSB beam/precoder/power
- kSSB/grid placement
- MIB identity and plan SHA-256

### `InitialAccessBeamState`

- measurement ID/epoch/age
- per-SSB RSRP/SINR
- selected SSB/beam
- blocked/tie state
- selected pathloss reference
- SSB-to-RO association ID

### `DecodedMIBState`

- received PBCH/BCH evidence ID
- MIB 23 information bits
- SFN/common SCS/kSSB/type-A position/pdcch-ConfigSIB1
- cell barred/reselection values
- semantic validation status
- configuration epoch

### `DecodedSIB1State`

- received message SHA-256
- ASN.1 schema and codec identity
- semantic tree SHA-256
- serving-cell common state
- RACH common state
- timers/constants
- configuration epoch

### `PRACHOccasionState`

- absolute frame/slot/symbol
- time/frequency occasion index
- active UL BWP
- SSB association
- preamble group/range
- RA-RNTI
- occasion SHA-256

### `RAAttemptContext`

- UE/cell/attempt ID
- selected beam/SSB/RO/preamble
- power counter and measured pathloss
- timer states
- temporary/final C-RNTI
- Msg3 HARQ state
- decoded evidence lineage
- failure/restart reason

### `RRCConnectionState`

- UE and gNB endpoint state
- transaction ID
- UE identity
- SRB0/SRB1 status
- message hashes
- T300 and relevant timers
- last valid decoded event

A later state may be created only by decoded/validated evidence from the previous stage. The scheduler's intended action is not receiver evidence.

## Exact SSB implementation

### Case and Lmax resolution

Use the selected NR band/table context, not only a frequency threshold. For the supplied bounded vectors implement and independently verify the Release-18 FR1 candidate floors:

```text
Case A, 15 kHz: l = {2,8} + 14*n; bounded Lmax 4 or 8 according to the declared band context
Case B, 30 kHz: l = {4,8,16,20} + 28*n; bounded Lmax 4 or 8
Case C, 30 kHz: l = {2,8} + 14*n; paired/unpaired band context determines bounded Lmax 4 or 8
```

Do not infer Case C from any arbitrary unpaired frequency without the band/profile table. `ssb_case_lmax_test_vectors.csv` supplies valid and invalid bounded contexts.

### SS/PBCH block resource ownership

Build the exact 240-subcarrier by four-symbol SS/PBCH resource map before modulation.

For `v = NCellID mod 4`, the supplied independent floor requires:

```text
PSS:          127 RE
SSS:          127 RE
PBCH:         432 RE
PBCH DM-RS:   144 RE
zero/reserved:130 RE
total:        960 RE
```

Use `expected_ssb_re_ownership.csv`; do not call the DUT to generate its own expected map.
Data, DM-RS and zero ownership must be explicit per zero-based `(symbol,subcarrier)` coordinate.

### Multi-SSB burst and beam sweep

- Consume the exact `ssb-PositionsInBurst` bitmap rather than constructing a one-hot mask.
- Create every active SSB at the correct candidate symbol in the half-frame.
- Apply the configured per-SSB precoder and power to PSS, SSS, PBCH and PBCH DM-RS consistently.
- Record the logical SSB index separately from physical antenna/beam identity.
- Ensure every active SSB carries consistent MIB/PBCH state and correct SSB-index bits.
- Permit sparse bitmaps and multiple active beams up to the resolved bounded Lmax.
- Reject bitmap length and out-of-range active positions; never clip them.

### Blind receiver

The strict receiver must perform:

```text
coarse frequency/timing search
-> PSS NID2 hypotheses
-> SSS NID1 and NCellID
-> SSB case/candidate timing hypotheses allowed by profile
-> PBCH DM-RS hypotheses including SSB index/half-frame state
-> channel estimation/equalization
-> PBCH demodulation and BCH decoding
-> BCH CRC
-> MIB semantic validation
```

The strict receive API must not contain transmitted timing, transmitted CFO, transmitted NCellID, transmitted SSB index, transmitted Lmax, transmitted beam index, expected BCH bits or a known waveform slice.
A synchronized calibration mode may use known timing only when labelled calibration, isolated from strict evidence and excluded from connected-profile results.

## PBCH and MIB

The MIB semantic object must expose the 23 ASN.1 information bits:

```text
systemFrameNumber                6
subCarrierSpacingCommon         1
ssb-SubcarrierOffset            4
dmrs-TypeA-Position             1
pdcch-ConfigSIB1                8
cellBarred                      1
intraFreqReselection            1
spare                           1
total                          23
```

Validate every field before deriving Type-0 state. A BCH CRC pass does not permit an invalid MIB semantic state.
Use `pbch_mib_test_vectors.csv` and `expected_mib_semantics.csv` for the bounded pure-bit floor.

## Type-0 CSS and SIB1 control

Delete the current 30 kHz/index-zero/AL4/one-candidate/32-bit mini-profile constants.
Reuse or complete the canonical PDCCH/DCI package from the PDCCH phase.

The Type-0 resolver must derive from decoded MIB and immutable band/carrier context:

- controlResourceSetZero and searchSpaceZero
- multiplexing pattern
- CORESET0 RB count, duration and RB offset
- PDCCH and SSB SCS relationship
- absolute monitoring SFN, slot and first symbol
- valid aggregation levels and candidate counts
- SI-RNTI procedure and contextual DCI 1_0 payload size
- candidate CCE/REG/RE maps
- reserved/unsupported table rows

The pack supplies 452 Type-0 table-vector rows copied from the independent PDCCH pack:
- `ia_type0_coreset0_test_vectors.csv` — 268 rows
- `ia_expected_type0_monitoring_tables.csv` — 64 rows
- `ia_type0_pattern23_monitoring_test_vectors.csv` — 80 rows
- `ia_expected_type0_gscn_offset_vectors.csv` — 40 rows

A SIB1 PDSCH assignment is created only from a CRC-valid, semantically valid blind-decoded DCI 1_0 for SI-RNTI in the exact Type-0 monitoring occasion.

## SIB1 ASN.1 and semantic installation

### Replace the custom anchor framing

Remove `sixgr_sib1_anchor_profile_v1`, the local anchor header/version and any custom field order that is not generated from TS 38.331 ASN.1.
Use a Release-18 ASN.1 schema and an independently validated unaligned PER codec.

Do not claim independence from a local encode/decode round trip. Before completion add frozen external vectors satisfying every row in `sib1_frozen_vector_requirements.csv`.
For each frozen vector record:

- ASN.1 schema version and SHA-256
- encoder name/version/command
- semantic JSON
- UPER hex and exact bit length
- vector SHA-256
- expected decode tree and constraints
- mutation origin for negative vectors

### Bounded SIB1 semantic profile

Implement the normative message hierarchy needed for the bounded profile, including at least:

- cellAccessRelatedInfo and cellSelectionInfo
- servingCellConfigCommon and DL/UL common configuration
- SSB positions and periodicity
- initial DL and UL BWP common state
- BCCH/PCCH common state needed by the profile
- RACH-ConfigCommon and RACH-ConfigGeneric
- prach-ConfigurationIndex, msg1-FDM, msg1-FrequencyStart and ZCZ
- preamble received target power, power ramping and preambleTransMax
- RA response window, total preambles and SSB-per-RO/preambles-per-SSB
- contention resolution timer and RSRP threshold
- SI scheduling and UE timers/constants required by connection establishment

Unsupported optional IEs may be rejected by the bounded capability registry, but the bitstream must remain normative for the supported tree.

### SIB1 scheduling and receiver

- Remove the synthetic one-millisecond waveform gap.
- Schedule SIB1 in the exact absolute Type-0 SI occasion.
- Use the decoded DCI assignment and canonical PDSCH/DL-SCH chain.
- Derive TBS/G/NRE from the final exact PDSCH resource ownership map.
- Do not scan PRB counts locally until one happens to fit.
- Do not floor or reconstruct NRE from an unrelated metadata field.
- Do not pass expected TX tree, payload hash or tree hash to the receiver.
- Decode BCCH-DL-SCH bytes from received DL-SCH bits, then invoke ASN.1.
- Install decoded values into a new configuration epoch with per-field bit/message provenance.

## PRACH implementation

### Configuration-index and format engine

Create one release-pinned resolver used by frame planning, SIB1 semantic installation, PRACH TX, detector and RA state machines.
Execute `prach_configuration_index_sweep.csv`: 256 indices for FDD and 256 for TDD.
Every row must resolve to a complete valid or reserved result. No missing row and no default format such as A1 is allowed.

For each resolved configuration export:

- preamble format and sequence length
- x/y frame periodicity and allowed frame residues
- subframe/slot applicability
- starting symbol and duration
- number of time occasions
- number and location of frequency occasions
- PRACH SCS and occupied bandwidth
- active UL BWP binding
- reserved status and exact table row identity

### Sequence, root, cyclic shift and restricted set

- Implement declared long and short formats through the actual waveform path.
- Implement unrestricted long/short configurations.
- Implement restricted-set Type A and Type B only for valid long-sequence configurations.
- Derive NCS from the exact format/ZCZ/restricted-set table.
- Map preamble index to root sequence and cyclic shift exactly.
- Detect root-sequence budget exhaustion before waveform generation.
- Export independent sequence and index SHA-256 values.
- Test wrong root, cyclic shift, sequence length, format, ZCZ and preamble index.

Use the production Toolbox kernels for waveform generation/detection where correct, but compare indexes/sequences against pure-spec or frozen independent vectors. A second call to `nrPRACH` is self-consistency only.

### Occasion enumeration and RA-RNTI

Enumerate every PRACH occasion in absolute frame/slot/symbol/frequency coordinates.
Do not store one global `PRACHOccasionSlot` and treat it as the complete procedure.

For the selected PRACH occasion compute:

```text
RA-RNTI = 1 + s_id + 14*t_id + 14*80*f_id + 14*80*8*ul_carrier_id
```

Use `ra_rnti_test_vectors.csv` and `expected_ra_rnti.csv` as an independent arithmetic floor.

### SSB-to-RO association

- Resolve the association period from configured active SSBs and available ROs.
- Implement one-eighth, one-fourth, one-half, one, two, four, eight and sixteen SSB-per-RO configurations.
- Assign contention-based preamble ranges per SSB.
- Bind selected measured SSB, RO and preamble group in one immutable association ID.
- Reject an RO or preamble not associated with the selected SSB.
- Ensure the gNB detector uses the same association state without receiving the UE's chosen preamble as an oracle.

The supplied sequential mapping floor is not a substitute for the complete TS 38.213 association procedure. Implement the complete procedure and retain the floor as a deterministic regression.

## Four-step random access

### State machines

Replace the single monolithic fixed-slot procedure with separate event-sourced UE and gNB state machines.

A valid attempt progresses through explicit states such as:

```text
IDLE
-> SIB1_CONFIGURED
-> RO_SELECTED
-> MSG1_READY
-> WAIT_RAR
-> RAR_RECEIVED
-> MSG3_READY
-> WAIT_CONTENTION_RESOLUTION
-> RRC_SETUP_RECEIVED
-> WAIT_RRC_SETUP_COMPLETE_ACK/PROCESSING
-> RRC_CONNECTED
```

Failure events enter BACKOFF/RESTART or FAILED according to exact timer/counter state. Do not continue later stages after an earlier failure.

### Msg1

- Select preamble group A/B from decoded SIB1, Msg3 size/pathloss thresholds and configured pool.
- Select a preamble from the correct contention-based range with deterministic seeded randomness.
- Use the selected SSB/RO association and exact absolute PRACH occasion.
- Compute target and transmit power from measured pathloss, delta preamble, ramping counter/step and Pcmax.
- Apply requested power to the actual time-domain waveform and measure it back.
- Record root, cyclic shift, occasion, RA-RNTI, beam and power provenance.

### Msg2 RAR

- Open the exact RA response window after the transmitted PRACH occasion according to the selected numerology/procedure.
- Blind-monitor the applicable RAR PDCCH candidates for the computed RA-RNTI.
- Decode DCI and RAR PDSCH/DL-SCH through the canonical control/data chains.
- Parse MAC RAR subheaders and payloads; match RAPID.
- Install timing advance, UL grant and temporary C-RNTI only after all identity/CRC/window checks pass.
- Process Backoff Indicator where present.

### Msg3

- Materialize PUSCH assignment from the decoded RAR UL grant.
- Carry the normative UL-CCCH RRCSetupRequest for the bounded connection-establishment profile.
- Implement the applicable Msg3 HARQ behavior, RV/NDI and soft buffer.
- Apply timing advance and power control to the actual waveform.
- At the gNB decode PUSCH/UL-SCH and ASN.1; preserve UE contention identity lineage.

### Msg4 and contention resolution

- Schedule Msg4 from gNB state and valid decoded Msg3, not a fixed slot.
- Carry the UE Contention Resolution Identity MAC CE and bounded DL-CCCH RRCSetup.
- Use the correct temporary/final C-RNTI procedure state.
- Stop the contention timer only after identity and required CRC/semantic checks pass.
- On identity mismatch, timer expiry or CRC failure, do not activate SRB1 or final connected state.

### Power ramping, timers, backoff and retries

At minimum implement:

- preamble transmission counter and preambleTransMax
- power-ramping counter and configured step
- preamble received target power and delta preamble
- measured pathloss reference and age
- Pcmax clipping
- RA response window exact boundaries
- Backoff Indicator and deterministic uniform selection
- contention resolution timer exact start/expiry
- Msg3 HARQ timing
- attempt restart and configuration-epoch validation
- multi-UE same/different-preamble contention
- near-far capture model using the actual superposed waveform

The independent power floor uses:

```text
target_at_gNB = preambleReceivedTargetPower + deltaPreamble
                + (powerRampingCounter - 1) * powerRampingStep

requested_tx_power = target_at_gNB + measuredPathloss
applied_tx_power   = min(requested_tx_power, Pcmax)
```

The complete implementation must also apply all release/profile-specific conditions governing counter reset/increment and measurement selection.

## RRC connection establishment

This profile is not complete at `RACompleted=true`.

Implement:

```text
Msg3 UL-CCCH: RRCSetupRequest
Msg4 DL-CCCH: RRCSetup
SRB1 configuration/activation
UL-DCCH on SRB1: RRCSetupComplete
```

- Use Release-18 ASN.1 codecs for all three messages.
- Preserve UE identity and RRC transaction identifier.
- Maintain independent UE and gNB state machines.
- Validate message CRC, ASN.1 semantics, transaction and identity before each transition.
- Start/stop T300 and other bounded timers at the correct events.
- Permit no transition to RRC_CONNECTED until SetupComplete is decoded and accepted by the gNB.
- Make duplicate, late, wrong-transaction, wrong-identity and CRC-failed SetupComplete explicit negative cases.
- Record SRB0/SRB1, RLC/PDCP context IDs and message lineage sufficient to prove the actual transport path.

## Extended profiles must remain explicit UNSUPPORTED

For the bounded profile, the following requests must fail at planning time with the supplied typed errors and zero waveform/state mutation:

- two-step RA / MsgA-MsgB
- contention-free random access
- beam-failure recovery random access
- supplementary-uplink random access
- NTN random access
- RedCap/eRedCap-specific access

Do not create placeholder results, configured success, scalar-SINR proxies or four-step fallback. Separate future profiles may be created only after their complete procedure is implemented and independently validated.

## Dependency-ordered implementation sequence

### IA-TASK-01 — Capability/profile and canonical SSB context

- Findings: `IA-001|IA-003|IA-005|IA-016`
- Depends on: `none`
- Implement: Create profile registry, immutable carrier/band context, supported/unsupported tuple planner.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-02 — Strict SSB grid/case validation

- Findings: `IA-002|IA-003|IA-005`
- Depends on: `IA-TASK-01`
- Implement: Remove clamp/retry/coercion; implement band-aware case/Lmax/candidate resolver.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-03 — Multi-SSB burst and beam TX

- Findings: `IA-004|IA-007`
- Depends on: `IA-TASK-02`
- Implement: Implement bitmap, candidate positions, per-beam precoder/power and RE ownership.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-04 — Blind PSS/SSS/PBCH/MIB receiver

- Findings: `IA-006`
- Depends on: `IA-TASK-03`
- Implement: Implement no-oracle hypothesis search, PBCH/BCH decode and MIB semantic validation.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-05 — Full bounded Type-0 CSS

- Findings: `IA-009`
- Depends on: `IA-TASK-04`
- Implement: Integrate canonical PDCCH Type0 resolver, monitoring occasions and blind DCI 1_0.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-06 — Release-18 SIB1 ASN.1/UPER

- Findings: `IA-008`
- Depends on: `IA-TASK-01`
- Implement: Replace custom anchor codec with independently validated BCCH-DL-SCH codec.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-07 — Exact SIB1 scheduling and reception

- Findings: `IA-010`
- Depends on: `IA-TASK-05|IA-TASK-06`
- Implement: Remove synthetic gap/oracles; schedule through decoded DCI and production PDSCH.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-08 — PRACH table/format/restricted-set engine

- Findings: `IA-013`
- Depends on: `IA-TASK-01`
- Implement: Consolidate config-index, format, NCS, root, cyclic-shift and waveform handling.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-09 — RO enumeration and SSB association

- Findings: `IA-014`
- Depends on: `IA-TASK-03|IA-TASK-08`
- Implement: Enumerate absolute ROs, RA-RNTI and SSB-to-RO/preamble mapping.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-10 — RA power, timer and contention services

- Findings: `IA-015`
- Depends on: `IA-TASK-07|IA-TASK-09`
- Implement: Implement measured-pathloss power, ramping, timers, backoff, group A/B and contention.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-11 — Event-sourced four-step RA

- Findings: `IA-012`
- Depends on: `IA-TASK-10`
- Implement: Implement multi-attempt Msg1/RAR/Msg3/Msg4 state machines and Msg3 HARQ.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-12 — RRCSetupComplete and connected transition

- Findings: `IA-011`
- Depends on: `IA-TASK-11`
- Implement: Implement RRCSetupRequest/Setup/SetupComplete, SRB1 and synchronized UE/gNB state.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-13 — Negative and statistical campaigns

- Findings: `IA-006|IA-009|IA-012|IA-013|IA-015`
- Depends on: `IA-TASK-12`
- Implement: No-signal/wrong-identity/collision/multi-seed confidence campaigns.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-14 — Production CSV/PNG artifacts

- Findings: `IA-001|IA-016`
- Depends on: `IA-TASK-13`
- Implement: Generate all base technical artifacts from actual runtime state.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-15 — Impact-analysis runner

- Findings: `IA-001|IA-016`
- Depends on: `IA-TASK-14`
- Implement: Execute 720 paired experiments and 90 acceptance rules.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

### IA-TASK-16 — Full regression and completion

- Findings: `IA-001|IA-016`
- Depends on: `IA-TASK-15`
- Implement: Run all mandatory tests, verifiers and repository regressions; report exact residual unsupported features.
- Exit gate: all assigned tests execute and pass; no skipped/blocked mandatory test

Do not start the broad impact campaign before the bounded base chain and negative suite pass.

## Supplied deterministic vectors and floors

Do not copy expected CSVs into the production artifact directory. Production outputs must come from the actual MATLAB chain and then be compared with the vectors.

- `ssb_case_lmax_test_vectors.csv` — 67 rows
- `expected_ssb_case_lmax.csv` — 67 rows
- `expected_ssb_burst_candidates.csv` — 360 rows
- `ssb_re_mapping_test_vectors.csv` — 4 rows
- `expected_ssb_re_ownership.csv` — 3840 rows
- `expected_ssb_re_counts.csv` — 4 rows
- `pbch_mib_test_vectors.csv` — 53 rows
- `expected_mib_semantics.csv` — 53 rows
- `ia_type0_coreset0_test_vectors.csv` — 268 rows
- `ia_expected_type0_monitoring_tables.csv` — 64 rows
- `ia_type0_pattern23_monitoring_test_vectors.csv` — 80 rows
- `ia_expected_type0_gscn_offset_vectors.csv` — 40 rows
- `sib1_asn1_semantic_test_vectors.csv` — 83 rows
- `expected_sib1_semantics.csv` — 83 rows
- `sib1_frozen_vector_requirements.csv` — 8 rows
- `prach_configuration_index_sweep.csv` — 512 rows
- `prach_format_restricted_test_vectors.csv` — 380 rows
- `ra_rnti_test_vectors.csv` — 128 rows
- `expected_ra_rnti.csv` — 128 rows
- `prach_occasion_pattern_test_vectors.csv` — 1120 rows
- `expected_prach_occasion_floor.csv` — 1120 rows
- `ssb_to_ro_association_test_vectors.csv` — 120 rows
- `expected_ssb_to_ro_association_floor.csv` — 120 rows
- `ra_power_ramping_test_vectors.csv` — 320 rows
- `expected_ra_power_ramping.csv` — 320 rows
- `ra_timer_backoff_test_vectors.csv` — 96 rows
- `expected_ra_timer_backoff.csv` — 96 rows
- `rrc_setup_transition_test_vectors.csv` — 32 rows
- `expected_rrc_setup_transition.csv` — 32 rows
- `initial_access_end_to_end_test_vectors.csv` — 146 rows
- `initial_access_negative_test_vectors.csv` — 138 rows
- `initial_access_declared_coverage_matrix.csv` — 271 rows
- `initial_access_impact_analysis_families.csv` — 60 rows
- `initial_access_impact_experiment_matrix.csv` — 720 rows
- `initial_access_impact_pairing_contract.csv` — 60 rows
- `initial_access_impact_acceptance_rules.csv` — 90 rows
- `initial_access_impact_dependency_waves.csv` — 3 rows
- `initial_access_impact_implementability_summary.csv` — 4 rows
- `expected_initial_access_impact_analytical_floor.csv` — 120 rows
- `desired_initial_access_csv_contract.csv` — 31 rows
- `desired_initial_access_image_contract.csv` — 20 rows
- `desired_initial_access_impact_csv_contract.csv` — 16 rows
- `desired_initial_access_impact_image_contract.csv` — 30 rows

The manifest currently protects 43 files and 11,307 rows. Run:

```bash
python tests/vectors/initial_access/verify_initial_access_vector_pack.py
```

The bounded floors do not replace the missing independent SIB1 UPER and complete PRACH table/vector sources. Add those sources with implementation/version/command/hash provenance before completion.

## Mandatory MATLAB tests

- `testInitialAccessCapabilityRegistry` — profile tuples and planning-time extension rejection
- `testSSBCaseResolverCaseA` — Case A candidate symbols/Lmax
- `testSSBCaseResolverCaseB` — Case B candidate symbols/Lmax
- `testSSBCaseResolverCaseC` — Case C paired/unpaired thresholds
- `testSSBGridValidation` — bandwidth/SCS/NRB/kSSB/no-clamp behavior
- `testSSBInvalidLmaxAndIndex` — typed rejection/no mutation
- `testSSBResourceOwnership` — exact 960-RE ownership for v=0..3
- `testSSBBurstBitmapAndCandidateTiming` — multi-SSB bitmap and exact absolute timing
- `testSSBPerBeamPrecodingAndPower` — beam matrix/power application
- `testSSBBlindCellSearchNoOracle` — PSS/SSS timing/CFO/cell ID without transmitted truth
- `testSSBBlindSearchMultiBeam` — best beam/tie/blockage cases
- `testPBCHDMRSAndBCHDecode` — sequence/index/BCH CRC
- `testMIBSemanticPacking` — 23-bit MIB fields and invalid values
- `testType0CORESET0Tables` — all bounded FR1 CORESET0 rows
- `testType0SearchSpace0Tables` — monitoring rows/patterns/reserved cases
- `testType0BlindDCI10SIRNTI` — true blind candidates and wrong-RNTI/no-signal
- `testSIB1IndependentUPERVectors` — external ASN.1 bit-exact vectors
- `testSIB1MalformedAndExtensions` — truncation/constraint/extension handling
- `testSIB1SemanticInstallation` — decoded RACH/common/timer state and epoch
- `testSIB1ExactScheduling` — decoded DCI controls PDSCH resources
- `testSIB1NoSyntheticGap` — absolute timing/sample mapping
- `testSIB1ReceiverNoOracle` — no expected tree/hash/payload input
- `testSIB1PDSCHDLSCHRoundTrip` — no-noise/AWGN/TDL/CDL SIB1 recovery
- `testPRACHConfigIndexFDD` — 0..255 table resolution
- `testPRACHConfigIndexTDD` — 0..255 table resolution
- `testPRACHLongFormats` — formats 0/1/2/3 waveform and detector
- `testPRACHShortFormats` — A1/A2/A3/B1/B4/C0/C2 waveform and detector
- `testPRACHRestrictedSetTypeA` — long-sequence Type A roots/cyclic shifts
- `testPRACHRestrictedSetTypeB` — long-sequence Type B roots/cyclic shifts
- `testPRACHZCZAndRootBudget` — NCS/root exhaustion/boundaries
- `testPRACHOccasionResolver` — frame/slot/symbol/FDM absolute occasions
- `testRARNTIArithmetic` — exact RA-RNTI for occasion coordinates
- `testSSBToROAssociation` — all declared ratios/preamble groups
- `testRAPreamblePowerControl` — target/pathloss/ramping/Pcmax/waveform power
- `testRAResponseWindow` — exact inclusive/exclusive boundaries
- `testRABackoff` — BI/deterministic random selection/restart
- `testRAContentionResolutionTimer` — exact timer start/stop/expiry
- `testRAPreambleGroupAB` — message/pathloss thresholds and selection
- `testFourStepRAFirstAttemptSuccess` — Msg1/RAR/Msg3/Msg4 causal path
- `testFourStepRAMultiAttempt` — miss/retry/backoff/ramping/preambleTransMax
- `testFourStepRACollisionAndCapture` — same/different preamble multi-UE
- `testRARWrongRNTIAndRAPID` — no false grant/state mutation
- `testMsg3HARQ` — RV/NDI/soft buffer and RRCSetupRequest lineage
- `testRRCConnectionEstablishment` — SetupRequest/Setup/SetupComplete success
- `testRRCSetupTransactionAndIdentity` — wrong transaction/identity rejection
- `testRRCSetupCompleteLateDuplicateCRC` — timer/duplicate/CRC/state rollback
- `testInitialAccessNoSignalFalseAlarm` — SSB/PDCCH/PRACH no-signal exact bounds
- `testInitialAccessWrongIdentityMatrix` — cell/RNTI/RO/preamble/transaction faults
- `testInitialAccessEndToEndChannels` — AWGN/TDL/CDL and mobility bounded profile
- `testInitialAccessArtifactGeneration` — 31 CSV/20 PNG production contracts
- `testInitialAccessImpactAnalysis` — 60 families/720 experiments/90 rules
- `testInitialAccessFullRegression` — all repository initial-access and dependent PHY suites

Every test is mandatory. A test may not `assumeFail`, return early, mark itself passed because a Toolbox function is unavailable, or silently switch to a proxy.

## Required production CSVs

- `initial_access_run_manifest.csv` — key `RunID`, minimum 1 rows
- `ssb_case_resolution.csv` — key `CaseID`, minimum 20 rows
- `ssb_burst_plan.csv` — key `CaseID|HalfFrame|SSBIndex0`, minimum 40 rows
- `ssb_re_ownership.csv` — key `CaseID|SSBIndex0|Symbol0|Subcarrier0`, minimum 960 rows
- `ssb_blind_search_hypotheses.csv` — key `TrialID|HypothesisID`, minimum 100 rows
- `ssb_beam_measurements.csv` — key `TrialID|SSBIndex0`, minimum 20 rows
- `pbch_mib_decode.csv` — key `TrialID`, minimum 20 rows
- `type0_coreset_resolution.csv` — key `CaseID`, minimum 50 rows
- `type0_monitoring_candidates.csv` — key `TrialID|MonitoringOccasionID|AggregationLevel|CandidateIndex`, minimum 100 rows
- `sib1_dci_resolution.csv` — key `TrialID`, minimum 20 rows
- `sib1_resource_ownership.csv` — key `TrialID|Symbol0|PRB0|SubcarrierInPRB0`, minimum 100 rows
- `sib1_asn1_decode.csv` — key `TrialID`, minimum 20 rows
- `decoded_sib1_install.csv` — key `TrialID|ParameterPath`, minimum 50 rows
- `prach_config_resolution.csv` — key `CaseID`, minimum 100 rows
- `prach_occasion_resolution.csv` — key `OccasionID`, minimum 100 rows
- `ssb_ro_association.csv` — key `AssociationID`, minimum 20 rows
- `prach_sequence_indices.csv` — key `CaseID|PreambleIndex`, minimum 64 rows
- `prach_detection_trials.csv` — key `TrialID`, minimum 100 rows
- `ra_power_control.csv` — key `AttemptID`, minimum 20 rows
- `ra_timer_events.csv` — key `AttemptID|TimerName|Event|AbsoluteSlot`, minimum 30 rows
- `ra_attempt_events.csv` — key `AttemptID|EventOrdinal`, minimum 50 rows
- `rar_decode.csv` — key `AttemptID`, minimum 20 rows
- `msg3_harq.csv` — key `AttemptID|HARQRound`, minimum 20 rows
- `contention_resolution.csv` — key `AttemptID`, minimum 20 rows
- `rrc_connection_events.csv` — key `AttemptID|Endpoint|EventOrdinal`, minimum 30 rows
- `initial_access_receiver_metrics.csv` — key `TrialID|Stage`, minimum 50 rows
- `initial_access_stage_bler.csv` — key `OperatingPointID|Stage`, minimum 30 rows
- `initial_access_negative_tests.csv` — key `CaseID`, minimum 50 rows
- `initial_access_independent_vector_results.csv` — key `VectorFamily|VectorID`, minimum 50 rows
- `initial_access_test_summary.csv` — key `TestSuite`, minimum 10 rows
- `initial_access_image_semantic_audit.csv` — key `ImageFile`, minimum 20 rows

## Required production figures

- `ssb_burst_timeline.png` from `ssb_burst_plan.csv`
- `ssb_resource_grid.png` from `ssb_re_ownership.csv`
- `ssb_beam_rsrp.png` from `ssb_beam_measurements.csv`
- `ssb_blind_search_heatmap.png` from `ssb_blind_search_hypotheses.csv`
- `pbch_mib_bit_layout.png` from `pbch_mib_decode.csv`
- `type0_coreset_searchspace.png` from `type0_coreset_resolution.csv|type0_monitoring_candidates.csv`
- `sib1_resource_grid.png` from `sib1_resource_ownership.csv`
- `sib1_asn1_tree_size.png` from `sib1_asn1_decode.csv`
- `prach_occasion_map.png` from `prach_occasion_resolution.csv`
- `prach_preamble_correlation.png` from `prach_detection_trials.csv`
- `ssb_ro_association.png` from `ssb_ro_association.csv`
- `ra_power_ramping.png` from `ra_power_control.csv`
- `ra_timer_timeline.png` from `ra_timer_events.csv`
- `ra_attempt_state_machine.png` from `ra_attempt_events.csv`
- `ra_collision_capture.png` from `prach_detection_trials.csv|ra_attempt_events.csv`
- `msg3_harq_timeline.png` from `msg3_harq.csv`
- `rrc_connection_timeline.png` from `rrc_connection_events.csv`
- `initial_access_stage_failures.png` from `initial_access_stage_bler.csv`
- `initial_access_success_vs_snr.png` from `initial_access_stage_bler.csv`
- `initial_access_latency_cdf.png` from `ra_attempt_events.csv|rrc_connection_events.csv`

Every figure must be generated from its source CSV, not from a separate in-memory result. Export source CSV and PNG SHA-256, title, axis labels, axes/series counts and finite-point count in `initial_access_image_semantic_audit.csv`.

## Impact analysis

After the base chain passes, execute all 60 families and 720 paired experiments in `initial_access_impact_experiment_matrix.csv`.
The sign convention is always treatment minus baseline.
Each pair uses identical seed, payload, channel, noise and initial state; only the declared factor changes.

### F01 — SSB periodicity

- Group: `SSB`
- Factor: `SSBPeriodicity_ms`
- Baseline: `20`
- Treatments: `5|10|40|80|160`
- Metrics: `AcquisitionLatency_ms|AcquisitionProbability|SSBOverhead`
- Wave: `A`
- Dependencies: `none`

### F02 — Active SSB beam count

- Group: `SSB`
- Factor: `NumActiveSSBs`
- Baseline: `1`
- Treatments: `2|4|8`
- Metrics: `BestBeamRSRP_dBm|AcquisitionProbability|SearchRuntime_ms|SSBOverhead`
- Wave: `A`
- Dependencies: `none`

### F03 — Sparse versus dense burst bitmap

- Group: `SSB`
- Factor: `SSBBitmapDensity`
- Baseline: `0.25`
- Treatments: `0.5|1.0`
- Metrics: `AcquisitionLatency_ms|MissProbability|BurstOverhead`
- Wave: `A`
- Dependencies: `none`

### F04 — Case A versus Case C at controlled bandwidth

- Group: `SSB`
- Factor: `SSBCase`
- Baseline: `A`
- Treatments: `C`
- Metrics: `DetectionProbability|TimingError_samples|Runtime_ms`
- Wave: `A`
- Dependencies: `none`

### F05 — PSS/SSS EPRE scaling

- Group: `SSB`
- Factor: `PSSSSSEPREOffset_dB`
- Baseline: `0`
- Treatments: `-6|-3|3|6`
- Metrics: `PSSDetectionProbability|NCellIDErrorRate|FalsePeakRate`
- Wave: `A`
- Dependencies: `none`

### F06 — SSB SNR sweep

- Group: `SSB`
- Factor: `SSBSNR_dB`
- Baseline: `-6`
- Treatments: `-4|-2|0|2|4|8`
- Metrics: `PSSDetectionProbability|BCHBLER|AcquisitionLatency_ms`
- Wave: `A`
- Dependencies: `none`

### F07 — Carrier-frequency offset stress

- Group: `SSB`
- Factor: `CFO_Hz`
- Baseline: `0`
- Treatments: `100|500|1000|2000`
- Metrics: `ResidualCFO_Hz|PSSDetectionProbability|BCHBLER`
- Wave: `A`
- Dependencies: `none`

### F08 — Timing-offset stress

- Group: `SSB`
- Factor: `TimingOffset_samples`
- Baseline: `0`
- Treatments: `2|8|32|128`
- Metrics: `TimingError_samples|PSSDetectionProbability|BCHBLER`
- Wave: `A`
- Dependencies: `none`

### F09 — Selected-beam mismatch

- Group: `BEAM`
- Factor: `BeamMismatchIndex`
- Baseline: `0`
- Treatments: `1|2|3`
- Metrics: `Type0DetectionProbability|SIB1BLER|AccessSuccessProbability`
- Wave: `B`
- Dependencies: `InitialAccessBeamState`

### F10 — Beam blockage and reselection

- Group: `BEAM`
- Factor: `BlockedSelectedBeam`
- Baseline: `false`
- Treatments: `true`
- Metrics: `ReselectionLatency_ms|AccessSuccessProbability|AttemptCount`
- Wave: `C`
- Dependencies: `beam_blockage_and_recovery_model`

### F11 — PBCH DM-RS SNR sensitivity

- Group: `PBCH`
- Factor: `PBCHDMRSSNR_dB`
- Baseline: `0`
- Treatments: `-6|-3|3|6`
- Metrics: `ChannelEstimateNMSE|BCHBLER|SSBIndexErrorRate`
- Wave: `A`
- Dependencies: `none`

### F12 — Lmax blind-hypothesis complexity

- Group: `PBCH`
- Factor: `Lmax`
- Baseline: `4`
- Treatments: `8`
- Metrics: `CandidateCount|Runtime_ms|FalseHypothesisRate`
- Wave: `A`
- Dependencies: `none`

### F13 — Single-bit MIB corruption

- Group: `MIB`
- Factor: `MIBBitMutation`
- Baseline: `none`
- Treatments: `sfn|scs|kssb|type0|barred`
- Metrics: `MIBCRCFailureRate|SemanticRejectRate|WrongType0Rate`
- Wave: `A`
- Dependencies: `none`

### F14 — kSSB placement and edge margin

- Group: `MIB`
- Factor: `SSBSubcarrierOffset`
- Baseline: `0`
- Treatments: `1|7|15`
- Metrics: `SSBGridMargin_subcarriers|BCHBLER|RejectRate`
- Wave: `A`
- Dependencies: `none`

### F15 — CORESET0 table selection

- Group: `TYPE0`
- Factor: `CORESET0Index`
- Baseline: `0`
- Treatments: `1|2|4|8|12`
- Metrics: `PDCCHDetectionProbability|CORESETOverhead_RE|Runtime_ms`
- Wave: `A`
- Dependencies: `PDCCH_Type0_resolver`

### F16 — SearchSpace0 table selection

- Group: `TYPE0`
- Factor: `SearchSpace0Index`
- Baseline: `0`
- Treatments: `1|2|4|8|12`
- Metrics: `SIB1MonitoringLatency_ms|CandidateCount|MissProbability`
- Wave: `A`
- Dependencies: `PDCCH_Type0_resolver`

### F17 — PDCCH aggregation level

- Group: `TYPE0`
- Factor: `AggregationLevel`
- Baseline: `4`
- Treatments: `1|2|8|16`
- Metrics: `PDCCHDetectionProbability|ControlOverhead_RE|Runtime_ms`
- Wave: `A`
- Dependencies: `PDCCH_blind_search`

### F18 — SIB1 MCS impact

- Group: `SIB1`
- Factor: `SIB1MCS`
- Baseline: `0`
- Treatments: `2|4|6|9`
- Metrics: `SIB1BLER|SIB1ResourceRE|AcquisitionLatency_ms`
- Wave: `A`
- Dependencies: `PDSCH_DLSCH`

### F19 — SIB1 payload size

- Group: `SIB1`
- Factor: `SIB1PayloadBits`
- Baseline: `256`
- Treatments: `512|1024|2048|4096`
- Metrics: `RequiredPRBs|SIB1BLER|DecodeRuntime_ms`
- Wave: `A`
- Dependencies: `ASN1_codec_and_PDSCH`

### F20 — Optional IE load

- Group: `SIB1`
- Factor: `SIB1OptionalIECount`
- Baseline: `0`
- Treatments: `2|4|8|12`
- Metrics: `UPERBits|RequiredPRBs|DecodeRuntime_ms`
- Wave: `A`
- Dependencies: `independent_ASN1_codec`

### F21 — SIB1 periodicity/repetition

- Group: `SIB1`
- Factor: `SIB1Periodicity_ms`
- Baseline: `160`
- Treatments: `20|40|80`
- Metrics: `AcquisitionLatency_ms|SIB1Overhead|SuccessProbability`
- Wave: `B`
- Dependencies: `SI_scheduler`

### F22 — Long versus short PRACH

- Group: `PRACH`
- Factor: `PreambleFormat`
- Baseline: `0`
- Treatments: `A1`
- Metrics: `DetectionProbability|TimingRMSE_samples|OccupiedTime_us`
- Wave: `A`
- Dependencies: `none`

### F23 — Preamble format versus delay spread

- Group: `PRACH`
- Factor: `PreambleFormat`
- Baseline: `A1`
- Treatments: `0|1|2|3|A2|A3|B4|C2`
- Metrics: `DetectionProbability|TimingRMSE_samples|FalseAlarmProbability`
- Wave: `A`
- Dependencies: `none`

### F24 — PRACH SCS versus CFO

- Group: `PRACH`
- Factor: `PRACHSCS_kHz`
- Baseline: `1.25`
- Treatments: `5|15|30|60`
- Metrics: `DetectionProbability|FrequencyError_Hz|TimingRMSE_samples`
- Wave: `A`
- Dependencies: `none`

### F25 — Restricted set Type A

- Group: `PRACH`
- Factor: `RestrictedSet`
- Baseline: `UnrestrictedSet`
- Treatments: `RestrictedSetTypeA`
- Metrics: `DetectionProbability|CyclicShiftCollisionRate|RootUsage`
- Wave: `A`
- Dependencies: `long_sequence_restricted_set`

### F26 — Restricted set Type B

- Group: `PRACH`
- Factor: `RestrictedSet`
- Baseline: `UnrestrictedSet`
- Treatments: `RestrictedSetTypeB`
- Metrics: `DetectionProbability|CyclicShiftCollisionRate|RootUsage`
- Wave: `A`
- Dependencies: `long_sequence_restricted_set`

### F27 — Zero-correlation-zone configuration

- Group: `PRACH`
- Factor: `ZeroCorrelationZoneConfig`
- Baseline: `0`
- Treatments: `1|5|10|15`
- Metrics: `NumCyclicShifts|DetectionProbability|CollisionLeakage`
- Wave: `A`
- Dependencies: `none`

### F28 — Root sequence reuse

- Group: `PRACH`
- Factor: `RootReuseFactor`
- Baseline: `1`
- Treatments: `2|4|8`
- Metrics: `FalseAlarmProbability|CollisionLeakage|RootBudget`
- Wave: `A`
- Dependencies: `none`

### F29 — Frequency-domain occasions

- Group: `PRACH`
- Factor: `Msg1FDM`
- Baseline: `1`
- Treatments: `2|4|8`
- Metrics: `CollisionProbability|DetectorRuntime_ms|FrequencyOccupancy_RB`
- Wave: `A`
- Dependencies: `none`

### F30 — RA occasion density

- Group: `PRACH`
- Factor: `RAOccasionsPer10ms`
- Baseline: `1`
- Treatments: `2|4|8|16`
- Metrics: `AccessLatency_ms|CollisionProbability|PRACHOverhead`
- Wave: `A`
- Dependencies: `none`

### F31 — SSB-to-RO ratio

- Group: `PRACH`
- Factor: `SSBsPerRO`
- Baseline: `1`
- Treatments: `0.125|0.25|0.5|2|4|8`
- Metrics: `CollisionProbability|BeamROConsistency|AccessLatency_ms`
- Wave: `B`
- Dependencies: `SSBToROAssociationEngine`

### F32 — Preamble group A/B selection

- Group: `RA`
- Factor: `PreambleGroupMode`
- Baseline: `A_only`
- Treatments: `A_and_B`
- Metrics: `LargeMsg3SelectionRate|CollisionProbability|AccessLatency_ms`
- Wave: `A`
- Dependencies: `none`

### F33 — Contention-based preamble pool

- Group: `RA`
- Factor: `CBPreamblesPerSSB`
- Baseline: `64`
- Treatments: `4|8|16|32`
- Metrics: `CollisionProbability|AccessSuccessProbability|MeanAttempts`
- Wave: `A`
- Dependencies: `none`

### F34 — Contending UE load

- Group: `RA`
- Factor: `NumContendingUEs`
- Baseline: `1`
- Treatments: `2|4|8|16|32|64`
- Metrics: `CollisionProbability|AccessSuccessProbability|P95Latency_ms`
- Wave: `A`
- Dependencies: `multi_UE_RA`

### F35 — Power-ramping step

- Group: `POWER`
- Factor: `PowerRampingStep_dB`
- Baseline: `2`
- Treatments: `0|4|6`
- Metrics: `DetectionProbability|MeanAttempts|EnergyPerAccess_mJ`
- Wave: `A`
- Dependencies: `none`

### F36 — Preamble target power

- Group: `POWER`
- Factor: `PreambleReceivedTargetPower_dBm`
- Baseline: `-100`
- Treatments: `-120|-110|-90`
- Metrics: `DetectionProbability|ClippingProbability|InterferencePower_dBm`
- Wave: `A`
- Dependencies: `none`

### F37 — Maximum preamble transmissions

- Group: `RA`
- Factor: `PreambleTransMax`
- Baseline: `10`
- Treatments: `3|5|20|50`
- Metrics: `DropProbability|P95Latency_ms|EnergyPerAccess_mJ`
- Wave: `A`
- Dependencies: `none`

### F38 — Backoff indicator

- Group: `RA`
- Factor: `BackoffIndicator_ms`
- Baseline: `0`
- Treatments: `10|20|40|80|160|320`
- Metrics: `CollisionProbability|P95Latency_ms|ChannelLoad`
- Wave: `A`
- Dependencies: `none`

### F39 — RAR response-window size

- Group: `RA`
- Factor: `RAResponseWindow_slots`
- Baseline: `8`
- Treatments: `1|2|4|10|20|40|80`
- Metrics: `RARMissProbability|AccessLatency_ms|MonitoringOverhead`
- Wave: `A`
- Dependencies: `none`

### F40 — RAR PDCCH aggregation/candidates

- Group: `RAR`
- Factor: `RARAggregationLevel`
- Baseline: `4`
- Treatments: `1|2|8|16`
- Metrics: `RARDetectionProbability|ControlOverhead_RE|FalseGrantProbability`
- Wave: `B`
- Dependencies: `PDCCH_DCI`

### F41 — RAR PDSCH MCS

- Group: `RAR`
- Factor: `RARPDSCHMCS`
- Baseline: `0`
- Treatments: `2|4|6|9`
- Metrics: `RARBLER|RARResourceRE|AccessLatency_ms`
- Wave: `B`
- Dependencies: `PDSCH_DLSCH`

### F42 — Msg3 payload size and MCS

- Group: `MSG3`
- Factor: `Msg3PayloadBytes`
- Baseline: `56`
- Treatments: `20|100|200|400`
- Metrics: `Msg3BLER|RequiredPRBs|AccessLatency_ms`
- Wave: `B`
- Dependencies: `PUSCH_ULSCH`

### F43 — Timing-advance residual error

- Group: `MSG3`
- Factor: `ResidualTimingAdvance_samples`
- Baseline: `0`
- Treatments: `2|8|16|32`
- Metrics: `Msg3EVM|Msg3BLER|TimingEstimateRMSE`
- Wave: `B`
- Dependencies: `PUSCH_ULSCH_and_TA`

### F44 — Contention-resolution timer

- Group: `RA`
- Factor: `ContentionResolutionTimer_ms`
- Baseline: `64`
- Treatments: `8|16|32|48`
- Metrics: `TimerExpiryProbability|AccessLatency_ms|MonitoringOverhead`
- Wave: `A`
- Dependencies: `none`

### F45 — Near-far capture in same-preamble collision

- Group: `RA`
- Factor: `NearFarCapture_dB`
- Baseline: `0`
- Treatments: `3|6|10|20`
- Metrics: `CaptureProbability|WrongUEResolutionRate|AccessSuccessProbability`
- Wave: `B`
- Dependencies: `multi_user_waveform_channel`

### F46 — RAPID mismatch rejection

- Group: `RAR`
- Factor: `RAPIDMutation`
- Baseline: `none`
- Treatments: `wrong_rapid`
- Metrics: `FalseGrantProbability|StateMutationCount|RejectRate`
- Wave: `A`
- Dependencies: `none`

### F47 — Wrong RA-RNTI rejection

- Group: `RAR`
- Factor: `RARNTIMutation`
- Baseline: `none`
- Treatments: `plus1|wrong_fdm|wrong_slot`
- Metrics: `FalseGrantProbability|StateMutationCount|RejectRate`
- Wave: `A`
- Dependencies: `none`

### F48 — No-signal PRACH false alarm

- Group: `PRACH`
- Factor: `PRACHSignalPresent`
- Baseline: `true`
- Treatments: `false`
- Metrics: `FalseAlarmProbability|ClopperPearsonUpper|SpuriousRARCount`
- Wave: `A`
- Dependencies: `none`

### F49 — Msg3 HARQ retransmission

- Group: `MSG3`
- Factor: `Msg3HARQEnabled`
- Baseline: `false`
- Treatments: `true`
- Metrics: `Msg3SuccessProbability|MeanRetransmissions|AccessLatency_ms`
- Wave: `B`
- Dependencies: `PUSCH_HARQ`

### F50 — RRCSetupRequest payload size

- Group: `RRC`
- Factor: `RRCSetupRequestBits`
- Baseline: `56`
- Treatments: `80|120|200`
- Metrics: `Msg3BLER|RequiredPRBs|AccessLatency_ms`
- Wave: `B`
- Dependencies: `ASN1_RRC_and_PUSCH`

### F51 — RRCSetup payload size

- Group: `RRC`
- Factor: `RRCSetupBits`
- Baseline: `256`
- Treatments: `512|1024|2048`
- Metrics: `Msg4BLER|RequiredPRBs|AccessLatency_ms`
- Wave: `B`
- Dependencies: `ASN1_RRC_and_PDSCH`

### F52 — RRCSetupComplete transaction mismatch

- Group: `RRC`
- Factor: `TransactionMutation`
- Baseline: `none`
- Treatments: `wrong_transaction|wrong_identity`
- Metrics: `RejectRate|IllegalConnectedTransitions|StateRollbackCount`
- Wave: `A`
- Dependencies: `none`

### F53 — End-to-end SNR sweep

- Group: `E2E`
- Factor: `CommonSNR_dB`
- Baseline: `-4`
- Treatments: `-2|0|2|4|8|15`
- Metrics: `RRCConnectedProbability|MeanAccessLatency_ms|StageFailureDistribution`
- Wave: `B`
- Dependencies: `all_bounded_chain`

### F54 — Mobility/Doppler

- Group: `E2E`
- Factor: `Speed_kmh`
- Baseline: `0`
- Treatments: `30|120|250|500`
- Metrics: `RRCConnectedProbability|BeamReselectionCount|MeanAccessLatency_ms`
- Wave: `C`
- Dependencies: `mobility_channel`

### F55 — Inter-cell initial-access interference

- Group: `E2E`
- Factor: `InterfererPowerOffset_dB`
- Baseline: `-20`
- Treatments: `-10|-5|0|5`
- Metrics: `RRCConnectedProbability|WrongCellRate|PRACHCollisionRate`
- Wave: `C`
- Dependencies: `multi_cell_waveform_interference`

### F56 — Runtime scaling

- Group: `SOFTWARE`
- Factor: `ScenarioScale`
- Baseline: `1beam_1ue`
- Treatments: `8beam_64ue`
- Metrics: `Runtime_ms|PeakMemory_MB|WaveformSamples`
- Wave: `A`
- Dependencies: `none`

### F57 — Seed and parallel reproducibility

- Group: `SOFTWARE`
- Factor: `ExecutionMode`
- Baseline: `serial`
- Treatments: `parallel`
- Metrics: `ArtifactDigestMatch|MetricDifference|EventOrderDifference`
- Wave: `A`
- Dependencies: `none`

### F58 — Two-step RA capability gate

- Group: `EXTENSION`
- Factor: `RequestedProcedure`
- Baseline: `four_step`
- Treatments: `two_step`
- Metrics: `PlanningRejectRate|WaveformGeneratedCount|FallbackCount`
- Wave: `C`
- Dependencies: `two_step_not_implemented`

### F59 — CFRA/BFR/SUL capability gates

- Group: `EXTENSION`
- Factor: `RequestedProcedure`
- Baseline: `four_step`
- Treatments: `cfra|bfr|sul`
- Metrics: `PlanningRejectRate|WaveformGeneratedCount|FallbackCount`
- Wave: `C`
- Dependencies: `extensions_not_implemented`

### F60 — NTN/RedCap capability gates

- Group: `EXTENSION`
- Factor: `RequestedProcedure`
- Baseline: `four_step`
- Treatments: `ntn|redcap|eredcap`
- Metrics: `PlanningRejectRate|WaveformGeneratedCount|FallbackCount`
- Wave: `C`
- Dependencies: `extensions_not_implemented`

### Statistical treatment

- Use Wilson confidence intervals for ordinary binomial probabilities.
- Use one-sided exact Clopper-Pearson upper bounds for zero-event false-alarm/false-grant cases.
- Use McNemar tests for paired binary success/failure outcomes.
- Use paired bootstrap confidence intervals for latency, power, energy, SINR, timing error, runtime and memory.
- Use Holm correction within related hypothesis families.
- Report treatment-minus-baseline absolute effect and a predefined practical threshold.
- Do not equate non-significance with equivalence; an equivalence claim requires a predefined margin and appropriate interval.
- Return `inconclusive` when trials/errors are insufficient. Never remove the point.

Evaluate every row of `initial_access_impact_acceptance_rules.csv` and write 90 rule rows.

## Required impact CSVs and figures

- `initial_access_impact_run_manifest.csv` — minimum 1 rows
- `initial_access_impact_raw_trials.csv` — minimum 720 rows
- `initial_access_impact_operating_points.csv` — minimum 120 rows
- `initial_access_impact_pairwise_effects.csv` — minimum 300 rows
- `initial_access_impact_rule_evaluation.csv` — minimum 90 rows
- `initial_access_impact_ssb.csv` — minimum 50 rows
- `initial_access_impact_type0_sib1.csv` — minimum 50 rows
- `initial_access_impact_prach.csv` — minimum 50 rows
- `initial_access_impact_beam.csv` — minimum 20 rows
- `initial_access_impact_power.csv` — minimum 30 rows
- `initial_access_impact_contention.csv` — minimum 30 rows
- `initial_access_impact_rrc.csv` — minimum 20 rows
- `initial_access_impact_runtime.csv` — minimum 20 rows
- `initial_access_impact_interactions.csv` — minimum 20 rows
- `initial_access_impact_summary.csv` — minimum 60 rows
- `initial_access_impact_image_semantic_audit.csv` — minimum 30 rows

- `ia_impact_ssb_periodicity.png` from `initial_access_impact_ssb.csv`
- `ia_impact_beam_count.png` from `initial_access_impact_ssb.csv`
- `ia_impact_ssb_snr.png` from `initial_access_impact_ssb.csv`
- `ia_impact_cfo_timing.png` from `initial_access_impact_ssb.csv`
- `ia_impact_pbch_dmrs.png` from `initial_access_impact_ssb.csv`
- `ia_impact_type0_coreset.png` from `initial_access_impact_type0_sib1.csv`
- `ia_impact_searchspace0.png` from `initial_access_impact_type0_sib1.csv`
- `ia_impact_pdcch_al.png` from `initial_access_impact_type0_sib1.csv`
- `ia_impact_sib1_mcs.png` from `initial_access_impact_type0_sib1.csv`
- `ia_impact_sib1_payload.png` from `initial_access_impact_type0_sib1.csv`
- `ia_impact_prach_format.png` from `initial_access_impact_prach.csv`
- `ia_impact_prach_scs_cfo.png` from `initial_access_impact_prach.csv`
- `ia_impact_restricted_set.png` from `initial_access_impact_prach.csv`
- `ia_impact_zcz.png` from `initial_access_impact_prach.csv`
- `ia_impact_msg1_fdm.png` from `initial_access_impact_prach.csv`
- `ia_impact_ro_density.png` from `initial_access_impact_prach.csv`
- `ia_impact_ssb_ro_ratio.png` from `initial_access_impact_prach.csv|initial_access_impact_beam.csv`
- `ia_impact_ue_load.png` from `initial_access_impact_contention.csv`
- `ia_impact_preamble_pool.png` from `initial_access_impact_contention.csv`
- `ia_impact_power_ramping.png` from `initial_access_impact_power.csv`
- `ia_impact_target_power.png` from `initial_access_impact_power.csv`
- `ia_impact_backoff.png` from `initial_access_impact_contention.csv`
- `ia_impact_response_window.png` from `initial_access_impact_contention.csv`
- `ia_impact_capture.png` from `initial_access_impact_contention.csv`
- `ia_impact_msg3_harq.png` from `initial_access_impact_rrc.csv`
- `ia_impact_rrc_messages.png` from `initial_access_impact_rrc.csv`
- `ia_impact_e2e_snr.png` from `initial_access_impact_operating_points.csv`
- `ia_impact_runtime_scaling.png` from `initial_access_impact_runtime.csv`
- `ia_impact_effect_forest.png` from `initial_access_impact_pairwise_effects.csv`
- `ia_impact_family_summary.png` from `initial_access_impact_summary.csv`

## Required runner APIs

Implement these production entry points:

```matlab
result = sixgr.phy.ia.runInitialAccessPhaseValidation( ...
    'VectorRoot', fullfile(pwd,'tests','vectors','initial_access'), ...
    'OutputDir', fullfile(pwd,'artifacts','initial_access_phase'), ...
    'SeedList', [11 23 47 89], ...
    'ConfidenceLevel', 0.95, ...
    'Strict', true);

impact = sixgr.phy.ia.runInitialAccessImpactAnalysis( ...
    'ExperimentMatrix', fullfile(pwd,'tests','vectors','initial_access','initial_access_impact_experiment_matrix.csv'), ...
    'OutputDir', fullfile(pwd,'artifacts','initial_access_impact'), ...
    'SeedList', [11 23 47 89 131 197], ...
    'ConfidenceLevel', 0.95, ...
    'Strict', true);
```

Both runners must return `Passed=false` when any mandatory test, operating point, artifact, independent vector or dependency is failed, skipped, blocked or incomplete.

## Exact execution commands

```bash
python tests/vectors/initial_access/verify_initial_access_vector_pack.py
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*SSB*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PBCH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*MIB*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*SIB1*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PRACH*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*RandomAccess*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*RRCSetup*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.ia.runInitialAccessPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','initial_access'),'OutputDir',fullfile(pwd,'artifacts','initial_access_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/initial_access/verify_initial_access_artifacts.py artifacts/initial_access_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.ia.runInitialAccessImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','initial_access','initial_access_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','initial_access_impact'),'SeedList',[11 23 47 89 131 197],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/initial_access/verify_initial_access_impact_artifacts.py artifacts/initial_access_impact
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

## Required artifact inspection

Do not stop after files exist. Programmatically and visually inspect:

- SSB timeline contains every active configured candidate and no inactive SSB.
- SSB grid shows exact PSS/SSS/PBCH/DM-RS/zero ownership and no overlap.
- Blind-search plot uses searched hypotheses, not transmitted candidate coordinates.
- Type-0 plot matches decoded MIB and table row.
- SIB1 grid matches decoded DCI assignment and contains no synthetic gap.
- PRACH map shows all time/frequency occasions and exact selected RO.
- Correlation plot has correct transmitted/detected preamble and timing peak.
- Power plot reconciles requested/applied/measured waveform power.
- Timer plot uses exact inclusive/exclusive boundaries.
- RA state plot stops at the fault stage for negative cases.
- RRC timeline shows both endpoints enter CONNECTED only at SetupComplete.
- BLER/success/latency plots contain all mandatory operating points and confidence intervals.

Use both supplied verifiers. Do not edit a verifier to hide an implementation failure.

## Completion blockers

- any SSB grid clamp/retry remains in strict dependencies
- unsupported Lmax or SSB index is coerced or clipped
- only one SSB is emitted when multiple bitmap positions are active
- TX/RX/frame/Type0 use different SSB case plans
- known timing/cell/index/beam information enters the strict receiver
- Type-0 remains fixed to 30 kHz/index zero/AL4/one candidate/32 bits
- custom SIB1 anchor header/profile remains in strict execution
- SIB1 receiver accepts expected tree or hash inputs
- a synthetic SSB-to-SI waveform gap remains
- configured SIB1 grant competes with decoded DCI
- PRACH config-index coverage is incomplete
- restricted-set or root/cyclic-shift behavior is untested for declared tuples
- only one PRACH occasion is owned by the RA path
- RA-RNTI or SSB-to-RO association is reconstructed from unrelated configuration
- Msg2/Msg3/Msg4 use fixed +1/+2/+3 slots
- pathloss comes from configured SNR
- power requested is not applied and measured on the waveform
- collision/capture is represented only by a boolean fault flag in the final implementation
- RA success is declared before RRCSetupComplete
- unsupported extension falls back to four-step
- same-Toolbox output is labelled independent
- a mandatory point is incomplete
- one of 47 required CSVs or 50 required PNGs is absent
- either artifact verifier returns nonzero
- MATLAB/5G Toolbox is unavailable or a mandatory test is skipped/blocked

## Definition of COMPLETE

You may return `COMPLETE` only when all of the following are true:

- all 16 findings are closed for `fr1_four_step_ra_rrc_connection_strict_r18`
- all 52 mandatory MATLAB tests execute and pass
- all supplied vectors pass and missing independent SIB1/PRACH sources have been added with provenance
- multi-SSB blind acquisition works without oracle timing/index
- all bounded Type-0 rows execute as valid or reserved
- SIB1 is decoded through independent normative ASN.1 and installed causally
- four-step RA supports real retries, power, timers, Msg3 HARQ and multi-UE contention
- RRCSetupComplete completes the connection and synchronizes UE/gNB state
- all 720 impact experiments execute
- all 90 rules have evidence and pass or produce the exact allowed statistical conclusion
- all 31 base CSVs, 20 base PNGs, 16 impact CSVs and 30 impact PNGs pass their contracts
- both Python artifact verifiers return exit code zero
- the complete repository MATLAB regression remains passing
- unsupported extension profiles remain explicit and have zero fallback count

## Required Codex response format after each implementation iteration

1. Iteration/task IDs and finding IDs addressed
2. Production files added, modified and deleted
3. Technical design decisions and any standards interpretation
4. Legacy shortcuts removed
5. Tests added or changed
6. Exact commands executed
7. MATLAB and 5G Toolbox versions
8. Test counts: run/passed/failed/skipped/blocked
9. Vector counts and mismatch counts
10. Generated CSV names and row counts
11. Generated PNG names, dimensions and SHA-256 values
12. Artifact-verifier outputs and exit codes
13. Impact experiments/rules completed
14. Remaining failures or real technical dependencies
15. Final status: COMPLETE, FAIL or BLOCKED

Do not answer with a plan only. Begin by creating the canonical profile/context, adding failing tests for IA-002/IA-003/IA-004/IA-006/IA-009/IA-010/IA-011, and then edit the production source until those tests and all dependent stages pass.
