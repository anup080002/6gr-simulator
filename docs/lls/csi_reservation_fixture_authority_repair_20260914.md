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

## Verified component result — 14 September, 21:06 IST

The focused batch completed on frozen source
`c72cdefa3991088bb297b2d8ebca1eb291b377ce` with MATLAB R2026a Update 4.
Both MATLAB and the PowerShell launcher exited zero. Git HEAD was unchanged
and the checkout was clean before and after execution.

| Test | Runtime result |
| --- | --- |
| `testCSIOnlyPUCCHResourceAuthority` | PASS, 41.51 s |
| `testCoupledTruthCSIReportSourceAuthority` | PASS, 51.61 s |

The latter reached `PUSCH_RECEIVED_CSI_SCHEDULER_AUTHORITY_PASS` and all
subsequent source, combined HARQ/CSI, queue/cache rebinding and stale-report
assertions. This closes the malformed reservation fixture failure at its
declared component scope. It does not turn its declared measurement inputs
or codec LLRs into received CSI-RS RF evidence.

Preserved local evidence in the integration checkout:
`logs/testall_20260914T153307425Z_9bceaebd/`, with the corresponding `.zip`.
The files are ignored local logs, not uploaded raw evidence. SHA-256:

| File | SHA-256 |
| --- | --- |
| `matlab.log` | `f6d07a8a3bcf44cdfbc0a0b1e7297d2ff6429d8cb59a0f78ddf817e7c9a0d9cf` |
| `summary.json` | `61ac7776740946094f4d4d5276df2c2971bb501bfd6af1bd0a61116ca9374aed` |
| `launcher.json` | `b30e4330a643ae53e0ba4a5d9c12cec94c14fde3170006e75ea3c7b3e4d538a3` |

The summary correctly records `scope=focused_tests`, two tests, zero
failures and `baseline_12db_qualified=false`; the launcher records
`focused_passed_not_testall` and `suite_pass=false`.

`testSharedCSIReportClock` was deliberately separate from this batch because
it executes a waveform receiver. Its subsequent memory-admission check
expired without launching MATLAB. It remains due on this source, along
with final-source `testAll` and the required guards above. All three older
full suites were left running; their source was not changed.
