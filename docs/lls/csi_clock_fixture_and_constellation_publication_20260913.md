# CSI clock fixture and constellation publication checkpoint

The production 58-slot 12 dB baseline remains held. This follows the
[CSI calendar checkpoint](csirs_calendar_and_remaining_gates_20260913.md).
The overall single-carrier 400 MHz / 7 GHz, high-order modulation, Keysight,
long impairment-enabled LLS and later NTN/ISAC scope is unchanged.

## HARQ clock failure: narrowed and corrected

The prior `testCSIRuntimeExecution` failure was reproduced with a manually
constructed fixture grant whose `Frame` and `Slot` aliases were zero-based.
Its caller then added one to those aliases for throughput execution. That
produced correct execution arguments but left the frozen grant's aliases
inconsistent with the executed-HARQ contract.

The actual main runtime stamps `grant.Frame=state.CurrentFrame` and
`grant.Slot=state.CurrentSlot`, with one-based execution indices; its separate
`ScheduledAbsoluteSlot` and canonical control/data/feedback fields are
zero-based. `resolveWaveformGrant` and its regression use the same separation.
The failure is therefore not evidence of a newly discovered main-runtime
clock defect. No production binder, timing guard or immutable grant has been
made to accept mixed clock conventions.

The fixture now constructs the correct one-based aliases before DCI/freeze,
asserts their relationship to the zero-based canonical timing, and passes the
aliases directly to the runner. The original absolute CSI occasion is unchanged.

`evidence_20260913/csi_runtime_clock_fixture_tests_01.txt` completed with
**exit 0**:

- `testExecutedHARQClock`: boundary/SFN-wrap and mismatch rejection checks.
- `testResolveWaveformGrantClock`: explicit control0/execution1 adapter checks.
- `testCSIRuntimeExecution`: complete CSI waveform/measurement/export regression,
  including the strict non-occasion case that previously stopped at the binder.

These are the existing component/calibration fixtures, not a full access run
at 12 dB. They include other channel configurations and 20 dB data cases. The
12 dB YAML has not been switched to their geometry or channel settings.

## Missing constellation PNG: publication repair

The checkpoint publisher already read the full constellation sample CSVs and
generated EVM PNGs, but its chart list omitted the existing post-equalization
constellation renderer. It now requests that renderer. No capture is inferred
from modulation order, scalar EVM or assumed ideal received symbols.

The renderer retains raw receiver equalized I/Q (no payload fitting), full
sample rows and exported references. Its CSV now retains UE, frame, SFN, slot,
layer, codeword, modulation, sample index and capture scope. It rejects known
proxy/fallback provenance, contradictory DL/UL identity and nonfinite/missing
receiver samples. Missing capture data produces no primary plot or synthetic
cloud. Materializer version v68 invalidates stale terminal render caches; live
snapshots additionally bind producer hashes.

The existing deterministic preview limits remain explicit: up to 450 retained
samples per direction are displayed, while all input observations remain in
CSV. This is not a reconstruction of an uncaptured waveform or a complete
eight-layer/high-order-QAM qualification.

Python receipts `live_constellation_tests_01.xml`, `_02.xml` and `_03.xml`
each record **91 passed**. `_03.xml` includes the actual preview lineage check.
Tests cover exact sample/identity preservation, alias precedence,
no fitting/proxy substitution, absent data, invalid values, source immutability,
repeat-publication reuse, PNG decoding, EVM and existing chart regressions.

## Retained preview, not a new simulation

Source: `evidence_20260913/gnb_feedback_ul_constellation_03/` (the previous
60 dB UL component fixture). Original bytes remain untouched.

Output: `evidence_20260913/constellation_publication_01/`, snapshot
`3a841e1865e5dcff6095b9dd610d49f2a6021e6e8957298c37486a64aea88584`.
Its post-equalization CSV preserves all **3,522** raw receiver samples. The
PNG is explicitly captioned **POST-RUN PREVIEW**, not a live 12 dB result.
Visual inspection shows the retained tight QPSK clusters, numerical I/Q axes,
exported reference markers and the source/display counts. No DL samples were
invented for this UL-only fixture.

All **nine** generated PNGs pass component source/hash lineage checks.
`constellation_publication_lineage_audit_01.json` preserves both an initial
incorrect internal-helper invocation without Windows extended-path conversion
and the successful CLI-equivalent invocation. The former falsely reported two
long paths missing; the real audit CLI already applies the conversion. No
audit assertion was relaxed and no source files were moved to force a pass.

Reproduction (choose a new output directory):

```powershell
matlab -batch "diary('docs/lls/evidence_20260913/csi_clock_NEW.txt'); setup6GRSimToolkit('Verbose',false); testExecutedHARQClock; testResolveWaveformGrantClock; testCSIRuntimeExecution; diary off"
python -m pytest tests/test_live_constellation_publication.py tests/test_live_csv_plot_publication.py tests/test_lls_full_constellation_source.py tests/test_lls_evm_profiles.py tests/test_lls_contract_materialization.py -q --junitxml=docs/lls/evidence_20260913/constellation_NEW.xml
New-Item -ItemType Directory -Path docs/lls/evidence_20260913/constellation_preview_NEW
python scripts/publish_lls_live_csv_plots.py --run-folder docs/lls/evidence_20260913/constellation_preview_NEW --source-run-folder docs/lls/evidence_20260913/gnb_feedback_ul_constellation_03
```

## Remaining gates

The saved CSI planner patch was retried and again rejected by the source
editor; it is still unapplied. User assistance applying that exact patch in
the IDE has been requested. PUCCH receiver/source editing, receive-only missed
DCI handling, Format-0 HARQ/SR and detector ROC, dynamic HARQ-ACK codebooks,
shared special-slot control/data/feedback execution, TA/synchronization,
all-channel measurement equations, measured TPMI/PMI, QCL/TCI, AMC chronology,
remaining RA/beam/phase artifacts and terminal qualification remain required.

The failed old planner receipts remain valid failures. The resolved test
fixture clock issue should not be counted as an open production-clock defect;
it also does not prove every other timing path correct. The approved two-port
SRS/PUSCH remains in the actual 12 dB YAML. No `testAll`, E2E campaign, full
58-slot scenario or new 400 MHz/30 dB run was launched for this checkpoint.
The NR-validation, result-integrity and config-driven skills were used to keep
clock/provenance guards and existing scenario authority intact.
