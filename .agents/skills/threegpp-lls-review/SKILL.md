---
name: threegpp-lls-review
description: Audit SixGR scenarios and implementation against versioned 3GPP NR requirements and 6G study assumptions, tracing antennas, PHY, L2/L3, YAML and measurement exports. Use for standards-gap, procedure-flow or scenario-readiness reviews; not as a certification claim.
---

# SixGR 3GPP / LLS implementation reviewer

Review the requested scope in the existing main codebase. This is a source-
backed engineering agent, not an embedded copy of every standard or an
independent conformance laboratory. Configuration presence is not execution.

## Select the relevant references

- For any standards comparison, read [standards.csv](references/standards.csv).
  It is a discovery index. Open the applicable official document, pin its
  version and inspect the actual clause/table before a normative finding.
- For implementation, parameters, measurements or procedure review, read
  [execution-review.md](references/execution-review.md). Follow its route into
  current source; listed files are starting points, not evidence of completeness.
- For RAN1 Chair-note coverage, read
  [chair-note-coverage.md](references/chair-note-coverage.md) and the linked
  repository output-requirements CSV. Review relevant original paragraphs,
  tables, formulas and tracked changes; do not treat a contribution's title
  or a historical coverage label as an agreement or current passing result.

## Establish evidence and scope

Record scenario/input paths, resolved configuration, run identity, source
revision plus dirty changes, MATLAB/toolbox versions, seeds and output root.
Preserve logs/results and unrelated edits. Separate LLS waveform execution,
calibrated SLS abstraction and modeled/analytical evidence. Inspect the current
process and final receipt before calling a run active, failed or completed.
Inspect running jobs before any test execution; do not edit a running job's
source and then call its result a frozen-source qualification.

Label requirements as one of:

- `NR_NORMATIVE`: versioned TS clause applicable to this configured feature.
- `3GPP_MODEL_OR_METHOD`: TR or evaluation method, with declared assumptions.
- `6G_STUDY_AGREEMENT`: identified meeting/document/paragraph, not final NR/6G TS.
- `STUDY_CANDIDATE`: proposal/FFS alternative requiring a comparator.
- `MATLAB_BEHAVIOR`: documented toolbox algorithm/API, not a 3GPP mandate.
- `IMPLEMENTATION_POLICY`: scheduler, estimator, OLLA, threshold or engineering choice.

Never infer a normative 6G feature from the presence of an NR implementation.
Check the current 3GPP registry when release/status matters. Do not silently
change the run's pinned release to a newer one during a review.

## Trace each requested feature

Follow the whole chain, identifying each real owner:

`YAML key -> inheritance/schema -> buildInternalConfig -> runtime consumer ->
transmitted signal/control -> receiver decision -> scheduler/protocol state ->
raw trial/CSV -> plotted CSV/PNG -> WebGUI -> final acceptance`.

For each parameter record unit, index origin, clock/power/reference plane,
configured/resolved/applied/measured value and evidence location. Inspect all
enabled configuration domains using the schema/catalog, not a handpicked few.
When there is no consumer, say `configured_not_wired`; when the consumer exists
but no execution is retained, say `wired_not_verified`.

Locate the reason for required missing values: disabled source, unexecuted
occasion, insufficient observations, missing receiver estimator, lost metadata,
wrong join key, serialization failure or UI omission. Implementing a producer
is different from changing its label. Do not invent historical measurements.
Use `not_applicable` only with a feature/format/reference-plane reason.

## Findings and closure

Return a table with Priority, Feature, Requirement/source/version/clause,
Configured/applied behavior, RCA, Production file/function, Evidence,
Required repair, Verification and Status. Separate observed defects from open
hypotheses and valid policy choices. Order causality/PHY defects before
reporting, then statistical qualification. For fixes requested by the user,
repair production owners and add a reproducer; do not weaken guards or merely
edit fixtures to conceal production failures.

Use scoped statuses: `not_reviewed`, `confirmed_defect`, `missing_capability`,
`configured_not_wired`, `wired_not_verified`, `focused_pass`, `integrated_pass`,
`statistically_qualified`, `not_applicable`. Every pass must name its test/run
and applicable parameter domain. A negative physical outcome is not itself a
software defect. A short run cannot qualify BLER/detector tails or network CDFs.

Honor the user's current test scope and applicable repository guidance;
resolve conflicts before full-suite execution. Never auto-run testAll or a
large campaign merely because this skill was invoked. Do not alter thresholds,
noise power, rank, traffic or scheduling gates merely to get a PASS.

When code is changed, apply the repository's relevant config-driven LLS,
NR-validation and result-integrity skills; use matlab-performance for hot paths.
This reviewer supplements those safeguards rather than overriding them.
