# LLS Executive Summary

- Scenario: `lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_5gnb_50ue_10slot`
- Runner profile: `waveform_bundle`
- Runtime-qualified description: `Strict waveform-honest NR Rel-20 study-anchor LLS scenario for 4 GHz TDD, 100 MHz, 5 gNBs, 50 randomly placed UEs, and 10 canonical slots launched from the browser-owned MATLAB path. (configured intent; DL dominant effective point layer=2, rank=2, modulation=QPSK, mcs=0 (112/150), configured-match rate 0.0%; UL dominant effective point layer=1, rank=1, modulation=16QAM, mcs=10 (48/96), configured-match rate 0.0%)`
- Run completion: `completed`
- Result OK: `true`
- Partial OK: `false`
- Artifacts generated: `true`
- Required failure count: `0 / 6`
- Optional/pruned case count: `0`
- Runtime (s): `4866.816`
- Covered output metrics: `177 / 220`
- Observed runtime metrics: `150`
- Derived metrics: `27`
- Config-only metrics: `12`
- Disabled metrics: `25`
- Placeholder artifacts/metrics: `0`
- Not-supported metrics: `0`
- Not-available metrics: `6`
- Not-exercised metrics: `0`
- Observed-runtime rollup count: `150`
- Config-only rollup count: `12`
- Report-derived rollup count: `27`
- Primary air-interface KPIs: `true`
- SNR sweep: `true`
- Report coverage table: `true`

## Operating Point

- Configured nominal MIMO: `64x4 nominal rank-2`
- Configured DL nominal operating point: `layers=2, rank=2, modulation=16QAM, mcs=10`
- Configured UL nominal operating point: `layers=2, rank=2, modulation=16QAM, mcs=10`
- Active grid RBs: `273` from `frequency.n_size_grid`
- Active duplex mode: `TDD`
- Active TDD pattern: `DDDSU`
- Effective DL dominant operating point: `layer=2, rank=2, modulation=QPSK, mcs=0 (112/150)`
- Effective DL layer histogram: `2:133|1:17`
- Effective UL dominant operating point: `layer=1, rank=1, modulation=16QAM, mcs=10 (48/96)`
- Effective UL layer histogram: `1:96`
- Effective runtime note: `DL: Runtime-selected operating point diverged from the configured nominal operating point. Dominant effective point: layer=2, rank=2, modulation=QPSK, mcs=0 (112/150). Divergence: dominant recommended RI 1 while transmitted rank remained 2; dominant modulation QPSK vs configured 16QAM; dominant MCS 0 vs configured 10. Exact configured-match rate: 0/150 (0.0%). UL: Runtime-selected operating point diverged from the configured nominal operating point. Dominant effective point: layer=1, rank=1, modulation=16QAM, mcs=10 (48/96). Divergence: dominant layer 1 vs configured 2; dominant rank 1 vs configured 2. Exact configured-match rate: 0/96 (0.0%).`

## Highlights

- DL BLER sweep: min=`0.266667`, mean=`0.266667`, max=`0.266667`
- UL BLER sweep: min=`0.46875`, mean=`0.46875`, max=`0.46875`
- DL throughput sweep: min=`3.20789`, mean=`3.20789`, max=`3.20789`
- UL throughput sweep: min=`9.27333`, mean=`9.27333`, max=`9.27333`
- SRS NMSE: min=`-30.3161`, mean=`-27.2656`, max=`-25.5225`
- HARQ RTT: `4.25`
- Beam hit rate: `0.64`
- UE energy per successful bit: `7.78506e-06`

## Key Plots

- `reports/image/bler_vs_snr.png`
- `reports/image/throughput_vs_snr.png`
- `reports/image/nmse_vs_snr.png`
- `reports/image/control_pass_rates.png`
- `reports/image/metric_coverage_by_category.png`
