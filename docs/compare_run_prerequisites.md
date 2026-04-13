# Compare-Run Prerequisites

Compare-run outputs are intentionally gated. They require:

- baseline and candidate run IDs
- comparable scenario family
- aligned config hash or a declared parameter-diff scope
- metric harmonization
- matching KPI source definitions
- final persisted artifacts for both runs

Until those conditions exist, compare-run outputs use:

`classification_code = r`

and:

`current_status = blocked`

The canonical gating artifact is:

`reports/csv/compare_run_prerequisites.csv`

The browser `/analytics` Coverage tab renders this table rather than fabricating a compare result from one run.
