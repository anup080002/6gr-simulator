# TDD CSI waveform verification and authorized suite stop

## TDD waveform result — 14 September, 21:56 IST

`testSharedCSIReportClock` passed in 69.16 seconds on frozen source
`5efccc81a521749c77c97615e600f9e517c6d3b3`, MATLAB R2026a Update 4.
MATLAB and the launcher exited zero; Git HEAD and the clean worktree were
unchanged across the run.

The retained markers show:

- TDD, no HARQ in this selected case, seven decoded CSI bits, due slot 4,
  delivered slot 5.
- Actual shared PUCCH receiver ledger, scoped power-plane assertions and
  CSV roundtrip passed.

The test executes shared PUCCH IQ/CDL/RF/noise and CSI decoding. Its CSI
measurement inputs and initial timing context are declared component inputs,
not a simulated access procedure or received CSI-RS measurement campaign.
It does not qualify the Format-0 detector, combined HARQ/CSI/SR operation,
the full suite, all measurements or the integrated 12 dB operating point.
The test's operating point and assertions were unchanged.

Local evidence: `logs/testall_20260914T162343112Z_112f93ce/` and its `.zip`
in the integration checkout. These ignored raw logs remain local.

| File | SHA-256 |
| --- | --- |
| `matlab.log` | `8ebca027a8cda88fa80073046610fd63e9a817e36be8ab1075a2756e5476b360` |
| `summary.json` | `93d46521da75cce17589be2bcc5759c6c25f504dc93705b36b2e05c7e7021a34` |
| `launcher.json` | `ba58d1022d363bacfd70d3735d19f88ff72c9aac2f5160737e720c3477cfd281` |

The summary retains `scope=focused_tests`, `baseline_12db_qualified=false`;
the launcher retains `suite_pass=false`. Six preceding CSI calendar and
publication checks passed on `a4848508`; these are separate exact-revision
runs, not a final full-suite pass.

## Authorized stop of two superseded suites

The user explicitly approved: "Stop the two superseded suites; preserve
their logs". At approximately 21:52:06 IST, only those two verified MATLAB
engines, their eight directly owned workers and two owned MATLAB windows
were terminated. Latest suite engine PID 3424 and its checkout were left
running and unchanged. No source, logs, result directories or jobs were
deleted. Written logs were preserved; no recovery of unflushed in-memory
execution state is claimed.

| Stopped run | Frozen revision | Completed pass/fail | Interrupted test (outcome unknown) |
| --- | --- | --- | --- |
| `testall_20260914T111309659Z_540a6fee` in Type-2 checkout | `3fa1399d` | 326 / 4 | `testPRACHRuntimeULDirectionAntennaContract` |
| `testall_20260914T121937365Z_2b988f23` in PUCCH checkout | `c5b21306` | 304 / 4 | `test6GLLSMultiUserBeamforming` |

Each original launcher recorded `failed_or_incomplete`, MATLAB exit -1,
launcher exit 1, unchanged HEAD and clean before/after status. Original
`summary.json` files were preserved as their stale in-process `running`
snapshots; added `user_stop_receipt.json` files explicitly override any
interpretation that these processes remain live or completed successfully.
Interrupted tests are not counted as passes or completed failures.

Each log folder was additionally archived to a sibling
`<run-name>_user_stopped.zip`. Both ZIPs were opened and checked for
`matlab.log`, `summary.json`, `launcher.json` and `user_stop_receipt.json`.
The original launcher ZIPs were also retained. Stop receipts and raw log
bundles remain local in their original checkouts, not uploaded evidence.

Full final-source `testAll`, applicable guards, independent detector
qualification, complete integrated measurement/export verification and
accepted 12 dB execution remain required before qualified-main promotion.
