# CSI-only reservation fixture authority repair

## Root cause

The retained Type-2 full suite on `3fa1399d` failed
`testCoupledTruthCSIReportSourceAuthority` at its explicit call to
`schedulePUCCHGrantRuntime`, before the codec/ledger checks could execute.
The reported identifier was `sixgr:truth:InvalidCSIResourceProvenance`.

The fixture constructed a CSI-only reservation without PRI provenance or
configured PUCCH resource fields. `buildPUCCHGrantTraceRowFromFeedback`
therefore retained `PRIValue=NaN` and empty provenance; the strict
CSI-only guard correctly rejected that row. The error text mentions a
manufactured HARQ PRI, but this failure did not demonstrate that runtime
had actually manufactured one. It demonstrated missing fixture authority.

## Change

Keep the original malformed reservation as a required rejection. Resolve
the CSI-only resource through `resolveConfiguredPRI(...,'csi')` and the
normal configured PUCCH receiver context. Populate its actual resource
identity/geometry and provenance; retain unavailable PRI. Require rejection
if a numeric HARQ PRI is inserted, even with otherwise valid CSI provenance.
Check that the resulting trace has no manufactured TBS or executed-PUCCH flag.

The production source, PRI guard, source-measurement assertions, decoded CSI
length/bit authority, queue/cache rebinding and combined HARQ/CSI assertions
are unchanged. These are declared component inputs, not a CSI-RS RF execution
or access qualification. No power, loss, noise or detector threshold changes.

## Verification boundary

Runtime verification is required on this repair revision:

```powershell
& .\scripts\run_server_testall.ps1 -Tests @('testCSIOnlyPUCCHResourceAuthority','testCoupledTruthCSIReportSourceAuthority','testSharedCSIReportClock')
& .\scripts\run_server_testall.ps1
```

Applicable NR/strict/config and result-integrity guard sets remain due for
the final integrated source. Earlier passes on `a448a240` do not cover this
fixture repair. A component pass will not qualify complete mixed-UCI RF
delivery, the detector or the integrated 12 dB scenario.
