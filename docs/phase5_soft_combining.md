# Phase 5 Soft Combining

Status: helper implemented, full connected-domain proof pending.

`+sixgr/+phy/+harq/combineSoftLLR.m` combines current and prior LLRs only when
both buffers are nonempty, finite in overlapping positions, and have the same
shape. The helper assumes inputs already share the same rate-recovered LDPC
code-block domain.

Phase 5 must prove for DL and UL:

- Rate recovery occurs before combining.
- Buffers are not reset every slot.
- NDI generations, TB identity, code-block identity and segmentation match.
- LLRs from different TBs or incompatible buffers are rejected.
- Combining gain is measured from runtime arrays, not invented after the run.
