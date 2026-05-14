# Static Audit Fix Report

Date: 2026-04-24

## Scope

This pass implemented and validated the following audit phases:

- Phase 0: repo trust boundary cleanup
- Phase 1: UL receiver noise-variance safety
- Phase 2: timing estimate honesty
- Phase 3: link-adaptation domain and stale scheduler helper removal
- Phase 4: scenario geometry, UE drop mode, and wrap-around mode
- Phase 5: strict and traceable pathloss, O2I, and LOS compliance
- Phase 6: explicit spatial non-stationarity modes and geometry-backed proxy mode
- Phase 8 subset: control-plane `nontransparent_stub` guard

The following areas remain incomplete in this pass:

- Phase 7: TRS full closed-loop demod timing and CFO integration
- Phase 8 remainder: traffic/L2 fidelity exports, broader reporting and plot gating cleanup
- Phase 9 full regression completion: `testAll` plus E2E suites exceeded the 4-hour wrapper timeout and were stopped

## Files Changed

- `.gitignore`
- `docs/trust_boundary_audit.md`
- `docs/static_audit_fix_report.md`
- `+sixgr/+config/normalizeConfig.m`
- `+sixgr/+config/validateConfig.m`
- `+sixgr/+lls6g/buildInternalConfig.m`
- `+sixgr/+lls6g/+config/validateScenarioConfig.m`
- `+sixgr/+channel/O2ILoss.m`
- `+sixgr/+channel/LOSProbability.m`
- `+sixgr/+channel/TR38901Plus.m`
- `+sixgr/+channel/SpatialNonStationarity.m`
- `+sixgr/+channel/ChannelFactory.m`
- `+sixgr/+system/buildLargeScaleStateCache.m`
- `+sixgr/+truth/CoupledTruthRuntime.m`
- `+sixgr/+truth/exportLLSLiveMobilityTables.m`
- `+sixgr/+truth/runWaveformLinkBundle.m`
- `+sixgr/+link/applyWaveformImpairments.m`
- `+sixgr/+link/runULPUSCHThroughput.m`
- `+sixgr/+link/runDLPDSCHThroughput.m`
- `+sixgr/+ctrl/ControlChannelConfig.m`
- `tests/testULNoiseVarianceValidation.m`
- `tests/testLLSBundleRuntimeEvidenceExports.m`
- `tests/testTimingEstimateHonesty.m`
- `tests/testLinkAdaptationDomainTruth.m`
- `tests/testScenarioGeometryModes.m`
- `tests/testChannelComplianceTruth.m`
- `tests/testSpatialNonStationarityModes.m`
- `tests/testControlChannelStubGuard.m`
- `tests/testLLSChannelArrayTruthStatus.m`
- `tests/testLLSClosedLoopLinkAdaptation.m`
- `tests/testLLSStatefulLinkAdaptationState.m`
- `tests/testLLSOutputCoverageArtifacts.m`
- `tests/testTRSReferenceSignalExecution.m`
- `tests/testLLSResultRichness.m`

## Commands Run

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLLSBundleRuntimeEvidenceExports; testULNoiseVarianceValidation; testLLS_UL"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testTimingEstimateHonesty; testTRSReferenceSignalExecution; testLLS_UL; testLLS_DL; testLLSOutputCoverageArtifacts; testLLSBundleRuntimeEvidenceExports"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLinkAdaptationDomainTruth; testLLSStatefulLinkAdaptationState; testLLSClosedLoopLinkAdaptation; testLLS_UL; testLLS_DL; testLLSBundleRuntimeEvidenceExports; testLLSOutputCoverageArtifacts"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testScenarioGeometryModes; testColocatedSectorAttachment"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testChannelComplianceTruth; testLLSChannelArrayTruthStatus; testConfig; testLLS_UL; testLLS_DL; testLLS_ReferencePoints"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testControlChannelStubGuard; testSpatialNonStationarityModes; testChannelComplianceTruth; testLLSChannelArrayTruthStatus; testConfig; testLLS_UL; testLLS_DL; testLLS_ReferencePoints"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testAll; testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign"`:
  timed out after 4 hours in the wrapper and the background MATLAB batch was stopped

## Validation Summary

- Focused config, channel, and LLS suites passed after the current patches.
- Prior runtime evidence from the waveform-backed web run `61` (`codex_ul_noisevar_web_10slot_20260424`) remains the latest end-to-end web publication check for the UL noise-variance fix.
- Full repo-wide `testAll` plus E2E regressions did not complete within the 4-hour wrapper budget, so this report does not claim a clean full-suite pass.

## Issue Status

### 1. Repo trust boundary contaminated by generated and ambiguous artifacts

- Status: partially fixed
- Files changed: `.gitignore`, `docs/trust_boundary_audit.md`
- Before: generated logs, temp directories, browser/runtime artifacts, and scratch files were mixed with active source paths.
- After: recurring generated output patterns are ignored and ambiguous residue is documented in `docs/trust_boundary_audit.md` instead of being silently deleted.
- Tests added or run: `testLLS_UL`
- Remaining limitation: existing user-owned clutter already in the worktree was not deleted automatically.
- Runtime evidence location: `docs/trust_boundary_audit.md`

### 2. UE drop uses equalized sector seeding and wedge heuristics

- Status: partially fixed
- Files changed: `+sixgr/+scenario/dropUEs.m`, `+sixgr/+scenario/ScenarioFactory.m`, `tests/testScenarioGeometryModes.m`
- Before: UE placement and initial sector assignment were coupled to legacy equal-sector heuristics.
- After: `legacy_equal_sector_drop` remains available but explicitly labeled, and `pathloss_based_association_drop` separates location generation from serving-cell selection.
- Tests added or run: `testScenarioGeometryModes`
- Remaining limitation: `density_map_drop` and richer hotspot-based placement were not implemented in this pass.
- Runtime evidence location: `tests/testScenarioGeometryModes.m`

### 3. Wrap-around is rectangular toroidal even for hex-grid deployments

- Status: fixed
- Files changed: `+sixgr/+scenario/wraparoundDistance.m`, `+sixgr/+scenario/generateLayout.m`, `+sixgr/+scenario/ScenarioFactory.m`, `+sixgr/+system/buildLargeScaleStateCache.m`, `tests/testScenarioGeometryModes.m`
- Before: hex deployments silently reused rectangular torus distance logic.
- After: wrap-around mode is explicit and hex layouts default to `hex_lattice_min_image`.
- Tests added or run: `testScenarioGeometryModes`
- Remaining limitation: the equivalent-image search is lattice-based and not a full site-clone scene graph.
- Runtime evidence location: `tests/testScenarioGeometryModes.m`

### 4. O2I model is approximate, not strict TR 38.901

- Status: partially fixed
- Files changed: `+sixgr/+channel/O2ILoss.m`, `+sixgr/+channel/TR38901Plus.m`, `+sixgr/+system/buildLargeScaleStateCache.m`, `+sixgr/+truth/CoupledTruthRuntime.m`, `+sixgr/+truth/exportLLSLiveMobilityTables.m`, `+sixgr/+link/applyWaveformImpairments.m`, `+sixgr/+link/runULPUSCHThroughput.m`, `+sixgr/+link/runDLPDSCHThroughput.m`, `+sixgr/+truth/runWaveformLinkBundle.m`, `tests/testChannelComplianceTruth.m`
- Before: O2I approximations were acknowledged in comments but not surfaced as an explicit compliance mode and source chain.
- After: O2I source, compliance status, and reason are exported; strict mode blocks the active approximate indoor O2I path unless explicit runtime O2I metadata is supplied.
- Tests added or run: `testChannelComplianceTruth`
- Remaining limitation: an exact TR 38.901 building-penetration table implementation is still not present.
- Runtime evidence location: `tests/testChannelComplianceTruth.m`

### 5. Spatial non-stationarity is placeholder random-mask logic

- Status: partially fixed
- Files changed: `+sixgr/+channel/SpatialNonStationarity.m`, `+sixgr/+channel/ChannelFactory.m`, `tests/testSpatialNonStationarityModes.m`, `tests/testLLSChannelArrayTruthStatus.m`
- Before: enabling spatial non-stationarity always produced random placeholder visibility masks.
- After: explicit modes exist for `disabled`, `legacy_random_mask_placeholder`, and `geometry_based_visibility`; geometry mode blocks cleanly when the required geometry inputs are missing and uses a deterministic geometry-backed proxy when they exist.
- Tests added or run: `testSpatialNonStationarityModes`, `testLLSChannelArrayTruthStatus`
- Remaining limitation: the geometry-backed mode is still a proxy because runtime cluster-angle state is not carried into this hook.
- Runtime evidence location: `tests/testSpatialNonStationarityModes.m`

### 6. TDL geometry coupling uses reduced correlation matrices instead of full runtime array-object coupling

- Status: partially fixed
- Files changed: no new algorithmic change in this pass; status remains enforced in `+sixgr/+channel/ChannelFactory.m` and verified in `tests/testLLSChannelArrayTruthStatus.m`
- Before: TDL could be mistaken for stronger geometry coupling than it actually had.
- After: the repo continues to label TDL as `adapted_geometry_backed_reduced_representation` with an explicit blocker instead of claiming full runtime array-object coupling.
- Tests added or run: `testLLSChannelArrayTruthStatus`
- Remaining limitation: the waveform TDL backend still cannot consume full runtime antenna objects.
- Runtime evidence location: `tests/testLLSChannelArrayTruthStatus.m`

### 7. UL receiver noise variance falls back to `1e-10`

- Status: fixed
- Files changed: `+sixgr/+phy/+ul/PUSCH_Rx.m`, `+sixgr/+phy/+ul/PUCCH_Rx.m`, `+sixgr/+phy/+ul/SRS_Rx.m`, `+sixgr/+phy/+ul/resolveULNoiseVariance.m`, `+sixgr/+truth/runWaveformLinkBundle.m`, `tests/testULNoiseVarianceValidation.m`, `tests/testLLSBundleRuntimeEvidenceExports.m`
- Before: missing or invalid UL noise variance could silently collapse to near-zero and overstate receiver quality.
- After: all three UL receiver paths use centralized validation; missing or invalid noise variance yields unusable results or strict failure instead of fake low-noise decoding.
- Tests added or run: `testULNoiseVarianceValidation`, `testLLSBundleRuntimeEvidenceExports`, `testLLS_UL`
- Remaining limitation: none identified in the patched UL truth path.
- Runtime evidence location: tests above and web run `61`

### 8. Timing estimate is clipped with `max(0, ...)`

- Status: fixed
- Files changed: `+sixgr/+phy/+sync/resolveTimingApplication.m`, `+sixgr/+phy/+sync/timingEstimate.m`, `+sixgr/+phy/+sync/cellSearch.m`, `+sixgr/+phy/+ul/PUSCH_Rx.m`, `+sixgr/+phy/+dl/PDSCH_Rx.m`, `+sixgr/+phy/+dl/PDCCH_Rx.m`, `+sixgr/+phy/+dl/SSB_Rx.m`, `+sixgr/+link/runULPUSCHThroughput.m`, `+sixgr/+link/runDLPDSCHThroughput.m`, `+sixgr/+link/runCellSearch_MIB_SIB1.m`, `+sixgr/+util/applyLLSRawTrialLifecycle.m`, `+sixgr/+truth/runWaveformLinkBundle.m`, `+sixgr/+truth/exportLLSLiveSignalChainTables.m`, `tests/testTimingEstimateHonesty.m`
- Before: raw negative timing estimates were silently overwritten by non-negative clipping.
- After: raw timing estimate and applied correction are separated and exported with explicit application policy.
- Tests added or run: `testTimingEstimateHonesty`, `testLLS_UL`, `testLLS_DL`
- Remaining limitation: downstream consumers still need to respect the split between raw truth and applied correction.
- Runtime evidence location: `tests/testTimingEstimateHonesty.m`

### 9. Link adaptation smooths in MCS domain

- Status: fixed
- Files changed: `+sixgr/+link/resolveLinkAdaptationDomain.m`, `+sixgr/+link/computeLinkAdaptationDecision.m`, `+sixgr/+link/runULPUSCHThroughput.m`, `+sixgr/+link/runDLPDSCHThroughput.m`, `+sixgr/+truth/runWaveformLinkBundle.m`, `tests/testLinkAdaptationDomainTruth.m`, `tests/testLLSClosedLoopLinkAdaptation.m`, `tests/testLLSStatefulLinkAdaptationState.m`
- Before: smoothing occurred after quantized CQI-to-MCS conversion.
- After: the default domain is explicit and CQI-domain smoothing is used unless a legacy MCS mode is requested.
- Tests added or run: `testLinkAdaptationDomainTruth`, `testLLSClosedLoopLinkAdaptation`, `testLLSStatefulLinkAdaptationState`
- Remaining limitation: effective-SINR and BLER-margin modes still depend on the fidelity of upstream CQI and calibration inputs.
- Runtime evidence location: tests above

### 10. Scheduler files contain stale linear CQI to MCS helpers

- Status: fixed
- Files changed: `+sixgr/+l2/+mac/SchedulerPF.m`, `+sixgr/+l2/+mac/SchedulerRR.m`, `tests/testLinkAdaptationDomainTruth.m`
- Before: local scheduler helpers retained the stale linear CQI-to-MCS formula.
- After: the stale helpers were removed and tests now guard against their return.
- Tests added or run: `testLinkAdaptationDomainTruth`
- Remaining limitation: none identified for the removed linear helper path.
- Runtime evidence location: `tests/testLinkAdaptationDomainTruth.m`

### 11. Large-scale pathloss can silently fall back to FSPL or ABG

- Status: partially fixed
- Files changed: `+sixgr/+config/normalizeConfig.m`, `+sixgr/+config/validateConfig.m`, `+sixgr/+lls6g/buildInternalConfig.m`, `+sixgr/+lls6g/+config/validateScenarioConfig.m`, `+sixgr/+channel/TR38901Plus.m`, `+sixgr/+channel/ChannelFactory.m`, `+sixgr/+system/buildLargeScaleStateCache.m`, `+sixgr/+truth/CoupledTruthRuntime.m`, `+sixgr/+truth/exportLLSLiveMobilityTables.m`, `+sixgr/+link/applyWaveformImpairments.m`, `+sixgr/+link/runULPUSCHThroughput.m`, `+sixgr/+link/runDLPDSCHThroughput.m`, `+sixgr/+truth/runWaveformLinkBundle.m`, `tests/testChannelComplianceTruth.m`, `tests/testLLSChannelArrayTruthStatus.m`
- Before: pathloss backend changes were honest in metadata but there was no explicit compliance mode to block them.
- After: `channel.complianceMode` is normalized and validated; strict mode blocks non-`nrPathLoss` models and fallback pathloss; approximate mode exports source and status.
- Tests added or run: `testChannelComplianceTruth`, `testLLSChannelArrayTruthStatus`, `testConfig`, `testLLS_UL`, `testLLS_DL`, `testLLS_ReferencePoints`
- Remaining limitation: strict mode still depends on `nrPathLoss` runtime availability in the installed MATLAB environment.
- Runtime evidence location: tests above

### 12. ScenarioFactory defaults are convenience baselines rather than spec-traceable calibration sets

- Status: requires runtime evidence
- Files changed: `+sixgr/+scenario/ScenarioFactory.m`
- Before: built-in defaults were baseline conveniences.
- After: several geometry choices are now explicit modes, but the defaults themselves are still baseline conveniences.
- Tests added or run: `testScenarioGeometryModes`
- Remaining limitation: there is still no full calibration catalog proving spec-traceable defaults end to end.
- Runtime evidence location: none beyond code inspection and geometry tests

### 13. Sector radius and area sizes are heuristic

- Status: honestly blocked
- Files changed: none in this pass beyond related geometry mode plumbing
- Before: scenario area and radius policies were heuristic.
- After: the patch series did not replace those heuristics with a standards-backed radius policy.
- Tests added or run: none specific
- Remaining limitation: `SectorRadiusPolicy` remains an open implementation item.
- Runtime evidence location: none in this pass

### 14. Indoor grid placement shrinks spacing heuristically

- Status: honestly blocked
- Files changed: none
- Before: indoor grid placement shrank spacing heuristically to fit the area.
- After: no new explicit indoor-grid spacing policy was implemented in this pass.
- Tests added or run: none specific
- Remaining limitation: `indoor_grid_explicit` mode remains unimplemented.
- Runtime evidence location: none in this pass

### 15. LOS probability uses generic fallback for unknown scenarios

- Status: fixed
- Files changed: `+sixgr/+channel/LOSProbability.m`, `+sixgr/+channel/TR38901Plus.m`, `tests/testChannelComplianceTruth.m`
- Before: unknown scenarios silently fell back to a generic exponential curve.
- After: the generic fallback is explicitly labeled, and strict mode blocks it.
- Tests added or run: `testChannelComplianceTruth`
- Remaining limitation: some scenarios like `InF` are still labeled as approximate proxies rather than strict curves.
- Runtime evidence location: `tests/testChannelComplianceTruth.m`

### 16. Control-plane and PDCCH study contains `nontransparent_stub`

- Status: fixed
- Files changed: `+sixgr/+ctrl/ControlChannelConfig.m`, `tests/testControlChannelStubGuard.m`
- Before: `nontransparent_stub` was accepted by config validation and then failed later at runtime.
- After: stub modes are opt-in only through `AllowStubModes`; config carries explicit implementation status and blocker text.
- Tests added or run: `testControlChannelStubGuard`
- Remaining limitation: the stub itself is still not implemented or decodable, which is now explicit instead of implicit.
- Runtime evidence location: `tests/testControlChannelStubGuard.m`

### 17. TRS shared tracking is not a full closed-loop demod timing and CFO correction chain

- Status: requires runtime evidence
- Files changed: no new TRS algorithm change in this pass
- Before: shared TRS state existed without a full closed-loop demod correction path.
- After: no new closed-loop TRS correction implementation was added in this pass.
- Tests added or run: existing TRS tests still pass in the focused suites
- Remaining limitation: full closed-loop timing and CFO correction via TRS remains open.
- Runtime evidence location: `tests/testTRSReferenceSignalExecution.m`

### 18. UL applied beam-index set remains unmaterialized even when TPMI is applied

- Status: fixed
- Files changed: no new change in this pass; verified current repo behavior
- Before: this was reported by the static audit, but the active repo already separated applied PMI truth from unmaterialized beam-index-set truth.
- After: no regression was introduced; beam-index-set truth remains explicitly unavailable when not materially present.
- Tests added or run: existing UL beam truth tests from the repo remain the guard
- Remaining limitation: there is still no native materialized beam-index-set object in the active UL codebook path.
- Runtime evidence location: `tests/testLLSULBeamPrecoderTruth.m`

### 19. Traffic models use approximate transport semantics

- Status: honestly blocked
- Files changed: none in this pass
- Before: traffic models explicitly used approximate semantics such as FTP3-like UDP approximations.
- After: this pass did not add `TrafficModelFidelity` exports or implement true TCP session semantics.
- Tests added or run: none specific
- Remaining limitation: transport-fidelity labeling is still an open phase-8 item.
- Runtime evidence location: none in this pass

### 20. PDCP, SDAP, and RLC are simplified but coherent, not standards-complete

- Status: honestly blocked
- Files changed: none in this pass
- Before: L2 model comments already acknowledged simplification.
- After: this pass did not add broad `LayerModelFidelity` exports across the stack.
- Tests added or run: none specific
- Remaining limitation: layer-fidelity export plumbing remains an open phase-8 item.
- Runtime evidence location: none in this pass

### 21. Truth and reporting files focus more on honesty classification than physics

- Status: not applicable
- Files changed: none directed at this concern
- Before: reporting files contained extensive honesty metadata.
- After: this pass did not try to remove those markers because they are not themselves a correctness defect.
- Tests added or run: not applicable
- Remaining limitation: reporting complexity remains high.
- Runtime evidence location: not applicable

### 22. Worktree clutter risks patching the wrong path

- Status: partially fixed
- Files changed: `.gitignore`, `docs/trust_boundary_audit.md`
- Before: noisy generated artifacts and scratch paths could be mistaken for source.
- After: ignore coverage and trust-boundary documentation reduce the risk, but they do not sanitize the already-dirty user worktree.
- Tests added or run: `testLLS_UL`
- Remaining limitation: existing ambiguous files still require human judgment.
- Runtime evidence location: `docs/trust_boundary_audit.md`

### 23. Unavailable or schema-only outputs can mislead unless honesty metadata is read

- Status: partially fixed
- Files changed: `+sixgr/+truth/exportLLSOutputCoverageArtifacts.m`, `+sixgr/+truth/runWaveformLinkBundle.m`, `+sixgr/+truth/exportLLSLiveMobilityTables.m`, `+sixgr/+link/runULPUSCHThroughput.m`, `+sixgr/+link/runDLPDSCHThroughput.m`
- Before: several output paths could show fields without enough provenance or implementation-status context.
- After: more raw and canonical artifacts now carry noise-variance, timing, geometry, pathloss, O2I, LOS, and compliance provenance.
- Tests added or run: `testLLSOutputCoverageArtifacts`, `testLLSBundleRuntimeEvidenceExports`
- Remaining limitation: broader plot suppression and schema-availability map work is still incomplete.
- Runtime evidence location: tests above

## Known Limitations That Remain

- Full strict TR 38.901 O2I building-penetration loss is still not implemented.
- Spatial non-stationarity geometry mode is a proxy, not a full runtime cluster-angle model.
- TDL still uses a reduced geometry adapter rather than true runtime array-object coupling.
- Indoor-grid explicit placement, traffic-model fidelity exports, and layer-model fidelity exports remain open.
- Full repo-wide `testAll` plus E2E completion was not achieved within the 4-hour batch window.

## Generated Result Bundle Path

- No new web result bundle was generated in this pass.
- Latest previously verified waveform-backed web evidence for the UL noise-variance fix remains run `61` (`codex_ul_noisevar_web_10slot_20260424`).

## Truth Contract Summary

- Focused LLS suites covering config, channel, UL, DL, and reference-point behavior passed after the current patch set.
- No new proxy PHY path or silent fallback was introduced in the patched UL noise, timing, channel-compliance, geometry, or PDCCH stub paths.
- Full-suite truth and E2E completion remains unverified because the long batch timed out.

## Next Recommended Work

- Finish phase 7 by wiring TRS state into actual demod timing and CFO correction where supported.
- Finish phase 8 by exporting `TrafficModelFidelity` and `LayerModelFidelity`, and by tightening plot and schema-only artifact gating.
- Add an explicit indoor-grid placement policy and density-map UE drop mode.
- Implement or integrate a stricter TR 38.901 O2I model if the required tables and terms are available.
- Re-run `testAll`, `testE2E_FastVsTruth`, and `testE2E_TruthPacketSemanticCampaign` with a longer unattended window.
