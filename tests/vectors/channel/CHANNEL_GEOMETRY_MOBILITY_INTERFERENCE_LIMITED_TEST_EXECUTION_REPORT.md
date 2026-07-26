# Channel, Geometry, Mobility and Interference — Limited Execution Report

## Scope

This report accompanies `CODEX_PROMPT_10_CHANNEL_GEOMETRY_MOBILITY_INTERFERENCE_WITH_IMPACT_ANALYSIS.md`. It is an implementation pack for the production MATLAB channel chain. It does not claim that the current simulator already passes the phase.

## Pack result

```text
Implementation findings:            24
Source static checks:               64
Targeted defect signatures found:   42
Unmatched regression guards:        10
Useful foundations found:           11
Independent vector files:           38
Independent/vector rows:            64,532
Impact families:                    64
Impact experiments:                 768
Matched pairs:                      384
Acceptance rules:                   96
Required base CSVs/PNGs:            32 / 22
Required impact CSVs/PNGs:          16 / 30
Required total artifacts:           100
```

## Current source result

The current uploaded simulator is **not complete for this phase**. Static inspection found 42 live source signatures associated with the 24 findings. The highest-risk confirmed paths are:

1. `buildPhase7ReadinessArtifacts.m` reconstructs speed-related and channel-related fields and can label rows as runtime trace evidence.
2. `buildScenarioGeometry.m` and `LOSProbability.m` contain threshold/exponential LOS proxies.
3. `OxygenAbsorption.m` uses a Gaussian engineering approximation instead of the selected table/profile.
4. `O2ILoss.m` contains old material coefficients, global RNG fallback and fixed indoor-distance/loss assumptions.
5. `ChannelFactory.m` contains reduced TDL correlation and CDL array/spacing/polarization/profile defaults or substitutions.
6. `wraparoundDistance.m` uses rectangular/minimum-image behavior instead of explicit cloned-sector links.
7. `dropUEs.m` uses convenience uniform/rectangle placement.
8. `TR38901Plus.m` is approximate and does not pin the full Release-19 7.125–24.25 GHz profile.
9. mobility dispatch can fall back to RandomWaypoint, and RandomWaypoint can use global RNG.
10. ray tracing can catch an error and use a default propagation model.
11. the mobility export path can select the serving cell from instantaneous scalar received power.
12. absolute power and sample-domain interference are not yet proven over every link and receiver reference point.

The static audit is in `current_channel_geometry_static_audit.csv`.

## Independent vector result

`verify_channel_vector_pack.py` completed:

```text
Checks:  139
Passed:  139
Failed:    0
```

The manifest protects 38 files and 64,532 rows. The pack includes bounded independent analytical floors for:

- geometry, distance, propagation delay, range rate, signed Doppler and phase;
- UMa/UMi/RMa/InH pathloss;
- UMa/UMi/RMa/InH LOS probability;
- Release-19 O2I material coefficients and selected material mixtures;
- the TR 38.901 oxygen-absorption table and interpolation;
- ULA/UPA steering responses;
- bounded TDL correlation matrices;
- LSP spatial-correlation mechanics;
- explicit 19-site/3-sector clone topology;
- deterministic UE drops;
- sample-domain interference superposition;
- mobility/Doppler phase continuity;
- absolute received-power and noise equations;
- ray-tracing contract hashes;
- negative fail-closed cases;
- capability and impact contracts.

Rows marked `SPEC_LOOKUP_REQUIRED` are intentionally not fake independent references. They must be replaced before the corresponding InF/CDL/advanced profile is enabled.

## Impact-analysis result

The experiment contract contains:

```text
Wave A: 44 families / 528 experiments
Wave B: 12 families / 144 experiments
Wave C:  8 families /  96 experiments
Total:  64 families / 768 experiments
Rules:  96
```

Wave A is directly implementable in the channel/geometry phase. Wave B requires internal multicell and mobility-control integration. Wave C requires real HST, blockage, ray-tracing or end-to-end dependencies. No wave may be replaced by scalar SINR, configured geometry, perfect covariance, perfect timing or default propagation.

## Artifact-verifier result

Base verifier:

```text
Complete synthetic set: 337 passed / 0 failed / exit 0
Injected hash mismatch: detected / exit 2
```

Impact verifier:

```text
Complete synthetic set: 343 passed / 0 failed / exit 0
Injected hash mismatch: detected / exit 2
```

The verifiers check CSV schemas, mandatory row counts, status values, observed provenance, deterministic errors, power reconciliation, fail-closed negative cases, test completion and PNG source/hash/semantic metadata.

## Existing output inventory

```text
CSV files inspected:                 225
Rectangular CSVs:                    224
Malformed CSVs:                      1
PNG files inspected:                 40
Decoded and structurally nonblank:   40
Contracted phase artifacts present:  0/100
```

The existing PNGs are mostly generic geometry/system outputs. They do not satisfy the channel-phase contracts. The one malformed existing CSV is the previously identified `tmp_geom_cfg_export_manual/run/reports/csv/phase7_truth_gates.csv`.

## Runtime limitation

MATLAB and Octave are unavailable in this environment. Therefore:

```text
Production MATLAB channel execution: BLOCKED
Relevant existing MATLAB tests:      47 files blocked
Current simulator phase result:      FAIL/BLOCKED
```

No statement is made that the current or future corrected MATLAB code passes until Codex executes the required MATLAB commands, generates all 100 artifacts and both artifact verifiers return zero.

## Required completion

Codex may report `COMPLETE` only after:

- all 24 findings are closed for the enabled profiles;
- all 88 mandatory MATLAB tests run and pass;
- every enabled deterministic tuple has an exact independent oracle;
- no configured/reconstructed value enters strict observed state;
- pathloss/LOS/O2I/oxygen and all statistical channel gates pass;
- TDL/CDL, array, polarization and mobility continuity pass;
- absolute power and noise reconcile within 0.05 dB;
- per-link sample-domain interference and covariance reconcile;
- all 768 impact experiments and 96 rules complete;
- all 48 CSVs and 52 PNGs pass;
- the complete repository MATLAB regression passes.
