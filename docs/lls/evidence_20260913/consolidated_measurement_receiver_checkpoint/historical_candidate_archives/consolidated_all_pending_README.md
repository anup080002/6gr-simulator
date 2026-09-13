# Consolidated feedback, CSI, waveform and PRACH candidates — 2026-09-13

Status: staged, unapplied, uncommitted, not pushed, and NOT runtime-validated.
The 12 dB scenario remains unqualified. This is consolidation of the retained
source proposals, not a claim that all remaining simulator issues are fixed.

Base revision: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.
Patch: pending_consolidated_all_20260913.patch.
29 files, 1,301 insertions, 96 deletions. Whitespace-strict git apply --check
passed against the base checkout. The stage is not another Git worktree and
must not be added to any running MATLAB suite's path.

## Consolidation performed

This patch includes the earlier 22-file feedback/CSI/CRC/independent-PUCCH,
final waveform preview and complete noise-capture proposals, together with
the previously separate PRACH native-allocation retention patch.

The PRACH merge adds three production files, three portable YAML fixtures and
testPRACHNativeRetention. Its sole overlap was an additional testAll entry;
all other 21 files from the preceding stage remain byte-identical. The staged
PRACH runner and ZC-DPE generator match the previously executed standalone
candidates exactly after package-name conversion and newline normalization.

The PRACH producer records allocations only after an active serving/interfering
transmitter is added to the actual receive waveform. Detector templates and
noise-only observations do not become transmit rows. It retains actual native
grids and the generator-plane waveform hash, with explicit study/attempt/UE
identity. Fallback waveform modulators cannot be labelled as standard waveform
execution in the primary native-allocation export. The public runSingle adapter
now passes these retained rows to the existing allocation publisher.

The PRACH evidence archive was SHA-verified before extraction. Its recorded
attempt 04 passed actual NR, noise-only and ZC-DPE component comparisons:
one/four, zero/zero and one/four actual-TX/allocation-row counts respectively.
TrialTable, ROTable and correlation traces matched the then-production runner
after excluding ComputeLatency_ms only. That evidence is for those exact
standalone candidates, not for this consolidated source or public runner path.

The retained NR and ZC-DPE CSVs were rechecked with the current publication
verifier in a fresh output folder. Both CSV/PNG checks exited 0, and both PNGs
were visually inspected. Their matching occupancy images describe matching
resource layouts, not equal detection performance or conformance. Existing
ZC-DPE study limitations remain; it is not relabelled as NR benchmark behavior.

## Preserve and supersede

Use this single patch instead of applying the older overlapping feedback/CSI,
CRC, independent-PUCCH, preview and noise-capture patches. It ALSO replaces
the separate pending_prach_native_retention.patch; do not apply that twice.
All previous stages, patches and evidence archives remain preserved.

The bundle includes the exact earlier PRACH archive, the new retained-CSV
render checks, source-proposal explanations, staged source and SHA manifest.
It does not claim new MATLAB execution merely because source and archive hashes
match. No power, noise, receiver threshold or acceptance assertion was relaxed.

## Required validation and remaining gates

All three original full suites are still live on unchanged checkouts. No new
MATLAB run was launched under the current memory pressure. After an integration
checkout becomes available, run the new tests, including testPRACHNativeRetention
and an actual public PRACH scenario through runSingle; also run the explicit
noise component to exercise its new per-occasion capture path.

The combined source must then pass repository/skill-required testAll and
NR/config/strict/grant/E2E/export/config-driven scenario tests. Earlier component
passes and the three currently running revisions cannot replace final-source
regressions. Retained PNG checks do not validate new public runner execution.

Still unfinished: normal shared PUCCH/PUSCH scheduled-HARQ integration, CSI
report calendar and independent measurement occasions, actual false/missed ACK
qualification, DL timing/CFO/EVM fixture contracts, complete integrated power,
noise, loss and all-measurement closure, the 12 dB run and same-chain SINR sweep.
The later long all-impairments/full-feature study also remains required.
