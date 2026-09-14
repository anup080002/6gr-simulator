# CSI-RS generator calendar regression registration

## Verified omission

At `09ca013bc4ea1910317531d39b5191495a5d1b84`,
`tests/testCSIRSGeneratorCalendar.m` existed but was absent from the explicit
test list in `tests/testAll.m`. The full-suite runner has no test-file
discovery step, and no other test called this function. Passing the planned
calendar check did not demonstrate execution of the generator check.

## Repair and scope

Register the unchanged generator test immediately after
`testCSIRSPlannedCalendar`. No existing test is removed, reordered or
excluded. This is a regression-coverage repair, not a PHY algorithm change.

The existing TDD fixture checks configured period/offset occasions,
cross-frame offsets, inactive-slot emptiness, matching MATLAB CSI-RS
indices/symbols and rejection of clock/configuration inconsistencies.
These are generator/allocation checks, not received CSI-RS, detector,
full-measurement or integrated 12 dB qualification.

## Required execution

Run the generator test together with the current-source TDD CSI clock,
publication and consumer checks:

```powershell
& .\scripts\run_server_testall.ps1 -Tests @('testSharedCSIReportClock','testCSIReportPublicationClock','testCSIMixedClockConsumer','testCSIRSPlannedCalendar','testCSIRSGeneratorCalendar')
```

Then run the required final-source full suite and NR guard sets. At the
registration commit, runtime verification was pending; the focused results
below now verify the generator and five publication/calendar checks. The
earlier three suites retain their original frozen source and therefore do
not include this addition.
The admission watcher ended without launching MATLAB before this edit;
no running suite's checkout was changed.

## Runtime verification — 14 September, 21:36 IST

Both focused batches ran on frozen source
`a4848508648240b27458d758fcafb4e32ac922b2`, MATLAB R2026a Update 4. Both
MATLAB processes and launchers exited zero, with identical before/after
HEADs and empty before/after Git status. The earlier three full suites were
not interrupted or modified.

| Test | Result and test duration |
| --- | --- |
| `testCSIRSGeneratorCalendar` | PASS, 45.34 s |
| `testCSIReportPublicationClock` | PASS, 63.38 s |
| `testCSIMixedClockConsumer` | PASS, 1.12 s |
| `testCSIRSPlannedCalendar` | PASS, 28.51 s |
| `testPeriodicCSIReportObligations` | PASS, 15.56 s |
| `testPeriodicCSIRuntimeProducer` | PASS, 23.86 s |

The publication test reached receiver clock sample 7680, retained one
publication row and queued report slot 4. The obligation test preserved
the 12 historical unavailable occasions and all 11 production available
occasions without shifting nominal report slots. The producer test retained
report slots 9/14 and source slots 3/8 despite a competing 90-slot AMC delay.
Its unexecuted/censored reports did not become decoded feedback. These are
declared receiver-input and clock/configuration tests, not CSI-RS RF or
integrated 12 dB qualification. The standalone generator test compares
actual generated CSI-RS indices/symbols; it does not execute an RF receiver.

Preserved local log directories (and corresponding `.zip` files):

- Generator: `logs/testall_20260914T155943751Z_875d1913/`.
- Five checks: `logs/testall_20260914T160238887Z_b9dfe1d4/`.

SHA-256 of terminal local evidence; raw ignored logs are not uploaded:

| Batch / file | SHA-256 |
| --- | --- |
| Generator / `matlab.log` | `a18723501fbc983562c65777841ea3051dc00d3c01c32bbb998e0684c3ba4323` |
| Generator / `summary.json` | `8f78f716d22873e6b07adeae6b6474775e39c35a546571105faadde9a37f7e2d` |
| Generator / `launcher.json` | `ce409871ee34e61b12244af96704e740b96758ead78b3d4e474352b16c586ab7` |
| Five checks / `matlab.log` | `480afe5d75bb1029f77885936c93c6c12a44c8028f48b389ef570ad3c4da6ec1` |
| Five checks / `summary.json` | `a7cf2590cbb2881981398bf066df2c864e8248c5eb1d87df91d941edfa70694b` |
| Five checks / `launcher.json` | `01b1147710c1617111d0714092d6303ff891bfff6491b39b2dad73a8f8b03cab` |

Both summaries correctly retain `baseline_12db_qualified=false` and
`scope=focused_tests`; both launchers retain `suite_pass=false`.
Current-source `testSharedCSIReportClock`, full `testAll` and the required
NR guard sets remain due. No assertion, physical operating point, detector
threshold or qualification gate was weakened for these passes.
