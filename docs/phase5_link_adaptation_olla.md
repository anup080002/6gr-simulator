# Phase 5 Link Adaptation And OLLA

Status: baseline scheduler OLLA exists; connected-mode convergence evidence
pending.

`+sixgr/+l2/+mac/SchedulerBase.m` updates OLLA deltas from ACK/NACK feedback
when the feedback is eligible for first-transmission link adaptation. Existing
tests guard that HARQ retransmission ACKs do not relax first-transmission
backoff.

Phase 5 label:

- Link adaptation is baseline non-CSI mode.
- ACK/NACK-driven OLLA is allowed only from decoded radio feedback.
- CSI-RS, CQI/PMI/RI, PUCCH Format 2 CSI, SRS and rank adaptation remain later
  phases.

Required evidence:

- OLLA sign convention.
- Target equilibrium and clipping.
- MCS timeline by UE and direction.
- Feedback source path through PUCCH or decoded PUSCH result.
