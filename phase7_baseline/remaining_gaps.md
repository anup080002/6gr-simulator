# Phase 7 Remaining Gaps

Status: `Phase7Ok=false` by design until every gate in
`+sixgr/+runtime/Phase7TruthEvaluator.m` is backed by runtime or campaign
evidence.

This baseline records the current scoped implementation validation state on
branch `fix/phase7-channel-mobility-kpi-publication`. It is not a publication
readiness claim.

Open blockers:

- The requested 50 m to 500 m traces at 100 km/h need roughly 32400 slots at
  0.5 ms per slot. The configured 500-slot scenario is a short mobility
  diagnostic, not a full-route mobility run.
- The two opposing linear UE paths violate the configured 25 m minimum
  inter-UE distance unless the scenario explicitly permits a virtual crossing
  or moves one UE to a separate lane.
- Channel/RF configured-vs-applied artifacts must come from real waveform
  runtime rows. Missing channel/RF artifacts leave their gates false.
- Multi-seed and multi-drop statistical adequacy, confidence intervals,
  campaign completion, serial/parallel determinism, and long-run stability
  are blocked until actual Phase 7 campaigns are executed.
- Final reports and KPI ledgers are generated as fail-closed audit artifacts;
  they must not be cited as publication-ready while `PublicationReadinessOk`
  is false.
