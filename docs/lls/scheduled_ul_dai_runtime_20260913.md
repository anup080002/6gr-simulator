# Scheduled UL total DAI runtime finalization

Base revision: `7c215d65`. Work is on the existing
`work/type2-runtime-20260913` branch, not the main worktree under validation.
The full shared-UCI integration and 12 dB measurement gates remain open.

## Runtime change

`runWaveformLinkBundle` now calls `prepareScheduledULDAI` before actual
PDCCH preparation. Ordinary connected DCI 0_1 no longer transmits its
provisional/default DAI unchanged. The finalizer counts accepted DL
assignments for the same UE, physical cell, component carrier, epoch and
feedback occasion as the PUSCH slot. It rejects future, corrupted,
duplicate or discontinuous matching scheduling entries.

It repacks only `first_dai`, retaining the original PHY allocation, TBS and
timing decision. Its authority record binds the selected scheduling entries
and the packed raw/semantic DAI. UE decode status, received ACKs and
observer-row order are not inputs. Zero assignments encode raw three
(semantic four), rather than inventing two feedback positions from the
old raw-one default.

The two-bit count mapping and no-DL-reception special case use
[TS 38.213 V18.8.0, clause 9.1.3.2 and Table 9.1.3-2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).
The supported context remains the ordinary single-cell, single-TB dynamic
codebook profile; this does not add SPS, CBG or grouped codebook support.

## Validation status

`testScheduledULTotalDAI` is registered in `testAll`. Its nine declared
scheduling-ledger cases cover counts zero through eight, unchanged unrelated
DCI/PHY/timing fields, repeated finalization, contradictory observer fields
and 24 corrupted/future-ledger negative checks. Each case must encode and
actually decode its UL DCI, then use that received capsule to form the
no-received-DL-event UE codebook. Scheduling fixtures are explicitly declared
inputs, not reported as nine real DL campaigns.

The first fixture failed before the finalizer: it requested a full UL
allocation in a special slot containing unresolved flexible symbols. The
second reached a legal UL slot but exposed a missing TPMI in the generic
`resolveWaveformGrant` calibration helper. Neither timing nor strict SRS/
precoding guards was relaxed. Both original logs are retained:

- `evidence_20260913/sixgr_scheduled_ul_dai_20260913_01.log`
- `evidence_20260913/sixgr_scheduled_ul_dai_20260913_02.log`

The current test instead uses the original frozen grant from
`evidence_20260913/received_ul_harq_slot_10.mat`, produced by a real shared
SRS/received-UL-command/PUSCH execution, and loads its matching authored
scenario. This preserves the actual two-port spatial and timing authority;
no SRS measurement or TPMI is synthesized. The new control receptions are
component evidence, not a fresh shared PUSCH or baseline pass.

The third focused run completed with exit zero and
`SCHEDULED_UL_DAI_FOCUSED_PASS`: nine actual UL DCI receptions, counts zero
through eight, 24 negative guards, and the existing DL counter regression.
Its ten original output files (1,119,462 bytes) are preserved with verified
copy hashes in `evidence_20260913/scheduled_ul_dai_03/`; the successful log
and source/artifact receipt are retained alongside both failures.
Required integrated regression and configuration/LLS/export/grant/E2E guards
remain required on this source.
The generic calibration helper's missing connected-UL TPMI remains a
separate unclosed issue; the test change does not claim to fix it.

The receipt records both exact as-executed source byte hashes and Git blob
identities. Checkout on Windows changes line endings; the earlier receipt
still matches all 12 files in its original live checkpoint worktree. Eleven
unchanged files have identical Git blobs/text across both worktrees. The
twelfth, `testAll`, has the newly added registry entry in this worktree.
No historical receipt or original source-byte hash was rewritten.

## Superseded validation preservation

The older development full suite was explicitly stopped to free its worktree
after both newer revisions had started validation. Its original source was
an ancestor of main and the receiver checkpoint. It is **stopped/incomplete**,
not passed: terminal wrapper output was `PROJECTION_FULL_EXIT=-1`.
No result folder, commit or branch was deleted.

Original final partial log:
`evidence_20260913/stopped_superseded_projection_full_20260913.log`,
SHA-256 `a4afb2e0eb62f5587e400ecac490fb227d8f31fdf506d6762ec2b841b4719327`.
It was copied only after the process exited and verified byte-for-byte.
Main `5b07063c` and checkpoint `7c215d65` suites continue on unchanged source.

## Remaining acceptance

Scheduled DAI finalization alone does not close B02. The shared PUCCH/PUSCH
transmit builders must consume the received-event codebooks; independent
gNB receive-only windows, payload-length/resource hypotheses and decoded-bit
disposition must replace UE-row-dependent decisions. Actual missed-DCI,
wrap, retained-ACK and absent-feedback cases remain necessary. Detector
qualification, the full measurement matrix, baseline execution and final
main consolidation remain open.

NR-validation and result-integrity rules determined the separate gNB/UE
authorities and preservation of failures. No power/noise scaling, detection
threshold or acceptance limit was changed.
