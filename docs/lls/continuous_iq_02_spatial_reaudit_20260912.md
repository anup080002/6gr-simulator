# `_02` spatial-power re-audit and approved two-port UL repair

This supplements `continuous_iq_02_terminal_repairs_20260912.md`. It does not
rewrite or requalify the old execution. The user approved two logical SRS and
PUSCH ports, rank one, with measured TPMI selection for the next 12 dB run.

## Baseline evidence and root causes

- The exhaustive audit parsed 1,013 CSV files / 1,300,260 rows from `_02`;
  another 35 CSV files belong to nested sweeps and were excluded deliberately.
  There were zero CSV parse/structural failures and zero decode failures in
  all 292 PNGs. All 292 source-CSV/image SHA-256 pairs also matched independently.
- The 14 header-only CSVs comprise six disabled contracts and eight contracted
  zero-event tables. These are not invented observations or failed decoders.
- Two required columns were unavailable: the DL and UL copies of
  `RuntimeChannelAlignmentLookaheadSamples`. The runtime already had the
  actual alignment evidence; shared-observation flattening omitted it. The
  repair copies only executed values that agree across contributing segments.
  The strict audit now rejects missing required primary values as well as
  uncontracted files. Old `_02` retains its missing fields and fails this gate.
- Two previously uncontracted CSVs were the continuous-IQ manifest and segment
  table. The new auditor checks actual finite binary samples, endpoint/port
  identity, gap-free clocks, byte hashes, MATLAB waveform hashes, RF output
  hashes, active samples, peak component and mean composite power. All four
  old port files and 116 endpoint segments passed. It uses only Python's
  standard library; an initial NumPy import broke MATLAB's plot publisher
  and was removed, not bypassed.
- The component cards selected three primary in-path artifacts and hid the
  separate derived plot contracts. The repair exposes 584 hash-verified
  derived artifacts (292 CSV/PNG pairs) separately from primary evidence.
  Plot presence never becomes a PHY PASS verdict. Unavailable L2/L3/system
  component evidence is not manufactured. A running GUI must load the new
  code before this change is visible; no live-browser deployment is claimed.

The immutable exhaustive audit is retained in
`qualification_working/continuous_iq_02_full_reaudit_20260912/`. Its summary
predates the new IQ-contract checker; do not edit its original verdict.

## What explains the DL/UL SINR gap?

Both directions injected grid noise variance 0.0630957344480193 with FFT
noise gain 512. Same frequency and a reciprocal TDD propagation channel do
not imply equal effective gain after different transmit/receive weights.

`tools/auditLLS12dBSpatialBudget.m` matched the actual matrix and captured
channel hashes, then evaluated both weights on the same frozen channel:

| Captured channel | DL branch-summed power gain | UL branch-summed power gain | Difference |
| --- | ---: | ---: | ---: |
| DL slot 31 | 7.627609 dB | 1.165649 dB | 6.461960 dB |
| UL slot 35 | 7.571930 dB | 1.165776 dB | 6.406154 dB |

The old DL physical vector was approximately `[1;0]`; the old single logical
UL port mapped to `[1;1]/sqrt(2)`. Both have unit total power. This offline
spatial-power diagnostic explains most of the approximately 6.96 dB reported
SINR difference, but is **not** a reconstruction of measured receiver SINR.
The remaining estimator/equalizer/time-domain difference is not independently
decomposed. No noise rescaling or forced SINR equality was added.

The old CSI reference SINR additionally averaged different logical ports and
receive branches. It was not the same quantity as SS-SINR or selected-PMI
CSI scheduling quality. The repair measures port 3000 reference-RE channel
power and received disturbance per branch, reports the maximum branch, and
exports the power/noise/port/CDM/branch evidence. This follows the measurement
scope in [TS 38.215, section 5.1.6](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.02.00_60/ts_138215v180200p.pdf).
The old all-port estimate remains an explicitly named diagnostic. The CSI
scheduling objective remains separately labeled and is not replaced by this
reference measurement. Low-SNR estimator bias and independent vendor agreement
have not been qualified by these bounded tests.

## YAML and UL control changes

The continuous-IQ scenario now explicitly configures:

```yaml
reference_signals:
  srs_ports: 2
  srs:
    num_ports: 2
    port_set: [0, 1]
pusch:
  num_antenna_ports: 2
control:
  ul_precoding:
    num_ports: 2
    max_rank: 1
    codebook_subset: fullyAndPartialAndNonCoherent
    transmission_scheme: codebook
    full_power_mode: not_configured
```

Logical sounding/codebook ports are not DM-RS layer count. PUSCH stays rank
one with one scheduled DM-RS port. The parent one-port scenarios are unchanged.
The YAML catalog registers the new optional control structure. The scheduled
DCI context rejects inconsistent SRS/PUSCH ports, rank or transform precoding.

The control audit found a separate legacy defect: DCI 0_1 always used six
bits and `TPMI + 16*(rank-1)`. The new explicit two-port context uses
[TS 38.212 tables 7.3.1.1.2-4/-5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf),
including table-dependent width, rank/TPMI mapping and reserved-codepoint
rejection. The approved rank-one/full-subset case uses three bits. The
scheduler, standalone builder and semantic parser share this configured
table. This does not qualify other legacy DCI fields or 4/8-port mappings;
unconfigured legacy precoding is explicitly marked not table-qualified.

## Verification and remaining gate

Focused validation includes actual two-port SRS at 12 dB on an independent
known channel selecting opposing-phase TPMI 3, unit total precoder power,
PF/RR propagation of nonzero TPMIs, codebook orientation, received CSI power,
SS measurement, TDD reciprocity, noise domains, QCL timing and IQ recording.
The Python audit/plot/dashboard regression passed 217 tests. Receipts are
retained under `docs/lls/evidence_20260912/`.

The shared 11-slot SRS/DCI/PUSCH/UCI fixture passed again **after** the
DCI-layout repair. Its received payload preserves the measured TPMI/rank;
actual PUSCH CRC and HARQ-ACK UCI match, with practical timing checked against
the received stream. Its persisted `received_pusch.csv` reports applied
TPMI 3, two logical ports, CRC=1, arrival offset 90 samples and residual timing
error zero. The exact row is copied to
`evidence_20260912/two_port_shared_fixture_received_pusch.csv`.
This is a high-margin component test, not the final
58-slot 12 dB performance run. Independent table mapping and five existing
DCI regressions passed. The production receiver's normalized-Es/N0 CSI test
also passed: finite SINR and relative power, preserved branch numerator/
denominator evidence, and no invented absolute dBm.
Initial partial-YAML/schema registration errors were detected before PHY
execution; no failed attempt is represented as a successful run.

Before the final 58-slot run:

1. Corrected two-port shared-clock regression: completed, focused PASS.
2. Close the active DCI field-context audit, particularly SRI presence/width,
   DM-RS antenna-port indication and other inherited fixed widths. The
   precoding-field repair alone is not whole-DCI conformance.
3. Preserve focused receipts, commit/push source and update the local bundle.
4. Run one fresh configured-12-dB validation only after these known mandatory
   blockers are closed; audit received PDCCH evidence, PMI/TPMI matrix identity,
   QCL timing consumption, CSI domains, alignment fields and IQ/PNG hashes.

The `_03` launch was stopped during initialization at the user's request to
finish this audit first. Its logs remain local. No new full 58-slot execution
has been used to validate this repair set. `_02` remains functional-only,
not production/FRC/hardware/statistical qualification. No `testAll` or E2E
campaign was launched. Single-carrier 400 MHz/7 GHz and higher QAM remain
subsequent work, not silently enabled in this 5 MHz baseline.

Focused reproduction commands (not `testAll`):

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testULPrecodingDCIField); assert(testTwoPortULYAMLAndSRS); assert(testCSIRSRPPhysicalMeasurement(true)); assert(testSharedPUSCHChannelArtifacts('TDD',true,false,false,true));"
python -m pytest tests/test_lls_continuous_iq_audit.py tests/test_lls_runtime_visualization_evidence.py tests/test_lls_realtime_component_dashboard.py tests/test_lls_csv_semantics.py tests/test_lls_radio_measurement_plots.py tests/test_audit_lls_run_exhaustive.py -q
```
