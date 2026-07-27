# 6GR validation/statistics/publication Codex pack

## Main prompt

`CODEX_PROMPT_14_VALIDATION_STATISTICS_EVIDENCE_PUBLICATION_GATES_WITH_IMPACT_ANALYSIS.md`

## Purpose

Implement one canonical fail-closed engine for:

```text
schemas
statuses and stop reasons
binomial intervals
sequential stopping
zero-error censoring
independent drops
reference/oracle independence
point joins
curve comparison
evidence provenance
measured SINR
time windows
run-class isolation
parallel task merging
artifact validation
canonical scenarios
archive acceptance
publication gates
```

## Installation

Copy this directory to:

```text
tests/vectors/validation/
```

Run:

```bash
python tests/vectors/validation/verify_validation_vector_pack.py tests/vectors/validation
```

Then give Codex the complete contents of the main prompt.

## Pack counts

```text
28 findings
33 independent manifest files
2,149 independent rows
168 capability rows
85 planned MATLAB tests
64 impact families
768 impact experiments
384 matched pairs
96 acceptance rules
48 CSV contracts
52 PNG contracts
```

## Completion boundary

The pack infrastructure passes its own vector and artifact-verifier tests.

The current uploaded MATLAB simulator does not pass this phase and MATLAB was not available for execution in this environment.
