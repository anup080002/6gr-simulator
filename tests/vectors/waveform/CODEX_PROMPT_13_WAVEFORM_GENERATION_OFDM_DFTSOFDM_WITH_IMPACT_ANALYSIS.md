# CODEX IMPLEMENTATION PROMPT 13 — WAVEFORM GENERATION, CP-OFDM, DFT-s-OFDM, MULTI-NUMEROLOGY AND SPECTRAL VALIDATION

## Mission

You are the lead MATLAB waveform, OFDM, transform-precoding, multi-numerology and spectral-validation engineer for this repository. This task is **not a review**, **not a documentation-only exercise**, and **not a truth-contract exercise**. Modify the production MATLAB waveform chain and execute the corrected implementation.

Close all 20 `WF-*` findings for the selected bounded profiles. Preserve correct Toolbox-backed kernels, but remove every silent waveform change, reduced-IFFT shortcut, parameter fallback, configured study flag and self-reference identified in `current_waveform_static_audit.csv`.

Implement this causal chain:

```text
pinned waveform profile + carrier/BWP/numerology context
    ↓
canonical Nfft / sample-rate / CP / symbol-time resolution
    ↓
zero-based RE-to-FFT-bin mapping with DC and guard ownership
    ↓
per-layer and per-port resource grids in an explicit power domain
    ↓
optional normative single-layer DFT spreading from decoded PUSCH state
    ↓
IFFT and CP insertion using one production OFDM engine
    ↓
explicit rectangular or research WOLA/filtering profile
    ↓
persistent stream state across symbols, slots, frames and chunks
    ↓
optional common-clock multi-numerology / multi-component-carrier composition
    ↓
channel, interference and RF front end
    ↓
receiver acquisition, CP removal, FFT, grid extraction and optional despreading
    ↓
no-noise/grid/bit closure + EVM/PAPR/PSD/OOB/ISI/ICI/BLER measurements
```

## Repository inputs

Place this pack under `tests/vectors/waveform/`. Treat the following as immutable test definitions and bounded independent analytical floors:

- `waveform_generation_20_findings.csv`
- `waveform_capability_profile_matrix.csv`
- `waveform_declared_coverage_matrix.csv`
- `waveform_implementation_task_graph.csv`
- `waveform_matlab_test_plan.csv`
- `waveform_error_contract.csv`
- `independent_vector_manifest.json`
- all `waveform_*_test_vectors.csv`
- all `expected_waveform_*.csv`
- all `desired_waveform*_contract.csv`
- all three Python verifiers.

Never copy an expected CSV into a production artifact directory. Production CSVs must be serialized from actual MATLAB runtime objects and actual generated samples.

## Pinned specification baseline

Pin every strict run to exact versions and record them in every output:

```text
3GPP TS 38.211 V19.3.0 (Release 19, 2026-04) — numerology, modulation, OFDM signal generation and transform precoding
3GPP TS 38.214 exact selected V19.x — PUSCH transform-precoding procedure and scheduling constraints
3GPP TS 38.331 exact selected V19.x — carrier/BWP and waveform-related RRC configuration
MATLAB release
5G Toolbox release
```

The strict PUSCH transform-precoding profile follows TS 38.211 clause 6.3.1.4: transform precoding is single-layer and uses a unitary DFT. The selected localized allocation uses `M = 12*N_RB` and permits only sizes whose prime factors are 2, 3 and 5. Do not enable a multi-layer or downlink DFT-s-OFDM candidate under a normative Release-19 profile.

Release-20/6G waveform work is a study context. A study flag is not an implementation. Every study candidate must have a mathematical definition, actual transmitter, receiver, reference-signal treatment, channel integration, independent vectors and impact tests before planning returns EXECUTE.

## Profile boundary

| Profile | Claim boundary | Executable scope |
|---|---|---|
| `nr_rel19_cp_ofdm_strict` | Release-19 normative NR waveform | CP-OFDM only, explicit supported numerology/CP/grid tuples, rectangular waveform by default |
| `nr_rel19_ul_dfts_ofdm_strict` | Release-19 normative UL transform-precoded PUSCH | Single-layer localized DFT-s-OFDM, valid DFT sizes, contiguous allocation, selected modulations |
| `nr_rel19_multinumerology_strict` | Bounded NR implementation profile | Explicit synchronized multi-BWP/multi-numerology and selected two-CC composition |
| `rel20_6g_waveform_study` | Non-normative 6G study | Only candidates with complete mathematical TX/RX and independent evidence |
| `waveform_research_candidate` | Implementation research | Explicit WOLA/filtering/low-PAPR candidates; no 3GPP normative claim |
| `unsupported_extension` | Non-executable | OTFS/AFDM/UFMC/FBMC or any candidate not fully implemented |

## Non-negotiable rules

1. Edit production MATLAB source and migrate all live callers. Do not return a plan-only response.
2. Consolidate one canonical runtime under `+sixgr/+phy/+waveform/`; do not add an unused parallel waveform stack.
3. Strict NR CP-OFDM defaults to `WindowingSamples=0`. Nonzero WOLA/filtering is explicit research or implementation-specific behavior.
4. Never use `nextpow2`, a default Nfft, a default sample rate, a default CP, or a synthesized carrier after a strict resolution failure.
5. Never compare a wrapper around `nrOFDMModulate` only against `nrOFDMModulate` and call it independent validation.
6. All zero-based RE, subcarrier, FFT-bin, sample and absolute-time indices must be exported and internally consistent.
7. Preserve stream state across arbitrary chunk boundaries: sample count, phase, window overlap, filter state, resampler state and digital-upconversion state.
8. Transform precoding is consumed from a decoded scheduling assignment. Modulation or a waveform string cannot independently enable it.
9. Strict transform-precoded PUSCH is single layer. Multi-layer DFT-s-OFDM remains a separate non-normative study profile.
10. Replace `runULLowPAPR`'s hand-written IFFT/CP/DFT chain with the canonical production waveform engine.
11. Every low-PAPR comparison must use paired identical bits, resource allocation, power, sample rate, channel and noise.
12. PAPR must be evaluated with an explicit reference domain and oversampling-convergence study. A native-rate maximum alone is not sufficient.
13. Every PSD/OOB/guard-leakage result must record sample rate, analysis window, FFT size, RBW, segment overlap, averaging and integration bands.
14. Layer/grid/port/useful-sample/CP/window/composite-carrier power must reconcile through one ledger.
15. Multi-numerology and component-carrier composition must use one common sample clock and phase-continuous digital frequency shifts.
16. A YAML flag alone cannot prove tone reservation, truncation, FDSS, flexible DFT, noncontiguous mapping, OTFS, AFDM, UFMC, FBMC or any other candidate.
17. Same-Toolbox comparisons are self-consistency only. Mandatory small FFT, CP, DFT, pi/2-BPSK, PAPR and spectral checks require pure-math or frozen independent vectors.
18. Missing MATLAB, skipped/blocked mandatory tests, incomplete operating points, absent CSV/PNG or a nonzero verifier exit code means the phase is not complete.

## The 20 findings to implement

| ID | Priority | Current technical defect | Required production correction | Mandatory acceptance |
|---|---:|---|---|---|
| **WF-001** | P0 | Normative NR CP-OFDM, normative single-layer UL DFT-s-OFDM, and Release-20/research waveform candidates are selected through overlapping strings and flags without one executable capability boundary. | Create WaveformSpecificationProfile, WaveformCapabilityProfile and WaveformPlanningResult. Separate nr_rel19_cp_ofdm_strict, nr_rel19_ul_dfts_ofdm_strict, nr_rel19_multinumerology_strict, rel20_6g_waveform_study, waveform_research_candidate and unsupported_extension. | Every capability tuple resolves to EXECUTE or REJECT before samples are generated. Research candidates never inherit a normative pass. |
| **WF-002** | P0 | Absent OFDM-windowing configuration silently becomes round(0.025*Nfft), so the strict waveform is changed from rectangular CP-OFDM without an explicit study profile. | Strict NR profiles default WindowingSamples=0. Add an explicit WindowingProfile/WOLAEngine for research or implementation-specific spectral shaping, with overlap state and a matched receiver. | Deleting the windowing setting leaves strict waveform rectangular. WOLA runs only when explicitly selected, and exports EVM/OOB/ISI trade-offs. |
| **WF-003** | P0 | When nrOFDMInfo fails, Nfft is synthesized with nextpow2(max(128,12*NSizeGrid)); this can silently execute a sample rate and CP plan different from the requested carrier. | Add OFDMParameterResolver driven by the pinned carrier/numerology/BWP/common-sample-rate profile. Unsupported or inconsistent Nfft/SampleRate/CP tuples fail; no nextpow2 fallback is allowed. | All supported carrier tuples match nrOFDMInfo and independent timing invariants. Every invalid tuple produces a typed planning error and no waveform. |
| **WF-004** | P1 | The canonical OFDM wrappers are thin calls to nrOFDMModulate/nrOFDMDemodulate, while important acceptance tests compare the wrapper to the same Toolbox implementation. | Keep Toolbox kernels, but add pure-math small-FFT, CP, bin-map, Parseval and round-trip oracles. Mark Toolbox-to-Toolbox checks as self-consistency only. | Injected bin, CP, scaling, phase and sample-index errors are detected by independent vectors. |
| **WF-005** | P0 | There is no single explicit contract for zero-based subcarrier coordinates, DC placement, guard carriers, Point-A/BWP offsets, FFT-bin order and carrier-frequency phase convention across every waveform producer. | Add SubcarrierMapper, OFDMSymbolPlan and WaveformFrequencyReference. Export the complete RE-to-FFT-bin map and reject any out-of-grid or duplicate ownership. | Every occupied RE maps to exactly one FFT bin and round-trips to the same RE. DC/guard/BWP offset negative tests fail closed. |
| **WF-006** | P0 | Waveform generation is mostly slot-local. Persistent phase, WOLA overlap, filter, resampler and digital-upconversion state across slots/frames is not one canonical object. | Create OFDMStreamState and WaveformStreamComposer with absolute sample time, NCO phase, overlap samples, filter state, frame/slot identity and deterministic chunking. | One-shot and arbitrarily chunked generation are sample-identical within tolerance; no slot-boundary discontinuity or duplicated/dropped sample exists. |
| **WF-007** | P0 | runULLowPAPR clamps N_RB, hard-codes 14 symbols, uses CP=round(Nsc/16), and uses the occupied subcarrier count as IFFT size, with no NR grid/guard/DC/common sample-rate mapping. | Remove the hand-written CP-OFDM path. Generate CP-OFDM through the same canonical carrier/grid/OFDM engine used by PDSCH/PUSCH. | Low-PAPR experiments use identical payload, resources, sample rate, CP, power and channel for baseline/treatment; the current reduced IFFT path is unreachable. |
| **WF-008** | P0 | runULLowPAPR applies an M-point DFT and then an M-point IFFT over the full occupied band. The two transforms substantially cancel, so it is not a faithful localized DFT-spread OFDM waveform. | Implement UnitaryDFTSpreader followed by localized mapping of M DFT outputs into an Nfft OFDM grid with Nfft>M, then canonical CP-OFDM generation. | Independent DFT coefficients, mapping indices, time samples, no-noise despreading and spectral localization all pass. |
| **WF-009** | P0 | Transform precoding can be auto-enabled from waveform/modulation strings; validity of one layer, permitted DFT sizes, contiguous allocation and PT-RS-aware symbol sets is not centrally enforced. | Create TransformPrecodingPlan from the decoded PUSCH assignment. Enforce the pinned TS 38.211 rules, including single layer and M=12*N_RB with only 2/3/5 prime factors for the selected strict profile. | Every valid DFT size round-trips; rank>1, noncontiguous allocation, invalid size and stale assignment fail before waveform generation. |
| **WF-010** | P1 | pi/2-BPSK is selectable, but exact symbol-index rotation, scrambling/DM-RS coupling and independent spectrum/PAPR verification are incomplete. | Add PiOver2BPSKMapper with exact symbol-index convention and use the production scrambling/procedure context. Add independent full-sequence vectors. | Bit-exact constellation, phase progression, despreading, EVM, PSD and PAPR results pass for odd/even offsets and chunk boundaries. |
| **WF-011** | P1 | PAPR is mainly measured at the native sample rate and summarized as an average/worst port; oversampling convergence, CCDF confidence, CP/window inclusion and multi-port/EIRP reference domains are not fully specified. | Add PAPRMeasurement with oversampling factors 1/2/4/8, interpolation filtering, per-port and aggregate reference domains, CP/window selection and empirical CCDF confidence intervals. | Reported PAPR converges with oversampling; CCDF points have trial counts/confidence bounds; treatment comparisons use paired identical payloads. |
| **WF-012** | P0 | Tone reservation, frequency-domain truncation, flexible DFT size, noncontiguous mapping, enhanced DM-RS/data multiplexing and multi-layer DFT-s-OFDM are exposed in YAML without complete causal waveform implementations. | Move each to an explicit study capability. Implement only through dedicated typed engines with exact resource ownership, receiver inversion and independent vectors; otherwise reject planning. | A flag alone cannot change samples or claim support. Unsupported rows return typed errors with no waveform/state mutation. |
| **WF-013** | P1 | There is no complete research WOLA/filtering engine with persistent overlap, transmit/receive matching, group delay, spectral masks, EVM and ISI/ICI accounting. | Implement explicit rectangular, WOLA and selected filtered-OFDM research profiles with coefficients, overlap, group delay, receiver processing and source hashes. | One-shot/chunked equality, overlap-add conservation, OOB reduction and bounded EVM/ISI/ICI are demonstrated. Research shaping never alters strict baseline implicitly. |
| **WF-014** | P0 | No canonical common-sample-rate composer aligns multiple BWPs/numerologies in absolute sample time and frequency while preserving CP, slot, symbol and phase identities. | Create MultiNumerologyWaveformComposer with rational rate conversion, common clock, exact digital frequency shift, per-BWP state, guard bands and asynchronous timing options. | Each component demodulates independently from the composite waveform; sample counts, phase, power and interference leakage reconcile across SCS ratios. |
| **WF-015** | P1 | Multi-component-carrier sample composition lacks one explicit digital upconversion, phase, frequency separation, common clock, filtering and power-allocation contract. | Add per-CC DigitalUpconverter and ComponentCarrierWaveformComposer with NCO state, resampling, anti-imaging filters, phase continuity and per-CC power ledger. | Each CC is recovered at the intended frequency with correct power and zero sample-time ambiguity; chunked and one-shot output match. |
| **WF-016** | P0 | Layer, port, grid, IFFT, CP/window, sample and carrier composition power conventions are not reconciled through one ledger. Some helpers fall back to all waveform samples when OFDM metadata is unavailable. | Create WaveformPowerLedger and ParsevalLedger from layer symbols to port grids to useful samples, CP/window samples and composite carriers. Missing metadata fails strict execution. | Per-stage energy and average power reconcile within 1e-10 relative error for no-window math tests and within 0.01 dB for production waveform tests. |
| **WF-017** | P1 | PSD, occupied bandwidth, guard leakage and ACLR-like research metrics are not consistently computed from a stateful oversampled waveform with declared FFT/window/RBW/averaging. | Add SpectralMeasurement with explicit sample rate, analysis window, segment overlap, FFT size, RBW, integration bands, averaging and reference plane. | Single-tone, multi-tone and OFDM analytical vectors pass; spectral-integral power matches time-domain power; plots are generated from exported CSVs. |
| **WF-018** | P0 | No-noise round trips, CP insufficiency, CFO/timing sensitivity, TDL/CDL behavior and transform-deprecoding equivalence are not covered across the complete selected waveform matrix. | Run every supported tuple through grid→waveform→channel/impairment→synchronization→demodulation→despreading→grid with exact error metrics. | No-noise NMSE/EVM/bit recovery pass; CP-exceeded channels create measured ISI; CFO/timing curves behave monotonically; BLER campaigns complete. |
| **WF-019** | P1 | Inter-numerology and asynchronous adjacent-waveform interference is not generated and separated through one sample-domain composition and receiver chain. | Compose per-link/per-BWP samples with exact timing, CFO, phase, frequency and filter states; export per-component contribution and measured interference covariance. | Composite samples equal the sum of contributions; desired/interferer power and covariance reconcile; guard and timing sweeps produce reproducible leakage curves. |
| **WF-020** | P0 | Multi-layer or DL DFT-s-OFDM and other 6G waveform candidates can be implied through scenario flags even though they are study items rather than the selected Release-19 normative baseline. | Create rel20_6g_waveform_study and waveform_research_candidate profiles. Each candidate needs a mathematical definition, TX/RX, reference signals, channel integration, independent vectors and impact tests before EXECUTE. | Unimplemented OTFS/AFDM/UFMC/FBMC/FDSS/multi-layer DFT-s-OFDM/DL DFT-s-OFDM requests fail during planning and cannot inherit NR CP-OFDM evidence. |

## Canonical production package

Create or consolidate:

```text
+sixgr/+phy/+waveform/
    WaveformSpecificationProfile.m
    WaveformCapabilityProfile.m
    WaveformPlanningResult.m

    OFDMNumerologyContext.m
    OFDMParameterResolver.m
    WaveformFrequencyReference.m
    OFDMSymbolPlan.m
    SubcarrierMapper.m
    ResourceGridToFFTMap.m

    OFDMStreamState.m
    WaveformChunk.m
    WaveformStreamComposer.m
    CPInsertionRemoval.m
    CanonicalOFDMModulator.m
    CanonicalOFDMDemodulator.m

    WindowingProfile.m
    WindowOverlapState.m
    WOLAEngine.m
    FilteredOFDMProfile.m
    FilteredOFDMEngine.m

    TransformPrecodingPlan.m
    UnitaryDFTSpreader.m
    UnitaryDFTDespreader.m
    LocalizedDFTMapper.m
    PiOver2BPSKMapper.m

    LowPAPRStudyProfile.m
    LowPAPRStudyRunner.m
    ToneReservationEngine.m
    FrequencyDomainShapingEngine.m
    FDSSStudyEngine.m

    RationalSampleRateConverter.m
    MultiNumerologyComponentState.m
    MultiNumerologyWaveformComposer.m
    DigitalUpconverter.m
    DigitalDownconverter.m
    ComponentCarrierState.m
    ComponentCarrierWaveformComposer.m

    WaveformPowerLedger.m
    ParsevalLedger.m
    PAPRMeasurement.m
    SpectralMeasurement.m
    WaveformEVMMeasurement.m
    WaveformContinuityChecker.m

    WaveformArtifactExporter.m
    runWaveformPhaseValidation.m
    runWaveformImpactAnalysis.m

    +oracle/
        SmallFFTSpec.m
        CPInsertionSpec.m
        SubcarrierMapSpec.m
        UnitaryDFTSpec.m
        PiOver2BPSKSpec.m
        WOLAWindowSpec.m
        StreamContinuitySpec.m
        PAPRSpec.m
        SpectralToneSpec.m
        PowerLedgerSpec.m
```

Existing `ofdmModulate`, `ofdmDemodulate`, `transformPrecode`, `transformDeprecode`, `resolveOFDMWindowing`, `ofdmReferencePower`, `calibrateOFDMNoiseTransform`, `runULLowPAPR` and modulation-tracking helpers may remain only as compatibility façades. They must delegate to the canonical runtime and cannot retain hidden defaults or fallback behavior.

## Exact CP-OFDM contract

For each OFDM symbol and antenna port, create an immutable `OFDMSymbolPlan` containing:

```text
ProfileID
ServingCellID / ComponentCarrierID / BWPID
SCS and CP type
absolute frame, slot and symbol
Nfft and sample rate
CP length in samples
carrier-frequency/reference-frequency state
zero-based occupied subcarrier coordinates
zero-based FFT-bin coordinates
window/filter profile and state IDs
input grid SHA-256
output sample SHA-256
```

The implementation must make its FFT scaling explicit. A permitted implementation is a unitary mathematical oracle:

```text
x[n] = 1/sqrt(Nfft) * sum_k X[k] * exp(j*2*pi*k*n/Nfft)
```

A Toolbox implementation may use a different internal amplitude convention only when `WaveformPowerLedger` exports the exact scale factor and both conventions reconcile.

Required checks:

```text
one occupied tone
negative/positive subcarrier pairs
DC excluded or explicitly owned
sparse QPSK grid
full selected BWP
multiple antenna ports
normal CP
60 kHz extended CP
nonzero BWP offset
carrier-frequency phase convention
one-shot versus chunked generation
```

No occupied RE may map to two FFT bins. No FFT bin may have two non-orthogonal owners.

## Exact transform-precoding contract

The production chain is:

```text
scrambled and modulated PUSCH symbols
    ↓
partition by actual OFDM symbol and PT-RS procedure
    ↓
unitary M-point DFT
    ↓
localized mapping into the assigned contiguous M subcarriers
    ↓
Nfft-point OFDM modulation and CP insertion
```

The unitary transform is:

```text
Y[k] = 1/sqrt(M) * sum_i x[i] * exp(-j*2*pi*i*k/M)
```

The receiver performs the exact inverse after FFT and subcarrier extraction.

Strict planning requires:

```text
LayerCount = 1
M = 12 * allocated PRBs
M has only prime factors 2, 3 and 5
resource allocation is contiguous for the selected profile
PUSCH assignment and configuration epoch are current
PT-RS symbol partition is exact
```

A DFT followed immediately by an equal-size full-band IFFT is not accepted as DFT-s-OFDM evidence.

## pi/2-BPSK

Implement symbol-index-dependent pi/2-BPSK exactly and preserve phase progression across chunk boundaries. The provided independent vectors test multiple starting symbol indices. The live mapper must consume actual procedure/scrambling context rather than a local alternating test pattern.

## Rectangular baseline and explicit WOLA/filtering

`nr_rel19_cp_ofdm_strict` and `nr_rel19_ul_dfts_ofdm_strict` use rectangular CP-OFDM unless a pinned implementation profile explicitly says otherwise.

For research WOLA/filtering:

```text
window coefficients are immutable and hashed
overlap state persists across symbols and chunks
group delay is recorded
receiver processing is matched or explicitly declared unmatched
useful-symbol samples and CP/overlap samples are distinguished
OOB reduction, EVM, ISI and ICI are measured together
```

The supplied complementary-window vectors validate coefficient arithmetic. Add exact production vectors for every enabled window/filter profile.

## Streaming continuity

One-shot generation and any legal chunk partition must produce the same sample sequence within the selected numeric tolerance.

The stream state includes:

```text
absolute next-sample index
time of next sample
OFDM symbol/slot/frame identity
carrier NCO phase
window overlap samples
filter and resampler states
component-carrier phases
configuration epoch
```

Tests must split waveforms at:

```text
inside CP
CP/useful boundary
inside useful symbol
symbol boundary
slot boundary
frame boundary
WOLA overlap
resampler/polyphase boundary
```

## Multi-numerology composition

Each component owns its own grid and OFDM plan but is placed on one common sample clock:

```text
component OFDM waveform
    ↓
exact rational sample-rate conversion, when required
    ↓
phase-continuous digital frequency shift
    ↓
explicit start sample and timing offset
    ↓
component filter/window
    ↓
power scaling
    ↓
sample-domain summation
```

Export:

```text
component sample contribution
common sample indices
component frequency offset
phase state
power
filter state
inter-numerology interference power
receiver-extracted grid and EVM
```

A scalar PSD sum or separate independent demodulation is not proof of sample-domain coexistence.

## Component-carrier composition

Implement separate CC identities, frequency offsets, sample-rate conversion, NCO state, power and filters. The composite sample vector must equal the sum of all recorded per-CC contributions. A receiver must recover each CC after digital downconversion and demodulation.

## Power, Parseval and normalization

Track these domains independently:

```text
modulation-symbol energy per layer
grid energy per logical antenna port
post-precoder port energy
useful OFDM sample energy
CP/window/overlap energy
complete slot/frame energy
per-BWP and per-CC power
composite waveform power
```

Strict mode cannot fall back to `all_waveform_samples_metadata_unavailable`.

Required numerical gates:

```text
pure-math Parseval relative error <= 1e-10
production power reconciliation <= 0.01 dB
no NaN/Inf samples
selected/applied scale-factor digest equality
```

## PAPR and CCDF

PAPR is:

```text
PAPR = max_n |x[n]|^2 / mean_n |x[n]|^2
```

But every result must record:

```text
reference domain
CP/window inclusion
oversampling factor and interpolation filter
port or aggregate waveform
payload/resource identity
number of trials
CCDF threshold, exceedance count and confidence interval
```

Evaluate oversampling factors 1, 2, 4 and 8. A mandatory result is complete only after the 4x-to-8x PAPR change is below the configured convergence tolerance.

## Spectral measurement

Every PSD/OOB metric records:

```text
sample rate
analysis segment length
FFT size
analysis window
segment overlap
RBW/equivalent noise bandwidth
averaging method
occupied and guard integration bands
reference plane and waveform hash
```

Time-domain integrated power and frequency-domain integrated power must agree within 0.01 dB. Do not call an arbitrary periodogram ACLR, SEM or RF conformance; RF measurement methods remain under the RF-emulation profile.

## Research waveform candidates

The following are not implemented merely because a YAML field exists:

```text
multi-layer DFT-s-OFDM
DL DFT-s-OFDM
flexible/pruned DFT size
noncontiguous DFT mapping
tone reservation
frequency-domain truncation
FDSS
OTFS
AFDM
UFMC
FBMC
```

For each candidate, either:

```text
1. implement a versioned mathematical TX/RX, pilots/reference signals, equalizer, channel integration, independent vectors and impact tests; or
2. leave the capability row REJECT with WAVEFORM:UnsupportedResearchCandidate.
```

Do not add shallow placeholders merely to increase the support count.

## Independent validation

Use the supplied pure-math vectors for:

```text
small FFT/IFFT and explicit bin order
CP insertion/removal
unitary DFT spreading
pi/2-BPSK
complementary WOLA coefficients
stream/NCO continuity
PAPR analytical signals
coherent single-tone spectra
capability resolution and negative cases
```

For every enabled full NR tuple also add at least one independent frozen vector or analytical invariant. A second wrapper around the same MATLAB `nr*` function is self-consistency only.

## Mandatory MATLAB tests

Implement all tests listed in `waveform_matlab_test_plan.csv`. At minimum, execute:

```text
testWaveformProfilePlanning
testOFDMParameterResolver
testOFDMInvalidParameterMatrix
testSubcarrierMapper
testSmallFFTIndependentVectors
testCPInsertionRemoval
testOFDMSampleScaling
testOFDMParseval
testOFDMPowerLedger
testOFDMNoNoiseRoundTrip
testOFDMNormalCP
testOFDMExtendedCP60kHz
testOFDMStreamState
testOFDMChunkEquivalence
testOFDMPhaseContinuity
testWindowingStrictDefaultZero
testWOLAWindowCoefficients
testWOLAOverlapAdd
testWOLAChunkContinuity
testWOLAMatchedReceiver
testTransformPrecodingPlan
testTransformPrecodingSingleLayer
testTransformPrecodingDFTSizes
testTransformPrecodingContiguousMapping
testUnitaryDFTIndependentVectors
testDFTSpreadingLocalizedMapping
testDFTDespreadingRoundTrip
testPiOver2BPSKIndependentVectors
testPiOver2BPSKChunkBoundary
testLowPAPRRunnerUsesCanonicalWaveform
testPAPRAnalyticalVectors
testPAPROversamplingConvergence
testPAPRCCDFConfidence
testSpectralSingleToneVectors
testSpectralParsevalClosure
testSpectralGuardLeakage
testMultiNumerologyPlanning
testMultiNumerologySynchronousComposition
testMultiNumerologyAsynchronousComposition
testMultiNumerologyDemodulation
testComponentCarrierPlanning
testComponentCarrierComposition
testDigitalUpconverterPhaseContinuity
testPerCarrierPowerLedger
testWaveformInterferenceContributionSum
testWaveformCFOAndTimingSensitivity
testWaveformCPExceededISI
testWaveformAWGNCampaign
testWaveformTDLCampaign
testWaveformCDLCampaign
testWaveformMIMOPortPower
testWaveformPRGPrecoding
testWaveformNegativeMatrix
testWaveformCapabilityMatrix
testWaveformIndependentVectorCoverage
testWaveformArtifactGeneration
testWaveformRuntimeScaling
testWaveformSerialParallelReproducibility
testResearchCandidatePlanningRejection
testFullWaveformProfileEndToEnd
```

Every negative test must verify:

```text
ActualError == ExpectedError
WaveformGenerated == false
StateMutation == false
```

## Required production CSVs and images

Generate all 32 CSVs in `desired_waveform_csv_contract.csv` and all 22 PNGs in `desired_waveform_image_contract.csv` under:

```text
artifacts/waveform_generation_phase/
```

Generate all 16 impact CSVs and all 30 impact PNGs under:

```text
artifacts/waveform_generation_impact/
```

Images must be generated from the corresponding production CSV, not from hidden in-memory arrays. Populate the image semantic audit with the source CSV SHA-256, PNG SHA-256, actual title, labels, dimensions, axes, series and finite-point count.

## Impact analysis

Execute all 768 rows in `waveform_impact_experiment_matrix.csv` as 384 matched baseline/treatment pairs. Within each pair preserve:

```text
seed
trial index
payload and resource identity
channel realization
noise realization
initial stream state
initial RF state
```

Only `FactorValue` may change.

Use:

```text
Wilson intervals for ordinary error probabilities
one-sided exact Clopper-Pearson bounds for zero-event studies
McNemar tests for paired decode outcomes
paired bootstrap intervals for EVM, PAPR, OOB, power, runtime and memory
Holm correction across related hypotheses
predefined practical engineering margins
INCOMPLETE or INCONCLUSIVE when evidence is insufficient
```

The 96 acceptance rules in `waveform_impact_acceptance_rules.csv` are mandatory.

## Execution commands

Run exactly or equivalently:

```bash
python tests/vectors/waveform/verify_waveform_vector_pack.py tests/vectors/waveform
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Waveform*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*OFDM*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PAPR*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*TransformPrecod*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.waveform.runWaveformPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','waveform'),'OutputDir',fullfile(pwd,'artifacts','waveform_generation_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/waveform/verify_waveform_artifacts.py artifacts/waveform_generation_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.waveform.runWaveformImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','waveform','waveform_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','waveform_generation_impact'),'SeedList',[11 23 47 89 131 197],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/waveform/verify_waveform_impact_artifacts.py artifacts/waveform_generation_impact
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

## Codex may not report COMPLETE while any of these remain

```text
implicit 2.5% Nfft windowing
nextpow2/default Nfft or sample-rate fallback
same-Toolbox result labelled independent
ambiguous DC/FFT-bin mapping
slot-local phase/window/filter state without continuity
runULLowPAPR reduced IFFT/CP path
DFT and equal-size full-band IFFT presented as DFT-s-OFDM
transform precoding enabled from modulation or a waveform string
rank>1 in normative transform-precoded PUSCH
invalid DFT size accepted
noncontiguous strict transform allocation
unknown modulation defaulting to 16QAM
native-rate-only PAPR used as final evidence
config-only low-PAPR feature presented as implemented
multi-numerology components generated on unrelated sample clocks
component-carrier NCO phase reset
all-sample fallback used for OFDM reference power
missing Parseval/power closure
PSD without declared RBW/window/integration bands
research candidate inheriting normative evidence
mandatory MATLAB test skipped or blocked
mandatory operating point incomplete
any of 48 CSVs absent
any of 52 PNGs absent
either artifact verifier returning nonzero
complete repository regression failing
```

## Definition of done

```text
All 20 WF findings closed for enabled profiles
All 60 mandatory MATLAB tests execute and pass
All 180 capability rows resolve correctly
All independent-vector mismatches equal zero
Strict baseline windowing is zero unless explicitly configured
No Nfft/sample-rate/CP fallback remains
One-shot and arbitrary chunk generation match
CP-OFDM and single-layer UL DFT-s-OFDM no-noise round trips pass
All valid/invalid DFT-size vectors pass
Power and Parseval ledgers pass
PAPR oversampling and CCDF campaigns complete
PSD/OOB and spectral-power closure pass
Multi-numerology and selected CC compositions pass
All 768 impact experiments execute
All 96 acceptance rules have valid evidence
All 48 CSVs pass
All 52 PNGs pass
Both artifact verifiers return exit code 0
Complete repository MATLAB regression passes
```

## Required Codex response format

At the end of every Codex execution response, report:

```text
1. findings closed and still open
2. production files added/changed
3. old paths migrated or deleted
4. exact MATLAB and Python commands executed
5. MATLAB/5G Toolbox versions
6. test pass/fail/skip/block counts
7. capability EXECUTE/REJECT counts
8. independent-vector mismatch counts
9. CSV row counts and SHA-256 hashes
10. PNG dimensions and SHA-256 hashes
11. verifier exit codes
12. residual unsupported research candidates
13. final status: COMPLETE, FAIL or BLOCKED
```

Do not return only architecture, pseudocode or a future plan. Make the changes, run them and provide the actual evidence.
