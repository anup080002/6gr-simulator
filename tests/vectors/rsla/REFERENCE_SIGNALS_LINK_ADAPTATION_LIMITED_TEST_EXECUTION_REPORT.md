# Reference Signals, Measurements and Link Adaptation — Limited Execution Report

## Scope

This report evaluates the uploaded simulator source and validates the accompanying Codex implementation pack without pretending that MATLAB execution occurred.

## Pack construction result

- Detailed Codex prompt: **697 lines**
- Findings: **18**
- Explicit capability tuples: **180**
- Independent/input files: **37**
- Total protected rows: **8760**
- Mandatory MATLAB tests: **70**
- Impact families: **64**
- Controlled experiments: **768**
- Matched pairs: **384**
- Acceptance rules: **96**
- Required production artifacts: **100** = 48 CSVs + 52 PNGs

The vector verifier exits with code **0**. Analytical RSRP/RSRQ/SINR/RSSI/EVM, EESM, OLLA drift, L3 filtering and paired-experiment checks pass.

## Important independence boundary

The pack provides exact independent analytical floors for measurements, EVM, EESM, OLLA, filtering, gaps, selected event arithmetic, collision set arithmetic and impact pairing. The DM-RS, CSI-RS, SRS, TRS and PT-RS input matrices intentionally mark several positive rows as `SPEC_LOOKUP_REQUIRED`. They are test definitions, not fabricated exact sequence/index oracles. Codex must add pure-spec or frozen independent vectors for every enabled reference-signal tuple before reporting completion.

## Current source result

- Static checks: **64**
- Targeted defect checks: **52**
- Defect signatures detected: **51**
- Useful foundation checks: **12**
- Useful foundations detected: **12**
- Current result: **FAIL**

Confirmed source-visible issues include best-effort/defaulted CSI-RS construction, generic/clamped TRS construction, infinite measurement age defaults, compact CSI payload packing, CQI/MCS laboratory defaults, EESM beta fallback, interpolation-based MCS thresholds, configured-SNR and configured-table paths, SRS clamping/full-carrier assumptions, configured Doppler/SNR around tracking, swallowed PT-RS errors, and absence of the canonical profile/state/calibration/event objects required by this phase.

Useful foundations already exist and should be preserved: Toolbox-backed CSI-RS generation, receiver post-equalization SINR, SRS no-oracle and channel-estimation helpers, strict SRS entry points, TRS timing/frequency estimators, PT-RS CPE correction, a causal measurement selector, a measured CSI feedback entry point and measured-SINR analytics.

## Existing output inventory

- Existing CSVs: **225**
- Rectangular CSVs: **224**
- Existing PNGs: **40**
- PNGs decoded: **40**
- Structurally nonblank PNGs: **40**
- Contracted RSLA artifacts present: **0/100**

The existing figures are generic system/geometry/SINR/throughput/queue figures. They do not prove exact RS mapping, CSI bit ownership, calibrated effective SINR, OLLA convergence, measurement filtering/events or tracking correction.

## Artifact-verifier self-tests

Base verifier:

- complete synthetic 32-CSV/22-PNG set: exit **0**
- injected PNG hash mismatch: exit **2**

Impact verifier:

- complete synthetic 16-CSV/30-PNG set: exit **0**
- injected PNG hash mismatch: exit **2**

## Runtime boundary

- MATLAB: **not found**
- Octave: **not found**
- Relevant existing MATLAB tests blocked: **87**

Therefore no claim is made that the current or future corrected MATLAB waveform chain passes. MATLAB unavailability is **BLOCKED**, not PASS.

## Limited result counts

- PASS: **15**
- WARN: **2**
- FAIL: **2**
- BLOCKED: **2**

The two expected pre-remediation failures are the current source defects and absence of all 100 contracted production artifacts.
