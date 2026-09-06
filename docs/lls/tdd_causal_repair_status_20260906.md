# TDD causal repair status — 2026-09-06

This is a bounded repair record, not production qualification or a claim that
all previous CSV/PNG values are correct. Historical outputs have not been rewritten.

## Diagnoses and changes

| Issue | Evidence and repair | Verification |
| --- | --- | --- |
| PRACH logical ports replaced physical channel dimensions | The stopped `tdd_12db_reciprocity_truth_20260906_103339` run rejected one Msg1 waveform column at a two-element CDL transmitter. Dynamic retargeting now reads actual channel input/output counts and retains the explicit complex port-to-element map. | Regression failed before the change. Afterward, reduced logical-port execution equals explicit element-domain projection, including unequal endpoint arrays and both direction transitions. |
| RA retained stale directional clock views | The reused-channel four-step test decoded access successfully but returned different DL/UL clock positions for one TDD object. RA now publishes the advanced canonical state to both direction views after every stage. FDD retains independent states. | `testTDDCausalFourStepRARuntimeTiming` passes with an already materialized channel, real Msg1–4/RRC setup waveforms, and final shared-clock assertions. |
| SSB ledger substituted PBCH SINR | `MeasuredSINR_dB` could override the actual `SS_SINR_dB` while the ledger described an SSS measurement. SSB now binds only SS-SINR; missing SS-SINR remains unavailable. | Source-field and missing-measurement assertions in `testReferenceSignalCausalProducersConsumers` pass. |
| A crashed RA producer appeared as simplified PRACH | The failed run had `Status=CRASH`, `Crash=0`, and a simplified-execution classification. The producer now sets Crash; canonical annotation preserves the execution failure and does not claim a receiver observation. | `testPRACHRuntimeFailureEvidence` passes. |
| FFT-window calibration cache omitted receiver placement | A calibration cached at CP fraction 0.25 was reused at 0.75 and differed from a fresh calculation. Cache authority now includes executed OFDM arguments, slot and noise-probe inputs. Receiver metadata records and forwards the actual CP fraction. | Before-fix numerical regression failed. Afterward, `testOFDMReceiverWindowEvidence` and `testOFDMWindowingCallers` pass, including exact Toolbox comparison and cached-versus-fresh calibration. |
| Receiver sampling metadata ignored executed options | A nondefault 1024-point/15.36 MHz transform executed correctly but reported the carrier-default FFT metadata. Metadata resolution now forwards the executed FFT size, sample rate and carrier phase-compensation options. | Expanded `testOFDMReceiverWindowEvidence` failed before the change and passes after it, including exact Toolbox grid/metadata comparisons. The combined focused MATLAB batch also passes. |
| Per-symbol EVM used averaged per-RE ratios | Chart aggregation could average ratios and pool repeated symbol indices across slots. It now computes RMS and peak percentages from summed reference/error energies, retaining direction/UE/frame/slot/TB/layer/codeword. | Unequal-reference-power, repeated-slot, source-alias, single-observation and exact-zero regressions pass. |
| Throughput/SINR pooled independent DL/UL trials | Equal SINR values were collapsed into one mean, losing MCS/rank/CRC and source identity. Individual measured trials are now preserved; scheduled TB bitrate and delivered goodput are separate series. | Equal-SINR DL/UL, failed-CRC zero goodput, configured/geometry-only SINR rejection and proxy rejection regressions pass. |

## Retained logs

- `logs/tdd_logical_port_retarget_before_fix_20260906.log`
- `logs/tdd_logical_port_sssinr_after_fix_20260906.log`
- `logs/tdd_reused_channel_ra_before_clock_fix_20260906.log`
- `logs/tdd_reused_channel_ra_after_clock_fix_20260906.log`
- `logs/tdd_mapping_required_regressions_20260906.log`
- `logs/ofdm_fft_window_before_fix_20260906.log`
- `logs/ofdm_fft_window_after_fix_20260906.log`
- `logs/ofdm_sampling_metadata_before_fix_20260906.log`
- `logs/tdd_prelaunch_focused_regressions_20260906.log`

The completed required PHY/export batch ran `testPRACHRuntimeFailureEvidence`,
`testConfig`, `testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`,
`testE2E_FastVsTruth`, and `testE2E_TruthPacketSemanticCampaign`.
The two Python CSV-audit modules passed 98 tests. The full `testAll` suite has
not been run for this patch; broad qualification remains unproven.

The later `tdd_prelaunch_focused_regressions_20260906.log` completed with
`TDD_PRELAUNCH_FOCUSED_REGRESSIONS_PASS`. It includes both OFDM-window tests,
dynamic TDD reciprocity, reused-channel four-step RA, PRACH failure evidence,
reference-signal producer/consumer binding, config and DL/UL/reference tests,
and both E2E truth/proxy and packet-semantic tests.

## Additional measured plots

The output contract now includes separate **PDSCH EVM per symbol** and
**PUSCH EVM per symbol** CSV/PNG pairs alongside the previous combined EVM,
subcarrier and layer views. Throughput versus measured SINR retains individual
DL/UL scheduled-TB bitrate and goodput observations with MCS, layers, CRC,
SINR source/domain and source-row identity. These are adaptive operating points,
not a controlled-SINR sweep or a fitted capacity curve. The code does not branch
on TDD/FDD; both use the canonical executed trial/sample tables.

For paired samples in each explicitly identified bucket, RMS percent is
`100*sqrt(sum(abs(eq-ref)^2)/sum(abs(ref)^2))`; peak percent is
`100*sqrt(max(abs(eq-ref)^2)/mean(abs(ref)^2))`. This follows the
[average-reference-power EVM normalization](https://www.mathworks.com/help/comm/ref/comm.evm-system-object.html),
not an arithmetic mean of per-RE ratios. It is not a full RF-conformance EVM test.

Important retained-run limitation: `deriveModulationTrackingMetrics` saved only
the first 512 constellation samples per trial. The reviewed run therefore
contains DL symbols 3–5 (six slots, 3072 samples) and UL symbols 1–2 (one slot,
512 samples). All saved samples are included in the aggregate CSVs; missing
symbols are not reconstructed. Full-allocation per-symbol EVM requires a
future producer capture/aggregation change and a fresh run, not relabeling these
previews as complete. PNGs may downsample dense series for display; CSVs retain
every computed bucket and its sample count.

`tools/export_lls_observed_data_plots.py` creates a separate saved-data review,
with source/output SHA-256 provenance and no modification of the retained run.
Unavailable charts are recorded in the review manifest, not manufactured as
numeric PNGs. The same chart producers are registered for normal WebGUI contract
materialization. A running Python server must load the updated module before
serving a newly materialized run.

Independent MATLAB verification (`tools/verifyLLSObservedEVM.m`) passed all
2111 emitted buckets against `comm.EVM` using the retained raw complex samples:
18 DL-symbol, 2 UL-symbol, 20 combined-symbol, 2064 subcarrier and 7 layer
buckets. See `logs/observed_evm_toolbox_crosscheck_20260906.log` and the final
repeat in `logs/observed_evm_toolbox_crosscheck_final_20260906.log`.
The focused Python set passed **202 tests** covering these plots, contract
materialization/applicability, visual auditing, CSV semantics and exhaustive
run auditing. The final six CSV/PNG pairs and source/output hashes are in
`results/lls/qualification_working/observed_plot_review_20260906_03/`.
No 25 dB scenario or new full PHY scenario was launched for this plot addition.

## Remaining gates before claiming success

1. Repeat a fresh short TDD scenario through
   the WebGUI from a recorded source revision. Do not rebuild the stopped run.
2. Inspect executed access, control, SRS/CSI and data rows, not just their counts.
   Verify CRC, causal timing, selected beam/precoder, MCS/rank decisions, physical
   received powers and noise/interference denominators.
3. Audit every output CSV (including the first five rows), semantic availability,
   and the saved-array provenance of each PNG. Close outstanding Top-50 evidence
   gaps and preserve the previously implemented outputs as well.
4. Do not treat the legacy packet-semantic test as a throughput qualification:
   it warns that UL traffic was generated but none was delivered. Investigate
   its scheduler/traffic conditions before crediting end-to-end data coverage.
5. Baseline transmit windowing/WOLA/filtering remain disabled by resolved YAML.
   Nonzero shaping still needs a separately configured, measured spectral and
   timing verification, continuous composite waveform export, and VSG-specific
   import validation. Receiver FFT metadata alone does not prove OOB compliance.
6. The baseline's `simulation.snr_db=12` is metadata in geometry/thermal-noise
   mode, not an applied 12 dB link authority. The eventual 25 dB experiment must
   explicitly resolve its physical noise/SINR authority and demonstrate adaptive
   CQI/PMI/RI, HARQ/OLLA and multi-layer scheduling from measured inputs.
7. Complete broader regressions, standards/reference comparisons, and the later
   impairment-enabled long-run study. No narrow test proves the entire LLS is
   production-grade or all 6G study features are standardized and supported.
8. Verify absolute waveform start times against the schedule, not only shared
   channel counters. The full RA chain can advance the shared channel into
   future stages before the outer scheduling loop reaches those stages; a
   negative requested advance currently clamps to zero. The bookkeeping
   regressions do not qualify simultaneous component composition or establish
   correct absolute-time execution of every scheduled channel.
