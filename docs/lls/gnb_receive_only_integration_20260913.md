# Actual gNB receive-only PUCCH integration

Development handoff based on `2faf8d91`; **not a 12 dB qualification**.

## Implemented boundary

The shared runner now arms the gNB feedback observation from committed actual
DL transmission, rather than conditioning its existence on UE DCI reception.
When no UE feedback producer exists, the registered physical capture can be
bound to an independent HARQ-only gNB allocation. Its bit identities come
from retained transmitted grants and packed DCI, its resource from installed
RRC, and decoding from actual post-RF samples plus received SRS timing.

No PUCCH waveform, prepared transmitter, UE report, expected ACK bits or
injected noise variance is manufactured for this path. Each real gNB
ACK/NACK/DTX decision updates the actual scheduled HARQ process and scheduler;
stale decisions are identified separately. All process identities are checked
before any process is mutated. The new gNB bit observation CSV retains actual
transmission/grant IDs, TBS, bit indices, mapping digest and sample clock.
The receiver-only trial explicitly says no PUCCH transmission is claimed.

The new path rejects enabled CSI reporting, UCI-on-PUSCH and installed SR
resources until their independent combined hypotheses exist. An explicitly
empty YAML SR list is accepted as no installed SR resource; missing SR
configuration still fails. It does not silently assume a configured SR is
negative. Normal transmitted-PUCCH/PUSCH consumers remain separate work.
The optional nature of SR resource configuration is consistent with
[TS 38.331 PUCCH-Config](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/17.00.00_60/ts_138331v170000p.pdf).
No detector thresholds, noise scaling, power gains/losses or acceptance gates
were changed.

## Executed evidence

- Attempt 01: failed before physical execution because the new fixture
  disabled CSI reporting but inherited enabled CQI/PMI/RI/CRI flags. The
  strict dependency check was preserved; the fixture was corrected.
- Attempt 02: actual two-DL-transmission/absent-PUCCH component passed, with
  two detected DTX outcomes. This preceded the explicit SR guard.
- Attempt 03: the new component and existing receiver/shared-clock checks
  passed; the *command as a whole failed* because its final test name
  `testPUCCHPowerControlRuntimeExport` did not exist. The real power-export
  assertions are already exercised by `testSharedPUCCHFeedbackClock`.
- Final attempt 04, through the new server launcher: **5 tests passed**, zero
  failed, MATLAB and launcher exit 0. Includes receive-only clock, receiver
  assignment, observation receiver, existing shared feedback/power CSV and
  regression harness authority. The harness intentionally executes failing
  and incomplete probes and must reject them; those messages are not failed
  top-level tests. The new receive-only case has eight rejection guards,
  unchanged HARQ state after rejected completions and actual-IQ replay
  equivalence. Actual observed feedback was DTX/DTX, not forced by the test.
- Windows launcher contract tests: **4 passed** (28.04 s). A fake executable
  is used only to test startup errors, missing terminal reports, nonzero
  exits and ZIP preservation; it is never PHY evidence.
- Real R2026a launcher preflight passed locally. Its original local log is
  retained under `/logs`; the final launcher prints toolbox versions without
  the license-number header from MATLAB's bare `ver` display.

Source and artifact hashes are in
`evidence_20260913/gnb_receive_only_server_receipt.json`. Original failed logs
and actual samples from attempts 02/03/04 are retained unchanged. The final
focused log/report/CSV files are under `server_focused_validation_04/`.

## What remains open

This component deliberately does not execute UE PDCCH/PDSCH reception; it is
not a measured missed-DCI rate or full access qualification. Its initial
connected timing/pathloss selector inputs are declared analytic component
fixtures, not measured access evidence. The physically transmitted DL and
received SRS/PUCCH captures are actual execution evidence.

Required next work remains: normal UE/gNB Type-2 codebook consumers, combined
CSI/SR/PUSCH allocation and disposition, missed-DCI/gap/wrap qualification,
independent detector statistics, full timing/power/noise/reference/data
measurement closure and current-run CSV/PNG/IQ audit. The previous two-bit
noise false-ACK result above its 1% gate is not erased by this component pass.

The `2faf8d91` guard batch finished with 12 passes; its full testAll is still
running on immutable local main. New-source full regression remains required.
The server handoff is source/evidence consolidation for testing, not a release
assertion. No historical outputs, branches, patches or working directories
were deleted. NR-validation and result-integrity guided actual-event mapping
and honest primary rows; the config-driven skill required explicit fixture
dependencies and unsupported-combination guards.
