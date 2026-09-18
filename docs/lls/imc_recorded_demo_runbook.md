# India Mobile Congress: recorded link performance and RF playback

## Recommended first exhibit

Use two clearly separated views. Screen 1 shows instrument waveform analysis;
screen 2 shows the offline recorded PHY/decoder dashboard. Suggested public title:
**400 MHz, four-stream research waveform demonstration — recorded DL/UL performance**.
Do not label the present recording as 13 Gbit/s, a >6 Gbit/s DL pass, a global
peak, a live RF throughput test, or standardized 6G conformance.

The retained recording delivered 5.926550 Gbit/s DL and 2.396846 Gbit/s UL over
10.5 ms. All 49 DL and 20 UL unique payloads were recovered. Initial BLER was
2.0408% DL / 0% UL; residual delivery BLER was 0% in both directions. It is
one short observation, not sustained-rate or statistical reliability proof.

| View | Show | Required label |
| --- | --- | --- |
| Recorded dashboard | Unique goodput, first/residual BLER, EVM, reference-error SINR, QAM/rank/rate, CRC/HARQ timeline | Recorded simulator results — not live RF |
| VSA offline recall | Recorded TX or simulated noisy RX IQ, spectrum/time traces, demodulation only after configuration is verified | Offline IQ replay; simulated receive condition for RX files |
| Cabled VXG → analyzer | Actual acquired spectrum, power, EVM if the custom waveform demodulator is configured | RF playback measurement; not live decoder goodput |
| Future live decoder display | CRC, unique delivered TBs, BLER and goodput derived from actual acquired RF samples | Only after acquisition, decoding and accounting are implemented/verified |

The current replay has no live RF connection or synchronization to a VSG
trigger. Its timeline can be slowed for audience explanation; this does not
alter sample time or throughput. It stops at the end rather than silently
turning repeated data into new trials. The slot-64 initial CRC failure and
slot-68 retransmission recovery remain visible. No invented constellation or
synthetic spectrum is drawn: use the actual IQ in VSA for those views.

## Implemented package

- `apps/build_recorded_demo.py`: standard-library offline HTML builder.
  It fails on incomplete/unaccepted runs, proxy rows, inconsistent summary or
  delivery accounting, noncausal feedback, missing layer data, source/IQ hash
  failures or IQ timing/port inconsistencies. It preserves all input artifacts.
- `apps/recorded_demo.html`: self-contained, full-screen-capable browser replay;
  no web server, CDN, login, MATLAB or network is needed to display it.
- `apps/package_recorded_vsa.py`: NumPy/SciPy packaging of exact existing
  normalized port arrays into joint MAT recordings. For four channels, the
  fields are `Y1_4` through `Y4_4`, with shared XDelta/InputCenter and no sample
  changes. File readback is checked; actual instrument import is not claimed.
- Generated audit JSON records source hashes and the rendered HTML hash.
  These are consistency/provenance checks, not a third-party signed certificate.
- Generated `instrument_handoff.csv` lists portable, run-relative IQ paths,
  sample counts, rates, common endpoint scaling, quantization bounds and hashes.

## Exact local commands

Run from the repository root in Windows PowerShell. Python 3.9+ is required
for building; NumPy/SciPy are additionally required for joint VSA packaging.
These packages are present in the current laptop's Python environment.
Use your environment's package manager if missing; no automatic installation
or instrument connection is performed. A copied `index.html` needs only a browser.

```powershell
$ErrorActionPreference = 'Stop'
$runFolder = 'results/lls/lls_7ghz_400mhz_adaptive_dl5_ul2_30db/committed_ef799fcb'
$demoTag = 'imc_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff')
$demoFolder = 'results/demos/' + $demoTag
$demoLogs = 'logs/' + $demoTag
New-Item -ItemType Directory -Path $demoLogs -ErrorAction Stop | Out-Null
python apps/build_recorded_demo.py $runFolder $demoFolder 2>&1 | Tee-Object -FilePath "$demoLogs/dashboard.log"
if ($LASTEXITCODE -ne 0) { throw 'Dashboard evidence checks failed; preserve the log.' }
python apps/package_recorded_vsa.py $runFolder ($demoFolder + '_vsa') 2>&1 | Tee-Object -FilePath "$demoLogs/vsa_packaging.log"
if ($LASTEXITCODE -ne 0) { throw 'VSA packaging failed; preserve the log and partial output.' }
Start-Process -FilePath (Join-Path (Resolve-Path $demoFolder).Path 'index.html')
```

This last command intentionally opens the visible demo the operator requested.
Move that browser to the second screen and press **Full screen** or F11. The
generator never overwrites an existing demo directory. On another computer,
copy the original completed run folder and set `$runFolder` to that location,
or create a new completed recording using the scenario command in the root
README. Old absolute IQ paths are relocated within the copied run only.

Keep these together for transport/backup:

1. Original completed run folder, including all four `waveform/*` endpoints,
   reports, HARQ ledger, manifest and source/config snapshots.
2. Generated dashboard folder (`index.html`, `replay_data.json`,
   `artifact_audit.json`, `instrument_handoff.csv`).
3. Generated joint-VSA folder and `vsa_recordings.json`.
4. Execution/build logs. Large IQ remains local, not committed to GitHub.

## Your instruments: M9484C VXG, N9042B UXA, N9032B PXA

The model families offer enough bandwidth for this waveform, but **installed
options are authoritative**. The N9042B configuration guide lists 1 GHz and
higher analysis-bandwidth options; the N9032B product page lists options up
to 2 GHz. The M9484C supports up to four synchronized, phase-coherent outputs
and up to 2.5 GHz modulation bandwidth per channel. None of this establishes
which options are installed on the exhibition units.

Verify before connecting RF:

- M9484C channel count and frequency option covering 7 GHz (a 6 GHz-only
  option is insufficient); modulation bandwidth, waveform memory and software.
- Analyzer installed bandwidth >=400 MHz, frequency coverage, input limits,
  firmware and the licensed 89600 VSA/custom OFDM or relevant demodulator.
- Number of simultaneous receive channels and supported coherent capture
  arrangement. One UXA plus one PXA does not, by itself, establish four
  simultaneous phase-coherent receive channels. Sequential port captures
  must not be labeled simultaneous four-layer RF reception.
- Common timing, suitable phase-coherence arrangement and calibrated path
  delay/gain/phase for a genuine multi-channel RF demonstration. A shared
  frequency reference alone does not establish phase coherence.
- Cabled/attenuated versus authorized OTA operation. Cabled operation is
  recommended for the first booth rehearsal. Keep RF off until the lab
  operator verifies attenuation, connector ratings, analyzer input protection
  and the power budget. Normalized IQ does not specify an absolute dBm level.

Read-only inventory queries `*IDN?` and `*OPT?`, or Instrument Information
screenshots, plus VSA version/license details, are useful inputs for the final
instrument-specific setup. No SCPI RF-enable/upload automation is included.

## VSG playback: select the correct samples

Use `waveform/dl_tx/port_N.wiq` for clean DL transmission, and
`waveform/ul_tx/port_N.wiq` for clean UL transmission. Each file is signed
16-bit **little-endian**, interleaved I,Q, at **491.52 Msamples/s**, containing
**5,160,960 complex samples (10.5 ms)**. The four ports at each endpoint share
one scale, preserving their relative amplitudes/phases. Do not independently
normalize ports, sum them, or concatenate ports in time to simulate MIMO.

M9484C documentation supports `.wiq` import. Set its default binary format
to **Int16 Little Endian before selecting the file**; the documented default
is big-endian. Set/check waveform sample rate to 491.52 MHz and RF center to
7 GHz. Verify imported length, bandwidth, RMS/scale and clipping. Begin with
single-trigger playback and capture; inspect any waveform-length extension,
resampling or padding warning instead of silently accepting a different
recording. Choose power only after the operator completes the RF power budget.

On a four-output VXG, map port 1→RF1 through port 4→RF4, with supported
synchronization. Test DL and UL as separate endpoint recordings first; this
does not create a full-duplex four-layer link. A single-port live RF trace is
useful waveform evidence but cannot validate four-layer aggregate throughput.

The `dl_rx`/`ul_rx` files already contain simulated AWGN. Use them for offline
VSA recall of the recorded receive condition. Do not add another 30 dB AWGN
impairment or assume RF replay of a noisy RX file preserves the original
30 dB SINR: instrument noise and impairments would be additional.

## VSA recall

In 89600 VSA, configure four measurement channels (simulated hardware may be
used for offline recall), then **File → Recall → Recall Recording** and select
`dl_tx_4ch_vsa.mat`, `dl_rx_4ch_vsa.mat`, `ul_tx_4ch_vsa.mat` or
`ul_rx_4ch_vsa.mat`. Joint recordings use Keysight's documented multi-channel
header names and contain the unchanged single-precision source samples.

Recall/import is not the same as successful OFDM demodulation. Start with
time/spectrum views, then configure 120 kHz SCS, FFT 4096, 264 PRBs, DMRS and
the recorded slot allocations/rank/QAM/rate from the resolved config and
`reports/csv/trials.csv`. The allocation changes with adaptation. Stock NR
auto-detection of this 7 GHz / 400 MHz research profile, especially custom
UL 1024-QAM, is not verified. Exported raw IQ is not a ready-made decoded
constellation. Do not substitute a fabricated one if the demodulator rejects
the setup.

Actual analyzer EVM/power must be labeled with its own measurement source,
capture settings and units. It must not overwrite the recorded MATLAB EVM,
BLER, SINR or throughput. Live throughput needs actual RF sample acquisition,
alignment, decoding/CRC and a unique-payload ledger; VSG playback plus a
spectrum/EVM trace alone is insufficient.

## Rehearsal gates and next improvement

1. Offline dashboard/recording audit and browser replay: automated checks.
2. Recall each joint MAT on the actual VSA version; verify all four channels,
   clock, record length, normalization and no unexpected resampling.
3. One-port cabled playback at safe operator-approved power; acquire and save
   the actual RF capture. Verify sample format and TDD timing before demodulation.
4. Extend to synchronized ports only when installed TX/RX channel capability
   is confirmed; save instrument states and measured EVM/spectrum screenshots.
5. Capture both screens for a clearly labeled rehearsal video. Keep a copied
   offline package as the event fallback, not a fake live connection.
6. Before advertising sustained or higher peak throughput, perform a separately
   approved longer run and, for a live RF claim, actual receive-side decoding.
   Repeating the same 10.5 ms IQ does not provide new statistical evidence.

No new PHY run or `testAll` is required just to build this recorded exhibit.
The user's previous stop on `testAll` remains in effect.

## Retained implementation checks, 18 September 2026

- Ready-to-open laptop dashboard:
  `results/demos/imc_recorded_20260918_exhibit/index.html`.
- Screenshot: the same folder's `dashboard.png`; browser-tested at 1920x1080
  without vertical scrolling and at 390px width without horizontal overflow.
- Joint VSA recordings: `results/demos/imc_vsa_20260918_v1/`, four files,
  each with four unchanged arrays of 5,160,960 complex samples. Independent
  SHA256 rereads matched all four packaging receipts. Actual VSA import is pending.
- Fourteen focused Python tests passed, including adversarial evidence checks,
  exact packaging/readback, source-header mismatch and no-overwrite behavior.
- Browser checks passed for headline values, recorded CRC failure/recovery,
  play/pause/seek controls, final clock, offline operation and absence of JS errors.
- Logs are retained under `logs/imc_recorded_demo_20260918/`. The earlier
  mobile-width failure is preserved in `final_browser_check.log`; the corrected
  exhibit passes in `exhibit_browser_check.log`.
- No MATLAB/PHY algorithms, scenario settings, throughput denominators or
  acceptance thresholds were changed. No new heavy PHY run or full suite was run.

## Primary instrument references

- [M9484C capabilities](https://www.keysight.com/dk/en/product/M9484C/m9484c-vxg-vector-signal-generator.html)
- [M9484C waveform-file formats](https://helpfiles.keysight.com/csg/m9484/Content/GPSS/Signals.htm)
- [M9484C binary endianness and extension policy](https://helpfiles.keysight.com/csg/m9484/Content/GPSS/IQ%20Waveform.htm)
- [N9042B configuration guide](https://go.keysight.com/us/en/assets/3121-1036/configuration-guides/N9042B-UXA-Signal-Analyzer.pdf)
- [N9032B capabilities](https://www.keysight.com/dk/en/product/N9032B/pxa-signal-analyzer-2-hz-55-ghz.html)
- [VSA multichannel header naming](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/yn_m.htm)
- [VSA recording recall and simulated hardware](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/saving_and_recalling_recordings.htm)
- [Keysight coherence and synchronization guidance](https://www.keysight.com/us/en/assets/7018-03831/application-notes/5991-1878.pdf)
