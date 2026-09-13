# Scheduled Type-2 DAI integration — incomplete runtime checkpoint

Development base: `8fba90cc`, branch `work/type2-runtime-20260913` in
`%TEMP%/sixgr_type2_runtime_20260913`. A separate worktree preserves the
unchanged source of the original main and receiver-revision validation jobs.
This is not full Type-2, baseline, detector or conformance qualification.

## Scheduled counter and control boundary

Inspection found fixed `DAI=1` in RR/PF candidates and a default/clamp in
`SchedulerBase.buildDCIBitfield`. The connected runtime must finalize a
chronological counter rather than publish that fixed candidate field.
For the installed ordinary two-bit, scalar-TB, single-cell profile,
the on-wire sequence is 0,1,2,3,0,... and its semantic counter values are
1,2,3,4,1,...; see [TS 38.213 V18.8.0, clause 9.1.3.1 and Table 9.1.3-1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

`nextScheduledType2DAI` returns a candidate ledger without mutating its input.
It groups scheduled assignments by UE/cell/carrier/configuration epoch and
feedback slot, checks chronology, rejects changed assignment identities or
unsupported multiple assignments in one monitoring pair, and makes repeated
packing idempotent. Expired feedback groups are retired for long-run storage.
Receiver status, ACK/NACK and payload fields are not accepted as inputs.

`prepareScheduledDLDAI` validates the existing connected policy and real
frozen scalar-TB allocation, changes only the packed DAI and corresponding
DCI metadata, and retains the unchanged PHY allocation/timing. It normalizes
the scheduler's `DCI_1_1` token through the existing format normalizer.

The coupled grant-control path calls this finalizer after control eligibility
checks. The shared path publishes its candidate ledger only after successful
PDCCH enqueue; the nonshared path publishes only after actual allocated control
execution. Failed UE decoding does not undo transmitted control assignments.
Queued control is still **not** an assertion of actual transmission or UE
reception; actual physical execution and receiver receipts remain separate.

## Focused validation

The initial test failed at empty MATLAB-struct-array initialization. That was
fixed without changing assertions. A second run rejected the scheduler's
prefixed DCI format; a diagnostic run confirmed valid control/feedback timing
and `DCI_1_1`. The implementation now uses the existing normalizer.

The final focused batch exited 0:

```matlab
setup6GRSimToolkit('Verbose',false);
testScheduledType2DAI;
testType2HARQACKLayout;
testType2HARQRuntimePlan;
testSchedulerGrantConsistency;
```

The new test covers eight scheduled ordinals, wraparound, separate UE/feedback
contexts, discarded candidates, repeated packing, invalid identities,
chronology, expiry, actual contextual DCI packing, unrelated-field invariance,
and receiver/scoring input independence. Existing layout tests retain their
256 DAI combinations and 24 vector regressions. These are procedure/packing
checks, not proof that the main-loop queue hook completed a waveform campaign.

Logs: `%TEMP%/sixgr_scheduled_type2_dai_20260913.log` and suffixes `_02`, `_03`,
`_04`; only `_04` is the passing complete focused batch.

## Remaining runtime work

- Retain actual `rx.DecodedDCI` counter/monitoring information through the
  connected receive callback. The receiver already supplies parsed bits to
  `localDecodeObservedPDCCHGrantDCI`; the current grant-field hash omits DAI.
- Replace the UE row-append feedback path with the typed received-event
  codebook and use its source-index map for received ACK/NACK associations.
- Integrate UL first-DAI/UCI-on-PUSCH policy, gNB expected-length resolution and
  independently armed missed-DCI receive windows. No such coverage is claimed.
- Validate actual control enqueue/receive behavior on the finalizer path,
  including multiple same-feedback assignments and missed control reception.
- Run the required full suite, configuration/LLS/export/grant tests and both
  E2E guards on this runtime revision. Existing jobs on older revisions do not
  qualify this change. No assertions, quarantine or false-ACK limits were weakened.

The NR-validation, result-integrity and config-driven skills kept the change
bound to the installed policy, real allocation, explicit scheduling provenance
and existing qualification gates. The broader impairment-enabled 6G/NR and
complete CSV/PNG objectives remain open.
