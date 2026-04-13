# LLS Truth Audit

Regenerated: 2026-04-13

## Purpose

This audit records the current truth boundary for the active coupled LLS path. It is intentionally evidence-led: every "implemented" claim below is backed by the current runtime code path and by focused tests that inspect exported semantics rather than just checking that code executes.

## Current Truth Status

| Area | Current status | Evidence |
| --- | --- | --- |
| Coupled LLS runtime orchestration | Active coupled runtime publishes per-slot truth state and export surfaces from the same runtime object. | [+sixgr/+truth/CoupledTruthRuntime.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+truth/CoupledTruthRuntime.m) |
| TDL array handling | Truthfully labeled as a reduced runtime-geometry-backed correlation adapter when runtime antenna metadata exists; count-only only when runtime geometry is absent. | [+sixgr/+channel/ChannelFactory.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+channel/ChannelFactory.m), [tests/testLLSChannelArrayTruthStatus.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/tests/testLLSChannelArrayTruthStatus.m) |
| TR38901 large-scale pathloss backend | The channel metadata now discloses whether large-scale pathloss came from the standards-backed `nrPathLoss` runtime backend or from an explicit FSPL fallback / ABG abstraction. | [+sixgr/+channel/TR38901Plus.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+channel/TR38901Plus.m), [+sixgr/+channel/ChannelFactory.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+channel/ChannelFactory.m), [tests/testLLSChannelArrayTruthStatus.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/tests/testLLSChannelArrayTruthStatus.m) |
| Spatial non-stationarity | When enabled, runtime metadata now marks the visibility masks as random placeholders rather than geometry-calibrated truth. | [+sixgr/+channel/SpatialNonStationarity.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+channel/SpatialNonStationarity.m), [+sixgr/+channel/ChannelFactory.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+channel/ChannelFactory.m), [tests/testLLSChannelArrayTruthStatus.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/tests/testLLSChannelArrayTruthStatus.m) |
| TRS runtime consumer | Shared receiver tracking state is integrated in the active coupled runtime and exported as the runtime consumer. | [+sixgr/+truth/CoupledTruthRuntime.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+truth/CoupledTruthRuntime.m), [tests/testTRSReferenceSignalExecution.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/tests/testTRSReferenceSignalExecution.m) |
| TRS timing/CFO materialization | Only real timing/CFO estimates are materialized. When no runtime estimate exists, values remain unavailable rather than fabricated. | [tests/testTRSReferenceSignalExecution.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/tests/testTRSReferenceSignalExecution.m) |
| Phase-noise execution status | Waveform impairment replay now states whether phase noise is merely configured, which helper backend is available, and that the active no-proxy waveform path does not materialize phase-noise impairment today. | [+sixgr/+link/applyWaveformImpairments.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+link/applyWaveformImpairments.m), [+sixgr/+rf/PhaseNoiseModel.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+rf/PhaseNoiseModel.m), [tests/testLLSChannelArrayTruthStatus.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/tests/testLLSChannelArrayTruthStatus.m) |
| Browser truth surfacing for antenna/channel handling | Browser truth modes surface the reduced TDL adapter status and exact blocker, not the old count-only status, when runtime-backed TDL evidence is present. | [tests/test_lls_browser_antenna_channel_truth.py](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/tests/test_lls_browser_antenna_channel_truth.py) |

## What Is Truthful Today

- Runtime-backed TDL handling is exposed as `nrtdl_runtime_geometry_correlation_channel`.
- Runtime-backed TDL handling status is exposed as `adapted_geometry_backed_reduced_representation`.
- The active blocker remains `nrtdlchannel_consumes_custom_spatial_correlation_matrices_not_runtime_array_objects`.
- TR38901 pathloss metadata now distinguishes `nrpathloss_runtime_backend` from `free_space_path_loss_fallback` and ABG abstraction.
- Spatial non-stationarity metadata now declares `approximate_random_placeholder_visibility_masks`.
- TRS runtime evidence updates the shared receiver tracking state object.
- Scheduler eligibility can consume that shared TRS tracking state when TRS gating is active.
- DL and UL receivers only persist TRS timing/CFO estimates when those estimates actually exist in runtime evidence.
- Waveform impairment replay now declares when phase noise is configured but `not_materialized_in_active_waveform_truth_path`.

## Remaining Honest Limits

- TDL is still not full runtime array-object, pose, element-pattern, polarization-angle, or per-path-angle coupling. It remains a reduced correlation-backed adapter and must stay labeled that way.
- Spatial non-stationarity still uses random placeholder visibility masks rather than geometry-calibrated cluster visibility.
- TR38901 pathloss remains truthful only when `nrPathLoss` is present; any FSPL or ABG path must stay labeled as approximate.
- TRS timing/CFO correction is not universally materialized. It is estimate-driven and remains unavailable when the runtime row does not provide a real estimate.
- Phase-noise helper code exists, but the active no-proxy waveform impairment replay still does not apply phase-noise impairment.
- Shared TRS receiver tracking integration should not be described as a blanket "full receiver-kernel synchronization solution"; the current truthful claim is narrower than that.

## Focused Verification Used For This Audit

Run with MATLAB R2023b:

```powershell
& 'C:\Program Files\MATLAB\R2023b\bin\matlab.exe' -batch "setup6GRSimToolkit('Verbose',false); testTRSReferenceSignalExecution; testLLSChannelArrayTruthStatus"
python tests/test_lls_browser_antenna_channel_truth.py
```

These checks validate:

- shared TRS receiver tracking integration
- non-fabricated timing/CFO semantics
- reduced runtime-geometry TDL labeling
- explicit TR38901 pathloss backend labeling
- explicit spatial non-stationarity placeholder labeling
- explicit phase-noise helper / execution-status labeling
- browser surfacing of the reduced TDL adapter and exact blocker
