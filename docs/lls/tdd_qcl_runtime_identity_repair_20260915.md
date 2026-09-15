# 5 MHz TDD / 12 dB: runtime QCL identity repair

Unqualified integration checkpoint. The scenario, noise/power authority, QCL
configuration and strict receiver assertions are unchanged. FDD and 400 MHz
remain deferred. The complete production-validation goal remains open.

## Integrated failure on cc1dae18

Run `tdd_5mhz_12db_cc1dae18_20260915` passed the prior SSB clock boundary:
actual SSB observations from source slots 21/22 published with valid complete
sample-clock evidence at slots 22/23. Initial access reached received Msg1
(15), RAR (17), Msg3 (20), Msg4 (23), RRCSetupComplete (25), all PASS with no
placeholder/fallback flags. Actual received RA MAT captures are retained.

SRS source slot 30 received PASS (NMSE -27.5487441552577 dB) and became usable
at slot 31. A real 1064-bit DL grant was issued and its DCI decoded. During
completion of the first PDSCH observation, at coordinator slot 32, the run
failed with `sixgr:qcl:ReferenceIdentityMismatch`. Connected DL/UL trial
counts were still zero. This is NOT a successful 12 dB run.

Original error: `meta/failure_debug_report.txt` under the run folder in
`logs/scenario_runs/lls/lls_causal_access_to_data_wiring_tdd_short_continuous_iq/`.
SHA256: `12c1553d19917b44c132a0de7da3143f6c1176060f636282904a1583a81d9ee6`.
Post-failure report recovery was stopped at 19:47 IST to free the checkout for
repair. Original raw evidence/logs remain; the recovered bundle is INCOMPLETE.
Queue 08 was stopped while still waiting; neither guards nor testAll ran in it.
Separate stop receipts are retained under logs. No active successful run was
stopped, and no failed output is promoted to a primary passing artifact.

## Root cause and fix

`CoupledTruthRuntime.applyUserContextImpl` supplied RuntimeServingCell, PCI
and deployment CellID but omitted RuntimeServingCellIndex. The received QCL
consumer intentionally uses the runtime layout index, separately from the RRC
serving-cell index and PCI. Its missing field became NaN and the exact identity
assertion failed. The old test manually supplied that field, hiding the gap.

- Bind RuntimeServingCellIndex from the same current runtime servingCell used
  for the prepared PHY link. Rebinding also replaces stale context values.
- Keep the QCL identity predicate unchanged. Its error now prints both sides
  of UE, runtime-cell, resource and sample-rate identity for future diagnosis.
- `testReceivedDLQCLAuthority` now invokes the real runtime binder instead of
  hand-setting the missing index, checks stale-context rebinding for DL/UL,
  then exercises retained actual received DCI/data. Its timing-source input
  remains an explicitly declared boundary fixture, not claimed TRS reception.

## Executed regression-first evidence (R2026a Update 4)

- Before producer repair: `logs/testall_20260915T141846139Z_0fb3764f`, FAIL
  `testReceivedDLQCLAuthority:MissingRuntimeServingCellIndex`, 24.54 seconds.
- After repair: `logs/testall_20260915T142038225Z_0f96513c`, 5/5 PASS:
  testReceivedDLQCLAuthority (31.92 s), testSharedQCLTimingTransfer (0.45 s),
  testSharedQCLScenarioContract (7.03 s), testDefaultCORESETQCLReference
  (11.87 s), testPDSCHQCLStatePropagation (0.82 s). The retained 1064-bit
  block decoded with measured delay 43 and search window [39,47]. Negative
  identity, DCI, stale/future and timing guards remain enforced.

These tests ran on unchanged dirty source based on cc1dae18; they are focused
evidence, not final clean-source full-suite or integrated qualification.

## Next acceptance work

Rerun the exact unchanged 58-slot 5 MHz TDD configured-12-dB scenario on this
clean repair. Verify PDSCH completion beyond the old QCL boundary, actual UL
data, shared HARQ/CSI/SR, full measurement definitions and exact CSV/PNG
provenance. Re-arm required guards and testAll behind the priority run on the
same frozen revision. Previous 46 full-suite failures and detector statistical
qualification remain open; main is not qualified.

The live output audit also found a misleading final-access summary label
(`prach_msg1_detected` for completed RRC access) in applyPRACHTrialImpl. SRS
NMSE availability, timing reference-plane labels and normalized RA capture
amplitude units need source-by-source reconciliation. Details are preserved
in `logs/tdd_5mhz_12db_cc1dae18_review.md`; none is declared fixed here.
