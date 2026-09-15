# 5 MHz / configured 12 dB TDD: installed SR calendar

Status: configuration repair and four focused tests passed. Not integrated
12 dB acceptance, detector qualification, or complete SR MAC/PHY support.

## Root cause and repaired files

The continuous-IQ 58-slot baseline inherited `sr_resource_ids: 0` but no
`scheduling_request_resources`. Resource inventory cannot define SR identity,
period, offset, or priority; the independent receiver correctly rejected it
with `sixgr:truth:MissingInstalledSRCalendar`.

`lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml` now explicitly
installs the already component-tested resource-configuration ID 1, scheduling
request ID 0, PUCCH resource 0, period 5 slots, offset 3, priority 0, with no
additional-periodicity capability required. This produces one-based slots
4,9,...,54 on the existing 15 kHz TDD calendar, using UL symbols 12 and 13.
The choice is a scenario configuration, not a universal 3GPP default.

The allowed five-slot period and offset range are defined in
[TS 38.331 V18.8.0, SchedulingRequestResourceConfig](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.08.00_60/ts_138331v180800p.pdf).
This configuration does not assert that any SR was transmitted or decoded.

Three existing HARQ-only component YAMLs that explicitly remove SR resource
inventory now also explicitly remove the inherited SR calendar. Their scope
is unchanged; the production baseline does not disable SR or CSI.

`testConfiguredSRCalendar.m` now checks the actual baseline against the
independently tested fixture. Its missing-calendar negative case explicitly
removes the field; all malformed configuration, unavailable-symbol, overlap,
receiver identity, and no-pending-UE-state assertions remain.

## Executed evidence

MATLAB R2026a Update 4; dirty-tree diagnostic on parent `4ff8091d`:

| Test | Result | Seconds |
| --- | --- | --- |
| testConfiguredSRCalendar | PASS | 29.78 |
| testSharedPUCCHCSIEnabledNonoccasion | PASS | 80.02 |
| testSharedPUCCHReceiveOnlyClock | PASS | 50.33 |
| testPeriodicCSIReportObligations | PASS | 7.66 |

Receipt: `logs/testall_20260915T151339621Z_3e52f252/summary.json`.
The two actual shared receive-only waveform cases produced DTX,DTX with no
PUCCH producer. These do not establish signal-present ACK detection rates.
The calendar test exports 11 legal configured opportunities and retains 12
blocked nominal opportunities in its deliberately invalid timing case.

## Remaining implementation and acceptance boundaries

1. `PUCCHConfigBuilder.localPlan` currently constructs empty SR reports.
   Configuring SR occasions does not implement positive/negative SR generation
   from a UE-owned MAC lifecycle. Do not insert zero SR bits to claim closure.
2. Normal combined PUCCH paths still derive receiver layout from a transmitted
   report. Build receiver obligations from gNB schedule and installed CSI/SR
   calendars, including CSI absence/priority/multiplex policy; never use UE
   pending-payload presence to select the receiver schema.
3. `buildScheduledHARQTransportReception` retains true CSI/SR overlap guards
   and the combined scheduled-PUSCH guard. No guard was deleted by this patch.
4. Full testAll and required config/LLS/strict/export/E2E guards, retained
   detector false-ACK and missed-ACK acceptance, all-measurement and artifact
   closure, and final integrated scenario acceptance remain mandatory.

The next 12 dB execution is diagnostic evidence on a frozen revision, not
permission to declare these remaining capabilities qualified or merge main.
No transmit power, noise, thresholds, TDD partition, CSI period, or simulation
duration was altered to improve the outcome. FDD and 400 MHz are deferred.
