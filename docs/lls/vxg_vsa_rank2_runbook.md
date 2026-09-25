# Native 400 MHz rank-2 instrument waveform

**7 GHz / 400 MHz 6G research waveform using 3GPP-derived NR PHY structures.**

This dedicated data-channel experiment is separate from the 5 MHz shared-control
and 400 MHz four-layer/adaptive scenarios. Existing scenarios are unchanged.
It is not a standardized single-carrier FR1 NR configuration, an access/network
demonstration, a statistically qualified BLER campaign, or measured RF performance.
UL 1024-QAM is an experimental 6G research extension, with no invented NR UL MCS.

## Audited reuse and parameter authority

The original rate-0.82 scenario was audited before implementation. One real DL and
one real UL coded slot were generated; the retained log is
`logs/vxg_vsa_existing_audit_20260925_v2.log`. The new focused test executes the same
PHY at the new MCS26 rate and checks actual decoding/noise calibration.

| Parameter | Existing resolved value | New requested/resolved value | Runtime authority / generating function | Verification |
|---|---|---|---|---|
| RF center | 7 GHz | 7 GHz | `frequency.center_frequency_hz`, exported metadata only | Manifest and MAT headers; no digital passband upconversion claim |
| Nominal bandwidth | 400 MHz | 400 MHz research | `frequency.bandwidth_hz` | Separate from measured occupied bandwidth |
| PRB / active SC | 264 / 3168 | Same | `FrameStructureEngine.NRB`, `nrResourceGrid`, `SharedChannelLink.allocation` | Actual grid dimensions and RE indices |
| SCS / FFT / Fs | 120 kHz / 4096 / 491.52 MSa/s | Same | `frame.SCSkHz`, `frame.FFTSize`, `frame.SampleRate_Hz`, `CanonicalOFDMModulator` | Native `nrOFDMModulate` output; Fs=Nfft*SCS |
| CP / duration | Normal / 80 slots | Normal / 10 ms | `nrOFDMModulate`, continuous sample cursor | Actual summed samples, not fixed rounded slot length |
| TDD | 3DL / mixed / 4UL | 5DL / 10D+2G+2U / 2UL | `frame.tdd_common`, `IsDLAllocation`, `IsULAllocation` | Exact timeline, no data in mixed slot |
| Layers / ports | Research DL/UL=2; inactive legacy layer count=1 | Consistent 2 / 2 | `SharedChannelLink.allocation.NumLayers`, `Precoder` | Actual waveform columns, actual layer symbol matrices |
| DL rate | Arbitrary 0.82 | MCS26=948/1024, MCS25=900.5/1024, MCS24=853/1024 | `nrPDSCHMCSTables.QAM1024Table`, per-profile resolved config | Lookup gate; primary YAML rate must match lookup |
| UL rate | Research 0.82 | Research 948/1024 | `research_ul.target_code_rate` | Explicit `research_extension` status |
| TBS / coding | Real nrTBS / NR LDPC | Same primitives, requested rates | `nrTBS`, `resolveCodingLayout`, `attachCRC`, `segmentLDPC`, `ldpcEncode`, `rateMatchLDPC` | Actual TBS, coded length, CRC, bit-exact receiver comparison |
| DMRS | Type1, length1, pos2, additional1, ports0/1 | Retained | `nrPDSCHDMRS` / `nrPUSCHDMRS`, actual indices | Measured allocation table/grid export; no removed pilots |
| Precoder | I/sqrt(2) | Retained | `SharedChannelLink.transmit` | Exact grid and common-port export scaling |
| AWGN | One 30 dB point | 30/35/40 dB for each DL profile | Independent RandStreams; calibrated sample-to-grid transform | Retained clean/noisy IQ and measured data-RE channel SNR |
| Receiver | Received DMRS / MMSE | Retained | `SharedChannelLink.receive` | No transmitted payload input, no perfect CSI |
| Instrument copies | Common endpoint scale | Retained across both ports | `build_lab_waveform_package.export_port` | Full CSV/MAT readback, int16 code readback and error bound |

At MCS26, the focused full-band allocation has TBS **704,904 bits** and coded
length **760,320 bits**. DMRS consumes 3,168 unique occupied RE positions; the
two CDM groups reserve 6,336 RE positions, leaving 38,016 data RE/layer.
This distinction matters: populated DMRS REs and data-unavailable REs are not
the same count. The zero/unused resource-grid class also includes reserved
but unpopulated positions.

Clean TX is generated once per profile and reused by its three SNR receivers.
TX/random-noise generators are separate; the same noise streams are reset for
each MCS comparison. HARQ is off, so every scheduled transport block is unique.
The 10 ms frame has 50 DL and 20 UL TBs/profile and 10 unused mixed slots.

The dedicated runner's SNR authority is `lab_waveform.rx_snr_db`, and its reference
energy is derived from the actual unit-total-power precoder (1/2 per data RE/port).
Inherited legacy `simulation.snr_db`, `simulation.noise_operating_mode` and
`simulation.awgn_reference_re_energy` are not this runner's noise controls.
No thermal-noise or geometry path is executed. Trial noise variances and the
independent native-grid replay verify the actually applied AWGN instead.

## Run from Windows Command Prompt

Requires MATLAB R2024a or later with the used 5G Toolbox capabilities (validated
here using R2026a), plus Python numpy/scipy/pandas/matplotlib/Playwright for packaging.
This is a large full-waveform run; do not run multiple copies on a memory-limited
laptop. A completed package can occupy many GB because exact IQ, noisy IQ, symbols,
CSV, MAT and instrument copies are all retained. No `testAll` is launched here.

Use a new run tag; existing run folders are never overwritten by MATLAB.

One launcher performs MATLAB execution, packaging, browser checks and final
artifact sealing (does not run `testAll`, does not enable RF):

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vxg_vsa_demo.ps1" -RunTag rank2_demo
```

Or execute the individual steps explicitly:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist logs mkdir logs
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\vxg_vsa_rank2_demo.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml','results','rank2_demo'); disp(out);"
python apps\build_lab_waveform_package.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\rank2_demo"
python tests\check_lab_waveform_browser.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\rank2_demo"
python apps\seal_lab_waveform_package.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\rank2_demo"
python apps\vxg_vsa_demo_dashboard.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\rank2_demo"
```

MATLAB reports `PHYCompleted` separately from `PayloadPass`, and returns
`PackagingRequired=true`. `Ok=false` at that intermediate stage is intentional:
an unvalidated/unpackaged waveform is not a complete instrument handoff.
Use the final package receipt for export/dashboard readiness. The final receipt
does not relabel failed CRCs as a passing communications result.

After packaging, open `webgui/index.html` or `demo_package/index.html` offline.
The dashboard shows recorded digital evidence, not live MATLAB or live RF.
Controls: F fullscreen, Space play/pause, Left/Right stage, R restart.
Per-port PSD/CCDF and per-layer constellations are separate measurements.
The initial view is the highest configured SNR (40 dB here), while the campaign
failure badge and all 30/35/40 dB cases remain visible/selectable. Recorded RX
streams retain silence outside that endpoint's scheduled receive slots; they are
slot-gated digital experiments, not continuous noise-floor RF captures.

After copying the complete waveform package to another PC, verify all bytes
without changing any artifact:

```bat
python apps\seal_lab_waveform_package.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\rank2_demo" --verify-only
```

## Output locations and definitions

Everything is under
`results/vxg_vsa/7ghz_400mhz_rank2_1024qam/<run_tag>/`:

- `config/`: resolved YAML/JSON, per-profile runtime JSON, source YAML copies.
- `dl_tx/mcs26/`, `ul_tx/mcs26/` (also mcs25/mcs24): exact raw `.iq64`, raw
  `*_port1/2.csv`, exact complex `*_port1/2.mat`, common-scale `.wiq`, per-port
  `_vsa.mat`, full reference-symbol streams, actual first-slot grid.
- `dl_rx_awgn/<profile>/snr30|35|40/` and UL equivalent: separate actual noisy
  waveforms, exact received MAT, full equalized/error vectors.
- `vsa/<profile>/`: joint two-channel recordings (`Y1`, `Y2`), not port summation.
- `reports/csv/`: trials, timeline, all-case throughput/EVM/PSD summaries,
  per-symbol/PRB measurement populations, every plotted curve/subset.
- `reports/image/`: real-data PNG plots. Unprefixed plot names refer to the primary
  profile/port1/layer1; the complete profile/port/layer images are also retained.
- `keysight/`: instrument handoff; `vsa/`: demodulation configuration.
- `validation/`: schema, export, browser and final package receipts.
- `meta/`: runtime provenance, actual source snapshots/hashes, source commit and
  dirty-tree status. An uncommitted new implementation is not falsely attributed
  to the previous commit alone.
- `webgui/`, `demo_package/`: fully local replay; no duplicated huge IQ binaries.

Raw `.iq64` / `.symbols64` are little-endian interleaved float64 I,Q, not WIQ.
CSV and raw MAT preserve the unnormalized PHY waveform exactly. WIQ and VSA MAT
use a documented common two-port scale per endpoint/profile. The raw MAT stores
that scale. Do not independently normalize the ports in the instrument.

EVM uses actual reference data REs and full error-energy/reference-energy sums.
`ReferenceErrorSINRdB` is explicitly derived from the symbol error vector; it is
not mislabeled an independently estimated SINR. `MeasuredDataREChannelSNRdB`
uses retained clean/noisy grids. Digital power is normalized baseband, not dBm.
Full-frame goodput includes mixed slots and opposite-direction time. Active-slot
rates and the pre-CP/pre-overhead raw modulation-layer rate are separate columns.
PAPR reports full-frame and active-slot mean definitions separately. Native-rate
PAPR is not an oversampled analog crest-factor claim.

## Keysight handoff and later hardware checklist

**PHYSICAL INSTRUMENT CAPABILITY VERIFIED: UNKNOWN** until actual hardware evidence
is supplied. This does not block the digital package.

Collect these read-only results from **each TX/RX instrument**:

1. Full `*IDN?` reply: vendor, exact model, serial number and firmware version.
2. Full `*OPT?` reply: do not provide only the bandwidth option. Preserve the raw
   response so model/firmware-specific option meanings can be checked.
3. Installed frequency range covering the entire 7 GHz carrier and occupied span.
4. TX bandwidth >=500 MHz on **both** used channels and support for playback at
   exactly 491,520,000 samples/s. Record the actual sample-rate setting/readback.
5. Waveform memory >=4,915,200 complex samples **per channel** and two installed RF
   outputs. The WIQ file is 19,660,800 bytes per port (16-bit I plus 16-bit Q).
6. Coherent TX alignment/shared LO/reference/trigger arrangement and measured
   relative timing/phase. Option names alone do not prove actual alignment.
7. RX bandwidth >=500 MHz on each measured path, frequency coverage, and whether
   **two simultaneous coherent RX channels** are actually available. A single
   wideband PXA/UXA input can measure ports separately, but that is not a full
   simultaneous rank-2 RF receiver demonstration.
8. 89600 VSA version and installed demodulation/custom-OFDM/1024-QAM licenses.
   Confirm the desired research UL demodulation is supported; do not assume a
   standard NR UL setup accepts experimental 1024-QAM.
9. Cabled path diagram, attenuation, reference/trigger wiring and safe input/output
   power limits. This software does not enable RF or choose RF output power.
10. Import/readback success for each provided recording, correct channel order,
    native Fs, sample count, common scale and no clipping. Save screenshots/setup
    files plus actual physical measurement exports.

Targets: M9484C VXG (7 GHz, B5X or wider, coherent two-output configuration), with
N5186A as an alternative; N9030B B5X / N9032B / N9042B with appropriate installed
frequency/bandwidth/options and coherent capture arrangement. These are target
requirements, **not verified installed capabilities**.

Keysight's current documents list M9484C B5X at 500 MHz / 600 MSa/s; the current
N5186A datasheet lists B5X at 500 MHz / 625 MSa/s. The proposed 491.52 MSa/s fits
those advertised maxima, but actual playback and channel options still need checking.

VSA recording headers use documented `Y` for one channel and `Y1`/`Y2` for two.
`XDelta=1/491520000`, `InputCenter=7e9`, complex zoom. The native-rate-compatible
`InputSpan` is **384 MHz**, because 491.52/384=1.28. It contains the 380.16 MHz active
subcarrier span. It is not a redefinition of the nominal 400 MHz research carrier.
Using a 400 MHz header span with this sample rate would trigger VSA resampling.
Export performs no resampling; instrument-internal processing remains unverified.

For playback, load the two **TX** WIQ files of the same direction and profile into
two channels, select signed 16-bit little-endian interleaved I/Q, and set Fs to
491.52 MSa/s and RF center to 7 GHz. Do not use `*_rx_awgn` files as clean TX.
Preserve the supplied common scaling and simultaneous start. RF output power,
attenuation, cabling and alignment must be checked before enabling RF; no script
here enables RF. DL and UL packages are separate waveform experiments, not four
streams combined into two outputs.

For offline VSA recall, use `vsa/<profile>/dl_tx_2ch_vsa.mat` or the UL counterpart;
single-port VSA MATs are also supplied. `vsa_demod_config.json` is an engineering
setup description, **not** a proprietary Keysight setup/macro file. Importing the
IQ recording does not itself configure or verify NR/custom-OFDM demodulation.
Use the actual installed VSA application's supported setup interface and retain
its setup/measurement exports. Do not force a standard FR1/UL profile to pretend
that this research waveform is a standardized combination.

Primary sources:

- [M9484C datasheet](https://www.keysight.com/us/en/assets/3122-1445/data-sheets/M9484C-VXG-and-V3080A.pdf)
- [N5186A datasheet](https://www.keysight.com/zz/en/assets/3123-1690/data-sheets/N5186A-MXG.pdf)
- [N9030B specifications](https://www.keysight.com/content/dam/keysight/en/doc/ungate/technical-specifications/9018-04934.pdf)
- [VSA data headers](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/data_header.htm)
- [VSA InputSpan / resampling](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/inputspan.htm)
- [MathWorks DL MCS table authority](https://www.mathworks.com/help/5g/ref/nrpdschmcstables.html)

## Later physical measurement import

`apps/physical_measurement.schema.json` defines the identity/units/scope contract.
Place actual, externally measured `physical_measurement.json` in the run folder.
The dashboard never substitutes digital data when that file is absent.
Required scope identifies per-layer data REs or per-port full-frame measurements.
Do not compare normalized digital power with dBm, or active-burst PAPR with
full-frame PAPR. Physical import requires new validation and packaging receipts;
do not modify an already sealed exhibition package and retain its old hashes.

PTRS remains disabled for this clean baseline. Oscillator phase noise/CPE and
PTRS belong in a separately configured later RF experiment, not a silent change
to the clean reference waveform.
