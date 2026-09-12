# YAML LLS runbook

This runbook covers the config-driven link-level simulator only. Commands are
written for PowerShell from the repository root. They do not launch the E2E
campaign runner.

## 1. Setup and validate a YAML without running it

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); p='simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short.yaml'; s=sixgr.lls6g.config.loadScenarioConfig(p); c=sixgr.lls6g.buildInternalConfig(s,'results'); sixgr.config.validateConfig(c); disp('CONFIG_VALID')"
```

The loaded/resolved YAML is authoritative. Do not edit a generated
`resolved_config.yaml` under `results/` and expect it to affect another run.

## 2. Exact bounded 12 dB TDD run

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short.yaml','results','tdd_12db_manual_01'); assert(out.Ok,'12 dB LLS closure failed')"
```

Use a new run tag for every attempt. This scenario is one configured-SNR
operating point with CDL-A, waveform-clock Doppler, initial access, shared TDD
timing, DL/UL scheduling, CSI/PMI/RI, SRS, TRS, HARQ and AMC. It intentionally
uses ideal RF and no path loss, shadowing or O2I so those effects cannot be
silently cancelled by fixed-SNR calibration. OFDM windowing is off because it
is not mandatory for this LLS baseline.

The configured value is SNR at the declared normalized reference plane. SS,
CSI, DM-RS and post-equalization SINR are measurements and need not each equal
12 dB; their source and reference plane must remain visible in the CSVs.

`out.Ok` is the functional LLS/root-contract verdict. This bounded one-point
AMC diagnostic is deliberately not a statistically or independently
FRC-qualified publication campaign, so a successful run can retain
`PublicationQualified=0` and must not advance `published/current.json`. Check
`reports/json/result_status_summary.json` for the functional verdict and the
separate publication-qualification fields.

## 3. Eight-point configured-SNR run

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_snr_sweep.yaml','results','tdd_snr_sweep_manual_01'); assert(out.Ok,'SNR sweep closure failed')"
```

The executed grid is `[-30, -20, -10, 0, 10, 20, 30, 40]` dB. Each point has
independent link and access state. This bounded sweep is a functional
regression. A publication BLER curve needs a separate fixed-MCS Monte Carlo
campaign with declared trial/error stopping rules and confidence intervals.

## 4. TDD and FDD examples

The current causal 12 dB qualification target is TDD:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short.yaml','results','tdd_gate_01'); assert(out.Ok)"
```

The existing bounded FDD MU-MIMO regression uses its own legal FDD control and
feedback timing; do not convert the TDD YAML by changing only one string:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_mimo4x4_multiuser_beamformed_cdl_d_fdd_12slot_gate.yaml','results','fdd_gate_01'); assert(out.Ok)"
```

That FDD scenario is a 34 dB regression, not the 12 dB TDD scenario.

## 5. Bandwidth and 7 GHz status

An existing 28 GHz/400 MHz research preset can be launched with:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_fr2_28ghz_400mhz_4site_indoor.yaml','results','fr2_400mhz_probe_01'); assert(out.Ok)"
```

This is not the requested single-carrier 7 GHz/400 MHz case. The present
`band_7ghz.yaml` catalog supports up to 100 MHz. The one-carrier 7 GHz/400 MHz
waveform remains a pending `optional_research_experiment`; do not relabel the
28 GHz preset or combine four 100 MHz carriers to claim that target. Its
command will be added only after numerology, grid/FFT/sample rate, PRACH/SSB,
control/BWP, shared-stream memory and Keysight playback gates pass.

## 6. Enable or disable features through a child YAML

Create a small scenario file that inherits a qualified parent and overrides
only the required fields. For example, an ideal-RF AMC diagnostic keeps:

```yaml
inherits:
  - ./lls_causal_access_to_data_wiring_tdd_short.yaml

meta:
  scenario_id: my_tdd_amc_variant
  research_class: baseline_benchmark
  maturity_tag: regression

link_adaptation:
  fixed_or_amc: amc
  operating_point_mode: adaptive
  inner_loop_flag: true
  outer_loop_flag: true

waveform:
  windowing_enabled: false

rf_frontend:
  enabled: false

impairments:
  cfo:
    enabled: false
    value_hz: 0
  phase_noise:
    enabled: false
    model: none
  iq_imbalance:
    enabled: false
  adc_quantization_enabled: false
```

Common signal toggles are under `reference_signals` (`ssb_enabled`,
`csi_rs_enabled`, `srs_enabled`, `trs_enabled`, `ptrs_enabled`), but disabling
an access/control dependency can make the scenario invalid. Run the validation
command in section 1 after every override.

CDL and Doppler are controlled by `channels.model_type`, `channels.profile`,
`channels.per_sample_fading_enabled`, `channels.mobility_kmph`,
`channels.doppler_source_mode` and `channels.doppler_hz`. Do not add a second
independent Doppler impairment on top of a moving CDL channel.

O2I, path loss, shadowing, transmit power, receiver noise figure and UL power
control belong to an explicitly named physical-link-budget scenario. They are
not drop-in toggles for a configured-SNR baseline. Hardware stress values for
PA, CFO, phase noise, I/Q imbalance and quantization are engineering/test
profiles unless tied to a specific pinned RF conformance test; 3GPP does not
prescribe one universal impairment realization for every LLS.

## 7. Save MATLAB test output to a timestamped file

Full suite, when explicitly resumed:

```powershell
New-Item -ItemType Directory -Force .\test_logs | Out-Null
$log = ".\test_logs\testAll_$(Get-Date -Format yyyyMMdd_HHmmss).log"
matlab -batch "setup6GRSimToolkit('Verbose',false); testAll" 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "testAll failed; inspect $log" }
```

Focused LLS configuration/channel checks:

```powershell
$log = ".\test_logs\lls_focused_$(Get-Date -Format yyyyMMdd_HHmmss).log"
matlab -batch "setup6GRSimToolkit('Verbose',false); testConfig; testLLS_DL; testLLS_UL; testLLS_ReferencePoints" 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "Focused LLS tests failed; inspect $log" }
```

`testAll` is the repository qualification gate. A focused pass or one short
run must not be reported as a full-suite pass.

## 8. Where to inspect the run

For a single run, inspect these first:

- `meta/resolved_config.yaml` and the run manifest for resolved authority and
  source identity;
- `air_interface/csv/dl_pdsch_trials.csv` and `ul_pusch_trials.csv` for actual
  grants, MCS/modulation, receiver SINR, EVM, CRC and timing;
- `air_interface/csv/prach_trials.csv`, `pucch_trials.csv`, `srs_trials.csv`
  and `trs_trials.csv` for UL/control evidence;
- `beamforming/csv/` for selected beam, RI/PMI, precoder and QCL/TCI evidence;
- `reports/csv/live_waveform_preview.csv` and the runtime IQ manifest for
  post-IFFT complex waveform evidence;
- final status/receipt tables for truth, standards, mandatory subsystem,
  visual and browser-contract gates.

Empty data, a missing artifact or a failed gate must remain empty/missing/
failed. It must never be repaired by inserting proxy or synthetic rows into a
truth table.

## 9. Keysight M9384B/M9383B and 89600 playback package

Do not edit a sealed run to add instrument files. Repackage its exact captured
Tx-IQ into a separate folder:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); src='results/lls/lls_causal_access_to_data_wiring_tdd_short/tdd_12db_fixed_snr_20260912_04'; dst='results/playback/tdd_12db_fixed_snr_20260912_04_keysight_01'; o=sixgr.truth.exportKeysightPlaybackPackage(src,dst); assert(o.Ok); disp(o.ManifestPath)"
```

For each DL/UL physical port the package contains:

- headerless UTF-8 CSV with normalized `I,Q` floating-point samples;
- `.wiq` with little-endian interleaved signed-int16
  `I0,Q0,I1,Q1,...` samples and explicit quantization metadata;
- an 89600-compatible MAT file with case-sensitive `Y`, `XDelta`,
  `InputCenter`, `InputZoom=1`, and `XDomain=2` variables;
- SHA-256, sample rate, center frequency, port count, normalization scale,
  capture scope, and physical-instrument-validation status in the manifests.

The M9383B/M9384B import sequence for a generated `.wiq` is:

```text
:SYSTem:WAVeform:BFILe:FORMat:DEFault I16Little
:MEMory:IMPort:WEXTension NONE
:SOURce:GROup1:SIGNal1:WAVeform:SELect "C:\keysight\final_tx_iq_dl_port1_keysight_le16.wiq"
:SOURce:GROup1:SIGNal1:WAVeform:SCLock:RATE 7.68MHz
```

Use the sample rate from `final_tx_iq_capture_manifest.csv`, not the example
literal. Keep extension `NONE`: the exporter already requires at least 1,024
samples and, for M9384B, a sample count divisible by 16, so the instrument must
not silently repeat or zero-pad the trace. Select one synchronized generator
channel per physical port and preserve the manifest's port ordering.

In 89600 VSA use **File > Recall > Recall Recording** on a generated
`*_89600vsa.mat` file. For multiple physical ports, recall the per-port files
as multiple single-channel recordings using `RecallMultifile`; do not combine
ports by summing their samples.

The current `_04` package preserves its source scope honestly: DL is the first
committed grant component, while UL is one complete selected-UE grant. It is
not a continuous 58-slot all-channel playback file, and the manifest therefore
retains `single_grant_component_not_complete_cell_transmission` for DL.

To create a new run with disk-backed continuous capture of every physical
gNB/UE transmitter on the shared sample clock, use the dedicated child YAML:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml','results','tdd_12db_continuous_iq_01'); assert(out.Ok,'continuous 12 dB LLS closure failed')"
```

That run must seal both of these truth artifacts before its capture is
complete:

- `waveform/csv/continuous_tx_iq_capture_manifest.csv` — one PASS row per
  physical transmitter, including sample horizon, port count, precision,
  common clock, source and file hashes;
- `waveform/csv/continuous_tx_iq_segments.csv` — one row per transmitter and
  scheduler slot, bound to the exact post-TX-RF execution hashes.

The per-port `waveform/raw/*_cf64le.bin` files use little-endian IEEE-754
`I0,Q0,I1,Q1,...` samples. They preserve the exact runtime values and include
intentional silence. They are source captures, not directly normalized VSG
files; do not load the raw float64 files as signed-int16 `.wiq`.

After the continuous run seals successfully, create a separate playback tree:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); src='results/lls/lls_causal_access_to_data_wiring_tdd_short_continuous_iq/tdd_12db_continuous_iq_01'; dst='results/playback/tdd_12db_continuous_iq_01_keysight_01'; o=sixgr.truth.exportContinuousKeysightPlaybackPackage(src,dst); assert(o.Ok); disp(o.ManifestPath)"
```

The exporter verifies the sealed capture and per-slot segment tables, source
file hashes, complete sample horizon and one common scale per physical
transmitter. It writes one headerless normalized I/Q CSV, little-endian int16
`.wiq`, and 89600 MAT per physical antenna port. All ports retain sample-zero
alignment, common clock and equal length. An entirely silent transmitter is
preserved as zeros with an explicit identity scale; activity is never
fabricated. The source run remains unchanged. Physical M9384B/M9383B/89600
loopback is still an operator/instrument acceptance step.

Official format references: [M9383B/M9384B waveform files and sample-rate
commands](https://helpfiles.keysight.com/csg/m9384/Content/GPSS/Signals.htm),
[binary byte order and extension policy](https://helpfiles.keysight.com/csg/m9384/Content/GPSS/Instrument%20Settings.htm),
and [89600 MATLAB source playback](https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/gui/content/source_using_matab.htm).
