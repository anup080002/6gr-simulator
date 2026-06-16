# UL PUSCH Receiver Post-Eq SINR Evidence

This note documents the current NR-baseline UL PUSCH receiver evidence gate. It
is not a normative 6G conformance claim.

## Implemented In This Patch

- `PUSCH_Rx` now reports receiver-stage evidence for DM-RS channel estimation,
  PUSCH resource extraction, equalization, UL-SCH decode, finite LLRs, and
  receiver-derived post-equalization SINR.
- `validatePUSCHReceiverEvidence` rejects strict receiver evidence when post-eq
  SINR is missing, non-finite, proxy/fallback/configured-SNR-like, EVM-derived,
  CQI/MCS-derived, or oracle/perfect-channel-like.
- `runULPUSCHThroughput` exports the gate fields into
  `air_interface/csv/ul_pusch_trials.csv`.
- In strict or no-proxy mode, the UL helper reports `Ok=false` if any PUSCH row
  lacks complete receiver evidence.

## Row-Level Evidence Columns

Required strict receiver evidence is exposed as:

- `StrictReceiverEvidenceOk`, `StrictOk`, `TruthStatus`
- `ChannelEstimateAttempted`, `ChannelEstimateAvailable`, `ChannelEstimateSource`
- `ResourceExtractionAttempted`, `ResourceExtractionAvailable`
- `EqualizationAttempted`, `EqualizationAvailable`
- `ULSCHDecodeAttempted`, `ULSCHDecodeAvailable`
- `LLRAvailable`, `LLRFinite`, `LLRScaleSource`, `LLRNoiseVariance`
- `PostEqSINRWidebanddB`, `PostEqSINRAvailable`, `PostEqSINRReceiverDerived`
- `SINRValidationStatus`, `SINRValidationReason`, `SINRComputationMethod`
- `ConfiguredSNRLikeSourceRejected`

`StrictReceiverEvidenceOk=true` means the measurement chain is complete. It does
not by itself mean the transport block CRC passed; CRC success is still reported
through `CRCPass` and the receiver `StrictOk` field.

## Current Limitations

- The complete AUD-UL-SINR-001 acceptance matrix is not fully closed yet.
- The high-rank/256QAM fixed-anchor positive profile and full configured-vs-
  effective rank/modulation gate still need separate validation.
- The full negative matrix requested in the audit prompt remains open:
  wrong DM-RS, wrong RNTI, wrong grant, wrong MCS/modulation, corrupted data,
  corrupted DM-RS, timing offset, and oracle-guard artifacts.
- UL KPI/goodput summary consistency is tracked separately as
  `AUD-KPI-UL-GOODPUT` and is not fixed by this receiver evidence patch.

## Verified Commands

```matlab
setup6GRSimToolkit('Verbose',false); testULPUSCHReceiverEvidenceGate; testPostEqSINR; testULNoiseVarianceValidation
setup6GRSimToolkit('Verbose',false); testLLS_UL; testLLSSINRFieldTruth; testLLSSINRRuntimeArtifacts
```
