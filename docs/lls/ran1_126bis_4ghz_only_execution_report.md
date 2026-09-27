# RAN1#126bis fixed-4 GHz campaign execution report

Date: 2026-09-27

## Scope

This revision establishes one terrestrial, single-carrier, TDD campaign at an
exact center frequency of 4,000,000,000 Hz. It does not execute FDD, carrier
aggregation, a carrier-frequency sweep, NTN, ISAC, or sensing. NR-derived
waveform/control/reference-signal blocks remain labeled benchmark building
blocks; this report does not claim a finalized 6GR or 3GPP evaluation method.

The repeated endpoint in the earlier user list was interpreted as `-30 dB`.
The executable primary axis is exactly `[-30,-20,-10,0,10,20,30,40] dB`.

## Implemented in this revision

- Matrix-wide resolved-config gate for exact carrier frequency, duplex,
  single-carrier/CA, frequency-sweep, NTN and ISAC constraints.
- Pre-execution `parameter_bindings.csv` with every discovered resolved
  carrier/duplex binding and its exact verification result.
- C4_20 profile: 20 MHz, 30 kHz SCS, 51 RB, FFT 1024, 30.72 MS/s.
- H4_100 registry profile: 100 MHz, 30 kHz SCS, 273 RB, FFT 4096,
  122.88 MS/s. It is registered but not in the Stage-0 execution list.
- A0, F1 TDL-A/30 ns and F2 CDL-C/100 ns reusable channel fragments at 4 GHz.
- LAB_4x2 profile and explicit 2x4 downlink AWGN matrix with unit-norm rows.
- Legal Case-B eight-hypothesis SSB codebook and a post-SSB CSI-RS occasion.
- Eight independent Stage-0 child points with paired seed 1001 and retained
  failure semantics.
- Parent combined CSV/PNG export at 300 dpi, stable common filenames, actual
  center-frequency annotation, and explicit unavailable-artifact reasons.
- Capability coverage for all 25 terrestrial agenda items without relabeling
  the Stage-0 PDSCH/PUSCH path as evidence for unimplemented WUS/CB-PUSCH/etc.

## Validation completed

- C4_20 resolved scenario builds through `buildInternalConfig` and
  `FrameStructureEngine` at the intended grid and 4x2 dimensions.
- `tests/test4GHzOnlyCampaignConfiguration.m`: three focused carrier/grid/
  matrix-preflight tests pass.
- `tests/test_lls_sweep_report.py`: 10 tests pass.
- Repository config/channel gates: `testConfig`, `testLLS_DL`, `testLLS_UL`,
  and `testLLS_ReferencePoints` pass in the combined gate command.

Truth/export and full-suite status are updated below only after their running
commands reach a terminal result.

## Execution status and honest gaps

The executable master is
`simulator/configs/campaigns/ran1_126bis_4ghz_only.yaml`. This revision is
Stage 0, not the entire requested qualification matrix. It uses one paired
seed for integration smoke; it does not yet satisfy the five-seed/5,000-TB
fixed-MCS or 20,000 measured-slot connected qualification budgets.

H4_100 fixed/adaptive families, fading/mobility, controlled waveform
interference, CB-PUSCH, cold-access episode budgets, RF compensation pairs,
geometry, WUS, and wideband W4_200/W4_400 studies remain blocked or pending
exactly as recorded in the capability coverage CSV. No synthetic measurements
or placeholder primary rows are emitted for them.

Formal agreement claims from the referenced agenda/Chair-note DOCX files remain
`source_pending` because those source documents were not supplied in this turn.
