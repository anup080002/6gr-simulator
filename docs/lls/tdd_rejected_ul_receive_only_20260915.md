# TDD rejected-UL-DCI receive-only connection

This is an implementation checkpoint, not full shared-feedback closure or
12 dB acceptance. FDD feature work remains deferred. Production 12 dB,
detector thresholds, channel/noise/power policy and the SINR sweep are unchanged.

## Root causes and changes

1. `runWaveformLinkBundle/localCompleteSharedScheduledPDCCH` previously
   cancelled an unexecuted UL allocation and returned immediately after
   rejected UL DCI. No scheduled gNB PUSCH capture existed. The TDD branch now
   calls `queueSharedPUSCHAfterRejectedControl`; the event dispatcher calls
   `completeSharedPUSCHAfterRejectedControl` when that capture completes.
2. `validateSharedRejectedULControl` requires the exact uniquely retained
   rejection, attempted non-crashed decoder result, completed same-clock
   observation and configured UL grant identity. A rejected command cannot
   install a UE allocation. Invalid/missing evidence is an error, not DTX.
3. The gNB receive window comes from canonical scheduled-slot boundaries
   plus the YAML-resolved timing uncertainty. It uses no UE timing advance,
   prepared UE waveform, transmitted TB, power injection or generated IQ.
   Late registration, duplicate registration and duplicate completion reject.
4. The new negative physical test exposed a separate known-candidate PDCCH
   timing bug: unrestricted correlation selected an offset beyond the actual
   complete-symbol capture, causing `IncompleteReceivedControlSymbols`.
   `completePDCCHReception` now passes the real complete-symbol offset interval
   to `PDCCH_Rx`. The receiver selects the correlation maximum within that
   interval, rather than clipping an unrestricted peak or padding reception.
   Already aligned connected/blind reception is not shifted a second time.
   The correlation-magnitude interface is documented by
   [MathWorks nrTimingEstimate](https://www.mathworks.com/help/5g/ref/nrtimingestimate.html).
5. Successful receive-only completion retains actual raw receiver evidence
   and `SharedRejectedULReceiveAuditTable`. The normal writer exports
   `control/csv/rejected_ul_receive_only_audit.csv`. It does not manufacture
   primary transmitted-TB trials, BER/BLER denominators, grant TBS, throughput,
   UE producers or HARQ TX/ACK/NACK rows. No PNG is inferred from one audit row.

## Explicit unfinished combinations

`completeSharedPUSCHAfterRejectedControl` currently completes new allocations
with independently empty HARQ and CSI obligations. It fails explicitly with:

- `RejectedULUCITransportOwnershipRequired` for due HARQ/CSI. The normal
  transmitted-PUSCH bookkeeping requires actual producer reservation fields;
  those fields cannot be invented when UL DCI was missed. Independent
  PUCCH/PUSCH receive-hypothesis ownership and exactly-once common disposition
  must be integrated before this guard can be replaced.
- `RejectedULReceiverHARQCombiningRequired` for retransmission. The existing
  receive-only adapter is current-observation-only, not combined HARQ.

These guards expose unfinished cases. They are not a claim that those cases
are supported, nor a replacement for implementing them. SR/CSI producers
must not be suppressed using gNB-only knowledge of a scheduled UL grant.

## Executed evidence

MATLAB R2026a Update 4; working-tree candidates based on `22303c79`, with
`AllowDirty` explicitly recorded. These are not clean-source full-suite runs.

| Local integration `logs/` directory | Result |
| --- | --- |
| `testall_20260914T190832825Z_4072f82b` | Preflight PASS; physical test FAIL at `IncompleteReceivedControlSymbols`; MATLAB/launcher 1 |
| `testall_20260914T191421734Z_25c14c85` | Preflight PASS 0.26 s; physical rejection-to-receive-only PASS 126.95 s; existing signal-present PDCCH PASS 28.43 s; MATLAB/launcher 0 |

Both folders and original ZIPs remain local. No failure was erased or
converted to a pass. The repaired physical test also asserts that the original
unrestricted timing peak remains outside the legal interval. Raw evidence:

- Legal control search offsets: 0 through 92 samples.
- Original unrestricted peak: 331; selected legal peak: 77.
- Independent Python/HDF5/NumPy argmax of the saved correlation: 77.
- Actual control rejection, one gNB-only PUSCH decode, no UE PUSCH TX and no
  HARQ commits. PUSCH demapping/LDPC attempted; actual CRCError=1. That outcome
  is retained, not inserted as an expected NACK.
- Control available at sample 62632; PUSCH capture [69043,76877), completed
  and delivered at 76877 on the 7.68 MHz owner clock.
- Altered control clock, injected UE assignment, duplicate registration,
  duplicate completion and out-of-coverage timing search reject.
- Audit CSV roundtrip preserves identity, sample times and no-TX/no-commit
  status. This is not full normal-writer/manifest/PNG export qualification.

Raw file `logs/tpbc1a88a4_44c3_4804_bd3b_f9f9c72e83db/rejected_ul_receive_only.mat`:
33,290,819 bytes, SHA-256
`aa38585d49dff4e0d2508d460f1cfab96ef03e40ba5d762662379f0217f51093`.

The physical component has two explicitly resolved endpoint fixtures: a
known-candidate UE control receiver and an installed connected-UL gNB schema.
Both use the authored -30 dB diagnostic stimulus. It does not simulate acquired
timing or connected blind control, nor execute the complete normal coordinator.
Both resolved configs, actual control observation and receiver outputs are in
the raw MAT. This negative stimulus does not modify the production 12 dB leaf.

## Required next verification and implementation

1. Run the resulting clean commit's focused tests, full `testAll` and all
   required NR/config/channel/export/E2E guards. Keep older live suites and
   their frozen source intact; use the resource-gated validation checkout.
2. Implement the independent due-HARQ/CSI PUCCH/PUSCH ownership reducer and
   receiver-owned retransmission combining, replacing the explicit guards
   only with tested behavior. Exercise missing/all-missed DCI, DAI wrap,
   combined HARQ/CSI/SR, no producer, overlap and duplicate/stale/late cases.
3. Complete detector qualification, integrated all-measurement/export checks
   and final-source regressions before accepting 12 dB or promoting main.
   The separate long-run impairment-enabled study remains subsequent work.
