# AI 10.3.2 corrected Alt-3/C3 implementation status — 2026-10-02

This is an implementation/evidence note, **not a final performance result or a 3GPP-agreed 6GR specification**. The corrected contribution is the authority for the proposed six-bit UL MCS design; Release-18 NR remains the baseline reference.

The normative NR references used here are [TS 38.212 V18.8.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf) for control coding/field layout and [TS 38.214 V18.8.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf) for data/MCS procedures. In NR DCI 0_1 the MCS field is five bits; SixGR's six-bit field is deliberately labelled a study extension.

Input document SHA-256: corrected Jio contribution `6292B0B1194B632FF8E6D34EBBBA5ADDB04732449108141F7BBA1D6F72990B1B`; RAN1#126 chair notes `99E44D237970377736D06C42512361A55BE5641A798438012D037538DCA3FF91`. Company results reported in the notes are not SixGR simulation results.

## Verified focused behavior

| Surface | Executed evidence | Limit |
|---|---|---|
| Corrected six-bit table | B0–B27 unchanged, H0–H3 at 32–35, stored-TBS meanings at 28–31/36, 37–63 unassigned; fractional and invalid indices rejected. `testRAN1AI1032CorrectedAlt3Mapping` passes. | This is a proposed research table, not a normative NR table. |
| Connected control | PDCCH waveform blind reception recovered UL H0 at index 32 from a 41-bit payload, materialized a rank-two grant, and left the paired DL field at five bits. `testRAN1AI1032Alt3PDCCHWaveform` passes. | One configured 25-PRB control case; no PDCCH detection probability or system scheduling claim. |
| New TB and stored-TBS HARQ | The received H0 grant encoded a 56,368-bit PUSCH TB. A later received index-36/unchanged-NDI grant reused the same UE HARQ payload for attempt two; no-history use was rejected. | Stored-TBS index 36 is a transmit/control ownership check, not yet an independent gNB decoding result. |
| Connected H0 PUSCH/UCI reception | At 25 PRBs and rank two, the independent gNB receiver decoded H0/index 32, the 56,368-bit TB and five HARQ-ACK bits on attempts RV0 and RV2; second-attempt soft combining was reported. `testRAN1AI1032Alt3ConnectedPUSCH` passes. | Both focused attempts passed CRC, so this does not measure a HARQ combining gain or conditional BLER. |
| Full-band connected H0 reception | At 273 PRBs / 30-kHz SCS (100-MHz carrier grid), rank two and 30-dB configured reference SNR, the independent gNB receiver decoded a 622,760-bit TB and five HARQ-ACK bits on RV0 and RV2; soft combining was present on attempt two. | One controlled AWGN operating point. This is not a statistically qualified 100-MHz BLER/throughput result; both attempts passed. |
| Full-band rank-four limit | The rank-four / H0 / 30-dB check decoded UCI but its first 273-PRB TB failed CRC. At a separately configured 40-dB reference SNR, both RV0 and RV2 attempts decoded the 1,245,544-bit TB and five HARQ-ACK bits; the applied noise variance changed from 0.00025 to 0.000025 as required by the ten-dB SNR difference. | These are individual seed/operating-point results, not an interpolated BLER threshold or proof of rank-four reliability at 30 dB. |
| Full-band fixed-MCS PHY | 273-PRB H0 coded PUSCH smoke passed at ranks one and four at 40 dB; its negative-SNR branch failed decoding as expected. `testRAN1AI1032F1PhysicalSmoke` reports `primary_calibration_evidence=0`. | A few smoke TBs do not establish a BLER curve or a proposal gain. |
| Planning | The corrected C3 labels reach S1/S4/S5 of the 17,280-row paired SLS plan; case-plan validation passes. | Planned rows remain blocked/ineligible until matched physical calibration and execution. |

The historical `experimental_6gr_ai1032_option_a` five-bit table is retained only as a comparison candidate. Its H0 index 28 must never be relabelled as corrected C3. The earlier retained 32-TB B27/−10-dB diagnostic was generated before this correction and is **not** a corrected-C3 result.

## Comparator and campaign infrastructure added on 2026-10-02

The YAML catalog now resolves distinct C0, C1, C2a, C3, C4 and C5 codepoint maps. C1/C2a/C4/C5 H0 were exercised through a bounded 25-PRB rank-two connected PDCCH/PUSCH/UCI receive path, including RV0 and RV2. That demonstrates field mapping and decoding in those selected cases; it does **not** establish matched adaptive performance or statistical control reliability. C2b's changed-context retransmission procedure and C6's configured-table activation/cost remain unimplemented and blocked.

The isolated planning folder now contains `mcs_indication_definitions.csv`: one YAML-backed definition table covering all 352 codepoints across C0–C5, including the 27 unassigned C3 values (37–63). Its manifest class is `deterministic_MCS_definition_not_performance`; it is suitable for checking a representation table, not a radio-performance claim.

The independent fixed-input arithmetic regression `testRAN1AI1032ReferenceArithmetic` passes for the contribution's 51-PRB, two-layer 256QAM fixture: `N_info=108783`, `N_info'=108544`, `TBS=108552`, BG1 has 13 code blocks, and the coded-bit budgets are 58,752 at 51 PRBs and 138,240 at 120 PRBs. This cross-checks `nrTBS`; it is a construction identity, not a decoded-performance measurement. The retained output is `logs/ai1032_reference_arithmetic_20261002.log`.

The fixed-MCS F1 runner now appends each actual decoded TB to a per-point journal before checkpointing. Resume validates trial ordinal, case, SNR, source and deterministic seed, including a checkpoint-lag recovery test. Each run preserves inherited YAML files, resolved configuration and source hashes. The journal and provenance tests are infrastructure tests, not a BLER qualification.

A bounded 273-PRB / 100-MHz AWGN B27 rank-one sizing run executed four physical TBs at −10 dB in **94.670 seconds** on local MATLAB R2026a; all four failed CRC. Its raw data are in `results/ai_10_3_2_modulation/benchmark_20261002_v1/f1`, with console evidence in `logs/ai1032_f1_100mhz_benchmark_20261002.log`. The run ended at its deliberate four-TB invocation budget, so `AllPointsComplete=false` and `ThresholdCount=0`. These four outcomes are neither a qualified BLER point nor a universal time-per-TB estimate. This run predates the final provenance-source hash additions and should not be resumed under a new source identity.

## Result gate still open

The study requires at least 2,000 physical TBs and 200 errors per SNR point (up to 100,000 TBs), plus independent HARQ fit/validation, matched DL/UL coverage where applicable, S0 traffic-load calibration and executed paired 21-cell confidence intervals. With 120 currently selected F1 cases and 56 coarse SNR points, the first-transmission minimum alone is **13,440,000 TBs**, before refinement or HARQ histories. No qualified corrected-C3 threshold or SLS primary result is installed. Do not report UPT, coverage or candidate gain from this status note.

The assumed 7-GHz NR-inspired phase-noise profile is a disclosed sensitivity assumption, not an instrument-qualified oscillator mask. Statistical conclusions must keep this branch separate from ideal-RF and other RF branches.

## Reproducible focused evidence

- `logs/ai1032_alt3_phy_focused_v2_20261002.log` — mapping and 273-PRB physical smoke.
- `logs/ai1032_alt3_pdcch_to_pusch_20261002.log` — received H0 control to actual UE-coded PUSCH and paired case-plan check.
- `logs/ai1032_alt3_stored_tbs_harq_20261002.log` — received index-36 retained-payload HARQ check.
- `logs/ai1032_alt3_connected_pusch_rx_20261002.log` — corrected H0 control/PUSCH/UCI through independent gNB decode and two HARQ attempts.
- `logs/ai1032_alt3_fullband_connected_rx_20261002.log` — 273-PRB / 30-kHz full-band connected H0 reception.
- `logs/ai1032_alt3_fullband_rank4_connected_rx_20261002.log` — retained rank-four / 30-dB CRC failure.
- `logs/ai1032_alt3_fullband_rank4_40db_20261002.log` — separately configured rank-four / 40-dB capability check.
- `logs/ai1032_alt3_required_focused_20261002.log` — table, DCI, F1 configuration/threshold, config, UL and reference regressions.
- `logs/ai1032_alt3_adjacent_regressions_20261002.log` — DL, implementation-audit and SLS planning/runtime regressions.
- `logs/ai1032_alt3_result_integrity_20261002.log` — `testE2E_FastVsTruth` and `testE2E_TruthPacketSemanticCampaign`, both completed with zero process exit status.

`testAll` remains a final repository verification gate after focused repairs. The tests above are focused checks, not a substitute for complete campaign qualification. No submission-grade TDoc performance or accepted SLS claim exists yet.
