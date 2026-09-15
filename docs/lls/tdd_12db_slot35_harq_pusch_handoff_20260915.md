# 5 MHz TDD / 12 dB: slot-35 handoff repair

Latest status at 16 September 2026, 00:23 IST: **not integrated-12-dB acceptance**.
The joint pre-DCI repair below is now implemented and focused-tested. The
earlier lifetime-only evidence is retained separately for provenance.

## Retained failure and root causes

The 58-slot run `tdd_5mhz_12db_5e3fc49b_20260915` failed at source slot 35
with `sixgr:truth:UnresolvedScheduledPUSCHReceiveHypothesis`. Its terminal
launcher receipt records exit 1 / `ScenarioPassed=false`. Failure recovery
finished; the run is no longer simulating. Three DL trial rows and zero UL
trial rows existed at the failure checkpoint. Retain the failed-run artifacts.

1. `runWaveformLinkBundle.m` popped the due UL grant out of the scheduling
   queue and copied only future grants into `SharedPendingULGrants` before
   `advanceSlot`. The shared PUCCH callback could consequently not reconcile
   the accepted due PUSCH grant. Consuming a scheduling entry is not completion
   of receiver/encoded-UCI ownership.
2. The transmitted schedule also needs a pre-DCI timing repair. The exported
   DL grant in slot 34 occupies symbols `[2,8]`, while the slot-35 PUSCH starts
   at symbol 0 and spans 13 symbols. Its overlapping PUCCH starts at symbol 12.
   Qualifying the later PUCCH start does not qualify the earlier PUSCH start.
   Even the pos0 capability-1 HARQ multiplexing duration exceeds that gap.
   Fixing calendar lifetime alone must not suppress the late-encoding guard.

## Implemented and focused-tested

- `advanceSharedSlotWithULGrants.m`, called by the real slot loop, retains due
  grants through the physical callbacks and then retires source-slot calendar
  entries. Callback-admitted future grants are retained, not overwritten by a
  pre-advance snapshot. It neither supplies decoded-control authority nor
  changes encoded UCI, waveform samples, ACK decisions, power or noise.
- `harqPUSCHMultiplexingProcessingTime.m` calculates capability-1 N1/d1,1 and
  N2/d2,1 plus the multiplexing symbol, with the smallest participating SCS.
  It uses actual NR PDSCH/PUSCH resource maps, including DM-RS-only first UL
  symbols. This duration helper is now wired into joint pre-DCI scheduling.
  Its scope explicitly excludes switching/d2,2 and aperiodic-CSI budgets;
  a caller must not treat it as a universal timing qualification.
- Both new tests are registered in `testAll`.

Focused MATLAB R2026a receipts, both exit 0:

| Log under this checkout's `logs/` | Result |
| --- | --- |
| `ul_calendar_lifetime_20260915.log` | 3/3 pass: new lifetime, preparation clock, physical PUCCH feedback clock |
| `harq_mux_processing_math_20260915.log` | 2/2 pass: new multiplexing arithmetic, existing PUSCH allocation timing |

SHA256, respectively:
`39F3A29987AFBB8EF097A3C498CBF61C68B72688EAB02168CB502F8D457F7944`
and `C4512F5128FDFA81811FBBBD76BFD372861901A463D1C0069E34C143224B2777`.

## Joint repair implemented on 16 September

- `runWaveformLinkBundle.m` separates tentative UL planning from control
  transmission, jointly resolves DL/UL timing, then prepares both DCIs.
  Existing first-SRS reservation priority remains before UL DCI preparation.
- `buildHARQPUSCHTimingConstraints.m` uses the actual frozen allocations and
  processing budgets. It rejects unsupported switching, aperiodic CSI and
  cross-numerology scope instead of silently assuming zero extra delay.
- `evaluateHARQPUSCHTimingConstraints.m` tests the earliest advanced start
  of the transitive overlapping UL group against PDSCH/PDCCH readiness.
  `TimingRelationEngine.m` applies this evidence to authored K1 candidates.
- `planJointHARQPUSCHTiming.m` preserves already transmitted controls and
  resolves tentative controls before enqueue. `CoupledWaveformStream.m`
  exposes completed gNB scheduling observations independently of UE decoding.
- `SchedulerBase.m` can refreeze the same attempt after canonical timing
  selection; retransmission rebinding removes stale prior-attempt constraints.
  Data occasion, symbols, PRBs, real TBS and HARQ identity are asserted unchanged.
- `CoupledTruthRuntime.m` exports nonempty scheduling audit rows to
  `joint_harq_pusch_timing_decisions.csv`. These are planning records, not
  measured receive success, power, SINR or ACK observations.

### Focused evidence, MATLAB R2026a

| Log under `logs/` | Terminal result |
| --- | --- |
| `joint_harq_pusch_timing_v6_20260916.log` | Exit 0, six tests: joint timing, multiplexing math, allocation timing, production timing migration, retransmission binding, physical missed-UL-DCI receive-only |
| `joint_harq_pusch_physical_completion_20260916.log` | Exit 1: both nonempty-HARQ and empty-UCI physical PUSCH tests passed; the source-order test failed because its locator expected the old function signature |
| `joint_first_srs_order_guard_20260916.log` | Exit 0: repaired source locator; original first-SRS assertions retained, additional joint-before-DCI assertions passed |

SHA256 in that order:
`D4068207EF782BEBCD84A0E08D89C7543A27753DDD4B18541674FC751D84212B`,
`5FB8BB8DDFC560E490C215589A2EC875C6D4A3CFDDB9ECBAD5808392D5110FBC`,
`AB7886E44272B1E56206B1BDFF4703F38C7BA68444B6B4DE2EB406FE4F116043`.

The joint unit fixture uses the actual short-slot resource geometry and
selects configured K1=5 instead of K1=1 while preserving its 1032-bit TB.
Its explicitly labeled SRS metadata is a unit fixture, not physical SRS
acceptance. The separate positive PUSCH companions execute physical SRS,
control and data; they are not the configured-12-dB integrated scenario.
Earlier failed development logs v1-v5 are retained, not counted as passes.

## Remaining acceptance, in order

Run the unchanged 5 MHz TDD configured-12-dB scenario as an integration
diagnostic, followed by final-source full `testAll` and required guards.
The older full suites on 73867a4 and 9bb69197 cannot qualify this repair.
Combined CSI/SR/HARQ, all requested measurements and exported artifacts,
original detector qualification and MATLAB R2023b remain unqualified.
FDD and 400 MHz remain deferred. Do not force the measured SINR to 12 dB.

The original repair checklist below is retained as a description of the
required coverage; implementation steps 1-3 now have focused evidence above,
whereas integrated acceptance in steps 4-5 remains open.

1. Split future-UL candidate planning from UL DCI preparation in
   `localScheduleCoupledFutureULGrantsFromDLControl`. Make tentative DL/UL
   allocations jointly available before either control waveform is queued.
2. In the canonical timing path, evaluate the earliest advanced UL start
   against every associated PDSCH and PDCCH endpoint. Resolve only authored
   K1 candidates; preserve the data allocation/TB and update all canonical
   feedback aliases and frozen PHY/DCI context before transmission. Preserve
   transmitted schedules unchanged. Do not indefinitely suppress UL traffic.
3. Include existing gNB-transmitted controls independently of UE DCI reception;
   future scheduling must not depend on successful UE decoding. Keep normal,
   missed/all-missed DCI and independent receiver transport assertions.
4. Test the actual short mixed-slot pair, legal alternatives, exact timing
   boundary / one-tick-early rejection, late-encoding rejection, and ordinary
   shared PUSCH completion. Check CSI/SR calendar overlap when the selected
   feedback occasion changes; a HARQ-only pass is not combined-UCI closure.
5. Run the final-source required guards and full `testAll`; then rerun the
   unchanged 5 MHz TDD configured-12-dB scenario with logs/artifacts. A
   configured reference point must not overwrite measured post-equalization
   SINR. All-measurement/export and detector qualification remain separate
   acceptance obligations. FDD and 400 MHz work remain deferred.

## Normative references

- [TS 38.213 V18.8.0 clause 9.2.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf), pp. 138-139.
- [TS 38.214 V18.8.0 clauses 5.3 and 6.4](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).
