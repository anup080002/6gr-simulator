# SixGR Foundation v2

## Current SLS delivery status (2 October 2026)

The repository provides YAML-selected LLS and SLS entry points, a network SLS
runner, calibration collection, causal CSI/SRS feedback, resource accounting,
and source-labelled exports. **This is not yet an accepted 21-cell study
result.** The production SLS template intentionally has no calibration file
or SHA256. The retained DL/UL SISO calibration is a population-design pilot:
292 episodes were collected in v5, 0/336 conditional audit rows qualified, and
the current v6 design has not been executed. Its SISO/ideal-RF key also cannot
validate the 4-by-4 network template. Statistical BLER/HARQ coverage, S0 load
calibration, integrated RF/array qualification and paired confidence intervals
remain open. Do not fill the empty calibration fields with a test fixture or
interpret an SLS execution receipt as primary-study acceptance.

Use the calibration command below to collect the next *pilot* increment. To
run SLS after an independently accepted, matching calibration exists, set
`sls.config.system.linkAbstraction.calibrationFile` and
`calibrationSHA256` in
`simulator/configs/scenarios/sls_network_calibrated.yaml`, then use the SLS
command in [YAML-selected LLS and SLS](#yaml-selected-lls-and-sls). Until those
fields and the matching physical coverage are supplied, that SLS command is
expected to fail closed; there is no honest "all scenarios ready" command.

## Generic DL/UL BLER and HARQ calibration

`run_link_calibration(configPath, outputRoot, runTag)` uses the existing
production PDSCH/PUSCH waveform adapters, independently of any agenda item.
The initial configuration is
`configs/calibration/nr_dl_ul_harq_baseline.yaml`: 4 GHz, 20 MHz carrier,
24 allocated PRBs, SISO QPSK / NR table-1 MCS 4 (308/1024), AWGN reference
and TDL-A/30 ns target, RV `[0,2]`. It explicitly uses practical DMRS channel
estimation, toolbox LDPC (custom MEX disabled), known noise variance, ideal timing and independent channel
realizations between attempts. These assumptions do not qualify RF-impaired,
multi-layer or correlated-channel HARQ cases.

Windows Command Prompt, from the repository root:

```bat
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\link_calibration_20261002_v6_01.log" -batch "setup6GRSimToolkit('Verbose',false); receipt=run_link_calibration('configs/calibration/nr_dl_ul_harq_baseline.yaml','results/calibration','nr_dl_ul_20261002_v6'); disp(receipt);"
```

One invocation collects at most 292 new episodes and resumes the same tag
without rerunning committed episodes. Use a new launcher log filename when
resuming. Changed scientific configuration, source or MATLAB/toolbox versions
require a new tag; observations from different execution versions are not pooled.
The configured population-design pilot contains 14,746 episodes across two
directions, four independent roles and their Cartesian SNR histories. The
reference and fading-fit roles have 100 starts/history; the independent
held-out roles have one smoke episode/history and **cannot** qualify validation.
It is **not** a statistically accepted calibration. The four roles are reference
AWGN, independent reference-validation AWGN, fading fit and held-out fading
validation. The first invocation collects one starting TB per case/role/history.
Do not interpret the invocation budget as statistical sufficiency or loop
unattended before inspecting `population_feasibility.csv` and the
conditional-population audit. The feasibility file is a deterministic upper
bound from frozen starting TBs, **not observed trials**. Under the current
0.02 independent-AWGN BLER-difference policy, identical 95% Wilson intervals
at BLER 0.5 require at least **9,600 trials in each independent reference
cohort** even before allowing for sampling differences. The 100-start pilot
cannot qualify any conditional cell under its frozen population, even if
every eligible retransmission occurs. A separate fixed-population expansion
is required after an independent pilot; validation samples must not be reused
to choose that plan.

Reference and target coverage are now independent YAML fields:
`reference_snr_axis_db: [-24,-18,-12,-6,0,6,12,18]` and
`target_snr_axis_db: [-6,0,6]`. Widening the AWGN envelope no longer moves
the fading operating points. This is a pilot envelope, not a guarantee for
every fading realization or a qualified dense HARQ reference surface.
`reference_domain_audit.csv` checks actual fit-only per-RE features over the
declared beta bounds without consulting held-out outcomes or extrapolating.

`conditional_population_plan.csv` uses only reference/fit pilot episodes,
not validation CRCs. It estimates preceding-failure reachability with
one-sided exact binomial bounds and simultaneous Bonferroni protection,
then solves for a **fixed** fresh starting population. Reference cohorts use
the independent-pair planning floor rather than the generic 2,000-trial
minimum. This floor is necessary at the BLER transition, not a guarantee that
two random cohorts will pass the 0.02 bound. Zero observed preceding
failures, fewer than 100 pilot starts, or a requirement exceeding the declared
budget remain unsupported. No retransmission is forced after a successful CRC.
The plan is advisory: it does not top up a validation cohort until it passes.
Freeze accepted quotas in a new YAML/new run with independent seeds, using
`starting_population_overrides` entries with `case_id`, `role`,
`history_index` (MATLAB Cartesian order), and `starting_tbs`. Unlisted cells
use `populations`; fit and validation quotas are independently declared.
Actual conditional counts and confidence checks still decide acceptance.
Do not launch the entire provisional population until these pilot checks
establish feasible coverage and storage/runtime requirements.

The run retains source snapshots/hashes and `campaign.mat`, lossless physical
episodes with checksums, `receipt.json`, `conditional_population_audit.csv`
and `fitting_status.json`. Future episodes use lossless MATLAB v7 storage; an
exact load-and-compare probe reduced one episode from 1,095,096 to 33,511
bytes. `reference_validation` supplies a second physical AWGN population.
The numerical EESM fitter uses only fit CRCs to
select beta, validates each held-out history group, and rejects reused seeds,
unidentifiable beta and reference-domain extrapolation. Confidence and beta
search settings are implementation/study policy, not prescribed 3GPP values.
Collection completion and fitted reports do **not** install a production SLS
calibration: matching network-provider/allocation/RF keys and the complete
required coverage matrix must still be established.
An SLS curve may mark unobserved conditional grid cells unsupported. Its
runtime interpolation checks all required grid corners and rejects missing
coverage. Accepted curve cells still require real waveform counts, retained
independent AWGN validation and fit/held-out checks. First HARQ attempts are
recorded with `PriorAttemptsFailed=false`; later attempts require actual prior
CRC failures. Production source CSV rows must resolve to retained, checksum
protected decoder episodes and agree on SNR history, MCS, rank, TBS, ports,
channel, ideal-RF branch, equalizer, CRC and seeds. The current 4-by-4 SLS network template cannot use
the SISO pilot as its production calibration.

The first 2026-10-02 pilot (`nr_dl_ul_20261002_v2`) retained 54 episodes / 76
physical attempts. None of its 72 conditional cells meets the population
gate; five fitting attempts are outside the initial reference domain for
every permitted beta. **Do not loop that pilot grid into a production
calibration.** Reference-domain coverage and conditional HARQ population
design need revision, with fresh independent validation populations.
The dedicated regression also exposed inherited SSB exclusions in the
standalone DL builder; the builder now disables that untransmitted broadcast
signal for data-only calibration. Its unchanged baseline regression passes
after this fix. The UL builder also forwards its configured MCS-table identity.
The post-fix pilot (`nr_dl_ul_20261002_v3`) completed 54 episodes / 75 attempts;
its population and reference-domain gaps remain, and no production calibration
was installed. Earlier pilot files remain unchanged and unqualified; different
source revisions are not pooled. Physical feedback timing, access and
throughput are not qualified by this transport-block collector.

The separated-grid pilot (`nr_dl_ul_20261002_v4`) completed **164 episodes /
250 physical attempts** on 2026-10-02. Its 29 fit-role attempts are all inside
the widened reference domain across the declared beta bounds. **0/192
conditional cells qualify statistically**; the wider grid increases the
number of reference cells. All 146 second-attempt population-plan entries
still need more independent pilot starts. These are distinct new-seed data,
not relabeled or pooled v3 observations. Four dedicated calibration checks
pass; this is not acceptance of all SLS configurations or the full regression
suite. The current SLS package loader also needs validated curve-tensor and
physical-key binding from the fitted collection before production installation.

The later v5 source revision retained **292 independent episodes / 440 physical
attempts**. Its 26 observed target-fit attempts stayed inside the widened
reference domain, but 0/336 role-specific conditional audit rows qualified.
It is preserved under `results/calibration/nr_dl_ul_20261002_v5` as an
unqualified pilot. The population-feasibility correction changed source
identity, so do not append current-code episodes to v5; use the v6 tag above.

## YAML-selected LLS and SLS

`run_sixgr(configPath, outputDir, runTag)` is the shared entry point. Existing
`run_6g_phy_lls_single` commands remain supported. Execution scope and PHY
backend are separate: SLS can use waveform replay or explicitly calibrated
link abstraction; selecting SLS does not make modeled metrics waveform truth.

| Control | LLS | SLS |
|---|---|---|
| YAML mode | `run_control.execution_mode: LLS` (legacy default) | `run_control.execution_mode: SLS` |
| Configuration | Existing ScenarioConfig YAML/inheritance | `sls.config` native configuration, plus explicit `sls.config_files` |
| Engine | Existing config-driven LLS runner | `sixgr.system.SystemLevelRunner` |
| Backend | Existing scenario-selected PHY execution | Explicit `system.phyBackend`: `waveform` or `calibrated_link_abstraction` |
| WebGUI | Existing PHY live panels and artifacts | Network progress, KPIs, UE/load/file metrics and modeled CSI/SRS/UCI tables |
| Results root | `results/lls/<scenario>/<tag>` | `results/sls/<scenario>/<tag>` |

Select a matching YAML in Configure; its fields are editable in Parameters.
LLS/SLS is also selectable in Configure. Changing the selector alone does not
convert an LLS configuration to SLS. Live and Results have an **All modes / LLS /
SLS** filter. SLS discovery uses its own durable run receipt and does not invoke
the LLS terminal materializer or manufacture missing waveform plots.

Generic SLS template: `simulator/configs/scenarios/sls_network_calibrated.yaml`.
This is **not a ready/qualified study**: its calibration path and SHA256 are
deliberately empty. Bind accepted waveform-derived calibration matching the
configured link keys before execution. Test-only calibration is rejected by
the public front door. Native fragments resolve in declared order, followed by
`sls.config`; scenario-name-derived presets and implicit local fragments are
not loaded. Default native parameters come from
`simulator/configs/schema/core_parameter_catalog.yaml` and may be overridden
under `sls.config`.

Windows **Command Prompt** (only after binding/validating a production SLS
calibration matching every configured key; the YAML as shipped fails closed):

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\sls_network_v1.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_sixgr('simulator/configs/scenarios/sls_network_calibrated.yaml','results','sls_network_v1'); disp(out); assert(out.Ok);"
```

Use a fresh tag for every SLS run; an existing folder is never overwritten.
To use the shared front door for an existing LLS scenario:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\lls_5mhz_v1.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_sixgr('simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml','results','lls_5mhz_v1'); disp(out); assert(out.Ok);"
```

Start/restart the WebGUI separately to load updated Python code:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "apps\start_lls_web_dashboard.ps1"
```

SLS output flags are `sls.config.outputs.saveCSV`, `saveMAT`, `saveFigures`,
`saveFIG`, `detailedSystemTrace` and `exportSLSOutputCatalog`. Retained outputs
include `meta/simulation_run.json`, input/config snapshots, `logs/run.log`,
`summaries`, `tables`, `traces`, `maps`, `plots` and the original `csv`/`image`
artifacts. These cover network KPIs, scheduler grants/TBS, HARQ, resource
reservations/opportunities, interference, mobility, loads and FTP3 delivery
when those producers execute. No universal set of CSV/PNG filenames constitutes
3GPP qualification. Missing measurements are not synthesized to populate plots.

**Remaining scientific acceptance work:** conditional BLER/HARQ populations and
held-out validation, DL/UL calibration coverage, S0 utilization calibration,
RF-aware network/common-control interference, mobile beam/TCI and array
qualification, broader physical UCI qualification and paired 21-cell confidence
intervals. `ExecutionOk` and `PrimaryStudyAccepted` remain separate; the generic
runner does not certify those studies. No `testAll` or production campaign is
launched by the mode-dispatch tests.

Delivery branch: **`main`**, with one Git worktree. Source, scenario YAMLs,
launchers and development patches are versioned; generated results, logs and
instrument IQ remain separate local artifacts. No result or recovery stash is
removed by source consolidation.

Current status: the 27 September 2026 TDD integration is on `main`. The
5 MHz n39 and 20 MHz n39/CDL-C YAMLs, shared-control/runtime changes, result
publication changes and focused tests are versioned in one codebase.

| Item | Verified scope and remaining limit |
|---|---|
| 400 MHz / 7 GHz rank-2 Keysight package | Digital export/demo package exists. Not a 4 GHz carrier test; not a full physical-control/shared-feedback scenario. Hardware capability remains UNKNOWN. |
| Consolidated source | Receiver, PDCCH, CSI/SRS, power-authority, reporting and WebGUI edits are committed together on `main`; generated results remain outside Git. |
| TDD scenario integration | The current 5 MHz and 20 MHz scenarios resolve as TDD; the 20 MHz carrier is n39 at 1.900 GHz, 15 kHz SCS, 106 PRBs, FFT 2048 and 30.72 MSa/s. |
| Configured-SNR power authority | Fixed-SNR sweeps use normalized occupied-RE Es/N0. Absolute dBm, pathloss, O2I and thermal noise are isolated in a separate physical link-budget arm. |
| Focused validation | The 20 MHz TDD configuration suite passed 10/10 checks. The five-MHz eight-point noise-isolation check passed all points. |
| Full acceptance | The complete `testAll` run was stopped at operator request and is not claimed as passed. Eight-point end-to-end scenario acceptance, detector qualification and full-control 400 MHz acceptance remain open. |
| H4 / 4 GHz / 100 MHz TDD | A dedicated one-UE family now resolves 273 RB at 30 kHz, a 10/2/2 special slot, a two-panel 64-TXRU gNB, a four-chain UE, four active SSB beams, eight CSI-RS/data beam states, and rank capability 1/2/4 in both directions. Focused config/runtime tests pass; complete waveform qualification is not yet claimed. |

Historical recovery patches remain evidence only; do not apply them on top of
current `main`. A committed implementation is not automatically a qualified
scenario result. Use the commands below and retain the generated logs and
artifacts for the exact checked-out commit.

### AI 10.3.2: assumed 7 GHz phase noise and SLS readiness

The working study configuration is `configs/tdoc/ai_10_3_2_modulation/study.yaml`.
Its F1 waveform calibration now selects `lls.execution.rf_branch: pn7_ptrs_compensated`.
This is an **assumed research oscillator**, not a measured hardware mask or a
normative 7 GHz requirement. The explicit profile is
`simulator/configs/rf/phase_noise_nr_inspired_7ghz.yaml`: the TR 38.803 multipole-zero
shape at 29.55 GHz is frequency-scaled to 7 GHz. The 10 kHz low-offset cutoff with
flat continuation, common TX LO across chains, ideal RX LO, and FIR synthesis
resolution are disclosed assumptions. Parameters follow the
[MathWorks TR 38.803 modeling reference](https://www.mathworks.com/help/rf/ug/model-rf-impairments-in-5g-downlink-waveform.html).

| F1 RF branch | Phase noise | Transmitted PT-RS | Receiver phase tracking |
|---|---|---|---|
| `pn7_ptrs_compensated` | Enabled in transmitted samples; CPE and ICI | Enabled | Measured PT-RS CPE correction |
| `pn7_ptrs_uncompensated` | Same assumed profile and seed | Same allocation | Disabled |
| `pn_off_ptrs_reference` | Disabled | Same allocation | Disabled |
| `ideal_debug` | Disabled | Disabled | Disabled; separate overhead-free reference |

Select the branch in the YAML; keep separate calibration run tags. Never reuse
the ideal-reference thresholds for an impaired branch. The oscillator retains
state across waveform chunks, and the receiver does not receive its phase trace.
PT-RS correction does not remove all ICI and need not improve every realization.
UL 1024-QAM remains explicitly labelled as a research transport extension.

Dedicated checks from a Windows Command Prompt already at the repository root:

```bat
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_phase_noise_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testNRInspiredPhaseNoise; testRAN1AI1032PhaseNoisePTRS(25,[1 2 4]); testRAN1AI1032PhaseNoisePTRS(273,1);"
```

Retained component/paired-waveform evidence is under
`logs/nr_inspired_phase_noise_20261001/`. These checks are not statistical BLER
calibration or an accepted 21-cell SLS campaign. Dynamic PUCCH obligations,
production spatial/interference/feedback integration, calibrated BLER/HARQ,
measured S0 offered-load calibration, exact array qualification and paired-drop
confidence intervals remain acceptance gates. Hardware qualification is UNKNOWN.
No full `testAll` or network campaign is launched by the command above.

The selected SLS feedback assumption is **ideal delayed CSI/SRS**, not
waveform-measured feedback. The UL modeled-SRS consumer now binds delivered
observations to scheduler rank/TPMI/SRI and the frozen grant. Its CP-OFDM
codebook search uses constant total power and an explicitly configured
sum-log-rate objective; that selection objective is not a mandated 3GPP rule.
Spatial validity does not make missing/stale CQI valid. Source, availability,
control and data slots are exported in `csv/system_modeled_spatial_feedback.csv`
with `WaveformBacked=false`. The policy is in
`simulator/configs/system/calibrated_link_abstraction.yaml`; it remains disabled
by default until the campaign supplies its production channel/interference
observation provider. `NetworkSpatialGrantProvider` now supplies NR TDL/CDL
frequency-domain channels, reciprocal UL/DL link ownership, actual-grant overlap
covariance and calendar-bound ideal SRS. Select it with the internal-config
overlay `simulator/configs/system/network_spatial_ideal_tdd.yaml` after the
calibrated-abstraction fragment. This is an **ideal-RF port-domain baseline**,
not acceptance of the impaired 64-TXRU study: RF/array qualification remains
false. It rejects overlapping opposite-direction cross-links, which need
additional BS-to-BS/UE-to-UE channels. The configured equal-PSD rule, allocated
PRB/symbol footprint (including pilots), and noise-only full-band sounding rank
reference are explicit model assumptions requiring matching calibration.
Interference currently covers scheduled shared-data grants; common/control
signal interference is not yet included or qualified. Resource reservation
alone must not be presented as execution of those interferers.

`networkSpatial.channelResponseSampling` is `signal_rate` by default. The
explicit zero-Doppler-only `static_exact` alternative uses native TDL `PathGainSampleRate=auto`
or CDL `SampleDensity=64` for frequency-domain **SLS model** responses, avoiding
sample-rate path-gain tensors at large array dimensions. It retains per-RE
frequency/time responses and changes the channel calibration identity. It
does not change the waveform PHY or qualify RF, polarization, or mobility.
`testSLSNetworkChannelSampling` requires numerical equality against dense static
sampling and rejects moving channels. A moving-channel comparison failed; this
option is not an equivalent mobility path. `testSLSMultiBeamMapping(true)`
exercises all eight CSI resources at 273 PRBs with Doppler explicitly zero.
This frequency-domain provider requires the R2024b-or-later 5G Toolbox
`ChannelResponseOutput` interface; it is not currently an R2023b SLS backend.

The original UL integration test uses a labelled numerical spatial fixture
and is not a study-result command:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_spatial_feedback_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSCausalSpatialFeedback; testSystemFTP3CalibratedDelivery('UL');"
```

Physical HARQ calibration collection is separate from first-transmission F1.
`study.yaml` → `harq.calibration` configures complete SNR histories, independent
fit/validation episode counts, seed base and invocation budget. The executor
keeps the same TB and position-aware mother-code soft buffer across RVs, stops
at the first CRC pass, and records only actually executed conditional attempts.
Its explicit channel assumption is **independent attempt realizations**, with
ideal delayed control; it does not qualify correlated-channel HARQ or UCI.

From the repository root in Windows Command Prompt, this bounded command can
be repeated with the same tag to resume. It executes physical waveforms:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\sls_harq_collection.log" -batch "setup6GRSimToolkit('Verbose',false); receipt=sixgr.studies.ran1ai1032.runHARQCalibrationCampaign('configs/tdoc/ai_10_3_2_modulation/study.yaml','results/ai_10_3_2_modulation','harq_waveform_v1'); disp(receipt);"
```

Outputs are under `results/ai_10_3_2_modulation/harq_waveform_v1/harq/`:
per-case/history `fit_attempts.csv`, `validation_attempts.csv`, atomic MAT
checkpoints, input/source identity and a receipt. Interrupted CSV publication
is rebuilt from the checkpoint. Scientific/source changes require a new tag.
The default three diagonal SNR histories are **not** complete SLS calibration
coverage. Independent effective-SINR fitting, conditional population/error
gates, full RV-history coverage and SLS-key matching remain required before
packaging; collection completion never sets `PrimaryStudyAccepted=true`.

The network-provider integration check uses actual NR fading and configured
SRS, but still uses a **test-only BLER curve**, not accepted LLS calibration:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_network_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSNetworkSpatialProvider; testSystemNetworkSpatialDelivery;"
```

Its run folder contains `csv/system_modeled_spatial_feedback.csv` and
`csv/system_network_spatial_evidence.csv`. The latter records resource count,
per-RE transmit/noise power, overlapping interferers, inter-layer output power,
modeled SINR, profile identities and qualification flags. No received-waveform
measurement is fabricated, and `PrimaryResultEligible` remains false.

DL CSI integration is configured separately with
`system.linkAbstraction.dlFeedback.enabled`. It uses actual configured CSI-RS
resource coordinates, the periodic CSI reference/report calendar, ideal delayed
delivery, and the existing NR Type-I codebooks. Rank selection uses the declared
sum-log-rate study objective. CQI uses the installed mapping; enabling this path
does **not** qualify its calibration. `networkSpatial.dlAntennaBasis: direct_ports`
requires CSI, PDSCH and channel ports to agree. The optional
`configured_csirs_elements` mode uses the existing YAML-resolved
`phy.csirs.precoderMatrices`: one semi-unitary physical-TXRU-by-CSI-port matrix
per CRI. It supports the configured 64-TXRU/four-logical-port/eight-beam mapping
without substituting a scalar array gain. Enable the existing element-domain
PDSCH/hybrid mapping too. The calendar retains an explicit zero-based CSI
resource index, and the frozen data matrix is `B_CRI * W_PMI`. Candidates from
one report occasion are compared across their actual sweep source slots;
availability and maximum age still apply. RF/array qualification is separate.
New grants retain the report's rank and precoder, and retransmissions retain the
original binding. Modeled reports never become `ReceivedCSIReport` waveform evidence.

`system.linkAbstraction.dynamicPUCCH.enabled` creates receive obligations from
scheduled DL K1/PRI, configured SR calendars and causally available CSI references.
The default policy is `dedicated_pucch_no_pusch_multiplexing`, with explicitly
ideal error-free delayed control. Set `phy.pucch.uciOnPUSCHEnabled=false`; the
scheduler excludes same-UE PUSCH on these feedback occasions. Installed PUCCH
resource selection, capacity and TDD checks remain active. Unsupported overlaps
and collisions fail rather than silently discard obligations. This does not
qualify physical UCI decoding, missed DCI or MU control multiplexing.

The opt-in `causal_native_pusch_multiplexing` policy requires
`phy.pucch.uciOnPUSCHEnabled=true`. It binds one same-cell HARQ/CSI obligation
known at the control slot to a symbol-overlapping, future native NR PUSCH.
The issued grant retains its native coded-bit/RE UCI plan and exact digest;
data-only BLER calibration cannot be reused for that allocation. SR is not
added as a PUSCH payload bit or claimed as delivered. Standalone SR and
multiple unsupported obligations keep dedicated PUCCH. Late changes to an
issued obligation fail closed rather than mutate its allocation. This is a
conservative ideal-control SLS subset, not physical missed-DCI qualification.
Completion requires the selected PUSCH to execute, and CSI/HARQ consumers
require the modeled transport completion. Ideal-control completion is
independent of the modeled UL-SCH CRC outcome and is labelled explicitly.

Dedicated software checks (test-only BLER calibration, not a study campaign):

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_dl_csi_pucch_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSDLCSIFeedback; testSLSDynamicPUCCH; testSystemNetworkDLCSI;"
```

Additional exports are `csv/system_modeled_dl_csi.csv` and
`csv/system_dynamic_pucch_obligations.csv`, plus
`csv/system_dynamic_uci_completions.csv`. They retain zero-based causal clocks,
field counts, context digests and model/qualification labels, not fabricated RF
trial rows. Both features remain opt-in until the selected study supplies its
matching calibration and passes its integrated acceptance checks.

`sixgr.phy.ul.pusch.planUCIResources` computes native NR single-codeword
HARQ/CSI-on-PUSCH coded-bit budgets, puncturing and exact RE coordinates.
Its output is resource-accounting evidence, **not a physical UCI trial**.
The native single-codeword data-PUSCH transmitter (without configured-grant
UCI) also checks this plan against its actual encoder budget and retains it
as `NativeUCIResourcePlan`. Other existing transport variants retain their
own handling; this is not a qualification of those branches.
The calibrated backend includes an attached `SLSUCIAllocation` in its physical
allocation key, preventing data-only BLER-curve reuse. Automatic selection is
limited to the policy described above; a transport label alone never releases
PUCCH reservations. The native waveform receiver check uses separately built
receive context/schema, not expected transmitted UCI bits. Passing a few
identity-channel cases is not statistical UCI qualification.

`sixgr.system.abstraction.buildCalibrationFromTrials(spec, policy, outputFile)`
packages retained waveform fit/held-out CSV populations into the backend MAT
schema. `spec` supplies physically keyed curve templates (including fitted
beta/MI mappings and SINR-history axes) and source-file hashes. Counts are
derived from raw rows, never filled in. Incomplete populations, reused trial
identities, changed files, development fixtures or failed statistical gates
prevent publication. This packager does not execute the missing waveform
campaign or turn an F1 first-transmission curve into HARQ calibration.

Additional dedicated checks (not `testAll` or a qualified study command):

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_mapping_uci_calibration_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSMultiBeamMapping; testSLSNativePUSCHUCIResources; testSLSNativePUSCHUCITransmission; testSLSResourceReservations; testSLSCalibrationSourceIntegrity; testSystemNetworkDLCSI;"
```

Automatic SLS transport integration and separate waveform receiver checks:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_automatic_uci_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSNativePUSCHUCIReception; testSystemAutomaticPUSCHUCI;"
```

### H4 4 GHz / 100 MHz TDD scenario family

These files are independent of the older 100-UE/19-site system scenario and
the older `lls_3gpp_4ghz_100mhz_longrun.yaml`:

- `h4_100_a0_fixed_mcs.yaml`: normalized AWGN calibration arm.
- `h4_100_tdla30_fixed_mcs.yaml`: TDL-A, 30 ns fixed operating point.
- `h4_100_cdlc100_fixed_mcs.yaml`: CDL-C, 100 ns fixed operating point.
- `h4_100_tdla30_connected_adaptive.yaml`: connected adaptive TDL-A.
- `h4_100_cdlc100_connected_adaptive.yaml`: connected adaptive CDL-C.
- `h4_100_cold_access_beam_sweep.yaml`: measured SSB/Type-0/SIB1/PRACH path.
- `h4_100_beam_refinement_tci.yaml`: measured P1/P2 and decoded-TCI binding.
- `h4_100_cdlc100_connected_impaired.yaml`: separate frozen RF-impairment
  treatment arm; its RF values are research assumptions, not 3GPP limits.
- `h4_100_cdlc100_connected_impaired_snr_sweep.yaml`: eight independent
  impaired CDL-C points at `40, 30, 20, 10, 0, -10, -20, -30 dB`, with
  four-chain UE state rebuilt at every point and joint campaign CSV/PNG
  publication under the parent run folder.

The gNB physical shape is 4×4 spatial positions × H/V × two panels = 64
elements/TXRUs. The UE is **four-chain 4×4 MIMO capability**, implemented as
1×2 spatial positions × H/V = four elements with four independent TX and RX
chains. Eight DL CSI/PDSCH logical ports are distinct from the four scheduled
layers; the UE exposes four PUSCH/SRS ports and maximum UL rank four.

Run the focused H4 configuration and causal beam-state guards from Windows
Command Prompt:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -batch "setup6GRSimToolkit('Verbose',false); assert(testH41004x4MIMOConfig); assert(testH4BeamManagementRuntimeBinding);"
```

Run one H4 waveform scenario (replace the YAML basename with another member
of the family when required):

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && if not exist "logs" mkdir "logs" && "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\h4_100_beam_refinement_tci.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_beam_refinement_tci.yaml','results','h4_100_beam_refinement_tci'); disp(out); assert(out.Ok,'H4 run failed; inspect retained evidence.');"
```

Run the complete eight-point impaired H4 sweep. Every child retains its own
truth artifacts under `sweeps/`; consolidated all-point CSVs and PNGs are
written under the parent run's `reports/csv` and `reports/image` folders:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && if not exist "logs" mkdir "logs" && "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\h4_100_cdlc100_connected_impaired_snr_sweep.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_snr_sweep.yaml','results','h4_100_cdlc100_connected_impaired_snr_sweep'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'H4 eight-point sweep failed; inspect retained child and parent evidence.');"
```

Start the WebGUI separately from PowerShell so it remains visible while the
MATLAB process runs:

```powershell
cd 'C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apps\start_lls_web_dashboard.ps1
```

Beam-failure recovery remains unavailable: the family does not claim BFR
until physical BFD, candidate-beam measurement, BFR PRACH and response
reception are implemented and qualified.

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

### Current TDD command catalog: 5 MHz, 20 MHz, 400 MHz and testAll

The commands in this section are for **Windows Command Prompt (`cmd.exe`)**.
Do not paste PowerShell `&`, backticks, arrays or line continuations directly
into Command Prompt. Commands were checked against the runner signature and
the YAML paths on `main`. Change each run tag or log filename before repeating
a run so an earlier result is not confused with a new experiment.

First enter the repository and optionally launch the live WebGUI in a second
Command Prompt window:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\apps\start_lls_web_dashboard.ps1" -Port 62906
```

Open `http://127.0.0.1:62906/`. The WebGUI is a separate process; starting a
batch run does not automatically start it. All direct commands below save
scenario artifacts below `results/lls/<scenario_id>/<run_tag>/` and the MATLAB
console log below `logs/`.

#### 5 MHz TDD commands

| Purpose | YAML |
|---|---|
| n39/1.900 GHz, 5 MHz, 4TX/2RX adaptive-rank, 0 dB focused point | `simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml` |
| 5 MHz shared physical control/feedback, saturated traffic, 20 dB | `simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml` |
| n39/1.900 GHz, saturated eight-point sweep `[40,30,20,10,0,-10,-20,-30]` dB | `simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml` |
| Historical 12 dB four-port diagnostic | `simulator/configs/scenarios/lls_tdd_5mhz_four_port_shared_awgn_12db.yaml` |

Additional 5 MHz YAMLs are retained for comparison or focused diagnostics:
`lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml`,
`lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml`,
`lls_tdd_5mhz_rank2_shared_awgn_20db.yaml`,
`lls_tdd_5mhz_rank2_shared_awgn_snr_sweep.yaml`,
`lls_tdd_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml` and
`lls_tdd_5mhz_outage_publication_fixture.yaml`. The last file is a publication
fixture, not an operator acceptance scenario.

Run the 0 dB focused point:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\5mhz_n39_0db_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml','results','5mhz_n39_0db_manual_01'); disp(out); assert(out.Ok,'5 MHz 0 dB run failed; preserve results and log.');"
```

Run the saturated 20 dB point:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\5mhz_rank2_20db_saturated_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml','results','5mhz_rank2_20db_saturated_manual_01'); disp(out); assert(out.Ok,'5 MHz 20 dB run failed; preserve results and log.');"
```

Run the complete eight-point 5 MHz sweep:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\5mhz_n39_8point_sweep_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml','results','5mhz_n39_8point_sweep_manual_01'); disp(out); assert(out.Ok,'5 MHz eight-point sweep failed; preserve parent and child artifacts.');"
```

The sweep retains per-point raw child evidence and publishes joint parent-level
CSV/PNG comparisons. It must not copy configured SNR into measured-SINR fields.

#### 20 MHz n39 TDD CDL-C commands

These are TDD scenarios. The reference carrier is NR band n39 at 1.900 GHz,
20 MHz bandwidth, 15 kHz SCS, 106 PRBs, normal CP, FFT 2048 and 30.72 MSa/s.
The configured-SNR studies and the physical O2I/thermal link-budget study are
separate by design.

| Purpose | YAML |
|---|---|
| Clean CDL-C configured-SNR reference at 0 dB | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_reference.yaml` |
| Clean CDL-C eight-point configured-SNR sweep | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_snr_sweep.yaml` |
| CDL-C with declared RF impairments, single reference point | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_impairments.yaml` |
| CDL-C/RF-impairment eight-point sweep | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_snr_sweep.yaml` |
| Absolute-power CDL-C/O2I/pathloss/thermal-noise link budget; not an SNR sweep | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_o2i_thermal.yaml` |

Run the clean 0 dB reference:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_0db_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_reference.yaml','results','20mhz_n39_cdlc_0db_manual_01'); disp(out); assert(out.Ok,'20 MHz reference run failed; preserve results and log.');"
```

Run the clean eight-point sweep:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_8point_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_snr_sweep.yaml','results','20mhz_n39_cdlc_8point_manual_01'); disp(out); assert(out.Ok,'20 MHz CDL-C sweep failed; preserve parent and child artifacts.');"
```

Run the RF-impairment point or its eight-point sweep:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_rf_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_impairments.yaml','results','20mhz_n39_cdlc_rf_manual_01'); disp(out); assert(out.Ok,'20 MHz RF-impairment run failed.');"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_rf_8point_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_snr_sweep.yaml','results','20mhz_n39_cdlc_rf_8point_manual_01'); disp(out); assert(out.Ok,'20 MHz RF-impairment sweep failed.');"
```

Run the separate absolute-power O2I/thermal link-budget case:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_o2i_thermal_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_o2i_thermal.yaml','results','20mhz_n39_cdlc_o2i_thermal_manual_01'); disp(out); assert(out.Ok,'20 MHz O2I/thermal run failed.');"
```

#### 400 MHz commands

| Purpose | YAML or launcher |
|---|---|
| Rank-2 Keysight/VXG/VSA package | `lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml` through `scripts/run_vxg_vsa_demo.ps1` |
| Fixed rate-0.82 DL/UL IQ capture | `lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml` |
| Four-layer/64-element CDL-C study | `lls_7ghz_400mhz_4layer_64gnb_4ue_30db.yaml` |
| Calibrated four-port adaptive DL-heavy study | `lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml` plus its calibration YAMLs |

Use the dedicated launcher for the rank-2 Keysight/VXG/VSA digital package:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -Config "simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml"
```

Run the fixed rate-0.82, 30 dB, DL/UL 1024-QAM IQ scenario directly:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\400mhz_7ghz_rate082_iq_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml','results','400mhz_7ghz_rate082_iq_manual_01'); disp(out); assert(out.Ok,'400 MHz rate-0.82 IQ run failed.');"
```

The adaptive DL-heavy scenario is
`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml`.
It requires its version-matched calibration files; use the complete calibrated
command block in [Exact command: measured 400 MHz four-layer adaptive run](#exact-command-measured-400-mhz-four-layer-adaptive-run), not an uncalibrated direct launch.

#### testAll command

The supported server launcher requires a clean Git checkout, creates a unique
`logs/testall_*` folder, writes terminal JSON/CSV/MATLAB logs and creates a ZIP
bundle. From Command Prompt:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_server_testall.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -PreflightOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_server_testall.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
```

The first line is environment preflight only. The second line runs `testAll`.
Do not call the second line a pass unless its `summary.json` says `passed`, the
launcher exits with code zero, and the source commit/worktree identity remains
unchanged throughout execution.

### 400 MHz / 7 GHz rank-2 Keysight waveform demonstration

**7 GHz / 400 MHz 6G research waveform using 3GPP-derived NR PHY structures.**
This is **400 MHz bandwidth at 7 GHz**, not a 4 GHz carrier. The dedicated YAML is
[`lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml`](simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml).
It preserves the existing 5 MHz and four-layer/shared-feedback scenarios.

Use `scripts/run_vxg_vsa_demo.ps1` below for a **new complete digital package**;
use `apps/vxg_vsa_demo_dashboard.py` below to **view the existing package only**.
Neither command verifies physical instrument capability. Updating `main` does
not rerun this experiment or replace the sealed measurements from `20260925_v1`.

Delivery status: one branch (`main`) and one Git worktree. Source, launchers,
YAMLs, tests and preserved development patches are versioned; generated IQ,
results and logs are transferred separately. Pending 5 MHz receiver patches
do not change or qualify this sealed 400 MHz data-channel demonstration.

The sealed measurements came from source commit
`6244d24f20b2ee55d426cfab9aa81d7c203d10d7` with additional working-tree edits;
the package retains the exact executed source snapshots. A new run on current
`main` is a new experiment, not a reproduction established by `git pull` alone.
Keep its new run folder and source identity alongside the original report.

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
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -Config "simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml"
```

On another PC, substitute that PC's checkout path. From its repository root,
the portable command is:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -Config "simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml"
```

For a **new checkout** on the other PC, first run these two commands from a
directory where you want to keep the repository, then use the portable
launcher above. Change `-MatlabExe` to the supported MATLAB installation on
that PC; these commands do not install MATLAB, Python or their dependencies.

```bat
git clone --branch main --single-branch https://github.com/anup080002/6gr-simulator.git
cd /d "6gr-simulator"
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
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && python apps\vxg_vsa_demo_dashboard.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\20260925_v1"
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

### Fixed 4.000 GHz terrestrial campaign

The RAN1#126bis research campaign front door is:

```cmd
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && if not exist "logs" mkdir "logs" && "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\ran1_126bis_4ghz_only.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_matrix('simulator/configs/campaigns/ran1_126bis_4ghz_only.yaml','results/ran1_126bis_4ghz_only','qualification_4ghz_v1'); disp(out); assert(out.Ok,'One or more 4 GHz campaign cases failed; inspect retained point evidence.');"
```

The matrix enforces the resolved physical scope before creating child runs:

- exactly 4.000 GHz for all carrier-frequency bindings;
- terrestrial single-carrier TDD only;
- no carrier aggregation or carrier-frequency sweep;
- no NTN or ISAC/sensing execution.

The current executable matrix is deliberately Stage 0: C4_20 (20 MHz,
30 kHz SCS, 51 RB, FFT 1024, 30.72 MS/s), a 4TX/2RX full-row-rank AWGN lab
operator, and targets `[-30,-20,-10,0,10,20,30,40]` dB. The campaign coverage
CSV retains later H4_100 and agenda studies as explicit blocked/partial items;
Stage-0 success must not be described as complete 25-item or 3GPP acceptance.

At matrix preflight, the runner writes `parameter_bindings.csv` and copies
`capability_coverage.csv`. The sweep parent publishes `point_status.csv`,
`metrics_long.csv`, `sinr_calibration.csv/.png`, and
`attempt_crc_failure_fraction.csv/.png`. Unsupported populations are listed in
`campaign_artifact_status.csv`; no empty or synthetic measurement rows are added.

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
