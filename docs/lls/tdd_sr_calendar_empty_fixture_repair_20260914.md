# TDD SR-calendar fixture repair: empty-vector shape

## Observed failure

The full suite on `e63418058cb3b63264407f8d6c27b96a049b5417` failed
`testConfiguredSRCalendar` at its line 73, comparing the installed
`additional_capability_slot_periods` with the independent expected list.
The original failure and saved configuration remain in the main checkout:

- `logs/testall_20260914T133904354Z_63765735/matlab.log`
- `logs/tdd_configured_sr_calendar/tp2a35fa9b_19f7_4e21_8102_6300dcdd6f28/meta/installed_sr_period_catalog.json`

The saved catalog has the expected lists at every authored SCS:
empty, 5, empty, [5, 10], empty, empty. The failing expression reshapes
the observed empty vector with `(:).'` into 1-by-0, but compares it with
the unreshaped 0-by-0 literal `[]`. MATLAB `isequal` checks dimensions.
This is a fixture representation mismatch, not evidence of a wrong SR period.

## Repair and preserved checks

Normalize both observed and expected additional-capability lists with
`double(...(:).')` before the existing exact equality check. Add an error
identifier and SCS/expected/observed diagnostics. The independent expected
values, order, allowed-slot-period tests, blocked-slot checks, malformed
configuration rejections, overlap checks and receiver-schema checks remain.

No catalog values, calendar algorithm, PHY behavior, detector threshold or
statistical gate changed. No FDD repair is included. The separate operator
master omission of `scheduling_request_resources` is NOT repaired here.

## Verification boundary

This isolated child of detector candidate `104e13f1` does not modify the
published detector branch or the three running suite checkouts. The original
failure is not replaced by a passing receipt. MATLAB runtime validation is
pending; static checking is not a substitute for executing the fixture.

Required next checks on a clean committed revision:

```powershell
& .\scripts\run_server_testall.ps1 -Tests @('testConfiguredSRCalendar')
& .\scripts\run_server_testall.ps1
```

The applicable NR/config skill regression sets remain required before final
consolidation. A repaired fixture pass would establish only the configured
SR calendar/overlap/schema checks, not MAC SR lifecycle, RF delivery, full
shared-HARQ closure or integrated 12 dB acceptance.
