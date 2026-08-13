# C0 forensic audit before repair

Date: 2026-08-13
Scope: `JIO_RAN1_126_AI_10_5_1_1_C0` only
Audited run: `results/ia/c0_tdoc_preflight_short_20260812_02`
Audit rule: this report was completed before changing C0 production source.

## Executive finding

The retained run is correctly labelled `quick_sanity`, but it is statistically and physically insufficient for a TDoc claim. It contains 12 trials at each of seven SNR values and 24 calibration plus 24 validation noise windows. Its global false-alarm threshold is calibrated on the maximum PSS statistic, not the complete cell-with-PCI declaration. PBCH BLER is conditional on successful practical PSS/SSS acquisition. Timing and CFO CDFs pool every SNR and include failed acquisitions. CFO has no fine estimator, so the 8,793.75 Hz coarse-grid spacing predicts a 2,538.2 Hz RMS quantization floor, consistent with the observed 2,494.2 Hz high-SNR RMSE. PBCH channel NMSE compares a practical, residual-CFO/residual-timing grid estimate with a perfect channel referenced before those receiver transformations and over the entire 240-by-4 grid; this is not a like-for-like effective-channel comparison.

The existing ten deterministic tests all passed on the untouched baseline, but several codify the defective behavior: the false-alarm test accepts a 32-window CI that merely contains 1%, and the crossing test explicitly accepts interpolation to a zero-error endpoint without adequate statistics.

## Actual retained counters

| SNR dB | total | PSS misses/errors | PSS successes | conditional SSS errors/denominator | joint SS errors/successes | wrong PCI declarations | conditional PBCH errors/attempts | complete successes/failures |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| -20 | 12 | 12 | 0 | 0/0 | 12/0 | 2 | 0/0 | 0/12 |
| -16 | 12 | 9 | 3 | 2/3 | 11/1 | 3 | 1/1 | 0/12 |
| -12 | 12 | 1 | 11 | 2/11 | 3/9 | 2 | 6/9 | 3/9 |
| -8 | 12 | 0 | 12 | 0/12 | 0/12 | 0 | 0/12 | 12/0 |
| -4 | 12 | 0 | 12 | 0/12 | 0/12 | 0 | 0/12 | 12/0 |
| 0 | 12 | 0 | 12 | 0/12 | 0 | 0/12 | 12/0 |
| 20 | 12 | 0 | 12 | 0/12 | 0 | 0/12 | 12/0 |

Noise-only counters are exact raw CSV counts:

- calibration windows: 24;
- validation windows: 24;
- validation false alarms: 1;
- measured PFA: 0.0416667;
- Wilson 95% CI: [0.00739346, 0.202418].

## File-by-file audit

| Area | File and relevant location | Current implementation | Correct? | Defect and required correction |
|---|---|---|---|---|
| Scenario root | `simulator/configs/initial_access/c0/C0.yaml:1-6` | Inherits one C0 common profile and freezes the C0 scenario ID. | Yes | Keep C0-only phase gate. Update description only if the actual antenna/port contract changes. |
| Common configuration | `simulator/configs/initial_access/c0/common.yaml:8-105` | Defaults to smoke; exposes carrier, waveform, concrete TDL-C, antenna count, oscillator, coarse CFO grid, false alarm, SNR, receiver, statistics, and raster outputs. | Partial | Several material policies are missing: declaration/SSS thresholding, fine CFO, timing-valid population/tolerance, component PBCH residual-CFO model, adaptive refinement span, stopping rule per metric, selected CDF SNRs, complexity accounting, debug categories, and developer-only plot override. Add them to YAML/schema; do not hide them in MATLAB. |
| Smoke overlay | `simulator/configs/initial_access/c0/run_modes/smoke.yaml:1-11` | 12 trials/SNR and 24+24 noise windows. | Correct only for smoke | Must never support a TDoc claim or TDoc-labelled render. |
| Quick overlay | `simulator/configs/initial_access/c0/run_modes/quick_sanity.yaml:1-9` | 2,000 trials/100 errors and 10,000+10,000 noise windows. | Suitable bounded validation | Add explicit development acceptance semantics; it cannot satisfy TDOC gates. |
| Preflight overlay | `simulator/configs/initial_access/c0/run_modes/tdoc_preflight.yaml:1-13` | Explicitly sets `quick_sanity` but uses 12 trials and 24+24 noise windows. | Misleading profile name, honest metadata | This is the direct source of the retained 12/24 counts. Rename or raise it to a meaningful bounded preflight. It must not resemble TDOC-grade output. |
| TDOC overlay | `simulator/configs/initial_access/c0/run_modes/tdoc.yaml:1-11` | 200,000 trials/500 errors and 100,000+100,000 noise windows. | Numerically aligned with requested minima | Add hard validation that TDOC cannot override these below the minima. |
| Schema | `simulator/configs/initial_access/c0/schema.yaml:1-47`; `+sixgr/+phy/+ia/+c0/+config/schema.m:1-7` | Required-path list and basic enums. | Partial | Does not enforce C0 constants or TDOC minima/dependencies and lacks the new receiver/statistics policies. Expand fail-closed schema/validation. |
| Config resolution | `+sixgr/+phy/+ia/+c0/+config/loadScenario.m:1-13`; `resolveScenario.m:1-51` | Resolves inheritance then applies caller-selected mode overlay. | Structurally correct | The public runner defaults to smoke and accepts the ambiguous preflight filename. Emit an explicit canonical uppercase run-mode field in every result and retain source overlays. |
| Config validation | `+sixgr/+phy/+ia/+c0/+config/validateScenario.m:1-80` | Validates C0 ID, concrete channel, resource dimensions, PBCH information length, basic ranges, and no-SVG policy. | Partial | It does not freeze all intended C0 constants, enforce TDOC statistical minima, validate CFO coverage/margin and fine grid, or reject contradictory timing/statistical policies. |
| PHY adapter | `+sixgr/+phy/+ia/+c0/+config/toPHYConfig.m:1-39` | Maps resolved C0 config into the existing strict SSB facade. | Partial | Periodicity, bitmap, FR, BWP origin and grid fields are partly hardcoded. Move researcher-controlled values to YAML and validate the fixed C0 anchor separately. |
| Waveform | `+sixgr/+phy/+ia/+c0/+waveform/buildNRAnchorA.m:19-121` | Uses production timing/resource/MIB contracts and Toolbox `nrBCH`, `nrPSS`, `nrSSS`, `nrPBCH`, `nrPBCHDMRS`, and OFDM modulation. 240-by-4 SSB is placed into a 20-RB slot. | Largely correct | `PayloadSeed` is not used because payload is fixed, which is acceptable if disclosed. Preserve 56-bit BCH/polar contract and add deterministic reference-vector checks. |
| Resource/energy audit | `auditResourceMap.m:1-40`; `normalizeEnergy.m:1-32` | Disjoint PSS/SSS/PBCH/DMRS ownership and equal-EPRE normalization closure. | Correct for C0 | Keep. Add the SNR calibration invariance matrix for active-RE count and receive branches. |
| TDL channel | `+sixgr/+phy/+ia/+c0/+channel/applyFading.m:1-64` | Unit-norm 2-Tx precoder, physical `nrTDLChannel`, concrete TDL-C, 4 Rx, path gains/filters, and `nrPerfectTimingEstimate`. | Mostly correct | Perfect timing is exported only as truth, not given to practical receiver. Effective-channel truth must carry precoder, path response, filter delay, sample times, and receiver transformations into the CE comparison. |
| Timing injection | `runC0Trial.m:16-35` | Random pad plus physical channel timing is bounded by one total uncertainty budget. Truth PSS timing is `timingPad + channelTiming + prefix(symbols before candidate)`. | Definition is explicit but incompletely exported | Export random pad, physical/filter delay, candidate occurrence, slot/SSB/PSS references and truth convention independently. Do not combine invalid detections into fine-timing RMSE/CDF. |
| CFO injection | `applyOscillatorCFO.m:1-18`; `runC0Trial.m:31-47` | Draws UE and TRP PPM independently; injects `TRP - UE` CFO once. TDL Doppler is not added to this scalar truth. | Sign/injection correct | Export UE Hz, TRP Hz, injected Hz separately. Current rows only preserve the sum. |
| AWGN scaling | `addNoiseForTargetSNR.m:1-28`; `measureActiveREPower.m:1-22`; `runC0Trial.m:34-41` | Uses calibrated sample-to-grid noise gain and measures active-RE power per receive branch before combining. | Correct in existing deterministic test | Extend the test across active-RE maps and Rx counts; store actual per-trial signal/noise powers, not only their ratio. |
| Blind PSS search | `runBlindPSSSearch.m:1-21`; `+sixgr/+phy/+sync/freqOffsetCorrect.m:43-181` | Searches 17 CFO values, 3 NID2 values, canonical candidate windows and all correlation lags using energy-normalized correlation. | Coarse acquisition is practical | No fine CFO refinement. Operation accounting records only 102 high-level hypotheses and omits timing lags/arithmetic/FFT/buffer/RF-active work. Search grid covers approximately +/-70.35 kHz but has no configured margin beyond the maximum combined oscillator magnitude. |
| SSS/PCI detection | `+sixgr/+phy/+dl/SSB_Rx.m:155-233` | Always chooses the argmax among 336 NID1 correlations after the PSS search. | Incomplete declaration logic | There is no SSS confirmation threshold or top-1/top-2 acceptance rule. Below-threshold PSS still causes SSS work, though `WrongPCI` currently gates on PSS threshold. Define a complete joint declaration statistic/path and calibrate exactly that path under noise. |
| PBCH DMRS/channel/decode | `+sixgr/+phy/+dl/PBCH_Recovery.m:77-240` | Tries every applicable iBar, estimates from candidate PBCH DMRS plus SSS, MMSE equalizes, PBCH demaps, polar/BCH decodes; CRC-passing candidate wins. | Physical chain exists | A CRC pass is allowed to select the hypothesis rather than first selecting DMRS by a declared practical rule; this can bias hypothesis/decode complexity. Separate DMRS hypothesis selection, wrong-hypothesis probability, and decode. Expose selected `Hhat` and receiver transformation metadata for CE validation. |
| Practical receiver | `runCompleteSSBReceiver.m:15-71` | Runs full SSB receiver first, then applies PSS threshold; attempts PBCH only if threshold, NID2 and full PCI are correct. | Partial | No explicit declaration triad; no fine CFO; SSS is forced argmax; failure trace is thin. `WrongPCI = pssDetected && ~sssCorrect` does not explicitly encode declaration/identity states. |
| PBCH metric | `runCompleteSSBReceiver.m:22-25,58`; `runC0.m:132-150` | `PBCHBLER = errors among PBCHAttempted`, where PBCHAttempted requires practical correct PSS threshold, NID2 and SSS/PCI. | Wrong for gamma PBCH | This is PBCH-B, conditional practical BLER. Add PBCH-A component execution for every channel realization with true PCI/occurrence and realistic DMRS CE/residual-CFO; retain PBCH-B separately and complete-SSB PBCH-C end to end. |
| Oracle | `runOracleReceiver.m:1-34` | Supplies true timing, CFO and PCI as an explicitly labelled upper bound. | Honest oracle/debug path | Keep out of primary practical curves and gamma. Use only deterministic isolation tests and upper-bound diagnostics. |
| CE NMSE | `channelEstimateMSE.m:1-43` | Practical `estimatedH = nrChannelEstimate(RxSSBGrid, DMRS+SSS)` is compared with a precoder-summed perfect grid from `nrPerfectChannelEstimate`. For C0, `h` is nominally 240-by-14-by-4-by-2, while both `trueH` and `estimatedH` are 240-by-4-by-4. | Not a valid like-for-like NMSE | `Hhat` contains practical residual timing/CFO phase while `Htrue` is referenced at perfect channel timing before those corrections. It compares every SSB RE rather than the declared PBCH data/DMRS set. Build `HtrueEff` after precoding, exact FFT-window/timing and CFO transformations; compare matching RE/dimensions. Do not rotate post hoc unless the receiver estimates that phase. |
| Trial export | `runC0Trial.m:53-93` | Exports seeds, combined CFO/timing, detector flags, conditional PBCH, NMSE and three coarse complexity counts. | Incomplete | Add declaration triad, PBCH A/B/C, detailed timing/CFO truth and estimates, selected occurrence, CE numerator/denominator/dB, raw powers, failure categories, SSS/DMRS metrics, and complete complexity telemetry. |
| Statistical stopping | `runC0.m:102-123` | One shared loop stops only when joint, conditional PBCH and complete errors all reach the configured minimum, otherwise at max trials. | Wrong metric ownership | Component PBCH needs an independent all-realization error count. Export stop reason and enforce 500 errors or 200,000 trials for every point used in a TDOC target. |
| Aggregation | `runC0.m:125-165`; `binomialCI.m:1-13` | Wilson intervals; aggregates conditional PBCH, wrong PCI, timing/CFO over all rows, and mean NMSE. | Partial | Add exact denominators and identities; compute fine timing/CFO only on the configured valid population; preserve zero estimate plus upper limit; add component PBCH and conditional wrong-PCI intervals. |
| Adaptive sweep | `runC0.m:168-194`; `findTargetCrossing.m:1-45`; `buildCrossingTable.m:1-15` | Extends until bracketing then intends to refine between bracket endpoints; accepts zero-error endpoints and linear probability interpolation. | Broken | `runC0.m:183` calls nonexistent `localCrossings`. Refinement is not +/-1.5 dB. Crossing qualification ignores sampling/stopping and CIs. Reject unqualified/zero raw endpoints for log interpolation and save both qualified brackets plus uncertainty. Add gamma SSB rows. |
| Plotting | `renderC0Figures.m:1-114`; `plotIAResults.m:1-29` | Renders 15 PNGs from CSV; probability axes are linear; timing/CFO CDFs pool all raw SNRs; PBCH is conditional; NMSE is linear; limited complexity. | Incorrect for requested package | Add run-mode render guard, 20 requested figures, log probability with CI/upper-limit markers, selected-SNR conditioned CDFs, NMSE dB, PBCH A/B/C, gross errors, failure breakdown and complete complexity. Never relabel quick/smoke as TDOC. |
| Validation/status | `validateC0.m:1-45`; `buildManifest.m:1-30`; `validateIAResults.m:1-42` | Fifteen weak gates; false alarm passes if CI contains 1%; crossing not applicable outside TDOC; claim class follows run mode. | Insufficient | Replace with C0-G01 through G20. Require sample minima and CI relative half-width, qualified crossings, CE-UT1..6, explicit populations and reproducible gamma bounds. Keep fail-closed status. |
| Later campaigns | `runAllIA.m:1-6`; `runCampaign.m:1-4` | `runAllIA` always errors; campaign facade rejects non-C0. | Correct | Keep C1-C15 frozen until persisted C0 `TDOC_PASS`. |

## Required root-cause answers

1. **Twelve-trial limit:** selected overlay `tdoc_preflight.yaml:4-7` sets mode `quick_sanity`, maximum 12 and minimum 4. `runC0.m:103-119` obeys those values. There is no accidental TDOC execution; the confusing preflight name masks an intentionally tiny quick run.
2. **Twenty-four noise windows:** the same overlay sets calibration and validation to 24 at lines 8-10. The runner uses these values exactly.
3. **Current PBCH BLER:** `P(PBCH CRC/payload failure | PSS threshold passed, NID2 correct, and SSS/full PCI correct)`. It is PBCH-B, not component PBCH-A.
4. **Wrong PCI at -20 dB while plotted PSS miss/error is 100%:** the plotted PSS error is `~(PSSDetected & PSSIdentityCorrect)`, not threshold miss alone. Two of twelve trials crossed the PSS threshold with wrong NID2; both remain PSS errors and are also counted as wrong-PCI declarations. Below-threshold forced SSS argmax values are not counted by the current `WrongPCI` Boolean, but the declaration lacks an SSS confidence threshold.
5. **Current timing truth:** `timingPad + nrPerfectTimingEstimate(pathGains,pathFilters) + sum(OFDM symbol lengths before candidate_start_symbol)`, i.e. the PSS-symbol start in the received capture under the chosen channel-filter-delay convention.
6. **CDF pooling:** yes. F09 uses every finite `raw.TimingErrorSamples`; F11 uses every finite `raw.CFOErrorHz`, across all SNRs and acquisition outcomes.
7. **CFO grid:** `[-70350 : 8793.75 : 70350]` Hz (17 explicit points) from YAML, crossed with 3 NID2 candidates and canonical candidate windows/lags.
8. **Fine CFO estimator:** none. `freqOffsetCorrect` returns the winning coarse-grid value and applies it directly.
9. **2-2.5 kHz floor:** quantization from the 8,793.75 Hz grid. A uniform residual inside one grid cell has RMS `8793.75/sqrt(12) = 2538.2 Hz`, agreeing with the measured 2,494.2 Hz at +20 dB.
10. **Current CE arrays:** `RxSSBGrid` and `Hhat` are 240-by-4-by-4. `nrPerfectChannelEstimate` produces the full 20-RB slot response with 4 Rx and 2 Tx dimensions (nominally 240-by-14-by-4-by-2); columns 5:8 are summed with the unit-norm 2-Tx precoder into a 240-by-4-by-4 `Htrue`. The code then compares all elements.
11. **NMSE near 2.2:** the arrays have matching sizes but inconsistent phase/time reference. `Hhat` is based on the practical FFT window after coarse CFO correction and practical timing; `Htrue` is generated at the perfect channel timing without applying residual CFO/timing/common-phase transformations. Comparing decorrelated phase references drives normalized squared error toward approximately two. The all-grid rather than PBCH-RE comparison adds another semantic mismatch.
12. **Required code changes:** add strict run-mode/statistical schema; implement a complete joint declaration and noise calibration; separate PBCH A/B/C; add fine CFO and detailed truth; correct conditioned timing/CFO populations; build receiver-referenced `HtrueEff`; qualify crossings/adaptive refinement; expand counters/debug/complexity; replace plots and C0-G01..G20.
13. **Untouched deterministic baseline:** 10/10 existing C0 tests passed. This does not validate the requested repair because the false-alarm and target-crossing tests encode insufficient acceptance rules and no CE unit-test suite exists.

## Repair order frozen by this audit

1. Run-mode/schema and C1-C15 hard gate.
2. Deterministic declaration, counter identities, and SNR calibration matrix.
3. PBCH CE effective truth and CE-UT1 through CE-UT6.
4. Fine CFO and timing/CFO truth/population semantics.
5. PBCH A/B/C execution and independent stopping.
6. Full declaration false-alarm calibration/validation.
7. Qualified adaptive refinement, gamma and confidence bounds.
8. Complexity/debug exports, C0 figures and C0-G01 through G20.
9. Deterministic tests, bounded QUICK_SANITY, then 10,000-window development FA. No full TDOC run until these pass.
