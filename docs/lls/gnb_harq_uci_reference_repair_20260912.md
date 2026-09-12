# gNB HARQ/UCI initial-reference repair

## Root causes repaired

- `runULPUSCHThroughput` passed current trial MCS as
  `InitialIMCSPerCodeword` on retransmission. It now obtains the original
  MCS from the gNB-owned TB context, independently of the UE transmitter and
  UE HARQ buffer. Missing history, wrong cell/UE/RNTI/process/NDI/NDI epoch/TBS,
  undefined initial MCS and a table/rate disagreement are rejected.
- `createTBContext` retained original MCS but overwrote original modulation,
  Qm, target rate, rank and layer count from the current attempt. It now
  preserves all those original fields for the same TB. A new transmission
  still initializes new originals.
- Raw PUSCH CSV rows now expose `PUSCHUCIInitialMCS` and
  `PUSCHUCIInitialMCSSource`; unavailable UCI is not given invented values.

The existing UCI multiplexer/demultiplexer use the initial-MCS vector to
select the owning codeword when there are multiple codewords. The baseline
has one codeword: correcting this selector alone does not create a SINR,
BLER or throughput gain. Actual UCI resource budgeting still depends on the
PUSCH allocation, coding and payload sizes, as described by the
[MathWorks UCI-on-PUSCH reference](https://www.mathworks.com/help/5g/ug/nr-uci-multiplexing-on-pusch.html).

## Verification

The three-test endpoint/context process exited zero:

1. `testPUSCHUCIInitialMCS`: original-field retention, new-TB replacement,
   initial-MCS selection and missing/mismatched-history rejections.
2. `testHARQTBContextInvariants`: existing TB identity, segmentation and
   short-IR validation guards.
3. `testReceivedULHARQState`: actual accepted DCI and coded PUSCH with
   HARQ-ACK `1|0` on initial transmission, reserved-MCS retransmission and
   NDI rollover. The gNB derives and stores its own context; it never reads
   the UE coding layout or buffer. All TB and HARQ-ACK decodes passed.

The endpoint waveform fixture is high-SNR/unit-channel, not the shared-CDL
12 dB run. Its declared HARQ-ACK codec input does not qualify dynamic DAI or
production DL-to-UL feedback construction.

The shared-stream process exited zero, including CSV write/read checks:
slot 10, MCS 4, initial UCI MCS 4, source `current_new_tb_mcs`, UE HARQ
attempt 1, TB CRC pass and exact HARQ-ACK match. This remains the high-margin
new-TB shared-CDL fixture, not a shared retransmission or 12 dB result.

`testPDSCHTwoCodewordHARQContext` passed. The first
`testSchedulerHARQContextIsolation` attempt failed because its hardcoded
`[2 12]` budget was absent from its active TDRA catalog. Its budget now reads
the fixture's configured control/data symbol allocations; the production
catalog assertion and all UE-isolation assertions remain unchanged. The
dedicated retry (`assert(testSchedulerHARQContextIsolation)`) exited zero.
That successful assertion produces no console text, so its empty log and
the observed process-completion receipt are both retained. The earlier
failed group log is preserved, not relabeled as passing.

## Still required before the final baseline

- A shared-clock retransmission with UCI through the complete main scheduler,
  gNB retained coding state and actual receiver soft-combining path.
- Strict production DL received-allocation/receiver HARQ integration.
- Dynamic DAI and monitoring-occasion-aware HARQ-ACK ordering/sizing, including
  the Type-2 builder/oracle limitations recorded in the prior checkpoint.
- The previously blocked disabled-power test-file repair.
- One final 58-slot configured-12-dB execution, then CSV/PNG/IQ/terminal audit.

No final 12 dB run, `testAll` or E2E campaign was started. The broader
single-carrier 400 MHz/7 GHz, high-QAM and impairment work remains pending;
these focused passes do not establish whole-simulator conformance.

## Commands

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testPUSCHUCIInitialMCS','testHARQTBContextInvariants','testReceivedULHARQState'});" -logfile gnb_harq_uci.log
matlab -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testSchedulerHARQContextIsolation','testPDSCHTwoCodewordHARQContext'});" -logfile gnb_harq_context.log
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testSharedPUSCHChannelArtifacts('TDD',true,false,false,true,true));" -logfile gnb_harq_shared.log
```
