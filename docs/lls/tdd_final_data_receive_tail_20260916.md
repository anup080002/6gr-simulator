# TDD finite-horizon data receive-tail repair

Status: four focused tests passed; integrated rerun and final-source full regression are pending. Parent revision: `6f2fd2ed731dd49aea59e44af3f58d75b40d40eb`.

## Executed failure and root cause

The frozen `d05c1441` 5 MHz TDD / configured 12 dB scenario executed all 58 scheduling slots, then failed with `sixgr:truth:SharedDataReceiveTailNotDrained`. Its retained failure checkpoint contains 19 completed DL and five completed UL trials. The slot-58 PDSCH receive observation had not completed at the scheduling horizon. This is a real finalization failure, not a successful run with optional missing plots.

`CoupledWaveformStream.queueData` registers complete receive windows including the executed channel pad. `advanceSlot` consumes only the current scheduled slot. `runWaveformLinkBundle` previously checked for pending data immediately after its last slot, without consuming those registered receive tails. The existing physical-queue fixture advanced an extra full slot, so it did not exercise the missing production finalization step.

## Repair

- `+sixgr/+truth/CoupledWaveformStream.m` retains the exact registered receive endpoint, adds `drainDataReceiveTail`, and lets the existing physical event loop stop at that endpoint inside a symbol. The same channel, noise and RF objects execute the extra samples. No receive padding, new channel realization, gain adjustment or invented decode is supplied.
- Draining rejects future, untransmitted data allocations before advancing time. It invokes no new scheduler slot-entry logic, restores the scheduled-slot counter, rejects new data-transmission commits, and is a no-op after all data observations complete. Pending future feedback still requires the existing finite-horizon censoring; it is not converted into a received ACK.
- Continuous transmitter-IQ capture remains scoped to the exact configured scheduling horizon. Receive-tail execution is reported separately in `reports/csv/shared_receive_tail.csv`, with actual sample bounds and pending-observation count.
- `+sixgr/+truth/runWaveformLinkBundle.m` drains physical observations and collects their normal receiver-completion results before sealing IQ and finalizing tables. The pending-data failure guard remains and also covers scheduled receive-only PUSCH windows.
- `tests/testSharedDataPhysicalQueue.m`, already registered in `testAll`, now invokes this same drain method instead of advancing an extra full slot. It checks future-transmission rejection, exact receive extent, no duplicate completion, unchanged scheduled-slot count and sealed continuous-IQ coverage. Existing independent channel/RF/hash/noise/measurement assertions remain.

## Executed tests

MATLAB R2026a, terminal exit **0**:

```matlab
setup6GRSimToolkit('Verbose',false);
r=runFocusedTests({'testSharedDataPhysicalQueue', ...
 'testContinuousRuntimeTxIQRecorder','testContinuousSharedTxIQCapture', ...
 'testTDDSharedPUSCHIndependentCompletion'});
assert(r.ok,'Shared receive-tail validation failed');
```

All four passed (102.69 s, 0.80 s, 22.36 s and 119.24 s respectively).
Log: `logs/data_receive_tail_v2_20260916.log`.
SHA-256: `8B2B2B89A1D658F0D101A666000734FC9C972932981F1EC09C017B38CE4C0448`.

The actual physical-queue fixture drained `[15360,15375)` at 7.68 MHz. Both gNB and UE transmitter manifests still contain exactly 15,360 samples and two scheduled segments. Its source/evidence is retained in `logs/shared_data_receive_tail/tp85a35764_e561_48f8_b1c6_20ec001c10b4/`. This queue fixture does not claim a decoded PDSCH. The independent PUSCH companion exercises actual receive completion but has empty UCI and a high-reference-SNR component configuration; it does not qualify nonempty HARQ or integrated 12 dB.

An earlier, simpler tail test also exited zero; its log `logs/data_receive_tail_v1_20260916.log` is retained (SHA-256 `4F69FB74A17EAC888431C656EA638FD8091DE7DE1F3AA2A2B7221C2F1FFC51AF`).

## Independent partial integrated evidence

The failed `d05c1441` run's completed rows were copied unchanged and hashed under that checkout's `logs/measurement_audit_20260916/all_slots_0714/`:

- All 24 completed transmissions: 71,079 full-allocation paired symbols; **264 EVM checks passed**. Receipt SHA-256 `62B2CEADD00931967A52C12A1906BB13555DB88A29373D954E06C1D496BA8F76`.
- **292 accounting checks passed**: immutable snapshot/unique trial pairing, configured occupied-RE noise, FFT variance transform, measured sample SNR, receive clocks, per-allocation goodput/offered rate and BER. Receipt SHA-256 `DE9BA173F884A8DC9A53817E4E1D4DD91C5A4AB09DEA0C6EF07860425FD964E1`.
- Completed DL: 136,248 compared bits; UL: 3,200; zero bit errors and zero CRC failures in those completed rows. These are not final wall-clock throughput, statistical BLER qualification or proof about the pending final allocation.

The initial causal audit's 27 failures comprise one missing measurement artifact followed by 26 dependency failures. That audit ran during failure recovery; neither a final pass nor 27 independent newly diagnosed PHY defects is established by it. Original failure and artifacts remain preserved.

## Remaining acceptance

Repeat integrated 5 MHz TDD / 12 dB on the repaired revision, including actual final-slot decode, finite-horizon HARQ/CSI accounting and final CSV/PNG review. Run `testAll`, configuration/NR/channel-estimation guards, strict/scheduler guards, export/artifact guards and both E2E truth/proxy guards. Detector statistical qualification, combined HARQ/CSI/SR coverage, older unresolved regressions, MATLAB R2023b validation and qualified-main consolidation remain separate open requirements. No threshold or assertion was weakened and no overall 3GPP qualification is claimed.
