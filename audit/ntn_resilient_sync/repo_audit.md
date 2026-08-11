# Resilient NTN synchronization repository audit

Audit date: 2026-08-11

## Reused calibrated and production surfaces

- `sixgr.lls.runLLS` executes waveform-truth PDSCH/PUSCH transport blocks and exports CRC-backed trials.
- `sixgr.lls.resolveNTNState` and `sixgr.ntn.validateConfig` own the existing NTN LLS orbit, delay, Doppler, and compensation configuration.
- `sixgr.phy.prach.runStrictPRACHValidation` and `sixgr.link.runPRACHDetection` provide waveform-backed PRACH detection, timing/CFO injection, false-alarm evidence, and search-space evidence.
- `sixgr.link.runPUCCHWaveformTrial` is the existing waveform PUCCH/UCI entry point.
- `sixgr.phy.trs.estimateTRSTiming` and `sixgr.phy.trs.estimateTRSFrequencyOffset` provide physical downlink timing/CFO observation interfaces.
- `sixgr.lls.stats.wilsonInterval`, `sixgr.util.sha256Hex`, and existing artifact/trace utilities provide confidence, hashing, and evidence primitives.

## Gaps found before implementation

- No state-versioned four-domain NTN compensation profile schema existed.
- No exact spherical-Earth reference-area Monte Carlo campaign or uniform-in-area regression existed.
- No common source-error-to-ULRP timing/frequency mapping existed.
- Existing NTN LLS state resolution depends on Satellite Communications Toolbox functions and did not expose a tagged circular-orbit analytical fallback.
- Existing calibrated PHY campaigns were not orchestrated under a single resilient-synchronization evidence contract.
- No public/confidential figure separation or TDoc traceability matrix existed for this study.

## Evidence policy

Analytical, Monte-Carlo geometry, calibrated LLS, scheduler/system, event/procedure, and architecture evidence remain distinct. Missing calibrated evidence blocks only the affected measured claim. It is never replaced with an analytical or synthetic row.
