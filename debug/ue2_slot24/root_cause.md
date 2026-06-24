# UE2 Slot 24 Root Cause

Status: pending live reproduction.

Known prior symptom:

- UE: 2
- Direction: DL
- Slot: 24
- MCS: 18
- Modulation: 64QAM
- Decoder iterations: 100
- Raw BER: approximately 0.140
- TB CRC: fail

This file deliberately does not classify the failure yet. The next patch must
capture the exact grant, receiver stages, independent RE/TBS reconciliation,
LLR/rate-recovery diagnostics, and reference-mode comparisons before changing
receiver, link-adaptation, scheduler, seed, channel, or decoder behavior.

Allowed final classifications are the Phase 5 prompt list: DCI mismatch,
resource extraction mismatch, RE collision, DM-RS mismatch, estimator defect,
timing/CFO/phase/noise/equalizer issue, layer/port mismatch, descrambling,
LLR sign or scale, rate-recovery, RV/TBS/segmentation, soft-buffer
contamination, decoder defect, or physically valid outage.

If physically valid, preserve the first-transmission NACK and prove recovery
through live HARQ. If a code defect is found, fix the defect and add a
deterministic regression test.
