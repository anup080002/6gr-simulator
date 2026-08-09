function artifacts = writeRFInterferenceReconciliation(cfg, runFolder, rawTrials, mobilityArtifacts, slotTrace)
%WRITERFINTERFERENCERECONCILIATION Publish RF/interference evidence gates.
%
% These are derived audit artifacts. A gate passes only when backed by
% concrete runtime trial columns or by explicit identity configuration for a
% disabled RF stage. Missing evidence is written as a false reconciliation
% row, not as a fabricated primary result.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || strlength(strtrim(string(runFolder))) == 0
    runFolder = pwd;
end
if nargin < 3 || ~isstruct(rawTrials)
    rawTrials = struct();
end
if nargin < 4 || ~isstruct(mobilityArtifacts)
    mobilityArtifacts = struct();
end
if nargin < 5 || ~isstruct(slotTrace)
    slotTrace = struct(); %#ok<NASGU>
end

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);

dlT = sixgr.util.structGet(rawTrials, "DL", table());
ulT = sixgr.util.structGet(rawTrials, "UL", table());
if ~(istable(dlT) && height(dlT) > 0)
    dlT = localReadTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
end
if ~(istable(ulT) && height(ulT) > 0)
    ulT = localReadTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
end
dlT = localEffectiveRows(dlT);
ulT = localEffectiveRows(ulT);

noiseT = localBuildNoiseTable(cfg);
interferenceT = localBuildInterferenceTable(dlT, ulT, cfg);
rfChainT = localBuildRFChainTable(cfg);
cfoT = localBuildCFOTable(dlT, ulT, cfg);
phaseNoiseT = localBuildPhaseNoiseTable(dlT, ulT, cfg);
timingT = localBuildTimingTable(dlT, ulT, cfg);
iqT = localBuildIQTable(dlT, ulT, cfg);
paT = localBuildPATable(dlT, ulT, cfg);
evmT = localBuildEVMTable(dlT, ulT, cfg);
paprT = localBuildPAPRTable(dlT, ulT, cfg);
mimoT = localBuildMIMOTable(dlT, ulT, cfg);
schedulerT = localBuildSchedulerTable(dlT, ulT, cfg);
mobilityT = localBuildMobilityTable(cfg, mobilityArtifacts, runFolder);
channelRfT = localBuildChannelRFTable(cfoT, phaseNoiseT, timingT, iqT, paT, evmT, paprT, rfChainT);

artifacts = struct();
artifacts.NoiseReconciliation = localWrite(layout.ReportCSVDir, "noise_reconciliation.csv", noiseT);
artifacts.InterferenceAccounting = localWrite(layout.ReportCSVDir, "interference_accounting.csv", interferenceT);
artifacts.RFChainDefinition = localWrite(layout.ReportCSVDir, "rf_chain_definition.csv", rfChainT);
artifacts.CFOReconciliation = localWrite(layout.ReportCSVDir, "cfo_reconciliation.csv", cfoT);
artifacts.PhaseNoiseReconciliation = localWrite(layout.ReportCSVDir, "phase_noise_reconciliation.csv", phaseNoiseT);
artifacts.TimingOffsetReconciliation = localWrite(layout.ReportCSVDir, "timing_offset_reconciliation.csv", timingT);
artifacts.IQImbalanceReconciliation = localWrite(layout.ReportCSVDir, "iq_imbalance_reconciliation.csv", iqT);
artifacts.PAReconciliation = localWrite(layout.ReportCSVDir, "pa_reconciliation.csv", paT);
artifacts.EVMReconciliation = localWrite(layout.ReportCSVDir, "evm_reconciliation.csv", evmT);
artifacts.PAPRReconciliation = localWrite(layout.ReportCSVDir, "papr_reconciliation.csv", paprT);
artifacts.ChannelRFReconciliation = localWrite(layout.ReportCSVDir, "channel_rf_reconciliation.csv", channelRfT);
artifacts.MIMOReconciliation = localWrite(layout.ReportCSVDir, "mimo_kpi_reconciliation.csv", mimoT);
artifacts.MobilityReconciliation = localWrite(layout.ReportCSVDir, "mobility_kpi_reconciliation.csv", mobilityT);
artifacts.SchedulerReconciliation = localWrite(layout.ReportCSVDir, "scheduler_kpi_reconciliation.csv", schedulerT);

artifacts.Tables = struct( ...
    "Noise", noiseT, ...
    "Interference", interferenceT, ...
    "RFChain", rfChainT, ...
    "CFO", cfoT, ...
    "PhaseNoise", phaseNoiseT, ...
    "Timing", timingT, ...
    "IQ", iqT, ...
    "PA", paT, ...
    "EVM", evmT, ...
    "PAPR", paprT, ...
    "ChannelRF", channelRfT, ...
    "MIMO", mimoT, ...
    "Mobility", mobilityT, ...
    "Scheduler", schedulerT);
end

function path = localWrite(dirPath, fileName, T)
path = fullfile(dirPath, fileName);
sixgr.analytics.writeAnalysisTable(path, T);
end

function T = localBuildNoiseTable(cfg)
bwHz = localNumber(cfg, ["global_radio_scope.channel_bandwidth_hz","frequency.bandwidth_hz","air_interface.channel_bandwidth_hz"], 100e6);
ueNF = localNumber(cfg, ["scenario.ue.noiseFigure_dB","air_interface.ue_noise_figure_dB","ue.noise_figure_db"], 7);
bsNF = localNumber(cfg, ["scenario.bs.noiseFigure_dB","air_interface.bs_noise_figure_dB","bs_noise_figure_db"], 5);
kTBdBm = -174 + 10 * log10(max(bwHz, eps));
ueFloor = kTBdBm + ueNF;
bsFloor = kTBdBm + bsNF;
mode = localString(cfg, ["run.noiseOperatingMode","run.noise_operating_mode", ...
    "simulation.noiseOperatingMode","simulation.noise_operating_mode", ...
    "noise.operatingMode","noise.operating_mode"], "receiver_noise_figure_thermal_noise");
ok = isfinite(bwHz) && bwHz > 0 && isfinite(ueNF) && isfinite(bsNF) && strlength(strtrim(mode)) > 0;
source = "resolved_config_noise_mode:" + string(mode);
T = table(bwHz, -174, kTBdBm, ueNF, bsNF, ueFloor, bsFloor, string(mode), ok, ...
    source, ...
    'VariableNames', {'BandwidthHz','ThermalNoiseDensity_dBmHz','ThermalNoisePower_dBm', ...
    'UE_NoiseFigure_dB','BS_NoiseFigure_dB','UE_NoiseFloor_dBm','BS_NoiseFloor_dBm', ...
    'NoiseOperatingMode','NoiseReconciliationOk','EvidenceSource'});
end

function T = localBuildRFChainTable(cfg)
paModel = localString(cfg, ["impairments.pa_nonlinearity.model","power_and_rf_frontend.pa_model"], "ideal_linear");
osc = localString(cfg, ["impairments.oscillator_profile","power_and_rf_frontend.oscillator_profile"], "lab_clean");
dacBits = localNumber(cfg, ["impairments.dac_quantization_bits","power_and_rf_frontend.dac_bits"], 12);
adcBits = localNumber(cfg, ["impairments.adc_quantization_bits","power_and_rf_frontend.adc_bits"], 12);
ueChains = localNumber(cfg, ["scenario.ue.nTxAnt","mimo.ue_num_rf_chains","phy.pusch.numTxPorts"], 1);
bsChains = localNumber(cfg, ["scenario.bs.nTxAnt","mimo.bs_num_rf_chains","phy.pdsch.numTxPorts"], 1);
ok = isfinite(dacBits) && isfinite(adcBits) && isfinite(ueChains) && isfinite(bsChains) && ...
    strlength(strtrim(paModel)) > 0;
T = table("DAC->RF_impairment_chain->PA->antenna_port", ...
    "antenna_port->LNA_noise_figure->ADC->baseband", ...
    string(paModel), dacBits, adcBits, string(osc), ueChains, bsChains, ok, ...
    "resolved_runtime_rf_chain_configuration", ...
    'VariableNames', {'TX_chain','RX_chain','PA_model','DAC_bits','ADC_bits','OscillatorProfile', ...
    'UE_RFChainCount','BS_RFChainCount','RfChainDefinitionOk','EvidenceSource'});
end

function T = localBuildCFOTable(dlT, ulT, cfg)
configured = localNumber(cfg, ["impairments.cfo.value_hz","rf.cfo_hz","power_and_rf_frontend.cfo_hz"], 0);
configuredEnabled = localBool(cfg, ["impairments.cfo.enabled","impairments.cfo_enabled", ...
    "rf.cfo_enabled","power_and_rf_frontend.cfo_enabled"], abs(configured) > 0);
rows = [localCFOTrialRow("DL", dlT, configured, configuredEnabled); ...
    localCFOTrialRow("UL", ulT, configured, configuredEnabled)];
T = struct2table(rows, "AsArray", true);
end

function row = localCFOTrialRow(direction, T, configured, configuredEnabled)
observed = istable(T) && height(T) > 0 && localHasColumn(T, "InjectedCFO_Hz");
inj = localFiniteColumn(T, "InjectedCFO_Hz");
est = localFiniteColumn(T, "EstimatedCFO_PreCorrection_Hz");
res = localFiniteColumn(T, "ResidualCFO_PostCorrection_Hz");
mismatch = localMaxAbs(inj - configured);
residual = localMaxAbs(res);
estimationRequired = logical(configuredEnabled) || abs(double(configured)) > 1e-12;
if estimationRequired
    estimatorOk = ~isempty(est) && ~isempty(res) && isfinite(residual) && residual <= 1;
    estimatorStatus = "required_and_observed";
else
    % A disabled zero-CFO stage is an identity transform.  Requiring an
    % estimator output in this case turns an honest N/A into a false fail.
    estimatorOk = true;
    estimatorStatus = "not_applicable_disabled_zero_cfo_identity";
end
ok = observed && isfinite(mismatch) && mismatch <= 1 && estimatorOk;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredCFO_Hz", double(configured), "MeanInjectedCFO_Hz", localMean(inj), ...
    "MeanEstimatedCFO_PreCorrection_Hz", localMean(est), "MeanResidualCFO_PostCorrection_Hz", localMean(res), ...
    "MaxConfiguredAppliedMismatch_Hz", double(mismatch), "MaxResidualCFO_Hz", double(residual), ...
    "CFOEstimationRequired", logical(estimationRequired), "CFOEstimationStatus", char(estimatorStatus), ...
    "CfoConfiguredAppliedOk", logical(ok), "EvidenceSource", char(localEvidenceSource(observed, "trial_rf_cfo_columns")));
end

function T = localBuildTimingTable(dlT, ulT, cfg)
configured = localNumber(cfg, ["impairments.to.value_samples","impairments.timing_offset_samples","rf.timing_offset_samples"], 0);
rows = [localTimingTrialRow("DL", dlT, configured); localTimingTrialRow("UL", ulT, configured)];
T = struct2table(rows, "AsArray", true);
end

function row = localTimingTrialRow(direction, T, configured)
observed = istable(T) && height(T) > 0 && localHasColumn(T, "InjectedTimingOffset_samples");
inj = localFiniteColumn(T, "InjectedTimingOffset_samples");
est = localFiniteColumn(T, "EstimatedTimingOffset_PreCorrection_samples");
res = localFiniteColumn(T, "ResidualTimingError_PostCorrection_samples");
mismatch = localMaxAbs(inj - configured);
residual = localMaxAbs(res);
ok = observed && isfinite(mismatch) && mismatch <= 1 && (~isempty(res) && isfinite(residual) && residual <= 1);
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredTimingOffset_samples", double(configured), "MeanInjectedTimingOffset_samples", localMean(inj), ...
    "MeanEstimatedTimingOffset_PreCorrection_samples", localMean(est), ...
    "MeanResidualTimingOffset_samples", localMean(res), ...
    "MaxConfiguredAppliedMismatch_samples", double(mismatch), "MaxResidualTimingError_samples", double(residual), ...
    "TimingOffsetConfiguredAppliedOk", logical(ok), "EvidenceSource", char(localEvidenceSource(observed, "trial_rf_timing_columns")));
end

function T = localBuildIQTable(dlT, ulT, cfg)
configuredEnabled = localBool(cfg, ["impairments.iq_imbalance.enabled","impairments.iq.enabled"], false);
gainCfg = localNumber(cfg, ["impairments.iq_imbalance.amplitude_imbalance_db","impairments.iq_amplitude_imbalance_dB"], 0);
phaseCfg = localNumber(cfg, ["impairments.iq_imbalance.phase_imbalance_deg","impairments.iq_phase_imbalance_deg"], 0);
model = localString(cfg, ["impairments.iq_imbalance.model","impairments.iq.model"], "none");
rows = [localIQTrialRow("DL", dlT, configuredEnabled, gainCfg, phaseCfg, model); ...
    localIQTrialRow("UL", ulT, configuredEnabled, gainCfg, phaseCfg, model)];
T = struct2table(rows, "AsArray", true);
end

function row = localIQTrialRow(direction, T, configuredEnabled, gainCfg, phaseCfg, model)
hasConfigured = localHasColumn(T, "IQImbalanceConfigured");
hasApplied = localHasColumn(T, "IQImbalanceApplied");
observed = istable(T) && height(T) > 0 && hasConfigured && hasApplied;
cfgCol = localLogicalColumn(T, "IQImbalanceConfigured");
appliedCol = localLogicalColumn(T, "IQImbalanceApplied");
gain = localFiniteColumn(T, "ConfiguredIQGainImbalance_dB");
phase = localFiniteColumn(T, "ConfiguredIQPhaseImbalance_deg");
configuredMatches = isempty(cfgCol) || all(cfgCol == logical(configuredEnabled));
appliedMatches = ~isempty(appliedCol) && all(appliedCol == logical(configuredEnabled));
gainMatches = isempty(gain) || localMaxAbs(gain - gainCfg) <= 1e-9;
phaseMatches = isempty(phase) || localMaxAbs(phase - phaseCfg) <= 1e-9;
ok = observed && configuredMatches && appliedMatches && gainMatches && phaseMatches;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredIQEnabled", logical(configuredEnabled), "AppliedIQEnabled", localAny(appliedCol), ...
    "ConfiguredModel", char(string(model)), "ConfiguredGainImbalance_dB", double(gainCfg), ...
    "ConfiguredPhaseImbalance_deg", double(phaseCfg), "ObservedMeanGainImbalance_dB", localMean(gain), ...
    "ObservedMeanPhaseImbalance_deg", localMean(phase), "IqImbalanceConfiguredAppliedOk", logical(ok), ...
    "EvidenceSource", char(localEvidenceSource(observed, "trial_rf_iq_columns")));
end

function T = localBuildPhaseNoiseTable(dlT, ulT, cfg)
configuredEnabled = localBool(cfg, ["impairments.phase_noise.enabled","rf.phase_noise.enabled"], false);
model = localString(cfg, ["impairments.phase_noise.model","rf.phase_noise.model"], "none");
floorDbc = localNumber(cfg, ["impairments.phase_noise.psd_floor_dbc_hz","rf.phase_noise.psd_floor_dbc_hz"], -150);
observed = localHasColumn(dlT, "PhaseNoiseApplied") || localHasColumn(ulT, "PhaseNoiseApplied");
applied = any([localLogicalColumn(dlT, "PhaseNoiseApplied"); localLogicalColumn(ulT, "PhaseNoiseApplied")]);
if ~observed
    applied = configuredEnabled;
end
cleanIdentity = ~configuredEnabled && any(lower(strtrim(string(model))) == ["none","disabled","off","ideal"]);
ok = (observed && applied == configuredEnabled) || cleanIdentity;
T = table(logical(configuredEnabled), logical(applied), string(model), floorDbc, ok, ...
    string(localTernary(observed, "trial_rf_phase_noise_columns", "configured_clean_identity_rf_stage")), ...
    'VariableNames', {'ConfiguredPhaseNoiseEnabled','AppliedPhaseNoiseEnabled','ConfiguredModel', ...
    'PSD_floor_dBc_Hz','PhaseNoiseConfiguredAppliedOk','EvidenceSource'});
end

function T = localBuildPATable(dlT, ulT, cfg)
configuredEnabled = localBool(cfg, ["impairments.pa_nonlinearity.enabled","power_and_rf_frontend.pa_enabled"], false);
model = localString(cfg, ["impairments.pa_nonlinearity.model","power_and_rf_frontend.pa_model"], "ideal_linear");
iip3 = localNumber(cfg, ["impairments.pa_nonlinearity.iip3_dbm","power_and_rf_frontend.pa_iip3_dbm"], 60);
p1db = localNumber(cfg, ["impairments.pa_nonlinearity.p1db_dbm","power_and_rf_frontend.pa_p1db_dbm"], 50);
observed = localHasColumn(dlT, "PAApplied") || localHasColumn(ulT, "PAApplied");
applied = any([localLogicalColumn(dlT, "PAApplied"); localLogicalColumn(ulT, "PAApplied")]);
if ~observed
    applied = configuredEnabled;
end
cleanIdentity = ~configuredEnabled && any(lower(strtrim(string(model))) == ["ideal_linear","linear","none","disabled","off"]);
ok = (observed && applied == configuredEnabled) || cleanIdentity;
T = table(logical(configuredEnabled), logical(applied), string(model), iip3, p1db, ok, ...
    string(localTernary(observed, "trial_rf_pa_columns", "configured_clean_identity_rf_stage")), ...
    'VariableNames', {'ConfiguredPAEnabled','AppliedPAEnabled','ConfiguredModel','IIP3_dBm','P1dB_dBm', ...
    'PaConfiguredAppliedOk','EvidenceSource'});
end

function T = localBuildEVMTable(dlT, ulT, cfg)
threshold = localNumber(cfg, ["analysis.evm_max_ok_rms","rf.evm_max_ok_rms"], NaN);
rows = [localEVMRow("DL", dlT, threshold); localEVMRow("UL", ulT, threshold)];
T = struct2table(rows, "AsArray", true);
end

function row = localEVMRow(direction, T, threshold)
evm = localFiniteColumn(T, "EVM_rms");
sinr = localFiniteColumn(T, "PostEqSINR_dB");
evmProxy = localNumericColumn(T, "EVMProxySINR_dB");
evmRaw = localNumericColumn(T, "EVM_rms");
identityMask = isfinite(evmProxy) & isfinite(evmRaw) & evmRaw >= 0;
identityError = NaN;
identityRequired = localHasColumn(T, "EVMProxySINR_dB");
finiteEVM = isfinite(evmRaw) & evmRaw >= 0;
if any(identityMask)
    expectedProxy = -20 * log10(max(evmRaw(identityMask), eps));
    identityError = max(abs(evmProxy(identityMask) - expectedProxy), [], "omitnan");
end
identityOk = ~identityRequired || (nnz(identityMask) == nnz(finiteEVM) && ...
    nnz(finiteEVM) > 0 && isfinite(identityError) && identityError <= 1e-8);
thresholdRequired = isfinite(threshold) && threshold > 0;
if thresholdRequired
    thresholdOk = ~isempty(evm) && localMean(evm) <= threshold;
    thresholdStatus = "configured_campaign_limit_evaluated";
else
    % EVM limits are modulation and test-condition specific.  A hidden
    % 15%% default is not a valid gate over a multi-SNR BLER campaign.
    thresholdOk = true;
    thresholdStatus = "not_applicable_no_yaml_campaign_limit";
end
ok = ~isempty(evm) && all(evm >= 0) && isfinite(localMean(evm)) && identityOk && thresholdOk;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "MeasuredEVMMean_rms", localMean(evm), "MeasuredEVMMax_rms", localMax(evm), ...
    "MeanPostEqSINR_dB", localMean(sinr), "EVMThreshold_rms", double(threshold), ...
    "EVMThresholdEvaluationStatus", char(thresholdStatus), ...
    "EVMProxySINRMaxIdentityError_dB", double(identityError), ...
    "EvmReconciliationOk", logical(ok), ...
    "EvidenceSource", char(localEvidenceSource(~isempty(evm), "trial_modulation_tracking_evm")));
end

function T = localBuildPAPRTable(dlT, ulT, cfg)
threshold = localNumber(cfg, ["analysis.papr_max_ok_db","rf.papr_max_ok_db"], NaN);
rows = [localPAPRRow("DL", dlT, threshold); localPAPRRow("UL", ulT, threshold)];
T = struct2table(rows, "AsArray", true);
end

function row = localPAPRRow(direction, T, threshold)
papr = localFiniteColumn(T, "PAPR_dB");
thresholdRequired = isfinite(threshold) && threshold >= 0;
if thresholdRequired
    thresholdOk = localMedian(papr) <= threshold && localMax(papr) <= threshold + 3;
    thresholdStatus = "configured_campaign_limit_evaluated";
else
    % PAPR limits depend on waveform, allocation, CFR and PA objectives.
    % Preserve measured PAPR, but never invent a universal hidden limit.
    thresholdOk = true;
    thresholdStatus = "not_applicable_no_yaml_campaign_limit";
end
ok = ~isempty(papr) && all(isfinite(papr)) && all(papr >= 0) && thresholdOk;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "PAPRMean_dB", localMean(papr), "PAPRMedian_dB", localMedian(papr), "PAPRMax_dB", localMax(papr), ...
    "PAPRThreshold_dB", double(threshold), "PAPRWindow", "active_samples_excluding_cp_when_ofdm_metadata_available", ...
    "PAPRThresholdEvaluationStatus", char(thresholdStatus), ...
    "PaprReconciliationOk", logical(ok), ...
    "EvidenceSource", char(localEvidenceSource(~isempty(papr), "trial_waveform_papr")));
end

function T = localBuildInterferenceTable(dlT, ulT, cfg)
rows = [localInterferenceRow("DL", dlT, cfg); localInterferenceRow("UL", ulT, cfg)];
T = struct2table(rows, "AsArray", true);
end

function row = localInterferenceRow(direction, T, cfg)
modeCfg = localString(cfg, ["interference.inter_cell_execution_mode","run.interference_mode","topology.inter_cell_execution_mode"], "");
modes = localStringColumn(T, "InterferenceMode");
contributors = localFiniteColumn(T, "InterferenceContributorCount");
power = localFiniteColumn(T, "InterferenceAggregatedRxPower_dBm");
source = localStringColumn(T, "InterferencePowerSource");
truth = localLogicalColumn(T, "FullInterfererChannelTruthUsed");
observed = localHeight(T) > 0 && (~isempty(modes) || ~isempty(contributors) || ~isempty(power));
modeEvidence = strjoin(unique(modes(strlength(strtrim(modes)) > 0), "stable"), "|");
if strlength(modeEvidence) == 0
    modeEvidence = modeCfg;
end
fullMode = contains(lower(string(modeEvidence)), "full_per_link_channel_waveform_sum") || ...
    contains(lower(string(modeEvidence)), "shared");
hasContributor = (~isempty(contributors) && max(contributors, [], "omitnan") > 0) || ~isempty(power);
truthOk = isempty(truth) || any(truth);
ok = observed && fullMode && hasContributor && truthOk;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredInterferenceMode", char(string(modeCfg)), "ObservedInterferenceMode", char(string(modeEvidence)), ...
    "MaxContributorCount", localMax(contributors), "MeanInterferencePower_dBm", localMean(power), ...
    "InterferencePowerSource", char(strjoin(unique(source(strlength(strtrim(source)) > 0), "stable"), "|")), ...
    "InterferenceTruthChannelUsed", logical(any(truth)), "InterferenceAccountingOk", logical(ok), ...
    "EvidenceSource", char(localEvidenceSource(observed, "trial_shared_slot_interference_columns")));
end

function T = localBuildMIMOTable(dlT, ulT, cfg)
cfgDLLayers = localNumber(cfg, ["mimo.max_dl_layers","phy.pdsch.nLayers","phy.pdsch.NumLayers"], NaN);
cfgULLayers = localNumber(cfg, ["mimo.max_ul_layers","phy.pusch.nLayers","phy.pusch.NumLayers"], NaN);
cfgBSTx = localNumber(cfg, ["scenario.bs.nTxAnt","mimo.n_tx_ant","mimo.nTxAnt"], NaN);
cfgUERx = localNumber(cfg, ["scenario.ue.nRxAnt","mimo.n_rx_ant","mimo.nRxAnt"], NaN);
cfgUETx = localNumber(cfg, ["scenario.ue.nTxAnt","mimo.ue_n_tx_ant"], cfgUERx);
cfgBSRx = localNumber(cfg, ["scenario.bs.nRxAnt","mimo.bs_num_rx_ant"], cfgBSTx);
maximumMCS = localNumber(cfg, ["phy.linkAdaptation.maximumMCSIndex","link_adaptation.maximum_mcs"], 31);
bootstrapMCS = localNumber(cfg, ["phy.linkAdaptation.initialMCSIndex","link_adaptation.initial_mcs"], NaN);
muRequested = localBool(cfg, ["mimo.mu_mimo_enable","mimo.mu_mimo_enabled"], false);

dl = localMIMODirectionContract(dlT, "DL", cfgDLLayers, cfgBSTx, cfgUERx, maximumMCS, cfg);
ul = localMIMODirectionContract(ulT, "UL", cfgULLayers, cfgUETx, cfgBSRx, maximumMCS, cfg);
muPairRows = dl.MUPairedRows + ul.MUPairedRows;
muExecutionOk = ~muRequested || muPairRows > 0;
observed = dl.ObservedRows > 0 && ul.ObservedRows > 0;
ok = observed && dl.ExactOk && ul.ExactOk && muExecutionOk;

T = table(cfgDLLayers, cfgULLayers, bootstrapMCS, maximumMCS, ...
    cfgBSTx, cfgUERx, cfgUETx, cfgBSRx, ...
    dl.ObservedRows, ul.ObservedRows, ...
    dl.RankMean, dl.RankMax, dl.RankExactFraction, ...
    ul.RankMean, ul.RankMax, ul.RankExactFraction, ...
    dl.PhysicalAntennaExactFraction, ul.PhysicalAntennaExactFraction, ...
    dl.MCSMin, dl.MCSMax, ul.MCSMin, ul.MCSMax, ...
    dl.ModulationSet, ul.ModulationSet, dl.MCSTableSet, ul.MCSTableSet, ...
    dl.MCSRangeOk, ul.MCSRangeOk, dl.MCSProfileExactOk, ul.MCSProfileExactOk, ...
    dl.RuntimeArrayModelOk, ul.RuntimeArrayModelOk, ...
    muRequested, dl.MUPairedRows, ul.MUPairedRows, muExecutionOk, ...
    dl.ExactOk, ul.ExactOk, ok, ...
    "raw_waveform_trials_rank_layers_physical_arrays_and_ts38214_mcs_profile", ...
    'VariableNames', {'ConfiguredDLLayers','ConfiguredULLayers','ConfiguredBootstrapMCS','ConfiguredMaximumMCS', ...
    'ConfiguredDLTxAntennas','ConfiguredDLRxAntennas','ConfiguredULTxAntennas','ConfiguredULRxAntennas', ...
    'ObservedDLRows','ObservedULRows', ...
    'AchievedDL_RI_mean','AchievedDL_RI_max','DL_RankExactFraction', ...
    'AchievedUL_RI_mean','AchievedUL_RI_max','UL_RankExactFraction', ...
    'DL_PhysicalAntennaExactFraction','UL_PhysicalAntennaExactFraction', ...
    'ObservedDL_MCS_min','ObservedDL_MCS_max','ObservedUL_MCS_min','ObservedUL_MCS_max', ...
    'ObservedDL_ModulationSet','ObservedUL_ModulationSet','ObservedDL_MCSTableSet','ObservedUL_MCSTableSet', ...
    'DL_MCSRangeOk','UL_MCSRangeOk','DL_MCSProfileExactOk','UL_MCSProfileExactOk', ...
    'DL_RuntimeArrayModelOk','UL_RuntimeArrayModelOk', ...
    'MUMIMOConfigured','DLMUPairedRows','ULMUPairedRows','MUMIMOExecutionOk', ...
    'DLConfiguredEffectiveExactOk','ULConfiguredEffectiveExactOk', ...
    'MimoKpiReconciliationOk','EvidenceSource'});
end

function out = localMIMODirectionContract(T, direction, configuredLayers, configuredTx, configuredRx, maximumMCS, cfg)
out = struct( ...
    "ObservedRows", double(localHeight(T)), "RankMean", NaN, "RankMax", NaN, ...
    "RankExactFraction", NaN, "PhysicalAntennaExactFraction", NaN, ...
    "MCSMin", NaN, "MCSMax", NaN, "ModulationSet", "", "MCSTableSet", "", ...
    "MCSRangeOk", false, "MCSProfileExactOk", false, ...
    "RuntimeArrayModelOk", false, "MUPairedRows", 0, "ExactOk", false);
if ~(istable(T) && height(T) > 0)
    return;
end

layers = localNumericColumn(T, "Layers");
if all(~isfinite(layers))
    layers = localNumericColumn(T, "Rank");
end
finiteLayers = layers(isfinite(layers));
out.RankMean = localMean(finiteLayers);
out.RankMax = localMax(finiteLayers);
rankExact = isfinite(configuredLayers) && ~isempty(finiteLayers) && ...
    numel(finiteLayers) == height(T) && all(abs(finiteLayers - configuredLayers) < 1e-9);
if isfinite(configuredLayers) && ~isempty(finiteLayers)
    out.RankExactFraction = mean(abs(finiteLayers - configuredLayers) < 1e-9);
end

physicalTx = localNumericColumn(T, "PhysicalTxAntennas");
physicalRx = localNumericColumn(T, "PhysicalRxAntennas");
antennaRowOk = isfinite(physicalTx) & isfinite(physicalRx) & ...
    abs(physicalTx - configuredTx) < 1e-9 & abs(physicalRx - configuredRx) < 1e-9;
if ~isempty(antennaRowOk)
    out.PhysicalAntennaExactFraction = mean(antennaRowOk);
end
sameAssumptions = localLogicalColumn(T, "ChannelUsesSameRuntimeAntennaAssumptions");
countOnly = localLogicalColumn(T, "ChannelUsesCountOnlyAntennaModel");
if isempty(sameAssumptions)
    sameAssumptions = false(height(T), 1);
end
if isempty(countOnly)
    countOnly = true(height(T), 1);
end
out.RuntimeArrayModelOk = all(antennaRowOk) && all(sameAssumptions) && ~any(countOnly);

mcs = localNumericColumn(T, "MCSIndex");
fallbackMCS = localNumericColumn(T, "MCS");
mcs(~isfinite(mcs) & isfinite(fallbackMCS)) = fallbackMCS(~isfinite(mcs) & isfinite(fallbackMCS));
finiteMCS = mcs(isfinite(mcs));
out.MCSMin = localMin(finiteMCS);
out.MCSMax = localMax(finiteMCS);
out.MCSRangeOk = numel(finiteMCS) == height(T) && all(finiteMCS >= 0 & finiteMCS <= maximumMCS);

mods = upper(strtrim(localStringColumn(T, "Modulation")));
tables = lower(strtrim(localStringColumn(T, "MCSTable")));
rates = localNumericColumn(T, "TargetCodeRate");
out.ModulationSet = strjoin(unique(mods(strlength(mods) > 0), "stable"), "|");
out.MCSTableSet = strjoin(unique(tables(strlength(tables) > 0), "stable"), "|");
profileOk = numel(mods) == height(T) && numel(tables) == height(T) && numel(rates) == height(T);
if profileOk
    for i = 1:height(T)
        tableToken = tables(i);
        if strlength(tableToken) == 0
            try
                tableToken = string(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
            catch
                profileOk = false;
                break;
            end
        end
        profile = sixgr.link.resolveMCSProfile(tableToken, mcs(i));
        if ~logical(profile.Valid) || upper(string(profile.Modulation)) ~= mods(i) || ...
                ~(isfinite(rates(i)) && abs(double(profile.TargetCodeRate) - rates(i)) < 1e-12)
            profileOk = false;
            break;
        end
    end
end
out.MCSProfileExactOk = logical(profileOk);

groupSize = localNumericColumn(T, "MUMIMOGroupSize");
muEnabled = localLogicalColumn(T, "MUMIMOEnabled");
if isempty(muEnabled)
    muEnabled = false(height(T), 1);
end
out.MUPairedRows = double(nnz(isfinite(groupSize) & groupSize >= 2 & muEnabled));
out.ExactOk = rankExact && out.RuntimeArrayModelOk && out.MCSRangeOk && out.MCSProfileExactOk;
end

function T = localBuildSchedulerTable(dlT, ulT, cfg)
slotMs = localNumber(cfg, ["frame_timing.slot_duration_ms","numerology.slot_duration_ms"], 0.5);
[dlGoodput, dlBits, dlTime] = localGoodputMbps(dlT, slotMs);
[ulGoodput, ulBits, ulTime] = localGoodputMbps(ulT, slotMs);
dlBLER = localBLER(dlT);
ulBLER = localBLER(ulT);
ok = localHeight(dlT) > 0 && localHeight(ulT) > 0 && isfinite(dlGoodput) && dlGoodput > 0 && ...
    isfinite(ulGoodput) && ulGoodput > 0;
T = table(localHeight(dlT), localHeight(ulT), dlBits, ulBits, dlTime, ulTime, dlGoodput, ulGoodput, ...
    dlBLER, ulBLER, ok, "trial_crc_goodbits_airtime_columns", ...
    'VariableNames', {'DL_GrantCount','UL_GrantCount','DL_GoodBits','UL_GoodBits','DL_Airtime_s','UL_Airtime_s', ...
    'DL_Goodput_Mbps','UL_Goodput_Mbps','DL_BLER','UL_BLER','SchedulerKpiReconciliationOk','EvidenceSource'});
end

function T = localBuildMobilityTable(cfg, mobilityArtifacts, runFolder)
resolution = sixgr.util.structGet(mobilityArtifacts, "Resolution", table());
if ~(istable(resolution) && height(resolution) > 0)
    resolution = localReadTable(fullfile(runFolder, "mobility", "csv", "trajectory_resolution.csv"));
end
slotMs = localNumber(cfg, ["frame_timing.slot_duration_ms","numerology.slot_duration_ms"], 0.5);
slots = localNumber(cfg, ["run.total_slots","run_control.total_slots","simulation.n_slots"], NaN);
speedKmh = localNumber(cfg, ["mobility.ue_speed_kmh","channels.mobility_kmph"], NaN);
actual = localFirstFinite(localFiniteColumn(resolution, "ActualDistanceTravelled_m"));
required = localFirstFinite(localFiniteColumn(resolution, "RequiredTraversalSlots"));
configuredSlots = localFirstFinite(localFiniteColumn(resolution, "ConfiguredSlots"));
if isfinite(configuredSlots)
    slots = configuredSlots;
end
full = localFirstLogicalColumn(resolution, "FullTrajectoryExecutedOk", false);
expected = NaN;
if isfinite(speedKmh) && isfinite(slots)
    expected = (speedKmh / 3.6) * double(slots) * (slotMs / 1e3);
end
if isfinite(required) && isfinite(speedKmh)
    expected = (speedKmh / 3.6) * double(required) * (slotMs / 1e3);
end
mismatch = abs(expected - actual);
ok = full && isfinite(mismatch) && mismatch <= 0.1;
T = table(logical(full), slots, required, speedKmh, expected, actual, mismatch, ok, ...
    "mobility_runtime_trajectory_resolution", ...
    'VariableNames', {'FullTrajectoryExecuted','ConfiguredSlots','RequiredTraversalSlots','ConfiguredSpeed_kmh', ...
    'ExpectedDistance_m','ActualDistance_m','DistanceMismatch_m','MobilityKpiReconciliationOk','EvidenceSource'});
end

function T = localBuildChannelRFTable(cfoT, phaseNoiseT, timingT, iqT, paT, evmT, paprT, rfChainT)
cfoOk = localAllFlag(cfoT, "CfoConfiguredAppliedOk");
pnOk = localAllFlag(phaseNoiseT, "PhaseNoiseConfiguredAppliedOk");
timingOk = localAllFlag(timingT, "TimingOffsetConfiguredAppliedOk");
iqOk = localAllFlag(iqT, "IqImbalanceConfiguredAppliedOk");
paOk = localAllFlag(paT, "PaConfiguredAppliedOk");
evmOk = localAllFlag(evmT, "EvmReconciliationOk");
paprOk = localAllFlag(paprT, "PaprReconciliationOk");
rfOk = localAllFlag(rfChainT, "RfChainDefinitionOk");
ok = cfoOk && pnOk && timingOk && iqOk && paOk && evmOk && paprOk && rfOk;
T = table(cfoOk, pnOk, timingOk, iqOk, paOk, evmOk, paprOk, rfOk, ok, ...
    "derived_from_rf_reconciliation_subgates", ...
    'VariableNames', {'CfoOk','PhaseNoiseOk','TimingOffOk','IqOk','PaOk','EvmOk','PaprOk','RfChainOk', ...
    'ChannelRfConfiguredVsAppliedOk','EvidenceSource'});
end

function T = localEffectiveRows(T)
if ~(istable(T) && height(T) > 0)
    T = table();
    return;
end
mask = true(height(T), 1);
if localHasColumn(T, "IsWarmupFrame")
    mask = mask & ~localColumnAsLogical(T.IsWarmupFrame);
end
if localHasColumn(T, "FinalizedFlag")
    finalized = localColumnAsLogical(T.FinalizedFlag);
    if any(finalized)
        mask = mask & finalized;
    end
end
if localHasColumn(T, "Status")
    status = upper(strtrim(string(T.Status)));
    mask = mask & status ~= "CRASH";
end
T = T(mask, :);
end

function T = localReadTable(path)
T = table();
if exist(char(path), "file") ~= 2
    return;
end
try
    T = readtable(char(path), "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function tf = localHasColumn(T, name)
tf = istable(T) && ismember(string(name), string(T.Properties.VariableNames));
end

function n = localHeight(T)
if istable(T)
    n = height(T);
else
    n = 0;
end
end

function vals = localFiniteColumn(T, name)
vals = zeros(0, 1);
if ~(istable(T) && height(T) > 0 && localHasColumn(T, name))
    return;
end
raw = T.(char(string(name)));
if isnumeric(raw) || islogical(raw)
    vals = double(raw(:));
else
    vals = str2double(string(raw(:)));
end
vals = vals(isfinite(vals));
end

function vals = localNumericColumn(T, name)
vals = nan(localHeight(T), 1);
if ~(istable(T) && height(T) > 0 && localHasColumn(T, name))
    return;
end
raw = T.(char(string(name)));
if isnumeric(raw) || islogical(raw)
    vals = double(raw(:));
else
    vals = str2double(string(raw(:)));
end
end

function vals = localStringColumn(T, name)
vals = strings(0, 1);
if istable(T) && height(T) > 0 && localHasColumn(T, name)
    vals = string(T.(char(string(name))));
    vals = vals(:);
end
end

function vals = localLogicalColumn(T, name)
vals = false(0, 1);
if ~(istable(T) && height(T) > 0 && localHasColumn(T, name))
    return;
end
vals = localColumnAsLogical(T.(char(string(name))));
end

function tf = localColumnAsLogical(values)
if islogical(values)
    tf = logical(values(:));
elseif isnumeric(values)
    v = double(values(:));
    tf = isfinite(v) & v ~= 0;
else
    token = lower(strtrim(string(values(:))));
    tf = token == "1" | token == "true" | token == "yes" | token == "pass" | token == "passed" | token == "ok";
end
end

function value = localMean(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = mean(vals, "omitnan");
end
end

function value = localMedian(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = median(vals, "omitnan");
end
end

function value = localMax(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = max(vals, [], "omitnan");
end
end

function value = localMin(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = min(vals, [], "omitnan");
end
end

function value = localMaxAbs(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = max(abs(vals), [], "omitnan");
end
end

function value = localFirstFinite(vals)
vals = double(vals(:));
idx = find(isfinite(vals), 1, "first");
if isempty(idx)
    value = NaN;
else
    value = vals(idx);
end
end

function tf = localAny(vals)
tf = ~isempty(vals) && any(logical(vals));
end

function frac = localFraction(mask)
if isempty(mask)
    frac = NaN;
else
    frac = mean(logical(mask(:)), "omitnan");
end
end

function [goodput, bits, airtime] = localGoodputMbps(T, slotMs)
bits = sum(localFiniteColumn(T, "GoodBits"), "omitnan");
if ~isfinite(bits)
    bits = 0;
end
ttiMs = localFiniteColumn(T, "AirInterfaceTTI_ms");
if isempty(ttiMs)
    airtime = max(localHeight(T), 0) * double(slotMs) / 1e3;
else
    airtime = sum(ttiMs, "omitnan") / 1e3;
end
if airtime > 0
    goodput = bits / airtime / 1e6;
else
    goodput = NaN;
end
gpCol = localFiniteColumn(T, "Goodput_Mbps");
if ~isempty(gpCol) && isfinite(localMean(gpCol)) && localMean(gpCol) > 0
    goodput = localMean(gpCol);
end
end

function bler = localBLER(T)
bler = NaN;
if ~(istable(T) && height(T) > 0 && localHasColumn(T, "CRCPass"))
    return;
end
crc = localColumnAsLogical(T.CRCPass);
if isempty(crc)
    return;
end
bler = mean(~crc, "omitnan");
end

function tf = localAllFlag(T, name)
tf = false;
if istable(T) && height(T) > 0 && localHasColumn(T, name)
    vals = localColumnAsLogical(T.(char(string(name))));
    tf = ~isempty(vals) && all(vals);
end
end

function tf = localFirstLogicalColumn(T, name, defaultValue)
tf = logical(defaultValue);
if istable(T) && height(T) > 0 && localHasColumn(T, name)
    vals = localColumnAsLogical(T.(char(string(name))));
    if ~isempty(vals)
        tf = logical(vals(1));
    end
end
end

function source = localEvidenceSource(observed, goodSource)
if observed
    source = string(goodSource);
else
    source = "evidence_missing";
end
end

function value = localNumber(cfg, paths, defaultValue)
value = defaultValue;
for path = string(paths)
    raw = localGet(cfg, path, []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            return;
        end
    else
        x = str2double(string(raw));
        if isfinite(x)
            value = x;
            return;
        end
    end
end
end

function value = localString(cfg, paths, defaultValue)
value = string(defaultValue);
for path = string(paths)
    raw = localGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    text = string(raw);
    if ~isempty(text) && strlength(strtrim(text(1))) > 0
        value = text(1);
        return;
    end
end
end

function tf = localBool(cfg, paths, defaultValue)
tf = logical(defaultValue);
for path = string(paths)
    raw = localGet(cfg, path, []);
    if islogical(raw) || isnumeric(raw)
        if isscalar(raw)
            tf = logical(raw);
            return;
        end
    else
        s = lower(strtrim(string(raw)));
        if s == "true" || s == "1" || s == "yes" || s == "on"
            tf = true;
            return;
        elseif s == "false" || s == "0" || s == "no" || s == "off"
            tf = false;
            return;
        end
    end
end
end

function value = localGet(cfg, path, defaultValue)
try
    value = sixgr.util.structGet(cfg, path, defaultValue);
catch
    value = defaultValue;
end
end

function out = localTernary(cond, a, b)
if logical(cond)
    out = string(a);
else
    out = string(b);
end
end
