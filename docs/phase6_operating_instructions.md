# Phase 6 Operating Instructions

Status: scaffold only. Do not use this branch to claim `Phase6Ok`.

1. Keep every Phase 6 run in a new empty result directory.
2. Resolve advanced-PHY configuration from decoded RRC before UE use.
3. Feed the scheduler only decoded CSI reports or received SRS-derived state.
4. Record measurement timestamps and age at every CSI/SRS scheduler use.
5. Keep true-channel tensors in reference and post-run reconciliation artifacts
   only.
6. Run selected change-oriented tests during development; do not use a passing
   focused test as a full Phase 6 acceptance claim.
7. When a gate is still missing runtime evidence, leave it false and explain the
   missing artifact.
