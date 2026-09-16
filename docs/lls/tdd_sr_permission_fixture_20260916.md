# TDD SR permission fixture correction

Candidate parent: fbf1a0f64b40d49415b59968163c698654d8dafc.
Scope: one declared-state/resource-planning fixture, not RF qualification.

The parent full suite reproduced `sixgr:truth:MissingSRProcedureState` at
`testPUCCHMultiplexingPermission.m:17`. That fixture inherits an installed SR
occasion but provided no explicit UE SR procedure state. It also independently
declared HARQ=2, CSI=4, SR=0 despite the configured negative SR indicator.

The correction initializes the existing typed procedure, advances its snapshot
to the exact occasion and independently declares HARQ=2, CSI=4, SR=1 (seven
bits). It additionally checks the transmitted negative indicator and agreement
with that receive declaration. Every original allowed/denied/malformed-policy,
per-format isolation and resource assertion is retained. No SR configuration,
production missing-state guard, power, noise, detector threshold or outcome
assertion is removed or relaxed.

Focused batch `logs/sr_permission_fixture_v1_20260916.log` terminated with exit 0:

- testPUCCHMultiplexingPermission
- testConfiguredSRWirePlanning
- testPUCCHCodeRateAllocation
- testPUCCHResourcePlanningWithoutPower

At 2026-09-16T18:41:20+05:30, engine 15712 and launcher 19092 were absent.
The edited fixture's pre/post SHA-256 matched:
`3D1B64BDE1C55C292A78CBED62CC66C5F4AF0180F55062712CA02C32A1932A43`.
Log SHA-256:
`EC8B04117D1CCA3F53A596EED92D777CC89931429A7FC6DEB1A62F80C0B701F4`.
Only the changed fixture had an explicit prelaunch byte-hash receipt; this is
not a claim of a separately captured complete transitive dependency manifest.

Required unfiltered final-source `testAll` remains due. The still-running parent
suite does not validate this fixture edit. Independent normal combined PUCCH,
detector qualification, SRS/measurement/export repairs, R2023b and integrated
5 MHz TDD / 12 dB acceptance remain open. This is not a qualified-main change.
