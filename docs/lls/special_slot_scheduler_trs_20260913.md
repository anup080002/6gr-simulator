# Special-slot scheduler/TRS repair and current baseline gates

This checkpoint follows [the TDRA/disposition repair](pucch_disposition_and_tdra_20260913.md).
It is not a qualified 58-slot run. Failed captures remain unchanged.

## Reproduced cause and repair

The main-created scheduler was exercised with the resolved continuous-IQ
12 dB baseline and explicit queued-UE/CQI inputs from
`simulator/configs/validation/baseline_special_slot_scheduler.yaml`.
Those inputs are a component fixture, not acquired access or measured CSI.

The prior budget repair selects the YAML's TDRA index 1, start 2, length 8
for the ten-DL-symbol special slots. The new scheduler test initially found
that zero-based slot 3 produced a real grant, but slot 8 produced none despite
25 eligible budget PRBs and valid timing. Its retained ResourceExclusions
table excluded every PRB (0 through 24), reason `TRS`; the candidate had a
free HARQ process but no legal frequency allocation. `_01` also had a
test-only DCI field-name error, corrected in `_02`; neither failure is hidden.

`SchedulerBase.ssbSafePRBSet` treated sparse periodic TRS as whole-PRB
ownership. In contrast, both the TX PDSCH allocator and independent
received-DCI allocator already install exact TRS `ReservedRE` before coding.
The scheduler now uses a distinct connected-PDSCH ownership check. It only
admits configured dedicated periodic NZP-CSI-RS with trs-Info after proving
its in-allocation REs are reserved and disjoint from PDSCH data, DM-RS and
PT-RS. The common/RA entry point remains unchanged. SSB and SIB1 exclusions,
final rank/MCS-specific feasibility, real TBS and DCI freezing remain active.

This follows [TS 38.211 v18.8.0, 7.3.1.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138211/18.08.00_60/ts_138211v180800p.pdf):
the applicable connected-PDSCH mapping excludes configured dedicated NZP
CSI-RS REs, not every PRB containing them. The distinction from mobility,
aperiodic CSI-RS and the separate TRS-ResourceSet IE matters; this repair
does not grant those cases the same automatic sharing policy.

`baseline_special_slot_scheduler_tests_03.txt` completed with exit 0:

- `testBaselineSpecialSlotScheduler`: both special slots produce one real
  grant, positive exact-feasible TBS, legal timing and DCI TDRA index 1.
- `testBaselineDLTDRABudget`: all eight DL-capable slots retain their legal
  catalog allocations; special slots use eight symbols, full DL uses twelve.
- `testSchedulerGrantConsistency`: existing grant/TBS/DCI checks pass.

These are scheduler/codec checks, not PDSCH decoding or HARQ radio qualification.
`connected_trs_resource_sharing_tests_01.txt` completed with exit 0:

- `testConnectedTRSResourceSharing`: actual noiseless encoded PDCCH waveform
  decoded; received TDRA selects slot 8 / [2,8]. The independent receiver
  reserves 36 TRS REs in its six-PRB allocation. G is 1788 bits versus 1932
  with TRS disabled in the isolated comparison; no disable is applied to the
  production scenario. Common/RA ownership and non-occasion checks pass.
- `testCommonDLResourceScheduling`: common SI/TRS protections in TDD/FDD
  and planning RNG preservation pass.
- `testPDSCHTRSExactReservation`: exact RE/G effects, non-occasion and
  TRS/DM-RS collision rejection pass.
- `testPDSCHTDRAFromDecodedDCI`: existing TDRA and negative checks pass.

The control-waveform fixture is noiseless and isolated, not a 12 dB shared
channel PDSCH/HARQ run. Reproduce with new evidence names:

```powershell
matlab -batch "diary('docs/lls/evidence_20260913/special_scheduler_NEW.txt'); setup6GRSimToolkit('Verbose',false); testBaselineSpecialSlotScheduler('docs/lls/evidence_20260913/special_scheduler_NEW'); testBaselineDLTDRABudget; testSchedulerGrantConsistency; diary off"
matlab -batch "diary('docs/lls/evidence_20260913/trs_sharing_NEW.txt'); setup6GRSimToolkit('Verbose',false); testConnectedTRSResourceSharing; testCommonDLResourceScheduling; testPDSCHTRSExactReservation; testPDSCHTDRAFromDecodedDCI; diary off"
```

## Access timing is a separate question

[The retained-run audit](continuous_iq_02_access_artifact_reaudit_20260913.md)
records, in zero-based slots: PBCH available 5, PRACH 14, RAR 16, Msg3 19,
Msg4 22, RRC setup complete 24, SRS 29, first data PDSCH 30. The configured
occasions and measured-SRS prerequisite explain this radio-time sequence;
it is not MATLAB wall-clock latency or a universal 30-slot start rule.
Missing RA grid producers can additionally make occupied slots look empty.
This checkpoint does not claim that the access schedule is latency-optimal.

## Current fixed-versus-pending boundary

Implemented with focused evidence: normalized PUCCH transmit power reference;
receiver DTX propagation and power-domain labeling; special-slot TDRA budget;
now main scheduler/TRS PRB eligibility. CSI-domain, received-control and
constellation-sampling repairs have earlier component evidence, not complete
run-level qualification. Approved two-port SRS/PUSCH, rank one, are present
in the actual 12 dB continuous-IQ YAML; they are not a separate unused profile.

Mandatory remaining gates, in repair order:

1. Resolve the two source-file patch failures. Git reports ordinary tracked
   files, no special attributes or index lock; a fresh allocator patch still
   fails. Git is not an evidenced cause. No alternate writer/ACL bypass was used.
2. Repair Format-0 HARQ/SR TX/RX semantics together; qualify false-ACK and
   missed-ACK behavior. The earlier borderline signal pass does not close ROC.
3. Apply CSI-RS non-occasion reservation/absolute-clock repair. It remains
   unapplied in `allocREsPDSCH.m` because that patch fails.
4. Close missed-DL-DCI disposition, retained HARQ/shared feedback chronology,
   and actual special-slot PDCCH/PDSCH/PUCCH execution together.
5. Qualify TA/TAG and DL/UL synchronization with delay perturbations and
   separate emission, propagation, channel-filter and capture-origin evidence.
6. Close SS/CSI/data/UL measurement equations, noise/power/complex-weight
   reconciliation, two-port measured UL TPMI, QCL/TCI consumption and link
   adaptation chronology. No arbitrary SINR offset or manufactured numbers.
7. Complete actual RA/beam grid and PNG producers, alignment columns,
   historical snapshot contracts, canonical artifact discovery and repeat-safe
   final rendering. Existing file/hash inventories are not all-equation proof.
8. Only then run one final 58-slot 12 dB baseline and audit terminal receipts,
   all CSV/PNG/IQ lineage and hashes. Keysight playback and the later single
   400 MHz/7 GHz/high-order-QAM scenario remain subsequent capability gates.

No new full baseline, `testAll`, E2E campaign or remote push was launched.
