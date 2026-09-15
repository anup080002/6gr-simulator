# TDD 5 MHz / configured 12 dB: direction-transition gain evidence (15 Sep 2026)

## Scope and root cause

The integrated run `tdd_5mhz_12db_73867a4f_20260915` failed at slot 35 with `sixgr:truth:MissingExecutedGainEnergy`, at `bindSharedLargeScaleEvidence:19` via `runWaveformLinkBundle>localCompleteSharedDataPlan`. It had retained three DL rows and no UL rows. At slot 34 the independent receiver had accepted both DL and UL DCI; the SRS row at slot 30 had measured NMSE -27.5487441552577 dB and `NMSEScoringAvailable=1` over 576 complex values.

A DL receive capture can cross a tail-safe reciprocal TDD direction reversal. The physical runtime already records the desired DL scoring contribution as inactive (actual zero samples) after reversal. The gain binder incorrectly required an active desired-link gain-stage measurement in every receive segment, although that link is then executing toward the opposite endpoint. Do not replace the absent desired-link measurement with the opposite-link energy, configured path loss, or a synthetic zero-energy gain-stage record.

## Repair

- `+sixgr/+truth/bindSharedLargeScaleEvidence.m`: identify one actually executed desired link; sum only its actual direction-active gain-stage records. A direction-inactive exclusion requires same-link reversed-endpoint execution, explicit inactive scoring provenance, and a complete same-window scoring capture whose excluded samples are actually zero.
- Keep complete execution coverage checks. Missing measurements in active segments still fail. Retain active and inactive interval JSON; exclude inactive segments from measured sample-element count. Label the restricted measurement scope explicitly.
- `tests/testSharedWaveformPhysicalRuntime.m`: retain real CDL/RF/noise captures across the switch. Compare DL tail and UL prefix energy/counts against separate direction-active captures. Preserve negative checks for missing active gain records, false inactive claims, missing scoring captures and nonzero excluded contributions.
- No scenario, waveform, power, noise, decoding, detection threshold, ACK, or acceptance-gate changes.

## Evidence and limits

The new physical-runtime case failed on the unmodified binder with the exact integrated error; log: `logs/tdd_gain_crossing_before_repair_20260915.log`.
The first repaired batch crossed that error and passed the energy equalities, but its newly added JSON interval assertion compared a MATLAB column vector to a row vector. The assertion was corrected to compare the exact two bounds independently of JSON vector orientation; no interval values or production gates were relaxed. In that batch, adjacent shared-data and in-path channel/RF tests passed.

Final focused results and new integrated run identity are recorded below when available. Focused tests are not integrated 12 dB acceptance, detector qualification, or complete 3GPP conformance. Queue 11 remains frozen at 73867a4f and must not be represented as testing this newer patch.

## Carried-forward CSV recovery repair

The retained old failure reproduction in the archive checkout reproduced `MATLAB:invalidConversion` in `canonicalizeLLSLiveSignalChainTable`: entirely blank CSI CSV fields import as cells, not numeric arrays. The repair uses the existing strict numeric parser, preserves missing CSI as unavailable, and rejects malformed evidence. Common status-note joining now deduplicates already-joined notes without changing verdict booleans or counts. Component regressions cover both fixes.

The complete copied-run recovery crossed that conversion error and refinalized persisted source CSVs. It still failed later with `sixgr:truth:recover:TerminalArtifactFixedPointFailed` at `recoverLLSRunArtifacts:333`: terminal status and exact plot-source hashes did not converge within three publication passes. This is OPEN, not repaired by the note deduplication claim. The original failed run was not modified or relabeled as passed. Evidence lives in archive `logs/recovery_2c45b257_20260915/`, including `exception_after_repair.json`.

## Still open

Integrated 12 dB completion and all-measurement/export acceptance; final-source required regressions; independent combined HARQ/CSI/SR ownership; detector statistical qualification; normalized CSI measurement availability labeling; terminal report/plot fixed-point consistency. FDD and 400 MHz work remain deferred.

### Final focused batch

MATLAB R2026a: **8/8 PASS**, `logs/tdd_gain_and_recovery_focused_20260915.log`: testSharedWaveformPhysicalRuntime (53.64 s), testSharedDataPhysicalQueue (64.40 s), testInPathChannelRFEvidence (26.11 s), testLLSStatusNoteIdempotency (0.07 s), testPersistedMIMOStatusReducer (1.24 s), testLLSBootstrapEvidenceCSV (1.92 s), testLLSArtifactSanitizerSchemaIdempotency (4.15 s), testLLSRecoveryErrorMessages (0.03 s). Register the previously omitted physical-runtime and in-path-evidence tests in the full suite as well as the CSV/status regressions. This is not a full-suite result.
