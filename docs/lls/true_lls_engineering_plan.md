# True LLS Engineering Plan

This plan is for rebuilding the scenario path as a measured PHY/MAC execution path, not a report-labeling exercise.

## Ground Rules

- Measurement columns in CSV outputs must contain measured values only.
- If a measurement was not produced, leave the measurement field blank/NaN.
- Do not make pass/fail depend on "available", "unavailable", "truth", or other label text.
- Keep any provenance text secondary to the measured numeric and boolean evidence.
- Validate math, physics, algorithms, and call flow against 3GPP NR specifications before changing each block.

## 3GPP Reference Set

- TS 38.211: physical channels, modulation, resource grids, OFDM, DMRS, PDSCH, PUSCH, PDCCH, PBCH, PRACH.
- TS 38.212: channel coding, CRC, code block segmentation, LDPC/polar coding, rate matching, scrambling.
- TS 38.213: physical layer procedures for control, search spaces, CORESET, PUCCH, PRACH procedures and timing.
- TS 38.214: physical layer procedures for data, MCS, TBS, HARQ, CSI, link adaptation.
- TS 38.321: MAC scheduling, HARQ process behavior, random access procedure.
- TS 38.331: RRC/SIB1 configuration ownership where broadcast and random access parameters enter the system.

Primary archive: `https://www.3gpp.org/ftp/Specs/archive/38_series/`

## Phase 1: Data Grant Waveform Replay

Goal: one scheduled grant must execute through real TX, channel, OFDM demodulation, channel estimation, equalization, demodulation, rate recovery, LDPC decode, CRC.

Files:
- `+sixgr/+system/+waveform/replayGrant.m`
- `+sixgr/+system/WaveformPHY.m`
- `+sixgr/+phy/+dl/PDSCH_Tx.m`
- `+sixgr/+phy/+dl/PDSCH_Rx.m`
- `+sixgr/+phy/+ul/PUSCH_Tx.m`
- `+sixgr/+phy/+ul/PUSCH_Rx.m`
- `+sixgr/+truth/exportSystemLevelCanonicalArtifacts.m`

Acceptance:
- `dl_pdsch_trials.csv` and `ul_pusch_trials.csv` contain measured `PostEqSINR_dB`, `DecoderIterations`, `CRCPass`, timing estimate when estimated, and blank CFO when CFO is not estimated.
- No system-level SINR budget is copied into receiver measurement columns.
- No EVM proxy is promoted into a decoder-truth or measured SINR column.

Current status:
- Focused replay evidence test now passes for measured receiver evidence.

## Phase 2: Broadcast, SSB, PBCH, MIB, SIB1

Goal: UE initial synchronization and SI acquisition must come from waveform execution.

Files:
- `+sixgr/+link/runCellSearch_MIB_SIB1.m`
- `+sixgr/+phy/+broadcast/*`
- `+sixgr/+l3/+rrc/SystemInformation.m`
- `+sixgr/+truth/exportSystemLevelCanonicalArtifacts.m`

3GPP anchors:
- 38.211 SSB/PBCH mapping and DMRS
- 38.212 PBCH coding and scrambling
- 38.213 initial access/control procedure timing
- 38.331 MIB/SIB1 payload ownership

Acceptance:
- `pbch_trials.csv`, `pbch_recovery_trials.csv`, and `sib1_recovery_trials.csv` contain decoded bits, CRC/pass result, timing/frequency metrics when measured, and no oracle fields.
- SIB1 PRACH configuration used by RACH comes from decoded/configured SI ownership, not hardcoded scenario logic.

## Phase 3: PRACH and RACH

Goal: Msg1 preamble generation, channel propagation, detection, RAR scheduling, Msg3 PUSCH, Msg4 contention resolution.

Files:
- `+sixgr/+link/runPRACHDetection.m`
- `+sixgr/+phy/+prach/*`
- `+sixgr/+phy/+ra/*`
- `+sixgr/+l3/+rrc/RACHProcedure.m`
- `+sixgr/+l3/+rrc/AttachProcedure.m`

3GPP anchors:
- 38.211 PRACH formats, sequences, occasions
- 38.213 random access physical procedures
- 38.321 MAC random access procedure

Acceptance:
- `prach_trials.csv` contains measured correlation peak, threshold, detected preamble, false alarm/miss state, timing estimate, and received power.
- RAR/Msg3/Msg4 rows are tied to actual RACH state transitions.

## Phase 4: DL/UL Control

Goal: PDCCH/PUCCH control must be either real waveform blocks or blank, never implied as decoded only because a scheduler grant exists.

Files:
- `+sixgr/+ctrl/*`
- `+sixgr/+phy/+ul/PUCCH_Rx.m`
- `+sixgr/+truth/exportControlPlaneTraces.m`
- `+sixgr/+truth/exportSystemLevelCanonicalArtifacts.m`

3GPP anchors:
- 38.211 PDCCH/PUCCH resources and DMRS
- 38.212 DCI/UCI coding
- 38.213 CORESET, search space, HARQ feedback timing

Acceptance:
- `pdcch_trials.csv` contains blind decode attempts, candidate identity, DCI CRC result, aggregation level, CCE/REG mapping.
- `pucch_trials.csv` contains actual UCI bits, HARQ ACK/NACK, decoding result, and resource mapping.

## Phase 5: MAC Scheduling and Link Adaptation

Goal: scheduler decisions must use measured CSI/CQI/RI/PMI/HARQ state, not configured SNR or synthetic fallback.

Files:
- `+sixgr/+l2/+mac/SchedulerBase.m`
- `+sixgr/+l2/+mac/SchedulerPF.m`
- `+sixgr/+link/computeLinkAdaptationDecision.m`
- `+sixgr/+link/resolveMCSFromCQI.m`
- `+sixgr/+system/SystemLevelRunner.m`

3GPP anchors:
- 38.214 MCS, TBS, CSI, HARQ data procedures
- 38.321 MAC scheduling and HARQ processes

Acceptance:
- Scheduler grant rows carry real PRB set, symbols, MCS, TBS, HARQ ID, RV, NDI.
- TBS comes from allocation math or actual transport block size.
- CQI/MCS changes follow measured receiver feedback.

## Phase 6: Channel, Impairments, Antenna, Deployment

Goal: the air interface must propagate actual waveforms through configured pathloss, fading, Doppler, antenna dimensions, beamforming, interference, CFO/timing/IQ/phase-noise impairments.

Files:
- `+sixgr/+channel/*`
- `+sixgr/+scenario/generateLayout.m`
- `+sixgr/+system/buildLargeScaleStateCache.m`
- `+sixgr/+link/applyWaveformTruthImpairments.m`
- `+sixgr/+link/synthesizeInterferenceWaveform.m`
- `+sixgr/+phy/+rx/channelEstimate.m`

3GPP anchors:
- 38.211 waveform/reference signal structure
- 38.901 channel model, pathloss, fading, antenna assumptions

Acceptance:
- Fading channels use per-resource channel estimates.
- Interferers are actual waveform/channel contributors where enabled.
- CFO/timing columns are populated only when impairment is injected and/or estimated.

## Phase 7: Output Generation

Goal: output tables should be measured artifacts, not contract-padding artifacts.

Files:
- `+sixgr/+truth/exportSystemLevelCanonicalArtifacts.m`
- `+sixgr/+truth/exportLLSLiveSignalChainTables.m`
- `+sixgr/+truth/exportLLSOutputCoverageArtifacts.m`
- `+sixgr/+report/OrganizeRunResults.m`

Acceptance:
- Primary CSVs contain rows only from executed runtime blocks.
- Measurement fields contain values only when measured.
- Missing measurements stay blank/NaN.
- Summary tables aggregate measured raw rows only.

## Immediate Next Step

Run the provided mobile 2-UE scenario after Phase 1 and compare:

- DL/UL CRC pass counts
- finite `PostEqSINR_dB`
- finite `DecoderIterations`
- finite timing estimates where timing is estimated
- CFO blank unless CFO is actually injected and estimated
- configured vs effective MCS/layer/rank behavior

The next fix should be selected from the first physical failure in that rerun, not from report labels.
