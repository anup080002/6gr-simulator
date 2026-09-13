# Baseline-array PUCCH noise/RF check

This checkpoint evaluates the configured Format-0 detector using independent
noise samples and the 12 dB profile's actual two-element gNB receive layout
and retained RX RF implementation. It is **not** a completed 12 dB baseline,
a signal-present ACK-miss test, or 3GPP conformance qualification.

## Execution and configuration

`simulator/configs/validation/pucch_baseline_dtx.yaml` owns the diagnostic
sample count, bit layouts, endpoint identities and source scenario. The
source scenario remains the continuous-IQ 58-slot configured-12-dB YAML,
including the approved two-port SRS/PUSCH configuration. No production
threshold was tuned during this experiment.

`testPUCCHBaselineNoiseRF` resolves that scenario and obtains the same
physical element counts as the shared waveform owner. It executes a
receiver-noise/RF component stream, advancing the owner through all intervening
slots and scoring only complete configured UL slots. There are 512 scored
occasions; each is decoded with one-bit and two-bit expected HARQ layouts.
Those two layouts share IQ and are not separate independent repetitions.

The physical owner injects noise once using its configured occupied-RE
Es/N0 calibration and retained receiver-specific RNG, then executes actual
retained RX RF once. No link is registered in this receiver-only experiment:
there is no transmitted PUCCH, CDL/O2I gain, applied beam or ACK-miss evidence
to invent. The slot window is prescribed, not acquired synchronization or
measured timing advance. The component calls `nrPUCCHDecode` directly; it is
not a replacement for the main receiver/controller integration check.

All scored post-RF IQ is preserved in `noise_observations.mat`, with CSV
sample offsets, absolute slots, noise seed/variance, branch count, RF stage
count, threshold/source and whole-file SHA-256. `configuration.mat` retains
the resolved scenario and runtime configuration; `source_provenance.json`
records the base commit and execution-source hashes.

## Results

The 512-occasion component process reached terminal exit 0, meaning execution
and internal checks completed, **not that detector performance passed**.
Evidence is under `docs/lls/evidence_20260913/pucch_baseline_noise_rf_01`.

| HARQ layout | Occasions | Any false detections | False ACK bits / positions | Observed bit fraction |
| --- | ---: | ---: | ---: | ---: |
| One bit | 512 | 8 | 2 / 512 | 0.390625% |
| Two bits | 512 | 16 | 12 / 1024 | **1.171875%** |

The two-bit fraction exceeds the 1% reference. The one-bit result is below
it empirically, but its 95% one-sided upper bound under the independent-
occasion assumption is about 1.2245%, so it does not establish the limit.
The corresponding two-bit any-ACK occasion upper bound is about 3.2904%.
No seed selection, early acceptance, production-threshold edit or PHY rerun
was used to improve those numbers.

The installed Format-0 decoder takes the maximum normalized correlation
over all candidate payload sequences. Two HARQ bits introduce four ACK/NACK
candidates instead of two, while this profile uses the same 0.42 threshold.
The observed right-shifted noise-only maximum-correlation distribution and
increased detections are consistent with that larger search space. The
implementation default is not a baseline performance guarantee. Receiver
policy must be qualified across payload length, symbols and receive branches,
with independent false-ACK and signal-present missed-ACK samples; increasing
the threshold without testing missed ACKs is not a completed repair.

An independent Python/h5py/SciPy audit checked all 1,024 CSV rows, the whole
IQ SHA-256, all 3,932,160 x 2 complex samples for finiteness, paired observation
identity, sample bounds, configured 12 dB calibration, detector decisions,
all counts and the statistical calculations. It passed. The actual RX
replay records one executed RF stage; absent TX/link stages are not counted
as executed. These checks validate this diagnostic's evidence, not the old
run's full measurement set.

The result denominator is false ACK bits divided by DTX occasions times
configured HARQ bits, not every false detection. The 1% reference is
[TS 38.104 section 8.3.1](https://www.etsi.org/deliver/etsi_ts/138100_138199/138104/18.10.00_60/ts_138104v181000p.pdf).
The stored one-sided statistical bound applies to occasions containing any
false ACK, under an explicitly declared independent-occasion assumption.
That is a conservative bound for the bit fraction, but retained RF can
introduce outcome dependence; it is not an unconditional conformance claim.
The 0.42 threshold is a [receiver implementation default](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html),
not a universal 3GPP constant.

## Remaining execution gates

1. Signal-present ACK-miss/NACK-to-ACK behavior with actual shared channel,
   RF, prior received UL timing, configured power and both HARQ layouts.
2. Main missed-DCI receive-only/DTX observations and the combined shared
   retransmission / retained-ACK / UCI sequence.
3. CSI-RS non-occasion PDSCH reservation. A normal edit to
   `+sixgr/+phy/+grid/allocREsPDSCH.m` was refused again this turn; that source
   remains unchanged. No alternate writer or permission change was used.
4. Special-slot TDRA/K1 dispatch, timing advance, TAG and independent
   DL/UL synchronization checks.
5. Remaining measurement-domain, SSB beam/QCL and phase artifact producers,
   followed by complete terminal CSV/PNG/IQ/publication qualification.

The [access/artifact audit](continuous_iq_02_access_artifact_reaudit_20260913.md)
explains the old slot-31 first data from actual PBCH/PRACH/RRC/SRS events.
It is a configured radio calendar, not CPU processing time or a universal
30-slot requirement. Special-slot scheduling remains separately unqualified.
See the [spatial audit](continuous_iq_02_spatial_reaudit_20260912.md) for the
measured old-weight power difference; it does not prove every SINR formula.
Eight-layer/high-QAM/400 MHz operation and Keysight playback remain later
qualification stages, not guaranteed by editable YAML alone.

No full 58-slot run, `testAll`, E2E campaign or push is authorized by this
component result. The main run remains held.

## Focused receipts

Under `docs/lls/evidence_20260913`:

- `pucch_baseline_noise_rf_tests_01.txt`: terminal exit 0; all planned
  observations complete, with the two-bit performance failure retained.
- `pucch_baseline_noise_rf_render_01.txt`: exit 1 after producing the first
  correct PNG. The command-line negative check used character addition for
  its temporary filename, failing before calling the intended assertion.
- `pucch_baseline_noise_rf_render_02.txt`: terminal exit 0. The dedicated
  `testPUCCHNoiseAuditRendering` renders only the existing CSVs and verifies
  rejection of inconsistent false-ACK counts. No noise or PHY rerun.
- `pucch_baseline_noise_rf_01/independent_audit.json`: independent whole-IQ,
  count and statistic audit.

Both render files and the failed command receipt are preserved. Visual
inspection confirmed readable axes, the configured threshold and the two-bit
bar above the reference limit. No production PHY source changed this turn;
the new YAML diagnostic, test, renderer and evidence expose an open defect.

## Reproduction

Use a new output directory; the test refuses to overwrite an existing one.

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); assert(testPUCCHBaselineNoiseRF('qualification_working/pucch_baseline_noise_rf'));" -logfile qualification_working/pucch_baseline_noise_rf.txt
```
