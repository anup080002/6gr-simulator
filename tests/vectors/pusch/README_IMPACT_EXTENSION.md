# PUSCH/UL-SCH implementation + impact-analysis Codex pack

This directory contains the original complete PUSCH/UL-SCH implementation pack plus a mandatory impact-analysis extension.

## Main prompt

Use `CODEX_PROMPT_03_PUSCH_ULSCH_WITH_IMPACT_ANALYSIS.md` as the standalone Codex prompt.

## Scope counts

- Correctness findings: 12
- Impact families: 52
- Experiment definitions: 705
- Pairing contracts: 52
- Acceptance rules: 70
- Independent analytical-floor rows: 59
- Base required CSVs: 20
- Base required PNGs: 11
- Additional impact CSVs: 16
- Additional impact PNGs: 26

## Preflight

```bash
python verify_pusch_vector_pack.py
python verify_pusch_impact_pack.py
python verify_pusch_impact_artifacts.py --self-test
```

The impact pack does not contain expected BLER curves. Performance values must come from the corrected MATLAB production chain. The supplied floor contains exact arithmetic, identity, power and fail-closed relationships only.

The pairing contract is mandatory: it separates paired baseline/treatment studies, within-trial comparisons, independent-oracle checks, multilevel sweeps, factorial analysis, and end-to-end scenario summaries.
