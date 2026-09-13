# Received UL DAI and independent feedback mapping

Work starts from integrated main `5b07063c`, in the existing receiver
checkpoint worktree. Main and the older development full-suite sources
remain unchanged while their jobs run. This is a bounded B02 repair;
**shared feedback integration and the 12 dB acceptance gate remain open**.

## Implemented candidate

- PUSCH Type-2 codebook construction consumes an integrity-checked, received
  DCI 0_1 capsule. Its two-bit total DAI controls the final codebook length.
  The received UL assignment/payload digests, UE, epoch and target slot remain
  bound to the typed codebook. DL events are neither rewritten nor invented.
- With no received DL event, UL semantic DAI four omits HARQ-ACK; other
  indicated positions are protocol NACKs. These positions are not measured
  PDSCH outcomes or receiver DTX.
- `PUSCHUCIPayload` retains the typed PUSCH report. PUCCH planning rejects
  accidental reuse of a PUSCH-specific codebook and mixed UE/occasion
  identities. Existing raw component payloads remain supported.
- `buildReceivedHARQACKCodebook` selects typed received events available on
  the shared physical clock. It does not read gNB expectations or observer
  feedback rows.
- `buildScheduledHARQACKMapping` constructs independent gNB bit identities
  from committed physical DL transmissions and their scheduling expectations.
  It does not read received UE events or expected ACK bits. Its supported
  scope is ordinary single-TB, two-bit-DAI Type-2 feedback, with one assignment
  per monitoring pair. Missing/inconsistent execution evidence fails.

The PUSCH-specific procedure follows
[TS 38.213 V18.8.0, clause 9.1.3.2 and Table 9.1.3-2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).
It is not interchangeable with the PUCCH final-length rule in clause 9.1.3.1.
This does not implement CBG, multi-TB bundling, SPS append, cross-carrier
scheduling or Type-2 grouping.

## Validation, not yet qualification

The first actual received-UL-DCI test failed with
`sixgr:phy:pucch:InvalidHARQEvent` in the empty-event source-index check.
For a nonempty all-gap codebook, MATLAB returned a differently shaped empty
selection than the empty expected-event vector. Both sides now use explicit
column shape; the invariant still requires each received event exactly once,
in order. The failed log is preserved as
`sixgr_ul_dai_focused_20260913_01.log`.

A second focused batch completed with exit 1: five tests passed; the new
scheduled-mapping test failed because hashing the full grant attempted to
JSON-encode complex precoder values. The mapping digest now covers its bit
identities, physical grant/context IDs and scheduled DCI hashes, while the
original grant remains separately retained for resource planning. No physical
execution check or feedback assertion was removed.

The second batch covered:

- 16 actual CRC-accepted PDCCH/DCI 0_1 receptions and 32 PUSCH codebooks,
  including no-DL-event cases, received capsule and identity negative tests.
- Existing Type-2 layout vectors and PUCCH resource planning, with new
  wrong-UE/slot/transport rejection checks.
- Two actually transmitted coded DL contributions for the independent gNB
  mapping. This fixture intentionally claims no UE decode or UCI reception.
- Archived retained-ACK provenance on an advanced shared clock, with
  observer-row independence and future-event/clock-rate rejection checks.
- Existing modulation-specific PUSCH UCI soft-decode/CRC evidence tests.

Passed: 16 actual UL DCIs, 32 codebooks and 64 guards; 256 DAI sequences and
24 legacy vectors; PUCCH planning/identity guards; retained shared-clock ACK
with 11 guards; modulation-specific PUSCH UCI evidence. Original passing UL
captures are retained in `evidence_20260913/received_ul_dai_codebooks_02/`
(17 files, 1,427,218 bytes; source/destination SHA-256 verified for every file).
The scheduled-mapping rerun and `testUCIPUSCHPhaseCore` completed with exit 0
and `UL_DAI_MAPPING_FOCUSED_PASS`. The mapping fixture transmitted two coded
DL assignments sharing feedback slot four, with zero UE receptions and zero
gNB ACK/NACK updates. The complete six-file fixture output, including four
continuous TX-IQ streams, is retained in
`evidence_20260913/scheduled_harq_mapping_03/` (1,512,979 bytes).
This is transmission/mapping evidence, not a UCI receive or access-run pass.
Source and artifact hashes, both original failures, and the successful rerun
are bound in `evidence_20260913/received_ul_dai_component_receipt.json`.

Required guards and the full suite must finish on the changed source before
any broader qualification claim. Earlier main/development passes cannot
qualify this candidate.

## Remaining integration work

1. Finalize the scheduled UL total DAI from the gNB scheduling ledger before
   PDCCH encoding. `ConnectedDCIProfile.scheduledFields` still defaults
   `first_dai` from `grant.DAI`; the new received-side helper does not repair
   that producer by itself.
2. Wire the shared PUCCH/PUSCH transmit builders to the received-event
   codebooks. Preserve protocol-gap positions and their event mapping;
   pending-feedback row order is not codebook order.
3. Arm gNB receive windows from transmitted scheduling obligations even
   when UE DCI decoding fails. Build receiver-only resource/length context
   independently; do not borrow the UE transmitted payload or its length.
4. Map actually decoded UCI through the gNB assignment mapping to HARQ
   process/NDI/source-slot state. Replace the current one-bit-per-row
   assumptions atomically, including PUSCH multiplexing/censoring paths.
5. Execute shared missed-DCI, DAI-wrap, retained-ACK and absent-feedback
   cases, then detector qualification and the full measurement matrix in
   `12db_measurement_closure_plan_20260913.md`.

No power scaling, noise injection, receiver detection threshold or acceptance
limit was changed. NR-validation and result-integrity rules guided the
separate authority boundaries and retention of failed evidence.
