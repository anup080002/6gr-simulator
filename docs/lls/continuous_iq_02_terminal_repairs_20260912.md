# Continuous-IQ `_02` terminal audit and repair ledger

## Preserved baseline

`tdd_12db_continuous_iq_02` completed without a restart on 2026-09-12 at
13:27:17 UTC, from clean commit `a4a405f5`. All 58 slots executed. The runner
reported functional PASS after 12258.343 seconds; it did not establish
independent-reference, statistical, FRC, hardware or production qualification.
No original run artifact has been rewritten by these repairs.

The terminal audit counted 1048 CSVs and 292 PNGs. The browser publication
receipt reported zero missing tables/charts (explicitly disabled contracts
remain disabled). Independent SHA-256 checks matched the raw execution
manifest, raw evidence index and all four continuous transmitter IQ files.
Each endpoint has two ports, 445440 samples/port, 58 shared-clock segments,
7.68 MSa/s and 2.35 GHz metadata. These are actual composed transmitter
samples before propagation, not independently regenerated channel waveforms.

## Root causes and repairs

| Issue | Root cause | Repair / acceptance |
| --- | --- | --- |
| DL received PDCCH evidence | Late control completion copied only part of its evidence; later annotation could restore stale planning flags. The gate also discarded data rows before checking contradictions. | Shared receiver-owned whitelist, identity/hash checks, immutable prepared request binding, and data/control consistency gate. Focused tests pass. |
| PMI identity | Re-inferring a bare PDSCH-port codebook index from a composed physical matrix changed the meaning of the reported PMI. | Preserve frozen CSI-port PMI and all composition hashes; export the equivalent PDSCH-port index separately. Four rank-one PMI matrices checked without changing waveform weights. |
| CSI SINR | Selected-PMI receiver-objective estimate was labeled as post-equalization measurement. | Explicit CSI-objective source/domain/role, separate reference-measured domain; AMC still accepts the measured-reference-derived objective. |
| CDL applicability | Readiness reduction defaulted missing internal `channel.model` to AWGN even when resolved YAML selected CDL. | Read the explicit YAML model authority; missing authority no longer grants AWGN exemptions. |
| Terminal receipt | Functional PASS but publication-unqualified diagnostic was stamped FAIL. | Successful unpublished finalization has PASS and `PublicationQualified=false`; it cannot advance the qualified-publication pointer. Failed functional/artifact results still fail. |
| QCL/TCI | Main shared receiver had no materialized state/codepoint/source binding or consumption evidence. | Explicit YAML preinitialized state 17/codepoint 0, actual TRS resource IDs and received timing reference, decoded DCI binding, bounded PDSCH DM-RS timing-prior consumption. Unit and enabled-scenario checks pass; final main-runtime qualification pending. |
| TRS blocker | Empty blocker on a committed observation was treated as missing and filled with a pre-observation default. | Preserve committed row values, including an authoritative empty blocker; retain actual failures and pending rows. Focused verification passed. |

QCL scope is **Type-A average-delay transfer**, not full Type-A parameter
qualification, Type-D spatial receive-beam qualification, unified TCI, UL TCI
or simulated RRC/MAC-CE activation. Initialization is explicitly labeled
`lls_preconfigured_higher_layer_context`. The receiver still measures timing
from actual PDSCH DM-RS; it receives no channel-delay truth. A scalar
`QCLAccuracy` is not manufactured. Delay residual and source/consumption
evidence are the applicable numeric outputs.

The CSI basis and QCL assumptions follow TS 38.214 sections 5.2.2.2.1 and
5.1.5. Receiver search radius and maximum reference age are declared simulator
receiver settings, not universal 3GPP-prescribed constants.

## Verification and next steps

Eight focused MATLAB tests passed in
`runLLS12dBRepairTests`: lifecycle, received grant clock, grant binding gate,
CSI scheduling authority, CDL readiness, two-port spatial PMI, QCL timing
transfer and correlation-not-QCL separation. The first Python plotting run
passed 83 tests and the final plotting rerun also passed 83 tests. Five
additional integration checks passed: enabled QCL scenario, shared data
physical queue, shared PDCCH clocks, TRS resource timing and TRS delivery.
Two final checks passed: committed TRS metadata and actual TRS receive
completion without repeating TX/RF/channel execution. That is 15 focused
MATLAB checks in total. Receipts are retained in
`docs/lls/evidence_20260912/`. No `testAll` or E2E campaign was launched.

1. Complete focused integration checks and retain test receipts.
2. Commit and push the repairs on the existing private `main` branch.
3. Launch exactly one new 58-slot configured-12-dB validation.
4. Audit original runtime CSV/PNG/IQ/hash/terminal evidence; do not reconstruct
   missing runtime fields from planned configuration.
5. Record the verdict, commit/push documentation, create a new local Git
   bundle and leave tracked source clean. Preserve all local run outputs.

Report-finalization performance remains a separate follow-up: `_02` invoked
four full chart-render passes and wrote a large MAT artifact. No integrity
check or artifact has been disabled to hide that cost. Single-carrier
400 MHz at 7 GHz, higher-order experimental QAM, 30-dB validation and
instrument playback remain subsequent work after this bounded run is accepted.
