# CODEX IMPLEMENTATION PROMPT 08

# MAC, HARQ, SCHEDULING, BSR, PHR, SR, LCP, MAC PDU/CE, TIMING ADVANCE, AND PACKET LINEAGE

You are the implementation owner for the MATLAB 5G/6G link-level simulator in this repository.

This is **not** a source-review task and **not** a request for a plan. Modify the production MATLAB implementation, migrate every live caller, add executable tests, run those tests on the declared MATLAB and 5G Toolbox release, generate the required CSV and PNG evidence, inspect every generated artifact, and continue correcting the implementation until every mandatory requirement in this prompt passes.

Do not spend this phase on branding, a truth-contract framework, release marketing, or generic documentation. The work is the actual technical MAC/HARQ/scheduler chain and its executable validation.

The repository already contains useful foundations—position-aware HARQ combining, mother-code positions, an NDI epoch, first-success delivery de-duplication, PF/RR schedulers, a grant-finalization hook, basic BSR/PHR helpers, TB metadata, and a Msg3 timing-advance helper. Preserve those kernels where correct, but replace the fragmented state ownership, heuristic timing, approximate tables, partial MAC procedures, and non-atomic scheduler/HARQ behavior.

## Final technical objective

1. Create one canonical event-sourced MAC state per UE and serving cell, updated only by typed decoded control, decoded feedback, decoded MAC CE, RRC, PHY outcome, traffic-arrival, and timer-expiry events.
2. Create one absolute-time timing service that owns K0, K1, K2, processing-time legality, TDD symbol ownership, feedback opportunities, persistent-grant occasions, measurement gaps, and time-alignment eligibility.
3. Replace the generic simple HARQ entity with direction-specific, serving-cell-specific, codeword-aware HARQ processes whose NDI/RV/TB/grant identities cannot be mixed.
4. Bind every soft-buffer contribution to exact mother-code positions, coding layout, TB identity, attempt identity, channel/noise realization, receiver build, and LLR digest.
5. Implement exact selected Release-18 BSR tables, PHR/PCMAX mappings, trigger/timer state machines, Scheduling Request state, LCP token buckets, MAC subheaders/CEs, timing advance, and TAG behavior.
6. Run every scheduler policy from the same immutable SchedulerSnapshot and central eligibility decision. Treat PF, RR, QoS-PF, and EDF as implementation policies—not as normative 3GPP algorithms.
7. Use two-phase scheduling: construct a non-mutating CandidateGrant, validate exact PHY/timing/control feasibility, then atomically emit a GrantCommit and the corresponding state events.
8. Create immutable packet/SDU/subPDU/PDU/TB/codeword/HARQ-attempt/delivery lineage and enforce byte/bit conservation and first-success delivery accounting.
9. Execute independent table/state vectors, negative fault injections, no-noise loops, AWGN/TDL/CDL campaigns, multi-UE traffic studies, process-exhaustion studies, and paired impact experiments.
10. Generate all contracted production CSVs and technical PNGs from the corrected live runtime and pass both artifact verifiers.

## Do not return a plan-only answer

Your response is acceptable only after source edits and execution. At the end, report exact files changed, architecture decisions, commands executed, MATLAB/toolbox versions, test counts, blocked items, experiment counts, generated CSV row counts, image dimensions, hashes, verifier exit codes, and any profile still explicitly unsupported.

# 1. Pinned technical baseline

Use the exact repository-selected release versions. Unless the repository already pins newer mutually compatible versions, use:

- 3GPP TS 38.321 V18.9.0 for MAC architecture, DL/UL HARQ entities, Scheduling Request, Logical Channel Prioritization, Buffer Status Reporting, Power Headroom Reporting, Timing Advance, MAC PDU/subheaders, MAC control elements, SPS, configured grants, timers, and state procedures;
- 3GPP TS 38.213 V18.8.0 for PDSCH-to-HARQ feedback timing, PUCCH/PUSCH opportunities, K1-related physical timing, TDD symbol availability, and physical-layer timing constraints;
- 3GPP TS 38.214 V18.9.0 for PDSCH/PUSCH time-domain resource allocation, K0/K2 interpretation, MCS/TBS/resource procedures, HARQ-related scheduling fields, SPS/configured-grant resource interpretation, and selected QoS-relevant PHY inputs;
- 3GPP TS 38.331 V18.9.0 for RRC-owned MAC configuration: logical channels, LCGs, BSR/PHR/SR timers, PUCCH/PUSCH resources, SPS/configured grants, serving cells, BWPs, DRX, TAGs, timeAlignmentTimer, and scheduler-visible configuration state;
- 3GPP TS 38.133 V18.8.0 for exact Power Headroom and PCMAX reporting mappings and the selected timing/measurement requirements;
- 3GPP TS 38.211 and TS 38.212 at the same release for the physical/control/data and UCI/DL-SCH/UL-SCH interfaces consumed by MAC;
- 3GPP TS 38.300 at the same release for architecture-level relationships among RRC, MAC, HARQ, scheduler, PHY, serving cells, and bearers.

Store these exact versions in one immutable `MACSpecificationProfile`. Every event, grant, table, state projection, output artifact, and test result must carry the profile ID and configuration epoch.

A scheduler policy is not a normative 3GPP algorithm. 3GPP specifies the state, signalling, timing, constraints, QoS inputs, and procedures the scheduler must honor. PF, RR, QoS-PF, EDF, utility functions, tie-breaking, and admission heuristics are implementation choices. Do not label a policy itself “3GPP-compliant”; instead prove that every grant it emits obeys the selected 3GPP profile and measure policy performance separately.

# 2. Non-negotiable technical rules

1. No generic HARQ process expiration based on an age threshold synthesized from RTT, K1, or a fixed slot count.
2. No Boolean-only HARQ feedback API. Feedback must preserve ACK, NACK, DTX/undetected, codebook, bit position, DAI, priority, cell, resource, and source-transmission identity.
3. No process overwrite when all HARQ process IDs are occupied. Return an explicit process-exhaustion decision.
4. No NDI toggle, RV advance, soft-buffer update, queue debit, or delivery count before a grant is atomically committed.
5. No retransmission may change TB size, codeword count, NDI epoch, coding layout, mother-code identity, or TB bytes.
6. No soft combining unless all identity and coding-position fields match exactly.
7. No K0/K1/K2 default, “next UL slot” search, fixed DDDSU pattern, or slot scan to force a legal feedback/transmission opportunity.
8. No symbol movement to fit TDD. A grant either targets the exact legal symbols or is rejected.
9. No configured/bootstrap grant may substitute for a decoded DCI on the receiving side.
10. No direct scheduler call to `HARQ.onFeedback`. gNB HARQ feedback must originate from decoded UCI; UE grant state must originate from decoded DCI, configured-grant state, SPS state, or RA state.
11. No scheduler candidate may mutate HARQ, queue, BSR, PHR, SR, or lineage state before commit.
12. No configured fixed MCS or bootstrap CQI in a strict connected profile unless the profile explicitly defines a calibration/bootstrap state and labels it.
13. No approximate TBS mode in strict execution.
14. No logarithmic approximation for any selected BSR table.
15. No linear approximation for PH or PCMAX reporting.
16. No guessed BSR format, PHR type, SR resource, LCID, eLCID, MAC CE length, or subheader length.
17. No scalar-priority-only LCP in a profile that enables PBR/BSD/Bj.
18. No default logical-channel priority of 100. Missing required RRC logical-channel configuration fails.
19. No “drop last SDU” shortcut. Segment, defer, or reject according to the selected exact procedure and buffer ownership.
20. No best-effort MAC PDU parse. Malformed, truncated, reserved, duplicate, overrun, or unsupported subPDUs fail with typed errors.
21. No connected UL scheduling while the applicable TAG is not time aligned.
22. No timing-advance metadata without applying the exact sample/time shift to the waveform path.
23. No scheduler eligibility decision scattered across policies. One central eligibility engine owns all reasons.
24. No state sharing across UE, serving cell, control cell, scheduled cell, component carrier, BWP, direction, HARQ process, codeword, or configuration epoch.
25. No delivery counted more than once after repeated ACKs, duplicate feedback, retransmission decoding, or replay.
26. No TB ID synthesized from a process/slot string when an immutable lineage ID exists.
27. No bytes may disappear between traffic arrival, queue, segmentation, MAC SDU, subPDU, MAC PDU, TB, HARQ attempts, delivery, or drop.
28. No policy-comparison experiment may use different traffic, channel, noise, CSI, seed, or eligible-resource realization between baseline and treatment.
29. No same-runtime result may be copied as an independent table/state reference.
30. No mandatory MATLAB test may be skipped or marked passed because MATLAB, Toolbox, or an adjacent feature is unavailable.
31. No required CSV or PNG may be generated from configured/reconstructed values in place of runtime events.
32. Never modify a test merely to accept an existing shortcut.

# 3. Current source anchors and required migration

The source audit supplied with this pack contains 48 targeted checks and 12 useful-foundation checks. At pack generation time, 47 targeted defect signatures were present and all 12 useful foundations were present. Re-run the audit after implementation and require all targeted defect signatures to be absent or replaced by explicitly scoped compatibility façades.

Useful foundations to preserve and integrate:
- **FND01 — Position-aware soft combining exists:** `+sixgr/+phy/+harq/combineSoftLLR.m`. line 77: PositionAware = true; info.Reason = "position_aware_harq_soft_buffer_accumulated"; info.CombinedNumel = double(nu
- **FND02 — Mother-code indices are stored:** `+sixgr/+phy/+harq/combineSoftLLR.m`. line 219: MotherCodeShape", uint32(size(llr)), ... "FillerMask", logical(fillerMask), ... "HARQKey", char(string(opt.
- **FND03 — Coding-layout hash is used:** `+sixgr/+phy/+harq/combineSoftLLR.m`. line 43: CodingLayoutHash = currentBuffer.CodingLayoutHash; info.SoftBuffer = currentBuffer; if priorEmpty info.Reason =
- **FND04 — NDI epoch exists:** `+sixgr/+l2/+mac/HARQEntity.m`. line 182: NDIEpoch', p.NDIEpoch, ... 'RV', p.RV, 'IsRetransmission', true); retx = struct(
- **FND05 — First-success delivery dedup exists:** `+sixgr/+l2/+mac/HARQEntity.m`. line 55: FirstSuccessDelivery',0) end methods function obj = HARQEntity(cfg, varargin) %#ok<INUSD> c
- **FND06 — PF scheduler exists:** `+sixgr/+l2/+mac/SchedulerPF.m`. line 1: classdef SchedulerPF < sixgr.l2.mac.SchedulerBase % sixgr.l2.mac.SchedulerPF % Proportional Fair (PF) scheduler. % % PF
- **FND07 — RR scheduler exists:** `+sixgr/+l2/+mac/SchedulerRR.m`. line 1: classdef SchedulerRR < sixgr.l2.mac.SchedulerBase % sixgr.l2.mac.SchedulerRR % Round-robin scheduler (very simple baseli
- **FND08 — Exact grant finalization hook exists:** `+sixgr/+l2/+mac/SchedulerBase.m`. line 1134: finalizeExactPHYFeasibility(grantOut); grantSeed = grantOut; if isfield(grantSeed, "PHYGrant")
- **FND09 — Basic BSR helper exists:** `+sixgr/+l2/+mac/BSR_PHR.m`. line 99: encodeShortBSR(lcgId, lcgBytes(active(1))); ce = struct('LCID',61,'Payload',payload,'IsFixed',
- **FND10 — Basic PHR helper exists:** `+sixgr/+l2/+mac/BSR_PHR.m`. line 126: encodeSingleEntryPHR(ph_dB, pcmax_dBm, opt.PowerBackoff); ce = struct('LCID',57,'Payload',payload,'IsFixed',
- **FND11 — TB metadata includes HARQ process:** `+sixgr/+l2/+mac/TBAssembler.m`. line 443: HARQProcess',{},'GrantSlot',{},'DeliverySlot',{},'DropCause',{},'Meta',{}); end function item
- **FND12 — Msg3 timing advance helper exists:** `+sixgr/+phy/+ra/applyMsg3TimingAdvance.m`. line 1: function out = applyMsg3TimingAdvance(waveform, timingAdvanceSamples) %APPLYMSG3TIMINGADVANCE Apply decoded

Targeted source behavior to remove or replace:
- **D01 — HARQ entity self-identifies as simple** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 3: Simple HARQ process manager for MAC/PHY integration. % % This class tracks HARQ process state per UE and per direction (DL/UL).
- **D02 — Generic synthesized stale timeout property** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 41: StaleProcessTimeoutSlots (1,1) double = NaN Logger = [] % optional sixgr.core.Logger end
- **D03 — Stale timeout derived from RTT or K1** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 108: 2 * rttSlots; else feedbackSlots = double(sixgr.util.structGet(cfg, "phy.har
- **D04 — Fallback max(16,4*K1)** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 115: max(16, 4 * feedbackSlots); end end obj.NumProcesses = max(1, round(obj.NumProcesses))
- **D05 — Age-based process expiry** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 226: expireStaleProcessArray(procs, slot); % 1) Serve pending retransmissions first pid = find([procs.N
- **D06 — Boolean ACK feedback API** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 373: function onFeedback(obj, rnti, harqId0, ack, varargin) % onFeedback Update HARQ process state after ACK/NACK. rnti = do
- **D07 — Stale feedback ignored counter** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 54: StaleFeedbackIgnored',0,'SoftBufferStore',0, ... 'SoftBufferClear',0,'FirstSuccessDelivery',0) end
- **D08 — Fixed common RV sequence embedded in entity** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 39: RVSequence (1,:) double = [0 2 3 1] StoreTB (1,1) logical = true StaleProcessTimeoutSlots (1,1) double = NaN Lo
- **D09 — TB identity synthesized from process/slot fallback** (not detected in this snapshot; retain a regression guard) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: not found
- **D10 — Default DDDSU pattern** (detected) in `+sixgr/+l2/+mac/resolveHARQFeedbackK1.m`. Evidence: line 9: DDDSU"; end if nargin < 3 || isempty(mu) mu = 1; end mu = max(0, round(double(mu))); slotsPerFrame =
- **D11 — K1 helper selects next UL opportunity** (detected) in `+sixgr/+l2/+mac/resolveHARQFeedbackK1.m`. Evidence: line 6: next UL opportunity in the configured TDD pattern. if nargin < 2 || isempty(tddPattern) tddPattern = "DDDSU"; end
- **D12 — K1 has no-UL/default fallback** (detected) in `+sixgr/+l2/+mac/resolveHARQFeedbackK1.m`. Evidence: line 33: k1 = 4; return; end ulSlots = []; for f = 0:ceil(slotsPerFrame / max(1
- **D13 — PF stamps configured SearchSpace** (detected) in `+sixgr/+l2/+mac/SchedulerPF.m`. Evidence: line 62: phy.dl.pdcch.SearchSpaceID", 0)))); coreset = max(0, round(double(sixgr.util.structGet(obj.Cfg, "phy.dl.pdcch.CORE
- **D14 — PF stamps configured CORESET** (detected) in `+sixgr/+l2/+mac/SchedulerPF.m`. Evidence: line 63: phy.dl.pdcch.CORESETID", 0)))); bwpId = max(0, round(double(sixgr.util.structGet(obj.Cfg, "phy.bwp.id", 0))));
- **D15 — PF stamps scalar BWP** (detected) in `+sixgr/+l2/+mac/SchedulerPF.m`. Evidence: line 64: bwpId = max(0, round(double(sixgr.util.structGet(obj.Cfg, "phy.bwp.id", 0)))); if isempty(ue
- **D16 — PF hardcodes DAI=1** (detected) in `+sixgr/+l2/+mac/SchedulerPF.m`. Evidence: line 150: DAI = 1; g.K1 = k1; g.K2 = k2; g.Se
- **D17 — RR hardcodes DAI=1** (detected) in `+sixgr/+l2/+mac/SchedulerRR.m`. Evidence: line 151: DAI = 1; g.K1 = k1; g.K2 = k2; g.SearchSpaceID
- **D18 — PF is simple PRB chunking** (detected) in `+sixgr/+l2/+mac/SchedulerPF.m`. Evidence: line 10: simple PRB chunking. % - This is intentionally "simple but correct" and is a good basis for % adding QoS (5QI), LCP
- **D19 — Retransmissions are unconditionally first** (detected) in `+sixgr/+l2/+mac/SchedulerPF.m`. Evidence: line 110: HARQ retransmissions first ------------------ if ~isempty(obj.HARQ) for t = 1:numel(ueIdx)
- **D20 — Configured fixed MCS path** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: line 567: configured_fixed_mcs"; amc.MCSValueStatus = "configured"; end amc.CQ
- **D21 — Bootstrap CQI/MCS path** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: line 651: bootstrap_cqi_conservative"]) && isstruct(amc.MCSProfile) && ... isfield(amc.MCSProfile, "Val
- **D22 — Approximate TBS mode** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: line 791: TBSMode", "approximate", "ViennaEquivalent", false, ... "PlanningOnly", logical(opt.PlanningOnly), ...
- **D23 — PHR simplified quantization comment** (detected) in `+sixgr/+l2/+mac/BSR_PHR.m`. Evidence: line 14: simplified quantization) % % IMPORTANT: Exact dB mapping for PH/PCMAX indices is defined in TS 38.133. % For simulation coh
- **D24 — Approximate linear PH mapping** (detected) in `+sixgr/+l2/+mac/BSR_PHR.m`. Evidence: line 18: round(PH_dB) + 23, 0, 63) % This matches the typical LTE/NR representation range [-23..40] dB. % % Keep this file ASC
- **D25 — Truncated BSR option reserved** (detected) in `+sixgr/+l2/+mac/BSR_PHR.m`. Evidence: line 70: Truncated' : true/false (default false) (reserved) ip = inputParser; ip.addParameter('Format','auto',@(x) ischar(x) || isstri
- **D26 — Smooth approximate 8-bit table** (detected) in `+sixgr/+l2/+mac/BSR_PHR.m`. Evidence: line 312: smooth approximation: % - Map bytes to a monotonic index in [0..255] using log scaling. % If yo
- **D27 — Approximate PCMAX mapping** (detected) in `+sixgr/+l2/+mac/BSR_PHR.m`. Evidence: line 250: PCMAX,f,c: 6 bits (index 0..63), approximate mapping to dBm % - Remaining bits: set to 0 (R bits / MPE not modelled here)
- **D28 — TB assembler describes pragmatic subset** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: line 5: pragmatic subset of 3GPP TS 38.321 MAC PDU building: % - Supports MAC SDUs (logical channel SDUs) and MAC CEs (e.g.
- **D29 — Drop-last-SDU shortcut enabled by default** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: line 41: AllowDropLastSDU',true,@(x) islogical(x) && isscalar(x)); ip.addParameter('Logger',[],@(x) true);
- **D30 — Scalar priority sort** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: line 58: sort([sduList.Priority],'ascend'); sduList = sduList(ord); end % Order: DL -> CEs
- **D31 — Missing priority defaults to 100** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: line 372: Priority = 100; end if ~isfield(sduList(i),'Meta') || isempty(sduList(i).Meta)
- **D32 — Best-effort PDU decode** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: line 178: best-effort, uses LCID heuristics for fixed-size CEs). ip = inputParser; ip.addParamete
- **D33 — LCID heuristic helper** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: line 239: isCE_LCID(lcid, dir) item.Type = "CE"; if needCE
- **D34 — No MACEvent class in canonical package** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: not found
- **D35 — No CentralMACTimingService** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: not found
- **D36 — No SchedulingRequestState** (detected) in `+sixgr/+l2/+mac/BSR_PHR.m`. Evidence: not found
- **D37 — No prioritizedBitRate/Bj state** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: not found
- **D38 — No timeAlignmentTimer in MAC** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: not found
- **D39 — No TimingAdvanceGroup state in MAC** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: not found
- **D40 — No central eligibility engine** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: not found
- **D41 — No PacketLineageGraph** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: not found
- **D42 — No ConservationLedger** (detected) in `+sixgr/+l2/+mac/TBAssembler.m`. Evidence: not found
- **D43 — No per-serving-cell HARQ entity type** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: not found
- **D44 — No integrated SPS state** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: not found
- **D45 — No integrated configured-grant state** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: not found
- **D46 — Scheduler intent constructs DCI/grant fields** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: line 1310: buildDCIBitfield(obj, grant) % buildDCIBitfield Build NR-style DCI intent fields for a grant.
- **D47 — HARQ feedback called directly from scheduler** (detected) in `+sixgr/+l2/+mac/SchedulerBase.m`. Evidence: line 285: HARQ.onFeedback(rnti, harqId, ack, "SourceSlot", double(sourceSlotList(k))); else
- **D48 — Delivery ledger only TB-level** (detected) in `+sixgr/+l2/+mac/HARQEntity.m`. Evidence: line 49: DeliveryLedger table = table() end properties Stats = struct('Tx',0,'Retx',0,'Ack',0,'Nack',0,'Drop',0,

# 4. Exact selected capability profiles

Create an executable registry at canonical source paths such as:

```text
+sixgr/+l2/+mac/MACSpecificationProfile.m
+sixgr/+l2/+mac/MACCapabilityProfile.m
configs/standards/mac_capability_profiles_r18.yaml
```
The supplied `mac_capability_profile_matrix.csv` is the initial tuple set. Every `Supported=true` row must execute through the live production chain. Every `Supported=false` row must fail during planning before waveform generation or state mutation.

## Profile `nr_rel18_bsr_phr_sr_strict`

- Matrix rows: 9
- Supported rows: 9
- Directions: UL
- Serving-cell values: 1, 2
- HARQ-process values: 16
- Scheduler policies: PF
- BSR profiles: exact, long, longTruncated, refinedLong, short, shortTruncated
- PHR profiles: multipleEntry, single, type1, type2, type3
- Timing-advance profiles: singleTAG
- SPS values: disabled
- Configured-grant values: disabled

## Profile `nr_rel18_ca_scheduler_strict`

- Matrix rows: 4
- Supported rows: 4
- Directions: BOTH
- Serving-cell values: 1, 2
- HARQ-process values: 16
- Scheduler policies: PF, QoS-PF
- BSR profiles: exact
- PHR profiles: multiple
- Timing-advance profiles: multiTAG
- SPS values: enabled
- Configured-grant values: Type1|Type2

## Profile `nr_rel18_dl_harq_strict`

- Matrix rows: 3
- Supported rows: 3
- Directions: DL
- Serving-cell values: 1
- HARQ-process values: 16, 4, 8
- Scheduler policies: PF
- BSR profiles: NA
- PHR profiles: NA
- Timing-advance profiles: singleTAG
- SPS values: disabled
- Configured-grant values: disabled

## Profile `nr_rel18_persistent_grant_strict`

- Matrix rows: 3
- Supported rows: 3
- Directions: BOTH
- Serving-cell values: 1
- HARQ-process values: 16
- Scheduler policies: PF
- BSR profiles: exact
- PHR profiles: single
- Timing-advance profiles: singleTAG
- SPS values: false, true
- Configured-grant values: CG-Type1, CG-Type2, disabled

## Profile `nr_rel18_qos_scheduler_strict`

- Matrix rows: 16
- Supported rows: 16
- Directions: BOTH
- Serving-cell values: 1
- HARQ-process values: 16
- Scheduler policies: EDF, PF, QoS-PF, RR
- BSR profiles: exact
- PHR profiles: single
- Timing-advance profiles: singleTAG
- SPS values: disabled
- Configured-grant values: disabled

## Profile `nr_rel18_timing_advance_strict`

- Matrix rows: 4
- Supported rows: 4
- Directions: UL
- Serving-cell values: 1, 2
- HARQ-process values: 16
- Scheduler policies: PF
- BSR profiles: exact
- PHR profiles: single
- Timing-advance profiles: TAReport, absoluteTA, multiTAG, singleTAG
- SPS values: disabled
- Configured-grant values: disabled

## Profile `nr_rel18_ul_harq_strict`

- Matrix rows: 3
- Supported rows: 3
- Directions: UL
- Serving-cell values: 1
- HARQ-process values: 16, 4, 8
- Scheduler policies: PF
- BSR profiles: basic
- PHR profiles: single
- Timing-advance profiles: singleTAG
- SPS values: disabled
- Configured-grant values: disabled

## Profile `unsupported_extension`

- Matrix rows: 6
- Supported rows: 0
- Directions: BOTH
- Serving-cell values: 1
- HARQ-process values: 16
- Scheduler policies: IAB-specialized, MBS-specific, NR-U-LBT-scheduler, NTN-Koffset, RedCap-eLCID-full, Sidelink-MAC
- BSR profiles: profile_dependent
- PHR profiles: profile_dependent
- Timing-advance profiles: profile_dependent
- SPS values: profile_dependent
- Configured-grant values: profile_dependent

Planning output for every tuple must contain:

```text
ProfileID ReleaseVersion TupleID Direction UEID ServingCellID ControlCellID
ScheduledCellID ComponentCarrierID BWPID HARQProcessCount SchedulerPolicy
BSRProfile PHRProfile SRProfile TAGProfile SPSProfile ConfiguredGrantProfile
Supported PlanningRejected TypedError StateChanged WaveformGenerated
RequiredEvidence EvidenceGenerated Status
```

For every unsupported tuple:

```text
PlanningRejected = true
StateChanged = false
WaveformGenerated = false
QueueChanged = false
HARQChanged = false
LineageChanged = false
```

# 5. Canonical production architecture

Consolidate production behavior under the existing `+sixgr/+l2/+mac/` package. Do not create an unused parallel stack.

```text
    MACSpecificationProfile.m
    MACCapabilityProfile.m
    MACEvent.m
    MACEventType.m
    MACEventStore.m
    MACEventBatch.m
    UEContextProjection.m
    ServingCellMACContext.m
    MACConfigurationEpoch.m
    CentralMACTimingService.m
    AbsoluteRadioTime.m
    MACTimingDecision.m
    HARQTBKey.m
    HARQAttemptKey.m
    HARQProcess.m
    HARQEntityDL.m
    HARQEntityUL.m
    HARQFeedbackEvent.m
    HARQFeedbackCodebookContext.m
    SoftBufferLedger.m
    SoftBufferContribution.m
    SPSState.m
    ConfiguredGrantType1State.m
    ConfiguredGrantType2State.m
    RandomAccessGrantState.m
    BSRTableR18.m
    BSRStateMachine.m
    PHRMappingR18.m
    PHRStateMachine.m
    SchedulingRequestState.m
    LogicalChannelState.m
    LogicalChannelPrioritizer.m
    MACCESchemaRegistry.m
    MACCEPriorityResolver.m
    MACSubheaderCodec.m
    MACPDUAssembler.m
    MACPDUDemultiplexer.m
    TimingAdvanceGroupState.m
    TimingAdvanceController.m
    UEEligibilityEngine.m
    EligibilityDecision.m
    SchedulerSnapshot.m
    SchedulerPolicy.m
    RoundRobinPolicy.m
    ProportionalFairPolicy.m
    QoSPFPolicy.m
    EDFPolicy.m
    CandidateGrant.m
    GrantFeasibilityResult.m
    GrantCommit.m
    PacketLineageGraph.m
    ConservationLedger.m
    MACArtifactExporter.m
    runMACHARQSchedulingPhaseValidation.m
    runMACHARQSchedulingImpactAnalysis.m
    +oracle/BSRTableSpec.m
    +oracle/PHRMappingSpec.m
    +oracle/HARQStateSpec.m
    +oracle/HARQFeedbackSpec.m
    +oracle/TimingSpec.m
    +oracle/LCPTokenBucketSpec.m
    +oracle/MACPDUCodecSpec.m
    +oracle/TimingAdvanceSpec.m
    +oracle/ConservationSpec.m
```

Legacy classes may remain only as compatibility façades:

```text
HARQEntity.m
BSR_PHR.m
TBAssembler.m
SchedulerBase.m
SchedulerPF.m
SchedulerRR.m
resolveHARQFeedbackK1.m
```

They must delegate to the canonical implementation and contain no hidden timeout, default timing, approximate table, guessed resource, early mutation, or best-effort parsing path.

# 6. Immutable event model and state projection

Every state-changing fact is an immutable `MACEvent`. At minimum:

```matlab
classdef MACEvent
    properties (SetAccess=immutable)
        EventID string
        EventSequence uint64
        EventType string
        AbsoluteTime sixgr.l2.mac.AbsoluteRadioTime
        UEID string
        ServingCellID double
        ControlCellID double
        ScheduledCellID double
        ComponentCarrierID double
        BWPID double
        Direction string
        ConfigurationEpoch uint64
        SourceEventIDs string
        Payload struct
        PayloadSHA256 string
    end
end
```

Required event families include:
- TrafficPacketArrived, UpperLayerSDUEnqueued, BufferOccupancyChanged
- RRCConfigurationInstalled, BWPActivated, BWPDeactivated, ServingCellActivated, ServingCellDeactivated
- DecodedDCIReceived, DCITransmissionCommitted, PDCCHDecodeFailed
- CandidateGrantCreated, GrantFeasibilityAccepted, GrantFeasibilityRejected, GrantCommitted, GrantCancelled
- HARQNewDataReserved, HARQTransmissionStarted, HARQTransmissionCompleted, HARQFeedbackExpected
- HARQFeedbackDecoded, HARQFeedbackDTX, HARQRetransmissionPending, HARQAcknowledged, HARQDropped, HARQFlushed
- SoftBufferContributionAdded, SoftBufferCombined, SoftBufferCleared
- BSRTriggered, BSRTimerExpired, BSRIncluded, BSRCancelled
- PHRTriggered, PHRTimerExpired, PHRIncluded, PHRCancelled
- SRTriggered, SRTransmitted, SRProhibitStarted, SRCancelled, SRFallbackToRA
- MACCETriggered, MACCESelected, MACCEDeferred, MACPDUAssembled, MACPDUDecoded
- TimingAdvanceCommandDecoded, TimingAdvanceApplied, TimeAlignmentTimerStarted, TimeAlignmentTimerExpired
- EligibilityEvaluated, SchedulerSnapshotCreated, SchedulerPolicyDecision
- PacketSegmented, SubPDUCreated, TransportBlockCreated, HARQAttemptLinked, FirstDelivery, PacketDropped
- TimerStarted, TimerExpired, RRCReset, MACReset

The `MACEventStore` is append-only. A `UEContextProjection` is a deterministic fold over ordered events:

```matlab
projectionN = fold(projectionNMinus1, eventN);
assert(projectionN.InputEventSequence == eventN.EventSequence);
assert(projectionN.ConfigurationEpoch == eventN.ConfigurationEpoch || eventN.EventType == "RRCConfigurationInstalled");
```

Replaying the same ordered event log must produce the same projection SHA-256, scheduler snapshot SHA-256, grant SHA-256, lineage graph SHA-256, and summary metrics.

Configured values become live only through an installation/activation event. Editing the source YAML or mutable MATLAB struct after installation must not change the projected state. A stale event with an older configuration epoch must be rejected.

# 7. Two-sided grant authority and atomic commit

Implement the physically correct two-sided ownership model:

1. The gNB scheduler creates a **non-mutating** `CandidateGrant` from a `SchedulerSnapshot`.
2. The timing, eligibility, resource, HARQ, control-channel, data-channel, power, and collision engines validate the candidate.
3. A successful validation creates one atomic `GrantCommit` event batch. Queue/HARQ/resource mutation happens only here.
4. For downlink, the gNB can transmit DCI and PDSCH from its committed grant; the UE updates its grant/HARQ receive context only from a CRC-valid decoded DCI event.
5. For dynamic uplink, the UE may transmit PUSCH only from a CRC-valid decoded DCI 0_x event. Configured Grant and RAR/Msg3 use their separate active state machines.
6. The gNB updates HARQ feedback only from decoded PUCCH/PUSCH UCI or a typed DTX/undetected outcome produced by the receiver procedure—not from scheduler truth.
7. If PDCCH transmission fails before commit, exact PHY feasibility fails, TBS is zero, resources collide, timing is illegal, or the HARQ identity is incompatible, the candidate is cancelled and every mutable ledger remains unchanged.

Required API shape:

```matlab
snapshot = mac.projectSchedulerSnapshot(ueIds, radioTime);
candidate = policy.propose(snapshot);                  % no mutation
feasibility = mac.validateCandidate(candidate);        % no mutation
if feasibility.Passed
    commit = mac.commitGrant(candidate, feasibility);  % atomic event batch
else
    commit = sixgr.l2.mac.GrantCommit.rejected(candidate, feasibility);
end
```

The grant digest must include all fields that affect waveform or state: UE/cell/BWP, direction, DCI identity, PDCCH occasion, K0/K1/K2, PRB/symbol allocation, MCS/TBS, HARQ process, NDI epoch, RV, codeword count, PUCCH resource, power, beam/precoder references, and configuration epoch.

# 8. Central MAC timing service

Create `AbsoluteRadioTime` using a common finest-time lattice or rational time representation. Never compare raw slot indices across different numerologies.

For same-numerology reference vectors:

```text
PDSCH_slot = PDCCH_slot + K0
PUCCH_slot = PDSCH_slot + K1
PUSCH_slot = PDCCH_slot + K2
```

For mixed numerology, convert the source occasion and offset using the release-defined reference SCS and compare absolute symbol boundaries. Every timing decision must export:

```text
DecisionID SourceEventID UEID ServingCellID BWPID Direction
PDCCHAbsoluteTime K0Source K0Value PDSCHAbsoluteTime
K1Source K1Value PUCCHAbsoluteTime PUCCHResourceID
K2Source K2Value PUSCHAbsoluteTime
ProcessingConstraint N1N2Passed TDDPatternID SymbolOwnership
MonitoringOccasionID Legal RejectionReason
```

Timing sources may be decoded DCI fields, installed RRC TDRA lists, SPS/CG occasion state, RAR/Msg3 state, or explicit calibration input. Missing source is an error. The service must not scan forward to a later UL/DL slot.

The TDD validator operates per OFDM symbol and preserves D/U/F. Flexible symbols are resolved by the scheduler/frame engine before the grant is committed; they are not forced to DL or UL by the timing helper.

# 9. HARQ identity and state machine

Create immutable keys:

```matlab
HARQTBKey = struct( ...
  UEID, Direction, ServingCellID, ScheduledCellID, ComponentCarrierID, ...
  BWPID, HARQProcessID, CodewordID, NDIEpoch, TBID, FirstGrantID, ...
  TransportBlockSizeBits, CodingLayoutSHA256, ConfigurationEpoch);

HARQAttemptKey = struct( ...
  HARQTBKey, AttemptIndex, GrantID, RV, E, G, Ncb, ...
  RateMatchPositionSHA256, TransmissionAbsoluteTime);
```

A one-field mismatch makes the operation incompatible. Do not coerce or copy fields to match.

Required bounded state graph:

```text
IDLE --RESERVE_NEW--> NEW_DATA_RESERVED
NEW_DATA_RESERVED --COMMIT_GRANT--> TX_SCHEDULED
NEW_DATA_RESERVED --CANCEL_GRANT--> IDLE
TX_SCHEDULED --PHY_TX--> TX_TRANSMITTED
TX_SCHEDULED --CANCEL_BEFORE_TX--> IDLE
TX_TRANSMITTED --START_FEEDBACK_WAIT--> AWAITING_FEEDBACK
AWAITING_FEEDBACK --ACK--> ACKED_DELIVERED
AWAITING_FEEDBACK --NACK/DTX--> RETX_PENDING
AWAITING_FEEDBACK --MAX_RETX--> DROPPED
AWAITING_FEEDBACK --TA_EXPIRED/RRC_RESET--> FLUSHED
RETX_PENDING --COMMIT_RETX--> RETX_SCHEDULED
RETX_PENDING --MAX_RETX--> DROPPED
RETX_PENDING --RRC_RESET--> FLUSHED
RETX_SCHEDULED --PHY_TX--> TX_TRANSMITTED
RETX_SCHEDULED --CANCEL_RETX--> RETX_PENDING
ACKED_DELIVERED/DROPPED/FLUSHED --RELEASE--> IDLE
```

No transition is caused by a generic `slot - FirstTxSlot > timeout` test. Every release, drop, DTX, retry, flush, reset, deactivation, and expiry row must name the governing event and its source.

The HARQ process count is profile/configuration owned. Process exhaustion returns a scheduler decision; it never steals an active process.

# 10. Typed HARQ feedback and codebooks

Replace `onFeedback(..., ack)` with a typed object:

```matlab
HARQFeedbackEvent = struct( ...
  FeedbackEventID, UEID, RNTI, ServingCellID, BWPID, ...
  FeedbackOutcome, ...          % ACK | NACK | DTX | INVALID
  CodebookType, PriorityIndex, DAI, BitPosition, ...
  FeedbackResourceID, FeedbackAbsoluteTime, ...
  SourceTransmissionIDs, SourceTBKeys, DecoderMetric, ...
  CRCOrDetectionStatus, ConfigurationEpoch);
```

Implement the selected bounded Type-1, Type-2, and Type-3 HARQ-ACK codebook contexts through the canonical UCI/PUCCH/PUSCH implementation. The MAC layer consumes decoded bit ownership and never guesses the bit position. Test ACK, NACK, DTX, wrong position, wrong cell, wrong DAI, duplicate, late, missing, stale epoch, and time-alignment-expired cases.

DTX is not aliased to ACK. A configured study policy may map DTX to retransmission behavior, but the original receiver outcome remains `DTX` in the event and artifacts.

# 11. Soft-buffer ledger and rate-recovery provenance

Preserve the existing position-aware combining kernel, but require a full ledger row for every contribution:

```text
LedgerEntryID HARQAttemptKey TBKey CodewordID RV E G Ncb
MotherCodePositionSHA256 FillerMaskSHA256 CodingLayoutSHA256
RateMatchSHA256 ReceiverImplementation ReceiverVersion
ChannelRealizationID NoiseRealizationID LLRSourceSHA256
LLRScale SampleCount CombinedBufferSHA256 Action Status
```

Combining is legal only when the TB key, codeword, NDI epoch, coding layout, mother-code positions, serving cell, BWP, and configuration epoch match. A one-bit rate-match position change must be detected. ACK, drop, reset, reconfiguration, and TAG expiry must clear exactly the intended buffers and no others.

# 12. SPS, configured grants, and random-access grant state

Implement separate state machines:

```text
SPSState: configured → activated → occasion_due → transmission → feedback/retx → release
ConfiguredGrantType1State: installed → occasion_due → transmission/repetition → retx/release
ConfiguredGrantType2State: installed → activation_pending → activated → occasion_due → transmission → deactivation/release
RandomAccessGrantState: RAR/MsgA grant → Msg3/MsgA attempt → HARQ → success/failure/restart
```

Every occasion uses absolute-time identity, configuration epoch, resource identity, HARQ identity, and collision decision. Wrong occasion, inactive/released state, failed activation CRC, wrong RNTI, stale configuration, dynamic-grant collision, and invalid repetition state must generate no waveform and no state mutation.

# 13. Scheduler snapshot, eligibility, and policies

All policies consume the same immutable `SchedulerSnapshot`:

```text
SnapshotID AbsoluteTime ConfigurationEpoch AvailableDLResources AvailableULResources
PerUE: RRC state, serving cells, active BWPs, DRX state, measurement gaps,
       half-duplex state, TAG/time alignment, beam/control state,
       DL/UL HARQ states, retransmission urgency, queue/LCG bytes,
       logical-channel QoS, HoL delay, PBR/BSD/Bj, SR/BSR/PHR state,
       CSI/SRS age and validity, power headroom, P_CMAX, pathloss,
       configured grants/SPS, capability and selected profile.
```

The `UEEligibilityEngine` runs before policy scoring and returns all exclusion reasons, not only the first. Required reasons include:
- not RRC connected or procedure-ineligible
- serving cell inactive
- BWP inactive/stale
- DRX sleep
- measurement gap
- half-duplex conflict
- illegal TDD symbols
- missing/failed PDCCH control opportunity
- stale/invalid CSI or SRS where required
- no valid TA/time alignment
- no power headroom or P_CMAX feasibility
- HARQ process unavailable
- retransmission context mismatch
- persistent-grant conflict
- resource collision
- beam/control state unavailable
- profile tuple unsupported

Policies to implement over identical snapshots:

```text
RoundRobinPolicy      deterministic cyclic baseline
ProportionalFairPolicy metric based on instantaneous rate / averaged throughput
QoSPFPolicy           PF plus explicit 5QI/PDB/GBR/MBR/HoL/priority terms
EDFPolicy             earliest eligible packet deadline, with deterministic tie-breaks
```

The exact policy equations and tie-breaks must be configuration-versioned and exported. Policy experiments compare throughput, delivered goodput, mean/P95/P99 latency, PDB misses, deadline misses, starvation, Jain fairness, retransmissions, control overhead, and energy/power feasibility. Do not call one policy normative.

# 14. Exact Logical Channel Prioritization

Create one `LogicalChannelState` per configured logical channel containing:

```text
LCID LCGID Priority PrioritizedBitRate BucketSizeDuration Bj
SRID AllowedServingCells AllowedSCS AllowedCGType1
MaxPUSCHDuration BitRateQueryProhibitTimer QoSFlow/Bearer references
QueueBytes HeadOfLineDelay ConfigurationEpoch
```

At each LCP update, follow the selected TS 38.321 procedure exactly. The independent analytical floor uses:

```text
Bj(t + Δt) = min(Bj(t) + PBR × Δt, PBR × BSD)
```

with exact handling of zero and infinity PBR, timer units, configured restrictions, retransmissions, CE precedence, segmentation, and remaining grant bytes. Phase ordering, Bj debit, priorities, restrictions, tie-breaks, and grant exhaustion must match the supplied `mac_lcp_test_vectors.csv`.

Do not sort one MATLAB struct array only by scalar priority and then drop the final SDU. Export each selection/defer/segment decision with reason and before/after Bj and queue bytes.

# 15. Exact Buffer Status Reporting

Implement table lookup as immutable arrays generated from the supplied independent CSVs:

```text
expected_bsr_5bit_table.csv          32 rows, TS 38.321 Table 6.1.3.1-1
expected_bsr_8bit_table.csv         256 rows, TS 38.321 Table 6.1.3.1-2
expected_refined_bsr_8bit_table.csv 256 rows, TS 38.321 Table 6.1.3.1-3
```

Requirements:
- Use exact lower/upper interval semantics at every boundary, including zero, greater-than-maximum, and reserved entries.
- Implement Short BSR, Long BSR, Short Truncated BSR, Long Truncated BSR, and the selected refined/extended format profile.
- Maintain a timestamped LCG buffer snapshot and source queue/lineage IDs for every reported value.
- Implement Regular, Periodic, Retx, and Padding BSR triggers; periodicBSR-Timer and retxBSR-Timer; cancellation/restart; logical-channel priority effects; and grant-size-dependent CE selection.
- After MAC PDU assembly, update BSR state only from actual included CE bytes and actual remaining data, not from intended contents.
- Decode each BSR CE at the gNB and compare its reconstructed demand against the exact originating LCG snapshot.

All 544 table rows plus lower-edge, upper-edge, just-below, exact-boundary, just-above, maximum, overflow, and reserved-value tests must pass. The logarithmic approximation in `BSR_PHR.m` must disappear from strict execution.

# 16. Exact Power Headroom Reporting

Use the supplied exact mappings:

```text
expected_phr_mapping.csv   64 rows, TS 38.133 Table 10.1.17.1-1
expected_pcmax_mapping.csv 64 rows, TS 38.133 Table 10.1.18.1-1
```

Implement the enabled Type 1, Type 2, Type 3, single-entry, and multiple-entry PHR procedures with:

```text
periodicPHR-Timer
phr-ProhibitTimer
pathloss-change trigger
activation/deactivation trigger
power-backoff / MPR / virtual-PH flags required by the profile
serving-cell and uplink-carrier identity
actual PUSCH/PUCCH/SRS power inputs
actual PCMAX and applied waveform power
```

Export requested power, applied power, measured waveform power, computed PH, PH index, PCMAX, PCMAX index, trigger cause, timer state, and decoded gNB value. Linear formulas such as `round(PH)+23` or approximate PCMAX mappings are prohibited.

# 17. Scheduling Request state

Create one `SchedulingRequestState` per configured SR ID/resource:

```text
SRID ResourceID Pending PendingCause TriggerEventID
TransmissionCounter MaximumTransmissions ProhibitTimer
NextOccasion LastTransmissionOutcome CancellationCause
FallbackToRAState ConfigurationEpoch
```

Implement trigger, pending, occasion, positive/negative SR, collision/multiplexing, prohibit timer, maximum transmissions, cancellation on grant or BSR state, and RA fallback. A scheduler must not infer SR from queue bytes without the corresponding MAC event in a profile requiring SR.

# 18. Exact MAC PDU, subheaders, LCID/eLCID, and CE priority

Build a release-pinned `MACCESchemaRegistry` for the **declared bounded profile**. Each LCID/eLCID entry contains:

```text
Direction LCID eLCID Name FixedOrVariableLength LengthBytes
AllowedSubheaderForms Parser Encoder PriorityClass
CoexistenceRules CancellationRules ReleaseVersion EnabledProfile
```

Implement exact F/L fields, one/two/three-byte length forms as applicable, fixed/variable CEs, padding, and byte ownership. The decoder must reject reserved/unsupported LCID/eLCID, invalid F values, length overrun, truncated CE, duplicate prohibited CE, impossible padding, extra bytes, and malformed ordering.

The `MACCEPriorityResolver` receives all triggered CEs and available grant bytes, applies the selected exact precedence/coexistence/cancellation procedure, then passes remaining bytes to LCP. Export selected/deferred/rejected reason for every CE. Do not use a generic fixed order detached from procedure state.

# 19. Timing Advance, TAG, and UL gating

Implement:

```text
TimingAdvanceGroupState
  TAGID ServingCells CurrentNTA AppliedSampleShift
  LastTACommand LastAbsoluteTA LastApplicationTime
  timeAlignmentTimer State ExpiryTime ConfigurationEpoch
```

Handle TA Command MAC CE, Absolute TA Command where enabled, timer start/restart/expiry, multi-TAG separation, TA reporting where enabled, and exact waveform timing application. When the applicable TAG is not aligned, the eligibility engine must gate the selected UL procedures and perform the release/flush actions required by the pinned procedure.

Tests must verify command arithmetic, sample shift, residual timing, timer boundaries, simultaneous TAGs, stale commands, wrong TAG, expiry, recovery, and interaction with PUCCH/PUSCH/SRS/HARQ.

# 20. Per-cell, per-BWP, and cross-carrier isolation

All MAC/HARQ state keys include serving cell and BWP. Cross-carrier scheduling additionally preserves control cell, scheduled cell, CIF/nCI, and the DCI/control event lineage. Two cells may use the same numerical HARQ process ID without sharing any state or soft buffer.

Multiple-entry PHR, TAG state, BSR/LCG state, CSI/SRS validity, and scheduler eligibility must be cell specific. Cross-cell feedback or stale-BWP events must fail with typed errors and zero state mutation.

# 21. Immutable packet lineage and conservation

Create a graph with immutable IDs and edges:

```text
TrafficPacket
  → SDAP/PDCP/RLC node references when those layers are enabled
  → MACSDU
  → MACSubPDU
  → MACPDU
  → TransportBlock
  → Codeword
  → HARQAttempt[0..N]
  → FirstDelivery or Drop
```

This MAC phase must fully close MAC-SDU-to-delivery lineage. When upstream protocol layers are not yet exact, accept immutable upstream IDs as inputs and mark the upstream portion outside this profile; never fabricate them.

Mandatory conservation equations per flow and run:

```text
ArrivedBytes = QueuedBytes + InFlightBytes + DeliveredBytes + DroppedBytes
UnownedBytes = 0
DuplicateDeliveredBytes = 0
EquationErrorBytes = 0
DeliveredGoodputBits = sum(first-success unique delivered payload bits)
```

Padding, headers, CRC, coding, retransmitted bits, and control overhead are tracked separately from payload goodput. A retransmission does not create new payload bytes. Duplicate ACK/feedback does not count another delivery.

# 22. Detailed closure requirements for all 20 findings

## MAC-001 — No canonical event-sourced UE/MAC context; configured/bootstrap state can compete with decoded DCI/UCI/MAC CE/RRC state.

- **Priority:** P0
- **Classification:** Confirmed defect
- **Current source evidence:** SchedulerBase.m uses configured/bootstrap CQI/MCS and SchedulerPF/RR stamp configured BWP/CORESET/SearchSpace values.
- **Why it matters:** The simulator can schedule or mutate HARQ using state that was never decoded or received.
- **Required production change:** Create immutable MACEvent records and an append-only MACEventStore. UEContext projections may change only from decoded DCI/UCI/MAC CE/RRC/PHY outcome/timer events.
- **Mandatory acceptance:** Mutating configuration after installation cannot change a live grant; mutating a decoded event must change the projected state and exact grant digest.
- **Pinned baseline:** 38.321 clauses 4-6; 38.331 MAC/RRC configuration ownership

## MAC-002 — HARQ processes are expired by a synthesized age timeout rather than procedure-owned feedback/timer events.

- **Priority:** P0
- **Classification:** Confirmed defect
- **Current source evidence:** HARQEntity.m:105-120 derives max(16,4*K1); 591-630 drops active processes by slot age.
- **Why it matters:** A valid late feedback or long-TDD timing can be converted into an artificial drop, and an actually invalid process can live too long.
- **Required production change:** Replace stale-age expiration with exact state transitions and explicit due/expiry events from the central timing service, configured-grant/SPS state, RA state or reset/reconfiguration.
- **Mandatory acceptance:** No process transition is caused by a generic age check. Every release/drop row names the governing event, source and normative/configured timer.
- **Pinned baseline:** 38.321 HARQ entity and timers; 38.213 timing

## MAC-003 — NDI, RV, TB, codeword, serving cell, HARQ process and new-data epoch ownership are not represented by one immutable key.

- **Priority:** P0
- **Classification:** Confirmed gap
- **Current source evidence:** HARQEntity is generic DL/UL and composeTBIdentity falls back to a composite string.
- **Why it matters:** A retransmission can combine or acknowledge the wrong TB/codeword/cell after reconfiguration or process reuse.
- **Required production change:** Create HARQTBKey and HARQAttemptKey including direction, UE, serving cell, BWP, process, codeword, NDI epoch, TB ID and grant ID. Enforce exact identity on every TX, soft combine and feedback event.
- **Mandatory acceptance:** Fault injection of one key field must reject the operation and leave state/soft buffer/delivery ledger unchanged.
- **Pinned baseline:** 38.321 DL/UL HARQ procedures; 38.212/214 codeword and RV context

## MAC-004 — K0/K1/K2, processing time, monitoring occasions and TDD symbol availability are fragmented and defaulted.

- **Priority:** P0
- **Classification:** Confirmed defect
- **Current source evidence:** resolveHARQFeedbackK1.m defaults DDDSU and selects next UL; schedulers use K1=4/K2=1 defaults.
- **Why it matters:** The generated grant/feedback timeline can be physically impossible or inconsistent with decoded DCI and active BWP numerology.
- **Required production change:** Implement a CentralMACTimingService over absolute frame/slot/symbol time, per-cell numerology, D/U/F ownership, decoded TDRA/K1 fields, processing constraints, PUCCH/PUSCH resources and configured offsets.
- **Mandatory acceptance:** Every grant and feedback has one timing decision row with field source, exact due time and legality. Missing/illegal timing fails before HARQ reservation.
- **Pinned baseline:** 38.213 PDSCH/PUSCH/HARQ timing; 38.214 data procedures; 38.331 TDRA/K1 lists

## MAC-005 — HARQ feedback is reduced to a Boolean ACK/NACK; DTX, codebook position, DAI, cell, priority and suppression are incomplete.

- **Priority:** P0
- **Classification:** Confirmed gap
- **Current source evidence:** HARQEntity.onFeedback accepts logical ack; SchedulerPF/RR stamp DAI=1.
- **Why it matters:** A DTX or wrong codebook bit can be interpreted as an ACK/NACK for the wrong transmission.
- **Required production change:** Consume typed HARQFeedbackEvent objects emitted by decoded PUCCH/PUSCH UCI, including ACK/NACK/DTX, codebook type, bit position, DAI, serving cell, feedback resource and source transmission IDs.
- **Mandatory acceptance:** Type-1/2/3 bounded codebook vectors, wrong-position, DTX, late, duplicate and timeAlignmentTimer-expired cases all produce exact state transitions.
- **Pinned baseline:** 38.321 DL HARQ; 38.213 HARQ-ACK procedures; 38.212 UCI

## MAC-006 — Position-aware LLR combining exists, but provenance is not bound to full TB/codeword/grant/channel/decoder identity.

- **Priority:** P0
- **Classification:** Confirmed gap
- **Current source evidence:** combineSoftLLR stores coding-layout and rate-match hashes but not complete immutable attempt lineage.
- **Why it matters:** Soft samples from another TB, codeword, UE, cell, trial or receiver configuration can contaminate a HARQ buffer.
- **Required production change:** Create SoftBufferLedger entries keyed by HARQAttemptKey and exact mother-code positions, Ncb/E/G/RV/coding layout, receiver version, channel realization, noise realization and LLR source digest.
- **Mandatory acceptance:** Every combine is reproducible from ledger rows; one-bit position or identity corruption is detected; ACK/reset/reconfiguration flushes exactly the intended buffer.
- **Pinned baseline:** 38.212 rate recovery; 38.321 HARQ combining semantics

## MAC-007 — SPS, configured-grant Type 1/2, RAR/Msg3 and MsgA grant ownership/timers are not one integrated MAC/HARQ state machine.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** Schedulers and PHY paths contain separate configured/frozen grant paths.
- **Why it matters:** Periodic or RA transmissions can use stale resources, wrong HARQ process or wrong activation state.
- **Required production change:** Implement separate SPSState, ConfiguredGrantType1State, ConfiguredGrantType2State and RandomAccessGrantState with activation, occasion, retransmission, deactivation/release and HARQ linkage.
- **Mandatory acceptance:** Wrong occasion, inactive/released state, CRC-failed activation, stale configuration and dynamic-grant collision fail without waveform or state mutation.
- **Pinned baseline:** 38.321 configured uplink grant/SPS/RA procedures; 38.331 configuration

## MAC-008 — Only basic PF/RR policies are implemented; policy inputs and QoS/deadline behavior are incomplete.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** SchedulerPF describes simple PRB chunking; SchedulerRR performs round-robin allocation.
- **Why it matters:** System results cannot represent 5QI/PDB/GBR/MBR, starvation, retransmission urgency or control overhead coherently.
- **Required production change:** Keep PF/RR as implementation policies, add QoS-PF and EDF/reference policies, and feed all from the same immutable SchedulerSnapshot. Include queue, HoL delay, 5QI, GBR/MBR, PDB, HARQ urgency, CSI age, power, BWP and eligibility.
- **Mandatory acceptance:** Policy comparisons preserve identical inputs and resources; per-flow throughput, delay, deadline miss, starvation and Jain fairness reconcile with grants and delivered bytes.
- **Pinned baseline:** 38.321 MAC state/procedures; scheduler policy itself is implementation-defined

## MAC-009 — Logical Channel Prioritization uses a scalar Priority sort and lacks PBR, BSD, Bj and channel restrictions.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** TBAssembler sorts SDUs by Priority and defaults missing priority to 100.
- **Why it matters:** The wrong logical channel can consume an uplink grant, violating configured QoS and token-bucket behavior.
- **Required production change:** Implement LogicalChannelState and exact selected-profile LCP with priority, prioritizedBitRate, bucketSizeDuration, Bj, LCG, SR ID, allowed serving cells/SCS, max PUSCH duration, configured-grant permission and segmentation.
- **Mandatory acceptance:** Independent multi-LC vectors verify Bj evolution, prioritization, zero/infinite PBR, restrictions, segmentation and grant exhaustion byte exactly.
- **Pinned baseline:** 38.321 clause 5.4.3.1; 38.331 logicalChannelConfig

## MAC-010 — Long BSR uses a logarithmic approximation and trigger/timer/format procedures are incomplete.

- **Priority:** P1
- **Classification:** Confirmed defect
- **Current source evidence:** BSR_PHR.m:312-326 states smooth approximation; Truncated option is reserved.
- **Why it matters:** Reported LCG occupancy can map to the wrong index and scheduler demand can be materially wrong.
- **Required production change:** Implement exact 5-bit, 8-bit and refined 8-bit tables; Regular/Periodic/Retx/Padding triggers; periodicBSR-Timer and retxBSR-Timer; short/long/truncated/refined formats; cancellation and LCG snapshot provenance.
- **Mandatory acceptance:** All 544 table rows plus boundary values pass; trigger/timer vectors produce exact MAC CE type and cancel/restart behavior.
- **Pinned baseline:** 38.321 clauses 5.4.5 and 6.1.3.1

## MAC-011 — PH and PCMAX are quantized with approximate linear formulas and PHR trigger/timer/type behavior is incomplete.

- **Priority:** P1
- **Classification:** Confirmed defect
- **Current source evidence:** BSR_PHR.m:14-19 and 248-250 describe simplified/approximate mappings.
- **Why it matters:** Scheduler power decisions and power-limited MCS/rank behavior can be based on invalid reports.
- **Required production change:** Implement exact PH and PCMAX report mappings, Type 1/2/3 and selected single/multiple-entry PHR, periodic/prohibit timers, pathloss-change and activation triggers, power-backoff flags and serving-cell provenance.
- **Mandatory acceptance:** All 128 mapping rows and boundary points pass; requested/applied/measured power and decoded PHR reconcile per cell.
- **Pinned baseline:** 38.321 clauses 5.4.6 and 6.1.3.8; 38.133 report mappings

## MAC-012 — Scheduling Request trigger, pending, prohibit timer, cancellation and RA fallback are not represented as a complete MAC state machine.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** No canonical SR state class exists in +sixgr/+l2/+mac; PUCCH behavior is handled separately.
- **Why it matters:** UL data can appear without a valid request/grant path or SR can persist after the triggering condition is gone.
- **Required production change:** Implement SchedulingRequestState per SR ID/resource with pending cause, transmission counter, sr-ProhibitTimer, maximum transmissions, cancellation on grant/BSR and RA fallback.
- **Mandatory acceptance:** Periodic/event-triggered vectors verify exact occasions, positive/negative SR, collisions, grant cancellation and fallback transition.
- **Pinned baseline:** 38.321 clause 5.4.4; 38.331 SchedulingRequestConfig

## MAC-013 — MAC PDU assembly/disassembly is explicitly a pragmatic subset with best-effort LCID heuristics.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** TBAssembler.m:5 and 178; limited fixed/variable header and LCID logic.
- **Why it matters:** Payload boundaries, LCID/eLCID interpretation and CE/SDU ownership can be wrong while CRC still passes.
- **Required production change:** Create release-pinned MACCESchemaRegistry, MACSubheaderCodec, MACPDUAssembler and MACPDUDemultiplexer for the declared DL/UL LCID/eLCID profile, exact F/L fields, fixed/variable CEs, padding and malformed-PDU rejection.
- **Mandatory acceptance:** Frozen bit vectors round-trip; every byte has exactly one subPDU owner; reserved/unknown/truncated/overrun cases fail with typed errors.
- **Pinned baseline:** 38.321 clauses 6.1-6.3

## MAC-014 — MAC CE inclusion priority, coexistence, cancellation and grant-size truncation are partial.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** TBAssembler orders DL CEs before SDUs and UL SDUs before CEs rather than procedure-specific trigger priority.
- **Why it matters:** A lower-priority CE/SDU can displace a mandatory CE, or duplicate mutually exclusive CEs can be sent.
- **Required production change:** Implement a MACCEPriorityResolver over triggered CEs, LCP, grant size, format-specific truncation and cancellation rules. Record selected/rejected reason for every CE.
- **Mandatory acceptance:** Boundary grants verify C-RNTI, BSR, PHR, BFR, TA and padding priorities; no duplicate or prohibited combination is emitted.
- **Pinned baseline:** 38.321 clauses 5.4.3.1 and 6.1.3

## MAC-015 — Only random-access Msg3 timing-advance helpers exist; connected TAG/timeAlignmentTimer behavior is missing.

- **Priority:** P0
- **Classification:** Confirmed gap
- **Current source evidence:** +sixgr/+phy/+ra/applyMsg3TimingAdvance.m exists, but no canonical TAG/timeAlignmentTimer state in MAC.
- **Why it matters:** UL transmission can continue while time alignment is invalid, and HARQ feedback/soft buffers may not be flushed correctly on expiry.
- **Required production change:** Implement TimingAdvanceGroupState, TA Command/Absolute TA application, timeAlignmentTimer, per-TAG NTA, TA report, UL gating and exact expiry actions.
- **Mandatory acceptance:** TA command, absolute TA, timer restart/expiry, multiple TAG and out-of-sync vectors produce exact sample shift and MAC/HARQ/PUCCH/PUSCH gating.
- **Pinned baseline:** 38.321 clause 5.2; 38.213/211 timing advance; 38.331 TAG configuration

## MAC-016 — Scheduling eligibility is not centrally gated by RRC state, active BWP, DRX, measurement gaps, half duplex, TDD symbols, beam/control state, TA and power.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** Eligibility checks are distributed through scheduler and access tests.
- **Why it matters:** The scheduler can create grants for a UE that cannot legally monitor or transmit in that interval.
- **Required production change:** Create UEEligibilityEngine returning an immutable decision and reasons for every candidate/slot/symbol/direction. Integrate it before HARQ reservation and resource allocation.
- **Mandatory acceptance:** Fault vectors cover DRX, inactive BWP, gap, half-duplex, invalid TA, TDD, PDCCH failure, stale CSI/SRS, no power and access state.
- **Pinned baseline:** 38.321 MAC procedures; 38.213 timing/control; 38.331 configuration

## MAC-017 — HARQ and scheduler state are not fully separated per serving cell, scheduled cell, control cell, BWP and codeword.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** Generic per-UE HARQ entity and scalar BWP/CORESET/SearchSpace values are used in schedulers.
- **Why it matters:** Cross-carrier grants and feedback can update the wrong cell/process or reuse one HARQ namespace.
- **Required production change:** Create per-serving-cell DL/UL HARQ entities, control/scheduled-cell bindings, CIF/nCI-aware grants, per-cell BSR/PHR/TA and codeword-specific feedback.
- **Mandatory acceptance:** Two-cell vectors prove cell-isolated process IDs, cross-carrier control, independent feedback and no state leakage.
- **Pinned baseline:** 38.321 per-serving-cell HARQ; 38.213 cross-carrier procedures; 38.331 serving-cell configuration

## MAC-018 — Retransmission resource compatibility and decoded-grant ownership are not uniformly enforced before HARQ state mutation.

- **Priority:** P1
- **Classification:** Confirmed gap
- **Current source evidence:** SchedulerBase has exact finalization hooks, while PF/RR first create scheduler-intent grants and allocate HARQ.
- **Why it matters:** A blocked PDCCH or incompatible retransmission can reserve or mutate a process before a valid executable grant exists.
- **Required production change:** Use two-phase scheduling: CandidateGrant without mutation, then decoded/executable GrantCommit. Reserve HARQ only at commit; validate original TB size, codeword, coding layout, RV, BWP and resource compatibility.
- **Mandatory acceptance:** PDCCH fail, zero TBS, collision and incompatible-retx cases leave queue/HARQ unchanged; valid commit produces one atomic event batch.
- **Pinned baseline:** 38.321 HARQ; 38.212/214 retransmission consistency

## MAC-019 — Packet-to-SDU/PDU/TB/codeword/HARQ/delivery lineage is partial and TB identity can be synthesized.

- **Priority:** P0
- **Classification:** Confirmed gap
- **Current source evidence:** TBAssembler carries some metadata; HARQEntity.composeTBIdentity falls back to process/slot text.
- **Why it matters:** Goodput, drops and latency cannot be independently reconciled, and duplicate delivery may be hidden.
- **Required production change:** Create immutable PacketLineageGraph from traffic packet through SDAP/PDCP/RLC/MAC SDU/subPDU/MAC PDU/TB/codeword/HARQ attempts to first delivery/drop. Export byte and bit conservation ledgers.
- **Mandatory acceptance:** For every run: arrivals = queued + in-flight + delivered + dropped; each byte has one owner; first delivery counted once; all IDs/digests join without orphan rows.
- **Pinned baseline:** 38.321 delivery semantics plus simulator conservation requirements

## MAC-020 — The current tests do not provide one closed-loop, multi-seed, fault-injected MAC/HARQ/scheduler acceptance matrix.

- **Priority:** P1
- **Classification:** Validation gap
- **Current source evidence:** Useful unit tests exist for fairness, soft combining, grant consistency and HARQ invariants, but not the complete event/timing/lineage procedure.
- **Why it matters:** Local unit passes can coexist with impossible timelines, state leaks, false deliveries or non-conserved bytes.
- **Required production change:** Add independent table/state vectors, no-noise control loops, AWGN/TDL/CDL campaigns, multi-UE traffic, process exhaustion, fault injection, statistical CIs and artifact verification.
- **Mandatory acceptance:** All mandatory tests execute; zero incomplete points; exact tables/state transitions and conservation pass; policy metrics are reproducible across serial/parallel runs.
- **Pinned baseline:** 38.321/213/214/331 selected profile plus statistical validation contract

# 23. Dependency-ordered implementation tasks

Execute the following task graph in order. Do not close a task based on class skeletons or unit tests that bypass the production call path.

## MAC-T01 — Wave 1: Freeze capability/specification profile

**Exit criterion:** Executable selected tuple registry and exact spec versions.

## MAC-T02 — Wave 1: Create event model and store

**Exit criterion:** Immutable typed events and deterministic replay.

## MAC-T03 — Wave 1: Create UE/cell context projections

**Exit criterion:** No direct mutable configured truth in live procedures.

## MAC-T04 — Wave 2: Central timing service

**Exit criterion:** All K0/K1/K2/TDD/processing/resource decisions centralized.

## MAC-T05 — Wave 2: Direction-specific HARQ entities

**Exit criterion:** Explicit DL/UL states, keys, feedback and process lifecycle.

## MAC-T06 — Wave 2: Soft buffer ledger

**Exit criterion:** Full provenance and position-aware combine ownership.

## MAC-T07 — Wave 3: Persistent grant states

**Exit criterion:** SPS, CG1, CG2 and RA grant event state.

## MAC-T08 — Wave 3: Exact BSR tables/state

**Exit criterion:** All tables, triggers, timers and formats.

## MAC-T09 — Wave 3: Exact PHR mappings/state

**Exit criterion:** PH/PCMAX, timers, triggers and multi-cell formats.

## MAC-T10 — Wave 3: Scheduling Request state

**Exit criterion:** Pending/prohibit/cancel/fallback behavior.

## MAC-T11 — Wave 4: Logical channel prioritization

**Exit criterion:** PBR/BSD/Bj, restrictions and segmentation.

## MAC-T12 — Wave 4: MAC PDU codec

**Exit criterion:** Bounded LCID/eLCID, subheaders, CEs and errors.

## MAC-T13 — Wave 4: CE priority resolver

**Exit criterion:** Exact selected-profile CE inclusion/cancellation.

## MAC-T14 — Wave 5: Timing advance groups

**Exit criterion:** TA commands, timers, sample shifts and UL gating.

## MAC-T15 — Wave 5: Eligibility engine

**Exit criterion:** DRX/BWP/gap/TDD/TA/control/power/access gating.

## MAC-T16 — Wave 6: Scheduler snapshots/policies

**Exit criterion:** RR/PF/QoS-PF/EDF over identical immutable inputs.

## MAC-T17 — Wave 6: Atomic grant commit

**Exit criterion:** No HARQ/queue mutation before executable grant commit.

## MAC-T18 — Wave 6: Multi-cell/CA isolation

**Exit criterion:** Per-cell HARQ, feedback, BSR/PHR/TA and cross-carrier.

## MAC-T19 — Wave 7: Packet lineage graph

**Exit criterion:** All packet/PDU/TB/codeword/attempt/delivery IDs.

## MAC-T20 — Wave 7: Conservation ledger

**Exit criterion:** Byte/bit/packet equations and duplicate-delivery detection.

## MAC-T21 — Wave 8: Independent vector suite

**Exit criterion:** Exact tables, states, timing, PDU, LCP and lineage vectors.

## MAC-T22 — Wave 8: No-noise closed loop

**Exit criterion:** Decoded DCI/UCI/MAC CE/RRC event chain without channel errors.

## MAC-T23 — Wave 9: AWGN/TDL/CDL campaigns

**Exit criterion:** Multi-seed HARQ/scheduler/traffic campaigns.

## MAC-T24 — Wave 9: Fault injection

**Exit criterion:** Every typed error and no-mutation invariant.

## MAC-T25 — Wave 10: Base artifacts

**Exit criterion:** Generate all base CSVs and PNGs.

## MAC-T26 — Wave 11: Impact runner

**Exit criterion:** Execute 768 paired experiments and 96 rules.

## MAC-T27 — Wave 12: Regression integration

**Exit criterion:** Run all control/data/RLC/RRC/channel tests.

## MAC-T28 — Wave 13: Clean removal of shortcuts

**Exit criterion:** No heuristic timeouts/tables/default grants remain.

# 24. Typed error contract

Use stable typed MATLAB error identifiers. Do not catch and convert these into warnings, defaults, empty arrays, or altered configurations.

| ErrorIdentifier                         | Meaning                                        | StrictAction                   |
|:----------------------------------------|:-----------------------------------------------|:-------------------------------|
| sixgr:mac:InvalidHARQTransition         | State/event pair is not legal                  | Reject; no state mutation      |
| sixgr:mac:HARQIdentityMismatch          | TB/codeword/cell/process/NDI key mismatch      | Reject and preserve buffer     |
| sixgr:mac:RVSequenceMismatch            | RV does not follow selected HARQ procedure     | Reject transmission            |
| sixgr:mac:LateHARQFeedback              | Feedback arrives outside expected event/window | Record late; no process update |
| sixgr:mac:DuplicateHARQFeedback         | Feedback already consumed                      | Reject duplicate               |
| sixgr:mac:InvalidHARQFeedbackContext    | Codebook/DAI/bit/source mismatch               | Reject feedback                |
| sixgr:mac:TimingContextMissing          | Decoded/configured timing state absent         | No grant                       |
| sixgr:mac:TDDResourceUnavailable        | Requested symbols have wrong ownership         | No grant                       |
| sixgr:mac:ProcessingTimeViolation       | N1/N2 or processing constraint fails           | No grant                       |
| sixgr:mac:SoftBufferProvenanceMismatch  | LLR source/key/layout mismatch                 | Reject combine                 |
| sixgr:mac:ConfiguredGrantInactive       | CG not activated/installed                     | No grant                       |
| sixgr:mac:ConfiguredGrantWrongOccasion  | CG occasion mismatch                           | No grant                       |
| sixgr:mac:SPSWrongOccasion              | SPS occasion mismatch                          | No grant                       |
| sixgr:mac:BSRTableMismatch              | Table/index mismatch                           | Fail vector/test               |
| sixgr:mac:BSRTriggerInvalid             | BSR trigger/timer state invalid                | Reject CE                      |
| sixgr:mac:PHRMappingMismatch            | PH/PCMAX mapping mismatch                      | Reject CE                      |
| sixgr:mac:PHRStateInvalid               | PHR trigger/timer state invalid                | Reject CE                      |
| sixgr:mac:InvalidSRTransition           | SR state transition invalid                    | Reject event                   |
| sixgr:mac:SRResourceMismatch            | SR resource/occasion mismatch                  | No transmission                |
| sixgr:mac:LCPConfigurationInvalid       | PBR/BSD/priority/restriction invalid           | Reject RRC install             |
| sixgr:mac:ReservedLCID                  | Reserved/unsupported LCID                      | Reject PDU                     |
| sixgr:mac:MACPDUOverrun                 | Subheader/length exceeds PDU                   | Reject PDU                     |
| sixgr:mac:MACPDUTruncated               | PDU ends before declared payload               | Reject PDU                     |
| sixgr:mac:DuplicateMACCE                | Prohibited duplicate CE                        | Reject assembly                |
| sixgr:mac:MACCECapacityInsufficient     | Mandatory CE cannot fit                        | Apply exact procedure or fail  |
| sixgr:mac:TimeAlignmentInvalid          | UL requested for expired TAG                   | No UL transmission             |
| sixgr:mac:TimingAdvanceCommandInvalid   | TA command outside procedure/domain            | Reject command                 |
| sixgr:mac:UEIneligible                  | One or more central eligibility gates fail     | No reservation/grant           |
| sixgr:mac:GrantAuthorityMissing         | No decoded/valid grant source                  | No commit                      |
| sixgr:mac:GrantCommitConflict           | Atomic state version changed                   | Abort and retry planning       |
| sixgr:mac:RetransmissionContextMismatch | Retx TB/coding/resource incompatible           | Reject retx                    |
| sixgr:mac:LineageConservationFailure    | Byte/bit ledger does not reconcile             | Fail run                       |
| sixgr:mac:OrphanLineageNode             | Lineage edge/node missing parent               | Fail run                       |
| sixgr:mac:DuplicateDelivery             | Same packet/TB counted twice                   | Fail run                       |
| sixgr:mac:UnsupportedProfileTuple       | Capability tuple not enabled                   | Reject planning                |

# 25. Source migration map

| Component         | FileOrAction                                                                         | RequiredChange                                                                 |
|:------------------|:-------------------------------------------------------------------------------------|:-------------------------------------------------------------------------------|
| Event store       | +sixgr/+l2/+mac/MACEvent.m; MACEventStore.m; UEContextProjection.m                   | Create immutable typed events and deterministic projections.                   |
| Timing            | +sixgr/+l2/+mac/CentralMACTimingService.m                                            | Own K0/K1/K2, processing time, TDD, feedback/resource timing.                  |
| HARQ              | +sixgr/+l2/+mac/HARQEntityDL.m; HARQEntityUL.m; HARQProcess.m                        | Replace generic simple entity with direction-specific event-sourced processes. |
| HARQ identity     | +sixgr/+l2/+mac/HARQTBKey.m; HARQAttemptKey.m                                        | Immutable cell/process/codeword/NDI/TB/grant identity.                         |
| Soft buffer       | +sixgr/+phy/+harq/SoftBufferLedger.m                                                 | Bind LLR positions and provenance to full attempt key.                         |
| Feedback          | +sixgr/+l2/+mac/HARQFeedbackEvent.m                                                  | ACK/NACK/DTX/codebook/DAI/source event.                                        |
| Persistent grants | +sixgr/+l2/+mac/SPSState.m; ConfiguredGrantType1State.m; ConfiguredGrantType2State.m | Activation/occasion/release and HARQ state.                                    |
| BSR               | +sixgr/+l2/+mac/BSRStateMachine.m; BSRTableR18.m                                     | Exact tables and triggers/timers/formats.                                      |
| PHR               | +sixgr/+l2/+mac/PHRStateMachine.m; PHRMappingR18.m                                   | Exact mappings and triggers/timers/multiple cells.                             |
| SR                | +sixgr/+l2/+mac/SchedulingRequestState.m                                             | Per-SR-ID pending/prohibit/cancel/fallback state.                              |
| LCP               | +sixgr/+l2/+mac/LogicalChannelState.m; LogicalChannelPrioritizer.m                   | PBR/BSD/Bj and restrictions.                                                   |
| PDU               | +sixgr/+l2/+mac/MACCESchemaRegistry.m; MACPDUAssembler.m; MACPDUDemultiplexer.m      | Exact bounded LCID/eLCID/subheaders/CEs.                                       |
| TA                | +sixgr/+l2/+mac/TimingAdvanceGroupState.m; TimingAdvanceController.m                 | TA command, timer, gating, reporting.                                          |
| Eligibility       | +sixgr/+l2/+mac/UEEligibilityEngine.m                                                | Central all-reason eligibility gate.                                           |
| Scheduler         | +sixgr/+l2/+mac/SchedulerSnapshot.m; SchedulerPolicy.m; QoSPFPolicy.m; EDFPolicy.m   | Policies over identical immutable state.                                       |
| Grant commit      | +sixgr/+l2/+mac/CandidateGrant.m; GrantCommit.m                                      | Two-phase atomic scheduling and HARQ reservation.                              |
| Lineage           | +sixgr/+l2/+mac/PacketLineageGraph.m; ConservationLedger.m                           | Immutable packet-to-delivery graph and conservation.                           |
| Artifacts         | +sixgr/+l2/+mac/MACArtifactExporter.m; runMACHARQSchedulingPhaseValidation.m         | Generate required CSV/PNG evidence.                                            |
| Impact            | +sixgr/+l2/+mac/runMACHARQSchedulingImpactAnalysis.m                                 | Execute paired experiment matrix and statistics.                               |
| Legacy migration  | HARQEntity.m; BSR_PHR.m; TBAssembler.m; SchedulerBase/PF/RR.m                        | Convert to compatibility facades with no hidden fallback.                      |

# 26. Independent vectors and analytical floors

The independent manifest protects **33 files** and **4,773 data rows**. Verify it before MATLAB execution:

```bash
python tests/vectors/mac/verify_mac_vector_pack.py
```

Mandatory vector families:

- `expected_bsr_5bit_table.csv` — 32 rows — exact 5-bit BSR table.
- `expected_bsr_8bit_table.csv` — 256 rows — exact 8-bit BSR table.
- `expected_refined_bsr_8bit_table.csv` — 256 rows — exact refined 8-bit BSR table.
- `expected_phr_mapping.csv` — 64 rows — exact Power Headroom report mapping.
- `expected_pcmax_mapping.csv` — 64 rows — exact PCMAX report mapping.
- `mac_harq_state_transition_vectors.csv` — 150 rows — HARQ state graph and invalid transitions.
- `mac_harq_feedback_codebook_vectors.csv` — 120 rows — typed ACK/NACK/DTX and codebook ownership.
- `mac_timing_k0_k1_k2_vectors.csv` — 80 rows — same-numerology timing arithmetic and source ownership.
- `mac_tdd_eligibility_vectors.csv` — 80 rows — symbol-level D/U/F legality.
- `mac_soft_buffer_provenance_vectors.csv` — 64 rows — soft-combining identity/provenance.
- `mac_bsr_trigger_timer_vectors.csv` — 120 rows — BSR triggers, timers, formats, cancellation.
- `mac_phr_trigger_timer_vectors.csv` — 400 rows — PHR triggers, timers, types, cells.
- `mac_sr_state_vectors.csv` — 32 rows — Scheduling Request transitions.
- `mac_lcp_test_vectors.csv` — 300 rows — PBR/BSD/Bj and restrictions.
- `mac_pdu_subheader_test_vectors.csv` — 77 rows — MAC PDU/subheader codec.
- `mac_ce_priority_test_vectors.csv` — 288 rows — MAC CE selection/coexistence.
- `mac_timing_advance_test_vectors.csv` — 105 rows — TA/TAG/timer/sample-shift behavior.
- `mac_scheduler_policy_test_vectors.csv` — 360 rows — policy decisions over common snapshots.
- `mac_packet_lineage_test_vectors.csv` — 301 rows — packet graph and conservation.
- `mac_negative_test_vectors.csv` — 150 rows — fault injection and zero-mutation requirements.
- `mac_declared_coverage_matrix.csv` — 128 rows — end-to-end declared tuples.
- `mac_capability_profile_matrix.csv` — 48 rows — supported and unsupported profile planning.

The supplied vectors are a bounded independent floor. Add additional pure-spec or frozen vectors for every MAC CE/eLCID/codebook/configuration tuple you enable beyond the supplied profile. A call to the same production class on both sides is not independent evidence.

# 27. Mandatory MATLAB tests

The supplied test plan contains **60 mandatory tests**. Implement all of them against the production path:

- `testMACEventStoreReplay` — scope: event store. Required result: PASS
- `testMACContextProjection` — scope: state ownership. Required result: PASS
- `testCentralMACTimingK0K1K2` — scope: timing. Required result: PASS
- `testCentralMACTimingTDD` — scope: timing. Required result: PASS
- `testHARQDLStateMachine` — scope: HARQ. Required result: PASS
- `testHARQULStateMachine` — scope: HARQ. Required result: PASS
- `testHARQIdentityKeys` — scope: HARQ. Required result: PASS
- `testHARQFeedbackACKNACKDTX` — scope: HARQ. Required result: PASS
- `testHARQCodebookBinding` — scope: HARQ. Required result: PASS
- `testHARQProcessExhaustion` — scope: HARQ. Required result: PASS
- `testHARQSoftBufferProvenance` — scope: HARQ. Required result: PASS
- `testHARQSoftCombiningGain` — scope: HARQ. Required result: PASS
- `testHARQResetAndFlush` — scope: HARQ. Required result: PASS
- `testSPSState` — scope: persistent grants. Required result: PASS
- `testConfiguredGrantType1State` — scope: persistent grants. Required result: PASS
- `testConfiguredGrantType2State` — scope: persistent grants. Required result: PASS
- `testExactBSR5BitTable` — scope: BSR. Required result: PASS
- `testExactBSR8BitTable` — scope: BSR. Required result: PASS
- `testExactRefinedBSRTable` — scope: BSR. Required result: PASS
- `testBSRTriggersAndTimers` — scope: BSR. Required result: PASS
- `testBSRFormats` — scope: BSR. Required result: PASS
- `testExactPHMapping` — scope: PHR. Required result: PASS
- `testExactPCMAXMapping` — scope: PHR. Required result: PASS
- `testPHRTriggersAndTimers` — scope: PHR. Required result: PASS
- `testMultipleEntryPHR` — scope: PHR. Required result: PASS
- `testSchedulingRequestState` — scope: SR. Required result: PASS
- `testSchedulingRequestFallback` — scope: SR. Required result: PASS
- `testLogicalChannelBj` — scope: LCP. Required result: PASS
- `testLogicalChannelPriority` — scope: LCP. Required result: PASS
- `testLogicalChannelRestrictions` — scope: LCP. Required result: PASS
- `testMACSubheaderCodec` — scope: PDU. Required result: PASS
- `testMACPDUAssemblyDemux` — scope: PDU. Required result: PASS
- `testMACCEPriority` — scope: PDU. Required result: PASS
- `testMACPDUNegativeMatrix` — scope: PDU. Required result: PASS
- `testTimingAdvanceCommand` — scope: TA. Required result: PASS
- `testTimeAlignmentTimer` — scope: TA. Required result: PASS
- `testMultipleTAG` — scope: TA. Required result: PASS
- `testUEEligibilityEngine` — scope: eligibility. Required result: PASS
- `testAtomicGrantCommit` — scope: scheduler. Required result: PASS
- `testSchedulerRR` — scope: scheduler. Required result: PASS
- `testSchedulerPF` — scope: scheduler. Required result: PASS
- `testSchedulerQoSPF` — scope: scheduler. Required result: PASS
- `testSchedulerEDF` — scope: scheduler. Required result: PASS
- `testSchedulerRetransmissionPriority` — scope: scheduler. Required result: PASS
- `testSchedulerFairnessAndStarvation` — scope: scheduler. Required result: PASS
- `testSchedulerQoSAndDeadlines` — scope: scheduler. Required result: PASS
- `testTwoCellHARQIsolation` — scope: CA. Required result: PASS
- `testCrossCarrierGrantState` — scope: CA. Required result: PASS
- `testPacketLineageGraph` — scope: lineage. Required result: PASS
- `testByteBitConservation` — scope: lineage. Required result: PASS
- `testFirstSuccessDeduplication` — scope: lineage. Required result: PASS
- `testMACNoNoiseClosedLoop` — scope: end-to-end. Required result: PASS
- `testMACAWGNCampaign` — scope: end-to-end. Required result: PASS
- `testMACTDLCampaign` — scope: end-to-end. Required result: PASS
- `testMACCDLCampaign` — scope: end-to-end. Required result: PASS
- `testMACFaultInjection` — scope: negative. Required result: PASS
- `testMACArtifactGeneration` — scope: artifacts. Required result: PASS
- `testMACImpactAnalysis` — scope: impact. Required result: PASS
- `testMACSerialParallelReproducibility` — scope: reproducibility. Required result: PASS
- `testMACFullRepositoryRegression` — scope: regression. Required result: PASS

Each test must report `Executed=true`, `Passed=true`, `Failed=0`, `Skipped=0`, and `Blocked=0`. A skipped mandatory test fails the phase.

# 28. Required base-phase production CSVs

Generate all **32** CSVs from the corrected production runtime. Do not copy expected-vector files into the output directory.

## `mac_run_manifest.csv`

- Primary key: `RunID`
- Minimum rows: 1
- Required columns: `RunID|GitCommit|MATLABVersion|ToolboxVersion|SpecProfile|SeedList|VectorManifestSHA256|Strict|Status`

## `mac_event_log.csv`

- Primary key: `RunID|EventSequence`
- Minimum rows: 50
- Required columns: `RunID|EventSequence|EventID|EventType|UEID|ServingCell|Direction|AbsoluteSlot|AbsoluteSymbol|SourceEventID|PayloadSHA256|Status`

## `mac_ue_context_projection.csv`

- Primary key: `RunID|EventSequence|UEID|ServingCell`
- Minimum rows: 20
- Required columns: `RunID|EventSequence|UEID|ServingCell|RRCState|ActiveDLBWP|ActiveULBWP|DRXState|TimeAligned|ConfigurationEpoch|ProjectionSHA256|Status`

## `mac_timing_decisions.csv`

- Primary key: `RunID|DecisionID`
- Minimum rows: 20
- Required columns: `RunID|DecisionID|UEID|Direction|SourceDCIEventID|K0|K1|K2|PDCCHSlot|PDSCHSlot|PUSCHSlot|FeedbackSlot|TDDLegal|ProcessingLegal|ResourceLegal|Status`

## `mac_harq_process_states.csv`

- Primary key: `RunID|EventSequence|Direction|ServingCell|UEID|HARQProcess|Codeword`
- Minimum rows: 50
- Required columns: `RunID|EventSequence|Direction|ServingCell|UEID|HARQProcess|Codeword|NDI|NDIEpoch|RV|TBID|State|TransitionEvent|SourceEventID|Status`

## `mac_harq_attempts.csv`

- Primary key: `RunID|AttemptID`
- Minimum rows: 30
- Required columns: `RunID|AttemptID|Direction|ServingCell|UEID|HARQProcess|Codeword|NDIEpoch|TBID|GrantID|RV|AttemptIndex|ScheduleSlot|TxSlot|TBSBits|CodingLayoutSHA256|Status`

## `mac_harq_feedback.csv`

- Primary key: `RunID|FeedbackEventID`
- Minimum rows: 20
- Required columns: `RunID|FeedbackEventID|UEID|ServingCell|HARQProcess|Codeword|SourceAttemptID|CodebookType|DAI|BitPosition|Outcome|DueSlot|ReceivedSlot|Applied|Reason|Status`

## `mac_soft_buffer_ledger.csv`

- Primary key: `RunID|LedgerRowID`
- Minimum rows: 50
- Required columns: `RunID|LedgerRowID|AttemptID|TBID|Codeword|NDIEpoch|RV|MotherCodeIndex|LLRSum|ObservationWeight|CodingLayoutSHA256|RateMatchSHA256|ChannelRealizationID|NoiseRealizationID|ReceiverSHA256|Status`

## `mac_bsr_state.csv`

- Primary key: `RunID|EventSequence|UEID|LCGID`
- Minimum rows: 20
- Required columns: `RunID|EventSequence|UEID|LCGID|BufferBytes|Trigger|PeriodicTimer|RetxTimer|ReportFormat|BSIndex|TableID|MACPDUId|Status`

## `mac_bsr_table_results.csv`

- Primary key: `TableID|Index`
- Minimum rows: 544
- Required columns: `TableID|Index|ExpectedLower|ExpectedUpper|ActualLower|ActualUpper|BoundaryMismatchCount|Status`

## `mac_phr_state.csv`

- Primary key: `RunID|EventSequence|UEID|ServingCell`
- Minimum rows: 20
- Required columns: `RunID|EventSequence|UEID|ServingCell|PHType|PH_dB|PHIndex|PCMAX_dBm|PCMAXIndex|Trigger|PeriodicTimer|ProhibitTimer|PowerBackoff|MACPDUId|Status`

## `mac_phr_mapping_results.csv`

- Primary key: `Mapping|Index`
- Minimum rows: 128
- Required columns: `Mapping|Index|ExpectedLower|ExpectedUpper|ActualLower|ActualUpper|BoundaryMismatchCount|Status`

## `mac_sr_state.csv`

- Primary key: `RunID|EventSequence|UEID|SRID`
- Minimum rows: 20
- Required columns: `RunID|EventSequence|UEID|SRID|State|Trigger|PendingCause|ProhibitTimer|TxCounter|ResourceID|OccasionSlot|CancelledByEventID|Status`

## `mac_logical_channel_state.csv`

- Primary key: `RunID|EventSequence|UEID|LCID`
- Minimum rows: 20
- Required columns: `RunID|EventSequence|UEID|LCID|LCGID|Priority|PBR_kBps|BSD_ms|Bj_Bytes|QueueBytes|HoLDelay_ms|AllowedServingCell|AllowedSCS_kHz|Eligible|Status`

## `mac_lcp_decisions.csv`

- Primary key: `RunID|DecisionID|LCID`
- Minimum rows: 20
- Required columns: `RunID|DecisionID|UEID|GrantBytes|LCID|Priority|BjBefore|EligibleBytes|SelectedBytes|BjAfter|SelectionOrder|RejectionReason|Status`

## `mac_pdu_subpdus.csv`

- Primary key: `RunID|MACPDUId|SubPDUIndex`
- Minimum rows: 30
- Required columns: `RunID|MACPDUId|Direction|SubPDUIndex|LCID|eLCID|Kind|HeaderOffset|HeaderLength|PayloadOffset|PayloadLength|OwnerID|PayloadSHA256|Status`

## `mac_pdu_roundtrip.csv`

- Primary key: `RunID|MACPDUId`
- Minimum rows: 10
- Required columns: `RunID|MACPDUId|Direction|TBSBytes|SubPDUCount|EncodedSHA256|DecodedSHA256|ByteMismatchCount|UnownedBytes|OverlappingBytes|PaddingBytes|Status`

## `mac_ce_selection.csv`

- Primary key: `RunID|DecisionID|CEID`
- Minimum rows: 20
- Required columns: `RunID|DecisionID|UEID|CEID|CEType|TriggerEventID|Priority|RequiredBytes|Selected|RejectedReason|CancelledBy|MACPDUId|Status`

## `mac_timing_advance_state.csv`

- Primary key: `RunID|EventSequence|UEID|TAGID`
- Minimum rows: 20
- Required columns: `RunID|EventSequence|UEID|TAGID|NTA|AppliedSampleShift|CommandType|CommandValue|TimerState|TimerExpirySlot|ULAllowed|SourceEventID|Status`

## `mac_eligibility_decisions.csv`

- Primary key: `RunID|DecisionID|UEID|Direction`
- Minimum rows: 20
- Required columns: `RunID|DecisionID|UEID|Direction|RRCEligible|BWPEligible|DRXEligible|GapEligible|HalfDuplexEligible|TDDEligible|TAEligible|PowerEligible|ControlEligible|OverallEligible|Reasons|Status`

## `mac_scheduler_snapshots.csv`

- Primary key: `RunID|SnapshotID|UEID`
- Minimum rows: 20
- Required columns: `RunID|SnapshotID|UEID|ServingCell|Direction|QueueBytes|HoLDelay_ms|FiveQI|GBR_kbps|MBR_kbps|PDB_ms|MeasuredCQI|CSIAgeSlots|PH_dB|HARQUrgency|Eligible|SnapshotSHA256|Status`

## `mac_scheduler_candidates.csv`

- Primary key: `RunID|CandidateID`
- Minimum rows: 20
- Required columns: `RunID|CandidateID|SnapshotID|Policy|UEID|Metric|Rank|RequestedPRBs|RequestedSymbols|RequestedTBSBits|HARQProcess|IsRetransmission|RejectionReason|Status`

## `mac_scheduler_grants.csv`

- Primary key: `RunID|GrantID`
- Minimum rows: 20
- Required columns: `RunID|GrantID|CandidateID|DecodedDCIEventID|UEID|ServingCell|ScheduledCell|Direction|BWPID|PRBSet|SymbolAllocation|MCS|TBSBits|HARQProcess|Codeword|NDIEpoch|RV|Committed|GrantSHA256|Status`

## `mac_scheduler_metrics.csv`

- Primary key: `RunID|Policy|UEID`
- Minimum rows: 10
- Required columns: `RunID|Policy|UEID|OfferedBits|ScheduledBits|DeliveredBits|DroppedBits|ThroughputMbps|GoodputMbps|MeanDelay_ms|P95Delay_ms|DeadlineMissRate|JainFairness|StarvationSlots|Status`

## `mac_packet_lineage_nodes.csv`

- Primary key: `RunID|NodeID`
- Minimum rows: 50
- Required columns: `RunID|NodeID|NodeType|ParentNodeID|PacketID|FlowID|UEID|Bytes|Bits|SHA256|CreatedEventID|Disposition|Status`

## `mac_packet_lineage_edges.csv`

- Primary key: `RunID|EdgeID`
- Minimum rows: 50
- Required columns: `RunID|EdgeID|FromNodeID|ToNodeID|EdgeType|Bytes|Bits|SourceEventID|Status`

## `mac_conservation_ledger.csv`

- Primary key: `RunID|FlowID`
- Minimum rows: 5
- Required columns: `RunID|FlowID|ArrivedBytes|QueuedBytes|InFlightBytes|DeliveredBytes|DroppedBytes|UnownedBytes|DuplicateDeliveredBytes|EquationErrorBytes|Status`

## `mac_negative_tests.csv`

- Primary key: `CaseID`
- Minimum rows: 25
- Required columns: `CaseID|FaultType|ExpectedError|ActualError|HARQStateChanged|QueueStateChanged|WaveformGenerated|GrantCommitted|DeliveryCounted|Passed|Status`

## `mac_independent_vector_results.csv`

- Primary key: `VectorFamily`
- Minimum rows: 15
- Required columns: `VectorFamily|OracleClass|OracleImplementation|OracleVersion|OracleArtifactSHA256|Cases|MismatchCount|MaxAbsoluteError|Status`

## `mac_test_summary.csv`

- Primary key: `TestName`
- Minimum rows: 20
- Required columns: `TestName|Scope|Mandatory|Executed|Passed|Total|Failed|Skipped|Blocked|DurationSeconds|Status`

## `mac_image_semantic_audit.csv`

- Primary key: `ImageFile`
- Minimum rows: 22
- Required columns: `RunID|ImageFile|SourceCSV|SourceCSV_SHA256|PNG_SHA256|Width|Height|AxesCount|SeriesCount|FinitePointCount|ActualTitle|ActualXLabel|ActualYLabel|Status`

## `mac_capability_resolution.csv`

- Primary key: `ProfileID|TupleID`
- Minimum rows: 20
- Required columns: `ProfileID|TupleID|ExpectedSupported|ActualSupported|PlanningRejected|StateChanged|Reason|Status`

# 29. Required base-phase technical figures

Generate all **22** PNGs from their exported production CSVs. Minimum size and semantic requirements are mandatory.

- `mac_event_state_timeline.png` from `mac_event_log.csv|mac_ue_context_projection.csv`; title contains `MAC event and UE state timeline`; x-axis `Absolute slot`; y-axis `State/event`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_harq_process_timeline.png` from `mac_harq_process_states.csv`; title contains `HARQ process state timeline`; x-axis `Absolute slot`; y-axis `HARQ state`; minimum axes 1, series 4, finite points 20, size 900×600.
- `mac_ndi_rv_attempt_timeline.png` from `mac_harq_attempts.csv`; title contains `NDI RV and attempt timeline`; x-axis `Transmission attempt`; y-axis `NDI / RV`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_k0_k1_k2_timeline.png` from `mac_timing_decisions.csv`; title contains `K0 K1 K2 timing timeline`; x-axis `PDCCH slot`; y-axis `Target slot`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_tdd_eligibility_map.png` from `mac_timing_decisions.csv|mac_eligibility_decisions.csv`; title contains `TDD and eligibility map`; x-axis `Absolute symbol`; y-axis `Direction / eligibility`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_harq_feedback_codebook.png` from `mac_harq_feedback.csv`; title contains `HARQ feedback codebook mapping`; x-axis `Feedback bit position`; y-axis `Outcome`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_soft_combining_gain.png` from `mac_soft_buffer_ledger.csv|mac_harq_attempts.csv`; title contains `HARQ soft combining evidence`; x-axis `Attempt`; y-axis `Combining metric`; minimum axes 1, series 2, finite points 20, size 900×600.
- `mac_harq_process_occupancy.png` from `mac_harq_process_states.csv`; title contains `HARQ process occupancy`; x-axis `Absolute slot`; y-axis `Active processes`; minimum axes 1, series 2, finite points 20, size 900×600.
- `mac_bsr_buffer_timeline.png` from `mac_bsr_state.csv`; title contains `BSR and buffer timeline`; x-axis `Absolute slot`; y-axis `Buffer bytes`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_bsr_quantization_error.png` from `mac_bsr_table_results.csv`; title contains `BSR table quantization boundaries`; x-axis `BSR index`; y-axis `Buffer bytes`; minimum axes 1, series 3, finite points 32, size 900×600.
- `mac_phr_power_timeline.png` from `mac_phr_state.csv`; title contains `Power headroom and PCMAX timeline`; x-axis `Absolute slot`; y-axis `Power dB / dBm`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_sr_state_timeline.png` from `mac_sr_state.csv`; title contains `Scheduling Request state timeline`; x-axis `Absolute slot`; y-axis `SR state`; minimum axes 1, series 2, finite points 20, size 900×600.
- `mac_lcp_bj_timeline.png` from `mac_logical_channel_state.csv|mac_lcp_decisions.csv`; title contains `Logical channel Bj and selection`; x-axis `Absolute slot`; y-axis `Bytes`; minimum axes 1, series 4, finite points 20, size 900×600.
- `mac_pdu_composition.png` from `mac_pdu_subpdus.csv`; title contains `MAC PDU composition`; x-axis `Byte offset`; y-axis `SubPDU owner`; minimum axes 1, series 4, finite points 20, size 900×600.
- `mac_ce_priority_selection.png` from `mac_ce_selection.csv`; title contains `MAC CE priority and selection`; x-axis `CE priority`; y-axis `Selected bytes`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_timing_advance_timeline.png` from `mac_timing_advance_state.csv`; title contains `Timing advance and alignment timer`; x-axis `Absolute slot`; y-axis `NTA / timer`; minimum axes 1, series 3, finite points 20, size 900×600.
- `mac_scheduler_allocation.png` from `mac_scheduler_grants.csv`; title contains `Scheduler resource allocation`; x-axis `Absolute slot`; y-axis `PRB / UE`; minimum axes 1, series 4, finite points 20, size 900×600.
- `mac_scheduler_fairness.png` from `mac_scheduler_metrics.csv`; title contains `Scheduler throughput and Jain fairness`; x-axis `UE`; y-axis `Throughput Mbps`; minimum axes 1, series 4, finite points 10, size 900×600.
- `mac_qos_latency_cdf.png` from `mac_scheduler_metrics.csv`; title contains `QoS packet latency CDF`; x-axis `Latency ms`; y-axis `CDF`; minimum axes 1, series 4, finite points 20, size 900×600.
- `mac_packet_lineage_graph.png` from `mac_packet_lineage_nodes.csv|mac_packet_lineage_edges.csv`; title contains `Packet to HARQ delivery lineage`; x-axis `Processing stage`; y-axis `Bytes`; minimum axes 1, series 5, finite points 20, size 900×600.
- `mac_conservation_balance.png` from `mac_conservation_ledger.csv`; title contains `Packet and byte conservation`; x-axis `Flow`; y-axis `Bytes`; minimum axes 1, series 5, finite points 10, size 900×600.
- `mac_grant_authority_trace.png` from `mac_scheduler_candidates.csv|mac_scheduler_grants.csv|mac_event_log.csv`; title contains `Decoded grant authority trace`; x-axis `Event sequence`; y-axis `Grant state`; minimum axes 1, series 4, finite points 20, size 900×600.

Every figure must have one row in `mac_image_semantic_audit.csv` containing actual title, labels, axes, series, finite points, dimensions, source CSV SHA-256, and PNG SHA-256. The Python verifier reads the PNG and recomputes the hashes.

# 30. Impact-analysis extension

The impact matrix contains **64 technical families**, **768 controlled experiments**, **64 family pairing contracts**, and **96 acceptance rules**.

Each pair uses common random numbers and identical:

- seed
- trial index
- traffic packet IDs and arrival times
- channel realization
- noise realization
- CSI/SRS realization and age
- eligible resources
- initial queue/HARQ/timer state
- UE and cell configuration except the declared factor

Only `FactorName` changes between baseline and treatment. Record `effect = treatment - baseline`.

## Wave A — Direct MAC/HARQ/scheduler implementation

- Impact families: 44
- Experiments: 528
- **F01 — HARQ process count:** `HARQProcesses` changes from `4` to `16`; metrics `throughput|blocking|latency`; Implement in this phase.
- **F02 — Maximum retransmissions:** `MaxRetx` changes from `1` to `4`; metrics `BLER|latency|goodput`; Implement in this phase.
- **F03 — RV sequence:** `RVSequence` changes from `0|0|0|0` to `0|2|3|1`; metrics `combining_gain|BLER`; Implement in this phase.
- **F04 — NDI epoch enforcement:** `NDIEpochCheck` changes from `off` to `on`; metrics `false_delivery|state_error`; Implement in this phase.
- **F05 — ACK versus DTX handling:** `DTXPolicy` changes from `nack_alias` to `explicit`; metrics `BLER|retx|false_ack`; Implement in this phase.
- **F07 — K1 timing:** `K1` changes from `4` to `decoded`; metrics `feedback_legality|latency`; Implement in this phase.
- **F08 — K2 timing:** `K2` changes from `1` to `decoded`; metrics `ul_latency|grant_legality`; Implement in this phase.
- **F09 — TDD flexible symbol resolution:** `FlexPolicy` changes from `force_dl` to `scheduler_resolved`; metrics `collision|utilization`; Implement in this phase.
- **F10 — HARQ process exhaustion:** `OfferedLoad` changes from `low` to `high`; metrics `blocking|queue|latency`; Implement in this phase.
- **F11 — Soft combining provenance:** `ProvenanceCheck` changes from `partial` to `complete`; metrics `false_decode|gain`; Implement in this phase.
- **F12 — Soft buffer position awareness:** `PositionAware` changes from `off` to `on`; metrics `BLER|combining_gain`; Implement in this phase.
- **F13 — Soft buffer age/reset:** `ResetPolicy` changes from `heuristic` to `event_driven`; metrics `drop|memory|errors`; Implement in this phase.
- **F14 — Scheduler policy RR versus PF:** `Scheduler` changes from `RR` to `PF`; metrics `throughput|fairness`; Implement in this phase.
- **F15 — PF averaging window:** `PFTau_ms` changes from `50` to `500`; metrics `fairness|responsiveness`; Implement in this phase.
- **F16 — QoS-PF policy:** `Scheduler` changes from `PF` to `QoS-PF`; metrics `pdb_miss|fairness|goodput`; Implement in this phase.
- **F17 — EDF policy:** `Scheduler` changes from `PF` to `EDF`; metrics `deadline_miss|throughput`; Implement in this phase.
- **F18 — Retransmission priority:** `RetxPriority` changes from `off` to `on`; metrics `latency|drop|fairness`; Implement in this phase.
- **F19 — Control overhead accounting:** `ControlOverhead` changes from `ignored` to `included`; metrics `net_goodput|allocation`; Implement in this phase.
- **F21 — BSR 5-bit exact table:** `BSRMapping` changes from `approx` to `exact5`; metrics `demand_error|throughput`; Implement in this phase.
- **F22 — BSR 8-bit exact table:** `BSRMapping` changes from `approx` to `exact8`; metrics `demand_error|throughput`; Implement in this phase.
- **F23 — Refined BSR table:** `BSRMapping` changes from `normal8` to `refined8`; metrics `quant_error|overhead`; Implement in this phase.
- **F24 — Regular BSR trigger:** `BSRTrigger` changes from `disabled` to `regular`; metrics `ul_latency|overhead`; Implement in this phase.
- **F25 — Periodic BSR timer:** `PeriodicBSR` changes from `off` to `on`; metrics `staleness|overhead`; Implement in this phase.
- **F26 — Retx BSR timer:** `RetxBSR` changes from `off` to `on`; metrics `grant_recovery|latency`; Implement in this phase.
- **F27 — Truncated BSR:** `TruncatedBSR` changes from `off` to `on`; metrics `ce_fit|demand_error`; Implement in this phase.
- **F28 — PH exact mapping:** `PHRMapping` changes from `linear` to `exact`; metrics `power_error|mcs`; Implement in this phase.
- **F29 — PCMAX exact mapping:** `PCMAXMapping` changes from `linear` to `exact`; metrics `power_error|clipping`; Implement in this phase.
- **F30 — PHR prohibit timer:** `PHRProhibit` changes from `off` to `on`; metrics `overhead|freshness`; Implement in this phase.
- **F32 — Scheduling Request state:** `SRState` changes from `basic` to `event_sourced`; metrics `access_latency|duplicates`; Implement in this phase.
- **F33 — SR prohibit timer:** `SRProhibit` changes from `off` to `on`; metrics `overhead|latency`; Implement in this phase.
- **F35 — LCP priority only versus token bucket:** `LCP` changes from `priority_only` to `pbr_bsd_bj`; metrics `qos|fairness`; Implement in this phase.
- **F36 — PBR:** `PBR_kBps` changes from `8` to `256`; metrics `throughput|bj|starvation`; Implement in this phase.
- **F37 — Bucket size duration:** `BSD_ms` changes from `10` to `100`; metrics `burst_delay|fairness`; Implement in this phase.
- **F38 — Logical-channel restrictions:** `LCRestrictions` changes from `ignored` to `enforced`; metrics `illegal_grant|utilization`; Implement in this phase.
- **F39 — MAC CE priority:** `CEPriority` changes from `fixed_order` to `procedure_order`; metrics `ce_drop|latency`; Implement in this phase.
- **F40 — MAC PDU exact subheaders:** `PDUCodec` changes from `heuristic` to `exact`; metrics `parse_error|overhead`; Implement in this phase.
- **F42 — SDU segmentation:** `Segmentation` changes from `drop_last` to `segment`; metrics `goodput|drop`; Implement in this phase.
- **F50 — Grant commit atomicity:** `CommitMode` changes from `early_mutation` to `atomic`; metrics `state_leak|errors`; Implement in this phase.
- **F57 — Packet lineage graph:** `Lineage` changes from `partial` to `complete`; metrics `orphan|duplicate|conservation`; Implement in this phase.
- **F58 — First-success delivery deduplication:** `Dedup` changes from `off` to `on`; metrics `goodput_error`; Implement in this phase.
- **F59 — Queue-byte conservation:** `Conservation` changes from `unchecked` to `checked`; metrics `byte_error|drop`; Implement in this phase.
- **F60 — Bursty traffic:** `Traffic` changes from `full_buffer` to `bursty`; metrics `latency|scheduler_response`; Implement in this phase.
- **F62 — Runtime scaling:** `NumUE` changes from `4` to `64`; metrics `runtime|memory`; Implement in this phase.
- **F63 — Serial/parallel reproducibility:** `Execution` changes from `serial` to `parallel`; metrics `artifact_hash|metrics`; Implement in this phase.

## Wave B — Internal integrated dependency

- Impact families: 14
- Experiments: 168
- **F06 — HARQ feedback codebook:** `Codebook` changes from `type1` to `type2`; metrics `payload|latency|errors`; Requires internal cross-channel integration.
- **F20 — CQI age gating:** `CSIAgePolicy` changes from `accept_stale` to `reject_stale`; metrics `BLER|utilization`; Requires internal cross-channel integration.
- **F31 — Multiple-entry PHR:** `PHRMode` changes from `single` to `multiple`; metrics `ca_power|overhead`; Requires internal cross-channel integration.
- **F34 — SR-to-RA fallback:** `SRFallback` changes from `off` to `on`; metrics `recovery|latency`; Requires internal cross-channel integration.
- **F41 — eLCID support:** `eLCID` changes from `off` to `bounded`; metrics `feature_coverage|overhead`; Requires internal cross-channel integration.
- **F43 — Timing advance command:** `TA` changes from `off` to `on`; metrics `ul_sinr|crc`; Requires internal cross-channel integration.
- **F44 — timeAlignmentTimer:** `TATimer` changes from `ignored` to `enforced`; metrics `illegal_ul|recovery`; Requires internal cross-channel integration.
- **F46 — UL timing error:** `ResidualTA_samples` changes from `0` to `8`; metrics `EVM|BLER`; Requires internal cross-channel integration.
- **F47 — Configured grant Type 1:** `GrantMode` changes from `dynamic` to `CG1`; metrics `latency|overhead`; Requires internal cross-channel integration.
- **F48 — Configured grant Type 2:** `GrantMode` changes from `dynamic` to `CG2`; metrics `latency|activation`; Requires internal cross-channel integration.
- **F49 — Downlink SPS:** `GrantMode` changes from `dynamic` to `SPS`; metrics `latency|overhead`; Requires internal cross-channel integration.
- **F51 — PDCCH decode authority:** `GrantAuthority` changes from `configured` to `decoded`; metrics `false_grant|throughput`; Requires internal cross-channel integration.
- **F52 — Active BWP eligibility:** `BWPCheck` changes from `off` to `on`; metrics `illegal_grant|utilization`; Requires internal cross-channel integration.
- **F61 — Mixed 5QI traffic:** `Traffic` changes from `single_qos` to `mixed_qos`; metrics `pdb_miss|fairness`; Requires internal cross-channel integration.

## Wave C — Adjacent system dependency

- Impact families: 6
- Experiments: 72
- **F45 — Multiple TAGs:** `TAGs` changes from `1` to `2`; metrics `ca_alignment|complexity`; Requires adjacent subsystem integration.
- **F53 — DRX eligibility:** `DRXCheck` changes from `off` to `on`; metrics `power|latency|illegal_grant`; Requires adjacent subsystem integration.
- **F54 — Measurement-gap eligibility:** `GapCheck` changes from `off` to `on`; metrics `illegal_grant|throughput`; Requires adjacent subsystem integration.
- **F55 — Two-cell HARQ isolation:** `Cells` changes from `1` to `2`; metrics `state_leak|throughput`; Requires adjacent subsystem integration.
- **F56 — Cross-carrier scheduling:** `CrossCarrier` changes from `off` to `on`; metrics `latency|state_isolation`; Requires adjacent subsystem integration.
- **F64 — End-to-end closed loop:** `Mode` changes from `shortcut` to `full_event_chain`; metrics `throughput|latency|conservation`; Requires adjacent subsystem integration.

Wave B and C experiments may be marked `blocked_dependency` while the named real dependency is not implemented during development. Final phase status cannot be `COMPLETE` while any mandatory selected-profile experiment remains blocked. Do not replace a missing real dependency with configured SINR, fake decoded DCI, perfect TA, fabricated UCI, or manually supplied state.

# 31. Impact acceptance rules

Implement and evaluate all acceptance rules in `mac_impact_acceptance_rules.csv`. The full registry is reproduced below:

| RuleID    | FamilyID   | Severity    | Metric            | Operator                  | Threshold   | RequiredEvidence                                           | Description                                                                                     |
|:----------|:-----------|:------------|:------------------|:--------------------------|:------------|:-----------------------------------------------------------|:------------------------------------------------------------------------------------------------|
| R-F01     | F01        | HARD        | throughput        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | HARQ process count must preserve exact state/timing/conservation invariants.                    |
| R-F02     | F02        | HARD        | BLER              | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Maximum retransmissions must preserve exact state/timing/conservation invariants.               |
| R-F03     | F03        | HARD        | combining_gain    | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | RV sequence must preserve exact state/timing/conservation invariants.                           |
| R-F04     | F04        | HARD        | false_delivery    | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | NDI epoch enforcement must preserve exact state/timing/conservation invariants.                 |
| R-F05     | F05        | HARD        | BLER              | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | ACK versus DTX handling must preserve exact state/timing/conservation invariants.               |
| R-F06     | F06        | HARD        | payload           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | HARQ feedback codebook must preserve exact state/timing/conservation invariants.                |
| R-F07     | F07        | HARD        | feedback_legality | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | K1 timing must preserve exact state/timing/conservation invariants.                             |
| R-F08     | F08        | HARD        | ul_latency        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | K2 timing must preserve exact state/timing/conservation invariants.                             |
| R-F09     | F09        | HARD        | collision         | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | TDD flexible symbol resolution must preserve exact state/timing/conservation invariants.        |
| R-F10     | F10        | HARD        | blocking          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | HARQ process exhaustion must preserve exact state/timing/conservation invariants.               |
| R-F11     | F11        | HARD        | false_decode      | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Soft combining provenance must preserve exact state/timing/conservation invariants.             |
| R-F12     | F12        | HARD        | BLER              | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Soft buffer position awareness must preserve exact state/timing/conservation invariants.        |
| R-F13     | F13        | HARD        | drop              | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Soft buffer age/reset must preserve exact state/timing/conservation invariants.                 |
| R-F14     | F14        | HARD        | throughput        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Scheduler policy RR versus PF must preserve exact state/timing/conservation invariants.         |
| R-F15     | F15        | HARD        | fairness          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | PF averaging window must preserve exact state/timing/conservation invariants.                   |
| R-F16     | F16        | HARD        | pdb_miss          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | QoS-PF policy must preserve exact state/timing/conservation invariants.                         |
| R-F17     | F17        | HARD        | deadline_miss     | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | EDF policy must preserve exact state/timing/conservation invariants.                            |
| R-F18     | F18        | HARD        | latency           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Retransmission priority must preserve exact state/timing/conservation invariants.               |
| R-F19     | F19        | HARD        | net_goodput       | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Control overhead accounting must preserve exact state/timing/conservation invariants.           |
| R-F20     | F20        | HARD        | BLER              | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | CQI age gating must preserve exact state/timing/conservation invariants.                        |
| R-F21     | F21        | HARD        | demand_error      | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | BSR 5-bit exact table must preserve exact state/timing/conservation invariants.                 |
| R-F22     | F22        | HARD        | demand_error      | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | BSR 8-bit exact table must preserve exact state/timing/conservation invariants.                 |
| R-F23     | F23        | HARD        | quant_error       | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Refined BSR table must preserve exact state/timing/conservation invariants.                     |
| R-F24     | F24        | HARD        | ul_latency        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Regular BSR trigger must preserve exact state/timing/conservation invariants.                   |
| R-F25     | F25        | HARD        | staleness         | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Periodic BSR timer must preserve exact state/timing/conservation invariants.                    |
| R-F26     | F26        | HARD        | grant_recovery    | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Retx BSR timer must preserve exact state/timing/conservation invariants.                        |
| R-F27     | F27        | HARD        | ce_fit            | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Truncated BSR must preserve exact state/timing/conservation invariants.                         |
| R-F28     | F28        | HARD        | power_error       | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | PH exact mapping must preserve exact state/timing/conservation invariants.                      |
| R-F29     | F29        | HARD        | power_error       | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | PCMAX exact mapping must preserve exact state/timing/conservation invariants.                   |
| R-F30     | F30        | HARD        | overhead          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | PHR prohibit timer must preserve exact state/timing/conservation invariants.                    |
| R-F31     | F31        | HARD        | ca_power          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Multiple-entry PHR must preserve exact state/timing/conservation invariants.                    |
| R-F32     | F32        | HARD        | access_latency    | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Scheduling Request state must preserve exact state/timing/conservation invariants.              |
| R-F33     | F33        | HARD        | overhead          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | SR prohibit timer must preserve exact state/timing/conservation invariants.                     |
| R-F34     | F34        | HARD        | recovery          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | SR-to-RA fallback must preserve exact state/timing/conservation invariants.                     |
| R-F35     | F35        | HARD        | qos               | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | LCP priority only versus token bucket must preserve exact state/timing/conservation invariants. |
| R-F36     | F36        | HARD        | throughput        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | PBR must preserve exact state/timing/conservation invariants.                                   |
| R-F37     | F37        | HARD        | burst_delay       | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Bucket size duration must preserve exact state/timing/conservation invariants.                  |
| R-F38     | F38        | HARD        | illegal_grant     | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Logical-channel restrictions must preserve exact state/timing/conservation invariants.          |
| R-F39     | F39        | HARD        | ce_drop           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | MAC CE priority must preserve exact state/timing/conservation invariants.                       |
| R-F40     | F40        | HARD        | parse_error       | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | MAC PDU exact subheaders must preserve exact state/timing/conservation invariants.              |
| R-F41     | F41        | HARD        | feature_coverage  | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | eLCID support must preserve exact state/timing/conservation invariants.                         |
| R-F42     | F42        | HARD        | goodput           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | SDU segmentation must preserve exact state/timing/conservation invariants.                      |
| R-F43     | F43        | HARD        | ul_sinr           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Timing advance command must preserve exact state/timing/conservation invariants.                |
| R-F44     | F44        | HARD        | illegal_ul        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | timeAlignmentTimer must preserve exact state/timing/conservation invariants.                    |
| R-F45     | F45        | HARD        | ca_alignment      | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Multiple TAGs must preserve exact state/timing/conservation invariants.                         |
| R-F46     | F46        | HARD        | EVM               | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | UL timing error must preserve exact state/timing/conservation invariants.                       |
| R-F47     | F47        | HARD        | latency           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Configured grant Type 1 must preserve exact state/timing/conservation invariants.               |
| R-F48     | F48        | HARD        | latency           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Configured grant Type 2 must preserve exact state/timing/conservation invariants.               |
| R-F49     | F49        | HARD        | latency           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Downlink SPS must preserve exact state/timing/conservation invariants.                          |
| R-F50     | F50        | HARD        | state_leak        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Grant commit atomicity must preserve exact state/timing/conservation invariants.                |
| R-F51     | F51        | HARD        | false_grant       | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | PDCCH decode authority must preserve exact state/timing/conservation invariants.                |
| R-F52     | F52        | HARD        | illegal_grant     | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Active BWP eligibility must preserve exact state/timing/conservation invariants.                |
| R-F53     | F53        | HARD        | power             | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | DRX eligibility must preserve exact state/timing/conservation invariants.                       |
| R-F54     | F54        | HARD        | illegal_grant     | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Measurement-gap eligibility must preserve exact state/timing/conservation invariants.           |
| R-F55     | F55        | HARD        | state_leak        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Two-cell HARQ isolation must preserve exact state/timing/conservation invariants.               |
| R-F56     | F56        | HARD        | latency           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Cross-carrier scheduling must preserve exact state/timing/conservation invariants.              |
| R-F57     | F57        | HARD        | orphan            | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Packet lineage graph must preserve exact state/timing/conservation invariants.                  |
| R-F58     | F58        | HARD        | goodput_error     | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | First-success delivery deduplication must preserve exact state/timing/conservation invariants.  |
| R-F59     | F59        | HARD        | byte_error        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Queue-byte conservation must preserve exact state/timing/conservation invariants.               |
| R-F60     | F60        | HARD        | latency           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Bursty traffic must preserve exact state/timing/conservation invariants.                        |
| R-F61     | F61        | HARD        | pdb_miss          | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Mixed 5QI traffic must preserve exact state/timing/conservation invariants.                     |
| R-F62     | F62        | HARD        | runtime           | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Runtime scaling must preserve exact state/timing/conservation invariants.                       |
| R-F63     | F63        | HARD        | artifact_hash     | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | Serial/parallel reproducibility must preserve exact state/timing/conservation invariants.       |
| R-F64     | F64        | HARD        | throughput        | valid_evidence            | required    | paired raw trials|operating point summary|source event IDs | End-to-end closed loop must preserve exact state/timing/conservation invariants.                |
| R-STAT-01 | F01        | STATISTICAL | latency           | p_adjusted_le             | 0.05        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-02 | F02        | STATISTICAL | throughput        | effect_size_reported      | required    | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-03 | F03        | STATISTICAL | fairness          | zero_event_upper_bound_le | 0.001       | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-04 | F04        | STATISTICAL | false_delivery    | ci_width_le               | 0.03        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-05 | F05        | STATISTICAL | BLER              | p_adjusted_le             | 0.05        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-06 | F06        | STATISTICAL | latency           | effect_size_reported      | required    | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-07 | F07        | STATISTICAL | throughput        | zero_event_upper_bound_le | 0.001       | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-08 | F08        | STATISTICAL | fairness          | ci_width_le               | 0.03        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-09 | F09        | STATISTICAL | false_delivery    | p_adjusted_le             | 0.05        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-10 | F10        | STATISTICAL | BLER              | effect_size_reported      | required    | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-11 | F11        | STATISTICAL | latency           | zero_event_upper_bound_le | 0.001       | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-12 | F12        | STATISTICAL | throughput        | ci_width_le               | 0.03        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-13 | F13        | STATISTICAL | fairness          | p_adjusted_le             | 0.05        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-14 | F14        | STATISTICAL | false_delivery    | effect_size_reported      | required    | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-15 | F15        | STATISTICAL | BLER              | zero_event_upper_bound_le | 0.001       | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-16 | F16        | STATISTICAL | latency           | ci_width_le               | 0.03        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-17 | F17        | STATISTICAL | throughput        | p_adjusted_le             | 0.05        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-18 | F18        | STATISTICAL | fairness          | effect_size_reported      | required    | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-19 | F19        | STATISTICAL | false_delivery    | zero_event_upper_bound_le | 0.001       | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-STAT-20 | F20        | STATISTICAL | BLER              | ci_width_le               | 0.03        | raw paired trials|confidence interval|Holm adjustment      | Statistical conclusion must be supported and incomplete points must not pass.                   |
| R-DIAG-01 | F42        | DIAGNOSTIC  | memory            | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-02 | F43        | DIAGNOSTIC  | queue             | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-03 | F44        | DIAGNOSTIC  | harq_occupancy    | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-04 | F45        | DIAGNOSTIC  | runtime           | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-05 | F46        | DIAGNOSTIC  | memory            | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-06 | F47        | DIAGNOSTIC  | queue             | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-07 | F48        | DIAGNOSTIC  | harq_occupancy    | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-08 | F49        | DIAGNOSTIC  | runtime           | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-09 | F50        | DIAGNOSTIC  | memory            | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-10 | F51        | DIAGNOSTIC  | queue             | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-11 | F52        | DIAGNOSTIC  | harq_occupancy    | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |
| R-DIAG-12 | F53        | DIAGNOSTIC  | runtime           | reported                  | finite      | runtime diagnostics                                        | Diagnostic metric must be finite, reproducible and linked to the run manifest.                  |

# 32. Statistical treatment

Do not use visual-only conclusions. Implement:

| Result type | Required method |
|---|---|
| BLER, drop probability, deadline-miss rate, false-delivery rate | Wilson confidence interval |
| Zero false delivery, zero state leakage, zero malformed-PDU acceptance | one-sided exact Clopper–Pearson upper bound |
| Paired binary ACK/delivery/drop outcomes | McNemar test |
| Throughput, latency, goodput, fairness, runtime, memory, queue, power effects | paired bootstrap confidence interval |
| Related hypothesis families | Holm family-wise adjustment |
| Practical importance | signed effect and predefined engineering margin |
| Insufficient trials or errors | explicit `incomplete` or `inconclusive`, never PASS |

Every operating point must preserve its row even if incomplete. Do not filter out failed or capped points before summary. Use one canonical point-status and stop-reason enumeration.

# 33. Required impact CSVs and figures

Generate all **16 impact CSVs**:

- `mac_impact_run_manifest.csv` — key `RunID` — minimum rows 1 — columns `RunID|GitCommit|MATLABVersion|ToolboxVersion|SpecProfile|ExperimentMatrixSHA256|SeedList|Strict|Status`
- `mac_impact_raw_trials.csv` — key `ExperimentID|TrialIndex` — minimum rows 768 — columns `ExperimentID|FamilyID|PairID|Variant|TrialIndex|Seed|PayloadID|ChannelRealizationID|NoiseRealizationID|Direction|Outcome|Latency_ms|DeliveredBits|DroppedBits|HARQAttempts|Runtime_ms|Status`
- `mac_impact_operating_points.csv` — key `ExperimentID` — minimum rows 768 — columns `ExperimentID|FamilyID|PairID|Variant|Trials|Errors|Incomplete|StopReason|BLER|CILower|CIUpper|MeanLatency_ms|MeanGoodputMbps|MeanFairness|MeanRuntime_ms|Status`
- `mac_impact_pairwise_effects.csv` — key `FamilyID|PairID|Metric` — minimum rows 192 — columns `FamilyID|PairID|Metric|BaselineMean|TreatmentMean|Effect|CILower|CIUpper|PValue|AdjustedPValue|EffectSize|Conclusion|Status`
- `mac_impact_rule_evaluation.csv` — key `RuleID` — minimum rows 96 — columns `RuleID|FamilyID|Severity|Metric|ObservedValue|Operator|Threshold|EvidenceRows|Result|Status`
- `mac_impact_harq.csv` — key `FamilyID|PairID` — minimum rows 20 — columns `FamilyID|PairID|ProcessBlockingEffect|RetxEffect|CombiningGainDB|FalseDeliveryCount|MeanHARQAttempts|Status`
- `mac_impact_timing.csv` — key `FamilyID|PairID` — minimum rows 20 — columns `FamilyID|PairID|K1EffectSlots|K2EffectSlots|IllegalGrantCount|FeedbackMissCount|LatencyEffect_ms|Status`
- `mac_impact_bsr_phr_sr.csv` — key `FamilyID|PairID` — minimum rows 20 — columns `FamilyID|PairID|BSRIndexError|DemandErrorBytes|PHIndexError|PCMAXIndexError|SRLatencyEffect_ms|ControlOverheadBytes|Status`
- `mac_impact_lcp_pdu.csv` — key `FamilyID|PairID` — minimum rows 20 — columns `FamilyID|PairID|BjErrorBytes|PriorityViolationCount|PDUParseErrors|CESelectionErrors|SegmentationDropBytes|Status`
- `mac_impact_scheduler.csv` — key `FamilyID|PairID|UEID` — minimum rows 20 — columns `FamilyID|PairID|UEID|ThroughputEffectMbps|LatencyEffect_ms|DeadlineMissEffect|FairnessEffect|StarvationEffectSlots|Status`
- `mac_impact_timing_advance.csv` — key `FamilyID|PairID` — minimum rows 10 — columns `FamilyID|PairID|NTAError|ResidualTimingSamples|ULBLEREffect|IllegalULCount|RecoveryLatency_ms|Status`
- `mac_impact_persistent_grants.csv` — key `FamilyID|PairID` — minimum rows 10 — columns `FamilyID|PairID|AccessLatencyEffect_ms|ControlOverheadEffectBytes|WrongOccasionCount|ActivationErrors|CollisionCount|Status`
- `mac_impact_lineage.csv` — key `FamilyID|PairID` — minimum rows 10 — columns `FamilyID|PairID|OrphanNodes|UnownedBytes|DuplicateDeliveredBytes|ConservationErrorBytes|GoodputAccountingErrorBits|Status`
- `mac_impact_runtime.csv` — key `FamilyID|PairID` — minimum rows 20 — columns `FamilyID|PairID|BaselineRuntime_ms|TreatmentRuntime_ms|RuntimeEffect_ms|BaselineMemoryMB|TreatmentMemoryMB|MemoryEffectMB|Status`
- `mac_impact_summary.csv` — key `FamilyID` — minimum rows 64 — columns `FamilyID|Title|Wave|ExperimentsExpected|ExperimentsComplete|RulesPassed|RulesFailed|PrimaryConclusion|IncompletePoints|Status`
- `mac_impact_image_semantic_audit.csv` — key `ImageFile` — minimum rows 30 — columns `RunID|ImageFile|SourceCSV|SourceCSV_SHA256|PNG_SHA256|Width|Height|AxesCount|SeriesCount|FinitePointCount|ActualTitle|ActualXLabel|ActualYLabel|Status`

Generate all **30 impact PNGs**:

- `mac_impact_harq_process_count.png` from `mac_impact_harq.csv`; title `HARQ process count impact`; axes `HARQ processes` / `Blocking / throughput`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_retransmissions.png` from `mac_impact_harq.csv`; title `HARQ retransmission impact`; axes `Maximum retransmissions` / `BLER / latency`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_rv_combining.png` from `mac_impact_harq.csv`; title `RV sequence combining impact`; axes `HARQ round` / `Combining gain dB`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_ack_dtx.png` from `mac_impact_harq.csv`; title `ACK NACK DTX impact`; axes `Feedback outcome` / `Process result`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_k1_k2.png` from `mac_impact_timing.csv`; title `K1 K2 timing impact`; axes `Timing configuration` / `Latency / legality`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_tdd_flex.png` from `mac_impact_timing.csv`; title `Flexible TDD allocation impact`; axes `Flexible policy` / `Collision / utilization`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_scheduler_policy.png` from `mac_impact_scheduler.csv`; title `Scheduler policy comparison`; axes `Scheduler policy` / `Goodput Mbps`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_fairness_latency.png` from `mac_impact_scheduler.csv`; title `Fairness and latency tradeoff`; axes `Jain fairness` / `Latency ms`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_qos_deadlines.png` from `mac_impact_scheduler.csv`; title `QoS deadline impact`; axes `Offered load` / `Deadline miss rate`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_bsr_mapping.png` from `mac_impact_bsr_phr_sr.csv`; title `BSR mapping impact`; axes `Buffer bytes` / `Demand error bytes`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_bsr_timers.png` from `mac_impact_bsr_phr_sr.csv`; title `BSR timer impact`; axes `Timer configuration` / `Latency / overhead`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_phr_mapping.png` from `mac_impact_bsr_phr_sr.csv`; title `PHR mapping impact`; axes `Power headroom dB` / `Index / power error`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_sr_state.png` from `mac_impact_bsr_phr_sr.csv`; title `Scheduling Request state impact`; axes `SR state` / `Latency / overhead`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_lcp_bj.png` from `mac_impact_lcp_pdu.csv`; title `LCP token bucket impact`; axes `Time ms` / `Bj bytes`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_pdu_codec.png` from `mac_impact_lcp_pdu.csv`; title `MAC PDU codec impact`; axes `PDU size bytes` / `Parse errors`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_ce_priority.png` from `mac_impact_lcp_pdu.csv`; title `MAC CE priority impact`; axes `Grant bytes` / `Selected CE bytes`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_segmentation.png` from `mac_impact_lcp_pdu.csv`; title `SDU segmentation impact`; axes `Grant bytes` / `Dropped / delivered bytes`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_timing_advance.png` from `mac_impact_timing_advance.csv`; title `Timing advance impact`; axes `Residual timing samples` / `UL BLER`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_time_alignment_timer.png` from `mac_impact_timing_advance.csv`; title `Time alignment timer impact`; axes `Time slot` / `UL eligibility`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_persistent_grants.png` from `mac_impact_persistent_grants.csv`; title `Persistent grant impact`; axes `Grant mode` / `Latency / overhead`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_grant_atomicity.png` from `mac_impact_persistent_grants.csv`; title `Atomic grant commit impact`; axes `Fault injection` / `State leakage`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_two_cell_isolation.png` from `mac_impact_lineage.csv`; title `Two-cell HARQ isolation impact`; axes `Serving cell` / `State errors`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_lineage.png` from `mac_impact_lineage.csv`; title `Packet lineage impact`; axes `Processing stage` / `Bytes`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_conservation.png` from `mac_impact_lineage.csv`; title `Byte conservation impact`; axes `Flow` / `Conservation error`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_goodput_dedup.png` from `mac_impact_lineage.csv`; title `First-success goodput impact`; axes `HARQ attempt` / `Counted goodput bits`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_runtime_scaling.png` from `mac_impact_runtime.csv`; title `MAC runtime scaling`; axes `Number of UEs` / `Runtime ms`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_memory_scaling.png` from `mac_impact_runtime.csv`; title `MAC memory scaling`; axes `Number of UEs` / `Memory MB`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_reproducibility.png` from `mac_impact_runtime.csv`; title `Serial parallel reproducibility`; axes `Execution mode` / `Metric difference`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_effect_forest.png` from `mac_impact_pairwise_effects.csv`; title `MAC impact effect forest`; axes `Treatment minus baseline` / `Effect size`; minimum series 2, finite points 10, size 900×600.
- `mac_impact_end_to_end.png` from `mac_impact_summary.csv`; title `End-to-end MAC impact summary`; axes `Impact family` / `Pass / effect`; minimum series 2, finite points 10, size 900×600.

Combined production requirement:

```text
Base CSVs:    32
Base PNGs:    22
Impact CSVs:  16
Impact PNGs:  30
Total CSVs:   48
Total PNGs:   52
Total files:  100
```

# 34. Required execution commands

Adjust only package/function paths necessitated by the repository layout. Do not omit any category.

```bash
python tests/vectors/mac/verify_mac_vector_pack.py
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*MAC*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*HARQ*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Scheduler*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*BSR*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*PHR*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*TimingAdvance*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.l2.mac.runMACHARQSchedulingPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','mac'),'OutputDir',fullfile(pwd,'artifacts','mac_harq_scheduling_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/mac/verify_mac_artifacts.py artifacts/mac_harq_scheduling_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.l2.mac.runMACHARQSchedulingImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','mac','mac_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','mac_harq_scheduling_impact'),'SeedList',[11 23 47 89 131 197],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/mac/verify_mac_impact_artifacts.py artifacts/mac_harq_scheduling_impact
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

# 35. Mandatory negative and fault-injection behavior

For every rejected case:

```text
ExpectedError = ActualError
HARQStateChanged = false
QueueStateChanged = false
WaveformGenerated = false
GrantCommitted = false
DeliveryCounted = false
```

Fault injection must include at least:
- one-field HARQ key mismatch
- NDI epoch mismatch
- RV/coding layout mismatch
- wrong mother-code position
- late/duplicate/wrong-position HARQ feedback
- DTX and no-signal feedback
- no free HARQ process
- illegal K0/K1/K2
- wrong numerology timing conversion
- DL/UL TDD symbol conflict
- PDCCH failure before commit
- zero or changed retransmission TBS
- stale BWP/configuration epoch
- BSR table boundary corruption
- reserved BSR index
- PH/PCMAX mapping boundary corruption
- BSR/PHR/SR timer duplicate and cancellation errors
- Bj overflow/underflow and logical-channel restriction
- truncated/overrun/reserved MAC PDU
- CE priority conflict
- TA wrong TAG/stale command/timer expiry
- cross-cell HARQ leakage
- packet-lineage orphan
- duplicate delivery
- unowned byte
- serial/parallel nondeterminism

# 36. Codex completion restrictions

Do not report `COMPLETE` while any of the following remains:

- `HARQEntity` remains a generic “simple” manager in the live path.
- a HARQ process can expire from a synthesized age timeout.
- feedback is reduced to a Boolean ACK flag.
- NDI/RV/TB/codeword/cell/BWP/grant identity is not immutable.
- K0/K1/K2 or the TDD pattern can default or scan forward.
- scheduler intent directly mutates HARQ before commit.
- configured/bootstrap state substitutes for decoded control/feedback at the receiving side.
- BSR uses logarithmic or smooth approximation.
- PH or PCMAX uses a linear approximation.
- BSR/PHR/SR trigger or timer state is incomplete for an enabled profile.
- LCP lacks PBR/BSD/Bj for an enabled profile.
- MAC PDU parsing is heuristic or best effort.
- CE priority/coexistence is not procedure owned.
- Timing Advance is metadata only or timeAlignmentTimer is absent.
- eligibility remains scattered across scheduler policies.
- a retransmission can change the original TB/coding identity.
- soft combining lacks complete provenance.
- packet/byte conservation has any orphan, duplicate, unowned byte, or equation error.
- first-success delivery can be counted twice.
- one enabled capability tuple is unexecuted.
- one mandatory test is skipped, blocked, or unexecuted.
- one mandatory statistical operating point is incomplete.
- one of the required production CSVs or PNGs is absent.
- either Python artifact verifier returns nonzero.
- MATLAB or 5G Toolbox runtime evidence is unavailable.
- complete repository regression fails.

The phase may report `COMPLETE` only after:

- all 20 findings are closed for every enabled capability row;
- all 60 mandatory MATLAB tests execute and pass;
- all exact BSR/PHR/PCMAX/state/timing/PDU/TA vectors pass with zero mismatches;
- all dynamic, SPS, CG Type 1/2, and selected RA grant states pass;
- all scheduler policies run over identical snapshots and all emitted grants are legal;
- all HARQ processes and soft buffers preserve identity and provenance;
- all packet lineage and conservation equations reconcile;
- all 768 impact experiments execute;
- all 96 acceptance rules have valid evidence;
- all 48 CSVs pass;
- all 52 PNGs pass;
- both artifact verifiers return exit code 0;
- full repository regression passes on the pinned MATLAB/toolbox release.

# 37. Required final Codex response

At the end of execution, report exactly:
1. phase name and all finding IDs
2. files added/modified/deleted
3. legacy paths converted to façades
4. event types and state projections implemented
5. HARQ state machine and key schema
6. timing service design and K0/K1/K2 source handling
7. exact BSR/PHR/PCMAX table results
8. LCP/PDU/CE/TA implementation status
9. scheduler policies and policy equations
10. lineage/conservation results
11. MATLAB and 5G Toolbox versions
12. every command executed with exit status
13. test total/pass/fail/skip/block counts
14. capability rows passed/rejected
15. impact experiments complete/incomplete
16. acceptance rules passed/failed
17. CSV row counts and SHA-256 values
18. PNG dimensions and SHA-256 values
19. artifact-verifier exit codes
20. remaining unsupported profiles/dependencies
21. final status: COMPLETE, FAIL, or BLOCKED

A plan-only answer, unexecuted class skeletons, a simulator run without exact table/state/PDU/lineage checks, or plots without verified source CSVs does not satisfy this prompt.

# Appendix A. Complete capability matrix

| ProfileID                        | Direction   |   ServingCells |   HARQProcesses | SchedulerPolicy    | BSR               | PHR               | SR                | TimingAdvance     | SPS               | ConfiguredGrant   | Supported   | RequiredEvidence                                 |
|:---------------------------------|:------------|---------------:|----------------:|:-------------------|:------------------|:------------------|:------------------|:------------------|:------------------|:------------------|:------------|:-------------------------------------------------|
| nr_rel18_dl_harq_strict          | DL          |              1 |               4 | PF                 | NA                | NA                | NA                | singleTAG         | disabled          | disabled          | True        | state|timing|soft_buffer|lineage|waveform        |
| nr_rel18_dl_harq_strict          | DL          |              1 |               8 | PF                 | NA                | NA                | NA                | singleTAG         | disabled          | disabled          | True        | state|timing|soft_buffer|lineage|waveform        |
| nr_rel18_dl_harq_strict          | DL          |              1 |              16 | PF                 | NA                | NA                | NA                | singleTAG         | disabled          | disabled          | True        | state|timing|soft_buffer|lineage|waveform        |
| nr_rel18_ul_harq_strict          | UL          |              1 |               4 | PF                 | basic             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | state|timing|soft_buffer|lineage|waveform        |
| nr_rel18_ul_harq_strict          | UL          |              1 |               8 | PF                 | basic             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | state|timing|soft_buffer|lineage|waveform        |
| nr_rel18_ul_harq_strict          | UL          |              1 |              16 | PF                 | basic             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | state|timing|soft_buffer|lineage|waveform        |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | RR                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 2UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | RR                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 4UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | RR                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 8UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | RR                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 16UE|fairness|latency|conservation               |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 2UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 4UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 8UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 16UE|fairness|latency|conservation               |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | QoS-PF             | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 2UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | QoS-PF             | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 4UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | QoS-PF             | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 8UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | QoS-PF             | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 16UE|fairness|latency|conservation               |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | EDF                | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 2UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | EDF                | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 4UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | EDF                | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 8UE|fairness|latency|conservation                |
| nr_rel18_qos_scheduler_strict    | BOTH        |              1 |              16 | EDF                | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | 16UE|fairness|latency|conservation               |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | short             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | exact_table|trigger_timer|pdu_roundtrip          |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | long              | single            | enabled           | singleTAG         | disabled          | disabled          | True        | exact_table|trigger_timer|pdu_roundtrip          |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | shortTruncated    | single            | enabled           | singleTAG         | disabled          | disabled          | True        | exact_table|trigger_timer|pdu_roundtrip          |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | longTruncated     | single            | enabled           | singleTAG         | disabled          | disabled          | True        | exact_table|trigger_timer|pdu_roundtrip          |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | refinedLong       | single            | enabled           | singleTAG         | disabled          | disabled          | True        | exact_table|trigger_timer|pdu_roundtrip          |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | exact             | type1             | enabled           | singleTAG         | disabled          | disabled          | True        | exact_mapping|trigger_timer|power_reconciliation |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | exact             | type2             | enabled           | singleTAG         | disabled          | disabled          | True        | exact_mapping|trigger_timer|power_reconciliation |
| nr_rel18_bsr_phr_sr_strict       | UL          |              1 |              16 | PF                 | exact             | type3             | enabled           | singleTAG         | disabled          | disabled          | True        | exact_mapping|trigger_timer|power_reconciliation |
| nr_rel18_bsr_phr_sr_strict       | UL          |              2 |              16 | PF                 | exact             | multipleEntry     | enabled           | singleTAG         | disabled          | disabled          | True        | exact_mapping|trigger_timer|power_reconciliation |
| nr_rel18_persistent_grant_strict | BOTH        |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | true              | disabled          | True        | activation|occasion|release|harq                 |
| nr_rel18_persistent_grant_strict | BOTH        |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | false             | CG-Type1          | True        | activation|occasion|release|harq                 |
| nr_rel18_persistent_grant_strict | BOTH        |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | false             | CG-Type2          | True        | activation|occasion|release|harq                 |
| nr_rel18_ca_scheduler_strict     | BOTH        |              1 |              16 | PF                 | exact             | multiple          | enabled           | multiTAG          | enabled           | Type1|Type2       | True        | per_cell_state|cross_carrier|feedback            |
| nr_rel18_ca_scheduler_strict     | BOTH        |              1 |              16 | QoS-PF             | exact             | multiple          | enabled           | multiTAG          | enabled           | Type1|Type2       | True        | per_cell_state|cross_carrier|feedback            |
| nr_rel18_ca_scheduler_strict     | BOTH        |              2 |              16 | PF                 | exact             | multiple          | enabled           | multiTAG          | enabled           | Type1|Type2       | True        | per_cell_state|cross_carrier|feedback            |
| nr_rel18_ca_scheduler_strict     | BOTH        |              2 |              16 | QoS-PF             | exact             | multiple          | enabled           | multiTAG          | enabled           | Type1|Type2       | True        | per_cell_state|cross_carrier|feedback            |
| nr_rel18_timing_advance_strict   | UL          |              1 |              16 | PF                 | exact             | single            | enabled           | singleTAG         | disabled          | disabled          | True        | sample_shift|timer|ul_gating                     |
| nr_rel18_timing_advance_strict   | UL          |              2 |              16 | PF                 | exact             | single            | enabled           | multiTAG          | disabled          | disabled          | True        | sample_shift|timer|ul_gating                     |
| nr_rel18_timing_advance_strict   | UL          |              1 |              16 | PF                 | exact             | single            | enabled           | absoluteTA        | disabled          | disabled          | True        | sample_shift|timer|ul_gating                     |
| nr_rel18_timing_advance_strict   | UL          |              1 |              16 | PF                 | exact             | single            | enabled           | TAReport          | disabled          | disabled          | True        | sample_shift|timer|ul_gating                     |
| unsupported_extension            | BOTH        |              1 |              16 | IAB-specialized    | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | False       | planning_rejection                               |
| unsupported_extension            | BOTH        |              1 |              16 | MBS-specific       | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | False       | planning_rejection                               |
| unsupported_extension            | BOTH        |              1 |              16 | Sidelink-MAC       | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | False       | planning_rejection                               |
| unsupported_extension            | BOTH        |              1 |              16 | NTN-Koffset        | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | False       | planning_rejection                               |
| unsupported_extension            | BOTH        |              1 |              16 | RedCap-eLCID-full  | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | False       | planning_rejection                               |
| unsupported_extension            | BOTH        |              1 |              16 | NR-U-LBT-scheduler | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | profile_dependent | False       | planning_rejection                               |

# Appendix B. Complete MATLAB test plan

| TestName                             | Scope             | Mandatory   | RequiredResult   |
|:-------------------------------------|:------------------|:------------|:-----------------|
| testMACEventStoreReplay              | event store       | True        | PASS             |
| testMACContextProjection             | state ownership   | True        | PASS             |
| testCentralMACTimingK0K1K2           | timing            | True        | PASS             |
| testCentralMACTimingTDD              | timing            | True        | PASS             |
| testHARQDLStateMachine               | HARQ              | True        | PASS             |
| testHARQULStateMachine               | HARQ              | True        | PASS             |
| testHARQIdentityKeys                 | HARQ              | True        | PASS             |
| testHARQFeedbackACKNACKDTX           | HARQ              | True        | PASS             |
| testHARQCodebookBinding              | HARQ              | True        | PASS             |
| testHARQProcessExhaustion            | HARQ              | True        | PASS             |
| testHARQSoftBufferProvenance         | HARQ              | True        | PASS             |
| testHARQSoftCombiningGain            | HARQ              | True        | PASS             |
| testHARQResetAndFlush                | HARQ              | True        | PASS             |
| testSPSState                         | persistent grants | True        | PASS             |
| testConfiguredGrantType1State        | persistent grants | True        | PASS             |
| testConfiguredGrantType2State        | persistent grants | True        | PASS             |
| testExactBSR5BitTable                | BSR               | True        | PASS             |
| testExactBSR8BitTable                | BSR               | True        | PASS             |
| testExactRefinedBSRTable             | BSR               | True        | PASS             |
| testBSRTriggersAndTimers             | BSR               | True        | PASS             |
| testBSRFormats                       | BSR               | True        | PASS             |
| testExactPHMapping                   | PHR               | True        | PASS             |
| testExactPCMAXMapping                | PHR               | True        | PASS             |
| testPHRTriggersAndTimers             | PHR               | True        | PASS             |
| testMultipleEntryPHR                 | PHR               | True        | PASS             |
| testSchedulingRequestState           | SR                | True        | PASS             |
| testSchedulingRequestFallback        | SR                | True        | PASS             |
| testLogicalChannelBj                 | LCP               | True        | PASS             |
| testLogicalChannelPriority           | LCP               | True        | PASS             |
| testLogicalChannelRestrictions       | LCP               | True        | PASS             |
| testMACSubheaderCodec                | PDU               | True        | PASS             |
| testMACPDUAssemblyDemux              | PDU               | True        | PASS             |
| testMACCEPriority                    | PDU               | True        | PASS             |
| testMACPDUNegativeMatrix             | PDU               | True        | PASS             |
| testTimingAdvanceCommand             | TA                | True        | PASS             |
| testTimeAlignmentTimer               | TA                | True        | PASS             |
| testMultipleTAG                      | TA                | True        | PASS             |
| testUEEligibilityEngine              | eligibility       | True        | PASS             |
| testAtomicGrantCommit                | scheduler         | True        | PASS             |
| testSchedulerRR                      | scheduler         | True        | PASS             |
| testSchedulerPF                      | scheduler         | True        | PASS             |
| testSchedulerQoSPF                   | scheduler         | True        | PASS             |
| testSchedulerEDF                     | scheduler         | True        | PASS             |
| testSchedulerRetransmissionPriority  | scheduler         | True        | PASS             |
| testSchedulerFairnessAndStarvation   | scheduler         | True        | PASS             |
| testSchedulerQoSAndDeadlines         | scheduler         | True        | PASS             |
| testTwoCellHARQIsolation             | CA                | True        | PASS             |
| testCrossCarrierGrantState           | CA                | True        | PASS             |
| testPacketLineageGraph               | lineage           | True        | PASS             |
| testByteBitConservation              | lineage           | True        | PASS             |
| testFirstSuccessDeduplication        | lineage           | True        | PASS             |
| testMACNoNoiseClosedLoop             | end-to-end        | True        | PASS             |
| testMACAWGNCampaign                  | end-to-end        | True        | PASS             |
| testMACTDLCampaign                   | end-to-end        | True        | PASS             |
| testMACCDLCampaign                   | end-to-end        | True        | PASS             |
| testMACFaultInjection                | negative          | True        | PASS             |
| testMACArtifactGeneration            | artifacts         | True        | PASS             |
| testMACImpactAnalysis                | impact            | True        | PASS             |
| testMACSerialParallelReproducibility | reproducibility   | True        | PASS             |
| testMACFullRepositoryRegression      | regression        | True        | PASS             |

# Appendix C. Complete base CSV contract

| FileName                           | PrimaryKey                                                          | RequiredColumns                                                                                                                                                                                 |   MinRows |
|:-----------------------------------|:--------------------------------------------------------------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------:|
| mac_run_manifest.csv               | RunID                                                               | RunID|GitCommit|MATLABVersion|ToolboxVersion|SpecProfile|SeedList|VectorManifestSHA256|Strict|Status                                                                                            |         1 |
| mac_event_log.csv                  | RunID|EventSequence                                                 | RunID|EventSequence|EventID|EventType|UEID|ServingCell|Direction|AbsoluteSlot|AbsoluteSymbol|SourceEventID|PayloadSHA256|Status                                                                 |        50 |
| mac_ue_context_projection.csv      | RunID|EventSequence|UEID|ServingCell                                | RunID|EventSequence|UEID|ServingCell|RRCState|ActiveDLBWP|ActiveULBWP|DRXState|TimeAligned|ConfigurationEpoch|ProjectionSHA256|Status                                                           |        20 |
| mac_timing_decisions.csv           | RunID|DecisionID                                                    | RunID|DecisionID|UEID|Direction|SourceDCIEventID|K0|K1|K2|PDCCHSlot|PDSCHSlot|PUSCHSlot|FeedbackSlot|TDDLegal|ProcessingLegal|ResourceLegal|Status                                              |        20 |
| mac_harq_process_states.csv        | RunID|EventSequence|Direction|ServingCell|UEID|HARQProcess|Codeword | RunID|EventSequence|Direction|ServingCell|UEID|HARQProcess|Codeword|NDI|NDIEpoch|RV|TBID|State|TransitionEvent|SourceEventID|Status                                                             |        50 |
| mac_harq_attempts.csv              | RunID|AttemptID                                                     | RunID|AttemptID|Direction|ServingCell|UEID|HARQProcess|Codeword|NDIEpoch|TBID|GrantID|RV|AttemptIndex|ScheduleSlot|TxSlot|TBSBits|CodingLayoutSHA256|Status                                     |        30 |
| mac_harq_feedback.csv              | RunID|FeedbackEventID                                               | RunID|FeedbackEventID|UEID|ServingCell|HARQProcess|Codeword|SourceAttemptID|CodebookType|DAI|BitPosition|Outcome|DueSlot|ReceivedSlot|Applied|Reason|Status                                     |        20 |
| mac_soft_buffer_ledger.csv         | RunID|LedgerRowID                                                   | RunID|LedgerRowID|AttemptID|TBID|Codeword|NDIEpoch|RV|MotherCodeIndex|LLRSum|ObservationWeight|CodingLayoutSHA256|RateMatchSHA256|ChannelRealizationID|NoiseRealizationID|ReceiverSHA256|Status |        50 |
| mac_bsr_state.csv                  | RunID|EventSequence|UEID|LCGID                                      | RunID|EventSequence|UEID|LCGID|BufferBytes|Trigger|PeriodicTimer|RetxTimer|ReportFormat|BSIndex|TableID|MACPDUId|Status                                                                         |        20 |
| mac_bsr_table_results.csv          | TableID|Index                                                       | TableID|Index|ExpectedLower|ExpectedUpper|ActualLower|ActualUpper|BoundaryMismatchCount|Status                                                                                                  |       544 |
| mac_phr_state.csv                  | RunID|EventSequence|UEID|ServingCell                                | RunID|EventSequence|UEID|ServingCell|PHType|PH_dB|PHIndex|PCMAX_dBm|PCMAXIndex|Trigger|PeriodicTimer|ProhibitTimer|PowerBackoff|MACPDUId|Status                                                 |        20 |
| mac_phr_mapping_results.csv        | Mapping|Index                                                       | Mapping|Index|ExpectedLower|ExpectedUpper|ActualLower|ActualUpper|BoundaryMismatchCount|Status                                                                                                  |       128 |
| mac_sr_state.csv                   | RunID|EventSequence|UEID|SRID                                       | RunID|EventSequence|UEID|SRID|State|Trigger|PendingCause|ProhibitTimer|TxCounter|ResourceID|OccasionSlot|CancelledByEventID|Status                                                              |        20 |
| mac_logical_channel_state.csv      | RunID|EventSequence|UEID|LCID                                       | RunID|EventSequence|UEID|LCID|LCGID|Priority|PBR_kBps|BSD_ms|Bj_Bytes|QueueBytes|HoLDelay_ms|AllowedServingCell|AllowedSCS_kHz|Eligible|Status                                                  |        20 |
| mac_lcp_decisions.csv              | RunID|DecisionID|LCID                                               | RunID|DecisionID|UEID|GrantBytes|LCID|Priority|BjBefore|EligibleBytes|SelectedBytes|BjAfter|SelectionOrder|RejectionReason|Status                                                               |        20 |
| mac_pdu_subpdus.csv                | RunID|MACPDUId|SubPDUIndex                                          | RunID|MACPDUId|Direction|SubPDUIndex|LCID|eLCID|Kind|HeaderOffset|HeaderLength|PayloadOffset|PayloadLength|OwnerID|PayloadSHA256|Status                                                         |        30 |
| mac_pdu_roundtrip.csv              | RunID|MACPDUId                                                      | RunID|MACPDUId|Direction|TBSBytes|SubPDUCount|EncodedSHA256|DecodedSHA256|ByteMismatchCount|UnownedBytes|OverlappingBytes|PaddingBytes|Status                                                   |        10 |
| mac_ce_selection.csv               | RunID|DecisionID|CEID                                               | RunID|DecisionID|UEID|CEID|CEType|TriggerEventID|Priority|RequiredBytes|Selected|RejectedReason|CancelledBy|MACPDUId|Status                                                                     |        20 |
| mac_timing_advance_state.csv       | RunID|EventSequence|UEID|TAGID                                      | RunID|EventSequence|UEID|TAGID|NTA|AppliedSampleShift|CommandType|CommandValue|TimerState|TimerExpirySlot|ULAllowed|SourceEventID|Status                                                        |        20 |
| mac_eligibility_decisions.csv      | RunID|DecisionID|UEID|Direction                                     | RunID|DecisionID|UEID|Direction|RRCEligible|BWPEligible|DRXEligible|GapEligible|HalfDuplexEligible|TDDEligible|TAEligible|PowerEligible|ControlEligible|OverallEligible|Reasons|Status          |        20 |
| mac_scheduler_snapshots.csv        | RunID|SnapshotID|UEID                                               | RunID|SnapshotID|UEID|ServingCell|Direction|QueueBytes|HoLDelay_ms|FiveQI|GBR_kbps|MBR_kbps|PDB_ms|MeasuredCQI|CSIAgeSlots|PH_dB|HARQUrgency|Eligible|SnapshotSHA256|Status                     |        20 |
| mac_scheduler_candidates.csv       | RunID|CandidateID                                                   | RunID|CandidateID|SnapshotID|Policy|UEID|Metric|Rank|RequestedPRBs|RequestedSymbols|RequestedTBSBits|HARQProcess|IsRetransmission|RejectionReason|Status                                        |        20 |
| mac_scheduler_grants.csv           | RunID|GrantID                                                       | RunID|GrantID|CandidateID|DecodedDCIEventID|UEID|ServingCell|ScheduledCell|Direction|BWPID|PRBSet|SymbolAllocation|MCS|TBSBits|HARQProcess|Codeword|NDIEpoch|RV|Committed|GrantSHA256|Status    |        20 |
| mac_scheduler_metrics.csv          | RunID|Policy|UEID                                                   | RunID|Policy|UEID|OfferedBits|ScheduledBits|DeliveredBits|DroppedBits|ThroughputMbps|GoodputMbps|MeanDelay_ms|P95Delay_ms|DeadlineMissRate|JainFairness|StarvationSlots|Status                  |        10 |
| mac_packet_lineage_nodes.csv       | RunID|NodeID                                                        | RunID|NodeID|NodeType|ParentNodeID|PacketID|FlowID|UEID|Bytes|Bits|SHA256|CreatedEventID|Disposition|Status                                                                                     |        50 |
| mac_packet_lineage_edges.csv       | RunID|EdgeID                                                        | RunID|EdgeID|FromNodeID|ToNodeID|EdgeType|Bytes|Bits|SourceEventID|Status                                                                                                                       |        50 |
| mac_conservation_ledger.csv        | RunID|FlowID                                                        | RunID|FlowID|ArrivedBytes|QueuedBytes|InFlightBytes|DeliveredBytes|DroppedBytes|UnownedBytes|DuplicateDeliveredBytes|EquationErrorBytes|Status                                                  |         5 |
| mac_negative_tests.csv             | CaseID                                                              | CaseID|FaultType|ExpectedError|ActualError|HARQStateChanged|QueueStateChanged|WaveformGenerated|GrantCommitted|DeliveryCounted|Passed|Status                                                    |        25 |
| mac_independent_vector_results.csv | VectorFamily                                                        | VectorFamily|OracleClass|OracleImplementation|OracleVersion|OracleArtifactSHA256|Cases|MismatchCount|MaxAbsoluteError|Status                                                                    |        15 |
| mac_test_summary.csv               | TestName                                                            | TestName|Scope|Mandatory|Executed|Passed|Total|Failed|Skipped|Blocked|DurationSeconds|Status                                                                                                    |        20 |
| mac_image_semantic_audit.csv       | ImageFile                                                           | RunID|ImageFile|SourceCSV|SourceCSV_SHA256|PNG_SHA256|Width|Height|AxesCount|SeriesCount|FinitePointCount|ActualTitle|ActualXLabel|ActualYLabel|Status                                          |        22 |
| mac_capability_resolution.csv      | ProfileID|TupleID                                                   | ProfileID|TupleID|ExpectedSupported|ActualSupported|PlanningRejected|StateChanged|Reason|Status                                                                                                 |        20 |

# Appendix D. Complete base image contract

| ImageFile                       | SourceCSV                                                               | ExpectedTitleToken                     | ExpectedXLabel        | ExpectedYLabel          |   MinAxesCount |   MinSeriesCount |   MinFinitePointCount |   MinWidth |   MinHeight |
|:--------------------------------|:------------------------------------------------------------------------|:---------------------------------------|:----------------------|:------------------------|---------------:|-----------------:|----------------------:|-----------:|------------:|
| mac_event_state_timeline.png    | mac_event_log.csv|mac_ue_context_projection.csv                         | MAC event and UE state timeline        | Absolute slot         | State/event             |              1 |                3 |                    20 |        900 |         600 |
| mac_harq_process_timeline.png   | mac_harq_process_states.csv                                             | HARQ process state timeline            | Absolute slot         | HARQ state              |              1 |                4 |                    20 |        900 |         600 |
| mac_ndi_rv_attempt_timeline.png | mac_harq_attempts.csv                                                   | NDI RV and attempt timeline            | Transmission attempt  | NDI / RV                |              1 |                3 |                    20 |        900 |         600 |
| mac_k0_k1_k2_timeline.png       | mac_timing_decisions.csv                                                | K0 K1 K2 timing timeline               | PDCCH slot            | Target slot             |              1 |                3 |                    20 |        900 |         600 |
| mac_tdd_eligibility_map.png     | mac_timing_decisions.csv|mac_eligibility_decisions.csv                  | TDD and eligibility map                | Absolute symbol       | Direction / eligibility |              1 |                3 |                    20 |        900 |         600 |
| mac_harq_feedback_codebook.png  | mac_harq_feedback.csv                                                   | HARQ feedback codebook mapping         | Feedback bit position | Outcome                 |              1 |                3 |                    20 |        900 |         600 |
| mac_soft_combining_gain.png     | mac_soft_buffer_ledger.csv|mac_harq_attempts.csv                        | HARQ soft combining evidence           | Attempt               | Combining metric        |              1 |                2 |                    20 |        900 |         600 |
| mac_harq_process_occupancy.png  | mac_harq_process_states.csv                                             | HARQ process occupancy                 | Absolute slot         | Active processes        |              1 |                2 |                    20 |        900 |         600 |
| mac_bsr_buffer_timeline.png     | mac_bsr_state.csv                                                       | BSR and buffer timeline                | Absolute slot         | Buffer bytes            |              1 |                3 |                    20 |        900 |         600 |
| mac_bsr_quantization_error.png  | mac_bsr_table_results.csv                                               | BSR table quantization boundaries      | BSR index             | Buffer bytes            |              1 |                3 |                    32 |        900 |         600 |
| mac_phr_power_timeline.png      | mac_phr_state.csv                                                       | Power headroom and PCMAX timeline      | Absolute slot         | Power dB / dBm          |              1 |                3 |                    20 |        900 |         600 |
| mac_sr_state_timeline.png       | mac_sr_state.csv                                                        | Scheduling Request state timeline      | Absolute slot         | SR state                |              1 |                2 |                    20 |        900 |         600 |
| mac_lcp_bj_timeline.png         | mac_logical_channel_state.csv|mac_lcp_decisions.csv                     | Logical channel Bj and selection       | Absolute slot         | Bytes                   |              1 |                4 |                    20 |        900 |         600 |
| mac_pdu_composition.png         | mac_pdu_subpdus.csv                                                     | MAC PDU composition                    | Byte offset           | SubPDU owner            |              1 |                4 |                    20 |        900 |         600 |
| mac_ce_priority_selection.png   | mac_ce_selection.csv                                                    | MAC CE priority and selection          | CE priority           | Selected bytes          |              1 |                3 |                    20 |        900 |         600 |
| mac_timing_advance_timeline.png | mac_timing_advance_state.csv                                            | Timing advance and alignment timer     | Absolute slot         | NTA / timer             |              1 |                3 |                    20 |        900 |         600 |
| mac_scheduler_allocation.png    | mac_scheduler_grants.csv                                                | Scheduler resource allocation          | Absolute slot         | PRB / UE                |              1 |                4 |                    20 |        900 |         600 |
| mac_scheduler_fairness.png      | mac_scheduler_metrics.csv                                               | Scheduler throughput and Jain fairness | UE                    | Throughput Mbps         |              1 |                4 |                    10 |        900 |         600 |
| mac_qos_latency_cdf.png         | mac_scheduler_metrics.csv                                               | QoS packet latency CDF                 | Latency ms            | CDF                     |              1 |                4 |                    20 |        900 |         600 |
| mac_packet_lineage_graph.png    | mac_packet_lineage_nodes.csv|mac_packet_lineage_edges.csv               | Packet to HARQ delivery lineage        | Processing stage      | Bytes                   |              1 |                5 |                    20 |        900 |         600 |
| mac_conservation_balance.png    | mac_conservation_ledger.csv                                             | Packet and byte conservation           | Flow                  | Bytes                   |              1 |                5 |                    10 |        900 |         600 |
| mac_grant_authority_trace.png   | mac_scheduler_candidates.csv|mac_scheduler_grants.csv|mac_event_log.csv | Decoded grant authority trace          | Event sequence        | Grant state             |              1 |                4 |                    20 |        900 |         600 |

# Appendix E. Complete impact-family registry

| FamilyID   | Title                                 | Wave   | FactorName         | BaselineValue   | TreatmentValue     | PrimaryMetrics                  | Implementability                            | RequiredDesign                          |
|:-----------|:--------------------------------------|:-------|:-------------------|:----------------|:-------------------|:--------------------------------|:--------------------------------------------|:----------------------------------------|
| F01        | HARQ process count                    | A      | HARQProcesses      | 4               | 16                 | throughput|blocking|latency     | Implement in this phase                     | paired common-random-numbers experiment |
| F02        | Maximum retransmissions               | A      | MaxRetx            | 1               | 4                  | BLER|latency|goodput            | Implement in this phase                     | paired common-random-numbers experiment |
| F03        | RV sequence                           | A      | RVSequence         | 0|0|0|0         | 0|2|3|1            | combining_gain|BLER             | Implement in this phase                     | paired common-random-numbers experiment |
| F04        | NDI epoch enforcement                 | A      | NDIEpochCheck      | off             | on                 | false_delivery|state_error      | Implement in this phase                     | paired common-random-numbers experiment |
| F05        | ACK versus DTX handling               | A      | DTXPolicy          | nack_alias      | explicit           | BLER|retx|false_ack             | Implement in this phase                     | paired common-random-numbers experiment |
| F06        | HARQ feedback codebook                | B      | Codebook           | type1           | type2              | payload|latency|errors          | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F07        | K1 timing                             | A      | K1                 | 4               | decoded            | feedback_legality|latency       | Implement in this phase                     | paired common-random-numbers experiment |
| F08        | K2 timing                             | A      | K2                 | 1               | decoded            | ul_latency|grant_legality       | Implement in this phase                     | paired common-random-numbers experiment |
| F09        | TDD flexible symbol resolution        | A      | FlexPolicy         | force_dl        | scheduler_resolved | collision|utilization           | Implement in this phase                     | paired common-random-numbers experiment |
| F10        | HARQ process exhaustion               | A      | OfferedLoad        | low             | high               | blocking|queue|latency          | Implement in this phase                     | paired common-random-numbers experiment |
| F11        | Soft combining provenance             | A      | ProvenanceCheck    | partial         | complete           | false_decode|gain               | Implement in this phase                     | paired common-random-numbers experiment |
| F12        | Soft buffer position awareness        | A      | PositionAware      | off             | on                 | BLER|combining_gain             | Implement in this phase                     | paired common-random-numbers experiment |
| F13        | Soft buffer age/reset                 | A      | ResetPolicy        | heuristic       | event_driven       | drop|memory|errors              | Implement in this phase                     | paired common-random-numbers experiment |
| F14        | Scheduler policy RR versus PF         | A      | Scheduler          | RR              | PF                 | throughput|fairness             | Implement in this phase                     | paired common-random-numbers experiment |
| F15        | PF averaging window                   | A      | PFTau_ms           | 50              | 500                | fairness|responsiveness         | Implement in this phase                     | paired common-random-numbers experiment |
| F16        | QoS-PF policy                         | A      | Scheduler          | PF              | QoS-PF             | pdb_miss|fairness|goodput       | Implement in this phase                     | paired common-random-numbers experiment |
| F17        | EDF policy                            | A      | Scheduler          | PF              | EDF                | deadline_miss|throughput        | Implement in this phase                     | paired common-random-numbers experiment |
| F18        | Retransmission priority               | A      | RetxPriority       | off             | on                 | latency|drop|fairness           | Implement in this phase                     | paired common-random-numbers experiment |
| F19        | Control overhead accounting           | A      | ControlOverhead    | ignored         | included           | net_goodput|allocation          | Implement in this phase                     | paired common-random-numbers experiment |
| F20        | CQI age gating                        | B      | CSIAgePolicy       | accept_stale    | reject_stale       | BLER|utilization                | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F21        | BSR 5-bit exact table                 | A      | BSRMapping         | approx          | exact5             | demand_error|throughput         | Implement in this phase                     | paired common-random-numbers experiment |
| F22        | BSR 8-bit exact table                 | A      | BSRMapping         | approx          | exact8             | demand_error|throughput         | Implement in this phase                     | paired common-random-numbers experiment |
| F23        | Refined BSR table                     | A      | BSRMapping         | normal8         | refined8           | quant_error|overhead            | Implement in this phase                     | paired common-random-numbers experiment |
| F24        | Regular BSR trigger                   | A      | BSRTrigger         | disabled        | regular            | ul_latency|overhead             | Implement in this phase                     | paired common-random-numbers experiment |
| F25        | Periodic BSR timer                    | A      | PeriodicBSR        | off             | on                 | staleness|overhead              | Implement in this phase                     | paired common-random-numbers experiment |
| F26        | Retx BSR timer                        | A      | RetxBSR            | off             | on                 | grant_recovery|latency          | Implement in this phase                     | paired common-random-numbers experiment |
| F27        | Truncated BSR                         | A      | TruncatedBSR       | off             | on                 | ce_fit|demand_error             | Implement in this phase                     | paired common-random-numbers experiment |
| F28        | PH exact mapping                      | A      | PHRMapping         | linear          | exact              | power_error|mcs                 | Implement in this phase                     | paired common-random-numbers experiment |
| F29        | PCMAX exact mapping                   | A      | PCMAXMapping       | linear          | exact              | power_error|clipping            | Implement in this phase                     | paired common-random-numbers experiment |
| F30        | PHR prohibit timer                    | A      | PHRProhibit        | off             | on                 | overhead|freshness              | Implement in this phase                     | paired common-random-numbers experiment |
| F31        | Multiple-entry PHR                    | B      | PHRMode            | single          | multiple           | ca_power|overhead               | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F32        | Scheduling Request state              | A      | SRState            | basic           | event_sourced      | access_latency|duplicates       | Implement in this phase                     | paired common-random-numbers experiment |
| F33        | SR prohibit timer                     | A      | SRProhibit         | off             | on                 | overhead|latency                | Implement in this phase                     | paired common-random-numbers experiment |
| F34        | SR-to-RA fallback                     | B      | SRFallback         | off             | on                 | recovery|latency                | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F35        | LCP priority only versus token bucket | A      | LCP                | priority_only   | pbr_bsd_bj         | qos|fairness                    | Implement in this phase                     | paired common-random-numbers experiment |
| F36        | PBR                                   | A      | PBR_kBps           | 8               | 256                | throughput|bj|starvation        | Implement in this phase                     | paired common-random-numbers experiment |
| F37        | Bucket size duration                  | A      | BSD_ms             | 10              | 100                | burst_delay|fairness            | Implement in this phase                     | paired common-random-numbers experiment |
| F38        | Logical-channel restrictions          | A      | LCRestrictions     | ignored         | enforced           | illegal_grant|utilization       | Implement in this phase                     | paired common-random-numbers experiment |
| F39        | MAC CE priority                       | A      | CEPriority         | fixed_order     | procedure_order    | ce_drop|latency                 | Implement in this phase                     | paired common-random-numbers experiment |
| F40        | MAC PDU exact subheaders              | A      | PDUCodec           | heuristic       | exact              | parse_error|overhead            | Implement in this phase                     | paired common-random-numbers experiment |
| F41        | eLCID support                         | B      | eLCID              | off             | bounded            | feature_coverage|overhead       | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F42        | SDU segmentation                      | A      | Segmentation       | drop_last       | segment            | goodput|drop                    | Implement in this phase                     | paired common-random-numbers experiment |
| F43        | Timing advance command                | B      | TA                 | off             | on                 | ul_sinr|crc                     | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F44        | timeAlignmentTimer                    | B      | TATimer            | ignored         | enforced           | illegal_ul|recovery             | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F45        | Multiple TAGs                         | C      | TAGs               | 1               | 2                  | ca_alignment|complexity         | Requires adjacent subsystem integration     | paired common-random-numbers experiment |
| F46        | UL timing error                       | B      | ResidualTA_samples | 0               | 8                  | EVM|BLER                        | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F47        | Configured grant Type 1               | B      | GrantMode          | dynamic         | CG1                | latency|overhead                | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F48        | Configured grant Type 2               | B      | GrantMode          | dynamic         | CG2                | latency|activation              | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F49        | Downlink SPS                          | B      | GrantMode          | dynamic         | SPS                | latency|overhead                | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F50        | Grant commit atomicity                | A      | CommitMode         | early_mutation  | atomic             | state_leak|errors               | Implement in this phase                     | paired common-random-numbers experiment |
| F51        | PDCCH decode authority                | B      | GrantAuthority     | configured      | decoded            | false_grant|throughput          | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F52        | Active BWP eligibility                | B      | BWPCheck           | off             | on                 | illegal_grant|utilization       | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F53        | DRX eligibility                       | C      | DRXCheck           | off             | on                 | power|latency|illegal_grant     | Requires adjacent subsystem integration     | paired common-random-numbers experiment |
| F54        | Measurement-gap eligibility           | C      | GapCheck           | off             | on                 | illegal_grant|throughput        | Requires adjacent subsystem integration     | paired common-random-numbers experiment |
| F55        | Two-cell HARQ isolation               | C      | Cells              | 1               | 2                  | state_leak|throughput           | Requires adjacent subsystem integration     | paired common-random-numbers experiment |
| F56        | Cross-carrier scheduling              | C      | CrossCarrier       | off             | on                 | latency|state_isolation         | Requires adjacent subsystem integration     | paired common-random-numbers experiment |
| F57        | Packet lineage graph                  | A      | Lineage            | partial         | complete           | orphan|duplicate|conservation   | Implement in this phase                     | paired common-random-numbers experiment |
| F58        | First-success delivery deduplication  | A      | Dedup              | off             | on                 | goodput_error                   | Implement in this phase                     | paired common-random-numbers experiment |
| F59        | Queue-byte conservation               | A      | Conservation       | unchecked       | checked            | byte_error|drop                 | Implement in this phase                     | paired common-random-numbers experiment |
| F60        | Bursty traffic                        | A      | Traffic            | full_buffer     | bursty             | latency|scheduler_response      | Implement in this phase                     | paired common-random-numbers experiment |
| F61        | Mixed 5QI traffic                     | B      | Traffic            | single_qos      | mixed_qos          | pdb_miss|fairness               | Requires internal cross-channel integration | paired common-random-numbers experiment |
| F62        | Runtime scaling                       | A      | NumUE              | 4               | 64                 | runtime|memory                  | Implement in this phase                     | paired common-random-numbers experiment |
| F63        | Serial/parallel reproducibility       | A      | Execution          | serial          | parallel           | artifact_hash|metrics           | Implement in this phase                     | paired common-random-numbers experiment |
| F64        | End-to-end closed loop                | C      | Mode               | shortcut        | full_event_chain   | throughput|latency|conservation | Requires adjacent subsystem integration     | paired common-random-numbers experiment |

# Appendix F. Complete impact CSV contract

| FileName                            | PrimaryKey              | RequiredColumns                                                                                                                                                                              |   MinRows |
|:------------------------------------|:------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------:|
| mac_impact_run_manifest.csv         | RunID                   | RunID|GitCommit|MATLABVersion|ToolboxVersion|SpecProfile|ExperimentMatrixSHA256|SeedList|Strict|Status                                                                                       |         1 |
| mac_impact_raw_trials.csv           | ExperimentID|TrialIndex | ExperimentID|FamilyID|PairID|Variant|TrialIndex|Seed|PayloadID|ChannelRealizationID|NoiseRealizationID|Direction|Outcome|Latency_ms|DeliveredBits|DroppedBits|HARQAttempts|Runtime_ms|Status |       768 |
| mac_impact_operating_points.csv     | ExperimentID            | ExperimentID|FamilyID|PairID|Variant|Trials|Errors|Incomplete|StopReason|BLER|CILower|CIUpper|MeanLatency_ms|MeanGoodputMbps|MeanFairness|MeanRuntime_ms|Status                              |       768 |
| mac_impact_pairwise_effects.csv     | FamilyID|PairID|Metric  | FamilyID|PairID|Metric|BaselineMean|TreatmentMean|Effect|CILower|CIUpper|PValue|AdjustedPValue|EffectSize|Conclusion|Status                                                                  |       192 |
| mac_impact_rule_evaluation.csv      | RuleID                  | RuleID|FamilyID|Severity|Metric|ObservedValue|Operator|Threshold|EvidenceRows|Result|Status                                                                                                  |        96 |
| mac_impact_harq.csv                 | FamilyID|PairID         | FamilyID|PairID|ProcessBlockingEffect|RetxEffect|CombiningGainDB|FalseDeliveryCount|MeanHARQAttempts|Status                                                                                  |        20 |
| mac_impact_timing.csv               | FamilyID|PairID         | FamilyID|PairID|K1EffectSlots|K2EffectSlots|IllegalGrantCount|FeedbackMissCount|LatencyEffect_ms|Status                                                                                      |        20 |
| mac_impact_bsr_phr_sr.csv           | FamilyID|PairID         | FamilyID|PairID|BSRIndexError|DemandErrorBytes|PHIndexError|PCMAXIndexError|SRLatencyEffect_ms|ControlOverheadBytes|Status                                                                   |        20 |
| mac_impact_lcp_pdu.csv              | FamilyID|PairID         | FamilyID|PairID|BjErrorBytes|PriorityViolationCount|PDUParseErrors|CESelectionErrors|SegmentationDropBytes|Status                                                                            |        20 |
| mac_impact_scheduler.csv            | FamilyID|PairID|UEID    | FamilyID|PairID|UEID|ThroughputEffectMbps|LatencyEffect_ms|DeadlineMissEffect|FairnessEffect|StarvationEffectSlots|Status                                                                    |        20 |
| mac_impact_timing_advance.csv       | FamilyID|PairID         | FamilyID|PairID|NTAError|ResidualTimingSamples|ULBLEREffect|IllegalULCount|RecoveryLatency_ms|Status                                                                                         |        10 |
| mac_impact_persistent_grants.csv    | FamilyID|PairID         | FamilyID|PairID|AccessLatencyEffect_ms|ControlOverheadEffectBytes|WrongOccasionCount|ActivationErrors|CollisionCount|Status                                                                  |        10 |
| mac_impact_lineage.csv              | FamilyID|PairID         | FamilyID|PairID|OrphanNodes|UnownedBytes|DuplicateDeliveredBytes|ConservationErrorBytes|GoodputAccountingErrorBits|Status                                                                    |        10 |
| mac_impact_runtime.csv              | FamilyID|PairID         | FamilyID|PairID|BaselineRuntime_ms|TreatmentRuntime_ms|RuntimeEffect_ms|BaselineMemoryMB|TreatmentMemoryMB|MemoryEffectMB|Status                                                             |        20 |
| mac_impact_summary.csv              | FamilyID                | FamilyID|Title|Wave|ExperimentsExpected|ExperimentsComplete|RulesPassed|RulesFailed|PrimaryConclusion|IncompletePoints|Status                                                                |        64 |
| mac_impact_image_semantic_audit.csv | ImageFile               | RunID|ImageFile|SourceCSV|SourceCSV_SHA256|PNG_SHA256|Width|Height|AxesCount|SeriesCount|FinitePointCount|ActualTitle|ActualXLabel|ActualYLabel|Status                                       |        30 |

# Appendix G. Complete impact image contract

| ImageFile                           | SourceCSV                        | ExpectedTitleToken              | ExpectedXLabel           | ExpectedYLabel            |   MinAxesCount |   MinSeriesCount |   MinFinitePointCount |   MinWidth |   MinHeight |
|:------------------------------------|:---------------------------------|:--------------------------------|:-------------------------|:--------------------------|---------------:|-----------------:|----------------------:|-----------:|------------:|
| mac_impact_harq_process_count.png   | mac_impact_harq.csv              | HARQ process count impact       | HARQ processes           | Blocking / throughput     |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_retransmissions.png      | mac_impact_harq.csv              | HARQ retransmission impact      | Maximum retransmissions  | BLER / latency            |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_rv_combining.png         | mac_impact_harq.csv              | RV sequence combining impact    | HARQ round               | Combining gain dB         |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_ack_dtx.png              | mac_impact_harq.csv              | ACK NACK DTX impact             | Feedback outcome         | Process result            |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_k1_k2.png                | mac_impact_timing.csv            | K1 K2 timing impact             | Timing configuration     | Latency / legality        |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_tdd_flex.png             | mac_impact_timing.csv            | Flexible TDD allocation impact  | Flexible policy          | Collision / utilization   |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_scheduler_policy.png     | mac_impact_scheduler.csv         | Scheduler policy comparison     | Scheduler policy         | Goodput Mbps              |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_fairness_latency.png     | mac_impact_scheduler.csv         | Fairness and latency tradeoff   | Jain fairness            | Latency ms                |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_qos_deadlines.png        | mac_impact_scheduler.csv         | QoS deadline impact             | Offered load             | Deadline miss rate        |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_bsr_mapping.png          | mac_impact_bsr_phr_sr.csv        | BSR mapping impact              | Buffer bytes             | Demand error bytes        |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_bsr_timers.png           | mac_impact_bsr_phr_sr.csv        | BSR timer impact                | Timer configuration      | Latency / overhead        |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_phr_mapping.png          | mac_impact_bsr_phr_sr.csv        | PHR mapping impact              | Power headroom dB        | Index / power error       |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_sr_state.png             | mac_impact_bsr_phr_sr.csv        | Scheduling Request state impact | SR state                 | Latency / overhead        |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_lcp_bj.png               | mac_impact_lcp_pdu.csv           | LCP token bucket impact         | Time ms                  | Bj bytes                  |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_pdu_codec.png            | mac_impact_lcp_pdu.csv           | MAC PDU codec impact            | PDU size bytes           | Parse errors              |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_ce_priority.png          | mac_impact_lcp_pdu.csv           | MAC CE priority impact          | Grant bytes              | Selected CE bytes         |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_segmentation.png         | mac_impact_lcp_pdu.csv           | SDU segmentation impact         | Grant bytes              | Dropped / delivered bytes |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_timing_advance.png       | mac_impact_timing_advance.csv    | Timing advance impact           | Residual timing samples  | UL BLER                   |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_time_alignment_timer.png | mac_impact_timing_advance.csv    | Time alignment timer impact     | Time slot                | UL eligibility            |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_persistent_grants.png    | mac_impact_persistent_grants.csv | Persistent grant impact         | Grant mode               | Latency / overhead        |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_grant_atomicity.png      | mac_impact_persistent_grants.csv | Atomic grant commit impact      | Fault injection          | State leakage             |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_two_cell_isolation.png   | mac_impact_lineage.csv           | Two-cell HARQ isolation impact  | Serving cell             | State errors              |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_lineage.png              | mac_impact_lineage.csv           | Packet lineage impact           | Processing stage         | Bytes                     |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_conservation.png         | mac_impact_lineage.csv           | Byte conservation impact        | Flow                     | Conservation error        |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_goodput_dedup.png        | mac_impact_lineage.csv           | First-success goodput impact    | HARQ attempt             | Counted goodput bits      |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_runtime_scaling.png      | mac_impact_runtime.csv           | MAC runtime scaling             | Number of UEs            | Runtime ms                |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_memory_scaling.png       | mac_impact_runtime.csv           | MAC memory scaling              | Number of UEs            | Memory MB                 |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_reproducibility.png      | mac_impact_runtime.csv           | Serial parallel reproducibility | Execution mode           | Metric difference         |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_effect_forest.png        | mac_impact_pairwise_effects.csv  | MAC impact effect forest        | Treatment minus baseline | Effect size               |              1 |                2 |                    10 |        900 |         600 |
| mac_impact_end_to_end.png           | mac_impact_summary.csv           | End-to-end MAC impact summary   | Impact family            | Pass / effect             |              1 |                2 |                    10 |        900 |         600 |

# Appendix H. Independent-vector manifest

```json
{
  "manifest_version": "1.0",
  "generator": "independent Python table/state/vector generator; no MATLAB or 5G Toolbox used",
  "specification_profile": "3GPP Release 18 bounded MAC/HARQ profile",
  "files": [
    {
      "path": "expected_bsr_5bit_table.csv",
      "rows": 32,
      "sha256": "ecdfaaabb579df01fcd1835848ba01d4ed34d7f529b5320a424524092c84fa90",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "expected_bsr_8bit_table.csv",
      "rows": 256,
      "sha256": "549a9302b130d4f509b97e2738c22b0a603cfc8206dab0f346f83993cbacd6fe",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "expected_refined_bsr_8bit_table.csv",
      "rows": 256,
      "sha256": "0f1555517e6d50e9c07ae2a3d2a136a584dcb257256a6917f68ea1a489a3584d",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "expected_phr_mapping.csv",
      "rows": 64,
      "sha256": "0ccb8779c83baa7e1b93670367a5e55db13d509aae7fa9027d1d9d664580406a",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "expected_pcmax_mapping.csv",
      "rows": 64,
      "sha256": "490202dd8af2dddc723904983174c1277f6021560fdc426d237c3236bbdea759",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_harq_state_transition_vectors.csv",
      "rows": 150,
      "sha256": "4ce609bdf0bc80ceed0f9dbf8ce0a9a97e4b3d98f2502c9128a6c2ccea7842c9",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_harq_feedback_codebook_vectors.csv",
      "rows": 120,
      "sha256": "6518500f0554be275296e8df85869ffc4d7224a51b5c86373feb9b3a58b7bf71",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_timing_k0_k1_k2_vectors.csv",
      "rows": 80,
      "sha256": "5adf2ad233d0402df9a4f6f8df9fcdd70f074b7c494707e82eff73c2ecd80b1c",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_tdd_eligibility_vectors.csv",
      "rows": 80,
      "sha256": "b4b3ca87d524c08e5bd0cc7fde9a83a24c849481a7d1dc877ce168b877840196",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_soft_buffer_provenance_vectors.csv",
      "rows": 64,
      "sha256": "8e559e6fd07dbdeb1e349e5df4616b992f372a6cec100289a5d93d960c3df06d",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_bsr_trigger_timer_vectors.csv",
      "rows": 120,
      "sha256": "a36dff41dcd1bacbf699e217a204ed5b4bf27c1aebf39a2e262916fb781a4e66",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_phr_trigger_timer_vectors.csv",
      "rows": 400,
      "sha256": "20117533a0448aeb9236cd08b5fa48848b7f2170e076c402d09d240660a0ab53",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_sr_state_vectors.csv",
      "rows": 32,
      "sha256": "229c01fd70839e29137912c913aa00db321b45b42902bbd54d65055c922a8673",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_lcp_test_vectors.csv",
      "rows": 300,
      "sha256": "22b0767aa4e7ad99d083e044cb8ab7affe298825e53ab96ce90c95d496ca2716",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_pdu_subheader_test_vectors.csv",
      "rows": 77,
      "sha256": "809a4bfa651d547427138a46baf484ed6055da92ec8f482885b50506df6f910a",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_ce_priority_test_vectors.csv",
      "rows": 288,
      "sha256": "98c30df2a51a7f03c7fdd7c043d86e7eaefd15eb52fe5c5118893db395bc9c57",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_timing_advance_test_vectors.csv",
      "rows": 105,
      "sha256": "9a8758765a49328dc723afa1c953562e7387ec692fb5d25e86ac65a9a183a973",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_scheduler_policy_test_vectors.csv",
      "rows": 360,
      "sha256": "1559327b939a2e82de8aa44d808a1ef1bbc56ab755ee6f12bdbd8b8b99aba1b3",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_packet_lineage_test_vectors.csv",
      "rows": 301,
      "sha256": "51dfbcc00aeea8a50cadb2ee481e663045590860409bd488b462b5a6ba3dd627",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_negative_test_vectors.csv",
      "rows": 150,
      "sha256": "e61be9f215c07c2707b76b1d23b78be2188d3cdba290946a55281ff2d717c0e9",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_declared_coverage_matrix.csv",
      "rows": 128,
      "sha256": "e49b1bdc793c05b0e18841619c042fe0b26227d7ff9233720fa86605f9fecef3",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_capability_profile_matrix.csv",
      "rows": 48,
      "sha256": "3cd11574c02ab50c03264ace83855d091bfb61386e4b965121870fef52e231b3",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_harq_scheduling_20_findings.csv",
      "rows": 20,
      "sha256": "9028b820b8f968823da702928e2a3292ccb1348eeef7114cf4b3d60d35f800dc",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_harq_error_contract.csv",
      "rows": 35,
      "sha256": "94635a091e503359508a0ffd40077ff6ffb2519021e99ac9c4deb9f543fb4e44",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_harq_implementation_task_graph.csv",
      "rows": 28,
      "sha256": "66c8b727d770210f23ea76557d30502941ef69fe61cd2f0b5a78e7a166f06fa7",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_harq_matlab_test_plan.csv",
      "rows": 60,
      "sha256": "e8d0449c78285921fb16dde1a8b6ea31a5fd7c49b2a5a78342ed4676d2648993",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_impact_analysis_families.csv",
      "rows": 64,
      "sha256": "0236a40169738e57914af79522a88292e20454007c11c7ba2d2a5d7f2d0ee3cc",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_impact_experiment_matrix.csv",
      "rows": 768,
      "sha256": "47098f650f06e218840ba59a10bc8f00bc6d3b29a0a3bdd003ebd1e74396fd37",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_impact_pairing_contract.csv",
      "rows": 64,
      "sha256": "bce7a426f21913acb64394d0504390dedeff5be463b3119050296e75024bf991",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_impact_acceptance_rules.csv",
      "rows": 96,
      "sha256": "ab9172e872b1d7ae6ec5e432ccf50d1e886e168ef3281fb55f278b6f198119aa",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_impact_dependency_waves.csv",
      "rows": 64,
      "sha256": "1853d04f026e414c5de2dc20c3ebb242f355e6c6896284ca33787a96392df8ae",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "mac_impact_implementability_summary.csv",
      "rows": 3,
      "sha256": "1aefed3793d963fd71ee6a247083dddacf5cda998f98f784102730f6b3da26ff",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    },
    {
      "path": "expected_mac_impact_analytical_floor.csv",
      "rows": 96,
      "sha256": "8bfbb0d8d3a8961ac873a4ff063c1381c7ab6dbc5ce603a57793e107ccdd2e09",
      "oracle_class": "pure_spec_table_or_deterministic_state_floor"
    }
  ]
}
```
