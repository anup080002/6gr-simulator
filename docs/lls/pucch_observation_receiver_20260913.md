# PUCCH observation receiver: practical timing and noise authority

Base revision: `d86dd096`. This checkpoint builds on all earlier received
UL DAI and scheduled-mapping commits. It is not a 12 dB qualification.
This is the consolidation tip for a fast-forward of main, retaining all
prior source commits. Qualification remains separate from consolidation.

## Implemented

`receivePUCCHObservation` accepts a typed allocation, count-only context,
complete captured samples and, for Format 0, a retained received UL pilot
clock. It does not construct a UE transmitter or inspect a transmitted
waveform, payload, applied power, injected noise variance or injected
interference covariance. The existing shared `runPUCCHWaveformTrial`
receiver now calls it. Transmit/scoring evidence remains separate.

Format 0 uses the retained SRS/PUSCH pilot timing reference and normalized
sequence correlation. Formats 1–4 use receiver-known DM-RS, bounded timing
search within actual captured samples and received-resource disturbance
estimation. No new channel/noise execution, zero padding, clipping, power
scaling or threshold change was introduced.

This uses the existing canonical receiver and Toolbox
[PUCCH decoding](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html) and
[practical channel estimation](https://www.mathworks.com/help/5g/ref/nrchannelestimate.html)
implementations. API equivalence is not independent simulator or conformance
validation.

`ReceivedULTimingReference.alignObservation` derives the nominal target
from the scheduled absolute slot instead of requiring a prepared PUCCH.
Its identity, prior-availability, age and complete aligned-sample checks
remain enforced. The legacy prepared adapter delegates to this same path.
The sample buffer must straddle the nominal slot origin and contain the
complete aligned FFT interval; a valid timing-advanced reception can end
before the nominal slot end.

The shared trial and primary PUCCH rows explicitly distinguish
`ReceiverInputSampleNoiseVarianceValueRole =
physical_execution_metadata_not_receiver_estimate` from the practical
receiver's grid disturbance estimate. `ReceiverInjectedNoiseVarianceConsumed`
is false for this shared path. The standalone provided-variance trial API
is separate and retains its existing behavior.

## Validation

The first focused replay exited 1: my initial capture guard incorrectly
required the nominal slot end to be captured, despite the retained valid
timing-advanced UL ending earlier. The corrected check retains complete
real aligned samples; no padding or clipping guard was relaxed.

The second focused run exited 0: retained post-RF Format-0 replay,
eight negative/metamorphic guards, and fresh standalone DM-RS Formats 1–4
passed. Its tests use the separately declared retained component resource
and length, not an independently resolved gNB Type-2 codebook.
Changing only injected variance/covariance metadata leaves semantic
receiver output unchanged. Wall-clock profiling fields are excluded from
semantic equality, not decode/timing/channel/noise fields.

Original failed/successful logs are retained unchanged under
`evidence_20260913/sixgr_pucch_observation_receiver_20260913_01.log` and
`_02.log`. They precede the subsequent primary-row provenance fields.
The subsequent eight-test batch ended with seven passes and one failure:
the observation API, both assignment tests, actual shared one/two-bit and
Format-2 feedback clocks, and noise-domain checks passed. Staged control
reception failed in its SRS noise-source assertion. Its failed batch log
is retained as `sixgr_pucch_observation_receiver_focused_20260913_03.log`;
the direct diagnostic `sixgr_pucch_observation_staged_failure_20260913_04.log`
identifies line 100 of `testUplinkControlStreamStages`.

This exposed an existing SRS provenance defect: `NoiseVarianceSource`
appended the physical injected-AWGN label even for a received-resource
estimate. The source now remains exactly `NoiseVarSource`; injection
provenance is preserved independently as
`InjectedSampleNoiseVarianceSource`, including in the primary SRS row.
No variance value or SRS estimator was changed. In particular, this does
not claim to remove every provided-noise path from SRS reception.

The original staged receiver-source assertion is unchanged. Its direct
repair rerun exited zero, including actual standalone 12 dB SRS and PUCCH
reception and the final shared SRS/PUCCH clock check.
The wideband SRS test now checks the injection label in its separate field
and additionally requires receiver-source equality; all numerical Es/N0,
power, bandwidth and SINR assertions remain intact.
The PUCCH CSV round-trip also checks the new receiver/injection provenance.
The final four-test batch exited zero on the combined source:
`testPUCCHObservationReceiver`, `testUplinkControlStreamStages`,
`testSRSRuntimeCanonicalWidebandResource` and
`testNoiseDomainEvidenceContract` all passed. This includes the new CSV
provenance round-trip and the unchanged staged-estimator assertion.
Its log is `sixgr_pucch_srs_provenance_final_20260913_06.log`.
The receipt binds exact working-source hashes, Git blob identities and
original logs. Mandatory full/export/NR/E2E guards are required after
main consolidation; focused passes do not replace them.

## Remaining blockers — not closed by this patch

1. Independent gNB resource/length/bit mapping is still not the shared
   controller's authority. The shared legacy assignment remains explicitly
   marked transmitter-coupled, even though the receiver no longer requires
   a prepared transmitter. Absent-UE receive-window dispatch and HARQ
   disposition still need integration with the physically scheduled ledger.
2. Received-event Type-2 transmit consumers, missed DCI, wrapped DAI,
   retained ACK and actual absent-feedback end-to-end qualification remain.
3. The retained two-bit false-ACK result is still 12/1024 (1.171875%),
   exceeding its 1% reference; independent signal-miss/false-ACK and Phase-05
   evidence remain required. No acceptance threshold was tuned.
4. Full timing, power/noise, reference/data/control measurements, CSI/SRS/
   beam causality and CSV/PNG/IQ closure remain as listed in
   `12db_measurement_closure_plan_20260913.md`.
5. Final revision-bound regression, main consolidation, 12 dB execution
   and the already authored same-chain nine-point sweep remain required.

## Superseded job preservation

The intermediate `7c215d65` full suite was intentionally stopped to free
this existing worktree. Its wrapper was stopped before the MATLAB process,
so queued intermediate guards were not launched. Terminal status was
exit -1: **stopped/incomplete**, never PASS.
No result directory, branch or commit was deleted.

Its final original partial log is retained as
`evidence_20260913/stopped_superseded_ul_dai_7c215d65_full_20260913.log`,
SHA-256 `214537d6fd0839f9c6e489aad5d260d99799285a9ecfb7c9b6320dd9e29e10be`.
After the final focused pass, the two remaining older full suites
(`5b07063c` and `d86dd096`) were also deliberately stopped for single-main
consolidation and validation. Both exited -1 and are **stopped/incomplete**,
not passed. Their queued guard/scenario batches did not execute.
The actual process and parent-wrapper commands were checked before stopping
only these owned jobs. Final original logs were copied after termination
with matching SHA-256:

| Preserved file under `evidence_20260913/` | SHA-256 |
| --- | --- |
| `stopped_superseded_main_5b07063c_full_20260913.log` | `d7d40b2c800b999691c4a7700032f5a56f5a32947c33525d8bd567891e6accb1` |
| `stopped_superseded_scheduled_dai_d86dd096_full_20260913.log` | `f5d38805d562752b65163d3e7c6e4215905ff885f79ea22adebd1853b1bed84e` |

Their result directories and all recovery refs remain intact. These partial
old-source results do not qualify the final receiver or the 12 dB baseline.

The NR-validation and result-integrity skills guided receiver/scoring
separation, explicit provenance and preservation of the original failure.
