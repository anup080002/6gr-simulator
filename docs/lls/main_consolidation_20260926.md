# Main consolidation — 26 September 2026

This is a source-preservation development checkpoint, not a qualified release.
The requested test is **400 MHz bandwidth at 7 GHz**, not a 4 GHz-carrier test.
The exact Windows Command Prompt launcher, YAML, recorded WebGUI command and
Keysight file mapping are in the [README](../../README.md#400-mhz--7-ghz-rank-2-keysight-waveform-demonstration).

## Source inventory and preservation

- Base `c5cdde8641089c5b7f1ed4912a9880836303a64d` matched freshly fetched
  `origin/main`. Only the `main` branch and one Git worktree exist; there is
  no separate branch to merge and no history rewrite is needed.
- All five outstanding source/test files are included: the standalone HARQ
  diagnostics repair, its new spatial-authority test, test registration, and
  the two configured-CSI clock regression updates. Assertions are retained.
- Two receiver-core candidate edits were developed in a temporary source
  snapshot to avoid changing the active sweep's receiver. Their complete diff
  is now versioned in
  [pending_received_csi_pucch_clock_20260926.patch](pending_received_csi_pucch_clock_20260926.patch).
  `git apply --check` passes against this checkpoint's unchanged receiver
  files. This is a preservation/applicability check, **not runtime verification**.
  Do not automatically apply this patch during an active execution.
- The candidate passes the causally received SRS clock into configured CSI
  PUCCH reception, retains it in observation evidence, and distinguishes an
  inapplicable clock from malformed configuration. It changes neither UCI
  ownership nor detector thresholds. Integration and focused execution remain
  pending; `testConfiguredCSIReceivedClock` is still a known failing regression
  against the installed receiver. The expanded eligibility assertions have
  not yet been exercised against the candidate.
- Both historical recovery stashes are preserved. Their previously documented
  integration commits `cd397f33` and `471334ff` are ancestors of `main`; the
  stashes are not blindly reapplied over newer source.
- `results/`, `logs/`, temporary snapshots and generated instrument files remain
  local under existing ignore rules. No cleanup deletes evidence. GitHub
  contains the source, YAMLs, tests, documentation and preserved pending patch,
  not the multi-GB IQ/results bundle.

## Implemented repair and verified scope

`+sixgr/+truth/exportLLSHARQDiagnostics.m` previously bypassed the explicit
AWGN spatial matrix. Halving the configured channel amplitude reduced power
to 0.25 in the main channel but left probe signal power unchanged at 1.0.
The probe now uses the existing `ChannelFactory` sample operator before adding
the same independently calibrated occupied-RE noise. UL receive dimensions
use the gNB's receive capability. Actual operator identity, matrix digest and
TX/RX dimensions are exported in the diagnostic rows.

The focused spatial regression covers DL and reciprocal UL, amplitudes 1/0.5,
2x2 rank one and 4x2 rank one/two: **12 physical cases passed**. The measured
probe power ratio now matches 0.25 without changing the fixed noise reference.
These cases do not prove arbitrary fading equivalence, the complete sweep or
the full 400 MHz shared-feedback scenario.

Retained evidence:

- Before repair: `logs/harq_spatial_authority_before_fix_20260926.log`.
- Initial post-repair checks: `logs/harq_spatial_authority_after_fix_20260926.log`;
  spatial authority, fixed-noise reference and runtime/probe separation passed.
- Expanded batch: `logs/harq_spatial_authority_matrix_guards_20260926.log`.
  At 01:58 IST, 10 of 11 named tests had passed: spatial authority, configuration,
  DL/UL/reference points, link export, artifact integrity, organizer preservation,
  scheduler consistency and `testE2E_FastVsTruth`.
  `testE2E_TruthPacketSemanticCampaign` was still running, not reported as passed.
- No `testAll` was started, respecting the user's explicit stop instruction.
  Registering tests does not mean the entire suite was executed or passed.
- Checkpoint Python validation: **36 tests passed** for lab waveform packaging
  and no-PDCCH-observation publication guards;
  `logs/consolidation_20260926_harq_checkpoint.xml`. Dependency deprecation
  warnings remain. The PowerShell launcher parses without errors, and all ten
  checked README handoff/dashboard paths exist in the sealed local package.

The active eight-point sweep is not restarted or relabeled by this checkpoint.
Its unfinished execution and failed acceptance checks remain distinct from the
focused repair evidence. No receiver likelihood candidate or unavailable-data
publication helper is silently installed.

## 400 MHz package remains unchanged

The sealed run is
`results/vxg_vsa/7ghz_400mhz_rank2_1024qam/20260925_v1`.
It uses 120 kHz SCS, FFT 4096, 491.52 MSa/s, 264 PRBs, two ports/two layers,
and received-DMRS estimation/MMSE. It is a dedicated data-channel experiment:
access, physical control/feedback, HARQ and link adaptation are disabled.
UL 1024-QAM remains explicitly experimental.

MCS26 at 35/40 dB passed 50/50 DL and 20/20 UL transport blocks, with full-frame
goodput 3.524520/1.409808 Gbit/s. The retained 30 dB failures are not removed or
relabeled; these finite samples are not statistical BLER qualification.

The root manifest was rechecked and remains SHA-256
`dbfd394b1b1781461e41f64b8475531931050c2dbdc32f6d95bda3756a67d60b`.
This check verifies the manifest identity, not a new readback of every IQ file.
The package is transferred separately from GitHub. Physical instrument
capability and hardware import remain **UNKNOWN** pending actual instrument
identity/options and coherent-channel evidence.
