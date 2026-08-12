# 10.8.3 ISAC waveform/reference-signal simulation audit

## Scope and repository authority

This audit covers the existing SixGR W0/W1/W2/W3 joint ISAC implementation.
It does not introduce a second simulator. The controlled waveform experiment
uses the repository's NR carrier and OFDM functions and remains distinct from
the coded PDSCH full-PHY anchor. Evidence from either path is not relabelled as
the other.

The active versioned study configuration is
`configs/isac/joint_isac_tdoc_master.yaml`. Every Stage-1 tolerance, sweep,
seed, W3 reset, and puncture condition is owned by that YAML and validated by
`+sixgr/+isac/validateJointConfig.m`.

## Implementation map

| Function | Role | Runtime evidence |
|---|---|---|
| `+sixgr/+isac/buildJointWaveform.m` | W0–W3 physical grid, RS rules, ordinary NR OFDM modulation and actual CP pattern | transmitted grid and sample hashes |
| `+sixgr/+isac/cumulativeCPState.m` | independent absolute-symbol W3 `q(l)` recurrence with explicit reset symbols | W3 state tables and puncture test |
| `+sixgr/+isac/applyLinearDelay.m` | zero-extended integer/fractional time-domain delay | CP-safe and long-delay gates |
| `+sixgr/+isac/runJointWaveformTrial.m` | common received observation, B0/B1/B2/C0 processing, detection, range, Doppler, communication EVM | raw waveform-trial rows and received hashes |
| `+sixgr/+isac/parabolicPeak.m` | common sub-bin delay estimator for all receiver profiles | off-grid rows |
| `+sixgr/+isac/runIntegrationStudies.m` | TDD, event, interference, ISI/ICI, collision and coherency studies | aggregate study tables |
| `+sixgr/+isac/analyzeJointWaveforms.m` | PAPR, spectrum, autocorrelation and cross-profile diagnostics | aggregate diagnostic tables |
| `+sixgr/+isac/runFullPHYAnchor.m` | legacy production DL-SCH/PDSCH anchor used by WFig01–WFig16 | separately labelled coded-PHY evidence |
| `+sixgr/+isac/runPDSCHProfileSweep.m` | WFig31/WFig32 production DL-SCH/PDSCH W0/W1-A/W1-B/W2/W3 paired sweep | coded-PHY trial, BLER, BER, EVM, goodput and provenance rows |
| `+sixgr/+isac/run1083Stage1.m` | fail-closed CP-safe, linear-convolution, off-grid, W3 puncture and coherence gates | WFig17–WFig19, CSV/MAT/FIG/PNG/PDF |
| `+sixgr/+isac/run1083Comparative.m` | paired fixed-H0-threshold B0/B1/B2/C0 delay/SNR execution | WFig20–WFig24 |
| `+sixgr/+isac/run1083Intrinsic.m` | range-Doppler maps, PAPR, numeric spectral integration, ambiguity and cross-correlation | WFig25–WFig28 |
| `+sixgr/+isac/run1083Stress.m` | same-observation inter-cell/SI, production PDSCH, puncture, relocation, W1 and complexity stress | WFig29–WFig36 |
| `+sixgr/+isac/run1083Validation.m` | ordered fail-closed campaign, artifact verifier, manifest and 22-section decision report | one timestamped WFig17–WFig36 evidence root |
| `+sixgr/+isac/regenerateJointFigures.m` | WFig01–WFig16 and joint report regeneration from saved evidence | image/source hashes |

Related production primitives are `+sixgr/+phy/+waveform/ofdmModulate.m`,
`+sixgr/+phy/+waveform/ofdmDemodulate.m`, and the PDSCH chain under
`+sixgr/+phy/+dl/`. The joint study uses `nrOFDMModulate` and
`nrOFDMDemodulate` directly because its carrier is an `nrCarrierConfig`; the
same carrier supplies FFT size and the physical normal-CP pattern.

## Waveform and receiver definitions

- **W0** uses symbol/occasion-dependent NR Gold QPSK RS without a sensing
  phase progression.
- **W1-A** randomizes the sequence per sensing occasion.
- **W1-B** holds a sequence for the configured reset-aligned interval.
- **W2** repeats one base sequence over the coherent symbol group.
- **W3** repeats the base sequence and applies the absolute physical
  subcarrier phase derived from cumulative physical CP state.
- **B0** performs ordinary CP removal/FFT and per-symbol matched processing.
- **B1** correlates the complete ordinary-W0 time observation; it requires no
  transmitter change.
- **B2** applies the same long-observation receiver to the repeated W2
  reference.
- **C0** reconstructs W3 state independently from the YAML reset and physical
  CP pattern. A deliberately wrong transmitted-sensing-counter rule exists
  only as negative evidence and is labelled in its output row.

## Assumptions retained

- Normal CP and the configured physical SCS/grid/cell identity are unchanged.
- Ordinary IFFT/CP insertion is unchanged for W3.
- Equal occupied RE count and total sensing energy are retained across paired
  waveform comparisons.
- W0–W3 component rows are uncoded common-waveform experiments. Coded BLER and
  transport-block results come only from the production PDSCH chain invoked
  by `runFullPHYAnchor` or `runPDSCHProfileSweep`.
- Quick mode is engineering evidence and is not publication statistics.
- Target geometry is truth input; estimated delay/Doppler are produced by the
  receiver and never copied from configured target values.

## Defects detected

1. The previous W3 recurrence used the preceding symbol's CP and initialized
   the first symbol at zero. The supplied 10.8.3 definition includes the
   current absolute symbol's CP from the reset anchor.
2. The production trial rounded all target delays to integer samples, making
   the mandatory off-grid delay experiment impossible.
3. WFig15 plotted only absolute W3 state. It did not execute a wrong
   transmitted-sensing-counter receiver or quantify its coherent/Doppler
   consequence.
4. WFig05 used raw adjacent OFDM sample jumps, which are not a sensing
   coherency metric.
5. The earlier ISI/ICI study used a linear integer delay, but no isolated
   two-distinct-symbol CP-safe/CP-violation gate prevented invalid beyond-CP
   conclusions.
6. Range estimation was integer-bin only, so grid-aligned targets could
   report exactly zero RMSE without validating sub-bin behavior.
7. WFig01–WFig16 alone did not satisfy the newly required WFig17–WFig36
   contract. The new ordered runner keeps later stages gated on Stage 1 and
   verifies 100 required plot-format files before finalization.
8. The inherited full-PHY anchor name and hash described its 30 GHz source
   template even after the 10.8.3 runner changed the executed carrier to
   7 GHz/100 MHz/30 kHz. It also left the PDSCH allocation at 24 PRBs while
   creating a carrier-wide sensing grid, obscuring the actual shared-resource
   intersection.
9. MATLAB's session-level dark axes defaults produced low-contrast WFig
   exports, and the generic stress renderer connected individual Monte Carlo
   rows as if they were an ordered curve.

## Corrections made

- Centralized the inclusive W3 cumulative-CP recurrence in
  `cumulativeCPState` and made both transmitter and C0 derive it independently.
- Kept puncturing out of the correct state recurrence; the wrong counter is an
  explicit negative receiver mode only.
- Added zero-extended time-domain integer/fractional delay through
  `applyLinearDelay` and wired it into the shared trial channel.
- Added one common parabolic sub-bin delay estimator for B0/B1/B2/C0.
- Added exact fractional delay/Doppler trial fields without exposing target
  state to any receiver.
- Added Stage-1 evidence and plots:
  `WFig17_linear_convolution_validation`,
  `WFig18_absolute_vs_transmitted_counter`, and
  `WFig19_cross_symbol_coherence`.
- The Stage-1 runner fails closed and does not proceed to comparative
  publication claims if any physical gate fails.
- The coded PDSCH sweep now records both the immutable anchor-template hash
  and a hash of the effective runtime configuration, plus the executed
  carrier frequency, bandwidth, SCS, grid, and shared allocation.
- The master YAML now owns the shared-PDSCH allocation. Sensing references
  are clipped to that allocation before TBS planning and transmission;
  dedicated tests require transmitted sensing RE count to equal PDSCH
  reserved-RE count.
- Grid Es/N0 and post-MMSE layer SINR now carry explicit domain labels. The
  latter is cross-checked against independently measured equalized-symbol EVM
  instead of being compared directly with the pre-channel Es/N0 input.
- Every WFig export applies a deterministic light publication style. WFig33,
  WFig34, and WFig35 aggregate repeated trials using mean, RMSE, or empirical
  probability according to the plotted metric.
- The original sensing SNR screening points saturated all four receivers at
  detection probability one. A short fixed-threshold probe located the
  actual target-echo transition, and the YAML-owned screening/publication
  grids now bracket it. Likewise, the shared-PDSCH grid brackets its measured
  coded waterfall instead of producing only zero-error points. These are
  operating-point corrections, not detector-threshold or acceptance changes.
- Range and Doppler RMSE are conditioned on a correct detection and export
  their exact contributing sample count. Miss probability and wrong-peak
  probability remain separate unconditional metrics; missed acquisitions are
  not silently converted into estimator error samples.

## Validation and numerical tolerances

The noiseless integer-delay CP-safe threshold is YAML-owned and defaults to
`1e-8` EVM RMS. Fractional delay uses a 129-tap Kaiser-windowed sinc
interpolator and therefore has a separately declared finite numerical
tolerance (`5e-4` by default); the measured value and tolerance are both
exported. This tolerance governs interpolation fidelity only, not a receiver
performance threshold.

The long-delay gate uses two different consecutive OFDM symbols and measures
the current FFT window's energy originating from the previous symbol,
off-diagonal residual energy from the current symbol, and post-diagonal-EQ
EVM. The operator is a zero-extended time-domain delay rather than an
independent per-symbol frequency response.

## Tests added or updated

- `tests/testISAC1083Stage1.m` executes the complete Stage-1 runner, checks all
  five fail-closed gates, checks the three figure/source contracts, and checks
  W3 correct-versus-wrong receiver separation.
- `tests/testJointISACTDoc.m` now asserts the inclusive absolute-symbol CP
  recurrence.
- `tests/testISACPDSCHReferenceGrid.m` verifies physical reservation,
  transmission, coded decoding, and constant TBS for W0–W3.
- `tests/testISAC1083StressGate.m` verifies WFig29–WFig36, effective carrier
  and configuration provenance, shared-resource equality, SNR-domain
  calibration, EVM/post-equalizer consistency, TDD punctures, relocation,
  and both W1 randomization modes.
- `tests/testISAC1083ArtifactVerifier.m` proves all 100 WFig17–WFig36
  CSV/MAT/FIG/PNG/PDF contracts fail closed on a missing artifact.

## Remaining statistical qualification

The implementation now covers WFig20–WFig36, multi-target/clutter sweeps, 2D
ambiguity, PAPR, numeric asymmetric ACLR, cross-cell sequence distributions,
same-observation inter-cell/SI stress, production coded PDSCH reservations,
relocation residuals, and separate runtime/operation counts. The screening
class is deliberately not publication qualified. A final claim still requires
the YAML publication class: 100,000 H0 trials for PFA 1e-3, 5,000 target trials
per important point, and the coded-PDSCH 100-error/10,000-TB stopping rule.
