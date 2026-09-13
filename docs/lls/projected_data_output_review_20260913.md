# Projected data output review — 2026-09-13

## Scope and provenance

This review covers completed component executions of MATLAB source revision
`ff00f0c1`, not a full run, an independent Monte Carlo sweep, or RF conformance.
The source remained unchanged throughout the focused batch. All five tests
passed and the process returned exit 0:

| Test | Seconds |
| --- | ---: |
| Geometry master runtime authority | 50.76 |
| Baseline DL TDRA budget | 21.18 |
| Shared PUSCH late UCI delivery | 226.32 |
| Shared PUSCH late CSI delivery | 189.15 |
| Executed DL data precoder evidence | 70.11 |

The terminal log is retained in
`evidence_20260913/projected_ul_late_uci_capture_01/focused_execution.log`.

## Retained evidence and independent checks

- `projected_ul_late_uci_capture_01`: an unchanged copy of the completed
  `tpe948456c_c17b_448e_b898_4976ed1e6683` temporary capture. All 25 original
  files were compared byte-for-byte by SHA256 after copying. The original
  partial-snapshot manifest binds 21 artifact files and two source CSVs;
  every declared hash matched. Its original paths and producer hashes were
  preserved, not rewritten to impersonate a new run. Long Windows paths in
  the snapshot were checked with PowerShell after ordinary Python path
  access hit the Windows long-path limitation.
- `projected_ul_late_uci_transport_01`: the original completed shared
  SRS/PUSCH component output, including channel MAT files and segment CSVs.
  The PUSCH row's linked channel MAT and segment CSV hashes were independently
  recomputed and matched their declared values. The MATLAB fixture also
  validated the channel observation structure against the actual receive
  branch count and transmitted physical element count.
- `projected_dl_matrix_capture_01`: four weight rows and 5,402 angular rows
  from two actually started DL transmissions. The existing Python beam
  validator verified every matrix digest, identity, layer and complete
  angular grid before rendering the representative view in
  `projected_dl_matrix_review_01/applied_data_beam.png`. Its receipt binds
  both CSV hashes and the PNG hash. This is pre-node-RF computed local-array
  directivity, not a measured OTA pattern or a received-DL qualification.

All directories above are under `docs/lls/evidence_20260913`.

The UL capture contains all 3,522 paired QPSK layer symbols. Independently
recomputing `sqrt(sum(abs(received-reference)^2)/sum(abs(reference)^2))`
from the CSV gives **0.1284814718498691 percent RMS EVM**. It agrees with
the trial within 1e-12 in linear EVM. The raw and reported equalized values
are identical; no reporter payload-derived gain/phase fit was applied.
The symbol/layer/subcarrier coordinates are unique. Every one of the
12 per-OFDM-symbol EVM buckets was independently recomputed, with its sample
count and RMS EVM matching the derived CSV.

The actual PUSCH trial has 2,152 TB bits, 2,152 compared bits, zero bit errors,
CRC pass and decoded HARQ bits `1|0`, matching the expected bits. Both
feedback rows retain transmission slot 10 and delivery slot 11, with zero
false ACK/NACK flags and no standalone PUCCH execution. The isolated source
DL receptions are component inputs; they were not transmitted by this
shared UL waveform owner.

## Visual review and remaining reporting defect

All nine UL checkpoint PNGs were visually inspected, as was the new DL beam
PNG. The plots show actual retained observations and declare partial scope;
one successful transport block is not a BLER curve. The constellation preview
declares its 450-point display limit while retaining all 3,522 CSV rows.
The precoder matrix graphic correctly limits its MATCH claim to recorded
consistency, not spatial correctness or optimality. The port-count plot
shows the native logical precoder's one port, not the two physical waveform
columns; the original trial explicitly labels `PrecoderDigestDomain=logical_port`.

**Open defect: limited-SINR provenance is lost in the BLER chart dataset and
not visible on the SINR-axis PNGs.** In this capture:

- `PostEqSINRRawEqualizer_dB = 60.0822250935111`;
- `PostEqSINR_dB = 45`;
- `PostEqSINRValueStatus = OK_dynamic_range_limited`;
- the trial explains that the raw estimate was limited to the maximum
  trusted 45 dB scheduling input.

`throughput_vs_sinr.csv` preserves `sinr_value_status`, but
`pusch_bler_vs_measured_sinr.csv` records only `value_status=available`.
Both plotted axes currently say measured SINR without exposing the limit.
The source is `apps/lls_radio_measurement_plots.py:_measured_sinr`, which
returns only value/field/source; its generic chart record does not carry the
source value status or limiting reason. The throughput renderer preserves
status in CSV but does not display that status in its plot.

Required follow-up: retain the selected source field's status and limiting
reason in derived CSVs and make capped scheduling-input coordinates explicit
in the corresponding plots. Do not replace them with configured SNR, remove
the trusted-range guard, or relabel EVM-derived values as measured SINR.
The original defective snapshot remains unchanged as reproduction evidence.
Plotting source was not edited while active MATLAB suites may invoke it.

## Qualification boundaries

The full primary-link CSV auditor was also run directly against the standalone
`received_pusch.csv`. It did **not** pass: missing canonical fields include
UEID, Rank, RawBER, RunID and ExecutionID, and full-run identity checks also
require RunTag and ConfigHash. The BER arithmetic check fails because the
canonical RawBER field is absent, not because the observed zero-error count
contradicts itself. This fixture bypasses the campaign finalizer; no IDs or
canonical values were backfilled after execution. It must not be promoted
as a qualified campaign table.

The new revision's broader guard batch remains live, with full `testAll`
queued after it. Main and receiver full suites are still on their earlier
unchanged revisions. No full-suite success, merge readiness, production
readiness, long impairment campaign, or broad 3GPP feature coverage is claimed.
The result-integrity skill guided preserving source artifacts, independently
checking derived values, and retaining the failed/partial qualification scope.
