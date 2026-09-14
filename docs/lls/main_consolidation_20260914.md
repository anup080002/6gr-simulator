# Main consolidation checkpoint — 14 September 2026

This is a source-integration checkpoint, **not a testAll pass or a qualified
12 dB simulator release**. The integrated source still requires execution.

Main retains both CSI commits through ancestry: `032ad7e6` (receiver availability
through publication) and `52f5df92` (configured periodic producer/calendar).
Twelve ordered retained repair patches were applied to that base. All 68 final
patched files match the hash-checked source composition. No old patch was
replayed on top of its successor. The other two running worktrees were unchanged.

Included repairs cover independent PUSCH receive context and scheduled HARQ
mapping, invariant UCI/data resource handling after failed CSI Part 1, separate
resolved-codeword LDPC/CRC decoding, configured PBCH-only channel/noise execution,
SINR status-aware progress reporting, normalized-versus-absolute transmit power
exports, DCI K1 configuration authority, common access control configuration,
resource-accounting error causes, and explicit isolated-test assumptions.

## Evidence boundary

Before integration, main's full suite completed 412 passing and 20 failing tests
then crashed in MATLAB; its native crash cause is not established. Its separate
12-test guard pipeline subsequently passed and exited normally. That guard pass
does not erase the full-suite failures or validate these newly applied patches.
Both main pipeline processes and the parent wrapper were terminal before edits.

Existing seven-test CSI and late-CSI physical component passes remain scoped to
their recorded source and conditions. The latter used 60 dB. The small PUCCH
preflight is not statistical qualification; the 12/1024 false-ACK failure remains.
No threshold, loss, noise or acceptance criterion was relaxed for consolidation.

Full local patch/source/archive receipts are preserved under
`logs/pending_integration_evidence_20260913/`. The final twelve-patch composition
receipt is in `sinr_progress_status_candidate_01/integration_chain_receipt.json`;
the actual main-application receipt is in `main_consolidation_20260914_01/receipt.json`.
These ignored local evidence directories are not automatically included by Git.

## Still required

- Execute the integrated tests and repair failures without weakened gates.
- Finish normal mixed HARQ/CSI/SR and independent PUSCH completion/commit wiring.
- Qualify false and missed ACKs using sufficient matched physical observations.
- Close all measurement families and audit actual CSV/PNG outputs and provenance.
- Run final-source testAll and NR/config/strict/scheduler/export/E2E/scenario guards.
- Run and audit the integrated 12 dB scenario, then its configured same-chain
  sweep `[-30,-20,-10,0,10,12,20,30,40]`.
- Run the later impairment-enabled 6G study with explicit benchmark/study/
  experiment classifications; do not imply universal 3GPP conformance.

The unfinished SR calendar/MAC components and detector-design experiments remain
preserved as candidates, not installed as completed runtime functionality.
No old logs, failed attempts, evidence archives or running worktrees were deleted.
