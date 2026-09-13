# PUCCH detector YAML and paired-IQ checkpoint

The production shared PUCCH path now consumes a YAML-owned threshold and
exports its exact source. **Detector conformance and the final 12 dB run
remain unqualified.** No full run, `testAll`, E2E campaign or push occurred.

## Root cause and implementation

The Format-0 noncoherent receiver's metric is a normalized sequence
correlation, not SINR, power, EVM or a CRC. The trial wrapper previously
supplied 0.2 for every format. For Format 0, the installed R2026a decoder
averages normalized correlation magnitudes over 12-subcarrier resource
groups / receive branches and selects the largest candidate value. A
noise-only input can therefore produce a nonzero detection metric; lowering
the threshold does not increase physical received SINR.

The named defaults are now in
`simulator/configs/control/pucch_receiver_thresholds.yaml`, explicitly
inherited by `defaults/global.yaml`. Schema bounds are [0,1].
`buildInternalConfig` carries the configured values into
`phy.pucch.receiverDetectionThresholds`. A partially supplied policy is
rejected; a wholly absent policy is not manufactured. Shared PUCCH
preparation/reception requires a policy and rejects argument overrides.
Standalone trial callers retain an explicitly labeled YAML catalog default
or explicit test argument, not a missing-live-config rescue.

The 12 dB continuous-IQ YAML explicitly contains:

```yaml
pucch:
  detection_threshold_format0_one_symbol: 0.49
  detection_threshold_format0_two_symbols: 0.42
```

These are the documented Format-0 receiver implementation defaults in
[nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html),
not universal 3GPP-prescribed constants. The other four fields are
`detection_threshold_format1` through `detection_threshold_format4`.
Their 0.2 defaults preserve the existing energy-aware decision metrics;
they must **not** be represented as equivalent to the toolbox's pure
correlation thresholds. Their metric/ROC repair remains open.

The actual trial and logical PUCCH grant trace now both retain
`DetectionThreshold` and `DetectionThresholdSource`. The shared SRS/PUCCH
test verifies those values after actual received completion, alongside
ACK/NACK decoding, independent prior-UL timing and the power ledger.

## Paired retained-IQ results

All 66 input MAT files from `received_harq_outcomes_04` were replayed, with
no resampling or seed selection. Each comparison row includes its input
path/SHA-256 and an independent `nrPUCCHDecode` metric/bit comparison using
the same FFT grid. This validates the decision path, not an independent FFT
implementation or the complete physical baseline.

| Policy | Noise-only occasions | Any false detection | False ACK bits | DTX-to-ACK bit fraction |
| --- | ---: | ---: | ---: | ---: |
| Previous 0.2 | 64 | 60 | 34 | 0.53125 |
| Configured 0.42 | 64 | 3 | 3 | 0.046875 |

Both signal-present ACK/NACK cases still decode. These are one-receive-branch
component inputs, not the baseline's complete array / RF / channel setup.
The count reduction is **not** a conformance pass. TS 38.104 section 8.3.1
defines DTX-to-ACK using falsely detected ACK bits divided by DTX occasions
and configured ACK/NACK bits per occasion, and specifies a 1% limit.
That is distinct from counting every false detection.
[TS 38.104 v18.13.0, 8.3.1](https://www.etsi.org/deliver/etsi_ts/138100_138199/138104/18.13.00_60/ts_138104v181300p.pdf).

Primary component evidence for this checkpoint is under
`docs/lls/evidence_20260913/pucch_detector_policy_04`:
`detector_policy_comparison.csv`, `noise_only_summary.csv`,
`resolved_receiver_policy.mat` and `noise_only_comparison_readable.png`.
The readable PNG was regenerated only from the actual summary CSV, checked
visually, and uses explicit light backgrounds/dark text. Earlier theme-
dependent PNGs remain preserved. The figure's source is component evidence,
not a missing phase artifact reconstructed for the old run.

## Test receipts and limitations

All receipts below are in `docs/lls/evidence_20260913`.

- `pucch_detector_policy_tests_01.txt`: exit 1, new test used `grid` as both
  a variable and plotting command; corrected to `rxGrid`.
- `pucch_detector_config_regression_01.txt`: exit 0, catalog/schema and
  existing scenario configuration validation.
- `pucch_detector_policy_tests_02.txt`: exit 0, threshold/override/schema
  checks, retained-IQ comparison and actual shared SRS/PUCCH threshold export.
- `pucch_detector_policy_tests_03.txt`: exit 1 after successful paired
  replay; the self-contained legacy config lacked the new fields.
- `pucch_detector_policy_tests_04.txt`: exit 0, final PHY/config source;
  paired replay, explicit absent-policy / override guards, PUSCH feedback
  reducer and actual shared SRS/PUCCH timing/power/threshold trace checks.
- `pucch_detector_render_tests_01.txt`: exit 0, separate readable rendering
  from `_04` CSV and rejection of impossible false-ACK counts. No PHY rerun.
- `pucch_detector_semantics_tests_01.xml`: 122 Python tests pass.

Two requested edits were refused by the normal editor: the low-level
`PUCCHReceiver.m` default and the fully materialized
`lls_causal_access_to_data_wiring.yaml`. Neither file was changed. The live
path uses the receiver's existing explicit-threshold argument. The legacy
materialized scenario may still be built for unrelated PHY/reducer checks,
but shared PUCCH execution rejects its absent detector policy. Its complete
physical-run qualification is not claimed. No alternate writer or ACL
change was used. The earlier CSI-RS allocator restriction remains open.

## Next mandatory work

Qualify an independent noise/signal trial set with the baseline's actual
receive-branch count, resource/bit layouts, retained RF and timing. Evaluate
DTX-to-ACK and ACK-miss denominators and statistical uncertainty; do not tune
only against these retained samples. Complete the other formats' distinct
metric paths and materialized-config migration. Then finish missed-DCI
receive-only observations, combined shared HARQ/retained-ACK timing,
special-slot allocation, TA/synchronization and remaining CSV/PNG/IQ gates.
The final 12 dB run and subsequent 400 MHz / high-QAM stages remain held.

Reproduce the focused check with a new evidence directory/log name:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testPUCCHDetectionYAMLAuthority('qualification_working/pucch_detector_check')); assert(testLLSPUSCHHARQACKRuntimeFeedback); assert(testSharedPUCCHFeedbackClock(true,'TDD'));" -logfile qualification_working/pucch_detector_check.txt
```
