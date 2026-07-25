# 6GR PUSCH / UL-SCH Codex implementation pack

This pack drives an implementation-and-execution remediation of the MATLAB PUSCH/UL-SCH chain. It is not a review-only checklist.

## Start here

1. Place this directory at `tests/vectors/pusch/` in the simulator repository.
2. Open Codex at repository root.
3. Paste the full contents of `CODEX_PROMPT_03_PUSCH_ULSCH.md`.
4. Require production edits and execution; reject a plan-only response.
5. Accept `COMPLETE` only after the MATLAB suites, phase runner, 20 CSVs, 11 PNGs, and Python artifact verifier pass.

## Pack scope

- 12 source-specific implementation findings;
- 2,700+ line Codex production prompt;
- 16 deterministic input files, 487 rows;
- 15 bounded independent expected files, 480 rows;
- source static audit and existing-output inventory;
- 20-CSV and 11-PNG output contracts;
- vector-integrity verifier;
- fail-closed artifact and image-semantic verifier;
- limited non-MATLAB execution report.

## Important correctness points

- Scheduling Request is routed to PUCCH, not encoded as generic UCI on PUSCH.
- Transform-precoded strict PUSCH is rank 1; high rank belongs to release-valid transform-disabled tuples.
- PUSCH strict modulation is pi/2-BPSK through 256QAM; 1024QAM and 4096QAM are rejected.
- Dynamic PUSCH, Type-1 CG, Type-2 CG, Msg3, MsgA, and calibration use separate factories.
- Same-Toolbox comparisons are self-consistency, not independent conformance vectors.

See `PUSCH_ULSCH_LIMITED_TEST_EXECUTION_REPORT.md` for measured current results and blocked runtime work.
