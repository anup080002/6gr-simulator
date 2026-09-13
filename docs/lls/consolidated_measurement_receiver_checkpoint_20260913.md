# Consolidated measurement/receiver checkpoint — 2026-09-13

This is an implementation checkpoint for continued validation, **not a qualified
12 dB run, full-suite PASS, or 3GPP conformance declaration**. It supersedes the
unapplied status of the 38-file PUSCH-preflight candidate only. Historical
documents and failed evidence are preserved unchanged.

## Consolidated source

Main was fast-forwarded from 2faf8d91 to 8412775e without discarding any commit.
All 38 candidate files were applied and compared with the saved stage: zero
missing or differing file contents after line-ending normalization. Further
repairs bring this checkpoint to 44 changed/new source and test files:

- Actual UCI CRC results, independent PUCCH receive boundary, receiver-owned
  field extraction, Type-2 gap/wrap identity binding, and HARQ-only shared
  preparation/completion wiring.
- PUSCH feedback binding/process preflight before HARQ mutation; decoder
  usability separated from transmitted-bit scoring. Full independent PUSCH
  Type-2 association is NOT completed by this preflight.
- CSI receiver-completion publication/consumer clocks and frozen planning
  knowledge; final waveform-preview retention; native PRACH allocation
  retention; fuller noise-capture evidence.
- Recovered configured combined HARQ/SR/CSI receive schema, with rank-independent
  PUCCH schema tests. The existing HARQ-only gNB constructor now uses that
  common constructor without changing its schema/digest. Combined runtime
  scheduling, CSI/SR obligations and transport selection remain unfinished.
- Canonical feedback export no longer relabels a usable false ACK as PASS.
  DecodeSuccess remains receiver usability; scoring Status and success/failure
  flags preserve content errors, including stale received feedback.
- Setup excludes logs from both initial and cached MATLAB path setup. Archived
  source below logs had shadowed a current test. Archives remain on disk, but
  must not execute as the current codebase.

No radio power, gain, noise, detector threshold, acceptance assertion or
truth/proxy label was relaxed to obtain these results.

## Evidence and limitations

Evidence is under
`docs/lls/evidence_20260913/consolidated_measurement_receiver_checkpoint/`.
`integrated_source_manifest.json` records the 44 execution-source file hashes
and normalized Git blob identities before this documentation-only addition.

- `focused_seven_pass`: 7/7 passed, process exit 0. Later path-contamination
  discovery limits unasserted test-path claims from this earlier batch.
- `physical_fixture_red`: combined waveform, larger PUSCH feedback, and shared
  receive-only checks passed; physical-clock test failed on incomplete declared
  SSB input. The shared test executed two DL transmissions and an absent-PUCCH
  observation, producing DTX/DTX; UE PDCCH reception was deliberately not run.
  Its actual waveform evidence is preserved separately, not a missed-DCI-rate
  or connected 12 dB claim.
- `feedback_export_red`: new scoring-export regression failed on the old
  canonicalizer's false-ACK PASS label. This is expected bug reproduction.
- `source_shadowing_red`: scoring/CSV checks passed but the physical-clock test
  still selected an archived copy. Do not claim this batch tested its edited
  fixture; the failure's line numbers and preserved archived source exposed it.
- `path_verified_calendar_fixture_red`: source-path assertions passed; 12/13
  checks passed. The current clock fixture then exposed its missing slot-entry
  calendar initialization. It was corrected to call production startSlot,
  not to invent clock values or weaken a production guard.
- `final_clock_and_scoring_pass`: 4/4 passed, process exit 0: source-path
  isolation, physical-owner knowledge consumer, existing future-UL planning
  causality, and feedback-scoring CSV round trip. The actual owner advanced
  7680 samples while the earlier planning view stayed at knowledge sample 0.
  CSI and SSB rows in this clock test are explicitly declared fixtures; no
  CSI-RS RF accuracy qualification is inferred.
- `combined_receiver_waveforms`: actual encoded/decoded rank-1 and rank-2 PUCCH
  component captures; the unchanged gNB schema recovered HARQ/SR/CSI exactly.
  Scheduling and payload inputs are declared component fixtures, not integrated
  report-calendar or propagation qualification.
- Python receipt: 137 tests passed for server launcher, Type-2 vectors, SINR
  limit provenance, radio-measurement plotting and beam-summary auditing.
  These are regression checks, not an audit of new 12 dB outputs.
- The JVM-free initial attempt is retained as failed: waveform hashing requires
  Java. Normal MATLAB reruns retain real hashing; no hash bypass was introduced.

The three earlier full-suite process IDs were absent when rechecked, and no
MATLAB suite process remained. Their logs have no terminal full-suite result.
They are preserved as incomplete, including their original stale `running`
metadata. They were not stopped by this consolidation. A new final-source
testAll and all required NR/config/strict/grant/export/E2E checks are still
required; old suite successes do not qualify this revision.

## Open 12 dB gates

1. Complete normal shared combined HARQ/SR/CSI and independent PUSCH Type-2
   missing-DCI/gap/UL-DAI mapping and receiver-driven commit.
2. Qualify false ACK and signal-present missed ACK jointly. The retained
   12/1024 false-ACK result still exceeds its 1% reference and remains failed.
3. Correct periodic CSI transmission-calendar authority, independent of the
   measurement source slot and arbitrary next-UL-slot shifting; verify actual
   receiver completion through reporting and all consumers.
4. Complete DL clock/CFO/EVM and integrated power/noise/loss, RSRP/RSSI/RSRQ,
   reference/post-equalization SINR, channel estimate, BER/BLER, throughput,
   CSI/SRS and CSV/PNG/IQ acceptance checks on the new execution.
5. Finish mandatory revision-bound regression, then run and audit the actual
   12 dB scenario. The configured same-chain sweep already contains
   [-30,-20,-10,0,10,12,20,30,40]; low-SNR decode failures remain legitimate data.
6. After that closure, perform the separately configured long impairment-enabled
   study. This checkpoint makes no all-features or universal conformance claim.

## Server handoff

Use the committed main branch as a development-validation checkpoint. Run
`scripts/run_server_testall.ps1` from Windows Terminal after Git LFS pull/fsck.
The launcher records MATLAB release, toolboxes, revision, failure details and
a shareable ZIP under `/logs`. Only R2026a has been exercised locally; other
MATLAB versions remain unqualified until their own tests run.

The NR-validation and result-integrity skills guided source/evidence separation,
preservation of false-ACK failures, and keeping fixture tests distinct from
physical qualification. No historical patch, failed capture, or checkpoint
branch was deleted to make the repository appear clean.
