# RF impairments, power control and receiver-front-end limited execution report

## Pack validation

- Findings: 14
- Mandatory MATLAB tests specified: 72
- Capability rows: 210
- Impact families: 64
- Controlled experiments: 768
- Matched pairs: 384
- Acceptance rules: 96
- Base production artifacts: 32 CSV + 22 PNG
- Impact production artifacts: 16 CSV + 30 PNG
- Total contracted artifacts: 100
- Independent manifest files: 24
- Vector verifier exit code: 0
- Base artifact verifier self-test: valid=0, injected corruption=2
- Impact artifact verifier self-test: valid=0, injected corruption=2

## Current source result

- Static checks: 58
- Source-visible defect signatures: 46
- Useful existing foundations: 11
- Current contracted artifacts: 0/100
- Existing CSV files inspected: 225
- Rectangular existing CSVs: 224
- Existing PNG files inspected: 40
- Decoded and nonblank existing PNGs: 40

The current source remains FAIL before remediation. The most consequential signatures are linear fixed-length SCO resampling, heuristic phase-noise masks, PA output-power restoration, hidden automatic AGC, simple quantization/covariance, direct sample-domain EVM, configured-SNR-derived pathloss and incomplete UL power-control loops.

## Runtime limitation

MATLAB and Octave are not installed in this environment. Therefore:

- the production MATLAB waveform chain was not executed;
- the 72 new mandatory tests were not executed;
- 403 existing RF-related MATLAB tests were not executed;
- no production RF CSV or PNG was generated.

Runtime unavailability is recorded as BLOCKED, never PASS.

## Non-MATLAB checks completed

The Python checks verified:

- all independent files, SHA-256 hashes and row counts;
- exact CFO, IQ, Friis and power-control analytical floors;
- 210 capability rows;
- 64 impact families, 768 paired experiments and 96 rules;
- CSV/image contracts;
- valid synthetic artifact acceptance;
- intentional PNG hash-corruption detection.
