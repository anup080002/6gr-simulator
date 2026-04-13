# Phase 2 Waveform System Truth Plan

## Goal

Enable an honest multi-cell waveform system truth path for scheduler, mobility, handover, CRC outcomes, and bidirectional traffic without routing truth-mode execution through abstract PHY or BLER proxy decisions.

## Current Blocker

The active repo no longer ships `AbstractPHY`, LUT/DB BLER proxy backends, hybrid calibration flows, or the old 60-cell stress/proxy runner. The remaining blocker is now practical waveform-system scale: longer-duration, larger-topology SLS runs still need more runtime optimization, validation breadth, and artifact review before they can be claimed as production-grade waveform system truth.

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
- Create dedicated waveform system validation configs before attempting 20-site, 60-cell truth runs.
- Keep stress/proxy profiles separate from truth-validation profiles.

## Acceptance Criteria

Truth system mode is only acceptable when all of the following are true:

- no `AbstractPHY` or removed proxy/hybrid backend in the active truth system path
- no LUT/logistic/BLER-proxy decode decisions in truth mode
- grant traces are backed by real allocations and CRC outcomes
- mobility and handover traces are driven by waveform-consistent measurements
- truth-labeled system artifacts contain no `proxy`, `fallback`, `lut`, `logistic`, `synthetic`, or `FAST_PROXY` markers
- dedicated tests cover multi-cell scheduler, mobility, handover, CRC, and artifact integrity

Only after those conditions are met should the repo add or claim a true 20-site, 60-cell system runner.
