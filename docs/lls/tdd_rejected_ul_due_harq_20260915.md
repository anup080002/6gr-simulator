# TDD rejected UL command with due HARQ: ownership checkpoint

This checkpoint is NOT detector qualification or 12 dB acceptance. The new
physical ownership test passed, but its silent-PUSCH observation produced an
actual false ACK. That result is preserved, not replaced with an expected DTX.
FDD work, production power/noise policies and the SINR sweep are unchanged.

## Implemented

- `findScheduledPUSCHOverlap` inventories the physically transmitted gNB UL
  command ledger. `buildScheduledHARQTransportReception` selects an ordinary
  single-overlap, HARQ-only scheduled PUSCH schema independently of UE ACK
  state. PUCCH-only callers still reject a selected PUSCH. Multiple PUSCH,
  combined CSI and overlapping SR cases retain explicit guards.
- The empty-producer branch of `prepareSharedPUCCHFeedbackRuntime` verifies
  that no received UE HARQ event/accepted DL control was lost, then binds an
  unselected PUCCH observation when the gNB expects PUSCH. This is NOT a UE
  transfer-to-PUSCH claim. No real UE producer is suppressed by this branch.
- `CoupledWaveformStream` retains the selection privately, with UL command,
  mapping and sample-clock identity. Actual unused PUCCH capture planes remain.
  `completeUnselectedPUCCHObservation` emits an audit, not a PUCCH decoder trial.
  The normal writer has `control/csv/unselected_pucch_capture_audit.csv`; full
  normal-writer/manifest/export verification remains required.
- `completeSharedPUSCHAfterRejectedControl` now completes due HARQ when no UE
  feedback producer exists. It rebuilds the schema against the actual hashed
  receive window, decodes actual IQ, and invokes the common exactly-once DL
  HARQ boundary. No transmitted UL TB, goodput, UL HARQ commit, or fabricated
  PUCCH ACK/NACK/DTX row is added. Audit columns distinguish DL and UL commits.
- Existing UE PUCCH producers, CSI, and receiver-owned UL retransmission
  combining are not completed by this patch. Their explicit guards remain.

The selected receiver is an implementation decision, not a claim that 3GPP
defines this detector. Conditional UE overlap/multiplexing rules are described
in [TS 38.213 section 9.2.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.05.00_60/ts_138213v180500p.pdf).

## Executed evidence

R2026a Update 4; working-tree candidates based on `78b5cea5`, recorded with
`AllowDirty`. Source was unchanged during each run. Original failure folders
and ZIPs remain in the integration checkout's local `logs/`.

| Log directory | Outcome |
| --- | --- |
| `testall_20260914T200023997Z_9b5e9700` | New fixture FAIL `ScheduledULDAIContextMismatch` 100.50 s; original rejected-UL FAIL `ChangedRejectedULReceiveContext` 64.98 s; no-PUSCH PUCCH PASS 95.08 s; launcher 1 |
| `testall_20260914T200649806Z_7daaf772` | New fixture FAIL missing top-level TPMI 95.43 s; original rejected-UL PASS 77.95 s; launcher 1 |
| `testall_20260914T201229574Z_02db4a0c` | New due-HARQ ownership test PASS 173.15 s; MATLAB/launcher 0; NOT receiver qualification |

Repairs preserved the assertions: the fixture rebuilds its control context
before TX under the installed timing list; TPMI is decoded from the retained
DCI and checked against the frozen physical allocation. That retained UL
allocation is an explicit component input, not a new SRS measurement. The
completion preflight and decoder now use the same actual receive-window ID,
instead of comparing it with the different registration ID.

Raw directory: `logs/tp1afe919f_cbd4_4726_88f8_c7167e14ef34`.

- One actual slot-6 DL transmission, 2088-bit TB; feedback target slot 10.
- UE DL decoding is deliberately unexecuted. This is NOT a measured missed-
  DL-DCI episode or acquired-access qualification. Connected timing is an
  explicitly declared component input. UL control is actually decoded/rejected.
- gNB control available at sample 62540; UE rejection available at 62632.
- Actual PUSCH capture [69043,76877), received/committed at 76877, 7.68 MHz.
- No UE PUSCH TX; actual UL TB decoder CRC error; one DL HARQ ACK applied;
  no UL HARQ commit or transmitted-TB score. Same-transport and cross-transport
  duplicate commit attempts reject. No PUCCH trial or transfer record is made.
- `rejected_ul_receive_only.mat`: 36,654,642 bytes, SHA-256
  `7bcdbb3fd48febad4403aaf5ecfa4886007a1a1348a1e3496bbc1a9ffdecb9a3`.
- `unselected_pucch_observation.mat`: 28,312,817 bytes, SHA-256
  `a573eaef64fabfccefdbad607e8213b226fc76f12b489efd059e966ef55da870`.

These raw files remain local; committing this report does not upload the raw
MAT files to GitHub. Both resolved endpoint configurations and raw decoder
outputs are retained in the result MAT.

## Newly demonstrated blocker: PUSCH short-UCI presence/confidence

Independent Python/HDF5 inspection confirms the decoder returned bit 1,
DecodeOk=true, DTXFlag=false on a capture with no UE PUSCH transmission.
The 24 retained HARQ LLR values have magnitude below 0.001. This is a real
false-ACK observation, not a successful silent-link detection result.

Root path: `decodeUCIWithEvidence` sets DecodeUsable from output length,
binary values and applicable CRC flags. For this one-bit field CRCApplicable
is false, so no detection/confidence criterion exists. `puschUCIFieldUsable`
and `normalizeReceivedPUSCHHARQ` carry that usability into common disposition.
The UL TB CRC is independently failed; it must NOT be used as a substitute
for the UCI field's own detection/decoding evidence.

Required next repair: receiver-only short-UCI confidence/presence evidence in
`+sixgr/+phy/+ul/+pusch/decodeUCIWithEvidence.m`, its demultiplexer/receiver
callers, `puschUCIFieldUsable.m` and `normalizeReceivedPUSCHHARQ.m`, backed by
explicit YAML policy and independent no-signal/signal-present qualification.
Choose and validate the statistic before choosing a threshold. Do not gate
on UE transmission knowledge, inject a CRC, or tune only to this saved episode.
Retain this original observation and its decoded ACK as the diagnostic anchor.

## Remaining acceptance work

1. Final clean-source focused tests, `testAll`, NR/config/channel/export/E2E
   guards. A queued suite is not a passed suite.
2. Short-UCI PUSCH and PUCCH detector qualification, including historical
   failures; existing-producer overlap, combined HARQ/CSI/SR, DAI gaps/wrap,
   duplicate/stale/late cases and receiver-owned retransmission combining.
3. Production SR calendar/timers; all-measurement and complete CSV/PNG/export
   verification; final-source integrated 12 dB acceptance before main promotion.
4. Subsequent long impairment-enabled 6G study with standards taxonomy kept
   explicit; never label all discussed candidate features as standardized NR.

The still-live older `e6341805` suite additionally reported failures in
`testConfiguredSRCalendar`, `testOperatorMasterConfigurationContract`,
`testCoupledTruthCSIReportSourceAuthority`, `test6GLLSMultiUserBeamforming`,
`testPRACHRuntimeULDirectionAntennaContract`,
`testTRSRuntimeControlGatingEvidenceContract`, `testRAStageCarrierSlotBinding`,
`testRADownlinkPowerScaling`, `testRuntimeOperatingAuthority`,
`testLLSRawTrialProvenance` and `testLLSCoupledTruthHARQRoundTrip`.
These need final-source reconciliation, not automatic attribution to this
patch. Intentional negative regression-harness probe failures are excluded.
