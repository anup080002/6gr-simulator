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
