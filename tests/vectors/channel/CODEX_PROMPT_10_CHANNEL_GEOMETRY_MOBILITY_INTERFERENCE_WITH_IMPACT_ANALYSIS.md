# CODEX IMPLEMENTATION PROMPT 10 — CHANNEL, GEOMETRY, MOBILITY AND INTERFERENCE

## Mission

You are the lead MATLAB 5G/6G link-level channel implementation engineer for this repository. This task is **not a review**, **not a documentation-only exercise**, and **not a truth-contract exercise**. Modify the live simulator and execute the corrected channel chain.

Close all 24 `CH-*` findings for the selected bounded profiles. Implement the physical and statistical behavior in production MATLAB. Unsupported combinations must fail during planning before waveform generation; they must never silently fall back to a generic channel, identity matrix, configured geometry, scalar SINR, default array, default LOS rule, default mobility model, or normalized path gain.

Implement and prove this causal chain:

```text
Pinned scenario/profile and coordinate frame
    ↓
explicit sites, sectors, cloned topology, UE drops and trajectories
    ↓
immutable per-link geometry state at absolute time
    ↓
exact pathloss, LOS/O2I/atmosphere and correlated LSP state
    ↓
exact array pose, element pattern, polarization and port projection
    ↓
TDL/CDL cluster, ray, delay, angle, Doppler and phase state
    ↓
absolute path gain and sample-domain channel application
    ↓
per-link timing/frequency/resource/power-causal waveform interference
    ↓
receiver-derived channel, SINR, covariance and mobility measurements
    ↓
decoded measurement/control events for reselection, handover and RLF
    ↓
runtime channel-state trace and statistical acceptance
```

## Repository inputs

Place this pack under `tests/vectors/channel/`. Treat these files as immutable test definitions and bounded independent analytical floors:

- `channel_geometry_mobility_interference_24_findings.csv`
- `channel_capability_profile_matrix.csv`
- `channel_declared_coverage_matrix.csv`
- `channel_geometry_implementation_task_graph.csv`
- `channel_geometry_matlab_test_plan.csv`
- `independent_vector_manifest.json`
- every `channel_*_test_vectors.csv`
- every `expected_*.csv`
- every `desired_channel*_contract.csv`
- the three Python verifiers.

Do not copy an expected CSV into a production artifact folder. Production artifacts must be serialized from the corrected MATLAB runtime objects and actual simulation results.

Rows marked `SPEC_LOOKUP_REQUIRED`, `BLOCKED_UNTIL_VECTOR_ADDED`, or `FROZEN_*_REQUIRED` are intentionally not exact oracles. Before enabling the corresponding profile, add an exact pure-spec implementation or a frozen independent vector with source/version/hash provenance. A same-MATLAB-Toolbox comparison is self-consistency, not independent conformance.

## Pinned technical baseline

Pin exact versions in code and outputs:

```text
3GPP TR 38.901 V19.2.0, Release 19
TS 38.211 / 38.214 / 38.215 / 38.331 versions selected by the scenario profile
TS 38.133 where mobility measurement performance is claimed
TS 38.104 and TS 38.101 only for explicitly selected RF/base-station/UE reference points
ITU-R P.676 version only when the optional atmosphere profile is enabled
MATLAB and 5G Toolbox release
```

The bounded strict channel profiles are:

```text
nr_r18_fr1_uma_strict
nr_r18_fr1_umi_strict
nr_r18_fr1_rma_strict
nr_r18_fr1_inh_strict
nr_r18_fr1_inf_strict, only after exact InF vectors pass
nr_r18_fr2_strict
rel19_7_24_study_strict
hst_study_strict
raytracing_reproducible_study
```

Do not use the informal term `FR3` as the model identity. For 7.125–24.25 GHz, record the actual Release-19 TR 38.901 profile, equation/table, frequency, scenario and calibration dataset.

## Non-negotiable implementation rules

1. Edit production MATLAB source and migrate all live callers. Do not return a plan-only response.
2. Create one canonical channel/geometry runtime; do not create a second unused implementation.
3. No strict path may clamp, crop, pad, retry, default, substitute, downgrade or silently change an invalid scenario/channel/array request.
4. No configured, reconstructed or expected value may be labelled runtime-observed.
5. No validation comparison may compare two values derived from the same configured/model source.
6. Missing observed geometry, channel, power, Doppler, pathloss, LOS or interference state must fail the strict run.
7. Every random process must use an injected named random stream keyed by run, scenario, link, state family and seed. Global `rand` or `randn` is forbidden in strict code.
8. LOS, O2I, shadowing, LSPs, clusters and blockage must evolve with position/time according to the selected state process; they cannot be redrawn independently per slot.
9. TDL must not be advertised as full geometry-based MIMO unless the exact declared spatial-correlation profile is used and proven. CDL must carry exact arrays, poses, element patterns, polarization and per-ray angles.
10. Path-gain normalization may be used only in explicitly named normalized calibration profiles. Absolute-power profiles must preserve the complete dBm/watt/PSD ledger.
11. Multicell interference must be composed from per-link samples with timing, CFO, resources, power and channel state. A scalar power sum is diagnostic only.
12. Serving-cell changes, handover and RLF must be caused by decoded measurement/control state, not by instantaneously selecting the largest simulator-truth RSRP.
13. Ray tracing must fail closed unless scene, coordinate frame, materials, solver, version, mesh, transmitter/receiver pose and result hashes are present.
14. A missing MATLAB runtime, blocked test, skipped mandatory test, incomplete statistical point, absent CSV/PNG or nonzero verifier exit code means the phase is not complete.

## The 24 findings to implement

| ID | Priority | Current technical defect | Required production correction | Mandatory acceptance |
|---|---:|---|---|---|
| **CH-001** | P1 | MathWorks TDL/CDL and nrPathLoss provide a useful baseline, but the declared channel capability matrix is broader than the independently validated runtime evidence. | Publish a channel capability matrix by scenario, model, delay profile, K-factor, arrays, Doppler, spatial consistency, O2I, blockage, frequency, and power convention; run calibrated campaigns for each declared row. | Every declared channel row has deterministic parameter evidence plus statistical calibration tests against the pinned reference tables/distributions. |
| **CH-002** | P0 | Missing runtime speed, distance, delay, LOS, Doppler and pathloss fields are reconstructed from configuration/model values inside the audit path. | Keep Observed*, DerivedFromObserved*, Configured*, and ReconstructedDiagnostic* fields separate; never overwrite observed values; strict gates require observed runtime values with per-field provenance. | Deleting each observed field causes the strict geometry gate to fail while diagnostic reconstruction remains visibly non-qualifying. |
| **CH-003** | P0 | Reconstructed geometry values can be labelled runtime_slot_trace/runtime_trace_complete and then compared against values derived from the same configuration. | Compute completeness only from observed runtime fields; maintain provenance at column/cell level; prohibit self-comparison in reconciliation gates. | A provenance graph detects common-source comparisons; tests that previously expected backfill now require strict failure. |
| **CH-004** | P1 | Mini geometry builders use simplified LOS rules such as exp(-d/500) or distance thresholds instead of the selected scenario model. | Remove mini LOS proxies from strict profiles; use the pinned TR 38.901 scenario LOS function and preserve one random LOS draw per spatially consistent drop. | LOS probability Monte Carlo matches reference curves within confidence bounds for every declared scenario. |
| **CH-005** | P1 | InF LOS probability uses exp(-d/50), explicitly an approximate proxy. | Implement the exact selected Release-19/38.901 InF model and scenario parameters, or keep InF study-only and block strict status. | Distance-sweep values and Monte Carlo LOS rates match pinned reference tables/curves. |
| **CH-006** | P1 | Unknown scenarios fall back to a generic exp(-d/100) LOS probability. | Reject unknown scenario names in strict mode; allow a generic research model only under an explicit custom_channel profile. | Misspelled/unsupported scenarios fail before geometry generation and cannot be auto-classified. |
| **CH-007** | P1 | Spatial non-stationarity uses random masks or deterministic aperture/bearing proxies without runtime cluster-angle state. | Implement cluster birth/death/visibility regions tied to actual per-path angles, delays, powers, UE movement and array sub-regions, or label the feature research-only. | Trajectory tests show continuous cluster evolution and reproducible visibility from actual channel state, not independent masks. |
| **CH-008** | P1 | Oxygen absorption is a simplified Gaussian engineering approximation around 60 GHz rather than a validated gaseous-attenuation implementation. | Use a validated ITU-R P.676 implementation with atmosphere inputs and frequency-dependent line-by-line/model outputs; version and test it independently. | Reference atmosphere/frequency points match authoritative values within tolerance; strict mode requires environment parameters. |
| **CH-009** | P1 | TDL geometry coupling uses reduced correlation matrices and does not carry full runtime array pose, element pattern, polarization and per-path angles. | Either bound TDL to a correlation-matrix profile with exact stated assumptions, or implement full array-response coupling using per-path angle state. | Declared TDL profile reproduces target correlation and power/delay statistics; no claim of full geometry coupling unless per-path evidence exists. |
| **CH-010** | P1 | CDL can consume array objects, but logical-port projection, normalization, polarization and time evolution are not broadly validated. | Audit port-to-element mapping, array normalization, per-path angles/powers/delays, polarization matrices and Doppler; export applied realization metadata. | Small deterministic CDL setups match analytical array responses and statistical reference distributions. |
| **CH-011** | P1 | Antenna element patterns, polarization, orientation, downtilt, sector pose and XPR are not one canonical object shared by geometry, pathloss, CDL and MIMO. | Create immutable antenna-array descriptors and a single coordinate-transform service; use them in path gain, channel coefficients, beamforming and reports. | Rotation/polarization tests match analytical patterns and conserve power across logical-port projection. |
| **CH-012** | P1 | Wraparound is a rectangular minimum-image approximation rather than full cloned-site/sector interference geometry for hexagonal deployments. | Implement topology-consistent wraparound with cloned interfering sites/sectors and minimum 3D path per serving/interfering link; validate edge UE symmetry. | Center and edge translations yield invariant SINR distributions and correct interferer identities. |
| **CH-013** | P2 | Hotspot, density-map, clustered, street-canyon and other spatial UE distributions are not fully supported or calibrated. | Implement explicit drop models with normalized PDFs, exclusion zones, indoor fractions, sector association and reproducible sampling. | Goodness-of-fit tests match target spatial distributions and association statistics. |
| **CH-014** | P2 | Indoor grid placement and spacing use convenience heuristics and can shrink geometry rather than preserve a declared layout. | Require explicit building/floor/room/corridor geometry or a versioned canonical layout; reject impossible spacing instead of shrinking silently. | Geometry audit proves requested dimensions and distances are preserved exactly. |
| **CH-015** | P1 | Sector radius, area dimensions and some site layouts are heuristic rather than derived from a pinned evaluation scenario. | Define scenario templates with explicit ISD, site/sector layout, antenna heights/azimuths/downtilts and area; prohibit radius inference in strict mode. | Generated geometry matches the canonical template and area/ISD identities exactly. |
| **CH-016** | P1 | Large-scale parameter spatial consistency, cross-correlation, temporal evolution and inter-link correlation lack complete calibration evidence. | Implement/pin correlation matrices, decorrelation distances, random-field generation, update intervals and cross-link rules; export realized LSPs. | Monte Carlo spatial/temporal correlations and marginal distributions match pinned targets within confidence bounds. |
| **CH-017** | P1 | Current O2I code claims strict low/high-loss modes, but independent value, material-state and spatial-consistency validation is incomplete. | Pin exact release formulas/parameters, building/material selection, low/high-loss mixture, indoor distance and spatial state; add independent reference sweeps. | Frequency/distance/material test points and Monte Carlo mixture statistics match the pinned model. |
| **CH-018** | P2 | Dynamic blockage, human/body loss, vehicle penetration, material-specific loss and time-correlated obstruction are not a complete bounded profile. | Separate each model into a versioned profile with geometry/state, temporal correlation and calibrated loss distributions. | Deterministic blockage trajectories and statistical distributions match declared references. |
| **CH-019** | P0 | The end-to-end path-gain, channel normalization, antenna gain, transmit power, noise PSD/NF and receiver scaling chain is not comprehensively proven in absolute units. | Define one reference point and unit convention; remove hidden normalizations; export every gain/loss; reconcile analytical received power with waveform RMS at each stage. | AWGN, FSPL and CDL calibration cases close an absolute-power budget within a tight declared tolerance. |
| **CH-020** | P1 | Interference topology, timing, frequency, waveform overlap, power and channel realization are not fully coupled for every interfering link. | Represent each interferer as an actual waveform/resource/power/channel path with identity and timing; prohibit SINR-only injected interference in waveform-strict runs. | Per-interferer power sums reconcile with received samples and disabling one link removes exactly its contribution. |
| **CH-021** | P2 | Broad spatially consistent mobility, cell reselection/handover, radio-link failure and interruption procedures are incomplete. | Implement trajectory/velocity/orientation state, channel updates, measurements/filtering/events, handover control and bearer continuity as a bounded system profile. | Canonical trajectories trigger expected measured events and handovers with no teleporting or state reset. |
| **CH-022** | P1 | The simulator labels 7.125-24.25 GHz as “FR3” research but does not pin the Release-19 38.901 enhancements and corrections for that range. | Create a rel19_7to24ghz_channel profile pinned to the exact 38.901 version, supported scenarios and parameters; keep “FR3” as an informal study label, not a normative range. | Reference sweeps across frequency/scenario match the pinned Release-19 model and manifest includes exact version. |
| **CH-023** | P2 | Optional ray tracing lacks a versioned scene/material/solver/calibration contract and can undermine reproducibility. | Pin scene assets, coordinate system, material database, solver/version/settings, path export format and stochastic augmentation; hash all inputs. | Same scene/toolchain reproduces identical paths; cross-check canonical scenes against analytical free-space/reflection cases. |
| **CH-024** | P1 | High-speed Doppler, radial velocity, direction changes, channel update cadence and spatial consistency are not independently validated for HST-style trajectories. | Compute Doppler from observed 3D velocity/path directions per path, preserve sign, update coefficients at adequate cadence, and validate against analytical tones/trajectories. | Known single-path trajectories yield correct signed Doppler and phase evolution; multi-path HST campaign meets correlation targets. |

## Existing source to refactor and preserve

- `+sixgr/+analytics/buildPhase7ReadinessArtifacts.m` — Delete all configuration/model backfill from strict runtime rows. Consume immutable ChannelStateTrace fields only; keep diagnostic reconstruction in a separate non-qualifying table. Issues: CH-002;CH-003.
- `tests/testGeometryScenarioAudit.m` — Invert the expectation: missing observed runtime fields must fail strict validation while diagnostics remain available. Issues: CH-002;CH-003.
- `+sixgr/+channel/buildScenarioGeometry.m` — Replace with ScenarioTemplateRegistry plus immutable SiteSectorTopology and GeometryStateFactory; no exponential LOS or fixed threshold. Issues: CH-004;CH-015.
- `+sixgr/+channel/LOSProbability.m` — Implement exact pinned TR 38.901 table equations per supported scenario and reject unknown scenarios. Add correlated LOSStateProcess for motion. Issues: CH-004;CH-005;CH-006;CH-016.
- `+sixgr/+channel/O2ILoss.m` — Implement Release-19 material coefficients and exact selected low/high/low-A models with UT-specific indoor distance and seeded spatially consistent state. Issues: CH-017;CH-022.
- `+sixgr/+channel/OxygenAbsorption.m` — Replace with exact TR 38.901 oxygen-absorption table/interpolation and optional versioned P.676 atmosphere profile. Apply cluster-delay-dependent loss. Issues: CH-008.
- `+sixgr/+channel/SpatialNonStationarity.m` — Create cluster/ray visibility regions and birth/death state driven by runtime angles, array aperture, motion and scenario profile. Issues: CH-007;CH-016.
- `+sixgr/+channel/ChannelFactory.m` — Consume canonical antenna/pose/polarization objects; remove spacing/shape/polarization defaults, profile substitution and reduced TDL full-geometry claims. Emit selected/applied profile digests. Issues: CH-001;CH-009;CH-010;CH-011.
- `+sixgr/+channel/TR38901Plus.m` — Replace with PathlossEngine38901, LSPRandomFieldEngine and exact V19.2.0 profile registry. Unknown or unpinned scenario/frequency tuples fail planning. Issues: CH-001;CH-016;CH-022.
- `+sixgr/+system/GeometryEngine.m` — Preserve as façade but migrate to immutable GeometryStateFactory with no hidden defaults and exact coordinate/velocity/phase integration. Issues: CH-002;CH-024.
- `+sixgr/+scenario/wraparoundDistance.m` — Replace strict hex profiles with explicit cloned site/sector topology and per-clone antenna orientation/channel state. Retain rectangular torus only as named synthetic profile. Issues: CH-012.
- `+sixgr/+scenario/dropUEs.m` — Add scenario-pinned UE drop engines for UMa/UMi/RMa/InH/InF/SMa, hotspots, streets, indoor floors, density maps and reproducible exclusion zones. Issues: CH-013;CH-014;CH-015.
- `+sixgr/+scenario/+mobility/updatePositions.m` — Reject unknown mobility models. Use immutable trajectory state and exact boundary/route behavior; no silent RandomWaypoint fallback. Issues: CH-021;CH-024.
- `+sixgr/+scenario/+mobility/MobilityRandomWaypoint.m` — Inject a named deterministic stream and export waypoint/segment state. Couple every position update to channel coefficient phase evolution. Issues: CH-021;CH-024.
- `+sixgr/+channel/RayTracingAdapter.m` — Require immutable scene/material/solver/version/mesh/coordinate contract and fail closed. Export ray sets and hashes. Issues: CH-023.
- `+sixgr/+link/applyRuntimeFadingChannel.m` — Consume exact ChannelStateTrace, preserve absolute path gain, and record sample-domain input/output power plus normalization ledger. Issues: CH-019;CH-024.
- `+sixgr/+link/addControlledAWGN.m` — Use kTB/noise-figure/implementation-loss/FFT/occupied-bandwidth reference points with exact complex-sample variance and no hidden SNR fallback. Issues: CH-019.
- `+sixgr/+link/synthesizeInterferenceWaveform.m` — Make it the sole strict interference composer; require per-link timing/frequency/resource/power/channel identity and emit a contribution ledger plus covariance. Issues: CH-020.
- `+sixgr/+truth/exportLLSLiveMobilityTables.m` — Remove instantaneous-power serving-cell authority and scalar interference approximation. Consume decoded measurement/handover events and receiver-derived per-link waveform metrics. Issues: CH-020;CH-021.
- `+sixgr/+truth/buildChannelImpulseResponseTable.m` — Extend to exact per-link/per-path delay, gain, angle, Doppler, polarization, cluster state and phase trace generated by the live runtime. Issues: CH-001;CH-009;CH-010;CH-016;CH-024.

Preserve useful foundations when correct: `nrTDLChannel`, `nrCDLChannel`, the sample-domain interference composer, the canonical geometry engine, channel-impulse-response export, channel reproducibility tests and measured interference-covariance estimation. Fix their inputs, ownership, state, normalization and coverage rather than replacing functioning kernels without evidence.

## Canonical MATLAB architecture

Create or consolidate:

```text
+sixgr/+channel/+runtime/
    ChannelSpecificationProfile.m
    ChannelCapabilityProfile.m
    ChannelPlanningResult.m
    ScenarioTemplateRegistry.m

    CoordinateFrame.m
    CoordinateTransformService.m
    SiteSectorTopology.m
    ClonedTopology.m
    UEPlacementProfile.m
    UEPlacementEngine.m

    AntennaElementPattern.m
    AntennaPanelGeometry.m
    AntennaArrayGeometry.m
    AntennaPose.m
    PolarizationBasis.m
    LogicalPortProjection.m
    ArrayResponseEngine.m

    GeometryStateID.m
    ImmutableGeometryState.m
    GeometryStateFactory.m
    MobilityTrajectoryState.m
    MobilityTrajectoryEngine.m

    ChannelStateTrace.m
    ChannelStateTraceWriter.m
    ChannelFieldProvenance.m
    ProvenanceGraph.m

    PathlossProfile38901.m
    PathlossEngine38901.m
    LOSProbabilityEngine38901.m
    LOSStateProcess.m

    O2IProfile38901.m
    O2IState.m
    O2IEngine38901.m
    OxygenAbsorptionProfile38901.m
    OxygenAbsorptionEngine38901.m
    AtmosphereProfileP676.m

    LSPProfile38901.m
    LSPCrossCorrelationEngine.m
    LSPRandomFieldEngine.m
    SpatialConsistencyState.m
    InterLinkCorrelationState.m

    SSPClusterState.m
    SSPRayState.m
    ClusterBirthDeathEngine.m
    SpatialNonStationarityEngine.m
    NearFieldChannelState.m

    TDLProfileAdapter.m
    TDLSpatialCorrelationProfile.m
    CDLProfileAdapter.m
    CDLArrayCouplingEngine.m
    PolarizationCouplingEngine.m

    DopplerPhaseEngine.m
    ChannelCoefficientUpdateEngine.m

    BlockageProfile.m
    BlockageStateMachine.m
    MaterialLossProfile.m
    VehiclePenetrationState.m

    AbsolutePowerLedger.m
    NoisePowerLedger.m
    OFDMScalingLedger.m

    InterferingLinkState.m
    MultiLinkInterferenceGraph.m
    WaveformInterferenceComposer.m
    ReceiverContributionLedger.m
    InterferenceCovarianceState.m

    MobilityMeasurementBridge.m
    HandoverChannelContinuityState.m
    RLFChannelContinuityState.m

    RayTracingSceneContract.m
    StrictRayTracingAdapter.m

    ChannelArtifactExporter.m
    runChannelGeometryPhaseValidation.m
    runChannelGeometryImpactAnalysis.m

    +oracle/
        GeometryKinematicsSpec.m
        PathlossSpec38901.m
        LOSProbabilitySpec38901.m
        O2ISpec38901.m
        OxygenAbsorptionSpec38901.m
        ArrayResponseSpec.m
        SpatialCorrelationSpec.m
        DopplerPhaseSpec.m
        AbsolutePowerSpec.m
        InterferenceSuperpositionSpec.m
```

Existing public APIs may remain as compatibility façades only. They must delegate to the canonical runtime and must not retain hidden defaults or alternative state.

# Part I — capability planning and immutable runtime state

## 1. Capability planning

Load `channel_capability_profile_matrix.csv`. Before allocating any waveform, call:

```matlab
plan = sixgr.channel.runtime.ChannelCapabilityProfile.resolve(request);
```

The result is exactly `EXECUTE` or `REJECT`. The request key includes:

```text
profile ID and exact spec version
scenario and LOS condition
frequency range
BS/UE heights and applicability range
pathloss/LOS/O2I/LSP profile
TDL/CDL profile and delay spread
array, pose, polarization and port projection
mobility/trajectory/update cadence
blockage/vehicle/near-field/SNS state
interference topology
absolute versus normalized power profile
ray-tracing contract, when applicable
```

An unsupported tuple produces `CHANNEL:UnsupportedProfile` and no random-state consumption, waveform, channel state, scheduler state or output artifact except the rejection record.

## 2. Immutable geometry state

At every channel update create one immutable state per directed link:

```text
GeometryStateID
absolute frame/slot/symbol/sample time
coordinate-frame ID
Tx/Rx site, sector, clone, UE and antenna IDs
Tx/Rx position
Tx/Rx velocity and acceleration
Tx/Rx orientation
2D and 3D displacement
2D and 3D distance
unit direction vector
azimuth/elevation in GCS and LCS
range rate
propagation delay
signed Doppler
integrated phase
scenario/indoor/floor/zone state
configuration epoch
```

Use:

```text
d = rRx − rTx
d3D = ||d||
u = d / d3D
vrel = vRx − vTx
rangeRate = vrel · u
fD = −(fc / c) × rangeRate
delay = d3D / c
phase(t + Δt) = phase(t) + 2π fD(t) Δt
```

The sign convention is: positive Doppler means approaching. Test approaching, receding, tangential and changing-direction trajectories.

The runtime may derive delay and Doppler **from the observed runtime position/velocity state**. It may not derive them from scenario configuration in the audit/export path.

## 3. Per-field provenance

Each emitted field carries:

```text
FieldName
Value
ProvenanceClass =
    OBSERVED_RUNTIME_STATE
    DERIVED_FROM_OBSERVED_RUNTIME_STATE
    DECODED_RECEIVER_STATE
    CONFIGURED
    RECONSTRUCTED_DIAGNOSTIC
SourceIDs
ComputationID
ProducerTime
AvailableTime
```

Strict consumers accept only the allowed first three classes. Diagnostic reconstruction is written to a separate table and never changes strict completeness.

Create a provenance DAG. Reject a comparison when expected and actual values share the same configured/reconstructed root. Add mutation tests that delete each observed field and prove that strict validation fails.

# Part II — topology, drops, pathloss and large-scale state

## 4. Scenario topology and UE placement

Implement pinned scenario templates for selected UMa, UMi Street Canyon, RMa, InH Office, InF and SMa profiles. A template owns:

```text
site layout and inter-site distance
sector count, orientation, downtilt and antenna height
streets/buildings/floors/rooms
UE-height and indoor/outdoor distributions
minimum BS/UE and UE/UE distances
hotspots/density maps
wraparound clone set
mobility routes
```

Use explicit 19-site/3-sector clones for the selected hex profile. Each clone has a distinct site/sector/link identity and its own antenna orientation and channel state. A rectangular torus may remain only as `synthetic_rectangular_torus`.

Implement deterministic seeded drop engines:

```text
uniform polygon/sector
hotspot Gaussian mixture
street canyon
indoor floor/room
RMa annulus/ring
scenario density map
```

Do not generate in a rectangle and clip. Test spatial CDFs, region occupancy, minimum distances, hotspot mean/covariance, floor counts and reproducibility.

## 5. Exact pathloss profiles

Implement a versioned profile registry from TR 38.901 V19.2.0. Every profile exposes:

```text
scenario/condition
equation/table ID
frequency/distance/height applicability
breakpoint/environment-height procedure
shadow-fading standard deviation
required environmental parameters
```

For the bounded analytical vectors, implement exact UMa, UMi Street Canyon, RMa and InH Office equations. Use d3D in the equation and d2D for breakpoint/condition selection as specified by the profile.

Never:

```text
use one generic log-distance equation
replace an unknown scenario with UMa/UMi
continue outside applicability without an explicit extrapolation-study profile
replace configured CDL/LOS condition from a local heuristic
```

All deterministic pathloss vectors must match to numerical precision before random shadowing is added.

## 6. Exact LOS probability and correlated LOS state

Implement scenario-specific LOS probability tables/equations. For the bounded UMa floor:

```text
Pbase =
    min(18/d2D, 1) × (1 − exp(−d2D/63))
    + exp(−d2D/63)

C'(hUT) =
    0, hUT ≤ 13 m
    ((hUT − 13)/10)^1.5, 13 m < hUT ≤ 23 m

PLOS =
    Pbase × [1 + C'(hUT) × 5/4 × (d2D/100)^3 × exp(−d2D/150)]
```

Clamp probability only to the mathematical `[0,1]` range after evaluating the exact formula; do not clamp input distance/height into applicability.

A probability is not a per-slot iid state. Implement a seeded spatially consistent `LOSStateProcess` whose marginal matches PLOS and whose transitions are continuous along the trajectory. Export probability, state, transition cause, age and random-field ID.

Unknown scenarios produce `CHANNEL:UnknownLOSScenario`. Remove all `exp(-d/500)`, threshold, `exp(-d/50)` and `exp(-d/100)` strict fallbacks.

## 7. Shadow fading and LSPs

Implement the exact selected distributions and cross-correlation matrices for:

```text
SF, DS, ASD, ASA, ZSD, ZSA, K factor
```

Generate correlated Gaussian random fields in the correct transformed domain using one deterministic state per scenario/link region. The implementation must:

```text
validate the target covariance matrix
generate a PSD factorization
preserve marginal mean/std
preserve cross-correlation
preserve spatial autocorrelation versus separation
preserve temporal continuity along mobility
support configured inter-link correlation where declared
```

A bounded analytical autocorrelation floor is:

```text
rho(Δd) = exp(−Δd / dCorr)
```

Exact scenario-specific correlation distances and cross-correlation matrices must come from the pinned profile, not from this generic floor.

Statistical acceptance uses multiple independent seeds and enough samples to estimate:

```text
mean/std and confidence intervals
5/50/95-percentiles
KS or Anderson-Darling goodness of fit
sample cross-correlation with Fisher-z intervals
spatial autocorrelation RMSE
temporal increment distribution
inter-link correlation
```

Do not pass only because one realization “looks plausible.”

## 8. O2I penetration

Implement UT-specific O2I state. For V19.2 material floors, use `f` in GHz:

```text
standard glass = 2 + 0.2 f dB
IRR glass      = 25.4 + 0.11 f dB
concrete       = 5 + 4 f dB
plywood        = 1.03 + 0.17 f dB
wood           = 4.85 + 0.12 f dB
```

For a material mixture:

```text
PLtw = 5 − 10 log10(Σ_i p_i × 10^(−L_i/10))
PLin = 0.5 × d2D-in
PLO2I = PLtw + PLin + Xsigma
```

Use exact selected low-loss, high-loss and low-loss-A mixtures and sigma. Generate `d2D-in` according to the scenario profile and keep it UT-specific and spatially stable. Use a named random stream for `Xsigma`. Export material state, indoor distance, random state and total loss separately.

## 9. Oxygen absorption

Replace the Gaussian helper. Implement the TR 38.901 table and linear interpolation:

```text
0–52 GHz: 0 dB/km
53:1, 54:2.2, 55:4, 56:6.6, 57:9.7, 58:12.6,
59:14.6, 60:15, 61:14.6, 62:14.3, 63:10.5,
64:6.8, 65:3.9, 66:1.9, 67:1, 68–100:0 dB/km
```

Apply the selected cluster-delay-dependent absorption procedure, not only a common distance loss. If a full atmosphere profile is enabled, pin ITU-R P.676 version, pressure, temperature and humidity and compare it independently. Never mix the table profile and P.676 profile without recording which one generated each value.

# Part III — arrays, TDL/CDL and time evolution

## 10. Canonical antenna, pose and polarization

One object must be shared by geometry, pathloss/sector gain, TDL/CDL, MIMO and beamforming. It contains:

```text
element coordinates in local frame
panel dimensions and panel offsets
element pattern and slant
mechanical/electrical orientation
GCS↔LCS rotation
dual-polar basis and XPR state
logical antenna ports
physical elements
frequency-dependent calibration
```

For element `m`:

```text
a_m(u,f,t) =
    F_m,pol(u_local,f)
    × calibration_m(f,t)
    × exp(j 2π r_m · u_local / lambda)
```

Do not infer panel dimensions with `sqrt(N)`, default to 0.5 lambda spacing, flatten a requested panel, or default polarization to ±45 degrees in strict mode. Validate array orientation and polarization using pure-math vectors and power conservation.

The logical-port projection matrix must have explicit dimensions and normalization. Export selected and applied digests; no transpose/crop/pad/identity fallback is allowed.

## 11. TDL profiles

Use `nrTDLChannel` only behind a strict adapter that resolves exact selected profile, delay spread, Doppler, sample rate, path-gain normalization, antenna counts and declared spatial-correlation profile.

Two distinct TDL profiles are allowed:

```text
normalized_link_calibration
absolute_power_runtime
```

Do not mix their results.

If a bounded Toeplitz port-correlation matrix is selected, record that it is an explicit analytical correlation profile, not a full geometry-based array model. Validate:

```text
tap delays and average powers
delay-spread scaling
path-gain normalization or absolute gain
temporal autocorrelation
Doppler PSD support and maximum Doppler
spatial-correlation matrix and PSD
seed reproducibility
```

## 12. CDL profiles

Build the CDL channel from:

```text
exact CDL-A/B/C/D/E profile
exact delay spread and K factor
Tx/Rx array and pose
element pattern and polarization
logical-port projection
runtime angles/rays
mobility and Doppler phase state
normalization/power profile
```

Do not replace the requested profile with CDL-C based on a local LOS heuristic. Do not flatten arrays. Do not hide normalization.

For each enabled tuple, add an independent/frozen profile vector and statistical tests for:

```text
cluster delays and powers
AOA/AOD/ZOA/ZOD distributions and spreads
XPR and polarization coupling
per-port correlation
K factor
impulse response
temporal correlation and Doppler
array rotation
time evolution
```

A successful call to `nrCDLChannel` is not sufficient evidence.

## 13. Spatial non-stationarity, near field and cluster birth/death

Remove random masks and aperture/bearing proxies from strict profiles. A cluster/ray state contains visibility region, birth/death time, per-array visibility, angles, delay, power, Doppler and phase.

State transitions must be driven by actual trajectory, array aperture and selected model. Test:

```text
cluster-count distribution
visibility duration
birth/death rate
power continuity at transitions
array-region continuity
reproducibility
```

Near-field spherical-wave behavior is a separate capability. If not implemented for a tuple, fail planning rather than applying far-field steering and labelling it near field.

# Part IV — mobility, power and interference

## 14. Mobility and Doppler

Every mobility model uses a named stream and exports immutable route/segment state. Unknown models fail; do not silently choose RandomWaypoint.

Integrate the channel state at an explicit cadence. Between geometry updates, phase evolution must remain continuous. Test:

```text
constant approach/recede/tangential motion
acceleration
turns and lane/route transitions
cell-boundary crossing
100–500 km/h HST-style trajectories
different channel update intervals
serial and parallel execution
```

For an isotropic bounded Doppler validation, compare temporal autocorrelation with the selected theoretical target such as `J0(2π fmax Δt)` where applicable. For directional CDL rays, compare each ray’s signed Doppler and phase directly.

## 15. Dynamic blockage, materials and vehicles

Implement only bounded profiles with exact equations/datasets. Each blocker/material/vehicle state has geometry, material, transition state, correlation time, frequency dependency and loss.

Do not replace dynamic blockage with a scalar “extra loss” sampled per slot. Test blockage onset/recovery continuity, body orientation, vehicle entry/exit, material differences, near-far behavior and multi-seed distributions.

Unsupported blockage variants return `CHANNEL:UnsupportedBlockageProfile`.

## 16. Absolute-power and noise ledger

Define named reference points:

```text
MAC/PHY requested power
per-layer symbols
post-precoder antenna-port power
post-OFDM sample power
antenna connector EIRP
post-pathloss/O2I/oxygen received power
post-fading received sample power
noise PSD and noise figure
post-receiver/equalizer power
```

Core scalar reconciliation:

```text
Prx_dBm =
    Ptx_dBm + Gtx_dBi + Grx_dBi
    − PL_dB − SF_dB − O2I_dB − Oxygen_dB − ImplementationLoss_dB

Noise_dBm =
    −174 dBm/Hz + 10 log10(B_Hz) + NF_dB
```

Use exact complex-sample variance after OFDM scaling. Enforce Parseval checks around modulation, precoding, OFDM and channel application. The production tolerance for analytical versus measured waveform power is at most 0.05 dB unless a stricter profile is configured.

No configured SNR may replace this chain in an absolute-power scenario.

## 17. Sample-domain multicell interference

Create one `InterferingLinkState` per desired/interfering transmission:

```text
Tx/Rx/link identity
absolute sample range
carrier/BWP/numerology
resource ownership
waveform samples
timing offset
frequency offset and phase noise
Tx power and antenna gain
channel state/impulse response
received contribution samples
```

The composer applies each link independently and sums received samples:

```text
y[n] = Σ_l y_l[n] + w[n]
```

Export a sample contribution ledger and verify:

```text
composite sample equals contribution sum
composite power reconciles
resource-overlap rules are exact
timing/CFO effects are applied
near-far powers are preserved
measured covariance equals sample covariance
no hidden iid noise/channel redraw per link
```

A wideband scalar `signal / sum(interference)` calculation may be exported as diagnostic metadata but cannot replace the actual waveform.

## 18. Mobility, reselection, handover and RLF coupling

Channel geometry produces measurements; it does not directly select the serving cell. The chain is:

```text
runtime channel
→ received SSB/CSI-RS/data
→ TS 38.215/receiver measurements
→ filtering and configured event
→ decoded report/control event
→ serving-cell/handover/RLF state
```

Preserve channel-state continuity across preparation/execution where the profile requires it. Export interruption, packet loss, beam/cell state and old/new link states. Test ping-pong, delayed report, measurement gap, HOF, RLF and recovery cases.

# Part V — Rel-19 mid-band and ray tracing

## 19. Release-19 7–24 GHz profile

Do not route 7.125–24.25 GHz through a generic “FR3” branch. Create `rel19_7_24_study_strict` and pin every enabled feature to V19.2 table/equation and a scenario-specific dataset:

```text
pathloss and LOS
O2I materials updated in Release 19
LSP statistics/correlation
array and polarization behavior
CDL/TDL profile
oxygen/atmosphere
blockage where enabled
```

Every output row carries the exact equation/table ID. Unsupported scenario/frequency combinations fail planning.

## 20. Reproducible ray tracing

A ray-tracing contract contains:

```text
scene ID and SHA-256
mesh/unit/coordinate frame
material database and SHA-256
solver and version
reflection/diffraction/scattering settings
transmitter/receiver arrays and poses
random seed, if any
ray/result SHA-256
calibration dataset
```

Remove catch-and-default behavior. If the contract fails, the scenario fails. Test repeated serial/parallel runs, coordinate transforms, material perturbation, solver-version mismatch and result-hash mismatch.

# Part VI — independent tests, statistical acceptance and impact analysis

## 21. Deterministic vector execution

Run `verify_channel_vector_pack.py`. Then implement MATLAB tests that load every vector file and compare the production objects.

Deterministic tolerances:

```text
geometry/delay/pathloss/LOS/O2I/oxygen formulas: ≤ 1e-9 where pure math
array coefficient magnitude/phase: ≤ 1e-10
Doppler: ≤ 1e-6 Hz for analytical vectors
integrated phase: ≤ 1e-5 rad
absolute sample-domain power: ≤ 0.05 dB
interference superposition: ≤ 1e-10 complex-sample NMSE
```

Exact table/profile vectors override these generic tolerances.

## 22. Statistical channel tests

For every enabled scenario/channel profile, run enough independent drops/seeds to estimate:

```text
pathloss residual and shadow-fading distribution
LOS probability in distance bins
O2I distribution
DS/ASD/ASA/ZSD/ZSA/K marginals
LSP cross-correlation
spatial autocorrelation
inter-link correlation
cluster/ray delay and angle statistics
Doppler PSD and temporal autocorrelation
TDL/CDL port correlation
blockage duration/loss
handover/interruption behavior
```

Use:

```text
Wilson intervals for proportions
exact Clopper–Pearson upper bounds for zero events
KS/Anderson–Darling for declared continuous distributions
Fisher-z intervals for correlations
paired bootstrap intervals for treatment effects
McNemar for paired binary outcomes
Holm correction for related hypothesis families
```

Do not turn low statistical power into PASS. Use `INCOMPLETE` or `INCONCLUSIVE`.

## 23. Impact matrix

Execute all 768 rows from `channel_impact_experiment_matrix.csv`. Preserve baseline/treatment pairing:

```text
same seed
same initial geometry
same payload and scheduling
same base random field
same noise realization
only declared factor changes
```

Evaluate all 96 rules. A performance improvement cannot compensate for an incorrect formula, wrong state identity, discontinuous phase, normalized power, missing interferer or circular evidence.

Wave A is direct channel implementation. Wave B requires multicell/mobility-control integration. Wave C requires reproducible ray tracing/HST/end-to-end dependencies. Temporary `BLOCKED_DEPENDENCY` is allowed while implementing, but final `COMPLETE` requires every mandatory dependency and experiment to execute.

## 24. Required MATLAB tests

- `testChannelCapabilityPlanning` — ChannelCapabilityPlanning.
- `testCoordinateFrameTransforms` — CoordinateFrameTransforms.
- `testImmutableGeometryState` — ImmutableGeometryState.
- `testRuntimeChannelStateTrace` — RuntimeChannelStateTrace.
- `testChannelFieldProvenance` — ChannelFieldProvenance.
- `testNoGeometryBackfill` — NoGeometryBackfill.
- `testCircularComparisonGuard` — CircularComparisonGuard.
- `testUMaScenarioTemplate` — UMaScenarioTemplate.
- `testUMiScenarioTemplate` — UMiScenarioTemplate.
- `testRMaScenarioTemplate` — RMaScenarioTemplate.
- `testInHScenarioTemplate` — InHScenarioTemplate.
- `testInFScenarioTemplate` — InFScenarioTemplate.
- `testSMaScenarioTemplate` — SMaScenarioTemplate.
- `testHexClonedTopology` — HexClonedTopology.
- `testRectangularSyntheticTopology` — RectangularSyntheticTopology.
- `testUEUniformDrop` — UEUniformDrop.
- `testUEHotspotDrop` — UEHotspotDrop.
- `testUEStreetCanyonDrop` — UEStreetCanyonDrop.
- `testUEIndoorFloorDrop` — UEIndoorFloorDrop.
- `testDropReproducibility` — DropReproducibility.
- `testPathlossUMa` — PathlossUMa.
- `testPathlossUMi` — PathlossUMi.
- `testPathlossRMa` — PathlossRMa.
- `testPathlossInH` — PathlossInH.
- `testPathlossInF` — PathlossInF.
- `testPathlossApplicability` — PathlossApplicability.
- `testLOSProbabilityUMa` — LOSProbabilityUMa.
- `testLOSProbabilityUMi` — LOSProbabilityUMi.
- `testLOSProbabilityRMa` — LOSProbabilityRMa.
- `testLOSProbabilityInH` — LOSProbabilityInH.
- `testLOSProbabilityInF` — LOSProbabilityInF.
- `testLOSStateSpatialConsistency` — LOSStateSpatialConsistency.
- `testO2IMaterialLoss` — O2IMaterialLoss.
- `testO2ILowHighLowA` — O2ILowHighLowA.
- `testO2IIndoorDistance` — O2IIndoorDistance.
- `testO2ISpatialConsistency` — O2ISpatialConsistency.
- `testOxygenAbsorptionTable` — OxygenAbsorptionTable.
- `testOxygenClusterDelayLoss` — OxygenClusterDelayLoss.
- `testLSPMarginals` — LSPMarginals.
- `testLSPCrossCorrelation` — LSPCrossCorrelation.
- `testLSPSpatialAutocorrelation` — LSPSpatialAutocorrelation.
- `testLSPTemporalContinuity` — LSPTemporalContinuity.
- `testInterLinkCorrelation` — InterLinkCorrelation.
- `testArrayCoordinateTransforms` — ArrayCoordinateTransforms.
- `testElementPattern` — ElementPattern.
- `testPolarizationCoupling` — PolarizationCoupling.
- `testLogicalPortProjection` — LogicalPortProjection.
- `testTDLDelayPowerProfiles` — TDLDelayPowerProfiles.
- `testTDLSpatialCorrelation` — TDLSpatialCorrelation.
- `testTDLDopplerSpectrum` — TDLDopplerSpectrum.
- `testCDLDelayAngleProfiles` — CDLDelayAngleProfiles.
- `testCDLArrayCoupling` — CDLArrayCoupling.
- `testCDLPolarization` — CDLPolarization.
- `testCDLTimeEvolution` — CDLTimeEvolution.
- `testClusterBirthDeath` — ClusterBirthDeath.
- `testSpatialNonStationarity` — SpatialNonStationarity.
- `testNearFieldProfile` — NearFieldProfile.
- `testBlockageStateMachine` — BlockageStateMachine.
- `testMaterialLossProfile` — MaterialLossProfile.
- `testVehiclePenetrationProfile` — VehiclePenetrationProfile.
- `testMobilityTraceReplay` — MobilityTraceReplay.
- `testRandomWaypointSeeded` — RandomWaypointSeeded.
- `testHighSpeedTrajectory` — HighSpeedTrajectory.
- `testSignedDoppler` — SignedDoppler.
- `testDopplerPhaseContinuity` — DopplerPhaseContinuity.
- `testDirectionChangeContinuity` — DirectionChangeContinuity.
- `testChannelUpdateCadence` — ChannelUpdateCadence.
- `testAbsolutePowerAWGN` — AbsolutePowerAWGN.
- `testAbsolutePowerFSPL` — AbsolutePowerFSPL.
- `testAbsolutePowerTDL` — AbsolutePowerTDL.
- `testAbsolutePowerCDL` — AbsolutePowerCDL.
- `testNoisePSDAndNF` — NoisePSDAndNF.
- `testOFDMScalingLedger` — OFDMScalingLedger.
- `testInterferenceSuperposition` — InterferenceSuperposition.
- `testInterferenceTimingOffset` — InterferenceTimingOffset.
- `testInterferenceFrequencyOffset` — InterferenceFrequencyOffset.
- `testInterferenceResourceOverlap` — InterferenceResourceOverlap.
- `testInterferenceCovariance` — InterferenceCovariance.
- `testNearFarInterference` — NearFarInterference.
- `testTwoCellWaveformInterference` — TwoCellWaveformInterference.
- `testHandoverMeasurementCoupling` — HandoverMeasurementCoupling.
- `testRLFContinuity` — RLFContinuity.
- `testRel19MidBandProfiles` — Rel19MidBandProfiles.
- `testRayTracingSceneContract` — RayTracingSceneContract.
- `testRayTracingReproducibility` — RayTracingReproducibility.
- `testChannelArtifactGeneration` — ChannelArtifactGeneration.
- `testChannelImpactAnalysis` — ChannelImpactAnalysis.
- `testCompleteChannelRegression` — CompleteChannelRegression.

Add boundary, negative, no-signal, no-motion, zero-interference, single-link, multi-link, wrong-profile, stale-state and reproducibility cases to every relevant suite.

# Required production artifacts

## Base phase: 32 CSVs

- `channel_profile_resolution.csv`
- `channel_geometry_state.csv`
- `channel_geometry_provenance.csv`
- `channel_topology_sites_sectors.csv`
- `channel_ue_drops.csv`
- `channel_wraparound_links.csv`
- `channel_pathloss_trials.csv`
- `channel_los_state.csv`
- `channel_o2i_trials.csv`
- `channel_oxygen_absorption.csv`
- `channel_lsp_samples.csv`
- `channel_lsp_statistics.csv`
- `channel_ssp_clusters.csv`
- `channel_tdl_profile.csv`
- `channel_tdl_spatial_correlation.csv`
- `channel_cdl_profile.csv`
- `channel_array_geometry.csv`
- `channel_polarization_port_projection.csv`
- `channel_mobility_trace.csv`
- `channel_doppler_phase.csv`
- `channel_blockage_material.csv`
- `channel_absolute_power_ledger.csv`
- `channel_noise_ledger.csv`
- `channel_interference_contributions.csv`
- `channel_interference_covariance.csv`
- `channel_handover_continuity.csv`
- `channel_rel19_midband_profiles.csv`
- `channel_raytracing_contract.csv`
- `channel_independent_vector_results.csv`
- `channel_negative_tests.csv`
- `channel_test_summary.csv`
- `channel_image_semantic_audit.csv`

## Base phase: 22 PNGs

- `channel_geometry_trajectory_3d.png` from `channel_geometry_state.csv`
- `channel_topology_clone_map.png` from `channel_topology_sites_sectors.csv`
- `channel_ue_drop_distribution.png` from `channel_ue_drops.csv`
- `channel_pathloss_curves.png` from `channel_pathloss_trials.csv`
- `channel_los_probability_state.png` from `channel_los_state.csv`
- `channel_o2i_material_loss.png` from `channel_o2i_trials.csv`
- `channel_oxygen_absorption.png` from `channel_oxygen_absorption.csv`
- `channel_lsp_marginals.png` from `channel_lsp_statistics.csv`
- `channel_lsp_spatial_correlation.png` from `channel_lsp_statistics.csv`
- `channel_cluster_delay_angle_map.png` from `channel_ssp_clusters.csv`
- `channel_tdl_impulse_response.png` from `channel_tdl_profile.csv`
- `channel_tdl_spatial_correlation.png` from `channel_tdl_spatial_correlation.csv`
- `channel_cdl_delay_angle_spectrum.png` from `channel_cdl_profile.csv`
- `channel_array_polarization_geometry.png` from `channel_array_geometry.csv`
- `channel_mobility_doppler_timeline.png` from `channel_doppler_phase.csv`
- `channel_blockage_material_timeline.png` from `channel_blockage_material.csv`
- `channel_absolute_power_reconciliation.png` from `channel_absolute_power_ledger.csv`
- `channel_interference_contribution_map.png` from `channel_interference_contributions.csv`
- `channel_interference_covariance.png` from `channel_interference_covariance.csv`
- `channel_handover_continuity.png` from `channel_handover_continuity.csv`
- `channel_rel19_midband_validation.png` from `channel_rel19_midband_profiles.csv`
- `channel_raytracing_reproducibility.png` from `channel_raytracing_contract.csv`

## Impact phase: 16 CSVs

- `channel_impact_run_manifest.csv`
- `channel_impact_raw_trials.csv`
- `channel_impact_operating_points.csv`
- `channel_impact_pairwise_effects.csv`
- `channel_impact_rule_evaluation.csv`
- `channel_impact_geometry.csv`
- `channel_impact_large_scale.csv`
- `channel_impact_tdl_cdl.csv`
- `channel_impact_arrays_polarization.csv`
- `channel_impact_mobility_doppler.csv`
- `channel_impact_interference.csv`
- `channel_impact_power.csv`
- `channel_impact_rel19_raytracing.csv`
- `channel_impact_runtime.csv`
- `channel_impact_summary.csv`
- `channel_impact_image_semantic_audit.csv`

## Impact phase: 30 PNGs

- `channel_impact_observed_provenance.png` from `channel_impact_geometry.csv`
- `channel_impact_coordinate_frame.png` from `channel_impact_geometry.csv`
- `channel_impact_topology_wraparound.png` from `channel_impact_geometry.csv`
- `channel_impact_ue_drop_statistics.png` from `channel_impact_geometry.csv`
- `channel_impact_pathloss.png` from `channel_impact_large_scale.csv`
- `channel_impact_los_probability.png` from `channel_impact_large_scale.csv`
- `channel_impact_o2i.png` from `channel_impact_large_scale.csv`
- `channel_impact_oxygen.png` from `channel_impact_large_scale.csv`
- `channel_impact_lsp_marginals.png` from `channel_impact_large_scale.csv`
- `channel_impact_lsp_cross_correlation.png` from `channel_impact_large_scale.csv`
- `channel_impact_lsp_spatial_consistency.png` from `channel_impact_large_scale.csv`
- `channel_impact_tdl_profile.png` from `channel_impact_tdl_cdl.csv`
- `channel_impact_tdl_spatial_correlation.png` from `channel_impact_tdl_cdl.csv`
- `channel_impact_tdl_doppler.png` from `channel_impact_tdl_cdl.csv`
- `channel_impact_cdl_statistics.png` from `channel_impact_tdl_cdl.csv`
- `channel_impact_cdl_polarization.png` from `channel_impact_arrays_polarization.csv`
- `channel_impact_array_pose.png` from `channel_impact_arrays_polarization.csv`
- `channel_impact_port_projection.png` from `channel_impact_arrays_polarization.csv`
- `channel_impact_spatial_nonstationarity.png` from `channel_impact_arrays_polarization.csv`
- `channel_impact_blockage.png` from `channel_impact_large_scale.csv`
- `channel_impact_doppler_sign_phase.png` from `channel_impact_mobility_doppler.csv`
- `channel_impact_hst.png` from `channel_impact_mobility_doppler.csv`
- `channel_impact_update_cadence.png` from `channel_impact_mobility_doppler.csv`
- `channel_impact_absolute_power.png` from `channel_impact_power.csv`
- `channel_impact_noise_scaling.png` from `channel_impact_power.csv`
- `channel_impact_interference_superposition.png` from `channel_impact_interference.csv`
- `channel_impact_interference_covariance.png` from `channel_impact_interference.csv`
- `channel_impact_multicell_handover.png` from `channel_impact_interference.csv`
- `channel_impact_rel19_midband.png` from `channel_impact_rel19_raytracing.csv`
- `channel_impact_effect_forest.png` from `channel_impact_pairwise_effects.csv`

Every PNG must be regenerated from its source CSV. `channel_image_semantic_audit.csv` and `channel_impact_image_semantic_audit.csv` must record:

```text
image filename
source CSV filename and SHA-256
PNG SHA-256
actual width/height
actual title and axis labels
axes count
series count
finite plotted points
status
```

Do not create placeholder or blank figures.

# Mandatory execution commands

Run from a clean repository root:

```bash
python tests/vectors/channel/verify_channel_vector_pack.py tests/vectors/channel
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Channel*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Geometry*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Mobility*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Interference*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*TDL*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*CDL*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.channel.runtime.runChannelGeometryPhaseValidation( ...
    'VectorRoot',fullfile(pwd,'tests','vectors','channel'), ...
    'OutputDir',fullfile(pwd,'artifacts','channel_geometry_phase'), ...
    'SeedList',[11 23 47 89], ...
    'ConfidenceLevel',0.95, ...
    'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/channel/verify_channel_artifacts.py artifacts/channel_geometry_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.channel.runtime.runChannelGeometryImpactAnalysis( ...
    'ExperimentMatrix',fullfile(pwd,'tests','vectors','channel','channel_impact_experiment_matrix.csv'), ...
    'OutputDir',fullfile(pwd,'artifacts','channel_geometry_impact'), ...
    'SeedList',[11 23 47 89 131 197], ...
    'ConfidenceLevel',0.95, ...
    'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/channel/verify_channel_impact_artifacts.py artifacts/channel_geometry_impact
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

# Work order

Execute in dependency order:

```text
1. capability profiles and coordinate frames
2. immutable geometry state and runtime trace
3. remove audit backfill and circular comparisons
4. scenario topology, clones and UE drops
5. pathloss, LOS, O2I and oxygen
6. LSP/SSP spatial consistency
7. antenna/pose/polarization and port projection
8. TDL adapter
9. CDL adapter
10. mobility, Doppler and phase
11. absolute power/noise
12. sample-domain interference
13. mobility/handover/RLF coupling
14. Rel-19 mid-band profile
15. blockage/HST/ray-tracing study profiles
16. base artifacts
17. 768 impact experiments
18. complete repository regression
```

For every step:

```text
add a failing reproduction test
modify production source
migrate all callers
run local and prior-phase tests
export exact runtime artifacts
record commands/results
do not close the step if a mandatory test is skipped or blocked
```

# Codex response contract

At the end of each Codex response report:

```text
implemented task IDs and CH issue IDs
production files changed
removed fallbacks/defaults
new canonical classes/functions
exact spec/table/equation profiles enabled
tests added
exact commands run
MATLAB/Toolbox versions
pass/fail/skip/block counts
statistical sample sizes and confidence results
CSV row counts and hashes
PNG dimensions and hashes
remaining SPEC_LOOKUP_REQUIRED tuples
remaining blocked dependencies
final status: COMPLETE / FAIL / BLOCKED
```

# Typed errors

- `CHANNEL:UnsupportedProfile` — Requested scenario/frequency/model tuple is not enabled by the capability profile.
- `CHANNEL:MissingObservedGeometry` — A strict consumer requested a geometry field not emitted by the runtime.
- `CHANNEL:InvalidProvenance` — A runtime field is configured, reconstructed or self-derived where observed evidence is required.
- `CHANNEL:CircularComparison` — Both sides of a validation comparison share the same non-observed source.
- `CHANNEL:InvalidCoordinateFrame` — A position, velocity, pose or ray uses an unknown/inconsistent coordinate frame.
- `CHANNEL:InvalidTopology` — Site/sector/clone topology is incomplete, duplicated or geometrically inconsistent.
- `CHANNEL:InvalidDropDistribution` — A UE drop violates the pinned scenario distribution or exclusion rules.
- `CHANNEL:UnknownLOSScenario` — No pinned LOS-probability equation exists for the requested scenario.
- `CHANNEL:InvalidLOSStateTransition` — LOS/NLOS state changes without the configured correlated process.
- `CHANNEL:PathlossOutOfRange` — Pathloss equation was requested outside its supported distance/height/frequency range.
- `CHANNEL:MissingLSPProfile` — No exact LSP distribution/cross-correlation profile matches the request.
- `CHANNEL:InvalidLSPCovariance` — The configured LSP cross-correlation matrix is not finite, symmetric or positive semidefinite.
- `CHANNEL:SpatialConsistencyViolation` — LSP/SSP evolution is discontinuous beyond the declared tolerance.
- `CHANNEL:MissingO2IMaterialProfile` — No exact material mixture exists for the requested O2I profile.
- `CHANNEL:InvalidIndoorDistance` — The UT-specific indoor distance is missing or outside the profile range.
- `CHANNEL:MissingOxygenProfile` — No exact oxygen/atmosphere profile matches the request.
- `CHANNEL:InvalidTDLProfile` — The TDL profile, delay spread or spatial-correlation tuple is unsupported.
- `CHANNEL:InvalidCDLProfile` — The CDL profile, delay spread, K-factor or array tuple is unsupported.
- `CHANNEL:InvalidAntennaArray` — Array geometry, element pattern, pose, polarization or logical-port projection is invalid.
- `CHANNEL:PortProjectionMismatch` — Logical-to-physical port projection is dimensionally or energetically inconsistent.
- `CHANNEL:InvalidDopplerState` — Doppler sign, phase or update cadence is inconsistent with runtime geometry.
- `CHANNEL:MissingAbsolutePowerReference` — The path gain/noise/antenna/OFDM reference points are incomplete.
- `CHANNEL:PowerLedgerMismatch` — Analytical and measured sample-domain power differ beyond tolerance.
- `CHANNEL:InterferenceLinkMissing` — An overlapping interferer lacks waveform, timing, channel or power state.
- `CHANNEL:InterferenceLedgerMismatch` — The composed waveform does not equal the sum of recorded contributions.
- `CHANNEL:CovarianceMismatch` — Measured interference covariance is inconsistent with the contribution ledger.
- `CHANNEL:UnknownMobilityModel` — An unrecognized mobility model was requested.
- `CHANNEL:InvalidMobilityTrajectory` — Trajectory position, velocity, acceleration or direction continuity is invalid.
- `CHANNEL:MissingHandoverMeasurement` — A handover/reselection/RLF state change lacks a decoded measurement/control event.
- `CHANNEL:UnsupportedBlockageProfile` — The requested blockage/material/vehicle model is not implemented.
- `CHANNEL:RayTracingContractMissing` — Scene, materials, solver, version, mesh or coordinate transform is absent.
- `CHANNEL:RayTracingHashMismatch` — The ray-tracing scene or result digest differs from the declared contract.
- `CHANNEL:StrictFallbackForbidden` — A strict path attempted to default, clamp, retry, substitute or downgrade.

# Completion restrictions

Do not report `COMPLETE` while any of these remains:

```text
configured/model geometry backfilled as runtime evidence
runtime rows labelled from reconstructed values
circular expected-versus-applied comparisons
generic exponential LOS fallback
independent per-slot LOS/LSP/O2I redraw
Gaussian oxygen approximation
old O2I material coefficients in the selected Rel-19 profile
global rand/randn in strict channel state
reduced TDL correlation presented as full array geometry
CDL array flattening, sqrt-panel inference or default polarization
configured CDL profile substitution
hidden path-gain normalization in an absolute-power profile
rectangular/minimum-image shortcut presented as explicit hex wraparound
UE rectangle drop plus clipping
unknown mobility falling back to RandomWaypoint
configured speed used instead of observed trajectory velocity
unsigned Doppler or discontinuous phase
scalar interference replacing waveform contributions
instantaneous max-RSRP serving-cell authority
ray-tracing catch-and-default behavior
an enabled SPEC_LOOKUP_REQUIRED tuple
same-Toolbox output labelled independent
mandatory statistical point incomplete
mandatory MATLAB test skipped or blocked
any required CSV or PNG absent
either artifact verifier returning nonzero
complete repository regression failing
```

# Definition of done

The phase is complete only when:

```text
all 24 CH findings are closed for enabled profiles
all 88 mandatory MATLAB tests execute and pass
all capability rows produce their exact EXECUTE/REJECT result
every enabled deterministic tuple has an independent oracle
runtime geometry/provenance contains no configured or reconstructed substitute
all pathloss/LOS/O2I/oxygen vectors pass
all enabled LSP/TDL/CDL statistical gates pass
all array/polarization/port-projection tests pass
signed Doppler and phase continuity pass through HST-style cases
absolute-power and noise ledgers reconcile within tolerance
sample-domain multicell interference and covariance reconcile
mobility/handover/RLF continuity passes
Rel-19 7–24 GHz rows are pinned to exact V19.2 profiles
ray-tracing contracts reproduce where enabled
all 768 impact experiments execute
all 96 acceptance rules have valid evidence
all 48 CSVs pass
all 52 PNGs pass
both Python artifact verifiers exit 0
the complete MATLAB repository regression passes
```
