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

noiseT = localBuildNoiseTable(cfg, dlT, ulT);
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
mobilityT = sixgr.analytics.buildMobilityKPIReconciliation(cfg, mobilityArtifacts, runFolder);
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

function T = localBuildNoiseTable(cfg, dlT, ulT)
bwHz = localNumber(cfg, ["global_radio_scope.channel_bandwidth_hz","frequency.bandwidth_hz","air_interface.channel_bandwidth_hz"], 100e6);
ueNF = localNumber(cfg, ["scenario.ue.noiseFigure_dB","air_interface.ue_noise_figure_dB","ue.noise_figure_db"], 7);
bsNF = localNumber(cfg, ["scenario.bs.noiseFigure_dB","air_interface.bs_noise_figure_dB","bs_noise_figure_db"], 5);
kTBdBm = -174 + 10 * log10(max(bwHz, eps));
ueFloor = kTBdBm + ueNF;
bsFloor = kTBdBm + bsNF;
mode = localString(cfg, ["run.noiseOperatingMode","run.noise_operating_mode", ...
    "simulation.noiseOperatingMode","simulation.noise_operating_mode", ...
    "noise.operatingMode","noise.operating_mode"], "");
rows = [localNoiseRow("DL", dlT, mode, bwHz, ueNF, bsNF, kTBdBm, ueFloor, bsFloor); ...
    localNoiseRow("UL", ulT, mode, bwHz, ueNF, bsNF, kTBdBm, ueFloor, bsFloor)];
T = struct2table(rows, "AsArray", true);
end

function row = localNoiseRow(direction, T, configuredMode, bwHz, ueNF, bsNF, kTBdBm, ueFloor, bsFloor)
n = localHeight(T);
mode = localStringColumn(T, "NoiseOperatingMode");
mode = lower(strtrim(mode));
configuredMode = lower(strtrim(string(configuredMode)));
modePresent = numel(mode) == n && n > 0 && all(~ismissing(mode) & strlength(mode) > 0);
modeMatches = modePresent && strlength(configuredMode) > 0 && all(mode == configuredMode);

receiverInput = localNumericColumn(T, "ReceiverInputSampleNoiseVariance");
postEq = localNumericColumn(T, "PostEqualizationNoiseVariance");
llr = localNumericColumn(T, "LLRNoiseVariance");
receiverInputOk = n > 0 && numel(receiverInput) == n && all(isfinite(receiverInput) & receiverInput > 0);
postEqOk = n > 0 && numel(postEq) == n && all(isfinite(postEq) & postEq > 0);
llrOk = n > 0 && numel(llr) == n && all(isfinite(llr) & llr > 0);

status = lower(strtrim(localStringColumn(T, "NoiseVarStatus")));
statusOk = numel(status) == n && n > 0 && all(~ismissing(status) & status == "ok");
strictFailure = localLogicalColumn(T, "NoiseVarStrictFailure");
strictFailureOk = numel(strictFailure) == n && n > 0 && ~any(strictFailure);
varianceSource = localStringColumn(T, "NoiseVarianceSource");
snrSource = localStringColumn(T, "AppliedNoiseSNRSource");
postEqSource = localStringColumn(T, "PostEqualizationNoiseVarianceSource");
llrSource = localStringColumn(T, "LLRNoiseVarianceSource");
varianceSourceOk = localAllNonblank(varianceSource, n);
snrSourceOk = localAllNonblank(snrSource, n);
postEqSourceOk = localAllNonblank(postEqSource, n);
llrSourceOk = localAllNonblank(llrSource, n);

configOk = isfinite(bwHz) && bwHz > 0 && isfinite(ueNF) && isfinite(bsNF) && ...
    strlength(configuredMode) > 0;
ok = configOk && modeMatches && receiverInputOk && postEqOk && llrOk && ...
    statusOk && strictFailureOk && varianceSourceOk && snrSourceOk && ...
    postEqSourceOk && llrSourceOk;
observedMode = strjoin(unique(mode(~ismissing(mode) & strlength(mode) > 0), "stable"), "|");
evidenceSource = localTernary(n > 0, ...
    "runtime_trial_noise_variance_and_lineage_columns:" + configuredMode, ...
    "evidence_missing");
row = struct( ...
    "Direction", char(direction), ...
    "ObservedRows", double(n), ...
    "BandwidthHz", double(bwHz), ...
    "ThermalNoiseDensity_dBmHz", -174, ...
    "ThermalNoisePower_dBm", double(kTBdBm), ...
    "UE_NoiseFigure_dB", double(ueNF), ...
    "BS_NoiseFigure_dB", double(bsNF), ...
    "UE_NoiseFloor_dBm", double(ueFloor), ...
    "BS_NoiseFloor_dBm", double(bsFloor), ...
    "NoiseOperatingMode", char(configuredMode), ...
    "ConfiguredNoiseOperatingMode", char(configuredMode), ...
    "ObservedNoiseOperatingMode", char(observedMode), ...
    "NoiseOperatingModeExactFraction", localFraction(~ismissing(mode) & mode == configuredMode), ...
    "ReceiverInputNoiseVariancePositiveFraction", localFraction(isfinite(receiverInput) & receiverInput > 0), ...
    "PostEqualizationNoiseVariancePositiveFraction", localFraction(isfinite(postEq) & postEq > 0), ...
    "LLRNoiseVariancePositiveFraction", localFraction(isfinite(llr) & llr > 0), ...
    "MeanReceiverInputSampleNoiseVariance", localMean(receiverInput), ...
    "MeanPostEqualizationNoiseVariance", localMean(postEq), ...
    "MeanLLRNoiseVariance", localMean(llr), ...
    "NoiseVarianceStatusOkFraction", localFraction(~ismissing(status) & status == "ok"), ...
    "NoiseVarianceStrictFailureCount", double(nnz(strictFailure)), ...
    "NoiseVarianceSourceObservedFraction", localNonblankFraction(varianceSource), ...
    "AppliedNoiseSNRSourceObservedFraction", localNonblankFraction(snrSource), ...
    "PostEqualizationNoiseVarianceSourceObservedFraction", localNonblankFraction(postEqSource), ...
    "LLRNoiseVarianceSourceObservedFraction", localNonblankFraction(llrSource), ...
    "NoiseReconciliationOk", logical(ok), ...
    "EvidenceSource", char(evidenceSource));
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
[flagPresent, flagEnabled] = localConfiguredInterferenceEnablement(cfg);
configuredModes = localConfiguredInterferenceModes(cfg);
configuredModes = lower(strtrim(configuredModes));
configuredModes = configuredModes(~ismissing(configuredModes) & strlength(configuredModes) > 0);
modeCfg = strjoin(unique(configuredModes, "stable"), "|");
configuredModeKnown = ~isempty(configuredModes);
configuredModeActive = configuredModeKnown && ...
    any(localIsWaveformTruthInterferenceMode(configuredModes)) && ...
    all(localIsDisabledInterferenceMode(configuredModes) | ...
        localIsWaveformTruthInterferenceMode(configuredModes));
configuredModeDisabled = configuredModeKnown && all(localIsDisabledInterferenceMode(configuredModes));
if flagPresent
    configuredEnabled = flagEnabled;
else
    configuredEnabled = configuredModeActive;
end
configuredConsistent = configuredModeKnown && ...
    ((configuredEnabled && configuredModeActive) || (~configuredEnabled && configuredModeDisabled));
modes = localStringColumn(T, "InterferenceMode");
modes = lower(strtrim(modes));
contributorsRaw = localNumericColumn(T, "InterferenceContributorCount");
powerRaw = localNumericColumn(T, "InterferenceAggregatedRxPower_dBm");
source = localStringColumn(T, "InterferencePowerSource");
truth = localLogicalColumn(T, "FullInterfererChannelTruthUsed");
observedRows = localHeight(T);
observed = observedRows > 0 && numel(modes) == observedRows && ...
    numel(contributorsRaw) == observedRows && numel(powerRaw) == observedRows && ...
    numel(source) == observedRows && numel(truth) == observedRows;
validMode = ~ismissing(modes) & strlength(strtrim(modes)) > 0;
modeEvidence = strjoin(unique(modes(validMode), "stable"), "|");
modePresent = observedRows > 0 && numel(modes) == observedRows && ...
    all(~ismissing(modes) & strlength(modes) > 0);
runtimeDisabled = modePresent && all(localIsDisabledInterferenceMode(modes));
runtimeActive = modePresent && all(localIsWaveformTruthInterferenceMode(modes));

contributorsDisabled = observedRows > 0 && numel(contributorsRaw) == observedRows && ...
    all(isfinite(contributorsRaw) & contributorsRaw == 0);
powerDisabled = observedRows > 0 && numel(powerRaw) == observedRows && ...
    ~any(isfinite(powerRaw));
% A disabled waveform path may either leave the power-source cell empty or
% emit the explicit runtime sentinel written by the canonical DL/UL trial
% exporters.  Accept only those two representations.  An arbitrary
% nonempty source remains a contradiction because it could conceal an
% interference contribution that was not accounted for.
sourceDisabled = observedRows > 0 && numel(source) == observedRows && ...
    all(localIsDisabledInterferencePowerSource(source));
truthDisabled = observedRows > 0 && numel(truth) == observedRows && ~any(truth);
disabledIdentity = runtimeDisabled && contributorsDisabled && powerDisabled && sourceDisabled && truthDisabled;

contributorsEnabled = observedRows > 0 && numel(contributorsRaw) == observedRows && ...
    all(isfinite(contributorsRaw) & contributorsRaw > 0);
powerEnabled = observedRows > 0 && numel(powerRaw) == observedRows && all(isfinite(powerRaw));
sourceEnabled = localAllNonblank(source, observedRows);
truthEnabled = observedRows > 0 && numel(truth) == observedRows && all(truth);
enabledTruth = runtimeActive && contributorsEnabled && powerEnabled && sourceEnabled && truthEnabled;

if configuredEnabled
    accountingStatus = "enabled_runtime_waveform_truth";
    runtimeSemanticsOk = enabledTruth;
    evidenceName = "trial_waveform_interference_truth_columns";
else
    accountingStatus = "disabled_runtime_identity";
    runtimeSemanticsOk = disabledIdentity;
    evidenceName = "trial_disabled_interference_identity_columns";
end
ok = observed && configuredConsistent && runtimeSemanticsOk;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredInterferenceMode", char(string(modeCfg)), "ObservedInterferenceMode", char(string(modeEvidence)), ...
    "ConfiguredInterferenceEnabled", logical(configuredEnabled), ...
    "ConfiguredModeConsistent", logical(configuredConsistent), ...
    "ObservedDisabledIdentity", logical(disabledIdentity), ...
    "InterferenceEvaluationStatus", char(accountingStatus), ...
    "MaxContributorCount", localMax(contributorsRaw), "MeanInterferencePower_dBm", localMean(powerRaw), ...
    "InterferencePowerSource", char(strjoin(unique(source(~ismissing(source) & ...
        strlength(strtrim(source)) > 0), "stable"), "|")), ...
    "InterferenceTruthChannelUsed", logical(any(truth)), "InterferenceAccountingOk", logical(ok), ...
    "EvidenceSource", char(localEvidenceSource(observed, evidenceName)));
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

% Resolve the configured operating point from the same canonical authority
% used by the main MIMO evidence builder.  A valid entry in a TS 38.214 MCS
% table is not, by itself, proof that the configured MCS/modulation ran.
mimoCfg = sixgr.mimo.buildMIMOConfigFromScenario(cfg);
dlCfg = mimoCfg(upper(string(mimoCfg.Direction)) == "DL", :);
ulCfg = mimoCfg(upper(string(mimoCfg.Direction)) == "UL", :);

dl = localMIMODirectionContract(dlT, "DL", cfgDLLayers, cfgBSTx, cfgUERx, maximumMCS, cfg, dlCfg);
ul = localMIMODirectionContract(ulT, "UL", cfgULLayers, cfgUETx, cfgBSRx, maximumMCS, cfg, ulCfg);
muPairRows = dl.MUPairedRows + ul.MUPairedRows;
muExecutionOk = ~muRequested || muPairRows > 0;
observed = dl.ObservedRows > 0 && ul.ObservedRows > 0;
ok = observed && dl.ExecutionPolicyOk && ul.ExecutionPolicyOk && muExecutionOk;

T = table(cfgDLLayers, cfgULLayers, bootstrapMCS, maximumMCS, ...
    dl.ConfiguredMCS, ul.ConfiguredMCS, dl.ConfiguredModulation, ul.ConfiguredModulation, ...
    dl.AdaptiveMode, ul.AdaptiveMode, ...
    cfgBSTx, cfgUERx, cfgUETx, cfgBSRx, ...
    dl.ObservedRows, ul.ObservedRows, ...
    dl.RankMean, dl.RankMax, dl.RankExactFraction, ...
    ul.RankMean, ul.RankMax, ul.RankExactFraction, ...
    dl.PhysicalAntennaExactFraction, ul.PhysicalAntennaExactFraction, ...
    dl.MCSMin, dl.MCSMax, ul.MCSMin, ul.MCSMax, ...
    dl.ModulationSet, ul.ModulationSet, dl.MCSTableSet, ul.MCSTableSet, ...
    dl.MCSRangeOk, ul.MCSRangeOk, dl.MCSProfileExactOk, ul.MCSProfileExactOk, ...
    dl.ConfiguredMCSExactOk, ul.ConfiguredMCSExactOk, ...
    dl.ConfiguredModulationExactOk, ul.ConfiguredModulationExactOk, ...
    dl.AdaptivePolicyOk, ul.AdaptivePolicyOk, ...
    dl.RuntimeArrayModelOk, ul.RuntimeArrayModelOk, ...
    dl.RuntimeArrayEvaluationStatus, ul.RuntimeArrayEvaluationStatus, ...
    muRequested, dl.MUPairedRows, ul.MUPairedRows, muExecutionOk, ...
    dl.ExactOk, ul.ExactOk, dl.ExecutionPolicyOk, ul.ExecutionPolicyOk, ok, ...
    "raw_waveform_trials_exact_configuration_and_adaptive_policy_contract", ...
    'VariableNames', {'ConfiguredDLLayers','ConfiguredULLayers','ConfiguredBootstrapMCS','ConfiguredMaximumMCS', ...
    'ConfiguredDL_MCS','ConfiguredUL_MCS','ConfiguredDL_Modulation','ConfiguredUL_Modulation', ...
    'DLAdaptiveOperatingPoint','ULAdaptiveOperatingPoint', ...
    'ConfiguredDLTxAntennas','ConfiguredDLRxAntennas','ConfiguredULTxAntennas','ConfiguredULRxAntennas', ...
    'ObservedDLRows','ObservedULRows', ...
    'AchievedDL_RI_mean','AchievedDL_RI_max','DL_RankExactFraction', ...
    'AchievedUL_RI_mean','AchievedUL_RI_max','UL_RankExactFraction', ...
    'DL_PhysicalAntennaExactFraction','UL_PhysicalAntennaExactFraction', ...
    'ObservedDL_MCS_min','ObservedDL_MCS_max','ObservedUL_MCS_min','ObservedUL_MCS_max', ...
    'ObservedDL_ModulationSet','ObservedUL_ModulationSet','ObservedDL_MCSTableSet','ObservedUL_MCSTableSet', ...
    'DL_MCSRangeOk','UL_MCSRangeOk','DL_MCSProfileExactOk','UL_MCSProfileExactOk', ...
    'DL_ConfiguredMCSExactOk','UL_ConfiguredMCSExactOk', ...
    'DL_ConfiguredModulationExactOk','UL_ConfiguredModulationExactOk', ...
    'DL_AdaptivePolicyOk','UL_AdaptivePolicyOk', ...
    'DL_RuntimeArrayModelOk','UL_RuntimeArrayModelOk', ...
    'DL_RuntimeArrayEvaluationStatus','UL_RuntimeArrayEvaluationStatus', ...
    'MUMIMOConfigured','DLMUPairedRows','ULMUPairedRows','MUMIMOExecutionOk', ...
    'DLConfiguredEffectiveExactOk','ULConfiguredEffectiveExactOk', ...
    'DLExecutionPolicyOk','ULExecutionPolicyOk', ...
    'MimoKpiReconciliationOk','EvidenceSource'});
end

function out = localMIMODirectionContract(T, direction, configuredLayers, configuredTx, configuredRx, maximumMCS, cfg, cfgRow)
out = struct( ...
    "ObservedRows", double(localHeight(T)), "RankMean", NaN, "RankMax", NaN, ...
    "RankExactFraction", NaN, "PhysicalAntennaExactFraction", NaN, ...
    "MCSMin", NaN, "MCSMax", NaN, "ModulationSet", "", "MCSTableSet", "", ...
    "MCSRangeOk", false, "MCSProfileExactOk", false, ...
    "ConfiguredMCS", NaN, "ConfiguredModulation", "", "AdaptiveMode", false, ...
    "ConfiguredMCSExactOk", false, "ConfiguredModulationExactOk", false, ...
    "AdaptivePolicyOk", false, "RuntimeArrayModelOk", false, ...
    "RuntimeArrayEvaluationStatus", "runtime_array_evidence_missing", ...
    "MUPairedRows", 0, "ExactOk", false, "ExecutionPolicyOk", false);
if istable(cfgRow) && height(cfgRow) == 1
    out.ConfiguredMCS = double(cfgRow.ConfiguredMCS(1));
    out.ConfiguredModulation = upper(strtrim(string(cfgRow.ConfiguredModulation(1))));
    out.AdaptiveMode = logical(cfgRow.AdaptiveMode(1));
    if isfinite(double(cfgRow.ConfiguredMaximumMCS(1)))
        maximumMCS = double(cfgRow.ConfiguredMaximumMCS(1));
    end
end
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
hasSameAssumptions = localHasColumn(T, "ChannelUsesSameRuntimeAntennaAssumptions");
hasCountOnly = localHasColumn(T, "ChannelUsesCountOnlyAntennaModel");
sameAssumptions = localLogicalColumn(T, "ChannelUsesSameRuntimeAntennaAssumptions");
countOnly = localLogicalColumn(T, "ChannelUsesCountOnlyAntennaModel");
if isempty(sameAssumptions)
    sameAssumptions = false(height(T), 1);
end
if isempty(countOnly)
    countOnly = true(height(T), 1);
end
fullRuntimeArrayOk = all(antennaRowOk) && hasSameAssumptions && hasCountOnly && ...
    numel(sameAssumptions) == height(T) && numel(countOnly) == height(T) && ...
    all(sameAssumptions) && ~any(countOnly);
channelModels = upper(strtrim(localStringColumn(T, "ChannelModel")));
explicitAWGN = numel(channelModels) == height(T) && ...
    all(~ismissing(channelModels) & channelModels == "AWGN");
scalarAWGNSISOIdentity = all(antennaRowOk) && configuredTx == 1 && configuredRx == 1 && ...
    configuredLayers == 1 && rankExact && explicitAWGN && hasCountOnly && ...
    numel(countOnly) == height(T) && all(countOnly);
if fullRuntimeArrayOk
    out.RuntimeArrayModelOk = true;
    out.RuntimeArrayEvaluationStatus = "physical_runtime_array_model";
elseif scalarAWGNSISOIdentity
    % A scalar unit channel is an allowed truth shortcut only for an
    % explicit 1x1 AWGN link.  It must never qualify a fading or spatial
    % MIMO campaign, where per-resource/per-antenna channel evidence is
    % mandatory.
    out.RuntimeArrayModelOk = true;
    out.RuntimeArrayEvaluationStatus = "explicit_awgn_siso_scalar_identity";
else
    out.RuntimeArrayModelOk = false;
    out.RuntimeArrayEvaluationStatus = "runtime_array_model_mismatch";
end

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
out.ConfiguredMCSExactOk = isfinite(out.ConfiguredMCS) && ...
    numel(finiteMCS) == height(T) && all(finiteMCS == out.ConfiguredMCS);
out.ConfiguredModulationExactOk = strlength(out.ConfiguredModulation) > 0 && ...
    numel(mods) == height(T) && all(mods == out.ConfiguredModulation);
out.AdaptivePolicyOk = localAdaptiveOperatingPointPolicyOk(T, mcs, mods, maximumMCS, out.AdaptiveMode);

groupSize = localNumericColumn(T, "MUMIMOGroupSize");
muEnabled = localLogicalColumn(T, "MUMIMOEnabled");
if isempty(muEnabled)
    muEnabled = false(height(T), 1);
end
out.MUPairedRows = double(nnz(isfinite(groupSize) & groupSize >= 2 & muEnabled));
spatialAndProfileOk = rankExact && out.RuntimeArrayModelOk && out.MCSRangeOk && out.MCSProfileExactOk;
out.ExactOk = spatialAndProfileOk && out.ConfiguredMCSExactOk && out.ConfiguredModulationExactOk;
operatingPointPolicyOk = (~out.AdaptiveMode && out.ConfiguredMCSExactOk && ...
    out.ConfiguredModulationExactOk) || (out.AdaptiveMode && out.AdaptivePolicyOk);
out.ExecutionPolicyOk = spatialAndProfileOk && operatingPointPolicyOk;
end

function tf = localAdaptiveOperatingPointPolicyOk(T, transmittedMCS, transmittedModulation, maximumMCS, adaptiveMode)
% An adaptive mismatch is acceptable only when the raw runtime row proves
% the scheduled decision, its application, its bound and its causal
% measurement lineage.  Merely falling inside an MCS range is insufficient.
if ~adaptiveMode
    tf = true;
    return;
end
scheduled = localNumericColumn(T, "ScheduledMCS");
if all(~isfinite(scheduled))
    scheduled = localNumericColumn(T, "ScheduledMCSIndex");
end
scheduledModulation = upper(strtrim(localStringColumn(T, "ScheduledModulation")));
scheduledFlag = localLogicalColumn(T, "LinkAdaptationScheduled");
appliedFlag = localLogicalColumn(T, "LinkAdaptationApplied");
if isempty(scheduledFlag), scheduledFlag = false(height(T), 1); end
if isempty(appliedFlag), appliedFlag = false(height(T), 1); end

lineage = strings(height(T), 1);
for name = ["MCSSelectionSource","MCSAuthority","ModulationAuthority", ...
        "AppliedOperatingPointSource","GrantOperatingPointSource"]
    values = strtrim(localStringColumn(T, name));
    if numel(values) == height(T)
        missing = strlength(lineage) == 0 & strlength(values) > 0;
        lineage(missing) = values(missing);
    end
end
evidenceId = strings(height(T), 1);
for name = ["CSIReportId","CSIPayloadHex","GrantContextId"]
    values = strtrim(localStringColumn(T, name));
    if numel(values) == height(T)
        missing = strlength(evidenceId) == 0 & strlength(values) > 0;
        evidenceId(missing) = values(missing);
    end
end
valueStatus = lower(strtrim(localStringColumn(T, "MCSValueStatus")));
if numel(valueStatus) ~= height(T)
    valueStatus = strings(height(T), 1);
end
widebandCQI = localNumericColumn(T, "WidebandCQI");
cqiDerivedMCS = localNumericColumn(T, "CQIDerivedMCS");
if all(~isfinite(cqiDerivedMCS))
    cqiDerivedMCS = localNumericColumn(T, "RawCQIDerivedMCS");
end
feedbackDecision = strlength(valueStatus) > 0 & ...
    ~contains(valueStatus, "bootstrap") & ...
    ~contains(valueStatus, "pending_data_feedback") & ...
    ~contains(valueStatus, "missing") & ...
    ~contains(valueStatus, "unavailable") & ...
    ~contains(valueStatus, "rejected") & ...
    ~contains(valueStatus, "error") & ...
    isfinite(widebandCQI) & isfinite(cqiDerivedMCS);
forbidden = ["proxy","fallback","configured_fixed","legacy","missing","unavailable","error","rejected"];
forbiddenLineage = false(height(T), 1);
for token = forbidden
    forbiddenLineage = forbiddenLineage | contains(lower(lineage), token);
end
tf = numel(scheduled) == height(T) && numel(transmittedMCS) == height(T) && ...
    numel(scheduledModulation) == height(T) && numel(transmittedModulation) == height(T) && ...
    all(scheduledFlag) && all(appliedFlag) && ...
    all(isfinite(scheduled) & isfinite(transmittedMCS) & scheduled == transmittedMCS) && ...
    all(scheduled >= 0 & scheduled <= maximumMCS) && ...
    all(strlength(scheduledModulation) > 0 & scheduledModulation == transmittedModulation) && ...
    all(strlength(lineage) > 0 & ~forbiddenLineage) && ...
    all(strlength(evidenceId) > 0) && any(feedbackDecision);
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
    raw = T.(char(string(name)));
    vals = string(raw);
    vals = vals(:);
    % readtable can infer an all-empty CSV text column as numeric NaN even
    % with TextType="string". Preserve those cells as missing evidence;
    % the literal token "NaN" is not a valid runtime source or mode.
    if isnumeric(raw)
        missingMask = ~isfinite(double(raw(:)));
        vals(missingMask) = missing;
    end
end
end

function vals = localLogicalColumn(T, name)
vals = false(0, 1);
if ~(istable(T) && height(T) > 0 && localHasColumn(T, name))
    return;
end
vals = localColumnAsLogical(T.(char(string(name))));
end

function tf = localAllNonblank(values, expectedCount)
values = string(values(:));
tf = expectedCount > 0 && numel(values) == expectedCount && ...
    all(~ismissing(values) & strlength(strtrim(values)) > 0);
end

function frac = localNonblankFraction(values)
values = string(values(:));
if isempty(values)
    frac = NaN;
else
    frac = mean(~ismissing(values) & strlength(strtrim(values)) > 0);
end
end

function tf = localIsDisabledInterferenceMode(values)
values = lower(strtrim(string(values(:))));
tf = ~ismissing(values) & (values == "none" | values == "disabled" | ...
    values == "off" | values == "no_interference" | values == "identity");
end

function tf = localIsDisabledInterferencePowerSource(values)
values = lower(strtrim(string(values(:))));
blank = ismissing(values) | strlength(values) == 0;
explicitRuntimeIdentity = ...
    values == "not_emitted_by_active_dl_pdsch_trials_runtime" | ...
    values == "not_emitted_by_active_ul_pusch_trials_runtime";
tf = blank | explicitRuntimeIdentity;
end

function tf = localIsWaveformTruthInterferenceMode(values)
values = lower(strtrim(string(values(:))));
tf = ~ismissing(values) & (values == "full_per_link_channel_waveform_sum" | ...
    values == "shared_slot_waveform_superposition");
end

function modes = localConfiguredInterferenceModes(cfg)
paths = [ ...
    "interference.inter_cell_execution_mode"
    "interference.intra_cell_execution_mode"
    "run.interferenceExecutionMode"
    "run.intraCellInterferenceExecutionMode"
    "run.interference_mode"
    "topology.inter_cell_execution_mode"];
modes = strings(0, 1);
for path = paths.'
    raw = localGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    value = string(raw);
    value = value(:);
    value = value(~ismissing(value) & strlength(strtrim(value)) > 0);
    modes = [modes; value]; %#ok<AGROW>
end
end

function [present, enabled] = localConfiguredInterferenceEnablement(cfg)
paths = [ ...
    "interference.inter_cell_interference_flag"
    "interference.inter_cell_interference_enable"
    "interference.interCellEnabled"
    "channel.interference.interCellEnabled"
    "interference.intra_cell_interference_flag"
    "interference.intra_cell_interference_enable"
    "interference.intraCellEnabled"
    "channel.interference.intraCellEnabled"
    "interference.mu_mimo_interference_flag"];
present = false;
enabled = false;
for path = paths.'
    raw = localGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    [parsed, ok] = localParseBool(raw);
    if ok
        present = true;
        enabled = enabled || parsed;
    end
end
end

function [value, ok] = localParseBool(raw)
value = false;
ok = false;
if (islogical(raw) || isnumeric(raw)) && isscalar(raw) && isfinite(double(raw))
    value = logical(raw);
    ok = true;
    return;
end
token = lower(strtrim(string(raw)));
if isscalar(token) && any(token == ["true","1","yes","on"])
    value = true;
    ok = true;
elseif isscalar(token) && any(token == ["false","0","no","off"])
    value = false;
    ok = true;
end
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
