# Execution and evidence map

Paths below are relative to the repository root. Read current implementations;
this map is navigation, not a feature-completeness certificate.

## Configuration and mode

Start at `run_6g_phy_lls_single.m`, `+sixgr/+lls6g/+config/loadScenarioConfig.m`,
`validateScenarioConfig.m` and `+sixgr/+lls6g/buildInternalConfig.m`.
Use `simulator/configs/schema/scenario_parameter_catalog*.yaml`,
`simulator/configs/defaults/`, band/waveform/channel/MIMO fragments and the
resolved YAML/JSON. Enumerate actual keys, defaults, ranges and dependencies
from these sources rather than maintaining another competing parameter list.
Check scalar/vector cardinality after inheritance: a late band pack can
overwrite an eight-resource CSI list with a single-resource default.

Read `+sixgr/+truth/runWaveformLinkBundle.m`, `CoupledTruthRuntime.m`,
`SharedWaveformPhysicalRuntime.m`, `CoupledWaveformStream.m` and
`+sixgr/+phy/+waveform/WaveformObservationBuffer.m` for physical orchestration.
The `+truth` package is production orchestration, not evidence of an oracle:
check which values actually enter the receiver or scheduler.
For SLS use `+sixgr/+system/SystemLevelRunner.m` and locate the current
calibrated-link backend, calibration key/domain guards and causal feedback.
Do not import waveform-LLS acceptance into an abstraction result.

## Review domains

| Domain | Production starting points | Parameters, causal flow and closure evidence |
|---|---|---|
| Carrier/time/grid | `+sixgr/+phy/FrameStructureEngine.m`, `+sixgr/+phy/+frame/SSBTimingResolver.m`, `+sixgr/+phy/+grid/applyRuntimeCarrierTimeline.m` | Band/ARFCN/GSCN, Point A, SCS, FFT, Fs, CP, BWP, absolute slot/sample, symbol-level TDD. Common and SSB SCS can differ. Compare physical time/frequency, not integer symbol indices across numerologies. |
| SSB/PBCH/SIB1 | `+sixgr/+phy/+dl/SSB_Tx.m`, `SSB_Rx.m`, `PBCH_Recovery.m`, `+sixgr/+phy/+broadcast/deriveType0PDCCHFromMIB.m`, `generateSSB_MIB_SIB1_Waveform.m` | PSS/SSS search, CFO/timing acquisition, PBCH CRC/MIB, Type-0 CORESET/search space, SI-RNTI DCI, SIB1 ASN.1. Band and paired/unpaired context must survive every adapter. Active beams differ from Lmax candidates. |
| PRACH/access | `+sixgr/+rach/PRACHConfig.m`, `+sixgr/+phy/+ra/`, `+sixgr/+mac/+ra/RandomAccessProcedure.m` | Real occasions, preamble/root/cyclic shift, RX correlation, detection threshold provenance, RAR RAPID/TA/UL grant, Msg3, contention identity, Msg4 and RRCSetupComplete. Event/processing windows, not arbitrary attach-slot deadlines. |
| PDCCH | `+sixgr/+phy/+pdcch/`, `+sixgr/+phy/+dl/PDCCH_Tx.m`, `PDCCH_Rx.m` | DCI widths, RNTI masks, CCE/REG/AL, DMRS, actual candidate/hypothesis identities, CRC versus semantic acceptance. Count independent no-signal waveforms separately from correlated blind hypotheses. |
| PDSCH | `+sixgr/+phy/+dl/PDSCH_Tx.m`, `PDSCH_Rx.m`, `+sixgr/+phy/+grid/allocREsPDSCH.m` | Exact TBS, TB CRC, segmentation, LDPC, RV/rate matching, scrambling, QAM, layers, precoding, DMRS/PTRS, RE mapping, OFDM; reverse RX with received DMRS estimates, soft bits and CRC. No injected-offset timing estimate. |
| PUSCH | `+sixgr/+phy/+ul/PUSCH_Tx.m`, `PUSCH_Rx.m` | UL codebook/TPMI, legal waveform/rank, UCI-on-PUSCH bit/RE accounting, UL MCS binding, DMRS/PTRS, received TA/CFO state, soft combining and independent decoder outcome. |
| PUCCH/UCI | `+sixgr/+phy/+ul/PUCCH_Tx.m`, `PUCCH_Rx.m`, `+sixgr/+phy/+pucch/` | Format, bits, coding/CRC applicability, HARQ/SR/CSI composition, DTX/miss/false ACK, power, reservations and received feedback delivery. Format-0 sequence detection is not DMRS channel estimation. |
| CSI-RS/CSI | `+sixgr/+phy/+refsig/csirs.m`, `receiveCSIRSWaveform.m`, `+sixgr/+link/prepareCSIRSTransmission.m`, `+sixgr/+phy/+mimo/NRCSIReportEngine.m` | Actual resource IDs, ports, comb/CDM/rows, measurements, codebook search, CRI/RI/PMI/CQI packing, physical UCI decode, causal scheduler consumption and frozen precoder. Receiver recommendation alone is not delivered CSI. |
| SRS/UL feedback | `+sixgr/+phy/+ul/SRS_Tx.m`, `SRS_Rx.m`, `+sixgr/+rf/BeamformingSRSReciprocity.m` | Actual sounded PRBs/ports/comb/symbols, received spatial estimates, age/availability, UL rank/TPMI/MCS and grants. A 104/106-PRB sounding is not literal full-carrier measurement. Single pilot cannot establish phase-rate or Doppler spread. |
| TRS/synchronization | `+sixgr/+link/runTRSTracking.m`, `+sixgr/+phy/+trs/`, `+sixgr/+phy/+sync/` | Period/age, independent pre/post front-end clock, estimates, applied correction and independently estimated residual. Separate scheduler usable, tracking health and simulator-only NMSE qualification. |
| Arrays/codebook/beam | `+sixgr/+rf/AntennaArrayFactory.m`, `+sixgr/+phy/+mimo/TypeISinglePanelCodebook.m`, `CodebookEngine.m`, `MatrixContract.m`, `+sixgr/+rf/BeamRefinementCSIRS.m` | Elements versus polarization dimensions versus TXRUs versus logical ports versus layers; 64 TXRU does not prove 64/192 elements. Matrix dimensions, power conservation, codebook indices/oversampling, real beam sweep, TCI activation and QCL source/time/type. DFT weights alone are not proof of Type-I compliance. |
| Channel/propagation | `+sixgr/+channel/ChannelFactory.m`, `buildMeasuredChannelPathTable.m` | Concrete TDL/CDL profile, delay spread, velocity/max Doppler versus radial frequency shift, arrays/orientation, AoA/AoD/ZoA/ZoD, UMa/UMi/O2I/path loss, fading seed/state and normalization. Shared link path loss differs from relative cluster gain. |
| RF/power | `+sixgr/+rf/PowerContext.m`, `resolveSSBPowerContract.m`, `resolveDACAmplitudeReference.m`, `applyRFImpairmentChain.m`, `PhaseNoiseModel.m` | Absolute W/dBm or normalized RE reference; analog/digital planes, DAC/ADC range, clipping, PA backoff, IQ imbalance, CFO, phase noise CPE/ICI and PTRS compensation. Raw PA backoff error is not gain-normalized modulation EVM. |
| Scheduler/LA | `+sixgr/+l2/+mac/SchedulerPF.m`, `SchedulerBase.m`, `UEEligibilityEngine.m`, `+sixgr/+link/computeLinkAdaptationDecision.m` | Traffic/queues, independent DL/UL gates, legal K0/K1/K2/symbol/processing options, exact grant/TBS, CSI/SRS authority, ILLA and OLLA units. PF/smoothing/confirmation policy is not mandated by NR. Rank 4 is a capability, not an outcome requirement. |
| HARQ/MAC | `+sixgr/+l2/+mac/HARQEntity.m`, `HARQProcess.m`, `SoftBufferLedger.m`, `MACPDUAssembler.m`, `BSRStateMachine.m`, `PHRStateMachine.m` | Same original TB, NDI/RV/process identity, actual soft-buffer contributions, received ACK/NACK/DTX, stop after CRC success, unresolved/censored tails, exact control reservations and queue conservation. Selective CBG requires actual group retransmission and feedback, not TB-equivalent CBG counters. |
| RLC/PDCP/SDAP | `+sixgr/+l2/+rlc18/`, `+sixgr/+l2/+pdcp18/`, `+sixgr/+l2/+sdap18/` | Locate consumers of each entity; test PDU codecs, segmentation/reassembly, SN/COUNT, reordering, AM status/retransmission, discard/poll timers, bearer/QFI mapping and security. Parallel older packages require explicit runtime ownership. |
| RRC/L3/NAS | `+sixgr/+rrc/+asn1/`, `+sixgr/+mac/+ra/receivedRRCSetup.m`, `buildRRCSetupComplete.m`, `+sixgr/+protocol/` | Actual ASN.1 decode/config installation, UE/RNTI lifecycle, timers, measurement/reconfiguration/BWP/mobility. Find the actual state owner and configured subset. RRC-connected does not prove NAS registration, PDU session or complete L3. |
| Exports/WebGUI | `+sixgr/+truth/runWaveformLinkBundle.m`, `+sixgr/+lls6g/+runners/runSingle.m`, `apps/lls_radio_measurement_plots.py`, `apps/lls_waveform_quality.py`, `apps/lls_web_dashboard.py` | Trial identity, producer availability, unit/reference plane, correct TX versus RX hash, nonempty CSV data, plotted-CSV identity, all sweep points in joint series, image validity, atomic state refresh and final receipt. Do not fix missing producers only in the UI. |
| Energy/complexity | `+sixgr/+rf/EnergyModelBS.m`, `EnergyModelUE.m`, `+sixgr/+truth/integrateLLSEndpointEnergy.m` | Executed time/resource intervals, non-overlapping endpoint states, declared hardware assumptions, joule/bit denominators, profiler wall-clock versus simulated time. No sleep savings from an always-awake baseline. |

## Known protocol boundaries to inspect explicitly

Inspect the current versions of `+sixgr/+mac/+ra/buildMsg3Payload.m`,
`+sixgr/+mac/+ra/buildMsg4ContentionResolution.m`,
`+sixgr/+mac/+ra/buildRRCSetupComplete.m` and
`+sixgr/+mac/+ra/receivedRRCSetup.m`. The reviewed implementation uses bounded
tagged payloads for these messages and records `MACRRCStandardsQualified=false`.
Actual physical decoding of those bytes does not establish release-pinned
NR ASN.1/MAC interoperability. Do not assume other ASN.1 codecs in the repository
are used by this particular procedure; trace the actual call chain.

Also inspect `+sixgr/+mac/+ra/RAConfig.m` and
`+sixgr/+phy/+ra/generateRRCSetupCompleteWaveform.m`: the reviewed SetupComplete
path takes its allocation from `random_access.setup_complete_pusch` rather
than demonstrating newly decoded authorization for that allocation. Distinguish
preconfigured procedure context from received-control-driven scheduling.
Full protocol qualification requires matching codecs, decoded configuration,
actual SRB/RLC/PDCP state flow and negative procedure/timer tests. Recheck these
boundaries after production changes; do not keep an obsolete limitation label.

Use TS 38.306 with TS 38.331 to distinguish the UE's advertised capability,
configured feature set and actually executed behavior. A YAML maximum rank or
antenna count alone establishes none of the capability-exchange procedure.

## Core arithmetic and experiments

- Slot duration is `1e-3 / 2^mu` seconds; normal CP has 14 symbols. Sum actual
  CP+FFT symbol lengths at the executed Fs. Distinguish slot zero/one origins,
  resource time, capture start/end, available time and publication wall time.
- `G` comes from actual modulation/layer/data-RE accounting; TBS follows the
  applicable 38.214 quantization with its specified RE cap, overhead, MCS and
  codeword rules. Do not substitute offered bytes or an uncapped RE product.
- Verify `y = H W x + i + n` dimensions and normalization at each interface.
  Pilot estimates on fading channels must retain resource dependence.
  Preserve total transmit power across rank/beam changes under the declared policy.
- For pilot EVM, retain reference and compared complex values, alignment,
  equalization and any fitted gain/phase. For NMSE retain the independently
  scored reference, estimated plane and compared indices. Decision-directed
  EVM, transmitted digital EVM and receiver EVM are different measurements.
- For SINR, identify signal/interference/noise planes and per-layer/post-
  equalizer averaging. Configured Es/N0 need not equal measured SINR in fading.
  Normalized dB is not dBm without an absolute calibration plane.
- Require independent realizations, retained errors/trials, confidence method,
  stopping/censoring rules and first-TX versus conditional-retry populations.
  Calibrated SLS must match waveform/rank/MCS/channel/RF keys and avoid extrapolation.

## Acceptance checks

Begin with the smallest failing reproducer and production path. Then test
affected bandwidth/SCS/rank/duplex boundaries and negative cases. Use native
MATLAB reference functions or independently implemented arithmetic where
appropriate, noting shared dependencies rather than claiming independence.
Compare configured values to applied runtime objects, not two copies of YAML.
For report changes exercise the producer, serializer, plot consumer and UI.
For checkpoint changes prove state/RNG/HARQ/channel continuation equivalence.
Do not create or resume checkpoints when the selected run disables them.

Deliver findings with exact paths/functions and source clauses, not an
unqualified promise that every future scenario passes. Missing full-band,
physical-control, statistical or final-publication evidence remains explicit.
