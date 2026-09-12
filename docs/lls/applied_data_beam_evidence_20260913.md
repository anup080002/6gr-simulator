# Applied data-beam evidence checkpoint

This is a component repair, not a successful 58-slot 12 dB baseline or an
instrument-playback qualification. The existing final-run hold remains.
The shared-queue fixture uses its declared 60 dB high-margin operating point;
it does not measure 12 dB baseline performance.

## Root causes and repairs

The former `beam pattern 3d` materializer could select a requested PMI, or
default to PMI 0, then construct a DFT matrix from array dimensions. That is
not proof of the matrix applied to a particular transmission. The replacement
requires exported actual element-by-layer weights and angular samples with
matching transmission, PRG, symbol-group, layer and matrix-digest identities.
Missing matrices now cause an error instead of a fabricated beam picture.

`commitSharedDataTransmission` captures the immutable prepared contribution
only after the private shared physical owner's ledger proves transmission has
started. DL uses its actual `PDSCHPrecoderBundle.W`; UL uses its actual
`PrecodeInfo.MatrixPorts`. The installed array and physical element ordering
are checked against the waveform columns. This does not claim reception or
completion merely because transmission started.

The existing YAML `outputs.antenna_pattern_samples_enabled` and azimuth/elevation
limits/steps control sampling. They are enabled in the causal 12 dB scenario.
No new scenario-specific RF or beam defaults were introduced.

The outputs are:

- `beamforming/csv/applied_data_precoder_weights.csv`
- `beamforming/csv/applied_data_precoder_patterns.csv`
- A rendered 3D surface using the exported samples, with PNG/CSV hash lineage.

The chart shows one explicitly identified slice of the latest captured data
transmission; its CSV preserves all exported slices. Directivity is in local
array coordinates, before node RF and runtime orientation. It is **not** an
OTA measurement, post-PA radiation pattern, measured array gain or SINR gain.
This image cannot justify adding its peak dBi to the configured 12 dB.

The array method uses the installed element model, including supported
polarization, rather than summing reconstructed isotropic ports. See the
[MathWorks array-pattern contract](https://www.mathworks.com/help/phased/ref/phased.nrrectangularpanelarray.pattern.html)
for directivity and weight conventions. An independent four-element isotropic
far-field check verifies the transmit phase sign at +30 degrees. Scaling all
weights by three changes linear directivity by only 1.24e-14 relative error.
The first test compared dB at numerical nulls and failed; that ill-conditioned
comparison is replaced by the linear-power invariant, retaining the failure log.

MATLAB's default numeric CSV formatting truncated weight coefficients and
prevented exact binary64 digest reconstruction. Coefficients now use 17-digit
decimal strings. The original `_01` CSVs remain historical failed-precision
evidence; `_02` is the first hash-round-tripping DL capture. Negative tests
explicitly reject the old precision-losing CSV rather than accepting a looser hash.

## Timing defect exposed by the UL test

The isolated DL-feedback donor passed `slot-1` as `resolveWaveformGrant`'s frame
argument. Its grant aliases then conflicted with the executed carrier clock.
Correcting only Frame/Slot exposed another namespace boundary: production
timing interprets the control slot as zero-based, while HARQ execution aliases
are one-based. `resolveWaveformGrant` now accepts an explicit zero-based
`ControlAbsoluteSlot`, separate from `Frame` and `Slot`. The donor and shared
DL fixture supply all domains explicitly. Existing callers keep their prior
behavior and are **not** globally certified by this API addition.

The earlier UL attempts failed before PUSCH and remain failed evidence. Neither
the clock guard nor TDD flexible-symbol eligibility was disabled. The follow-up
test first checks explicit control/execution clocks at slots 1, 3, 6 and 21,
then attempts actual two-port SRS/received-DCI/PUSCH/UCI execution. That third
attempt passed all clock checks but failed at `MissingReceivedDLAssignment`:
the isolated DL-feedback donor has actual decoded control bits but does not
yet forward the typed received-control capsule required by the connected QCL
receiver boundary. This is a newly exposed fixture integration failure, not
proof of a successful PUSCH transmission. Do not bypass the capsule assertion
or substitute scheduler/TX knowledge for received control. No UL beam capture
was produced and no two-port UL beam qualification is claimed.

## Focused checks and remaining boundaries

- DL shared physical queue: two started transmissions, four coefficient rows,
  5,402 angular rows; `_02` completed with exit 0. The updated explicit-clock
  `_03` capture and independent phase-convention test also complete with exit 0
  in `applied_data_precoder_dl_03.txt`. Python checks now consume `_03`.
- `tests/test_lls_applied_beam.py`: ten checks pass, covering exact CSV hash
  round-trip, missing/tampered evidence, metadata identity, grid completeness,
  invalid clocks, requested-PMI independence and semantic-audit wiring.
- `tests/test_lls_csv_semantics.py`: exit 0.
- Transmit phase/scale convention assertions pass in the combined UL attempt;
  that process ultimately failed at the separate donor-clock boundary.
- `testExecutedHARQClock`: five slot cases / twenty negative guards pass,
  including SFN wrap. `testResolveWaveformGrantClock`: slots 1, 3, 6 and 21 pass.
  The combined clock/UL process exits 1 at the missing received capsule;
  its following DL capture was consequently not executed. A separate fresh
  DL-only test records the updated fixture without restarting the UL chain.
- Broad chart regression: the aggregate PRACH rate-card defect is repaired
  and its exact 2/4 rate, counts and confidence bounds are checked. The next
  assertion remains open: the operational PRACH peak builder returns an
  observation-index plot while the test expects `sparse_prach_peak_evidence`.
  No assertion was removed to report a blanket pass.

This checkpoint does not qualify SSB applied-weight capture, multi-layer or
multi-PRG angular evidence, Type-D QCL, the full main-scheduler RX/HARQ handoff,
all existing grant-clock callers, or repeated-rendering performance. The
previous CSI non-occasion reservation failure and write restriction remain;
no allocator change or rerun with corrected allocation is claimed here.

The wider mandatory list remains in the
[access/artifact audit](continuous_iq_02_access_artifact_reaudit_20260913.md)
and [received-report handoff audit](dl_received_report_boundary_20260913.md):
special-slot dispatch, downstream access grids, complete measurement-domain
reconciliation, historical snapshot contracts, independent TA/synchronization
perturbations, dynamic DAI and causal UCI/HARQ delivery. Single-carrier
400 MHz/7 GHz, eight layers/two codewords, extended QAM and Keysight playback
remain downstream qualification tasks, not automatic consequences of changing YAML.

Only focused tests were used. No `testAll`, E2E campaign or full 58-slot run
was launched for this checkpoint. Do not promote the old failed run's artifacts
to corrected results or claim full 3GPP compliance from these component checks.

## Reproduce the standalone image

Use a new output directory so historical evidence cannot be overwritten:

```powershell
python tools/render_applied_data_beam.py docs/lls/evidence_20260913/applied_data_precoder_03 docs/lls/evidence_20260913/applied_data_beam_new
python tests/test_lls_applied_beam.py
```

The rendering receipt binds both input CSV hashes, the selected matrix digest
and the output PNG hash. It explicitly states `full_run_qualification: false`.
