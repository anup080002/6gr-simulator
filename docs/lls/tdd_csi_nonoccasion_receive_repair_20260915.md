# TDD CSI non-occasion receiver repair — 15 September 2026

Status: focused component checks passed; integrated 5 MHz / configured 12 dB
acceptance remains incomplete. This is not detector or 3GPP qualification.

## Cause and change

The retained `tdd_5mhz_12db_2c45b257_20260915` execution stopped at coordinator
slot 35 with `UnresolvedCombinedPUCCHReceiveHypothesis`. The receiver builder
rejected every HARQ-only opportunity whenever CSI reporting was enabled,
without checking the installed periodic calendar. Coordinator slot and the
requested receive target must not be conflated: integration must verify the
actual target on rerun.

`configuredCSIReportCalendar` now obtains nominal receiver obligations from
installed identity/configuration only. `buildScheduledHARQTransportReception`
rejects actual CSI resource overlaps, not global enablement. The normal
`CoupledTruthRuntime` HARQ-only caller can use independent reception on a
non-report occasion. Nonperiodic activation remains explicitly unsupported.
No UE pending report, payload presence, or serialized bit count defines the
receiver calendar. Actual CSI and SR overlaps retain fail-closed guards.

## Executed checks

MATLAB R2026a Update 4, focused dirty-tree diagnostic on parent `4a01e94c`:

| Test | Result | Duration |
| --- | --- | --- |
| testPeriodicCSIReportObligations | PASS | 22.83 s |
| testSharedPUCCHCSIEnabledNonoccasion | PASS | 79.15 s |
| testSharedPUCCHReceiveOnlyClock | PASS | 50.63 s |

Receipt: `logs/testall_20260915T150430246Z_400b500c/summary.json`.
The CSI-enabled fixture retains reporting but configures a non-report target;
its physical receive-only check produced two DTX decisions without a PUCCH
producer. Original real-overlap rejection, malformed configuration rejection,
and state-poisoning independence assertions remain. This fixture has no SR
inventory and does not qualify combined CSI/HARQ/SR operation.

## Next confirmed boundaries, not fixed by this patch

- The production TDD baseline lists SR resource 0 but lacks its installed
  scheduling-request identity/period/offset/priority calendar. The existing
  configured-SR fixture already demonstrates the missing-calendar rejection.
- Real combined CSI/HARQ/SR runtime receiver ownership is unfinished; the
  existing typed combined component is not end-to-end qualification.
- Scheduled PUSCH selection still rejects combined CSI reception here.
- Full required guards, final-source testAll, detector statistical acceptance,
  all-measurement/export closure, and the complete integrated 12 dB run remain.

No production noise, transmit power, detection threshold, acceptance assertion,
or enabled feature was changed by this repair. Preserve the failed integrated
run and its raw artifacts; do not report these three checks as a scenario pass.
