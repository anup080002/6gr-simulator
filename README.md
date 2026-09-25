# SixGR Foundation v2

Current development snapshot: [25 September consolidation and known failures](docs/lls/main_consolidation_20260925.md#pucch-reporting-checkpoint).
This checkpoint is not acceptance of the eight-point sweep or full shared-feedback 400 MHz run.
The latest PUCCH reporting repair separates receiver detection from payload
correctness; its focused tests pass, but detector statistical qualification
remains open. Source, scenario YAMLs and launchers are delivered on `main`;
generated logs, results and instrument IQ packages remain separate local artifacts.

For the dedicated **7 GHz / 400 MHz rank-2 VXG/VSA data-channel experiment**, see
[the quick-start commands and measured results below](#400-mhz--7-ghz-rank-2-keysight-waveform-demonstration)
and [the full native-IQ runbook and hardware checklist](docs/lls/vxg_vsa_rank2_runbook.md).
This is separate from shared-feedback acceptance; digital export readiness does
not verify installed Keysight options or physical RF measurements.

This repository is a MATLAB-based 5G/6G simulator with three closely related uses:

1. link-level PHY execution and diagnostics,
2. config-driven 6G PHY LLS scenario execution, and
3. broader campaign-style truth, proxy, and end-to-end validation workflows.

At the center of the repo is the `+sixgr` package tree, which holds the reusable simulator library. Around that library are a few front-door scripts, a large YAML scenario/config system for the newer 6G LLS workflow, legacy JSON-driven configuration for broader campaign runs, a GUI, tests, and a structured results/export pipeline.

This README is intended to be the practical "start here" document for the codebase:

- what the project is,
- which entry point to use,
- how configuration is organized,
- what the major folders/files do,
- how results are laid out,
- how to run the main workflows,
- how to validate changes, and
- where to read more detailed architecture/specification documents.

## Table of Contents

For the measured four-layer 400 MHz run, use the
[exact Windows PowerShell commands](#exact-command-measured-400-mhz-four-layer-adaptive-run).
`main` is the single development branch; old merged branch tips are retained
as `archive/consolidated-20260918/*` tags, not alternative runnable branches.

For the India Mobile Congress two-screen exhibit, see the
[recorded dashboard and M9484C / N9042B / N9032B operating guide](docs/lls/imc_recorded_demo_runbook.md).
It includes exact commands for the offline DL/UL replay and checked four-channel
VSA MAT packaging. This displays measured simulator results, not live RF throughput.

1. [What This Repository Contains](#what-this-repository-contains)
2. [Recommended First-Time Setup](#recommended-first-time-setup)
3. [Which Runner Should You Use](#which-runner-should-you-use)
4. [Quick Start Commands](#quick-start-commands)
5. [Repository Structure](#repository-structure)
6. [Major Entry-Point Files](#major-entry-point-files)
7. [Configuration Systems](#configuration-systems)
8. [How the Main Run Flows Work](#how-the-main-run-flows-work)
9. [Results and Artifact Layout](#results-and-artifact-layout)
10. [Important Output/Truthfulness Semantics](#important-outputtruthfulness-semantics)
11. [Tests and Validation Workflow](#tests-and-validation-workflow)
12. [How to Add or Modify a Scenario](#how-to-add-or-modify-a-scenario)
13. [Troubleshooting](#troubleshooting)
14. [Detailed Documentation Pack](#detailed-documentation-pack)

## What This Repository Contains

The codebase mixes a few layers of functionality that are related but not identical:

### 1. Reusable simulator library under `+sixgr`

This is the real engine. It contains:

- PHY blocks for DL/UL waveform generation and reception,
- channel and RF modeling,
- scenario construction,
- reporting/export utilities,
- truth-validation helpers,
- system-level and hybrid flows,
- L2/L3 packet-flow components, and
- utility/config infrastructure.

If you are changing simulation behavior, you are usually editing something inside `+sixgr`.

### 2. Config-driven 6G PHY LLS framework

This is the newer YAML-based scenario system under `simulator/configs/`. It is designed so that LLS scenario behavior is driven by resolved configuration rather than hard-coded runner defaults.

Its main front doors are:

- `run_6g_phy_lls_single.m`
- `run_6g_phy_lls_matrix.m`

This is the best starting point if your goal is "run a defined LLS scenario" or "run a regression matrix of LLS scenarios".

### 3. Broader truth/proxy/campaign orchestration

This is the more general orchestration path built around:

- `sixgr_run_3gpp_full_campaign.m`
- `run_truth_validation_profile.m`

These are used for larger combined runs, truth validation, E2E coupling, structured artifact verification, and broader result bundles.

### 4. Browser WebGUI / interactive usage

The live scenario-management browser workflow has one implementation and launcher:

- `apps/lls_web_dashboard.py`
- `apps/start_lls_web_dashboard.ps1`

It loads scenarios, edits and downloads configuration, launches MATLAB LLS
runs, and presents live status, tables, plots, files, and resource-grid
evidence in one interface. The MATLAB `uifigure` utility remains a separate
desktop tool; it is not another browser server.

The separate `apps/vxg_vsa_demo_dashboard.py` exhibition viewer replays a completed,
validated lab package. It does not launch live PHY runs or replace the scenario
manager. Its default address is `http://127.0.0.1:8991/webgui/`, and its exported
HTML also works offline.

## Recommended First-Time Setup

Open MATLAB with the repository root as the working folder, then run:

```matlab
setup6GRSimToolkit
```

What `setup6GRSimToolkit.m` does:

- adds the project root to the MATLAB path,
- optionally adds non-package subfolders,
- avoids adding `+pkg` and `@class` folders directly,
- optionally checks for toolbox/capability availability.

### Toolboxes and capabilities the setup script checks for

The setup script probes for these capabilities:

- 5G Toolbox
- Communications Toolbox
- Deep Learning Toolbox
- Parallel Computing Toolbox
- Phased Array System Toolbox
- Wireless Network Simulation Library support
- Site Viewer support
- RF Propagation support

Practical guidance:

- For serious NR/6G PHY execution, assume 5G Toolbox is required.
- Communications Toolbox is commonly needed for channel/noise helpers.
- Parallel and MEX acceleration are optional performance helpers.
- AI/ML scenarios can depend on Deep Learning Toolbox or descriptor-driven AI assets.
- Some SLS or map/site workflows can rely on phased/RF/site-viewer functionality.

### Recommended MATLAB version

The GUI header in `apps/SimSuiteGUI.m` targets `R2025b+`. Even outside the GUI, this repository is clearly written for a recent MATLAB release. If you run into odd syntax/class issues on older versions, upgrade first before assuming the simulator is broken.

## Which Runner Should You Use

Use this table as the quick decision guide.

| Goal | Recommended entry point | Notes |
| --- | --- | --- |
| Run one config-driven 6G PHY LLS scenario | `run_6g_phy_lls_single` | Best front door for a single YAML scenario |
| Run a matrix/regression of LLS scenarios | `run_6g_phy_lls_matrix` | Best front door for suite-style YAML execution |
| Run the stricter truth-validation profile | `run_truth_validation_profile` | Truth E2E plus supplemental waveform/control artifacts |
| Run the broader campaign orchestrator | `sixgr_run_3gpp_full_campaign` | More general and more configurable; used by compatibility flows too |
| Launch the live scenario-manager WebGUI | `apps/start_lls_web_dashboard.ps1` | Defaults to `http://127.0.0.1:62906/` |
| Generate the rank-2 Keysight waveform package | `scripts/run_vxg_vsa_demo.ps1` | Actual PHY execution, instrument exports, browser checks and artifact hashes |
| View a completed rank-2 exhibition package | `apps/vxg_vsa_demo_dashboard.py` | Recorded digital evidence, not live RF; defaults to port 8991 |
| Launch the MATLAB desktop utility | `Start6GRSimToolkit` or `SimSuiteGUI` | MATLAB-only interactive usage; not a browser server |
| Use older compatibility path | `SixGR_Simulator` | Deprecated wrapper; forwards to the full campaign |

## Quick Start Commands

### 400 MHz / 7 GHz rank-2 Keysight waveform demonstration

**7 GHz / 400 MHz 6G research waveform using 3GPP-derived NR PHY structures.**
This is **400 MHz bandwidth at 7 GHz**, not a 4 GHz carrier. The dedicated YAML is
[`lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml`](simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml).
It preserves the existing 5 MHz and four-layer/shared-feedback scenarios.

The run uses 120 kHz SCS, FFT 4096, native 491.52 MSa/s, normal CP, 264 PRBs,
2x2 logical identity MIMO and two layers. Each port has 4,915,200 samples over
10 ms. The TDD period is 5 DL slots / one 10D+2G+2U mixed slot / 2 UL slots;
data occupy full DL/UL slots only. DL uses MCS26/25/24 from the 1024-QAM table;
UL uses experimental 1024-QAM at rate 948/1024, without an invented NR UL MCS.
Real TBS/LDPC/CRC and received-DMRS estimation/MMSE are executed. Access,
physical control/feedback, HARQ and link adaptation are disabled in this
dedicated clean-waveform experiment, not silently bypassed in shared scenarios.

Requirements: MATLAB R2024a+ with the needed 5G Toolbox features (executed here
with R2026a), Python numpy/scipy/pandas/matplotlib/Playwright and its Chromium
browser. The launcher checks Python/browser availability before MATLAB.

From **Windows Command Prompt**, this one line executes MATLAB, exports and
reads back the files, checks the browser, and seals the artifact inventory.
The run tag is generated automatically; existing runs are not overwritten:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vxg_vsa_demo.ps1"
```

On another PC, substitute that PC's checkout path. From its repository root,
the portable command is:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
```

Outputs are saved to `results/vxg_vsa/7ghz_400mhz_rank2_1024qam/<run_tag>/`;
launcher, packaging and browser logs are in `logs/`. The package is about
12.1 GB because full native/noisy IQ and multiple validated formats are retained.
The launcher does not run `testAll` or enable RF.

For this test, use the rank-2 `vxg_vsa` YAML above, not the older four-layer
adaptive or shared-feedback YAMLs later in this README. From an existing clean
checkout, update the single delivery branch before executing the launcher:

```bat
git switch main && git pull --ff-only origin main
```

The launcher prints `RUN_FOLDER` for the exact new execution. Within that folder:

| What to inspect or share | Location |
|---|---|
| Engineering summary and all-case measurements | `reports/engineering_report.md`, `reports/csv/` |
| Spectrum, PSD, PAPR, EVM and constellation plots | `reports/image/` |
| Recorded WebGUI, without starting another simulation | `webgui/index.html` |
| VSG/VSA file mapping and hardware checklist | `keysight/instrument_handoff.json`, `keysight/hardware_checklist_and_runbook.md` |
| Readback validation and immutable file inventory | `validation/export_receipts.json`, `manifest.json` |

These generated files are not downloaded by `git pull`: either run the launcher
or transfer the existing complete package separately. Do not overwrite the
sealed `20260925_v1` package with results from a newer source revision.

The completed local run `20260925_v1` contains 630 receiver trials across
MCS26/25/24 and 30/35/40 dB. Primary MCS26 results are:

| Simulated SNR | DL CRC passes | UL CRC passes | DL full-frame goodput | UL full-frame goodput | DL / UL RMS EVM |
|---|---:|---:|---:|---:|---:|
| 30 dB | 0/50 | 0/20 | 0 | 0 | 3.7814% / 3.7796% |
| 35 dB | 50/50 | 20/20 | 3.524520 Gbit/s | 1.409808 Gbit/s | 2.1278% / 2.1285% |
| 40 dB | 50/50 | 20/20 | 3.524520 Gbit/s | 1.409808 Gbit/s | 1.1964% / 1.1970% |

All profiles passed their tested payloads at 35/40 dB. At 30 dB, MCS24 DL passed
10/50 TBs; MCS25 DL and the fixed-rate UL failed all tested TBs. These finite
samples are **not statistical BLER qualification**. Export/demo readiness is
not an all-SNR payload pass, shared-feedback acceptance or RF measurement.
The [versioned validation record](docs/lls/vxg_vsa_validation_20260925.md) preserves
the test scope and sealed package identity; all cases remain in the CSVs/GUI.

Open the completed local package without rerunning MATLAB:

```bat
python apps\vxg_vsa_demo_dashboard.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\20260925_v1"
```

Open `http://127.0.0.1:8991/webgui/`, or open `<run_folder>/webgui/index.html`
offline. Use F for fullscreen and Space for recorded replay. For another run,
replace `20260925_v1` with its actual tag. After transfer, verify the complete
package without modifying its bytes:

```bat
python apps\seal_lab_waveform_package.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\20260925_v1" --verify-only
```

For Keysight, share these primary-profile files (paths relative to the run folder):

| Destination | Files |
|---|---|
| VSG DL, two coherent outputs | `dl_tx/mcs26/dl_tx_port1.wiq`, `dl_tx/mcs26/dl_tx_port2.wiq` |
| VSG UL, separate playback experiment | `ul_tx/mcs26/ul_tx_port1.wiq`, `ul_tx/mcs26/ul_tx_port2.wiq` |
| 89600 VSA, DL two-channel recording | `vsa/mcs26/dl_tx_2ch_vsa.mat` |
| 89600 VSA, UL two-channel recording | `vsa/mcs26/ul_tx_2ch_vsa.mat` |

Also share `keysight/instrument_handoff.json`,
`keysight/hardware_checklist_and_runbook.md`, `vsa/vsa_demod_config.json` and
`validation/export_receipts.json`. WIQ is signed int16 **little-endian**,
interleaved I/Q, with a common scale across both ports. Set native Fs to
491.52 MSa/s and RF center to 7 GHz; preserve simultaneous start and port order.
Do not use simulated noisy RX files for clean VSG transmission. The demodulation
JSON is an engineering description, not a proprietary Keysight setup file.

**PHYSICAL INSTRUMENT CAPABILITY VERIFIED: UNKNOWN.** Actual `*IDN?`/`*OPT?`,
installed options, coherent TX/RX channels and import success remain unverified.
The sealed results and logs stay local under existing Git ignore rules; cloning
GitHub downloads the implementation, not this multi-GB recorded package.

### Current TDD runs: 5 MHz / 12 dB and 400 MHz / 30 dB

Use **`main`** as the consolidated delivery branch. From Windows PowerShell,
clone once (Git LFS is needed for tracked MATLAB evidence):

```powershell
git clone --branch main https://github.com/anup080002/6gr-simulator.git
Set-Location .\6gr-simulator
git lfs install
git lfs pull
```

For an existing clean clone, use `git switch main` and `git pull --ff-only
origin main`. Preserve local edits first; do not reset or clean them away.

These are **different YAML scenarios**, not two bandwidth overrides of one
qualified full-stack scenario. As of 17 September 2026:

| Scenario | YAML under `simulator/configs/scenarios/` | Verified outcome |
| --- | --- | --- |
| 5 MHz TDD, configured 12 dB, continuous TX IQ | `lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml` | All 58 slots plus receive tail executed on `68140bb9`; overall acceptance **failed** despite 20/20 DL and 5/5 UL CRC-passing attempts. |
| 400 MHz TDD, 7 GHz metadata, configured 30 dB reference SNR, DL/UL 1024-QAM | `lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml` | Research capture **completed successfully** on `6be2985f`: 30/30 DL and 40/40 UL TBs correct over 10 ms; 1.868280 Gbit/s DL and 2.491040 Gbit/s UL. |

The 400 MHz run uses two layers, code rate 0.82, ideal AWGN and preconfigured
timing. Its goodput includes the complete TDD interval. It is the highest
passing rate tested for this fixed configuration, not a global throughput
maximum or standardized 6G/full-stack qualification. Control/access, HARQ,
CSI/SRS and RF impairments are disabled in that research YAML. The 30 dB value
is a configured reference SNR, not a guarantee of 30 dB measured SINR.
Full regression qualification is unfinished and has recorded failures.
The 10.5 GHz study is deferred; neither command below selects it.

Run **one scenario at a time** from the repository root. Select the installed
MATLAB executable; the recorded runs used R2026a Update 4. R2023b compatibility
is **not qualified**:

```powershell
$matlabExe = 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe'
# On the other server, use its installed path, for example:
# $matlabExe = 'C:\Program Files\MATLAB\R2023b\bin\matlab.exe'
```

**5 MHz / 12 dB diagnostic (known failed acceptance; not a passing release):**

```powershell
$runTag = 'tdd_5mhz_12db_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $runRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$runRoot/matlab.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml','$runRoot','$runTag'); assert(out.Ok,'5 MHz / 12 dB scenario acceptance failed; preserve the logs.');"
if ($LASTEXITCODE -ne 0) { throw "5 MHz run failed. Preserve $runRoot and its matlab.log." }
```

**400 MHz / 7 GHz / 1024-QAM DL+UL research run with IQ capture:**

```powershell
$runTag = 'tdd_400mhz_30db_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $runRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$runRoot/matlab.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml','$runRoot','$runTag'); assert(out.Ok && out.ResultOk,'400 MHz research scenario acceptance failed; preserve the logs.');"
if ($LASTEXITCODE -ne 0) { throw "400 MHz run failed. Preserve $runRoot and its matlab.log." }
```

Both commands retain console logs and scenario artifacts beneath their unique
`logs/<runTag>/` directory. Copy that directory when reporting failures.
In the 400 MHz scenario run folder, `waveform/dl_tx`, `ul_tx`, `dl_rx` and
`ul_rx` contain exact `raw_iq.mat`, per-port VSA MAT and WIQ files. Each stream
has 4,915,200 samples at 491.52 Msamples/s. TX is clean; RX includes AWGN, so
do not add noise again when replaying the captured receive condition.
File readback was verified; actual Keysight application import was not.
Large generated IQ/log directories stay local, not in GitHub; the source,
YAMLs and small evidence receipts are committed.

The separate **four-layer / 64 gNB-element / 4 UE-element** scenario is
`lls_7ghz_400mhz_4layer_64gnb_4ue_30db.yaml`. It uses actual polarized
physical-element CDL-C propagation, fixed semi-unitary DFT beams, and
per-resource DMRS channel estimation. It is **not** the passing two-layer
identity-AWGN capture above. Its 30 dB value fixes noise relative to the
pre-channel layer power; measured SINR and decoding success are not forced.
It retains 1024-QAM/rate 0.82 and the 80-slot TDD horizon. Timing is configured,
the channel is static with independently filtered slot bursts, and there is
no adaptive CSI/beam feedback. CSV/PNG and antenna evidence go to `results/`;
raw multichannel IQ capture is disabled. Run from the repository root:

```powershell
$runTag = 'tdd_400mhz_4layer_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff')
$logRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $logRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$logRoot/matlab.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_4layer_64gnb_4ue_30db.yaml','results','$runTag'); assert(out.Ok && out.ResultOk);"
if ($LASTEXITCODE -ne 0) { throw 'Four-layer run failed; preserve results and logs. Do not label it a pass.' }
```

The latest requested **4x4 identity-AWGN adaptive benchmark** supersedes that
physical-CDL run as the active task. Its candidate menu is 1024-QAM/rank 2,
1024-QAM/rank 4, and 256-QAM/rank 4, initially with rate 0.9 and ideal delayed HARQ.
Code-rate adaptation up to 0.9 is now approved; additional 1024-QAM/rank-4
rates 0.82 and 0.85 require their own coded calibration before selection.
The new ILLA/OLLA path requires actual coded calibration for the exact
allocation; it does not reuse the two-layer capture as calibration. See
[adaptive implementation and acceptance boundary](docs/lls/research_4x4_awgn_harq_integration_20260917.md).
The approved DL-heavy run has now completed with payload acceptance passing;
the separate >6 Gbit/s target was missed. Its exact command and measured result
are below. The earlier physical-CDL and two-layer commands are different runs.

The full-width candidate is
`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_rank_qam_30db.yaml`.
It retains the existing 120 kHz / 264-PRB carrier and 3-DL/4-UL/1-mixed
pattern; it is not the proposed DL-heavy >6 Gbit/s benchmark. Calibration
executes 540 real independent initial TBs (three candidates, both directions,
three reference-SNR points, 30 trials per point). Calibration does not run
`testAll` or generate a final IQ capture. The complete command block below
generates both required calibration datasets if they are absent.

The additional rate profile executes 120 actual initial TBs (two rates, both
directions, 30 trials at 30 dB each), preserving the original calibration.
The multiple-source loader and controller integration passed focused checks.
Full-band rates 0.82 and 0.85 each had 0/30 initial CRC failures in both DL and
UL at 30 dB, meeting the configured pointwise 95%-confidence/10%-BLER gate.
The combined five-candidate configuration preflight also passed. The user has
approved the separate **5-DL/2-UL/1-mixed** scenario below for the >6 Gbit/s DL
attempt. Execution and artifacts have now been checked: see the measured
outcome below. The original 3-DL/4-UL profile is retained unchanged.

### Exact command: measured 400 MHz four-layer adaptive run

Use this YAML, not the older two-layer or 64-element CDL YAML:
`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml`.
It reproduces the adaptive experiment that selected four layers throughout
the recorded run. Rank 2 remains allowed by the approved adaptive menu;
1024-QAM is the maximum modulation, not a forced startup modulation.
This is a throughput attempt, not a guaranteed maximum or >6 Gbit/s pass.

Open **Windows Terminal / PowerShell**. For a new server checkout, first run
these commands from the parent directory where the repository should be created:

```powershell
git clone --branch main --single-branch https://github.com/anup080002/6gr-simulator.git
if ($LASTEXITCODE -ne 0) { throw 'Clone failed; do not continue.' }
Set-Location -LiteralPath '.\6gr-simulator'
```

For an existing checkout, open its repository root and use `git switch main`
and `git pull --ff-only origin main`; stop on any error rather than discarding
local edits. Then paste this **entire self-contained block**. It prefers the
validated R2026a installation, otherwise uses the requested R2023b server
installation; the selected executable is printed. R2023b end-to-end execution
has not yet been qualified. MATLAB and 5G Toolbox must be installed/licensed.

```powershell
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath '.\setup6GRSimToolkit.m')) { throw 'Run from the repository root.' }
$matlabExe = 'C:/Program Files/MATLAB/R2026a/bin/matlab.exe'
if (-not (Test-Path -LiteralPath $matlabExe)) { $matlabExe = 'C:/Program Files/MATLAB/R2023b/bin/matlab.exe' }
if (-not (Test-Path -LiteralPath $matlabExe)) { throw 'MATLAB R2026a or R2023b was not found at its default installation path.' }
Write-Host "MATLAB executable: $matlabExe"
$scenarioYaml = 'simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml'
$runTag = 'adaptive_dl5_ul2_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff')
$logRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $logRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$logRoot/preflight.log" -batch "setup6GRSimToolkit('Verbose',false); assert(testResearchFixedPorts()); assert(testResearchIdealDelayedHARQ()); assert(testResearchDLHeavyConfig());"
if ($LASTEXITCODE -ne 0) { throw "Focused preflight failed. See $logRoot/preflight.log" }
if (-not (Test-Path -LiteralPath 'results/research_adaptation_calibration/full264_20260918/trials.csv')) {
    & $matlabExe -wait -singleCompThread -logfile "$logRoot/calibration.log" -batch "setup6GRSimToolkit('Verbose',false); sixgr.phy.research.calibrateAWGNAdaptation('simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_rank_qam_30db.yaml');"
    if ($LASTEXITCODE -ne 0) { throw "Primary calibration failed. Preserve $logRoot/calibration.log and partial results." }
}
if (-not (Test-Path -LiteralPath 'results/research_adaptation_calibration/rates082_085_30db_20260918/trials.csv')) {
    & $matlabExe -wait -singleCompThread -logfile "$logRoot/rate_calibration.log" -batch "setup6GRSimToolkit('Verbose',false); sixgr.phy.research.calibrateAWGNAdaptation('simulator/configs/scenarios/lls_7ghz_400mhz_rate_calibration_30db.yaml');"
    if ($LASTEXITCODE -ne 0) { throw "Rate calibration failed. Preserve $logRoot/rate_calibration.log and partial results." }
}
& $matlabExe -wait -singleCompThread -logfile "$logRoot/execution.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('$scenarioYaml','results','$runTag'); disp(out.SummaryTable); assert(out.ResultOk,'Payload delivery failed; preserve artifacts.');"
if ($LASTEXITCODE -ne 0) { throw "Execution failed. See $logRoot/execution.log; do not delete its results." }
$resultRoot = 'results/lls/lls_7ghz_400mhz_adaptive_dl5_ul2_30db/' + $runTag
$summary = @(Import-Csv -LiteralPath "$resultRoot/reports/csv/summary.csv")
$summary | Format-Table Direction,GoodputBitsPerSecond,FirstTransmissionBLER,BLER,PendingTransportBlocks
$dl = $summary | Where-Object Direction -eq 'DL'
Write-Host ('DL >6 Gbps target met: ' + ([double]$dl.GoodputBitsPerSecond -gt 6e9))
Write-Host "Results: $resultRoot"
Write-Host "Logs: $logRoot"
```

The first invocation on a fresh checkout runs **660 calibration trials**,
then the integrated scenario. Later invocations retain existing calibration;
the MATLAB loader still checks its completeness, source/profile fingerprints
and MATLAB version. A present CSV is not assumed to be valid. On a stale,
incomplete or version-mismatched calibration, stop and preserve its evidence;
use a fresh checkout for a new-version campaign. Do not copy R2026a calibration
into the R2023b checkout. No calibration, previous run or log is overwritten.
This block runs focused checks only, **not `testAll`**.

Outputs under the printed result folder:

- `reports/csv/summary.csv`, `trials.csv`, `layer_measurements.csv`;
- `reports/image/tdd_goodput.png`;
- `harq/csv/`, `adaptation/csv/`, `air_interface/csv/timeline.csv`;
- `waveform/iq_manifest.csv` plus `dl_tx`, `dl_rx`, `ul_tx`, `ul_rx`
  subfolders containing raw MAT, per-port WIQ and VSA MAT IQ;
- `meta/manifest.json` and executed configuration/source provenance.

This uses 80 data slots plus four feedback-drain slots, with 50 full-slot DL
and 20 full-slot UL opportunities. The fixed 14-symbol data allocations do
not occupy the mixed slot. Goodput includes the complete sample-clock horizon,
including idle and drain time. `ResultOk` checks payload delivery, not the
separate >6 Gbit/s goal; inspect measured DL goodput in `reports/csv/summary.csv`.
The 7 GHz / 400 MHz / 120 kHz waveform remains an optional research experiment,
with explicitly ideal feedback, not a standardized 6G conformance result.

Measured on R2026a, source `ef799fcb`, seed 20260920: **5.926550 Gbit/s DL
and 2.396846 Gbit/s UL** over 10.5 ms. All 49 DL and 20 UL unique payloads
were delivered; one DL initial failure recovered on its second attempt.
Payload acceptance passed, but the **>6 Gbit/s DL target was not met**.
Four-port TX/RX IQ, CSV and PNG exports completed and their artifact audit
passed. See [the measured outcome and evidence](docs/lls/research_dl5_ul2_outcome_20260918.md).

The YAML chooses the calibration destination under `results/`. Existing
calibration CSVs are never overwritten: choose a new `calibration_file` in
the YAML for a new campaign. Regenerate calibration on each MATLAB version;
the current focused qualification used R2026a. MathWorks documents 1024-QAM
support since R2023a for [PDSCH configuration](https://www.mathworks.com/help/5g/ref/nrpdschconfig.html)
and [LDPC rate matching](https://www.mathworks.com/help/5g/ref/nrratematchldpc.html),
but this is not proof that the complete repository passes on R2023b. Keep the
preflight and calibration logs for that verification.

Full-suite commands below are optional operator instructions, not part of
the four-layer run; `testAll` remains stopped for the current work.
For an independent full-suite run on the other server, with logs under `logs/`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1 -MatlabExe $matlabExe -PreflightOnly
if ($LASTEXITCODE -ne 0) { throw 'MATLAB preflight failed; inspect logs before running the suite.' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1 -MatlabExe $matlabExe
if ($LASTEXITCODE -ne 0) { throw 'testAll failed; preserve its logs directory.' }
```

Details: [5 MHz terminal outcome](docs/lls/tdd_5mhz_12db_68140bb9_outcome_20260917.md),
[400 MHz IQ / Keysight handoff](docs/lls/keysight_research_iq_handoff_20260917.md),
and [source consolidation](docs/lls/main_delivery_consolidation_20260917.md).

### A. Setup once per MATLAB session

```matlab
setup6GRSimToolkit("Verbose", true);
```

### B. Run one LLS scenario

```matlab
out = run_6g_phy_lls_single( ...
    "simulator/configs/scenarios/dl_4ghz_baseline.yaml", ...
    "results", ...
    "manual_run");
```

What you get:

- a clean run folder under `results/lls/...`,
- `meta/` with resolved config and manifest,
- `reports/` with summaries, CSVs, and images,
- `air_interface/` with waveform-level exports.

### C. Run the LLS matrix/regression suite

```matlab
out = run_6g_phy_lls_matrix( ...
    "simulator/configs/scenarios/matrix_regression.yaml", ...
    "results", ...
    "matrix_run");
```

What you get:

- one matrix root under `results/lls/...`,
- per-scenario runs under `runs/`,
- combined suite/point/scenario rollups under `reports/csv/`.

### D. Run the truth-validation profile

```matlab
out = run_truth_validation_profile( ...
    "ConfigFile", "config/suite_config_truth_validation.json", ...
    "ResultsRoot", "results", ...
    "Verbose", true);
```

What this does:

- runs a base E2E truth validation campaign,
- generates supplemental waveform link/control artifacts,
- writes a truth-validation report and manifest,
- scans artifacts for proxy/fallback violations.

### E. Run the broader full campaign directly

```matlab
report = sixgr_run_3gpp_full_campaign( ...
    "config/suite_config.json", ...
    "ResultsRoot", "results", ...
    "Verbose", true);
```

Use this when you want combined campaign orchestration rather than only the LLS YAML scenario framework.

### F. Launch the single browser WebGUI

Copy the sanitized machine-local template once, then edit `apps/.env` with the
MySQL address and credentials for that system:

```powershell
Copy-Item .\apps\.env.example .\apps\.env
.\apps\start_lls_web_dashboard.ps1
```

Open <http://127.0.0.1:62906/>. The launcher creates
`apps/.webgui-venv`, installs `apps/requirements-webgui.txt`, discovers the
newest installed MATLAB release unless `SIXGR_MATLAB_EXE` is set, and starts
only `apps/lls_web_dashboard.py`. Use `SIXGR_DASHBOARD_HOST=0.0.0.0` only when
intranet access is intended; keep the real `apps/.env` untracked.

For the separate MATLAB desktop utility:

```matlab
Start6GRSimToolkit
```

## Repository Structure

This section is the "what is what" map of the repo.

### Top-level folders

| Path | Purpose |
| --- | --- |
| `+sixgr/` | Main MATLAB package tree; almost all real simulator logic lives here |
| `apps/` | MATLAB GUI and UI panels |
| `config/` | Legacy/modular JSON config fragments used by the broader campaign stack |
| `docs/` | Architecture docs, result layout docs, and the 6G LLS deliverables pack |
| `results/` | Generated run outputs |
| `simulator/configs/` | YAML-based config-driven 6G PHY LLS scenario framework |
| `tests/` | Regression and validation test suite |

### Top-level files you will actually use

| File | What it does |
| --- | --- |
| `setup6GRSimToolkit.m` | Adds paths and checks toolboxes/capabilities |
| `run_6g_phy_lls_single.m` | Front door for one YAML LLS scenario |
| `run_6g_phy_lls_matrix.m` | Front door for one YAML LLS matrix |
| `run_truth_validation_profile.m` | Truth-validation wrapper with stricter artifact checks |
| `sixgr_run_3gpp_full_campaign.m` | Unified campaign orchestrator |
| `Start6GRSimToolkit.m` | GUI launcher/helper |
| `SixGR_Simulator.m` | Deprecated compatibility wrapper over the full campaign |
| `sixgr_loadConfig.m` | Thin wrapper over `sixgr.config.loadConfig` |
| `sixgr_build_mex_accel.m` | Builds supported MEX accelerators |
| `sixgr_deep_validate_campaign.m` | Deep audit/validation helper for campaign outputs |
| `tests/testAll.m` | Master regression test entry point |

### Root-level files you can usually ignore

The repo root also contains a few scratch, probe, temp, or compatibility-oriented files such as:

- `__tmp_*.m`
- `temp_*.m`
- one-off logs or helper command files

These are not the canonical public entry points. When in doubt, start from the runner files listed above, the `+sixgr` packages, and the `simulator/configs/` tree.

### Important top-level MEX/kernel files

You will also notice several `sixgr_*_kernel.m` and `sixgr_*_kernel_mex.mexw64` files, for example:

- `sixgr_awgn_complex_kernel.*`
- `sixgr_channel_est_ls_kernel.*`
- `sixgr_corr_metric_kernel.*`
- `sixgr_freq_corr_search_kernel.*`
- `sixgr_ldpc_decode_batch_kernel.*`
- `sixgr_truth_grant_hash_kernel.*`

These are performance accelerators or performance-oriented kernels. They are not the right place to start if you are trying to understand the simulator architecture; treat them as optimized implementations supporting higher-level flows.

### The `+sixgr` package map

The `+sixgr` root is the library. Its main subpackages are:

| Package | Purpose |
| --- | --- |
| `+sixgr/+ai` | AI/ML helpers and AI-related runtime/report support |
| `+sixgr/+channel` | Channel creation and fading/channel-model plumbing |
| `+sixgr/+config` | Legacy/full-campaign JSON config loading, normalization, validation |
| `+sixgr/+core` | Core utilities such as logging, execution context, and shared run infrastructure |
| `+sixgr/+hybrid` | Hybrid/truth-vs-proxy or mixed-mode workflows |
| `+sixgr/+l2` | Layer-2 stack logic such as PDCP/RLC/SDAP |
| `+sixgr/+l3` | Layer-3 / RRC-related logic |
| `+sixgr/+link` | Link-level wrappers, KPI exporters, and experiment helpers |
| `+sixgr/+lls6g` | Config-driven 6G PHY LLS framework |
| `+sixgr/+phy` | Physical-layer blocks, TX/RX chains, coding, reference signals, modulation, synchronization |
| `+sixgr/+report` | Run folder layout, output organization, artifact verification |
| `+sixgr/+rf` | RF impairment and RF-related helpers |
| `+sixgr/+scenario` | Topology/layout generation, UE drop, scenario construction |
| `+sixgr/+system` | System-level / SLS runtime logic |
| `+sixgr/+truth` | Truth-mode waveform execution, reporting bundles, artifact scans, strict semantics |
| `+sixgr/+util` | Shared utility functions |
| `+sixgr/+visual` | Visualization helpers |

### The `+sixgr/+phy` package map

Inside the PHY tree, the first directories to know are:

| Path | Role |
| --- | --- |
| `+sixgr/+phy/+dl` | Downlink channel TX/RX helpers such as PDSCH/PDCCH/PBCH-related logic |
| `+sixgr/+phy/+ul` | Uplink channel TX/RX helpers such as PUSCH/PUCCH/PRACH/SRS |
| `+sixgr/+phy/+rx` | Shared RX-side helpers such as channel estimation/equalization-related logic |
| `+sixgr/+phy/+sync` | Synchronization/cell-search style blocks |
| `+sixgr/+phy/+refsig` | Reference signal helpers |
| `+sixgr/+phy/+mimo` | MIMO, precoding, rank/layer-related helpers |
| `+sixgr/+phy/+waveform` | Waveform construction helpers |
| `+sixgr/+phy/+phycode` | Coding/PHY-code related helpers |
| `+sixgr/+phy/+mod` | Modulation/demodulation helpers |
| `+sixgr/+phy/+tb` | Transport-block helpers |
| `+sixgr/+phy/+scramble` | Scrambling/interleaving-related helpers |
| `+sixgr/+phy/+rrc` | PHY-facing RRC helpers/data |
| `+sixgr/+phy/+grid` | Resource-grid mapping helpers |

### The `+sixgr/+lls6g` package map

This is the config-driven LLS framework introduced for scenario-defined execution.

| Path | Role |
| --- | --- |
| `+sixgr/+lls6g/+config` | YAML reader, schema validation, scenario registry, parameter catalog access, resolved-config object |
| `+sixgr/+lls6g/+runners` | Single-scenario and matrix execution |
| `+sixgr/+lls6g/+kpi` | KPI helpers used by the LLS framework |
| `+sixgr/+lls6g/+cases` | Case definitions or case helpers for LLS execution |
| `+sixgr/+lls6g/+ai` | AI-related scenario helpers within the LLS framework |

### `simulator/configs/` map

The `simulator/configs/` tree is the main home for the YAML-based LLS framework.

| Path | Purpose |
| --- | --- |
| `simulator/configs/defaults/` | Global/shared defaults |
| `simulator/configs/scenarios/` | Concrete runnable scenarios and scenario suites |
| `simulator/configs/scenario_families/` | Higher-level grouping/coverage manifests |
| `simulator/configs/schema/` | Parameter catalogs and validation schema inputs |
| `simulator/configs/bands/` | Band packs |
| `simulator/configs/channels/` | Channel packs |
| `simulator/configs/coding/` | Coding packs |
| `simulator/configs/control/` | Control-channel related packs |
| `simulator/configs/reference_signals/` | RS-related packs |
| `simulator/configs/initial_access/` | Initial-access / PRACH / access-related packs |
| `simulator/configs/harq/` | HARQ-related packs |
| `simulator/configs/mimo/` | MIMO/beam/rank/layer packs |
| `simulator/configs/impairments/` | Impairment packs |
| `simulator/configs/energy/` | Energy/profiling related packs |
| `simulator/configs/ai_ml/` | AI/ML packs |
| `simulator/configs/waveforms/` | Waveform packs |
| `simulator/configs/models/` | Supporting model-related config packs |
| `simulator/configs/releases/` | Release/profile-specific packs |

### Useful shipped scenarios to know by name

If you are browsing `simulator/configs/scenarios/` for the first time, these are especially useful anchors:

| Scenario file | Why it is useful |
| --- | --- |
| `dl_4ghz_baseline.yaml` | Simple single-scenario LLS starting point |
| `dl_700mhz_coverage.yaml` | Coverage-oriented downlink example |
| `dl_7ghz_mimo4x4.yaml` | Higher-order MIMO example |
| `ul_4ghz_cpofdm.yaml` | Basic uplink CP-OFDM example |
| `ul_4ghz_dfts_pi2bpsk.yaml` | Uplink DFT-s-OFDM / pi/2-BPSK example |
| `prach_detection.yaml` | Initial-access / PRACH-oriented scenario |
| `pdcch_blind_decode_sweep.yaml` | Control-channel sweep example |
| `lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml` | Canonical truth-style LLS scenario |
| `lls_harq_retransmission_exercise.yaml` | Dedicated stressed HARQ exercise scenario |
| `matrix_regression.yaml` | Broad LLS matrix/regression suite |
| `HARQ_AND_RETRANSMISSION.yaml` | HARQ-focused grouped scenario file |
| `AI_ML_AND_ENERGY.yaml` | AI/ML and energy-focused grouped scenario file |

### The legacy `config/` tree

Do not confuse `config/` with `simulator/configs/`.

The `config/` directory is still important, but it serves the broader/older configuration path used by `sixgr.config.loadConfig` and the full campaign stack.

Main subfolders:

| Path | Purpose |
| --- | --- |
| `config/phy/` | PHY JSON fragments |
| `config/channel/` | Channel JSON fragments and tables |
| `config/traffic/` | Traffic model fragments |
| `config/energy/` | Energy model fragments |
| `config/ai/` | AI-related JSON fragments |
| `config/io/` | Output/export-related JSON fragments |
| `config/presets/` | Preset JSON configs |

### The `docs/` tree

Important docs currently present:

| File or folder | Purpose |
| --- | --- |
| `docs/result_output_layout.md` | Canonical run folder/result-tree documentation |
| `docs/6g_phy_lls_config_driven_framework.md` | Compact overview of the config-driven 6G LLS framework |
| `docs/6g_lls/` | Larger deliverables/specification pack |

### The `tests/` tree

This is a large regression suite, not just a few smoke tests. It covers:

- config normalization and validation,
- scenario schema/catalog coverage,
- PHY reference-point execution,
- LLS reporting integrity,
- availability/coverage semantics,
- HARQ exercise behavior,
- truth/proxy separation,
- E2E truth semantics,
- artifact integrity and naming,
- system/hybrid coupling behavior.

The master entry point is:

- `tests/testAll.m`

## Major Entry-Point Files

This section explains the files most people need to know first.

### `setup6GRSimToolkit.m`

Purpose:

- sets up the MATLAB path,
- optionally adds non-package subfolders,
- optionally checks toolboxes/capabilities.

Use it first in almost every session.

### `run_6g_phy_lls_single.m`

Purpose:

- minimal front door for one config-driven LLS scenario.

Behavior:

- validates required arguments,
- defaults `outputDir` to `results`,
- delegates real execution to `sixgr.lls6g.runners.runSingle`.

Use this when you want one scenario, one result bundle, and a clean front door.

### `run_6g_phy_lls_matrix.m`

Purpose:

- minimal front door for a matrix of scenarios.

Behavior:

- loads and validates a matrix config,
- creates a matrix run root,
- runs each scenario, sequentially or in parallel depending on config,
- writes scenario/point/suite summary CSVs.

Use this for regression suites and scenario sweeps.

### `run_truth_validation_profile.m`

Purpose:

- runs a stricter truth-validation wrapper flow.

Why it exists:

- it combines a base truth E2E pass with supplemental waveform link/control exports,
- verifies artifacts,
- scans for proxy/fallback contamination,
- writes a dedicated truth validation report and manifest.

Use it when your question is not just "did the simulator run?" but "did the truth-mode result bundle stay semantically honest?"

### `sixgr_run_3gpp_full_campaign.m`

Purpose:

- the broader unified campaign orchestrator.

It can coordinate:

- waveform link-level outputs,
- detailed link diagnostics,
- system-level outputs,
- mMTC probes,
- auxiliary probes,
- E2E stack probes,
- structured metadata,
- campaign plots,
- artifact verification.

If you need the most general run surface, this is the main orchestrator.

### `Start6GRSimToolkit.m`

Purpose:

- setup + GUI launch helper.

Behavior:

- runs `setup6GRSimToolkit`,
- launches `SimSuiteGUI` if available,
- otherwise prints CLI usage guidance.

### `apps/SimSuiteGUI.m`

Purpose:

- pure-code MATLAB GUI for the unified simulator.

Notable points from the file header:

- it is a `uifigure`-based GUI, not an `.mlapp`,
- it is designed to integrate with the `+sixgr` library,
- it can accept a config struct or config path.

### `SixGR_Simulator.m`

Purpose:

- deprecated compatibility wrapper.

Important:

- it is intentionally retained for backward compatibility,
- it forwards work to `sixgr_run_3gpp_full_campaign`,
- new work should generally call the full campaign directly instead.

## Configuration Systems

One of the most important things to understand in this repo is that there are two related configuration systems.

### System 1: Legacy/general JSON config path

This is used by the broader campaign stack.

Main code:

- `sixgr_loadConfig.m`
- `+sixgr/+config/loadConfig.m`
- `+sixgr/+config/normalizeConfig.m`
- `+sixgr/+config/validateConfig.m`

What it does:

1. loads defaults,
2. loads optional modular JSON fragments from `config/`,
3. optionally loads a preset,
4. merges user config over defaults/fragments/preset,
5. normalizes aliases and dependent fields,
6. validates consistency.

Use this path when you are working with:

- `sixgr_run_3gpp_full_campaign`,
- `run_truth_validation_profile`,
- the GUI in legacy/general config mode.

### System 2: Config-driven YAML LLS scenario path

This is the newer LLS scenario framework.

Main code:

- `+sixgr/+lls6g/+config/readConfigFile.m`
- `+sixgr/+lls6g/+config/loadScenarioConfig.m`
- `+sixgr/+lls6g/+config/normalizeScenarioAliases.m`
- `+sixgr/+lls6g/+config/validateScenarioConfig.m`
- `+sixgr/+lls6g/+config/ScenarioConfig.m`

What it does:

1. reads one YAML scenario file,
2. recursively resolves all `inherits` parents,
3. merges the inheritance chain,
4. normalizes aliases,
5. validates schema/compatibility,
6. computes a config hash,
7. wraps the result in an immutable `ScenarioConfig` object.

This is the config system behind:

- `run_6g_phy_lls_single`
- `run_6g_phy_lls_matrix`

### Why both systems exist

Because the repository is serving more than one execution style:

- the older/general campaign flow still uses the JSON-config stack,
- the config-driven 6G LLS framework uses the newer YAML/scenario stack.

When documenting or debugging behavior, always identify which stack you are in first.

## How the Main Run Flows Work

This section is a conceptual walkthrough of the main execution flows.

### Flow A: Single config-driven LLS scenario

High-level path:

1. `run_6g_phy_lls_single`
2. `sixgr.lls6g.runners.runSingle`
3. `sixgr.lls6g.config.loadScenarioConfig`
4. runner-specific scenario execution
5. result layout + manifests + CSV/image/report export

What `runSingle` does at a high level:

- calls `setup6GRSimToolkit`,
- loads a resolved `ScenarioConfig`,
- creates a clean run folder,
- dispatches to the appropriate runner profile,
- writes meta/report artifacts.

Inside `runSingle`, different scenario runner profiles trigger different execution branches. Examples visible from the file include:

- waveform bundle scenarios,
- PRACH detection scenarios,
- PDCCH blind decode sweeps,
- AI benchmark scenarios,
- generic sweeps.

This is why the YAML scenario field `scenario.runner_profile` matters so much.

### Flow B: Matrix config-driven LLS execution

High-level path:

1. `run_6g_phy_lls_matrix`
2. `sixgr.lls6g.runners.runMatrix`
3. matrix config validation
4. per-scenario calls to `runSingle`
5. aggregation into combined summary CSVs

What `runMatrix` adds on top of `runSingle`:

- a matrix root folder,
- scenario repetition handling,
- optional parallel scenario execution,
- combined scenario/point/suite summaries,
- matrix manifest and config snapshots.

Outputs you should expect from a matrix root:

- `meta/matrix_config_resolved.json`
- `meta/matrix_manifest.json`
- `reports/csv/matrix_scenario_summary.csv`
- `reports/csv/matrix_point_summary.csv`
- `reports/csv/matrix_suite_summary.csv`
- `runs/...` with all child scenario runs

### Flow C: Truth-validation profile

High-level path:

1. `run_truth_validation_profile`
2. setup and config load/prepare
3. `sixgr_run_3gpp_full_campaign(..., "OnlyE2E", true, ...)`
4. `sixgr.truth.runWaveformLinkBundle` for supplemental waveform artifacts
5. `sixgr.truth.exportControlPlaneTraces`
6. `sixgr.truth.scanTruthArtifacts`
7. `sixgr.report.verifyCampaignArtifacts`
8. report + manifest writeout

This profile is especially useful when you care about:

- truth-only semantics,
- no proxy/fallback contamination,
- artifact completeness,
- reproducibility evidence,
- honest reporting.

### Flow D: Full campaign

High-level path:

1. `sixgr_run_3gpp_full_campaign`
2. config load/merge/normalize/validate
3. run-folder creation and logging setup
4. optional link-level run
5. optional detailed diagnostics
6. optional system-level run
7. optional mMTC/auxiliary/E2E probes
8. export reports, manifests, checks, and summaries

It is the broadest orchestration layer in the repo.

## Results and Artifact Layout

The canonical result layout is documented in `docs/result_output_layout.md`.

### Top-level results buckets

Runs are generally organized under:

```text
results/
  lls/
  sls/
  e2e/
```

### Canonical run tree

Typical run folders are organized like this:

```text
<runFolder>/
  meta/
  reports/
    csv/
    mat/
    image/
  logs/
  air_interface/
    csv/
    mat/
    image/
    logs/
    detailed/
      csv/
      mat/
      image/
      logs/
  control/
    csv/
    image/
  harq/
    csv/
  system/
    csv/
    mat/
    image/
    logs/
  mmtc/
    csv/
    mat/
    image/
    logs/
  interference/
    csv/
  beamforming/
    csv/
  numerology/
    csv/
  rf/
    csv/
  v2x/
    csv/
  ntn/
    csv/
  packet_flow/
    csv/
    mat/
    image/
    logs/
  calibration/
```

### How to think about these folders

| Folder | Meaning |
| --- | --- |
| `meta/` | Reproducibility data: resolved config, manifests, config chains, environment/context |
| `reports/` | Human-readable and analysis-ready rollups: CSVs, MAT files, plots, markdown |
| `air_interface/` | LLS/truth waveform outputs and detailed PHY diagnostics |
| `control/` | Control-plane traces and related outputs |
| `harq/` | HARQ probe and summary CSV outputs |
| `system/` | System-level/SLS outputs |
| `packet_flow/` | E2E stack/packet-flow outputs |
| `logs/` | Run logs |

### Common files you will inspect after a run

At minimum, these are often worth opening:

- `meta/scenario_config_resolved.json`
- `meta/scenario_manifest.json`
- `reports/csv/scenario_summary.csv`
- `reports/csv/lls_output_spec_coverage.csv`
- `reports/executive_summary.md`
- `reports/technical_report.md`
- `air_interface/csv/*.csv`
- `reports/image/*.png`

For matrix runs, also inspect:

- `reports/csv/matrix_scenario_summary.csv`
- `reports/csv/matrix_point_summary.csv`
- `reports/csv/matrix_suite_summary.csv`

## Important Output/Truthfulness Semantics

This repository is opinionated about result honesty. That matters when you read the code and when you interpret outputs.

### Truth vs proxy separation

The repo distinguishes true waveform/truth execution from approximations such as:

- LUT,
- logistic,
- fast proxy,
- synthetic,
- fallback.

Important principle:

- outputs should not relabel proxy data as truth.

If you are editing exporters, manifests, summary tables, or report wording, keep this distinction explicit.

### No fake primary rows

Primary tables are not supposed to be padded with invented rows just to keep shapes stable. If real data is unavailable, the correct behavior is generally:

- leave the table empty,
- skip the artifact, or
- mark it unavailable honestly.

### Availability semantics matter

The reporting system uses semantic availability states so that:

- observed runtime evidence,
- derived metrics,
- config-only claims,
- disabled features,
- placeholders,
- unsupported items,
- not-available items,
- not-exercised items

are not all counted as the same thing.

That is a deliberate design choice. It means some metrics or plots may disappear or be marked unavailable when semantics are tightened. That is usually a correction, not a regression.

### Configured vs effective behavior

The codebase also distinguishes:

- configured/nominal parameters, and
- effective runtime-selected behavior.

That matters especially for:

- MIMO rank/layers,
- modulation,
- MCS,
- HARQ activity,
- access-delay semantics,
- compute latency vs radio/procedure delay.

When reading reports, do not assume the configured scenario description means the runtime sustained that operating point.

## Tests and Validation Workflow

The master regression entry point is:

```matlab
testAll
```

Or explicitly:

```matlab
report = testAll();
```

From `tests/testAll.m`, this is a broad suite covering:

- config/catalog/schema correctness,
- 6G LLS scenario framework coverage,
- PHY reference points and regressions,
- MIMO/precoding,
- channel-estimation and channel-profile guards,
- LLS result richness/report bundle correctness,
- availability aggregation,
- HARQ exercise semantics,
- status propagation,
- strict coverage/output completeness,
- truth/proxy guards,
- E2E truth packet semantics,
- artifact integrity,
- scheduler grant consistency,
- PDCP/RLC conservation and security profiles.

### Recommended validation commands

If you just changed code and want broad confidence:

```matlab
setup6GRSimToolkit("Verbose", false);
testAll;
```

If you are focused on config/channel/LLS reference behavior:

```matlab
setup6GRSimToolkit("Verbose", false);
testConfig;
testLLS_DL;
testLLS_UL;
testLLS_ReferencePoints;
```

If you changed truth/proxy separation, E2E semantics, manifests, or export/report integrity:

```matlab
setup6GRSimToolkit("Verbose", false);
testE2E_FastVsTruth;
testE2E_TruthPacketSemanticCampaign;
```

### Helpful targeted tests

Some especially useful focused tests to know by name:

- `testLLSReportBundle`
- `testLLSAvailabilityAggregation`
- `testLLSHARQExercise`
- `testLLSEffectiveOperatingPointSummary`
- `testLLSResultRichness`
- `testLLSScenarioStatusPropagation`
- `testStrictProxyGuards`
- `testNoProxyTruthContract`
- `testSchedulerGrantConsistency`
- `testTruthValidationProfile`

## How to Add or Modify a Scenario

### For the config-driven YAML LLS framework

This is the preferred path for new LLS scenarios.

1. Create or copy a scenario file under `simulator/configs/scenarios/`.
2. Use `inherits:` to compose it from existing packs.
3. Override only scenario-specific fields.
4. Run it through `run_6g_phy_lls_single`.
5. Inspect the resolved config and exported reports.

Very small example:

```yaml
inherits:
  - ../defaults/global.yaml
  - ../bands/band_4ghz.yaml
  - ../channels/tdl_c.yaml
  - ../waveforms/cp_ofdm.yaml

meta:
  scenario_id: my_new_scenario
  scenario_title: My New Scenario

scenario:
  runner_profile: waveform_bundle
  target_cases: ["dl_pdsch", "ul_pusch"]
```

### How inheritance resolution works

From `+sixgr/+lls6g/+config/loadScenarioConfig.m`:

1. the file is read,
2. parents in `inherits` are recursively resolved first,
3. parents are merged in order,
4. the local file is merged on top,
5. aliases are normalized,
6. validation runs,
7. a config hash is generated.

### For the legacy/full-campaign config path

If you are modifying broader campaign behavior rather than adding a YAML LLS scenario:

- work in `config/*.json` fragments or presets,
- use `sixgr.config.loadConfig`,
- run the full campaign or truth-validation profile.

## Troubleshooting

### "Function not found" or package/class not recognized

Usually means MATLAB path setup has not been done for the current session.

Run:

```matlab
setup6GRSimToolkit
```

### Scenario YAML does not resolve

Check:

- the file exists,
- `inherits` paths are correct relative to the scenario file,
- the inherited file exists under `simulator/configs/...`,
- the scenario passes schema validation.

The relevant loader/validator code is in:

- `+sixgr/+lls6g/+config/loadScenarioConfig.m`
- `+sixgr/+lls6g/+config/validateScenarioConfig.m`

### Full campaign config fails validation

Check:

- required fields exist,
- channel family/profile is concrete and not ambiguous,
- duplicated fields are not contradictory,
- waveform and transform-precoding settings are consistent.

Relevant code:

- `+sixgr/+config/normalizeConfig.m`
- `+sixgr/+config/validateConfig.m`

### Results folder looks strange or incomplete

Check:

- whether you ran a single scenario, matrix, truth-validation profile, or full campaign,
- whether artifacts were intentionally skipped by scope,
- whether the output was suppressed because a feature was disabled, not supported, not exercised, or not available,
- whether the run failed early and only partially exported.

Use:

- `meta/*.json`
- `logs/*.log`
- `reports/csv/*coverage*.csv`
- `reports/executive_summary.md`

### Performance is poor

Possible causes:

- MEX accelerators not built,
- parallelism disabled,
- truth-mode waveform execution being used intentionally,
- large matrices or large E2E truth budgets.

Things to inspect:

- `sixgr_build_mex_accel.m`
- campaign options such as `UseMexAcceleration`, `UseParallelAcceleration`, `AutoStartParallelPool`
- scenario scope and Monte Carlo settings

### GUI does not launch

Try:

```matlab
setup6GRSimToolkit
app = SimSuiteGUI();
```

If that still fails:

- check MATLAB version,
- check UI support in your installation,
- try CLI runners first to verify core simulator health.

## Shared eight-point sweep outputs

For a waveform-bundle SNR sweep, use the **parent run folder**, not a single
`sweeps/<point>` folder, for comparisons across all configured SNR points:

- `reports/csv/sweep_comparison_manifest.csv` maps each source table/plot to its
  shared output and lists missing completed points separately from unfinished points.
- `reports/csv/sweep_combined__*.csv` contains exact source rows from completed
  points, with explicit point, configured SNR, source path and completion status.
- `reports/image/sweep_combined__*.png` contains SNR-labeled original plot panels;
  unavailable or unfinished points are identified explicitly, not replaced by curves.
- `reports/csv/sweep_link_comparison.csv` and
  `reports/image/sweep_link_comparison.png` provide common-SNR-axis comparisons.
  Mean per-attempt goodput is **not** whole-run wall-clock throughput.

The WebGUI's realtime **SNR sweep progress** panel lists all points, their slot
progress, passed/failed completion, ongoing finalization and pending execution.
These are persisted states, not a guarantee that the MATLAB process is still alive.
Per-point raw evidence remains intact for diagnosis. Publication of a shared file
does not turn a failed point into a passing point or fill absent measurements with zero.

The runner exports shared results at sweep completion. To refresh shared files as
points finish in an already-running sweep, run this separately (it does not start MATLAB):

```cmd
python scripts\export_lls_sweep.py --run-folder "<parent-run-folder>" --watch
```

## Detailed Documentation Pack

If you want more than this README, the best next documents are:

### Architecture/specification pack

- `docs/6g_lls/README.md`
- `docs/6g_lls/delivery_overview.md`
- `docs/6g_lls/architecture.md`
- `docs/6g_lls/config_schema_reference.md`
- `docs/6g_lls/block_diagrams_and_parameters.md`
- `docs/6g_lls/processing_chains.md`
- `docs/6g_lls/scenario_library.md`
- `docs/6g_lls/scenario_family_library.md`
- `docs/6g_lls/result_specification.md`
- `docs/6g_lls/validation_rules.md`
- `docs/6g_lls/sweep_framework.md`

### Supporting docs

- `docs/LLS_RUNBOOK.md` — exact YAML commands for the 12 dB TDD run, an
  eight-point configured-SNR sweep, FDD and 400 MHz examples, feature toggles,
  validation, output inspection, and timestamped `testAll` logs
- `docs/6g_phy_lls_config_driven_framework.md`
- `docs/result_output_layout.md`

## Practical "Start Here" Recommendations

If you are brand new to the repo, this is the shortest good path:

1. Run `setup6GRSimToolkit`.
2. Read this README once front to back.
3. Read `docs/6g_phy_lls_config_driven_framework.md`.
4. Open `docs/result_output_layout.md`.
5. Run one known-good scenario with `run_6g_phy_lls_single`.
6. Inspect the generated `meta/`, `reports/`, and `air_interface/` folders.
7. Read `+sixgr/+lls6g/+runners/runSingle.m`.
8. Read `+sixgr/+truth/runWaveformLinkBundle.m`.
9. Run `testAll`.

If your goal is research iteration on LLS scenarios:

1. work mostly under `simulator/configs/`,
2. use `run_6g_phy_lls_single` and `run_6g_phy_lls_matrix`,
3. inspect resolved configs and coverage/summary CSVs,
4. keep configured vs effective and truth vs proxy semantics explicit.

If your goal is broader campaign or E2E validation:

1. learn `sixgr_run_3gpp_full_campaign`,
2. learn `run_truth_validation_profile`,
3. study `+sixgr/+truth` and `+sixgr/+report`,
4. use the truth/proxy and artifact-integrity tests aggressively.
