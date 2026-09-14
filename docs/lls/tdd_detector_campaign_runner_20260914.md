# TDD detector campaign implementation checkpoint

## Completed physical development evidence

On frozen `9ef53d44b1901df47b8d98a007b19efed9357513`, the threshold-0.77
paired physical candidate test passed in 624.49 s. Both noise hypotheses
and all six signal payloads had zero observed event errors. All eight
retained MAT hashes and MAT/CSV accounting passed. MATLAB and launcher
exited 0 with unchanged clean source.

Integration-checkout evidence:
`logs/testall_20260914T163257802Z_00bbd4f1/` and its launcher ZIP;
raw received evidence: `logs/tp4e07bd89_ceeb_4525_8e10_1594772bf2cf/`.
These ignored logs remain local. One paired development episode per case
does not qualify the detector: every confidence upper bound is 0.99375,
above 0.01. The original threshold-0.42 failure and production policy are
unchanged.

## Missing capability and implementation

The prior physical runner only supported development pilots. It could not
preregister a held-out source/config/seed identity, execute bounded batches,
or audit existing evidence on resume.

- `pucch_tdd_detector_held_out.yaml`: declares 600 episodes, original 0.05
  family alpha and 0.01 event-error limit, a disjoint planned seed schedule,
  known development exclusions, and one new attempt per invocation.
- `runPUCCHDetectorEpisodes`: shared physical executor extracted from the
  existing pilot; waveform, timing, receiver and error-counting logic retained.
  `runPUCCHDetectorPilot` remains a development-only compatibility wrapper.
- `validatePUCCHDetectorCampaignPolicy`: rejects relaxed gates, fewer episodes,
  overlapping/overflowing seeds, missing pilot exclusions and unknown fields.
- `runPUCCHDetectorCampaign`: registers clean Git/MATLAB/config/resolved-scenario
  identity before RF, takes an exclusive directory lock, retains every started
  attempt, and audits seed, source, raw hashes, receiver independence, sample
  clocks, decoded payloads and error counts on resume. Changed identity or
  corrupt evidence fails loudly. Interrupted attempts are not rerun or replaced.
- `summarizePUCCHDetectorCampaign`: keeps missing episodes out of physical rows
  and includes them conservatively in an explicitly scoped accounting table.
  No automatic detector qualification or 12 dB acceptance is emitted.

The history-completeness declaration remains **false**. Known seed exclusion
does not prove complete development history or independent RF realizations.
Independent evidence review, full campaign execution and final-source
regressions remain required. This checkpoint does not finish those tasks.

## Tests actually executed

Diagnostic dirty-tree run `logs/testall_20260914T165341012Z_cd56c6cd/`:

- `testPUCCHDetectorCampaignAccounting`: PASS, 4.92 s. Declared mathematical
  inputs only: overlap, overflow, reduced/relaxed gates, missing observations,
  duplicate rows and seed mismatch. Zero errors in 600 episodes pass the
  original confidence gate; one error fails it. These fixtures are not RF rows.
- `testPUCCHDetectorPilotAccounting`: PASS, 4.65 s.
- `testPUCCHDetectorModelCandidateConfig`: PASS, 23.68 s.

The initial run `logs/testall_20260914T165145778Z_3f644f93/` failed because the
duplicate-seed fixture concatenated a YAML column vector horizontally. Its
logs are retained; the fixture was repaired by normalizing to a column.
No assertion or acceptance gate was removed. Independent retained-MAT reads
also established CSV metric roundoff below 5e-16; the new auditor permits
8 machine epsilons for serialization only, never for detector decisions.

Full `testAll`, required configuration/NR/E2E/result-integrity guards, actual
new campaign execution and restart/failure-injection checks remain pending
at this checkpoint. Static syntax checks reported no errors.

## Bounded campaign command after runtime verification

From a clean frozen checkout, with logs under that checkout:

```matlab
setup6GRSimToolkit('Verbose',false);
runPUCCHDetectorCampaign( ...
    'simulator/configs/validation/pucch_tdd_detector_held_out.yaml', ...
    fullfile(pwd,'logs','tdd_detector_held_out_v1'));
```

Each invocation starts at most one new episode and re-audits prior evidence.
Repeat with the same source, MATLAB, config and output root. Do not alter
receiver settings after seeing held-out results or treat repeated seeds as
new observations. An interrupted lock requires checking its former process
before recovering the empty lock; do not delete the attempt or its evidence.
