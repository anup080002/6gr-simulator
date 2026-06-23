# Reporting Pipeline Architecture

Phase 1 separates runtime evidence from post-link reporting.

The reporting path now emits heartbeat and stage events through `sixgr.runtime.RuntimeEvidenceBus`. Table artifacts written by `sixgr.truth.exportLLSOutputCoverageArtifacts` are wrapped with `sixgr.runtime.RuntimeArtifactTransaction`, producing explicit `ARTIFACT_BEGIN`, `ARTIFACT_COMMIT`, or `ARTIFACT_FAIL` records.

This does not make PHY blocks pass. It only proves whether reporting progressed, which artifact was being written, whether it was committed, and whether a readback/size validation ran.

The intended lifecycle is:

1. Runtime journals are created during execution/reporting.
2. Reporting stages emit `STAGE_START`, `HEARTBEAT`, and `STAGE_END`/`STAGE_FAIL`.
3. Artifacts are written and committed with byte count and SHA-256.
4. Derived CSVs are generated from the journal for audit use.
5. Final status must be composed by a root-gate evaluator, not by lower-level labels.

Current Phase 1 scope instruments the existing post-link exporter. Later phases should add `RuntimeBlockScope` and `RuntimeMessageTracker` around live PHY/MAC blocks without changing numerical behavior.
