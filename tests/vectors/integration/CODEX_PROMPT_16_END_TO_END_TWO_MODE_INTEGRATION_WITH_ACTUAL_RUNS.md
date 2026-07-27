# CODEX PROMPT 16 — End-to-end two-mode integration with actual MATLAB runs

## Role

You are the lead integration engineer for the current 6GR MATLAB repository. The following technical phases are already implemented or substantially implemented in the live branch:

- frame, grid, numerology and duplexing;
- waveform generation, CP-OFDM and UL DFT-s-OFDM;
- PDSCH/DL-SCH and PUSCH/UL-SCH;
- PDCCH/DCI and PUCCH/UCI;
- SSB, initial access, SIB1 and random access;
- reference signals, measurements and link adaptation;
- MIMO, CSI, precoding and beamforming;
- channel, geometry, mobility, interference and RF;
- MAC, HARQ and scheduling;
- RLC, PDCP, SDAP, RRC and traffic;
- validation, independent oracles and statistics;
- canonical WebGUI, security, software and release architecture.

Your task is **not** to review these phases again and **not** to create another parallel simulator. Your task is to integrate the live implementations into one causal, production-grade link/system LLS runtime with two supported run modes:

```text
FIXED_SNR_SWEEP
GEOMETRY_NETWORK
```

Both modes must use the same production channel coding, grid mapping, reference signals, waveform, channel-application interface, RF front end, receiver, decoding, HARQ, measurement, scheduler and artifact infrastructure wherever the physics/procedure is common.

The mode difference must be limited to the environment/operating-point adapter:

```text
FIXED_SNR_SWEEP
    controlled SNR/noise operating points and optional bounded channel profile

GEOMETRY_NETWORK
    runtime geometry, pathloss, fading, mobility, multi-link interference,
    absolute power, measurement-driven control and network procedures
```

## Required inputs

Read before editing:

```text
AGENTS.md and nested instructions
all current phase implementation reports and issue ledgers
current scenario schema and parameter catalog
current active WebGUI backend/frontend
current canonical scenario files
integration_32_findings.csv
integration_architecture_contract.yaml
integration_mode_contract.yaml
integration_state_ownership_matrix.csv
integration_interface_contract.csv
integration_actual_run_matrix.csv
integration_cross_mode_equivalence_vectors.csv
integration_negative_test_vectors.csv
integration_acceptance_rules.csv
integration_matlab_test_plan.csv
desired_integration_csv_contract.csv
desired_integration_image_contract.csv
```

Inspect the current branch and map existing classes/functions into the contracts below. **Do not assume old source paths still exist. Do not create duplicate production engines merely because this prompt names a target class.** Reuse and consolidate the already implemented production classes.

## Non-negotiable integration rules

1. Do not change a test to accept a shortcut.
2. Do not bypass the implemented waveform chain in either mode.
3. Do not use configured SNR as measured SINR.
4. Do not use configured geometry/channel values as runtime observations.
5. Do not allow configured grants, CSI, ACK, beam or RRC state to override decoded state in connected execution.
6. Do not let calibration grants satisfy connected-control/network gates.
7. Do not build geometry interference from scalar SINR or scalar powers when a waveform contribution is required.
8. Do not consume an event, measurement or channel state before its `AvailableAt` time.
9. Do not silently clamp, retry, downgrade, normalize, rescale or replace an unsupported configuration.
10. Do not create separate frame, clock, seed, power, waveform, receiver or KPI services for the two modes.
11. Do not mark a run complete when any mandatory test is skipped, blocked, unavailable or not executed.
12. Do not call a Release-20/6G study run normative or conformant.
13. Do not report success from static fixtures; execute fresh MATLAB runs from clean output roots.
14. Do not return a plan-only response. Modify the repository, run the commands and inspect the generated results.

## Required profiles and orthogonal dimensions

The runtime has two orthogonal dimensions:

```text
RunMode
    FIXED_SNR_SWEEP
    GEOMETRY_NETWORK

RadioProfile
    nr_rel18_system_lls_strict
    rel19_extension_strict
    rel20_6g_study_context
```

A Release-20 study may run in geometry mode, but it must remain `Normative=false`. A fixed-SNR run may be either calibration or a bounded connected-control smoke test.

## Target integration package

Consolidate existing production components behind contracts equivalent to:

```text
+sixgr/+integration/
    IntegrationSpecificationProfile.m
    IntegrationCapabilityProfile.m
    RunMode.m
    RadioProfile.m
    IntegrationPlanningResult.m

    ResolvedRunConfiguration.m
    SimulationContext.m
    ComponentRegistry.m

    AbsoluteRadioClock.m
    AbsoluteEventScheduler.m
    EventEnvelope.m
    EventSourcedStateStore.m

    FixedSNREnvironmentAdapter.m
    GeometryNetworkEnvironmentAdapter.m
    ChannelApplicationContract.m

    SlotExecutionPlan.m
    ResourceTransactionManager.m
    CommonAirInterfacePipeline.m
    SampleDomainLinkGraph.m
    MeasurementAvailabilityQueue.m
    GrantCausalityLedger.m
    PacketLineageBridge.m

    IntegrationArtifactExporter.m
    IntegrationAcceptanceRunner.m
    runTwoModeIntegrationValidation.m
    runTwoModeIntegrationAcceptance.m
```

Names may be adapted to the current codebase. The architectural responsibilities may not be omitted.

## One immutable run configuration

Before constructing any runtime object:

```text
source YAML
    ↓
effective inherited YAML
    ↓
resolved canonical YAML
    ↓
immutable staged YAML file
    ↓
SHA-256
    ↓
ResolvedRunConfiguration
```

The run manifest records:

```text
RunID
ScenarioID
RunMode
RadioProfile
RunClass
SourceYAML path/hash
EffectiveYAML hash
ResolvedYAML hash
ExecutedYAML hash
Source Git commit
MATLAB release
5G Toolbox release
all enabled capability profile versions
seed/task plan
output root
```

MATLAB must execute the exact staged resolved YAML. If any hash differs, fail before simulation.

## One SimulationContext

Create one immutable context containing:

```text
ResolvedRunConfiguration
AbsoluteRadioClock
ComponentRegistry
SeedLedger
carrier/BWP/numerology contexts
antenna/array contexts
power/noise reference-plane contexts
state/event stores
resource transaction manager
artifact sink
run and configuration identity
```

No production subsystem may recreate a local carrier, BWP, clock, seed service, power context, waveform engine or receiver implementation.

## Absolute event time and causality

Every event carries:

```text
EventID
EventType
Producer
Consumer
ProducedAt
AvailableAt
ExpiryAt
ConsumedAt
ParentEventIDs
RunID
ConfigurationEpoch
PayloadSHA256
```

Use one absolute time representation based on sample/symbol time. Frame, slot and symbol indices are views of the same clock.

Mandatory causality examples:

```text
CSI measurement
    produced after the relevant received RS samples
    available after measurement/processing/report/decode delay
    consumed only at or after availability

Decoded DCI
    produced after PDCCH receiver completion
    consumed by grant materializer after CRC/RNTI/semantic validation

HARQ feedback
    produced by decoded UCI or typed DTX at the exact K1 opportunity
    consumed by the matching TB/codeword/HARQ process only
```

Any early, stale, wrong-context or future consumption fails with a typed error and produces no state mutation.

## Common event-driven execution graph

The integrated runtime must execute an event graph equivalent to:

```text
1. Advance absolute radio clock.
2. Apply due geometry/mobility/channel/RF-state events.
3. Generate traffic and protocol timer events.
4. Release measurements/control reports whose AvailableAt time has arrived.
5. Project event-sourced UE/cell state.
6. Build immutable scheduler snapshot and eligibility state.
7. Create non-mutating candidate grants.
8. Validate frame/TDD/resource/HARQ/power/beam/measurement constraints.
9. Commit valid control/data/resource transactions atomically.
10. Build PDCCH/SSB/RS/PRACH/PUCCH/PDSCH/PUSCH resource grids.
11. Generate all channels with the canonical waveform engine.
12. Apply per-link channel, absolute power, RF and sample-domain interference.
13. Run synchronization, estimation, equalization and decoding.
14. Emit decoded DCI/UCI/data/measurement events.
15. Update HARQ, MAC, RLC/PDCP/SDAP/RRC and packet lineage.
16. Export raw runtime evidence and incremental artifacts.
```

Never use a same-slot scheduler truth value as if it had already been decoded by the receiving endpoint.

## FIXED_SNR_SWEEP mode

### Purpose

This mode is a controlled link-calibration environment. It is not automatically a connected-network conformance run.

### Required subprofiles

```text
calibration_grant
    Explicit immutable grant is allowed.
    Must use the same PDSCH/PUSCH, waveform, channel, RF and receiver chain.
    Cannot satisfy PDCCH, decoded-grant, scheduler, RRC or network gates.

connected_control_smoke
    Uses decoded PDCCH/DCI, PUCCH/UCI and HARQ.
    Required to prove that the fixed-SNR environment can run the connected chain.
```

### Exact SNR definition

Define one profile-owned reference plane. Record separately:

```text
ConfiguredSNR_dB
AnalyticalInputSNR_dB
MeasuredInputSNR_dB
PostEqualizationSINR_dB
```

Noise variance must derive from:

```text
sample rate
FFT/occupied bandwidth
OFDM normalization
number of ports/layers where applicable
reference-plane signal power
profile-defined thermal/NF behavior
```

Never tune noise using decoded errors or measured post-equalization SINR.

### Fixed-link campaigns

Use the canonical sequential statistics engine. A mandatory point passes only when:

```text
minimum trials satisfied
and either
    minimum errors + adjusted CI-width target satisfied
or
    approved zero-error one-sided upper bound satisfied
```

`max trials reached` without a valid completion rule is incomplete and fails the acceptance campaign.

The full run matrix is in `integration_actual_run_matrix.csv`. Run both DL and UL at selected MCS values and preserve all independent seed/drop identities.

## GEOMETRY_NETWORK mode

### Link authority

Configured SNR is prohibited as the link-quality authority. Derive the received waveform from:

```text
runtime Tx/Rx positions and poses
runtime velocity and signed radial velocity
antenna patterns and beams
pathloss, LOS/NLOS, shadowing and O2I
TDL/CDL/declared channel coefficients
Doppler and phase continuity
absolute transmit power
sample-domain desired and interfering links
receiver NF/noise and RF state
```

### Network/control loop

The live loop must be:

```text
received reference signals
    ↓
measured channel/SINR/RSRP/RSRQ/SRS state
    ↓
configured report construction
    ↓
PUCCH/PUSCH UCI waveform
    ↓
decoded report
    ↓
scheduler MCS/rank/PMI/SRI/TPMI/beam decision
    ↓
decoded DCI and actual grant
    ↓
data waveform
    ↓
ACK/NACK/DTX and next OLLA/HARQ state
```

Geometry may generate the channel. It cannot directly set CQI, beam winner, serving-cell decision or handover outcome.

### Sample-domain interference

For every receiver:

```text
y[n] = sum_l y_l[n] + w[n]
```

Each contribution has an immutable LinkID, timing, carrier/BWP, frequency shift, phase, beam, power, channel and sample hash. The composite sample hash, contribution sum, power ledger and covariance must reconcile.

### Mobility and handover

Use measured and filtered events. Preserve channel/Doppler/phase continuity across mobility updates and serving-cell changes. Handover must include the implemented measurement report, target preparation, target access and RRC completion path for the bounded profile.

## Resource transaction integration

Before any waveform is generated, commit one exact RE ownership map covering:

```text
SSB/PBCH
PDCCH/CORESET
PDSCH and DM-RS/PT-RS
PUSCH and DM-RS/PT-RS
PUCCH
PRACH
CSI-RS/CSI-IM
SRS
TRS
TDD guard/flexible symbols
```

Every ownership row includes absolute time, PRB, subcarrier, logical port, physical port, owner, orthogonality identity and configuration epoch.

Post-waveform collision masking is prohibited.

## Shared waveform and receiver proof

Every run records the implementation/version hashes for:

```text
resource-grid mapper
OFDM/DFT-s-OFDM engine
continuous stream state
channel application
RF front end
synchronizer
channel estimator
receiver/equalizer
soft demapper
channel decoder
```

For the same profile/configuration, these digests must be identical in both modes.

## Mandatory cross-mode reduction tests

Execute every row in `integration_cross_mode_equivalence_vectors.csv`.

### AWGN reduction

Construct a geometry adapter with:

```text
one cell
one stationary UE
zero pathloss or an exactly ledgered constant gain
no shadowing/O2I/blockage
identity channel
no interference
same Tx/Rx arrays and power reference
same payload/grant/resource map
same noise samples
same waveform/RF/receiver state
```

Expected result:

```text
transmit bits equal
resource grids equal
waveform samples equal
received samples equal
decoded bits equal
receiver result digests equal
BLER/BER trial outcomes equal
measured SINR error <= 0.10 dB
```

### TDL reduction

Use the same TDL coefficient samples, timing, Doppler, payload, grant and noise samples in both adapters. Recovered grids and decode outcomes must match. Any difference must be explained by an explicit adapter metadata operation and remain within the declared NMSE tolerance.

## State ownership and no-oracle enforcement

Implement every row in `integration_state_ownership_matrix.csv`.

A connected receiver must never receive:

```text
transmitted bits
transmitted ACK/CSI values
known DCI candidate or CCE
configured winning beam
true channel/CFO/timing for correction
scheduler's original grant
configured post-equalization SINR
```

Diagnostic truth may be exported after the receiver decision, with diagnostic provenance only.

## HARQ, MAC and packet lineage

The common HARQ identity includes:

```text
UE
Direction
ServingCell
ScheduledCell
BWP
HARQ process
Codeword
NDI epoch
TB ID
Grant ID
Coding layout
Attempt
RV
rate-match position hash
configuration epoch
```

The packet lineage must prove:

```text
ArrivedBytes = QueuedBytes + InFlightBytes + DeliveredBytes + DroppedBytes
UnownedBytes = 0
DuplicateDeliveredBytes = 0
ConservationErrorBytes = 0
```

## Determinism and parallel execution

Use immutable TaskIDs and deterministic random substreams.

Required equivalence:

```text
serial execution
parallel execution
shuffled task completion
identical retry
resume after worker loss
```

All must yield the same canonical merged tables and hashes. The same TaskID with different output hashes is a hard failure.

## Failure handling

A run may be:

```text
VALIDATED
QUEUED
RUNNING
COMPLETED
FAILED
STOPPED
LOST_WORKER
RECOVERING
```

Only `COMPLETED` with all mandatory acceptance rules passed can satisfy the integration gate.

Write artifacts to a staging directory and commit the final manifest atomically. A stopped or failed run may preserve partial diagnostics but must never appear complete.

## Actual-run suite

Create schema-valid scenario overlays from the live current scenario schema rather than inventing unrecognised field paths. Do not duplicate the canonical source scenarios.

Mandatory scenarios:

```text
simulator/configs/scenarios/lls_true_snr_sweep_awgn_1ue.yaml
simulator/configs/scenarios/lls_true_geometry_2cell_2ue_200kmh.yaml
```

If the live repository has renamed these files, locate the exact active equivalents and record the mapping in the run manifest.

Execute all `MustRun=YES` rows in `integration_actual_run_matrix.csv`. Conditional rows become mandatory only when their capability profile is currently enabled.

## Mandatory commands

Adapt paths to the current repository, but do not bypass these gates:

```bash
python tests/vectors/integration/verify_integration_pack.py tests/vectors/integration
```

```bash
matlab -batch "setup6GRSimToolkit('Verbose',false); r=runtests('tests','IncludeSubfolders',true,'Name','*Integration*'); assertSuccess(r);"
```

```bash
matlab -batch "setup6GRSimToolkit('Verbose',false); r=runtests('tests','IncludeSubfolders',true,'Name','*TwoMode*'); assertSuccess(r);"
```

```bash
matlab -batch "setup6GRSimToolkit('Verbose',false); s=sixgr.integration.runTwoModeIntegrationValidation('RunMatrix',fullfile(pwd,'tests','vectors','integration','integration_actual_run_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','integration_validation'),'Strict',true); assert(s.Passed);"
```

```bash
matlab -batch "setup6GRSimToolkit('Verbose',false); s=sixgr.integration.runTwoModeIntegrationAcceptance('RunMatrix',fullfile(pwd,'tests','vectors','integration','integration_actual_run_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','integration_acceptance'),'SeedList',[11 23 47 89 131 197],'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/integration/verify_integration_artifacts.py artifacts/integration_acceptance tests/vectors/integration
pytest -q
matlab -batch "setup6GRSimToolkit('Verbose',false); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

Also execute both canonical scenarios through the new WebGUI and verify the exact ConfigRevisionID/RunID/artifact manifest binding.

## Required tests

Implement all 100 rows in `integration_matlab_test_plan.csv`.

Every negative row in `integration_negative_test_vectors.csv` must produce:

```text
ActualError = ExpectedError
WaveformGenerated = false
StateChanged = false
RunCompleted = false
```

## Required acceptance rules

Evaluate all 120 rows in `integration_acceptance_rules.csv` from actual runtime artifacts. Do not hard-code PASS rows.

Hard correctness rules cannot be overridden by good performance. Examples:

```text
wrong grant causality
resource collision
future measurement use
power mismatch
HARQ identity mismatch
packet conservation error
different waveform implementation between modes
```

## Required CSV artifacts

Generate every artifact listed in `desired_integration_csv_contract.csv` from actual runtime data.

The most important outputs are:

```text
integration_run_manifest.csv
integration_config_resolution.csv
integration_component_registry.csv
integration_event_trace.csv
integration_resource_transactions.csv
integration_power_ledger.csv
integration_noise_ledger.csv
integration_acceptance_results.csv

fixed_snr_trials.csv
fixed_snr_bler_curve.csv
fixed_snr_ber_curve.csv
fixed_snr_measured_sinr.csv
fixed_snr_reference_comparison.csv

geometry_mobility_trace.csv
geometry_link_state_trace.csv
geometry_channel_state_trace.csv
geometry_interference_contributions.csv
geometry_measurements.csv
geometry_csi_reports.csv
geometry_scheduler_trace.csv
geometry_grant_trace.csv
geometry_harq_trace.csv
geometry_beam_mimo_trace.csv
geometry_rf_tracking.csv
geometry_packet_lineage.csv
geometry_ue_kpi.csv
geometry_cell_kpi.csv

cross_mode_equivalence.csv
cross_mode_waveform_digest.csv
cross_mode_receiver_digest.csv
cross_mode_noise_power_reconciliation.csv
cross_mode_kpi_comparison.csv
```

## Required PNG artifacts

Generate every image in `desired_integration_image_contract.csv` from the corresponding source CSV.

The dashboard must prominently show:

```text
fixed BLER/BER versus SNR with confidence and independent reference
measured versus configured SNR/SINR
throughput/goodput versus SNR
constellation, EVM, PAPR and PSD

geometry topology and UE trajectory
signal strength along route and error-rate behavior
channel impulse response/PDP and Doppler continuity
PSD, eye diagram and constellation
EVM per RB and per OFDM symbol
antenna/beam pattern and MIMO state
measurement → CSI → MCS/rank timeline
scheduler allocation, HARQ and queue timeline
per-link interference contributions
RF target-versus-measured tracking with zoom regions
power-control convergence
packet latency CDF and handover timeline

cross-mode AWGN/TDL equivalence
power/noise reconciliation
digest equality matrix
acceptance waterfall and failure heatmap
```

No image may be generated from configured placeholders. When source data is unavailable, the run must fail the mandatory artifact gate rather than fabricate a plot.

## Artifact verification

Run:

```bash
python tests/vectors/integration/verify_integration_artifacts.py artifacts/integration_acceptance tests/vectors/integration
```

The verifier checks:

```text
all required files
CSV schemas and unique keys
mandatory status values
all 120 acceptance rules
zero failed/skipped/blocked tests
PNG decode and minimum dimensions
image/source CSV hash binding
semantic-audit rows
```

Do not edit the verifier to accept missing results.

## Performance and trace policy

Provide two trace levels:

```text
FULL_EVIDENCE
    per-event/per-resource/per-link evidence required by acceptance

PRODUCTION_SUMMARY
    bounded summaries for long exploratory runs
```

Acceptance scenarios must use `FULL_EVIDENCE`. If memory pressure occurs, stream to disk or use chunked tables; do not silently discard mandatory evidence.

Record per-stage runtime, peak memory, samples, events and artifact bytes. Hardware-specific runtime budgets are configuration-owned, but a budget miss cannot silently reduce fidelity.

## Completion restrictions

Do not report `COMPLETE` while any of the following remains:

```text
separate production waveform or receiver path per mode
configured SNR labelled measured SINR
configured geometry/channel values filling runtime observations
calibration grant satisfying connected/network gates
configured grant/CSI/ACK/beam/RRC overriding decoded state
future or stale evidence consumed
post-waveform collision masking
hidden channel/power normalization
scalar-only geometry interference
selected/applied precoder mismatch
HARQ identity or rate-position mismatch
packet conservation error
global RNG or nondeterministic merge
partial/stopped run marked complete
fixed and geometry artifact/gate leakage
Release-20 study marked normative
mandatory actual scenario not executed
mandatory test skipped or blocked
required CSV or PNG missing
artifact verifier returning nonzero
full repository regression failing
```

## Definition of done

The integration phase is complete only when:

```text
All 32 integration findings are closed.
All 100 mandatory integration tests execute and pass.
All 120 acceptance rules are evaluated from actual runtime evidence and pass.
Both canonical run modes execute through one common PHY/waveform/receiver stack.
Connected fixed-SNR smoke uses decoded control and UCI.
Full fixed-SNR DL/UL campaigns complete statistically.
Canonical 2-cell/2-UE 200 km/h geometry run completes over all required seeds.
Cross-mode AWGN tests are bit-exact.
Cross-mode TDL tests meet the declared grid/receiver tolerances.
Power/noise/reference-plane ledgers reconcile.
No future/stale/configured-oracle decision remains.
No unauthorized resource collision remains.
No HARQ, precoder, packet-lineage or conservation mismatch remains.
Serial, parallel, shuffled and retried campaigns are canonical-hash identical.
The WebGUI executes and displays the exact selected configuration/run.
Every required CSV and PNG is generated from actual data and verified.
The complete MATLAB and Python regressions pass on the pinned toolchain.
```

## Required final Codex response

Return exactly these sections:

```text
1. Integration phase and issue IDs closed
2. Existing components reused and duplicate paths removed
3. Files added, changed and deleted
4. Final architecture and mode adapters
5. Exact scenario files and resolved configuration hashes
6. Exact commands executed
7. Test counts: passed/failed/skipped/blocked
8. Actual run table with RunID, mode, profile, seeds, duration, status and output path
9. Key numerical results for fixed-SNR mode
10. Key numerical results for geometry mode
11. Cross-mode equivalence results
12. Power/noise/resource/causality/lineage reconciliation results
13. CSV artifact counts, row counts and hashes
14. PNG artifact dimensions, source hashes and image hashes
15. Acceptance-rule summary
16. Remaining technical limitations
17. Final status: COMPLETE, FAIL or BLOCKED
```

`COMPLETE` is invalid if MATLAB was unavailable or any mandatory actual run was not executed.
