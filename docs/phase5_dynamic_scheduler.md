# Phase 5 Dynamic Scheduler

Status: scheduler primitives exist; complete candidate lineage pending.

Existing surfaces:

- `+sixgr/+l2/+mac/SchedulerBase.m`
- `+sixgr/+l2/+mac/SchedulerPF.m`
- `+sixgr/+l2/+mac/SchedulerRR.m`
- `+sixgr/+l2/+mac/resolveHARQFeedbackK1.m`

The scheduler currently supports HARQ retransmission priority, queue-limited
TBS sizing, PF and RR scheduling, k1/k2 fields, and OLLA updates from feedback.
Phase 5 requires every legal DL and UL opportunity to emit candidate and
rejection lineage, including PF score inputs, tie-break reasons, HARQ state,
queue source, power/control constraints, TDD legality and starvation guards.

Connected-mode UL grants must be sourced from decoded SR/BSR/PHR and permitted
protocol state. Direct UE queue reads remain outside Phase 5 truth.
