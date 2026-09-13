# CSI mixed-clock consumer follow-up — 2026-09-13

Status: incomplete candidate validation; not integrated, committed or qualified for 12 dB.

Base production revision: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.

## Source changes

- causalMeasurementMixedClockCandidate distinguishes a row's explicit clock domain from NaN columns added by mixed-table schema alignment. Slot-only SSB/SRS rows may still be selected by slot-based callers; sample-clocked CSI still requires sample-level knowledge and matching epoch/rate/chronology. Unknown domains and attempts to relabel finite clock evidence as slot-only are rejected. Sample-mode callers still require complete clock evidence; no sample availability is invented for slot-only rows.
- csirsMeasurementAvailabilityStrictCandidate rejects unknown clock domains and prevents availability/epoch fields from being silently discarded by missing or slot-only labels.
- CoupledTruthRuntimeCSIConsumerCandidate connects publication to the sample-clock selector, using referenceMeasurementClockArgumentsCandidate to read the actual CoupledWaveformStream owner. Future UL planning views retain their original decision sample/rate/epoch, so advancing a shared handle cannot reveal later measurements to an earlier decision.
- The clock-argument helper filters by valid matching measurements and does not infer the consumer's time from a measurement's availability. Historical slot requests are bounded to that slot; OFDM boundaries come from slotStartSample, not average slot duration.

## Executed and unexecuted checks

- testCausalMeasurementMixedClockRegressionCandidate PASSED. It retains the prior boundary, older-ready/newer-future retention, row-order, nonuniform-calendar, malformed clock, epoch and legacy regression checks.
- testCSIMixedClockConsumerCandidate reached line 43 after its pure-selector assertions, then MATLAB stopped with Out of memory at the runtime-class publication call. This is NOT a whole-test pass.
- testCSIPhysicalKnowledgeConsumerCandidate was queued after that failure and did NOT execute. It must verify the actual-owner clock and frozen future-planning view once memory is available. Its CSI rows are declared boundary fixtures, not CSI-RS RF evidence.
- Batch exit code was 1. The failure log is retained as csi_mixed_consumer_candidate_01.log.
- After the failed run, the clock-argument helper's binary validity/filtering guard was added. This helper change is untested.

At diagnosis Windows reported 12,405,860 KiB visible RAM, 1,141,308 KiB free RAM, and 2,445,100 KiB free virtual memory. All three requested suites were kept running. No MATLAB worker or suite was stopped, no pagefile/system setting was changed, and no further memory-heavy test was launched.

## Candidate source consolidation

CoupledTruthRuntimeCombinedCandidate mechanically combines the earlier HARQ feedback-commit candidate with this CSI publisher/consumer candidate. A source-delta comparison passed: the CSI additions/deletions match exactly and the HARQ candidate code is retained. This is a SOURCE MERGE CHECK ONLY. The combined runtime class has NOT been executed. Earlier candidate source/evidence is preserved for comparison.

The combined class still needs the rest of normal shared-feedback wiring, independent CSI/SR report obligations/calendar, normal PUCCH/PUSCH consumers and actual CSI receiver-completion binding at production execution sites. It is not a replacement for those unfinished changes.

After integration, execute the pending targeted tests and the repository/skill-required full, NR/config/strict/grant/E2E/export tests on the final source revision. The three older live suite runs do not validate these candidate edits. The baseline false/missed-ACK and all-measurement/power/noise/loss/12 dB gates remain open.
