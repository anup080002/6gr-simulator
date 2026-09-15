# TDD 5 MHz / configured 12 dB: channel diagnostic capture clock

## Root cause

The integrated `tdd_5mhz_12db_471334ff_20260915` execution failed at runtime slot 35 with `sixgr:truth:NonContiguousChannelDiagnosticCapture`, in `exportSharedChannelObservation>localDiagnosticContext`, called by `runWaveformLinkBundle>localCompleteSharedDataPlan`. Three DL trial rows retained CRC pass, zero bit errors and 1064 compared/good bits each; there was no completed UL trial row. This is a failed, partial run, not 12 dB acceptance.

`sharedLinkScoringObservation` and the persisted channel-artifact validator already distinguish actual direction-active coefficient captures from explicitly inactive TDD intervals. The diagnostic adapter instead required coefficients across the entire receive observation, including a prefix or tail during which that link executes in the reverse direction. This incorrectly rejects legitimate TDD boundary captures after the preceding gain-energy repair.

## Repair and invariant

- `+sixgr/+truth/exportSharedChannelObservation.m`: validate exact active/inactive coverage of the entire observation. Require the actual active coefficient captures themselves to remain contiguous. Bind diagnostic runtime start/end and sample count to that active span, with an explicit `RuntimeChannelCaptureScope` label.
- Preserve full receive-window bounds, inactive intervals, immutable captured tensors and their hashes in the existing channel manifest. Preserve the complete actual desired-link waveform. Every excluded inactive interval must contain actual zero desired-link samples.
- Do not fill missing coefficients, take the reverse link's coefficients, execute a replacement channel, interpolate over gaps, or expose the diagnostic arrays to the practical receiver. Internal active-capture gaps remain rejected. No waveform, receiver, noise, power, scenario or acceptance-threshold changes.
- `tests/testSharedWaveformPhysicalRuntime.m`: capture both real DL-tail and UL-prefix windows across the reciprocal TDD switch. Reload and validate persisted channel artifacts; compare diagnostic arrays/times exactly with actual captures. Reject a removed active coefficient and a nonzero waveform falsely offered as inactive scoring. The existing physical-runtime test remains registered in `testAll`.

## Focused evidence (MATLAB R2026a)

Logs are retained in the archive development checkout under `logs/`:

1. `tdd_channel_crossing_before_repair_20260915.log`: reproduced the exact integrated failure against the original exporter.
2. `tdd_channel_crossing_after_repair_20260915.log`: shared-data physical queue (79.43 s), PHY signal diagnostics (71.55 s), and in-path channel/RF evidence (21.34 s) passed. The new crossing test reached a valid exported artifact but failed on its JSON single-interval vector orientation check. The fixture was corrected without changing interval values or production assertions.
3. `tdd_channel_crossing_final_physical_20260915.log`: physical runtime passed (74.86 s), including DL active `[0,30720)` / inactive `[30720,31232)` and UL active `[30720,31232)` / inactive `[0,30720)`, exact-array checks and both negative guards. Process exit 0.

These are four focused passes across two repaired-source batches, not a full-suite pass. Final-source required config/LLS/strict/scheduler/export/E2E guards and `testAll`, integrated 12 dB completion, detector qualification, combined HARQ/CSI/SR and all-measurement/export acceptance remain outstanding. Earlier validation queues test older revisions and cannot qualify this repair. FDD and 400 MHz remain deferred; the authored SNR sweep is unchanged.
