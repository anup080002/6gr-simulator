# Independent periodic CSI reception: development evidence

Parent: `fd8d2a09713c71719311c88cab683f46f826b496`.
Scope: TDD receiver ownership and completion, not 12 dB acceptance.

## Production change

- `CoupledTruthRuntime` arms configured periodic CSI receive windows without a
  UE pending report. The independently empty actual DL HARQ schedule is checked
  before choosing CSI-only reception; missing UE events cannot erase HARQ.
- `buildConfiguredPUCCHCSIReception` derives resource/schema/transport from
  installed CSI/SR calendars and actual gNB scheduling. SR inventory alone does
  not imply an installed SR procedure. An overlapping scheduled PUSCH retains
  the same configured CSI obligation.
- `CoupledWaveformStream` binds CSI-only receive-only/unselected observations
  without inventing a HARQ mapping or prepared transmitter.
- `normalizeReceivedPUCCHCSI` validates actual receiver flags/bits and the bound
  typed schema. Reserved CSI wire values are unavailable decode results, not
  fabricated CSI. Other errors propagate.
- The actual receive-completion callback reuses common CSI publication and
  PUCCH outcome accounting. UE reports are optional audit data. Duplicate and
  late completion/producer guards remain explicit. No power, noise, samples,
  threshold, payload, channel-estimation or processing delay is substituted.

## Focused execution

MATLAB R2026a, `-wait -singleCompThread`. Both batches exited 0 and their
launcher/engine processes were absent before terminal log hashing.

| V4 test | Result | Seconds |
| --- | --- | ---: |
| `testSharedPeriodicCSIProducer` | Present, removed-after-TX, absent producer; configured receive window, completion clock, counters, duplicates and power CSV checks passed | 353.093 |
| `testTDDSharedPUSCHIndependentCSICompletion` | Actual shared DL HARQ/CSI and received PUSCH completion passed both ordinary and removed/poisoned UE-audit cases | 1375.660 |
| `testSharedCSIReportClock` | Existing TDD CSI clock and power-export regression passed | 216.378 |
| `testCSIOnlyPUCCHResourceAuthority` | Configured resource, PRI independence and invalid-binding checks passed | 31.990 |

V4 log: `logs/csi_owner_v4_20260916.log`, SHA256
`A0F5A35063E0F145953CAC6201C5561963A1D78F7CB98E298AEA100A943E4DD6`.
All 24 selected pre/post source hashes matched; this is not a transitive manifest.
The ordinary clock fixture retains its legacy slot-4 component path; it does
not establish removal of all legacy combined reception.

After V4, only tests/diagnostics changed: the shared-PUSCH fixture now retains
the complete receiver decision for receive-only captures, and the Type-2 fixture
was migrated to explicit installed SR state. V7 passed that fixture and an
independent replay of the retained slot-5 no-PUCCH capture. All 26 selected
hashes matched. V7 log: `logs/csi_owner_v7_20260916.log`, SHA256
`58F53388E762954C6DE69D0A0354CA807AF42E132BC72F30E8C7DAE959527C68`.
Code Analyzer reported style warnings and unavailable user settings; no syntax
error. The new receiver-retention lines still require the final-source suite.

### Type-2 fixture root cause and correction

The installed SR procedure requires explicit state, including negative SR.
The old assertion then incorrectly compared the entire internal `[HARQ; SR]`
serialization with only the HARQ bits. The test now asserts exact owners and
values `[HARQ_ACK; HARQ_ACK; SR]` / `[0;1;0]`, unchanged HARQ subset `[0;1]`,
Format 0/set 0, separate receiver counts, native symbol equality for negative SR
versus HARQ-only, and distinct positive-SR symbols. Missing-state and all previous
identity/transport rejections remain. The production transmitter already passes
separate HARQ and SR inputs, as documented by
[MathWorks nrPUCCH0](https://www.mathworks.com/help/5g/ref/nrpucch0.html) and
[nrPUCCH](https://www.mathworks.com/help/5g/ref/nrpucch.html).

V5 failed before tests because MATLAB `run` entered the diagnostic script's
directory; V6 fixed cwd and exposed the stale whole-vector assertion. Both logs
and terminal receipts are retained, not reclassified as passes.

## Additional actual evidence, not qualification

- Both PUSCH cases exported two received CSI rows. An independent Python CSV
  comparison found no differences except optional `UEReferenceRecordJSON`.
- Slot 5 had no prepared PUCCH but the receiver published CQI=5, RI=1, PMI=0,
  CRI=0. Same-IQ replay reproduced metric `0.2384850435968231` above configured
  threshold `0.2`, DTX=false, CRC not applicable. This finite-metric false alarm
  is distinct from the separately open invalid-metric fail-open defect. It must
  remain visible; transmitter absence must not be used to force receiver DTX.
- The intended slot-10 PUSCH report was CQI=15, RI=1, PMI=3 in both cases.
- Independent EVM reconstruction from 3522 unique exported resource coordinates
  gave `0.0010687193348400076`, versus reported `0.00106871933483974` (absolute
  difference `2.675810961694225e-16`). Raw/exported equalized symbols matched.
  The generated constellation PNG was visually checked. This fixture has
  configured SNR=60 dB; its exported post-equalization SINR=45 dB is explicitly
  marked `OK_dynamic_range_limited`. It is not the requested 12 dB scenario.

## Remaining acceptance gates

Required final-source unfiltered `testAll` and config/framework/NR/strict/export/
scheduler/E2E guards are still pending. R2023b is unqualified. Normal combined
PUCCH HARQ/CSI/SR, missing/all-missed DCI and cross-transport cases, rejected UL
control, detector qualification, SRS corrections, reporting populations/identity/
goodput, integrated all-measurement CSV/PNG acceptance, historical patch
reconciliation, qualified-main consolidation and 5 MHz/12 dB acceptance remain
open. No detector threshold, confidence gate or original false-ACK limit changed.
