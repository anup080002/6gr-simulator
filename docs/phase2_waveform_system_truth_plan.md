# Phase 2 Waveform System Truth Plan

## Goal

Enable an honest multi-cell waveform system truth path for scheduler, mobility, handover, CRC outcomes, and bidirectional traffic without routing truth-mode execution through abstract PHY or BLER proxy decisions.

## Current Status

The active repo no longer ships `AbstractPHY`, LUT/DB BLER proxy backends, hybrid calibration flows, or the old 60-cell stress/proxy runner. A bounded multicell waveform-truth scale profile now exists at `simulator/configs/scenarios/variants/SCN00_BOUNDED_WAVEFORM_TRUTH_SCALE.yaml`; it keeps the 4 GHz / 100 MHz / TDD / 30 kHz system-level waveform path active, emits runtime scale/profile tables, captures MATLAB profiler CSVs, and runs the primary truth-artifact scanner. Large-topology, long-duration production truth is still not claimed until those same checks pass on longer 19-site or 20-site runs.

## Scope Boundary

Phase 1:
- waveform LLS
- truth E2E replay
- strict artifact verification
- explicit truth-vs-proxy separation

Phase 2:
- waveform multi-cell SLS/system execution
- decode-driven grant outcomes
- mobility and handover coupled to waveform measurements
- truth-grade 20-site, 60-cell runs

## Required Workstreams

1. Keep waveform-only system truth as the only active execution path
- Maintain the waveform-capable system PHY path in [`+sixgr/+system/SystemLevelRunner.m`](c:\Users\anup0\OneDrive\Documents\Simulator\sixgr_foundation_v2\+sixgr\+system\SystemLevelRunner.m) and [`+sixgr/+system/PhyFactory.m`](c:\Users\anup0\OneDrive\Documents\Simulator\sixgr_foundation_v2\+sixgr\+system\PhyFactory.m).
- Do not reintroduce abstract/proxy PHY backends into the active runtime surface.

2. Make grant outcomes decode-driven
- DL and UL grant success/failure must come from real waveform decode and CRC outcomes.
- Truth-mode grant traces must not use LUT, logistic, synthetic, fallback, or aggregate-served-bit reconstructions.

3. Couple measurements to waveform channels
- CSI, CQI, BLER, timing, and channel-estimation inputs must come from waveform-consistent channels and receivers.
- Mobility and handover triggers must consume those measurements rather than abstract shortcuts.

4. Preserve result integrity in system exports
- Primary grant/HARQ/KPI tables must remain empty or fail loudly when truth-grade backing data is unavailable.
- No fallback-only rescue rows may enter truth-labeled system outputs.

5. Add scale-aware validation profiles
- Maintain dedicated waveform system validation configs before attempting 20-site, 60-cell truth runs.
- Use `SCN00_BOUNDED_WAVEFORM_TRUTH_SCALE` as the local bounded guard profile for runtime profiling and truth-artifact scans.
- Keep stress/proxy profiles separate from truth-validation profiles.

## Acceptance Criteria

Truth system mode is only acceptable when all of the following are true:

- no `AbstractPHY` or removed proxy/hybrid backend in the active truth system path
- no LUT/logistic/BLER-proxy decode decisions in truth mode
- grant traces are backed by real allocations and CRC outcomes
- mobility and handover traces are driven by waveform-consistent measurements
- truth-labeled system artifacts pass `reports/csv/truth_primary_artifact_scan.csv` with zero active `proxy`, `fallback`, `lut`, `logistic`, `synthetic`, or `FAST_PROXY` marker issues
- dedicated tests cover multi-cell scheduler, mobility, handover, CRC, and artifact integrity

Only after those conditions are met should the repo add or claim a true 20-site, 60-cell system runner.

## Actual LLS Implementation, Not Labels

Phase-2 system truth is not allowed to stop at truth labels, dashboard cards, or green status rows. For every enabled PHY/MAC/RF block, the system path must prove actual runtime execution with generated evidence, numerical sanity checks, and DUT-vs-reference comparison where a trusted reference exists.

The minimum implementation-proof package for bounded and large-topology system runs is:

- runtime function coverage showing expected functions actually called
- waveform/grid/bit/decoder/channel evidence rows for each enabled block
- analytical or 5G Toolbox reference comparisons for mobility, timing, CFO, TBS, and other exposed block outputs
- explicit oracle/proxy/fallback detection that fails closed in truth mode
- final `Actual LLS Implementation Verdict` reporting whether the run is full actual LLS, partial actual LLS, a label/proxy simulator, or a failed evidence run

System-truth claims must therefore be backed by the same implementation-validation harness artifacts and hard-failure rules used by waveform LLS truth. No future 20-site or 60-cell truth claim is acceptable if the run only preserves honest labels while missing real execution proof.
