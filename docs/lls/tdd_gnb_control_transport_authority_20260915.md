# TDD gNB control and PUCCH transport authority

Implementation checkpoint, not detector qualification, full shared-feedback
closure, or 12 dB acceptance. FDD feature work remains deferred. Production
power/noise/channel policy, detector thresholds and the SINR sweep are unchanged.

## Root causes and repairs

1. `buildScheduledPUCCHHARQReception` previously rejected HARQ-only reception
   merely because UCI-on-PUSCH was globally enabled. That flag does not prove
   that PUSCH overlaps this PUCCH occasion. The builder now checks the actual
   transmitted gNB UL-command schedule using `assertNoScheduledPUSCHOverlap`.
   Real overlap still fails explicitly; no combined receiver is fabricated.
   TS 38.213 section 9.2.5 describes conditional UCI multiplexing and overlap:
   [ETSI Release 18 specification](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.05.00_60/ts_138213v180500p.pdf).
   This implementation's gNB ledger is not itself a standardized detector.
2. `CoupledWaveformStream` now binds scheduled PDCCH payload and frozen grant
   identity at queue time (`scheduledPDCCHGrantBinding`), but only records TX
   availability when the actual same-clock transmitter-prefix capture is
   complete. `readTransmittedULControls` does not consult UE accepted commands,
   pending ACKs, prepared UE payloads or UE control-decoder results. Queued
   commands are not labeled transmitted. Missing control lineage rejects.
3. Rejected-UL capture registration/completion now recover their allocation
   through `scheduledGrantForRejectedULControl`, from that physical gNB ledger.
   A retained UE rejection cannot replace protected grant fields. The audit
   retains gNB control observation identity and availability separately from
   UE rejection availability. It creates no transmitted TB, HARQ commit,
   synthetic BER/BLER denominator, throughput or fallback primary row.
4. `CoupledTruthRuntime` permits the schedule-checked HARQ-only branch when
   UCI-on-PUSCH is enabled, and retains transport evidence on receiver-only
   completion. New signal-present normal-coordinator coverage remains needed.
5. Descendant fixture resolution exposed disabled CSI with inherited enabled
   CRI policy. `lls_pucch_gnb_receive_only_fixture.yaml` now declares coherent
   disabled CQI/PMI/RI/CRI acquisition-policy aliases. Production CSI is not
   disabled, and configuration validation is not weakened.

## Executed tests

MATLAB R2026a Update 4. Working-tree candidates based on `3fd9a3e1`, explicitly
recorded with `AllowDirty`; not clean-commit full-suite qualification. Source
and HEAD were unchanged while each focused run was live.

| Integration checkout log directory | Result |
| --- | --- |
| `logs/testall_20260914T193113976Z_d55d5060` | New descendant fixture FAIL before PHY with `ContradictoryRuntimeAuthority`; rejected-UL test PASS 98.35 s; original PUCCH test PASS 128.77 s; launcher 1 |
| `logs/testall_20260914T193938486Z_9a0507cc` | Rejected-UL preflight PASS 0.65 s; no-PUSCH occasion PASS 139.20 s; strengthened rejected-UL physical test PASS 71.56 s; original PUCCH physical test PASS 74.21 s; MATLAB/launcher 0 |

Both original log folders and ZIPs are preserved locally, including the failure.
The new test is registered in `testAll`.

### Actual physical evidence and scope

- No-PUSCH occasion: two actual DL transmissions, actual SRS and independent
  PUCCH IQ reception, no scheduled UL command, no UE UCI producer, and two
  actual DTX dispositions. Poisoning UE pending grant/ACK state leaves the
  gNB mapping, assignment and transport evidence unchanged. This component
  deliberately does not execute UE DL control/data reception, so it does not
  measure missed-DCI probability or qualify the detector.
- `logs/tp69ee78af_5034_4338_9ab4_5e3fc2357118/received_pucch_absent.mat`:
  1,556,592 bytes; SHA-256
  `7f6d1a3f08a58fa42d4fbbf155817a3c446971a39737f8529fe75a584c0ec9bf`.
  The real observation is [61263,69112), available at 69112, at 7.68 MHz.
  The two source DL TBs each contain 2088 bits. Seeded enabled/disabled-policy
  fixtures are paired regressions, not independent qualification episodes.
- Rejected UL: actual gNB control prefix [61440,62540), available at 62540;
  actual UE rejection available at 62632; actual PUSCH capture [69043,76877),
  available at 76877. Decode attempted, CRC error observed, no UE PUSCH TX,
  no transmitted-TB scoring and no HARQ state commit. A pending control,
  overlapping scheduled PUSCH and altered retained TBS each reject as tested.
- `logs/tpe50c6187_39e5_431b_bc44_016d82334def/rejected_ul_receive_only.mat`:
  34,431,332 bytes; SHA-256
  `9ee4eefbbc7bf0c49f8c00a0085731e8a119a42dda72e9c47b9090939ff27b01`.
  Independent HDF5 inspection confirms the saved actual control grant bits
  equal the gNB ledger bits, with payload SHA-256
  `6d9040832cedacc51f9286933403a013a8bc18dda42bf720e070afc79c020bb7`.
- The original PUCCH fixture's default raw output remains outside the checkout:
  `C:/Users/anup0/AppData/Local/Temp/tp32fb574a_f6b5_476a_b133_57a71b7ee8d9`.
  Its launcher logs are under repository `logs/`. No claim that every raw file
  is uploaded to GitHub is made; this document records local evidence.

## Still required, in order

1. Clean-source focused regressions, full `testAll`, and required
   NR/config/channel/export/E2E guards on the frozen validation checkout.
   Older live suites are evidence for their own revisions only.
2. Decouple UE PUCCH production from the gNB's independently scheduled
   transport expectation. Complete due-HARQ/CSI rejected-UL handling,
   exactly-once common feedback disposition and receiver-owned retransmission
   combining. `RejectedULUCITransportOwnershipRequired`,
   `RejectedULReceiverHARQCombiningRequired`, combined-CSI and actual-PUSCH-
   overlap guards remain deliberately unfinished, not silently bypassed.
3. Signal-present normal independent PUCCH, missing/all-missed DCI, DAI wrap,
   HARQ/CSI/SR overlap, no producer, duplicate/stale/late feedback; production
   SR calendar/timer closure; independent detector qualification with the
   original failure retained; integrated all-measurement and export checks.
4. Accept 12 dB and promote main only after final-source evidence supports it.
   No fixed completion time is claimed from four component passes.
