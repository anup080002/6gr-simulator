# 12 dB readiness recheck

Source revision inspected: `c409fa107c894d48765cad2b23c05dc876ed9cf9`.
No production source repair was applied in this recheck. The final 58-slot
simulation remains held; this is not a qualification receipt.

## Source editor investigation

The CSI planner patch still fails with `Failed to write file`, including
relative, absolute and Windows extended-path invocations of the patch tool.
The saved patch is `pending_csirs_planner_calendar.patch`; it remains unapplied.

Read-only diagnostics on `buildPlannedREAllocation.m`, `PUCCHReceiver.m` and
`allocREsPDSCH.m` found ordinary tracked-file status, no special Git attributes,
no index lock, and non-read-only file attributes. Windows permitted opening
write handles; no bytes were written and SHA256 hashes remained unchanged.
Restart Manager reported no file users for these targets. These checks neither
prove a security-tool problem nor identify Git/GitHub as the cause. No security
setting, ACL, source replacement or alternate source writer was used.

## Focused readiness checks

Receipt: `evidence_20260913/baseline_readiness_recheck_01.txt`.

- `testCSIRSPlannedCalendar`: FAIL. The caller still materializes inactive
  CSI-RS occasions; the strict materializer correctly rejects empty REs.
- `testCSIRSNonoccasionDataCapacity`: PASS. The retained received-DCI component
  allocation at absolute slot 62 has G=3108 and TBS=1064 with CSI enabled or
  disabled; there are zero extra reserved REs on that inactive occasion.
- `testTwoPortULYAMLAndSRS`: PASS. The actual continuous-IQ scenario resolves to
  two SRS/PUSCH ports, rank one, and matching UL DCI precoding configuration.
  A separate 12 dB two-port pilot-waveform fixture selects measured TPMI=3.
  This does not qualify the complete shared-CDL scenario or its AMC loop.
- `testBaselineSpecialSlotScheduler`: PASS. Main-created grants at zero-based
  slots 3 and 8 use TDRA 1, [2,8] symbols, valid timing and positive exact TBS.

Terminal MATLAB exit: 1; three checks passed and one failed. No MATLAB process
remained after this batch. The failure was retained, not converted to a pass.

No `testAll`, E2E campaign or full 58-slot run was requested by this recheck.
The focused scope follows the user's explicit restriction; it is not a claim
of passing the repository-wide suite.

## Access delay and special slots

The retained run's zero-based timeline is PBCH available 5, PRACH 14, RAR 16,
Msg3 19, Msg4 22, RRC complete 24, SRS 29 and first data PDSCH 30. Configured
access occasions and the measured-SRS prerequisite explain this schedule, not
MATLAB wall-clock processing. Some occupied RA slots lack grid publication.
NR defines configured monitoring/timing procedures, not a universal 30-slot
traffic-start delay; see TS 38.213 v18.8.0 section 8.2:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

The earlier special-slot causes were [2,12] PDSCH exceeding the ten-symbol DL
partition and sparse TRS excluding entire PRBs. Current YAML provides [2,8]
TDRA, and exact TRS RE reservation is implemented. Grant-generation tests do
not replace actual shared PDCCH/PDSCH/PUCCH execution.

## Remaining mandatory gates

1. Apply and validate CSI planner calendar and character-array selector repair;
   resolve the source editing failure without assuming a Git/permission cause.
2. PUCCH receiver-only context, missed-DL-DCI receive/disposition, Format-0
   HARQ/SR semantics and false/missed ACK detector qualification.
3. Dynamic Type-2 HARQ-ACK DAI ordering, wrap and missing-assignment handling;
   complete shared feedback chronology and special-slot execution.
4. TA/TAG/NTA offsets, physical transmit/capture origins, propagation and
   channel-filter delays, and DL/UL synchronization perturbation checks.
5. All-channel SINR/RSSI/EVM/power equation closure, including SS/CSI/data
   reference domains, complex spatial weights, PRACH margins and SRS/PUCCH.
   The exhaustive old-file inventory does not establish all PHY values correct.
6. Actual measured two-port SRS-to-PUSCH TPMI, PMI basis identity, QCL/TCI
   consumption and link-adaptation feedback causality in the baseline.
7. Remaining RA/native PRACH/post-channel grid, SSB/data beam and phase PNGs;
   alignment CSV columns, historical snapshot contracts and canonical discovery.
   Constellation publication has separate passing retained-capture tests.
8. One final 58-slot configured-12-dB run only after preceding gates close;
   then audit terminal verdict, every required CSV/PNG and IQ manifests/hashes.

After baseline qualification: Keysight playback, single-carrier 400 MHz at
7 GHz, 1024-QAM UL/4096-QAM DL study modes and 30 dB validation, broader
layer/antenna configuration coverage, and later NTN/ISAC remain pending.

Earlier fixes and their scoped receipts are preserved in
`csi_clock_fixture_and_constellation_publication_20260913.md`,
`csirs_calendar_and_remaining_gates_20260913.md` and
`continuous_iq_02_access_artifact_reaudit_20260913.md`.
