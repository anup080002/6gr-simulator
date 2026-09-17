# Research IQ handoff: 7 GHz / 400 MHz / TDD / 1024-QAM

## Available verified package

### Selected rate-0.82 capture: ten milliseconds

The highest passing tested rate for the fixed two-layer configuration now
has a complete IQ package from clean commit
`6be2985f9f6b78b4349c91ab71da81f32e25f7c8`:

`logs/research_selected_iq_6be2985f_20260917/execution/lls/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq/committed_source`

All 30 DL and 40 UL transport blocks passed CRC and exact-payload checks.
Goodput over the complete 10 ms TDD interval is **1.868280 Gbit/s DL** and
**2.491040 Gbit/s UL**. Every TX/RX port stream contains 4,915,200 samples
at 491.52 Msamples/s. The package contains 58 files / 804,357,388 bytes;
large IQ files remain local under `logs`, not in Git. The source scenario
is `simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml`.

This is best observed among rates 0.75, 0.80, 0.82, 0.85 and 0.90 with the
same link budget and configuration, not a global throughput optimum. The
capture repeats the same seed; it is not an independent reliability trial.
Rates 0.85 and 0.90 produced real failures retained in the comparison.

The native capture and file readback passed. An independent audit verified
20 artifact hashes, all stream lengths, MAT container headers, TDD silence,
RX noise presence and delivered-bit accounting. Small receipts and the
read-only audit script are in `evidence_20260917/research_selected_iq_10ms`.
Final-source full regression is running; actual Keysight import is not
verified. This remains an optional research experiment, not qualified NR
or standardized 6G behavior.

The original auxiliary CSV check failed because MATLAB guessed underscore
as delimiter. A subsequent read-only MATLAB check passed with explicit CSV
options (exit 0). Both receipts are retained. Read the manifest using:

```matlab
iq = readtable(fullfile(runFolder,'waveform','iq_manifest.csv'), ...
    'Delimiter',',','ReadVariableNames',true,'TextType','string');
```

### Earlier rate-0.75 package: one millisecond

The clean-source, one-ms lab run from
`3f0ed1e4ae7debe3d4136c733fd2dcce4d2e4b40` is preserved at:

`logs/checkpoint_3f0ed1e4_validation_20260917/execution/lls/lls_7ghz_400mhz_1024qam_tdd_30db/committed_source`

This package passed MATLAB exact-IQ and quantized-file readback, not a
Keysight application or instrument test. Its measured payload result was
3/3 DL and 4/4 UL TBs correct. The code-rate comparison runs separately;
this package is not yet a best-throughput selection.

A separate read-only PowerShell audit verified all 20 unique file hashes,
all eight WIQ byte/sample counts, the contiguous TDD clock and unique-TB
goodput accounting. It also checked exact TX silence over 1,105,792
inactive complex samples across ports and nonzero RX noise in all 18
inactive port/slot intervals. The receipt is
`evidence_20260917/research_tdd_link_committed_30db/independent_export_audit.json`.
This audit did not reexecute PHY decoding or Keysight import.

## Choose the correct capture point

| Directory | Meaning |
| --- | --- |
| `waveform/dl_tx` | Clean, pre-channel DL transmit samples |
| `waveform/ul_tx` | Clean, pre-channel UL transmit samples |
| `waveform/dl_rx` | DL receiver samples including the configured AWGN |
| `waveform/ul_rx` | UL receiver samples including the configured AWGN |

Each directory contains exact `raw_iq.mat`, per-port `port_N_vsa.mat`, and
little-endian interleaved signed-int16 `port_N.wiq`. The VSA and WIQ copies
are normalized using one common scale for the endpoint, preserving relative
port amplitudes and phases. The scale and SHA256 values are in
`waveform/iq_manifest.csv`. The raw MAT is the amplitude authority; the
normalized copies are not calibrated volts or dBm. Do not add AWGN to the
RX package again when reproducing the existing simulated receive condition.

## Recording import versus demodulation

In 89600 VSA, use **File > Recall > Recall Recording** and select the
MATLAB recording format for a `port_N_vsa.mat` file. Keysight documents
MATLAB v5/v7 recording support. The emitted fields are `Y`,
`XDelta=1/491520000`, `InputCenter=7000000000`, `InputZoom=1` and `XDomain=2`.
These describe complex time-domain samples, not decoded symbol data.
See [recording recall](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/saving_and_recalling_recordings.htm),
[MAT support](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/matlab.htm),
and [header definitions](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/data_header.htm).

The files currently contain one VSA input channel each. Do not treat one
port as a complete two-layer MIMO measurement, sum ports, or concatenate
ports in time. A synchronized multi-channel setup is needed for a joint
two-port analysis; its import procedure depends on the installed Keysight
application/version. The exact raw MAT retains both ports on the same
sample clock.

Importing a recording does not configure the OFDM demodulator. This is a
custom research carrier, not a claimed standard 6G preset. The configuration
uses 120 kHz SCS, FFT 4096, 264 PRBs (380.16 MHz occupied), normal CP,
two layers, and the TDD pattern saved in `meta/resolved_config.yaml`.
Use the captured slot/sample timeline; do not assume a single constant CP
length. DMRS geometry, identities and port sets are in `research_dl` and
`research_ul`. No SSB/PBCH/PRACH, PDCCH/PUCCH, HARQ or CSI feedback ran.

Keysight documents a Custom OFDM option and a `Qam1024` modulation value.
That establishes a possible analysis path, not compatibility with this
specific resource map, MIMO mode, licensing or installation. No `.setx`
demodulator setup or hardware download has been validated.
See [Custom OFDM option](https://helpfiles.keysight.com/csg/89600B/Webhelp/content/about_optional_features.htm)
and [modulation enumeration](https://helpfiles.keysight.com/csg/89600B/WebHelp-apiref/Agilent.SA.Vsa.CustomOfdm.Interfaces~Agilent.SA.Vsa.CustomOfdm.ModulationFormat.html).

## Evidence to return after import

Keep the application name/version, enabled analysis options, selected file
and SHA256, detected sample rate/center frequency/sample count, import error
text if any, and saved measurement setup. For demodulation discrepancies,
include synchronization settings, resource/DMRS map, per-port settings,
EVM normalization and measurement interval. Do not compare full-record
silence-inclusive power to active-data-RE SNR without accounting for TDD
and pilot overhead. The configured 30 dB is an AWGN reference SNR, not a
forced measured post-equalization SINR.
