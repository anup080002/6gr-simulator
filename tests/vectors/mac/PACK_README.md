# 6GR MAC/HARQ/Scheduling Codex Pack

## Purpose

This pack is an implementation-and-execution package for the actual MATLAB MAC/HARQ/scheduler chain. It is not a review-only checklist.

## Install in the repository

Copy this folder to:

```text
tests/vectors/mac/
```

Keep the standalone Codex prompt available at the repository root or paste its full content into Codex:

```text
CODEX_PROMPT_08_MAC_HARQ_SCHEDULING_WITH_IMPACT_ANALYSIS.md
```

## Required order

1. Verify the vector pack.
2. Implement event store, state projection, central timing and HARQ identity first.
3. Implement soft-buffer provenance and atomic grant commit.
4. Implement exact BSR, PHR, SR, LCP, MAC PDU/CE and timing advance.
5. Migrate PF/RR and add QoS-PF/EDF over a common immutable snapshot.
6. Implement packet lineage and conservation.
7. Run all MATLAB tests and base phase validation.
8. Run impact analysis.
9. Run both Python artifact verifiers.
10. Run the complete repository regression.

## Core commands

```bash
python tests/vectors/mac/verify_mac_vector_pack.py
```

```bash
matlab -batch "addpath(pwd); s=sixgr.l2.mac.runMACHARQSchedulingPhaseValidation('VectorRoot',fullfile(pwd,'tests','vectors','mac'),'OutputDir',fullfile(pwd,'artifacts','mac_harq_scheduling_phase'),'SeedList',[11 23 47 89],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/mac/verify_mac_artifacts.py artifacts/mac_harq_scheduling_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.l2.mac.runMACHARQSchedulingImpactAnalysis('ExperimentMatrix',fullfile(pwd,'tests','vectors','mac','mac_impact_experiment_matrix.csv'),'OutputDir',fullfile(pwd,'artifacts','mac_harq_scheduling_impact'),'SeedList',[11 23 47 89 131 197],'ConfidenceLevel',0.95,'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/mac/verify_mac_impact_artifacts.py artifacts/mac_harq_scheduling_impact
```

## Completion floor

- 20 findings closed for enabled profiles
- 60 mandatory MATLAB tests executed and passed
- 48 capability rows resolved correctly
- 768 impact experiments complete
- 96 acceptance rules evaluated
- 48 production CSVs verified
- 52 production PNGs verified
- zero incomplete mandatory points
- zero lineage/conservation errors
- complete repository regression passed
