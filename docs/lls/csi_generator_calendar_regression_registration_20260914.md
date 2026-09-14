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

Then run the required final-source full suite and NR guard sets. This
registration is not yet runtime-verified. The earlier three suites retain
their original frozen source and therefore do not include this addition.
The admission watcher ended without launching MATLAB before this edit;
no running suite's checkout was changed.
