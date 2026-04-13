# 6G PHY LLS Result Specification

## Goals

The result set must be:

- machine-readable
- human-readable
- reproducible
- easy to compare across scenarios and sweeps
- rich enough for debugging, KPI review, and publication-quality analysis

## Canonical Output Tree

The canonical LLS result root is:

```text
results/lls/<scenario_id>/<run_tag_or_current>/
```

Within a run:

```text
meta/
reports/csv/
reports/mat/
reports/image/
logs/
air_interface/csv/
air_interface/mat/
air_interface/image/
control/csv/
control/image/
beamforming/csv/
beamforming/image/
```

Additional directories may appear when enabled:

- `packet_flow/`
- `rf/`
- `numerology/`
- `harq/`
- `interference/`

## Mandatory Metadata Artifacts

- raw input config copies
- resolved config in JSON and YAML
- scenario manifest JSON
- source-chain table
- schema validation context
- simulator version and git hash
- random seed summary
- environment summary
- scenario report markdown

## Mandatory KPI Tables

The mandatory LLS KPI set includes:

- overall case status table
- link KPI summary table
- SNR sweep summary
- per-trial PDSCH table when DL data is enabled
- per-trial PUSCH table when UL data is enabled
- per-trial PBCH/SSB table when initial access blocks are enabled
- per-trial PDCCH table when control is enabled
- per-trial PRACH table when random access is enabled
- per-trial PUCCH and SRS tables when enabled

## Mandatory Per-Trial Fields

When applicable, per-trial rows should include:

- scenario and config identity
- trial index
- direction
- waveform/channel profile
- SNR and measured SINR
- BLER / BER / block pass-fail
- CQI / PMI / RI where applicable
- rank and layer count
- beam index / panel / TRP identifiers where applicable
- channel gain / noise variance / timing offset
- RS port counts and RS configuration fingerprints
- HARQ attempt / RV / combining mode

## Mandatory Plots

At minimum, the simulator should generate plots for enabled features:

- BLER vs SNR
- throughput vs SNR
- measured SINR distribution or trial trace
- beam or channel-score plots for beamforming studies
- control detection pass-rate plots for PDCCH/PRACH studies
- CSI quality plots such as NMSE/SGCS when enabled
- energy and complexity plots when energy instrumentation is enabled

## Optional KPIs

Optional but recommended KPIs include:

- NMSE
- SGCS
- EVM-like debug metrics
- CFO residual
- phase-tracking residual
- beam condition number
- beam score spread
- control false-alarm / miss-detection breakdown
- HARQ latency and stop-condition statistics
- model complexity, inference count, and fallback rate for AI cases
- UE and NW energy per bit or per delivered block

## Optional Intermediate Debug Outputs

Optional debug artifacts may include:

- equalizer weights
- channel-estimate snapshots
- beam score matrices
- RS correlation traces
- soft-bit or LLR summaries
- HARQ combining traces
- AI model confidence traces
- impairment state traces

These should be written only when explicitly enabled, and they should not replace primary KPI tables.

## Machine-Readable Artifacts

Required machine-readable formats:

- JSON for metadata and manifests
- CSV for primary KPIs and summaries
- MAT for MATLAB-native replay/debug bundles

Optional machine-readable formats:

- Parquet mirrors for large KPI tables
- HDF5/NPZ for intermediate arrays and traces

## Human-Readable Artifacts

Required:

- Markdown summary report
- PNG plots

Optional:

- HTML/PDF-ready report rendering
- slide-friendly figure exports

## Pass/Fail Checks

Each run should emit explicit pass/fail or status checks for:

- config validation
- run completion
- required artifact presence
- per-case block pass/fail
- no skipped primary rows unless the scenario explicitly excludes that block
- deterministic-mode state recorded
- AI fallback state recorded when AI is enabled

## Sanity Checks

The result layer should also record sanity checks such as:

- finite SNR/SINR values
- no contradictory waveform/channel labeling
- no impossible layer count relative to antenna dimensions
- no missing manifest fields
- no missing mandatory plots when the relevant block was enabled
- no empty beamforming CSV for beamforming-enabled runs

## Example Primary Files

Typical primary files include:

- `reports/csv/scenario_summary.csv`
- `meta/scenario_manifest.json`
- `air_interface/csv/lls_kpi_summary.csv`
- `air_interface/csv/lls_snr_sweep.csv`
- `air_interface/csv/dl_pdsch_trials.csv`
- `air_interface/csv/ul_pusch_trials.csv`
- `air_interface/csv/pbch_trials.csv`
- `control/csv/pdcch_blind_decode_trials.csv`
- `control/csv/prach_detection_trials.csv`
- `beamforming/csv/probe_beam_mimo.csv`

## Result Integrity Rules

- Primary exports must contain real data for the mode they claim.
- No proxy, fallback, or synthetic rows may be relabeled as truth outputs.
- Empty or missing data should remain empty or be omitted, not backfilled with fake rows.
- Artifact names must match the enabled subsystems and runner profile.

## Expected Results and What a Correct 6G PHY LLS Should Be Able to Show

This section defines the expected physical-layer trends that the simulator should reveal when the configuration, signal processing, and result outputs are all working correctly. These are not cosmetic expectations. They are the interpretation rules that tell a lab user whether the generated curves and tables behave like a credible 5G/6G PHY LLS.

### 1. Baseline Scenario Trends

For the NR-like benchmark baseline, the result set should show the following directions:

- `BLER vs SNR` must decrease monotonically on average as SNR increases for fixed waveform, coding, rank, and impairment settings. Small Monte Carlo noise is acceptable, but gross reversals across adjacent points are a correctness problem.
- `Throughput vs SNR` must increase as the decode success rate increases, then plateau once the selected modulation/coding/rank saturates.
- `BER` should fall before `BLER` fully collapses, and `FER/TB error rate` should track block-level failures more directly than bit-level BER.
- `Decoder iterations` should decrease as the operating point moves farther above the waterfall region, especially when early stopping is enabled.
- `CE NMSE` should improve with SNR until interpolation loss, phase tracking residual, or model mismatch becomes dominant.
- `Measured SINR`, `CQI`, `PMI`, `RI`, and `CRI` should become more stable as SNR rises and channel estimation quality improves.
- `Constellation scatter` should contract with increasing SNR, while `EVM` should improve until RF impairment floors dominate.
- `PDCCH`, `PBCH`, `PRACH`, `PUCCH`, `PDSCH`, and `PUSCH` pass rates should all improve with SNR, but at different operating points depending on their coding, repetition, and signal-energy assumptions.

For a correct baseline campaign, the SNR axis should usually split into three visible operating regions:

- `Low-SNR region`:
  - `BLER` and `FER` remain high.
  - `Throughput` and `goodput` remain low.
  - `Decoder iterations` and `decode latency` are near their worst values.
  - `Constellation scatter`, `EVM`, and `symbol error rate` all indicate strongly impaired decisions.
  - The proving artifacts are `lls_snr_sweep.csv`, `dl_pdsch_trials.csv`, `ul_pusch_trials.csv`, `bler_vs_snr.png`, and `throughput_vs_snr.png`.

- `Waterfall region`:
  - `BLER` drops sharply over a relatively small SNR interval.
  - `Throughput` rises sharply over the same interval.
  - `CQI`, `RI`, and `PMI` stop oscillating and begin to stabilize.
  - `CE NMSE` and `phase tracking error` improve rapidly if the RS density is sufficient.
  - The proving artifacts are `lls_snr_sweep.csv`, `srs_trials.csv`, `trs_trials.csv`, `dl_pdsch_trials.csv`, `ul_pusch_trials.csv`, and `nmse_vs_snr.png`.

- `High-SNR region`:
  - `BLER` approaches zero or the configured floor.
  - `Throughput` reaches the configured rank/MCS ceiling.
  - `Decoder iterations` fall toward their minimum.
  - Residual impairment metrics such as `EVM`, `CFO error`, and `phase tracking error` stop improving materially if the run is impairment-limited rather than noise-limited.
  - The proving artifacts are `dl_pdsch_trials.csv`, `ul_pusch_trials.csv`, `modulation_shaping_outputs.csv`, and `channel_estimation_tracking_outputs.csv`.

The minimum artifacts that should reveal these trends are:

- `air_interface/csv/lls_snr_sweep.csv`
- `air_interface/csv/lls_kpi_summary.csv`
- `air_interface/csv/dl_pdsch_trials.csv`
- `air_interface/csv/ul_pusch_trials.csv`
- `air_interface/csv/pdcch_trials.csv`
- `air_interface/csv/prach_trials.csv`
- `air_interface/csv/pbch_trials.csv`
- `air_interface/csv/srs_trials.csv`
- `reports/image/bler_vs_snr.png`
- `reports/image/throughput_vs_snr.png`
- `reports/image/nmse_vs_snr.png`

The interpretation is incorrect if any of the following happen without an explicit scenario reason:

- `BLER` increases while `MeasuredSINR_dB` also increases in adjacent sweep points.
- `Throughput` decreases after `BLER` has already collapsed and the configured MCS/rank did not change downward.
- `CQI` or `RI` become less stable at higher SNR while `NMSE` and `EVM` both improve.
- `Decoder iterations` rise in the high-SNR region without a simultaneous coding, rank, or HARQ-state explanation.

### 2. Expected Low-Band, Mid-Band, Around-7GHz, and 30GHz Differences

The simulator should show physically different operating regimes across the reference bands:

- Around `700 MHz`:
  - Lower path loss and better coverage should shift required-SNR and outage curves in the favorable direction for coverage-oriented cases.
  - Delay spread and spatial richness may still hurt equalization, but wide-area robustness should be stronger than at higher bands.
  - Beam-management sensitivity should be lower than at high band because links are less beam-centric.
  - Evidence should appear in lower outage probability, lower access failure rate, and broader success region in `BLER vs SNR`, `PRACH detection`, and `PBCH detection`.
  - The artifact set that must reveal this is `basic_phy_performance_outputs.csv`, `initial_access_random_access_outputs.csv`, `prach_trials.csv`, `pbch_trials.csv`, and `access_delay_cdf.png`.

- Around `2 GHz`:
  - This should behave as a balanced baseline region with better capacity than 700 MHz and less severe beam fragility than 30 GHz.
  - Compared with 700 MHz, spectral efficiency should improve for the same array size and bandwidth assumptions, but coverage margin should be somewhat reduced.
  - Compared with 4/7 GHz, CFO sensitivity and beam-management burden should still be milder.
  - The artifact set that must reveal this is `lls_snr_sweep.csv`, `beam_management_outputs.csv`, `csi_outputs.csv`, and `channel_estimation_tracking_outputs.csv`.

- Around `4 GHz` mid-band:
  - This should behave like the practical baseline operating point for many benchmark scenarios.
  - Capacity and array gain should improve relative to low band, while delay spread, Doppler, and calibration assumptions remain manageable.
  - CSI quality and MIMO rank opportunities should usually improve versus low-band compact arrays, provided the channel has usable spatial separation.
  - The artifact set that must reveal this is `pdsch_outputs.csv`, `csi_outputs.csv`, `beamforming/csv/probe_beam_mimo.csv`, and `complexity_implementation_outputs.csv`.

- Around `7 GHz`:
  - Wideband/high-capacity scenarios should show stronger dependence on beam management, CSI quality, rank adaptation, and RF impairment visibility.
  - Higher bandwidth and denser arrays should improve peak throughput and spectral efficiency when beam alignment and CSI are good.
  - The penalty for CSI aging, beam mismatch, reciprocity mismatch, and Doppler should become more visible.
  - These effects should appear in `beam hit rate`, `PMI/RI accuracy`, `beam/precoder gain`, and throughput sensitivity under mobility.
  - The artifact set that must reveal this is `beam_management_outputs.csv`, `csi_outputs.csv`, `pdsch_outputs.csv`, `cfo_to_tracking_traces.csv`, and `heatmap_beam_rank_trp_kpi.png`.

- Around `30 GHz` high band:
  - Links should become strongly beam-centric and much more sensitive to blockage, beam mismatch, CFO, phase noise, and tracking density.
  - Peak throughput can be highest when beam alignment is maintained, but access robustness and mobility robustness should degrade faster than at lower bands.
  - `Initial access latency`, `beam switch latency`, `tracking failure probability`, and `beam misalignment probability` should all become more critical.
  - The correct artifacts are `beamforming/csv/probe_beam_mimo.csv`, `pbch_trials.csv`, `prach_trials.csv`, `trs_trials.csv`, and beam-management plots or summaries.
  - A correct 30 GHz run should therefore show steeper degradation than low-band when `CFO`, `phase noise`, or beam-mismatch knobs are increased, and the effect must appear simultaneously in `beam_management_outputs.csv`, `channel_estimation_tracking_outputs.csv`, and `initial_access_random_access_outputs.csv`.

### 3. Expected Trade-Offs Across Feature Choices

#### CP-OFDM vs DFT-s-OFDM

- `DFT-s-OFDM` should show lower `PAPR CCDF` and lower clipping/backoff stress than `CP-OFDM`, especially in UL power-limited cases.
- `CP-OFDM` should remain more flexible for multi-layer and non-contiguous allocations.
- UL power-limited scenarios should show a `PA backoff impact` advantage for DFT-s-OFDM.
- Beamformed or multi-layer UL candidate studies may show better spatial flexibility for CP-OFDM, while DFT-s-OFDM should preserve an efficiency advantage in low-PAPR terms.
- The proving artifacts are `PAPR CCDF`, `low-PAPR gain`, `PA backoff impact`, `UL throughput`, and `EVM` under PA impairment.
- The direction must be explicit:
  - `PAPR CCDF` for DFT-s-OFDM must lie below CP-OFDM at the same probability level.
  - `Configured backoff` and observed `EVM` under PA stress must be lower for DFT-s-OFDM in power-limited UE studies.
  - If the scenario enables multi-layer or non-contiguous UL mapping, CP-OFDM should preserve configuration feasibility or throughput where DFT-s-OFDM becomes candidate-only or constrained.

#### CSI-RS vs DMRS-based CSI Tracking

- `CSI-RS` should provide cleaner explicit measurement opportunities and stronger benchmark interpretability, especially for scheduled or semi-static CSI acquisition.
- `DMRS-based` tracking should reduce dedicated overhead but become more dependent on data activity, scheduling timing, and demodulation context.
- Under faster time variation, DMRS-based tracking may show lower aging loss if updated frequently, but under sparse scheduling it may degrade relative to CSI-RS.
- The direction should appear in `CQI/PMI/RI accuracy`, `CSI aging loss`, `report latency`, `NMSE`, and `scheduler application loss`.
- The measurement artifacts that should reveal this are `csi_outputs.csv`, `channel_estimation_tracking_outputs.csv`, `channel_snapshots.csv`, and `cfo_to_tracking_traces.csv`.

#### DL-based vs UL-based vs Joint DL/UL CSI

- `DL-based CSI` should show stronger dependence on DL RS density and DL feedback overhead.
- `UL-based CSI` should show stronger dependence on reciprocity assumptions, SRS quality, and calibration mismatch.
- `Joint DL/UL CSI` should improve robustness when mapping and timing are correct, but should also expose more failure modes if port mapping or timelines are inconsistent.
- The relevant outputs are `CQI accuracy`, `PMI accuracy`, `RI accuracy`, `RSRP accuracy`, `CSI report size`, `report latency`, `SRS-port scaling impact`, and `reciprocity mismatch impact`.
- The direction must be explicit:
  - increasing reciprocity mismatch must hurt `UL-based` and `joint` modes more than `DL-based` mode
  - increasing SRS port count should improve UL-based observability only until estimation noise or port overhead dominates
  - misaligned report/application timelines must increase `scheduler application loss` even if raw CSI accuracy stays high

#### QPSK / 16QAM / 64QAM / 256QAM / 1024QAM / 4096QAM

- Higher modulation order should increase peak throughput and spectral efficiency only when the channel estimate, RF chain, and interference environment support it.
- Required SNR at target BLER should shift upward as modulation order increases.
- `1024QAM` and especially `4096QAM` should show much stronger sensitivity to `EVM`, `phase noise`, `CFO`, `IQ imbalance`, and residual channel-estimation error.
- If high-order modulation curves do not separate clearly from lower orders in required-SNR, EVM, and robustness metrics, the simulator configuration or impairment visibility is suspect.
- The proving outputs are `required SNR at target BLER`, `EVM`, `symbol error rate`, `high-order modulation robustness under impairments`, and throughput curves under the same coding/rank assumptions.
- The direction must be explicit:
  - required SNR at `10%`, `1%`, `0.1%`, and `0.01%` BLER must increase with modulation order
  - `EVM` tolerance must tighten with modulation order
  - the gap between ideal and impaired runs must widen markedly for `1024QAM` and `4096QAM`

#### Standard Mapping vs Shaping / NUC / Mixed Modulation

- `NUC`, `mixed modulation`, and shaping options should improve the performance-complexity frontier only in operating regions where their geometric/probabilistic advantage is relevant.
- Gains should show up as leftward BLER shifts, lower required SNR at target BLER, or better throughput at the same BLER target.
- Those gains should be offset by added `distribution matching latency`, `shaping rate loss`, `mapping sensitivity`, or decoder complexity.
- The proving artifacts are `BLER vs SNR`, `required SNR`, `distribution matching latency`, `LLR reliability imbalance metrics`, and `complexity vs gain`.
- The interpretation is only credible if both the gain and the cost are visible in the same run family. A leftward BLER shift without a matching complexity or latency cost is not enough evidence for a shaping or mapping claim.

#### Legacy LDPC vs Candidate Coding Enhancements

- Candidate coding enhancements should either improve waterfall position, lower error floor, reduce complexity at equal BLER, or improve retransmission efficiency.
- If a candidate coding mode claims improvement, the report should show whether the gain appears as `SNR gain at same complexity`, `complexity reduction at same BLER`, `error-floor reduction`, or `latency reduction`.
- `CB size distribution`, `segmentation statistics`, and `puncturing/shortening statistics` should move consistently with the configured coding strategy.
- The measurement artifacts that should reveal this are `coding_decoder_outputs.csv`, `basic_phy_performance_outputs.csv`, `complexity_implementation_outputs.csv`, and `lls_snr_sweep.csv`.

#### Baseline PDCCH vs Repetition / Feedback / 2-stage DCI Candidates

- `PDCCH repetition` should improve miss-detection probability and coverage at the cost of control overhead and monitoring energy.
- `Detection feedback` should improve effective control robustness only if feedback timing and interaction policies are configured correctly.
- `2-stage or multi-stage DCI` should reduce control burden for some payload structures but may add detection latency or capacity trade-offs.
- These changes should appear in `miss-detection probability`, `false-alarm probability`, `blocking probability`, `blind-decode count`, `control capacity under load`, `control latency`, and `PDCCH monitoring energy`.
- The direction must be explicit:
  - repetition should move `miss-detection probability` downward and `monitoring energy` upward
  - two-stage DCI should reduce `DCI size distribution` or `CORESET utilization` only if it does not worsen `control latency` beyond the configured target
  - prior-information or detection-feedback schemes must not improve false-alarm behavior while simultaneously making `control capacity` collapse

#### Baseline Initial Access vs Repetition / Clustering / Beam-Prediction Candidates

- `SSB/PBCH repetition` should improve detection probability and PBCH decode success in weak-link conditions, but increase overhead and energy.
- `Clustering` should reduce common-signal overhead or energy in sparse/common-signal studies, but may degrade worst-case access delay or search complexity.
- `Beam-prediction` should reduce beam sweep burden and improve beam-pair acquisition success if the predictor generalizes well; otherwise it should increase miss rate or wrong-beam probability.
- The proving artifacts are `one-shot SSB detection probability`, `PBCH decode success`, `initial access latency`, `search complexity`, `PRACH detection probability`, `beam-pair acquisition success`, and `initial-access energy`.
- The direction must be explicit:
  - repetition should improve `PBCH decode success` and `PRACH detection probability` at weak SNR but increase `common-signal energy`
  - clustering should reduce `SSB/PBCH/common-signal energy` or `initial-access energy` while shifting `access delay CDF` to the right in sparse designs
  - beam prediction should increase `beam index hit rate` and decrease `beam switch latency` only if `confidence score statistics` and `fallback rate` remain healthy

#### Non-AI vs AI/ML Approaches

- AI/ML should only be considered credible if it improves one of: `NMSE`, `detection accuracy`, `beam hit rate`, `CSI compression efficiency`, `latency`, or `energy`, while its added complexity is also reported.
- It must also show a non-AI baseline comparator and explicit `baseline delta`.
- Robustness must be tested across `bands`, `speeds`, `delay spreads`, `channels`, `arrays`, and `impairments`; otherwise an apparent gain is not enough.
- The proving artifacts are `confidence score statistics`, `fallback rate`, `performance-complexity frontier`, `train/test mismatch loss`, `generalization sweeps`, and `baseline delta`.
- The direction must be explicit:
  - if AI improves `NMSE`, `beam hit rate`, or `CSI report size`, the same run family must also show whether `inference latency`, `operation frequency`, and `memory footprint` rise
  - if mismatch sweeps are harsh, `fallback rate` should rise before catastrophic KPI collapse, not remain artificially flat

#### Energy-Efficient Sparse/Common-Signal Designs vs Latency/Complexity

- Energy-saving sparse/common-signal designs should reduce `UE energy per bit`, `gNB energy per bit`, `RF-chain active time`, or `PDCCH monitoring energy`.
- Those gains should usually come with a penalty in one or more of `initial access latency`, `tracking robustness`, `control latency`, or `access success probability`.
- A correct simulator should show the energy gain and the latency/reliability cost in the same report package, not one without the other.
- The measurement artifacts that should reveal this are `energy_efficiency_outputs.csv`, `initial_access_random_access_outputs.csv`, `pdcch_control_outputs.csv`, `energy_timeline_trace.csv`, and `energy_vs_throughput.png`.

### 4. Expected Shifts With Sweep Dimensions and Operating Conditions

The following trend directions should be visible when the sweep configuration changes:

- `Bandwidth`:
  - Higher bandwidth should increase peak throughput and may improve frequency diversity, but also raises RF linearity, phase-noise visibility, and processing cost.
  - `Energy per bit` may improve or degrade depending on the balance between higher throughput and higher RF/baseband activation.
  - The effect must appear in `throughput`, `PAPR`, `EVM`, `complexity_implementation_outputs.csv`, and `energy_efficiency_outputs.csv`.

- `SCS`:
  - Higher SCS should reduce symbol duration and improve robustness to phase noise and some Doppler effects, but can reduce delay-spread tolerance and increase CP overhead sensitivity.
  - Delay-dominated channels should usually prefer lower SCS; phase-noise/CFO-dominated high-band cases may prefer higher SCS.
  - The effect must appear in `cfo_rmse`, `to_rmse`, `phase_tracking_error`, `ce_nmse`, and `bler_vs_snr`.

- `Delay spread`:
  - Larger delay spread should degrade `CE NMSE`, `interpolation loss`, and BLER unless the RS density, equalizer, or numerology is adapted.
  - The effect should be visible in `NMSE`, `EVM`, and waterfall shift.
  - The proving artifacts are `srs_trials.csv`, `trs_trials.csv`, `channel_estimation_tracking_outputs.csv`, and `nmse_vs_snr.png`.

- `Doppler` and `speed`:
  - Higher Doppler or speed should degrade CSI aging, beam tracking, and channel-estimation stability.
  - It should increase `tracking failure probability`, `PMI/RI inaccuracy`, and throughput loss if adaptation lag is not controlled.
  - The proving artifacts are `csi_outputs.csv`, `beam_management_outputs.csv`, `cfo_to_tracking_traces.csv`, and `throughput_vs_snr.png` for matched mobility sweeps.

- `Beam count`:
  - More beams should improve peak beam gain and top-k beam coverage, but increase search, training, reporting, and switching overhead.
  - The report should show both `beam hit rate` improvement and `beam-management overhead`.
  - The proving artifacts are `beam_management_outputs.csv`, `beam_score_trace.csv`, and `heatmap_beam_rank_trp_kpi.png`.

- `Rank`:
  - Higher rank should increase peak throughput only if channel condition number, CSI quality, and SINR support it.
  - At weak SINR or poor conditioning, higher rank should raise BLER and reduce effective throughput.
  - The proving artifacts are `pdsch_outputs.csv`, `csi_outputs.csv`, `beamforming/csv/probe_beam_mimo.csv`, and `dl_pdsch_trials.csv`.

- `TRP count`:
  - More TRPs should improve robustness, diversity, or coverage in coordinated cases, but add coordination cost, CSI burden, and possibly synchronization constraints.
  - The relevant outputs are `mTRP gain`, `beam-selection gain`, `control latency`, and CSI/report overhead.
  - The proving artifacts are `beam_management_outputs.csv`, `pdsch_outputs.csv`, `pdcch_control_outputs.csv`, and `heatmap_beam_rank_trp_kpi.png`.

- `CFO`, `TO`, and `drift`:
  - Larger offsets or drift should degrade synchronization, tracking, and demodulation.
  - The direction should be visible in `CFO RMSE`, `TO RMSE`, `phase tracking error`, `PBCH/PDCCH miss detection`, and BLER.
  - The proving artifacts are `channel_estimation_tracking_outputs.csv`, `cfo_to_tracking_traces.csv`, `pbch_trials.csv`, `pdcch_trials.csv`, and `bler_vs_snr.png`.

- `RF impairments`:
  - Stronger `PA nonlinearity`, `IQ imbalance`, `phase noise`, `quantization noise`, and `clipping` should worsen `EVM`, increase required SNR, and especially hurt high-order modulation.
  - The proving artifacts are `modulation_shaping_outputs.csv`, `basic_phy_performance_outputs.csv`, `llr_histograms.csv`, and `heatmap_impairment_kpi.png`.

- `Reciprocity mismatch`:
  - This should mainly hurt UL-based or joint CSI approaches, reducing PMI/RI quality, beam/precoder gain, and scheduler application effectiveness.
  - The proving artifacts are `csi_outputs.csv`, `beam_management_outputs.csv`, and `scheduler application loss` rows in `csi_outputs.csv`.

- `Scheduling/application delay`:
  - Longer feedback application delay should increase CSI aging loss and reduce the benefit of otherwise accurate reporting.
  - The report should show a shift in `scheduler application loss`, throughput, and BLER rather than only in raw CSI accuracy.
  - The proving artifacts are `csi_outputs.csv`, `basic_phy_performance_outputs.csv`, and `lls_snr_sweep.csv` for the matched delay sweep.

### 5. Mandatory Correctness-Proving Outputs vs Debug-Useful Outputs

The following outputs are mandatory to prove that the simulator is behaving correctly for a scenario family:

- `Resolved config`, `manifest`, `seed`, `environment`, and `runtime summary`
- `BLER vs SNR/SINR/EsN0`
- `Throughput vs SNR`
- `Per-trial DL/UL tables` with measured SINR and pass/fail state
- `Control and initial-access trial tables` when those blocks are enabled
- `CE/CSI quality tables` when RS/CSI features are enabled
- `Beamforming tables` when beam/rank/TRP features are enabled
- `Coverage table for the requested result spec`, showing which metrics are truly available and which are not

A result is correctness-proving only if it satisfies all of the following:

- the metric varies in the physically expected direction when the governing sweep variable changes
- the same direction is visible in both the summarized output and the underlying per-trial tables
- the metric is tied to a real source artifact rather than a placeholder or derived note-only row
- related metrics are mutually consistent
  Example: if `BLER` improves, `throughput` should not collapse unless `MCS`, `rank`, or control failure explains it.

These are useful for debugging but are not by themselves sufficient to prove correctness:

- constellation snapshots
- equalized waveform traces
- raw channel snapshots
- LLR histograms
- HARQ timeline traces
- DCI candidate traces
- PRACH correlation traces
- AI confidence traces
- energy timeline traces

These debug outputs are still important because they localize failure causes:

- `constellation` and `LLR` traces explain whether failure is driven by demapping quality or coding margin
- `CFO/TO` traces explain whether the problem is synchronization rather than decoding
- `PRACH correlation` and `DCI candidate` traces explain whether the problem starts before payload decode
- `beam score` traces explain whether a throughput loss is a beam-selection problem rather than a coding problem

If the mandatory correctness-proving outputs are missing, flat when they should vary, contradictory across files, or inconsistent with the configured scenario, the simulator should be treated as unverified for that case even if rich debug traces exist.
