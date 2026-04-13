# 6G PHY LLS Block Diagrams and Parameter Lists

The exact ordered chains that back these block diagrams are now carried in the machine-readable top-level config section `processing_chains`. See [processing_chains.md](processing_chains.md) for the normative ordered lists and config bindings.

## DL Tx Chain

```mermaid
flowchart LR
    A[Transport Block] --> B[CRC Attach]
    B --> C[LDPC Encode]
    C --> D[Rate Match]
    D --> E[Scramble]
    E --> F[Modulate]
    F --> G[Layer Map]
    G --> H[Precode / Beamform]
    H --> I[PDSCH + DMRS + PTRS Mapping]
    I --> J[OFDM Modulate]
    J --> K[RF Impairments]
```

Primary parameters:

- `coding.*`
- `modulation.*`
- `mimo.*`
- `reference_signals.*`
- `waveform.*`
- `impairments.*`

## DL Rx Chain

```mermaid
flowchart LR
    A[Rx Waveform] --> B[Timing / CFO / Tracking]
    B --> C[OFDM Demod]
    C --> D[RS-Based Channel Estimation]
    D --> E[Equalization]
    E --> F[Beam / Layer Recovery]
    F --> G[Demodulation]
    G --> H[Descramble]
    H --> I[Rate Recover]
    I --> J[LDPC Decode]
    J --> K[CRC Check]
    D --> L[CSI / SINR / CQI / PMI / RI]
```

Primary parameters:

- `reference_signals.channel_estimation_mode`
- `reference_signals.receiver_example`
- `impairments.*`
- `ai_ml.*` for AI-assisted estimation or demod
- `kpis.*`

## UL Tx Chain

```mermaid
flowchart LR
    A[UL Payload] --> B[CRC Attach]
    B --> C[LDPC Encode]
    C --> D[Rate Match]
    D --> E[Scramble]
    E --> F[Modulate]
    F --> G[Transform Precoding Optional]
    G --> H[Layer Map]
    H --> I[Precode / Beamform]
    I --> J[PUSCH + DMRS + PTRS / SRS Mapping]
    J --> K[OFDM or DFT-s-OFDM Modulate]
    K --> L[UE Power / RF Impairments]
```

Primary parameters:

- `waveform.ul_waveform`
- `waveform.transform_precoding_enabled`
- `waveform.low_papr_mode`
- `waveform.noncontiguous_mapping_enabled`
- `modulation.pi2_bpsk_enabled`
- `reference_signals.pusch_dmrs_ports`
- `reference_signals.srs_*`

## UL Rx Chain

```mermaid
flowchart LR
    A[Rx Waveform] --> B[Timing / CFO / Phase Tracking]
    B --> C[OFDM Demod]
    C --> D[DMRS / SRS Channel Estimation]
    D --> E[MMSE-IRC / RML / Candidate Receiver]
    E --> F[Layer Recovery]
    F --> G[Demodulation]
    G --> H[Descramble]
    H --> I[Rate Recover]
    I --> J[LDPC Decode]
    J --> K[CRC Check]
```

Primary parameters:

- `reference_signals.receiver_example`
- `reference_signals.channel_estimation_mode`
- `channels.*`
- `impairments.*`
- `ai_ml.use_case=channel_estimation`

## Initial Access / PRACH Chain

```mermaid
flowchart LR
    A[SSB / Beam Sweep] --> B[PSS / SSS Detection]
    B --> C[PBCH Decode]
    C --> D[Beam / Timing Hypothesis]
    D --> E[PRACH Preamble Generate]
    E --> F[PRACH Detect]
    F --> G[Beam / RO Mapping]
    G --> H[Msg3 Waveform Consistency]
```

Primary parameters:

- `reference_signals.ssb_enabled`
- `reference_signals.pbch_enabled`
- `random_access.*`
- beam mapping and repetition fields
- candidate AI/ML beam prediction fields

## CSI Acquisition / Reporting Chain

```mermaid
flowchart LR
    A[CSI-RS / DMRS / SRS] --> B[Channel Estimation]
    B --> C[Noise / Interference Estimation]
    C --> D[Codebook and CRI Candidate Generation]
    D --> E[CSI Compression / Selection]
    E --> F[CQI / PMI(Type1/Type2/eType2) / RI / CRI / Candidate CSI Payload]
    F --> G[Feedback or Reciprocity Use]
```

Primary parameters:

- `reference_signals.csi_rs_enabled`
- `reference_signals.srs_enabled`
- `reference_signals.csi_acquisition_mode`
- `reference_signals.operation_orientation`
- `reference_signals.srs_ports`
- `reference_signals.srs_periodicity_ms`
- `reference_signals.sgcs_reporting_enabled`
- `reference_signals.nmse_reporting_enabled`
- `ai_ml.use_case=csi_feedback`

## Control Channel Chain

```mermaid
flowchart LR
    A[DCI Bits] --> B[Polar Encode]
    B --> C[Rate Match]
    C --> D[PDCCH Mapping to REG / CCE / CORESET]
    D --> E[DMRS Insert]
    E --> F[OFDM Modulate]
    F --> G[Blind Decode / Prior-Aided Candidate]
    G --> H[DCI Validation / Detection Feedback]
```

Primary parameters:

- `control.search_space_type`
- `control.aggregation_levels`
- `control.dci_formats`
- `control.blind_decode_candidates`
- `control.coreset_duration`
- `control.coreset_frequency_resources`
- repetition, higher-AL, multi-stage, and prior-aided candidate fields

## Tracking RS Chain

```mermaid
flowchart LR
    A[TRS / PTRS / Tracking RS] --> B[Time-Frequency Tracking]
    B --> C[CFO / Phase / Timing Drift Compensation]
    C --> D[Residual Error Metrics]
```

Primary parameters:

- `reference_signals.trs_enabled`
- `reference_signals.tracking_rs_enabled`
- `reference_signals.ptrs_enabled`
- `impairments.cfo_hz`
- oscillator drift and initial-acquisition packs

## Beam Management Chain

```mermaid
flowchart LR
    A[Beam Codebook / Panel Set] --> B[Beam Sweep]
    B --> C[Measurement Collection]
    C --> D[Beam Score / Candidate Ranking]
    D --> E[Selected Beam / Panel / TRP]
    E --> F[Optional AI Prediction]
```

Primary parameters:

- `mimo.n_tx_ant`, `mimo.n_rx_ant`, `mimo.n_layers`
- `mimo.precoder_type`
- `mimo.beam_sweep_enabled`
- `mimo.beam_count`
- `mimo.panel_count`
- `mimo.multi_panel_ready`
- `mimo.trp_count`
- `mimo.precoding_granularity`
- `ai_ml.use_case=beam_prediction`

## HARQ Chain

```mermaid
flowchart LR
    A[Tx Attempt] --> B[CRC Outcome]
    B --> C[ACK / NACK / DTX Model]
    C --> D[RV Selection]
    D --> E[Soft Combining]
    E --> F[Stop Condition]
    F --> G[Latency / Reliability / Energy Metrics]
```

Primary parameters:

- `harq.enabled`
- `harq.process_count`
- `harq.rv_sequence`
- `harq.feedback_timing_slots`
- `harq.combining_mode`
- `harq.cbg_enabled`
- feedback-efficiency and PDCCH-miss-related behavior fields

## AI/ML Hooks

```mermaid
flowchart LR
    A[Classical PHY Path] --> B[AI Hook Decision]
    B --> C1[AI Demod]
    B --> C2[AI CSI Compression]
    B --> C3[AI Beam Prediction]
    B --> C4[AI Channel Estimation]
    B --> C5[AI IA / RACH]
    C1 --> D[Fallback-to-Non-AI Check]
    C2 --> D
    C3 --> D
    C4 --> D
    C5 --> D
```

Primary parameters:

- `ai_ml.enabled`
- `ai_ml.use_case`
- `ai_ml.mode`
- `ai_ml.model_id`
- `ai_ml.model_version`
- `ai_ml.model_path`
- `ai_ml.fallback_to_non_ai_enabled`
- `ai_ml.download_mode`
- `ai_ml.benchmark_observations`

## Energy / Complexity Instrumentation Chain

```mermaid
flowchart LR
    A[Scenario Config] --> B[Per-Block Processing Counters]
    A --> C[RF-Chain Counters]
    A --> D[Sleep / Active State Tracking]
    B --> E[UE Energy]
    C --> F[NW Energy]
    D --> G[Duty-Cycle and Race-to-Sleep Metrics]
    E --> H[Energy Report]
    F --> H
    G --> H
```

Primary parameters:

- `energy_efficiency.tx_power_dbm`
- per-block processing energy controls
- RF-chain energy controls
- bandwidth adaptation controls
- PDCCH monitoring adaptation
- blind-decoding reduction
- active/sleep duty-cycle tracking
- wideband vs narrowband trade-off controls

## Parameter Ownership Summary

| Chain | Primary Sections |
|---|---|
| DL Tx | `coding`, `modulation`, `mimo`, `reference_signals`, `waveform`, `impairments` |
| DL Rx | `reference_signals`, `channels`, `impairments`, `ai_ml`, `kpis` |
| UL Tx | `waveform`, `modulation`, `coding`, `reference_signals`, `mimo`, `energy_efficiency` |
| UL Rx | `reference_signals`, `channels`, `impairments`, `ai_ml`, `harq` |
| Initial access | `reference_signals`, `random_access`, `mimo`, `ai_ml` |
| CSI | `reference_signals`, `mimo`, `csi_acquisition_and_reporting`, `ai_ml`, `kpis` |
| Control | `control`, `reference_signals`, `coding`, `harq` |
| Tracking RS | `reference_signals`, `impairments`, `channels` |
| Beam management | `mimo`, `reference_signals`, `ai_ml`, `channels` |
| HARQ | `harq`, `control`, `coding`, `kpis` |
| AI/ML hooks | `ai_ml`, `kpis`, `logging` |
| Energy instrumentation | `energy_efficiency`, `kpis`, `logging` |
