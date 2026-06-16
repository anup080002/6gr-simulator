# DL PDSCH/DL-SCH Receiver Evidence And Raw BLER/BER Gate

This page documents the AUD-PDSCH-001 closure scope. It is NR baseline/study
behavior for the implemented simulator profile, not a normative 6G conformance
claim.

## Implemented Profile

- `PDSCH_Tx` generates waveform-backed DL-SCH/PDSCH trials using transport-block
  CRC, LDPC code-block segmentation, rate matching, scrambling/modulation, layer
  mapping, PDSCH DM-RS, optional configured precoding, and OFDM mapping.
- `PDSCH_Rx` demodulates the received waveform/grid, estimates the channel from
  PDSCH DM-RS or an explicitly flat AWGN validation path, extracts/equalizes
  PDSCH REs, demodulates LLRs using receiver noise variance, rate-recovers and
  LDPC-decodes DL-SCH, checks the TB CRC, and emits row-level receiver evidence.
- Strict receiver evidence is accepted only when channel estimation, resource
  extraction, equalization, DL-SCH decode, finite LLRs, and receiver-derived
  post-equalization SINR are all present.

## Raw Objective Gate

`+sixgr/+truth/evaluatePDSCHObjectiveStrict.m` is the objective authority.

- Raw BLER = `TBCrcFailCount / (TBCrcPassCount + TBCrcFailCount)`.
- Weighted raw BER = `sum(BitErrors) / sum(BitsCompared)`.
- Strict runs fail if raw BLER/BER exceed configured thresholds, or default
  strict thresholds when none are supplied.
- Strict runs fail if CRC evidence, BER denominators, receiver evidence, or
  no-proxy evidence are missing.
- Fixed-anchor runs fail when configured MCS, modulation, layers, or rank do not
  match effective raw trial rows.

## Artifacts

- `air_interface/csv/dl_pdsch_trials.csv`
- `air_interface/csv/dl_pdsch_receiver_evidence_audit.csv`
- `reports/csv/dl_pdsch_raw_bler_ber_objective.csv`
- `reports/csv/dl_pdsch_objective_failures.csv`
- `reports/csv/dl_pdsch_objective_artifact_schema.csv`
- `reports/json/dl_pdsch_toolbox_capabilities.json`

## Dependency Rules

- Strict scheduled DL requires decoded PDCCH grant references. If the scenario
  uses configured/test-vector grants, it must not claim scheduled-control DL
  conformance.
- Layers/rank greater than one require runtime MIMO/precoder/rank evidence.
- Non-AWGN or RF-impaired objectives require Channel/RF reference evidence.
- HARQ fields may be exported, but this fix does not claim full MAC/HARQ timing,
  K0/K1/K2, ACK/NACK, RV/NDI, retransmission, or soft-combining conformance.

## Tests

Focused tests:

```matlab
setup6GRSimToolkit('Verbose',false);
testDLPDSCHReceiverEvidenceGate;
testDLPDSCHRawBLERBERObjectiveGate;
testDLPDSCHArtifactSchemas;
```

Regression tests also run for this patch:

```matlab
testPDSCHSISORegression;
testPDSCHMultiPortPrecoding;
testLLS_DL;
testLinkExportPipeline;
testLLSRuntimeTruthContractGates;
testLLSStrictConformanceIssueGates;
testStrictProxyGuards;
testStrictMode_NoFallbackAnywhere;
testSchedulerGrantConsistency;
testLLSEffectiveOperatingPointSummary;
testKPIArtifactSchemas;
testLLSSummaryRawConsistency;
```

`testPDSCH6GR` remains a broader study-suite regression. In this patch pass it
was attempted separately but exceeded the 5-minute targeted-test timeout, so it
is not used as closure evidence here.

## Known Limitations

- DCI grant types and scheduled-control DL remain dependent on PDCCH evidence.
- Advanced PT-RS, reserved-resource/rate-match cases, high-rank multi-codeword
  modes, FR2 phase-noise cases, and Rel-17/18/19/20 extensions are not claimed.
- Broad production Channel/RF lineage still depends on the Channel/RF issue row.
- Full MAC/HARQ procedure behavior remains tracked separately.
