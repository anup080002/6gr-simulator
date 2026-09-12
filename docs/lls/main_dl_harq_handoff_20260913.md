# Main connected DL HARQ handoff: unqualified checkpoint

The main handoff is implemented but **not yet passing**. Two focused MATLAB
processes terminated with exit 1. This is a local preservation checkpoint,
not a release, a successful 12 dB run or a reason to push unqualified repairs.
The existing final 58-slot hold remains. No baseline, `testAll` or E2E was run.

## Implementation movement

`runWaveformLinkBundle.localCompleteSharedDataPlan` now retains a value-semantic
`ReceivedDLHARQState` per UE for connected DL and supplies it in the received
context. A completed actual receive attempt must return that entity before
the coordinator can retain it. Non-connected procedures remain separate.

For connected shared reception, `runDLPDSCHThroughput` now calls the UE-owned
entity with the received DCI capsule, received samples, measured physical
observation and timing search window. The old transmitter coding-argument
list is not supplied to that call. Missing UE identity/state fails rather
than falling back to transmitter plans. The main coordinator and the isolated
DL-feedback donor supply the entity.

The connected path no longer calls the wrapper's second soft-combining or
combined-decoding operation. `receivedDLHARQCombiningEvidence` projects the
canonical decoder's actual current/combined LLRs, retained buffer, counts and
combining diagnostics. It rejects authority/domain mismatches. Existing
non-connected/calibration behavior remains separate.

Final trial exports carry received-assignment digest, decoder CRC input domain,
the current-only CRC-measurement flag and receiver-state source. A combined
decoder result is labeled as including UE-owned prior soft state; it is not
an independent standalone decode. Soft evidence is projected after early
receiver dispositions too, so scheduler-held prior LLRs cannot be returned as
the UE's new result through an early branch. These additions still require
successful main-path execution and downstream feedback-table propagation.

Already-decoded repeated assignments remain explicit failures at the wrapper
boundary: they need a protocol-only ACK disposition, not a fresh CRC/trial.
Failed DCI retains the existing DTX-disposition guard. Neither path has been
replaced by a fabricated PHY row. Their integration remains mandatory.

## Verification and root causes

### Connected donor process: FAIL

`evidence_20260913/main_dl_received_handoff_01.txt` records
`testReceivedDLFeedbackAuthority` stopping at
`sixgr:pdsch:ReceivedTCIMappingUnavailable` in
`PDSCHAssignmentFactory.fromReceivedConnectedDCI`.

The source YAML `lls_received_ul_shared_queue_fixture.yaml` explicitly sets
`control.connected_dci.tci_present: false` and disables the Type-A QCL transfer
fixture because its isolated DL donors have no preceding TRS. The strict
received-DL factory, however, unconditionally requires `received.TCIPresent`
and an active QCL mapping. The integration validator also requires an
activated TCI state for every dedicated PDSCH. The old donor passed only
because it used the legacy receiver route, not because this combination was
qualified through the UE-owned received-assignment factory.

This is an unsupported receiver configuration exposed by the handoff, not
permission to turn on an invented TCI/reference or silently return to legacy
decoding. The prior UL component results at `f299bcf4` remain historical
passes; their donor is **not currently qualified on the new handoff**.

TS 38.214 V18.8.0 clause 5.1.5 supports scheduling without a TCI field. For
the applicable scheduling-offset case, the PDSCH uses the scheduling CORESET's
TCI/QCL assumption; short-offset and other configured cases have additional
rules. Absent TCI does not mean that an arbitrary active state or TRS can be
manufactured. See [the specification, pages 50–51](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).

The next repair must model the actual installed/received CORESET QCL
association, its cell/BWP/epoch identity and applicable timing rule, expose
configurable policy in YAML, and carry that reference through factory,
integration validation and receiver reporting. Explicit-TCI behavior must
remain intact. Missing source evidence must still fail; the fixture needs
an actual source or explicitly qualified installed association, not a made-up
measurement. No YAML or QCL assertion was weakened in this checkpoint.

### Combining/report replay process: FAIL overall, checks passed before failure

`evidence_20260913/received_dl_combining_projection_01.txt` records:

- The new projection test passed saved attempts 1, 2 and 4. Current and
  combined mother-code buffers each contain 5,600 values; only attempt 2
  has 5,600 prior values. Exact canonical buffers/diagnostics are preserved.
  Six tampered-domain/authority negative checks also passed.
- `testReceivedDLHARQReplay` passed all four actual capture replays and its
  seven guards, including NACK, combined ACK, repeated ACK without duplicate
  delivery, and NDI reset. This tests the existing UE endpoint, not the main
  scheduler callback.
- `testReceivedDLReportEvidence` passed its three report comparisons, then
  called `testReceivedDLDisabledCSI` and failed its unchanged ACK/delivery
  equality assertion. Disabling CSI-RS removes the historical non-occasion
  allocation holes and therefore changes the archived waveform mapping.

The allocation defect and prior file-write restriction remain as documented
in the [received-report checkpoint](dl_received_report_boundary_20260913.md).
The allocator was not edited or retried through another write mechanism.
Old captures were not overwritten. Do not count the failed combined process
as a green regression suite or remove its nested failing check.

## Next execution gate

1. Resolve the non-occasion allocator repair and generate new, separately named
   captures with corrected mapping; keep the existing failing regression.
2. Implement and test the absent-TCI CORESET-QCL path above, then rerun the
   donor and actual SRS/PUSCH/UCI and PUCCH regressions.
3. Execute a bounded main-coordinator connected-DL test proving retained
   per-UE state, one decode/combination, QCL timing and actual feedback delivery.
4. Complete failed-control DTX, repeated ACK, dynamic DAI, special-slot TDRA
   and independent timing/TA perturbation checks. Reconcile all measurement
   domains and publication contracts before the final 58-slot validation.

The broader work remains in the issue ledger: complete CSI/SS/data/UL power
and SINR reconciliation, all-channel artifacts, repeated rendering, waveform
and instrument playback verification, then single-carrier 400 MHz/7 GHz,
eight layers/two codewords and extended-QAM qualification. None is certified
by this handoff patch or its replay checks.
