# CSI publication and scheduled HARQ integration follow-up

Base production revision: `8412775e52ffba94f2cb9cb6dc9779d6ac54192a`.
All candidate files remain outside Git checkouts. No 12 dB qualification or
complete combined HARQ integration is claimed.

## CSI evidence

- `csi_publication_clock_candidate_01.log`: declared publication boundary
  passed; actual DL fixture stopped before the CSI binding with
  `sixgr:link:HARQExecutedClockMismatch`. The copied fixture called
  `resolveWaveformGrant(cfg,direction,controlSlot0)` even though the third
  argument is the one-based frame; it also overwrote the job execution slot.
- Attempt 02 retained that fix but incorrectly read a nonexistent legacy
  `cfg.phy.tddTiming` alias. This is a candidate fixture error, not evidence of
  a production channel defect. The final fixture uses the scheduler's
  canonical timing resolver and explicit one-based execution aliases.
- `csi_publication_clock_candidate_03.log`: actual coded DL and CSI receiver
  executed. CSI row Valid=1, ProducerSlot=7, AvailableSlot=8,
  ResultAvailableAtSample=53767. Existing measurement fields were unchanged
  by the binding; the candidate runtime publisher retained clock fields.
  The HARQ executed-clock and received-symbol timing assertions passed.
- The complete attempt 03 still exited 1 at an inherited CFO assertion.
  The parent YAML explicitly disables CFO correction; exported CFO is NaN.
  Do not change that missing estimate into zero or claim the whole test passed.
  The captured EVM was 0.056076 and its independent paired-symbol equation
  and CSV roundtrip passed; that does not qualify the fixture's later 0.02
  performance expectation, which was not reached.
- Raw attempt-03 paired-symbol/trial CSVs remain at
  `C:/Users/anup0/AppData/Local/Temp/tpb5a8bd7f_58c3_458d_87f4_fb17d939cfa2/air_interface/csv`.
- Shared production consumer sample-clock wiring, mixed-signal ledger schema
  handling and the independent periodic CSI report calendar remain open.

## HARQ integration under test

`CoupledTruthRuntimeFeedbackCandidate.m` now includes a shared gNB disposition
entry using the actual transmitted-grant mapping and retained complete RX
buffer. It prevalidates every process/TBS/NDI, guards duplicate consumption
across transports, applies HARQ and scheduler feedback once, and publishes
actual mapping/disposition evidence. The existing receiver-only shared PUCCH
path is wired to this entry in the candidate class.

`testSharedScheduledFeedbackCommitCandidate` exercises actual shared DL TX,
SRS, thermal noise and absent-PUCCH reception, with independent replay and
duplicate-transport negative checks. Terminal exit was 0 in
`shared_scheduled_feedback_commit_candidate_01.log`: two actual DL TXs,
zero UE UCI producers, two correctly mapped DTX dispositions, independent
actual-IQ replay equivalence, and rejected repeated/cross-transport commits
without changes to HARQ processes, counters or buffers. This is not a
measured missed-DCI rate, PUSCH decode test or detector qualification.
The normal combined PUCCH and PUSCH adapters are not yet migrated; this
candidate is not full B02 closure and has not been merged or uploaded.

## Workflow

The three previously started full suites still run on unchanged checkouts.
The user explicitly chose to keep all three full suites running. Their
source checkouts must remain unchanged. No process has been stopped.
