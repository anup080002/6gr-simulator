# Shared-control LLS completion plan

## Core CQI authority and EESM numerical repair (23 September)

Two new core defects reproduced in MATLAB, retained in
`logs/cqi_math_before_20260923.log`: a rejected configured-SNR input with a
rank-two layer vector still produced CQI, and flat 30 dB EESM input with
beta=-3 dB produced Inf. These are declared diagnostic inputs, not findings
that those exact inputs occurred in the current physical run.

`resolveWidebandCQI` now applies its existing input-provenance rejection to
the per-codeword path as well. `EESMMapper` and the CQI reducer use the same
stable algebraic EESM reduction in `sixgr.util.eesmLinear`; it factors out
the minimum linear SINR and uses expm1/log1p, without clipping measured
values or replacing them with a configured/whole-band value. Scalar and
MCS-indexed beta values are interpreted in dB: zero and negative dB remain
valid. The YAML catalog and `buildInternalConfig` preserve those values.
No scenario was switched to EESM or granted a new calibration claim.

Seven focused tests pass in `logs/cqi_math_after_v2_20260923.log`: rejected
layer authority, EESM numerical stability, the existing BLER-LUT selector,
rank/codeword mapping, post-equalization SINR, signed-beta scenario binding,
and parameter-catalog coverage. Numerical coverage includes 32 flat cases
over all eight requested SNR points, 24 public DL/UL cases, four MCS-catalog
cases, plus six actual scenario-builder bindings. The first after-fix run
stopped because the new numerical fixture omitted its required CQI table;
that fixture was corrected without weakening the production guard.

The saturated run started before these edits and is not their integrated
acceptance evidence. It has physically passed rank-two DL slots 48 and 49
with real TB sizes 36896 and 23040 bits (one-ms slot rates 36.896 and
23.040 Mbps). The finite-load V9 engine remains alive in terminal browser
closure; the second forced renderer finished and a subsequent closure
renderer is active (Python 19100, parent MATLAB 14196). The queued
measurement/export tests have not been restarted. Full eight-point
shared-control acceptance, Type-II on-air integration/qualification and
400 MHz shared-control execution remain open. No testAll was launched.

## Per-layer CSV fix and saturated SSB policy (23 September)

`pruneStructurallyBlankTableColumns` used a nonscalar numeric predicate for
multi-column table variables. The original condition reproduced
`MATLAB:nonLogicalConditional`. A two-line all-elements reduction now keeps
the complete measurement variable unchanged. Three focused tests passed:
`logs/csv_per_layer_array_validation_20260923.log` (matrix-valued measurement
round-trip, empty schema, CRC applicability). This is an export edge-case
repair, not the cause of V10's later SSB-slot scheduling gaps.

V10 slots 41/42 excluded PRBs 2:22 for SSB, leaving [0 1 23 24]. The existing
four-PRB minimum correctly prevented crossing that reservation. The public
`scheduler.min_prbs_per_grant` catalog field was not consumed by the builder.
It is now wired to `mac.scheduler.minPRBPerUE`, with positive-integer and
maximum-bound checks. Both saturated 5 MHz YAMLs explicitly select 2; the
running V10 retains its original 4. PF now reports the exact contiguous-PRB
blocker instead of a generic PF/resource rejection. No SSB guard is removed.
`test5MHzSchedulerMinimumGrantPolicy` exercises both SSB slots at RI 2/CQI 15,
quiet-slot full-band allocation and invalid configuration. It and the updated
`test5MHzSaturatedTrafficConfiguration` passed, process exit 0, in
`logs/saturated_ssb_minimum_grant_policy_20260923.log`. This proves core
scheduler/config behavior, not yet the next integrated waveform execution.
The broader four-test verification group remains at the front of the queued
export-validation script. V9's MAT save finished at 19:10 UTC; it now waits
on its second forced browser materialization (Python 8568, launched 19:12
UTC). Measurement/export queues remain live, not restarted.

## Integrated evidence checkpoint (23 September, 00:30 IST)

V10 slot 35 physically executed PUSCH on PRBs 0:24, rank/layers 2,
MCS 22 / 64QAM, target code rate 0.650390625. CRC passed with 0/28168
bit errors and 28.168 Mbps slot goodput. Fixed reference Es=0.25 and
requested SNR=20 dB give injected grid variance 0.0025; measured
post-equalization SINR is 21.3902619784794 dB (not forced to the input).
Slot 34 independently decoded HARQ=3, SR=1, CSI=0, expected/decoded=4/4.
This is actual single-occasion proof, not full-run or statistical acceptance.

Completed V9 retained-data audits: UL/control 294 checks, SSB 168 checks,
RA captures 52 checks, all passed. Receipts are under
`logs/v9_completed_{ul,ssb,ra}_evidence_20260923_0030.json` (the RA path
is a directory containing the source-hash-named JSON/CSV receipt).
These are arithmetic/provenance audits, not independent PHY qualification.
V9 `scenario_summary.csv` now says Ok=1; process 14196 still saves the
optional MAT bundle. Known CSI/rank export repairs remain unverified,
and the focused MATLAB queues remain waiting for that process to exit.

## Received CSI public-table repair (23 September, focused/replay verified)

`buildLLSPublicOutputTables` previously constructed `csi_report_table` from
scheduler grants, joined MCS by CQI/UE without report identity, and inferred
modulation from a table-independent MCS threshold. V9 has four actual
`control/csv/received_csi_reports.csv` rows: source slots 34/39/44/49,
delivered 39/44/49/54, RI 2, PMI 30/17/17/27, raw CQI-derived MCS 28 / 64QAM.

The public reducer now consumes only those independent receiver records.
It retains report identity, source/due/delivery timing and reception outcome;
failed or unavailable decoding cannot publish CQI/PMI/RI values. It never
fills numerical SINR from UE reference JSON or scheduler thresholds. The
old scheduler-join/modulation helpers are removed. Scheduler observation
tables remain separate. Coverage export reads the canonical receiver CSV.

`testReceivedCSIReportPublicExport` covers absent/poisoned scheduler data,
poisoned UE references, failed/unknown decode outcomes, rejected non-receiver
sources and exact modulation lineage. The coverage fixture now explicitly
supplies a declared receiver report instead of relying on scheduler rows.
Two small single-threaded tests passed in
`logs/received_csi_export_smoke_20260923.log`; the process exited successfully.
Actual retained receiver CSV replay also passed, preserving four reports,
RI 2, PMI 30/17/17/27, MCS 28 / 64QAM and distinct source/delivery clocks:
`logs/received_csi_export_retained_replay_20260923.log` and
`logs/received_csi_export_v9_replay_20260923.csv`. These short tests used
recovered memory while the two existing engines remained active; they were
not additional PHY runs or testAll. V9 primary results were not overwritten.
The full coverage fixture and adjacent integrity tests remain queued after
PowerShell 19220: `logs/received_csi_export_validation_20260923.log`.
End-to-end integration/regeneration is still pending.

## Measurement-timeseries authority repair (23 September, verification pending)

Retained V9 `reports/csv/measured_sinr_timeseries.csv` has five wrong DL rank
labels: slots 32/37 say 4 instead of executed 1; slots 47/52/57 say 4 instead
of executed 2. Raw receiver `EffectiveRank`/`Rank` and `Layers` are intact.
`buildPhase7ReadinessArtifacts/localMeasuredSINRRowsFromTrials` prioritized
`RankEstimate` (channel hypothesis) over the transmitted allocation.

The reducer now selects executed rank/layer fields, not RankEstimate or
RankIndicator. It also uses `selectReceiverDataSINR` per row with exact
source/role/status, so missing data SINR cannot be filled from pilot or
large-scale SINR. CQI-derived recommendations no longer fill unknown
transmitted MCS/modulation. No physical channel/rank decision was altered.

Added `testPhase7MeasuredSINRAuthority` and corrected the geometry audit's
declared measurement fixture metadata. The three focused checks (new test,
receiver selector, geometry export audit) are queued behind V9 publication
engine 14196, preserving a maximum of two MATLAB engines. Expected log:
`logs/measured_sinr_rank_authority_20260923.log`. Do not claim this repair
verified until that process completes. V9 still requires a fresh derived
export after verification; its original incorrect CSV remains retained.

## Latest focused integration (22 September, late evening)

The saturated single-UE YAMLs now turn off the permanent PUCCH frequency-pool
exclusion only; physical PUCCH, per-occasion temporal overlap detection,
UCI-on-PUSCH and `reject_before_waveform` remain enabled. The configuration
test calls the production slot-budget producer and contiguous allocation
primitive: old allocation 6:24, new schedulable allocation 0:24. This is not
yet a measured throughput result or general multi-UE reservation solution.
`logs/saturated_ul_occasion_policy_20260922.log` records 3/3 passing tests:
saturated traffic/budget, rank/precoder contract, and PUSCH HARQ transport.
The transport fixture now uses the actual target TDD format-2 policy and a
legal next UL feedback occasion; illegal DL-slot feedback remains rejected.
No production decoder or timing guard was weakened.

Publication optimization: `buildPHYPackageExecutionAudit`
normalizes the profiler's immutable path column once per invocation instead
of repeating scalar normalization in both source inventories. The old exact
implementation and before/after experiment are retained under
`logs/publication_audit_reference_20260922`. All five output tables compare
exactly on the retained five-file/384-profile-row fixture: 10.325052 seconds
before, 2.978155 after (3.467x on that fixture only). The full source-inventory
regression and saturated eight-point physical-noise check both PASS in
`logs/publication_audit_equivalence_v2_20260922.log` (process exit 0).
Across [-30,-20,-10,0,10,20,30,40] dB, the largest absolute measured sample/grid
noise discrepancy is 0.0471708 dB, below the unchanged 0.3 dB test limit.
These are generated-noise checks, not an integrated eight-point run.
No audit gate is skipped.

Started the saturated integrated 20 dB candidate at 23:54:46 IST on 22 September:
`logs/5mhz_rank2_20db_saturated_20260922_v10.log`, run tag
`5mhz_rank2_20db_saturated_20260922_v10`. This is the first integrated run of
the queue-utilization repair plus the saturated per-occasion overlap policy.
Do not infer its pass status or measured throughput from focused checks.

V9's persisted causal PHY gate now reports 28 stages and zero required-stage
failures. Source-inventory evidence gates also pass (2,158 source files and
7,852 captured/exported profiler functions). Final publication is still active.

## Saturated traffic and expanded acceptance scope

User selected saturated traffic for the next 5MHz run. New YAMLs preserve
the original finite-load scenario and all physical control/reference blocks:
`lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml` and
`lls_tdd_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml`.
The latter retains independent points [-30,-20,-10,0,10,20,30,40] dB.
The shared traffic fragment offers 100Mbps in each direction, exceeding
the 50.4Mbps rate-one/no-overhead rank-two 64QAM upper bound. This is
explicit finite saturated offered load, not injected delivered throughput.
`logs/5mhz_saturated_config_validation_20260922.log` records 2/2 passing
configuration/precoder checks, including actual generated arrivals and
unchanged PHY/channel/MAC configuration at that checkpoint. The later
permanent-reservation policy change and integrated launch are described above.

The expanded goal includes SSB beam management, CSI beamforming, causal
PMI/RI/CQI, and separate applicable Type-I/Type-II codebook verification;
the existing Type-I result is not Type-II qualification. Complete 5MHz
sweep/measurement/CSV/PNG acceptance precedes full-control 400MHz acceptance.

UL resource-use finding: mixed-slot PUCCH uses zero-based PRBs4-5 on
symbols12-13. Full UL PUSCH grants use PRBs6-24, symbols0-12. The configured
static PUCCH pool reserves PRBs0,4,5 even outside its active occasions;
PF's minimum four-PRB contiguous chunk skips the remaining PRBs1-3.
This is a conservative allocation limitation, not measured RF loss.
Occasion/symbol-aware reclamation must preserve independently scheduled
receive obligations, Type-2 HARQ identity and PUCCH/PUSCH overlap guards.
Do not disable the physical PUCCH path or its per-occasion overlap guards.

V9 runner reported result.Ok=1 and requiredFailures=0 at 17:50:42Z;
terminal CSV/PNG/browser publication is still in progress, not accepted yet.

## Queue-limited throughput repair (22 September, after V9 physical completion)

V9 completed all 58 physical slots and sealed continuous Tx-IQ at 17:38:09Z.
Raw receiver evidence contains 19/20 DL CRC passes and 5/5 UL passes; the
slot-58 DL failure remains recorded (rank2, one PRB, MCS27, TBS1480,
G1584, 47 bit errors, post-EQ SINR19.6369493750123 dB). Final artifact
generation is still active; this is not an overall acceptance receipt.

The slot48/49 throughput drop is a separate scheduler defect: the
preserve-AMC queue-limited branch selected the smallest positive TB even
when larger TBs fitted the remaining queue. SchedulerBase now selects the
largest exact TB fitting that queue, then minimizes PRBs among equal-TBS
allocations. Only a queue below the minimum legal TB uses explicit padding.
MCS/rank authority and subsequent exact PHY-capacity checks are retained.
The production edit was made after V9 physical execution completed; V9 is
pre-repair evidence. Its exact scheduler source is preserved with matching
SHA256 in logs/v9_queue_scheduler_before_20260922/SchedulerBase.m.

- Before: logs/scheduler_queue_utilization_before_20260922.log reproduces
  one PRB versus the enumerated exact fitting allocation.
- After: logs/scheduler_queue_utilization_after_20260922.log records 6/6
  focused tests passing, including 48 PF/RR, DL/UL, rank1/2 queue cases,
  NRCQI/grant sizing, actual DL coded capacity, grant consistency, OLLA dB
  mapping, and exact TBS/poisoned-override rejection. No testAll was run.
- For a rank2 1414-byte queue and 12 symbols the repaired planner chooses
  7 PRBs/TBS10760; this is a planner result, not a new measured throughput.
- Still open: integrated rerun of this scheduler revision and final V9
  publication/measurement audit. The YAML's finite 5Mbps BIDIR flow,
  split equally DL/UL, does not provide truly saturated traffic despite
  the inherited full_buffer label. Do not claim peak-throughput acceptance.

## Slot-48 repair verified in V9 (22 September, 22:44 IST)

The actual `air_interface/csv/dl_pdsch_trials.csv` row for slot48 now
records rank2, MCS27, TBS1480, rate-matched bits1584, and CRCPass=1.
Original/current TBS and rate-matched sizes agree; the TS38.212 bit-count
delta is zero. Post-EQ SINR is20.598409250921 dB. The previous
BadInitialCodeRate boundary is therefore passed by the integrated physical
receiver, not only the isolated feasibility test. ConfiguredLayers remains1.
The active run has not yet finalized; slots49 onward, feedback disposition
and final measurement/publication acceptance remain unverified.

## Current validation and live UI (22 September, 22:40 IST)

- `logs/tdd_transport_revalidation_20260922.log` finished 3/3 passing:
  typed Type-2 runtime planning, physically rejected UL control with no UE
  PUSCH and no false usable HARQ feedback, and actual shared DL reception
  feeding nonempty HARQ on received PUSCH through the common commit path.
  These are focused components, not the full missing-DCI probability matrix.
- `logs/final_report_semantics_20260922.log`: 119 Python tests pass across
  exact captured PHY chart closure, constellation source, row lookup and
  CSV semantics. Final-run generated artifacts are still unverified.
- Actual V9 DL slots44 and46 pass CRC at rank2/MCS28 while retaining initial
  ConfiguredLayers=1; their post-EQ SINRs are 21.3016 and21.3856 dB. Slot44
  PUCCH also passes12/12 bits. Slot48 and run finalization remain ahead.
- WebGUI started using the supported launcher, loopback62906, auth retained.
  Active filesystem run ID9651786322 is discoverable with status running:
  http://127.0.0.1:62906/realtime?run_id=9651786322 . Login page HTTP200
  verified. Browser opening was blocked by the tool policy; user got link.
- OLLADeltaMCS is an intentionally retained legacy dB alias, not an MCS
  index increment: actual rows declare OLLADomain=delta_db_required_sinr_margin
  and preserve required-SINR threshold lineage. It was inspected, not changed.
  Do not list that naming compatibility as a new proven arithmetic bug.

## Cross-path follow-through (22 September, 22:27 IST)

- The standalone reference-energy/DL/UL/OFDM set finished 4/4 passing in
  `logs/standalone_awgn_reference_after_20260922.log`.
- A further actual numerical defect was reproduced in
  `addPUSCHReferenceNoise`: non-unit DataEPRE was used in its signal ledger
  but omitted from the common physical noise call. Es=0.25 injected Ngrid
  0.188364908949 instead of 0.0470912272372 at the held 7.25 dB point.
  The first test launch failed in MATLAB's licensing service before code
  execution; the retry reproduced the assertion. Neither was hidden.
- Production repair passes DataEPRE to addOccupiedREAWGN. The strengthened
  FRC regression compares actual demodulated noise, exact same-seed sample
  equivalence after explicit slot-SNR to RE-Es/N0 conversion, and energy
  accounting for both mapping types at Es=0.25/4. Default Es=1 is unchanged.
- `logs/frc_scaled_reference_after_20260922.log`: 5/5 pass, including FRC
  slot-SNR, common-noise adapter, configured shared receiver noise at
  25PRB/15kHz and 264PRB/120kHz, and the fading receive-normalization guard.
  This does not establish complete coded-link BLER equivalence across paths.
- V9 slot39 is now an actual PASS: HARQ4/SR1/CSI10, expected/decoded15/15,
  all four HARQ feedback decisions applied. The run is active at slot40.
- Next bounded focused batch: Type2HARQRuntimePlan,
  SharedRejectedULDueHARQ, TDDSharedPUSCHNonemptyCompletion, recorded in
  `logs/tdd_transport_revalidation_20260922.log`. No testAll or 400 MHz
  scenario was launched; only the 400 MHz receiver-noise component ran.

## Standalone core noise reference repair (22 September, 22:19 IST)

- The normalized before-test reproduced EsRef=0.25 ignored by the standalone
  DL path: applied Es=1, Ngrid=0.001 instead of 0.00025 at 30 dB (6.02 dB).
- `runDLPDSCHThroughput` and `runULPUSCHThroughput` now bind configured
  reference energy before channel realization. Received occupied-RE energy
  remains separate measurement evidence; it cannot recalibrate AWGN.
- Absolute-power callers convert that reference with the actual single TX
  amplitude scale squared. UL's dormant helper incorrectly multiplied the
  power-control alias a second time; that duplicate factor is removed.
  The thermal-noise branch and physical waveform power are unchanged.
- Only the standalone local noise functions and their calls changed in
  this turn. V9 uses prepareOnly/receivedCompletion, not those functions.
  Exact pre-edit files are in `logs/standalone_noise_pre_repair_20260922`.
- `logs/standalone_awgn_reference_after_20260922.log`: the new four-case
  DL/UL test passes for EsRef=0.25 and 1. Adjacent DL/UL and OFDM tests are
  still running; no full cross-path or full-suite qualification is claimed.
- V9 is running at slot37/58. Actual slot34: PASS, HARQ3/SR1/CSI0,
  expected/decoded4/4, three feedback decisions applied. UL35 CRC passes,
  MCS22, configured initial layers1 versus executed rank2, measured
  post-EQ SINR21.5003 dB; configured/applied reference SNR20/20.
- No testAll or 400 MHz run launched. Full 58-slot and final artifact
  acceptance, broad missing-control/detector statistics and matched-seed
  rank1/rank2 scientific campaigns remain pending.

## Probe cross-path and real UL combining repair (22 September, 22:05 IST onward)

V9 is active (launcher 5924 / engine 14196, creation 21:47:47), using the
5 MHz full-control YAML. Its active data-runtime source remains unchanged.
This turn repairs the standalone HARQ probe, which is NOT substituted for
the coupled runtime's own HARQ observations.

- The first probe noise repair still recalibrated Es from each noiseless
  received waveform. `harq_probe_fixed_reference_before_20260922_v2.log`
  reproduced violation of configured reference energy 0.25. The probe now
  uses `resolveAWGNReferenceEnergy`, while exporting measured received Es
  and empirically measured injected grid-noise variance separately.
- A new physical UL test exposed a second defect: receiver CRC passed with
  zero bit errors, but the wrapper's redundant decoder declared NACK. The
  wrapper also omitted prior UL soft-buffer delivery. Both are repaired:
  actual receiver decode/soft-buffer ownership is retained and no second
  LDPC decoder is invoked to overwrite ACK/NACK.
- A cumulative CRC is no longer exported as an independently measured
  current-attempt CRC. CurrentDecodeOK is unavailable for combined-only
  attempts, with CurrentAttemptStandaloneCRCMeasured=false.
- `logs/harq_probe_canonical_decoder_after_20260922.log`: 3/3 tests pass,
  including real DL/UL rank1/rank2 CRC/bit comparison, fixed grid variance
  0.00025 at 30 dB with EsRef=0.25, and a held -12 dB UL episode with four
  attempts and three position-aware combinations. Runtime-only HARQ export
  reuse passes. This is not a statistical gain or BLER qualification.
- Actual test CSVs are retained under
  `results/lls/harq_probe_fixed_noise_reference/20260922_220406_729`.
- Standalone runDLPDSCHThroughput/runULPUSCHThroughput still derive noise
  from measured received Es instead of the fixed configured reference.
  `testStandaloneAWGNReferenceEnergy` covers that remaining gap; the first
  receipt includes default absolute-power scaling, and a second execution
  explicitly selects normalized FIXED_SNR_SWEEP for a like-for-like check.
  These active V9 source files have NOT been edited during the run.
- V8's four unresolved PUCCH grant rows are due at slot49, after its slot48
  termination. Its slot34/39/44 completed grant rows are finalized successes.
  Do not describe that pending-future registry entry as a new slot34 failure.

## Current core-MATLAB integration (22 September, after V8 termination)

This section supersedes the historical candidate-only status below. V8 ended
with `BadInitialCodeRate` at slot 48; its recovered result, Phase7 and
publication gates are all false. No full 5 MHz acceptance is claimed.

- Main `computeLinkAdaptationDecision` now maps the legacy OLLA dB margin
  through required-SINR thresholds. Six production tests pass in
  `logs/olla_main_integration_20260922.log`.
- Main `SchedulerBase` recomputes exact allocation feasibility before
  freezing new DL grants. The reproduced slot-48 allocation now chooses
  MCS27, TBS1480/G1584, retaining rank2 and raw CQI15/MCS28 provenance.
  Fixed-MCS rejection and immutable retransmission guards remain enabled.
- `PUSCH_Rx`, `runULPUSCHThroughput` and the noise-domain validator preserve
  the actual pre/post-EQ decoder variance domain. No noise value was altered
  merely to change a label.
- ConfiguredLayers was overwritten by grant-mutated config in runtime
  exports. It now travels from rank policy through AMC, PF/RR plans and
  grants to DL/UL rows; the shared row annotator no longer overwrites it.
  Missing original configuration is not replaced with actual trial rank.
- `logs/rank_noise_runtime_after_20260922.log`: six focused tests pass,
  including both scheduler classes' DL/UL rank provenance, noise-domain
  contract, actual UL link, slot-48 feasibility and scheduler consistency.
- HARQ probe formerly used whole-waveform power for AWGN and a legacy CSI
  extractor. Baseline reproduced successful CRC but NaN SINR, not a proven
  universal 43 dB error. It now uses the common occupied-RE noise primitive
  and receiver post-EQ SINR. The strengthened DL probe measures injected
  noise on demodulated REs and passes; post-EQ SINR is 32.993 dB at a 30 dB
  reference with two receive branches. Runtime-HARQ reuse also passes in
  `logs/harq_probe_noise_after_20260922.log`. This is not a complete UL/fading
  or retransmission-gain qualification.
- OFDM transform, shared AWGN/FRC adapter equivalence and FRC noise tests
  pass after repairing component-fixture setup. Two Doppler component tests
  pass; V8 has 48 `static_zero_doppler_reconciled` rows. This does not qualify
  all moving/fading scenarios.

Still required: integrated rerun through all 58 slots, physical missing-DCI
and transport-overlap matrix, actual-policy detector statistics, all final
CSV/PNG/measurement gates, and numerical cross-path rank1/rank2 campaigns
with matched reference definitions and adequate sample counts. The current
eight-point sweep explicitly remains a diagnostic, not a BLER publication
campaign. Full physical-control 400 MHz follows 5 MHz acceptance; ideal
feedback does not satisfy that goal. No testAll was launched in this repair.

## Legacy OLLA candidate verified while V8 exports (22 September, 21:24 IST)

This goal turn made concrete progress: the isolated candidate now removes
legacy dB-as-index arithmetic, routes all domains through the existing
required-SINR mapping, preserves HARQ dB state at MCS bounds, and stops
labeling that state as an index-domain offset. It retains the legacy ILLA
smoothing option. **This is not yet a main-code or scenario acceptance.**

Candidate file:
`tmp/olla_units_candidate_20260922/+sixgr_candidate/computeLinkAdaptationDecision.m`.
Only the package namespace differs; dependencies remain the current repository
implementations. Tests default to the real production function and accept an
explicit function handle only for this isolated source-frozen verification.

- `logs/legacy_olla_units_candidate_20260922.log`: DL and UL both select
  MCS17 at -5.4 dB, matching the threshold mapping; unchanged feedback count
  and dB state, finite threshold lineage and correct OLLA domain pass.
- `logs/legacy_olla_smoothing_candidate_20260922.log`: existing legacy ILLA
  smoothing/reset regression passes with its mixed-unit expectation replaced
  by an independent threshold-table calculation. The 22.4 smoothed MCS and
  reset assertions are retained.
- Production `computeLinkAdaptationDecision.m` is still unchanged and its
  explicit legacy branch still needs the verified patch integrated.

V8's engine 11940, creation 20:08:52, was revalidated live throughout the
turn. It finished constructing coverage tables and is writing CSV/sidecars.
No restarted simulation and no testAll. Main runtime/config/publisher edits
remain paused during artifact recovery to protect result provenance.

Additional actual V8 output now proves that all three completed UL trials
appear in `air_interface/csv/lls_measured_sinr_summary.csv` (UL aggregate and
UE1 groups), median 21.5003032315911 dB. This supports the specific status-
filter repair only, not overall acceptance or every throughput formula.

Pre-DCI repair integration notes: the runtime reapplies received AMC and
refreezes new-data grants through `SchedulerBase.freezePHYGrantForGrant`.
Capacity backoff must therefore survive this same finalization boundary,
keep the received CQI/OLLA recommendation distinct from the executable MCS,
and reconcile served/buffer bytes with the final exact TBS. Retransmissions
must preserve their original TB. PF/RR currently pack DCI immediately after
freezing; merely setting Valid=false at the new guard would move the failure
earlier, not complete the repair.

## TBS, OLLA and UL-SINR claim audit (22 September, 21:12 IST)

The three user-reported allegations were checked against current production
callers and actual retained results, not accepted as a diagnosis wholesale.

| Claim | Current evidence | Status |
| --- | --- | --- |
| Default TX bypasses nrTBS and self-certifies an approximation | Both TX chains independently call nrTBS. The scheduler defaults to faithful/exact sizing. `testTransportBlockSizeExactness` passes all 12 DL and 12 UL allocation checks and poisoned-grant/echoed-override rejection in both directions. | Not reproduced in current default path. |
| OLLA dB added to MCS index | CQI scheduler/runtime callers use `applyOLLADeltaDbToMCSIndex`; their regression passes. However, the explicitly configured `legacy_mcs` branch of `computeLinkAdaptationDecision` still adds the shared dB-valued state to an index. New regression reproduces DL MCS16 versus required-SINR mapping MCS17 at -5.4 dB. | Default CQI path repaired; legacy branch remains open. |
| UL bounded-residual SINR discarded | Generator uses shared `isAcceptableSINRStatus`; status and artifact regressions pass with the exact status. Retained V6 summary has five UL trials, median 21.392866 dB. V8 raw UL slots 35/40/45 have MCS22/20/22 and finite bounded-residual SINR. | Not reproduced in current generator. |

Receipts:

- `logs/tbs_olla_ul_sinr_claims_20260922.log`: 5/5 focused tests pass
  (scheduler consistency, frozen TBS vectors, scheduler OLLA mapping, SINR
  status usability, measured-SINR curve artifacts).
- `logs/tbs_exact_override_guard_20260922.log`: exact-default and both TX
  poisoned-override guards pass.
- `logs/legacy_olla_units_before_20260922.log`: new targeted legacy regression
  fails as expected; production repair has not been applied. The test contains
  both DL/UL checks, but stops at the first DL failure before UL executes.

Legacy repair: retain optional MCS-domain **inner-loop smoothing**, but route
the shared HARQ **dB-domain outer-loop margin** through the same required-SINR
mapping in every domain. Remove the legacy branch's dB-as-index addition and
MCS-bound rewriting of the accumulated dB state. Correct its OLLADomain and
offset provenance; do not change active CQI policy or tune against V8.

### V8 failed at slot 48; not accepted

Physical execution failed at 21:02:55 IST with `sixgr:harq:BadInitialCodeRate`.
The run is still recovering report artifacts at this checkpoint; engine
11940 (created 20:08:52) is active. Runtime/config/publisher sources remain
unchanged during that recovery. No testAll, cleanup, push or new scenario run.

`testSharedDLActualCodeRateFeasibility` reproduces the exact target YAML and
slot-48 allocation independently: PRB0, symbols [2 12], rank2, MCS28,
nominal NRE/PRB=138, exact nrTBS=1544, actual coded G=1584 (132 data RE/PRB).
The scheduler incorrectly reports Valid=true; the downstream HARQ guard
rejects 1544/1584=0.974747. Receipt:
`logs/slot48_code_rate_before_20260922.log` (expected failing regression).

Required repair is pre-DCI resource-aware feasibility in
`SchedulerBase.finalizeExactPHYFeasibility`, with integration into final
selection rather than allowing an infeasible grant into DCI/TX. Preserve exact
nominal nrTBS, actual reference reservations, retransmission TB identity and
the HARQ guard. An invalid result alone is insufficient: PF currently calls
`buildDCIBitfield` immediately after freeze, so rejection/reselection must be
handled by the scheduler instead of moving the crash earlier.

Standards note for the forthcoming repair: TS 38.214 v18.8.0 section 5.1.3
defines DL effective rate **including CRC bits**, and permits the receiver
to skip initial decoding above 0.95. Existing `createTBContext` currently
exports payload-only TBS/G; do not describe that as the standards-defined
CRC-inclusive rate or silently reinterpret old artifacts. Source:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf

Still pending alongside these repairs: the pre/post-EQ decoder-domain label
fix below, final measurement/publication acceptance, physical detector and
missing-DCI qualification, and full-control 400 MHz implementation/acceptance.

## Decoder-domain repair regression reproduced (22 September, 20:59 IST)

The current goal turn made progress by reproducing the open domain-label
defect at all three boundaries. `logs/ul_decoder_noise_domain_before_20260922.log`
completed with three expected failures, exit 1:

- `testNoiseDomainEvidenceContract`: existing validator accepts the wrong
  pre-EQ domain label instead of rejecting it.
- `testConnectedFourPortUL`: actual PUSCH decoded its transport block, then
  failed the new comparison of public domain versus executed resolver domain.
- `testLLS_UL`: actual low/high-SNR trials ran, and the new primary-export
  assertion failed on the low-SNR table's domain label.

The tests now also contain post-repair checks for pre/post-EQ mode, once-only
CSI weighting, and rank 1/2/4 reception; those later checks have **not** yet
executed past the first pre-fix failure. No production file was changed while
V8 was running. The required repair spans `PUSCH_Rx`, trial-domain propagation
in `runULPUSCHThroughput`, and `validateNoiseDomainEvidence`; it must not change
variance values or decoder/CSI weighting. Research-transport annotation must
also avoid naming the native decoder when the experimental demapper executed.

Additional actual V8 evidence: slot 44 decoded **1 HARQ + 1 SR + 10 CSI**
(12/12 bits). Its PDSCH used rank/layers=2, MCS28/64-QAM, two measured DMRS
ports and passed CRC, with applied CSI source slot 34. The earlier slot-39
grant remained rank one. Thus received CSI changes a future grant without
rewriting the already-issued grant. V8 remains live at slot 46/58; final
artifacts and overall acceptance remain pending.

## V8 combined CSI/HARQ and first PUSCH verified (22 September, 20:51 IST)

This goal turn made progress through actual integrated slot-39 feedback,
causal UL adaptation, independent EVM comparison, and a newly exposed
decoder-noise domain-label defect. V8 remains live at slot 43/58; production
source remains frozen and overall acceptance is unproven.

### Passing integrated evidence

- Slot 39: **4 HARQ + 1 SR + 10 CSI Part 1 + 0 CSI Part 2**, expected /
  decoded / receiver-expected **15 / 15 / 15**, CRC pass, UCI content match,
  DTX=0, four feedback applications, zero stale dispositions. ACKs bind to
  source slots **34, 36, 37, 38**.
- Decoded CSI source slot 34 / due slot 39: **RI=2, CQI=15**, delivered to
  the runtime scheduler from decoded fields, not raw UE measurements.
- Slot-35 PUSCH: rank/layers=2, measured DMRS ports=2, 64-QAM, MCS22,
  scheduler CQI12, target code rate 0.650390625, CRC pass, RawBER=0.
  It uses the received slot-30 SRS minimum-layer prediction 22.558135 dB.
  Configured/applied AWGN reference SNR=20/20 dB; measured post-EQ SINR
  21.500303 dB. These are distinct physical reference planes.
- EVM from all 5,472 retained raw equalized/reference symbol pairs across
  two layers is 8.636770006816045%; exported value is 8.63677000681604%.
  Independent `comm.EVM` gives 8.63677000681607% (peak 30.9545955384117%).
  Receipt: `logs/5mhz_v8_slot35_evm_toolbox_20260922_v2.log`, exit 0.
  First launcher failed string quoting before measurement and is preserved
  as `logs/5mhz_v8_slot35_evm_toolbox_20260922.log`.
- `logs/5mhz_v8_slot39_combined_binding_20260922.json`: zero failures under
  the then-existing audit, including seven HARQ dispositions and the first
  decoded CSI delivery. This does not subsume the new domain check below.

### New open measurement-export defect (not a decoder-value failure)

`PUSCH_Rx.localResolvePUSCHDecoderNoiseVariance` correctly retains
`pre_equalization_channel_estimator_noise_variance_for_nrPUSCHDecode` for
its pre-EQ variance plus once-applied equalizer-CSI path. However,
`PUSCH_Rx.m` near line 1221 and `runULPUSCHThroughput.m` near line 2534
hardcode `LLRNoiseVarianceDomain=unit_constellation_soft_demapper_input`.
Slot-35/40 exported values match the pre-EQ estimator variance, not a
post-EQ unit-constellation variance. The numeric decoder path is unchanged.

Required repair after V8's production freeze:

1. Export the executed noise resolver's domain from `PUSCH_Rx`.
2. Collect and propagate that per-trial domain through `runULPUSCHThroughput`,
   including its shared-completion/export paths; do not relabel the numeric
   value, inject a conversion, or alter LLR/CSI weighting.
3. Extend focused pre/post-EQ receiver/export tests and rerun the retained
   integration audit. The generic MATLAB noise-domain test currently only
   requires this domain to be nonblank and does not catch the mismatch.

The independent audit now catches the mismatch. Final-source audit tests:
**62 passed**, `logs/ul_decoder_noise_domain_audit_20260922_v2.xml`.
Actual receipt `logs/5mhz_v8_ul_decoder_noise_domain_20260922_v2.json` has
**two failures**, precisely the domain labels at UL slots 35 and 40; the
variance-value checks pass. The first audit attempt relied on a configured
mode column absent from integrated exports and therefore skipped this check;
its zero-failure receipt is retained but is not evidence for domain closure.
The guard now keys on the actual exported decoder source and its unit test
explicitly omits the optional mode field.

Slot-41/42 no-grant investigation: the retained exclusion table records SSB
reservations leaving `[0,1,23,24]`, two disjoint two-PRB ranges. The PF final
allocator enforces its minimum contiguous chunk, unlike its one-PRB-minimum
probe. CSI input is RI2/CQI15/MCS28 with free HARQ processes; this is not a
reproduction of the bootstrap-rank cap. No resource policy was loosened.

Remaining scope is unchanged: final 58-slot execution, all measurement and
artifact closure (including the domain repair), detector/missing-DCI and
MAC-SR gaps, then full-control 400 MHz. No `testAll` or 400 MHz run started.

## V8 slot-34 integrated closure (22 September, 20:38 IST)

The previous goal turn made progress through the exact-target absent-producer
component and its legacy regression. This turn adds independently checked
integrated evidence: V8 completed slot 34 and advanced to slot 35. The original
mixed numeric/logical table crash did not recur.

Actual `air_interface/csv/pucch_trials.csv` slot 34:

- Expected/decoded/receiver-expected totals: **4 / 4 / 4**.
- Field ownership: **3 HARQ + 1 SR + 0 CSI Part 1 + 0 CSI Part 2**.
- PUCCHDecodeOk=1, UCIContentMatch=1, DTXFlag=0.
- HARQFeedbackAppliedCount=3, StaleHARQFeedbackCount=0.
- `control/csv/gnb_harq_feedback_observations.csv` independently records
  ACK and actual application for source slots **31, 32, 33**, due at 34.

The independent audit now reconciles PUCCH HARQ disposition rows with their
gNB mapping, UE/RNTI/occasion, capture sample clock, actual decoded bits and
stale/application flags. It checks complete unique bit dispositions and
aggregate applied/stale counts. It does not use expected TX bits to override
receiver outcomes, does not require a UE producer, and explicitly does not
claim the separate PUSCH binding schema is covered. This is an audit-tool
change only; V8 production source is unchanged.

- Final-source Python tests: **155 passed** across uplink audit and CSV
  semantics; `logs/pucch_harq_binding_semantics_20260922.xml`.
- Actual V8 partial receipt: `logs/5mhz_v8_slot34_harq_binding_20260922.json`,
  zero failures, three PUCCH observations, two standalone SR observations,
  three HARQ dispositions, one SRS observation. PUSCH and delivered CSI
  were not yet observed in that checkpoint and are not counted as passing.
- Earlier retained-V6 audit remains failed only on its known slot-24 CSI
  state-change export mismatch; all added HARQ binding checks passed there.
  Receipt: `logs/5mhz_v6_harq_binding_audit_20260922.json`.

Still open: V8 slot 39/later combined feedback, all 58 slots, final
measurement/CSV/PNG closure, detector/missing-DCI qualification, unsupported
short HARQ+SR resource hypotheses and MAC-SR lifecycle, then full-control
400 MHz integration/execution. This checkpoint is not full-run acceptance.

## Exact-target absent-producer component passed (22 September, 20:31 IST)

`logs/5mhz_exact_receive_only_20260922_v4.log` records a passing physical
component on the unchanged 5 MHz/20 dB target configuration:

- Three actual DL transmissions, no executed UE DCI/data decoding, and no
  UE UCI producer. This is an absent-producer test, not an observed PDCCH
  missed-decode rate.
- Independent gNB obligation: HARQ=3, SR=1, CSI=0, format 2, four bits.
- Actual noise-only receiver metric 0.18923 against unchanged threshold
  0.2; DTX and all three HARQ dispositions DTX. No false ACK in this one
  episode; no statistical qualification claim.
- Frozen-context, stale/duplicate completion, UE-evidence poisoning,
  absent-calendar rejection and actual IQ replay-equivalence guards pass.
- Evidence: `logs/5mhz_exact_receive_only_20260922_v4/`, including actual
  SRS/IQ captures, `pucch_receive_only_trials.csv` and
  `gnb_harq_feedback_observations.csv`.
- At 20:32 IST the same batch also passed the original two-grant default:
  two actual DL transmissions, no UCI producer, DTX/DTX, and all existing
  rejection/replay guards retained. Its physical evidence is under
  `logs/5mhz_legacy_receive_only_20260922_v4/`.
- Production source remains frozen for V8, currently at slot 31 with actual
  received SRS and first DL DCI passing. Slot 34/39 and final artifacts
  remain unverified on V8 at this checkpoint.

## Verification follow-up (22 September, 20:24 IST)

- V8 remains active on its frozen production source, last observed at slot
  23/58. No final acceptance or slot-34/39 result is claimed yet.
- The adjacent export/E2E batch finished: five of six passed, including
  `testE2E_FastVsTruth` and all three seeds of
  `testE2E_TruthPacketSemanticCampaign`. The original scheduler test failed
  to acquire the 5G Toolbox license; its separate retry passed in
  `logs/sr_export_closure_20260922_v2.log`. Preserve both receipts rather
  than relabeling the first batch as passing.
- Exact-YAML receive-only component attempt 1 exposed missing test artifact
  authority (`run.rootRunFolder`); the test now supplies the output root and
  initializes the production sweep clock instead of disabling IQ capture.
- Attempt 2 reached the existing explicit guard for two HARQ bits plus SR:
  `UnresolvedSRPUCCHReceiveHypothesis`. This unsupported short-payload case
  remains open. The guard and production behavior have not been weakened.
- The component test now optionally schedules three real DL transmissions
  at slots 6/7/8, preserving its original two-grant default. This permits
  testing the slot-34-shaped independent receive obligation (3 HARQ + 1 SR)
  with no UE UCI producer. Its third attempt is running under
  `logs/5mhz_exact_receive_only_20260922_v3.log`. This is not a measured
  PDCCH missed-decode rate or statistical detector qualification.
- No `testAll`, 400 MHz run, cleanup, commit, or push was started.

Follow-up at 20:28 IST: attempt 3 completed all three physical DL
transmissions and reached the receive-layout counterexamples, then failed
the test's `MissingInstalledSRCalendar` expectation. The exact target already
has an installed SR calendar; setting its resource ID to zero did not remove
that calendar. The counterexample now explicitly clears only its copied
calendar before asserting rejection. Attempt 4 reruns the three-grant exact
YAML case followed by the original two-grant default. Its log is
`logs/5mhz_exact_receive_only_20260922_v4.log`; earlier failed receipts remain.

Partial V8 evidence, not final acceptance:

- `logs/5mhz_v8_partial_ssb_arithmetic_20260922_2025.json`: four retained SSB
  occasions, zero arithmetic/provenance failures.
- `logs/5mhz_v8_partial_uplink_sr_20260922_2027.json`: one PUCCH/SR
  observation, zero consistency failures; other listed channels were not
  yet observed and are not counted as passing coverage.
- Slot 24 records HARQ=0, SR=1, CSI=0, no prepared transmitter, DTX=1,
  SuccessFlag=0, TimingEstimateUsed=1. No unavailable CSI or transmitted
  payload has been fabricated to fill this quiet SR observation.

## Current candidate V8 and export closure (22 September, 20:09 IST)

The previous goal turn made concrete progress: it reproduced and repaired
the slot-34 mixed numeric/logical append, with actual shared HARQ reception
passing afterward. This turn closed three further reproduced export gaps
and a related per-layer source inconsistency. None establishes full-run or
detector qualification by itself.

| Repair | Final-source evidence |
| --- | --- |
| SR timing-use flag | `pucchReceiverStageEvidence` recognizes actual bounded received-SR sequence timing. Oracle timing and prior prediction remain excluded. Metadata test and both physical SR episodes pass. |
| Positive-SR transmitted-bit audit | `completeConfiguredPUCCHSR` reads the frozen serialization only after independent RX and actual TX identity verification. Exports actual expected/decoded bits, counts and XOR. No-TX fields remain unavailable, not a fabricated zero-bit transmission. |
| Layer panels | Renderer includes every captured group and sizes the canvas for all rows. Tests cover four and eight panels and their bounds. |
| Layer source identity and sample plane | Full captures take priority, one source per direction prevents alias duplication, and raw/no-payload-fit provenance is required. Malformed/missing samples fail closed. Cache version is v71. |

Verification:

- `logs/sr_export_closure_20260922_v2.log`: timing metadata, 13 merge cases,
  both standalone SR PHY episodes, canonical/component guards, and
  `testSchedulerGrantConsistency` pass. The earlier scheduler license failure
  remains preserved in its original batch; this fresh recheck passed.
- Independent audits of negative/positive episodes pass 11/17 checks with
  zero failures, respectively. Episode folders:
  `logs/tpf4c07a87_4a18_43dd_ad99_651df8e3dbb0` and
  `logs/tpad7471b6_3621_4408_aca9_8a9a178834ca`.
- `logs/sr_constellation_export_regressions_20260922.xml`: **256 passed**.
- Retained V6 replay: `logs/5mhz_v6_layer_source_closure_20260922/receipt.json`
  binds 78,736 source rows and DL1/DL2/UL1/UL2 panels to source/code hashes.
  Original run artifacts and acceptance are unchanged. PNG is explicitly a
  first-450-samples-per-panel preview; CSV retains all selected source rows.
- First SR test failed a new assertion expecting blank canonical text;
  raw fields were correctly blank and canonical fields correctly carried
  the existing explicit N/A token. The test now verifies both representations
  and still rejects fabricated payload bits. Original failure log retained.
- `testE2E_FastVsTruth` passed. The three-seed packet-semantic guard is still
  executing under engine 10620; no full-suite or new 400 MHz run is active.

Fresh 5 MHz/20 dB V8 started **20:08:52 IST**, launcher **5812**, engine
**11940**, with unchanged four-dimensional/rank-two YAML and shared controls.
Log: `logs/5mhz_full_control_acceptance_20260922_v8.log`.
Output: `results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v8`.
Production source is frozen for this candidate. V7 has exited after report
recovery and remains an incomplete, failed physical execution at slot 34.

Candidate SHA256 anchors (not a complete source-tree snapshot):

- `CoupledTruthRuntime.m`: `0950E24B00C94D7AED6B4BC815234965E5A7DF5E10BA38220EC036B7BE53ACE0`
- `pucchReceiverStageEvidence.m`: `67FA9B816F77D8ED9B5DE3939A227E8BF59911D4E43B5E8710770012E1479244`
- `lls_contract_materializer.py`: `95D0E1AF82FAE672D1B1DB8E0150AE3ADCEF2B2678F66ED1A07018D51A13E905`
- target YAML: `03CF3F1C4F26B38BC0ABA822C16BD8C4B8CA2DA0CE0210243566D18C2496F625`

Still required: final-source 58-slot execution (including slots 34/39),
measurement/CSV/PNG acceptance, independent detector/missing-DCI qualification,
and then full-control 400 MHz implementation/execution. The phase-08 MAC SR
trigger/timer consumer and positive-SR/PUSCH overlap remain explicitly
unsupported, not silently enabled or claimed by these export repairs.

## Slot-34 terminal failure repair (22 September, 19:50 IST)

V7 stopped physical execution at slot 34, 19:41:19 IST, with
`MATLAB:nologicalnan`. The retained `meta/failure_debug_report.txt` identifies
`CoupledTruthRuntime.harmonizeColumns` called by `appendCompatTable`,
`appendPUCCHFeedbackTrial`, and `completeSharedPUCCHFeedbackRuntime`.
Earlier standalone SR observations have unavailable numeric content-match
evidence; the later HARQ observation supplies a logical flag. The old merger
coerced the numeric column to logical, which cannot represent NaN. This is
a table-merge crash, not proof of a CRC/layout failure at slot 34.

The production merger now converts numeric evidence to logical only when
every value is exactly 0 or 1. Otherwise it promotes the logical side to
the numeric representation, preserving NaN and nonbinary values in both
append orders. No PHY bits, receiver thresholds or success gates changed.
The failed run remains failed; its report-recovery process and artifacts
are preserved. No new scenario or `testAll` was started for this repair.

- `tests/testRuntimeTableMissingEvidence.m` reproduced the original stack
  before the fix and passes all 13 metadata cases afterward.
- `testPUCCHReceiverOnlyExportEvidence` passes after the fix.
- `testSharedPUCCHFeedbackClock` passed at 19:52 IST, checking actual HARQ completion after
  a declared unavailable SR schema sentinel, removing that metadata-only
  sentinel before exporting physical rows. Actual feedback commitment,
  power-ledger export and the existing receiver/timing assertions passed.
- Independent uplink semantic audit tests: 53 passed, receipt
  `logs/runtime_missing_evidence_semantics_20260922.xml`.
- Adjacent guards: `testLinkExportPipeline`, `testArtifactIntegrity` and
  `testOrganizeRunResults_E2EArtifactPreservation` passed.
  `testSchedulerGrantConsistency` failed before its assertions because
  `nrCarrierConfig` could not obtain a `MATLAB_5G_Toolbox` license. The two
  truth-mode E2E guards remain running as of 19:55 IST. Do not call this
  batch passing; retain `logs/runtime_missing_evidence_export_guards_20260922.log`.
  This is a focused batch, not `testAll`.
- Logs: `logs/runtime_missing_evidence_before_20260922.log` and
  `logs/runtime_missing_evidence_after_20260922.log`.
- Earlier measurement check: six focused measurement tests passed; the
  hardened BLER/LLR rerun executed 20 BLER trials across five reference
  points and eight LLR trials without skips. This is smoke-test evidence,
  not statistical qualification. See `logs/bler_llr_executed_evidence_20260922.log`.

The earlier chronology below is retained; its LIVE/frozen V7 status is
superseded by this failure. Full 58-slot acceptance and the other documented
SR/constellation export gaps remain open.

Latest state (22 September, 19:29 IST): V6 finished at 19:13:36 IST with
launcher `out.Ok=1` for its adaptive diagnostic scope. It completed all 58
physical slots and artifact publication, but retained Phase-7 MIMO remains
false and `PublicationLLSEligible=false`. Do not promote that scoped pass
to final scientific acceptance: its PHY execution predates the CSI/SR
and MIMO repairs. V5 and V6 remain preserved. Fresh V7 started at 19:14:22
IST, launcher 19840 / engine 2456, on the repaired source. Production
source is frozen for this execution; no `testAll` or 400 MHz run is active.
V7 passed slot 24 with standalone SR only (zero CSI), no UE PUCCH TX,
no detection and `Status=NA`, `FailureFlag=0`, `SuccessFlag=0`. Export-only
timing and layer-panel defects below remain open; this is not acceptance.

| Current finding | Evidence / remaining action |
| --- | --- |
| Active SNR binding, UL feedback plane, SRS rank-power and per-layer measurements | Previously integrated; V6 has 20 DL and five UL rows with configured/applied AWGN SNR 20/20 dB. |
| Configured CSI-only disposition flags | Caller integration complete; helper and actual runtime present/removed/absent-producer checks pass. |
| Receiver-only PUCCH frontend | Actual replay proved missing AGC compensation; both callers repaired. Actual CSI-only and HARQ receiver-only replay tests pass. |
| Independent CSI applicability | Combined/PUSCH receivers use owner-verified CSI-RS TX. CSI-only applies the same eligibility gate; an ineligible report leaves the independently installed SR occasion intact. Eight CSI/SR integration tests, five export tests and the final four-test component/status rerun passed. Sets overlap; do not sum them as distinct tests. V7 is the pending final-source integrated check. |
| MIMO reconciliation | Identity-AWGN classification and canonical adaptive grant/capability checks integrated. Expanded regression and production replay of all 25 retained V6 rows pass. Exact-match statistics preserved. |
| Independent PUCCH IQ retention | Opt-in capture integrated for pilot-bearing CSI-only/receiver-only completions and standalone Format-0 SR; preserves exact receiver input and timing prior where used. Serialization/identity/clock tests pass. Statistical qualification remains separate. |
| Detector qualification | Still open; neither the frontend repair nor one integrated run establishes false-ACK/missed-ACK performance. |
| 400 MHz physical shared control | Still pending after 5 MHz closure; the earlier ideal-feedback benchmark is not acceptance. |

`testAll` remains stopped. Earlier LIVE/frozen checkpoints below are historical;
the dated receiver-frontend/MIMO section contains the next integration steps.

Updated objective: complete the 5 MHz TDD run, then the 400 MHz run with
physical PDCCH, PUCCH/PUSCH UCI, CSI reporting, SRS and received feedback.
The expanded goal explicitly includes all measurement corrections and
CSV/PNG extraction, not merely successful slot execution or CRCs.
Earlier ideal-delayed-feedback throughput results do not satisfy this goal.
Full-suite execution remains stopped at the user's request; focused tests
and the target scenario executions are the immediate verification gates.

## Failure-log recheck: 22 September, 14:40 IST

The preceding v2 terminal error is confirmed at slot 31 in
`logs/5mhz_full_control_acceptance_20260922_v2.log`:
`MATLAB:nonExistentField`, `Unrecognized field name "SNR"`.
The active-point argument repair in `bindSharedDataNoiseEvidence` is
already integrated; v5 has passed that boundary. The independent physical
noise test covers all eight configured points, with maximum sample/grid
variance error 0.047171 dB. It does not prove access or decoding at -30 dB.

The historical v3 chart-publication failure and repair are documented in
`5mhz_v3_chart_failure_repair_20260922.md`. A fresh focused Python check of
the six captured-chart, lookup, contract, physical-axis, applicability/sweep
and CSV-semantic test files passes **193 tests in 11.08 seconds**. This
subset differs from the earlier 198-test invocation; do not add the counts
or describe this as a full suite.

V5 engine PID 17068 remains active. The latest observed log is slot 57/58,
18 DL and 5 UL rows, with no terminal verdict yet. Neither another scenario
nor `testAll` was launched during this review. Production source remains
frozen. The independently reproduced CSI reference/data-plane mixing bug
below remains **unfixed in the executing runtime**: its standalone selector
passes focused tests, but integration and runtime re-verification are still
required after v5 terminates. Receiver-only Format-2 detector qualification
is also still open. These findings must not be hidden by a later successful
publication verdict.

### PHY completion and additional reproduced export defects (14:56 IST)

V5 completed all 58 slots and sealed 445,440 TX samples per physical port.
Its waveform bundle and active-runtime control checks passed; MATLAB engine
17068 remains live, annotating/exporting artifacts. No terminal launcher
verdict is available yet. The completed raw tables contain **19/20 DL CRC
passes and 5/5 UL CRC passes**, with all five UL attempts at rank 2. The one
DL failure is slot 58, rank 2/MCS 27, post-equalization SINR 19.636949 dB,
feedback due slot 59 outside the 58-slot observation. Its delivery ledger
correctly counts zero goodput bits. That failed first attempt is not proof
of exhausted HARQ, nor does a nonzero initial BLER alone establish a bug.

PUCCH slot 54 also passed: HARQ/SR/CSI = 4/1/10, 15 decoded bits, CRC pass.
The immutable `logs/5mhz_v5_slot58_uplink_audit_20260922.json` observes
PRACH=1, PUCCH=7, PUSCH=5, SRS=6 and zero checked consistency failures. It
explicitly retains the unqualified slot-24 no-producer detection. This audit
does not cover every remaining issue, including the two defects below.

1. **PUCCH executed-stage provenance:** `runPUCCHWaveformTrial` derives
   `ChannelEstimateAttempted` from the propagation profile and therefore
   publishes AWGN Format-2 DM-RS/MMSE execution as a unit-channel shortcut.
   The added assertion in `testLLSPUCCHWaveformFeedback` reproduces this:
   `logs/pucch_awgn_estimator_provenance_before_fix_20260922.log` (exit 1).
   New `sixgr.link.pucchReceiverStageEvidence` derives evidence from the
   canonical receiver's actual execution mode and retained timing/variance
   fields, without transmitter/configured-noise inputs. Its metadata test
   passes, together with the 66-case data-SINR selector:
   `logs/pucch_receiver_stage_and_sinr_helpers_20260922.log` (exit 0).
   **Neither helper is integrated into executing production callers yet.**
   Integrate stage evidence in the waveform wrapper and both receiver-only
   completions; preserve those fields through the shared-trial mapper.
2. **Delivery-clock double counting:**
   `reconstructLLSKPISummaryFromRaw.localAttemptStartTimes` adds a radio-frame
   offset to an already absolute `Slot`. V5 slot 58 has
   `RuntimeAbsoluteSlotIndex0=57` and actual sample start 437760/7680000 =
   0.057 s, but its derived attempt start is 0.107 s. The same function also
   overwrites higher-priority finite timestamps when any other row is
   missing. New `testKPICanonicalAttemptClock` reproduces the absolute-slot
   error (`logs/kpi_canonical_attempt_clock_before_fix_20260922.log`, exit 1)
   and includes 15/120 kHz and partial-explicit-clock cases. Repair the
   existing helper after source unfreeze: preserve timestamp priority per
   row, consume canonical absolute-slot evidence before legacy frame/local
   slot reconstruction, and never add both representations of the frame.

The CSI isolation regression now additionally checks reference-only rows
and exact provenance retention for both struct and table inputs. Its
expanded version still awaits post-integration execution. Production
runtime/publisher source remains frozen until v5 is terminal. `testAll`
and the 400 MHz run remain unlaunched.

At 14:59 IST, the newly written rank table has 25 `pass` rows and correctly
retains DL rank-one/rank-two execution, UL rank two, measured DM-RS counts
and unavailable port IDs. That does **not** close all per-layer measurement
claims: `resolveNominalVsEffectiveMIMO` lines around 553 still copy aggregate
trial `EVM_rms`, `NMSE_dB`, `LLRMeanAbs`, BER and TB CRC into every layer row.
For example, slot-44 layers 1/2 have distinct post-equalization SINRs
21.2945/21.217 dB, but both show EVM -21.2547018440 dB, NMSE -23.8879352222
dB and LLR magnitude 45.7969472672 from the aggregate trial. These are not
independent per-layer observations. Required follow-up: publish actual
layer-domain EVM where paired received/reference symbols exist, and keep
trial/channel/codeword aggregates explicitly scoped rather than claiming
per-layer NMSE, LLR or CRC. Do not replace missing layer measurements with
repeated aggregate values or introduce gain/phase fitting during reporting.
`deriveModulationTrackingMetrics.localPrepareMatchedLayerSymbols` currently
validates the paired layer matrices then flattens them for aggregate EVM;
retain their layer identity before that reduction when adding real layer
measurements. The executing publisher remains unchanged.

## Current checkpoint: 22 September, v5 launched

The fresh final-source 5 MHz run started at 13:35 IST with tag
`5mhz_rank2_20db_full_control_20260922_v5`. Launcher PID 8408 and engine
PID 17068 were verified against their command lines; these are historical
launch identities, not a substitute for checking current process state.
Log: `logs/5mhz_full_control_acceptance_20260922_v5.log`.
Results: `results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v5`.
No `testAll` or 400 MHz scenario was started. The MATLAB runtime and Python
publisher are frozen while v5 executes. Offline audit/test changes below
are not imported by either runtime. Earlier checkpoint tables and process
states below are chronological evidence, not the current status.

The prerequisite 21 MATLAB checks passed. An additional read-only SRS CSV
audit now checks power provenance/closure, absence of a post-MMSE shift,
one value per selected layer, weakest-layer selection and linear-power
averaging. Seven negative cases failed before these guards were added.
The combined Python audit/CSV/publication regression passed **165 tests**:
`logs/srs_prediction_audit_full_focus_20260922.log`.

Re-auditing historical v3 records identifies six SRS rows failing each of
the power-provenance, power-closure and nonzero-offset checks; their layer
counts/minima/means are internally consistent. This explains why coherent
tables and a terminal `out.Ok=1` did not establish scientific correctness.
The independent native-codebook/MMSE regression proves the underlying
power error; this CSV audit only verifies exported evidence contracts.
Receipt: `logs/5mhz_v3_srs_prediction_layer_reaudit_20260922.json`.

V5 still requires complete PHY execution and final same-run audits. Do not
mark it accepted based on startup, source inspection or focused tests.

### V5 live receiver checkpoint: 22 September, approximately 13:59 IST

Access completed and execution reached slot 35 without a terminal error.
The slot-30 SRS row now reports rank 2, measured reference signal power
`1.00021342570953`, disturbance power `0.00265903068743297`, weakest-layer
PUSCH prediction `22.5581350157488 dB`, and zero post-MMSE calibration
offset. Historical v3 reported `25.7343290893413 dB` after adding
`3.17619407359245 dB`. Its measured receiver noise and NMSE are unchanged;
the correction changes the scheduling prediction, not the received noise.
The immutable checkpoint audit has zero failed checks, including all ten
SRS checks: `logs/5mhz_v5_srs_slot30_audit_20260922.json`.

The actual slot-34 PUCCH row verifies HARQ=3, SR=1, CSI-Part1=0,
CSI-Part2=0, expected/decoded bits=4/4, zero bit errors, and three applied
HARQ decisions for source slots 31/32/33. It records independent receiver
assignment and no payload-bit oracle. CRC is not applicable for this
short payload; it must not be described as a CRC pass. Slot 39 and final
run/artifact acceptance are still pending at this checkpoint.

At approximately 14:00 IST, the first PUSCH row (slot 35) proves runtime
consumption of slot-30 SRS: `SchedulerAdjustedSINR_dB=22.5581350157488`,
feedback source slot 30, CQI 12, MCS 22, 64-QAM, code rate 0.650390625,
two layers, and transport-block CRC pass. The measured post-equalization
SINR is `21.5003032315911 dB`; the underlying equalizer estimate is
`22.7734860224181 dB` and the export explicitly identifies the
decision-residual bound. The scheduling prediction is not relabelled as
the subsequent measured SINR. The checkpoint audit observes PRACH=1,
PUCCH=3, PUSCH=1 and SRS=2 with zero consistency failures:
`logs/5mhz_v5_ul_slot35_audit_20260922.json`. Execution reached slot 36.
This demonstrates the repaired SRS-to-grant path, not final acceptance
or detector statistical qualification.

The slot-24 Format-2 receiver-only occasion remains a detector concern:
no PUCCH producer was prepared, but the receiver declared detection.
`SuccessFlag=0` honestly preserves that distinction. Do not call this
noise-only without excluding other UL waveforms in its actual capture
window. The retained eight-case detector campaign covers Format 0 only;
it cannot qualify this Format-2 population, even if all its episodes pass.
No detector threshold has been tuned against the integrated run.

### V5 slot-39 verification and cross-table audit (22 September, 14:06 IST)

Slot 39 now verifies HARQ=4, SR=1, CSI-Part1=10, expected/decoded=15/15,
CRC pass, zero bit errors and four applied HARQ feedback decisions. The
run reached slot 40 without a terminal error. Immutable observed-byte
audit: `logs/5mhz_v5_slot39_combined_audit_20260922.json`, zero consistency
failures. This supersedes the slot-39 pending status above, but not the
full-run or final CSV/PNG acceptance gates.

The offline `audit_lls_uplink_evidence.py` now reconciles SRS-backed PUSCH
grants to the unique retained source slot/UE/RNTI/cell/sweep-SNR row. It
checks source-slot age and that the scheduling SINR is the trusted
weakest-layer prediction minus the explicitly exported backoff. It never
chooses among ambiguous rows by signal similarity or substitutes pilot
SINR or a subsequent data measurement. This is evidence reconciliation,
not a CQI calibration or full sample-clock causality proof. Live CSV files
are not an atomic cross-file snapshot; missing-source findings require
re-observation before diagnosing a live runtime failure.

The actual slot-35 grant passes all three new binding checks. Receipt:
`logs/5mhz_v5_srs_grant_binding_audit_20260922.json`. Five new Python tests
cover correct backoff, changed/ambiguous identity, untrusted prediction,
source age, unrelated feedback sources and run-level CSV invocation. The
combined Python regression passes **170 tests**:
`logs/srs_grant_binding_run_audit_focus_20260922.log`. These offline changes
are not imported by the executing simulator or publisher.

Further detector diagnosis is specifically scoped to receiver evidence:
the slot-24 PUCCH observation is `[176463,184297)` at 7.68 MHz; the actual
RRCSetupComplete receive window is `[184143,191977)` on the same UL link.
Those *capture windows* overlap by 154 samples. This does not establish
that the FFT-selected PUCCH REs contain the access waveform. The
receiver-only trial constructor in
`CoupledTruthRuntime.completeConfiguredPUCCHCSI` omits resource coordinates,
`rx.ReceiveTiming`, and the equalized decoder disturbance despite those
values existing in the canonical receiver. Do not infer them from a
transmitted PUCCH (none exists). After v5 terminates, inspect its retained
`SharedGNBUCIReceptions` and exact waveform support, then propagate the
actual receiver/assignment fields through both receiver-only constructors.
Keep this export completeness repair separate from physical detector
qualification; no threshold tuning or successful transmission claim is
authorized by the presence of a decoded 11-bit word without a producer.

### New measurement-policy finding from the second UL grant (14:08 IST)

The actual slot-40 PUSCH passed CRC at rank 2, 64-QAM/MCS 20. It used
feedback from slot 35, with OLLA update count 1 and margin
`0.0333333333333333 dB`. Its scheduling SINR is `19.7776672573192 dB`,
whereas the source slot-35 data measurement was `21.5003032315911 dB`
and its reference-channel measurement was `19.7776672573192 dB`.
The current slot-40 data measurement is `21.5203288412308 dB`.
This is not a regression of the SRS repair: its source has changed to
`runtime_reported_cqi`, and the new SRS-binding audit appropriately does
not pretend it is still SRS-driven. Checkpoint receipt:
`logs/5mhz_v5_slot40_binding_audit_20260922.json` (zero checked consistency
failures, not acceptance of every measurement policy).

Read-only root-cause trace:
`CoupledTruthRuntime.schedulerMeasuredSINRFromRow` takes the minimum of
all eligible `PostEqSINR_dB`, `MeasuredTrialSINR_dB`, `MeasuredSINR_dB` and
`ReceiverHestSINR_dB` values, regardless of their different reference
planes. When both types exist it reports
`measured_scheduler_csi_conservative_min_channel_estimate_posteq` with role
`measured_post_equalization_scheduling_input`. Thus a reference-signal
measurement is relabelled as a post-equalization scheduling input. A
conservative link-adaptation heuristic is not by itself a receiver physics
failure, but it must not claim to be the actual post-equalization quantity.

After the executing source is unfrozen, add a focused unequal-plane case
and repair the scheduler's measurement authority: use receiver-derived
data post-equalization evidence for that claimed role; keep the reference
measurement distinct. If a conservative policy is retained, it needs an
explicit configuration/provenance and calibration rather than an implicit
minimum. Preserve unavailable/failed-receiver behavior and received
feedback/OLLA timing. Verify the integrated grant source, CQI/MCS and
measurement labels, not just CRC. Do not tune MCS upward to force a desired
throughput or claim this policy is a 3GPP-required SINR mapping.

### Unequal-plane regression reproduced; DL pause isolated (14:16 IST)

New focused test `tests/testRuntimeCSIReferencePlaneIsolation.m` invokes
the public runtime CSI resolver with the exact 5 MHz TDD configuration,
both DL and UL, a fixed 21.5 dB data measurement and independently varied
reference-pilot measurements. It fails **10/12** value/provenance cases:
six cases select a lower reference value and four retain the mixed-plane
source label even when the numerical minimum equals the data value. The
two unavailable-reference cases pass. Real data degradation still reduces
CQI in both directions. This is a metadata-authority regression, not an
RF qualification campaign. Before-fix log:
`logs/csi_reference_plane_before_fix_20260922.log` (MATLAB exit 1).
The test is deliberately failing until the production fix; do not count
it among the earlier 21 passing focused MATLAB functions. The diagnostic
MATLAB process ended; the same v5 engine remains active.

`testRuntimeMeasuredCSIFeedbackDerivation` currently codifies the old
conservative minimum. Its unequal-plane assertions need to change with
the proven measurement-authority correction, preserving actual data
degradation, per-layer limits, missing-evidence and scoring-isolation
guards. Do not remove the guard or merely relax its numeric tolerance.

DL slots 41/42 have only `[0,1,23,24]` available after the configured
SSB PRB/symbol reservation; slot 43 has only PRB 24 after SIB1/Type0-PDCCH
reservation. `SchedulerPF.MinPRBPerUE` defaults to four and
`contiguousPRBChunk` correctly refuses to bridge those frequency gaps.
This explains the no-grant result despite a queued UE with CQI 15/RI 2;
it is not evidence of a stuck rank/CSI receiver. Slot 44 and slot 46
subsequently scheduled DL grants again. The generic
`NOT_SELECTED_LOWER_PF_OR_RESOURCE_LIMIT` label is an observability gap:
report the actual insufficient-contiguous-resource reason without
overriding the physical reservation or quietly lowering allocation limits.
Evidence: v5 `packet_flow/csv/scheduler_resource_exclusions.csv` and
`packet_flow/csv/live_scheduler_decision_log.csv`.

The full scenario reached slot 46. PUSCH slots 35/40/45 all passed CRC
at rank 2; OLLA update counts were 0/1/2 respectively. Full terminal and
artifact acceptance, receiver-only detector diagnosis, the measurement
authority repair and the subsequent 400 MHz work remain open.

### Measurement selector implemented, awaiting runtime integration (14:25 IST)

Added `+sixgr/+link/selectReceiverDataSINR.m` and
`tests/testSelectReceiverDataSINR.m`. The selector preserves the actual
source/role/status of an eligible data post-equalization measurement. It
prioritizes the canonical field over legacy aliases, never caps it with a
reference-pilot value, never uses a configured/oracle/proxy/predicted value,
and leaves missing evidence unavailable. It does not invent CQI calibration
or average layer measurements. It accepts scalar struct and one-row table
evidence and rejects malformed numeric/provenance values.

The expanded focused test passed **66 metadata cases**. The same MATLAB
batch also completed `testStrictProxyGuards` and
`testStrictMode_NoFallbackAnywhere` with exit 0. Log:
`logs/receiver_data_sinr_selector_final_focus_20260922.log`.
The earlier 59-case version is separately retained in
`logs/receiver_data_sinr_selector_focus_20260922.log`.
These are focused checks, not `testAll` or waveform qualification.

**Not integrated yet:** no executing runtime/publisher file was changed.
The original `testRuntimeCSIReferencePlaneIsolation` still fails until the
runtime delegates to this selector. Once v5 terminates:

1. Replace `schedulerMeasuredSINRFromRow`'s cross-plane minimum with the
   tested selector and remove the now-unneeded
   `schedulerCQIResolverSINRProvenance` renaming function.
2. Apply the same authority in `appendTelemetry`. Its existing
   `large_scale_interference_budget_fallback_not_receiver_measured` branch
   must not fill the receiver-derived wideband value when receiver evidence
   is absent. Keep the separate `LargeScaleSINR_dB` diagnostic instead.
3. Remove the old `schedulerSINRProvenanceIsEligible` helper only after
   replacing its remaining telemetry callers; do not leave a second path
   that reclassifies reference measurements as data-plane evidence.
4. Update the old minimum-policy regression to assert plane isolation,
   preserving data degradation, per-layer, missing-evidence, scoring and
   ILLA/OLLA guards. Rerun focused integration and actual scenario checks.

Read-only review confirms `resolveWidebandCQI` already rejects
`receiver_hest`/`reference_signal_measurement` inputs: the old runtime
renaming bypasses that protection. Preserving the original source fixes
the authority boundary rather than tuning a rate or changing RF power.

V5 reached slot 50. Slot 49 combined PUCCH has 15 expected/decoded bits,
CRC pass, zero bit errors and four applied HARQ decisions. DL slots
44/46/47/48 executed rank 2 and passed CRC. Full terminal/export acceptance
and the new measurement-policy integration remain outstanding.

### Live row-level measurement/export checkpoint (14:31 IST)

The existing primary-link semantic checker passed its 28 covered checks
across 14 observed DL and four UL rows: identity, unique trial keys,
scheduled/transmitted operating point, TB/CRC/BER/goodput arithmetic,
noise/SINR/EVM lineage and truth/proxy/lifecycle. This deliberately excludes
the expected-final-trial-count check because the run is live; it is not
whole-run or artifact acceptance. Receipt:
`logs/5mhz_v5_live_primary_semantic_audit_20260922.json`. The source hashes
in this one-off receipt were read after parsing; it is not an atomic
cross-file checkpoint. Repeat on finalized artifacts for acceptance.

Raw rank-two DL and UL rows report `MeasuredDMRSPortCount=2`, not the
bootstrap rank or the four available antenna dimensions. Their
`ConfiguredSNR_dB` and `AppliedAWGNSNR_dB` are both 20. The UL executed
sample variance is `4.8828125e-6`, its equivalent grid variance is `0.0025`,
and the OFDM sample-to-grid variance gain is 512. Receiver-estimated
disturbance remains a separate measured quantity. The final MIMO rank/layer
exports are not yet materialized, and reconciliation summaries still
include the initial zero-observation snapshot; do not evaluate those as
terminal outputs yet.

The same v5 process reached slot 53. DL slots 51/52 used rank two/MCS 25
and passed CRC. A later independent uplink audit covers PRACH=1, PUCCH=6,
PUSCH=4 and SRS=5 with zero checked consistency failures, retaining the
slot-24 PUCCH-absent detection explicitly:
`logs/5mhz_v5_slot52_uplink_audit_20260922.json`. None of these checks covers
or closes the already reproduced scheduler reference/data-plane defect.

### Revalidated 400 MHz blockers; no live-runtime edits

- The existing adaptive 400 MHz YAML still inherits `research_tdd_link`
  with ideal feedback and disabled PDCCH/PUCCH/CSI/SRS/access. Preserve it
  as the old benchmark; author a separate shared-control configuration.
- `generateSSB_MIB_SIB1_Waveform.localSSBGridInCarrierNumerology` explicitly
  rejects different SSB and initial-BWP numerologies with
  `MixedNumerologyCollisionValidationRequired`. Physical initial access
  needs a valid common/active-BWP design and exact collision/timeline
  support, not a pre-attached bypass.
- `resolveMCSProfile` implements standard MCS tables 1/2/3 only;
  `resolveConfiguredCQITable` and `buildInternalConfig` accept CQI tables
  1/2 only. A 1024-QAM DL configuration cannot gain standards-backed
  table-4 adaptation merely by setting a maximum modulation token.
- For the installed Release-18 profile, TS 38.214 clause 5.1.3.1 selects
  DL table 4 for the specified 1024-QAM configurations; clause 6.1.4.1
  does not select it for PUSCH. Keep requested UL 1024-QAM explicitly
  experimental rather than labelling the DL table a normative UL table.
  Source rechecked on 22 September:
  [TS 38.214 V18.8.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).
- Receiver-calibrated SINR-to-CQI thresholds are a separate task from
  implementing the normative modulation/code-rate rows. Current thresholds
  in `cqiRequiredSINRTable` are explicitly lab defaults, not 3GPP constants.

## Acceptance sequence

1. Repair and verify generic-sweep profiler ownership without disabling
   child PHY or diagnostics. Preserve each child's profiling configuration;
   save and release the parent's preflight profile before child execution.
   The parent's preflight timings must not claim to cover child execution.
2. Run `lls_tdd_5mhz_rank2_shared_awgn_20db.yaml` from the final source with a
   fresh run tag. Require 58 completed slots, physical DL/UL CRC evidence,
   causal ILLA/OLLA/rank updates, and accepted CSV/PNG/browser artifacts.
3. Check slot 34 (3 HARQ + 1 SR, no eligible CSI) and slot 39 (4 HARQ + 1 SR
   + 10 CSI) against actual scheduling, received layout and completion rows.
   Verify missing DCI, DAI wrap, cross-transport ownership, stale/duplicate
   feedback with focused physical tests. Do not infer these passes merely
   from a nominal high-SNR run.
4. Run the isolated 5 MHz sweep at -30, -20, -10, 0, 10, 20, 30, 40 dB.
   Require configured/applied AWGN agreement and independent point state.
   Acquisition or decoding failure at low SNR is a physical outcome, not a
   reason to fabricate measurements or force a successful attach. The
   runner and exports must retain and classify those outcomes correctly.
5. Complete detector qualification and relevant BLER/LLR measurements from
   frozen independent campaigns. Track functional completion separately
   from statistical qualification; a few successful PUCCH occasions do not
   qualify false-ACK/missed-ACK rates.
6. Build the 400 MHz shared-control YAML from the verified common runtime,
   using the 120 kHz / 4096 FFT / 491.52 MHz / 264-PRB carrier dimensions and
   four-port rank capability. Reconcile numerology-specific access, BWP,
   CORESET, K1/K2, CSI/SR/SRS calendars, DM-RS and shared UCI allocations.
   Keep the existing ideal-feedback benchmark as a separately labeled
   historical comparison. Never use it to claim physical-control acceptance.
7. Run and qualify the full 400 MHz / 30 dB shared-control scenario. Report
   actual modulation, rank, MCS/code rate, measured SINR/EVM, initial and
   residual BLER, HARQ retransmissions, and unique-payload DL/UL throughput
   including actual TDD/control/reference-signal overhead.

For both bandwidths, acceptance must reconcile actual power/noise/gain/loss
accounting, reference-plane and post-equalization SINR, RSRP/RSSI/RSRQ, EVM,
channel estimates, BER/initial and residual BLER, unique-payload throughput,
rank/layers/DM-RS, and causal CSI/SRS feedback. Every required CSV and PNG
must trace to the same received trial/plane and final verdict. A configured
SNR is not a substitute for measured SINR; unavailable measurements remain
explicitly unavailable, and a low-SNR decoding failure is not relabeled as
a successful transmission.

## Current evidence and open work

| Area | Authoritative evidence | State / next check |
| --- | --- | --- |
| Latest sweep startup | `logs/5mhz_rank2_awgn_snr_sweep_20260920.log`: `ProfilerSessionAlreadyActive` before the first child executed a slot | Profiler handoff implemented; both children, parent and PRACH execution completed successfully in `logs/sweep_profiler_handoff_20260922.log`. The added final test assertion used a removed `RunFolder` column; corrected to the relative child-artifact index, full matrix test rerun pending. Do not claim the whole test passed |
| Superseded profiler attempt | `logs/sweep_profiler_integration_20260922.log` | Deliberately stopped; it disabled child diagnostics and is not acceptance evidence |
| Sweep noise | `test5MHzRank2SharedAWGNSweepIsolation`, `testSharedDataPhysicalQueue('TDD')` passed in the previous focused verification | Corrected isolated child execution and configured/applied guard remain in the worktree; final-source integrated rerun required |
| Actual sample/grid noise sweep | Strengthened isolation test passed in the v2 log: all eight points independently measured; largest absolute sample/grid variance error 0.03277 dB | Noise generation and variance transform verified at -30 through 40 dB; full access/data sweep acceptance still pending |
| Sweep parent evidence scope | Static inspection: `exportCausalPHYChainAudit` and waveform truth reduction still expect local PHY artifacts; the proposed generic parent inherits the full child audit configuration | Must verify/delegate parent acceptance to identity-bound child evidence before claiming full waveform-sweep acceptance. The AI matrix profiler regression alone does not cover this contract. No copied or fabricated parent PHY rows are allowed |
| PDCCH AL8 exhaustion | Shared path previously threw after the first candidate occupied the physical resources | Explicit blocked-grant/cancellation path implemented; focused allocation/capacity tests passed; integrated low-SNR contention remains to verify |
| Last retained 20 dB run | `results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_srs_illa_fix_20260919` | Historical failure at terminal browser closure: per-layer/DM-RS export inconsistency; source repairs must be verified on a fresh run |
| Retained combined PUCCH | The retained run's `air_interface/csv/pucch_trials.csv`: slot 34 receiver HARQ/SR/CSI=3/1/0, expected/decoded=4/4, three HARQ applications; slot 39=4/1/10, 15/15, CRC pass, four HARQ applications; both `OraclePayloadBitsUsed=0` | Historical physical layout repair is demonstrated. Slot 34 has no UCI CRC by design (`CRCApplicable=0`), so do not claim a CRC pass for that four-bit payload. Fresh final-source integration still required |
| UL DM-RS measurement domain | Retained rank-one PUSCH rows report `MeasuredDMRSPortCount=4`. New physical regression reproduced the erroneous 4/4 logical/antenna count after successful rank-one decoding: `logs/pusch_dmrs_domain_before_fix_20260922.log` | Fixed in `PUSCH_Rx`. Actual connected PDCCH/PUSCH rank 1/2/4 decoding, exact logical/antenna counts, primary-evidence propagation and invalid-noise cases passed in `logs/5mhz_full_control_acceptance_20260922_v1.log`; integrated run pending |
| Rate-recovery limit evidence | The v1 focused batch then failed `testMeasuredPHYEvidenceCellAggregation`: `MeasuredRateRecoverNrefBits` was unavailable instead of 99. The helper discarded the multi-codeword cell input before its existing cell-aware reducer | Fixed in `appendMeasuredPHYEvidence`; focused test and new inconsistent/missing-codeword negative cases passed in the v2 log. Complete agreeing limits survive; incomplete/different limits remain unavailable. Integrated export still pending |
| CSI/PUCCH, SRS, MCS, rank and measurement repairs | Existing focused tests and source changes | Revalidate on the same final integrated execution; do not carry forward acceptance from old snapshots |
| Current SRS receiver regression | V2 log: all 24 port/comb/hopping cases at 25/264 PRBs passed; max absolute noise error 0.99807 dB, worst channel NMSE -19.16297 dB. Evidence: `results/lls/srs_receiver_noise_despreading/20260922_082644_738/receiver_noise.csv` | Focused receiver fix verified at both bandwidth grids; full scenario measurement/feedback consumption pending |
| Export/feedback semantic regression | `python -m pytest -q tests/test_lls_csv_semantics.py tests/test_lls_retained_ack_semantics.py tests/test_pucch_harq_flag_semantics.py`: 124 passed on 22 September | Parser/audit behavior verified; not proof of fresh physical scenario acceptance |
| Constellation/antenna browser regression | `test_live_constellation_publication.py`, `test_lls_browser_antenna_channel_truth.py`, `test_lls_full_constellation_source.py`: 15 passed on 22 September | Exact-plane and honest AWGN browser contracts verified in focused tests; same-run MATLAB evidence still required |
| Frozen detector campaign | `logs/tdd_detector_awgn_20db_held_out_v2_67b1fdb6_launcher.log`: eight physical cases from one episode, no detector errors, `DetectorQualified=0` | 599 additional episodes per case and required review remain; do not treat the pilot as qualification |
| 400 MHz control | Existing `lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml` still uses the ideal-feedback research runner | Shared-control integration remains required after 5 MHz completion; see `400mhz_shared_feedback_integration_20260918.md` |

## Standards and measurement boundaries

Use TS 38.211/38.212/38.213/38.214 procedures for the supported NR PHY,
coding, timing and feedback profile, and explicitly identify experimental
extensions. Do not claim universal 3GPP conformance from passing software
tests. TS 38.104 V19.2.0 places 7 GHz in FR1 and lists the 400 MHz / 120 kHz /
264-PRB single-carrier grid in the FR2 tables. Therefore the requested 7 GHz
single-carrier combination remains a research extension; converting it to
carrier aggregation or changing carrier frequency would be a separate user
choice, not a silent change to this task.

Source: https://www.etsi.org/deliver/etsi_ts/138100_138199/138104/19.02.00_60/ts_138104v190200p.pdf
(clauses 5.1, 5.3.2 and 5.3.5).

Keep receiver measurements independent of configured SNR labels and
transmitted payload hypotheses. Preserve exact signal/reference planes,
executed noise calibration, gain/loss closure, raw sample provenance, and
measured DM-RS identity. Missing data remains unavailable; it is never a
synthetic primary row. Logs go under `logs`, results under `results`, and
every rerun uses a fresh tag to preserve prior evidence.

## Current serial verification queue

- Completed nested profiler regression log: `logs/sweep_profiler_handoff_20260922.log`.
  Executions passed; the added final CSV lookup assertion failed and was
  corrected. The complete test rerun remains pending; the standalone 5 MHz
  target does not execute a nested sweep parent.
- The initial standalone-run queue was canceled before it started any MATLAB
  process after finding the UL DM-RS domain defect above. Resume it only
  after that defect has a focused failing-then-passing regression.
- The pre-fix DM-RS failure is retained; after its engine exited, the
  corrected-source focused verification started (one MATLAB engine).
- Nineteen focused checks cover actual generated noise at eight SNR points,
  full-control/rank/MCS configuration, measured DM-RS mapping, MIMO evidence,
  constellation paths, AWGN antenna semantics, 24 SRS receiver cases, and
  combined/CSI-nonoccasion/independent TDD PUCCH completion, invalid-noise
  guards, reference-power arithmetic, config and DL/UL reference points.
- All nineteen focused checks passed (`FIVE_MHZ_READINESS_PASS count=19`).
  The unchanged 5 MHz / 20 dB target YAML started on 22 September at
  03:03:46 UTC (08:33:46 IST); slot one prepared at 03:04:57 UTC.
  It subsequently failed at slot 31 (03:22:11 UTC), before the first data
  reception completed: the new noise guard read nonexistent `Context.SNR`.
  The data context owns `Job.SNR_dB`; the similarly named PDCCH context has
  a different schema. This was an integration mistake in the new guard,
  not a physical decoding failure. The one-line correction now binds the
  existing frozen PHY-job SNR. A structural call-site guard and actual
  shared-queue context regression were added to `testSharedDataPhysicalQueue`.
  Log: `logs/5mhz_full_control_acceptance_20260922_v2.log`.
  Results: `results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v2`.
  An existence guard refuses to overwrite that result folder.
- V2 is **failed, recovery incomplete**, not accepted. Engine 17552 was
  stopped only after its terminal PHY failure and partial causal audit
  were retained; no results or logs were deleted. The failed runtime diff
  is retained in `logs/5mhz_full_control_v2_failed_runtime_source.patch`.
  Access completed through actual RRCSetupComplete at slot 25; actual SRS
  at slot 30 passed with estimated grid noise 0.00265903068743297 and channel
  NMSE -27.1106 dB. These observations do not prove data/feedback acceptance.
- V3 serial verification now runs the strengthened TDD shared data queue,
  independent TDD PUSCH completion, and eight-point actual noise-isolation
  checks. Only on success does it launch the unchanged 58-slot target with
  fresh tag `5mhz_rank2_20db_full_control_20260922_v3`.
  Log: `logs/5mhz_full_control_acceptance_20260922_v3.log`.
  Do not claim the repaired coordinator is runtime-verified until it passes
  the first PDSCH completion and final integrated gates on this rerun.
  All three follow-up checks have now passed. The independent PUSCH fixture
  recorded one actual UL transmission/common receiver commit and 3,522
  exact-plane constellation samples. It had empty UCI, so it does not
  qualify nonempty/missing-DCI HARQ combinations or the whole coordinator.
  The v3 integrated run has now crossed the repaired callback: at
  03:49:09 UTC it published the actual slot-31 PDSCH row and advanced to
  slot 32. That row records CRC pass, rank 1, QPSK/MCS 4 and measured DM-RS
  port count 1. Configured/applied AWGN SNR are 20/20 dB, occupied-RE energy
  is 0.25, replay grid variance is 0.0025, replay sample variance is
  4.8828125e-6, and the sample-to-grid variance gain is 512. This verifies
  the original callback crash repair and executed noise closure, not the
  remaining 58-slot/feedback/artifact acceptance gates.
- Consolidated Python export regression: **139 passed**;
  `logs/5mhz_export_semantics_20260922.log`.
- Additional read-only measurement-audit regressions: **166 passed** on
  22 September (26.12 seconds), covering radio-measurement plots, large-scale
  power semantics, PUCCH noise evidence, beam summaries, continuous IQ and
  observed uplink evidence. Thirteen warnings were third-party Matplotlib /
  Pyparsing deprecations, not failed checks. These are audit-tool tests, not
  integrated scenario or statistical detector qualification.
- Final artifact-audit tool regressions: **34 passed** (9.19 seconds),
  covering visual artifacts, static chart integrity, browser truth integrity,
  exhaustive run audit and deep audit paths. Retained log:
  `logs/5mhz_final_artifact_audit_tests_20260922.log`.
- An early observed-uplink checkpoint contained no published PRACH, PUCCH,
  PUSCH or SRS rows yet. Its zero failed checks is therefore **not** evidence
  of uplink or feedback acceptance. Receipt:
  `logs/5mhz_full_control_20260922_v2_uplink_checkpoint_slot20.json`.
- A queued command or a running test is not a pass. No 400 MHz execution is
  queued ahead of 5 MHz acceptance.
- The v3 observed-uplink audit at the slot-31 checkpoint retained two flags:
  `logs/5mhz_full_control_20260922_v3_uplink_checkpoint_slot31.json`.
  Slot 24 is receiver-only (no prepared PUCCH transmitter) and exports
  `PUCCHDecodeOk=1` while normalized `ReceiverUsable=0`; it has no transmitted
  expected vector to compare. Slot 29 exports an explicit not-applicable
  token in the decoded-bit column, which the binary-vector auditor rejects.
  These require separate receiver-only/export/audit semantic reconciliation;
  do not infer a transmitter payload mismatch, fabricate expected bits, or
  discard a possible false detection. Source inspection shows
  `repairControlReferenceEvidenceColumnsImpl` overwrites the PUCCH receiver
  flag using transmitter content-match evidence, while the receiver-only
  CSI branch records its independent decoder result. Reproduce and distinguish
  that export contract from the physical receiver before modifying either.
  No production change has been made for these audit flags during the v3 run.
- Read-only uplink auditor repair: explicit unavailable tokens are not binary
  payloads, union-schema NaN cells do not claim numeric counts, and genuinely
  receiver-only completeness uses all independent HARQ/SR/CSI1/CSI2 widths
  rather than requiring transmitted reference bits. Unknown/malformed tokens,
  wrong finite counts, missing independent widths and contradictory receiver
  flags still fail. Detections without a prepared transmitter are retained in
  `ReceiverOnlyNoProducerDetections`; they are not transmission successes or
  detector qualification. New failing-then-passing metadata tests and adjacent
  flag/ACK/noise audit regressions: **96 passed**, 13 third-party deprecation
  warnings, `logs/receiver_only_uplink_audit_regression_20260922.log`.
  This tool is not called by the active MATLAB run and does not mutate its CSVs.
- Fresh v3 slot 34: independent HARQ/SR/CSI1 widths **3/1/0**, expected/decoded
  counts **4/4**, exact bits **1110/1110**, receiver usable and decode success,
  `OraclePayloadBitsUsed=0`, no requested CSI report. CRC is correctly not
  applicable, not a claimed CRC pass.
- Fresh v3 slot 39 subsequently completed: independent HARQ/SR/CSI1 widths
  **4/1/10**, CSI2=0, expected/decoded **15/15**, exact bits
  **111101111101111/111101111101111**, receiver usable, CRC pass,
  `OraclePayloadBitsUsed=0`, one requested CSI report. Both the slot-34
  no-CSI occasion and the genuine combined slot-39 occasion are now verified
  in the same final-source execution; subsequent rank changes and final
  acceptance/artifact gates still remain.
  HARQ feedback application counts are 3 and 4 respectively, with zero stale
  feedback counts. The independently received slot-39 CSI report is processed
  and delivered in slot 39 with ten decoded CSI bits, RI=2 and CQI=15.
- Fresh v3 slot 35 PUSCH: **CRC pass**, rank 2, 64-QAM, MCS 24 using
  `qam64_table1` / CQI table 1, CQI 13, target code rate **0.75390625**.
  Applied link-adaptation feedback source slot **30**; first-grant OLLA update
  count 0, so later ACK-driven updates remain to verify. Configured/applied
  AWGN SNR **20/20 dB**, measured post-equalization SINR **21.3846076866534 dB**.
  Logical DM-RS ports **2**, antenna ports **4**: the production DM-RS domain
  correction and UL rank/ILLA operation are now observed in the exact run.
  The next PUSCH at slot 40 also passed CRC at rank 2: MCS **20**, applied
  OLLA update count **1**, margin **0.0333333333333333 dB**, and feedback source
  slot **35**. The changed operating point is an actual frozen physical grant,
  not only a computed adaptation recommendation.
- Fresh v3 slot 44 PDSCH proves the DL rank change: **CRC pass, rank 2,
  16-QAM, MCS 16**, CQI 15, applied feedback reference source slot 34 (the
  independent CSI report was delivered in slot 39), OLLA update count 7.
  Measured logical DM-RS ports **2**, antenna ports **4**, per-layer
  post-equalization SINR **21.2945 | 21.217 dB**, configured/applied AWGN SNR
  **20/20 dB**. Previously issued bootstrap rank-one grants remain unchanged.
  Slot-44 PUCCH independently expected HARQ/SR/CSI1 **1/1/10**, decoded
  **12/12** bits and applied one HARQ result with no payload oracle.
- Additional provenance gap: the shared replay sets `AppliedAWGNSNRSource`,
  but `runDLPDSCHThroughput` and `runULPUSCHThroughput` copy only its numeric
  value into trial arrays; the union schema then has an empty source string.
  Existing sample/grid variances and calibration-source fields verify physical
  noise closure. Preserve that executed source through both trial exporters
  after the frozen v3 run; do not reconstruct it from the configured SNR label.
- Prepared focused metadata regression `testPUCCHReceiverOnlyExportEvidence`
  for the raw receiver-flag/decoded-outcome preservation defect. It is **not
  yet executed**: the single MATLAB engine remains occupied by the v3 run.
  Run it against the current producer/exporter first, retain the failure,
  then repair the annotation and rerun. Its fixture is explicitly metadata,
  not physical noise/detection qualification. Do not modify loaded PHY source
  mid-run or claim this new regression already passes.
- Interim primary-row semantics: nine DL and three UL rows passed the
  existing identity, operating-point, transport CRC/BER/goodput, noise/SINR/
  EVM lineage, MIMO and truth/lifecycle checks. This explicitly excludes a
  final trial-count claim. SHA256-bound receipt:
  `logs/5mhz_v3_observed_link_semantics_slot46_20260922.jsonl`.
- Independent arithmetic over actual saved constellation samples: ten DL
  observations (slots 31-39 excluding UL slot 35, plus 44 and 46) and three
  UL observations (35/40/45), **52,516 samples** total, all finite; per-observation
  full-allocation counts and sample indices close, and EVM recomputed as
  sqrt(sum(abs(equalized-reference)^2)/sum(abs(reference)^2)) matches the
  recorded EVM. It checks the exact saved equalized plane, not final PNG or
  browser acceptance. SHA256-bound receipt:
  `logs/5mhz_v3_constellation_arithmetic_slot46_20260922.jsonl`.
- CSI measurement inspection resolved an apparent gap: blank `CSI_RSSI_dB`
  and `CSI_RSRQ_dB` in the PDSCH strict-report view do **not** mean the actual
  CSI-RS measurement is missing. The canonical `csi_rs_trials.csv` already
  retains normalized RSRP/RSSI, RSRQ, per-branch vectors, chosen branches,
  resource identity, RB bandwidth and symbols. Do not add a duplicate
  measurement path or put extra fields into the PUCCH CSI payload.
  The three observed CSI-RS occasions at slots 32/37/47 passed independent
  per-branch and selected-branch RSRQ arithmetic; maximum discrepancy was
  7.961e-11 dB. Receipt:
  `logs/5mhz_v3_csirs_measurement_closure_slot49_20260922.jsonl`.
  The physical-power unit remains explicitly normalized occupied-RE energy;
  unavailable absolute dBm values must not be synthesized.
  Reference for the same-RB/same-branch measurement relationship and
  diversity selection: TS 38.215 V18.4.0 clauses 5.1.2/5.1.4,
  https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.04.00_60/ts_138215v180400p.pdf.

### Additional frozen-v3 observations before terminal reporting

- At 04:55:47 UTC the normal waveform bundle, strict runtime control/reference
  checks and initial scenario aggregation reported success with zero required
  failures. Terminal publication/identity checks are still separate gates.
- The refreshed rank/layer export closes for all **25 trials / 42 layers**:
  transmitted-layer count equals the per-layer SINR vector and measured
  DM-RS count; each derived layer row matches its source SINR. All execution
  contracts pass, while the failed slot-58 decode remains separately false.
  `mimo_layer_metrics.csv` contains `DMRSPort`, leaving identity NaN where
  only count is known. Receipt:
  `logs/5mhz_v3_rank_layer_export_closure_20260922.json`.
- Reporting delay investigation: the 881,324,019-byte v7.3 MAT source,
  synchronized staging copy and short-path readback all had SHA256
  `ef5d028752669bfdb5931e27b4200fe9662aac9e77504d90721c647657d237a1`.
  Independent streaming hashes each took roughly four seconds. Existing
  `matSave` inventories the validated source and then inventories both
  byte-identical readbacks again. Repeated HDF5 inventory is a candidate
  optimization, not yet changed or timed independently; preserve size/hash
  verification and the initial closed-source MAT inventory if optimizing.
- The complete 58-slot PHY execution finished at 04:40:06 UTC. Retained
  trials: DL 19 CRC passes / 20 attempts; UL 5 / 5. DL slot 58 failed at
  rank 2, 64-QAM, MCS 27, target rate 0.888671875, measured post-EQ SINR
  19.6369494 dB. Do not convert this failed decode into a pass, or confuse
  this attempt count with finalized residual HARQ BLER at the run boundary.
- All 15 existing primary-row checks passed in each direction for the
  complete 20/5 row populations, including count against the terminal PHY
  log, CRC/BER/goodput arithmetic, rank, noise and measurement lineage.
  Receipt: `logs/5mhz_v3_completed_phy_row_semantics_20260922_v2.jsonl`.
  The first invocation had a Python import-path error; it is not a test pass.
  Full uplink evidence audit still has two receiver-only export consistency
  failures: `logs/5mhz_v3_post_phy_uplink_audit_20260922.json`.
- Visually inspected the live post-equalization constellation PNG under
  checkpoint `ac1d5097800a0eb64a5e291eb17f08df94ee6676b3397af039262d2e6b4ff838`:
  both DL and UL contain actual plotted symbols and reference points;
  full retained counts 51,376 / 27,360 are labeled separately from the
  450-symbol-per-direction preview. Its own partial-checkpoint watermark
  remains correct; this is not final materializer/browser acceptance.
- Five UL rows (35/40/45/50/55) now have CRC passes at rank two, 64-QAM;
  MCS is 24 then 20/20/20/20, OLLA update counts are 0/1/2/3/4, and
  configured/applied reference AWGN SNR is 20/20 dB on every row.
  Measured post-equalization SINR ranges from 21.2963 to 21.5203 dB.
- Actual combined PUCCH slots 49 and 54 retain 4 HARQ + 1 SR + 10 CSI,
  expected/decoded counts 15/15 and successful decoding. This is not
  terminal run acceptance or independent detector qualification.
- Added (not yet executed) metadata and physical-fixture assertions for
  receiver-only HARQ and CSI exports: preserve raw usability, all four
  scheduled field widths, decoded bit count, and no invented transmission
  success. Also require DL/UL trials to retain replay's applied-noise source.
- The metadata regression was subsequently executed against unchanged
  production source and failed exactly on the overwritten receiver flag:
  `logs/pucch_receiver_only_export_before_fix_20260922_v2.log`.
  Its first launcher omitted toolkit path setup and failed to locate the
  test; that is retained separately and is not defect evidence. The corrected
  short MATLAB process exited. Physical regression extensions remain unrun.
  Production edits are still deferred until v3's reporting process terminates.
- Receiver-only slot 24 remains an actual no-producer detection: metric
  0.7973186 against configured threshold 0.2, 11 decoded bits. The existing
  export overwrites receiver usability; repairing that must expose this
  detection, not erase it, retune the threshold against this run, or call it
  successful transmission. Slot 29 has metric 0.1700178 and DTX=true.
- A further union-schema provenance defect is visible: prepared PUCCH
  trials do not publish `PUCCHTransmissionPrepared`, so appending them to
  explicit no-producer rows fills their missing logical value with false.
  Propagate the actual preparation flag from the waveform trial; never infer
  it from decoding success or label a no-producer trial as transmitted.

## Additional verified findings, 22 September 10:56 IST

- The retained v2 terminal exception is `MATLAB:nonExistentField`, missing
  `SNR`, at slot 31. The main-source completion callback now passes the
  scheduled job's `SNR_dB`. V3 completed all 58 PHY slots with that repair;
  this is not yet a terminal CSV/PNG/browser acceptance claim.
- `testType2HARQACKLayout`, `testType2HARQRuntimePlan`, and
  `testScheduledULTotalDAI` passed in
  `logs/tdd_type2_control_identity_focus_20260922.log`. The last test retains
  nine actual UL DCI receptions and 24 guard checks. Its original evidence
  was copied, not moved or deleted, into the adjacent `_total_dai` folder.
- The v3 rank/layer closure audit found 25 trials and 42 per-layer rows,
  with zero dimensional/reconciliation failures. Missing measured DMRS IDs
  remain unavailable rather than invented. Receipt:
  `logs/5mhz_v3_rank_layer_export_closure_20260922.json`.
- The receiver-only export candidate passes its metadata regression in
  `logs/pucch_export_isolated_candidate_20260922_v4.log`. It preserves raw
  receiver usability/decoding and false detections, separates transmission
  success from no-producer observations, and preserves strict validation.
  Repeated-publication testing also exposed a missing-value label being
  mistaken for an executed proxy; the candidate corrects that while still
  quarantining every finite decoder-proxy value.
- MAT publication profiling found 49 saves / 147 inventories in v3, with
  about 748 seconds in inventory validation. The unchanged seven-case
  persistence baseline performed 21 inventories. The isolated candidate
  passes the same exact IQ/table/NaN and long-OneDrive-path round trips with
  seven inventories. Both staging/final readbacks still compare byte count
  and SHA-256 to the source validated between matching hashes. This proves
  eliminated repeated work, not a measured end-to-end speedup.
- Candidate source is staged outside the active MATLAB source tree at
  `C:/Users/anup0/AppData/Local/Temp/sixgr_pucch_export_repair_20260922`.
  A portable copy is preserved in
  `docs/lls/pending_receiver_export_and_mat_publication_20260922.patch`;
  `git apply --check` passes. **Not integrated yet:** active v3 reporting
  still uses its original production source. The new physical producer,
  receiver-only width, and applied-SNR-source propagation assertions must
  run against main source after integration; metadata tests are not their
  substitute.
- V3's issue registry has now been evaluated over 130 runtime source rows
  and reports zero registry issues. The independent uplink audit still
  exposes the receiver-only export contradictions, so an empty registry is
  not sufficient to declare measurement/export acceptance.

### Continued evidence, 22 September 11:13 IST

- Read the actual seven retained `SharedGNBUCIReceptions` records directly
  from `air_interface/mat/link_results.mat`, without loading the entire MAT
  payload or changing it. Exact observation sample bounds/rate uniquely
  matched all seven CSV rows. Slot 24's raw usability is true but the CSV
  overwrites it to false; its 11 decoded bits are unchanged. Actual expected
  counts at slots 34/39 are 4/15. The receipt binds the MAT and CSV hashes:
  `logs/5mhz_v3_retained_uci_receipt_comparison_20260922.json`.
- The isolated candidate's `testSharedPUCCHReceiveOnlyClock` passed actual
  IQ execution: two DL transmissions, no UE UCI producer, two DTX outcomes,
  nine guard rejections, unchanged rejected HARQ state and replay equality.
  `logs/pucch_receiver_only_physical_candidate_20260922.log` records the
  source-isolated scope. The result folder is
  `results/lls/pucch_receiver_only_export_candidate/20260922`.
  Subsequent candidate cleanup keeps preparation flags numeric (0/1/NaN)
  to avoid mixed-table logical conversion of an unknown into true, and
  labels receiver width provenance explicitly; main-source retesting is
  still required after integration.
- The active browser materializer is PID 14664, a child of the original
  v3 launcher. It is doing work, not waiting on another simulator. A
  nonblocking stack sample found 66/239 samples in repeated row lookup and
  136/239 in rasterization (10 sampling errors retained in tool output).
  Source: `logs/5mhz_v3_browser_materializer_sample_20260922.txt`.
- A staged, bounded schema-only lookup cache preserves exact/alias/blank
  precedence, column order, changing values, and changed alias definitions.
  It caches no measurement values. Thirty-six browser/lookup tests pass:
  `logs/browser_row_lookup_candidate_20260922.log`. On 12,500 lookups over
  the first 500 retained RE rows, values match exactly and lookup time falls
  from 1.014 s to 0.025 s. This is not an end-to-end speedup claim. The
  benchmark is in `logs/browser_row_lookup_candidate_benchmark_20260922.json`.
  Patch: `docs/lls/pending_browser_row_lookup_20260922.patch`.
- Neither staged production patch has been integrated while v3 is active.
  No full suite or additional full scenario was launched.
- The staged applied-noise-source export also passed the actual shared
  PUSCH empty-UCI completion fixture, including received SRS/DCI timing,
  one UL transmission/common commit and 3,522 retained constellation
  samples. It is not a nonempty-HARQ or missing-DCI qualification.
  Log: `logs/shared_pusch_source_export_candidate_20260922.log`.
- Tightened `test5MHzRank2SharedAWGNSweepIsolation` to construct each owner
  with `cfg.rf.configurationEpoch`, exactly as the normal coupled runtime
  does, instead of an artificial per-point test epoch. Production already
  includes configured SNR in its receiver noise-seed identity. The stronger
  check passed all eight actual noise points with distinct noise seeds in
  `logs/5mhz_sweep_noise_production_epoch_20260922.log` (exit 0). Maximum
  absolute sample/grid variance error was 0.0471708 dB. This is physical
  noise generation evidence, not full access/control/sweep acceptance.

## 400 MHz shared-run prerequisites (read-only review, not implemented)

### Table-4 integration findings verified against the primary specification

Primary reference: ETSI TS 138 214 V18.8.0 / 3GPP TS 38.214 Release 18,
Tables 5.1.3.1-4 and 5.2.2.1-5:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf

This review did not change production configuration or launch a 400 MHz run.
It confirmed the following coordinated changes are needed; merely adding a
1024-QAM modulation string is insufficient:

1. `resolveMCSProfile.m`: add the normative DL table-4 rows 0..26, preserving
   reserved rows 27..31 as unavailable new-TB profiles. Its 1024-QAM rows
   23..26 have R*1024 = 805.5, 853, 900.5, 948. A configured maximum rate 0.9
   must select a valid eligible row, not clip row 26's rate to 0.9.
2. `resolveCQIProfile.m`: add CQI table 4 and Qm=10 modulation conversion.
   CQI 14/15 use R*1024 = 853/948. Keep the normative, rounded spectral
   efficiencies consistent between MCS and CQI to avoid skipping an exactly
   matching codepoint through a rounding mismatch.
3. `resolveConfiguredCQITable.m`, `resolveMCSFromCQI.m` and
   `resolveMCSIndexFromProfile.m`: recognize the explicit DL table-4 token;
   do not infer table 1/2 for an installed 1024-QAM table.
4. YAML schema/catalogs and `buildInternalConfig.m`: the present builder
   copies one CQI token into both DL and UL, while both builder and runtime
   resolver whitelist only table1/table2. Introduce validated direction-
   specific CQI choices so changing DL does not silently change the UL
   scheduling authority. Preserve existing table1 scenarios unchanged.
5. `cqiRequiredSINRTable.m` / `resolveWidebandCQI.m`: bind explicitly
   configured/calibrated thresholds to the selected direction and CQI table.
   Table-4 normative entries are not SINR calibration. Do not reuse table-2
   thresholds under a new label or manufacture 1024-QAM thresholds.
6. Verify integer/reserved codepoints, CQI-to-MCS selection, rate-cap behavior,
   received DCI/new-data and HARQ retransmission identity, and independent
   DL/UL choices before enabling the new table in the full shared scenario.

The existing UL experimental adapter remains labeled experimental; this DL
table work must not relabel it as a calibrated normative UL implementation.

### Final staged receiver-export verification (22 September, 11:49 IST)

Integration update: after the old run completed PHY execution and MAT
publication and entered its external Python terminal refresh, the reviewed
five-file MATLAB patch was applied to the main working tree. Reverse
`git apply --check` confirms the archived patch is fully incorporated.
The earlier hold-until-process-exit plan was narrowed at this safe boundary;
the current v3 run is still not final-source PHY qualification. A fresh
main-source MATLAB engine is running nine focused receiver, publication,
artifact and truth/proxy guard tests, not `testAll`:
`logs/5mhz_receiver_export_main_focus_20260922.log`. Its final CSV ledger will
record every pass/failure before any overall assertion. No final-source full
scenario has started yet.

At 12:01 IST, seven of those nine main-source tests passed: receiver-only
export semantics, atomic MAT round-trip, prepared PUCCH feedback, actual
receiver-only shared PUCCH, independent shared PUSCH completion, artifact
integrity and the link export pipeline. The two required E2E truth/proxy
guards were still running; their existing fixtures include FDD system-level
paths, but no FDD feature/configuration repair is being undertaken. The
original v3 external browser refresh was also still live. The next full
5 MHz output folder `5mhz_rank2_20db_full_control_20260922_v4` did not exist
and no such run was launched. Free disk space was approximately 181 GiB.

- `testSharedPUCCHReceiveOnlyClock` now also asserts the nullable numeric
  preparation/receiver-only flag schema, receiver-length source, exact frozen
  context digest and CRC applicability against the actual receiver receipt.
  The final staged candidate passed this physical test and
  `testPUCCHReceiverOnlyExportEvidence`: two actual DL transmissions, zero
  UE PUCCH producers, two DTX HARQ outcomes, nine rejected-invalid-operation
  guards and retained-IQ replay equivalence.
  Log: `logs/pucch_receiver_export_candidate_final_20260922.log`.
  Raw component evidence:
  `results/lls/pucch_receiver_only_export_candidate/20260922_final`.
- The corresponding transmitter-present test,
  `testLLSPUCCHWaveformFeedback`, now asserts that actually prepared ACK,
  NACK and CSI trials are not marked receiver-only. Its fixture path is
  anchored to the test's repository rather than the current directory, so
  isolated source overlays test the identical installed scenario. It passed
  against the final candidate in
  `logs/pucch_prepared_export_candidate_final_20260922.log`.
- These are scoped component/export passes, not noise-only false-ACK
  qualification, a full missing-DCI matrix, or final 5 MHz acceptance.
- The original v3 MATLAB engine completed its optional MAT save at
  06:17:21 UTC. At 06:18:44 UTC it started its normal second browser refresh
  (`--strict --force`), now using the repaired publisher. This remains
  older-PHY/newer-publisher evidence. The old MATLAB production source is
  still unmodified; the reviewed receiver/export/MAT-publication patch
  passes `git apply --check` and awaits safe main-source integration and
  verification after this process exits.

Update, 22 September browser closure: the v3 browser phase ended with five
missing charts despite captured source arrays being present. The Python
consumer repair and previously staged column-lookup cache are now integrated
after that external browser process exited. The MATLAB production files are
still unchanged while its final MAT save is active. See
`docs/lls/5mhz_v3_chart_failure_repair_20260922.md` for root causes, 198 focused
test passes and separate exact-source CSV/PNG replay evidence. This supersedes
the earlier statement that both production patches remain wholly staged;
the MATLAB receiver/export/MAT-publication patch remains staged. No run has
been relabeled as passing.

The current DL-heavy 400 MHz YAML explicitly describes ideal delayed HARQ.
It is not the full shared physical-control acceptance configuration. Preserve
that benchmark and its retained evidence; create a separately identified
shared-waveform scenario after the 5 MHz gate, rather than silently changing
the old benchmark's meaning.

- Resolve 264-PRB DL/UL BWPs, 120 kHz carrier/control/reference-signal grids,
  four-port channel and DM-RS dimensions, and the requested 5-DL/2-UL/1-mixed
  calendar together. Do not inherit the 5 MHz scenario's 25-PRB / 15 kHz
  initial-access or control allocations unchanged.
- Bind processing capability to numerology 3. The existing
  `TimingPolicyCatalog.capability1(3)` supplies base N1=20 and N2=36 symbols;
  TDRA, K1/K2, switching and UCI budgets must still be checked against actual
  physical symbol times. The 5 MHz base N1=8/N2=10 is not transferable.
- `resolveMCSProfile.m` currently has normative tables 1/2/3 and the
  separately labeled experimental registry, but no normative DL 1024-QAM
  table 4. `resolveCQIProfile.m` supports CQI tables 1/2, not CQI table 4.
  Add consistent catalog, resolver, modulation and CQI-to-MCS coverage before
  claiming standards-backed DL 1024-QAM link adaptation. Do not describe the
  experimental square-QAM table or an invented SINR threshold as a normative
  3GPP table. Calibration remains distinct from normative MCS entries.
- Derive an execution horizon sufficient for actual access, CSI/SRS,
  adaptation and HARQ completion. Fifty-eight slots at 120 kHz are only
  7.25 ms, not the 58 ms covered by the 15 kHz scenario.
- Keep 7 GHz / 400 MHz single-carrier and the requested UL 1024-QAM research
  extensions explicitly labeled. Validate their actual decoding and feedback
  without disabling PDCCH/PUCCH/CSI/SRS or replacing feedback with ideal ACKs.

These findings are implementation prerequisites, not newly observed failures
of the active 5 MHz run. Its source and configuration remain unchanged while
the current v3 MATLAB execution is active.

### Main-source acceptance attempt v4 (22 September, 12:23 IST)

This update supersedes the historical staged-only and seven-of-nine status
above. The five-file receiver/export/MAT-publication patch is integrated in
the main working tree. All nine main-source MATLAB focused tests passed;
the final ledger is `logs/5mhz_receiver_export_main_focus_20260922.csv`.
The Python captured-plane/export regression was repeated: 198 passed.

A fresh MATLAB process was started for the unchanged full-control
`lls_tdd_5mhz_rank2_shared_awgn_20db.yaml`, with unique run tag
`5mhz_rank2_20db_full_control_20260922_v4`. It asserts `out.Ok` after return;
the launch is not itself acceptance. Log:
`logs/5mhz_full_control_acceptance_20260922_v4.log`. Output:
`results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v4`.

The v3 process remains in artifact finalization; its PHY and historical raw
rows predate the MATLAB export repair. No old outputs were overwritten and
no `testAll` or 400 MHz execution was started. The next gate is complete v4
PHY/export/terminal acceptance, including actual receiver-only PUCCH evidence
and the slot-34/39 combined-UCI checks. Statistical detector qualification
and the separate full-control 400 MHz implementation remain open.

### Independent receiver-context audit coverage (22 September, 12:35 IST)

While v4 runs, its MATLAB runtime and publisher source remain unchanged.
An offline audit gap was reproduced with four negative tests: the checker
did not reject a receiver-context total inconsistent with its HARQ/SR/CSI
field widths, absent context provenance, or invented transmitted-reference
bits/success on a receiver-only observation. The check now covers installed
context widths even for DTX; it does not equate an absent UE producer with
a successful transmission or a qualified detector.

Only `tools/audit_lls_uplink_evidence.py` and its Python tests changed for
this follow-up guard. The combined offline audit/publication regression
passed **248/248** in 22.94 seconds, retained in
`logs/5mhz_receiver_context_audit_focus_20260922.log`. The checker also passed
all four applicable checks on the actual main-source focused test's retained
`pucch_receive_only_trials.csv` (one exported observation). These are audit
coverage and component evidence, not an integrated v4 verdict.

At this checkpoint v4 had reached slot 20/58 without a reported failure.
The old v3 process was still in terminal browser finalization. Neither run
has been declared final-source accepted, and no 400 MHz run has started.

### V4 integrated receiver-only export proof (22 September, slot 24)

The actual v4 `air_interface/csv/pucch_trials.csv` now records one completed
receiver-only occasion: HARQ=0, SR=1, CSI-Part1=10, CSI-Part2=0;
`ReceiverExpectedBitCount=11`, `DecodedBitCount=11`, decoded bits
`10110110100`, width source `receiver_length_context`, and retained context
digest `25da6704e5aeb8047eac4aa71774a4ab296b13841575dde5b04e03ffe0547e7d`.
`ReceiverUsable=1`, `PUCCHDecodeOk=1`, `DTXFlag=0`, and
`PUCCHTransmissionPrepared=0` are no longer contradictory. Crucially,
`SuccessFlag=0`: the no-producer detection is not a successful transmission.
CRC is not applicable and `CRCPass=NaN` remains unavailable.

The read-only independent audit reports zero consistency failures for these
observed bytes, preserving the no-producer detection explicitly. Receipt:
`logs/5mhz_v4_slot24_receiver_export_audit_20260922.json`. PRACH, PUSCH and SRS
were not yet observed by this checkpoint audit, so it is not full-run
acceptance. This closes the specific slot-24 receiver-only export repair in
an integrated execution; it does not qualify the physical detector or hide
its PUCCH-absent detection (other waveform overlap has not been excluded).
No detector threshold was adjusted.

### SRS prediction correction and run-state reconciliation (22 September)

The v3 terminal log ultimately reported `out.Ok=1` at 07:16:55 UTC
(12:46:55 IST). Its earlier missing-chart report was superseded by terminal
publication. This is not final-source scientific acceptance: v3 executed
the older SRS predictor, and its publisher changed during finalization.
The v4 attempt was intentionally interrupted at slot 32 after an independent
test proved that predictor wrong; its logs and partial results are retained.
See `logs/5mhz_v4_interrupted_for_srs_rank_power_repair_20260922.md`.

Root cause: `estimateSRSRITPMI.m` added the difference between the SRS
reference SINR and the predicted layer mean to every layer. This cancelled
the native unit-total-power precoder's rank-dependent power split. The
independent native-codebook/MMSE reference showed +3.0103 dB at rank two
and +6.0206 dB at rank four, at both 20 and 30 dB. Evidence:
`logs/srs_pusch_rank_power_independent_20260922_v2.log`.

The main source now retains measured reference signal/disturbance power,
uses that disturbance before MMSE/RI/TPMI selection, and removes the
post-MMSE shift. The normalized fixed-SNR path explicitly identifies its
unit-grid power conversion. A thermal link-budget total without a measured
SRS/PUSCH per-RE conversion is diagnostic-only, not an authorized scheduling
SINR. `CoupledTruthRuntime` checks this provenance before installing CQI/MCS;
`runWaveformLinkBundle` carries it into the normal SRS trial/export schema.
Neither injected noise nor decoder acceptance thresholds were changed.

Focused evidence:

- `logs/srs_pusch_rank_power_repair_focus_20260922.log`: three tests passed,
  including all six independent rank/power cases with zero numerical error.
- `logs/srs_rank_power_runtime_integration_20260922.log`: five tests passed.
  The actual 5 MHz scenario's SRS waveform measured 20.0084 dB and predicted
  minimum rank-two layer SINR 16.8127 dB. Runtime UL ILLA consumed that exact
  prediction and selected CQI 10/MCS 18. Five missing-provenance cases were
  rejected. This is component/scheduler integration, not a complete run.
- The same batch passed the 24-case SRS noise/despreading test (25/264 PRBs,
  1/2/4 ports, combs 2/4, hopping on/off), OLLA retransmission exclusion,
  reference-SINR evidence and shared TDD PUSCH independent completion.

No new full scenario or `testAll` was launched for this follow-up. A fresh
full 5 MHz run remains required after the corrected predictor, followed by
separate 400 MHz shared-control acceptance. The independent detector
statistical qualification remains open.

### Final focused verification receipt (22 September, 13:32 IST)

The adjacent batch finished with `FOCUSED_TOTAL=13 FAILED=0` in
`logs/srs_rank_power_adjacent_guards_20260922.log`: configuration, DL/UL
chains, reference points, scheduler grant consistency, both strict proxy/
fallback guards, link export, artifact integrity/preservation, both E2E
truth/packet guards, and shared PDCCH resource allocation. The latter
includes AL8 candidate exhaustion and collision handling at component
level; it is not an exact slot-34 sweep rerun. The E2E guards retain their
existing FDD fixtures; no FDD feature implementation was undertaken.

Together with the preceding three estimator/waveform tests and five runtime
integration tests, **21 test functions passed, zero failed**. `testAll` was
not executed. The independent power matrix contains six cases and the SRS
despreading matrix contains 24 cases; those are cases within the 21 tests,
not extra test functions. No fresh full scenario was started. A clean
final-source 58-slot run, low-SNR sweep acceptance, detector statistical
qualification and full 400 MHz shared-control acceptance are not claimed.

### V5 measurement audit and production repairs (22 September, 15:24 IST)

V5 completed 58 PHY slots, but was deliberately interrupted during derived
evidence canonicalization at 15:07 IST after four defects were reproduced.
It is **incomplete, not accepted**, and no scenario is currently running.
The original log and results are preserved. Interruption receipt:
`logs/5mhz_v5_interruption_receipt_20260922.json`. Results:
`results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v5`.

Actual primary rows contain 19/20 DL CRC passes and 5/5 UL CRC passes. The
slot-58 DL failure has feedback due outside the scheduling horizon; it is
not proof of exhausted HARQ or a measured residual-BLER failure. Slot 34
contains 3 HARQ + 1 SR + 0 CSI, 4/4 decoded bits and all three HARQ decisions
applied. Slot 39 contains 4 HARQ + 1 SR + 10 CSI, 15/15 bits and CRC pass.
Slot-34 CRC is not applicable, not a fabricated CRC pass.

| Defect observed in V5 | Production repair | Verification state |
| --- | --- | --- |
| UL CSI refresh used pilot-reference 19.7777 dB instead of receiver data 21.5003 dB | `selectReceiverDataSINR` is shared by scheduler feedback and telemetry in `CoupledTruthRuntime`; original post-equalization source/role/status retained; no configured or pilot fallback | Runtime reference-plane isolation, derivation and scoring tests pass |
| AWGN PUCCH exported skipped/unit-channel stages although DMRS estimation and MMSE ran | `pucchReceiverStageEvidence` takes the actual receiver result and independent assignment; waveform, receiver-only and primary-row paths retain stage/timing/noise/resource evidence | Metadata, actual waveform and receiver-only clock tests pass |
| DL slot 58 delivery trace starts at 0.107 s rather than 0.057 s | `reconstructLLSKPISummaryFromRaw` prioritizes explicit clocks and zero-based absolute slot, avoiding double frame offset; no row-number clock | DL/UL numerologies 0/3 and existing deduplicated-goodput/duration tests pass |
| Aggregate EVM/NMSE/LLR repeated as if measured independently on every layer | Paired layer symbols produce per-layer EVM; both trial builders preserve it; MIMO reducer keeps aggregate metrics in `Trial*` columns and leaves unavailable layer NMSE/LLR as NaN | Eight layer/coded-chain tests passed, including actual ranks 1/2/4 PUSCH and DL/UL trial tables |

First integrated batch: `logs/measurement_runtime_integration_focus_20260922.log`,
10 test functions passed, zero failed, MATLAB exit 0. Per-layer batch:
`logs/per_layer_measurement_integration_focus_20260922.log` (8/8 passed,
MATLAB exit 0). Both empty DL/UL trial schemas retain the additive EVM fields.
The semantic auditor now requires measured EVM provenance (including exact
zero-error/-Inf-dB handling) and explicit unavailable layer NMSE/LLR status
with separately preserved trial aggregates. Copied aggregate values are
rejected. This validates honest scope, not missing per-layer measurements.
`logs/measurement_export_python_focus_20260922.log`: 144 passed, exit 0.
Adjacent guards: `logs/measurement_repair_adjacent_guards_20260922.log`.
No `testAll`, final-source full-run acceptance,
or detector qualification is claimed. The receiver-only slot-24 detection
remains separately identified with no PUCCH producer and no transmitted
success; no detector threshold was tuned to hide it.

### Final measurement-repair verification (22 September, 15:47 IST)

`logs/measurement_repair_adjacent_guards_20260922.log` finished with
`FOCUSED_TOTAL=15 FAILED=0`, MATLAB exit 0. This covers configuration,
strict proxy/fallback guards, DL/UL chains and reference points, scheduler
grant semantics, exports/artifact integrity/preservation, both E2E guards,
MIMO layer/DMRS mapping, shared PDCCH allocation and eight-point AWGN sweep
isolation. Existing E2E/PDCCH fixtures include FDD regression cases; the
requested scenario remains TDD and no FDD feature work was added.

All eight actual noise realizations passed against independently calculated
sample/grid variances at [-30,-20,-10,0,10,20,30,40] dB. The largest absolute
error was 0.0471708 dB. Point identities and physical noise seeds are distinct.
The PDCCH test includes AL8 resource exhaustion/collision rejection; it does
not establish exact slot-34 behavior in a full low-SNR access run.

Across the three MATLAB batches there are 33 successful invocations of 30
distinct test functions, zero failures. Python scope remains the four-file
144-test batch, not `testAll`. Source changes are in the main working tree;
the retained V5 run was not rewritten or relabeled as passed. A fresh full
5 MHz acceptance run, independent detector qualification and the full
400 MHz shared-control run remain outstanding. Unavailable per-layer NMSE
and LLR measurements remain explicitly unavailable, not fabricated.

### V6 full-control acceptance execution (22 September, 15:52 IST)

Launch identities checked from Win32_Process: launcher 17160, MATLAB engine
3200, creation 15:48:44 IST, exact V6 command line. Execution session 70586.
These are historical launch identities; check PID/creation/command again
before declaring it live, stopped or taking any process action.

Log: `logs/5mhz_full_control_acceptance_20260922_v6.log`.
Results:
`results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v6`.
The runner captures the resolved configuration, Git identity, tracked patch
and untracked source bundle. Runtime MATLAB/config and Python publisher
source remain frozen during this execution; this documentation update is
not an executable source change.

`testRank2SharedAWGNPrecoderContract` passed before the scenario started.
It rejects disabled PDCCH, PUCCH, CSI/RI/PMI/CQI/CRI, SRS, TRS, HARQ and
ILLA/OLLA, verifies both bootstrap ranks 1 and ceilings 2, the four-port
reference/physical dimensions, paired UL MCS authority and actual rank-two
precoder normalization. The normal runner resolved to `waveform_bundle`
for `slot_coupled_truth`, reported `exact_yaml_runtime_no_auto_reduction`,
20 dB and 58 slots, then entered physical slot 1. No acceptance verdict is
available at this checkpoint.

Required same-run checks: slot 34's 4-bit HARQ/SR context; slot 39's 15-bit
HARQ/SR/CSI context; physical control ownership; actual data-SINR consumption
and causal SRS use; rank/layer/DMRS and EVM provenance; delivery timestamps;
deduplicated goodput; final CSV/PNG/manifest closure. Detector qualification
and full 400 MHz acceptance remain separate requirements, not inferred from
a possible successful 5 MHz launcher exit.

#### Detector receipts revalidated, not resumed

- `logs/tdd_detector_awgn_20db_held_out_v2/run_status.json`: revision
  `6ee28639154e74b1f3cfb14a157a7f939bd43aac`, terminal candidate rejection,
  zero physical rows, one incomplete attempt. Do not restart it as if clean.
- `logs/tdd_detector_awgn_20db_held_out_v2_67b1fdb6/run_status.json`: revision
  `67b1fdb619a542ac7f511b5cec0739de3f87066e`, eight physical rows (one episode
  across eight cases), 600 episodes/case planned, qualification false.
- `validatePUCCHDetectorEpisodePolicy` explicitly restricts this harness to
  eight Format-0 hypotheses with one/two HARQ bits. It does not cover the
  actual Format-2 combined HARQ/SR/CSI occasions in the target run.
- Campaign registration locks source revision, MATLAB, seeds and resolved
  scenario and requires a clean source. Current dirty main cannot append
  episodes to that old registration. Preserve those receipts; a tested,
  frozen current-source campaign and separately defined Format-2 coverage
  remain required. No threshold has been tuned against V6 or old slot 24.

### Independent UL feedback-plane audit while V6 executes

The standalone `tools/audit_lls_uplink_evidence.py` now checks actual saved
`csi_feedback_reports.csv` bytes as well as PUSCH/SRS rows. This tool and its
Python test are not imported by the MATLAB runtime or Python publisher;
their edits do not change V6 execution. Runtime/config/publisher remain frozen.

For UL `PUSCH-DMRS` reports it requires one receiver source identified by
slot/UE/RNTI/serving cell and exact scalar/source/role/status preservation
from the canonical post-equalization data plane. It rejects ambiguous,
missing, pilot, proxy or otherwise untrusted sources. For later
`runtime_reported_cqi` UL grants it checks the cited source/age, one delivered
report, and preservation of that report's frozen adjusted SINR/backoff.
It does not infer an aging formula, compare DL quantized CSI to unreported
UE analog measurements, or treat SRS prediction as a received PUSCH sample.
The ordering check is slot-level, not sample-clock causality qualification.

Seven new metadata test functions exercise positive and corruption cases.
`logs/data_feedback_audit_focus_final_20260922.log`: **135 Python tests pass**
across the uplink audit and CSV semantic test files. This overlaps earlier
test sets; do not add those counts. No additional MATLAB suite was started.

Retained V5 re-audit:
`logs/5mhz_v5_data_feedback_reaudit_20260922.json` records exactly five
`data_feedback_receiver_plane_binding` failures, at source slots
35/40/45/50/55. This reproduces the already-repaired pilot/data-plane mixing
from actual old CSVs rather than only passing constructed fixtures. The
original V5 files and earlier audit receipts are unchanged. V6 must pass
these checks once its corresponding data/report rows exist; startup alone
cannot close them. Last process verification at slot 23/58 still matched
engine PID 3200 and its original creation time/command.

### V6 first integrated PUCCH stage-export proof (slot 24)

The new main-runtime path has published its first actual receiver-only row:
`ChannelEstimationMode=dmrs_per_resource_mmse_equalization`, estimation and
equalization attempted, Format 2, start PRB 4, two symbols. The acquired
reference-correlation timing offset and applied correction are both 131
samples, and `TimingEstimateUsed=1`. These are executed receiver results,
not fields inferred from the AWGN propagation profile.

The same row retains `ReceiverOnlyAssignment=1`,
`PUCCHTransmissionPrepared=0`, `SuccessFlag=0`. Thus the export repair does
not convert a receiver-only detection into a successful UE transmission.
The independent first-observation receipt is
`logs/5mhz_v6_receiver_only_first_observation_20260922.json`. It records
observed-byte hashes and coverage; missing later SRS/PUSCH/CSI rows are not
invented. Statistical detector qualification is still not claimed.

### V6 access completion and independent normalized-AWGN audit

Access completed at slot 25; the slot-26 runtime records access=1/1 and
valid TRS tracking. By slot 31, the UE physically received its first data
DCI (`control_slot=31`, `data_slot=31`, `sample=231500`). No terminal pass is
inferred from those intermediate milestones.

The standalone RA audit initially rejected the five saved access stages:
its old checks required dBm/mW and thermal-noise mode, whereas the actual
rows explicitly use normalized waveform power and fixed reference-Es/N0.
This was an audit applicability gap, not evidence of wrong injected noise.
The original rejected receipt is retained under
`logs/5mhz_v6_access_capture_audit_20260922`.

`tools/audit_lls_ra_capture.py` now separately audits normalized AWGN rows.
It requires a non-device-power claim, unavailable physical dBm/mW fields,
normalized transmit-power arithmetic, and the independently saved resolved
scenario's SNR and reference RE energy. It checks grid variance = reference
energy / linear SNR, sample variance times the OFDM transform gain = grid
variance, and equality to the actual pre-front-end noise ledger. It retains
the original thermal checks and refuses missing or contradictory policy;
it does not infer reference energy from the variance under test.

`logs/ra_awgn_capture_audit_focus_20260922.log`: **165 Python tests pass**
across RA capture, uplink evidence and CSV semantics (overlapping prior
sets, not additive). Corrupted timing/power/noise, missing configuration,
false device-power labels and mismatched reference authority are rejected.
Only standalone audit/test code changed; V6 runtime and publisher remain
frozen. No new MATLAB suite was started.

The re-audit passes Msg1, Msg2, Msg3, Msg4 and RRCSetupComplete on identical
source CSV bytes (SHA-256
`07faebb25aaba85184a183d2e7c4ba4b54a7890cac649bf67331f85f79039716`).
New separate receipt directory:
`logs/5mhz_v6_access_capture_audit_awgn_20260922`.
This proves the audited capture/power/noise arithmetic only, not receiver
performance, physical detector qualification or end-to-end acceptance.

V6's first primary PDSCH row (slot 31) has CRC pass, one transmitted layer,
measured DMRS count 1, `ConfiguredSNR_dB=AppliedAWGNSNR_dB=20`, and absolute
slot index 30. Aggregate EVM is 0.0574054930160732 and its one-layer EVM is
0.057405493016073214, with source
`paired_layer_symbols_average_reference_power_no_payload_fit`. This proves
the additive EVM fields survive the normal coupled execution/export path.
It is not yet a multi-layer or final derived-MIMO acceptance result.
Measured post-equalization SINR is 24.8209309769778 dB; it is a separate
receiver data plane and is not forced to equal the configured reference SNR.
The independent uplink receipt at this checkpoint is
`logs/5mhz_v6_access_srs_checkpoint_20260922.json`: PRACH=1, PUCCH=2, SRS=1,
zero checked failures; PUSCH and CSI-feedback rows not yet observed.

### V6 follow-up: slot-31 crash repair and actual UL feedback binding

At the 22 September approximately 16:19 IST review, the engine remained
PID 3200, created at 15:48:44, executing the V6 command. Execution had reached
slot 39/58; no terminal acceptance is claimed. No production runtime or
publisher files were changed during this review, and no testAll was launched.

The retained V2 failure is `MATLAB:nonExistentField`, missing `SNR`, at
slot 31. The integrated caller now supplies `job.SNR_dB` explicitly to
`bindSharedDataNoiseEvidence`; the helper checks it against the executed
fixed-AWGN noise calibration. V6 has crossed that boundary. This is not an
export-label correction.

Slot 34 has the required four-bit HARQ/SR payload, no CSI ownership,
`StateChangeApplied=1`, `HARQFeedbackAppliedCount=3`, and source slots
31/32/33. Its CRC is not applicable, not a fabricated CRC pass.

The first actual V6 PUSCH (slot 35) passes CRC at rank 2 / MCS 22, with
measured DMRS count 2 and configured/applied AWGN SNR both 20 dB. Its two
measured layer EVM values are 0.087097111109663949 and 0.085648166661831074.
Its scheduling SINR is 22.5581350157488 dB from the preceding SRS prediction.
The subsequent UL report, sourced at 35 and delivered at 36, retains actual
post-equalization SINR 21.50030323159114 dB, with the receiver's original
decision-residual-bounded source and status. It no longer substitutes the
pilot-plane minimum seen in V5.

Independent receipt `logs/5mhz_v6_ul35_receiver_binding_20260922.json`
records zero failed checks with PRACH=1, PUCCH=3, PUSCH=1, SRS=2 and
CSI-feedback=2. It also explicitly retains the slot-24 receiver-only
detection without a prepared PUCCH. Inspection of `received_csi_reports.csv`
confirms that detection delivered CQI 4 / RI 1, referencing slot 19, to the
runtime scheduler at slot 24. This is an outstanding physical detector
qualification concern, not proof of a real UE transmission. Rejecting it
merely by consulting producer absence would introduce a transmitter oracle.
Full V6 acceptance, later-grant feedback consumption, and detector
qualification remain separate gates.

At 16:19 IST the slot-39 primary PUCCH row was also available: independent
receive layout HARQ=4, SR=1, CSI Part 1=10, Part 2=0; expected/decoded width
15/15; applicable CRC passes; `HARQFeedbackAppliedCount=4`. Thus both
slot-34 and slot-39 layout checkpoints now have same-runtime V6 evidence.

### V6 later-grant proof and independently reproduced CSI export defect

At approximately 16:28 IST the same live V6 engine had reached slot 45/58.
Slot 40's PUSCH passes CRC at rank 2 / MCS 20 and cites feedback source slot
35 with `SchedulerCQISource=runtime_reported_cqi`. The data-feedback audit
now verifies actual receiver -> delivered report -> later grant, not just
the existence of a report. The first SRS-driven slot-35 grant remains a
separate prediction path.

Added `audit_received_csi_binding` to the standalone uplink audit. It joins
received PUCCH CSI by independent context digest, due slot, UE, RNTI and
cell identity; it does not match CQI values or infer a transmitter. Prepared
PUCCH rows name their cell `BaseStationID`, whereas receiver-only rows use
`ServingCell`; both existing authorities are recognized, with conflicts
rejected. Failed/stale CSI does not forbid a separate HARQ state change.

`logs/received_csi_state_audit_focus_20260922_v2.log`: **171 Python tests
pass**, overlapping prior audit sets. Six new tests cover false-detection
delivery, missing/duplicate/wrong identities, contradictory flags, the
explicit cell alias, non-delivery and the file-level entrypoint. This is
metadata validation, not physical detector qualification.

Actual V6 receipt `logs/5mhz_v6_received_csi_state_reaudit_20260922_v2.json`
has **one failed check**, `received_csi_delivery_state_change_visible` at
slot 24. Its CSI report says delivered to the runtime scheduler, but the
same receiver-context row has all three state-change flags false. Source
inspection identifies `CoupledTruthRuntime.completeConfiguredPUCCHCSI`:
the receive-only trial is appended without disposition flags, followed by
`stageIndependentCSI`, which really publishes the decoded report. The
normal combined-HARQ completion path already updates its disposition flags;
the configured CSI-only completion path does not. Repair must bind the
actual post-publication disposition to that exact trial, preserving absent
TX and failed/stale decisions. Do not turn it into TX success or suppress
the physical false detection. Production is still frozen for V6; this
runtime correction is **not integrated or verified yet**.

The earlier new-audit receipt (without `_v2`) also flagged slot 39 because
the audit initially recognized only `ServingCell`; the current audit fixes
that schema applicability mistake and retains both immutable receipts.
No missing cell identity is fabricated.

Detector investigation: installed R2026a `nrPUCCHDecode` and its Format-2
implementation perform small-block correlation detection for 3--11 UCI
bits, returning empty soft bits on rejection. The simulator additionally
uses an energy metric for all Formats 2--4, regardless of payload length,
and does not retain the toolbox correlation metric in its final receiver
struct. Slot 24 exported energy metric 0.797318595431028 against configured
threshold 0.2, grid disturbance 199.118628116776, and equalized disturbance
0.147862296666497. Its 11-bit block has no CRC. This identifies the metric
selection/observability path to qualify; it does **not** prove that merely
preserving the correlation metric or increasing a threshold fixes slot 24.
The toolbox already applies that threshold before UCI decoding. Do not tune
the policy against this retained episode or claim it was noise-only; an
actual interference/capture decomposition is still required.

Primary API reference checked during this review:
https://www.mathworks.com/help/5g/ref/nrpucchdecode.html

### CSI-only disposition repair prepared and replay-verified (16:34 IST)

Added `+sixgr/+truth/bindConfiguredCSITrialDisposition.m` and focused
`tests/testConfiguredCSITrialDisposition.m`. The reducer accepts a completed
PUCCH CSI publication, finds exactly one matching independent receiver
context/slot/UE/RNTI/cell, and rejects combined HARQ occasions. It replaces
legacy decode-based state flags with the real delivered/stale/rejected CSI
disposition. Processing an unsuccessful report is distinct from applying a
scheduler change. No receiver bits, CRCs, transmission flags, success flags
or other physical measurements are rewritten.

The metadata test passes (log
`logs/configured_csi_disposition_focus_20260922.log`), including receiver-only
delivery, stale and rejected reports, duplicate/wrong identities, conflicting
cell aliases and attempted combined-HARQ use. It is registered in `testAll`
for later coverage, but **testAll has not been run**.

A separate MATLAB replay reads actual V6 CSVs and applies the new reducer
to its two CSI-only observations, checking that all non-disposition columns
remain unchanged. Log:
`logs/configured_csi_disposition_retained_replay_20260922_v2.log`.
The preview is `logs/configured_csi_disposition_repair_preview_20260922.csv`;
it is diagnostic, not a primary run result or a physical rerun. The first
replay launcher used a concatenated character vector instead of a string
list for its allowed-change comparison and failed its own assertion; that
log is retained without overwriting, and the corrected launcher passes.

**Integration is pending**: the new reducer is not called by V6 or any
existing runtime path yet. To integrate after V6 becomes terminal, return
the actual post-publication report as the optional second output of
`stageIndependentCSI`, consume that output in `completeConfiguredPUCCHCSI`,
and bind the completed row with this reducer. This avoids relying on an
earlier pre-publication copy. Then run the focused shared CSI/PUCCH runtime
tests and export/packet-accounting guards. The live runtime/publisher remain
unchanged; V6 had reached slot 48 with engine PID 3200 still active.

### V6 measurement audit expansion (16:40 IST)

The same V6 engine remains live and has reached slot 51. Actual DL rows
44/46/47/48 use two transmitted layers, measured DMRS count two, and two
distinct receiver-derived EVM values. UL slots 35/40/45/50 all pass CRC at
rank two, with MCS 22/20/22/20. Slots 40/45/50 cite preceding UL feedback
sources 35/40/45 respectively. Combined PUCCH occasions 39/44/49 decode
15/12/15 bits with the applicable HARQ/SR/CSI field widths retained.

`logs/5mhz_v6_primary_row_semantics_checkpoint_20260922.json` records
28 primary-row semantic checks with zero failures over 13 DL and four UL
observations. The final-population check was explicitly excluded: this
checkpoint cannot establish complete run populations, final HARQ outcomes,
or CSV/PNG publication. It exercises the existing primary-row audit for
operating-point/transport-block arithmetic, CRC/BER, noise and provenance.

The standalone SSB audit previously assumed physical watts/dBm, while the
fixed-AWGN primary rows explicitly retain normalized occupied-RE energy and
remove physical dBm claims. The original audit rejected all eight actual
occasions on its inapplicable RSRP/power-payload checks. That receipt is kept
as `logs/5mhz_v6_ssb_audit_before_normalized_support_20260922.json`.

`tools/audit_lls_ssb_occasion_evidence.py` now uses the explicit normalized
reference plane to select the corresponding power schema. It checks
per-antenna RSSI from the mean linear symbol power, without the watts-to-dBm
30 dB offset; window RSRQ still closes from its own reported reference and
bandwidth. It rejects physical-unit aliases in normalized payloads, retains
the existing physical-power branch, and does not relabel this four-symbol
SSB-window measurement as full-carrier or SMTC RSSI/RSRQ.

`logs/normalized_ssb_measurement_audit_focus_20260922.log`: **184 Python
tests pass** across SSB, RA, UL-evidence and CSV-semantic audits (overlapping
previous sets). New cases include one/two/four receive branches and corrupted
units, absolute-power claims, power/RSSI/RSRQ and missing reference-plane
authority. No production runtime/publisher was changed.

Actual V6 normalized audit:
`logs/5mhz_v6_ssb_normalized_audit_20260922.json`, eight observed occasions,
zero failed checks. This is independent arithmetic/metadata verification,
not statistical PHY, detector or end-to-end standards qualification.

### Format-2 policy diagnostic and retained capture overlap (16:50 IST)

Added `tests/diagnosePUCCHFormat2SymbolDetection.m`, a deliberately limited
decoder-input diagnostic. It loads the installed scenario's CSI resource,
SR overlap, report width, seed and detection threshold. It runs public UCI
coding/PUCCH modulation and decoding plus the production metric selector.
It does not execute OFDM/channel estimation/timing acquisition and is not a
waveform campaign or a statistical result. The initial helper tried an
uninstalled `cfg.phy.rnti`; it now reads the authored `cfg.lls6g.users.rnti_start`.
The first failed diagnostic log is preserved, not confused with a V6 error.

Successful diagnostic log:
`logs/pucch_format2_symbol_diagnostic_20260922_v2.log`.
The matching directory retains CSV, input symbols/configuration MAT and an
explicit scope JSON with `QualificationPassed=false`, `ThresholdTuned=false`.
Configured payload width is 11 bits, 32 QPSK symbols, threshold 0.2; these
small-block payloads have no CRC. Results:

| Decoder-input case | Toolbox correlation | Selected energy metric | Accepted |
| --- | ---: | ---: | --- |
| Coded UCI + noise | 0.99301 | 0.97982 | Yes, all payload bits match |
| Noise only | 0.42335 | 0.16545 | No |
| Unrelated QPSK + noise | 0.40964 | 0.98084 | Yes |

This proves one unrelated-symbol acceptance under the unchanged configured
policy, not a false-detection probability or the cause of V6 slot 24.
Both correlation and energy exceed the existing threshold in that case;
merely publishing or using correlation at the same threshold cannot reject
it. Do not tune a threshold against this observation. A frozen independent
waveform campaign must include both absent-producer noise and interference,
the real timing search, DMRS estimation and signal-present misses.

The retained V6 sample ledger supplies a specific interference hypothesis
for replay: PUCCH slot 24 captures [176463,184297), while RRCSetupComplete
captures [184143,191977), at 7.68 MHz. Their capture intervals overlap by
154 samples. PUCCH timing selected a 131-sample correction. These facts do
not yet prove interfering energy occupied the extracted PUCCH REs or that
the nominal `StageSlot` labels use the same indexing. The actual sample
coordinates, not labels or guessed TX timing, must drive the replay.

V6 remained on engine PID 3200 with the original creation time/command,
processing slot 55; production receiver, configuration and publisher remain
frozen. No detector threshold or physical outcome was changed in this work.

### Previous-failure review and completed PHY checkpoint (22 September, 17:01 IST)

V6 completed all 58 physical slots and sealed continuous TX IQ at 11:27:28 UTC.
It is still finalizing; this is not a terminal acceptance verdict. Primary
data rows contain 19/20 DL CRC passes and 5/5 UL CRC passes. Every data row
records configured SNR = applied AWGN SNR = 20 dB. DL slot 58 failed its
first attempt; its feedback lies beyond this execution boundary, so this
does not establish an exhausted-HARQ/residual-BLER failure.

The earlier slot-31 missing `SNR` exception and captured-chart publication
failure have existing integrated repairs, as detailed in the companion
`5mhz_v3_chart_failure_repair_20260922.md`. The current PHY passed the former
boundary. The latter still needs this run's final publication verdict.

The fresh post-slot-58 uplink audit receipt is
`logs/5mhz_v6_post_slot58_uplink_audit_20260922.json`: seven PUCCH rows, five
PUSCH rows, six SRS rows and six received-CSI reports. Its one failed check
is the already identified slot-24 received-CSI disposition mismatch. The
receiver-only false detection is explicitly retained, not scored as a
successful transmission or suppressed using transmitter absence.

Added assertions to `testSharedPeriodicCSIProducer` for completed CSI
publication versus trial disposition, for present, removed-audit and absent
producer modes. Running the absent mode against the unchanged production
runtime reproduced `test:MissingCSITrialDisposition`. The log is
`logs/configured_csi_runtime_disposition_before_20260922.log`; its captured
physical evidence is under
`logs/tpea6f062e_adb8_43b3_a46f_a462b9b12fc2`. This was one focused test,
not `testAll`. The prepared reducer is still not wired into production;
the live-run source freeze remains in place until V6 is terminal.

A fresh Python regression invocation passed 170 tests across captured PHY
charts, contract row lookup, uplink evidence, SSB evidence and CSV semantics.
This overlaps earlier sets and is not an additional 170 distinct campaign
or physical qualifications. Existing run outputs were not rewritten by
these audits. No new scenario, commit, push or cleanup was performed.

### Receiver frontend and MIMO audit root causes (22 September, 17:21 IST)

The preceding goal turn made progress by reproducing the CSI disposition
failure in an executed runtime test. This continuation found two additional
production-path gaps while V6 engine 3200 (creation 15:48:44) remained live.
At this checkpoint V6 has completed its waveform/control checks and is
canonicalizing derived evidence; it has not returned its terminal verdict.

1. **Receiver frontend depends on producer presence.** Prepared PUCCH uses
   `sharedObservationEvidence`'s digital-AGC-compensated observation.
   `completeConfiguredPUCCHCSI`'s absent-producer branch and
   `completeSharedPUCCHReceiveOnlyRuntime` instead pass native post-RF samples
   directly into `receivePUCCHObservation`. Both must apply the same existing
   `sixgr.phy.rx.compensateReceivedAGC` operation using the actual post-RF
   plane's `Segments` and gNB receiver ID. This uses receiver-known applied
   analogue gain, not transmitter bits or injected noise variance.

   Extended `testSharedPeriodicCSIProducer` and
   `testSharedPUCCHReceiveOnlyClock` to compare actual completion against
   a calibrated replay of the same ADC observation. The absent-producer
   test reproduces `test:CSIReceiverFrontendMismatch`:
   `logs/pucch_receive_only_frontend_before_20260922.log`.
   Actual gain varies from 80.3263 to 81.5945 dB; native versus calibrated
   grid variance is 93.3571 versus 7.72857e-7, and detection metric is
   0.148653 versus 0.150851. These variances belong to different planes;
   this is **not** proof of incorrectly injected noise. Both metrics are
   below 0.2. It proves inconsistent preprocessing, not that this repair
   eliminates V6 slot 24's false CSI detection.

2. **MIMO reconciliation has two outdated contracts.**
   `writeRFInterferenceReconciliation.localMIMODirectionContract` admits a
   fully array-backed channel or scalar 1x1 AWGN, but not the explicitly
   executed 4x4 identity operator. It also requires `rankExact` for
   `ExecutionPolicyOk`, even in adaptive mode, so bootstrap rank 1 versus
   actual rank 2 is incorrectly rejected.

   `diagnoseAWGNMIMOReconciliation` replays the existing production writer
   on retained primary rows into a separate diagnostics directory. The
   failure is reproduced in
   `logs/identity_awgn_mimo_reconciliation_before_20260922_v2/receipt.json`
   and its sibling launcher log: DL and UL array checks and the overall
   MIMO check are false. The first diagnostic attempt failed on its own
   untyped empty structure accumulator; the corrected explicit structure
   schema reaches the production assertion. Both logs remain preserved.

   Prepared `identityAWGNRuntimeEvidence` validates the existing operator
   source/class, AWGN applicability, all configured/physical/waveform
   dimensions, valid ranks and explicitly absent pattern/count-only claims.
   `testIdentityAWGNRuntimeEvidence` passes 1/2/4-dimensional positive and
   missing/contradictory-evidence negative cases. The helper also passes
   all 20 actual DL and five UL rows, without changing those rows:
   `logs/identity_awgn_mimo_evidence_focus_20260922.log`.
   **It is not connected to the production reconciler yet.**

3. **Exact receiver-only PUCCH capture is missing.** Completed dispatcher
   windows are removed, and the existing UL-control capture writer requires
   a prepared transmitter. Added the unused opt-in helper
   `exportIndependentPUCCHObservation`, gated by the existing raw-IQ and
   save-waveform settings. It retains the independent assignment/context,
   exact receiver-input samples, separate native pre/post-RF planes and a
   TX audit window with its own bounds. TX audit samples do not determine
   PUCCH presence. Native samples are not universally labeled sqrt(mW).
   This helper currently supports pilot-bearing formats; it does not claim
   to retain the Format-0 received timing prior.

   `logs/independent_pucch_capture_focus_20260922_v3.log` passes the capture
   test and AWGN classifier test. Checks include exact complex single
   precision, compensated-input versus native-plane separation, absent TX,
   shifted TX intervals, wrong/incomplete/duplicate planes, identity/clock
   mismatch and disabled capture. The v2 test readback exposed Windows
   HDF5 MAX_PATH limits; v3 uses a hash-identical short-path readback while
   leaving published captures intact. This is serialization validation,
   **not** a physical detector campaign. The capture helper is not wired
   into V6 or another production execution yet.

#### Integrate after V6 is terminal, then verify

- In `completeConfiguredPUCCHCSI`, apply recorded AGC compensation in the
  receiver-only branch; retain `ReceiverGainCompensation` in `rx` for both
  prepared and receiver-only branches. Save the actual receiver input via
  `exportIndependentPUCCHObservation` before buffers are discarded.
- Apply the same receiver gain compensation in
  `completeSharedPUCCHReceiveOnlyRuntime`, preserving its received Format-0
  timing prior, independent mapping and existing physical failure outcomes.
- Return the final report as the optional second output of
  `stageIndependentCSI`; bind the actual published disposition using
  `bindConfiguredCSITrialDisposition` only in configured CSI-only completion.
- Wire the identity-AWGN classifier into MIMO reconciliation. For adaptive
  rank execution, reuse `resolveNominalVsEffectiveMIMO`'s existing
  `RankLayerTrials.SpatialContractMatch` and installed maximum capability;
  do not accept arbitrary in-range rank without grant correspondence.
  Keep `ExactOk`/exact-match fractions separate from adaptive execution.
- Run all three periodic-CSI producer modes, shared receive-only HARQ,
  combined PUCCH/CSI clock tests, AGC compensation, export/packet guards,
  and the retained MIMO audit replay. Preserve the red before-fix receipts.
  Then rerun the integrated scenario with actual receive captures enabled.
  Do not claim a detector qualification or 400 MHz acceptance from these
  focused checks. `testAll` remains prohibited and was not launched.

These production callers, the configuration and the publisher remain
unchanged during V6 finalization. The new tests are registered for future
suite coverage, not evidence that a full suite was run.

### CSI applicability authority diagnostic (22 September, 17:35 IST)

V6 remains live, exporting tables. Its interim truth-contract failures for
the issue registry, visual audit and artifact-generation receipt are
`NOT_EVALUATED` while those artifacts are still being produced, not new
terminal failures. Separately, the generated Phase-7 table explicitly names
the reproduced MIMO reconciliation failure. The canonical rank-layer table
has 20 DL and five UL `SpatialContractMatch=1`/`ExecutionContractMatch=1`
rows and all eight strict MIMO gates pass. Thus the legacy reconciler must
reuse those existing adaptive rank semantics rather than the bootstrap
rank-equality condition.

Further CSI review found an authority gap that must be fixed before claiming
independent feedback closure:

- `armConfiguredCSIReception` and `buildConfiguredPUCCHCSIReception` use an
  installed calendar and connected UL timing, but do not bind a completed
  gNB CSI-RS transmission obligation. V6 monitors CSI-only slots 24/29;
  its retained CSI-RS rows are slots 32/37/47/52/57. Slot 24's calendar
  reference is slot 19. No earlier report-source CSI-RS reception is in
  the retained table. Absence from that table alone is not a proof about
  every possible TX waveform; the gNB transmission ledger must be the
  implementation authority, not guessed UE readiness or payload presence.
- `resolveCSIReceiveReferenceEvidence`, used by combined HARQ/CSI
  reception, reads `ControlTrials.CSIRS` through
  `csirsMeasurementAvailability`. The latter requires UE `Observed`,
  `Consumed`, extraction, channel-estimate and measurement-success flags.
  That is a receiver-outcome dependency even though CQI/RI values and UCI
  payload bits are not directly consulted.
- New `diagnoseCSIReceiveReferenceAuthority` copies the first real V6
  CSI-RS row and changes each of those five flags individually, retaining
  its transmitted flag, identity and clocks. All five changes switch gNB
  eligibility from true to false. Evidence:
  `logs/csi_receive_reference_authority_before_20260922/authority_dependency.csv`
  and its `receipt.json`; launcher log has the same basename. The intentional
  failure is `test:CSIReceiveLayoutUsesUEOutcome`. This is an analytic
  dependency diagnostic on copied rows, not a new RF or CSI occasion.

The normative boundary was checked in ETSI TS 138 214 V18.8.0, clause
5.2.2.5, page 160: after relevant configuration/activation changes, this
report type needs eligible channel/interference measurement occasions by
its reference resource; otherwise the UE drops the report. A report
calendar by itself does not create a measured report.
Source: https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf

Implementation direction after the live-run freeze:

1. Extend the **existing executed data-TX ledger** at
   `commitSharedDataTransmission` with CSI-RS resource metadata from the
   immutable prepared grid/runtime event, only after the physical owner
   proves that transmission started. Include full TX bounds, cell/UE,
   resource/configuration epoch, sample clock and transmission identity.
   Preparation alone cannot establish execution. Reference eligibility
   additionally requires the physical clock to pass the retained TX end.
2. Resolve the gNB receive obligation from that executed ledger and the
   installed reference calendar, active sweep, resource identity and epoch.
   Do not use UE `ControlTrials.CSIRS` measurement-success flags to choose
   the gNB payload schema. Keep them in the separate UE report producer.
3. Apply the same gNB eligibility to CSI-only and combined PUCCH/PUSCH
   hypotheses. No preceding eligible reference must not be confused with
   an eligible reference followed by a missing/failed UE report: the latter
   must still execute independently and retain its physical outcome.
4. Preserve independently applicable HARQ and SR procedures when CSI is
   inapplicable; do not silently disable an SR monitoring obligation.
5. Extend fixtures with explicit reference-TX authority and test unchanged
   gNB schemas under UE measurement/payload poisoning, absent producers,
   activation/sweep/epoch boundaries and both UCI transports. Keep slot 34
   at 3 HARQ + 1 SR + 0 CSI and slot 39 at 4 HARQ + 1 SR + 10 CSI.

This finding does **not** qualify the detector or erase the historically
recorded slot-24 detection. No production eligibility code has changed yet.

## Focused integration after V6 PHY/CSV completion (22 September, 17:44 IST)

V6 finished all PHY execution and canonical CSV export and entered Python
browser materialization at 17:40:53 IST. The earlier blanket source freeze
was narrowed to the active publisher: only already-completed runtime and
MIMO-reconciliation paths were edited. Do not call V6 a final-source test
of these repairs. Its original primary evidence remains unchanged.

Integrated, awaiting the post-change focused verdict:

- `writeRFInterferenceReconciliation`: classify executed identity-AWGN
  spatial operators distinctly from physical array/pattern propagation;
  use canonical scheduled/transmitted/capability reconciliation for AMC.
  Preserve exact bootstrap-match flags and fractions. Added wrong-grant,
  above-capability, missing-port, false-pattern and fading negatives.
- `CoupledTruthRuntime`: compensate actual per-sample applied receiver AGC
  in both receiver-only PUCCH completion paths, exactly as the producer-
  backed receiver already does. Preserve the Format-0 received timing prior.
  This does not undo ADC clipping or alter the physical noise stream.
- CSI-only completion now binds the actual publication disposition back
  to its independent trial. It does not set transmit success or change bits.
- Pilot-bearing CSI-only/receiver-only completions can retain exact native
  pre/post-RF and actual compensated receiver-input samples through
  `exportIndependentPUCCHObservation`, under existing capture flags.

Before-change regression:
`logs/mimo_adaptive_identity_regression_before_20260922.log` fails the
valid adaptive identity-AWGN fixture, reproducing the retained-run blocker.
After-change batch:
`logs/pucch_mimo_integrated_repairs_focus_20260922.log` (8 focused tests).
No `testAll` or new full scenario has been launched at this checkpoint.
The independent CSI-reference authority repair and detector statistical
qualification remain separate open work; neither is bypassed here.

Post-change focused batch completed: **8 tests passed, 0 failed**, process
exit 0, including all three periodic CSI producer modes, receiver-only HARQ,
combined HARQ/SR/CSI waveforms, and the normal shared feedback clock. The
absent producer retained a physical observation and DTX without fabricated
TX or CSI. This is not a statistical detector qualification. The exact
before-change missing-compensation and disposition failures are retained.

Retained V6 MIMO production re-audit and four export/grant guards launched
next in `logs/mimo_retained_repair_and_export_guards_20260922.log`.
Their output is separate from the original run. Broader E2E truth guards,
final-source scenario acceptance and the full suite are not claimed by
this eight-test batch.

Retained-row replay passed at 17:53 IST:
`logs/identity_awgn_mimo_reconciliation_after_20260922/receipt.json`.
Both direction execution policies and `MimoKpiReconciliationOk` are true
for the original 20 DL / 5 UL rows. Exact-match flags remain false, with
bootstrap rank-exact fractions 0.4 DL and 0 UL. No primary rows were
rewritten; the receipt includes hashes of its original CSV inputs.

The four additional export/grant guards also completed with **4 passed,
0 failed**, exit 0: `testLinkExportPipeline`, `testArtifactIntegrity`,
`testOrganizeRunResults_E2EArtifactPreservation`, and
`testSchedulerGrantConsistency`. Thus this integration has 12 distinct
passing focused/guard tests plus the retained-row MIMO replay, not a full
suite or final scenario pass. Normal repository `git diff --check` passed.
The temporary `core.autocrlf=false` diagnostic produced CRLF whitespace
noise; it did not modify files and is not a source defect.

## Executed CSI reference authority (22 September, 18:12 IST)

Production integration:

- `commitSharedDataTransmission` now records CSI-RS reference metadata only
  after the physical owner's started-TX record is verified. Resource IDs,
  indices and symbols must match the retained mapped grid. The record binds
  physical epoch, cell/BWP, installed reference/report configurations and
  the transmission identity; it is not proof that the UE received CSI.
- `resolveCSIReceiveReferenceEvidence` now requires owner-verified TX and
  elapsed physical transmission end, active-sweep/reference-slot bounds,
  matching configuration/epoch and no configured measurement gap. It never
  reads `ControlTrials.CSIRS` or `PendingCSITable`. Cell-common reference
  applicability does not depend on which UE's PDSCH embedded the reference.
- All production PUSCH receive/selection/completion call sites now use
  `resolveSharedPUSCHCSIReceiveObligation`: installed schema plus this same
  executed-reference authority. The original pure calendar builder remains
  a configuration/planning API, not physical applicability evidence.
- The old receiver-only test's fabricated UE CSI row is now a **negative**
  oracle guard. Positive reference execution is tested by actual shared DL
  samples in `testExecutedCSIReferenceAuthority`, not fake measurement rows.

`logs/executed_csi_reference_authority_focus_20260922_v2.log` passes:
actual CSI-RS-bearing DL execution, no UE CSI measurement, unchanged
eligibility under poisoned UE state, unfinished-transmission rejection and
nine negative cases. The first attempt exposed a component grant using
`BaseStationID` rather than `ServingCell`; the writer now accepts either
explicit identity and rejects conflicts. No fabricated cell default.

`logs/csi_tx_authority_transport_regressions_20260922.log` is the separate
five-test integration regression batch; do not assume its verdict yet.

Still open: CSI-only arming/completion and standalone SR. Current early
CSI-only windows overlap installed Format-0 SR resource 0. Disabling the
whole window when CSI is ineligible would silently lose SR monitoring.
Low-level `PUCCHResourcePlan` and codec support SR-only presence, but the
shared coordinator currently schedules HARQ/CSI producers and has no
standalone SR receive/publication path. Integrate that path (including
positive/negative SR TX procedure state, received timing, overlap/transport
rules and honest DTX disposition) before replacing early CSI-only windows.
Do not use known UE absence as a gNB detection/eligibility oracle.

V6 pre-fix browser materialization completed at 18:00:11 IST with 734
artifacts and zero missing tables/charts. Runtime truth re-evaluation at
18:01:14 reported no missing evidence/strict failures. The retained Phase-7
MIMO gate is still false, as expected for its pre-fix rows/reconciler.
Engine 3200 was still writing its MAT result at this checkpoint; no final
launcher acceptance verdict is claimed.

## Reference-transport regression follow-up (22 September, 18:25 IST)

The five-test batch in `logs/csi_tx_authority_transport_regressions_20260922.log`
finished **4 passed, 1 failed**. Passing tests cover the independent PUSCH
obligation, PUCCH receive-only clock, unselected PUCCH producer, and normal
TDD PUSCH HARQ/CSI completion. The last test repeats actual shared-waveform
execution with producer bookkeeping removed/poisoned; received scheduler
feedback is unchanged. These are component runs, not target-scenario acceptance.

`testSharedRejectedULCSI` failed while accessing `SharedGNBCSIReportTable`.
Its configured report calendar had no actual CSI-RS TX, so the repaired gNB
correctly created no CSI receive obligation. The fixture previously relied
on configuration alone. The repair adds a real slot-6 DL/CSI-RS transmission,
without executing a UE DL decoder or injecting a UE CSI row. Its configured
K1=3 keeps that DL's feedback occasion separate from the tested slot-10 CSI
PUSCH. The test retains actual UL-DCI rejection, no UE PUSCH, no UE TB scoring,
receiver-owned HARQ state and no usable CSI from noise. The original
out-of-window noise-peak assertion remains in the unchanged data-only
fixture; the new CSI fixture has a different physical/RNG history and does
not claim to reproduce that original peak.

The first fixture check in `logs/rejected_ul_csi_reference_fixture_20260922.log`
rejected inherited `harq.feedback_timing_slots=4` against K1=[3]. The fixture
now explicitly configures all three timing fields consistently at 3; the
strict production validator is unchanged.

`logs/rejected_ul_csi_reference_fixture_20260922_v2.log` subsequently **passed**
at approximately 18:29 IST. It records one actual control rejection, one gNB
receive-only execution, zero UE UL transmissions and no usable CSI delivery.
Raw evidence is retained at
`logs/tpe7027278_a806_4a53_af38_a5ba691ac2d9`.
Thus all five selected transport tests have passing evidence across the
original four passes and this repaired-fixture rerun, not a newly executed
five-test batch. One noise episode is not detector qualification.
The standalone CSI/SR coordinator gap above is still open. Neither the
old run's primary CSVs nor its acceptance status have been overwritten.

## Standalone SR / CSI-only integration (22 September, 18:52 IST)

Implemented in production, after V6 physical execution finished:

- `buildConfiguredPUCCHReception`: installed no-HARQ receive obligation;
  eligible CSI uses the existing CSI builder, otherwise an installed SR
  resource remains monitored. No eligible CSI and no SR means no occasion.
  No UE payload/procedure state supplies the gNB schema.
- `buildConfiguredPUCCHCSIReception`: now enforces actual completed reference
  TX even for CSI-only reception, not just combined HARQ/CSI or PUSCH.
- `CoupledTruthRuntime`: arms standalone SR/CSI from configuration; binds
  the independent hypothesis; negative SR creates no contributor; positive
  UE procedure state prepares a typed waveform through `planSR` and the same
  shared physical owner. Completion publishes actual SR detection and TX
  audit separately, preserves duplicate guards, and never calls it CSI.
- Before the first actual SRS/PUSCH timing reference, standalone Format-0 SR
  acquires using the one configured positive-SR sequence and a bounded
  received-sample correlation. HARQ-bearing Format 0 still requires its
  retained measured UL timing prior. Neither branch consumes TX payloads,
  injected channel delay/noise or zero padding.
- `received_sr_observations.csv` is wired into the normal control CSV export.
  Opt-in exact PUCCH capture now preserves acquired-SR inputs or the actual
  Format-0 timing prior; it does not claim detector qualification.

`logs/shared_standalone_sr_physical_20260922_v2.log` passed both actual
5 MHz / 20 dB episodes: no TX/no positive detection, and one positive SR TX
with successful independent reception. Both have zero CSI bits. The first
attempt only exposed the fixture's missing `run.rootRunFolder` required by
continuous IQ capture; the fixture now supplies it rather than disabling
capture. Access timing is a declared component input, not full access proof.

`logs/csi_sr_independent_integration_20260922.log` is an eight-test batch.
Its standalone-SR test has passed again with native replay capture enabled;
periodic CSI present/removed/absent-producer tests are currently executing.
The periodic fixture now actually transmits a CSI-RS-bearing DL; its UE CSI
values are still explicitly declared transport-fixture inputs. No claim of
UE CSI estimator qualification is made by that fixture.

Remaining boundaries before another full run:

1. Finish this batch and repair any causal-reference fixture regressions.
2. Correct standalone-SR export scoring: raw negative-SR rows currently have
   `UCIContentMatch=0`, which the generic annotation could treat as failure.
   With no UE payload the content match must be unavailable, no-SR/no-detect
   is not a decode failure, while false/missed SR remain audit failures.
   Do not change the class while the current frozen integration batch runs.
3. MAC-trigger/timer ownership and positive-SR/PUSCH overlap remain explicit
   unsupported guards, not silently simulated scheduling. Current target
   YAML does not enable the phase-08 MAC SR lifecycle; received SR records
   correctly say `SchedulerStateChanged=false`.
4. Acquired-SR detection and long-format CSI false detection still need their
   independent statistical qualification. Two successful episodes do not
   close that gate. Full final-source 5 MHz acceptance is not yet proven.

Normative reference: TS 38.213 V18.8.0 clause 9.2.4 specifies positive-only
standalone SR transmission; clause 9.2.5 treats combined UCI separately.
The bounded-acquisition receiver is an implementation choice, not a claim
that the specification mandates or statistically qualifies this detector.

### Focused integration outcome and SR export follow-up (18:58 IST)

`logs/csi_sr_independent_integration_20260922.log` completed: **8 passed,
0 failed**. This includes real standalone SR positive/negative episodes,
periodic CSI with present/removed/absent producer bookkeeping, configured
combined UCI, actual TDD shared combined completion, capture serialization,
installed SR calendar, typed wire planning and physical SR resource checks.
The actual TDD test monitored SR (zero CSI) at slot 5 before the reference
transmission, then decoded the genuine combined occasion at slot 10.
These are focused component/integration checks, not the target 58-slot run.

Production SR completion now records no-TX/no-detection as `Status=NA` with
`UCIContentMatch=NaN`, not a successful payload decode and not a failure.
Actual false and missed SR detections retain `Status=FAIL` and explicit
flags. The ordinary canonical exporter remains unchanged. The physical
regression now checks canonical success/failure/observation flags and
declared export-only false/missed counterexamples. Its log is
`logs/standalone_sr_export_regression_20260922.log`; verdict pending.

### SR report consumer and component-gate audit (19:08 IST)

The first SR export regression failed loudly because the downstream
canonicalizer attempted `logical(NaN)` for unavailable UCI content match.
The canonical strict-evidence reducer now requires an explicit numeric
match of one. The reporting-bundle ratio preserves unknown values and
excludes them from its finite-evidence denominator. The five-test rerun
`logs/standalone_sr_export_regression_20260922_v2.log` passed all five,
including report generation with a declared `[NaN,0,1]` comparison fixture.
That fixture is not measured PHY evidence.

A subsequent inspection of the physical SR canonical CSV exposed an
additional issue not covered by that test's initial assertions: a positive
SR had `Status=FAIL` because strict evidence demanded a noise estimate and
resource-extraction flag not emitted by this noncoherent path. Also, the
in-path component gate required every silent SR monitor to decode payload.

Corrections now under test:

- `PUCCHReceiver` records whether its actual extracted resources are finite.
- Standalone SR completion retains that flag and the actual metric-valid
  flag. Canonical strict evidence explicitly recognizes Format-0 SR's
  noncoherent/no-noise-variance-consumed domain; no variance is fabricated.
- `evaluateInPathComponentEvidence` retains quiet standalone SR rows in the
  identity/truth audit, requiring completed sample clocks, actual detector
  evidence and explicit no-TX/no-detection/no-HARQ/no-CSI fields. They never
  count as successful decodes, and cannot alone qualify PUCCH reception.
  False/missed SR and invalid/oracle timing are not exempted.
- The physical test now asserts canonical `Status`, `StrictOk` and strict
  receiver evidence, plus the component gate and malformed-row rejection.

Four-test log: `logs/standalone_sr_component_integration_20260922.log`.
No final-source target scenario has been launched yet. The V6 browser
publisher is still operating on preserved pre-fix artifacts.

That four-test batch finished **3 passed, 1 failed**. The strengthened
physical SR assertion found the export check had inferred noncoherent
detection from `ChannelEstimationMode`; the actual AWGN receiver reports
`awgn_direct_resource_extraction` while separately setting
`NoncoherentSequenceDetection=true`. The correction propagates and uses
that executed detection flag, leaving the channel-estimation label honest.
The same four tests are rerunning in
`logs/standalone_sr_component_integration_20260922_v2.log`. The quiet-SR
gate also requires the content-match column to be explicitly present
and unavailable, rather than treating an omitted field as evidence.

### Final focused verdict and fresh target execution (19:15 IST)

`logs/standalone_sr_component_integration_20260922_v2.log` finished with
**4 passed, 0 failed** and MATLAB exit 0. Both actual SR RF episodes pass
their strengthened canonical-status and component checks. The quiet
episode remains a non-decode observation, not success; false/missed,
HARQ/CSI ownership, missing-field and oracle/zero-padding counterexamples
remain failures. Existing in-path component, receiver-only export and
PUCCH waveform regressions also pass. This is not detector qualification.

Fresh target:

- YAML: `simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml`
- Log: `logs/5mhz_full_control_acceptance_20260922_v7.log`
- Intended output: `results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v7`
- Launch: 19:14:22 IST; MATLAB launcher 19840 / engine 2456.
- Preflight: `testRank2SharedAWGNPrecoderContract`, then unchanged 58-slot
  scenario. No acceptance verdict yet. Preserve source until its PHY and
  exports finish, and keep V6 as the pre-fix comparison.

Required integrated checks include no CSI before an eligible actual
reference, standalone SR absence handled without fake decode success,
slot 34 HARQ/SR/CSI counts 3/1/0, slot 39 counts 4/1/10, actual applied
20 dB noise, adaptive rank/MCS audit, and final CSV/PNG closure. Broader
NR/E2E guards and statistical detector qualification are not newly claimed
by these focused batches. Full 400 MHz shared-control acceptance remains
pending after 5 MHz closure.

## V7 live evidence and independent CSV/PNG audit (19:29 IST)

The previous goal turn made production progress; this turn revalidated
engine 2456 (creation 19:14:22) and added independent audit coverage while
the production source remains frozen. The run reached slot 25 after the
actual slot-24 SR result described above. No full suite was started.

`tools/audit_lls_uplink_evidence.py` now joins standalone SR trials to
`control/csv/received_sr_observations.csv` in both directions. It checks
receiver assignment/context identity, cell/UE/RNTI/slot, completion clocks,
field ownership and truthful positive/quiet/false/missed outcome scoring.
Its **53 metadata-audit tests pass**, receipt
`logs/uplink_sr_semantics_20260922.xml`. This is neither RF nor statistical
qualification. It is an independent tool, not called by the active runner.

Newly reproduced export gaps, not fixed in V7's frozen production source:

| Gap | Proof | Required production repair after the freeze |
| --- | --- | --- |
| Applied SR timing flag | V7 slot 24 actually applies 145 samples from `received_configured_SR_sequence_bounded_search` but exports `TimingEstimateUsed=0`. The small regression fails in `logs/sr_timing_export_before_fix_20260922.log`. | `pucchReceiverStageEvidence.m`: recognize the actual SR reference acquisition source as an applied estimate, without claiming valid detection/timing lock; preserve prior-prediction distinction. |
| Positive SR TX audit bits | The physical positive SR fixture `logs/tpff8ea9a3_7788_4f96_a2cc_01f0951d07d7/pucch_trials_canonical.csv` has a received bit and successful TX but no transmitted reference bit. Existing independent payload audit rejects it. | `CoupledTruthRuntime.completeConfiguredPUCCHSR`: retain the actual frozen prepared report's serialized bits as TX audit only. No reference bits for an untransmitted SR; do not feed them into the independent receiver. |
| Constellation image drops layers | V6 `constellation-per-layer.csv` has DL1=38038, DL2=13338, UL1=13680, UL2=13680 samples, but its PNG shows only DL1/DL2/UL1. `_render_scatter_panels_svg` explicitly iterates `panels[:3]`. | `apps/lls_contract_materializer.py`: render every supplied group and grow the layout; preserve exact source samples and CSV group coverage. Two new regressions fail, with five existing tests passing: `logs/constellation_layer_coverage_before_fix_20260922.xml`. |

Completed V6 read-only checks:

- `logs/5mhz_v6_final_uplink_sr_audit_20260922.json`: one consistency failure
  at old slot 24 (`received_csi_delivery_state_change_visible`); its actual
  false CSI detection remains visible. V6 has no standalone SR sidecar.
- `logs/5mhz_v6_final_ra_capture_audit_20260922`: all five retained stages
  (Msg1/2/3/4 and RRCSetupComplete) pass the capture-clock, coverage and
  normalized noise/power arithmetic audit. Not radio qualification.
- Full CSV/PNG inventory is executing under Python PID 9204, creation
  19:24:09, output target `logs/5mhz_v6_final_csv_png_audit_20260922`.
  No audit verdict yet; an observation timeout is not process termination.
- The visible DL throughput decrease after slot 48 agrees with actual
  allocated PRBs changing from 25 to 1 and smaller real TBs. Do not fix it
  by scaling throughput or replacing the grants. Traffic/scheduler intent
  is a separate question from the chart's arithmetic.

400 MHz inspection reconfirmed the existing mixed-SSB/BWP-numerology
collision guard and ideal-feedback benchmark inheritance. No 400 MHz
scenario or production integration has been started ahead of 5 MHz.
