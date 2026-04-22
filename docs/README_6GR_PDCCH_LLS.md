# 6GR PDCCH LLS Study Framework

## Architecture

This study framework adds a 6GR PDCCH-like control-channel chain under `+sixgr/+ctrl/`.
It is not presented as a frozen standard. Agreed baselines and FFS hooks are kept explicit.

Main blocks:

- `ControlChannelConfig`, `CORESETConfig`, `SearchSpaceConfig`
- `REGIndexer`, `REGBundleMapper`, `CCEToREGMapper`
- `HashFunction6GR`, `PDCCHCandidateGenerator`
- `ControlPayloadBuilder`, `CRCAttachAndScramble`, `PayloadScrambler`
- `PDCCHModulator`, `PDCCHDMRS`, `PDCCHGridMapper`, `PDCCHRepeater`
- `PDCCHChannelEstimator`, `PDCCHEqualizer`, `PDCCHDecoder`
- `PDCCHBlindDetector`, `PDCCHReceiver`, `PDCCHMetrics`
- `MRSSResourceCoordinator`
- `runPDCCHStudyLLS`

## Supported study knobs

- CORESET duration, mapping type, contiguous/noncontiguous frequency allocation
- CSS and USS
- aggregation levels `1,2,4,8,16` baseline, `32` hook accepted in config
- CRC scrambling on or off
- payload scrambling on or off
- repetition `none`, `intra_slot`, `inter_slot`
- REG bundle size and REGs per CCE
- MRSS NW-side resource coordination
- realistic DMRS-based channel estimation or ideal calibration mode hook
- `full_ofdm` or `grid_mode` selection

## Baseline assumptions vs FFS items

Baseline:

- QPSK only
- single-port DMRS
- slot-level monitoring periodicity
- explicit CORESET and search space
- interleaved and noninterleaved CCE-to-REG mapping

FFS / study hooks:

- nontransparent transmit diversity
- higher than baseline aggregation levels
- alternative hash functions
- alternative DMRS densities and layouts
- MRSS sharing policies

## Honesty notes

- The current fading path inside `runPDCCHStudyLLS` uses an explicit grid-equivalent channel study approximation when the study point requests fading. It does not relabel that approximation as full time-domain fading truth.
- `nontransparent_stub` is intentionally left as a fail-loud future hook.
- CRC scrambling and payload scrambling are implemented as study baselines with traceable seeds and masks.

## How to run

Standalone study:

```matlab
addpath('scripts');
out = run6GRPDCCHStudy;
```

Browser or repo runner path:

```matlab
run_6g_phy_lls_single('simulator/configs/scenarios/pdcch_6gr_study.yaml');
```

## Outputs

Standalone outputs are saved under:

- `results/ctrl6gr_pdcch_<timestamp>/`

Runner-integrated outputs are additionally mirrored into canonical LLS paths:

- `air_interface/csv/pdcch_trials.csv`
- `control/csv/pdcch_trials.csv`
- `reports/csv/pdcch_control_outputs.csv`
- `reports/csv/pdcch6gr_*.csv`

## Known limitations

- Full time-domain fading support is not yet implemented in this control-study runner.
- The current transparent transmit-diversity hook is baseline only and does not claim a finalized 6GR design.
- Per-bundle precoding is a study hook, not a finalized standardized behavior.

## Next extensions for 10.5.2.1

- fuller time-domain TDL/CDL support in `full_ofdm`
- multi-UE control monitoring studies
- richer DMRS pattern families
- future non-transparent diversity and REG-bundle precoding refinements
- tighter MRSS coupling with dual-stack 5G/6G NW-side schedulers
