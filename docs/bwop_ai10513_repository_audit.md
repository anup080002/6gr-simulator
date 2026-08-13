# RAN1 AI 10.5.1.3 bandwidth-operation repository audit

Audit date: 2026-08-13
Repository: SixGR MATLAB / 5G Toolbox simulator
Branch/commit at audit: `main` / `7285ad78b6e1ab88a73676670c674ad6e36fb392`
Worktree at audit: dirty; pre-existing changes from other campaigns are retained and are not part of this audit.

## Environment

- MATLAB: R2026a Update 4, `26.1.0.3312084`.
- 5G Toolbox: `26.1`.
- 6G Exploration Library for 5G Toolbox: `26.1.5`.
- Communications Toolbox: `26.1`.
- Phased Array System Toolbox: `26.1`.
- RF Toolbox: `26.1`.
- Parallel Computing Toolbox: `26.1`.

The controlling source named by the implementation prompt,
`R1-26xxxxx_On_Bandwidth_Operation_During_and_Right_After_Initial_Access_for_6GR_Jio_v2.docx`,
was not found in the repository or `C:\Users\anup0\Downloads` during this audit. Therefore values explicitly described by the prompt as source-reported are usable only with the provenance label `source_baseline_from_supplied_prompt`; they cannot be presented as independently verified document extractions.

## Existing production modules that can be reused

| Domain | Existing authoritative implementation | Reuse decision |
|---|---|---|
| PBCH/MIB | `+sixgr/+phy/+dl/PBCH_Recovery.m`, `+sixgr/+phy/+ia/+c0/+receiver/recoverPBCH.m`, `+sixgr/+truth/bindStandalonePBCHTrial.m` | Reuse for high-SNR sanity and future practical payload curves. Do not replace with analytical capacity output. |
| PDCCH/DCI | `+sixgr/+phy/+pdcch/`, including `PDCCHTransmitter`, `PDCCHReceiver`, `PDCCHWaveformTrialEngine`, `CORESETDefinition`, `SearchSpaceDefinition`, DCI schema/size alignment and RIV helpers | Reuse for calibrated PDCCH points. BWOP arithmetic must remain a separate exact layer. |
| PDSCH/DL-SCH | `+sixgr/+phy/+dl/PDSCH_Tx.m`, `PDSCH_Rx.m`, `+sixgr/+pdsch/`, `+sixgr/+lls/runPDSCHTransportBlock.m` | Reuse. Actual allocation `A` must bind to the explicit PRB set and remain distinct from schedulable reference width `N_S`. |
| PUSCH/UL-SCH | `+sixgr/+phy/+ul/PUSCH_Tx.m`, `PUSCH_Rx.m`, `+sixgr/+phy/+ul/+pusch/`, `+sixgr/+lls/runTransportBlock.m` | Reuse for Msg3/MsgA allocation studies. |
| PRACH | `+sixgr/+phy/+prach/`, `+sixgr/+phy/+ra/generateMsg1PRACHWaveform.m`, `detectMsg1PRACH.m`, `+sixgr/+rach/+tdoc10512/` | Reuse only for success/resource relations. This AI must not invent PRACH formats or occasions. |
| PUCCH/UCI | `+sixgr/+phy/+pucch/`, `+sixgr/+phy/+ul/PUCCH_Tx.m`, `PUCCH_Rx.m` | Reuse for the Msg4 HARQ-ACK confirmation alternative. |
| Fading/CE | TDL/CDL channel surfaces and `+sixgr/+phy/+rx/channelEstimate.m` | Reuse with concrete profiles such as `TDL-C`; scalar full-grid estimates remain AWGN-only. |
| Scheduler | `+sixgr/+l2/+mac/SchedulerBase.m`, RR/PF schedulers, grant validation and trace exporters | Reuse scheduling concepts. BWOP common-control CCE budgeting needs a dedicated, bounded procedure model. |
| Initial access | `+sixgr/+phy/+ia/`, `+sixgr/+phy/+ra/`, `+sixgr/+l3/+rrc/RACHProcedure.m`, four-step contention implementation | Reuse physical messages and event semantics. No new channel/message type is required. |
| BWP/time | `+sixgr/+phy/+frame/BWPConfig.m`, `BWPStateMachine.m`, `AbsoluteTime.m` | Reuse absolute-time utilities only. This AI is not authorization for a new connected-mode multi-BWP or multi-carrier framework. |
| Energy | `+sixgr/+rf/EnergyModelUE.m`, `EnergyModelBS.m`, `+sixgr/+truth/resolveLLSEnergyModelConfig.m` | Reuse when calibrated inputs exist. Prompt-provided normalized source arithmetic remains source reproduction. |
| Plotting | `+sixgr/+visual/`, `+sixgr/+util/exportFigureArtifact.m`, `+sixgr/+visual/exportRasterAtomic.m` | Reuse for PNG. BWOP additionally needs source-bound FIG/PDF publication for the explicit TDoc contract. |
| Results/manifests | `+sixgr/+report/resultLayout.m`, `verifyCampaignArtifacts.m`, `OrganizeRunResults.m`, database artifact store | Reuse hashing/provenance conventions. BWOP output remains filesystem-first and independently reproducible; MySQL availability cannot determine scientific status. |

## Configuration architecture

The repository uses layered YAML resolved by `sixgr.lls6g.config.loadScenarioConfig`, with a catalog-backed validator under `simulator/configs/schema/`. Existing TDoc work (`+sixgr/+rach/+tdoc10512`) demonstrates the intended pattern: one YAML authority, a custom semantic validator, immutable resolved configuration, configuration hash, deterministic seeds, focused campaign entry point, and strict evidence classification.

`simulator/configs/scenarios/bandwidth_operation_profiles.yaml` currently provides only generic 20/40/100 MHz waveform-bundle overrides. It does not model `N_C`, `N_S`, actual allocation `A`, source reproduction, RF-span feasibility, initial-access inheritance, post-IA transition, paging, evidence classes, or the required figure/manifest contract. It must not be treated as implementation of AI 10.5.1.3.

## Capability findings

### Non-contiguous PRB allocation

Supported. `PDSCHResourcePlan` owns an explicit `PRBSet`; `PDSCH_Tx` checks it against the frozen grant; `PDSCHAssignmentFactory` preserves BWP- and carrier-relative PRB sets; and `FDRAAllocator` supports bitmap/RIV materialization. BWOP must add tests proving separated clusters are used rather than a contiguous allocation with the same RB count.

### Multiple CORESET/search-space configurations

The strict PDCCH namespace has reusable CORESET/search-space definitions, candidate enumeration, monitoring budgets and DCI sizing. The older `+sixgr/+ctrl` study path supports multiple search-space records but only one resolved CORESET object per control configuration. BWOP should construct independent common/target region records and enforce aggregate UE BD/CCE budgets rather than silently merging them.

### SI, paging and RACH procedures

- Physical SIB1/PDCCH/PDSCH and four-step RA components exist.
- Msg1, Msg2/RAR, Msg3, Msg4/contention resolution and RRC completion hooks exist.
- Two-step MsgA/MsgB coverage is incomplete and must remain gated where the existing physical chain lacks truth evidence.
- No complete bandwidth-aware SI-window scheduler, idle paging bandwidth study, or post-IA common/target overlap state machine exists.

### RF preparation/retuning

The repository has RF front-end and BWP activation state, but no RAN4-calibrated class-0/1/2 preparation-time model for this procedure. `K_act`, retuning gap, BB expansion delay and simultaneous-monitoring capability must therefore remain YAML-owned sensitivity assumptions until external calibration is supplied. No synthetic dB penalty is permitted.

## New reusable capability required

1. A `+sixgr/+bwop` campaign namespace with evidence classification and scenario registry.
2. Exact `N_C`/`N_S`/`A` arithmetic, RIV/FDRA, PBCH cost, power accounting and RF-span geometry.
3. Dedicated initial-access bandwidth state machines for common-anchor inheritance and post-IA activation/fallback; these must not mutate the connected-mode BWP framework.
4. Bounded common/target monitoring-budget and common-control scheduler models.
5. Source-calibration adapters over the existing PDCCH/PDSCH/PUSCH truth chains.
6. A source-bound figure, caption, traceability and artifact verifier supporting PNG plus editable FIG/vector PDF without SVG.
7. Explicit blocker artifacts for unavailable calibrated dependencies; no placeholder curve may be promoted as measured evidence.

## Planned files and rationale

- `+sixgr/+bwop/*`: generic campaign, analytical, procedural, evidence and reporting capabilities.
- `simulator/configs/bwop_ai10513/*`: one master YAML and reusable mode profiles; all scenario policy remains configurable.
- `tests/testBWOPAI10513*.m`: exact arithmetic, geometry, state-machine, monitoring-budget and artifact-integrity regressions.
- `runBWOPAI10513Campaign.m`: front door accepting only config path, output root, run ID, mode and resume flag.
- `docs/bwop_ai10513_repository_audit.md`: this prerequisite audit.

No existing PHY transmitter or receiver namespace should be duplicated.

## Backward-compatibility risks and controls

- Extending the scenario catalog can affect strict top-level validation. Keep BWOP fields isolated in an optional extension and run config regression tests.
- Existing BWP state is connected-mode oriented. Do not use it as a semantic substitute for initial-access common/target bandwidth state.
- Generic PDSCH code may infer allocation from carrier/BWP width. BWOP tests must freeze and compare the exact PRB set.
- Existing visual utilities are raster-first. BWOP vector output must be additive and must not re-enable SVG globally.
- Existing result organizers can copy or rename artifacts. BWOP scientific status must derive from its own source hashes and evidence class, not folder presence.
- The worktree already contains unrelated changes. Patches must not revert or bundle them implicitly.

## Focused validation plan

1. Exact arithmetic: minimum RB, PBCH cost, RIV/FDRA, CCE capacity and power closure.
2. Geometry: case relations, carrier/guard/RF-span containment and invalid-case fail-closed behavior.
3. Allocation: explicit distributed clusters and `N_S`/`A` separation.
4. Procedures: common-control budget, initial-UL containment, transition classes, activation reference, early cease, unsupported-profile fallback and deadlock bound.
5. PHY sanity: existing high-SNR PBCH/PDCCH/PDSCH/PUSCH focused tests; no `testAll` during bounded implementation iterations.
6. Artifact integrity: every emitted figure has CSV/MAT, caption, configuration hash, evidence class and traceability; assumption/smoke artifacts cannot enter `tdoc_ready`.
7. Campaign smoke run and verifier, followed by source-calibration and priority TDoc tiers only after the bounded gates pass.

## Audit conclusion

The repository has suitable production PHY building blocks, but AI 10.5.1.3 is not implemented by the current generic bandwidth sweep. The safe implementation path is a config-driven BWOP orchestration/evidence layer that reuses the existing PHY chains, keeps `N_S` distinct from actual allocation `A`, and fails closed whenever a calibrated dependency is absent.
