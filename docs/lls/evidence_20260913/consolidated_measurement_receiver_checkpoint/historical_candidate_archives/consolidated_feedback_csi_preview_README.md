# Feedback/CSI and final waveform preview candidate — 2026-09-13

Status: staged, unapplied, uncommitted, not pushed, and NOT runtime-validated.
The 12 dB scenario remains unqualified. All three existing full suites continue
against their unchanged source checkouts; none validates this candidate.

Base: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.
Patch: pending_consolidated_feedback_csi_preview_20260913.patch.
21 files, 1,101 insertions and 93 deletions. Whitespace-strict git apply --check
passed against the base checkout. This is applicability evidence, not a test pass.

## Newly isolated failure and proposed correction

The checkpoint suite logged test6GLLSCoupledTruthBidirectional FAIL at 13:56 UTC.
The stack identifies runWaveformLinkBundle line 329. Its error message used
horizontal concatenation of two string scalars, producing a string array and
MATLAB:error:badMessageArgument instead of MissingFinalSharedWaveformPreview.

The preceding execution log identifies immediate per-grant DL/UL execution.
Source inspection shows that this path creates real WaveformPreviewTable rows,
sends them to chunk-level live publication, but does not retain them in the
returned runtime. Finalization incorrectly requires SharedWaveformPreviewTable
for all slot-coupled runs, including this non-shared path.

The new staged source retains each committed immediate grant's existing preview
table in runtimeState.WaveformPreviewTable. finalCoupledWaveformPreview selects
that table for immediate execution and SharedWaveformPreviewTable when the
runtime has a typed shared owner. The two evidence stores cannot rescue one
another. Missing/empty/non-table evidence still raises a named scalar diagnostic.
No waveform, grid, power, noise, bit decision, threshold or KPI is reconstructed.

testFinalCoupledWaveformPreview adds declared-table boundary cases: exact value
and metadata preservation, path selection, invalid runtime owner, missing/empty
and non-table previews, and rejection of cross-path rescue. It is registered in
testAll but has NOT run. Its fixtures are not actual RF qualification evidence.

The candidate remains subject to the integrated coupled bidirectional regression,
shared-stream execution and final artifact inspection. The original scratch
scenario was removed by the suite's own cleanup; the durable suite log snapshot
preserves its failure stack, not its already-deleted raw waveform artifacts.

## Consolidation and remaining work

This patch supersedes pending_consolidated_feedback_csi_20260913.patch and includes
all its staged source changes. Old patch, stage and evidence archives are retained.
Only the bundle source and testAll changed among its existing files; the new helper
and test are added. Separate PRACH retention work is still NOT included. Do not
apply overlapping older HARQ/CSI/CRC/PUCCH proposals on top of this patch.

Existing HARQ/CSI/CRC/independent PUCCH qualifications retain their exact earlier
scope; they do not validate the combined source. Normal shared PUCCH/PUSCH mapping,
CSI reporting calendar and independent occasions, detector false/missed ACK limits,
DL fixture timing/CFO/EVM contracts, and all-measurement closure remain unfinished.

After an integration checkout is available, run the new leaf test and integrated
test6GLLSCoupledTruthBidirectional, then all repository/skill-required testAll,
NR/config/strict/grant/E2E/export tests on the final source. No additional MATLAB
batch was launched during this change: three requested full suites are live and
the preceding candidate batch exhausted memory. Do not interpret this deferred
validation as a waiver of any test or acceptance gate.
