# CODEX IMPLEMENTATION PROMPT 11 — RF IMPAIRMENTS, POWER CONTROL AND RECEIVER FRONT END

## Mission

You are the lead MATLAB RF/baseband impairment, receiver-front-end and uplink-power-control engineer for this repository. This task is **not a review**, **not a documentation-only exercise**, and **not a truth-contract exercise**. Modify the production MATLAB waveform chain and execute the corrected implementation.

Close all 14 `RF-*` findings for the selected bounded profiles. Preserve correct existing PHY kernels, but remove every silent default, physical shortcut, configured-oracle correction and power-normalization workaround identified in `current_rf_frontend_static_audit.csv`.

Implement this causal waveform chain:

```text
profile + explicit reference planes + calibrated RF parameters
    ↓
baseband layers/ports in physical power units
    ↓
CFR and DPD, when selected
    ↓
DAC quantization + reconstruction filter
    ↓
TX IQ/DC/LO leakage + PA AM-AM/AM-PM/memory
    ↓
TX oscillator CFO/SCO/phase-noise state
    ↓
antenna-connector or declared conducted reference plane
    ↓
channel + wanted/interfering/blocker sample contributions + thermal noise
    ↓
RX RF selectivity + LNA/mixer/nonlinearity + oscillator impairments
    ↓
stateful AGC + anti-alias filter + ADC
    ↓
blind timing/CFO acquisition and tracking + measured IQ/CPE correction
    ↓
receiver channel estimation/equalization/decoding
    ↓
EVM/ACLR/SEM/OBUE/power/dynamic-range measurements at explicit reference planes
    ↓
decoded TPC/pathloss events → PUSCH/PUCCH/SRS/PRACH power-control state
    ↓
next actual waveform transmission
```

## Repository inputs

Place this pack under `tests/vectors/rf/`. Treat these files as immutable test definitions and bounded independent analytical floors:

- `rf_impairments_power_control_frontend_14_findings.csv`
- `rf_capability_profile_matrix.csv`
- `rf_declared_coverage_matrix.csv`
- `rf_frontend_implementation_task_graph.csv`
- `rf_frontend_matlab_test_plan.csv`
- `rf_frontend_error_contract.csv`
- `independent_vector_manifest.json`
- every `rf_*_test_vectors.csv`
- every `expected_rf_*.csv`
- every `desired_rf*_contract.csv`
- all three Python verifiers.

Do not copy expected CSVs into a production artifact directory. Expected files are independent analytical floors. Production CSVs must be serialized from actual MATLAB runtime objects and actual waveform results.

## Non-negotiable profile and claim boundary

Implement exactly these planning classes:

```text
ideal_phy_strict
    Exact identity front end except explicitly selected thermal noise and physical power scaling.
    No RF impairment or RF conformance claim.

rf_impaired_research
    Explicit, versioned and reproducible impairment models.
    Study/research conclusions only.

rf_conformance_emulation
    Implements selected TS 38.101/38.104/38.141/38.521 measurement methods and reference conditions.
    Every result must say EMULATION_ONLY.

rf_device_conformance
    NON-EXECUTABLE in this repository.
    Always fail with RF:DeviceConformanceClaimForbidden.
```

A baseband LLS cannot certify a UE, base station, RF chain, antenna connector, radiated system or commercial product. Do not use wording such as `RF conformant`, `certified`, `passes 3GPP RF conformance`, `type approved` or `device compliant`. Permitted wording is `baseband RF-impairment emulation under the declared profile`.

## Pinned specification baseline

Record exact versions in every run manifest. The selected Release-19 baseline is:

```text
TS 38.101-1 V19.4.0 — UE Range 1 RF requirements
TS 38.101-2 V19.4.0 — UE Range 2 RF requirements
TS 38.104 V19.4.0 — base-station RF requirements
TS 38.141-1 V19.4.0 — BS conducted conformance-test methods
TS 38.141-2 V19.x — BS radiated conformance-test methods, only when a radiated emulation profile is explicitly implemented
TS 38.521-1 / 38.521-2 exact selected versions — UE test methods, only for bounded emulation profiles
TS 38.211 / 38.212 / 38.213 / 38.214 / 38.215 / 38.331 exact versions used by the corresponding PHY/MAC profile
MATLAB and 5G Toolbox release
```

Do not hard-code one RF limit across bands, BS classes, UE power classes, waveform configurations or reference planes. Implement a versioned table registry. Rows without an exact table/vector remain `SPEC_LOOKUP_REQUIRED` and cannot be enabled.

## Non-negotiable implementation rules

1. Edit production MATLAB source and migrate all live callers. Do not return a plan-only response.
2. Create one canonical RF runtime under `+sixgr/+rf/+runtime/`; do not create another unused parallel stack.
3. Strict execution must not use legacy aliases, hidden defaults, auto AGC, parameter clamping, vector padding/truncation, model fallback or power restoration.
4. Every impairment stage owns an immutable configuration ID, dynamic state ID, input/output reference plane, input/output sample hash and actual applied-parameter record.
5. The receiver may not use injected CFO, timing, phase, IQ or transmitted bits to estimate/correct impairments. Injected truth is diagnostic only after receiver decisions.
6. Tx and Rx oscillator states are separate. Relative CFO/SCO/phase noise are derived once and applied once with a documented sign convention.
7. Oscillator, resampler, AGC, PA memory, DPD and power-control state must remain continuous across slots/chunks.
8. PA output shall not be renormalized to its input power. Compression and spectral regrowth are physical outputs.
9. ADC/DAC full scale, code convention, filtering, bit depth and sample rate must be explicit. Bit depth is an integer; do not round an invalid value.
10. Configured SNR shall never be converted into measured pathloss for strict power control.
11. Requested, applied and measured waveform power must reconcile at the declared reference plane.
12. ACLR/SEM/OBUE/blocking/intermodulation evidence must come from actual sample-domain wanted/interferer/front-end processing.
13. Same-Toolbox comparisons are self-consistency only. Mandatory equations, coefficients, code values, frequencies and measurement bands need a pure-math or frozen independent reference.
14. Missing MATLAB, skipped/blocked mandatory tests, incomplete operating points, absent CSV/PNG or a nonzero verifier exit code means the phase is not complete.

## The 14 findings to implement

| ID | Priority | Current technical defect | Required production correction | Mandatory acceptance |
|---|---:|---|---|---|
| **RF-001** | P0 | The same ordered impairment chain is used for ideal, research and strict-labelled executions. Strictness is mainly inferred from configuration/mutation evidence, while the source has no immutable profile that distinguishes ideal PHY, RF-impaired research, conformance-method emulation and actual RF-device conformance. | Create RFSpecificationProfile and RFCapabilityProfile with exactly three executable classes: ideal_phy_strict, rf_impaired_research and rf_conformance_emulation. Add a fourth non-executable claim type rf_device_conformance that always rejects in this baseband LLS. Every run, CSV and plot shall record profile ID, specification/version, reference plane and permitted claim wording. | Planning rejects any attempt to claim UE/BS RF conformance or certification. Ideal profile is identity except explicitly selected thermal noise/channel effects. Research profiles execute only explicit models. Emulation profiles use pinned test methodology and are labelled EMULATION_ONLY. |
| **RF-002** | P0 | PowerContext has useful sqrt(mW) scaling, but strict runs can receive silent defaults for Tx power, gains, NF, impedance and PA efficiency. Reference planes before/after DAC, PA, connector, channel, LNA, mixer, filter, AGC and ADC are not one reconciled chain. | Create RFReferencePlane, AbsolutePowerLedger, OFDMScalingLedger and NoisePowerLedger. Track watts, dBm, PSD, impedance, gain/loss, bandwidth and sample units at every stage. Strict profiles require explicit Tx power, antenna/connector convention, gains, losses, NF, filter ENBW, full scale and calibration state. | Analytical and measured waveform power reconcile within 0.05 dB at every declared reference plane. Parseval closure, per-port power sum and noise ENBW tests pass. Removing any required reference-plane parameter fails planning. |
| **RF-003** | P1 | CFO is primarily a sample-wise complex rotation. CP/RS estimators exist, but integer/fractional CFO acquisition, Tx/Rx oscillator ownership, drift, ambiguity resolution, false-lock handling, loop state and correction provenance are incomplete. | Create independent TxOscillatorState and RxOscillatorState; derive relative CFO without double application. Implement coarse integer-subcarrier search, fractional CP/DM-RS/TRS estimator, stateful frequency/phase tracking loop, phase continuity, drift/random-walk and residual-CFO measurement. True injected CFO may appear only in diagnostic comparison after receiver decisions. | Blind acquisition succeeds over the declared CFO range without true-CFO input; false-lock, no-signal and ambiguity tests pass; correction is applied to samples; residual CFO and phase error meet profile thresholds over multi-slot drift. |
| **RF-004** | P0 | Timing uses a fractional-delay helper, while SCO is implemented as fixed-length linear interp1 resampling and is labelled configured_pending_resampling. It has no anti-alias filter, persistent clock state, cumulative drift, output-time accounting or timing-loop coupling. | Create TimingAcquisitionEngine, TimingTrackingLoop, SampleClockState and StatefulSampleRateOffsetResampler. Model t_rx[n]=(n+tau0)*(1+epsilon)/Fs with epsilon in ppm. Use a stateful bandlimited/polyphase rational or Farrow resampler, persistent fractional phase, anti-alias filtering and exact output timestamps. | Impulse, tone, OFDM and long-duration drift vectors pass. Timing correction is receiver-derived and applied. SCO produces the expected accumulated drift, sample count and spectrum without boundary zero-fill artifacts. Deleting timing/SCO state fails strict execution. |
| **RF-005** | P1 | When no explicit mask is present, PhaseNoiseModel creates heuristic masks from carrier frequency. The fallback process reinitializes a named stream per apply call and normalizes its output to an integrated target, which can break continuous oscillator phase across chunks and does not model common/independent LO correlation across RF chains. | Create versioned PhaseNoiseProfile and stateful PhaseNoiseProcess. Require explicit offset/PSD masks or calibrated oscillator parameters. Preserve phase across waveform chunks. Support common LO, independent LO and configured correlation across RF chains. Validate single-sideband PSD, integrated phase variance, CPE/ICI split and receiver PT-RS/TRS correction. | Measured PSD follows every mask point and integrated RMS within tolerance; continuous chunks equal one-shot generation; configured correlation is observed across chains; no heuristic default mask is allowed in strict profiles. |
| **RF-006** | P1 | The current widely-linear IQ model is useful but mostly frequency-flat. Runtime IQ metrics are fitted after the complete impairment chain, so PA, phase noise, CFO and quantization can contaminate the estimated alpha/beta. Receiver compensation can use configured coefficients instead of an independently estimated state. | Implement separate Tx/Rx frequency-flat and selected frequency-selective IQ profiles using y=alpha*x+beta*conj(x)+d. Add DC offset, LO/carrier leakage, image measurement, pilot/training-based IQ estimation and a stateful compensator. Record pre/post image rejection and EVM at defined reference planes. | Independent alpha/beta/image vectors pass; receiver does not receive configured correction coefficients in strict mode; compensation improves image rejection/EVM without using transmitted bits; wrong-image and no-signal cases fail closed. |
| **RF-007** | P0 | PAModel silently falls back to a normalized soft limiter with A=1 and uses generic default memory-polynomial taps/orders/weights. applyPowerContext then rescales PA output to restore the original input power, erasing physical compression and output-power loss. | Create calibrated PAProfile with gain, saturation/P1dB, AM-AM, AM-PM, IIP3/OIP3, memory coefficients, sample rate, bandwidth, temperature and coefficient provenance. Implement Rapp/Saleh/LUT, memory polynomial and GMP profiles. Apply in physical sample units and never restore output power after nonlinearity. | AM-AM/AM-PM, gain compression, P1dB, IM3, memory spectrum, output power, EVM and ACLR match independent/frozen vectors. Missing coefficients or unsupported model rejects planning; PA output power remains physically compressed. |
| **RF-008** | P1 | The production source has no complete CFR/DPD training, validation, coefficient ageing or interaction with the PA and measurement chain. | Implement bounded CFR and indirect-learning DPD profiles. Support memory-polynomial/GMP predistorters, separate training and holdout waveforms, coefficient normalization, adaptation stability, ageing/retraining, coefficient hashes and bypass comparison. | For declared PA profiles, DPD/CFR report pre/post PAPR, EVM, ACLR, SEM, output power and efficiency. Holdout improvement must satisfy acceptance margins without power normalization cheating. Unsupported DPD profiles fail planning. |
| **RF-009** | P0 | DAC bits are recorded but no explicit Tx DAC stage is present. ADC uses a simple scalar quantizer with rounded bit count and default full scale. Composite receiver code silently creates an AGC target of 0.25 full scale with plus/minus 120 dB limits. LNA/mixer/filter stages and dynamic state are incomplete. | Implement explicit DACModel, ReconstructionFilter, LNAProfile, MixerProfile, RFSelectivityFilter, stateful AGC, AntiAliasFilter and ADCModel. Quantizer profiles shall define signed code convention, mid-rise/mid-tread, clipping, full scale, ENOB, dither, INL/DNL and aperture jitter. No implicit AGC may be created in strict mode. | Code-level vectors, clipping thresholds, quantization SNR, filter response, AGC attack/release/hold, overload recovery and ADC code histograms pass. DAC/ADC bit depth is integer and explicit. Requested full scale is applied to actual samples. |
| **RF-010** | P1 | The composite receiver front end operates after signal summation, which is a useful integration point, but there is no complete wanted-plus-blocker RF filter/LNA/mixer nonlinearity model, IIP2/IIP3 state, reciprocal mixing or overload/desensitization campaign. | Create BlockerScenario, RFSelectivityFilter, LNAProfile, MixerProfile and ReceiverFrontEnd. Inject blockers and interferers as sample-domain carriers before the nonlinear/front-end stages. Model gain compression, IIP2/IIP3 products, reciprocal mixing from LO phase noise, AGC/ADC overload and post-filter covariance. | Reference sensitivity, ACS/selectivity, in-band/out-of-band blocking and receiver-intermodulation emulation cases produce expected frequencies, powers, desensitization and BLER. Scalar interference penalties are not accepted as RF blocker evidence. |
| **RF-011** | P0 | Current EVM is a direct sample-domain RMS difference between pre- and post-chain waveforms. Exact synchronization, carrier leakage removal, reference equalization, allocated-RE selection, measurement interval and ACLR/SEM/OBUE filters are not implemented broadly. | Implement EVMMeasurement, FrequencyErrorMeasurement, ACLRMeasurement, SpectrumEmissionMeasurement, InBandEmissionMeasurement and carrier/image leakage measurements with profile-specific reference plane, synchronization, correction, FFT/RBW/filter, window, averaging and occupied-resource rules. Conformance profiles are emulation only. | Independent ideal and impaired vectors pass. EVM is calculated after permitted timing/frequency correction and carrier-leakage removal at the correct REs. ACLR/SEM/OBUE integrate exact filter bands. Measurement configuration and source waveform hashes are exported. |
| **RF-012** | P0 | PUSCH power control defaults to enabled, may derive pathloss from configured SNR, defaults P0/alpha/PCMAX/deltaTF/TPC, clamps alpha, omits the explicit numerology factor in the allocated-bandwidth term and mutates configuration with the result. Complete PUCCH, SRS and PRACH loops are not integrated. | Create event-sourced UplinkPowerControlState and separate PUSCH/PUCCH/SRS/PRACH controllers. Resolve pathloss from the configured pathloss-reference RS measurement, P0, alpha, 10log10(2^mu*M_RB), deltaTF, TPC accumulation/absolute mode, closed-loop index, PCMAX and simultaneous-channel power sharing. Apply requested power to the actual waveform. | Exact analytical vectors pass for all selected channels. No configured-SNR-derived pathloss or silent default is allowed. Requested, applied and measured waveform power reconcile within 0.05 dB; TPC command timing and saturation/convergence are proven. |
| **RF-013** | P1 | Post-front-end noise variance is replayed mainly by AGC gain plus step squared over six ADC quantization variance. This assumes additive white independent quantization noise and does not propagate IQ, filters, clipping, phase noise, nonlinearities or correlated per-chain noise. | Implement Friis cascade noise figure, filter ENBW, per-stage noise temperature, correlated per-chain noise, colored noise, LO reciprocal-mixing noise and sample-derived post-ADC covariance. Quantization/clipping covariance must be measured from actual error samples, not assumed white unless an explicitly validated approximation profile is selected. | Friis and thermal-noise vectors pass; sample covariance matches the exported receiver covariance; noise and interference transformation through all linear stages is exact; nonlinear/quantized stages use actual sample error and confidence intervals. |
| **RF-014** | P1 | Existing tests prove several stages are present but do not cover all interactions, multi-chain correlation, acquisition/tracking failures, blocker overload, power-control feedback, long waveform state continuity or independent waveform-quality evidence. | Add a phase runner and impact runner over isolated impairments, pairwise interactions and end-to-end profiles. Preserve oscillator/resampler/AGC/DPD/power-control state across slots. Inject no-signal, false-lock, wrong-profile, saturation, stale-state, nonfinite and unsupported combinations. Use named random streams and deterministic parallel merge. | All selected capability rows execute or reject as declared; multi-seed BLER/EVM/ACLR/power/false-lock campaigns complete; serial and parallel artifacts match; every required CSV and PNG passes the verifier; full repository regression remains passing. |

## Canonical production package

Create or consolidate:

```text
+sixgr/+rf/+runtime/
    RFSpecificationProfile.m
    RFCapabilityProfile.m
    RFPlanningResult.m
    RFChainConfiguration.m
    RFReferencePlane.m
    RFStateTrace.m
    RFStageLedger.m
    AbsolutePowerLedger.m
    OFDMScalingLedger.m
    NoisePowerLedger.m
    OscillatorState.m
    CFOState.m
    CFOAcquisitionEngine.m
    CFOTrackingLoop.m
    TimingAcquisitionEngine.m
    TimingTrackingLoop.m
    SampleClockState.m
    StatefulSampleRateOffsetResampler.m
    PhaseNoiseProfile.m
    PhaseNoiseProcess.m
    PhaseNoiseCorrelationState.m
    IQImbalanceProfile.m
    IQImbalanceEstimator.m
    IQImbalanceCompensator.m
    DCOffsetAndLOLeakage.m
    DACModel.m
    ReconstructionFilter.m
    PAProfile.m
    MemoryPolynomialPA.m
    GeneralizedMemoryPolynomialPA.m
    DPDProfile.m
    DPDTrainer.m
    CrestFactorReduction.m
    LNAProfile.m
    MixerProfile.m
    RFSelectivityFilter.m
    AGCState.m
    ADCModel.m
    AntiAliasFilter.m
    BlockerScenario.m
    IntermodulationScenario.m
    ReceiverFrontEnd.m
    TransmitterFrontEnd.m
    UplinkPowerControlState.m
    PUSCHPowerController.m
    PUCCHPowerController.m
    SRSPowerController.m
    PRACHPowerController.m
    EVMMeasurement.m
    ACLRMeasurement.m
    SpectrumEmissionMeasurement.m
    InBandEmissionMeasurement.m
    FrequencyErrorMeasurement.m
    TimeAlignmentMeasurement.m
    RFArtifactExporter.m
    runRFFrontEndPhaseValidation.m
    runRFFrontEndImpactAnalysis.m

+sixgr/+rf/+runtime/+oracle/
    CFOAnalyticalSpec.m
    FractionalDelaySpec.m
    ResamplingSpec.m
    IQWidelyLinearSpec.m
    PhaseNoisePSDOracle.m
    RappSalehSpec.m
    MemoryPolynomialSpec.m
    QuantizerSpec.m
    FriisNoiseFigureSpec.m
    PowerControlSpec.m
    EVMReferenceSpec.m
    ACLRFilterSpec.m
```

Existing `RFImpairments`, `PAModel`, `PhaseNoiseModel`, `applyRFImpairmentChain`, `PowerContext`, `applyPowerContext`, CFO estimators and composite-front-end helpers may remain only as compatibility facades. They must delegate to the canonical runtime and cannot retain independent hidden defaults.

## Exact RF reference-plane and power contract

Use a reference-plane enum rather than free text. At minimum support:

```text
DIGITAL_LAYER_PORT
POST_PRECODER_DIGITAL
DAC_INPUT
DAC_OUTPUT
POST_RECONSTRUCTION_FILTER
PA_INPUT
PA_OUTPUT
TX_ANTENNA_CONNECTOR_OR_DECLARED_TAB
RX_ANTENNA_CONNECTOR_OR_DECLARED_TAB
LNA_INPUT
LNA_OUTPUT
MIXER_OUTPUT
POST_SELECTIVITY_FILTER
AGC_INPUT
ADC_INPUT
ADC_OUTPUT
SYNCHRONIZED_BASEBAND
EQUALIZED_RE
```

For every stage `k`:

```text
Pout_dBm = Pin_dBm + Gain_k_dB - Loss_k_dB + NonlinearPowerChange_k_dB
```

The ledger records:

```text
complex sample unit
reference impedance
sample rate
occupied bandwidth
noise-equivalent bandwidth
per-port and total power
average and peak power
PAPR
gain/loss/compression
PSD
calibration and configuration epoch
```

For thermal noise:

```text
N_dBm = -174 dBm/Hz + 10*log10(B_ENBW_Hz) + NF_dB
```

For cascaded noise factor:

```text
F_total = F1 + (F2-1)/G1 + (F3-1)/(G1*G2) + ...
NF_total_dB = 10*log10(F_total)
```

`B_ENBW` must come from the actual filter response or an explicitly validated rectangular profile; channel bandwidth is not automatically equal to ENBW.

## CFO and oscillator implementation

Use separate transmitter and receiver oscillator state:

```text
f_relative(t) = f_tx_error(t) - f_rx_error(t) + f_link_doppler(t)
phase[n+1] = phase[n] + 2*pi*f_relative[n]/Fs + delta_phase_noise[n]
```

Define the sign once and use it throughout. The receiver chain shall perform:

```text
coarse time acquisition
integer-subcarrier CFO hypothesis search
fractional CP or reference-signal CFO estimate
hypothesis scoring and ambiguity rejection
sample-domain CFO correction
fine DM-RS/TRS tracking
residual CFO measurement
state prediction/update across slots
```

The strict estimator API cannot receive `TrueCFO_Hz`, transmitted CCE/DM-RS phase or a success flag. A false lock is a distinct failure, not a large error silently clipped into range.

## Timing and sample-clock implementation

Model:

```text
epsilon = SCO_ppm * 1e-6
t_rx[n] = (n + tau0) * (1 + epsilon) / Fs
```

A proper implementation needs:

```text
stateful fractional delay
stateful sample-rate conversion
polyphase/Farrow or equivalent bandlimited interpolation
anti-alias and reconstruction filters
persistent phase accumulator
input/output timestamp mapping
variable output sample count or explicit time-grid contract
acquisition and tracking-loop state
```

Delete the fixed-length `interp1(...,"linear",0)` shortcut from strict execution. Long-duration tests must show cumulative drift and chunk-boundary equality.

## Phase noise

An enabled strict phase-noise profile must provide:

```text
profile/version ID
offset-frequency and SSB PSD mask or calibrated oscillator parameters
sample rate and carrier frequency
common/independent LO topology
cross-chain correlation matrix
initial phase and persistent state
random-stream identity
```

Generate a continuous phase process whose measured PSD and integrated variance match the declared mask. Do not infer a mask from carrier frequency. Export:

```text
measured PSD at every mask point
integrated RMS phase
per-chain correlation
CPE and ICI power
PT-RS/TRS correction before/after metrics
```

## IQ imbalance, DC and LO leakage

Use the bounded widely-linear model:

```text
y[n] = alpha*x[n] + beta*conj(x[n]) + d[n]
alpha = 0.5*(1 + g*exp(-j*phi))
beta  = 0.5*(1 - g*exp(+j*phi))
IRR_dB = 20*log10(|alpha|/|beta|)
```

For frequency-selective profiles, `alpha` and `beta` become FIR filters with independent coefficient provenance. Estimate receiver correction from pilots/training or blind statistics. Never supply configured alpha/beta directly to the strict receiver.

## PA, CFR and DPD

Support bounded, explicit PA families:

```text
Rapp memoryless
Saleh AM-AM/AM-PM
measured LUT
memory polynomial
GMP
```

Memory polynomial form:

```text
y[n] = sum_m sum_p a[p,m] x[n-m] |x[n-m]|^(p-1)
```

A GMP profile may add lagging/leading envelope cross terms. Every coefficient matrix has units, sample rate, bandwidth, operating temperature, extraction dataset and SHA-256.

Do not normalize `y` back to input power. Measure:

```text
small-signal gain
P1dB
AM-AM and AM-PM
IIP3/OIP3 or declared equivalent
input/output power
PAPR
EVM
ACLR
SEM/OBUE margin
```

DPD/CFR must use separate training and holdout data. The holdout waveform—not the training waveform—decides acceptance. Export coefficient hashes and convergence/ageing state.

## DAC, receiver front end, AGC and ADC

The Tx chain shall include:

```text
CFR/DPD → DAC code generation → zero-order/declared reconstruction behavior → reconstruction filter → IQ/LO/PA
```

The Rx chain shall include:

```text
RF selectivity → LNA → mixer/LO phase noise → baseband filter → stateful AGC → anti-alias filter → ADC
```

Each quantizer profile defines:

```text
integer bit depth
signed code range
mid-rise or mid-tread
full-scale voltage or normalized reference with impedance
clipping behavior
dither
ENOB
INL/DNL, when selected
aperture jitter, when selected
```

AGC is an explicit state machine with attack, release, hold, min/max gain, update delay and overload state. Remove automatic 0.25-full-scale/±120 dB AGC creation.

## Blocking and receiver intermodulation

Construct sample-domain blocker scenarios before the receiver nonlinear/front-end chain. For two tones at `f1` and `f2`, verify products including:

```text
2*f1 - f2
2*f2 - f1
f1 + f2
|f1 - f2|
```

Model and report:

```text
RF/baseband filter rejection
LNA/mixer compression
IIP2/IIP3-derived products
LO reciprocal mixing from phase noise
AGC response
ADC clipping
desensitization
post-front-end SINR/EVM/BLER
```

A configured scalar interference penalty is not a blocker or intermodulation simulation.

## Waveform-quality measurements

### EVM

EVM measurement must declare:

```text
reference plane
allocated signal and RE set
measurement interval
allowed timing/frequency correction
carrier-leakage removal
equalizer/reference-channel treatment
RMS averaging rule
modulation-specific limit table and applicability
```

Use:

```text
EVM_rms = sqrt(sum |x_meas - x_ref|^2 / sum |x_ref|^2)
```

but only after the profile-specific synchronization/correction and on the correct symbols/REs. Direct pre-chain versus post-chain sample RMS is not an RF EVM method.

### ACLR

Use actual filtered powers:

```text
ACLR_lower = 10*log10(P_assigned / P_adjacent_lower)
ACLR_upper = 10*log10(P_assigned / P_adjacent_upper)
```

The assigned and adjacent filters, bandwidths and frequency offsets come from the pinned profile table. Export the filter impulse/response digest.

### SEM/OBUE and in-band emission

Measure PSD/power in the exact resolution bandwidth, offsets and averaging windows. Limits are table-driven by band, channel bandwidth, BS class/UE profile, spectrum arrangement and reference plane.

## Exact UL power-control implementation

Create separate event-sourced controllers for PUSCH, PUCCH, SRS and PRACH. For the bounded PUSCH profile implement the selected TS 38.213 procedure in the form:

```text
P_PUSCH = min(
    P_CMAX,
    P0_PUSCH
    + 10*log10(2^mu * M_RB)
    + alpha * PL
    + Delta_TF
    + f_TPC
)
```

This equation is only a compact representation; the production implementation must resolve the exact selected state/index/pathloss-reference procedure, serving cell, BWP, closed-loop index, TPC mode and simultaneous-transmission constraints.

Requirements:

```text
pathloss comes from the configured reference-RS measurement
TPC commands come from decoded DCI/control events
accumulation/absolute mode is explicit
command timing and configuration epoch are checked
P_CMAX and power sharing are applied before waveform scaling
requested/applied/measured powers are all exported
```

Implement corresponding selected PUCCH, SRS and PRACH procedures. Delete configured-SNR-derived pathloss and all silent defaults.

## Noise and covariance

Propagate linear-stage signal/noise covariance through the actual matrices/filters. For nonlinear and quantized stages, derive error samples and covariance from the actual stage input/output:

```text
e[n] = y_actual[n] - y_linear_reference[n]
R_e = E[e e^H]
```

Do not always add `step^2/6` as white ADC noise. That approximation may exist only as an explicitly named, independently validated high-resolution/no-clipping profile.

## Capability matrix

`rf_capability_profile_matrix.csv` contains 210 explicit profile/feature tuples. Every row must produce exactly the declared `EXECUTE` or `REJECT` result. `unsupported_rf_device_conformance` must always reject.

## Independent vectors

Run and extend the supplied vectors for:

```text
CFO phase/frequency arithmetic
SCO accumulated drift and time-grid mapping
phase-noise PSD/integrated variance
IQ alpha/beta/image rejection
PA AM-AM/AM-PM and memory
quantizer codes and clipping
Friis noise figure and thermal noise
blocker/intermodulation frequencies
waveform-quality thresholds and methods
PUSCH/PUCCH/SRS/PRACH power-control arithmetic
negative fail-closed behavior
```

Rows marked as bounded analytical floors do not replace full conformance tables. Add exact frozen vectors before enabling any new band/class/test-method tuple.

## Impact analysis

Execute all 64 families and 768 controlled experiments. Every baseline/treatment pair shares:

```text
seed
trial ID
payload ID
channel realization
noise realization
initial RF state
```

Only the declared factor may change.

| Family | Analysis | Wave | Dependency |
|---|---|---|---|
| F01 | Static CFO magnitude | A | RF_FRONTEND_CORE |
| F02 | Integer CFO acquisition | A | RF_FRONTEND_CORE |
| F03 | Fractional CFO estimation | A | RF_FRONTEND_CORE |
| F04 | CFO drift and loop bandwidth | A | RF_FRONTEND_CORE |
| F05 | Doppler versus oscillator separation | B | INTERNAL_PHY_INTEGRATION |
| F06 | CFO estimator SNR | A | RF_FRONTEND_CORE |
| F07 | CFO false-lock probability | A | RF_FRONTEND_CORE |
| F08 | CFO chunk continuity | A | RF_FRONTEND_CORE |
| F09 | Integer timing offset | A | RF_FRONTEND_CORE |
| F10 | Fractional timing offset | A | RF_FRONTEND_CORE |
| F11 | SCO ppm drift | A | RF_FRONTEND_CORE |
| F12 | SCO tracking bandwidth | A | RF_FRONTEND_CORE |
| F13 | Resampler stopband and aliasing | A | RF_FRONTEND_CORE |
| F14 | Phase-noise mask severity | A | RF_FRONTEND_CORE |
| F15 | Phase noise versus carrier frequency | A | RF_FRONTEND_CORE |
| F16 | CPE versus ICI decomposition | A | RF_FRONTEND_CORE |
| F17 | Common versus independent LO | A | RF_FRONTEND_CORE |
| F18 | PT-RS phase-noise correction | B | INTERNAL_PHY_INTEGRATION |
| F19 | TX IQ amplitude mismatch | A | RF_FRONTEND_CORE |
| F20 | TX IQ phase mismatch | A | RF_FRONTEND_CORE |
| F21 | RX IQ imbalance | A | RF_FRONTEND_CORE |
| F22 | Frequency-selective IQ imbalance | A | RF_FRONTEND_CORE |
| F23 | DC offset and LO leakage | A | RF_FRONTEND_CORE |
| F24 | IQ compensation convergence | A | RF_FRONTEND_CORE |
| F25 | PA input/output backoff | A | RF_FRONTEND_CORE |
| F26 | PA model family | A | RF_FRONTEND_CORE |
| F27 | AM-PM distortion | A | RF_FRONTEND_CORE |
| F28 | PA memory depth | A | RF_FRONTEND_CORE |
| F29 | Cross-carrier PA memory | B | INTERNAL_PHY_INTEGRATION |
| F30 | Crest-factor reduction | A | RF_FRONTEND_CORE |
| F31 | DPD order and memory | A | RF_FRONTEND_CORE |
| F32 | DPD coefficient ageing | A | RF_FRONTEND_CORE |
| F33 | DAC bit depth | A | RF_FRONTEND_CORE |
| F34 | ADC bit depth | A | RF_FRONTEND_CORE |
| F35 | ADC full scale | A | RF_FRONTEND_CORE |
| F36 | Clipping probability | A | RF_FRONTEND_CORE |
| F37 | Dither | A | RF_FRONTEND_CORE |
| F38 | Aperture jitter | A | RF_FRONTEND_CORE |
| F39 | AGC target | A | RF_FRONTEND_CORE |
| F40 | AGC attack and release | A | RF_FRONTEND_CORE |
| F41 | LNA noise figure | A | RF_FRONTEND_CORE |
| F42 | Cascaded noise figure | A | RF_FRONTEND_CORE |
| F43 | Blocker power | B | INTERNAL_PHY_INTEGRATION |
| F44 | Blocker frequency offset | B | INTERNAL_PHY_INTEGRATION |
| F45 | Reciprocal mixing | B | INTERNAL_PHY_INTEGRATION |
| F46 | Receiver IIP2 | B | INTERNAL_PHY_INTEGRATION |
| F47 | Receiver IIP3 | B | INTERNAL_PHY_INTEGRATION |
| F48 | ADC overload under blocker | B | INTERNAL_PHY_INTEGRATION |
| F49 | EVM measurement correction | A | RF_FRONTEND_CORE |
| F50 | ACLR measurement | A | RF_FRONTEND_CORE |
| F51 | SEM and OBUE | B | INTERNAL_PHY_INTEGRATION |
| F52 | Carrier and image leakage | A | RF_FRONTEND_CORE |
| F53 | PUSCH P0 | B | INTERNAL_PHY_INTEGRATION |
| F54 | PUSCH alpha | B | INTERNAL_PHY_INTEGRATION |
| F55 | Numerology and bandwidth term | B | INTERNAL_PHY_INTEGRATION |
| F56 | Delta TF | B | INTERNAL_PHY_INTEGRATION |
| F57 | TPC accumulation | B | INTERNAL_PHY_INTEGRATION |
| F58 | PCMAX clipping | B | INTERNAL_PHY_INTEGRATION |
| F59 | PUCCH power control | B | INTERNAL_PHY_INTEGRATION |
| F60 | SRS power control | B | INTERNAL_PHY_INTEGRATION |
| F61 | PRACH power ramping | B | INTERNAL_PHY_INTEGRATION |
| F62 | Simultaneous UL channel sharing | C | MULTI_CHANNEL_END_TO_END |
| F63 | Impairment interaction factorial | C | MULTI_CHANNEL_END_TO_END |
| F64 | End-to-end RF-impaired link | C | MULTI_CHANNEL_END_TO_END |

Statistical requirements:

```text
Wilson confidence interval for ordinary BLER/detection rates
one-sided Clopper-Pearson upper bound for zero false locks/false decodes
a paired McNemar test for binary paired outcomes
paired bootstrap confidence interval for EVM, ACLR, power, residual CFO/timing, latency and runtime
Holm adjustment for related families
predefined engineering effect margins
INCOMPLETE or INCONCLUSIVE when evidence is insufficient
```

The sign convention is always `treatment - baseline`.

## Mandatory MATLAB test suites

Add and execute all 72 tests:

- `testRFProfileSeparation` (RF-001)
- `testRFDeviceConformanceClaimRejected` (RF-001)
- `testRFReferencePlaneUnits` (RF-002)
- `testRFAbsolutePowerClosure` (RF-002)
- `testRFParsevalClosure` (RF-002)
- `testRFNoisePowerENBW` (RF-002)
- `testRelativeOscillatorState` (RF-003)
- `testIntegerCFOAcquisition` (RF-003)
- `testFractionalCFOCP` (RF-003)
- `testFractionalCFODMRS` (RF-003)
- `testCFOTrackingDrift` (RF-003)
- `testCFOFalseLock` (RF-003)
- `testCFOPhaseContinuity` (RF-003)
- `testTimingAcquisition` (RF-004)
- `testFractionalTimingCorrection` (RF-004)
- `testSCOStatefulResampler` (RF-004)
- `testSCOLongDrift` (RF-004)
- `testSCOAntiAlias` (RF-004)
- `testResamplerChunkContinuity` (RF-004)
- `testPhaseNoiseMaskPSD` (RF-005)
- `testPhaseNoiseIntegratedVariance` (RF-005)
- `testPhaseNoiseChunkContinuity` (RF-005)
- `testPhaseNoiseLOCorrelation` (RF-005)
- `testPhaseNoiseCPEICI` (RF-005)
- `testIQAnalyticalModel` (RF-006)
- `testFrequencySelectiveIQ` (RF-006)
- `testIQEstimatorNoOracle` (RF-006)
- `testIQCompensation` (RF-006)
- `testDCOffsetLOLeakage` (RF-006)
- `testPARappSaleh` (RF-007)
- `testPAMemoryPolynomial` (RF-007)
- `testPAGMP` (RF-007)
- `testPAP1dBIP3` (RF-007)
- `testPANoPowerRestoration` (RF-007)
- `testPAAMAMAMPM` (RF-007)
- `testCFRPAPR` (RF-008)
- `testDPDTraining` (RF-008)
- `testDPDHoldout` (RF-008)
- `testDPDAgeing` (RF-008)
- `testDACQuantizer` (RF-009)
- `testReconstructionFilter` (RF-009)
- `testLNAFilterChain` (RF-009)
- `testAGCAttackRelease` (RF-009)
- `testAGCOverloadRecovery` (RF-009)
- `testADCQuantizer` (RF-009)
- `testADCApertureJitter` (RF-009)
- `testNoImplicitAGC` (RF-009)
- `testReceiverBlocker` (RF-010)
- `testAdjacentChannelSelectivity` (RF-010)
- `testReceiverIIP2IIP3` (RF-010)
- `testReciprocalMixing` (RF-010)
- `testBlockerADCOverload` (RF-010)
- `testEVMMeasurementMethod` (RF-011)
- `testFrequencyErrorMeasurement` (RF-011)
- `testACLRMeasurement` (RF-011)
- `testSEMOBUEMeasurement` (RF-011)
- `testCarrierLeakageMeasurement` (RF-011)
- `testPUSCHPowerControlExact` (RF-012)
- `testPUCCHPowerControlExact` (RF-012)
- `testSRSPowerControlExact` (RF-012)
- `testPRACHPowerControlExact` (RF-012)
- `testTPCAccumulation` (RF-012)
- `testPCMAXPowerSharing` (RF-012)
- `testNoConfiguredSNRPathloss` (RF-012)
- `testFriisNoiseCascade` (RF-013)
- `testColoredCorrelatedNoise` (RF-013)
- `testQuantizationErrorCovariance` (RF-013)
- `testReceiverCovarianceClosure` (RF-013)
- `testRFInteractionFactorial` (RF-014)
- `testRFNoSignalNegativeMatrix` (RF-014)
- `testRFSerialParallelReproducibility` (RF-014)
- `testRFArtifactGeneration` (RF-014)

Add positive, negative, boundary, no-signal, false-lock, wrong-profile, stale-state, saturation, clipping, chunk-continuity, serial/parallel and interaction tests.

## Required base CSV artifacts

- `rf_profile_resolution.csv`
- `rf_chain_stage_ledger.csv`
- `rf_reference_plane_power.csv`
- `rf_cfo_acquisition.csv`
- `rf_cfo_tracking.csv`
- `rf_timing_acquisition.csv`
- `rf_timing_tracking.csv`
- `rf_sco_resampler.csv`
- `rf_phase_noise_psd.csv`
- `rf_phase_noise_tracking.csv`
- `rf_iq_imbalance.csv`
- `rf_iq_compensation.csv`
- `rf_pa_characterization.csv`
- `rf_pa_memory.csv`
- `rf_dpd_training.csv`
- `rf_dpd_validation.csv`
- `rf_dac_quantization.csv`
- `rf_agc_trace.csv`
- `rf_adc_quantization.csv`
- `rf_noise_figure_cascade.csv`
- `rf_blocker_trials.csv`
- `rf_intermodulation_trials.csv`
- `rf_receiver_dynamic_range.csv`
- `rf_evm_measurement.csv`
- `rf_aclr_measurement.csv`
- `rf_sem_obue_measurement.csv`
- `rf_ul_power_control.csv`
- `rf_power_control_state.csv`
- `rf_receiver_metrics.csv`
- `rf_negative_tests.csv`
- `rf_test_summary.csv`
- `rf_image_semantic_audit.csv`

## Required base PNG artifacts

- `rf_chain_reference_planes.png`
- `rf_cfo_acquisition_tracking.png`
- `rf_cfo_residual_vs_snr.png`
- `rf_timing_tracking.png`
- `rf_sco_drift_resampling.png`
- `rf_phase_noise_mask.png`
- `rf_phase_noise_cpe_ici.png`
- `rf_iq_constellation_image.png`
- `rf_iq_compensation.png`
- `rf_pa_amam_ampm.png`
- `rf_pa_memory_spectrum.png`
- `rf_dpd_aclr_evm.png`
- `rf_dac_adc_quantization.png`
- `rf_agc_overload_trace.png`
- `rf_noise_figure_cascade.png`
- `rf_blocker_desensitization.png`
- `rf_intermodulation_spectrum.png`
- `rf_evm_by_modulation.png`
- `rf_aclr_spectrum.png`
- `rf_sem_obue_spectrum.png`
- `rf_ul_power_control_convergence.png`
- `rf_end_to_end_bler.png`

## Required impact CSV artifacts

- `rf_impact_run_manifest.csv`
- `rf_impact_raw_trials.csv`
- `rf_impact_operating_points.csv`
- `rf_impact_pairwise_effects.csv`
- `rf_impact_rule_evaluation.csv`
- `rf_impact_cfo_timing.csv`
- `rf_impact_phase_noise_iq.csv`
- `rf_impact_pa_dpd.csv`
- `rf_impact_data_converters.csv`
- `rf_impact_blocker_receiver.csv`
- `rf_impact_waveform_quality.csv`
- `rf_impact_power_control.csv`
- `rf_impact_runtime.csv`
- `rf_impact_interactions.csv`
- `rf_impact_summary.csv`
- `rf_impact_image_semantic_audit.csv`

## Required impact PNG artifacts

- `rf_impact_cfo_magnitude.png`
- `rf_impact_cfo_tracking.png`
- `rf_impact_timing_offset.png`
- `rf_impact_sco_drift.png`
- `rf_impact_phase_noise_mask.png`
- `rf_impact_phase_noise_cpe_ici.png`
- `rf_impact_lo_correlation.png`
- `rf_impact_iq_imbalance.png`
- `rf_impact_iq_compensation.png`
- `rf_impact_pa_backoff.png`
- `rf_impact_pa_memory.png`
- `rf_impact_cfr_papr.png`
- `rf_impact_dpd_order.png`
- `rf_impact_dpd_ageing.png`
- `rf_impact_dac_bits.png`
- `rf_impact_adc_bits.png`
- `rf_impact_adc_fullscale.png`
- `rf_impact_agc_dynamics.png`
- `rf_impact_aperture_jitter.png`
- `rf_impact_noise_figure.png`
- `rf_impact_blocker_power.png`
- `rf_impact_blocker_offset.png`
- `rf_impact_reciprocal_mixing.png`
- `rf_impact_intermodulation.png`
- `rf_impact_evm_method.png`
- `rf_impact_aclr.png`
- `rf_impact_sem_obue.png`
- `rf_impact_power_control.png`
- `rf_impact_interaction_forest.png`
- `rf_impact_runtime_scaling.png`

Every PNG must be regenerated from the corresponding production CSV. `rf_image_semantic_audit.csv` and `rf_impact_image_semantic_audit.csv` must record title, axes, series count, finite points, dimensions, source-CSV SHA-256 and PNG SHA-256.

## Mandatory execution commands

```bash
python tests/vectors/rf/verify_rf_vector_pack.py tests/vectors/rf
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*RF*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*CFO*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Timing*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PowerControl*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*EVM*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.rf.runtime.runRFFrontEndPhaseValidation( ...
    'VectorRoot',fullfile(pwd,'tests','vectors','rf'), ...
    'OutputDir',fullfile(pwd,'artifacts','rf_frontend_phase'), ...
    'SeedList',[11 23 47 89], ...
    'ConfidenceLevel',0.95, ...
    'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/rf/verify_rf_artifacts.py artifacts/rf_frontend_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.rf.runtime.runRFFrontEndImpactAnalysis( ...
    'ExperimentMatrix',fullfile(pwd,'tests','vectors','rf','rf_impact_experiment_matrix.csv'), ...
    'OutputDir',fullfile(pwd,'artifacts','rf_frontend_impact'), ...
    'SeedList',[11 23 47 89 131 197], ...
    'ConfidenceLevel',0.95, ...
    'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/rf/verify_rf_impact_artifacts.py artifacts/rf_frontend_impact
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

## Required Codex work pattern

For each dependency-ordered phase:

1. Read the assigned finding rows and current source evidence.
2. Add a failing production test before changing implementation.
3. Modify the live source and migrate every caller.
4. Add independent vectors or frozen references.
5. Run the focused tests and all previously closed RF tests.
6. Generate production CSV/PNG artifacts from actual MATLAB execution.
7. Run the Python artifact verifier.
8. Commit a phase-sized change with finding IDs.
9. Report exact commands, toolchain versions, files changed, test counts, artifact hashes and remaining dependencies.

## Codex may not report COMPLETE while any of these remain

```text
one RF chain mixing ideal/research/emulation claims
RF-device conformance or certification wording
legacy/global aliases in the strict path
silent Tx power/gain/NF/full-scale defaults
simple CFO injection without blind acquisition/tracking evidence
true CFO/timing/IQ state supplied to receiver correction
fixed-length linear-interpolation SCO
heuristic phase-noise mask
phase-noise state reset between chunks
configured IQ correction coefficients
soft-limiter PA fallback
PA output-power restoration
unversioned PA/DPD coefficients
missing DAC stage
rounded ADC bits or implicit full scale
hidden automatic AGC
step^2/6 quantization covariance used universally
scalar blocker/intermodulation penalty
sample-domain direct EVM presented as RF EVM
missing ACLR/SEM/OBUE filters
configured-SNR-derived pathloss
missing 2^mu bandwidth term
TPC not driven by decoded events
requested power not applied to actual waveform
same-Toolbox result labelled independent
mandatory MATLAB test skipped or blocked
mandatory impact point incomplete
required CSV or PNG absent
artifact verifier returning nonzero
complete repository regression failing
```

## Definition of done

```text
All 14 findings closed for enabled profiles
All 72 mandatory MATLAB tests executed and passed
All 210 capability rows resolved correctly
All independent vector mismatches are zero
All RF reference planes reconcile within 0.05 dB
CFO/timing/SCO acquisition and tracking pass without oracle input
Phase-noise PSD, continuity and correlation pass
IQ estimation/compensation pass
PA compression/memory and DPD holdout pass without power restoration
DAC/AGC/ADC and blocker/intermodulation chains pass
EVM/ACLR/SEM/OBUE methods pass for selected emulation profiles
PUSCH/PUCCH/SRS/PRACH power-control loops pass
All 768 impact experiments execute
All 96 acceptance rules have valid evidence
All 48 CSVs pass
All 52 PNGs pass
Both artifact verifiers return exit code 0
Complete repository MATLAB regression passes
```

At the end of each Codex response report:

```text
phase and finding IDs
files changed
architectural decisions
exact equations/tables implemented
tests added and executed
commands and results
CSV row counts and hashes
PNG dimensions and hashes
closed/open findings
blocked dependencies
remaining claim restrictions
next dependency-ordered phase
```
