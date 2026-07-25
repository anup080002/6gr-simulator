# PDCCH/DCI Codex implementation and impact-analysis pack

Main instruction: `CODEX_PROMPT_04_PDCCH_DCI_WITH_IMPACT_ANALYSIS.md`

Contents:

- 14 source-specific PDCCH/DCI findings;
- 24 deterministic input/reference files with 1,369 rows;
- complete Release-18 Type-0 CORESET Tables 13-0 through 13-10A, monitoring Tables 13-11/12/12A, pattern-2/3 Tables 13-13 through 13-15A, and GSCN Tables 13-16/17;
- pure-spec CRC24C/RNTI masking, scrambling, QPSK, PDCCH DM-RS, CORESET mapping, candidate-enumeration, and grant-authority floors;
- 50 impact families, 600 experiments, and 300 controlled baseline/treatment pairs;
- 75 acceptance rules;
- 21 base CSVs, 13 base PNGs, 16 impact CSVs, and 28 impact PNGs—78 required production artifacts in total;
- vector, artifact, and impact verifiers with corruption self-tests.

MATLAB production execution remains mandatory. The pack does not permit completion based only on Python, static, or vector checks.
