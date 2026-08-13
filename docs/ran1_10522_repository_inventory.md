# RAN1 AI 10.5.2.2 PDSCH/DM-RS repository inventory

Generated from clean `main` at `86408ac978e6f828e7f63dd1fe810e780bda65b4` before production changes.

## Source and toolchain

- Implementation prompt: `C:/Users/anup0/Downloads/CODEX_MASTER_PROMPT_RAN1_10_5_2_2_PDSCH_DMRS_WIDEBAND_FULL_SIMULATION.md`
- Prompt SHA-256: `680db7439450b55b074342284d435cde95671c947bdae220adb6d8221f22e5cc`
- Named controlling TDoc: `R1-26xxxx_Jio_PDSCH_DMRS_Wideband_6GR_v2.docx`
- Controlling TDoc availability: **missing from the repository and Downloads**. Results must bind to the prompt hash and must not claim full document equivalence.
- MATLAB: R2026a Update 4 (`26.1.0.3312084`)
- 5G Toolbox: `26.1`
- OS: Windows 11 Home Single Language
- CPU: Intel Core i7-8550U, 4 cores / 8 logical processors
- RAM: 11.83 GiB

## Canonical call flow

`run_6g_phy_lls_single` calls `sixgr.lls6g.runners.runSingle`, which loads and validates YAML through `sixgr.lls6g.config.loadScenarioConfig`, resolves the internal configuration through `sixgr.lls6g.buildInternalConfig`, and calls `sixgr.truth.runWaveformLinkBundle`. Coupled jobs are built by `sixgr.truth.buildGrantPHYJob` and executed by `sixgr.truth.executeGrantPHYJob`. The DL link path calls `sixgr.link.runDLPDSCHThroughput`, which executes `sixgr.phy.dl.PDSCH_Tx`, the configured channel, `sixgr.phy.dl.PDSCH_Rx`, DL-SCH/CRC processing, and `sixgr.truth.evaluatePDSCHObjectiveStrict`. No new study code may replace this waveform path.

## Capability inventory

| Capability | Existing file/symbol | Status | Integration action | Tests found | Risks |
|---|---|---|---|---|---|
| YAML/WebGUI scenario loading | `+sixgr/+lls6g/+config`, `+sixgr/+lls6g/+runners/runSingle.m` | REUSE | Add versioned WebGUI-visible study templates; study orchestration reads a single validated YAML | config and WebGUI tests | Unknown study keys must not silently affect baseline runs |
| Canonical PDSCH front door | `+sixgr/+link/runDLPDSCHThroughput.m` | REUSE | Use for every controlled waveform row | `testDLPDSCHThroughputExecutionContract` | Runtime can be large; bounded campaign must remain explicitly unconverged |
| PDSCH transmitter | `+sixgr/+phy/+dl/PDSCH_Tx.m` | REUSE | Execute unchanged NR baseline for bounded controlled evidence | no-noise, grant-driven, multiport tests | TDoc TD-OCC-X patterns beyond NR DM-RS are not presently a canonical TX surface |
| PDSCH receiver | `+sixgr/+phy/+dl/PDSCH_Rx.m` | REUSE | Require practical DM-RS estimation and CRC-backed decode | AWGN/TDL/CDL, high-rank tests | Do not label scalar MMSE as IRC; preserve per-resource fading estimates |
| DL-SCH coding/CRC/rate match | `+sixgr/+pdsch/DLSCHEncoder.m`, `DLSCHDecoder.m`, `DLSCHCodingPlan.m` | REUSE | Export actual TBS/CB/CRC/rate-matched counts | coding/vector tests | Candidate multi-TB modes require truly independent codewords/TBs |
| DM-RS NR mapping | `+sixgr/+phy/+refsig/dmrsPDSCH.m`, `+sixgr/+pdsch/PDSCHDMRS.m` | REUSE | Use authoritative Toolbox indices/symbols for NR baseline evidence | DM-RS vector and no-mutation tests | Not a TD-OCC-X research mapper |
| DM-RS configuration validation | `+sixgr/+pdsch/PDSCHDMRSValidator.m` | REUSE | Keep existing valid NR tuples and fail closed | invalid-combination/port table tests | Extended patterns must not be mislabelled NR Rel-18 |
| PT-RS | `+sixgr/+pdsch/PDSCHPTRS*.m`, `+sixgr/+phy/+refsig/ptrsPDSCH.m` | REUSE | Run only supported canonical common PT-RS; region-specific modes remain gated | PT-RS presence/indices/benefit tests | Per-region independent correction is not yet a verified canonical path |
| Resource ownership and reserved REs | `PDSCHResourceOwnershipMap.m`, `ReservedREUnionSpec.m` | REUSE | Use exact ownership for valid baseline and deterministic masks | reserved-RE tests | MRSS-specific dynamic masks are incomplete |
| PRG/bundled precoding | `PDSCHPrecoderBundle.m`, `resolvePDSCHPrecoding.m` | REUSE | Reuse exact PRG matrix application | PRG and power-conservation tests | PRG is not automatically the proposed RF-region bundle abstraction |
| FDRA/RBG/VRB-to-PRB | `FDRAAllocator.m`, `PDSCHAssignmentFactory.m` | REUSE | Reuse normative baseline; add deterministic study bundle/RBG analysis outside PHY | FDRA and scheduling tests | Candidate complete-bundle interleaver is not a canonical waveform mapping |
| Layer/codeword mapping | `CodewordLayerMapper.m` | REUSE | Use NR rank 1–8 mapping and exact structural alternatives only | rank 1–8 and independent-vector tests | Enhanced codeword modes must not post-split an encoded codeword |
| HARQ | `PDSCHHARQManager.m`, `PDSCHHARQContext.m` | REUSE | First transmission mandatory; reuse canonical HARQ only where identity is stable | NDI/RV/combining tests | Multi-TB HARQ remains unsupported unless independently executed |
| Multi-TRP | `PDSCHMultiTRPExecutor.m` | EXTEND | Reuse mapping/hash validation; waveform modes only where executor supports them | two-TRP tests | No arbitrary new multi-TRP scheme is authorized |
| Strict result evaluation | `+sixgr/+truth/evaluatePDSCHObjectiveStrict.m` | REUSE | Bind controlled rows to strict objective evidence | raw BLER/BER/objective tests | Never promote incomplete curves to calibrated claims |
| Channel models | `+sixgr/+channel/ChannelFactory.m`, `TR38901Plus.m` | REUSE | Require concrete TDL/CDL profiles and continuous channel state | TDL/CDL receiver tests | Never substitute AWGN after fading failure |
| Fading channel estimation | `PDSCH_Rx.m`, shared RX estimation helpers | REUSE | Preserve per-resource practical estimates | fading PRG/high-rank tests | Perfect CE is audit-only and unavailable for receiver decisions in some profiles |
| MMSE/IRC/covariance | receiver/equalizer and measured covariance fields in `runDLPDSCHThroughput` | EXTEND | Export exactly what receiver executes; label scalar MMSE separately | MIMO noise-domain tests | Full nested-MU separate/pooled covariance experiment is missing |
| Sample-domain MU coupling | coupled truth runtime and multi-user contribution path | EXTEND | Reuse only after a bounded pairing fixture proves shared-resource superposition | multi-user/PDSCH tests | Cannot replace with post-hoc scalar interference |
| Artifact layout/manifests | `+sixgr/+report`, `+sixgr/+truth`, `+sixgr/+visual/exportRasterAtomic.m` | REUSE | Emit CSV/MAT/JSON/PNG, hashes, replay and audit | artifact/export tests | No placeholder or stale-config artifacts |
| Deterministic TD profile/implicit L | no reusable equivalent found | MISSING | Add generic study-level exact derivation helper | new exhaustive tests required | Must not mutate NR DM-RS defaults |
| Nested TD family | no reusable equivalent found | MISSING | Add exact study-level set construction/truncation helper | new subset tests required | Waveform nested MU remains separately gated |
| Region-anchored bundles/RBG alignment | partial PRG/RBG support only | EXTEND | Add exact study-level bundle enumeration; keep canonical PRG separate | new bundle tests required | Boundary-constrained and coherent-common-grid modes differ |
| Common-grid sequence indexing audit | Gold/DM-RS sequence oracles exist | EXTEND | Add deterministic index-map comparison without replacing canonical generator | sequence vector tests plus new invariants | Reset modes are negative comparisons, not proposed truth |
| FD-OCC/CDM candidate enumeration | NR DM-RS port tables exist | EXTEND | Enumerate only fully defined mappings; mark research tuples BLOCKED | new structural tests | `FD-OCC*CDM` alone is insufficient |
| 200/400 MHz planning | carrier/grid infrastructure exists | EXTEND | Add exact memory/grid planning and fail `RESOURCE_BLOCKED` | bandwidth tests | 11.83 GiB host cannot silently downscale |
| Genuine multi-cell SLS | geometry/system framework exists but not proven for this study | BLOCKED | Require separately validated multi-cell traffic/scheduler/interference/PHY coupling | system tests | A single-link CDF cannot be relabelled SLS |
| Common-EVM calibration | no exact versioned AI 10.5.2.2 profile located | BLOCKED | Fail closed in `common_evm` mode | calibration binding tests | Similar-looking local values are not a common-EVM profile |

## Dimensional contracts

- Resource grid: `[12*NSizeGrid x SymbolsPerSlot x logical ports]`.
- Waveform: `[time samples x physical transmit antennas]`; receiver waveform uses physical receive branches.
- DM-RS indices identify resource-grid pages/ports and must match the configured layer/port set.
- Fading-channel estimates are per resource/port/layer; scalar full-grid estimates are forbidden outside explicit AWGN/unit-channel execution.
- Per-layer LLRs preserve codeword/layer inverse mapping before rate recovery and LDPC decode.
- Interference covariance is `[Nrx x Nrx]` per supported estimation scope and must be Hermitian/PSD-audited before an IRC claim.
- HARQ buffers retain rate-matched positions, TB/CW identity, NDI and RV; aggregate served bits are not a valid soft-buffer substitute.

## Proposal gap matrix

| Proposal | Existing backing | Initial status | Required closure |
|---:|---|---|---|
| 1 | canonical scheduling/PDSCH inputs | PARTIAL | exact container-equivalence derivation and hash |
| 2 | no implicit-L helper | MISSING | exhaustive X/G/L derivation and controlled comparison |
| 3 | no floor/remainder helper | MISSING | exhaustive exact proof |
| 4 | existing symbol scheduling | PARTIAL | first-reference/buffer derivation and controlled comparison |
| 5 | NR DM-RS L=1/2 support | PARTIAL | TD-OCC-X controlled execution and normalization proof |
| 6 | no nested family | MISSING | exact family proof; MU waveform later |
| 7 | shared-resource runtime exists | PARTIAL | explicit overlap/rate-match/covariance experiment |
| 8 | slot waveform infrastructure | PARTIAL | continuous cross-slot channel/profile support |
| 9 | NR FD/CDM mappings | PARTIAL | exact research-pattern structural enumeration and selected LLS |
| 10 | Gold sequence oracles | PARTIAL | common/reset index maps and controlled comparison |
| 11 | high-rank PDSCH tests | PARTIAL | exact 24/32/48 mappings and genuine SLS CDF |
| 12 | carrier/PRG infrastructure | PARTIAL | region bundle construction and wideband controlled LLS |
| 13 | NR-like VRB mapping | PARTIAL | complete-bundle interleaver and inverse mapping |
| 14 | RBG allocator | PARTIAL | exhaustive P/N/offset compatibility |
| 15 | canonical PT-RS | PARTIAL | independently processed per-region PT-RS receiver path |
| 16 | one/two-codeword and HARQ support | PARTIAL | true multiple-TB candidate execution and overhead ledger |
| 17 | MCS resolution/link adaptation | PARTIAL | causal aligned segment-specific MCS execution |
| 18 | NR rank 1–8 mapping | PARTIAL | exact enhanced independent-codeword candidates |
| 19 | multi-TRP executor | PARTIAL | common-profile hash validation; bounded waveform if supported |
| 20 | reserved-RE ownership | PARTIAL | MRSS validity/no-shift/no-reset and valid LLS |
| 21 | artifact/report frameworks | PARTIAL | study-specific proposal matrix, replay and publication gate |

## Pre-change focused regression

The following ten entry points passed with MATLAB exit code zero: DM-RS symbol positions, DM-RS port tables, invalid combinations, no-noise DL-SCH, TDL receiver, CDL receiver, PDSCH data/DM-RS/PT-RS consistency, PT-RS phase-noise benefit, rank 1–8 codeword/layer mapping, and HARQ position-aware combining.
