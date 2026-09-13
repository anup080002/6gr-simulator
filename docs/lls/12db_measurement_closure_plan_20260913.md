# 12 dB baseline: pending issues, acceptance and consolidation plan

Current follow-up: [main integration status](main_integration_status_20260913.md).
Main now contains both saved branch histories; the three recent candidate
patches are applied. The received-event shared-clock handoff is implemented,
but its PUCCH/PUSCH consumer and independent gNB mapping remain open.
The status below records the original plan, not an integrated-run pass.

## Status and scope

Requested on 2026-09-13. Source inspected: development `630be334`, main
`b03aed95`, receiver checkpoint `8fba90cc`. Both other branch tips are
ancestors of development. All three worktrees were clean before this plan.
The saved edits are present; the final baseline is **not qualified**.
Follow-up: [received HARQ event handoff and stale-capture isolation](received_harq_event_handoff_20260913.md)
adds a tested received-DCI/private-UE-state event boundary and fresh actual
captures. It exposes pre-calendar-fix replay fixtures and missing testAll
coverage; fixture/registry migration and shared feedback integration remain
pending. The development 12-test guard batch has now completed with exit 0;
its full testAll is running, not merely queued.
This document supersedes old *current-status* statements about blocked
source editing and unapplied CSI/Type-2 consumer patches, not their historical
failure evidence. Those three old companion patches were applied in `8cfac549`.

Baseline authority:
`simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml`.
It inherits the short and TDD profiles: 58 slots, 5 MHz, 15 kHz SCS,
CDL-A, two UL sounding/transmit ports, rank one, actual access and connected
DL/UL, shared physical clock, dynamic Type-2 HARQ, CSI/SRS/TRS and continuous IQ.
The 58 slots are a bounded integration diagnostic, not sufficient by themselves
for statistically qualified BLER curves or broad device conformance.

The current parent explicitly sets `standalone_awgn_snr_argument`, `snr_db: 12`
and a fixed pre-equalization unit-energy occupied-RE reference. It disables
pathloss/shadowing, external interference, CFO, phase noise, IQ imbalance and
ADC quantization. It preserves CDL fading, normalization declarations and
antenna processing. Do not call this an all-impairments run. Qualify that
separately after the controlled baseline; do not silently change this profile.

## Priority and exit gates

All entries below remain open unless their bounded completed scope is stated.
Presence of a helper, passing fixture or exported column is not main-run closure.

| ID | Pending issue / existing evidence | Required repair or verification; exit evidence |
| --- | --- | --- |
| B01 | Sweep configuration drift. The existing eight-point sweep inherits the older short profile, not the current continuous-IQ/two-port/connected-DCI profile. | Inherit the exact baseline; include `[-30,-20,-10,0,10,12,20,30,40]` in both authored sweep arrays. Verify resolved aliases, independent per-point access/HARQ/channel state and unchanged PHY settings. Pending patch accompanies this plan; runtime YAML is not yet changed. |
| B02 | Type-2 HARQ end-to-end integration. Layout/gaps/wrap, typed resource planning and scheduled DAI finalization exist; the main feedback builder still appends expected ACK bits by table row. | Build UE events from CRC-accepted received DCI and actual UE decoder/retained-ACK state; preserve received DAI, epoch, monitoring order and target occasion. Carry typed codebook and bit-to-event mapping through PUCCH/PUSCH and gNB disposition. Test leading/interior missed DCI, wraps, retained ACK, DTX and multiple assignments to one occasion on real shared samples. No gNB ledger may fabricate UE knowledge. |
| B03 | PUCCH receive-only integration and detector qualification. Canonical receiver component exists. The retained two-bit noise case has 12 false ACK bits/1024 positions (1.171875%), exceeding its configured 1% empirical reference. Phase-05 rejects unverified evidence. | Complete independent gNB receive windows even when UE misses DCI; separately test Format-0 HARQ/SR hypotheses, true-signal misses and noise-only false ACKs, and applicable Formats 1-4. Use independent seeds, explicit event/bit denominators and confidence bounds. Produce required independent executed Phase-05 evidence. Do not tune on the same validation sample, remove the evidence gate, or improve false ACK at the expense of unmeasured ACK misses. |
| B04 | Timing and special-slot integrated qualification. Legal TDRA/scheduler and several clock fixtures pass, not the whole baseline. | Verify received control -> data -> K1/K2 feedback chronology, TA/TAG expiry/application, NTA offsets, Tx/capture origins, propagation and filter delay exactly once. Perturb timing independently, exercise special-slot PDCCH/PDSCH plus legal feedback, require no cropped waveform or unconsumed tail. |
| B05 | Complete power/noise equation closure across all executed channels, beyond selected spatial component checks. | Recompute grid/time-domain power with the actual FFT/CP convention, occupied REs, layer/port/element matrices and Rx branches. Trace TX scaling, propagation, RF/AGC compensation and noise injection once. Check complex noise variance, fixed reference, and gain/loss conservation; never normalize each fade or change signal power to meet a desired result. |
| B06 | Measurement correctness and independence across all families, not just SINR. | Execute the measurement matrix below on new raw samples and trial records. Separate reference measurements, equalizer estimates, scheduler inputs and offline scoring. No configured-SNR, LUT, logistic, EVM-derived or oracle substitutes in primary receiver measurements. Required missing evidence fails; inapplicable metrics have explicit empty/NaN applicability. |
| B07 | CSI/SRS/beam/AMC causality in the full baseline. Two-port selection and physical precoder export have bounded passing checks. | Trace actual SRS/CSI reception to delivered TPMI/PMI/RI/CQI, received DCI, exact applied complex weights and decoded data. Verify basis identity, QCL/TCI source age and consumption, layer count, interference assumptions and non-oracle adaptation. Keep spatial pattern calculation distinct from measured over-the-air gain. |
| B08 | CSV/PNG/IQ and canonical publication closure. Old run has missing alignment columns and uncontracted historical snapshots. Applied data matrices now have retained projection evidence; access-grid and remaining beam/phase publication need checking. | Audit every current primary table, historical snapshot and required image with explicit applicability and lineage. Finish actual RA stage/native PRACH/post-channel grid production where absent. Match row counts, IDs, source/derived hashes, sample clocks and plot coordinates. Inspect every required image family. Preserve old failed snapshots unchanged. |
| B09 | Limited-SINR reporting defect. Source 45 dB scheduling input can lose its limiting status in BLER CSV/plots, while raw equalizer diagnostic is about 60.08 dB in a retained component. | Integrate `pending_sinr_limit_plot_provenance.patch`: retain value/status/reason/domain/raw diagnostic and visible limited labels. Candidate passes 153 Python tests; it is not yet integrated. Revalidate the integrated exporter and all normal/missing/limited/proxy-negative cases. Do not remove the trusted-range guard or replace measurements with the nominal point. |
| B10 | Revision-bound regression completion and lossless consolidation. Three MATLAB jobs remain active on immutable source revisions. | Collect terminal results, distinguish intentional harness-negative tests from real failures, fix remaining defects without weakening assertions, and rerun on the final integrated source. Preserve every commit/evidence/patch before fast-forwarding main and retiring extra worktrees. Then execute the final baseline and its own output audit. |

## Full measurement acceptance matrix

For every metric retain units, reference plane, bandwidth/RE/symbol window,
branch/port/layer identity, numerator/denominator, producer clock and source hash.
Independent scoring data must not enter the practical receiver or scheduler.

| Family | Required numerical and causal checks |
| --- | --- |
| Power, gain and noise | Linear mean-square power and dBm conversion; declared per-RE versus total/active-window power; FFT/CP normalization; logical-to-physical precoder power; exactly-once losses/noise; AGC versus compensated planes; per-branch noise and cross-branch covariance where used. |
| SS/CSI/reference measurements | SS/CSI RSRP, RSSI, RSRQ and SINR using their own specified RE/port/branch/time-bandwidth scopes; correct linear averaging and matching numerator/denominator scope. SSB-window power must not be renamed full-carrier RSSI. CSI scheduling quality is not automatically CSI reference SINR. |
| PDSCH/PUSCH receiver | Practical timing/CFO where estimated; per-resource fading Hest; decoder noise/LLR and post-equalization domains; EVM RMS from paired complex symbols; no reporting-only fit; raw versus range-limited SINR; constellation coverage across the actual modulation/time sequence. |
| Data integrity and throughput | Actual TB/bit/error counts, CRC, first-transmission versus residual BLER, BER denominator, real grant TBS, retransmissions, delivered unique bits and elapsed radio-time denominator. Zero errors remains zero with a separately reported uncertainty bound. |
| PDCCH/PBCH/access | Actual blind-decode/CRC and recovered payload/configuration, synchronization estimates, detection/miss/false-alarm denominators; PRACH detection and timing margins must not be mislabeled CRC BLER. Actual RAR/Msg3/Msg4/RRC chronology and resources. |
| PUCCH/PUSCH UCI/HARQ | Actually decoded ACK/NACK/DTX/SR/CSI, bit-to-assignment identity, counter DAI, feedback occasions and gNB state updates. Noise-only false ACK and true-signal missed ACK are separate measurements. No expected-TX-bit borrowing at RX. |
| CSI/SRS/TRS/PTRS and spatial processing | Reference powers, channel estimates/scoring NMSE where a genuine scoring reference exists, measured tracking errors, feedback freshness, selected/reported/applied weights and basis, QCL/TCI validity, effective rank and exact beam-pattern input. |
| Artifacts/statistics | Every applicable CSV value and PNG coordinate/legend/domain reconciles with actual producer evidence. Correct sample/trial/event denominators, independent seeds, confidence intervals and unavailable states; IQ continuity and manifests. No synthetic rescue rows or epsilon substitutions for missing BER/BLER. |

Mathematical checks start with `P = mean(abs(x).^2)`, the declared sample
unit conversion, `SINR = S/(I+N)` on a common plane, and paired-symbol
`EVM_RMS = sqrt(sum(abs(z-s).^2)/sum(abs(s).^2))`. These expressions do not
replace signal-specific measurement definitions or estimator qualification.
Exact identities use numerical tolerances derived from precision; noisy
estimates use sample-count-aware statistical checks, not forced equality.

## Fastest safe execution order

1. Complete current immutable-source validation while preparing isolated
   candidates and source-bound evidence. No fourth heavy suite or duplicate
   baseline should contend with the three existing MATLAB jobs.
2. On a free development checkout integrate B01/B09 and repair B02/B03 first;
   these block meaningful connected HARQ results. Complete B04-B08 with the
   smallest actual-waveform positive and negative regressions per defect.
3. Freeze the integrated revision. Run `setup6GRSimToolkit('Verbose',false); testAll`
   through `matlab -batch`, plus required config/LLS, export/grant/E2E and
   scenario validation suites from AGENTS.md and the applicable skills.
   Run the Python measurement, semantic, visual, IQ and candidate regressions.
   Old revision successes do not qualify newer source.
4. Consolidate all commits onto main by fast-forward if ancestry and cleanliness
   still hold. Keep checkpoint refs until file/tree/commit and LFS availability
   verification completes. Inventory untracked/ignored outputs before cleanup;
   no blanket `git clean`, reset, branch deletion or artifact deletion.
5. Execute the exact 58-slot 12 dB baseline once from the clean consolidated
   revision through the normal YAML-driven front door. Record resolved config,
   code hash, environment, seed, command, terminal exit and elapsed time. Audit
   that run's own CSV/PNG/IQ and terminal gates; commit the audit and repairs.
6. Execute the same-chain sweep only after baseline closure. Low-SNR points may
   legitimately fail acquisition/decode and produce no connected data. That is
   a measured outcome, not a reason to inject successful packets or alter noise.
   Distinguish an honestly executed point from a performance-target pass. Do not
   require strict monotonicity from a short adaptive/noisy sample.
7. Qualify the separately configured impairment-enabled/long campaign afterward.
   Preserve the broader feature backlog without delaying the bounded baseline
   for unrelated 400 MHz, extended-QAM, NTN/ISAC or instrument playback work.

## Current validation evidence and preservation

At plan creation main and receiver full suites are still running. Both older
revisions report NSCID/operator-contract, TDRA-fixture and late-PUSCH UCI/CSI
failures. Their repairs are in development (`87bab74b`, `ff00f0c1`) with focused
passing receipts; these do not retroactively turn the older failures into passes.
Development guards have passed Config, strict guards, DL/UL/reference points,
export/artifact/grant tests and E2E_FastVsTruth. E2E_TruthPacketSemanticCampaign
is active; development testAll is queued afterward, not yet passed.

The current eight-point sweep already contains all eight values requested by
the user. The companion patch additionally includes 12 dB and fixes inheritance.
Both new and previous pending patches must remain preserved until applied and
validated. The source checkouts used by live jobs remain unchanged by this plan.

### Verification performed for this plan

- `git apply --check docs/lls/pending_12db_same_chain_sweep.patch`: passed.
- Independent in-memory application checked every patch context line and parsed
  the candidate YAML. Both arrays have the exact nine unique ordered points;
  base SNR is zero, direct inheritance is the continuous-IQ baseline, and both
  independent-state policies are retained. Baseline declarations for two SRS
  ports, two PUSCH ports, rank one, dynamic HARQ and continuous IQ were checked.
  The original runtime YAML bytes were unchanged. This is a static check, not
  MATLAB inheritance/schema/runtime qualification.
- Seven existing Python audit modules passed **67 tests in 12.57 s**: exhaustive
  run audit, deep paths, visual artifacts, uplink evidence, SSB occasions,
  continuous IQ and large-scale power semantics. Receipt:
  `evidence_20260913/12db_plan_audit_regressions_01.xml`. These test the auditors,
  not a new 12 dB execution.
- `git diff --name-only ff00f0c1 -- +sixgr apps tests simulator/configs` was empty:
  the live validation dependencies were not changed by the subsequent evidence
  and plan commits. Final integrated-source MATLAB validation remains required.

## External reference and comparison policy

- [TS 38.215 V18.4.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.04.00_60/ts_138215v180400p.pdf): use the applicable SS/CSI measurement definitions, not a single generic RSSI/SINR name.
- [TS 38.213 V18.8.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf): control/timing and Type-2 codebook procedure references; unsupported extensions remain explicit.
- [MathWorks SNR definition](https://www.mathworks.com/help/5g/ug/snr-definition-used-in-link-simulations.html): compare per-RE/per-Rx-antenna references with matching channel normalization and FFT convention. Its reference SNR does not absorb array/channel effects. Do not copy its noise factor into this differently normalized physical-connector model without conversion.

Match MCS/table, coding, resource allocation, ports/layers, channel, noise plane,
receiver assumptions, seeds and trial budget before comparing another simulator.
MathWorks-backed regression equivalence is not independent implementation
evidence when both paths use the same Toolbox decoder. No independent-vendor
or universal 3GPP compliance pass is claimed by this plan.

The config-driven, NR-validation and result-integrity skills determine the
YAML-only sweep change, actual-waveform acceptance and preservation of failures.
