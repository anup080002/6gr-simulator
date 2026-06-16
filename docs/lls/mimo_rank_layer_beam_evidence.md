# MIMO Rank, Layer, and Beam Evidence

This document describes the implemented `AUD-MIMO-RANK-001` closure scope. It is
NR baseline/study behavior for this simulator, not a claim of normative 6G
conformance.

## Implemented Scope

The MIMO evidence exporter separates configuration intent from runtime evidence:

- Physical antenna counts, RF chains, antenna ports, and DM-RS ports come from
  the resolved scenario/config surfaces and are validated fail-closed.
- Scheduled and transmitted rank/layers are read from raw DL PDSCH and UL PUSCH
  trial rows.
- Receiver-estimated rank is derived from receiver rank fields or from finite
  per-layer receiver metrics.
- Effective decoded rank/layers are populated only for CRC/decode/receiver-usable
  rows with finite per-layer post-equalization evidence.
- Fixed-anchor scenarios fail when rank/layers, modulation, or MCS collapse
  below the configured objective.
- Multi-layer rows require PMI/precoder lineage and beam-source lineage before
  top-level MIMO strict evidence can pass.

Nominal capability is never counted as effective waveform rank. If raw trial rows
are missing, the configured-vs-effective summary fails instead of copying
configured values into effective fields.

## Runtime Artifacts

The link KPI export writes these artifacts for every raw-trial-backed export:

- `beamforming/csv/mimo_config_strict.csv`
- `beamforming/csv/mimo_config_validation.csv`
- `beamforming/csv/antenna_array_config.csv`
- `beamforming/csv/antenna_port_mapping.csv`
- `beamforming/csv/rank_layer_trials.csv`
- `beamforming/csv/mimo_layer_metrics.csv`
- `beamforming/csv/mimo_configured_vs_effective.csv`
- `beamforming/csv/precoder_evidence.csv`
- `beamforming/csv/beam_codebook.csv`
- `beamforming/csv/beam_sweep_measurements.csv`
- `beamforming/csv/mimo_negative_trials.csv`
- `beamforming/csv/mimo_oracle_guard.csv`
- `reports/csv/mimo_rank_utilization_table.csv`
- `reports/json/mimo_toolbox_capabilities.json`

Each rank/layer trial row carries a source artifact reference and source-row hash
for the raw DL/UL trial table used to reconstruct the evidence.

## Fixed-Anchor No-Collapse Rule

For a strict fixed-anchor objective, a row counts as strict MIMO success only
when all of these agree with the configured objective:

- Scheduled rank/layers.
- Transmitted rank/layers.
- Effective decoded rank/layers.
- Effective decoded modulation.
- Effective decoded MCS.

A rank-2/layers-2/256QAM/MCS20 anchor cannot pass with rank-1, one-layer, QPSK,
or lower-MCS effective evidence. Missing per-layer receiver evidence also fails;
it is not repaired using nominal labels.

## Validation Tests

Focused regression tests:

- `testMIMOConfigStrictValidation`
- `testMIMONominalVsEffectiveRankEvidence`
- `testMIMOFixedRank2AnchorNoCollapse`
- `testULRankEvidenceNoFalse4TxClaim`
- `testMIMOPrecoderEvidence`
- `testMIMOBeamCodebookAndSweep`
- `testMIMOConfiguredVsEffectiveSummary`
- `testMIMOOracleGuard`
- `testMIMOArtifactSchemas`

Related integration checks:

- `testPDSCHMultiPortPrecoding`
- `testLLSEffectiveOperatingPointSummary`
- `testLLSRuntimeTruthContractGates`
- `testLLSStrictConformanceIssueGates`
- `testLinkExportPipeline`
- `testKPIArtifactSchemas`

## Known Limitations

The closure is intentionally narrow. These modes remain unsupported unless a
future patch adds equivalent runtime evidence, artifacts, and tests:

- Type-II and multi-panel CSI codebooks.
- MU-MIMO and CoMP/multi-TRP.
- FR2 hybrid analog/digital beamforming.
- Polarization and XPR modeling.
- High-rank UL profiles beyond implemented raw PUSCH trial evidence.
- Exhaustive high-rank PDSCH waveform-negative matrices.
- Full per-trial ChannelRealizationId/RFImpairmentChainId lineage for every
  production PDSCH/PUSCH row.

Unsupported modes must fail closed or remain outside the strict scenario
objective. They must not be represented as successful MIMO truth evidence.
