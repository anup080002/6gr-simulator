# Four-layer AWGN throughput integration boundary

The latest request replaces the interrupted 64-gNB/4-UE CDL experiment with
a 4x4 AWGN benchmark: 400 MHz, target rate 0.9, full buffer, perfect channel
knowledge, LDPC BG1, HARQ enabled and RF impairments disabled. The subsequent
user request replaces fixed rank/modulation and OLLA-off with ILLA/OLLA
selection among 1024-QAM/rank 2, 1024-QAM/rank 4 and 256-QAM/rank 4.
The requested PDSCH goodput target is greater than
6 Gbit/s. No final run is authorized by a component-test result.

## Configuration choices still awaiting confirmation

- Fs 491.52 MHz and FFT 4096 imply SCS 120 kHz, not the requested 128 kHz.
- With the existing 264-PRB allocation and two full-symbol DMRS reservations,
  each four-layer DL slot has 1,520,640 coded bits. Multiplication by target
  rate 0.9 gives a nominal payload budget of 1,368,576 bits, before TBS
  quantization, CRC/control overhead and retransmissions.
- The old three-DL/four-UL/one-mixed pattern permits about 4.11 Gbit/s DL
  payload budget over the complete clock. The proposed five-DL/two-UL/one-
  mixed pattern gives about 6.84 Gbit/s before additional overhead and errors.
  Changing the pattern trades UL airtime for DL airtime; it is not yet applied.
- HARQ feedback fidelity was confirmed by the user: ideal error-free delayed
  feedback for this AWGN link benchmark. It must never be described as an
  executed physical control channel.

## Exact implementation boundaries

1. `+sixgr/+phy/+research/SharedChannelLink.m` previously always called
   `nrChannelEstimate` for channel and noise. It now has a catalog-controlled
   `perfect_identity_awgn` channel-knowledge option, retaining received-DMRS
   noise estimation. The channel is derived only from the installed identity
   channel/precoder. Fading, path loss, and enabled RF impairments are rejected.
   BG1 is checked against the existing authoritative coding-layout selection;
   it is not forced onto incompatible TBs. Default DMRS reception is preserved.
2. The adapter now accepts HARQ only with the explicit ideal-delayed policy
   and a scheduled TB/process-epoch identity. It retains received mother-code
   observations and validates both their identity and coding compatibility
   before combining another RV. Unconfigured HARQ remains rejected.
3. `+sixgr/+phy/+harq/combineSoftLLR.m` already implements position-aware
   combining. Reuse it; do not simply add rate-matched LLR vectors from
   different RVs. Its returned validity/reset information must be checked.
4. `+sixgr/+l2/+mac/HARQEntity.m` already exposes allocation, pending
   retransmission, transmitted-TB retention, feedback application and a
   delivery ledger. `+sixgr/+phy/+research/IdealDelayedHARQ.m` now binds these
   to the research slot clock, process count, RV sequence, retransmission
   limits and feedback availability. Receiver buffers are retained separately
   from transmitted TBs. This new adapter is under focused qualification.
5. `+sixgr/+lls6g/+runners/runResearchTDD.m` now schedules either new data or
   the retained TB when HARQ is enabled, exports attempt and TB identity
   separately, and counts delivered TBs through the existing first-success
   ledger. Waiting, UL, mixed/guard, retransmission and feedback-drain time
   remain in the denominator. The configured final drain delivers feedback
   only; unresolved retransmissions remain explicitly pending and prevent
   an all-TBs-success acceptance claim.
6. YAML catalogs, manifests and trial exports must identify perfect versus
   DMRS CSI, noise authority, BG, HARQ feedback mode, attempts and delivery
   status. Keysight IQ must correspond to actual transmitted/received samples.

## Focused verification

`testResearchPerfectAWGNReceiver` tests full-width four-layer BG1 coding with
perfect identity CSI at 40 dB, retains separate 30 dB observations, checks
legacy DMRS reception, and rejects fading/CFO/perfect-CSI conflicts. It does
not enable HARQ or establish integrated TDD goodput. Its log is
`logs/research_perfect_awgn_20260917/component.log`.

The initial HARQ stress test (0 dB first attempt, 40 dB retransmission) failed
its two-attempt recovery assertion. That log is retained, not relabeled as a
pass. The expanded configured-RV-sequence test also exposed a missing caller
TB-identity guard, which was added to the research adapter (not the shared
combiner). Subsequent qualification must still prove exact payload recovery.

HARQ verification must cover RV-dependent position mapping,
NACK/retransmission/ACK timing, duplicate delivery prevention, process reuse,
stale feedback rejection, exhausted attempts and final pending processes.
Then execute the agreed scenario and audit actual TB goodput and IQ artifacts.
`testAll` remains stopped by explicit user instruction; no unrelated fixes
are part of this work.

## Adaptive rank/modulation implementation

- `SharedChannelLink.m`: optional `research_awgn_mimo` separates the fixed
  physical identity-channel dimensions from active layers. The rectangular
  layer-to-port precoder has squared Frobenius norm one at both ranks. The
  perfect channel has receive-port by layer dimensions, not layer by layer.
- `runResearchTDD.m`: fixed YAML noise-reference EPRE is independent of rank;
  total expected transmit data-RE power remains one. Actual power/noise is
  exported separately from the configured reference. Inactive physical ports
  remain present, and receive independent AWGN.
- `IdealDelayedHARQ.m`: stores each initial TB's full allocation/configuration
  by process epoch. Later new-data choices cannot change that TB's rank,
  modulation, coding or DMRS. OLLA receives the attempt index along with the
  delayed receiver CRC. An ILLA outage blocks new TBs but not pending retx.
- `AWGNLinkAdaptation.m`: inner-loop selection uses delayed receiver DMRS
  noise, the explicitly known identity channel, actual candidate `nrTBS`, and
  waveform-calibrated per-candidate thresholds. It does not consume the
  configured SNR or transmitter-reference EVM. The existing `OLLAState`
  implements the outer loop; only initial-attempt CRC feedback updates it,
  once per TB. The provisional YAML target is 10% first-transmission BLER,
  ACK step 0.05 dB and NACK step 0.45 dB; this is configurable.
- `calibrateAWGNAdaptation.m`: generates independent actual RV0 TBs and
  received waveforms for every direction/candidate/SNR point. A candidate
  point is eligible only when its one-sided exact binomial BLER upper bound
  is at or below the target with the configured sample count/confidence.
  Thresholds are implementation-specific predictions, not universal 3GPP
  values or measured campaign KPIs. The confidence gate is pointwise, not a
  simultaneous or holdout qualification of the complete adaptive controller.
- Calibration binds to the allocation, receiver, physical ports, frequency,
  waveform, impairments, MATLAB version and codec hash. Rows are first bound
  to the saved executed calibration input; compatibility then compares active
  PHY settings, not inactive aliases added during front-door YAML reload.
  Eight-PRB component calibration is
  rejected for the full 264-PRB allocation. Missing/incompatible calibration
  fails closed. Stale measurements or no eligible candidate produce an
  explicit new-data outage; no proxy TB/CRC/goodput is inserted.
- The ideal measurement-feedback transport is labeled separately from actual
  coded data. No CSI-RS/SRS/PUCCH waveform or standardized 6G control procedure
  is claimed. Candidate forecasts are in `adaptation/csv`, not primary decoded
  KPI columns. Rank 2 is an available choice, not a rank that must be forced
  into the schedule when another feasible candidate carries more payload.

### Evidence and remaining acceptance boundary

`logs/research_perfect_awgn_20260917/fixed_ports_harq_freeze_schema.log`
ends with `FIXED_PORTS_HARQ_FREEZE_BATCH_PASS`: all three rank/QAM candidates
passed exact coded DL and UL reception at 40 dB with unchanged four-port
noise, HARQ recovered through its configured RV sequence, and changing the
next new-data allocation did not alter retransmissions. The earlier schema
registration failure is preserved in `fixed_ports_harq_freeze.log`.

The new adaptive component test is `testResearchAWGNAdaptation`. Its 8-PRB
calibration and integrated loop are not a full-band/30-dB throughput pass.
The retained calibration contains 180 actual CRC-passing, exact RV0 TBs:
30 trials per candidate per direction at 40 dB. The subsequent 48 dB
integrated component executed 6 DL and 8 UL TBs, all exact, with zero
pending/dropped TBs. It switched from the configured 256-QAM/rank-4
bootstrap to feedback-selected 1024-QAM/rank 4. Rank 2 was independently
decoded in the fixed-port component checks, not forced into that schedule.
The controller test also passed actual low-SNR NACK response, stale-input
outage, retx permission during new-data outage, duplicate feedback rejection,
retransmission exclusion from first-attempt OLLA, and wrong-allocation
calibration rejection. See `adaptation_active_profile.log` in the same log
folder and `results/component_validation/adaptive_20260917_235532_837`.
Earlier constructor-name and inactive-alias fingerprint failures remain
preserved in their original logs; no calibration rows were rewritten.

The complete 264-PRB calibration, final TDD/SCS choice, integrated adaptive
run, goodput/BLER audit and final IQ capture remain separate acceptance work.
No guarantee of >6 Gbit/s or every initial CRC passing follows from enabling
adaptation. Feedback-drain and retransmission airtime stay in the denominator.

The reusable opt-in fragments are
`simulator/configs/mimo/research_identity_4x4.yaml` and
`simulator/configs/coding/research_adaptive_rank_qam.yaml`, together with the
perfect-receiver and ideal-delayed-HARQ fragments. For an approved full
scenario, first run `sixgr.phy.research.calibrateAWGNAdaptation(configPath)`
and then `run_6g_phy_lls_single(configPath,'results',runTag)`; the calibration
path, candidates, target, confidence and episode count all come from YAML.
Do not use the component fixture as a full-band benchmark. Regenerate
calibration when changing the allocation, active receiver settings or MATLAB
version. This work has only been exercised on the installed R2026a, not R2023b.

## Full-width calibration started 18 September

The new full-width candidate YAML is
`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_rank_qam_30db.yaml`.
It retains the existing 120 kHz and 3-DL/4-UL/1-mixed pattern; no final
DL-heavy pattern has been silently selected. Its calibration uses all 264
PRBs, rates 0.9, fixed four physical ports and fixed reference EPRE 0.25.
The three candidate modes execute at 28/30/32 dB in both directions, 30
independent RV0 TBs per combination, for 540 planned trials.

The MATLAB batch was launched at 00:02 IST on 18 September. Logs are in
`logs/research_adaptive_full264_20260918/calibration.log`; exact source and
configuration snapshots plus incrementally written actual trial rows are in
`results/research_adaptation_calibration/full264_20260918`. Completion and
candidate qualification must be checked from those artifacts; launch is not
completion. The batch does not launch the final adaptive IQ campaign.
