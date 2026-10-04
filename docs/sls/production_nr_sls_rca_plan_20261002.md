# Production NR-based SLS: root-cause and execution plan

Status: **in progress, not production-qualified**. This plan is for the general
LLS/SLS simulator, not AI 10.3.2. A 3GPP NR Release-18 baseline is the
standards-backed reference; proposed 6G features must retain separate study
labels. Passing component tests is not an accepted multi-cell result.

The retained 61-area Vienna parity inventory currently records 16 `not_wired`,
15 `unverified`, 16 `partial`, 12 `not_equivalent`, and only two narrow
component-verified entries. These labels identify audit work; Vienna legacy
models are not automatically NR obligations or interchangeable calibrations.

## Current evidence and root causes

| Priority | Requirement and root cause | Exact implementation surface | Closure evidence |
|---|---|---|---|
| P0 | The public calibrated SLS scenario has an empty `calibrationFile` and `calibrationSHA256`. `CalibratedLinkPHY` correctly rejects it, so no production BLER/HARQ result can be produced. The retained general DL/UL collection has 292/29,200 episodes, not qualified curves. | `simulator/configs/scenarios/sls_network_calibrated.yaml`; `+sixgr/+system/CalibratedLinkPHY.m`; `+sixgr/+system/+abstraction/{buildCalibrationFromTrials,validateCalibrationSources}.m`; waveform calibration runner | Independent waveform fit/validation populations for each exact MCS/rank/allocation/receiver/RF/HARQ-history key; no out-of-domain lookup; installed source hash and held-out error bounds. |
| P0 | The present calibration key hashes the *literal* grant PRB set, symbols, DMRS, frozen coding/resources and UCI allocation, plus TBS, rank, MCS, channel, RF and receiver identities. The retained pilot has only rank-1 QPSK/24-PRB DL and UL cases; finishing it would not cover changing 273-PRB rank-adaptive grants. Broadening lookup by dropping allocation fields would be scientifically unjustified without held-out invariance evidence. | `+sixgr/+system/CalibratedLinkPHY.m` (`calibrationKey`); `+sixgr/+calibration/{fitCollection,fitEffectiveSINR}.m`; `+sixgr/+system/+abstraction/{buildCalibrationFromTrials,assertSupportedSINRHistory}.m` | Inventory exact keys from frozen scheduler grants; establish waveform fit/held-out coverage for each key, or qualify an explicitly versioned equivalence class over allocation translations/shapes with independent validation. Reject unqualified class matches and retain exact grant/TBS in traces. |
| P0 | The original `+sixgr/+calibration` executor was SISO-only; a separate rank-two equal-dimension AWGN feature now has focused evidence, but neither path executes or retains an SLS frozen grant. Its source-row exporter previously checked a caller-supplied calibration key only by direction, and the package validator checked coding/ports but not the full allocation/profile digest. A fabricated exact SLS key could therefore be attached to a real but physically different episode. | `+sixgr/+calibration/{loadCampaign,executeEpisode,exportReferenceTrialRows}.m`; `+sixgr/+system/+abstraction/validateCalibrationSources.m`; a new grant-bound waveform-calibration adapter | Reject unproven full runtime keys now; then implement grant-bound waveform execution that records the exact issued PRB/symbol/DMRS/coding/UCI, channel/array/RF/receiver and HARQ history. Recompute the full runtime key from retained episode evidence during packaging; test deliberate rank/TBS/allocation/profile poisoning. Merely increasing the present pilot population cannot close this gap. |
| P0 | The retained 292-episode general calibration pilot cannot be treated as resumable after the current source edits: `loadCampaign` hashes the entire `+sixgr` implementation and schema catalogs into its scientific identity. A fresh frozen-source collection is required, or a separately justified and validated dependency-scoped hashing policy. | `+sixgr/+calibration/loadCampaign.m`; `results/calibration/nr_dl_ul_20261002_v5/receipt.json` | Exact identity check on a frozen source, append-only episodes and separate fit/held-out seeds; no mixed-source population. |
| P0 | The reusable calibrated-link fragment defaults causal SRS, DL CSI, and dynamic PUCCH to disabled, but the public 21-cell scenario now inherits `connected_causal_feedback_tdd.yaml` and enables them. Component and one-cell fixture tests do not prove that the complete scheduled feedback loop works in strict multi-cell execution. | `simulator/configs/system/{calibrated_link_abstraction,connected_causal_feedback_tdd,network_spatial_ideal_tdd,resource_reservations}.yaml`; `+sixgr/+system/{SystemLevelRunner,SLSDynamicPUCCH}.m`; `+sixgr/+system/+abstraction/{CausalSpatialFeedbackBuffer,CausalDLCSIFeedback,NetworkSpatialGrantProvider}.m` | One strict multi-cell run with generated CSI/SRS obligations, available/delivery clocks, rank/PMI/CRI/SRI decisions, PUCCH/PUSCH selection, and completed HARQ; no fixture injection. |
| P0 | Explicit SLS SINR policy is not catalogued and `localResolveSINRModel` silently maps an unknown token to the explicit model. This can misstate the model used. | `simulator/configs/schema/core_parameter_catalog.yaml`; `+sixgr/+system/SystemLevelRunner.m`; config/SLS regression tests | Invalid policy rejected before any grant or primary row; canonical selected policy recorded and tested. |
| P0 | A long-lived MATLAB/WebGUI session caches the core YAML catalog forever, so edits to the catalog are not enforced until restart. This was reproduced when the newly added invalid SINR policy passed validation in the already-running MATLAB engine. | `+sixgr/+config/loadCoreCatalog.m` | Re-reading the edited catalog in the same MATLAB session changes validation; unchanged content reuses the parsed cache. |
| P0 | The activity-power SINR path is a wideband scheduling estimate, not a per-grant/per-RE interference or receiver measurement. The calibrated provider does use overlapping scheduled grants but labels common-channel interference and RF/array qualification false. Cross-link overlap is rejected. | `SystemLevelRunner.m` (`localBuildExplicitSINRState`); `+sixgr/+system/+abstraction/NetworkSpatialGrantProvider.m`; `+sixgr/+system/GeometryEngine.m` | For DL/UL, compare predicted per-resource SINR against independent small-network waveform cases; preserve separate modeled, measured and pre-schedule budget columns. Explicitly reject unsupported dynamic-TDD cross-link cases until BS–BS/UE–UE channels exist. |
| P0 | Resource/control qualification is incomplete across a production network. Existing focused tests cover common reservations, dynamic UCI and six physical PUSCH-UCI cases, but the latter explicitly says `statistical_qualification=0`. | `+sixgr/+system/{resolveSLSResourceReservations,buildSLSCommonChannelCalendar,SLSDynamicPUCCH,validateSLSPUSCHUCIReservation}.m`; PDCCH/PUCCH/PUSCH PHY | Every granted PRB-symbol has one owner; PDCCH, SSB/SIB1, CSI-RS, SRS, PUCCH and PUSCH reservations reconcile; noise-only DTX and signal-present UCI campaigns meet frozen confidence gates. |
| P1 | 3D geometry and TR 38.901 channel/array cases are partially verified. The network provider explicitly exports `ArrayQualified=false`, `RFQualified=false`; the 61-area Vienna parity checklist includes unverified/non-equivalent branches. Vienna-only legacy features are not automatically NR requirements. | `+sixgr/+system/GeometryEngine.m`; `+sixgr/+channel/TR38901Plus.m`; `+sixgr/+rf/AntennaArrayFactory.m`; `+sixgr/+system/+abstraction/NetworkSpatialGrantProvider.m` | Versioned 3GPP-domain pathloss/LOS/O2I/shadow/mobility tests, array/polarization power closure, beam/TCI cases and independent Vienna comparisons where model definitions match. Qualify each RF profile separately; assumed 7-GHz phase noise is not an instrument mask. |
| P1 | No accepted general S0 load calibration or paired 21-cell campaign/confidence intervals. A runnable component test or planned case table is not a result. | `+sixgr/+system/SystemLevelRunner.m`; traffic/load calibration runners; `+sixgr/+report/exportSLSOutputCatalog.m`; campaign driver | Freeze measured 20/50/70% load arrivals against S0, execute at least 30 independent paired drops per comparator, report confidence intervals, seed/source/config hashes and censored failures. |
| P1 | The existing S0 FTP3 bisection and resource-union accounting are under `+sixgr/+studies/+ran1ai1032`, so the general SLS has no study-independent load-calibration entrypoint. The calculation itself uses executed PRB-symbol union over an independent opportunity calendar and can be reused without changing its definition. | `+sixgr/+studies/+ran1ai1032/{calibrateSLSFTP3Loads,measureSLSResourceUtilization,executeS0FTP3CalibrationCase}.m`; new general `+sixgr/+system` API and regression | Move reusable measurement/calibration contracts into core SLS, retain compatibility wrappers, verify unchanged study tests plus general two-cell cases; never bind fixture-generated rates as accepted loads. |
| P1 | The public SLS receipt always has `PrimaryStudyAccepted=false`. This is honest today, but a future qualified case needs an evidence-based acceptance evaluator rather than a hard-coded success claim. | `+sixgr/+system/runConfiguredSLS.m`; `+sixgr/+report/exportSLSOutputCatalog.m` | Acceptance true only after every configured calibration, channel/RF/control, population and artifact-integrity gate passes; development fixture and missing evidence remain false. |

## Execution sequence

1. **Freeze and validate policy.** Reject unknown SINR modes and contradictory channel/control settings before execution. Preserve input YAML, resolved config, seeds and hashes. This is the first code repair in this plan.
2. **Make the NR baseline executable.** Define a separate strict TDD multi-cell baseline YAML with explicit Type-0/SIB1, timing, BWP, traffic, feedback and reservation policy. Keep optional waveform and calibrated-abstraction backends distinct; no implicit calibration or proxy switch.
3. **Close causal network operation.** Run two-cell then 21-cell DL/UL/mixed cases. Qualify per-resource interference, CSI/SRS delivery, adaptive rank, HARQ and UCI resource ownership. Every modeled quantity must be labeled as such.
4. **Qualify calibration.** Collect independent physical first-transmission and conditional HARQ populations over the *actual* runtime domain. Fit and validate effective-SINR curves without extrapolation; install only hash-matched curves. This is a compute campaign, not a code-only gate.
5. **Qualify channel, RF and traffic.** Verify TR 38.901 domain and array/polarization assumptions, label or reject unqualified RF branches, calibrate S0 loads and freeze paired seeds.
6. **Accept and publish.** Execute paired network drops, verify confidence intervals and file-level/UE/cell metrics, then run focused guards and repository `testAll` on the frozen source. A failed or unsupported branch stays `BLOCKED`, not a synthetic primary row.

Minimum maintained focused guards: `testSimulationModeDispatch`, `testSLSInterferenceMuting`, `testSLSNetworkSpatialProvider`, `testSLSNetworkChannelSampling`, `testSLSDLCSIFeedback`, `testSLSMeasuredSRSConsumer`, `testSLSDynamicPUCCH`, `testSLSNativePUSCHUCIReception`, `testSLSResourceReservations`, `testSLSCalibrationSourceIntegrity`, `testSLSOutputCatalog`, `testSchedulerGrantConsistency`, `testE2E_FastVsTruth`, and `testE2E_TruthPacketSemanticCampaign`.

Reference boundaries: 3GPP NR TS 38.211/212/213/214/215 define the NR air-interface baseline, while TR 38.901 defines channel-model assumptions and validity domains. This simulator's 6G proposals, ideal delayed CSI/SRS, and assumed phase-noise profiles are study assumptions, not agreed 3GPP 6G requirements.

## File-level implementation plan and release gates

The dependency order below is deliberate. A completed MATLAB run is not a
qualified SLS result, and no development calibration or synthetic grant row
may satisfy a later gate. The NR baseline and each optional 6G study feature
must have separate resolved-config and result classifications.

| Gate | Root cause / action in production files | Focused evidence required before advancing |
|---|---|---|
| G0: freeze and config | `loadCoreCatalog.m`, `validateConfig.m`, the core catalog and the SLS scenario must reject unknown SINR/interference policy, contradictory policy, bare TDL/CDL profiles, and an absent calibration identity. Freeze resolved YAML, source hash, seeds, MATLAB/toolbox versions. | Same-session catalog-edit regression; `testConfig`, `testSimulationModeDispatch`, strict-proxy and channel-profile guards. Unknown policy must fail before a grant. The 21-cell YAML remains a template while its calibration path/hash are blank. |
| G1: exact PHY calibration domain | Inventory literal scheduler keys from `SystemLevelRunner.m`/`CalibratedLinkPHY.m`, including direction, allocation, MCS, rank, TBS, receiver, RF and HARQ history. Extend `+sixgr/+calibration` and waveform runners to collect first-TX and conditional retries across the actual domain. Fit and validate separate seeds in `+sixgr/+system/+abstraction`; do not generalize allocation keys without held-out invariance proof. | A source-frozen package with SHA256, independent fit/validation populations, confidence bounds, reference-SINR domain closure and zero missing runtime keys. The current pilot has 292/29,200 episodes committed and all 336 rows in its conditional-population audit marked insufficient; it does **not** satisfy this gate. |
| G2: causal network loop | Complete scheduled CSI/SRS publication, delivery and consumption through `CausalDLCSIFeedback.m`, `CausalSpatialFeedbackBuffer.m`, `NetworkSpatialGrantProvider.m`, `SLSDynamicPUCCH.m` and `SystemLevelRunner.m`. Assert per-UE/slot resource ownership and frozen-grant identity through PUCCH/PUSCH and HARQ. | Two-cell then 21-cell DL/UL/mixed focused traces with CSI-RS/SRS producer, observation, availability and delivery slots; rank/PMI/CRI/SRI chosen from delivered evidence; UCI disposition and no unresolved grant. Ideal delayed feedback remains labeled as an SLS modeling assumption. |
| G3: resource and interference | Use `buildSLSCommonChannelCalendar.m`, `resolveSLSResourceReservations.m`, `buildResourceOpportunityTable.m`, `measureResourceUtilization.m` and `NetworkSpatialGrantProvider.m` to reconcile every scheduled PRB-symbol, common/control reservation, transmitter PSD, noise and overlapping interferer. Implement or explicitly reject cross-link and common-control interference cases rather than reusing shared-data covariance. | Resource-union accounting equals executed grants; idle opportunities stay in denominator; no PUCCH/PUSCH double booking; independent small-network waveform-vs-model SINR/power comparison over matched grants and seeds. Keep modeled SINR distinct from receiver-measured SINR. |
| G4: RF/arrays | Qualify `GeometryEngine.m`, `TR38901Plus.m`, `AntennaArrayFactory.m` and the network provider over configured 3D placement, LOS/O2I/shadow/mobility, polarization, beams, RF impairments and power planes. An assumed 7-GHz phase-noise CPE/ICI profile is a sensitivity case, not a measured oscillator mask. | Matched-domain geometry/array power checks, RF-on/off/PT-RS cases, independent waveform or analytical references and explicit validity-domain assertions. Do not set `ArrayQualified`/`RFQualified` true until these checks exist. |
| G5: S0 load and paired network | Move the generic FTP3 bisection contract from `+studies/+ran1ai1032` into `+system`, keeping the study API as a compatibility wrapper. Execute S0 with the G1 dataset and G2–G4 frozen assumptions; measure 20/50/70% PRB-symbol use from grants and an independent calendar. Bind each frozen rate/seed bundle to paired cases. | Minimum independent-drop policy, saved iterations, measured tolerance, unchanged backend/calibration/config hashes, then at least 30 paired 21-cell drops per comparison and paired bootstrap intervals. No fixture-derived rate is accepted. |
| G6: publication | Add a campaign-level acceptance evaluator to `runConfiguredSLS.m` and `exportSLSOutputCatalog.m` only after G1–G5. Keep model-estimate and waveform-truth tables separate; publish UE/cell/file, HARQ, rank, CSI/SRS, reservation, interference, RF and confidence-interval artifacts with source hashes. | Recompute every plotted value from its CSV; verify no fallback/synthetic primary rows and no out-of-domain BLER lookup. Run focused E2E/export guards and final-source `testAll`; report blocked branches rather than marking them passed. |

Immediate execution slice: verify the newly extracted core resource-union test,
S0 evidence gate, source-key rejection tests and exact calibration-key grant
export. Then build the grant-bound waveform calibration adapter before
collecting a new production population; do not spend compute completing the
old SISO pilot as though it covered rank-adaptive 21-cell SLS. The ongoing
`testAll` began before those edits and is diagnostic only; it cannot certify the
final source snapshot. Do not launch a 21-cell performance campaign before G1
and the integrated G2–G4 gates pass.

## Execution checkpoint — 2026-10-02

- Implemented catalog-backed `system.sinrModel` and
  `channel.interferenceModel` validation. Unknown policy names now reject
  instead of silently selecting `explicit_activity_power_sum`; conflicting
  simultaneous policy declarations also reject before scheduling.
- Repaired `loadCoreCatalog` so long-lived MATLAB sessions compare current
  catalog content and reparse on change; the earlier cached policy remained
  stale during this investigation.
- Made the two-cell interference regression explicitly data-only and gave it
  a configured DCI 1_1 feedback-timing list. Its two waveform runs now
  schedule both cells and pass busy-versus-muted interference assertions.
- Focused `testConfig`, `testSimulationModeDispatch`, and
  `testSLSInterferenceMuting` passed in the active MATLAB R2026a session.
  The additional conflicting-policy assertion was added after that pass and
  still needs runtime verification. An E2E regression tool call timed out
  while MATLAB continued using CPU, so its result is **unknown**, not a pass
  or failure. This does **not** qualify the complete SLS; `testAll` and
  production calibration/paired-network campaigns remain open.
- The old general calibration pilot is *not* resumed across these code and
  catalog edits. Its source-wide identity is intentionally fail-closed.
- Added `connected_causal_feedback_tdd.yaml` as a reusable SLS-only overlay
  enabling ideal-delayed DL CSI and UL SRS, dynamic HARQ/CSI/SR PUCCH and
  causal UCI-on-PUSCH selection. Added a separate 4-GHz/100-MHz, 21-cell,
  4x4 TDD scenario with an explicit TDL-A/30-ns fading profile. Its
  calibration path/hash are intentionally blank: this is a validated
  configuration template, **not** a runnable or accepted study result.
- `testSimulationModeDispatch` now checks the connected scenario's mode,
  21-cell topology, feedback/RS/UCI switches, reservations and test-fixture
  exclusion. It passes after setting CP-OFDM for the rank-4 UL configuration.
  The existing one-cell network automatic-UCI integration test also passes,
  but uses a clearly labeled development BLER fixture; two-cell provider
  mathematics and component feedback tests pass separately. A strict
  integrated 21-cell calibrated run is still unproven.
- Added core `+sixgr/+system/measureResourceUtilization.m` and a focused
  regression for exact executed-PRB-symbol union against independent
  opportunity rows. The study-specific entrypoint now delegates to the
  core function and maps its historical error identifiers; its regression
  asserts byte-for-byte equivalent result structs. These edits are not yet
  runtime-tested because the repository-wide suite owns MATLAB. That suite
  began before these edits and is diagnostic only; final-source focused
  and full validation remain required. Neither fixture rates nor
  unqualified PHY may become an accepted S0 calibration.
- Added exact calibration-key SHA256 to modeled grant traces and the full
  key JSON/SHA256 to missing-curve failures. This makes actual scheduler
  key coverage auditable without weakening exact-match lookup or creating
  synthetic primary rows. Focused calibration/grant-export regressions are
  staged but not yet runtime-verified while the earlier suite is active.
- Extracted the S0 iteration evidence gate to core
  `+sixgr/+system/validateS0LoadIteration.m`. The existing study load
  calibrator calls it through a compatibility error mapping. It rejects
  wrong backend, development calibration, changed seeds, missing exact
  grant/opportunity/arrival tables, fallback, non-FTP3 traffic and
  unavailable UL decodes. `testSLSLoadIterationEvidence` was added, but
  these latest edits still require focused MATLAB verification on the
  final source after the earlier suite releases the engine.
- Audited the waveform-to-SLS calibration bridge. The calibration executor
  now has a focused rank-two AWGN feature but still does not retain an SLS frozen grant. Added
  export-time coding/rank/TBS/port/receiver checks and fail-closed rejection
  of unproven full SLS allocation/profile key fields; the package source
  validator applies the same guard against manually forged CSV rows, and
  the production packager now requires the complete runtime key schema
  before writing a MAT package.
  `testLinkCalibrationResume` now poisons rank, TBS and the full-key claim.
  This is an integrity repair, **not** the missing multi-layer grant-bound
  calibration executor, and it still needs MATLAB verification.
- Repaired the direct LLS AWGN channel helper's MIMO dimension contract:
  its old unit `TrueChannelGrid` was always 1x1 even for a multi-column
  waveform. It now publishes an explicit equal-dimension identity matrix
  per RE and rejects unsupported rectangular TX/RX dimensions. The
  `testLLSAWGNMIMOIdentity` regression is staged. This enables correct
  4x4 AWGN reference evidence but does not itself implement multi-layer
  fading-feature extraction or frozen-grant calibration.

## Next implementation work package: waveform calibration bridge

The remaining G1 failure is not a population-size problem alone. The code
currently has **two different physical execution contracts**:

1. `+sixgr/+calibration/executeEpisode.m` calls
   `+sixgr/+lls/runTransportBlock.m` and retains a real TB/CRC/HARQ outcome.
   Rank-one SISO keeps its original feature; rank-two equal-dimension AWGN
   now uses an executed per-layer feature. Neither path receives an immutable
   SLS grant, and neither can prove a full network calibration key.
2. `+sixgr/+system/+waveform/replayGrant.m` can bind an issued SLS grant to
   PDCCH and PDSCH/PUSCH waveform execution. Its AWGN helper now uses the
   occupied-RE noise plane, but returned evidence still lacks the
   per-data-RE applied channel/noise feature needed by the calibration fitter.
   Reusing its reported decoder/EVM SINR as that feature would mix different
   definitions and is prohibited.

Implement the bridge in this order, with each step fail-closed:

| Step | Production edit | Required proof |
|---|---|---|
| G1a | Add a grant-bound physical episode entrypoint beside `executeEpisode.m`: pass the frozen grant and original TB through real Tx/channel/Rx, retain each RV attempt, stop on CRC success, and hash the exact grant, TBS, allocation, coding, UCI and precoder used. | Poisoned grant/TBS/RV/precoder tests reject before packaging; independent CRC and soft-buffer assertions remain unchanged. |
| G1b | Expose the **applied**, per-data-RE channel matrix and grid-domain noise from the executed waveform. For multi-layer codewords compute a separately labeled per-layer linear SINR feature using the actual applied precoder and desired/inter-layer/noise covariance; never call it measured receiver SINR. Reconcile occupied-RE and sample-domain AWGN with a matched-seed equivalence test. | SISO identity agrees with the existing feature; 2-by-2 and 4-by-4 orthogonal/ill-conditioned cases agree with independent matrix calculations, preserve total power, and do not use scalar fading estimates. |
| G1c | Recompute `CalibratedLinkPHY.calibrationKey` from retained execution evidence inside the packager, not a caller-supplied label. Preserve literal allocation identity until translation/shape equivalence is independently validated. | Rank, PRB, symbol, DMRS, RF/channel/receiver, TBS and UCI poisoning all reject. No legacy SISO row can claim a full network key. |
| G1d | Freeze source/config/seeds; inventory exact keys from the connected scheduler; collect fitting and held-out waveform populations for the keys actually issued, including conditional retries. | Every installed key has independent confidence/domain evidence and zero extrapolated lookups; unmatched grants fail without primary fallback rows. |

Only after G1a-G1d should the 21-cell template receive a nonempty
`calibrationFile`/SHA. The current `292/29,200` SISO pilot remains development
evidence and must not be relabeled or copied into that production package.

The repository-wide suite launched earlier on 2026-10-02 is still running
against an older source snapshot. It is diagnostic, not final verification of
the AWGN MIMO or calibration-provenance edits. Run the new focused guards,
then the AGENTS.md-required final-source tests and `testAll` after that
engine releases the machine; do not start a competing MATLAB process while
memory is constrained.

### G1b implementation checkpoint

`+sixgr/+calibration/extractAppliedSpatialSINR.m` now forms a separate
multi-layer calibration feature from the **executed** layer/port symbols,
constant applied precoder, per-RE channel matrix and grid-domain noise.
It checks that the claimed precoder reproduces the transmitted port symbols,
then computes LMMSE or ZF per-layer SINR with inter-layer interference in the
denominator. Varying-PRG, hybrid-element and transform-precoded UL cases
reject rather than borrowing a wideband feature. `loadCampaign.m` requires
the feature name to agree with rank and receiver; `executeEpisode.m` keeps
the original SISO feature unchanged and uses the new feature for MIMO.
`testCalibrationSpatialFeature` covers two-layer identity/coupled channels
and poisoned precoder, RE mapping, and noise cases.
`testCalibrationMIMOEpisode` additionally requests actual coded 2-by-2
PDSCH and PUSCH AWGN episodes with practical DMRS estimation and checks
their retained per-layer features. Both tests are registered in `testAll` but have not run
on the final source yet.
`run_link_calibration.m` now rejects an episode before committing it if the
executed feature identity differs from the campaign YAML's frozen
`sinr_feature`; a channel-dimension or receiver-path regression therefore
cannot silently populate the wrong calibration family.
`configs/calibration/nr_dl_ul_rank2_feature_smoke.yaml` declares a small
DL/UL rank-two integration population with the new feature token. Its
one-trial roles and single RV are explicitly diagnostic and cannot meet the
2,000-conditional-trial gate or authorize production SLS lookup.

The rank-two smoke and its focused tests passed later in the checkpoint below.
It does not yet satisfy G1a/G1c: the episode is still not bound to
an immutable network grant, varying-PRG/array/RF cases are not supported,
and no qualified MIMO or full SLS calibration package has been collected.

### General SLS waveform replay AWGN correction (staged)

The frozen-grant replay path in
`+sixgr/+system/+waveform/replayGrant.m` still used a local
`mean(abs(time_waveform).^2)/SNR` noise rule, whereas direct LLS uses the
calibrated occupied-RE grid Es/N0 primitive. This made replay BLER curves
depend on cyclic prefix and inactive FFT-bin occupancy. The replay data and
PDCCH paths now call `sixgr.phy.waveform.addOccupiedREAWGN` with energy from
the executed occupied symbols and the executed OFDM Nfft/windowing. They
retain the grid/sample variance and reference-plane provenance. The local
sample-average helper was removed. Frozen-grant DL and received-DCI UL
tests now assert the applied Es/N0 equation. This is a necessary G1b
cross-path repair, **not** qualified equivalence yet: focused MATLAB tests
and independent matched-seed noise/BLER comparisons remain required.

The repository-wide suite that was already running before this edit is a
pre-edit diagnostic snapshot. Its outcome must be preserved, but it cannot
validate this AWGN change; run focused replay/LLS checks and a new frozen-
source `testAll` after the current MATLAB evaluation finishes. No
`+sixgr/+studies/+ran1ai1032` or `configs/tdoc` files were changed for this
general-SLS correction.

The replay entrypoint now also accepts separate optional PDCCH-noise,
data-noise and fading-channel seeds. The occupied-RE primitive uses a local
noise stream when a seed is supplied, and replay records both the requested
channel seed and whether a fading channel actually used it; an AWGN case
does not claim fading-seed application. This is required for future
independent grant-bound fit/held-out episodes. Focused AWGN and TDL replay
regressions are staged but **not yet MATLAB-verified** while the running suite
owns the desktop. Existing unseeded runtime calls retain their previous
global-stream policy.

Replay now also derives the transmitted TB bit count, per-codeword sizes,
SHA-256 and RV from the actual PDSCH/PUSCH transmitter output, checking
their consistency with the grant before recording them. These fields are
needed for the eventual G1a episode proof; they do not by themselves
constitute a qualified calibration or an accepted SLS result.
The replay channel initializer no longer substitutes a fixed 30.72-MHz
sample rate when transmitter OFDM metadata is unavailable. It now rejects
that condition and records the executed control/data sample rates. This
prevents silent sample-rate miscalibration in wideband cases; focused MATLAB
verification is still pending while the existing suite runs.

### 2 October final-source focused verification update

The older-source `testAll` was kept running as requested. It subsequently
terminated at `testTRSTruthContractInvariants` with a graphics
`Invalid graphics object` export error and an MCP output-stream error;
`logs/sls_required_testall_20261002.log` retains that failure. It does not
validate the latest source.

On the final source, `testCalibrationSpatialFeature` exposed and now guards
the ordered per-layer RE map. The first real rank-two episode revealed that
`+sixgr/+lls/validateConfig.m` incorrectly prohibited **all** AWGN MIMO as
though every AWGN case were the original SISO baseline. It now accepts only
dimensionally exact equal-port/equal-RX identity AWGN and rejects rectangular
or projected cases; `+sixgr/+lls/applyChannel.m` still enforces the waveform
column contract. The next episode exposed a separate error in
`runTransportBlock.m` and `runPDSCHTransportBlock.m`: both enabled the scalar
fast-AWGN receiver shortcut for rank two. They now enable it only for 1-by-1
rank-one AWGN; rank two uses the full receiver.

After those repairs, `testCalibrationSpatialFeature` and the coded DL/UL
`testCalibrationMIMOEpisode` passed in MATLAB R2026a. The required focused
`testLLSAWGNMIMOIdentity`, `testConfig`, `testLLS_DL`, `testLLS_UL`, and
`testLLS_ReferencePoints` also returned without errors. These are **narrow
physical and configuration passes**, not 2,000-trial populations or installed
SLS calibration. A final-source `testAll` remains required; the failed
older-source suite cannot substitute for it.

### Grant identity in waveform calibration replay (staged)

Source review found that payloadless `replayGrant` normalized PDSCH/PUSCH
RNTI and scrambling identifiers to `1` for TX caching, while the template
cache key omitted RNTI. Thus a scheduled UE's waveform could execute with
another physical scrambling identity even though its grant metadata still
named the scheduled UE. The general SLS replay now projects the grant RNTI
into the DL/UL PHY configuration, preserves the transmitter channel object
unchanged, includes UE/cell/scrambling identity in its template key, and
checks the transmitted RNTI against the scheduled grant. Explicit TB bits
are no longer silently zero-padded, truncated, or converted from nonbinary
values: MAC must form the exact TB before physical replay. Focused DL/UL
control-binding and frozen-grant tests now cover these identities and the
negative payload paths. Non-frozen grants bypass template/TX caching because
they lack a complete immutable physical-context key, and unserializable
frozen cache identities fail rather than falling back to a partial key.
The executed TX object is also checked against the grant's exact PRB set,
symbol allocation, rank and modulation, with those values retained in replay
evidence for a future grant-bound calibration packager.
These edits await MATLAB runtime verification after
the preserved older-source suite releases the engine; no SLS calibration
package is installed or qualified by this source-level correction.

### General S0 FTP3 load driver (staged, not an accepted rate)

The study-independent `+sixgr/+system/calibrateFTP3Loads.m` now takes a
baseline case table and externally supplied load policy. It requires distinct
drop IDs and seed bundles, checks the frozen base-config and link-calibration
hashes on every iteration, retains each request and runtime result, and uses
core executed-grant PRB-symbol union over the independent opportunity table.
Its frozen-rate receipt says `measured_baseline_load_converged_not_study_accepted`;
the returned `PrimaryStudyAccepted` remains false. A separate core test covers
the bisection and negative identity paths with private contract fixtures.
The core `validateS0LoadIteration.m` now rejects empty grant/opportunity/
arrival evidence, mismatched waveform versus calibrated grant roles, and
unqualified or differently hashed abstract grant decisions. The older
agenda-named regression fixture was updated outside its study folder to meet
this stricter common contract; no agenda implementation was changed.

These additions have passed static Code Analyzer checks only. The preserved
older-source `testAll` still owns MATLAB, so the new core/compatibility tests
and required final-source `testAll` have **not** yet run. The driver is not yet
wired to a public YAML campaign or a qualified BLER package, has no restart
resume, and has not produced accepted 20/50/70% rates or paired drops.

### 2026-10-03 evening repair reconciliation (not final acceptance)

The latest user instruction is to **not restart testAll**. Rerun affected
failed tests only. Historical requests for a final suite above do not
authorize a new full-suite launch now. No agenda-item implementation was
edited in this repair.

The seven failures in `sls_feedback_trs_followup_20261003.log` have passing
targeted reruns. Repairs cover common RA PT-RS configuration, consistent
64-element SSB/four-logical-port CSI/PDSCH configuration, recorded receiver
AGC gain compensation for TRS scoring, ideal-RF fixture authority, and
multicell desired-grant exclusion independent of vector orientation.
The final multicell run also rejects an actual late PUCCH reservation before
decoding the conflicting issued UL grant. Evidence:

- `logs/sls_seven_failures_repair_20261003.log`
- `logs/sls_master_and_multicell_repair_20261003.log`
- `logs/sls_multicell_reservation_repair_20261003.log`

Subsequent access verification passed `testMIBPDCCHConfigSIB1Derivation`
and `testRAStageCarrierSlotBinding` in
`logs/lls_access_failed_tests_20261003.log`. These confirm earlier staged
fixture repairs, not two newly discovered production fixes.
`testFourStepRARuntimeStageComposer` was repaired here and passes in
`logs/lls_ra_composer_type0_repair_20261003.log`: retain SSB index 3, reject
the original UL Type-0 slot 43, configure SearchSpaceZero 1/CORESET0 5,
check DL slot 41 and DM-RS/control noncollision, and execute all five RA
waveform stages through RRCSetupComplete. No timer or receiver guard was
weakened.

The content-hashed retained-log inventory is
`logs/sls_failure_inventory_20261003_all_retained/receipt.json` with companion
`failure_reconciliation.csv`. It covers 962 distinct test names and 68 names
with failure observations across historical full/focused runs. Within the
original 48-failure full-suite population, 15 have pass observations and 33
have no pass observation. These are **evidence inventory counts**, not
frozen-source acceptance: historical execution source hashes that were not
recorded remain unknown. The inventory parser's five Python tests pass.

#### Next P0 access review: independent Type-0 frequency and time coverage

Static comparison against TS 38.213 V18.8.0 clause 13 identified two additional
concerns, not resolved or qualified by the passing zero-offset fixtures:

1. `Type0PDCCHResolver.m` currently computes CORESET RB start as initial BWP
   start plus the table offset. Clause 13 defines that offset between the
   CORESET's lowest RB and the common RB overlapping the SSB's first RB.
   Trace received SSB/Point-A frequency authority through
   `deriveType0PDCCHFromMIB.m` and `SSBTimingResolver.m`; independently check
   nonzero offsets before changing the resolver and its consumers.
2. `localMonitoringOccasions` currently emits one slot per matching frame.
   For the implemented FR1 numerologies, clause 13 specifies monitoring in
   n0 and n0+1. Audit `MonitoringOccasions`, SearchSpace duration, ordinal
   selection and both transmit/receive consumers together; do not silently
   shift existing fixtures or claim two-slot coverage from one returned row.

Reference: https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

The disabled-access HARQ fixture's missing received UL timing authority also
remains open. Do not inject a fictitious decoded RAR or disable that guard.
Production SLS calibration, full interference/RF qualification and paired
study campaigns remain unaccepted.

### 2026-10-03 Type-0 frequency/calendar repair (focused acceptance)

The preceding static Type-0 findings have now been implemented in the core
resolver and MIB facade. This is an access/control repair, not complete SLS
or full NR conformance acceptance.

| Finding | Repair | Retained verification |
|---|---|---|
| CORESET start used BWP start plus table offset | Require the first SSB common RB relative to Point A; subtract the normative offset. Pass the actual carrier grid and SSB placement through `deriveType0PDCCHFromMIB`. Missing frequency context and out-of-BWP allocations remain errors. | 144 FR1 table vectors, nonzero offsets/BWP origin, and physical PBCH/SIB1 recovery with control at RB 15 |
| Calendar omitted n0+1 | Emit both ordered slots, including frame carry; set search-space duration to two slots and reduce its offset modulo the period. Hash the actual resolved calendar. | All 16 search-space rows, 256 SSB/SCS/search-space combinations, frame-boundary checks; actual sample-based SIB1 recovery at slots 40 and 41 |
| Existing ordinal 2 meant the next 20-ms period | Explicitly migrate authored YAMLs and access fixtures to ordinal 3; no hidden ordinal translation. The negative-occasion diagnostic now tests n0+2, since n0+1 is legal. | No-oracle receiver retains absolute slot 40; invalid TDD Type-0 slot 43 remains rejected |
| RA component fixture assumed RB-0 CORESET but implicitly centred SSB | Declare its Point-A-aligned SSB explicitly, retaining nonzero beam identity in the stage composer. Keep the RIV allocation guard. | Actual Msg1, Msg2, Msg3, Msg4 and RRCSetupComplete stage-composer test passes |

Thirteen distinct focused tests have pass evidence in:

- `logs/type0_frequency_pair_repair_20261003.log` (also retains the initial
  RA allocation failure before the explicit fixture repair)
- `logs/type0_access_regressions_20261003.log` (also retains the stale
  ordinal assertion, repaired and rerun in the following log)
- `logs/type0_migration_final_focused_20261003.log` (six tests, all pass)

The target-YAML audit additionally found that the 25-RB, 5-MHz TDD profile
needs CORESET0 index 1 / SearchSpaceZero 2 (`pdcch_config_sib1: 18`) to keep
24 control RBs inside the carrier at its declared SSB position. The H4
centred SSB gives a CORESET start of RB 126; its authored Msg2/Msg4 allocations
must use that frequency reference, not RB 0. Both exact-YAML resource checks
and the real full-band 273-RB / 64-element H4 broadcast-preparation check
pass in `logs/type0_target_yaml_repair_20261003.log`. This brings this repair
to 15 distinct tests with passing evidence. H4 waveform preparation is not
a claim of successful impaired-channel reception or full scenario completion.
No new complete scenario campaign or testAll was launched. The prior
48-failure inventory count has not been promoted to final-source acceptance.

Still open: the disabled-access HARQ fixture's causal UL timing ownership,
the remaining historical failures, broader Type-0/DCI applicability and
exact-scenario acceptance, production calibration and the other work
packages in the consolidated plan. Agenda-item files remain untouched by
this repair.

### 2026-10-03 received-timing HARQ and retained-result reconciliation

Only affected focused tests are authorized; no new `testAll` is running.
The audit now recognizes paired `FOCUSED_START` / `FOCUSED_PASS` or
`FOCUSED_FAIL` records as well as full-suite markers and timed focused
results. Nested probes, unpaired component markers and interrupted starts
do not become completed tests. Eight Python parser tests pass. The new
snapshot is `logs/sls_failure_inventory_20261003_paired_markers_v2`;
the earlier snapshots remain preserved.

Of the original 48 full-suite failures, 17 now have retained pass evidence
and 31 have none. The two additionally recognized passes are
`test5MHzSchedulerMinimumGrantPolicy` and `testLLSAvailabilityAggregation`.
This corrects inventory undercounting; it does not attribute historical
execution to the current source revision or declare final-source acceptance.

| Failure | Root cause and repair | Verification state |
|---|---|---|
| `testLLSCoupledTruthHARQRoundTrip`: `MissingReceivedULTiming` | The old fixture disabled access, so no decoded RAR could install initial TAG timing. The test now loads `validation/lls_received_timing_harq.yaml`: actual shared-waveform access followed by fixed high-rate bidirectional data. No timing guard or receiver evidence is bypassed. | `results/lls/coupled_truth_harq_roundtrip/20261003_214529_250`: actual Msg1 detection, Msg2, Msg3, Msg4 and RRCSetupComplete completed; RA strict acceptance passed. Shared SRS slot 30 passed and actual DL DCI was received at slot 31. The first DL CRC failed without a PHY crash; subsequent runtime/publication processing threw `MATLAB:nologicalnan`. The full test remains failed; exact NaN throw site is under investigation. |
| `testLLSHARQExercise`: selected K1 outside candidate set | Install K1=2 in the fixture's allowed list when selecting scalar K1=2. Add a negative assertion proving an uninstalled K1 still fails. | Static check passes; original test rerun pending. |
| `testPDCCH6GR`: FDD reciprocity on TDD carrier | Explicitly configure TDD reciprocity in the generic `pdcch_6gr_study.yaml` scenario instead of inheriting the contradictory FDD MIMO default. | Original test rerun pending; no duplex guard weakened. |

The two K1/PDCCH tests are being rerun serially, with retained artifacts
under `results/lls/harq_exercise` and `results/lls/pdcch6gr_regression`.
The current transcript destination is
`logs/harq_k1_pdcch_duplex_focused_20261003.log` (written after completion).
Failure checkpoints now include the original exception stack, rather than
only its identifier/message, to survive unavailable remote console output.

The timing-owner focused test already passed in
`logs/received_timing_harq_repair_20261003.log`. The connected MATLAB tool
call timed out after five minutes, but its MATLAB execution continued;
`bundle/air_interface/logs/run.log` and the retained RA stage log are the
live authorities. A tool timeout is not treated as a scenario failure or
permission to launch a duplicate. Agenda-item folders are unchanged by
this repair. Production calibration and overall SLS acceptance remain open.

### 2026-10-03 nullable PDCCH publication and follow-on fixture failures

The two-test batch completed with two failures, retained in
`logs/harq_k1_pdcch_duplex_focused_20261003.log`; neither is counted as a fix.

- The slot-31 runtime NaN failure has a matching isolated reproduction in
  `CoupledTruthRuntime.annotateControlReferenceTrialTableImpl`: nullable
  PDCCH admission metadata was cast directly to logical. Publication now
  requires explicit finalized=1 and selected=0 to classify a pre-TX block,
  preserving unknown fields and actual receiver execution. The original
  integrated test still needs its rerun. The focused disposition and joint
  admission tests pass in `logs/pdcch_nullable_admission_repair_20261003.log`.
- `testPDCCH6GR` passed configuration and waveform execution but exposed
  an invalid brace-based table-column rename in `runSingle.m`. This is
  replaced by `renamevars`, retaining component identity separately from
  execution identity. The original test is rerunning; final acceptance is
  not inferred from intermediate artifact creation.
- `testLLSHARQExercise` now installs its selected K1 and tests legal TDD
  occasions: control/data slot 4, ACK slot 6 and UL data slot 7. Its
  assertions distinguish DL K1 from UL K2 instead of requiring an
  inapplicable timing value on both directions. Actual waveform execution
  at 4 dB then produced four first-attempt ACKs and no retries. Evidence:
  `results/lls/harq_exercise/20261003_221555_001`. The exercise YAML now
  declares -12/-8/-4/4 dB points to test genuine failure/recovery; this
  expanded test awaits verification. No CRC outcome is forced and no
  statistical HARQ qualification is claimed.

The retained-inventory parser's eight Python tests also pass again.
No testAll was launched, no agenda-specific source was changed, and no
historical failure is closed based solely on these staged edits.

### 2026-10-03 22:34 IST focused verification checkpoint

Five tests passed in `logs/publication_harq_resume_focused_20261003.log`:
`testPDCCHExecutionDisposition`, `testPDCCHIntegratedRuntimeEvidenceGate`,
`testPDCCHGrantBindingEvidenceReport`, `testLLSHARQExercise` and
`testLinkCalibrationResume`. The last two are original full-suite failures.
The updated inventory is
`logs/sls_failure_inventory_20261003_focused_closure_v3`: **19 of the original
48 failures now have retained pass evidence; 29 have none**. This is still
historical/focused reconciliation, not final-source suite acceptance.

The physical HARQ exercise retained 41 attempts for 16 packets across
DL/UL and -12/-8/-4/4 dB. Both directions recovered packets through actual
retransmissions at -8 and -4 dB, exhausted retries at -12 dB, and decoded
first attempts at 4 dB. These small deterministic regression populations
do not qualify BLER curves. Calibration resume passed with four independent
retained episodes and `qualification=0`; source/checksum guards were not
relaxed. No source edits were made while that five-test batch executed.

Two additional publication repairs are implemented:

- `evaluateLLSRuntimeTruthContract.m` now distinguishes an explicit
  standalone PDCCH qualification objective from a builder-derived control
  gating objective when selecting the component-study contract. Tests
  retain strict integrated evidence, explicit standalone requirements and
  missing component-artifact failures.
- `runSingle.m` and `RunEvidenceLifecycle.m` agree on functional completion
  when the optional artifact contract is explicitly disabled by YAML.
  Unknown, required-but-disabled, executed-but-disabled, failed and
  nonqualified states are not promoted to qualified publication. Two tests
  pass in `logs/optional_artifact_lifecycle_repair_20261003.log`; the existing
  qualified pointer remains unchanged.

`testPDCCH6GR` has not yet passed as a whole. Its latest execution passed
the production rename but exposed a wrongly placed new test assertion:
component IDs belong to the auxiliary candidate table, not the canonical
trial table. The assertion is corrected and now also checks agreement with
the terminal finalization receipt. Its integrated rerun, and the shared
access/HARQ rerun after the nullable-publication fix, remain required.
No full testAll or statistical study campaign has been started.

### 2026-10-03 22:50 IST integrated result and remaining root causes

`testPDCCH6GR` completed in 725.76 seconds and still **fails**. Its retained
scenario now has `ResultOk=true`, zero required root failures and a functional
terminal `PASS`, while `PublicationQualified=false` remains explicit. This
verifies the identity rename and optional-contract finalization repairs; it
does not close the complete PDCCH regression.

Evidence: `logs/pdcch_shared_harq_integrated_repair_20261003.log` and
`results/lls/pdcch6gr_regression/20261003_223515_757/lls/pdcch6gr_runner_smoke/pdcch6gr_runner_smoke`.

| Open check | Source-level root cause / next change | Guard to retain |
|---|---|---|
| PDCCH false-alarm coverage | `runPDCCHStudyLLS.m` currently executes signal-present transmissions only. Its canonical trial table has neither an explicit H0 population nor `SignalPresent`/`TrialType` identity. `exportLLSReportingBundle.m` correctly excludes those rows from noise-only false-alarm denominators. Add configurable, actually executed no-signal observations, explicit population identity and separate H0/H1 reductions in the study receiver/metrics/export path. | Do not relabel wrong-candidate events under H1 as a noise-only population or fabricate zero false-alarm probability. Preserve the original coverage assertions. The missing P_FA/FAR/P_MD/P_D plot sources also require population-aware review. |
| Geometry hybrid antenna fixture | `testGeometryHybridAntennaDomain.m` omits CRI despite 32 CSI-RS resources, and its grant declares two ports against a four-port CSI basis. Author explicit fixture CRI/PMI and the correct selected CSI-port domain while retaining two data layers and 64 waveform elements. | Missing CRI and incompatible basis dimensions must still fail; this analytical fixture is not measured feedback. |
| PDSCH channel-estimation assertion | `testPDSCH6GR.m` still expects pilot reconstruction residual to be labeled channel NMSE. `PDSCHReceiver.m` correctly publishes `PilotReconstructionResidualRatio` separately and leaves independent NMSE unavailable without a reference. Assert those two contracts explicitly. | Do not restore the misleading residual-as-NMSE alias. Keep the independently scored receiver tests. |
| Waveform replay fixture | `testSystemLevelWaveformReplayEvidence.m` supplies incomplete installed timing, selects K2=1 for a full-slot UL allocation and only observes one TTI despite future grants. Use the existing canonical timing fixture and an observation window that can execute the delayed grants; then inspect the actual result before changing production. | Keep exact grant, decoder, DMRS, LLR, channel-estimation and export assertions. Timing rejection is not bypassed. |

The shared access/HARQ rerun started at 22:46:50 IST in
`results/lls/coupled_truth_harq_roundtrip/20261003_224650_986` and remains
in progress. Production and test source are unchanged during this integrated
batch. The inventory remains **19/48 with later pass evidence, 29/48 without**.
The common/control/reference interference implementation, production
calibration, RF/array qualification, S0 calibration and paired campaign are
still separate open SLS work packages; these fixture findings do not close them.

### 2026-10-03 23:25 IST scheduler rejection and antenna verification

The shared HARQ rerun ended after 1154.83 seconds at slot 39 with
`sixgr:SchedulerBase:InfeasibleGrantDCI`. The earlier slot-31 nullable
publication failure is cleared: this execution completed physical access,
received SRS and published subsequent data slots. It is still a failed
integrated regression, not scenario acceptance.

Root cause: exact PHY finalization correctly rejected a fixed-MCS new-data
grant (`initial_dl_code_rate_exceeds_actual_capacity`), but PF then tried to
construct DCI for it. RR had the same unchecked path. Both schedulers now
defer that explicit capacity rejection, release never-issued HARQ
reservations and retain PRB/CCE availability. PF rejects a spatial group
atomically rather than retaining a peer with the wrong MU normalization.
Other resource/configuration errors retain their strict failure path.
`HARQEntity.cancelTentativeTx` has an explicit `DCINotIssued` option to undo
the tentative NDI/epoch change; existing cancellation after issued control
retains its previous semantics. No TBS, MCS capacity limit or PHY decoding
outcome was altered to obtain a pass.

Seven focused tests pass in
`logs/scheduler_capacity_antenna_repair_20261003.log`:
`testSharedDLActualCodeRateFeasibility`,
`testSchedulerExactGrantFinalization`, `testSchedulerGrantConsistency`,
`testSchedulerHARQStateUnblockAndLineage`,
`testGeometryHybridAntennaDomain`, `testJointPDCCHRuntimeAdmission` and
`testJointPDCCHCandidateAdmission`. The capacity regression verifies repeated
rejection, a free HARQ process, no issued DCI/resource debit, preserved NDI
and a subsequent legal fixed-MCS28 grant. Its old resource expectation was
updated for the actual four-port CSI-RS row-4 configuration: G=1536 and
MCS26; an independent nrTBS/CRC calculation rejects MCS27 at the unchanged
capacity threshold.

The geometry fixture now distinguishes four logical CSI/PDSCH ports from
two transmitted layers over 64 elements. Missing CRI and a mismatched
two-port CSI basis remain negative tests. Explicit basis-times-PMI
composition and unit-total-power checks pass. This is configuration/precoder
verification, not physical measured-feedback or full array qualification.

The shared HARQ validation YAML now inherits the existing
`pdcch_joint_tdd_admission.yaml` policy. AL8 and actual control capacity are
unchanged; this addresses the retained UL starvation at coincident control
occasions. Resolved YAML binding and joint admission tests pass; the complete
shared HARQ rerun is still pending.

Inventory `logs/sls_failure_inventory_20261003_focused_closure_v4` records
**20/48 original failures with later pass evidence and 28/48 without**.
The PDCCH H0 population/export repair remains open. PDSCH evidence assertions
and the waveform replay fixture are staged; their original whole-test
verification is not yet complete. No testAll, production calibration or
paired campaign was launched, and agenda-specific folders were not edited.

At 23:25 IST, `testSystemLevelWaveformReplayEvidence` also passed (74.01 s),
retaining `results/sls/waveform_replay_evidence/20261003_232409_347` and
`logs/system_waveform_replay_repair_20261003.log`. Four TTIs contain four DL
attempts and one delayed UL attempt with receiver evidence. Unique delivered
throughput is zero; this test validates waveform replay/export wiring, not
a successful decoding operating point or production SLS performance.
The original-failure tally therefore advances to **21 with later passes,
27 without**; the v4 inventory above predates this last result.

At 23:28 IST, the whole `testPDSCH6GR` regression passed (98.56 s), including
the smoke runner/export assertions. Evidence:
`logs/pdsch_evidence_repair_20261003.log` and
`results/lls/pdsch6gr_runner_smoke/pdsch6gr_runner_smoke`.
The receiver's pilot-residual observable stays separate from independent
channel NMSE; missing independent reference data is not converted to NMSE.
Smoke publication is explicitly not release qualification.

The v5 reconciliation (`logs/sls_failure_inventory_20261003_focused_closure_v5`)
now records **22/48 original failures with later passing evidence, 26/48
without**. Nine focused tests passed in this batch. No MATLAB test remains
active at this checkpoint. The next integrated check is the original shared
HARQ test after scheduler rejection and joint-control admission repairs;
the independent-no-signal PDCCH population implementation remains open.

## 4 October focused repair checkpoint

The PDCCH study now executes explicit, independently seeded H0/H1 receiver
populations. H0 sends neither payload nor DMRS. Receiver polar dimensions are
resolved from installed payload/CRC configuration and candidate capacity,
not transmitted metadata. Misses and false alarms use their own populations;
summary counts and Wilson intervals are retained. Pilot reconstruction
residual is no longer mislabeled independent channel NMSE, and receiver
compute time is not represented as an air-interface delay. These component
and population checks pass, including poisoned transmitter metadata.

The original runner at
`results/lls/pdcch6gr_regression/20261003_235244_149/lls/pdcch6gr_runner_smoke/pdcch6gr_runner_smoke`
executed five H1 and five H0 observations at AL1/2/4/8/16. All signals decoded
and all H0 trials were correctly rejected. Functional finalization passed;
publication remains explicitly NOT_QUALIFIED. Five noise observations are
not statistical qualification. Its original test then exposed a stale
16-metric assertion: category F now has 17 entries. The repaired assertion
requires the exact catalog key set, retains every required observed metric,
and passed a component/artifact recheck against this retained physical run.
The recheck did not execute another scenario and is not frozen-source suite
acceptance. Evidence: `logs/pdcch_retained_artifact_recheck_20261004.log`.

`testTruthValidationControlCoverage` exposed two further production-path
failures. `prepareValidationConfig` passed the SLS speed range [3,30] into
single-link PRACH Doppler computation; it now binds PRACH to the validation
profile's explicit 70-Hz channel Doppler. `PRACHConfig` rejects unresolved,
negative and nonfinite link speeds instead of silently selecting an endpoint
or replacing invalid Doppler by zero. After that fix, executed channel-path
provenance attempted to send 3,019,898,933 bytes to Java in one update.
`ChannelFactory`, `WaveformHash` and `sha256Hex` now stream the identical
class/shape/real/imaginary byte representation in bounded chunks on Java.
No channel samples or gain/noise definitions were changed. PRACH failures
now retain their identifier and detailed error/cause report.

Passing focused tests: `testPDCCHStudyPopulations`,
`testBinomialSequentialQualification`, `test6GParameterCatalog`,
`testWaveformHashChunking`, `testFixedMatrixAWGNRuntime`, and the original
`testTruthValidationControlCoverage` (57.35 s). SHA-256 boundary/type/shape
equivalence and known digest checks pass. Evidence:
`logs/pdcch_population_mcp_receipt_20261003.log` and
`logs/prach_hash_streaming_repair_20261004.log`.

Inventory `logs/sls_failure_inventory_20261004_focused_closure_v7` records
**24/48 original failures with later passing evidence, 24/48 without**.
This includes the explicitly labelled retained-run PDCCH recheck, not a
claim that all original tests ran again on one frozen revision. Remaining
production SLS/calibration/interference/array/statistical gates are unchanged.
No testAll or statistical campaign was launched; agenda folders were not
edited. The next dedicated execution is the original shared HARQ roundtrip
after the existing capacity-rejection and joint-control-admission repairs.

### In-progress staged-reception and campaign attach repairs

The dedicated HARQ rerun is retained at
`results/lls/coupled_truth_harq_roundtrip/20261004_001727_739/bundle`.
It has passed the previous slot-39 admission boundary, executed UL grants,
and recorded a CRC-successful DL retransmission after failed first attempts.
These observations are not yet the test's final PASS or scenario acceptance.
The MATLAB tool's 300-second timeout did not stop this execution; no second
copy was started.

Three additional changes await focused runtime verification:

- `testDataChannelStreamStagesFDD`: its independent gNB HARQ identity case
  lacked an installed DCI context. The new test configuration
  `validation/lls_fdd_staged_data_connected_dci.yaml` preserves the FDD
  carrier and rank-two allocation while explicitly installing paired DCI,
  TDRA and SRS/DMRS/precoding policy. It does not derive receiver context
  from the transmitted grant or convert the test to TDD.
- `testUplinkControlStreamStages`: its expected noise-source label described
  the old channel-estimator residual. The assertion now requires the actual
  received vacant-comb estimator and independently reconstructs its sample
  population, checks its energy numerically and retains an injected-noise
  comparison. Positive/finite and injection-versus-estimation provenance
  checks remain mandatory.
- `sixgr_run_3gpp_full_campaign`: strict attach incorrectly released traffic
  at Msg4 even when RRCSetupComplete was required, and confused a zero-based
  completion slot with a count of blocked campaign rows. The new
  `resolveRAAttachCompletion` binds both to the actual successful completion,
  rejects missing/contradictory completion evidence and blocks the whole
  completion slot. `testRAAttachCompletionGate` covers these metadata
  contracts; it is not physical-access qualification. Original exception
  identifiers remain unchanged and their extended stacks are now logged.

No original failure is newly counted as fixed until its focused test passes.
The next batch is these affected FDD/SRS tests, the new completion-clock
guard and the original no-proxy E2E regression. No testAll is authorized or
queued, and no agenda-item folder was changed.

### Verified follow-up: 4 October, 01:17 IST

- `testUplinkControlStreamStages` passes (55.57 s), including the independent
  vacant-comb noise calculation, actual combined PUCCH reception and the
  shared feedback-clock test. `testRAAttachCompletionGate` passes (0.09 s).
- The first FDD rerun exposed a production defect in `ConnectedDCIProfile`:
  it dereferenced `qcl.state_id` when TCI/QCL was disabled. An unconfigured
  state now remains NaN, while enabled QCL requires a valid explicit state.
  Preconfigured QCL with an absent DCI TCI field still retains its installed
  state. `testConnectedDCIProfile` passes (46.44 s), and the original
  `testDataChannelStreamStagesFDD` passes all four cases (155.91 s), including
  actual independently bound PUSCH-UCI reception. Evidence:
  `logs/fdd_connected_tci_repair_20261004.log`.
- The original HARQ waveform run completed all 58 slots, then its test failed
  because the derived HARQ timeline dropped `SweepPointIndex`. It did not
  fail at the old slot-39 capacity boundary. The exporter now preserves the
  received sweep index, retains NaN when it is absent, and preserves source
  row order instead of regrouping interleaved points by SNR.
  `testLLSHARQFailureRateTruth` passes (57.09 s), including distinct point
  identities with repeated SNR values and persisted CSV checks.
- The repaired exporter was independently rerun on the retained receiver
  CSVs into `results/lls/harq_projection_recheck/20261004_011345_112`.
  The original HARQ test's retained-data assertions pass for 11 DL, five UL
  and 16 HARQ observations, including every source slot/CRC, received access,
  retransmissions and frame clocks. The old failed CSV remains untouched.
  Evidence: `logs/harq_retained_projection_recheck_20261004.log`.
  This is an explicitly labelled retained-run recheck, not another waveform
  execution or final-source whole-scenario acceptance.

Inventory `logs/sls_failure_inventory_20261004_focused_closure_v8` records
**27/48 original failures with later passing evidence; 21/48 without**.
The 27 include the two labelled PDCCH/HARQ retained-run rechecks. The wider
inventory also contains diagnostic/new-test failures; its distinct-failure
count must not be confused with the original 48-test population.

`testNoProxyTruthContract` remains failed (21.99 s). The newly retained
extended stack proves the next E2E root cause: strict attach initializes a
runtime and proceeds to RA without received broadcast selection; Msg2's
`CommonPDSCHQCLReference.fromRA` requests a missing
`random_access.associated_ssb_index` and `SSBBurstPlan` rejects it as
nonfinite. Required repair is causal broadcast/SSB selection and its RACH
association handoff in `sixgr_run_3gpp_full_campaign` using the existing
physical broadcast/RA producers. Substituting SSB zero, a transmitter oracle
or an invented QCL reference is not a repair. Preserve the downstream
received configuration/timing handoff as part of that integration. Evidence:
`logs/e2e_no_proxy_root_cause_20261004.log`.

No full suite, calibration campaign or agenda-item edit was performed.

### Verified E2E broadcast, TDRA and event-clock repair: 4 October 01:44 IST

The original failure population now has **28/48 tests with later passing
evidence and 20/48 without**. Two of the 28 remain the explicitly labelled
retained-run PDCCH/HARQ rechecks, not fresh final-source scenario executions.
The mixed-source inventory is
`logs/sls_failure_inventory_20261004_focused_closure_v10`; it is not full-suite
or scientific qualification.

Production changes and proof:

- `sixgr_run_3gpp_full_campaign.m` now executes actual cell-search/MIB/SIB1
  reception before strict RA, binds verified received SSB identity through
  `bindReceivedBroadcastForRA`, and passes decoded SIB1 plus the continued DL
  channel state into RA. PRACH starts no earlier than the end of the received
  sample buffer. No configured SSB-zero rescue or transmitted-beam oracle was
  added. The negative handoff contract test passes.
- The first 20-slot no-proxy rerun passed but had **zero data grants**. That
  result was insufficient: the test now covers 40 slots and requires actual
  post-attach waveform grant rows. An intermediate 80-slot diagnostic exposed
  unsupported special-slot `[2 8]` TDRA grants; its failures remain retained.
- `DCIContextFactory.supportsSymbolAllocation` and the pre-scheduler resource
  check in `SystemLevelRunner` now consult the same installed or YAML-derived
  active TDRA lists as the DCI packer. A clipped TDD window cannot manufacture
  a new TDRA row or consume a HARQ process before failing DCI construction.
  Configured-list and original wrong-index/K0/K2 negative tests pass. This
  does not enable an unconfigured short-slot transmission.
- E2E attach exports previously discarded `RAEventLog.Frame`, so events at
  absolute slots 22/24 appeared at slots 2/4. `resolveRAEventAbsoluteSlots`
  now uses the actual frame and in-frame slot, rejects missing/invalid clocks,
  and removes row-ordinal substitution. The focused clock test and integrated
  monotonic/completion-clock assertions pass.

Final focused evidence:
`logs/e2e_absolute_attach_clock_repair_20261004.log` records
`testRAEventAbsoluteClock` PASS (0.08 s) and strengthened
`testNoProxyTruthContract` PASS (95.83 s). The 40-slot system replay completed
with **nine grant rows and 2,600 system served bits**, not an empty scheduler.
Actual attach and grant CSVs are retained in
`results/sls/e2e_no_proxy_contract/20261004_014205_534/e2e/packet_flow/current/packet_flow/csv/`.
`logs/e2e_tdra_budget_units_20261004.log` retains the two passing TDRA checks.

Limits: this proves the focused single-UE DL replay contract, not complete
shared-clock multicell access, UL spatial feedback, production calibration or
RF/array qualification. Per-UE received RRC/RAR identity and timing continuity
into the separate system scheduler still need explicit integrated coverage.
No full `testAll` was started; no agenda-item files were edited.

### Verified UE-index / protocol-RNTI repair: 4 October 02:15 IST

The original-failure count remains **28/48 with later passing evidence and
20/48 without**; two of the 28 are the already-labelled retained-run checks.
This work repairs an additional production defect and verifies its consumers;
it does not close another original failure without rerunning that test.
Inventory: `logs/sls_failure_inventory_20261004_focused_closure_v11`.
It contains 983 distinct tests and 72 tests with some historical failure
evidence. Those numbers are not a new suite result or 72 current failures.

Root cause and implementation:

- `SystemLevelRunner` used `grant.RNTI` as an internal UE array index, even
  clamping it to the UE-count range. A protocol C-RNTI such as 4660 could
  therefore select the wrong queue, channel or file owner. New
  `bindGrantUEIdentity` associates grants with the exact cell scheduling
  population; `resolveGrantUEIndex` rejects missing/out-of-range ownership
  without clamping or inferring it from RNTI. Physical frozen grant fields
  and the actual scrambling RNTI are not rewritten.
- The runner now preserves protocol RNTI for HARQ and uses internal UEIndex
  for queues, pending grants, channel populations and delivery accounting.
  `SystemTransportBlockState` preserves internal ownership across retries
  and uses it for terminal file drops. `NetworkSpatialGrantProvider` uses
  UEIndex for propagation/power indices and retains RNTI as separate evidence.
- `SLSDynamicPUCCH` and `SLSUCIResourceBindings` retain the installed identity
  map through CSI/SR/HARQ obligations, UCI resource digests and PUSCH transport.
  The first automatic-transport rerun exposed a missing committed-state map;
  that failure is preserved in `sls_ue_identity_export_transport_20261004.log`.
  The corrected handoff passes in `sls_ue_identity_csi_transport_20261004.log`.
- `exportSystemLevelCanonicalArtifacts` no longer fabricates RNTI from UE
  index. Grant/raw-trial exports preserve scheduled RNTI, and a separate
  `TransmittedRNTI` comes only from actual waveform replay. Summary/geometry
  exports use the explicit runtime map; absent identity remains unknown.
  HARQ and network-spatial tables preserve both identities too.

**14 distinct affected focused tests have passing evidence**: identity binding,
transport-block ownership, dynamic PUCCH, finite predictor, FTP3 integration,
network UL, waveform replay/export, UCI resources, automatic UCI-on-PUSCH,
network DL CSI, native spatial covariance, committed finite covariance,
deferred reference feedback and eight-beam mapping. Logs:
`logs/sls_ue_identity_components_20261004.log`,
`logs/sls_ue_identity_integrated_20261004.log`,
`logs/sls_ue_identity_uci_bindings_20261004.log`,
`logs/sls_ue_owner_retx_guard_20261004.log`,
`logs/sls_ue_identity_export_transport_20261004.log`,
`logs/sls_ue_identity_csi_transport_20261004.log`, and
`logs/sls_ue_identity_spatial_regressions_20261004.log`.

The retained waveform export is
`results/sls/waveform_replay_evidence/20261004_020805_854/`.
Its four DL and one UL rows each retain UEIndex=1 and
RNTI=TransmittedRNTI=4660. **All five CRC outcomes are failures**: this test
proves execution/identity/export consistency, not successful link performance.
The SLS transport tests use explicitly labelled development BLER calibration
and ideal delayed control, not qualified physical UCI or accepted throughput.

The new runtime identity map is explicitly preconfigured; this is not yet
the full decoded per-UE RAR/RRC identity/timing handoff. That integration,
the remaining original failures, production calibration, full common/control
interference, RF/arrays, S0 loads and accepted paired campaigns remain open.
No full testAll or study campaign was launched. No agenda-item folder changed.

### E2E grant projection and original UL failure reproduction: 4 October

The packet-replay adapter still rebuilt protocol RNTI from the internal UE
index, clamped it when selecting packet queues, and reconstructed contiguous
PRBs from count/start. `projectSystemGrantTraceForE2E.m` now retains the exact
serialized PRB indices and separate UEIndex/RNTI. Invalid slots, identities,
allocations and unknown directions fail explicitly instead of being changed
or discarded. `sixgr_run_3gpp_full_campaign.m` uses UEIndex for queues, RNTI
for packet HARQ, and exports RNTI in both scheduler and HARQ trace tables.

Verification:

- `testE2EGrantProjection` passes non-contiguous PRBs, distinct UE/RNTI and
  twelve negative guards; its rows are explicitly test fixtures, not PHY data.
- `testSystemGrantUEIdentity` passes again.
- `testNoProxyTruthContract` passes on the corrected source in 96.36 seconds,
  with nine actual post-attach DL grant rows. Retained results:
  `results/sls/e2e_no_proxy_contract/20261004_023227_588/`.
- Two intermediate failures in this patch are preserved: adding RNTI to the
  wrong template caused dissimilar-struct assignment, and the CSV column
  whitelist then omitted RNTI. Both are corrected; the later integrated pass
  includes the new export assertion.
- The original failed `testE2ETruthChunkMetadata` now requires actual UL
  grants and runs 40 slots instead of ending during access at 20 slots. It
  still FAILS after 59.39 seconds: `MissingSRSState` at slots 29, 34 and 39.
  This is not accepted as metadata-only success with no data execution.

Logs: `logs/e2e_grant_identity_projection_20261004.log`,
`logs/e2e_grant_identity_projection_schema_20261004.log`, and
`logs/e2e_grant_projection_dl_ul_20261004.log`. The last log contains the final
DL pass and the actual remaining UL failure, not a passing batch. Static
MATLAB checks found no reported parse errors; the scoped diff check passes.

Confirmed remaining production gap: `SystemLevelRunner.m` calls spatial
feedback advancement only for `calibratedBacked`. `WaveformPHY.m` exposes
grant replay but has no physical SRS/CSI production/completion handoff. Thus
the strict waveform E2E UL scheduler receives no causal SRS identity. The
next repair must execute the configured physical reference occasions with
the same UE/channel/power state, retain completion/availability clocks, and
deliver receiver-owned spatial state before eligible future UL grants. Do
not copy the abstraction's modeled SRS into waveform truth, invent a pilot
measurement, or disable `MissingSRSState` to make this test pass.

The separate decoded-access handoff also remains open: E2E still does not
install each attached UE's received C-RNTI and connected TAG into the system
data runner. This turn's adapter repair does not claim that integration.
**Original 48 inventory remains 28 with later passing evidence / 20 open.**
These focused results do not qualify SLS calibration, RF, or final campaigns.
No testAll, study campaign, agenda-item edits, commit, or cleanup was performed.

### Absolute fading clock and deferred PDSCH execution: 4 October

Two production defects were isolated; neither was an export-label repair.

1. `replayGrant.m` defaulted channel initial time to zero when the system
   supplied a nonzero scheduled slot. `resolveReplayChannelTime.m` now binds
   data fading to `ScheduledAbsoluteSlot` and control fading separately to
   `ControlAbsoluteSlot`. Explicit calibration time must agree with an issued
   grant's clock. Legacy component calls without an issued absolute slot use
   their configured carrier frame/slot, not an invented zero timestamp.
2. `SystemLevelRunner.m` executed PDSCH immediately even when canonical K0
   selected a future data slot. The retained four-slot failure had DL rows at
   TTI 1/2/3/4 but fading times 0.0005/0.001/0.0015/0.002 seconds, each one
   0.5-ms slot early. UL already had a future-grant queue. Both directions now
   use the canonical timing engine to select the target budget, retain frozen
   grants until that slot, and avoid issuing outside the execution horizon.
   CSI freshness is checked for the target slot. Dynamic HARQ/UCI obligations
   are registered at grant issuance, not deferred until data execution.

`assertSLSExecutingReservations.m` shares the execution-time reservation
guard between DL and UL; the old UL entry point remains a wrapper. Late
obligations cannot rewrite frozen PRBs, symbols or TBS. The existing
one-pending-grant-per-UE policy is preserved for UL and applied to DL; this
does not claim unrestricted pipelined scheduling or throughput qualification.

Focused evidence:

- `testWaveformReplayClock`, `testSLSHARQChannelTime` and
  `testSystemWaveformPDCCHGrantBinding` pass. The latter is a fresh physical
  rerun, replacing its earlier retained-artifact-only recheck. Native TDL-A
  and CDL-C DL/UL clock comparisons agree at nonzero absolute slots.
- `testSystemLevelWaveformReplayEvidence` first failed the new clock
  assertion; that failure is retained in
  `logs/waveform_channel_clock_integration_20261004.mat`. The accompanying
  recovered `.log` is explicitly a saved-report summary, not captured stdout.
- After the queue repair, `testSystemLevelWaveformReplayEvidence` passes
  (30.49 s), including actual scheduled-slot, fading-time, UE/RNTI and both
  DL/UL receiver-export assertions. `testSLSExecutingULReservations` also
  passes (7.89 s), now covering DL early execution, wrong direction and late
  PDCCH collision without mutating a frozen grant.
- Actual captured output: `logs/dl_k0_execution_repair_20261004.log` and its
  saved report `.mat`. Physical rows and CSVs:
  `results/sls/waveform_replay_evidence/20261004_025811_443/`.
  CRC failures and zero goodput remain visible; passing this test establishes
  execution/export consistency, not a successful performance benchmark.
- The three affected integration guards also pass:
  `testSystemNetworkDLCSI` (85.90 s), `testSystemAutomaticPUSCHUCI`
  (102.84 s), and `testSystemLevelCausalCQIFeedback` (72.12 s).
  Captured log and saved report:
  `logs/dl_k0_feedback_transport_regressions_20261004.log` / `.mat`.
  The first two retain test-only BLER calibration and ideal delayed control;
  they are software integration evidence, not accepted study performance.

The final retained execution rows are DL TTI 2 / control slot0 0 / data
slot0 1; UL TTI 3 / control slot0 0 / data slot0 2; DL TTI 4 / control slot0
2 / data slot0 3. Their fading times are respectively 0.0005, 0.001 and
0.0015 seconds. All three ACK/CRC outcomes remain false. Scoped diff checks
pass and MATLAB reports no parse errors in the repaired production files.
Source hashes checked after the focused batch, without intervening source
edits: `SystemLevelRunner.m` SHA256
`c11ae4ca4aa43f577481bfbc7050a9ca4f06f5ec2dbe22d8cd370b0224fbc58a`;
`replayGrant.m` SHA256
`a5e5dd68542df08849872307e3434e9665732b873aeb0b65059bcb7a35e5c66f`.

The original 48 inventory remains **28 with later passing evidence / 20 open**.
Physical SRS/access handoff, production calibration and the broader plan are
not closed by this repair. No full testAll or agenda-item work was started.

### Received access identity and payload ownership: 4 October

The next access-handoff prerequisite exposed three concrete defects in
`+sixgr/+phy/+ra/runFourStepRA.m`:

- Successful Msg4 processing overwrote the decoded final C-RNTI with
  `raCfg.FinalCRNTI` in two places. `receivedMsg4Identity.m` now accepts only
  successful received control/data plus matching UE contention identity;
  it has no configured/TX final-RNTI input. RRCSetupComplete generation uses
  that received C-RNTI. The primary RA/Msg4 tables retain its source and the
  explicitly bounded codec profile.
- `RARBytesHex` came from the transmitted RAR even on failed reception. It
  now comes only from `rarRx.Hex`. Failure leaves received bytes absent.
- Completed RA discarded decoded RAR and Msg4 structures needed by the
  subsequent timing/identity handoff. They are retained as `DecodedRAR` and
  `DecodedMsg4`, not reconstructed from configured timing advance or identity.
  Consumers must still check acceptance and actual receive-completion clocks.

`buildMsg4ContentionResolution.m` also validates identity before converting
to `uint16`, preventing saturation/rounding from making payload bytes disagree
with metadata. TX and received-identity guards accept C-RNTI 0001..FFF2 and
reject the reserved/common identities above it, per
[TS 38.321 V18.6.0 Table 7.1-1](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.06.00_60/ts_138321v180600p.pdf).
**This does not qualify the existing Msg4 MAC/RRC encoding:**
`legacy_bounded_not_NR_MAC_RRC` remains explicit.

Five distinct affected tests have passing evidence:

| Focused test | Verified scope |
|---|---|
| `testRAReceivedMsg4Identity` | Decode/contention guards, missing/malformed identities, both valid range endpoints and every FFF3..FFFF reserved/common value. |
| `testRAReceivedObservationBoundary` | Five actual coded TDD receivers over an explicit short FIR; poisoning configured final C-RNTI after waveform preparation does not alter decoded identity or subsequent UE PUSCH scrambling. Received payloads, completion windows and primary Msg4 export agree. |
| `testMsg4ReceiverOwnsDCI` | Independent TDD/FDD Msg4 control/data reception, full and short mapping-B allocations, and identity recovery despite poisoned intended RNTI. |
| `testRANegativeMsg4IdentityMismatch` | No C-RNTI is installed after contention mismatch. |
| `testRANegativeWrongRARNTI` | Failed Msg2 reception exports no received RAR bytes. |

The Msg4 component's first FDD attempt failed before decoding: centred SSB
put CORESET0 at [2,26) in a 25-RB BWP. Its component fixture now explicitly
places SSB at Point A, matching its RB-0-authored allocation. The bounds
assertion was not weakened. The passing component rerun does not accept the
entire older FDD scenario YAML.

Logs (including the intermediate failure):
`logs/ra_received_msg4_identity_20261004.log`,
`logs/ra_msg4_independent_identity_retry_20261004.log`,
`logs/ra_received_access_payload_guards_20261004.log`,
`logs/ra_received_access_export_20261004.log`, and
`logs/ra_crnti_reserved_value_guards_20261004.log`.
Retained MAT and CSV evidence:
`results/sls/ra_received_access_identity/20261004_031831_296/`.
This is a component FIR/ownership test, not fading/RF qualification or an
accepted integrated SLS run. Production RA source SHA256 after the checks:
`2d33a24a92a6aacb63a30f2a21deffde8e08917952afb4e07fa6c1c54ef91bcd`.

Still open: the E2E wrapper runs one access procedure and does not hand each
UE's received identity, SIB1/TAG and completed physical channel state into
`SystemLevelRunner`. Merely copying one C-RNTI to every UE would be wrong.
The standalone waveform backend still lacks causal physical SRS delivery;
its guard remains enabled. **Original 48 count stays 28 with later passing
evidence / 20 open.** No testAll, campaign, agenda-item edit or commit occurred.

### 2026-10-04 received RRC setup and access-completion clock repair

Further access-path root causes corrected in production:

- `runFourStepRA.m` compared the UE's decoded Setup transaction/bearer with
  gNB configuration, then generated SetupComplete from that configuration.
  `receivedRRCSetup.m` now installs the accepted received values, which drive
  the UE reply. The gNB checks its actually issued Setup separately. Changing
  configuration after Msg4 waveform preparation cannot change either side's
  retained transaction. The bounded codec remains explicitly **not full NR
  MAC/RRC qualification**; this repairs ownership, not the missing codec.
- The RRC CSV exports received Setup transaction, SRB1 LCID and source
  separately from gNB expectations and decoded UL reply fields.
- Actual RA stage composition omitted receive-window sample-rate/extent
  fields. It now retains the executed channel extent and checks it against
  the actual RX sample count; it does not invent an unexecuted filter tail.
- `resolveRAAttachCompletion.m` previously released scheduling from a
  nominal final stage slot alone. Its scheduling gate now requires actual
  final-stage receive completion, including a tail crossing into another
  slot. The historical event slot remains distinct from the blocked-slot
  count. The strict E2E caller supplies the real carrier clock.
- Strict E2E attach no longer substitutes temporary/default RNTI 1 for a
  missing final identity. Accepted identity comes from decoded Msg4;
  failure returns NaN. This does **not yet** connect that identity to every
  UE's SystemLevelRunner state.

Eight focused tests passed; no full suite ran:

| Test | Scope / evidence |
|---|---|
| `testRAReceivedMsg4Identity` | Received Setup boundaries, missing/malformed fields, and identity guards. |
| `testRAReceivedObservationBoundary` | Five actual coded TDD stages over an explicit short FIR; poisoned configured C-RNTI, transaction and LCID do not change the decoded UE reply. |
| `testFourStepRARuntimeStageComposer` | Actual composed receive extent/rate/completion matches channel execution. |
| `testRAAttachCompletionGate` | Exact slot-end and seven-sample-late completion, plus missing/invalid clock rejection. |
| `testRANegativeMsg4IdentityMismatch` | Failed contention cannot install an identity. |
| `testRANegativeWrongRARNTI` | Failed RAR reception retains no fabricated received payload. |
| `testInitialAccessRRCPhaseCore` | Bounded RRC state/codec regression, not full ASN.1 qualification. |
| `testNoProxyTruthContract` | 40-slot TDL-C execution with nine actual post-access DL grant rows; 2,600 served bits. This is not UL/SRS or multi-UE acceptance. |

Evidence: `logs/ra_received_setup_clock_20261004.log` (3/3) and
`logs/ra_received_handoff_gates_20261004.log` (5/5), with MAT reports beside
them. Received RRC CSV/MAT:
`results/sls/ra_received_access_identity/20261004_033125_722/`.
E2E output:
`results/sls/e2e_no_proxy_contract/20261004_033408_188/e2e/packet_flow/current/`.

Source SHA256 for the verified RA implementation:
`aadbe7a57c6b1f48a58eacd059204fa54fababa6fed48b57d12b91df84350207`;
received-Setup helper:
`6a05ef68a001c7e283c1371bc886cb97f1617b3216535a12da91e1d5d4835576`;
completion gate:
`2589ecf01333b65479ac5abe1ecac79b3f83bfd17bff0a70f6b3783063f95b33`.

**Original 48 reconciliation remains 28 with later passing evidence / 20
open.** These eight focused passes are prerequisites, not eight additional
closures in that inventory. Next: complete per-UE received access-state
handoff and causal physical SRS production/delivery. Do not install one UE's
identity for all UEs, disable the SRS guard, or substitute modeled SLS
feedback for waveform reception. General calibration, RF/array and campaign
qualification work remains open as listed above. Agenda-item files were not
edited; no full testAll or performance campaign was launched.

### 2026-10-04 per-UE received identity and Type-0 receiver authority

Production repairs and their verified boundary:

- `resolveReceivedAccessBindings.m` reparses each UE's retained Msg4 bytes,
  verifies its contention/CRC/completion evidence and resolves a separate
  C-RNTI. Missing/duplicate UE records and duplicate same-cell C-RNTIs fail.
- `SystemLevelRunner.m` uses that received map for scheduling and feedback
  identities; grants cannot precede the UE's actual access-completion gate.
  A cell change cannot silently reuse the old received access binding.
- The E2E wrapper now executes serial, independently received access for
  each UE. This is explicitly a stage-composed access warm-up, **not** a
  shared simultaneous multi-cell access/interference qualification.
- The two-UE test exposed a real receiver oracle: SIB1 Type-0 derivation
  used configured SSB index 0 after decoding another PBCH/DMRS hypothesis.
  `recoverSIB1FromWaveform.m` now supplies the actually observed SSB index.
  Candidate reception accepts only an actually decoded complete SIB1;
  illegal UL-slot Type-0 monitoring remains rejected. It does not add
  missing SIB1 transmissions to other beams.

Verified: `testSIB1NoOracleReceiver` (including poisoned configured SSB
index), `testReceivedBroadcastRAHandoff`, `testReceivedAccessBindings`,
`testSystemGrantUEIdentity`, and `testE2EReceivedAccessMultiUE`.
The final two-UE run has decoded C-RNTIs 4660/4661, completion slot0 values
34/54, blocked-slot counts 35/55, and three actual DL grant rows per UE.
The test verifies their grant identities and causal release, not just an
access-success label.

Evidence: `logs/received_type0_ssb_authority_20261004.log`,
`logs/received_access_multiue_type0_fix_20261004.log` (235.21 s), and
`results/sls/e2e_no_proxy_contract/20261004_035512_729/e2e/packet_flow/current/`.
Earlier failed attempts are retained in
`logs/received_access_multiue_20261004.log` and
`logs/received_access_multiue_clock_fix_20261004.log`.

Remaining: actual continuous access-to-data channel-state transfer, physical
SRS production/delivery in the standalone waveform backend, and complete
beam-wise SI/control coverage. The bounded MAC/RRC codec is still labelled
`legacy_bounded_not_NR_MAC_RRC`, not full NR codec qualification.
Original48 count remains **28 later-pass / 20 open** at this checkpoint.
Focused publication regression is being repaired separately: its old
standalone PRACH fixture failed before its artifact assertions could run.
No testAll was launched and agenda-item folders remain untouched.

### 2026-10-04 publication regressions after received-access integration

`testArtifactVerificationScope` reproduced
`sixgr:mac:ra:ConfiguredPRACHOccasionMismatch` before publication assertions:
its standalone RA component fixture specified frame 0 / slot 2, incompatible
with this received-SIB1 cold-access execution. The report fixtures previously
also limited execution to 24 slots, insufficient for two serially received
access procedures followed by actual data.

`e2eReceivedAccessConfig.m` now supplies the fully resolved causal-access
scenario, two UEs, explicit TDL-C, and 70 slots of deterministic offered DL
traffic. This is a publication fixture, **not** a bidirectional qualification
or calibrated SLS campaign. Existing export assertions are retained and new
assertions require independently received access and actual data grants for
both UEs. Production SRS/control guards are not disabled. Evidence is kept
under `results/sls/`, not deleted after the test.

The campaign wrapper also no longer uses protocol-only access for a truth
request merely because `E2EStrictValidation=false`. Per-UE received access is
required for either validation setting; failed access cannot become a truth
data run.

Verified historical failure closures:

| Test | Focused result | Retained log |
|---|---|---|
| `testArtifactVerificationScope` | PASS, 237.52 s; original scope assertions plus actual per-UE grants | `logs/artifact_scope_received_access_repair_20261004.log` |
| `testCalibrationProvenanceHonesty` | PASS, 227.09 s; non-strict request still uses received access; no calibration artifacts and LUT rejection retained | `logs/calibration_provenance_received_access_20261004.log` |
| `testPartialCampaignReportHonesty` | PASS, 216.87 s; original category/report honesty assertions and per-UE data checks retained | `logs/partial_report_received_access_20261004.log` |

Original48 checkpoint: **31 later-pass / 17 open**, not frozen-source suite
acceptance. The failed artifact diagnosis is retained in
`logs/artifact_scope_access_diagnosis_20261004.log`.
Campaign source SHA256 for these focused executions:
`ab7d892ec3e704c1254c0ddc644ae0186f636bff34461b125fa03d4893cc14af`;
SystemLevelRunner:
`b6730f397a8bbcbd2d01943d4ddb8736faa25de1045f3e9879b91c9bb3602cbd`;
received-SIB1 receiver:
`0eb15ab4b69c40fd8a7515696d7f769288d90a39f416ddc13e73385248e8b81c`.
No full suite or agenda-item execution was launched.

Final inventory for this block:
`logs/sls_failure_inventory_20261004_focused_closure_v12/`.
It snapshots 988 distinct historically observed tests and 74 tests with
some failure evidence across revisions; **74 is not the current open count**.
All three closures above are confirmed failures in the original 48-test
set. The original-set count is **31 later-pass / 17 open**.

The additional configured-frame poisoning check in
`testSIB1NoOracleReceiver` also passed (12.057 s), retained in
`logs/received_type0_frame_authority_diagnosis_20261004.log`.
The receiver already clears that configured hint during normalization;
this check did not establish a new frame-oracle defect and no speculative
production change was made for it. Nonzero-SFN/capture-origin qualification
is not implied by this frame-zero waveform test.

All focused calls launched in this repair block have completed. The next
implementation priority remains actual access/SIB1/TAG/channel-state
handoff into physical SRS production and causal UL delivery; do not close
UL/accounting failures by disabling its guard or reducing their intended
bidirectional coverage. SLS calibration and scientific acceptance remain
unqualified. No `testAll` was run.

### 2026-10-04 received access-to-UL timing handoff

The standalone received-access path previously dropped the actual decoded
SSB clock and the RAR decoder context before entering SystemLevelRunner.
`completeCellSearchBroadcast.m` now retains the received clock centrally;
the shared caller no longer duplicates that construction. `runFourStepRA.m`
retains the accepted RAR receiver context. `resolveReceivedAccessULTiming.m`
reparses received SIB1 bits and MAC RAR bytes, checks receiver acceptance,
owner and completion, and uses `connectedTimingFromRAR` to retain the TAG.
SystemLevelRunner and campaign outputs retain the state by UE and export
`packet_flow/csv/e2e_received_ul_timing.csv` plus the access-receipt MAT.

Focused evidence:

| Test | Result | Evidence |
|---|---|---|
| `testConnectedRARTimingAuthority` | PASS, 8.008 s | `logs/received_access_ul_timing_handoff_20261004.log` |
| `testConnectedULTransmissionTiming` | PASS, 0.223 s | same log |
| `testNoProxyTruthContract` | PASS, 102.45 s after payload-schema repair | `logs/received_access_ul_timing_payload_fix_20261004.log` |
| `testE2EReceivedAccessMultiUE` | PASS, 221.16 s, two received C-RNTIs and timing records | `logs/received_access_ul_timing_multiue_20261004.log` |

The first integration attempt exposed an error in the new reader:
`SIB1PayloadBytes` is a count, not the payload. The reader was corrected to
decode `SIB1PayloadBits`; the initial failure remains in the handoff log.
Poisoned cached TA/timer values do not override received bits/bytes, and
unaccepted RAR or missing received DL clock remains rejected.

The two-UE evidence root is
`results/sls/e2e_no_proxy_contract/20261004_043115_988/`.
This is a **timing handoff**, not physical SRS qualification:
`WaveformTimingApplied=false` and `PhysicalSRSReceived=false` remain explicit.
No new waveform owner was initialized after access and no SRS guard was
disabled. Shared continuous access/SRS/data execution remains open.
Original48 count remains **31 later-pass / 17 open**; these additional
integration checks do not close a previously open original test.

The retained timing CSV audit found that the generic writer pruned the
all-infinite expiry column. The campaign writer now uses `PreserveSchema`
for this table; `testNoProxyTruthContract` additionally compares the exported
expiry to each retained received TAG. PASS, 95.39 s:
`logs/received_access_timing_csv_schema_20261004.log`. The decoded infinite
timer is retained as infinity, not converted to zero or a guessed expiry.

### 2026-10-04 isolated LLS execution-profile repair (verification pending)

The original `testLLSScenarioStatusPropagation` failed before its status
assertions with `MissingExecutionProfile`. The 100 MHz independent component
bundle had neither PDSCH nor PUSCH execution authority configured.
`lls_100mhz_tdlc_bidirectional_truth.yaml` now explicitly selects
`phy_calibration` for its isolated waveform trials and states that scope.
The strict decoded-grant guards are unchanged; this is not a conversion of
a connected scenario into calibration execution. Existing coupled scenarios
must still explicitly select `scheduler_truth`.

The status test retains all original failure/status assertions, adds profile
wiring assertions, and keeps timestamped evidence rather than deleting it.
Its first focused launch inherited four parallel workers; those workers were
stopped, but the runner's pool-start retry launched replacements. The fixture
now explicitly requests one worker and no automatic pool for subsequent
execution. That fixture edit does not change the already-loaded run.
No new `testAll` was started. Do not count this test as closed until its
original status assertions finish and pass.

Further inspection of this same attempt exposed conflicting fixture units:
it specified both `simulation.n_frames=4` and `simulation.n_slots=4`.
The resolver prioritizes frames when `run_control.total_slots` is absent,
so four 30-kHz frames resolve to 80 slots. The resolved snapshot confirms
there was no inherited `run_control.total_slots=80`; that preliminary
interpretation was incorrect. The worker count was inherited as 24, capped
to the available four-worker pool by the launcher.
The focused fixture now explicitly binds four 30-kHz slots (2 ms), zero
warmup, four measurement slots and one worker, with a build-time assertion.
This correction is only to the regression fixture, not the user scenario's
run duration. The already-loaded 80-slot attempt remains distinct; its MCP
wait timed out at 300 s without terminating MATLAB. No duplicate was launched.

Completed timing-test logs are included in
`logs/sls_failure_inventory_20261004_focused_closure_v13/`.
The in-progress status test is not a pass or a closure in that inventory.

### 2026-10-04 SSB physical-array handoff (implemented, verification pending)

The retained status run's `air_interface/csv/link_anchor_kpis.csv` reports
`CellSearch_MIB_SIB1` failing because the TX runtime waveform count is one
while the channel requires two. The PBCH raw sweep also retained failed
acquisition rows; these are not successful measurement evidence.

Root cause: `SSB_Tx` has already applied its configured beam vectors and
produces two physical-element columns, but `initWaveformTruthChannelState`
previously reused the data antenna's one-logical-port waveform interface.
Its physical-SSB branch correctly avoided another precoder application, but
did not specialize that interface to the already-produced element waveform.

The initializer now verifies retained array element counts and positions,
then specializes only the waveform count/domain. It retains logical ports,
RF chains, geometry and polarization; it neither pads IQ nor removes the
channel's dimension guard. `testSSBPhysicalElementRuntimeAntenna` covers the
actual 100 MHz scenario, sample comparison with an explicitly element-domain
reference, no duplicate expansion, immutable data context and contradictory
element-count rejection. This new test is awaiting the existing MATLAB job;
it has not yet produced a runtime pass.

The status fixture is additionally restricted to its intended single -10 dB
negative point (four slots, serial). The already-loaded attempt inherited
three points `[-10,0,10]` and remains separate. Public scenario sweeps and all
original status assertions are unchanged. No full `testAll` was launched.

The same retained raw export contains 240 PUCCH component crashes with
`Connected PUCCH campaign requires a configured finite RNTI.` The standalone
collector in `runWaveformLinkBundle.localCollectPUCCHTrials` reads `phy.rnti`,
whereas the bundle's user preparation records identity in
`lls6g.userContext.RNTI` (and, for enabled multi-user execution, the explicit
PDSCH/PUSCH RNTI fields). Its root-config call has not bound that identity.
This is an unresolved component-collector binding problem, not a measured
false-ACK/missed-detection population. The repair must also validate the
configured CSI resource, coding policy and legal TDD occasion; simply adding
a magic RNTI would not establish a valid PUCCH trial.

### 2026-10-04 isolated PUCCH collector repair (MATLAB verification pending)

The collector binding repair is now implemented in
`+sixgr/+link/preparePUCCHComponentProbe.m` and wired into
`runWaveformLinkBundle.localCollectPUCCHTrials`. The scenario and parameter
catalog expose explicit component identity, payload lengths, seed-derived
trials and legal TDD occasions. The helper uses installed carrier/BWP identity
and the existing typed resource/coding/power constructor. It does not create
causal CSI reports or substitute for independent shared-runtime reception.

The retained 20-information-bit format-2 probe requires 11 CRC bits. Its old
two-PRB/two-symbol allocation has 64 coded bits: 31/64 exceeds the configured
0.35 rate. The explicit three-PRB allocation has 96 coded bits and fits
31/96; neither the coding-rate assertion nor receiver thresholds were relaxed.
Configured unit-norm PUCCH transmit weights retain the physical antenna
dimensions, rather than relying on absent root-level `phy.rnti` metadata.

Canonical control-table annotation previously replaced every source label
with an integrated-runtime label. It now preserves explicitly isolated
component/diagnostic provenance, marks their runtime consumers as absent,
and does not describe them as active coupled-runtime observations. Component
PUCCH detection success follows the detector outcome, separately from overall
decode/qualification success.

Verification performed:

- MATLAB standalone Code Analyzer (`mlint.exe -id`) reported no issues in
  the new probe helper and the two new SSB/PUCCH regression files.
- `python -m pytest tests/test_lls_csv_semantics.py -q`: **96 passed**.
- `testPUCCHComponentProbeBinding` includes deterministic/configured identity,
  resource budget, invalid-config/TDD rejection, physical receiver execution,
  and isolated-provenance assertions. It has **not yet run in MATLAB**.
- The SSB physical-array regression also awaits MATLAB execution.

The existing oversized status-only regression still owns the MATLAB engine;
its timed-out tool wait did not stop execution. No duplicate scenario or full
`testAll` was launched. An interruption decision was requested; until that
decision or completion, these staged repairs are not counted as verified
closures. The original-48 inventory remains **31 later-pass / 17 open**,
not final-source scientific acceptance. Agenda-item folders are untouched.

### 2026-10-04 PBCH standalone state and measurement follow-up

The same retained diagnostic contains 120 PBCH crash rows: three initial
`ChannelFactory:RuntimeAntennaPortMismatch` failures and 117 subsequent
`sixgr:link:InvalidInitialRuntimeChannelState` failures. The latter are not
117 independent antenna defects. `localCollectPBCHTrials` carried the failed
initializer's uninitialized output into the next standalone seeded trial.

The collector now initializes each standalone realization from its own
configuration instead of carrying the previous trial's channel. Explicit
runtime slots, retained channel state and already-received observations stay
on the continuous single-occasion path; a multiplicity guard rejects attempts
to treat one runtime occasion as multiple independent trials. Independent
PBCH rows retain isolated-component provenance. This is not a reset/fallback
for failed connected reception and does not mark a crashed trial successful.

The collector also overwrote a successful receiver's detection correlation
with `1` after CRC success. That overwrite is removed: the receiver's
`ssbDetectionEvidence` metric remains authoritative, while acquisition and
CRC remain separate decisions. The SSB note label no longer says PRACH.
The existing PBCH source-wiring guards have been extended; their MATLAB
execution and the bounded integrated regression remain pending.

Other retained component counts in this diagnostic are 240 PDCCH passes,
120 PRACH passes, and SRS 54 failures at -10 dB, 54 failures at 0 dB, 54 passes
at 10 dB. The SRS failures report the configured channel-NMSE threshold, not
a crash; this audit does not establish that those physical failures are bugs
or justify relaxing their threshold. The TRS CSV is header-only, not an
executed trial population. These component outcomes are not overall scenario
or SLS acceptance.

### 2026-10-04 WebGUI master probe configuration closure

Focused Python testing exposed a configuration-surface regression introduced
by the isolated PUCCH repair: both operator master YAMLs lacked the new
catalog field `pucch_resources.component_probe`. Both now expose the same
explicit probe policy with `enabled: false`; the 100 MHz component scenario
explicitly enables it. The MATLAB helper rejects direct execution of a
disabled probe, while the collector emits no trial rows for an explicitly
disabled diagnostic. Missing or malformed required probe configuration is
not silently treated as disabled. Connected feedback remains a separate path.

The initial access/WebGUI batch recorded 12 passes and this one failure
(209.47 s including home-page rendering). The exact failed surface test then
passed after the repair. The post-repair focused batch excluding the slow
home-page render passed **12/12** (7.00 s); the new browser serialization
round-trip test also passed (1.80 s). No MATLAB scenario was launched by these
Python checks. This closes the identified WebGUI surface defect, not the
pending MATLAB PHY qualification or the original-48 inventory.

### 2026-10-04 SSB/PUCCH/PBCH focused MATLAB verification

The staged physical-array and component-probe changes above now have MATLAB
execution evidence. `logs/ssb_pucch_binding_focused_20261004.log` and its MAT
report retain the initial batch: SSB physical-element runtime antenna PASS
(100.01 s), PUCCH component-probe binding PASS (20.22 s), and PBCH SINR runtime
binding PASS (8.17 s). The artifact-isolation source guard initially failed
because its MATLAB regular expression did not locate the collector; this was
a test parser defect, not an artifact-isolation result.

The parser now matches the actual function declaration without relying on
the incorrect word-boundary expression. All ownership assertions remain.
Only that failed test was rerun: `testParallelPBCHArtifactIsolation` PASS
(0.51 s), retained in `logs/pbch_artifact_isolation_matcher_20261004.log` and
its MAT report. Do not describe the initial batch as four passes.

These supplemental passes do not close the original report/scenario tests
or qualify SLS calibration. The original-48 inventory remains 31 later-pass
and 17 open at this checkpoint. No full testAll or agenda-item work occurred.

### 2026-10-04 report-richness execution footprint repair (runtime pending)

`testLLSResultRichness` declared four legacy simulation slots but inherited
the authoritative `run_control.total_slots` and sweep values. Its fixture
now explicitly binds four slots, one serial worker and the two intended
points (the parent's 30 dB anchor plus offsets -12 and 0), in
`simulator/configs/fixtures/lls_result_richness.yaml`. Unrelated reference
and adaptive sweeps are explicitly disabled for this bounded regression.
The two Monte Carlo realizations and all existing measurement/artifact assertions remain.
It saves configuration and outputs under a unique retained
`results/lls/result_richness/` directory instead of deleting the diagnostic
configuration at exit. Configuration assertions precede waveform execution.

Static MATLAB checking found no syntax error (one existing unused-variable
warning remains). The WebGUI inheritance/normalization check preserves four
slots, two realizations (canonical browser field `run_control.num_drops`),
18/30 dB, serial execution and disabled extra sweeps. MATLAB waveform
execution remains unverified: this is a fixture repair, not a passing
richness test. The original four-slot mobile YAML-wiring test is currently
being verified separately; no full suite or duplicate status run was started.

### 2026-10-04 original mobile YAML-wiring failure verified closed

`testLLSMobile2UEScenarioYamlWiring` PASS (779.64 s), retained in
`logs/mobile_2ue_calendar_original_20261004.log` and its MAT test report.
Configuration and complete runtime output are retained under
`logs/tpab7c7d0f_85cf_4df3_a6b3_4a0a995116e8/`.
The exact original assertions ran: configured CSI-RS/SSB calendar and MIMO
binding, four actual system slots, scheduler/export fields, and no UL data
grants in the one-symbol special-slot tail. Eight DL grants executed; the
runtime recorded 99,904 served bits. This short check does not cover a full
UL occasion, cold access, physical CSI/SRS feedback or full mobile acceptance.

The original-48 inventory is now **32 later-pass / 16 open**, still mixed-source
diagnostic evidence rather than final-source acceptance. After that engine
exited, only `testLLSResultRichness` was launched on its bounded YAML; no
full testAll was launched and no original assertion was relaxed.

### 2026-10-04 bounded report diagnostics: native configuration correction

The first bounded richness invocation failed before PHY execution with
`sixgr:lls6g:config:BadRunSlotControl`: the new fixture declared both one full
30-kHz frame (20 slots) and four total slots. Removed only the redundant
`run_control.total_frames` declaration; the validator, four-slot workload,
two realizations and both 18/30-dB points are unchanged. Retain the initial
failure in `logs/lls_richness_bounded_original_20261004.log` and its MAT file.
The affected-test-only rerun is
`logs/lls_richness_bounded_slots_repair_20261004.log`; configuration validation
now passes and physical execution has started, but no terminal pass exists yet.

`testLLSReportBundle` now preserves its generated scenario, resolved native
configuration and complete result under a unique
`results/lls/report_bundle_regression/` directory. Removed its exit-time
deletion of evidence and added a pre-execution assertion for its existing
20-slot serial workload. All existing publication/measurement assertions
remain. This retention change is not a report-bundle pass; no extra MATLAB
job was started while the richness rerun and older status diagnostic remain
active. Agenda-item files remain untouched.

The retained richness control CSVs then exposed a distinct export defect:
all eight isolated PUCCH trials reported `ProcedureDelay_ms=0` although
`runPUCCHWaveformTrial` supplies no protocol-procedure delay field. The
collector in `+sixgr/+truth/runWaveformLinkBundle.m` supplied zero as its
missing-field default. Changed that default to `NaN`, retaining a provided
measurement if one exists. Detection, coding, CRC and waveform execution
are unchanged. Extended `testPUCCHComponentProbeBinding` to guard both the
physical producer's unavailable delay and the collector binding. Static
MATLAB checking passes for that test; its affected native rerun is pending
the existing bounded MATLAB job. Already-written CSVs are not relabelled.
The active richness run loaded the old collector and is not evidence for
this later repair. Its eight PUCCH, six SRS and six TRS trial rows currently
report PASS, but the complete report test is still running.

### 2026-10-04 TDD scheduler deferral and retained report failure isolation

Staged in `SchedulerBase.ssbSafePRBSet`: reject a timing candidate with an
explicit empty-resource disposition when its data or HARQ-ACK occasion hits
fixed opposite-direction, guard or unused TDD symbols. Do not issue/move the
grant or allocate HARQ state. Missing timing authority and malformed timing
still throw; the exception now includes the canonical `ReasonCode` as well
as `Diagnostic`. Extended `testSchedulerSSBResourceSelection` for RR/PF,
unchanged HARQ state, exact source/target-slot evidence and missing-context
rejection. Native execution is pending; this is not yet a verified closure.

`testMobilityControlLoop` now installs explicit test-owned Type-0/SIB1 and
DL-to-UL ACK timing inputs from `scheduler_feedback_timing.yaml`, retaining
TDD, waveform execution and both DL/UL traffic. It preserves configuration
and complete output under `results/sls/mobility_control_loop/`. Native
verification is pending; the fix does not assert that the separate physical
SRS integration gap has been closed.

The bounded richness run's PHY bundle returned `Ok=1`, but its subsequent
acceptance evaluation recorded six failures in the retained
`reports/csv/case_status.csv` (run `richness_20261004_061753_598`):

| Failed check | Retained cause / next repair boundary |
| --- | --- |
| Strict PDCCH and PUCCH | `runtime_scenario_or_config_identity_mismatch`. The runner uses the in-path evaluator for isolated waveform components; binding an identity alone must not promote those components into connected-runtime evidence. Resolve the declared evidence scope and preserve integrated guards. |
| PRACH strict anchor | Missing `random_access.statistical_qualification`; explicit fixture configuration is required, not a production default invented by the validator. |
| SRS strict anchor | Only `corrupted_srs_symbols` was unexpectedly accepted (metric 0.89484). The other seven negative cases were rejected. Its waveform corruption is scaled by full-waveform amplitude deviation, so pilot occupancy changes the disturbance seen on SRS REs. Diagnose/qualify the fault population rather than tuning the receiver threshold against this observation. |
| SIB1 strict anchor | The validator was requested although YAML disabled SIB1 (`SIB1DisabledByYAML`). Reconcile fixture intent and enabled execution; do not invent decoded SIB1. |
| MIMO configured/effective | Early trials retain configured MCS 10 without applied feedback, yet generic decoration labels them `runtime_cqi_to_amc`. Later trials do apply feedback. Correct producer/bootstrap lineage and verify the contract; do not turn `LinkAdaptationApplied` on just to pass the export gate. |

Later finalization additionally reports roundtrip mismatches and missing
runtime evidence. These are not yet reconciled or fixed. The run is still
finalizing, so no terminal test pass or new original-48 closure is claimed.
`testLLSResultRichness` now saves `test_output.mat` before asserting `out.Ok`
on future invocations, preserving failed runner return values for diagnosis.

The scope audit exposed a separate fail-open route in
`evaluateInPathComponentEvidence.m`: explicit isolated/component-anchor rows
were not rejected on scope before evaluating their receiver outcomes. Added
a scope guard for the producer classification, declared evidence scope,
runtime consumer and explicit `SameScenarioInPathEligible=false`. Rejection
preserves the original table and does not label it as connected reception.
Extended `testInPathComponentEvidenceEvaluation` with successful isolated
PUCCH rows under each marker. Static checking passes (one pre-existing unused
function warning); native verification remains pending. This guard is not
the report-fixture scope repair and does not close its six failed checks.

Only two affected checks are queued after the existing richness process
exits: `testSchedulerSSBResourceSelection` and
`testPUCCHComponentProbeBinding`, with output in
`logs/scheduler_tdd_pucch_delay_focused_20261004.log` and its MAT report.
The queue waits for that process; it does not launch a concurrent MATLAB
engine or a full suite. Run the additional in-path scope guard separately
after this queue completes. No new full scenario or testAll was started.

### 2026-10-04 strict SRS anchor: noise plane and corruption fixture repair

Source inspection confirmed `applySRSChannel.m` used average sample power
to label an occupied-RE SNR sweep, including idle symbols and unused
subcarriers. Its no-signal branch instead used a unit sample-domain noise
variance reference. Neither matched the common production occupied-RE
definition. It now calls `addOccupiedREAWGN` with the actual transmitted SRS
symbol energy and executed FFT/sample-rate/windowing metadata. The same
reference remains in place for no-signal and corrupted-symbol episodes.
Exports disclose sample-domain variance, grid-domain reference variance,
transform gain and reference plane. The helper executes an AWGN component
anchor, so the applied model is now explicitly AWGN, with the requested
parent model retained separately; it does not claim to have executed TDL.

The corrupted-symbol negative case previously added noise proportional to
the whole waveform's amplitude deviation. Sparse occupancy could leave the
occupied reference symbols largely intact (the retained wide-carrier case
had correlation 0.89484). The new, version-labelled diagnostic applies
independent uniform phase errors to the actual occupied SRS REs and
remodulates them, preserving each RE's energy. No receiver threshold,
channel-estimator criterion or negative-case assertion was changed. This is
a new explicitly identified fault population, not a relabelled pass for the
old additive-noise observation or statistical detector qualification.

Extended `testSharedOccupiedREAWGNPath` with native Toolbox generation and
independent demodulation at 24/273 PRBs and RE energies 1/0.25. It checks
measured noise variance, identical no-signal noise reference, actual AWGN
labelling, and occupied-symbol corruption without an RE-power change.
Static checking passes; native execution and the original
`testSRSCorruptedSymbolsNegative` remain pending the current bounded test
queue. Do not claim these repairs passed before those results exist.

Reference for the OFDM noise-plane distinction:
[MathWorks SNR definition in link simulations](https://www.mathworks.com/help/5g/ug/snr-definition-used-in-link-simulations.html).
The diagnostic's corruption model is not asserted to be a 3GPP-mandated RF
impairment or an oscillator qualification profile.

### 2026-10-04 disabled SIB1 incorrectly selected by PBCH/SSB evidence policy

The retained richness diagnostic reports `SIB1DisabledByYAML`. The selector
in `resolveStrictSupplementalEvidencePolicy.m` combined SIB1, PBCH and SSB
enable flags with OR, then treated PBCH/SSB targets as permission to execute
SIB1. Thus an isolated PBCH/SSB bundle could launch a deliberately disabled
SIB1 producer. The selector now distinguishes the actual SIB1 enable flag
from related broadcast targets. Explicit SIB1 targets/objectives and required
acquisition obligations still invoke validation when disabled, preserving the
producer's configuration failure instead of silently skipping a requirement.

Extended `testSIB1StrictMiniAnchorWiring` covers PBCH/SSB-only with SIB1 off,
explicit disabled SIB1, required disabled SIB1, and enabled broadcast SIB1.
Static analysis reports no errors (only existing redundant-suppression
notices); native focused verification remains pending. This does not close
the original report-richness test, its other five failed checks, or any
statistical/production SLS acceptance gate. The currently executing report
diagnostic started before this repair and is not final-source evidence.

Native verification is now queued behind the existing two-test scheduler/
PUCCH batch, not in parallel with another MATLAB engine. The five affected
checks are `testSIB1StrictMiniAnchorWiring`,
`testInPathComponentEvidenceEvaluation`, `testSharedOccupiedREAWGNPath`,
`testSRSCorruptedSymbolsNegative`, and
`testSRSScoringReferenceIndependence`. Their terminal report will be retained
in `logs/srs_scope_sib1_focused_20261004.log` and the matching MAT file.
Queued is not running or passing; no original failure count is reduced yet.

### 2026-10-04 retained standalone adaptation decision lineage

Source tracing found a second adaptation-evidence defect alongside the
richness bootstrap mismatch. `updateLinkAdaptationState` correctly retained
`CurrentConfig` between feedback updates, but its `Applied=false` event was
used by both throughput producers to erase the decision lineage for those
held operating points. The event now separately reports `DecisionInEffect`;
`Applied` still means a new update occurred at this slot. The state retains
the actual applied decision and its source slot. Held events preserve the
original application slot and report the current feedback age, without
reapplying a decision or updating OLLA. DL and UL producers consume this
distinction. Bootstrap and legacy states without recorded lineage remain
unproven; no receiver CQI is retroactively attached to the transmitted TB.

Extended `testLinkAdaptationFeedbackDelayAuthority` covers pre-delivery
bootstrap, application, held DL/UL decisions, pending replacements, legacy
missing lineage, corrupted causal slots and cross-direction reuse. Static
analysis passes apart from existing informational notices. Native testing
is pending; this is not evidence that the separate initial-MCS/bootstrap
contract or the report-richness acceptance failure is closed.

The waiting SRS/scope/SIB1 batch was replaced before it launched (no MATLAB
child and no batch log existed), adding the two affected adaptation tests.
It still waits for the scheduler/PUCCH batch and uses the same log/MAT paths;
there is no duplicate batch or additional concurrent MATLAB engine.

### 2026-10-04 joint-sweep trial-key audit repair: verified

The richness materializer exposed eight false duplicate-key findings in
each DL and UL primary table. Both SNR points (18 and 30 dB) restart local
frame/slot/seed numbering, but `_audit_link_table` in
`tools/lls_csv_semantics.py` keyed only direction/frame/slot/UE/HARQ/execution.
The joint-sweep key now includes numeric configured SNR (legacy `SNR_dB`
alias supported), never receiver-measured SINR. Numeric spelling is
normalized so `18` and `18.0` remain the same point. Fixed-link campaign
point/drop/trial identity remains unchanged.

All **97 tests in `tests/test_lls_csv_semantics.py` passed** using
`C:/ProgramData/anaconda3/python.exe -m pytest tests/test_lls_csv_semantics.py -q`
(6.96 seconds). The WebGUI virtual environment lacked pytest; no package was
installed there. A read-only audit of the retained richness primary tables
then verified the key check for all **16 DL and 16 UL rows**, zero duplicate
findings. Negative tests retain rejection of actual same-point duplicates,
including alternative numeric spelling and changed measured SINR.

This verifies only the key repair. Missing component/scenario identities,
connected-versus-isolated evidence scope, bootstrap operating-point evidence,
and the remaining finalization requirements are still open. The live
diagnostic's historical failure is preserved; its files were not rewritten
or relabelled as a passing scenario.

### 2026-10-04 standalone identity and PBCH capture publication

`localCollectTrialsAcrossSweep` wrote standalone control/reference rows
before lifecycle binding; only the coupled branch later bound all control
tables. Added `bindComponentExecutionIdentity` at the fresh standalone
collector boundary, including the separate PRACH collector. It uses the
existing immutable identity checks and sets `EvidenceScope=component_anchor`
and `SameScenarioInPathEligible=false` before the first CSV write. It does
not change measurements, receiver outcomes or source classifications, does
not invent a missing low-level lifecycle, and rejects contradictory identity
or already-in-path scope. `testComponentExecutionIdentity` covers identity,
scope, idempotence, source preservation and rejection by the in-path
evaluator. Static analysis passes; native verification is pending.

The terminal PBCH timeline failure had real sample-clock evidence: start 0,
end 614400, sample rate 122880000 Hz, completion 0.005 s. Its producer labels
the clock `actual_complete_pbch_receiver_input_sample_extent`; the renderer
accepted only the connected-runtime clock label and required UE/cell IDs
that these isolated component observations do not carry. The renderer now
has an explicitly isolated branch using the measured extent and actual
seed/frame/slot identity. It preserves blank UE/cell fields and separates
independent realizations and SNR points; it does not turn them into a
connected UE or beam timeline. Missing/corrupt clocks, proxy rows, mixed
component/connected populations and attempted in-path promotion still fail.

The focused Python sparse-signal/semantic suite passed **111 tests** in
8.29 seconds before the final additional scope-negative assertions. A
read-only invocation on the retained four PBCH rows successfully constructed
four distinct component captures without rewriting retained files. The full
report scenario still fails; these results prove only this plot/identity
repair scope, not final publication, link reliability or complete SLS.

After adding explicit mixed-scope/promotion negatives and the component
image-status label, all **14 sparse-signal tests passed** (1.87 seconds).
The already-queued `testInPathComponentEvidenceEvaluation` also now exercises
the real component producer binder and verifies that adding immutable run
identity does not make a successful isolated PUCCH row in-path eligible.

### 2026-10-04 explicit control-component acceptance scope

The standalone bidirectional waveform bundle collected actual PDCCH and
PUCCH observations but `runSingle` unconditionally applied the connected
control validator. Missing identity was not the only defect: a component
PDCCH has no issued connected grant, and isolated PUCCH has no connected
HARQ lifecycle. The scenario now explicitly selects the existing YAML
`validation.strict_component_evidence` component-anchor scope for these two
families. The control policy defaults to in-path when unspecified and rejects
component scope for required causal control, slot-coupled execution, or
PUSCH-UCI. The system-level runner retains its in-path validator.

`evaluateConfiguredControlEvidence` dispatches on that resolved policy,
never on missing rows or failed outcomes. `evaluateComponentControlEvidence`
requires immutable run/config identity, explicit component scope, actual
receiver/decode evidence, matching positive integer payload lengths and zero
bit errors, plus CRC where applicable. It preserves the input table and
marks connected-runtime and statistical-detector eligibility false. Component
KPI names and notes now disclose their scope; no supplemental waveforms or
replacement rows are generated by this validator.

`testComponentControlEvidenceScope` covers exact payload/CRC failures, wrong
identity, proxy rows, missing evidence, attempted promotion, required-control
conflicts and default in-path behavior. It is included as a small guard in
the already-queued in-path evaluator test; no additional MATLAB engine or
full suite was started. MATLAB Code Analyzer and the targeted whitespace
check pass. Native verification and the original richness regression remain
pending; the original-failure closure count therefore remains 32/48, not
increased by this staged repair. Existing active jobs use mixed source and
cannot constitute final-source acceptance.

### 2026-10-04 initial MCS execution and terminal error preservation

The standalone adaptation state initialized `CurrentConfig` directly from
the fixed PDSCH/PUSCH fields and never applied the configured adaptive
`initialMCSIndex`. In the retained report fixture this executed MCS 10 while
the adaptive initial-MCS authority was 1. Initialization now resolves the
direction-specific MCS table, validates the initial index and ceiling, and
sets the actual modulation/code rate/index before the first transmission.
It does not change layers, the other direction, fixed-MCS calibration, or a
resumed state. Bootstrap is not a receiver decision: its source slot stays
unavailable and Applied/DecisionInEffect stay false until actual feedback
arrives. The DL/UL raw producers now publish `configured_initial_mcs` and
`bootstrap_not_measured_cqi` for these transmissions. The queued feedback
delay test includes DL/UL initialization, fixed-policy preservation, invalid
indices and delayed-feedback ownership checks. Static analysis passes;
native verification is pending. The MIMO summary's separate bootstrap and
standalone decision-lineage reconciliation is still open and is not marked
closed by this core repair.

The active richness diagnostic reached a second diagnostic-rendering defect
at 01:56:17 UTC: `MATLAB:error:nonScalarInput`. Its preserved stack identifies
the terminal fixed-point error in `runSingle`. That branch passed a two-element
string array to `%s`, masking the underlying publication convergence failure.
It now concatenates a scalar string and preserves the intended
`sixgr:lls6g:TerminalArtifactFixedPointFailed` identifier. The existing exact
production-statement test now covers this runner branch in addition to the
recovery branches. This does not waive terminal convergence or make the run
pass. The existing job remains live in artifact recovery; no replacement
run or full suite was started.

The user subsequently approved stopping the failed richness diagnostic.
PID 22788 was revalidated against its exact log/test command and stopped;
its log, raw trial CSVs, plot artifacts, failure history and checkpoint files
were preserved. No result was relabeled a pass. Artifact recovery was
interrupted, so terminal export completeness remains unproven. The other
MATLAB engine (3380) and its workers were not stopped. The existing waiting
two-test scheduler/PUCCH batch was left intact to start when 22788 exited.

### 2026-10-04 MIMO bootstrap versus applied feedback reconciliation

The MIMO exporter previously required `LinkAdaptationScheduled` (a decision
queued after this TB) together with `LinkAdaptationApplied` (the decision
that owned this TB), and used the current receiver CQI as its adaptive
evidence. It now exports/checks the actually applied decision MCS, CQI,
source slot, age and configured delay. Same/future-source, missing-clock and
wrong-MCS decisions fail; a held decision does not require another update
to be scheduled at every TB. Current receiver CQI is still exported as its
own measurement and is not retroactively applied to the transmitted block.

Explicit `configured_initial_mcs` rows are checked against the configured
initial MCS/modulation and require absent applied-feedback state. They can
conform to the operating-point contract but do not count as observed
adaptive feedback. The aggregate still rejects a bootstrap-only campaign.
UL configured MCS-table provenance now reads the UL field rather than
preferentially copying the DL table. `testMIMONominalVsEffectiveRankEvidence`
adds mixed/bootstrap-only, held-feedback, wrong-decision and causal-clock
cases; its algebraic fixtures explicitly declare the simulated causal fields.
Static analysis/whitespace checks pass. Three affected MIMO/identity/error
guards are queued serially after the existing seven-test batch, with one
log `logs/mimo_causal_ownership_focused_20261004.log`; no additional MATLAB
engine runs concurrently and no full suite was requested. Native results
remain pending.

### 2026-10-04 focused queue results after the authorized diagnostic stop

The two scheduler/PUCCH checks passed in
`logs/scheduler_tdd_pucch_delay_focused_20261004.log`. Six of seven checks
passed in `logs/srs_scope_sib1_focused_20261004.log`: stateful adaptation,
SIB1 selection, component/in-path evidence separation, occupied-RE AWGN,
SRS corruption rejection and scoring-reference independence. At 273 PRBs,
the SRS noise error was 0.001805 dB for both reference energies 1 and 0.25;
the independent occupied-SRS-RE phase-corruption case was rejected. These
are component results, not statistical receiver or integrated acceptance.

The feedback-delay test exposed two fixture defects: it expected a new
operating point from unchanged CQI, and left the UL policy fixed while
expecting UL adaptation. The test now explicitly verifies `no_change`, then
uses changed CQI for delayed replacement and explicitly enables UL AMC.
No production decision was forced to make this test pass.

The MIMO/identity/terminal batch passed component identity and scalar
terminal-error diagnostics. The MIMO test exposed a production ordering
defect introduced by the causal-policy dependency: the exporter counted
accepted feedback before evaluating that policy, reading its default false
value. The observation reduction now follows the causal-policy check.
Only the two failed checks were rerun in
`logs/mimo_feedback_repair_rerun_20261004.log`: feedback-delay authority
passed in 2.31 seconds and MIMO evidence passed in 21.11 seconds, with the
MAT report retained alongside the log. All 12 distinct tests across these
focused batches now have passing results. The historical original-48
inventory is still 32 later passing,
16 open; these auxiliary checks do not by themselves close original failures.
No full `testAll` or agenda-item change was made.

### 2026-10-04 independent-calibration reciprocity and original grant test

The retained richness source explicitly selects `independent_link_sweep`
with DL and UL `phy_calibration`; all 16 DL and 16 UL rows declare the
corresponding isolated producer taxonomy. The semantic auditor previously
required a common reciprocal channel timeline solely from TDD/fading/Doppler
configuration. It now verifies the explicit configuration and every producer
row before marking connected reciprocity **not required, not evaluated and
not passed**. This does not qualify independent calibration as a connected
link. Unknown, mixed, missing or falsely connected producer evidence still
fails. The connected reciprocity checks are unchanged.

Both affected Python tests pass (`pytest tests/test_lls_csv_semantics.py -q
-k dynamic_tdd`). A read-only audit of the retained 32 actual rows confirms
the same scope classification without modifying any retained run artifacts.
PRACH statistical configuration and overall terminal closure remain open.

`testGrantTraceIntegrity` previously stopped before its assertions because
the default fixture lacked received timing/Type-0 installation. It now uses
the already-tested two-UE cold-access fixture with deterministic DL traffic
and enough slots for both actual attaches. Strict validation and the fading
path remain enabled, the original TBS/proxy/backend assertions remain, and
an additional assertion requires both received access bindings and both
UEs' executed grants. Outputs are preserved under
`results/sls/grant_trace_integrity/`; the dedicated original-test rerun is
active in `logs/grant_trace_received_access_20261004.log`. No closure is
claimed until that original test finishes successfully.

### 2026-10-04 control producer provenance repair

The shared PDCCH row producer unconditionally used `active_integrated` and
`coupled_slot_runtime`, including calls with no scheduled grant context.
Those calls now declare isolated component execution. The four-step PRACH
row producer likewise declared a `CoupledTruthRuntime.applyPRACHTrial`
consumer even when the standalone collector supplied no runtime slot; that
case now has an explicitly absent runtime consumer. Actual grant-owned
PDCCH and slot-owned RA retain their connected labels. CRC, errors, signal
measurements and procedure-stage outcomes are unchanged.

Fresh standalone SRS/TRS/PRACH collectors could also leave classification
blank, allowing the generic exporter to supply a connected default. The
component identity binder now fills only an absent/blank classification
with its known isolated scope, preserving explicit failure/proxy labels.
The extended `testComponentExecutionIdentity` verifies the exact producer
statements and canonical exports, including full-RA fields, missing labels,
failure labels and proxy labels. This is a metadata contract check, not
another physical or statistical qualification claim. It is queued after
the original grant-trace test in `logs/control_producer_scope_20261004.log`.
Static syntax/whitespace checks pass; native verification remains pending.
Current jobs are diagnostic source snapshots, not frozen-source acceptance.

The original `testGrantTraceIntegrity` subsequently passed in 447.95 seconds
(`logs/grant_trace_received_access_20261004.log` and matching MAT report).
All 70 slots completed, both received access bindings and both UEs' executed
DL grants satisfied the added assertion, and final system served bits were
4,992. This closes one original failure, updating the working original-48
count to **33 later passing / 15 open**, not final-source acceptance.

The original artifact-naming test has the same retained
`MissingType0MonitoringOccasion`/`InvalidFeedbackTimingList` fixture failure.
`testE2E_TruthArtifactNaming` now uses the same received-access fixture,
preserves its evidence, and keeps all original naming/semantics assertions
plus the two-UE received-access/grant assertion. Static checks pass; its
original-test rerun has not started. The pending component-label check must
finish before another serial CLI test is launched.

The component-label check subsequently passed in 4.93 seconds; its log and
MAT report are retained at `logs/control_producer_scope_20261004.*`.
The original artifact-naming test is now the only serial CLI test running,
with evidence at `logs/truth_artifact_naming_received_access_20261004.*`.
The stopped failed richness diagnostic (PID 22788) remains stopped, with
all its outputs preserved; the other existing MATLAB job was not stopped.
No full `testAll` was launched. The working original-failure count remains
33 later passing / 15 open until another original test actually passes.

### 2026-10-04 bidirectional packet-accounting dependency

The retained original `testE2E_SummaryRawConsistency` failure stops before
packet replay with missing Type-0 monitoring and installed K1-list errors.
Its fixture now uses the received-access configuration while preserving
the original two-UE, bidirectional mMTC traffic settings and every original
accounting assertion. Its formerly implicit traffic flow is declared
explicitly, with the same configured rates, packet sizes, jitter and QoS.
It preserves results and requires real access for both UEs plus executed
DL/UL grants and packet populations. MATLAB static syntax and whitespace
checks pass. This is staged, **not a verified original-test closure**.

The original UL chunk-metadata rerun already exposes the next production
dependency in `logs/e2e_grant_projection_dl_ul_20261004.log`: UL scheduling
at slots 29/34/39 rejects `MissingSRSState`. Inspection identifies the
backend boundary rather than a missing scalar configuration default:

| Location | Current evidence | Required integration |
|---|---|---|
| `+sixgr/+system/WaveformPHY.m` | Grant replay exposes decode/mapBLER, but no causal sounding producer or delivery lifecycle. | Execute configured sounding through the physical channel/receiver and retain owner, resource, completion and availability evidence. |
| `+sixgr/+system/SystemLevelRunner.m` | Spatial feedback advance and committed capture are currently called only for the calibrated backend. | Wire physical waveform feedback to the corresponding scheduler state, without labeling ideal/modelled feedback as physical SRS. |
| `+sixgr/+system/resolveReceivedAccessULTiming.m` | Received access provides timing; explicitly reports `PhysicalSRSReceived=false`. | Keep access timing separate from measured sounding. Do not repurpose RA receipts as spatial measurements. |
| `+sixgr/+phy/+ul/resolvePUSCHPrecoding.m` | Correctly rejects missing causal SRS identity/slot. | Retain the guard; supply real eligible evidence from the producer, including freshness and UE/cell ownership. |

The physical codebook dependency is distinct from the calibrated SLS
ideal-delayed-feedback integration and its still-unqualified curves.
Further inspection of `core_parameter_catalog.yaml` confirms that the
original summary/raw test used **non-codebook, one-layer PUSCH**. The
received-access helper had unintentionally changed that fixture to
codebook PUSCH. The test now explicitly restores its original UL scheme
and layer count from the catalog while preserving the new access, grants
and bidirectional packet assertions. This is not a repair or qualification
of the missing physical codebook-SRS producer; that gap remains open.

The original `testE2E_TruthArtifactNaming` passed in 585.74 seconds, with
70 slots, actual two-UE received access and executed grants. Evidence:
`logs/truth_artifact_naming_received_access_20261004.log` and its MAT report.
The working original-48 inventory is now **34 later passing / 14 open**.
This is diagnostic mixed-source evidence, not frozen-source acceptance.

### 2026-10-04 deadline/QoS reporting fixture repairs staged

`testE2E_DeadlineMissAccounting` and `testE2E_QoSvsSemanticReporting`
retain three UEs, bidirectional XR traffic, the 0.1-ms deadline, the
512-byte RLC chunk and every original accounting/QoS assertion. They now
use explicit received-access/control setup and retain results rather than
deleting them on test exit. The shared test fixture supports three UEs and
an explicitly selected original catalog traffic profile. Its existing
DL-only traceReplay callers are unchanged.

The explicit flow carries the same 0.1-ms deadline as the run-level traffic
configuration, avoiding a stale inherited 50-ms flow deadline. Both tests
add non-vacuous checks for all three access bindings, DL/UL grants and
generated packets in both directions. These are bounded one-cell reporting
regressions, not multi-cell geometry, codebook-SRS or mobility qualification.
Static MATLAB syntax and diff checks pass; neither original test has been
rerun yet. Only `testE2E_SummaryRawConsistency` is currently executing in
the serial CLI engine (`logs/summary_raw_received_access_20261004.*`).
The original-failure count remains 34 later passing / 14 open.

`testStrictnessMetadataConsistency` is also staged. Its retained original
failure is `AttachFailedStrict`, caused by `MissingControlGatingConfig`,
before metadata assertions. Both branches now receive the explicit access
fixture while preserving their opposite campaign/E2E strictness settings,
the two UEs, mMTC/XR traffic choices and seed 41. Added assertions require
the exact requested strictness flags (not just agreement between two wrong
exports), actual access for both UEs and DL/UL grants. Evidence is retained
under `results/sls/strictness_metadata/`. Static syntax and whitespace
checks pass; the two-branch original rerun has not started. No calibration
provenance assertion was removed, and no strict production guard was changed.

The original `testE2E_SummaryRawConsistency` subsequently **passed in
484.41 seconds** (`logs/summary_raw_received_access_20261004.log` and MAT).
The run executed 70 slots with both UEs' received access and actual DL and
UL grants; all original raw/summary packet-conservation and latency checks
passed. Working original-48 count: **35 later passing / 13 open**.

The next serial CLI job runs `testE2EReportingFixtureConfiguration` first:
seeded DL/UL offered-bit matrices must match the original catalog traffic
for mMTC/XR, seeds 23/29/41 and 50/0.1-ms budgets. Only if that check passes
does it launch the two original deadline/QoS tests. Evidence is retained in
`logs/deadline_qos_received_access_20261004.log` and the corresponding MAT
reports. No full suite, new study campaign or agenda-item modification is
part of this job. Physical codebook-SRS integration remains open.

### PRACH report preflight repair and focused execution (4 October)

`testE2EReportingFixtureConfiguration` passed in 47.87 seconds. The existing
serial CLI job has proceeded to the original deadline-accounting test; the
QoS-reporting test follows it. Neither original is counted as passing before
its native result arrives. The working original-48 count remains 35 later
passing / 13 open, across diagnostic source revisions.

The retained report-richness `case_status.csv` identifies a separate concrete
failure: `PRACH_StrictValidation` raised
`sixgr:phy:prach:MissingStatisticalQualificationConfig`. Its inherited
`lls_100mhz_tdlc_bidirectional_truth.yaml` requested strict PRACH validation
without a statistical design. Added an explicit reusable
`validation/prach_statistical_qualification.yaml` inheritance with the existing
canonical design: 3,000–12,000 noise trials, 300–2,000 detection trials, 0.001
false-alarm / 0.01 missed-detection targets, 95% confidence, separate declared
seeds and planned sequential looks. These are simulator qualification-policy
settings, not 3GPP-mandated populations or a claim of a qualified detector.

`runSingle.m` now validates the required PRACH campaign configuration before
the data waveform bundle. In-path access without a requested statistical
campaign remains independent of this preflight. No PRACH threshold, physical
receiver outcome, statistical gate or original report assertion was relaxed.
The YAML-authority regression now checks both the 100-MHz parent and richness
fixture and rejects missing, disabled and insufficient-look designs.

JSON/YAML syntax, sequential budget bounds, MATLAB static analysis and scoped
whitespace checks pass. Native YAML-authority verification is still pending
behind the running deadline/QoS job; no new MATLAB engine or full suite was
launched for this repair. Full report-richness acceptance and the physical
PRACH campaign remain unverified, not closed by these static checks.

`testE2E_DeadlineMissAccounting` subsequently **passed in 694.65 seconds**
in `logs/deadline_qos_received_access_20261004.log`. Its preserved run is
`results/sls/deadline_miss_accounting/20261004_082307_580/`.
Independent CSV inspection confirms three received access bindings
(completion slots 0-based: 34, 54, 74), 12 executed DL grants and five UL
grants. Packet integrity records 520 DL and 150 UL generated packets, all
670 correctly marked as deadline misses against the deliberately sub-slot
0.1-ms budget, with accounting-integrity checks passing. Mean delivered
packet latency is unavailable in this case; it is not a latency-performance
qualification. The preserved original assertions and added non-vacuous
access/grant checks passed without changing receiver or accounting guards.

Working original-48 count: **36 later passing / 12 open**, still diagnostic
mixed-source evidence. The same serial MATLAB batch has advanced to
`testE2E_QoSvsSemanticReporting`, with evidence root
`results/sls/qos_vs_semantic_reporting/20261004_083442_444/`.
The new PRACH YAML-authority regression remains pending until that engine
finishes; no concurrent CLI engine or full suite was launched.

`testE2E_QoSvsSemanticReporting` **passed in 634.59 seconds** in the same
retained log; `logs/deadline_qos_received_access_20261004.mat` contains both
original results. The QoS run completed 100 slots with 12 DL and five UL
grants. Its summary correctly reports `QoSPass=0` for the deliberately
impossible packet budget while the original accounting/report-separation
assertions pass. This is not a positive QoS-performance result. Working
original-48 count is now **37 later passing / 11 open**.

Further RCA on `run_truth_validation_profile` found a second, independent
reporting defect behind its still-open mandatory-RACH failure: the entry
point accepts a scalar configuration struct but its settings exporter used
`char(string(opt.ConfigFile))`. Moved the unchanged physics/settings mapping
to `sixgr.truth.buildValidationSettings`, with explicit `file` versus
`in_memory_struct` provenance (no invented path), and invoke it before
expensive waveform execution. Added `testTruthValidationSettings` for both
input representations, JSON serialization and malformed-input rejection;
registered it for a future authorized suite, without launching `testAll`.
MATLAB static analysis and scoped whitespace checks pass. Native verification
is pending the serial slot; this metadata repair does not close the original
truth-validation profile's RA/configuration/runtime acceptance gap.

The previous CLI batch exited with code 0. Its successor is the single
serial focused batch in `logs/remaining_reporting_repairs_20261004.log`:

- `testTruthValidationSettings`: **PASS, 0.32 s**.
- `testPRACHStatisticalQualificationYAMLAuthority`: **PASS, 65.08 s**,
  including the parent/richness scenario inheritance and malformed-design
  rejection added above. No detector population was executed by this test.
- `testStrictnessMetadataConsistency`: next/running in the same batch; its
  original two-branch acceptance remains pending until the native result.

The first two reports are saved in
`logs/remaining_reporting_configuration_20261004.mat`. They verify the
metadata repair and PRACH configuration wiring, not the full truth-profile
or report-richness scenarios. Original-failure count remains **37 / 11**.

`testStrictnessMetadataConsistency` subsequently **passed in 815.24 s**:
both original strictness branches completed 70 slots with received access
and executed DL/UL grants. Evidence is retained in
`logs/remaining_reporting_repairs_20261004.log` and
`logs/strictness_metadata_received_access_20261004.mat`; run artifacts are
under `results/sls/strictness_metadata/20261004_084926_158/`.
The working original-48 count is **38 later passing / 10 open**, still
mixed-source diagnostic evidence, not frozen-source acceptance.

While tracing the still-missing waveform-backend SRS delivery, inspection
found another physical defect in `runSRSChannelEstimation.m`: the standalone
non-fading branch passes the original transmitted `x` to its tracking-Doppler
helper after ChannelFactory has already produced `y`. This discards a fixed
AWGN spatial matrix, including unequal TX/RX dimensions. Added
`testSRSFixedMatrixChannelPreservation` to check actual 2-port UE / 4-branch
gNB reception and a 6.02-dB received-power change on halving channel amplitude.
The before-fix native regression **failed in 51.30 s** with
`test:SRSFixedMatrixBranches`: both channel amplitudes produced only two
receive branches, and both reported exactly `-3.00997472561457` dB reference
power. Evidence: `logs/srs_fixed_matrix_before_repair_20261004.log/.mat` and
`results/lls/srs_fixed_matrix_channel/20261004_090555_406/channel_preservation.csv`.
Changed the tracking rotation's input from `x` to the already propagated `y`;
no channel normalization, estimator threshold or reported label was changed.
The after-fix regression plus fixed-matrix runtime, receiver/scoring
independence and 24-case SRS noise/despreading checks are running serially in
`logs/srs_fixed_matrix_repair_20261004.log`. This standalone-path repair is
separate from, and does not close, the causal SRS producer/completion
integration gap or qualify common/control/reference interference in SLS.

The serial after-fix batch exited **0**, with all four tests passing:

| Focused check | Result | Measured evidence |
|---|---|---|
| `testSRSFixedMatrixChannelPreservation` | PASS, 46.36 s | Four measured RX branches in both physical trials; reference power `-6.02064249291664` / `-12.0412424061963` dB, exactly the expected 6.0206-dB change; both complete receiver trials usable and passing. |
| `testFixedMatrixAWGNRuntime` | PASS, 14.63 s | Executed 4-by-2 DL / reciprocal 2-by-4 UL sample operators and matrix identity. |
| `testSRSScoringReferenceIndependence` | PASS, 0.71 s | Poisoning/removing scoring truth does not change practical noise or rank/TPMI estimates. |
| `testSRSReceiverNoiseDespreading` | PASS, 23.79 s | All 24 bandwidth/port/comb/hopping cases; maximum absolute noise error 0.308 dB, worst pilot NMSE -19.163 dB. |

Reports: `logs/srs_fixed_matrix_repair_20261004.log/.mat`. Physical matrix
measurements: `results/lls/srs_fixed_matrix_channel/20261004_090823_064/`.
Noise/despreading measurements:
`results/lls/srs_receiver_noise_despreading/20261004_090904_940/`.
The added matrix regression also requires complete usable receiver output;
partial channel estimates cannot conceal a later receiver exception. Original
48-failure count remains **38 / 10** (this newly discovered defect is not an
extra closure of an original failing test). No `testAll`, new full scenario,
agenda-file edit, calibration installation or study-acceptance claim occurred.

### Coupled bidirectional preflight: broadcast applicability and frequency placement

The original `test6GLLSCoupledTruthBidirectional` rerun failed in 484.03 s
before executing slots: Type-0 CORESET0 required RB interval `[2,26)` on a
25-RB initial DL BWP. Its log and structured report are
`logs/coupled_bidirectional_original_20261004.log/.mat`. The test now retains
its scratch evidence rather than deleting it on failure.

Two separate causes were found and repaired:

- `buildPlannedREAllocation.m` planned Type-0 merely because SSB/MIB were
  enabled, even with normalized `phy.sib1.enable=false`. It now follows the
  same SIB1 execution flag as the waveform runtime. Output selection no
  longer disables an unselected but required Type-0 dependency; selected-only
  SIB1 plans resolve that dependency without publishing unrequested rows.
  Enabled SIB1 with missing SSB/MIB authority remains an explicit failure.
- The inherited FDD `lls_causal_access_to_data_wiring.yaml` still selected
  CORESET0 index 0 despite its SSB starting in common RB 2. Changed
  `pdcch_config_sib1` from 2 to 18: index 1 gives a two-RB offset and the
  legal `[0,24)` CORESET, retaining SearchSpace0 index 2. The SSB frequency,
  carrier dimensions and receiver bounds check are unchanged.

The first focused batch retained the bad YAML failure (50.15 s) and passed
`testPDSCHOccasionAllocationPreflight` (47.46 s); evidence is in
`logs/broadcast_allocation_dependencies_20261004.log/.mat`. The extended
`testExactDLULAllocationPreflight` **passed in 51.49 s** after the YAML correction,
in `logs/broadcast_allocation_dependencies_repaired_20261004.log/.mat`. It checks
full-versus-selected exact rows, disabled broadcast obligations, canonical
configuration authority, and rejection of the old out-of-BWP configuration
and missing MIB/SSB dependencies.

This does not close the original coupled test. Its five-slot fixture also
disables access while shared-stream grants require received UL timing.
`PreAttachUEsBeforeMeasurement` is currently stored but has no execution
consumer; setting that flag alone is not a timing repair. No received TAG,
RAR or SRS evidence was invented. Original-48 count remains **38 / 10**;
the new focused checks are not a substitute for original-test acceptance.

The coupled fixture now enables the parent's physical SIB1 and four-step
RA procedure and gates data scheduling on received PBCH/access completion.
It retains FDD, two UEs, 2-by-2 spatial dimensions, fixed rank one, the
50-dB AWGN point, simultaneous DL/UL assertions, exact-TBS reconciliation,
HARQ, SRS lineage and all original data/export checks. The old assertion
that PRACH must be absent is replaced by the stronger requirement that
both UEs have actual `RACompleted` rows. The observation budget is 70 slots
to include separate access opportunities and connected data; no protocol
timer, decode threshold or received-timing guard was relaxed.

Focused verification is running in
`logs/coupled_bidirectional_received_access_20261004.log`, with artifacts in
`results/lls/coupled_bidirectional/20261004_093132_977/c/lls/lls_coupled_truth_smoke/smoke/`.
The out-of-BWP preflight failure cleared. At slot 6 this execution failed
with `sixgr:truth:PBCHPassedWithoutMeasuredBeamSelection`; it is preserving
partial artifacts, not accepted access or data evidence.

The runtime evidence corrected the earlier shared-owner assumption:
`ChannelFactory.requiresRuntimeChannelState` does not enable the shared
owner for plain AWGN. This fixture had never set
`channels.shared_identity_awgn_enabled`; SRS therefore ran as standalone
observations before attachment, and standalone PBCH lacked the measured
selection required by the coupled acquisition consumer. The fixture now
explicitly selects the existing shared identity-AWGN operator and asserts
its resolved runtime ownership and physical-access prerequisites before
execution. This last change awaits a serial rerun after the failed job
finishes recovery. The strict timing/beam-selection guards are unchanged.
No full suite or additional campaign was started; the other existing
MATLAB diagnostic is left untouched. Original-test closure remains pending.

The received-access diagnostic subsequently terminated with exit 1 and the
same PBCH selection error (637.53 s). Its structured report is retained in
`logs/coupled_bidirectional_received_access_20261004.mat`. Failed-run browser
recovery also reported missing DL/UL trial CSVs: no data grants had executed,
so those files must not be replaced by fabricated rows. This recovery failure
does not supersede the original physical-runtime exception.

After that engine exited, the explicit shared-owner rerun started serially in
`logs/coupled_bidirectional_shared_access_20261004.log`. Its evidence root is
`results/lls/coupled_bidirectional/20261004_094729_617/c/lls/lls_coupled_truth_smoke/smoke/`.
The pre-execution ownership/access assertions passed. Runtime acceptance is
still pending; neither the fixture change nor the new launch closes the
original test. No full suite was started.

That shared-owner execution reached slot 1 and then failed during broadcast
preparation, before any samples were advanced:
`sixgr:link:BroadcastPowerNormalizationGridUnavailable`. Static tracing gives
an exact configuration cause: the test overrides the parent's physical
SSB domain with `logical_rf_chain_post_analog_precoder`, whose SIB1 producer
correctly records `MatrixAppliedHere=false`. The fixed-EPRE grid collector
requires the actually applied physical-port matrix. Removed that fixture
override so the parent's two-element physical mapping is retained, and added
a resolved-domain assertion. No matrix, power estimate, receiver evidence or
fallback grid was synthesized; the production rejection is unchanged.
This correction awaits verification after the failed job finishes recovery.

The shared-owner failure terminated with exit 1 after 610.11 s; its report is
`logs/coupled_bidirectional_shared_access_20261004.mat`. Most of that elapsed
time followed the already-recorded slot-1 failure while recovery exported
diagnostics. The next serial check therefore isolates broadcast preparation
and reception, using the same retained fixture with only the physical-domain
correction. It saves the actual prepared transmission, resolved configuration
and all candidate receiver results in
`logs/coupled_broadcast_physical_mapping_20261004.mat`; its launcher log uses
the same stem. No original-test pass or SLS acceptance is inferred from this
smaller check.

The first probe launcher used `ScenarioConfig` as a mutable struct and failed
before PHY execution; the corrected launcher uses `toStruct`, revalidates and
hashes the modified configuration. Its actual receiver evidence is retained
in `logs/coupled_broadcast_physical_mapping_corrected_20261004.mat/.log`.
Physical preparation passed: one logical SI port was mapped by the actual
`[1/sqrt(2),1/sqrt(2)]` producer matrix into two waveform columns. All four
candidate PBCHs passed CRC and identity/strict receiver checks. The probe's
final assertion incorrectly demanded the normalized power column although
this direct component configuration uses the absolute measurement plane;
its finite measured SS-RSRPs are -2.009993, -2.008460, -2.009367 and
-2.009247 dBm, respectively. That launcher assertion is not evidence of
missing receiver power or acceptance of the integrated run.

The receiver evidence also exposes a separate multi-beam limitation: only
candidate 0 recovered SIB1; 1/2 failed SI-RNTI blind decoding and candidate 3
had no complete scheduled SIB1 slot in the capture. A four-candidate burst
with only one associated SI transmission cannot establish general multi-beam
access acceptance. This remains open for the beam-managed scenario and must
not be repaired by selecting a beam from transmitted SI success or inventing
missing SI samples.

The bidirectional test explicitly disables beam management and requests a
fixed first beam. Its fixture now declares the matching active bitmap `1000`
while retaining the physical two-element precoder and Lmax=4; a resolved
active-index assertion prevents accidental inheritance of a beam sweep. This
is scoped fixture correction, not a multi-beam production repair. The
original coupled test is running serially in
`logs/coupled_bidirectional_physical_access_20261004.log` and still must pass
both UEs' real access and every original connected DL/UL assertion. Original
48-failure closure remains 38 later passing / 10 unresolved.

### 2026-10-04 core-repair boundary (not fixture-only closure)

The original 48 failures remain the repair inventory. A later passing test
is not, on its own, proof that the corresponding production capability is
complete. In particular, the fixed-first-beam bidirectional fixture does
not qualify multi-beam SIB1, and received access timing does not supply a
physical SRS spatial-feedback producer to `WaveformPHY`.

The logical-domain broadcast preparation rejection is now repaired in
production code rather than avoided only through the fixture's physical
domain selection:

- `+sixgr/+link/broadcastSIB1WaveformPortGrid.m` resolves the exact emitted
  waveform-port grid from retained producer evidence. Physical-element
  samples require the actually applied matrix. Logical samples keep their
  single logical grid and `external_physical_projection_required` ownership.
  Missing or contradictory evidence remains an error.
- `+sixgr/+link/prepareCellSearchBroadcast.m` uses this grid for composite
  power normalization; it no longer requires a locally applied physical
  matrix for a legitimately logical waveform.
- `+sixgr/+truth/buildObservedBroadcastREAllocation.m` consumes the same
  domain contract for PDCCH/PDSCH exports, without claiming unexecuted ports.
- `testBroadcastWaveformPortGrid` independently demodulates actual SI
  samples in both domains, reconciles exact exported RE counts and rejects
  contradictory/missing mapping metadata. It is registered but no full
  suite is started. Static MATLAB and whitespace checks pass. Native
  verification passed all three tests in
  `logs/broadcast_port_domain_core_repair_20261004.log` (plus MAT report):
  `testBroadcastWaveformPortGrid` (49.21 s),
  `testObservedBroadcastREAllocation` (29.33 s), and
  `testNormalizedSSBBroadcastPower` (24.85 s). Independently demodulated SI
  grid errors were 2.26e-16 (physical) and 2.30e-16 (logical); emitted port
  counts were 2 and 1 respectively. The serial batch exited successfully.

The original coupled test has a terminal failed report (1274.4 s), after
both UEs acquired broadcast and UE 2 physically received Msg2/Msg3:
`logs/coupled_bidirectional_physical_access_20261004.log/.mat`.
Its root exception at slot 28 is `WAVEFORM:CommittedTransmission`, through
`CoupledWaveformStream.queueRA`, called by
`runWaveformLinkBundle.localCompleteSharedRAObservation` after a receive
completion. This is still OPEN. The next-stage enqueue must respect both
the actual receive-completion boundary and advanced UL transmit/observation
origins. Do not permit insertion into committed samples, synthesize a
missing received prefix, or merely increase fixture delays to hide it.
The retained stage/capture evidence is under
`results/lls/coupled_bidirectional/20261004_100724_176/c/lls/lls_coupled_truth_smoke/smoke/`.

These are mixed-source diagnostics, not a frozen-source acceptance run.
The original 48 count remains 38 later passing / 10 unresolved; the new
component repair does not close an original failing test until its original
runtime assertions pass. No agenda-item files are changed by this repair.

### 2026-10-04 audit of the 38 later-pass records before the remaining ten

User priority: production coverage of the 38 first, then the ten open
originals. **38 later-pass records is not 38 production-qualified features.**
Two records (`testPDCCH6GR`, `testLLSCoupledTruthHARQRoundTrip`) came from
explicit retained-run rechecks. The latter used a separately reprojected
HARQ CSV. These are useful export checks, not fresh final-source execution.
The remaining 36 have historical focused execution evidence with different
configuration/component scopes; they are not one frozen-source run.

| Audited tests / count | Production owner and acceptance boundary |
|---|---|
| `test5MHzSchedulerMinimumGrantPolicy`, `testSchedulerHARQStateUnblockAndLineage` / 2 | `SchedulerBase.m`, `SchedulerPF.m`, `SchedulerRR.m`, `HARQEntity.m`: actual timing, contiguous resources, exact scheduled DMRS/TBS and tentative-HARQ ownership. Authored feedback inputs do not qualify a feedback receiver. |
| `testDataChannelStreamStagesFDD`, `testUplinkControlStreamStages` / 2 | Shared staged channel/data/control completion, including `runSRSChannelEstimation.m`: actual sample/slot ownership and vacant-comb disturbance. This does not close missing SRS production in `WaveformPHY`. |
| `testPDCCH6GR`, `testDCITDRAFailureDiagnostics`, `testMIBPDCCHConfigSIB1Derivation` / 3 | `+ctrl/PDCCHBlindDetector.m`, `PDCCHDecoder.m`, `DCIContextFactory.m`, broadcast Type-0 producer/receiver: independent decoding, installed timing, actual MIB/control resources. Fresh PDCCH execution replaces the retained-only acceptance record only after terminal success. |
| `testPDSCH6GR`, `testTRSRuntimeControlGatingEvidenceContract` / 2 | Shared PDSCH study receiver and `runTRSTracking.m`: real demodulation, AGC/noise plane and honest residual-vs-NMSE/SINR semantics. An unavailable independent NMSE/SINR reference is not a measured zero or a qualification pass. |
| `testFourStepRARuntimeStageComposer`, `testPRACHRuntimeULDirectionAntennaContract`, `testRADownlinkPowerScaling`, `testRAStageCarrierSlotBinding`, `testRuntimeOperatingAuthority` / 5 | `runFourStepRA.m`, RA waveform builders, PRACH native-grid exporter and installed authority: decoded RAR timing, actual antenna domain/power, common-DL legality. Some component tests author the initial beam; they do not prove blind multi-beam acquisition or shared-stream continuation. |
| `testGeometryHybridAntennaDomain`, `testSLSMultiBeamMapping`, `testSLSNetworkSpatialProvider`, `testSystemNetworkDLCSI` / 4 | `freezePHYGrant.m`, `NetworkSpatialGrantProvider.m`, `SystemLevelRunner.m`: selected CSI beam/PMI basis, native channel/covariance and causal scheduler delivery. Numerical BLER fixtures and explicitly unqualified RF/array branches remain unqualified. |
| `testLLSMobile2UEScenarioYamlWiring`, `testLLSResolvedFeatureConfigAuthority`, `testPrompt2TopologySRSPRACHRuntimeWiring` / 3 | YAML plus `buildInternalConfig.m` and `CoupledTruthRuntime.m`: canonical calendar, power-control and frame/slot authority. Wiring checks alone do not prove mobile end-to-end completion. |
| `testLinkCalibrationResume` / 1 | `+calibration/executeEpisode.m`, `exportReferenceTrialRows.m`, source-key validation: actual retained episode and immutable resume identity. Not sufficient calibration populations. |
| `testLLSHARQExercise`, `testLLSCoupledTruthHARQRoundTrip` / 2 | `exportLLSHARQDiagnostics.m`, `runWaveformLinkBundle.m` and HARQ exports: real retransmission/recovery versus retained-output reprojection. Fresh shared-runtime HARQ remains to be verified. |
| `testLLSAvailabilityAggregation`, `testTwoModeAcceptanceGates`, `testTruthValidationControlCoverage` / 3 | Reporting reducers, mode gates and `prepareValidationConfig.m`: denominators, unavailable evidence and actual component control checks. Fixture rows remain test-only, not primary study evidence. |
| `testSystemLevelWaveformReplayEvidence` / 1 | `SystemLevelRunner.m`, `WaveformPHY.m`, `+waveform/replayGrant.m`, `exportSystemLevelCanonicalArtifacts.m`: real future-slot DL/UL replay, RNTI versus UE identity and measured receiver exports. Not simultaneous multi-cell sample-level interference. |
| `testArtifactVerificationScope`, `testPartialCampaignReportHonesty`, `testCalibrationProvenanceHonesty` / 3 | `sixgr_run_3gpp_full_campaign.m`, received-access binding and report exporters. Earlier passes used DL-only trace traffic; restored original XR/MMTC bidirectional intent and added both-direction grant assertions. These stronger versions await rerun. |
| `testE2E_DeadlineMissAccounting`, `testE2E_QoSvsSemanticReporting`, `testE2E_SummaryRawConsistency`, `testE2E_TruthArtifactNaming`, `testGrantTraceIntegrity`, `testStrictnessMetadataConsistency`, `testNoProxyTruthContract` / 7 | Campaign/runtime packet accounting, `resolveReceivedAccessULTiming.m`, actual grant replay and exports. Keep exact payload/CRC/deadline/provenance assertions; rank-one non-codebook reporting tests do not establish codebook SRS qualification. |

**New production defect found during this audit:** the PDCCH study receiver
used one average DMRS channel response for every payload RE even on fading
channels. `PDCCHEqualizer.m` also silently averaged incompatible antenna
dimensions. The repair uses native per-resource `nrChannelEstimate` for
explicit TDL/CDL profiles, retains flat averaging only for explicit AWGN,
and rejects mismatched resource/antenna dimensions. Equalizer noise is
propagated into the unit-gain demapper plane and through repetition weights;
the QPSK decoder receives per-RE variances instead of pre-equalization noise.
Candidate exports retain channel-estimator and LLR-noise sources.
`testPDCCHPerResourceChannel` checks native resource extraction, independent
equalizer/noise algebra, a one-RE/two-antenna boundary and dimension rejection.
The dedicated final-source `testPDCCHPerResourceChannel` passed in 5.07 s
(`logs/pdcch_per_resource_core_repair_20261004.log/.mat`), including actual
sample-filtered native TDL-C, per-resource channel extraction, propagated
noise and symbol-by-symbol native QPSK LLR comparisons. This is component
verification, not full fading-study qualification: `runPDCCHStudyLLS.m`
still explicitly labels its equivalent scalar fading study approximation.
Native API reference: https://www.mathworks.com/help/5g/ref/nrchannelestimate.html

The first fresh four-test batch passed the minimum-grant test (43.22 s),
then inherited automatic PDCCH worker-pool startup. Only that newly started
engine and its four workers were stopped; log/results remain in place as
incomplete (`logs/original38_core_control_recheck_20261004.log`). The older
MATLAB diagnostic was not stopped. The PDCCH focused fixture now explicitly
requests one worker without automatic pool startup; physical populations
and assertions are unchanged.

The serial retry (`logs/original38_core_serial_recheck_20261004.log`) passed
`testPDSCH6GR` (187.76 s) and `testTRSRuntimeControlGatingEvidenceContract`
(34.33 s), followed by `testPDCCH6GR` (678.92 s). Core PDCCH edits overlapped
this diagnostic, so its result is not frozen-source acceptance of the new
edits. Its publication warnings also exposed missing assertions and two
production export defects:

- `tools/lls_csv_semantics.py` rejected genuine PDCCH noise-only trials
  because target-signal SINR/EVM/NMSE were correctly unavailable. The H0
  exception now requires actual zero transmitted energy, positive received
  energy/noise, blind-decode trials and consistent CRC/false-alarm/status
  evidence. It rejects fabricated signal metrics. **99 semantic tests pass.**
- `apps/lls_contract_materializer.py` suppressed measured zero/one detector
  probabilities at a single SNR as placeholder curves. These are now
  explicitly observed scalar probabilities, with no interpolation or
  statistical-qualification claim. **41 materializer tests pass.**

Re-materializing the retained physical PDCCH output with `--strict` passed:
31 available tables, 163 policy-disabled tables, 32 available charts,
358 policy-disabled charts, zero missing/unavailable artifacts. No raw
physical observations were changed or replaced. This is a derivative
publication check, not a new PHY execution. The retained root is
`results/lls/pdcch6gr_regression/20261004_104622_418/lls/pdcch6gr_runner_smoke/pdcch6gr_runner_smoke`.

The strengthened PDCCH test now requires the actual four probability PNG/CSV
pairs. A serial four-test fresh-source batch is running in
`logs/original38_production_publication_recheck_20261004.log/.mat`:
`testPDCCH6GR`, `testArtifactVerificationScope`,
`testPartialCampaignReportHonesty`, `testCalibrationProvenanceHonesty`.
The last three retain their restored bidirectional requirements. Their
terminal results remain pending. No testAll, agenda-item campaign, or final
SLS qualification was started.

The fresh PDCCH test **passed at 11:14 IST in 773.53 s**, including its new
CSV/PNG assertions. It materialized 97 artifacts with zero missing
tables/charts; final truth reported `ok=1`, `evidenceMissing=0`,
`strictFailures=0`. The batch then started `testArtifactVerificationScope`;
the three bidirectional reporting tests have no terminal result yet.
The 38-record audit also identified a live-export ownership defect:
`CoupledTruthRuntime.writeTablesImpl` writes process-state rows to the
observation timeline filename, while `exportLLSLiveDerivedTables` later
writes raw-receiver observations to that same filename. The final reducer
has been repaired. The live writer now emits separate
`runtime_harq_process_summary.csv` and `runtime_harq_process_timeline.csv`
files. `testCoupledLiveExecutionIdentity` now checks that refreshing process
state leaves both receiver-observation files byte-for-byte unchanged. This
additional core repair passes static checks but awaits its native focused
rerun after the current serial batch. No retained physical files were changed.

Continuation checkpoint: `testArtifactVerificationScope` passed in 382.15 s
with the restored two-UE XR bidirectional assertions. The same serial batch
advanced to report honesty, followed by calibration provenance. The older
MCP status-propagation diagnostic was confirmed terminal from its saved
log/MAT (09:06 IST, 15875.97 s): PUSCH reported missing `DecisionInEffect`.
Current `updateLinkAdaptationState.m` already initializes that field for all
returns; the old execution overlapped its source update. This failure is
retained as a mixed-source observation requiring current-source reproduction,
not proof that today's producer lacks the field. The now-idle MCP session
is running only `testCoupledLiveExecutionIdentity` and
`testLLSHARQFailureRateTruth` in
`logs/harq_live_writer_ownership_repair_20261004.log/.mat`.

The HARQ ownership batch is terminal **2/2 PASS**:
`testCoupledLiveExecutionIdentity` (133.78 s) checks both TDD/FDD live-writer
ownership without replacing observation bytes; `testLLSHARQFailureRateTruth`
(19.07 s) verifies independent process/receiver accounting and sweep identity.
These are export-contract checks, not a fresh physical round trip. The idle
worker pool from the completed oversized diagnostic was closed, and its
MATLAB session now runs only the fresh, serial
`testLLSCoupledTruthHARQRoundTrip`, with no retained-folder arguments:
`logs/original38_fresh_harq_roundtrip_20261004.log/.mat`.

At 11:27 IST `testPartialCampaignReportHonesty` passed (387.19 s), again
with both-direction/two-UE assertions. The publication batch is 3 PASS,
0 FAIL, with calibration provenance still running. The HARQ ownership MAT
report was independently read back and confirms both component passes;
MCP captures console output internally, so its diary file is empty and must
not be cited as a populated transcript. The fresh HARQ physical run records
progress in
`results/lls/coupled_truth_harq_roundtrip/20261004_112453_721/bundle/air_interface/logs/run.log`.
Its focused terminal result is still pending. No full-suite rerun was started.

At 11:33 IST the serial production-publication batch finished **4/4 PASS**:
PDCCH (773.53 s), artifact scope (382.15 s), partial-report honesty
(387.19 s), and calibration-provenance honesty (388.07 s). The last three
now exercise the restored bidirectional, two-UE inputs, not the earlier
DL-only reductions. Their source/export assertions passed. The saved
`logs/original38_production_publication_recheck_20261004.mat` and populated
matching log are the terminal records. This does not qualify statistical
SLS calibration or the remaining ten original failures.

The fresh HARQ roundtrip's MCP call timed out after 300 s; the MATLAB engine
and its physical run continued. No duplicate was launched. At slot 31 it
had actual completed access and usable SRS/TRS. Its terminal result remains
pending until the saved focused report is present.

Read-only RCA of the outstanding FDD bidirectional failure distinguishes
Msg3-to-Msg4 from Msg4-to-SetupComplete timing. In the retained 10:07 run,
Msg3 reception ends at sample 207337, before Msg4 slot 27 starts at 207360.
Msg4's independent contention capture ends at sample 215040 (7.68 MSa/s).
The retained configuration allocates Msg4 symbols [2,12], followed by
SetupComplete symbols [0,14] at K2=1, with a 100-sample common UL timing
advance offset. Thus the next UL transmission starts before the complete
Msg4 observation is available. Full-slot Msg4 cannot be made causal by
discarding a zero prefix: this UL allocation starts at symbol zero.
The event stream correctly rejects transmission into committed samples.
This is not evidence that Msg3-to-Msg4 failed, nor a reason to relax the
stream guard. Repair must validate received-clock causality in core access
timing and provide a legal configured SRB1 occasion. No running-test PHY
source has been changed during this RCA.

### 2026-10-04 PDCCH production audit: diversity power and bundle estimation

The 38-record audit exposed a branch the one-TX PDCCH regression could not
cover. `runPDCCHStudyLLS` assigned unnormalized unit-modulus phases to every
TX dimension in REG-bundle mode, multiplying total transmitted energy by
NTx. Its `bundleFromRET` returned all ones, so every RE also used one bundle.
The replaced local mapper is now `applyPDCCHStudyTransmitDiversity.m`:
actual candidate REG identities select unit-norm weights, per-RE total
power is preserved, repetition coordinates remain explicit, and a private
random stream leaves the campaign RNG unchanged. Additional occupied input
ports or unmapped/duplicate REs are rejected, not discarded or invented.

The receiver needed the corresponding independent repair:
`PDCCHStudyDMRS.m` retains receiver-known REG identities;
`PDCCHChannelEstimator.m` estimates each configured AWGN REG bundle from
its own received DMRS. It no longer averages different precoder responses
into one channel or counts their deterministic phase changes as noise.
No transmitted weights are provided to that estimator. The scalar AWGN
shortcut remains only for the constant-precoder branch, and the existing
per-resource fading estimator is unchanged.

Focused terminal evidence:
`logs/pdcch_diversity_receiver_repair_20261004.log/.mat` records
`testPDCCHTransmitDiversityPower` PASS (10.69 s) and
`testPDCCHPerResourceChannel` PASS (5.74 s). The actual coded-runner rows in
`results/lls/pdcch_diversity_power/20261004_114847_476/power_trials.csv`
have TX energy 288 for each of 1, 2 and 4 TX dimensions, with all three CRC
and payload matches passing. Independent mapping checks cover 2/4/8 TX,
noncontiguous REG identities, repeated slots and invalid-input rejection.
The test now also explicitly asserts those observed coded-payload passes.
Its final strengthened version passed in 9.25 s in
`logs/pdcch_diversity_coded_acceptance_20261004.log/.mat`, retaining new
coded rows under `results/lls/pdcch_diversity_power/20261004_115108_916`.

These changes repair a generic control-study branch, not an agenda-item
configuration. Seeded phase cycling and the runner's equivalent scalar
fading remain explicitly study assumptions, not qualified NR beamforming
or native fading. The live HARQ run does not call this study branch and
continued through slot 39 with actual DL/UL observations. No testAll ran.

At this checkpoint the fresh HARQ run remains live at slot 41/58, with six
DL and two UL raw observations. Its terminal roundtrip assertions remain
unverified; the 300-s MCP observation timeout did not stop the engine.

### 2026-10-04 dual-mode production-path verification

The focused SLS batch terminated successfully (exit 0); its saved MAT was
independently read and all three `reports{k}.ok` values were true:

| Test | Terminal result | Scope / limitation |
|---|---|---|
| `testSystemNetworkDLCSI` | PASS, 234.67 s | Network-derived delayed CSI drives real scheduler grants, including rank 2 and combined HARQ/CSI/SR obligations. |
| `testSystemNetworkSpatialDelivery` | PASS, 97.38 s | No UL grants before causal modeled SRS delivery; late reservations reject execution before decode. |
| `testSystemAutomaticPUSCHUCI` | PASS, 187.70 s | Automatic UCI transport and completion, with ideal delayed control; physical UCI is not qualified by this test. |

Evidence: `logs/sls_dual_mode_feedback_recheck_20261004.log/.mat`.
All three use explicit **test-only BLER calibration**. Their channel and
scheduler integration is exercised, but this does not install production
calibration or qualify RF/arrays or common/control-channel interference.
The separate physical LLS HARQ roundtrip is still executing (slot 51/58 at
this checkpoint); no terminal LLS acceptance is inferred from SLS passes.

A cross-mode regression reproduced another production boundary defect:
`PhyFactory.create(cfg, struct('PHYBackend','waveform'))` selected the
waveform executor but retained `cfg.system.phyBackend` as
`calibrated_link_abstraction`. The original reproduction terminated with
`test:WaveformBackendAuthority`, retained in
`logs/cross_mode_feedback_reproduction_20261004.log`.
`WaveformPHY` now owns its actual backend identity. Both the waveform
executor (before audit deferral) and direct `waveform.replayGrant` check
the scheduler and frozen precoding bindings for modeled CSI/SRS authority.
Modeled feedback is not promoted to physical feedback by a mode override.
Focused DL/UL negative-path and ordinary waveform-backend regressions all
passed in `logs/cross_mode_feedback_repair_20261004.log/.mat`:
`testSLSDLCSIFeedback` (9.06 s), `testSLSCausalSpatialFeedback` (1.13 s),
`testWaveformReplayClock` (1.83 s), `testSLS_WaveformBackend` (201.34 s).
The latter executes eight slots with four UEs and actual DL waveform
decoding; it is not a UL physical-SRS qualification. The saved MAT reports
were independently checked. No agenda-item files or full-suite run were
used for this repair. The original 48-failure inventory is not reduced by
these additional cross-mode checks.

The current-source, four-slot `testLLSScenarioStatusPropagation` rerun was
started next, retaining `logs/lls_status_current_source_recheck_20261004.log/.mat`.
Its old oversized failure is not counted fixed until the current run
reaches the original terminal publication assertions. The independent
58-slot LLS HARQ run remains active at slot 54 at this checkpoint.

The first current-source status rerun terminated after 20.37 s at the
existing `SNRSweepNeedsAtLeastTwoPoints` validator: its four-slot fixture
declared an enabled sweep with one SNR point. The fixture now correctly
declares a disabled sweep at -10 dB; production validation was not relaxed.
`logs/lls_status_single_point_recheck_20261004.log/.mat` is the subsequent
run. It has reached physical execution with four slots and two realizations;
the original status/export assertions remain pending.

Backend selection has also been unified before scheduling:
`PhyFactory.resolveConfig` resolves and validates the existing backend
selector; both `SystemLevelRunner` and `PhyFactory.create` use that result.
Previously a runtime override selected the decoder but left the scheduler
and grant validation with the original backend identity. This change does
not install calibration, enable feedback, or alter receiver measurements.
The focused test now explicitly starts with a waveform configuration and
selects calibrated abstraction through the existing internal runner
parameter, retaining causal network CSI and all prior reservation/grant
assertions. Verification completed with exit 0 in
`logs/system_backend_authority_recheck_20261004.log/.mat`:
`testSLSDLCSIFeedback` PASS (13.47 s), `testSystemNetworkDLCSI` PASS
(258.10 s), and `testSLS_WaveformBackend` PASS (190.93 s). All saved MAT
report flags were independently read as true. This verifies runtime mode
selection and preserves the explicit test-calibration limitation.

The LLS HARQ run has executed all 58 slots and is now publishing terminal
artifacts. Raw observations include real RV=2 retransmissions in both DL
and UL; the derived timeline and final assertions are still pending.

Further access RCA found that `bindReceivedRARTiming.m` calls
`RAEventScheduler.resolve` without the `PDSCHResourceAvailability` callback
used by `RAConfig.m`. Thus receiving a RAR discards installed common-resource
ownership from the subsequent plan. A new assertion in
`testRADuplexAllocationTiming` checks preservation of SSB/SIB1/TRS ownership
after rebinding, with reproduction running in
`logs/received_rar_resource_reproduction_20261004.log`. No production
access-timing change had yet been made at that checkpoint.

The RAR reproduction subsequently terminated with
`test:ReceivedRARLostReservations`. The production repair now reuses
`CommonDLResourcePlan` in `bindReceivedRARTiming.m`, including the decoded
Msg2 PRB/symbol allocation. `testRADuplexAllocationTiming` passed in 65.52 s
in `logs/received_rar_resource_repair_20261004.log/.mat`; the actual coded
`testRARReceiveWindow` check also passed (29.07 s), including wrong-RAPID
rejection followed by received-RAR acceptance in TDD and FDD. Both saved
MAT result flags were independently checked; batch exit was 0. This does not yet close the
separate Msg4-to-SetupComplete timing-advance/K2 issue.

The fresh `testLLSCoupledTruthHARQRoundTrip` terminated PASS in 3799.98 s.
The saved `harqProductionReport.ok` was independently read as true from
`logs/original38_fresh_harq_roundtrip_20261004.mat`. Its 58-slot execution
retains 11 DL and 5 UL observations; the final HARQ timeline has exactly
16 matching rows, including seven retransmissions. This is fresh physical
execution and terminal-export verification, not a retained-only recheck.
It upgrades evidence within the 38 later-pass records; the ten other
original failures are not declared closed.

The status-propagation run has finished its DL/UL physical trials but
hit `FixedReferenceModeRequired` and is recovering report artifacts.
Read-only RCA identifies `runSingle.m:localResolveFixedLinkCampaignRuntimeConfig`:
it honors the validated campaign block only when `enabled=true`; when the
resolved master block explicitly says `enabled=false`, it falls through
to legacy reference-sweep defaults and may launch a fixed-link campaign
anyway. This run's resolved JSON has `validation.fixed_link_campaign.enabled=false`
and no `sweeps_and_matrix.fixed_link_calibration` block. Preserve the
disabled master configuration in the core resolver; do not set
`fixed_reference_mode=true` merely to appease the runtime validator.
No change to the still-executing `runSingle` has been made yet.

### 2026-10-04: disabled calibration launch authority repair

The status-propagation check subsequently terminated FAIL in 1755.50 s
with `FixedReferenceModeRequired`; its failed PHY execution and recovery
artifacts are retained. It is not a pass of the intended status assertions.

`resolveFixedLinkCampaignAuthority.m` now separates explicit campaign
enablement from reference-SNR diagnostics. Master-YAML authority owns both
true and false; an explicitly enabled legacy campaign remains supported
when no master authority selects otherwise. Absence of either campaign
switch no longer enables a separate campaign through reference-sweep flags.
`runSingle.m` now calls this resolver rather than manufacturing an enabled
default from `run.referenceSweepEnabled`.

`testFixedLinkCampaignEnablement` passed in 43.23 s
(`logs/fixed_link_enablement_recheck_20261004.log/.mat`). It exercises both
the actual disabled report YAML and the enabled master sweep YAML, plus
legacy/master precedence. The original runner was preserved as
`logs/lls_status_121440_runSingle_before_enablement_repair_20261004.m`
(SHA256 `98856AA74A9E2528D2F0DDF91496A602D5D866C6BF8E8D2DCAA1A3641F1FE33E`)
while the old failed run finished recovery. Do not attribute that old
execution to the repaired source.

The fresh, serial focused batch in
`logs/lls_fixed_campaign_authority_repair_20261004.log/.mat` runs
`testFixedLinkMasterYAMLAuthority` and then
`testLLSScenarioStatusPropagation`. The latter now also asserts that the
exported fixed-link campaign remains disabled. Both full-runtime results
remain pending at this checkpoint; the original ten-failure count has not
been reduced. No `testAll` or agenda-item campaign was launched.

The enabled-master guard subsequently passed in 90.78 s, executing one
real DL and one real UL transport block. The repaired status-propagation
scenario is still executing; its eight DL and eight UL trials have run.

### 2026-10-04: received-control completion and advanced UL origin

The separate bidirectional-access failure has an exact sample-clock cause:
Msg4 observation ends at sample 215040, but the configured next-slot full
SRB1 waveform starts at 214940 after the common 100-sample UL timing
advance. The committed-stream guard is correct. Increasing contention
timers, disabling TA or cropping transmitted samples would not repair it.

`testSharedULTimingOrigins` first reproduced the missing causal check
(`logs/ra_control_completion_reproduction_20261004.mat`, FAIL). The core
`runFourStepRA.m` now binds exact received-observation completion ticks
from accepted RAR and Msg4 observations. `sharedULStageTiming.m` checks
the complete advanced UL waveform origin against that received control
availability before submission. It retains the completion ticks and source
in physical timing evidence. Missing/future control is not inferred from
the planned transmitter slot.

The public FDD causal-access YAML now uses an explicit two-slot configured
SRB1 delay instead of one; the TDD override was already two. This is a
scenario processing budget, **not a universal 3GPP K2 minimum**. The
existing bounded SRB1 configuration still does not establish full dynamic
UL-DCI/NR RRC signalling qualification (`SetupCompleteGrantQualified`
remains false). This repair proves a necessary receive-causality boundary,
not every UE preparation-time capability in TS 38.214 clause 6.4.

Focused verification is running for `testSharedULTimingOrigins`,
`testRADuplexAllocationTiming`, and `testRAReceivedMsg4Identity` in
`logs/ra_control_completion_repair_20261004.log/.mat`. The original
bidirectional scenario must still be rerun on this repair before closing
that original failure.

The three focused checks subsequently passed: shared UL origins 26.19 s,
TDD/FDD allocation timing 97.77 s, and received Msg4 identity 0.37 s.
The saved `causalRepairReport.ok` is true. The original
`test6GLLSCoupledTruthBidirectional` is now running on the repair; its
physical run is retained under
`results/lls/coupled_bidirectional/20261004_125454_734` and its terminal
report will be saved to
`logs/coupled_bidirectional_causal_control_repair_20261004.log/.mat`.
Do not treat the focused clock/codec tests as that integrated result.

Read-only RCA for another original failure, `testTruthValidationProfile`,
identifies a distinct public-wrapper problem: `run_truth_validation_profile.m`
defaults to `config/suite_config_truth_validation.json`, then
`prepareValidationConfig.m` hardcodes carrier/resource/PRACH fields but
does not install the mandatory RACH/common-control contract. The retained
suite failed `MissingMandatoryRACHFields` before its export assertions.
The complete correction must resolve an explicit YAML-owned access/data
configuration, not fill individual RACH fields with guessed defaults.
Waveform-SLS causal physical SRS integration is a further prerequisite;
no claim that the wrapper is repaired has been made.

### 2026-10-04: bounded status regression and newly exposed RRC failure

The user-approved interruption of MATLAB PID 8628 is recorded in
`logs/lls_status_diagnostic_8628_interrupted_20261004.json`. The original
log/results were preserved. Its 16 DL/UL trials completed, but its inherited
`scenario.target_cases` also requested a separate large PRACH statistical
anchor. This interrupted test is not a pass. The new explicit fixture
`simulator/configs/fixtures/lls_status_propagation.yaml` retains ordinary
PRACH reception and every status/export assertion while excluding that
unrelated qualification request. Production statistical budgets/thresholds
are unchanged. The single-test rerun is retained in
`logs/lls_status_bounded_scope_recheck_20261004.log/.mat` and remains pending.

The bidirectional run crossed the former slot-28 waveform-commit failure,
received SRS, then failed at slot 30 with
`MATLAB:InputParser:ArgumentFailedValidation` for `ReceivedTransactionID`.
`recoverRRCSetupComplete` correctly returns no decoded message after a CRC
failure. `runFourStepRA` incorrectly supplied its missing transaction to
the Msg4 state-machine input, whose validator only accepts finite IDs.
It also used the later UL LCID to decide whether SRB1 had been installed.

The core repair separates received Msg4 identity from received UL completion
identity in `RRCConnectionEstablishmentStateMachine.m` and `runFourStepRA.m`.
Missing UL identity remains unavailable; CRC failure terminates at the
SetupComplete event, not an argument-parser exception. Accepted Msg4 SRB1
configuration is retained, without claiming connected access. Existing
bounded-codec callers remain explicitly without separate completion-identity
evidence; this is not full TS 38.331 qualification. Extended state tests and
`testRANegativeSetupCompleteCRC` cover these boundaries. Verification is
pending in `logs/rrc_completion_identity_repair_20261004.log/.mat`.
Pre-edit copies/hashes of both production files are retained under `logs`.

Additional RCA, not yet a verified repair: SRS arbitration checks queued
connected PUSCH grants but not pending RA-stage PUSCH transmissions. The
failed run's SetupComplete allocation spans all 14 symbols of 24 PRBs,
and an SRS reception completed at the same physical occasion. Exact overlap
must be reproduced before attributing the CRC failure to this path. Do not
solve this by disabling SRS or substituting decoded payloads.

Separately, `SystemLevelRunner.localSlotDuration` accepts a multi-slot
`TTI_s` while scheduler/provider absolute slot counters advance by one.
The mobility fixture uses 0.25 seconds per iteration. This needs a common
canonical physical clock or a genuinely implemented multi-slot integration
loop; the existing comment alone does not make those clocks consistent.
No mobility or full SLS qualification is claimed from the current fixture.

Subsequent focused verification and core repairs:

- `logs/rrc_completion_identity_repair_20261004.log/.mat`: existing 32 RRC
  transition vectors, added separate-completion identity cases, and bounded
  codec checks pass (`testInitialAccessRRCPhaseCore`, 9.87 s); received Msg4
  identity checks pass (0.26 s).
- `logs/rrc_completion_physical_repair_20261004.log/.mat`: future UL planning
  and optional-SRS access-causality checks pass (86.27 s). The first physical
  negative test exposed an undefined `localCorruptWaveform` call. The explicit
  RAR/SetupComplete negative branches now reuse the existing power-relative
  waveform-corruption helper; ordinary physical runs are unchanged. This
  failed check is retained, not overwritten.
- `logs/rrc_and_sls_clock_recheck_20261004.log/.mat`: production clock
  authority test passes (5.61 s), physical corrupted SetupComplete passes
  its negative assertions (11.27 s), and the positive AWGN four-step RA
  anchor passes (6.86 s). An intermediate test incorrectly expected final
  `RACompleted` to survive terminal failure; its replacement checks actual
  accepted Msg4 CRCs and requires final `RACompleted=false`, preserving the
  stronger separate-event/terminal-outcome semantics.
- `coupledSRSAttemptDue.m` now applies the already configured required-access
  gate even when SRS is optional for data admission. This prevents the
  reproduced pre-access future SRS scheduling; it does not disable SRS.
  The retained SRS capture reports PRBs 0--23 and TX samples 222620--230300,
  at the same occasion as the configured full-slot SetupComplete. Full
  connected-grant/RA reservation reconciliation remains broader work.
- `SystemLevelRunner.m` now delegates to `resolveSlotDuration.m`. Both
  supported backends execute one canonical slot per iteration; arbitrary
  `TTI_s` stretching is rejected before scheduling. Slower mobility updates
  belong in `scenario.mobility.updatePeriod_s`. Numerology/slot reference:
  [TS 38.211, clause 4.3.2](https://www.etsi.org/deliver/etsi_TS/138200_138299/138211/19.01.00_60/ts_138211v190100p.pdf).
  The separate positive `testSLS_WaveformBackend` and
  `testSystemNetworkDLCSI` rechecks are running, with final report target
  `logs/sls_dual_backend_clock_recheck_20261004.log/.mat`. The latter uses
  test-only calibration/labelled ideal feedback, not accepted study curves.

The bidirectional original test ended FAIL after 1605.64 s on the pre-repair
RRC transaction parser defect. It needs another integrated rerun after the
now-passing RRC/SRS focused repairs. The bounded status original test is
still finalizing. Therefore neither original failure is closed yet and no
new aggregate production-pass count is asserted. No `testAll` was launched.

### 2026-10-04: shared slot and mobility-clock continuation

The two positive backend rechecks are now terminal PASS:
`testSLS_WaveformBackend` (178.08 s) and `testSystemNetworkDLCSI`
(129.02 s), retained in
`logs/sls_dual_backend_clock_recheck_20261004.log/.mat`.
The latter remains test-calibrated, ideal-feedback integration evidence,
not a qualified production BLER package.

A separate core defect was found in `SystemLevelRunner.m`: the mobility
loop advanced positions before slot zero and integrated the following
interval, clipped to the remaining run length. It now retains the initial
drop at time zero and integrates the elapsed configured cadence at later
refresh boundaries. This affects both backends; it does not stretch PHY
slots or alter the mobility model. `testSystemMobilityElapsedClock` checks
actual production-run geometry for one- and three-slot cadences, including
a truncated final interval. Its idle traffic deliberately isolates geometry
and does not qualify decoded PHY performance or handover completion.

`testLargeScaleStateCacheStability` now uses the canonical slot duration
instead of 0.5 seconds per physical slot, retaining its real DL/UL grant
requirements. These two tests are running with receipt target
`logs/sls_mobility_clock_repair_20261004.log/.mat`; results are not assumed.
The clock tests were registered for future suites, but `testAll` was not run.

Terminal follow-up: `testLargeScaleStateCacheStability` PASS (113.95 s),
including actual DL and UL waveform grants. The first mobility test failed
because its independent straight-line comparison inherited indoor random
heading jitter. The test now explicitly configures outdoor UEs, preserving
exact position and elapsed-clock assertions. Its rerun PASS (40.35 s) is
retained in `logs/sls_mobility_elapsed_recheck_20261004.log/.mat`; the first
failure remains in the earlier report. This is geometry-clock coverage,
not closure of the original handover control-loop failure.

The original `test6GLLSCoupledTruthBidirectional` has now been relaunched
against the focused-verified RRC/SRS repairs, with incremental log
`logs/coupled_bidirectional_rrc_srs_recheck_20261004.log`, terminal MAT of
the same basename, and pre-execution source hashes in
`logs/coupled_bidirectional_rrc_srs_recheck_source_20261004.mat`.
It is running, not accepted. No agenda-item source was changed in this
continuation; no full suite was started.

### 2026-10-04: original status-export failure closed

`testLLSScenarioStatusPropagation` is now terminal PASS (2244.08 s), in
`logs/lls_status_bounded_scope_recheck_20261004.log/.mat`. Its deliberately
failing physical scenario stayed failed; MAT, CSV, manifest and reports
agreed on that outcome. The test also verified that the disabled fixed-link
campaign stayed disabled and the unrelated PRACH qualification anchor did
not execute. The 13 absent browser tables remain disclosed; this test does
not establish complete browser coverage or a successful physical scenario.

This leaves 39 of the historical 48 failures with subsequent passing test
records, and 9 original tests unresolved. That is mixed-source regression
progress, not final-source production or scientific acceptance. The
bidirectional rerun remains active. The next affected rerun is
`testRunScopeConformanceMetadata`; its former temporary result deletion was
removed so failures retain decoded access and export evidence under
`results/e2e/scope_conformance_regression`.

### 2026-10-04: core horizon acceptance gap and LLS sidecar clock

The metadata-only E2E rerun reported PASS (211.16 s), but inspection of its
retained `probe_e2e_summary_truth.csv` disproved production closure:
`NumSlots=20`, `AttachSlots=35`, offered UL=0, and no grants. The current
test's assertions did not require post-attach data. Therefore this extra
passing record is explicitly NOT accepted as repair of the production
path; the unresolved original-test count remains nine pending the
strengthened recheck.

Core repair: `sixgr_run_3gpp_full_campaign.m` now retains the actual access
receipts in `e2e_received_access_horizon.mat` and invokes
`sixgr.truth.requirePostAttachWindow` before clamping the access gate.
A truth data campaign with no post-attach slot raises
`sixgr:e2e:InsufficientPostAttachWindow` instead of qualifying an empty
offered population. It does not extend the user's duration automatically.
The explicit test window is now YAML-owned in
`simulator/configs/fixtures/e2e_scope_conformance_window.yaml` (80 slots).
`testRunScopeConformanceMetadata` retains all metadata assertions and now
also requires an accepted run, nonzero post-attach UL offered traffic and
actual UL scheduler rows. `testRAAttachCompletionGate` adds exact-boundary
and out-of-horizon rejection cases. Their focused batch is running in
`logs/e2e_post_attach_horizon_repair_20261004.log/.mat`.

The LLS sidecar exporter had a separate off-by-one cadence: it moved three
slots of geometry at the first post-zero observation. Its mobility, beam
and propagation refresh clocks now use the elapsed zero-based slot;
propagation also refreshes on actual movement. The YAML-driven
`testLLSMobilitySidecarClock` passed (20.81 s), including persisted CSV
positions, in `logs/lls_mobility_sidecar_clock_recheck_20261004.log/.mat`.
This establishes derived-geometry clock consistency, NOT receiver-measured
beam qualification. Core beam callers still invoke legacy geometry-based
selection without the measured-selection API. That production integration
gap remains open and is not erased by passing helper tests.

### 2026-10-04: integrated RRC/SRS repair boundary crossed

The live bidirectional rerun has crossed its former slot-30 RRC failure.
In `results/lls/coupled_bidirectional/20261004_134226_034/c/lls/lls_coupled_truth_smoke/smoke/control/csv/rrc_setup_complete.csv`,
UE 2 has scheduled absolute slot 29, CRC=1, Decoded=1,
RRCConnected=1, transaction 0, SRB1 LCID 1 and decoded identity UE-2.
The slot-31 log then records `access=1/2`, and queues UE 2's first SRS
for source slot 32. This supplies integrated evidence for the repaired
RRC identity path and post-access SRS activation, without claiming the
70-slot original test has passed or that UE 1 has attached.

The post-attach horizon boundary test passed (1.63 s). The strengthened
80-slot E2E metadata rerun is live, retaining actual access completion at
slot count 35; no post-attach data acceptance is inferred from the old
20-slot empty-data pass. Both original integrated regressions remain open.

### 2026-10-04: exact-resource cache collision and demand watchdog repaired

The original bidirectional test subsequently failed at slot 31 with nominal
N_RE=138 versus actual N_RE=132. This was reproduced in a fresh process:
one CDM group cached 138, then a two-group allocation incorrectly reused it.
`SchedulerBase.localSchedulerCacheScopeToken` attempted raw JSON on complex
beam configuration and, on serialization failure, collapsed the entire key
to direction/grid/symbol count. Different DM-RS configurations then aliased.
The core now serializes real/imaginary configuration explicitly using the
shared JSON representation and never substitutes a coarse cache identity.
The exact resource-consistency guard remains unchanged.

Before-repair evidence: `logs/scheduler_cache_collision_before_repair_20261004.log/.mat`
records `testSchedulerComplexConfigCache` failing with 138 versus 132.
After repair, `logs/core_cache_watchdog_repair_20261004.log/.mat` records:

| Focused test | Result |
|---|---|
| testSchedulerComplexConfigCache (DL and UL, cold and repeated keys, independent native allocation/TBS) | PASS, 12.11 s |
| testSystemDemandStallClock | PASS, 0.01 s |
| testSchedulerGrantConsistency | PASS, 11.38 s |
| testSystemSlotClockAuthority | PASS, 2.97 s |

The E2E watchdog incorrectly charged 208 s of initialization/access time
against the first unserved demand slot. `SystemLevelRunner` now uses
`updateDemandStallClock`: an interval starts with observed unserved active
demand, not process startup, and disarms on idle/progress. The timeout and
slot-count limits are not raised or disabled. The production E2E coupling
also retains its diagnostic context under the campaign's
`packet_flow/diagnostics/system_coupling` instead of deleting a temporary
directory immediately after a failure.

The strengthened E2E rerun reached all 80 slots without the premature
watchdog failure, but **failed** (324.65 s) on actual `MissingSRSState` at
UL scheduling slots 39/44/49/54/59/64/69/74. Evidence:
`logs/e2e_demand_clock_recheck_20261004.log/.mat` and
`results/e2e/scope_conformance_regression/20261004_140920_247`.
The launcher's final assertion additionally used nonexistent `report.Passed`;
the saved `report.ok=false` and individual test failure remain authoritative.
No acceptance is claimed. `SystemLevelRunner` advances spatial feedback only
for `CalibratedLinkPHY`; `WaveformPHY` has no corresponding physical SRS
producer/completion path. That integration must be implemented without
injecting modeled ideal feedback into a waveform claim or disabling its guard.

A fresh-process rerun of the original 70-slot bidirectional LLS test is now
started in `logs/coupled_bidirectional_cache_repair_20261004.log`, with source
hashes in the adjacent `_source_` MAT. Its terminal acceptance is pending.
No full testAll, agenda-item edits, or primary-result substitutions were made.
The four new focused passes do not change the historical 39-later-pass /
9-open reconciliation or qualify all 39 as final-source production passes.

### 2026-10-04: scope limited to LLS/SLS; UCI handover ownership repair

The user's latest instruction defers E2E mode. No further E2E or full
`testAll` launches are authorized. Existing E2E edits and evidence are
preserved, not reverted or counted as repaired. Of the nine historical
original tests still open, five remain in the active LLS/SLS repair scope:
`test6GLLSCoupledTruthBidirectional`, `test6GLLSMultiUserBeamforming`,
`testLLSReportBundle`, `testLLSResultRichness`, and `testMobilityControlLoop`.
The other four remain deferred, not passed. Agenda-item files are untouched.

A new general-SLS defect was reproduced separately from that historical
inventory. `SLSDynamicPUCCH.configureServingCells` skipped its handover
ownership check entirely for shared configured resources, and pooled
resources stopped protecting a grant after its feedback slot elapsed.
Consequently a source-cell obligation could disappear without completion.
`logs/sls_uci_handover_before_repair_20261004.log/.mat` retains the failing
`testSLSUCIHandoverOwnership` result (`LostUCIOwnership`, 22.00 s).

The production ledger now checks both resource policies, protects overdue
uncompleted grants and published SR/CSI obligations, and releases ownership
only against recorded completion IDs/exact HARQ source-grant digests. It
does not generate ACKs, physical CRC evidence, or time-based expiry. Explicit
handover cancellation/retargeting remains unsupported; callers must drain
outstanding obligations rather than silently relabel their serving cell.

`logs/sls_uci_handover_repair_20261004.log/.mat` records source hashes and:

| Focused test | Result |
|---|---|
| testSLSUCIHandoverOwnership | PASS, 9.70 s |
| testSLSDynamicPUCCH | PASS, 21.40 s |
| testSLSExecutingULReservations | PASS, 13.74 s |

Dedicated DL-CSI and automatic PUCCH/PUSCH integration are now being rerun
in `logs/sls_uci_ownership_integration_20261004.log`, with source hashes in
the adjacent `_source_` MAT. Added checks reuse actual scheduler-issued
grants to verify completion permits release and failed/unexecuted transport
does not. These runs still use test-only BLER calibration and explicitly
ideal delayed control; they cannot qualify physical UCI or primary SLS
study performance. Their terminal results remain pending at this checkpoint.

The concurrent original bidirectional LLS rerun has now crossed the previous
slot-31 exact-resource failure: its retained log at 09:03:19 UTC records one
scheduled DL grant, and at 09:03:40 UTC records actual shared DL DCI reception
for UE 2 at control/data slot 31. One UE has completed RRC access; both have
acquired SSB/PBCH. This confirms the repaired cache boundary on this path,
not completion of the 70-slot test or successful later data/artifact checks.

### 2026-10-04: SLS ownership integration passes; new LLS boundary isolated

The saved terminal report `logs/sls_uci_ownership_integration_20261004.mat`
has `uciIntegrationReport.ok=true`: `testSystemNetworkDLCSI` passed in
142.31 s and `testSystemAutomaticPUSCHUCI` passed in 194.21 s. Both retain
test-only calibration/ideal-control labels. Exact issued-DL-grant completion
and actual PUSCH execution now permit old-cell ownership release; pending,
overdue and unexecuted obligations reject handover. The MCP observation
timed out, but the existing job completed and its MAT was inspected; no
duplicate run was started. The diary was empty, so the saved report and
underlying per-attempt logs/CSVs are the evidence, not the empty diary file.

The original bidirectional LLS run executed two DL rows and received SRS
successfully at slot 32, then failed at slot 33 with
`sixgr:phy:pdcch:missing_dci_context`. The retained stack is:
`prepareSharedPUCCHFeedbackRuntime -> buildReceivedHARQACKCodebook ->
DCIContextFactory.fromRuntimeConfig -> fromOperatorControl`.
The inherited FDD causal-access YAML has neither a connected DCI profile
nor `pdcch_strict`; generic scheduled transmission proceeded until the
independent HARQ codebook required the installed receiver context. Required
next repair: install the explicit control schema and fail at shared-runtime
preflight when it is absent, without reconstructing receiver authority from
transmitted DCI. The compatible staged FDD control profile resolves both
1_1 and 0_1 contexts in a focused configuration check, but is not yet wired
into this original run. Failure evidence is preserved under
`results/lls/coupled_bidirectional/20261004_141706_259/c/lls/lls_coupled_truth_smoke/smoke/meta/failure_debug_report.txt`.
The failed process is rebuilding artifacts; permission to stop only that
process while preserving evidence has been requested, not assumed.

Report-richness preparation also reproduced a stale catalog: the raw YAML
contained `pucch_resources.component_probe`, but the in-process merged
parameter catalog did not. `loadParameterCatalog` cached scenario/matrix
policy indefinitely. Its core cache now compares base/overlay file content
and optional-overlay presence before reuse. An isolated-copy regression
passes creation, same-size/same-mtime content changes, matrix changes,
invalid changed input rejection, and overlay removal. No actual repository
catalog is modified by the test. The actual report-richness configuration
subsequently passed preflight in the same MATLAB session.

The report-richness fixture now explicitly excludes its independent PRACH
statistical anchor while retaining physical bundle PRACH measurements and
all original artifact/measurement assertions. Its full rerun is not started.
Preflight evidence: `logs/richness_bounded_preflight_20261004.mat`.
Additional configuration regressions are running in the existing MCP
session, with terminal output planned in `logs/parameter_catalog_guards_20261004.mat`.
No full `testAll`, E2E campaign, agenda edits, or accepted-study-result claim.

The terminal `parameter_catalog_guards_20261004.mat` report is now complete:
`testParameterCatalogCacheRefresh` PASS (1.29 s), `test6GParameterCatalog`
PASS (1.82 s), `test6GScenarioConfigValidation` PASS (35.59 s), and
`testConfig` PASS (20.08 s). The final cache test also changes the base
catalog while retaining the independently updated overlay. These passes
verify configuration/cache correctness, not the still-failed slot-33 LLS
execution or the full report-richness artifact contract.

### 2026-10-04: independent DCI startup repair (LLS/SLS scope; E2E deferred)

The previous bidirectional process finished naturally. Its terminal MAT and
log retain the slot-33 `missing_dci_context` failure (2027.65 s); it was not
stopped and its recovery artifacts were preserved. The shared waveform owner
now calls `validateSharedDCIConfiguration` for every UE before any RF/channel
materialization. This validates installed paired receiver contexts and size
alignment without modifying configuration or deriving a layout from TX data.
Missing or inconsistent policy fails before physical execution.

The original bidirectional test now uses the existing explicit FDD connected
control overlay. Rank one retains two SRS/PUSCH ports and an explicit rank-one
UL codebook ceiling. Physical access, 70 slots, two UEs, simultaneous DL/UL,
HARQ and original artifact assertions remain required. The legacy bare parent
is not silently filled with inferred control defaults.

`logs/shared_dci_preflight_guards_20261004.mat` retains source hashes and four
passes: startup preflight (13.87 s), Type-2 layout (3.64 s), Type-2 runtime
planning (8.04 s), and configured combined PUCCH reception (3.70 s). The layout
test covers 256 DAI sequences and 24 legacy vectors; the PUCCH test executes
two real coded component waveforms, not a full connected run. The separate
connected DCI profile test also passed (11.67 s). Startup tests check missing
and malformed policy, port mismatch, a later invalid UE before materialization,
FDD/TDD contexts and rank-one/two-port consistency.

The original bidirectional rerun is launched with evidence under
`logs/coupled_bidirectional_dci_repair_20261004.log` and a separate source-hash
MAT. Its terminal result is pending. These focused passes do not close that
historical failure or qualify complete LLS/SLS. No full `testAll`, E2E run,
agenda-item edit, proxy evidence or modified physical acceptance threshold.

### 2026-10-04: preserve UE identity for SR-only SLS obligations

Further ownership inspection reproduced a separate production defect:
`SLSDynamicPUCCH.configureUEIdentities` rejected changes after data grants or
PUSCH bindings, but allowed a replacement RNTI after publishing an SR-only
obligation under shared configured resources. No data grant is necessary for
UCI to already own an installed protocol identity. The retained negative test
`logs/sls_uci_identity_before_20261004.mat` failed with `LostUCIIdentity`.

The core ledger now rejects identity replacement after any published UCI or
completion trace as well. This preserves historical identity after completion;
it does not pretend to implement an RRC reconfiguration/identity-transfer
procedure. The regression checks both resource policies and verifies that
rejection leaves the original RNTI, pending trace and completion trace intact.

`logs/sls_uci_identity_repair_20261004.mat` contains the source hashes and:
- `testSLSUCIHandoverOwnership`: PASS, 8.11 s.
- `testSLSDynamicPUCCH`: PASS, 20.55 s.
- `testSLSUCIResourceBindings`: PASS, 81.61 s; 21 cells/210 UE SR obligations
  plus two independent offset-BWP waveform round trips.

DL CSI and automatic UCI-on-PUSCH system integration regressions are running
in the existing MCP engine. The pending terminal receipt is
`logs/sls_uci_identity_integration_20261004.mat`; source hashes were saved
before execution. Those integrations retain development BLER calibration and
ideal-control labels. Full handover draining/cancellation is still unimplemented.
The concurrent 70-slot LLS rerun remains live; both UEs acquired SSB/PBCH, but
neither this observation nor the new SLS guards closes the original complete
scenario failures. Historical 48-failure acceptance counts are unchanged.

The identity integration terminal receipt is now verified: DL CSI PASS
(172.87 s), automatic PUCCH/PUSCH UCI PASS (175.67 s). The tool observation
expired at 300 s, but the existing MATLAB job completed at 15:08:24 IST;
the saved terminal MAT was inspected and no duplicate was launched.

### 2026-10-04: export installed RNTI on SLS UCI evidence

The internal obligation carried its real installed RNTI, but publication and
completion tables omitted it. `sls_uci_export_identity_before_20261004.mat`
reproduces `MissingUCIExportIdentity`. `SLSDynamicPUCCH` now copies `o.RNTI`
into both tables; the existing system exporters retain the entire table with
`PreserveSchema=true`. No UE-index-to-RNTI inference or received-CRC claim is
introduced. The result-integrity skill's provenance separation is retained.

The final component receipt `logs/sls_uci_export_identity_repair_20261004.mat`
records ownership/export PASS (5.95 s) and dynamic PUCCH PASS (11.60 s), with
source hashes. Actual CSV readback for both resource policies verifies
RNTI=4660, UEIndex=1 and WaveformBacked=false. The CSVs are preserved under
`results/sls/uci_identity/20261004_150953_163`. The preceding system integration
passes predate these additive export columns; they are not represented as
a final-source rerun of the changed export schema.

### 2026-10-04: connected DL QCL startup and recovery TDRA round trip

The original bidirectional LLS rerun ended FAIL (1084.76 s), not a timeout.
Physical UE-2 Msg4 and RRCSetupComplete completed and slot-31 PDCCH decoded.
The next PDSCH materialization rejected `sixgr:qcl:MissingCORESETAssociation`.
The independently installed DCI overlay had `tci_present=false` but omitted
the scheduling CORESET association required by `PDSCHAssignmentFactory`.
No connected-data row completed. This supersedes the pending status above;
it does not establish passage of the old slot-33 HARQ boundary.

`shared_qcl_preflight_before_20261004.mat` proves the production startup check
accepted that incomplete configuration while the actual receiver rejected it.
The FDD validation YAML now explicitly supplies its Type-A SSB-0 association.
`validateSharedDCIConfiguration` validates absent-TCI DL association identity
before any shared-stream materialization, for every configured UE. No TCI
codepoint, measured timing prior or receive spatial-filter gain is invented.
Actual activation time remains validated at reception. UL-only operation
does not acquire an irrelevant PDSCH requirement.

`logs/shared_qcl_preflight_repair_20261004.mat` retains hashes and three passes:
startup/preflight plus actual blind FDD PDCCH-to-PDSCH binding (22.21 s),
default-CORESET QCL reference/negative tests (10.14 s), and connected DCI
profile (8.68 s). Missing/wrong-epoch configurations and a later invalid UE
are rejected before RF/channel execution.

The same failed run exposed an independent recovery defect: a singleton
TDRA `[index,start,length,K]` becomes a 4x1 vector after MATLAB JSON decoding.
`buildInternalConfig` now reconstructs only that unambiguous four-field row,
without modifying the resolved snapshot, its hash or any allocation value.
Malformed/multi-record input is not flattened or padded. The retained
before/after receipts are `logs/recovery_tdra_before_20261004.mat` and
`logs/recovery_tdra_after_20261004.mat`. The actual failed-run snapshot now
rebuilds DL `[0 2 12 0]` and UL `[0 0 14 1]` with exact persisted authority
and unchanged ConfigHash `e32125161435bd370ad205883a1c1f7eb29be6a06105425dc290a41b821f1ca5`.
This verifies configuration recovery, not complete report republication.

`logs/tdra_roundtrip_repair_20261004.mat`: singleton/multi-row DL/UL and
malformed-list regression PASS (18.08 s); immutable recovery authority PASS
(14.42 s). The new regression is registered, but no full `testAll` was run.
Core/config repairs do not close the historical bidirectional test until its
complete rerun passes. E2E and agenda-item work remain deferred.

Additional affected guards in `logs/qcl_tdra_affected_guards_20261004.mat`:
`testConfig` PASS (10.89 s), `testReceivedDLHARQReplay` PASS (21.45 s), and
`testReceivedDLQCLAuthority` PASS (10.16 s). Eight focused tests passed in
this repair batch. Replay verifies the original failed-first/successful-retry
decode, retained ACK without duplicate delivery, and unchanged negative guards.

The original bidirectional test is now running with source hashes in
`logs/coupled_bidirectional_qcl_repair_source_20261004.mat`, log
`logs/coupled_bidirectional_qcl_repair_20261004.log`, and retained root
`results/lls/coupled_bidirectional/20261004_152621_205`. It reached slot 2/70;
no terminal pass is claimed. The original 48-failure disposition is unchanged.
Final-source SLS DL CSI/UCI export integration is also running, with receipt
target `logs/sls_uci_export_integration_20261004.mat`. Readback of the first
integration's actual CSVs under
`logs/sls_calibrated_delivery_fixtures/20261004_152554_261/attempt_3/csv`
verified six obligations and six completions with UEIndex=1/RNTI=4660,
WaveformBacked=false and PhysicalDecodeQualified=false. Overall two-test
terminal acceptance remains pending; calibration is still development-only.

### 2026-10-04: final-source SLS UCI export integration verified

The saved `logs/sls_uci_export_integration_20261004.mat` is terminal PASS:
`testSystemNetworkDLCSI` 142.75 s and `testSystemAutomaticPUSCHUCI` 230.38 s.
The MCP observation expired at 300 s, but PID 3380 continued and saved its
result at 15:31:54 IST. No duplicate job was started. Source hashes match the
repaired UCI publication/completion exporter used for these checks.

Additional real-file readback in `logs/sls_uci_export_readback_20261004.mat`
checks the UL run at
`logs/sls_calibrated_delivery_fixtures/20261004_152817_430/attempt_2/csv`:
seven obligations, seven completions, both PUCCH and PUSCH, UEIndex=1 and
RNTI=4660. All completions retain WaveformBacked=false and
PhysicalDecodeQualified=false. These are production-path integration checks
using test-only BLER calibration and ideal control, not study qualification.

The affected original `testLLSResultRichness` is now running in the freed MCP
engine. Its rechecked preflight preserves four slots, two SNR points, two
realizations, serial execution and no independent PRACH detector campaign.
It still exercises actual DL/UL waveforms, strict artifact closure and the
original measurement/constellation assertions. Evidence root:
`results/lls/result_richness/richness_20261004_153331_697`; pending terminal
receipt `logs/lls_richness_export_repair_20261004.mat`. Source hashes and
preflight evidence are saved separately. The bidirectional LLS rerun remains
live (slot 19/70 at this checkpoint); no shared production source is edited
while either run is active.

`test6GLLSMultiUserBeamforming` now preserves its result directory under
`results/lls/multiuser_beamforming` and restores only its environment variable.
The old cleanup deleted all IQ/configuration/diagnostic evidence on failure.
This is an evidence-retention repair, not a PHY or runtime acceptance claim;
its missing physical access/control setup remains open and it was not run.
Its original MIMO/CSI/UL power/overlap assertions are unchanged. E2E and
agenda-item files remain untouched, and no full `testAll` has been launched.

### 2026-10-04: report-richness live audit (not terminal acceptance)

PID 3380 continues the original report-richness regression after its MCP
observation timed out. The actual run log and CPU counters are advancing;
no duplicate was launched. `link_anchor_kpis.csv` contains six Ok=1,
Skipped=0 component rows, and the runtime-stage profile records completion
of that initial anchor bundle in 245.54 s. PBCH, PRACH, PDCCH, PUCCH, SRS
and TRS raw rows subsequently appeared at both 18 and 30 dB. This is not a
terminal report/measurement pass; primary data and final artifact checks
remain in progress.

The persisted configuration reveals an additional fixture error:
`lls_result_richness.yaml` sets `cfo_hz: 40` and
`timing_offset_samples: 16` but inherits `cfo_enabled: false` and
`timing_offset_enabled: false`. `buildInternalConfig` correctly honors
these disabled flags (localResolveRuntimeCFOHz/localResolveRuntimeTimingOffsetSamples).
The current run therefore cannot qualify the intended nonzero impairment
branch. Required next repair, after the run ends: explicitly enable both in
the fixture and assert their effective values before executing the test.
Do not change production semantics to turn disabled impairments on merely
because inactive configured magnitudes are nonzero.

PDCCH receiver-Hest SINR also changes little across the two points. Its raw
rows have ConfiguredSNR_dB=AppliedAWGNSNR_dB at 18 and 30, and the exported
AppliedNoiseSNR_dB changes by exactly 12 dB for the paired realizations.
All eight PDCCH CRCs pass. The plateau is not evidence of a frozen SNR label;
fading channel-estimator/normalization behavior needs independent replay
before diagnosing a physical bug. No values or labels were adjusted to
force agreement. Both active LLS jobs retain frozen production source.

### 2026-10-04: slot-31 repair verified; slot-33 identity and sweep-label defects

The current bidirectional run (`20261004_152621_205`) passed the previous
QCL failure boundary. Its actual DL CSV contains CRC-passing UE 2 / RNTI 202
trials at slots 31 and 32; the shared SRS completed at slot 32. At slot 33,
the run failed with `sixgr:truth:ReceivedHARQCodebookContextMismatch` and
entered report recovery. This is NOT an original-test pass, and no UL data
trial has been accepted. Logs/results are preserved.

Static tracing localizes an identity discrepancy to the feedback callback:
`runWaveformLinkBundle.localPrepareUserCfg` binds per-UE PDSCH/PUSCH RNTIs,
whereas `CoupledTruthRuntime.applyUserContextImpl`, called directly from
`prepareSharedPUCCHFeedbackRuntime` with `state.CfgMobility`, does not.
`ConnectedDCIProfile` derives its RNTI/digest from `phy.pdsch.RNTI`.
The next regression in `testSharedDCIConfigurationPreflight` now compares
both paired DCI contexts for two UEs in both directions. This added case
is pending execution; the corresponding core repair is not yet applied.
Keep the codebook's context/epoch/clock rejection: do not copy an event
digest into the installed configuration or relax the comparison.

The report-richness run now has 16 DL and 16 UL raw trials across 18/30 dB.
Its DL and UL constellation previews each contain 2,500 rows, ALL labeled
30 dB, including samples carrying the 18-dB trial's EVM/SINR. Root cause:
`deriveModulationTrackingMetrics` initializes `SNR_dB` from the base
`cfg.channel.snr_dB`; both throughput producers replace that field only
when nonfinite. The finite but stale base value survives. Repair must bind
the exact executed trial's configured operating point and keep applied
noise and measured SINR in separate fields. Both direction writers need
cross-table sweep-lineage regression coverage; no retained evidence has
been relabeled to conceal this defect.

All 16 UL trials passed CRC, but the first 18-dB trial has EVM=10.91656 and
post-equalization SINR=-22.3699 dB after the DMRS-residual bound (unbounded
equalizer result=11.1445 dB). This discrepancy needs receiver/symbol replay;
CRC success alone neither validates the measurements nor proves a PHY bug.

Focused Python export checks completed: `test_lls_csv_semantics.py` and
`test_lls_sparse_signal_evidence.py`, 113 passed in 7.27 s. They do not
cover the above cross-file constellation discrepancy. No `testAll`, E2E,
agenda-item work, or additional MATLAB process was launched. Both existing
MATLAB engines were confirmed live during their export/recovery phases;
shared production source remains unchanged until those executions finish.

### 2026-10-04 16:01: focused regression preparation during verified export wait

The report-richness waveform bundle completed at 15:56:56 IST, but its
original test has not returned and no terminal receipt exists. PID 3380
continues consuming CPU during artifact closure. PID 18656 is also live;
the failed bidirectional job has advanced through recovery output-coverage
tables (control/beam/timing). Neither observation is a passed test or a
reason to launch a duplicate.

The exact constellation lineage regression is now staged in
`testDataChannelStreamStages` and `verifyReceivedConstellationCapture`.
The DL/UL shared-observation test requests a point different from the base
configuration while keeping its independently executed fixed sample noise.
The capture checker requires ConfiguredSNR_dB, AppliedAWGNSNR_dB and
AppliedNoiseSNR_dB to match the originating trial (including NaN), and both
SNR label aliases to match ConfiguredSNR_dB. This detects the stale finite
label and an incorrect repair that substitutes measured sample-noise SNR.
These test additions are not executed or claimed passing yet. Source fixes
and the affected reruns follow the existing jobs' terminal receipts;
production files and active scenario configuration remain frozen.

### 2026-10-04: core beam units and per-UE feedback identity repaired

The bidirectional original test terminated after recovery with
`sixgr:truth:ReceivedHARQCodebookContextMismatch` (2511.10 s). Its receipt is
`logs/coupled_bidirectional_qcl_repair_20261004.mat`; this original failure
remains open until its actual scenario passes on repaired source.

The small preflight reproduced `test:SharedUEControlIdentityMismatch`
before waveform execution. `CoupledTruthRuntime.applyUserContextImpl` now
binds both PDSCH/PUSCH RNTIs and user metadata from the configured per-UE
identity, including callbacks starting directly from CfgMobility. Invalid
or overflowing identities are rejected, not rounded/clamped. Received HARQ
context/epoch/clock guards are unchanged. Final-source preflight passed for
two UEs, both directions, and malformed identity rejection.

`selectBestBeamPerLink` no longer exports selected absolute RSRP/SINR as an
antenna gain. It records SelectedMeasurement and its resource identity;
gain is unavailable (NaN) without an independent gain reference. Single-beam
K-by-B-by-1 input is accepted despite MATLAB's trailing-dimension elision.
Three measured-beam/strict-selection checks and the colocated-sector
geometry regression passed. Receipt:
`logs/beam_identity_focused_20261004.mat` (also retains the pre-repair
identity failure). The geometry production branch was not changed.

The subsequent five-test batch has four passes and one failure:
`testSharedDCIConfigurationPreflight`, `testSharedPUCCHReceiveOnlyClock`,
`testPUSCHScheduledHARQAuthority`, and `testType2HARQRuntimePlan` passed.
`testSharedPUCCHFeedbackClock` fails early: its legacy queue fixture lacks
an installed paired DCI policy. Further inspection also finds manually
rewritten K1/PRI after isolated source DCI decoding and no received-event
ledger integration. Updating that fixture requires real decoded timing and
UE HARQ transitions; disabling the preflight or manufacturing event bits
would be wrong. Receipt: `logs/shared_ue_identity_repair_20261004.mat`.

Both core throughput writers now bind constellation SNR labels from the
actual trial's ConfiguredSNR_dB and export AppliedAWGNSNR_dB and
AppliedNoiseSNR_dB separately. Retained old CSVs were not rewritten. Actual
coded TDD DL/UL stage checks are running under
`logs/constellation_lineage_repair_20261004.log`; no pass is claimed yet.

The older report-richness job is still finishing publication after its PHY
bundle ended at 15:56:56. Its initial source receipt remains preserved.
Core repairs made after that physical execution do not retroactively fix
its measurements or make it final-source acceptance. No full suite, E2E
work, agenda-item edits, new full campaign, commit or push was performed.

The first constellation check produced a real CRC-passing DL trial but
stopped before the capture-readback assertions: the test wrapper ignored
its new SNR_dB argument and passed cfg.channel.snr_dB into buildGrantPHYJob.
The wrapper now forwards the requested value and asserts the frozen job's
SNR. This is a fixture plumbing correction, separate from the two production
writer repairs above. The failure/stimulus is preserved under the first
receipt; the rerun uses `logs/constellation_lineage_repair_v2_20261004.log`
and its own source hashes. Full constellation verification remains pending
until that rerun returns; the earlier pass claim is limited to DL decoding.

At 16:28 IST the corrected TDD stage rerun completed successfully, with
actual coded DL/UL CRC passes, timing/one-TX-one-RX checks, independently
summed receiver EVM and constellation CSV/plot readback. DL retained 3,348
symbols (EVM 5.46532414954%); UL retained 3,522 symbols (EVM 5.65205310657%).
These are explicitly fixed-connector/noise component observations, not a
0-dB link-performance claim. Independent Python CSV readback confirmed the
requested 0-dB sweep coordinate remains separate from applied sample-noise
SNR (DL 19.9567148808698 dB), with absent applied-AWGN evidence kept NaN.
Final receipt: `logs/constellation_lineage_repair_v2_20261004.mat`.
The complete original report-richness test is still exporting, and the
legacy shared-feedback-clock fixture and full bidirectional rerun remain
open. Component passes do not close those original scenario failures.

### 2026-10-04: disabled QCL authority and shared clock follow-up

The connected feedback-clock migration exposed a production mismatch:
`resolveDLQCLTCIBinding` froze inherited state 17 even when the resolved
QCL policy explicitly disabled it; the independent connected-DCI context
correctly contained no active state. The resolver now respects explicit
disablement. Enabled QCL remains authoritative even if its optional DCI
indication is absent. Two malformed/mismatched-state error messages also
used nonscalar string arrays, hiding their intended identifiers; these
messages are repaired without weakening their conditions.

`testConnectedDCIProfile` and `testSharedQCLScenarioContract` pass on this
source (41.12 s and 10.29 s). The retained v3 log/source receipt is
`logs/qcl_feedback_core_v3_20261004.log` and
`logs/qcl_feedback_core_v3_source_20261004.mat`. The earlier negative-test
failure remains in `logs/qcl_disabled_binding_20261004.log`.

The feedback-clock fixture now selects K1/DAI before DCI encoding, imports
actual isolated receiver decisions explicitly, and queues the same coded
DL TB through the shared waveform owner. Only its actual DataTX callback
creates gNB expectations and HARQ transmission state. The shared DL capture
is not relabelled as the isolated ACK receiver. Late-source variants queue
their physical transmissions at their real source slots and defer only
receiver-result publication. These clock changes remain under focused
verification; neither the original bidirectional scenario nor SLS campaign
acceptance is claimed. No agenda folder or E2E implementation was changed.

The v3 clock check decoded the source TB but exposed missing serving-array
context in the new fixture transmission. The fixture now calls production
`applyUserContext` before preparing that transmission. The v4 check then
reached independent PUCCH hypothesis construction and exposed ServingCell
being added only to a copied grant, not its frozen transmitted binding.
The optional connected-feedback helper now binds that identity before DCI
and waveform preparation. Both failed receipts are retained; verification
continues in `logs/shared_feedback_clock_connected_v5_20261004.log` with its
separate source receipt. These setup repairs do not bypass the real DataTX,
HARQ, independent receive-layout, or serving-cell guards.

The v5 check reached PUCCH completion but its missing-timing negative test
did not reject: actual source CSI-RS now legitimately made inherited slot 9
a combined Format-2 occasion, which has its own DM-RS timing. That is not a
production timing-guard defect. The dedicated HARQ-only clock overlay now
retains an enabled 20-slot CSI calendar with a legal first report at slot 19,
outside its 10/11-slot window. The test explicitly checks Format 0/no CSI
before requiring rejection of a missing prior UL clock. Production reporting
calendars and combined-UCI assertions are untouched. The v6 receipt/log is
`logs/shared_feedback_clock_connected_v6_20261004.*`; result still pending.

The v6 focused check subsequently PASSED (137.12 s), including actual DL TX,
isolated coded source ACK, shared SRS/PUCCH reception, delayed HARQ commit,
missing-prior rejection, immutable TX-ledger checks and power-export CSV
round-trip verification. Terminal receipt:
`logs/shared_feedback_clock_connected_v6_20261004.mat`. This closes the
default HARQ-only clock regression, not the late-feedback variants, the
complete original bidirectional scenario, or production SLS qualification.
The QCL production resolver change is separately covered by both v3 QCL
checks. No passing assertion was removed or receiver oracle introduced.

### 2026-10-04: late-feedback verification and publication RCA

The connected late-feedback batch passed on its retained source:
`testSharedPUCCHLateFeedbackClock` (153.23 s) and
`testSharedPUCCHLateFormat2Clock` (74.71 s). Evidence is
`logs/shared_feedback_late_connected_20261004.mat` / `.log`, with
`logs/shared_feedback_late_connected_source_20261004.mat`. These extend the
default-clock component evidence; they do not accept the original full
bidirectional scenario or production SLS.

The report-richness run `richness_20261004_153331_697` persisted
`TerminalArtifactFixedPointFailed`. Its publication receipt identifies an
earlier primary-CSV semantic failure, before raster materialization; this
is not evidence that the PHY decoder or a plot renderer failed. Missing
CSI-RS execution identity, raw/derived MIMO identities and metric scope,
HARQ population reconciliation, and component-versus-connected artifact
applicability are separate blockers. The original engine was still doing
recovery/export when this entry was written; no duplicate run was launched.

Core `runWaveformLinkBundle` now binds standalone CSI-RS execution metadata
using the existing component-identity function. Measurements are unchanged;
the rows remain `component_anchor`, not eligible as same-scenario in-path
evidence. `testComponentExecutionIdentity` PASSED (4.83 s), including CSI-RS
scope, immutability, conflict and no-promotion checks. Evidence:
`logs/standalone_csirs_identity_20261004.mat` / `.log` and its source receipt.
The old run's missing metadata has not been backfilled or claimed repaired.

Further core RCA found that DL/UL throughput snapshots retained RNTI only
from an optional input grant and otherwise read the wrong generic
`phy.rnti` field. `bindExecutedDataIdentity` now retains the RNTI actually
used by PDSCH/PUSCH and checks it against bound grant identities. It also
retains an executed DL assignment's UE identity and explicit UL/runtime UE
bindings; absent UE identity is not guessed from RNTI. Both core throughput
wrappers use this binding for trial and observed-RE identity. The focused
test includes real one-frame DL and UL executions with a deliberately stale
legacy RNTI alias; result is pending in
`logs/executed_data_identity_20261004.*`. No original HARQ context guard was
weakened. No testAll, E2E test, agenda edit or production campaign was started.

The first executed-identity check PASSED (92.18 s): real DL/UL trial exports
retained RNTIs 181/182 rather than the poisoned legacy alias 999, with UE 1.
Follow-up inspection found `PDSCHCalibrationFacadeAdapter` always started
calibration assignments at UE 1 even with an explicit different configured
or frozen UE. Its calibration branch now retains that explicit identity
and rejects conflicting bindings; connected receiver assignment ownership
is unchanged. The v2 test uses UE 2 and runs the existing
`testPUSCHScheduledHARQAuthority` afterward. Its source and pending result
are retained in `logs/executed_data_identity_v2_source_20261004.mat` and
`logs/executed_data_identity_v2_20261004.*`. This targeted follow-up does not
constitute a full suite or a new scenario launch.

The v2 focused batch PASSED: `testExecutedDataIdentity` (96.15 s), with
actual UE-2 DL/UL transmissions exporting RNTIs 181/182, and
`testPUSCHScheduledHARQAuthority` (46.70 s), with 16 declared binding cases
and unchanged wrong-identity/transport/DAI rejection checks. The latter is
explicitly a retained-control/binding regression, not fresh RF qualification.
Both results are retained in `logs/executed_data_identity_v2_20261004.mat`.
Remaining report blockers above are not closed by these identity passes.

### 2026-10-04: causal adaptive-report audit repair

`tools/lls_csv_semantics.py` still required both a newly scheduled feedback
decision and an applied decision on each adaptive TB. It also compared the
current TB's receiver CQI with the decision that selected that TB. This was
inconsistent with the causal MATLAB reducer: post-TB feedback is for a future
grant, while a previous decision may remain in effect without a new update.
The audit now distinguishes configured bootstrap from applied/held feedback,
checks source-slot/age/delay and actual applied MCS/CQI, and independently
recomputes whether an adaptive decision was observed. Bootstrap modulation
is checked against the direction/table/index entry in the run's MCS
reference CSV; a missing or ambiguous entry does not qualify bootstrap.
Future feedback, wrong decisions and bootstrap-only qualification remain
rejected. Re-auditing the untouched old richness rows now agrees with their
MATLAB execution-contract result; their 32 missing-UE-lineage failures remain.

`testAdaptiveOperatingPointTrialAuthority` PASSED (133.86 s): three actual
coded attempts per direction, each with one bootstrap and two applied
feedback decisions, on the current core throughput paths. This confirms
that the old run's `link_adaptation_mode_reference` bootstrap label is not
reproduced by the current source. These six attempts are not BLER or SLS
qualification. Real trial CSVs/configuration are retained under
`results/lls/adaptive_trial_authority/20261004_172334_117`.
`testMIMONominalVsEffectiveRankEvidence` PASSED (17.17 s), including held,
future, wrong-MCS and bootstrap-only negatives. Batch/source receipts:
`logs/adaptive_trial_authority_20261004.mat` and
`logs/adaptive_trial_authority_source_20261004.mat`.

The metric audit also now accepts the producer's explicit `not_exercised`
availability state while requiring `CountsTowardCoverage=false`. No missing
HARQ retry measurement is promoted to observed data. A separate core repair
in `exportLLSOutputCoverageArtifacts` removes the beam table's RNTI-to-UE-index
substitution; both identities remain separate. Its Python regression
rejects the substitution, and the existing MATLAB coverage-export test now
checks source rows with RNTI but no UE index. That MATLAB check is in progress
in `logs/beam_export_identity_20261004.*`; its source receipt is retained.
The expanded semantic Python file passed all 103 tests before the adjacent
materializer regression was added to the final focused batch.

Still open: independent channel-NMSE reference binding and per-layer/trial
measurement scope, HARQ population reconstruction, and applicability of
connected-only exports to isolated component runs. These are not closed by
fixing the audit. No historical run was rewritten; no testAll/E2E or agenda
work was performed.

Final focused Python batch: **144 passed** across
`test_lls_csv_semantics.py` and `test_lls_contract_materialization.py`.
Machine-readable receipt: `logs/publication_semantics_20261004.xml`.
The MATLAB coverage-export check remains active after building its beam and
timing tables; its subsequent package/provenance audit has not yet returned
a terminal test result. It has not been restarted or called a pass.

### 2026-10-04: beam export verified; HARQ attempt-identity guard

The existing `testLLSOutputCoverageArtifacts` finished PASS (479.49 s),
including separate UE-index/RNTI export and the missing-CSI-RS-source
negative case. Receipt: `logs/beam_export_identity_20261004.mat`.
This is export integration evidence, not a waveform scenario acceptance.

The next retained report defect exposes an insufficient core KPI guard:
`reconstructLLSKPISummaryFromRaw.localHARQMetrics` previously checked only
whether process/time column names existed. A NaN process or absent TBId
could therefore publish an accepted HARQ attempt/NACK population. It now
requires actual nonblank TB identity, integer nonnegative process and slot,
and unique attempts within available UE/cell/sweep scope. Missing evidence
is not replaced with invented identities or decode outcomes.

Focused objective-binding tests now cover missing/blank TBId, NaN process,
fractional slot, duplicate attempts and distinct sweep populations. The
existing received-feedback test retains its CRC-poisoning assertions; its
attempt fixture now supplies its actual declared TB identity. All four
focused KPI tests PASSED: objective bindings (9.43 s), received-feedback
authority (2.10 s), raw schema validation (0.70 s), and artifact schemas
(11.19 s). Source/receipt paths:
`logs/harq_kpi_identity_source_20261004.mat` and
`logs/harq_kpi_identity_20261004.mat`. No full suite was launched.

The original coupled bidirectional scenario and report-richness terminal
closure are still not accepted; these focused repairs do not close all
LLS/SLS runtime or statistical qualification requirements.

### 2026-10-04: actual per-trial HARQ outcomes, not false export defaults

Further production tracing found that `runDLPDSCHThroughput` and
`runULPUSCHThroughput` computed current/combined decoder outcomes but did not
retain them in their per-trial tables. `runWaveformLinkBundle` installed
false defaults for those missing columns. Both core runners now retain
per-attempt current/combined decisions, combining-applied state and the
measured combining diagnostic. Frames which never reach the decision
remain NaN; the final iteration's `out.HARQ` is not replicated across rows.
The bundle no longer fills absent HARQ decisions/retransmission flags with
false.

`exportLLSLiveDerivedTables` preserves numeric unknowns rather than coercing
them to logical values or deriving HARQ decisions from a generic CRC.
Its HARQ CSV now preserves the declared identity/decision schema even when
all values in a column are unavailable. The first focused run exposed this
CSV pruning defect; its failed receipt remains in
`logs/harq_unknown_outcomes_20261004.mat`.
The repaired export test subsequently passed (21.42 s). The actual coded
DL/UL trial-authority test passed (98.14 s; three DL and three UL attempts),
as did KPI objective binding (4.25 s) and received-feedback authority
(2.02 s). All four final-source focused checks passed under
`logs/harq_trial_outcomes_v2_20261004.*`, with complete touched-source copies
in `logs/harq_trial_outcomes_v2_source_20261004.mat`.

The older report-richness job is now terminal, not still exporting:
`logs/lls_richness_export_repair_20261004.mat` records FAIL after 7464.30 s,
identifier `sixgr:lls6g:TerminalArtifactFixedPointFailed`. Its earlier browser
receipt records the actual semantic publication failures. No historical
artifacts have been rewritten as passing. Independent NMSE-reference
binding and component-versus-connected applicability remain open, as does
the repaired-source original bidirectional scenario acceptance.

### 2026-10-04: isolated DL/UL channel-estimate scoring integrated

The core `runDLPDSCHThroughput` and `runULPUSCHThroughput` paths now retain
their already-executed desired-link waveform before additive noise,
interference and receive RF, when physical signal diagnostics are enabled.
`scoreIsolatedDataChannelEstimate` scores captured practical pilot estimates
after decoding through the existing shared reference operator. The reference
is explicitly a noiseless-DMRS LS effective-channel reference, not an oracle
supplied to the receiver or a perfect propagation-channel claim. No extra
channel execution or replacement measurement is introduced. Per-resource
complex CSV and MAT evidence is archived beneath the configured run folder;
unexecuted rows remain unknown.

The first focused execution exposed a production SISO export defect in
`buildReceiverChannelEstimateTable`: REPELEM produced a row-shaped branch
index when SUB2IND required a column. Explicit column shaping repairs this
without dropping resource samples. That failed run is retained in
`logs/isolated_channel_scoring_20261004.*`. The same batch's default shared
PUSCH test stopped before reception because its legacy fixture omitted
`pdcch_strict`; that separate fixture failure is not classified as repaired.

On the corrected source, `testIsolatedDataChannelScoring` PASSED (86.86 s),
including exact baseline/scored decode-outcome equality, independent NMSE
energy reconciliation, complex CSV round-trip and archival hashes in both
directions. Its two baseline/scored TBs failed CRC identically; the passing
test does not relabel those TBs as decoded successes.
`testDataChannelEstimateScoring` PASSED (41.93 s; eight DL/UL rank-1/rank-2
cases at -10 and 20 dB). Evidence/source receipts are under
`logs/isolated_channel_scoring_v2_20261004.*` and
`logs/isolated_channel_scoring_v2_source_20261004.mat`.
The third check, `testTDDSharedPUSCHIndependentCompletion`, subsequently
PASSED (114.84 s): actual SRS/DCI/PUSCH execution, one independently bound
empty-UCI completion, 300 archived complex channel-estimate values and
received-constellation evidence. It does not qualify nonempty HARQ/UCI,
missing DCI or the entire scenario coordinator. All three focused checks
passed. Full scenario publication closure, component-versus-connected
export applicability and the original bidirectional scenario remain
pending. No testAll, E2E or agenda-item work was started.

### 2026-10-04: live NMSE semantics and disabled-audit publication repaired

`exportLLSLiveSignalChainTables` previously labeled every NMSE value as
pilot-residual error divided by pilot power. That is incorrect for the
independent post-decode channel estimator score. The core exporter now
retains NMSE source, captured-resource count, reference plane and CSV/MAT
identity, and publishes the channel-error/reference-channel-energy
definition only with explicit independent-scoring provenance. The separately
measured `PilotReconstructionResidualRatio_dB` remains separate. Missing
channel reference stays unavailable; finite values lacking provenance are
explicitly unverified. The channel-estimation CSV preserves its declared
schema and round-trip numeric precision, including unknown NMSE columns.

`testIsolatedDataChannelScoring` PASSED (108.42 s) after extending the actual
DL/UL test through live CSV export, including scored and unscored receiver
outputs. Original CRC outcomes remain unchanged (these two TBs did not
decode successfully). `testBroadcastWaveformPreview` also PASSED (2.58 s),
retaining 1024 samples across four branches. Receipts/source:
`logs/channel_nmse_live_semantics_20261004.*` and
`logs/channel_nmse_live_semantics_source_20261004.mat`.

The retained richness run also contains an identity-bound causal-audit gate
with Enabled=false, Required=false, zero stage/binding counts and
DISABLED_BY_YAML. Its typed empty detail/binding tables were incorrectly
required by the generic Python domain audit. `tools/lls_csv_semantics.py`
now recognizes that precise producer contract. Missing/contradictory/wrong-
identity receipts, enabled or required configuration, and populated evidence
remain subject to validation. No blanket component-run exemption was added.
145 semantic/materializer tests PASSED; receipt:
`logs/publication_applicability_v2_20261004.xml`. The initial new test's
failure remains in `logs/publication_applicability_20261004.xml`; its final
negative case checks the existing ConfigHash identity audit, not an assumed
cross-run RunID comparison that the generic audit does not implement.

Next confirmed production defect: `runWaveformLinkBundle` initializes
`finalWaveformPreview` empty and only populates it for coupled execution.
Both standalone PHY runners return actual `WaveformPreviewTable` samples,
but the independent sweep collectors discard them and terminal publication
therefore overwrites the preview with an empty table. Preserve exact previews
through single-/multi-user and interleaved collectors, keeping sweep/user
identity, before terminal publication. Do not exempt this required waveform
output. Per-UE throughput can also be derived from actual isolated raw rows
and must not be exempted simply because this older run omitted UE identity.
Full report-richness closure and the original bidirectional run remain open.
