# Received ACK/NACK/DTX checkpoint

This is a focused repair checkpoint, **not** a qualified 12 dB baseline.
No final 58-slot run, `testAll`, E2E campaign or GitHub push was performed.

## Repaired causal defects

The shared PUCCH feedback consumer collapsed unusable UCI into Boolean false
and passed it to `HARQEntity.onFeedback` as a decoded NACK. Its scheduler
boundary also rebuilt an outcome from that Boolean, making missing feedback
eligible for first-transmission OLLA. The same scheduler conversion affected
PUSCH-carried feedback even though its HARQ consumer already used DTX.

- `resolveReceivedHARQBit` now distinguishes a usable decoded ACK/NACK from
  receiver DTX, unusable decoding and a missing codebook position. Expected
  payload bits affect only scoring; a false ACK remains possible.
- Both PUCCH observation consumers use the same interpretation. A missing
  bit is no longer exported as a decoded NACK or false NACK.
- The live HARQ consumer receives the explicit outcome and scheduled
  feedback slot. NACK and DTX both permit retransmission, but their counters
  and delivery-ledger reasons are separate (`Stats.Nack`, `Stats.Dtx`).
- Runtime-owned and scheduler-local OLLA exclude DTX from ACK/NACK updates.
  Existing genuine first-transmission and retransmission rules remain.
- Per-grant feedback traces retain `FeedbackOutcome` and
  `FeedbackOutcomeReason`; PUSCH no longer labels DTX as a decoded NACK.

Here DTX means **no usable ACK/NACK at the receiver**, not proof that the UE
emitted nothing. A missed downlink DCI still needs a genuine gNB expected-UCI
observation path. This repair does not create that path or remove its stop.
Legacy generic state-change flags and final counter reductions still need
cross-table qualification; the new outcome fields do not qualify them.

## Focused test receipts

Evidence root: `docs/lls/evidence_20260913`.

| Receipt | Exit | Scope |
| --- | ---: | --- |
| `received_harq_outcomes_tests_01.txt` | 1 | New unit test incorrectly expected an empty struct instead of the allocator's empty HARQ assignment. |
| `received_harq_outcomes_tests_02.txt` | 1 | New test's empty-struct accumulation failed; changed to explicit cell accumulation. |
| `received_harq_outcomes_tests_03.txt` | 1 | A noise-only realization produced a receiver false detection; the test incorrectly assumed every no-signal trial must be DTX. ACK/NACK MAT captures are retained. |
| `received_harq_outcomes_tests_04.txt` | 0 | Actual isolated PUCCH ACK/NACK plus 64 retained noise-only receptions; declared MAC unit transitions; runtime/local OLLA exclusion; event-driven HARQ and scheduler-grant consistency. |
| `received_harq_shared_regression_01.txt` | 0 | Actual shared SRS/PUCCH with ACK and NACK in one occasion, timing/power/CSV checks, plus PUSCH feedback-reducer regression. The latter is not an additional shared PUSCH waveform qualification. |
| `received_harq_semantics_tests_01.xml` | 0 | 122 retained-ACK, CSV semantics and exhaustive-inventory Python tests. |

Commands:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testReceivedHARQFeedbackOutcome('docs/lls/evidence_20260913/received_harq_outcomes_04')); assert(testCoupledTruthOLLARetransmissionExclusion); assert(testSchedulerHARQStateUnblockAndLineage); assert(testSchedulerGrantConsistency);" -logfile docs/lls/evidence_20260913/received_harq_outcomes_tests_04.txt
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testSharedPUCCHFeedbackClock(true,'TDD')); assert(testLLSPUSCHHARQACKRuntimeFeedback);" -logfile docs/lls/evidence_20260913/received_harq_shared_regression_01.txt
python -m pytest tests/test_lls_retained_ack_semantics.py tests/test_lls_csv_semantics.py tests/test_audit_lls_run_exhaustive.py -q --junitxml=docs/lls/evidence_20260913/received_harq_semantics_tests_01.xml
```

Use new output names when repeating these commands; preserve historical
receipts. The MATLAB tests retain actual received samples and receiver
objects. Their MAC payload/clock inputs are explicitly declared unit inputs,
not a claim that a shared PDCCH/PDSCH retransmission was executed.

## New mandatory detector gate

The existing hardcoded Format-0 threshold of 0.2 yielded **60 false
detections in 64 noise-only component observations**, including 34 apparent
ACKs and 26 apparent NACKs. Four observations yielded DTX. The observed
correlation range was 0.1637262639 to 0.4519987778. All 64 outcomes are
retained in `received_harq_outcomes_04`, without seed selection, output
filtering or a threshold change. The ACK/NACK signal-present cases are
separate rows. This small experiment is not a false-alarm-rate qualification
for the baseline channel/receiver.

The installed R2026a `nrPUCCHDecode` source and its
[official documentation](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html)
specify format-dependent implementation defaults: 0.49/0.42 for Format 0
with one/two symbols, 0.22 for Format 1 and 0.45 for Formats 2-4. These are
receiver implementation choices, not universal 3GPP-prescribed constants.
The repository currently overrides them with 0.2 in its receiver/trial path.

Before the baseline: expose detector policy and thresholds through YAML,
verify the actual metric domain and format-dependent use, and compare the
same retained noise/signal samples across policies. Then qualify miss and
false-alarm behavior under the baseline's physical receiver conditions.
Do not merely select a threshold that passes this sample set or turn failed
detection into a synthetic NACK.

## Remaining execution gates

1. The normal editor again refused the CSI-RS non-occasion allocator patch
   at `+sixgr/+phy/+grid/allocREsPDSCH.m`; source remains unchanged. The known
   12-extra-RE / G=3060 versus 3108 capacity failure remains real. No ACL or
   alternate-writer workaround was attempted.
2. Main failed-DCI expected-UCI observation/DTX handling and the complete
   shared retransmission / retained ACK / actual UCI sequence remain open.
3. Complete the detector gate above, special-slot TDRA/K1 dispatch,
   independent TA/DL-UL synchronization, measurement-domain reconciliation,
   applied SSB/data beam evidence, and terminal CSV/PNG/IQ publication gates.
4. Only afterward run the final 58-slot 12 dB baseline. The production YAML
   already declares two-port SRS/PUSCH and short special-slot PDSCH TDRA;
   those declarations are not proof of runtime execution.
5. Keysight playback qualification, single-carrier 400 MHz at 7 GHz,
   higher-order study modulation and the 30 dB scenario remain subsequent
   stages. No all-configurations / all-measurements qualification is claimed.
