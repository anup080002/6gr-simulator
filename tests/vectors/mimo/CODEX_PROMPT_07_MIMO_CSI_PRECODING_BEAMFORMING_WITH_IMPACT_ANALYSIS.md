# CODEX IMPLEMENTATION PROMPT 07

# MIMO, CSI, PRECODING, BEAMFORMING, MU-MIMO, MULTI-TRP, HYBRID BEAMFORMING, AND STRICT IRC

You are the implementation owner for the MATLAB 5G/6G link-level simulator in this repository.

This is not a source-review task and not a request for a plan. Modify the production MATLAB implementation, migrate every live caller, add executable tests, run those tests on the declared MATLAB and 5G Toolbox release, generate the required CSV and PNG evidence, inspect the generated artifacts, and continue correcting the source until every mandatory requirement in this prompt passes.

The current implementation contains useful waveform and receiver foundations, but it is not a complete MIMO/CSI implementation. It mainly uses a compact rank-1/rank-2 DFT-like codebook, SVD or configured-rank decisions, custom CSI packing, heuristic panel inference, configured TPMI paths, and an IRC-to-MMSE fallback. Replace those behaviors in the selected production profiles.

## Final technical objective

Create one canonical, release-pinned, closed-loop MIMO chain in which:

1. antenna panels, physical elements, logical antenna ports, polarization, pose and calibration are explicit;
2. every enabled codebook profile enumerates exact candidates and restrictions;
3. CSI measurement resources and interference resources create timestamped measured state;
4. RI, PMI, CQI and CRI are selected from the declared CSI report configuration and receiver objective;
5. CSI Part 1 and Part 2 are constructed as typed fields, serialized and decoded through the applicable UCI procedure;
6. decoded CSI is the scheduler's live authority for rank, precoder and MCS decisions where the selected procedure requires it;
7. the exact selected matrix is the exact matrix applied to data, DM-RS and PT-RS at every PRG and symbol group;
8. DL and UL high-rank operation retains all layers and codewords end to end;
9. MU-MIMO, multi-TRP, coherent joint transmission, hybrid beamforming and beam management are isolated profiles with their own real state and measurements;
10. strict IRC runs only when a measured, sufficiently supported, positive-semidefinite, sufficiently recent covariance matrix is available;
11. unsupported combinations are rejected during planning, before any waveform or state mutation;
12. all selected profiles are proven by independent vectors, no-noise round trips, controlled waveform campaigns and generated technical artifacts.

## Do not return a plan-only answer

Your response is acceptable only after source edits and execution. At the end, report exact files changed, commands executed, test counts, blocked items, artifact row counts, image dimensions, SHA-256 values and residual unsupported profiles.
# 1. Pinned technical baseline

Use the exact repository-selected release versions. Unless the repository already pins newer mutually compatible versions, use:

- 3GPP TS 38.211 V18.8.0 for physical channels, modulation, antenna-port mapping, DM-RS/PT-RS/CSI-RS/SRS and layer mapping;
- 3GPP TS 38.212 V18.8.0 for UCI encoding, CSI Part 1/Part 2 channel coding, multiplexing and rate matching;
- 3GPP TS 38.213 V18.8.0 for physical-layer procedures, beam-related monitoring, TCI application timing and control procedures;
- 3GPP TS 38.214 V18.9.0 for CSI reporting, Type-I/Type-II codebooks, RI/PMI/CQI procedures, PDSCH/PUSCH MIMO operation and multi-TRP procedures;
- 3GPP TS 38.215 V18.x for measured quantities and applicable L1 measurement behavior;
- 3GPP TS 38.331 V18.9.0 for `CSI-MeasConfig`, `CSI-ReportConfig`, codebook configuration, CSI-RS/SRS resource configuration, TCI state, spatial relation and UE capability context;
- 3GPP TR 38.901 V18.0.0 for antenna arrays, polarization, element response, spatial channel behavior and channel-model validation.

Store the exact versions in one immutable `MIMOSpecificationProfile`. Do not scatter release strings across functions.

This phase is allowed to use MATLAB 5G Toolbox as the production waveform kernel, but a call to the same `nr*` function on both DUT and reference sides is self-consistency only. Mandatory codebook, index, bit, matrix, array-response and state-transition families require pure-math or frozen independent references.
# 2. Non-negotiable technical rules

The following rules apply to every strict MIMO profile.

1. Do not infer a square panel from `sqrt(NPorts)`.
2. Do not clamp `N1`, `N2`, `O1`, `O2`, panel count, port count, rank, codebook index, beam index, subband index or PRG index.
3. Do not silently replace an invalid panel by a ULA, a single panel or an identity array.
4. Do not silently transpose, crop, pad, repeat or truncate a precoder to make its dimensions fit.
5. Do not silently replace a requested precoder with an identity, SVD, MRT, ZF or configured matrix.
6. Do not use a generic DFT candidate set while labelling it Type-I, Type-II or enhanced Type-II.
7. Do not select PMI only by `norm(H*W,'fro')^2`.
8. Do not select RI only by singular-value thresholds or configured SNR.
9. Do not construct a fixed RI/PMI/CQI bit container or custom hexadecimal payload.
10. Do not supply transmitted RI, PMI, CQI, CRI, CSI bits, winning beam or candidate index to a strict receiver.
11. Do not use geometry truth to choose the winning beam in a measured beam-management profile.
12. Do not allow configured TPMI to override a required measured SRS decision.
13. Do not label a covariance-free MMSE detector as IRC.
14. Do not continue strict IRC with missing, stale, indefinite or poorly supported covariance.
15. Do not collapse configured rank, number of layers, port count, number of codewords, number of TRPs or number of RF chains without a typed failure.
16. Do not normalize every precoder column independently when the selected normative codebook matrix defines a different total normalization.
17. Do not regenerate the precoder downstream from PMI after the selected matrix digest has been recorded.
18. Do not use one wideband matrix where the assignment requires PRG/subband-varying matrices.
19. Do not share one mutable CSI state across UEs, cells, BWPs, report configurations, resource configurations or measurement epochs.
20. Do not accept a CSI report whose configuration epoch, resource identity, UE identity or BWP identity is stale.
21. Do not claim coherent joint transmission unless independent TRP clock, timing and phase state is explicitly modelled and applied to samples.
22. Do not claim hybrid beamforming unless analog and digital matrices, RF-chain count, phase constraints, quantization and actual application are explicit.
23. Do not treat a plot or CSV as proof if its values were reconstructed from configuration rather than emitted by the production runtime.
24. Do not skip mandatory tests because a capability is difficult. Mark a profile unsupported during planning until it is implemented.
25. Never modify a test merely to accept an existing shortcut.
# 3. Exact selected capability profiles

Create a machine-readable registry at a canonical source path such as:

```text
+sixgr/+phy/+mimo/MIMOCapabilityProfile.m
configs/standards/mimo_capability_profiles_r18.yaml
```

The CSV `mimo_capability_profile_matrix.csv` is the required initial tuple set. The registry must be executable: every `Supported=true` tuple must execute through the real production chain, and every `Supported=false` tuple must fail before waveform generation.

Implement the following profiles as independent scopes. A profile may be enabled only after all of its mandatory rows pass.
## Profile `beam_management_p1_p2_p3_bfr_strict`

- Registry rows: 1
- Supported rows: 1
- Explicitly unsupported rows: 0
- Directions: BOTH
- Codebook types: beamManagement
- Port values: 64
- Rank values: 1
## Profile `fr1_2trp_cjt_strict`

- Registry rows: 1
- Supported rows: 1
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: multiTRP
- Port values: 16
- Rank values: 2
## Profile `fr1_2trp_ncjt_strict`

- Registry rows: 1
- Supported rows: 1
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: multiTRP
- Port values: 16
- Rank values: 2
## Profile `fr1_enhancedTypeII_strict`

- Registry rows: 4
- Supported rows: 4
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: enhancedTypeII
- Port values: 16
- Rank values: 1, 2, 3, 4
## Profile `fr1_high_rank_ul_strict`

- Registry rows: 20
- Supported rows: 20
- Explicitly unsupported rows: 0
- Directions: UL
- Codebook types: codebook, nonCodebook
- Port values: 2, 4, 8
- Rank values: 1, 2, 3, 4
## Profile `fr1_mu_mimo_2ue_strict`

- Registry rows: 1
- Supported rows: 1
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: typeI-SinglePanel
- Port values: 8
- Rank values: 2
## Profile `fr1_mu_mimo_4ue_strict`

- Registry rows: 1
- Supported rows: 1
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: typeI-SinglePanel
- Port values: 16
- Rank values: 4
## Profile `fr1_typeII_PortSelection_strict`

- Registry rows: 4
- Supported rows: 4
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: typeII-PortSelection
- Port values: 4, 8
- Rank values: 1, 2
## Profile `fr1_typeII_strict`

- Registry rows: 2
- Supported rows: 2
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: typeII
- Port values: 8
- Rank values: 1, 2
## Profile `fr1_typeI_multi_panel_strict`

- Registry rows: 20
- Supported rows: 20
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: typeI-MultiPanel
- Port values: 8, 16, 32
- Rank values: 1, 2, 3, 4
## Profile `fr1_typeI_single_panel_strict`

- Registry rows: 102
- Supported rows: 102
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: typeI-SinglePanel
- Port values: 2, 4, 8, 12, 16, 24, 32
- Rank values: 1, 2, 3, 4, 5, 6, 7, 8
## Profile `fr2_hybrid_beamforming_strict`

- Registry rows: 1
- Supported rows: 1
- Explicitly unsupported rows: 0
- Directions: DL
- Codebook types: hybrid
- Port values: 64
- Rank values: 2
## Profile `unsupported_extension`

- Registry rows: 6
- Supported rows: 0
- Explicitly unsupported rows: 6
- Directions: DL
- Codebook types: CJTEnhancedTypeII_4TRP, FR2_8layer_hybrid, distributedMIMO_moreThan2TRP, furtherEnhancedTypeII, multiPanel_8panels, predictedPMITypeII
- Port values: 0
- Rank values: 0
Planning output for every tuple must include:

```text
ProfileID
ReleaseVersion
Direction
ServingCellID
ComponentCarrierID
BWPID
CodebookType
Ports
Panels
N1 N2 O1 O2
PolarizationModel
Rank
CodewordCount
FrequencyGranularity
ReceiverType
RequiredMeasurementResources
RequiredInterferenceResources
RequiredUCIChannel
Supported
PlanningRejected
TypedError
```

A rejected tuple must have:

```text
WaveformGenerated = false
SchedulerStateChanged = false
HARQStateChanged = false
CSIStateChanged = false
BeamStateChanged = false
```
# 4. Canonical production architecture

Consolidate production code under one package. Reuse good kernels, but do not create a second unused MIMO stack.

```text
+sixgr/+phy/+mimo/
    MIMOSpecificationProfile.m
    MIMOCapabilityProfile.m
    MIMOPlanningResult.m

    AntennaElementPattern.m
    AntennaPanel.m
    AntennaArray.m
    AntennaPose.m
    PolarizationBasis.m
    AntennaPortMap.m
    AntennaCalibrationState.m
    ArrayResponseEngine.m

    CodebookConfiguration.m
    CodebookSubsetRestriction.m
    TypeI2PortCodebook.m
    TypeISinglePanelCodebook.m
    TypeIMultiPanelCodebook.m
    TypeIIPortSelectionCodebook.m
    TypeIICodebook.m
    EnhancedTypeIICodebook.m
    CodebookCandidate.m
    CodebookCandidateSet.m

    CSIResourceState.m
    CSIInterferenceState.m
    CSIMeasurementState.m
    CSIReportConfigurationState.m
    CSIReport.m
    CSIPart1.m
    CSIPart2.m
    CSIReportBuilder.m
    CSIReportSerializer.m
    CSIReportDecoder.m
    CSIReportValidityChecker.m

    RankSelectionObjective.m
    RISelector.m
    PMISelectionObjective.m
    PMISelector.m
    CQISelector.m
    CRISelector.m
    WidebandSubbandMapper.m

    PrecoderBundle.m
    PrecoderSelectionState.m
    PrecoderApplicationLedger.m
    PrecoderPowerNormalizer.m

    DLClosedLoopMIMOState.m
    ULChannelSoundingState.m
    ULSRSDecisionEngine.m
    HighRankDLContext.m
    HighRankULContext.m

    InterferenceCovarianceState.m
    InterferenceCovarianceEstimator.m
    CovarianceValidityChecker.m
    StrictMIMOReceiver.m
    ZFDetector.m
    MMSEDetector.m
    IRCDetector.m

    MUMIMOUserContext.m
    MUMIMOSchedulingContext.m
    MUMIMOGroupSelector.m
    MUMIMOPrecoder.m
    MUMIMOReceiver.m

    MultiTRPContext.m
    MultiTRPTransmissionOccasion.m
    NCJTController.m
    CJTCoherenceState.m
    CJTController.m

    HybridBeamformingArchitecture.m
    AnalogBeamCodebook.m
    HybridBeamformer.m
    HybridBeamTrainingState.m

    BeamMeasurementState.m
    BeamReport.m
    TCIActivationState.m
    BeamManagementStateMachine.m
    BeamFailureDetectionState.m
    BeamFailureRecoveryState.m

    MIMOArtifactExporter.m
    runMIMOCSIBeamformingPhaseValidation.m
    runMIMOCSIBeamformingImpactAnalysis.m

    +oracle/
        AntennaArrayResponseSpec.m
        TypeI2PortCodebookSpec.m
        TypeISinglePanelSpec.m
        TypeIMultiPanelSpec.m
        TypeIIPortSelectionSpec.m
        CSIFieldLayoutSpec.m
        CSIReportBitOwnershipSpec.m
        RIObjectiveSpec.m
        PMIObjectiveSpec.m
        PrecoderApplicationSpec.m
        CovarianceSpec.m
        ReceiverSINRSpec.m
        SRSDecisionSpec.m
        MUMIMOInterferenceSpec.m
        MultiTRPCompositeSpec.m
        HybridBeamformingSpec.m
        BeamStateTransitionSpec.m
```

Existing public entry points may remain as compatibility façades, but they must delegate to the canonical implementation. Remove independent behavior from:

```text
+sixgr/+mimo/buildNRCodebook.m
+sixgr/+mimo/selectPMI.m
+sixgr/+mimo/resolveNominalVsEffectiveMIMO.m
+sixgr/+mimo/buildCSIFeedback.m
+sixgr/+phy/+dl/pmiCodebookCandidates.m
+sixgr/+phy/+dl/packCSIFeedbackPayload.m
+sixgr/+phy/+rx/mimoDetect.m
+sixgr/+phy/+rx/estimateInterferenceCovarianceIRC.m
+sixgr/+phy/+ul/estimateSRSRITPMI.m
+sixgr/+mimo/selectULBeamFromSRS.m
+sixgr/+rf/BeamRefinementCSIRS.m
+sixgr/+rf/BeamformingSRSReciprocity.m
+sixgr/+system/selectBestBeamPerLink.m
+sixgr/+mimo/executeSpatialComposite.m
+sixgr/+phy/+mimo/precoder.m
```
# 5. Canonical data and matrix contracts

## 5.1 Coordinate and indexing conventions

Use one documented convention throughout:

- MATLAB arrays may be one-based internally, but all exported standard indices are zero-based.
- Element positions are expressed in wavelengths and metres at a named reference frequency.
- Global position vector is `[x;y;z]`.
- Azimuth/elevation and local/global rotations use one declared right-handed convention.
- Logical antenna ports are not physical elements.
- Every logical port maps to one or more physical elements and one polarization branch through an immutable `AntennaPortMap`.
- CSI-RS, SRS, DM-RS and data port identities remain distinct typed identities.

## 5.2 Channel and precoder dimensions

Use:

```text
H[k,l]          : Nrx × Nport complex channel at subcarrier k and symbol l
W[p,g]          : Nport × Nlayer precoder for PRG p and symbol group g
x[k,l]          : Nlayer × 1 layer symbols
y[k,l]          : Nrx × 1 received samples
R_i+n[k,l]      : Nrx × Nrx interference-plus-noise covariance
G[k,l]          : Nlayer × Nrx linear detector
```

The canonical precoder bundle is:

```text
W[Nport, Nlayer, NPRG, NSymbolGroup]
```

It contains:

```text
ProfileID
CodebookType
CodebookIndices
RI
PMI fields
ServingCellID
CCID
BWPID
ReportConfigID
MeasurementStateID
MeasurementEpoch
SelectionTimestamp
ValidityWindow
PRG boundaries
Symbol-group boundaries
MatrixSHA256 per slice
WholeBundleSHA256
NormativeNormalization
```

Do not infer matrix orientation from dimensions. A mismatched matrix must raise a typed error.

## 5.3 Power normalization

Preserve the normative codebook coefficient normalization. Separately define the transmission-power contract.

For every applied slice, export at least:

```text
trace(W^H W)
column norms
per-port power weights
maximum port power
minimum port power
total data-layer power before W
total antenna-port power after W
power error in dB
```

The no-channel power test must reconcile actual samples to the requested total power. A valid codebook matrix must not be modified merely to make all columns unit norm unless the pinned procedure requires it.

## 5.4 Immutable identity

Every selected matrix receives a digest before transmission. The transmitter must export the digest of the matrix actually multiplied by the layer symbols. The two digests must match for every PRG and symbol group.
# 6. Canonical antenna, panel, polarization and channel projection

Implement an antenna model that is shared by channel generation, codebook generation, precoder application, measurements and plots.

For physical element position `r_m`, propagation unit vector `u`, wavelength `lambda`, element/polarization response `e_m(u,f)` and calibration coefficient `c_m(f,t)`, the array response must be represented explicitly as:

```text
a_m(u,f,t) = e_m(u,f) * c_m(f,t) * exp(j*2*pi/lambda * r_m^T*u)
```

For dual polarization, carry the full complex polarization response and cross-polar terms. Do not reduce XPR to one scalar gain after channel creation. Validate:

```text
panel dimensions N1/N2
number of panels Ng
horizontal and vertical spacing
panel spacing
physical element ordering
polarization ordering
logical port ordering
mechanical/electrical downtilt
orientation and rotation
frequency-dependent response
calibration amplitude and phase
```

The supplied `expected_antenna_array_response.csv` is the independent deterministic floor. Add additional frozen vectors for the exact supported TR 38.901 panel profiles.

Required tests include:

- broadside and end-fire steering;
- azimuth/elevation sign and rotation;
- half-wavelength ULA/UPA phase progression;
- dual-polar response and XPR;
- panel-to-panel phase;
- port permutation detection;
- frequency change and beam squint where relevant;
- calibration amplitude/phase perturbation;
- exact projection from physical elements to logical ports.
# 7. Codebook implementation

## 7.1 Exact 2-port Type-I floor

Implement the exact two-port rank-1 and rank-2 codebook in `TypeI2PortCodebook`. The supplied file `expected_typeI_2port_codebook.csv` is mandatory and must be matched coefficient by coefficient.

Do not implement this table through a generic beam generator. The matrix identity and normalization must match the pinned specification table.

## 7.2 Type-I single-panel

For each selected tuple:

```text
N1, N2
O1, O2
number of CSI-RS ports
rank
codebook mode
codebook subset restriction
RI restriction
wideband/subband reporting mode
```

implement the exact table/formula-defined candidates and indices. Support only the tuples in `mimo_capability_profile_matrix.csv` whose `Supported` value is true.

Required behavior:

1. Enumerate a deterministic candidate set in exact normative index order.
2. Apply every subset restriction before selection.
3. Preserve co-phasing, polarization and layer-dependent vector construction.
4. Support the selected ranks through rank 8 where the tuple permits them.
5. Export all normative index fields separately; do not collapse them into a custom integer unless a separate reversible view is required.
6. Reject a candidate whose dimensions or allowed-rank relationship is invalid.
7. Compare every enabled candidate with independent frozen vectors.

## 7.3 Type-I multi-panel

Implement only the selected 8-, 16- and 32-port multi-panel tuples listed as supported. The profile must explicitly own:

```text
number of panels
panel topology
per-panel element topology
panel co-phasing indices
beam indices
rank
subset restrictions
report field widths
```

Do not emulate a multi-panel codebook by concatenating single-panel DFT beams.

## 7.4 Type-II and port-selection Type-II

Implement one bounded profile at a time. Each profile must include:

```text
basis/beam selection
port selection where applicable
wideband amplitudes and phases
subband amplitudes and phases
nonzero coefficient selection
normalization
RI and PMI field structure
Part-1 and Part-2 field ownership
candidate/search complexity bounds
```

Do not enable a Type-II label until the complete report serialization and closed-loop scheduler use pass.

## 7.5 Enhanced Type-II

Implement only the tuples explicitly present in the capability matrix. All unlisted enhanced, high-resolution or release-extension options remain rejected.

## 7.6 Independent codebook evidence

For every enabled tuple, produce:

```text
candidate count
normative index fields
matrix dimensions
coefficient real/imag values or frozen hash
Frobenius power
orthogonality error
subset-allowed flag
independent mismatch count
```

A same-Toolbox comparison may be retained as regression evidence but cannot be the only oracle.
# 8. CSI measurement and report pipeline

## 8.1 Measurement-state ownership

Create immutable measurement states keyed by:

```text
UEID
ServingCellID
CCID
BWPID
CSIResourceConfigID
CSIReportConfigID
MeasurementResourceID
InterferenceResourceID
MeasurementSlot
MeasurementSymbol
MeasurementEpoch
Beam/TCI state
```

The state must contain measured, not configured, values:

```text
estimated H per resource/PRG
estimated noise power
estimated interference covariance
per-port/per-layer measurement quality
resource collision state
age and validity window
```

## 8.2 Exact report configuration

`CSIReportConfigurationState` must be built from installed RRC state and UE capability. It owns:

```text
report quantity
report type: periodic, semi-persistent or aperiodic
PUCCH or PUSCH UCI channel
codebook type and mode
RI restriction
codebook subset restriction
wideband/subband frequency granularity
CQI table
PMI fields
CRI/SSBRI fields
L1-RSRP/L1-SINR fields where selected
Part-1/Part-2 relationship
report priority
trigger state
configuration epoch
```

## 8.3 Typed report object

Create:

```text
CSIReport
    CSIPart1
    CSIPart2
    report identity
    source measurement identity
    report configuration identity
    selected CRI/SSBRI
    selected RI
    selected PMI fields
    selected CQI fields
    subband/PRG field vectors
    report age
    validity and confidence
```

No production code may expose one fixed `RI|PMI|CQI` bit string.

## 8.4 Part 1 and Part 2

Construct the exact report-dependent field ordering and widths from the selected configuration. Part 1 and Part 2 are encoded separately when required by TS 38.212 and are multiplexed on the selected UCI channel through the canonical PUCCH/PUSCH UCI implementation.

The implementation must export one ownership row per information bit:

```text
ReportID
Part
BitIndex
FieldName
FieldInstance
NormativeIndex
ValueBit
ConfigurationEpoch
```

Every bit has exactly one owner. No missing, duplicated, padded, truncated or custom-container bits are allowed.

## 8.5 Decode and validation

At the receiver/scheduler side:

1. recover Part 1 and Part 2 using the actual UCI chain;
2. validate CRC and expected contextual length;
3. parse fields using the installed report configuration;
4. reject stale or wrong-configuration reports;
5. create a `DecodedCSIEvent` that can update scheduler state;
6. preserve decoded report identity, age and provenance.
# 9. Exact RI, PMI, CQI and CRI selection

## 9.1 Receiver-aware per-layer SINR

For candidate rank `nu` and precoder `W`, define the effective layer channel:

```text
F = H * W
```

For layer `q`, using detector row `g_q`, compute:

```text
signal_q = |g_q * f_q|^2
interference_q = sum_{j != q} |g_q * f_j|^2
noise_q = real(g_q * R_i+n * g_q^H)
SINR_q = signal_q / (interference_q + noise_q)
```

Use the exact receiver selected by the profile: ZF, MMSE or strict IRC. Do not evaluate one objective and transmit with another detector unless the profile explicitly studies mismatch.

## 9.2 PMI objective

Replace raw Frobenius gain with an explicit configurable objective. At minimum support:

```text
post-equalization mutual-information proxy
calibrated expected goodput
calibrated BLER-constrained spectral efficiency
```

For a candidate, calculate the objective over every relevant PRG/subband using measured covariance and channel state. Example goodput objective:

```text
ExpectedGoodput(W,nu) =
    scheduled_information_bits(nu, MCS)
    * (1 - PredictedBLER(postEQ_SINR_vector, MCS, codewords))
    / transmission_time
    - configured_overhead_penalty
```

Use calibrated mappings generated from waveform campaigns, not arbitrary fixed thresholds.

## 9.3 RI objective

RI selection must compare every allowed rank under the same report configuration, codebook restrictions, receiver, covariance, MCS/CQI mapping, codeword mapping and overhead. Export:

```text
candidate rank
best PMI for that rank
per-layer post-EQ SINR
predicted BLER per codeword
predicted goodput
rank overhead
selection confidence
reason selected/rejected
```

Configured rank is an upper bound/capability input, not the measured selected rank.

## 9.4 Wideband and subband/PRG selection

Implement wideband and subband/PRG decisions according to the report profile. Do not average `H` over frequency and then reuse one matrix when the report requires frequency-selective selection.

The selected `PrecoderBundle` must have a matrix slice for every PRG and symbol group that the assignment needs.

## 9.5 CQI

CQI must be selected from the measured post-equalization quality and the selected CQI table. It must be calibrated against the same production PDSCH/PUSCH chain and target BLER. A configured CQI or fallback alternating value cannot enter strict mode.

## 9.6 CRI and beam/resource selection

CRI/SSBRI selection must use measurements from configured resources and preserve resource identity. A geometry-derived best-beam label cannot substitute for measured CRI/SSBRI.
# 10. Closed-loop downlink implementation

Implement this causal chain:

```text
configured CSI-RS and CSI-IM resources
    ↓
actual waveform transmission and reception
    ↓
measured H, noise and interference state
    ↓
report-config-aware RI/PMI/CQI/CRI selection
    ↓
CSI Part 1/Part 2 serialization
    ↓
PUCCH/PUSCH UCI transmission and decoding
    ↓
decoded CSI event
    ↓
scheduler rank/MCS/precoder decision
    ↓
DCI and PDSCH scheduling assignment
    ↓
exact selected PrecoderBundle application to PDSCH, DM-RS and PT-RS
    ↓
receiver per-layer SINR, EVM, codeword CRC and HARQ result
```

Mandatory rules:

- the scheduler may not read the transmitter's selected RI/PMI directly;
- the selected report may be delayed, stale or erroneous according to the actual UCI result;
- the scheduler must reject or age out stale CSI;
- the PDSCH assignment must reference the decoded CSI event and matrix digest;
- the transmitter must export selected versus applied rank, ports and matrix for every PRG;
- ranks 5–8 must preserve the correct two-codeword split and per-codeword HARQ state;
- channel estimation and DM-RS port mapping must be consistent with the applied rank and codebook.
# 11. Closed-loop uplink and SRS authority

Implement this causal chain:

```text
configured SRS resources
    ↓
actual SRS waveform and receiver channel estimates
    ↓
timestamped ULChannelSoundingState
    ↓
RI/SRI/TPMI or non-codebook precoder decision
    ↓
scheduler decision and applicable DCI 0_x fields
    ↓
PUSCH scheduling assignment
    ↓
exact selected UL matrix application
    ↓
receiver per-layer SINR and UL-SCH/UCI decode
```

The SRS state must contain:

```text
UEID
SRS resource and resource-set IDs
slot/symbol
sounded bandwidth
channel-estimate digest
noise estimate
covariance estimate
measurement age
selected RI
selected SRI
selected TPMI
selected matrix digest
validity window
```

A configured TPMI is permitted only in an isolated calibration profile. In the strict SRS-driven profile, no configuration-only override may change the live matrix.

For codebook and non-codebook profiles, implement the exact selected UL rank/precoder subset. Broad unsupported UL ranks or codebook combinations must fail planning.
# 12. Covariance-qualified IRC

## 12.1 Covariance estimator

Estimate covariance only from samples that are valid for the configured interference/noise measurement procedure. Export:

```text
CovarianceStateID
UEID
CCID/BWPID
resource/PRG identity
sample count
sample slots and symbols
measurement age
raw sample covariance
shrinkage coefficient
regularization amount
eigenvalues
condition number
PSD result
source signal exclusions
```

A robust estimator may use diagonal loading or shrinkage, but every correction must be explicit and bounded.

Example shrinkage structure:

```text
R_hat = (1-alpha) * S + alpha * mu * I
mu = trace(S)/Nrx
```

The configured profile must define:

```text
minimum sample count
maximum age
maximum condition number
minimum eigenvalue tolerance
allowed shrinkage range
PRG/subband granularity
```

## 12.2 Strict IRC gate

Strict IRC is available only when:

```text
finite matrix
Hermitian within tolerance
positive semidefinite within tolerance
minimum sample support met
age within limit
condition number within limit after allowed regularization
resource and UE identity match
no desired-signal leakage violation
```

If one requirement fails, raise the corresponding typed error and do not label the detector IRC. A study profile may explicitly run MMSE fallback, but its output must say `DetectorUsed=MMSE_FALLBACK`, never `IRC`.

## 12.3 Receiver evidence

Export per layer:

```text
detector requested
detector actually used
covariance state ID
filter-vector digest
signal power
inter-layer interference
external interference
noise power
post-EQ SINR
EVM
LLR quality
CRC result
```

Controlled interference campaigns must show the intended behavior of ZF, MMSE and IRC without using configured SINR as the measured result.
# 13. High-rank DL and UL closure

For every supported high-rank tuple:

1. preserve configured, selected and applied rank separately;
2. validate logical DM-RS ports against rank and codebook;
3. validate PT-RS association;
4. validate layer-to-codeword mapping;
5. preserve codeword-specific MCS, TBS, RV, HARQ process and soft buffer;
6. export per-layer channel estimate, SINR and EVM;
7. export per-codeword BER, BLER, decoder iterations and HARQ result;
8. reconcile data-layer and antenna-port power;
9. reject silent rank reduction;
10. run no-noise, AWGN, TDL and CDL cases over multiple seeds.

A rank test passes only when:

```text
ConfiguredRank == SelectedRank == AppliedRank
AppliedLayerCount == ExpectedLayerCount
AppliedCodewordCount == ExpectedCodewordCount
AllLayerMappingsPresent == true
AllPortMappingsPresent == true
RankCollapsed == false
PowerErrorDB within tolerance
```

where the scenario deliberately requests that exact rank and the channel is constructed to support it.
# 14. MU-MIMO profile

Implement MU-MIMO as a real shared-resource procedure, not as two independent SU-MIMO results added after decoding.

Each `MUMIMOSchedulingContext` must contain:

```text
shared PRB/symbol allocation
UE identities and RNTIs
per-UE ranks and codewords
per-UE CSI/SRS states
per-UE precoder bundles
per-UE power allocation
DM-RS identities/ports/CDM/OCC
cross-user interference prediction
receiver/covariance policy
scheduler utility and admission decision
```

The sample-domain waveform must contain simultaneous contributions from all scheduled UEs on the shared resources.

Implement at least:

- two-UE DL MU-MIMO strict profile;
- four-UE DL MU-MIMO bounded profile;
- two-UE UL MU-PUSCH strict profile if the capability matrix enables it;
- orthogonal-pilot positive cases;
- pilot-collision negative cases;
- near-far power cases;
- highly correlated-channel rejection;
- well-separated-channel admission;
- covariance ageing and IRC availability cases.

Export per UE and cross pair:

```text
scheduled/admitted
channel correlation
precoder leakage
predicted SINR
measured SINR
interference covariance
power
DM-RS identity
decoded CRC
BLER
goodput
scheduler accounting
```

A sum-throughput improvement is not sufficient if one UE identity, pilot, power or CRC is wrong.
# 15. Multi-TRP and coherent joint transmission

Implement non-coherent joint transmission before coherent joint transmission.

## 15.1 NCJT

The bounded two-TRP NCJT profile must include:

```text
TRP identities
per-TRP carrier/BWP and TCI state
per-TRP channel and beam
per-TRP power
transmission occasion ownership
HARQ and control ownership
UE combining policy
```

Do not call two independent repeated transmissions coherent.

## 15.2 CJT

For coherent joint transmission, model the actual composite signal:

```text
y[n] = sum_t H_t * W_t * x[n - tau_t] * exp(j*phi_t[n]) + z[n]
```

where each TRP has independently explicit:

```text
timing offset tau_t
carrier-frequency offset
initial phase
phase-noise process
sample clock state
power and calibration
channel and precoder
```

CJT may be labelled coherent only when the configured synchronization bounds are met and applied to samples. The controlled experiment must demonstrate:

- coherent gain when timing and phase align;
- loss under deterministic phase error;
- loss under residual timing error;
- failure outside the cyclic-prefix/coherence bounds;
- selected versus applied per-TRP matrix and phase digest;
- correct TCI/QCL state and report ownership.
# 16. FR2 hybrid beamforming profile

A strict hybrid profile must declare:

```text
number of physical antennas
number of RF chains
number of layers
subarray or fully connected architecture
analog phase-shifter constraints
phase quantization bits
amplitude constraints
frequency dependence
analog beam codebook
baseband digital precoder
training/measurement resources
calibration state
```

Use:

```text
W_total[k] = F_RF[k] * F_BB[k]
```

with the exact architecture constraints. If analog weights are phase-only, enforce constant modulus and quantized phase. Reconcile total and per-antenna power after the product.

Implement and test:

- valid RF-chain/layer limits;
- analog beam search from measured reference signals;
- baseband precoder selection conditioned on the selected analog beam;
- phase quantization impact;
- beam squint across bandwidth;
- calibration amplitude/phase error;
- blocked-beam recovery;
- selected versus applied analog and digital matrix digests;
- no hidden full-digital fallback.
# 17. Complete beam-management state machine

Implement an event-sourced state machine for the bounded profile:

```text
IDLE
P1_SWEEP_CONFIGURED
P1_MEASURING
P1_REPORT_PENDING
P1_REPORT_DECODED
P2_REFINEMENT_CONFIGURED
P2_MEASURING
P2_REPORT_PENDING
P3_UE_SPECIFIC_MEASURING
TCI_ACTIVATION_PENDING
TCI_ACTIVE
BEAM_APPLICATION_PENDING
BEAM_APPLIED
BEAM_FAILURE_MONITORING
BEAM_FAILURE_DECLARED
BFR_PRACH_PENDING
BFR_RESPONSE_PENDING
RECOVERED
FAILED
```

State transitions must be driven by actual events:

```text
SSB/CSI-RS/SRS transmission
measured RSRP/SINR
measurement filtering
UCI beam report
PDCCH/RRC/MAC TCI activation where applicable
application-time expiry
data/control transmission using the new beam
beam-failure detection measurements and timers
candidate-beam measurement
BFR random-access resource and response
```

The state machine must preserve:

```text
UEID
beam/resource identity
measurement value and timestamp
report identity
selected beam
TCI state
activation command identity
application slot
actual applied beam digest
failure counter/timer
recovery attempt identity
```

Geometry may be used to create a channel, but not to directly select the winning beam in strict mode.
# 18. Detailed remediation of the 16 registered findings
## MIMO-005 — RI/PMI/CQI are packed into a custom fixed container rather than exact report-dependent CSI Part 1/Part 2 bits.

**Priority:** P0  
**Classification:** Confirmed shortcut  
**Required profile:** CSI feedback strict profile  
**Current evidence:** `+sixgr/+mimo/buildCSIFeedback.m:24-64`

### Required production implementation

Implement TS 38.214 report semantics and TS 38.212 UCI serialization; remove custom packing from strict paths.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Bit-exact independent vectors cover all declared report configurations and UCI channels.

### Baseline

TS 38.212; TS 38.214
## MIMO-013 — The detector silently falls back to MMSE when interference covariance is unavailable, while an IRC configuration may still be requested.

**Priority:** P0  
**Classification:** Confirmed shortcut  
**Required profile:** IRC strict profile  
**Current evidence:** `+sixgr/+mimo/mimoDetect.m:41-59`

### Required production implementation

In strict IRC mode require a finite positive-semidefinite covariance with provenance and age; otherwise fail or mark IRC unavailable. Use an explicitly named MMSE fallback only in study mode.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Removing covariance causes strict failure; valid covariance changes the detector and improves the designed interference case.

### Baseline

Receiver implementation profile; TS 38.214 measurements
## MIMO-001 — The implemented NR codebook is explicitly a compact Type-I single-panel DFT codebook, mainly ranks 1-2.

**Priority:** P1  
**Classification:** Confirmed shortcut  
**Required profile:** Codebook-based MIMO strict profile  
**Current evidence:** `+sixgr/+mimo/buildNRCodebook.m:1-60`

### Required production implementation

Define the exact supported Type-I single-panel subset with release/table parameters; implement missing declared ranks/antenna configurations or reject them.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Independent codebook-vector tests match every declared candidate and reject unsupported panel/rank combinations.

### Baseline

TS 38.214
## MIMO-003 — PMI selection maximizes ||H·W||²_F, not the complete configured CSI reporting/receiver objective.

**Priority:** P1  
**Classification:** Confirmed shortcut  
**Required profile:** PMI selection strict profile  
**Current evidence:** `+sixgr/+mimo/selectPMI.m:1-45`

### Required production implementation

Implement report-configuration-aware PMI selection using the declared receiver, interference covariance, layer mapping, SINR/MI metric, subband/wideband scope, and codebook restrictions.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Selected PMI matches exhaustive independent metric evaluation for deterministic channels and changes correctly with interference covariance.

### Baseline

TS 38.214
## MIMO-004 — Effective rank is selected through SVD/lab thresholds rather than a complete CSI reporting procedure and calibrated BLER/throughput objective.

**Priority:** P1  
**Classification:** Confirmed shortcut  
**Required profile:** RI selection strict profile  
**Current evidence:** `+sixgr/+mimo/resolveNominalVsEffectiveMIMO.m; buildCSIFeedback.m`

### Required production implementation

Use configured CSI report quantities and calibrated per-rank post-processing SINR/throughput with overhead and constraints; report uncertainty/age.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Deterministic channel cases select the analytically optimal allowed rank; multi-seed campaigns meet target BLER without configured-rank collapse.

### Baseline

TS 38.214
## MIMO-006 — Low-level ranks up to 8 exist, but high-rank CSI feedback, codebook selection, layer SINR, HARQ, and scheduler operation are not fully proven.

**Priority:** P1  
**Classification:** Validation gap  
**Required profile:** High-rank downlink strict profile  
**Current evidence:** `PDSCH conformance row; high-rank focused tests`

### Required production implementation

Build end-to-end rank 1-8 profiles for supported antenna sizes and channels, with codeword-aware BLER and effective-rank evidence.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Per-rank multi-seed campaigns pass configured/effective rank, codeword/layer, BLER, and throughput gates.

### Baseline

TS 38.211; TS 38.212; TS 38.214
## MIMO-011 — Array pose, element pattern, polarization, XPR, port mapping and logical-to-physical projection are not consistently validated end-to-end.

**Priority:** P1  
**Classification:** Validation gap  
**Required profile:** Antenna/channel strict profile  
**Current evidence:** `channel/MIMO conformance rows; TDL/CDL limitations`

### Required production implementation

Create canonical antenna/panel/port objects used by codebook, channel, power normalization, and reports; preserve polarization and pattern through the channel.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Deterministic array-response tests match analytical steering/polarization and actual applied port mappings.

### Baseline

TR 38.901; TS 38.214
## MIMO-014 — Interference covariance estimation, regularization, sample support, aging, per-PRB granularity, and calibration are not publication-gated.

**Priority:** P1  
**Classification:** Validation gap  
**Required profile:** IRC/MU/interference profiles  
**Current evidence:** `IRC issue ledger and detector paths`

### Required production implementation

Implement estimator metadata, shrinkage/conditioning, validity tests, and held-out interference campaigns.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Estimated covariance is PSD, well-conditioned, source-correct, and yields expected SINR/BLER behavior across seeds.

### Baseline

Receiver implementation profile
## MIMO-015 — TPMI/RI estimation helpers are not yet the authoritative live scheduler/DCI source with complete applied-beam evidence.

**Priority:** P1  
**Classification:** Confirmed shortcut  
**Required profile:** SRS-driven UL MIMO  
**Current evidence:** `docs/static_audit_fix_report.md issue 18; phase6 limitations`

### Required production implementation

Connect measured SRS decision to scheduler, DCI, PUSCH precoder, and applied-beam artifacts with timestamps and UE/resource identity.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

The scheduler-selected TPMI equals the PUSCH-applied matrix and changes with measured channel; no config-only override remains.

### Baseline

TS 38.214
## MIMO-016 — Configured rank/ports/precoder can pass focused anchors without broad no-collapse, power-normalization, condition-number, and per-layer performance campaigns.

**Priority:** P1  
**Classification:** Validation gap  
**Required profile:** MIMO strict profiles  
**Current evidence:** `MIMO conformance matrix; fixed-anchor tests`

### Required production implementation

Require per-trial configured-versus-applied rank/ports/W, power, per-layer SINR/EVM/BLER, and multi-seed no-collapse gates.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Every declared MIMO profile passes per-layer accounting and no hidden rank/port/beam reduction.

### Baseline

TS 38.211; TS 38.214
## MIMO-002 — Type-I multi-panel, Type-II/eType-II, high-resolution, multi-TRP and other advanced CSI codebooks are not implemented end-to-end.

**Priority:** P2  
**Classification:** Unsupported profile  
**Required profile:** Advanced CSI codebook profile  
**Current evidence:** `MIMO conformance matrix and issue plan`

### Required production implementation

Keep unsupported in baseline; add one bounded codebook profile at a time with exact parameterization, payload serialization, search, and scheduler use.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Each enabled codebook has independent candidate/payload vectors and measured performance campaigns.

### Baseline

TS 38.214
## MIMO-007 — Broad rank-2 to rank-4 UL codebook/non-codebook feedback and receiver evidence are incomplete.

**Priority:** P2  
**Classification:** Unsupported profile  
**Required profile:** High-rank uplink strict profile  
**Current evidence:** `PUSCH conformance row and phase limitations`

### Required production implementation

Implement SRS-based rank/TPMI, exact UL codebook mapping, layer-aware power, channel estimation, and receiver detection for the declared subset.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Independent TPMI/codebook vectors and multi-rank BLER campaigns pass.

### Baseline

TS 38.214
## MIMO-008 — Sample-domain multi-user waveform overlap primitives exist, but full scheduler, pilot, power, control, covariance, feedback and decoding procedures are not closed.

**Priority:** P2  
**Classification:** Confirmed shortcut  
**Required profile:** MU-MIMO profile  
**Current evidence:** `phase6 limitations; interference/runtime helpers`

### Required production implementation

Create an explicit MU-MIMO profile with shared-resource grants, orthogonal/non-orthogonal RS design, per-UE precoders/power, covariance estimation, IRC/SIC policy, and decoded control.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Two-or-more UE shared-PRB campaigns show correct identity isolation, SINR, BLER, and scheduler accounting.

### Baseline

TS 38.211; TS 38.214
## MIMO-009 — Multi-TRP state, QCL/TCI, timing/phase coherence, control, feedback, and joint transmission/reception are not complete.

**Priority:** P2  
**Classification:** Unsupported profile  
**Required profile:** Multi-TRP/coherent transmission profile  
**Current evidence:** `MIMO/beam limitations and research modules`

### Required production implementation

Implement bounded non-coherent then coherent multi-TRP profiles with explicit synchronization, per-TRP channel/beam/power, and report ownership.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Controlled two-TRP channels demonstrate expected combining and failure under timing/phase mismatch.

### Baseline

TS 38.214; TS 38.331
## MIMO-010 — Hybrid analog/digital beamforming, RF-chain limits, beam squint, per-panel calibration, and codebook/search procedures are not normative end-to-end features.

**Priority:** P2  
**Classification:** Unsupported profile  
**Required profile:** FR2 hybrid-beamforming profile  
**Current evidence:** `MIMO/beam code and research issue ledger`

### Required production implementation

Fence research models; for a strict profile define RF-chain architecture, analog codebook, digital precoder, training, feedback, and impairment calibration.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Beam-training and data campaigns use the actually applied hybrid weights and meet power/EVM constraints.

### Baseline

TS 38.214; implementation/RF profile
## MIMO-012 — Beam sweeping, measurement, refinement, reporting, TCI activation, failure detection and recovery are not a complete state machine.

**Priority:** P2  
**Classification:** Unsupported profile  
**Required profile:** Beam-management profile  
**Current evidence:** `phase limitations; beam evidence is focused`

### Required production implementation

Implement bounded beam-management profiles with measured SSB/CSI-RS/SRS inputs, timers, report payloads, and control/data application.

### Why the current behavior is technically invalid

Without this correction, the mimo, csi, precoding and beamforming result is incomplete, ambiguous, or unsuitable for a strict conformance claim.

### Mandatory acceptance

Mobility/blockage tests perform measured beam transitions with no configured winning beam.

### Baseline

TS 38.213; TS 38.214; TS 38.215; TS 38.331
# 19. Source migration requirements

Use `mimo_source_change_map.csv` as the minimum source-edit list. Do not satisfy the task by adding classes that no production caller uses.

For every migrated function:

1. identify all call sites;
2. replace ad-hoc fields with the canonical typed object;
3. remove or fence legacy fallback logic;
4. add a compatibility façade only when required by existing public APIs;
5. prove via a dependency test that strict runners call the canonical implementation;
6. delete dead duplicate helpers after callers migrate;
7. preserve backwards compatibility only for explicitly labelled study/calibration profiles.

Minimum source changes:
| Component                           | FileOrAction                                                 | RequiredChange                                                                                                            |
|:------------------------------------|:-------------------------------------------------------------|:--------------------------------------------------------------------------------------------------------------------------|
| Antenna capability/profile registry | NEW:+sixgr/+phy/+mimo/MIMOCapabilityProfile.m                | Create explicit supported tuples by release, direction, ports, panel, codebook, rank, CSI quantity, receiver and feature. |
| Canonical array model               | NEW:+sixgr/+phy/+mimo/AntennaPanel.m                         | Own geometry, element pattern, polarization, port mapping, pose, calibration and frequency response.                      |
| Canonical codebook engine           | REPLACE:+sixgr/+mimo/buildNRCodebook.m                       | Delegate to exact Type-I single/multi-panel, Type-II/port-selection and selected enhanced Type-II constructors.           |
| PMI selector                        | REPLACE:+sixgr/+mimo/selectPMI.m                             | Exhaustive configured objective over codebook, covariance, receiver, wideband/subband and rank.                           |
| RI selector                         | REFACTOR:+sixgr/+mimo/resolveNominalVsEffectiveMIMO.m        | Separate runtime selection from evidence export; remove configured-SNR/SVD/fallback shortcuts.                            |
| CSI report builder                  | REPLACE:+sixgr/+mimo/buildCSIFeedback.m                      | Build typed report-dependent CSI Part1/Part2 and no custom hex payload.                                                   |
| CSI payload serializer              | REPLACE:+sixgr/+phy/+dl/packCSIFeedbackPayload.m             | Use TS 38.214 fields plus TS 38.212 UCI serialization.                                                                    |
| Advanced codebooks                  | REPLACE:+sixgr/+phy/+dl/pmiCodebookCandidates.m              | No generic DFT labels; exact profile-specific enumeration and restrictions.                                               |
| DL CSI processing                   | REFACTOR:+sixgr/+phy/+dl/CSI_Feedback.m                      | Consume report config, measurement state and exact field objects.                                                         |
| DL precoder integration             | REFACTOR:+sixgr/+phy/+dl/resolvePDSCHPrecoding.m             | Apply immutable wideband/subband/PRG matrices and TCI state.                                                              |
| UL precoder integration             | REFACTOR:+sixgr/+phy/+ul/resolvePUSCHPrecoding.m             | Apply authoritative measured-SRS RI/SRI/TPMI decision.                                                                    |
| SRS selection                       | REFACTOR:+sixgr/+mimo/selectULBeamFromSRS.m                  | Remove rank2/configured-SNR defaults; add timestamped measured state.                                                     |
| SRS RI/TPMI                         | EXTEND:+sixgr/+phy/+ul/estimateSRSRITPMI.m                   | Exact UL codebook/non-codebook candidate matrix and objective.                                                            |
| Linear receiver                     | REFACTOR:+sixgr/+phy/+rx/mimoDetect.m                        | Strict receiver selection; no silent IRC downgrade.                                                                       |
| Covariance estimator                | REPLACE:+sixgr/+phy/+rx/estimateInterferenceCovarianceIRC.m  | Per-PRB/subband covariance with sample support, age, shrinkage, PSD and held-out quality.                                 |
| Precoder application                | REFACTOR:+sixgr/+phy/+mimo/precoder.m                        | One matrix orientation, no identity fallback, immutable matrix and exact power ledger.                                    |
| MU/Multi-TRP waveform               | REFACTOR:+sixgr/+mimo/executeSpatialComposite.m              | Typed grants, per-UE/TRP identity, clocks, channel, phase, power and actual decoding.                                     |
| CSI-RS beam refinement              | REPLACE:+sixgr/+rf/BeamRefinementCSIRS.m                     | Measured CSI-RS resources, report trigger, refinement state and TCI application.                                          |
| SRS reciprocity                     | REPLACE:+sixgr/+rf/BeamformingSRSReciprocity.m               | Calibration-aware measured SRS state and codebook/non-codebook procedure.                                                 |
| Beam selection                      | REPLACE:+sixgr/+system/selectBestBeamPerLink.m               | Geometry only configures channel; measured RS selects beam.                                                               |
| Beam state machine                  | NEW:+sixgr/+phy/+beam/BeamManagementStateMachine.m           | P1/P2/P3 measurements, report, TCI activation, application, failure and recovery.                                         |
| Multi-TRP state                     | NEW:+sixgr/+phy/+mimo/MultiTRPTransmissionContext.m          | NCJT/CJT timing, phase, power, TCI, report and combining ownership.                                                       |
| Hybrid beamforming                  | NEW:+sixgr/+phy/+mimo/HybridBeamformer.m                     | RF-chain constrained analog/digital weights, codebooks, squint and calibration.                                           |
| Artifact runner                     | NEW:+sixgr/+phy/+mimo/runMIMOCSIBeamformingPhaseValidation.m | Execute vectors, waveform campaigns and export all base artifacts.                                                        |
| Impact runner                       | NEW:+sixgr/+phy/+mimo/runMIMOCSIBeamformingImpactAnalysis.m  | Execute paired impact matrix and statistics.                                                                              |
# 20. Typed errors and fail-before-waveform behavior

Use the following typed-error contract. Each negative vector expects the exact identifier. Do not replace these with generic assertions, warnings or `try/catch` continuation.
| ErrorIdentifier                             | Meaning                                                                           | StrictAction                         |
|:--------------------------------------------|:----------------------------------------------------------------------------------|:-------------------------------------|
| sixgr:mimo:UnsupportedProfile               | Requested capability profile is not enabled.                                      | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:UnsupportedAntennaTuple          | Port/panel/polarization tuple is outside the selected profile.                    | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidPanelGeometry             | Panel dimensions or spacing are invalid.                                          | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidPortMapping               | Logical CSI-RS/SRS/DM-RS ports do not map uniquely to physical ports.             | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidPolarization              | Polarization/XPR definition is inconsistent.                                      | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidCodebookType              | Codebook type is unsupported or inconsistent with RRC state.                      | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidCodebookSubsetRestriction | Subset restriction length or domain is invalid.                                   | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:UnsupportedRank                  | Rank is unsupported for the selected ports/codebook/direction.                    | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidPMI                       | PMI indices are outside the configured candidate domain.                          | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidRI                        | RI is outside the configured rank domain.                                         | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidLI                        | Layer indicator is inconsistent with RI/codeword state.                           | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidCRI                       | CSI-RS resource indicator is not part of the measurement set.                     | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidCQI                       | CQI is outside the configured table/domain.                                       | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:MissingCSIReportConfig           | No active CSI report configuration exists.                                        | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:StaleCSIReportConfig             | CSI report configuration epoch is stale.                                          | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:MissingMeasurementState          | Required CSI-RS/SRS/SSB measurement state is unavailable.                         | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:StaleMeasurementState            | Measurement age exceeds the configured validity window.                           | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidCSIPart1Length            | CSI Part 1 length differs from the report schema.                                 | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidCSIPart2Length            | CSI Part 2 length differs from the report schema.                                 | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:CSISerializationMismatch         | Decoded report fields do not reproduce the serialized bits.                       | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:UnsupportedTypeIIProfile         | Requested Type-II variant is not enabled.                                         | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:UnsupportedMultiPanelProfile     | Requested Type-I multi-panel tuple is not enabled.                                | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:MissingInterferenceCovariance    | Strict IRC requires covariance.                                                   | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidInterferenceCovariance    | Covariance is nonfinite, non-Hermitian or non-PSD.                                | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InsufficientCovarianceSamples    | Covariance sample support is below the profile threshold.                         | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:StaleInterferenceCovariance      | Covariance age exceeds the validity window.                                       | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:IllConditionedCovariance         | Covariance conditioning remains invalid after allowed shrinkage.                  | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:PrecoderDimensionMismatch        | Precoder dimensions do not equal Nport-by-Nlayer.                                 | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:PrecoderNormalizationMismatch    | Precoder violates the expected normalization/power contract.                      | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:PrecoderDigestMismatch           | Selected and applied precoder digests differ.                                     | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:ConfiguredPrecoderOverride       | Configuration attempted to override an authoritative measured decision.           | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:RankCollapse                     | Applied rank is lower than the valid scheduled rank without a new decision event. | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:PortCollapse                     | Applied physical/logical port set differs from the assignment.                    | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:MissingSRSDecision               | UL codebook/non-codebook PUSCH requires measured SRS decision state.              | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:StaleSRSDecision                 | SRS decision state is too old for the transmission occasion.                      | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidMUResourceSharing         | MU users do not share the declared resource or violate pilot/port constraints.    | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:MUIdentityCollision              | UE identities or reference-signal identities collide.                             | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:MissingTRPState                  | Multi-TRP transmission lacks per-TRP state.                                       | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:TRPTimingMismatch                | CJT timing mismatch exceeds the selected coherence limit.                         | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:TRPPhaseMismatch                 | CJT phase/calibration mismatch exceeds the selected limit.                        | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InactiveTCIState                 | Scheduled TCI state is not active.                                                | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:QCLSourceMismatch                | QCL/TCI source does not match the scheduled data/control resource.                | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:MissingHybridBeamState           | FR2 hybrid profile lacks analog/digital/RF-chain state.                           | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:RFChainLimitExceeded             | Requested streams exceed available RF chains.                                     | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:AnalogWeightConstraintViolation  | Analog weights violate constant-modulus/quantization constraints.                 | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:BeamSquintLimitExceeded          | Frequency-dependent beam loss exceeds profile bound.                              | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:BeamMeasurementOracleForbidden   | Configured/geometry winning beam was supplied to strict selection.                | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:BeamReportMismatch               | Beam report does not match measured resources and report config.                  | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:InvalidBeamStateTransition       | Beam state-machine transition is illegal.                                         | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:BeamFailureTimerExpired          | Beam failure was not recovered within configured procedure.                       | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
| sixgr:mimo:UnsupportedResearchFallback      | Research-only SVD/MRT/identity fallback entered a strict profile.                 | FAIL_BEFORE_WAVEFORM_OR_STATE_CHANGE |
# 21. Independent vector pack

Place this pack under:

```text
tests/vectors/mimo/
```

The manifest `independent_vector_manifest.json` protects 24 files and 4,228 rows. The supplied vectors are a bounded independent floor, not a substitute for complete normative vectors for every enabled codebook.

Mandatory supplied files include:

```text
mimo_capability_profile_matrix.csv
expected_typeI_2port_codebook.csv
expected_antenna_array_response.csv
mimo_port_mapping_test_vectors.csv
mimo_csi_report_schema_test_vectors.csv
expected_csi_bit_ownership_floor.csv
mimo_ri_pmi_metric_test_vectors.csv
expected_mimo_ri_pmi_selection.csv
mimo_covariance_test_vectors.csv
mimo_precoder_application_test_vectors.csv
mimo_srs_authority_test_vectors.csv
mimo_mu_mimo_test_vectors.csv
mimo_multitrp_test_vectors.csv
mimo_hybrid_beamforming_test_vectors.csv
mimo_beam_state_transition_vectors.csv
mimo_negative_test_vectors.csv
mimo_declared_coverage_matrix.csv
```

Add frozen independent files for every enabled general Type-I, multi-panel, Type-II and enhanced Type-II tuple before enabling that tuple. Record:

```text
ReferenceID
ReferenceType
SpecificationVersion
Clause/Table
GeneratorImplementation
GeneratorVersion
GenerationCommand
FileSHA256
RowCount
```

Never generate the reference vectors with the DUT code in the same test execution.
# 22. Mandatory MATLAB tests

Implement and run every row in `mimo_matlab_test_plan.csv`. No mandatory test may be skipped or blocked when reporting completion.
| TestName                              | Scope                                          | Mandatory   | RequiredResult                 |
|:--------------------------------------|:-----------------------------------------------|:------------|:-------------------------------|
| testMIMOCapabilityProfile             | Capability tuple positive/negative matrix      | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testAntennaPanelGeometry              | Element positions, spacing, pose and steering  | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testAntennaPolarizationAndXPR         | Dual-polarized response and cross-polar terms  | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testLogicalPhysicalPortMapping        | CSI-RS/SRS/DM-RS/data port projection          | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testPrecoderMatrixConvention          | Nport-by-Nlayer strict orientation             | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testPrecoderPowerNormalization        | Column/total/per-port power invariants         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testTypeI2PortCodebook                | Exact rank1/rank2 table vectors                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testTypeISinglePanelRank1To8          | Selected single-panel codebooks ranks 1-8      | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testTypeISinglePanelSubsetRestriction | Subset restriction bitmaps                     | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testTypeIMultiPanelCodebook           | Selected multi-panel tuples                    | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testTypeIIPortSelectionCodebook       | Bounded Type-II port-selection profile         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testEnhancedTypeIICodebook            | Bounded enhanced Type-II profile               | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testUnsupportedCodebookPlanning       | All unimplemented variants reject before run   | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIReportConfigMaterializer       | RRC context to immutable report schema         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSITypeIPart1Part2                | Exact Type-I fields and lengths                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSITypeIIPart1Part2               | Exact Type-II fields and lengths               | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIEnhancedTypeIIPart1Part2       | Exact bounded eType-II fields                  | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIReportPUCCHSerialization       | CSI report through PUCCH UCI coding            | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIReportPUSCHSerialization       | CSI report through PUSCH UCI coding            | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIWrongLengthAndContext          | Wrong Part1/Part2/configuration rejection      | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIWidebandSubbandGranularity     | Frequency granularity and report fields        | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testRISelectionIndependentObjective   | Exhaustive objective comparison                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testPMISelectionIndependentObjective  | Exhaustive candidate metric comparison         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCQILICRISelection                 | CQI/LI/CRI report semantics                    | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIInterferenceMeasurement        | CSI-IM/NZP-CSI-RS interference state           | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCSIMeasurementAge                 | Stale CSI measurement rejection                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testDLClosedLoopMIMO                  | CSI→scheduler→PDSCH applied precoder           | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testULClosedLoopMIMO                  | SRS→scheduler→PUSCH applied precoder           | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testHighRankDLPDSCH                   | DL ranks 1-8 no-noise and fading               | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testHighRankULPUSCH                   | UL declared ranks and codewords                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testTwoCodewordRank5To8               | Two-codeword mapping and HARQ                  | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testNoRankCollapse                    | Configured/selected/applied rank identity      | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testNoPortCollapse                    | Logical and physical port identity             | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testPerLayerSINRAndEVM                | Receiver-derived per-layer metrics             | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testPRGPrecoding                      | Wideband/subband/PRG matrix application        | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCovarianceEstimatorPSD            | Hermitian PSD and conditioning                 | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCovarianceMinimumSamples          | Sample support and held-out validation         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCovarianceAgeAndGranularity       | Age, PRB/subband identity and validity         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testStrictIRCNoFallback               | Missing covariance produces typed failure      | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testIRCInterferenceGain               | IRC versus MMSE in designed interference       | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMUMIMO2UE                         | Two-UE shared PRB waveform and decoding        | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMUMIMO4UE                         | Four-UE bounded scheduler and decoding         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMUReferenceSignalIsolation        | DM-RS/CSI-RS identity isolation                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMUPrecoderPowerAccounting         | Per-UE power and total power                   | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testNCJT2TRP                          | Two-TRP noncoherent transmission               | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCJT2TRPPerfectSync                | Coherent gain with valid sync/calibration      | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testCJT2TRPTimingPhaseFailure         | Expected loss/rejection under mismatch         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMultiTRPTCIAndReportOwnership     | Per-TRP TCI/CSI ownership                      | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testHybridBeamformerRFChainLimit      | RF-chain and stream constraints                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testHybridAnalogWeightConstraints     | Constant modulus and quantization              | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testHybridBeamSquint                  | Frequency-dependent array response             | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testBeamP1Acquisition                 | Measured SSB/CSI-RS beam acquisition           | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testBeamP2Refinement                  | CSI-RS beam refinement                         | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testBeamP3UETxSelection               | SRS-based UL beam selection                    | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testTCIActivationApplication          | TCI MAC/RRC state to actual W                  | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testBeamFailureRecovery               | Failure detection, candidate beam and recovery | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testBeamMobilityAndBlockage           | Measured transitions without geometry oracle   | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMONoSignalFalseDecision         | No-signal RI/PMI/beam false decision           | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMOWrongIdentity                 | Wrong CSI-RS/SRS/UE/TRP identity rejection     | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMOAWGNCampaign                  | Rank/codebook sanity in AWGN                   | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMOTDLCampaign                   | Frequency-selective TDL campaigns              | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMOCDLCampaign                   | Spatial CDL/polarized campaigns                | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMOMultiSeedReproducibility      | Serial/parallel deterministic seeds            | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMOArtifactGeneration            | All base CSV/PNG artifacts                     | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
| testMIMOImpactAnalysis                | All paired impact experiments and rules        | True        | PASS_WITH_ZERO_SKIPS_OR_BLOCKS |
# 23. Required base validation runner

Implement:

```matlab
result = sixgr.phy.mimo.runMIMOCSIBeamformingPhaseValidation( ...
    'VectorRoot', fullfile(pwd,'tests','vectors','mimo'), ...
    'OutputDir', fullfile(pwd,'artifacts','mimo_csi_beamforming_phase'), ...
    'SeedList', [11 23 47 89], ...
    'ConfidenceLevel', 0.95, ...
    'Strict', true);
```

The runner must execute, at minimum:

1. all capability positive and negative rows;
2. exact antenna-array and port-projection vectors;
3. exact Type-I 2-port vectors;
4. every enabled codebook tuple and frozen vector;
5. CSI Part 1/Part 2 construction, serialization, UCI transmission and decode;
6. deterministic RI/PMI objective cases;
7. selected-versus-applied precoder digest checks;
8. DL high-rank no-noise/AWGN/TDL/CDL cases;
9. UL SRS-driven high-rank cases;
10. covariance and strict IRC cases;
11. MU-MIMO shared-resource cases;
12. NCJT and CJT cases;
13. hybrid beamforming cases;
14. beam-management state-transition cases;
15. all negative vectors;
16. required artifact generation and semantic audit.

Every runtime row must carry the actual profile, measurement state, decoded report, selected matrix and applied matrix identities.
# 24. Base CSV output contract

Generate all base CSVs from actual production execution. Do not copy expected vector files into the artifact directory.
| FileName                            | PrimaryKey                                       |   MinRows | RequiredColumns                                                                                                                                                                                                                                                    |
|:------------------------------------|:-------------------------------------------------|----------:|:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| mimo_run_manifest.csv               | RunID                                            |         1 | RunID|GitCommit|MATLABVersion|ToolboxVersion|SpecProfile|SeedList|VectorManifestSHA256|Strict|Status                                                                                                                                                               |
| mimo_capability_resolution.csv      | RunID|ProfileID|TupleID                          |        50 | RunID|ProfileID|TupleID|Direction|CodebookType|Ports|Panels|N1|N2|O1|O2|Rank|Supported|ExpectedSupported|ParametersMutated|PlanningRejected|Status                                                                                                                 |
| mimo_antenna_panel.csv              | RunID|PanelID|ElementID|FrequencyHz              |       100 | RunID|PanelID|ElementID|FrequencyHz|XLambda|YLambda|ZLambda|Polarization|LogicalPort|PhysicalPort|PatternGainDB|SteeringReal|SteeringImag|IndependentMismatchCount|Status                                                                                          |
| mimo_port_mapping.csv               | RunID|MappingID|LogicalPort                      |        32 | RunID|MappingID|LogicalPort|PhysicalElement|Polarization|MappingEpoch|Bijective|IndependentMismatchCount|Status                                                                                                                                                    |
| mimo_codebook_candidates.csv        | RunID|ProfileID|Rank|CandidateID|PRGID           |        40 | RunID|ProfileID|CodebookType|Ports|Rank|CandidateID|PRGID|CodebookIndices|SubsetAllowed|MatrixSHA256|FrobeniusPower|OrthogonalityError|GenericDFTApproximationUsed|Status                                                                                          |
| mimo_codebook_vector_results.csv    | RunID|VectorID|Port|Layer                        |        16 | RunID|VectorID|CodebookType|Ports|Rank|PMI|Port|Layer|ExpectedReal|ExpectedImag|ActualReal|ActualImag|AbsoluteError|MatrixSHA256|IndependentMismatchCount|Status                                                                                                   |
| mimo_csi_report_config.csv          | RunID|UEID|ReportConfigID|Epoch                  |         8 | RunID|UEID|ReportConfigID|Epoch|CodebookType|ReportQuantity|ReportType|ChannelResourceConfigID|InterferenceResourceConfigID|FrequencyGranularity|UCIChannel|Part1ExpectedBits|Part2ExpectedBits|ConfigurationProvenance|Status                                     |
| mimo_csi_part1_part2.csv            | RunID|UEID|ReportID|Part                         |        20 | RunID|UEID|ReportID|ReportConfigID|Part|FieldOrder|InformationBits|EncodedBits|DecodedBits|BitErrors|CRCPassed|SeparateEncoding|CustomContainerUsed|Status                                                                                                         |
| mimo_csi_bit_ownership.csv          | RunID|ReportID|Part|BitIndex                     |       100 | RunID|ReportID|Part|BitIndex|Field|FieldBitIndex|OwnerCount|ExpectedOwner|ActualBit|ExpectedBit|Mismatch|Status                                                                                                                                                    |
| mimo_ri_pmi_selection.csv           | RunID|UEID|DecisionID|CandidateRank|CandidatePMI |        30 | RunID|UEID|DecisionID|ReportConfigID|MeasurementID|CandidateRank|CandidatePMI|CandidateMetric|Objective|SelectedRI|SelectedPMI|ExpectedRI|ExpectedPMI|SelectedMatrixSHA256|ExpectedMatrixSHA256|ConfiguredSNRUsed|SVDThresholdUsed|IndependentMismatchCount|Status |
| mimo_cqi_li_cri_selection.csv       | RunID|UEID|DecisionID                            |         8 | RunID|UEID|DecisionID|CQI|LI|CRI|Codeword0SINRDB|Codeword1SINRDB|CQITable|ReportQuantity|ExpectedCQI|ExpectedLI|ExpectedCRI|IndependentMismatchCount|Status                                                                                                        |
| mimo_measurement_state.csv          | RunID|UEID|MeasurementID|ResourceID|PRGID        |        20 | RunID|UEID|MeasurementID|ResourceType|ResourceID|PRGID|Slot|AgeSlots|MaxAgeSlots|MeasuredSINRDB|NoiseVariance|CovarianceID|ChannelEstimateSHA256|MeasurementProvenance|ConfiguredOracleUsed|Valid|Status                                                           |
| mimo_precoder_selection.csv         | RunID|UEID|DecisionID|PRGID                      |        12 | RunID|UEID|DecisionID|Direction|Rank|PMI|SRI|TPMI|PRGID|SelectionObjective|MeasurementID|MatrixSHA256|MatrixRows|MatrixColumns|ConfiguredOverrideUsed|FallbackUsed|Status                                                                                          |
| mimo_precoder_application.csv       | RunID|UEID|TransmissionID|PRGID                  |        12 | RunID|UEID|TransmissionID|Direction|Rank|LogicalPorts|PhysicalPorts|PRGID|SelectedMatrixSHA256|AppliedMatrixSHA256|MatrixRegenerated|RequestedPowerDBM|MeasuredPowerDBM|PowerErrorDB|Orientation|Status                                                            |
| mimo_rank_port_trials.csv           | RunID|TrialID|UEID                               |        20 | RunID|TrialID|UEID|ProfileID|ConfiguredRank|SelectedRank|ScheduledRank|AppliedRank|DecodedRank|ConfiguredLogicalPorts|AppliedLogicalPorts|RankCollapsed|PortCollapsed|Codewords|TBCRC0|TBCRC1|Status                                                               |
| mimo_per_layer_metrics.csv          | RunID|TrialID|UEID|Layer                         |        40 | RunID|TrialID|UEID|Layer|Rank|MeasuredSINRDB|EVMPercent|BER|BLER|ChannelGainDB|PostEQNoiseVariance|ConditionNumber|Finite|Status                                                                                                                                   |
| mimo_covariance_estimation.csv      | RunID|CovarianceID|PRGID                         |        12 | RunID|CovarianceID|UEID|PRGID|SourceResource|SampleCount|MinSamples|AgeSlots|MaxAgeSlots|HermitianError|MinEigenvalue|ConditionNumber|ShrinkageMethod|ShrinkageFactor|HeldOutError|Available|Valid|Status                                                          |
| mimo_receiver_comparison.csv        | RunID|TrialID|UEID|Receiver                      |        12 | RunID|TrialID|UEID|Receiver|RequestedReceiver|AppliedReceiver|CovarianceID|FallbackUsed|MeasuredSINRDB|EVMPercent|BLER|TBCRC|Status                                                                                                                                |
| mimo_srs_ul_decisions.csv           | RunID|UEID|DecisionID                            |        12 | RunID|UEID|DecisionID|SRSResourceID|MeasurementSlot|AgeSlots|RI|SRI|TPMI|SelectionMatrixSHA256|SchedulerMatrixSHA256|AppliedMatrixSHA256|ConfiguredOverrideUsed|Authoritative|Status                                                                               |
| mimo_mu_mimo_trials.csv             | RunID|TrialID|UEID                               |         8 | RunID|TrialID|UEID|NumUE|SharedPRBDigest|SharedSymbolDigest|DMRSIdentity|PrecoderSHA256|RequestedPowerDBM|MeasuredPowerDBM|CovarianceID|Receiver|MeasuredSINRDB|TBCRC|BLER|SchedulerAccounted|Status                                                               |
| mimo_multitrp_trials.csv            | RunID|TrialID|UEID|TRPID                         |         8 | RunID|TrialID|UEID|TRPID|Mode|TCIStateID|TimingOffsetSamples|PhaseErrorDeg|PowerDBM|PrecoderSHA256|ChannelSHA256|CombiningMethod|CombinedSINRDB|TBCRC|ValidCoherence|Status                                                                                        |
| mimo_hybrid_beamforming_trials.csv  | RunID|TrialID|SubcarrierGroup                    |         8 | RunID|TrialID|Nant|NRFChains|NStreams|SubcarrierGroup|AnalogMatrixSHA256|DigitalMatrixSHA256|ConstantModulusError|PhaseQuantizationBits|BeamSquintLossDB|CalibrationErrorDeg|MeasuredPowerDBM|EVMPercent|BLER|Status                                               |
| mimo_beam_management_events.csv     | RunID|UEID|EventSequence                         |        20 | RunID|UEID|EventSequence|Slot|FromState|Event|ToState|MeasuredResourceID|MeasuredRSRPDBM|MeasuredSINRDB|ReportedBeamID|ActivatedTCIState|AppliedBeamID|GeometryOracleUsed|TimerID|TimerValue|Status                                                                |
| mimo_bler_curve.csv                 | RunID|ProfileID|Channel|Rank|SNRDB               |        20 | RunID|ProfileID|Direction|Channel|Rank|Receiver|SNRDB|Trials|BlockErrors|BLER|CILower|CIUpper|MeanGoodputMbps|MeanSINRDB|Incomplete|StopReason|Status                                                                                                              |
| mimo_negative_tests.csv             | RunID|CaseID                                     |        20 | RunID|CaseID|FaultType|ExpectedError|ActualError|WaveformGenerated|StateChanged|GrantCreated|Passed|Status                                                                                                                                                         |
| mimo_independent_vector_results.csv | RunID|VectorFamily|VectorID                      |        20 | RunID|VectorFamily|VectorID|OracleClass|OracleImplementation|OracleVersion|OracleArtifactSHA256|Cases|MismatchCount|MaxAbsoluteError|Status                                                                                                                        |
| mimo_test_summary.csv               | RunID|TestSuite                                  |        20 | RunID|TestSuite|Mandatory|Executed|Passed|Total|Failed|Skipped|Blocked|DurationSeconds|Status                                                                                                                                                                      |
| mimo_image_semantic_audit.csv       | RunID|ImageFile                                  |        20 | RunID|ImageFile|SourceCSV|SourceCSV_SHA256|PNG_SHA256|Width|Height|AxesCount|SeriesCount|FinitePointCount|ActualTitle|ActualXLabel|ActualYLabel|Status                                                                                                             |
# 25. Base image output contract

Generate every image from the corresponding production CSV. Do not create decorative figures detached from the data.
| ImageFile                          | SourceCSV                                                 | ExpectedTitleToken               | ExpectedXLabel     | ExpectedYLabel       |   MinAxesCount |   MinSeriesCount |   MinFinitePointCount |   MinWidth |   MinHeight |
|:-----------------------------------|:----------------------------------------------------------|:---------------------------------|:-------------------|:---------------------|---------------:|-----------------:|----------------------:|-----------:|------------:|
| mimo_antenna_panel_geometry.png    | mimo_antenna_panel.csv                                    | Antenna panel geometry           | Element x [lambda] | Element z [lambda]   |              1 |                2 |                    20 |        900 |         600 |
| mimo_typeI_2port_codebook.png      | mimo_codebook_vector_results.csv                          | Type-I 2-port codebook           | Codebook index     | Coefficient          |              1 |                4 |                    12 |        900 |         600 |
| mimo_codebook_beam_patterns.png    | mimo_codebook_candidates.csv|mimo_antenna_panel.csv       | Codebook beam patterns           | Azimuth [deg]      | Normalized gain [dB] |              1 |                4 |                    50 |        900 |         600 |
| mimo_ri_pmi_objective_map.png      | mimo_ri_pmi_selection.csv                                 | RI PMI objective                 | PMI candidate      | Objective            |              1 |                2 |                    20 |        900 |         600 |
| mimo_csi_part1_part2_layout.png    | mimo_csi_part1_part2.csv|mimo_csi_bit_ownership.csv       | CSI Part 1 Part 2                | Bit index          | Field owner          |              1 |                2 |                    30 |        900 |         600 |
| mimo_wideband_subband_pmi.png      | mimo_ri_pmi_selection.csv                                 | Wideband and subband PMI         | PRG index          | PMI                  |              1 |                2 |                    12 |        900 |         600 |
| mimo_rank_application_timeline.png | mimo_rank_port_trials.csv                                 | Configured selected applied rank | Trial              | Rank                 |              1 |                4 |                    20 |        900 |         600 |
| mimo_precoder_digest_timeline.png  | mimo_precoder_selection.csv|mimo_precoder_application.csv | Selected and applied precoder    | Transmission       | Matrix identity      |              1 |                2 |                    12 |        900 |         600 |
| mimo_per_layer_sinr.png            | mimo_per_layer_metrics.csv                                | Per-layer SINR                   | Layer              | SINR [dB]            |              1 |                2 |                    20 |        900 |         600 |
| mimo_per_layer_evm.png             | mimo_per_layer_metrics.csv                                | Per-layer EVM                    | Layer              | EVM [%]              |              1 |                2 |                    20 |        900 |         600 |
| mimo_rank_bler.png                 | mimo_bler_curve.csv                                       | Rank BLER                        | SNR [dB]           | BLER                 |              1 |                4 |                    20 |        900 |         600 |
| mimo_covariance_eigenvalues.png    | mimo_covariance_estimation.csv                            | Covariance eigenvalues           | Covariance case    | Eigenvalue           |              1 |                2 |                    12 |        900 |         600 |
| mimo_irc_mmse_comparison.png       | mimo_receiver_comparison.csv                              | IRC and MMSE                     | SNR [dB]           | BLER                 |              1 |                2 |                    12 |        900 |         600 |
| mimo_srs_tpmi_timeline.png         | mimo_srs_ul_decisions.csv                                 | SRS RI SRI TPMI                  | Slot               | Decision index       |              1 |                3 |                    12 |        900 |         600 |
| mimo_mu_mimo_user_sinr.png         | mimo_mu_mimo_trials.csv                                   | MU-MIMO per-user SINR            | UE                 | SINR [dB]            |              1 |                2 |                     8 |        900 |         600 |
| mimo_multitrp_combining.png        | mimo_multitrp_trials.csv                                  | Multi-TRP combining              | Phase error [deg]  | Combined SINR [dB]   |              1 |                2 |                     8 |        900 |         600 |
| mimo_hybrid_beam_squint.png        | mimo_hybrid_beamforming_trials.csv                        | Hybrid beam squint               | Subcarrier group   | Loss [dB]            |              1 |                2 |                     8 |        900 |         600 |
| mimo_beam_state_timeline.png       | mimo_beam_management_events.csv                           | Beam management state            | Slot               | State                |              1 |                2 |                    20 |        900 |         600 |
| mimo_beam_measurements.png         | mimo_beam_management_events.csv                           | Beam measurements                | Slot               | RSRP [dBm]           |              1 |                2 |                    20 |        900 |         600 |
| mimo_profile_bler_vs_snr.png       | mimo_bler_curve.csv                                       | MIMO profile BLER                | SNR [dB]           | BLER                 |              1 |                4 |                    20 |        900 |         600 |
# 26. Impact analysis

After the base phase passes, execute the 64-family controlled impact matrix.

The supplied `mimo_impact_experiment_matrix.csv` contains 768 experiment rows, organized as matched baseline/treatment pairs. For each pair preserve the same:

```text
seed
trial index
payload identity
channel realization
noise realization
UE placement and mobility state
measurement resource state
interference realization
all configuration not named by FactorName
```

Only the declared factor may change.

## Impact dependency waves

- Wave A: direct codebook, CSI, RI/PMI, high-rank, covariance and receiver work in this phase.
- Wave B: internal MU-MIMO, multi-TRP, hybrid and beam-management integrations.
- Wave C: adjacent full-stack/RF/channel dependencies that must use real implementations rather than scalar proxies.

Do not fabricate a result for an unavailable dependency. During development it may be `blocked_dependency`; final completion requires every mandatory family selected by this prompt to execute.

The 64 families are:
| FamilyID   | Title                                           | Wave   | FactorName               | BaselineValue      | TreatmentValue    | PrimaryMetrics                 | Implementability            | RequiredDesign                         |
|:-----------|:------------------------------------------------|:-------|:-------------------------|:-------------------|:------------------|:-------------------------------|:----------------------------|:---------------------------------------|
| F01        | Type-I single-panel codebook versus compact DFT | A      | codebook_engine          | compact_dft        | exact_typeI       | PMI accuracy|BLER|goodput      | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F02        | Type-I rank breadth 1-8                         | A      | rank                     | 1                  | 8                 | throughput|BLER|condition      | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F03        | Codebook subset restriction                     | A      | subset_restriction       | disabled           | enabled           | search complexity|PMI accuracy | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F04        | Panel geometry mismatch                         | A      | panel_geometry           | correct            | inferred_square   | array gain|PMI errors          | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F05        | Polarization and XPR                            | A      | polarization_model       | co-polar           | dual-polar        | rank|SINR|BLER                 | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F06        | Port mapping permutation                        | A      | port_mapping             | correct            | permuted          | EVM|BLER|port leakage          | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F07        | RI objective SVD versus goodput                 | A      | ri_objective             | svd_threshold      | goodput           | RI accuracy|goodput            | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F08        | PMI objective gain versus post-EQ MI            | A      | pmi_objective            | frobenius_gain     | posteq_mi         | PMI|SINR|BLER                  | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F09        | Wideband versus subband PMI                     | A      | csi_granularity          | wideband           | subband           | goodput|feedback bits          | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F10        | PRG precoding                                   | A      | precoder_granularity     | wideband           | PRG               | SINR|BLER|runtime              | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F11        | CSI Part1/Part2 exact versus custom             | A      | csi_serialization        | custom10bit        | exact             | bit errors|scheduler decisions | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F12        | CSI report omission priority                    | A      | part2_capacity           | full               | constrained       | omission|goodput               | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F13        | CSI delay                                       | A      | csi_age_slots            | 0                  | 8                 | PMI age loss|BLER              | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F14        | CSI measurement noise                           | A      | csi_measurement_snr      | 20                 | 0                 | RI/PMI accuracy                | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F15        | CSI-IM interference measurement                 | A      | interference_measurement | none               | CSI-IM            | CQI calibration|BLER           | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F16        | CQI calibration                                 | A      | cqi_mapping              | heuristic          | calibrated        | BLER target|goodput            | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F17        | High-rank DL                                    | A      | dl_rank                  | 2                  | 8                 | throughput|per-layer SINR      | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F18        | High-rank UL                                    | B      | ul_rank                  | 1                  | 4                 | throughput|BLER|power          | internal_integration        | paired_same_seed_channel_noise_payload |
| F19        | Two codewords                                   | A      | codewords                | 1                  | 2                 | goodput|HARQ independence      | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F20        | SRS-derived TPMI authority                      | B      | ul_precoder_source       | configured         | measured_srs      | SINR|TPMI accuracy             | internal_integration        | paired_same_seed_channel_noise_payload |
| F21        | SRS sounding bandwidth                          | B      | srs_bandwidth            | narrow             | full              | TPMI|frequency selectivity     | internal_integration        | paired_same_seed_channel_noise_payload |
| F22        | SRS age                                         | B      | srs_age                  | 0                  | 16                | UL precoder loss               | internal_integration        | paired_same_seed_channel_noise_payload |
| F23        | Reciprocity calibration                         | B      | reciprocity              | uncalibrated       | calibrated        | DL beam gain|EVM               | internal_integration        | paired_same_seed_channel_noise_payload |
| F24        | Covariance sample count                         | A      | cov_samples              | 4                  | 128               | PSD|IRC gain                   | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F25        | Covariance age                                  | A      | cov_age                  | 0                  | 16                | IRC loss|BLER                  | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F26        | Covariance granularity                          | A      | cov_granularity          | wideband           | per_PRB           | IRC SINR|runtime               | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F27        | Covariance shrinkage                            | A      | shrinkage                | none               | LedoitWolf        | condition|BLER                 | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F28        | Receiver MMSE versus IRC                        | A      | receiver                 | MMSE               | IRC               | SINR|BLER                      | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F29        | Strict IRC no fallback                          | A      | missing_covariance       | fallback_MMSE      | strict_failure    | false pass prevention          | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F30        | ZF versus MMSE                                  | A      | receiver                 | ZF                 | MMSE              | SINR|BLER                      | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F31        | MU-MIMO 2 UE                                    | B      | mu_users                 | 1                  | 2                 | sum rate|per UE BLER           | internal_integration        | paired_same_seed_channel_noise_payload |
| F32        | MU-MIMO 4 UE                                    | B      | mu_users                 | 2                  | 4                 | sum rate|fairness|runtime      | internal_integration        | paired_same_seed_channel_noise_payload |
| F33        | MU angular separation                           | B      | angular_separation       | 5                  | 60                | condition|sum rate             | internal_integration        | paired_same_seed_channel_noise_payload |
| F34        | MU DM-RS collision                              | B      | dmrs_identity            | orthogonal         | collision         | false decode|BLER              | internal_integration        | paired_same_seed_channel_noise_payload |
| F35        | MU near-far power                               | B      | power_delta_db           | 0                  | 20                | weak UE BLER|IRC               | internal_integration        | paired_same_seed_channel_noise_payload |
| F36        | MU scheduler objective                          | B      | scheduler                | channel_gain       | weighted_sum_rate | fairness|goodput               | internal_integration        | paired_same_seed_channel_noise_payload |
| F37        | NCJT two-TRP                                    | C      | trp_mode                 | single             | NCJT              | coverage|BLER                  | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F38        | CJT perfect coherence                           | C      | trp_mode                 | NCJT               | CJT               | array gain|BLER                | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F39        | CJT phase mismatch                              | C      | phase_error_deg          | 0                  | 45                | coherent loss                  | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F40        | CJT timing mismatch                             | C      | timing_fraction_cp       | 0                  | 0.25              | EVM|BLER                       | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F41        | TRP power imbalance                             | C      | trp_power_delta_db       | 0                  | 10                | combining gain                 | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F42        | TRP CSI ownership                               | C      | csi_owner                | per_trp            | shared_wrong      | PMI|BLER                       | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F43        | TCI activation delay                            | B      | tci_delay_slots          | 0                  | 4                 | beam application loss          | internal_integration        | paired_same_seed_channel_noise_payload |
| F44        | QCL source mismatch                             | B      | qcl_state                | correct            | wrong             | channel estimation|BLER        | internal_integration        | paired_same_seed_channel_noise_payload |
| F45        | P1 beam acquisition                             | B      | beam_selection           | geometry_oracle    | measured_ssb      | selection accuracy             | internal_integration        | paired_same_seed_channel_noise_payload |
| F46        | P2 beam refinement                              | B      | refinement               | disabled           | CSI-RS            | beam gain|overhead             | internal_integration        | paired_same_seed_channel_noise_payload |
| F47        | P3 UL beam selection                            | B      | ul_beam                  | configured         | measured_srs      | UL SINR                        | internal_integration        | paired_same_seed_channel_noise_payload |
| F48        | Beam mobility tracking                          | C      | mobility_kmh             | 3                  | 120               | outage|switch rate             | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F49        | Beam blockage recovery                          | C      | blockage                 | none               | event             | recovery latency               | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F50        | Beam report delay                               | B      | beam_report_delay        | 0                  | 8                 | outage|wrong beam              | internal_integration        | paired_same_seed_channel_noise_payload |
| F51        | Hybrid RF-chain count                           | C      | rf_chains                | 1                  | 4                 | rank|goodput|power             | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F52        | Hybrid phase quantization                       | C      | phase_bits               | 2                  | 6                 | array gain|EVM                 | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F53        | Hybrid beam squint                              | C      | bandwidth_mhz            | 100                | 800               | edge loss|BLER                 | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F54        | Hybrid calibration error                        | C      | calibration_error_deg    | 0                  | 15                | array gain|EVM                 | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F55        | Analog versus digital beam search               | C      | beam_search              | hierarchical       | exhaustive        | training overhead|gain         | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
| F56        | No rank collapse gate                           | A      | rank_gate                | absent             | enabled           | hidden collapse detections     | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F57        | No port collapse gate                           | A      | port_gate                | absent             | enabled           | mapping errors                 | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F58        | Power normalization                             | A      | w_normalization          | column_mutation    | exact_matrix      | power|EVM                      | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F59        | Wrong RNTI/resource identity                    | A      | identity                 | correct            | wrong             | false decode                   | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F60        | No-signal false beam/CSI decision               | A      | signal                   | present            | absent            | false alarm bound              | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F61        | Runtime scaling ports/rank                      | A      | complexity               | 4p_r1              | 32p_r8            | runtime|memory                 | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F62        | Serial versus parallel reproducibility          | A      | execution                | serial             | parallel          | hash equality                  | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F63        | Closed-loop versus open-loop MIMO               | A      | loop                     | open               | closed            | goodput|BLER                   | direct_mimo_phase           | paired_same_seed_channel_noise_payload |
| F64        | End-to-end mobility MU multi-TRP beam loop      | C      | scenario                 | single_user_static | integrated        | goodput|outage|latency         | adjacent_subsystem_required | paired_same_seed_channel_noise_payload |
# 27. Statistical treatment

Implement the following analysis rules:

- Wilson confidence intervals for ordinary BLER, BER and selection accuracy;
- one-sided exact Clopper-Pearson upper bounds for zero-event false-selection or false-decode cases;
- McNemar tests for paired block-success outcomes;
- paired bootstrap intervals for SINR, EVM, goodput, rank, runtime, memory, covariance error and beam-switch latency;
- Holm adjustment within each family of related hypotheses;
- signed effect convention `treatment - baseline`;
- explicit practical margins before calling an effect technically important;
- explicit `incomplete` when minimum trials/error counts or interval criteria are not met;
- explicit `inconclusive` when the confidence interval crosses the predefined equivalence or superiority margin.

No mandatory operating point may disappear from a summary. Do not drop failed or incomplete rows before plotting.

The supplied acceptance rules are mandatory:
| RuleID    | FamilyID   | Severity    | Metric              | Operator                       | Threshold                | RequiredEvidence                                     | Description                                                                      |
|:----------|:-----------|:------------|:--------------------|:-------------------------------|:-------------------------|:-----------------------------------------------------|:---------------------------------------------------------------------------------|
| MRULE-001 | F01        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Type-I single-panel codebook versus compact DFT        |
| MRULE-002 | F02        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Type-I rank breadth 1-8                                |
| MRULE-003 | F03        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Codebook subset restriction                            |
| MRULE-004 | F04        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Panel geometry mismatch                                |
| MRULE-005 | F05        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Polarization and XPR                                   |
| MRULE-006 | F06        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Port mapping permutation                               |
| MRULE-007 | F07        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for RI objective SVD versus goodput                        |
| MRULE-008 | F08        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for PMI objective gain versus post-EQ MI                   |
| MRULE-009 | F09        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Wideband versus subband PMI                            |
| MRULE-010 | F10        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for PRG precoding                                          |
| MRULE-011 | F11        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CSI Part1/Part2 exact versus custom                    |
| MRULE-012 | F12        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CSI report omission priority                           |
| MRULE-013 | F13        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CSI delay                                              |
| MRULE-014 | F14        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CSI measurement noise                                  |
| MRULE-015 | F15        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CSI-IM interference measurement                        |
| MRULE-016 | F16        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CQI calibration                                        |
| MRULE-017 | F17        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for High-rank DL                                           |
| MRULE-018 | F18        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for High-rank UL                                           |
| MRULE-019 | F19        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Two codewords                                          |
| MRULE-020 | F20        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for SRS-derived TPMI authority                             |
| MRULE-021 | F21        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for SRS sounding bandwidth                                 |
| MRULE-022 | F22        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for SRS age                                                |
| MRULE-023 | F23        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Reciprocity calibration                                |
| MRULE-024 | F24        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Covariance sample count                                |
| MRULE-025 | F25        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Covariance age                                         |
| MRULE-026 | F26        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Covariance granularity                                 |
| MRULE-027 | F27        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Covariance shrinkage                                   |
| MRULE-028 | F28        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Receiver MMSE versus IRC                               |
| MRULE-029 | F29        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Strict IRC no fallback                                 |
| MRULE-030 | F30        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for ZF versus MMSE                                         |
| MRULE-031 | F31        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for MU-MIMO 2 UE                                           |
| MRULE-032 | F32        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for MU-MIMO 4 UE                                           |
| MRULE-033 | F33        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for MU angular separation                                  |
| MRULE-034 | F34        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for MU DM-RS collision                                     |
| MRULE-035 | F35        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for MU near-far power                                      |
| MRULE-036 | F36        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for MU scheduler objective                                 |
| MRULE-037 | F37        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for NCJT two-TRP                                           |
| MRULE-038 | F38        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CJT perfect coherence                                  |
| MRULE-039 | F39        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CJT phase mismatch                                     |
| MRULE-040 | F40        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for CJT timing mismatch                                    |
| MRULE-041 | F41        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for TRP power imbalance                                    |
| MRULE-042 | F42        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for TRP CSI ownership                                      |
| MRULE-043 | F43        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for TCI activation delay                                   |
| MRULE-044 | F44        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for QCL source mismatch                                    |
| MRULE-045 | F45        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for P1 beam acquisition                                    |
| MRULE-046 | F46        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for P2 beam refinement                                     |
| MRULE-047 | F47        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for P3 UL beam selection                                   |
| MRULE-048 | F48        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Beam mobility tracking                                 |
| MRULE-049 | F49        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Beam blockage recovery                                 |
| MRULE-050 | F50        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Beam report delay                                      |
| MRULE-051 | F51        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Hybrid RF-chain count                                  |
| MRULE-052 | F52        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Hybrid phase quantization                              |
| MRULE-053 | F53        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Hybrid beam squint                                     |
| MRULE-054 | F54        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Hybrid calibration error                               |
| MRULE-055 | F55        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Analog versus digital beam search                      |
| MRULE-056 | F56        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for No rank collapse gate                                  |
| MRULE-057 | F57        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for No port collapse gate                                  |
| MRULE-058 | F58        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Power normalization                                    |
| MRULE-059 | F59        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Wrong RNTI/resource identity                           |
| MRULE-060 | F60        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for No-signal false beam/CSI decision                      |
| MRULE-061 | F61        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Runtime scaling ports/rank                             |
| MRULE-062 | F62        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Serial versus parallel reproducibility                 |
| MRULE-063 | F63        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for Closed-loop versus open-loop MIMO                      |
| MRULE-064 | F64        | HARD        | technical_invariant | family_specific                | defined_in_prompt        | raw_trials|operating_points|pairwise_effects         | Correctness invariant for End-to-end mobility MU multi-TRP beam loop             |
| MRULE-065 | F01        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Type-I single-panel codebook versus compact DFT |
| MRULE-066 | F02        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Type-I rank breadth 1-8                         |
| MRULE-067 | F03        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Codebook subset restriction                     |
| MRULE-068 | F04        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Panel geometry mismatch                         |
| MRULE-069 | F05        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Polarization and XPR                            |
| MRULE-070 | F06        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Port mapping permutation                        |
| MRULE-071 | F07        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for RI objective SVD versus goodput                 |
| MRULE-072 | F08        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for PMI objective gain versus post-EQ MI            |
| MRULE-073 | F09        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Wideband versus subband PMI                     |
| MRULE-074 | F10        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for PRG precoding                                   |
| MRULE-075 | F11        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for CSI Part1/Part2 exact versus custom             |
| MRULE-076 | F12        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for CSI report omission priority                    |
| MRULE-077 | F13        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for CSI delay                                       |
| MRULE-078 | F14        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for CSI measurement noise                           |
| MRULE-079 | F15        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for CSI-IM interference measurement                 |
| MRULE-080 | F16        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for CQI calibration                                 |
| MRULE-081 | F17        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for High-rank DL                                    |
| MRULE-082 | F18        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for High-rank UL                                    |
| MRULE-083 | F19        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Two codewords                                   |
| MRULE-084 | F20        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for SRS-derived TPMI authority                      |
| MRULE-085 | F21        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for SRS sounding bandwidth                          |
| MRULE-086 | F22        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for SRS age                                         |
| MRULE-087 | F23        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Reciprocity calibration                         |
| MRULE-088 | F24        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Covariance sample count                         |
| MRULE-089 | F25        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Covariance age                                  |
| MRULE-090 | F26        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Covariance granularity                          |
| MRULE-091 | F27        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Covariance shrinkage                            |
| MRULE-092 | F28        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Receiver MMSE versus IRC                        |
| MRULE-093 | F29        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for Strict IRC no fallback                          |
| MRULE-094 | F30        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for ZF versus MMSE                                  |
| MRULE-095 | F31        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for MU-MIMO 2 UE                                    |
| MRULE-096 | F32        | STATISTICAL | primary_effect      | paired_CI_and_practical_margin | defined_before_execution | pairwise_effects|confidence_interval|adjusted_pvalue | Statistical/effect-size rule for MU-MIMO 4 UE                                    |
# 28. Impact artifact contracts

Generate all impact CSVs:
| FileName                             | PrimaryKey                    |   MinRows | RequiredColumns                                                                                                                                                                                                                                       |
|:-------------------------------------|:------------------------------|----------:|:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| mimo_impact_run_manifest.csv         | RunID                         |         1 | RunID|GitCommit|MATLABVersion|ToolboxVersion|SeedList|ExperimentMatrixSHA256|ConfidenceLevel|Status                                                                                                                                                   |
| mimo_impact_raw_trials.csv           | RunID|ExperimentID|TrialIndex |       768 | RunID|ExperimentID|FamilyID|PairID|Variant|FactorName|FactorValue|Seed|TrialIndex|PayloadID|ChannelRealizationID|NoiseRealizationID|Profile|Channel|SNRDB|BlockError|BitErrors|RI|PMI|MeasuredSINRDB|EVMPercent|GoodputMbps|RuntimeMs|MemoryMB|Status |
| mimo_impact_operating_points.csv     | RunID|ExperimentID            |       768 | RunID|ExperimentID|FamilyID|PairID|Variant|Trials|BlockErrors|BitErrors|BLER|BLERCILower|BLERCIUpper|MeanSINRDB|MeanEVMPercent|MeanGoodputMbps|MeanRuntimeMs|MeanMemoryMB|Incomplete|StopReason|Status                                                |
| mimo_impact_pairwise_effects.csv     | RunID|FamilyID|PairID|Metric  |        64 | RunID|FamilyID|PairID|Metric|BaselineValue|TreatmentValue|AbsoluteEffect|RelativeEffect|CILower|CIUpper|PValue|AdjustedPValue|EffectSize|PracticalMargin|Conclusion|Status                                                                            |
| mimo_impact_rule_evaluation.csv      | RunID|RuleID                  |        96 | RunID|RuleID|FamilyID|Severity|Metric|ObservedValue|Threshold|Passed|EvidenceCSV|Status                                                                                                                                                               |
| mimo_impact_codebook_ri_pmi.csv      | RunID|ExperimentID            |        24 | RunID|ExperimentID|CodebookType|Rank|SelectedRI|ExpectedRI|SelectedPMI|ExpectedPMI|PMIAccuracy|FeedbackBits|Objective|Status                                                                                                                          |
| mimo_impact_csi_feedback.csv         | RunID|ExperimentID            |        24 | RunID|ExperimentID|Part1Bits|Part2Bits|OmittedPart2Bits|ReportAgeSlots|CQIError|PMIError|GoodputMbps|Status                                                                                                                                           |
| mimo_impact_high_rank.csv            | RunID|ExperimentID|Layer      |        24 | RunID|ExperimentID|Rank|Layer|MeasuredSINRDB|EVMPercent|BLER|GoodputMbps|RankCollapsed|Status                                                                                                                                                         |
| mimo_impact_covariance_receiver.csv  | RunID|ExperimentID            |        24 | RunID|ExperimentID|Receiver|Samples|AgeSlots|ConditionNumber|MinEigenvalue|ShrinkageFactor|MeasuredSINRDB|BLER|FallbackUsed|Status                                                                                                                    |
| mimo_impact_srs_ul.csv               | RunID|ExperimentID            |        24 | RunID|ExperimentID|SRSAgeSlots|SoundedBandwidthRB|SelectedRI|SelectedTPMI|AppliedTPMI|TPMIAccuracy|MeasuredSINRDB|BLER|Status                                                                                                                         |
| mimo_impact_mu_mimo.csv              | RunID|ExperimentID|UEID       |        16 | RunID|ExperimentID|NumUE|UEID|AngularSeparationDeg|PowerDeltaDB|Receiver|MeasuredSINRDB|BLER|GoodputMbps|Fairness|Status                                                                                                                              |
| mimo_impact_multitrp.csv             | RunID|ExperimentID            |        16 | RunID|ExperimentID|Mode|TimingMismatchFractionCP|PhaseMismatchDeg|PowerDeltaDB|CombinedSINRDB|BLER|CoherentGainDB|Status                                                                                                                              |
| mimo_impact_hybrid.csv               | RunID|ExperimentID            |        16 | RunID|ExperimentID|Nant|NRFChains|NStreams|PhaseBits|BandwidthMHz|SquintLossDB|ArrayGainDB|EVMPercent|BLER|Status                                                                                                                                     |
| mimo_impact_beam_management.csv      | RunID|ExperimentID            |        16 | RunID|ExperimentID|MobilityKMH|Blockage|ReportDelaySlots|BeamSwitches|WrongBeamSlots|OutageProbability|RecoveryLatencySlots|GoodputMbps|Status                                                                                                        |
| mimo_impact_summary.csv              | RunID|FamilyID                |        64 | RunID|FamilyID|ExperimentsExpected|ExperimentsExecuted|PairsExpected|PairsComplete|HardRulesFailed|StatisticalRulesInconclusive|BlockedCount|Status                                                                                                   |
| mimo_impact_image_semantic_audit.csv | RunID|ImageFile               |        30 | RunID|ImageFile|SourceCSV|SourceCSV_SHA256|PNG_SHA256|Width|Height|AxesCount|SeriesCount|FinitePointCount|ActualTitle|ActualXLabel|ActualYLabel|Status                                                                                                |
Generate all impact PNGs:
| ImageFile                          | SourceCSV                           | ExpectedTitleToken        | ExpectedXLabel                | ExpectedYLabel           |   MinAxesCount |   MinSeriesCount |   MinFinitePointCount |   MinWidth |   MinHeight |
|:-----------------------------------|:------------------------------------|:--------------------------|:------------------------------|:-------------------------|---------------:|-----------------:|----------------------:|-----------:|------------:|
| mimo_impact_codebook_accuracy.png  | mimo_impact_codebook_ri_pmi.csv     | Codebook accuracy         | Experiment                    | PMI accuracy             |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_rank_scaling.png       | mimo_impact_high_rank.csv           | Rank scaling              | Rank                          | Goodput [Mbps]           |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_subset_restriction.png | mimo_impact_codebook_ri_pmi.csv     | Subset restriction        | Candidate count               | PMI accuracy             |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_panel_geometry.png     | mimo_impact_codebook_ri_pmi.csv     | Panel geometry            | Geometry case                 | Array gain [dB]          |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_polarization.png       | mimo_impact_high_rank.csv           | Polarization              | XPR [dB]                      | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_ri_objective.png       | mimo_impact_codebook_ri_pmi.csv     | RI objective              | SNR [dB]                      | RI accuracy              |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_pmi_objective.png      | mimo_impact_codebook_ri_pmi.csv     | PMI objective             | SNR [dB]                      | PMI accuracy             |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_wideband_subband.png   | mimo_impact_csi_feedback.csv        | Wideband and subband CSI  | SNR [dB]                      | Goodput [Mbps]           |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_csi_payload.png        | mimo_impact_csi_feedback.csv        | CSI payload               | CSI bits                      | Goodput [Mbps]           |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_csi_age.png            | mimo_impact_csi_feedback.csv        | CSI age                   | Age [slots]                   | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_high_rank_sinr.png     | mimo_impact_high_rank.csv           | High-rank SINR            | Layer                         | SINR [dB]                |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_two_codewords.png      | mimo_impact_high_rank.csv           | Two codewords             | SNR [dB]                      | Goodput [Mbps]           |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_srs_tpmi.png           | mimo_impact_srs_ul.csv              | SRS TPMI                  | SRS SNR [dB]                  | TPMI accuracy            |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_srs_age.png            | mimo_impact_srs_ul.csv              | SRS age                   | Age [slots]                   | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_covariance_samples.png | mimo_impact_covariance_receiver.csv | Covariance samples        | Samples                       | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_covariance_age.png     | mimo_impact_covariance_receiver.csv | Covariance age            | Age [slots]                   | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_irc_mmse.png           | mimo_impact_covariance_receiver.csv | IRC and MMSE              | Interference level [dB]       | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_mu_users.png           | mimo_impact_mu_mimo.csv             | MU-MIMO users             | Number of UEs                 | Sum goodput [Mbps]       |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_mu_separation.png      | mimo_impact_mu_mimo.csv             | MU angular separation     | Separation [deg]              | Goodput [Mbps]           |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_mu_near_far.png        | mimo_impact_mu_mimo.csv             | MU near far               | Power delta [dB]              | Weak UE BLER             |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_ncjt_cjt.png           | mimo_impact_multitrp.csv            | NCJT and CJT              | Mode                          | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_cjt_phase.png          | mimo_impact_multitrp.csv            | CJT phase                 | Phase error [deg]             | Coherent gain [dB]       |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_cjt_timing.png         | mimo_impact_multitrp.csv            | CJT timing                | Timing mismatch [CP fraction] | BLER                     |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_hybrid_rfchains.png    | mimo_impact_hybrid.csv              | Hybrid RF chains          | RF chains                     | Goodput [Mbps]           |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_hybrid_phase_bits.png  | mimo_impact_hybrid.csv              | Hybrid phase quantization | Phase bits                    | Array gain [dB]          |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_hybrid_squint.png      | mimo_impact_hybrid.csv              | Hybrid beam squint        | Bandwidth [MHz]               | Squint loss [dB]         |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_beam_mobility.png      | mimo_impact_beam_management.csv     | Beam mobility             | Speed [km/h]                  | Outage probability       |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_beam_recovery.png      | mimo_impact_beam_management.csv     | Beam recovery             | Blockage case                 | Recovery latency [slots] |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_runtime_scaling.png    | mimo_impact_operating_points.csv    | MIMO runtime scaling      | Ports times rank              | Runtime [ms]             |              1 |                2 |                     8 |        900 |         600 |
| mimo_impact_effect_forest.png      | mimo_impact_pairwise_effects.csv    | MIMO impact effects       | Effect size                   | Family                   |              1 |                2 |                     8 |        900 |         600 |
# 29. Technical acceptance tolerances

Use tighter values when the selected specification/vector requires them. At minimum:

```text
Independent complex coefficient absolute error <= 1e-12 for exact analytic vectors
Array-response complex NMSE <= 1e-12 for deterministic analytic cases
No-channel precoder multiplication NMSE <= 1e-12
Selected matrix digest equals applied matrix digest exactly
Power reconciliation absolute error <= 0.05 dB
Hermitian covariance error <= 1e-12 normalized
Minimum covariance eigenvalue >= -1e-10 times trace scale
No strict IRC without minimum sample count and age compliance
No-noise bit recovery exact for every supported rank/codeword tuple
Configured/selected/applied rank equality in forced-rank cases
No silent port, panel, layer, codeword, PRG, TRP or RF-chain reduction
CSI information-bit mismatch count = 0
CSI decoded-bit mismatch count = 0 in no-noise cases
Wrong configuration/RNTI/resource/epoch false state change count = 0
```

Waveform BLER thresholds must be profile- and campaign-specific and use confidence intervals rather than one hard-coded number across all MCS/rank/channel combinations.
# 30. Required execution commands

Run from the repository root.

```bash
python tests/vectors/mimo/verify_mimo_vector_pack.py tests/vectors/mimo
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*MIMO*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*CSI*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Beam*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*IRC*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.mimo.runMIMOCSIBeamformingPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','mimo'),'OutputDir',fullfile(pwd,'artifacts','mimo_csi_beamforming_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/mimo/verify_mimo_artifacts.py artifacts/mimo_csi_beamforming_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.phy.mimo.runMIMOCSIBeamformingImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','mimo','mimo_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','mimo_csi_beamforming_impact'),'SeedList',[11 23 47 89 131 197],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/mimo/verify_mimo_impact_artifacts.py artifacts/mimo_csi_beamforming_impact
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

Also run any existing PDSCH, PUSCH, PUCCH, PDCCH, CSI-RS and SRS regression suites affected by the migration.
# 31. Artifact inspection requirements

After generation, do not stop at file existence.

For every CSV:

- parse successfully;
- match the contracted schema;
- have unique primary keys;
- contain the minimum row count;
- contain no hidden skipped/blocked mandatory row;
- contain finite required metrics;
- reconcile raw, operating-point and summary totals;
- retain failed and incomplete points explicitly.

For every PNG:

- decode successfully;
- meet minimum dimensions;
- be nonblank;
- contain the expected title and axis-label semantics;
- contain at least the required axes, series and finite data points;
- use the contracted source CSV;
- record source-CSV and PNG SHA-256 values;
- have exactly one semantic-audit row;
- agree with actual dimensions and file size.

Run the supplied verifiers. A nonzero verifier exit code is a phase failure.
# 32. Mandatory negative and fault-injection cases

At minimum inject and detect:

```text
unsupported profile
unsupported panel/port/rank tuple
invalid panel geometry
invalid polarization/XPR configuration
logical-to-physical port collision
invalid codebook type or mode
invalid subset restriction
invalid RI restriction
out-of-range codebook index
wrong matrix orientation
wrong matrix dimensions
matrix mutation after selection
selected/applied digest mismatch
PRG count mismatch
wideband matrix used for subband assignment
missing CSI measurement state
stale CSI measurement
wrong CSI resource identity
wrong interference resource identity
wrong report configuration epoch
wrong CSI Part 1 length
wrong CSI Part 2 length
custom CSI container used
invalid CQI table
configured RI override
configured PMI/TPMI override
SVD rank fallback
identity/SVD/MRT precoder fallback
rank collapse
port collapse
codeword collapse
missing covariance
stale covariance
insufficient covariance samples
non-Hermitian covariance
indefinite covariance
covariance with desired-signal leakage
IRC-to-MMSE silent downgrade
MU-MIMO pilot collision
MU-MIMO wrong UE identity
MU-MIMO unscheduled shared-resource waveform
multi-TRP missing TCI state
CJT phase/timing outside limit
hybrid RF-chain count below layers
hybrid analog matrix violates phase-only constraint
beam report from wrong resource
TCI activation not yet applicable
geometry oracle winning beam
beam-failure timer mismatch
unsupported advanced profile silently mapped to Type-I rank 1/2
```

Every rejected case must produce the expected typed error, no waveform, and no relevant state mutation.
# 33. Codex implementation sequence

Work in dependency order and commit coherent changes.

For every task:

1. add a failing test or vector comparison;
2. modify the real production source;
3. migrate callers;
4. run focused tests;
5. run all previously passing affected tests;
6. generate/update technical artifacts when the task has runtime output;
7. record commands and exact results;
8. do not mark the task done when a mandatory test is unavailable.

Task graph:
| TaskID   |   Wave | Task                          | ExitCriterion                                                                      |
|:---------|-------:|:------------------------------|:-----------------------------------------------------------------------------------|
| MIMO-T01 |      1 | Capability profiles           | Create release/version-pinned supported tuple registry and planning rejection.     |
| MIMO-T02 |      1 | Canonical antenna model       | Implement element/panel/pose/polarization/port/calibration objects.                |
| MIMO-T03 |      1 | Power and matrix contract     | Define Nport-by-Nlayer convention, normalization, PRG scope and immutable digests. |
| MIMO-T04 |      2 | Type-I 2-port floor           | Implement exact table 5.2.2.2.1-1 and independent vectors.                         |
| MIMO-T05 |      2 | Type-I single-panel           | Implement selected 4/8/12/16/24/32-port ranks 1-8 and restrictions.                |
| MIMO-T06 |      3 | Type-I multi-panel            | Implement selected 8/16/32-port panel profiles and ranks.                          |
| MIMO-T07 |      3 | Type-II port selection        | Implement bounded Type-II/port-selection profile with exact indices/coefficients.  |
| MIMO-T08 |      3 | Enhanced Type-II              | Implement one bounded enhanced Type-II profile; fence all others.                  |
| MIMO-T09 |      4 | CSI report schema             | Build typed CSI report configuration and exact field presence/width/order.         |
| MIMO-T10 |      4 | CSI Part1/Part2 serialization | Integrate TS 38.212 UCI sequences for PUCCH/PUSCH.                                 |
| MIMO-T11 |      5 | Measurement state             | Bind CSI-RS/SRS/SSB measurements, interference and ages to reports.                |
| MIMO-T12 |      5 | RI selection                  | Exhaustive rank objective using post-EQ SINR/MI/BLER/goodput.                      |
| MIMO-T13 |      5 | PMI selection                 | Exhaustive wideband/subband/PRG objective with covariance and receiver.            |
| MIMO-T14 |      5 | CQI/LI/CRI                    | Implement report-configuration-aware selection and field validation.               |
| MIMO-T15 |      6 | DL closed loop                | CSI trigger→report→scheduler→DCI→PDSCH W application→receiver evidence.            |
| MIMO-T16 |      6 | UL closed loop                | SRS→RI/SRI/TPMI→scheduler/DCI→PUSCH W application→receiver evidence.               |
| MIMO-T17 |      7 | High-rank DL                  | Execute ranks 1-8, two codewords, ports, DM-RS, HARQ and receiver.                 |
| MIMO-T18 |      7 | High-rank UL                  | Execute declared ranks/codewords, codebook/non-codebook and power.                 |
| MIMO-T19 |      8 | Covariance estimator          | Sample support, per-PRB granularity, shrinkage, PSD, condition and age.            |
| MIMO-T20 |      8 | Strict IRC                    | No downgrade; covariance-qualified IRC and held-out campaigns.                     |
| MIMO-T21 |      9 | MU-MIMO                       | Two/four UE shared-resource scheduling, pilots, power, covariance and decoding.    |
| MIMO-T22 |     10 | NCJT multi-TRP                | Two-TRP noncoherent state, control, channel, combining and feedback.               |
| MIMO-T23 |     10 | CJT multi-TRP                 | Timing/phase/calibration-aware coherent joint transmission.                        |
| MIMO-T24 |     11 | FR2 hybrid beamforming        | Analog/digital codebooks, RF chains, quantization, squint and training.            |
| MIMO-T25 |     12 | Beam-management loop          | P1/P2/P3, report, TCI, application, failure and recovery.                          |
| MIMO-T26 |     13 | Independent oracles           | Codebook/CSI/array/covariance/precoder frozen vectors and math invariants.         |
| MIMO-T27 |     14 | Base phase runner             | Generate all base CSVs/PNGs from actual production execution.                      |
| MIMO-T28 |     15 | Impact runner                 | Execute paired experiments, statistics, rules and all impact artifacts.            |
| MIMO-T29 |     16 | Regression integration        | Run PDSCH/PUSCH/PDCCH/PUCCH/CSI/SRS/channel tests with new APIs.                   |
# 34. Completion restrictions

Do not report `COMPLETE` while any of the following remains in a selected strict path:

```text
compact generic DFT codebook labelled normative Type-I/II
rank-1/rank-2-only fallback for a declared higher-rank tuple
N1/N2/O1/O2 clamp or inferred square panel
Frobenius-only PMI selection
SVD/configured-SNR RI selection
custom fixed CSI container or custom hex payload
transmitted CSI/beam oracle input to the receiver
configured TPMI overriding measured SRS
identity/SVD/MRT matrix fallback
precoder transpose/crop/pad/repeat guess
selected/applied matrix digest mismatch
one wideband matrix substituted for required PRG matrices
rank, port, layer, codeword, TRP or RF-chain collapse
missing or stale measurement accepted
IRC without valid covariance
silent IRC-to-MMSE fallback
MU-MIMO evaluated as independent SU links
CJT without explicit sample-domain phase/timing state
hybrid beamforming with hidden full-digital fallback
beam selection from geometry truth
TCI/beam state recorded but not applied to control/data samples
same-Toolbox result called independent reference
mandatory MATLAB test skipped or blocked
mandatory operating point incomplete
any required CSV or PNG missing
artifact verifier returns nonzero
```

`COMPLETE` requires:

```text
all 16 registered findings closed for every enabled profile
all 65 mandatory MATLAB tests executed and passed
all supported capability rows executed
all unsupported rows rejected before waveform generation
all independent vector mismatches equal zero
all selected/applied rank, port and matrix digests reconcile
all required no-noise and waveform campaigns pass
all 768 impact experiments execute
all 96 acceptance rules have valid evidence
all 44 CSVs pass their contracts
all 50 PNGs pass their contracts
both artifact verifiers return exit code 0
complete repository MATLAB regression passes
```
# 35. Required final Codex response

Return a technical implementation report with exactly these sections:

1. **Status** — `COMPLETE`, `FAIL`, or `BLOCKED`.
2. **Profiles enabled** — exact profile IDs and supported tuples.
3. **Profiles still unsupported** — exact tuples and reasons.
4. **Files changed** — one line per file and purpose.
5. **Legacy shortcuts removed** — map each of the 16 finding IDs to source changes.
6. **Architecture implemented** — canonical production objects and call graph.
7. **Independent references** — files, generator/version and hashes.
8. **Commands executed** — exact commands.
9. **MATLAB/toolbox versions**.
10. **Test results** — pass/fail/skip/block counts for every suite.
11. **Vector results** — row counts and mismatch counts.
12. **Waveform results** — profiles, channels, seeds, operating points and incomplete counts.
13. **Impact results** — 768-experiment and 96-rule status.
14. **CSV artifacts** — filename, rows and SHA-256.
15. **PNG artifacts** — filename, dimensions, source CSV and SHA-256.
16. **Verifier results** — exact exit codes.
17. **Residual technical limitations**.
18. **Git commit(s)**.

Do not report `COMPLETE` based on static source inspection, class creation, synthetic artifact tests, or same-implementation comparisons alone.
# Appendix A — Input and expected-vector inventory
- `expected_antenna_array_response.csv` — 1860 rows; columns: CaseID, N1, N2, Polarization, AzimuthDeg, ElevationDeg, Element, Real, Imag, VectorNorm, Convention, ExpectedStatus
- `expected_csi_bit_ownership_floor.csv` — 192 rows; columns: CaseID, Part, BitIndex, Field, FieldBitIndex, ExpectedOwner, ExpectedStatus
- `expected_mimo_impact_analytical_floor.csv` — 26 rows; columns: FloorID, Family, Input, ExpectedMetric, ExpectedValue, Tolerance
- `expected_mimo_ri_pmi_selection.csv` — 30 rows; columns: CaseID, ExpectedRI, ExpectedPMI, ExpectedPrecoderSHA256, Objective, ExpectedStatus
- `expected_typeI_2port_codebook.csv` — 16 rows; columns: CaseID, Ports, Rank, CodebookIndex, Port, Layer, Real, Imag, MatrixSHA256, FrobeniusPower, ExpectedStatus
- `mimo_beam_state_transition_vectors.csv` — 100 rows; columns: CaseID, FromState, Event, ToState, MeasuredResourceRequired, ExpectedValid, ExpectedError
- `mimo_capability_profile_matrix.csv` — 164 rows; columns: ProfileID, Direction, CodebookType, Ports, Panels, N1, N2, O1, O2, Rank, MaxCodewords, FrequencyGranularity, Supported, RequiredEvidence
- `mimo_covariance_test_vectors.csv` — 90 rows; columns: CaseID, MatrixName, Dimension, Matrix, Samples, AgeSlots, MinSamples, MaxAgeSlots, Hermitian, MinEigenvalue, ConditionNumber, ExpectedValid, ExpectedError
- `mimo_csi_beamforming_16_findings.csv` — 16 rows; columns: ID, Priority, Domain, Classification, RequiredFor, ClosureStatus, Finding, Evidence, WhyItMatters, RequiredFix, AcceptanceTest, 3GPPBaseline, ClaimAfterFix, CodexPhase, Owner, Commit, TestsRun, Notes
- `mimo_csi_report_schema_test_vectors.csv` — 41 rows; columns: CaseID, CodebookType, Ports, Rank, ReportQuantity, NumCSIResources, FrequencyGranularity, Part1Fields, Part2Fields, Part1Bits, Part2Bits, SeparateEncoding, ExpectedValid, ExpectedError
- `mimo_declared_coverage_matrix.csv` — 87 rows; columns: CaseID, Profile, Direction, Channel, Rank, Ports, Codebook, Receiver, CSIGranularity, HARQ, Mandatory, RequiredResult, SNRdB
- `mimo_error_contract.csv` — 51 rows; columns: ErrorIdentifier, Meaning, StrictAction
- `mimo_hybrid_beamforming_test_vectors.csv` — 108 rows; columns: CaseID, Nant, NRFChains, NStreams, PhaseQuantizationBits, ConstantModulus, Subcarriers, CenterFrequencyGHz, BandwidthMHz, ExpectedValid, ExpectedError, RequiredMetrics
- `mimo_impact_acceptance_rules.csv` — 96 rows; columns: RuleID, FamilyID, Severity, Metric, Operator, Threshold, RequiredEvidence, Description
- `mimo_impact_analysis_families.csv` — 64 rows; columns: FamilyID, Title, Wave, FactorName, BaselineValue, TreatmentValue, PrimaryMetrics, Implementability, RequiredDesign
- `mimo_impact_dependency_waves.csv` — 64 rows; columns: FamilyID, Wave, ImplementNow, BlockingDependency
- `mimo_impact_experiment_matrix.csv` — 768 rows; columns: ExperimentID, FamilyID, PairID, Variant, FactorName, FactorValue, BaselineFactorValue, Seed, PayloadID, ChannelRealizationID, NoiseRealizationID, Profile, Channel, SNR_dB, TrialsTarget, MinimumErrors, ConfidenceLevel, ExpectedStatus
- `mimo_impact_implementability_summary.csv` — 3 rows; columns: Wave, FamilyCount, ExperimentCount, Meaning
- `mimo_impact_pairing_contract.csv` — 64 rows; columns: FamilyID, PairKey, OnlyAllowedDifference, RequiredStatistics, IncompletePolicy
- `mimo_implementation_task_graph.csv` — 29 rows; columns: TaskID, Wave, Task, ExitCriterion
- `mimo_matlab_test_plan.csv` — 65 rows; columns: TestName, Scope, Mandatory, RequiredResult
- `mimo_mu_mimo_test_vectors.csv` — 48 rows; columns: CaseID, NumUE, SharedPRBSet, SharedSymbols, AngularSeparationDeg, DMRSDesign, PowerDeltaDB, Receiver, ExpectedValid, ExpectedError, RequiredEvidence
- `mimo_multitrp_test_vectors.csv` — 64 rows; columns: CaseID, Mode, NumTRP, TimingMismatchFractionCP, PhaseMismatchDeg, PowerImbalanceDB, TCIStateTRP1, TCIStateTRP2, ExpectedValid, ExpectedError, ExpectedBehavior
- `mimo_negative_test_vectors.csv` — 38 rows; columns: CaseID, FaultType, ExpectedError, WaveformGenerated, StateChanged, GrantCreated, ExpectedStatus
- `mimo_port_mapping_test_vectors.csv` — 22 rows; columns: CaseID, LogicalPorts, PhysicalElements, DualPolarized, XPRdB, MappingBijective, ExpectedValid, ExpectedError
- `mimo_precoder_application_test_vectors.csv` — 31 rows; columns: CaseID, NPorts, Rank, NSymbols, Matrix, MatrixSHA256, InputPowerPerLayer, ExpectedTotalPortPower, ExpectedMatrixFroPower, ExpectedOrientation, ExpectedStatus, ExpectedError
- `mimo_ri_pmi_metric_test_vectors.csv` — 180 rows; columns: CaseID, ChannelName, SNRdB, Covariance, Rank, PMI, Metric, MetricValue, RawMI, CandidateMatrixSHA256
- `mimo_source_change_map.csv` — 25 rows; columns: Component, FileOrAction, RequiredChange
- `mimo_srs_authority_test_vectors.csv` — 72 rows; columns: CaseID, UEID, SRSResourceID, SNRdB, AgeSlots, ChannelClass, ExpectedRI, ExpectedSRI, ExpectedTPMI, DecisionAuthoritative, ExpectedValid, ExpectedError
