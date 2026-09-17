# Paused bug-fix checkpoint

The user explicitly stopped bug fixing on 17 September and requested this
order: finish the running 5 MHz / 12 dB scenario, update GitHub, then develop
the 400 MHz / 7 GHz / 30 dB TDD research capability with DL and UL 1024-QAM
and actual Keysight IQ capture.

## What this source checkpoint contains

- `68140bb9`: independently selected PUSCH reception retains an actual
  surviving UE PUCCH transmission. Existing focused component guards passed.
- `7e31bec9`: explicit SR-state/selector fixture repairs; focused 4/4 passed.
- `76bf3e69`: independent combined HARQ/CSI/SR PUCCH reception; first focused
  batch 4/4 and strengthened retained-IQ replay/transport guards 3/3 passed.
- Preserved **unfinished, runtime-unverified** mixed PUCCH/PUSCH CSI producer
  disposition edits made before the stop instruction. Files are
  `CoupledWaveformStream.m`, `buildScheduledHARQTransportReception.m`,
  `completeSharedPUSCHAfterRejectedControl.m`,
  `stageUnselectedPUCCHProducerDisposition.m`, and the shared-PUSCH component
  test helper/new `testSharedUnselectedCombinedPUCCHProducer.m` wrapper.
  This new wrapper has not been registered in `testAll` or executed.

Preserving these edits in Git is a backup/checkpoint, **not a claim that the
unfinished path, detector, all measurements or full regression are qualified**.
No detector threshold, power/noise setting or pass assertion was relaxed in
response to the stop instruction. Further repair of the preserved unfinished
changes is outside the latest user-requested scope.

The running 12 dB diagnostic uses frozen commit `68140bb9`, not this newer
checkpoint. Its terminal outcome must be reported separately; a successful
component batch cannot override a failed integrated scenario.

## Cleanup

Only repository `results` and `tmp` were cleared, as explicitly selected by
the user. Six empty subdirectories were removed. The two September 1 evidence
trees (295 files, 56,741,393 bytes) were moved with file-hash verification to
`logs/cleanup_repo_results_tmp_20260917`; they remain recoverable. Windows Temp,
all worktrees, active-run data and unique source edits were untouched.
