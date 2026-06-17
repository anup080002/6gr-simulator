# LLS Truth Re-Architecture Plan

## Purpose

This plan fixes the waveform LLS truth path so that:

- every reported live value comes from the same canonical DL/UL processing flow
- no major result surface is produced by a disconnected sidecar while pretending to be part of the active PHY chain
- bidirectional execution is truly coupled at the TTI or slot level
- run status, database state, and web state remain consistent and truthful

This document is based on the validated issues observed in `run_id=9` and the current implementation under:

- `+sixgr/+truth/runWaveformLinkBundle.m`
- `+sixgr/+truth/exportLLSLiveSignalChainTables.m`
- `+sixgr/+truth/exportLLSLiveDerivedTables.m`
- `+sixgr/+truth/exportLLSLiveMobilityTables.m`
- `+sixgr/+link/runDLPDSCHThroughput.m`
- `+sixgr/+link/runULPUSCHThroughput.m`
- `+sixgr/+link/computeLinkAdaptationDecision.m`
- `+sixgr/+link/resolveWidebandCQI.m`
- `+sixgr/+system/buildLargeScaleStateCache.m`
- `apps/lls_web_dashboard.py`

It is also now aligned against the execution model used in the Vienna simulator under:

- `C:/Anup/6gsimulation/vienna/simulate.m`
- `C:/Anup/6gsimulation/vienna/+simulation/LocalSimulation.m`
- `C:/Anup/6gsimulation/vienna/+simulation/SimulationSetup.m`
- `C:/Anup/6gsimulation/vienna/+simulation/ChunkSimulation.m`
- `C:/Anup/6gsimulation/vienna/+simulation/+results/TemporaryResult.m`
- `C:/Anup/6gsimulation/vienna/+simulation/+postprocessing/PartialPP.m`
- `C:/Anup/6gsimulation/vienna/+networkElements/+ue/User.m`
- `C:/Anup/6gsimulation/vienna/+feedback/Feedback.m`
- `C:/Anup/6gsimulation/vienna/+feedback/LTEDLFeedback.m`
- `C:/Anup/6gsimulation/vienna/+scheduler/Scheduler.m`
- `C:/Anup/6gsimulation/vienna/+linkQualityModel/linkQualityModel.m`
- `C:/Anup/6gsimulation/vienna/+linkPerformanceModel/LinkPerformanceModel.m`

## Vienna-Derived Design Decisions

The Vienna code confirms several architecture choices that our fix plan should adopt more explicitly.

### 1. Separate setup from execution

Vienna uses a clean split:

- `SimulationSetup` creates topology, users, base stations, movement, and small-scale traces
- `ChunkSimulation` owns the actual slot loop

We should adopt the same split:

- one preparation stage that builds immutable or slowly varying simulation state
- one canonical runtime that owns every TTI or slot transition and every published result

This is better than our current pattern where orchestration, sidecar export, and partial publishing are mixed together inside `runWaveformLinkBundle.m`.

### 2. Separate segment-boundary updates from slot updates

Vienna does not recompute everything every slot. In `ChunkSimulation`, it:

- updates cell association and handover only when a new segment starts
- updates macroscopic state at segment boundaries
- updates small-scale fading, scheduler state, feedback, and link results every slot

Our fix plan should follow that pattern directly:

- geometry, LOS, pathloss, shadowing, association, and handover are segment-level state
- waveform, channel realization, CSI, decoding, ACK/NACK, HARQ step, and publication are slot-level state

This will reduce inconsistency and keep mobility and serving-cell logic tied to real state transitions.

### 3. Every slot should create one authoritative trace object

Vienna uses `TemporaryResult` as the canonical per-slot container, and the postprocessor extracts every saved result from that trace.

That is the right structural pattern for us:

- every slot should produce one authoritative `SlotTrace`
- raw rows, summary rows, map state, and live DB payloads should be built from that `SlotTrace`
- nothing should bypass it through a sidecar path

### 4. Feedback must be a first-class runtime object with delay

Vienna stores feedback on the UE object and uses an explicit delayed feedback buffer in `feedback.Feedback`.

We should adopt that idea, but extend it beyond Vienna:

- CQI, PMI, RI, CRI, ACK/NACK, and CSI payloads should live in an explicit feedback state object
- feedback delay must be modeled as part of the runtime loop
- BS adaptation must consume delayed feedback objects, not locally recompute adaptation in isolation

### 5. Scheduler signaling should be attached to runtime entities, not reconstructed later

Vienna attaches scheduler signaling to the UE and BS objects in the same slot where scheduling occurs.

Our plan should do the same:

- grant state should be attached to the canonical runtime state in the slot where it is issued
- PDSCH, PUSCH, HARQ, control, and web reporting should consume the same grant object
- we should not infer grant-like behavior after the fact from decoded raw rows

### 6. Link quality and link performance should stay separate

Vienna keeps:

- `linkQualityModel` for post-equalization SINR generation
- `LinkPerformanceModel` for BLER and throughput mapping

We should preserve this conceptual separation in the refactor:

- estimation, equalization, SINR, CSI, and channel diagnostics belong to a link-quality stage
- TBS success, BLER, throughput, ACK/NACK, and HARQ process updates belong to a link-performance stage

That separation will make our exports cleaner and our diagnostics easier to validate.

## Vienna Limits We Should Not Copy

The Vienna code is useful, but it also shows limits that we must not carry into the new truth path.

### 1. Vienna is primarily DL-centric

The current Vienna execution path is centered on `scheduleDL`, DL feedback, DL LQM, and DL throughput extraction. The UL classes exist in places, but the main runtime loop is not a full coupled DL+UL+HARQ truth loop.

So we should copy Vienna's slot-trace architecture, but not inherit its DL-only runtime bias.

### 2. Vienna feedback is still partly abstracted above the physical control transport

Vienna computes feedback objects directly from link state. That is structurally much better than our current sidecar logic, but it is still not the same as a full NR control-transport realization.

Our plan should therefore:

- use explicit feedback objects like Vienna
- but also connect them to actual control timing and HARQ process state in the runtime chain

### 3. Vienna is postprocessor-first, not realtime DB-first

Vienna saves per-slot trace state and combines it afterward with postprocessors. That is excellent for truthfulness, but our environment also needs realtime MySQL and web updates.

So our architecture should be:

- `SlotTrace` first, like Vienna
- realtime DB/web publish second, derived from `SlotTrace`
- never the reverse

## Current Root Problems

### 1. Execution model must stay on the coupled SlotTrace path

Status: patched in the active LLS runtime.

The active multi-user truth scenarios now use `execution_model: slot_coupled_truth`.
Strict, no-proxy, or truth-tagged multi-user scenario configs are rejected if they
attempt to use `execution_model: independent_link_sweep`.

The coupled runtime now emits:

- `reports/csv/run_state.csv`
- `reports/csv/slot_trace.csv`
- `packet_flow/csv/slot_trace.csv`

The SlotTrace rows are the canonical parent for DL scheduling, UL scheduling,
HARQ observations, control gating, mobility updates, and waveform PHY trial rows.
Legacy sweep-style helpers may remain for non-truth reference scenarios, but they
are not allowed for strict/truth multi-user execution.

### 2. Live reporting is built from partial and inconsistent sources

Current live tables are produced from three different categories of data:

- raw PHY trial rows
- derived summary tables built from partial raw slices
- mobility and coverage sidecar tables built from a separate large-scale preview path

Consequences:

- `live_stage_status.csv` can be stale
- coverage and user-performance tables can be empty while DL raw rows exist
- map CQI or SINR can disagree with current DL trial CQI or SINR
- HARQ and beam tables may exist in the DB but appear inconsistent with stage reporting

### 3. Several exported metrics were not tied tightly enough to actual PHY state

Examples already seen in `run 9`:

- stale stage file
- wrong fixed-beam reporting
- unreliable DL Doppler export
- wrong DL NMSE definition or sign
- stale run status in `sim_runs`
- partial DL-only persistence while UL never materialized

### 4. The database and run lifecycle are not authoritative yet

Current failure mode:

- MATLAB process can die or stall
- `sim_runs.status_text` can remain `running`
- web keeps treating an old run as live

This is worsened right now by an infrastructure blocker:

- the `C:` drive is full, which is preventing clean DB temp writes and status updates

## What Must Be True After The Fix

The target truth LLS path must obey these invariants:

1. One canonical frame or TTI state drives all outputs.
2. Every major result table is either:
   - derived from canonical frame state, or
   - explicitly labeled as preview or sidecar.
3. DL control, DL data, UE RX, CSI acquisition, ACK or NACK generation, UL control, UL data, and HARQ update all belong to one continuous loop.
4. Stage reporting is a direct reflection of actual execution progress, not a guessed overlay.
5. Run status in MySQL becomes authoritative and self-healing.
6. Web pages show only what the current run has actually produced.

## Target Architecture

### A. Canonical LLS Runtime

Replace the current sweep-first and sidecar-heavy truth flow with a single canonical runtime. Structurally, this should look much closer to Vienna's `SimulationSetup -> ChunkSimulation -> TemporaryResult/Postprocessor` split, but extended for realtime publication and full bidirectional truth.

1. Simulation setup
   - resolve config
   - build topology
   - place UEs
   - initialize mobility state
   - initialize segment boundaries
   - initialize large-scale state cache
   - initialize small-scale trace or channel providers
   - initialize CSI state
   - initialize HARQ state
   - initialize scheduler or grant state
   - initialize reporting buffers
   - initialize DB heartbeat and stale-run watchdog state

2. For each SNR point
3. For each slot or TTI
4. If segment boundary is reached
   - update mobility-derived segment markers
   - refresh large-scale state
   - refresh serving-cell association
   - process handover or reselection effects
   - clear or preserve feedback and HARQ buffers according to policy
5. For each active UE or scheduled allocation
   - run DL control and reference signals for the slot
   - run DL data transmission and UE reception
   - compute UE-side measurements from the actual received state
   - generate CSI, PMI, RI, CRI, CQI, ACK, NACK, and UCI as canonical feedback objects
    - update BS-side link adaptation and HARQ process state from those feedback objects
    - run UL control and UL data using the same canonical state
6. finalize one authoritative slot state object
7. publish a slot-consistent DB snapshot from that slot state object

The important design rule is:

- no map telemetry
- no HARQ summary
- no beam summary
- no CQI or user-performance snapshot

may be built outside the slot state that produced the current raw PHY rows.

### B. Canonical Runtime State Objects

Introduce explicit state objects or structs. Vienna's `TemporaryResult` should be treated as the closest existing reference pattern for how these objects should be shaped and owned.

#### RunState

- run id
- scenario id
- start time
- status
- current phase
- current SNR index
- current slot
- current UE index
- heartbeat time

#### TopologyState

- sites
- sectors
- cells
- TRPs
- UE geometry
- map anchor mode

#### MobilityState

- UE positions
- headings
- speeds
- serving cell history
- reselection history

#### LargeScaleState

- d2d
- d3d
- LOS
- shadow
- pathloss
- beam index
- beam gain
- rx power
- rsrp

#### DLState and ULState

Per slot and per UE or grant:

- scheduled resources
- modulation
- code rate
- MCS
- TBS
- layers
- precoder
- waveform preview
- tx metadata
- rx metadata
- equalization metadata
- decoding metadata
- CRC outcome
- scheduler signaling or grant signaling
- control timing context

#### FeedbackState

- CQI
- PMI
- RI
- CRI
- CSI payload bits
- ACK or NACK
- feedback validity
- application slot

#### HARQState

- process id
- NDI
- RV
- redundancy version history
- new data flag
- retransmission count
- outstanding TB metadata

#### LivePublishState

- artifact versions
- last published slot
- last published SNR point
- per-table row counts
- DB commit state

#### SlotTrace

This is the most important object and should become the single source of truth for publishing.

Minimum contents:

- slot index
- segment index
- UE index or scheduled allocation id
- serving cell and beam
- DL control state
- DL waveform and RX state
- feedback state
- UL control state
- UL waveform and RX state
- HARQ process update
- map-visible serving metrics
- publish-ready raw and summary row payloads

## Concrete Refactor Plan

### Phase 0: Infrastructure And Integrity Prework

#### 0.1 Free disk space and stabilize temp storage

Problems:

- MySQL temp writes are failing because `C:` is full
- stale status updates can no longer be committed reliably

Actions:

- clear temporary run artifacts and stale local debug dumps
- remove obsolete DB-backed large blob artifacts that are no longer needed
- move MySQL temp directory if necessary
- add free-space preflight guard before run start

Acceptance:

- `sim_runs` and `sim_artifacts` writes succeed reliably
- run finalization updates never fail because of temp space

#### 0.2 Add stale-run watchdog

Actions:

- add a heartbeat timestamp in `sim_runs`
- if heartbeat is older than threshold and MATLAB PID no longer exists, auto-mark run as `failed` or `aborted`
- show stale-run warning on the web

Acceptance:

- no dead run remains `running`

### Phase 1: Replace Independent Link Sweep With Canonical TTI Orchestrator

#### 1.1 Introduce a new orchestrator

Add a new runtime entry under `+sixgr/+truth` or `+sixgr/+lls6g/+runtime`.

Suggested new module:

- `+sixgr/+truth/runWaveformLLSTTISession.m`

Suggested companion modules, mirroring Vienna's separation of responsibilities:

- `+sixgr/+truth/setupWaveformLLSSession.m`
- `+sixgr/+truth/updateLLSSegmentState.m`
- `+sixgr/+truth/finalizeLLSSlotTrace.m`
- `+sixgr/+truth/publishLLSSlotTrace.m`

Responsibilities:

- own the slot loop
- own the SNR loop
- own persistent state
- call DL, feedback, UL, HARQ, and reporting in-order
- keep slot execution and publication separated, like Vienna's runtime vs postprocessor separation

#### 1.2 Keep current collectors only as legacy mode

Current collectors in `runWaveformLinkBundle.m` should not remain the default truth path:

- `localCollectTrialsAcrossSweep`
- `localCollectMultiUserLinkTrialsAcrossSweep`
- `localCollectSingleUserLinkTrialsAcrossSweep`
- `localCollectInterleavedMultiUserLinkTrialsAcrossSweep`

They can remain only as:

- benchmark mode
- legacy compatibility mode
- non-truth debug mode

Truth mode must route through the new slot orchestrator.

`runWaveformLinkBundle.m` should become:

- a compatibility entry point
- a mode selector
- a wrapper around the new orchestrator

not the place where the truth chain, sidecar exporters, and partial live publishing are all mixed together.

Acceptance:

- a strict truth run does not use `independent_link_sweep`
- DL and UL publish through one canonical `SlotTrace`
- `run_state.csv` reports the same SlotTrace row count as `slot_trace.csv`

### Phase 2: Make Every Major Result A Child Of Canonical Slot State

#### 2.1 Raw tables

The following must come directly from slot execution:

- `dl_pdsch_trials.csv`
- `ul_pusch_trials.csv`
- `pbch_trials.csv`
- `prach_trials.csv`
- `pdcch_trials.csv`
- `pucch_trials.csv`
- `srs_trials.csv`
- `trs_trials.csv`

Each row must include:

- slot
- frame
- UE
- serving cell
- SNR context
- link adaptation context
- HARQ context when relevant
- feedback context when relevant

#### 2.2 Signal-chain tables

Current file:

- `exportLLSLiveSignalChainTables.m`

Problem:

- it projects traces from trial tables after the fact
- Vienna's `TemporaryResult` pattern shows that the correct direction is the reverse: capture once in the slot, then extract or project later

Target:

- build these tables directly from canonical slot state
- allow postprocessing-style extraction from `SlotTrace`, but never from disconnected sidecars

Required tables:

- waveform
- modulation and demodulation
- channel estimation
- equalization
- CSI feedback
- channel state
- constellation

Each should carry:

- `SourceKind = canonical_slot_state`
- exact slot and UE references

#### 2.3 Derived tables

Current file:

- `exportLLSLiveDerivedTables.m`

Problem:

- derived tables can publish from incomplete inputs

Target:

- derived tables are refreshed only from the same canonical aggregate state that produced the current raw slot set
- no empty user-performance table while coverage snapshot is full

Acceptance:

- `live_user_performance_snapshot.csv` and `live_coverage_layer.csv` cannot be empty when sufficient raw slot data exists

### Phase 3: Couple Mobility, Serving Cell, CQI, Beam, And Map To The Actual Chain

#### 3.1 Mobility must stop living as a detached preview path

Current file:

- `exportLLSLiveMobilityTables.m`

Problem:

- mobility and serving traces are generated by a large-scale sidecar, not from the actual active waveform slot state

Target:

- mobility update remains reusable
- but map-facing serving cell, CQI, SINR, throughput, and RSRP must be emitted from canonical slot state

Keep only these as reusable services:

- layout generation
- UE movement model
- large-scale cache update

Do not keep:

- separate sidecar CQI
- separate sidecar serving selection presented as if it were the same as active link trials

This is directly informed by Vienna's segment model in `ChunkSimulation`: association and handover are runtime state transitions, not reporting side jobs.

#### 3.2 Beam and cell selection

Target behavior:

- serving cell selection and reselection use the actual large-scale and feedback state used by the current slot
- beam selection tables reflect the actual selected beam used in the active chain
- `fixed_first_beam` means selected beam remains fixed unless policy explicitly changes

Acceptance:

- raw trial beam fields and beam summary fields agree
- map-serving cell and raw-slot serving cell agree for the same slot

### Phase 4: Turn HARQ Into A Real Process Loop

Current problem:

- live HARQ tables are observational summaries of raw decode outcomes

Target:

- a real HARQ process state machine

Required process fields:

- HARQ process id
- NDI
- RV
- new-data versus retransmission
- TB size
- original slot
- feedback slot
- ACK or NACK
- retransmission count
- final success or drop

Where to integrate:

- before DL new-data generation
- after UE decode
- before UL feedback control
- before next scheduling decision

Acceptance:

- HARQ tables no longer read like post-hoc analytics only
- they represent a real process timeline

### Phase 5: Close The Feedback Loop Properly

Current problem:

- link adaptation decision is computed locally from metrics in MATLAB, without a true transport of feedback through a control loop

Target:

- feedback objects created at UE RX
- these objects are timestamped and fed into BS adaptation logic with realistic delay
- DL and UL control carry or schedule the relevant responses

Required feedback entities:

- CQI
- PMI
- RI
- CRI
- ACK or NACK
- scheduling request if used

Acceptance:

- CQI or PMI used by the BS can be traced to a specific prior UE feedback object
- web tables can show feedback delay and application slot

### Phase 6: Make Stage And Run Status Authoritative

#### 6.1 Stage status

`live_stage_status.csv` must be generated from canonical runtime state only.

It must include:

- current phase
- current slot
- current SNR point
- current UE
- DL progress
- UL progress
- feedback progress
- HARQ progress
- artifact readiness

No inference-only fallbacks for truth mode.

#### 6.2 Run finalization

At run end:

- flush all outstanding artifacts
- write final summary
- mark `sim_runs.status_text = completed`
- persist a final integrity record

At failure:

- capture failure report
- persist status
- surface failure on web

### Phase 7: Web Contract Cleanup

The browser should consume only two classes of table:

1. canonical live slot tables
2. post-run summary tables

It should stop guessing semantic readiness from sparse artifacts.

Required web changes:

- distinguish `live_slot`, `live_aggregate`, and `post_run_summary`
- clearly label any large-scale preview layer if used
- do not display empty summary blocks as if data is missing from MATLAB when the source is just not applicable yet
- tie result tabs to artifact class and execution phase

### Phase 8: Validation Matrix

#### 8.1 Unit validations

- fixed-first-beam remains fixed in raw and summary tables
- Doppler estimate is either sane or explicitly unavailable
- NMSE sign and definition are consistent across DL, TRS, and SRS exports
- live stage status reflects real artifact and slot progress
- user-performance and coverage tables populate when raw slot data is present
- HARQ process tables contain real process ids and retransmission semantics

#### 8.2 Integration validations

- 1 UE DL-only truth run
- 1 UE UL-only truth run
- 1 UE bidirectional truth run
- 4 UE bidirectional truth run
- 100 UE macro truth run

#### 8.3 Web and DB validations

- every result section has at least one truthful source table when the chain has reached that phase
- map and raw slot tables agree for the same slot and UE
- stale runs are auto-demoted from `running`

## What Must Move Into The True Chain

The following should no longer live as disconnected logic:

- map CQI
- map SINR
- map serving-cell state
- map throughput
- HARQ observation tables
- signal-chain projections that are not traceable to real slot state
- CSI-RS summaries that are only shared-path approximations

They may remain as helper calculations, but only if:

- they are explicitly labeled `preview` or `derived_preview`
- they are not presented as the same as the active chain

## Suggested File-Level Execution Order

### Step 1

Stabilize infrastructure and lifecycle:

- `apps/lls_web_dashboard.py`
- DB lifecycle helpers
- run heartbeat and stale-run cleanup

### Step 2

Introduce canonical orchestrator:

- new `+sixgr/+truth/runWaveformLLSTTISession.m`
- adapt `runWaveformLinkBundle.m` to call it in truth mode

### Step 3

Refactor DL and UL runtime interfaces so they can consume and emit slot state:

- `runDLPDSCHThroughput.m`
- `runULPUSCHThroughput.m`
- associated PHY helpers

### Step 4

Integrate feedback and HARQ:

- `computeLinkAdaptationDecision.m`
- `updateLinkAdaptationState.m`
- new HARQ process state helpers

### Step 5

Rebuild live exports from canonical state:

- `exportLLSLiveSignalChainTables.m`
- `exportLLSLiveDerivedTables.m`
- `exportLLSLiveMobilityTables.m`

### Step 6

Rework browser pages once canonical artifacts exist:

- `apps/lls_web_dashboard.py`

## Immediate First Fixes To Land Before Rerunning Truth

1. Free disk space and restore reliable DB updates.
2. Make stale-run cleanup authoritative.
3. Keep validation guard coverage for truth use of `independent_link_sweep`.
4. Keep live-stage export aligned with `reports/csv/slot_trace.csv`.
5. Ensure per-user and per-slot live aggregates continue to publish from the SlotTrace-backed runtime object.
6. Re-run a small 4-UE bidirectional truth case before any 100-UE truth rerun.

## Rerun Policy

Do not use `run 9` for scientific conclusions.

The next valid evaluation sequence should be:

1. small bidirectional truth run
2. validate all live tables and map agreement
3. medium multi-user truth run
4. validate HARQ and feedback loop
5. full 100-UE truth run
6. post-run audit against the same checklist used here

## Definition Of Done

The re-architecture is complete only when:

- no major result on the web depends on a disconnected sidecar while pretending to be active-chain truth
- DL and UL execute in one canonical slot loop
- HARQ is a real process loop
- map telemetry, beam, CQI, SINR, and user performance match the same slot state
- all run statuses finalize correctly in MySQL
- the browser renders the same truth the database stores

## Actual LLS Implementation, Not Labels

Truth/status fields remain required, but they are only acceptance summaries. They must never replace implementation evidence. A block is implemented for a scenario only when the real runtime path executed, the expected waveform/grid/bit/decoder/channel artifacts were produced, numerical sanity checks passed, and a DUT-vs-reference path either passed or failed closed as unavailable.

The active implementation-proof surface is now the validation harness under `+sixgr/+validation/LLSValidationHarness.m` with companion modules for block evidence, reference comparison, invariants, function coverage, bypass detection, and report writing. That harness must emit:

- `reports/csv/phy_block_validation_matrix.csv`
- `reports/csv/dut_reference_comparison.csv`
- `reports/csv/phy_value_invariant_checks.csv`
- `reports/csv/implementation_function_coverage.csv`
- `reports/csv/real_phy_path_evidence.csv`
- `reports/csv/oracle_proxy_fallback_detector.csv`
- `reports/csv/generated_value_plausibility_audit.csv`
- `reports/csv/lls_phy_outcome_summary.csv`
- `reports/csv/lls_link_performance_summary.csv`
- `reports/csv/lls_block_correctness_summary.csv`
- `reports/csv/lls_reference_comparison_summary.csv`
- `reports/csv/lls_real_implementation_coverage_summary.csv`

Hard-fail rules for this phase:

- no pass row may rely on label/config/status evidence only
- no expected PHY/MAC/RF function may be treated as called without runtime call evidence
- no enabled data-channel pass may exist without decoder and CRC evidence
- no proxy, fallback, skipped, or bypass path may contribute to `ImplementationPass=true`
- no suspicious numerical output may pass silently when the invariant table or comparison table says otherwise

The first section of every final implementation report must be `Actual LLS Implementation Verdict`, and it must classify the run as one of:

- `full actual LLS`
- `partial actual LLS`
- `label/proxy simulator`
- `failed evidence run`
