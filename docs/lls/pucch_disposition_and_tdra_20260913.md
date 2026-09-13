# Receiver disposition, normalized power and special-slot TDRA

Follow-up to [the power-reference checkpoint](pucch_power_and_remaining_gates_20260913.md).
This is focused component/budget evidence, not a qualified full 58-slot run.

Follow-up: [main scheduler/TRS special-slot repair](special_slot_scheduler_trs_20260913.md)
records the subsequent real scheduler-grant and received-control allocation
checks. The remaining gates below are retained as this earlier checkpoint's scope.

## Receiver disposition and power export

The physical PUCCH receiver and `resolveReceivedHARQBit` retained the DTX
decision, but `updatePUCCHGrantTraceAfterObservation` never assigned it to
the logical grant's `DTXFlag`. The updater now copies the explicit receiver
decision through `pucchReceiverDisposition`, including a scoped reason.
Missing or nonbinary decisions fail rather than becoming false non-DTX.
Logical HARQ DTX caused by a missing decoded bit remains distinct from a
physical receiver DTX decision; the helper does not infer one from the other.

The projection-only regression checks actual retained `_02` DTX and `_03`
non-DTX decisions, plus missing-bit/invalid-input negatives. Its derived CSV
is explicitly diagnostic replay of existing decisions, not new PHY output.
The old primary captures and their incorrect grant rows remain immutable.

Normalized-Es/N0 PUCCH trials no longer label the target-derived 103 dB
power-control margin as physical headroom. They export:

- `PUCCHPowerHeadroomApplicable=false`;
- `PUCCHPowerHeadroom_dB=NaN`, with an explicit normalized-domain reason;
- `PUCCHPowerControlTargetHeadroom_dB=103` as the retained diagnostic target.

In physical-power mode the original calculated margin remains applicable,
but is explicitly not a decoded MAC PHR. No RF/noise/receiver threshold was
changed by this export repair.

`pucch_disposition_and_power_tests_01.txt` reached terminal **exit 0** for
the projection negatives, original-IFFT/physical-power checks, and an actual
baseline-configuration shared SRS/PUCCH capture (`pucch_baseline_signal_04`).
Both logical grants received ACK/NACK correctly, had non-DTX flags matching
their physical occasion, and retained power fields passed CSV roundtrip
checks. The detection metric remained exactly 0.420294752122787 at threshold
0.42. Marginal detection robustness and the prior false-ACK failure remain
open; neither is fixed by exporting a better disposition.

This shared component executed before the later TDRA-budget edit below.
Its manually declared DL feedback source is not evidence of special-slot
PDCCH/PDSCH scheduling or a full acquired-access timing path.

## Reproduced main-budget cause of empty special slots

The current resolved baseline YAML already has `[index=1,start=2,length=8,K0=0]`.
The main `defaultSlotBudget` nevertheless only tried the legacy configured
allocation `[2,12]`, then rejected the ten-symbol special-slot DL partition.

`baseline_dl_tdra_budget_tests_01.txt` reached terminal **exit 1** after
preserving all eight DL-capable budgets in one configured ten-slot frame.
At zero-based slots **3 and 8**, an eligible YAML TDRA existed but the
producer returned **zero PRBs**, length 12 and the typed unavailable reason.
Full DL slots returned 25 PRBs. This directly proves a runtime budget-selection
defect, not merely a missing GUI rendering or slow MATLAB computation.

The repair consults configured TDRA rows when the preferred allocation does
not fit. A candidate must fit the direction's actual symbol partition and
match the actual control-to-data slot offset. It selects the first eligible
row in YAML order and preserves its index/source/offset in budget evidence.
No row is invented; symbols are not clipped; unresolved flexible symbols
are not assigned to data; K0/K2 is not rewritten to force a fit. If no row
fits, the original typed unavailability remains. Full fitting allocations
retain their existing behavior. The existing exact PHY/DCI/HARQ gates remain.

Selection by YAML order is an explicit simulator scheduler policy, not a
3GPP-mandated optimization algorithm. The standards requirement used here
is that the DCI time-domain field identifies an applicable allocation-table
row and its associated timing/symbol semantics; see
[TS 38.214, section 5.1.2.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/17.10.00_60/ts_138214v171000p.pdf).

The first repaired test attempt (`baseline_dl_tdra_budget_tests_02.txt`)
failed on an incorrect test-only `cfg.phy.rnti` lookup before completing its
DCI-context checks. The fixture now uses the scenario's configured
`users.rnti_start` and `users.n_users`. This failure was not evidence that
the TDRA repair passed or failed. A separately named rerun preserves that
distinction.

The corrected rerun `baseline_dl_tdra_budget_tests_03.txt` reached terminal
**exit 0**. Both special slots now retain 25 PRBs, choose `[start=2,length=8]`
and bind DCI TDRA index **1**. All six full-DL slots retain length 12 and
index **0**. Wrong-offset, zero-DL-region and conflicting-alias negatives
pass. `testPDSCHTDRAFromDecodedDCI` and
`testTDDCausalWiringShortYAMLAuthority` also pass in the same process.

`tdra_scheduler_grant_consistency_01.txt` reached terminal **exit 0**.
It exercises the existing generic scheduler grant/TBS/DCI/link-adaptation
lineage guards; it is not actual baseline special-slot PHY execution.

Commands (use new output/log names to preserve previous captures):

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); testPUCCHReceiverDisposition('docs/lls/evidence_20260913/pucch_disposition_projection_NEW'); testPUCCHNormalizedTransmitReference; testPUCCHBaselineSignalClock('docs/lls/evidence_20260913/pucch_baseline_signal_NEW')" -logfile docs/lls/evidence_20260913/pucch_disposition_and_power_tests_NEW.txt
matlab -batch "setup6GRSimToolkit('Verbose',false); testBaselineDLTDRABudget('docs/lls/evidence_20260913/baseline_dl_tdra_budget_NEW'); testPDSCHTDRAFromDecodedDCI; testTDDCausalWiringShortYAMLAuthority" -logfile docs/lls/evidence_20260913/baseline_dl_tdra_budget_tests_NEW.txt
matlab -batch "setup6GRSimToolkit('Verbose',false); testSchedulerGrantConsistency" -logfile docs/lls/evidence_20260913/tdra_scheduler_grant_consistency_NEW.txt
```

## Remaining qualification boundary

- Actual special-slot scheduler dispatch through received PDCCH, PDSCH
  decoding and legal K1/PUCCH remains a separate required gate.
- The helper checks DTX projection against a retained failed capture; a
  fresh shared main-path DTX occasion still needs integration coverage.
- Format-0 HARQ/SR semantics, detector ROC, CSI-RS nonoccasion reservation,
  missed-DCI/shared-retransmission handling, TA perturbations, complete
  measurement/beam closure and terminal CSV/PNG publication remain open.
- The separate patch-tool failures on PUCCHReceiver and allocREsPDSCH are
  not repaired by these changes. No alternate file writer was used.
- No full 58-slot run, testAll, E2E campaign or remote push is authorized by
  these component passes. The focused-test hold and later 400 MHz/Keysight
  capability qualification remain unchanged.
