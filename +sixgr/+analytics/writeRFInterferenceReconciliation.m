function artifacts = writeRFInterferenceReconciliation(cfg, runFolder, rawTrials, mobilityArtifacts, slotTrace)
%WRITERFINTERFERENCERECONCILIATION Publish RF/interference evidence gates.
%
% These are derived audit artifacts. A gate passes only when backed by
% concrete runtime trial columns. A disabled-stage configuration alone is
% not proof of execution. Missing evidence is written as a false reconciliation
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
[dlT,ulT]=sixgr.analytics.resolveRetainedDirectionalTrials(runFolder,dlT,ulT);
% Credit logical TBs before any population slicing; both exporters use the
% same owner for this artifact instead of overwriting it with anchor gates.
schedulerT = sixgr.analytics.buildSchedulerKPIReconciliation(dlT, ulT, cfg);
dlT = localEffectiveRows(dlT);
ulT = localEffectiveRows(ulT);

noiseT = localBuildNoiseTable(cfg, dlT, ulT);
interferenceT = localBuildInterferenceTable(dlT, ulT, cfg);
rfChainT = localBuildRFChainTable(cfg);
cfoT = localBuildCFOTable(dlT, ulT, cfg);
syncObservationsT = localBuildSynchronizationObservations(dlT, ulT);
phaseNoiseT = localBuildPhaseNoiseTable(dlT, ulT, cfg);
timingT = localBuildTimingTable(dlT, ulT, cfg);
iqT = localBuildIQTable(dlT, ulT, cfg);
paT = localBuildPATable(dlT, ulT, cfg);
evmT = localBuildEVMTable(dlT, ulT, cfg);
paprT = localBuildPAPRTable(dlT, ulT, cfg);
mimoT = localBuildMIMOTable(dlT, ulT, cfg);
mobilityT = sixgr.analytics.buildMobilityKPIReconciliation(cfg, mobilityArtifacts, runFolder);
channelRfT = localBuildChannelRFTable(cfoT, phaseNoiseT, timingT, iqT, paT, evmT, paprT, rfChainT);

artifacts = struct();
artifacts.NoiseReconciliation = localWrite(layout.ReportCSVDir, "noise_reconciliation.csv", noiseT);
artifacts.InterferenceAccounting = localWrite(layout.ReportCSVDir, "interference_accounting.csv", interferenceT);
artifacts.RFChainDefinition = localWrite(layout.ReportCSVDir, "rf_chain_definition.csv", rfChainT);
artifacts.CFOReconciliation = localWrite(layout.ReportCSVDir, "cfo_reconciliation.csv", cfoT);
artifacts.SynchronizationObservations = localWrite(layout.ReportCSVDir, "rf_synchronization_observations.csv", syncObservationsT);
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
    "SynchronizationObservations", syncObservationsT, ...
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
receiverInputDomain = localStringColumn(T, "ReceiverInputSampleNoiseVarianceDomain");
receiverInputSource = localStringColumn(T, "ReceiverInputSampleNoiseVarianceSource");
strictReceiverEvidence = localLogicalColumn(T, "StrictReceiverEvidenceOk");
referenceEstimatedDownstream = n > 0 && numel(receiverInput) == n && ...
    all(isnan(receiverInput)) && numel(receiverInputDomain) == n && ...
    all(receiverInputDomain == "receiver_sample_waveform_post_composite_front_end") && ...
    numel(receiverInputSource) == n && all(receiverInputSource == ...
    "unavailable_after_actual_RF_ADC_gain_compensation_receiver_reference_RE_estimation_required") && ...
    numel(strictReceiverEvidence) == n && all(strictReceiverEvidence);
receiverInputEvidenceOk = receiverInputOk || referenceEstimatedDownstream;

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
ok = configOk && modeMatches && receiverInputEvidenceOk && postEqOk && llrOk && ...
    statusOk && strictFailureOk && varianceSourceOk && snrSourceOk && ...
    postEqSourceOk && llrSourceOk;
observedMode = strjoin(unique(mode(~ismissing(mode) & strlength(mode) > 0), "stable"), "|");
if receiverInputOk
    receiverInputEvaluationStatus = "finite_post_front_end_variance_available";
elseif referenceEstimatedDownstream
    receiverInputEvaluationStatus = ...
        "not_scalar_after_actual_front_end_downstream_reference_estimates_strictly_valid";
else
    receiverInputEvaluationStatus = "missing_or_unqualified_receiver_input_noise_evidence";
end
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
    "ReceiverInputNoiseVarianceUnavailableFraction", localFraction(isnan(receiverInput)), ...
    "ReceiverInputNoiseEvidenceOk", logical(receiverInputEvidenceOk), ...
    "ReceiverInputNoiseEvaluationStatus", char(receiverInputEvaluationStatus), ...
    "DownstreamReferenceEstimatedNoisePath", logical(referenceEstimatedDownstream), ...
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
% Live exports receive buildInternalConfig output, not the scenario YAML.
% Prefer the same effective device fields used by applyRFImpairmentChain.
% An absent definition is not an ideal RF chain or a 12-bit converter.
[paModel, paSource] = localString(cfg, ["rf.pa.method", ...
    "rf.frontend.pa.model","rf_frontend.pa.model", ...
    "impairments.pa_nonlinearity.model","power_and_rf_frontend.pa_model"], "");
[osc, oscSource] = localString(cfg, ["rf.frontend.phase_noise.profile_id", ...
    "rf_frontend.phase_noise.profile_id","impairments.oscillator_profile", ...
    "power_and_rf_frontend.oscillator_profile"], "");
[dacBits, dacSource] = localNumber(cfg, ["rf.frontend.dac.bits", ...
    "rf.dacBits","phy.impairments.dacQuantizationBits", ...
    "rf_frontend.dac.bits","impairments.dac_quantization_bits", ...
    "power_and_rf_frontend.dac_bits"], NaN);
[adcBits, adcSource] = localNumber(cfg, ["rf.hardware.adc.resolutionBits", ...
    "rf.adcBits","phy.impairments.adcQuantizationBits", ...
    "rf.frontend.receiver.adc.bits","rf_frontend.receiver.adc.bits", ...
    "impairments.adc_quantization_bits","power_and_rf_frontend.adc_bits"], NaN);
ueChains = localNumber(cfg, ["mimo.ue_num_rf_chains","scenario.ue.nTxAnt"], NaN);
bsChains = localNumber(cfg, ["mimo.bs_num_rf_chains","scenario.bs.nTxAnt"], NaN);
counts = [dacBits adcBits ueChains bsChains];
ok = all(isfinite(counts) & counts > 0 & counts == fix(counts)) && ...
    all([dacBits adcBits] >= 2 & [dacBits adcBits] <= 24) && ...
    strlength(strtrim(paModel)) > 0 && strlength(strtrim(osc)) > 0;
T = table("DAC->IQ->element_RF->PA->phase_noise->CFO->timing->sample_clock", ...
    "timing->LO_CFO->phase_noise->IQ->element_RF->sample_clock->AGC->ADC", ...
    string(paModel), dacBits, adcBits, string(osc), ueChains, bsChains, ok, ...
    "explicit_rf_chain_configuration_not_execution_evidence", ...
    'VariableNames', {'TX_chain','RX_chain','PA_model','DAC_bits','ADC_bits','OscillatorProfile', ...
    'UE_RFChainCount','BS_RFChainCount','RfChainDefinitionOk','EvidenceSource'});
T.PAModelConfigurationSource = paSource;
T.OscillatorProfileConfigurationSource = oscSource;
T.DACBitsConfigurationSource = dacSource;
T.ADCBitsConfigurationSource = adcSource;
T.EvaluationScope = "configuration_definition_only_not_RF_qualification";
end

function T = localBuildCFOTable(dlT, ulT, cfg)
% The live producer passes the resolved internal config; offline audits
% may pass scenario YAML. Runtime injection authority takes precedence.
configured = localNumber(cfg, ["phy.impairments.cfoHz","rf.cfo_Hz", ...
    "impairments.cfo_hz","impairments.cfo.value_hz", ...
    "rf.cfo_hz","power_and_rf_frontend.cfo_hz"], NaN);
configuredEnabled = localBool(cfg, ["phy.impairments.cfoEnabled", ...
    "impairments.cfo_enabled","impairments.cfo.enabled", ...
    "rf.cfo_enabled","power_and_rf_frontend.cfo_enabled"], abs(configured) > 0);
if ~configuredEnabled && isfinite(configured), configured = 0; end
rows = [localCFOTrialRow("DL", dlT, configured, configuredEnabled); ...
    localCFOTrialRow("UL", ulT, configured, configuredEnabled)];
T = struct2table(rows, "AsArray", true);
end

function row = localCFOTrialRow(direction, T, configured, configuredEnabled)
observed = istable(T) && height(T) > 0 && localHasColumn(T, "InjectedCFO_Hz");
inj = localNumericColumn(T, "InjectedCFO_Hz");
est = localNumericColumn(T, "EstimatedCFO_PreCorrection_Hz");
res = localNumericColumn(T, "ResidualCFO_PostCorrection_Hz");
n = localHeight(T);
injectionComplete = n > 0 && numel(inj) == n && all(isfinite(inj));
mismatch = localMaxAbs(inj - configured);
residual = localMaxAbs(res);
estimationRequired = logical(configuredEnabled) || abs(double(configured)) > 1e-12;
if ~isfinite(configured)
    estimatorOk = false;
    estimatorStatus = "configuration_unavailable";
elseif estimationRequired
    estimatorComplete = n > 0 && numel(est) == n && numel(res) == n && ...
        all(isfinite(est)) && all(isfinite(res));
    estimatorOk = estimatorComplete && isfinite(residual) && residual <= 1;
    if ~estimatorComplete
        estimatorStatus = "required_missing_observations";
    elseif ~estimatorOk
        estimatorStatus = "required_residual_limit_failed";
    else
        estimatorStatus = "required_and_observed";
    end
else
    % A disabled zero-CFO stage is an identity transform.  Requiring an
    % estimator output in this case turns an honest N/A into a false fail.
    estimatorOk = true;
    estimatorStatus = "not_applicable_disabled_zero_cfo_identity";
end
% This compares configuration with execution metadata, not a noisy estimate.
% A one-hertz acceptance window would silently accept a different injection.
metadataTolerance = 32 * eps(max(abs(double(configured)), 1));
injectionOk = observed && injectionComplete && isfinite(mismatch) && mismatch <= metadataTolerance;
ok = injectionOk && estimatorOk;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredCFO_Hz", double(configured), "MeanInjectedCFO_Hz", localMean(inj), ...
    "MeanEstimatedCFO_PreCorrection_Hz", localMean(est), "MeanResidualCFO_PostCorrection_Hz", localMean(res), ...
    "MaxConfiguredAppliedMismatch_Hz", double(mismatch), "MaxResidualCFO_Hz", double(residual), ...
    "CFOEstimationRequired", logical(estimationRequired), "CFOEstimationStatus", char(estimatorStatus), ...
    "CFOInjectionConfiguredAppliedOk", logical(injectionOk), ...
    "CFOReferenceResidualCheckOk", logical(estimatorOk), ...
    "CFOEstimatorQualificationOk", false, ...
    "CFOEstimatorQualificationStatus", 'not_established_by_injected_oscillator_reference_difference', ...
    "ReferenceResidualLimit_Hz", 1, ...
    "ReferenceResidualLimitSource", 'legacy_reconciliation_policy_not_a_3GPP_accuracy_requirement', ...
    "InjectionMetadataTolerance_Hz", metadataTolerance, ...
    "CfoConfiguredAppliedOk", logical(ok), ...
    "EvaluationScope", 'legacy_injection_and_reference_residual_checks_not_receiver_accuracy_qualification', ...
    "EvidenceSource", char(localEvidenceSource(observed, "trial_rf_cfo_columns")));
end

function T = localBuildTimingTable(dlT, ulT, cfg)
configured = localNumber(cfg, ["phy.impairments.timingOffsetSamples", ...
    "rf.timingOffsetSamples","impairments.timing_offset_samples", ...
    "impairments.to.value_samples","rf.timing_offset_samples"], NaN);
enabled = localBool(cfg, ["phy.impairments.timingOffsetEnabled", ...
    "impairments.timing_offset_enabled","impairments.to.enabled"], abs(configured) > 0);
if ~enabled && isfinite(configured), configured = 0; end
rows = [localTimingTrialRow("DL", dlT, configured); localTimingTrialRow("UL", ulT, configured)];
T = struct2table(rows, "AsArray", true);
end

function row = localTimingTrialRow(direction, T, configured)
observed = istable(T) && height(T) > 0 && localHasColumn(T, "InjectedTimingOffset_samples");
inj = localNumericColumn(T, "InjectedTimingOffset_samples");
est = localNumericColumn(T, "EstimatedTimingOffset_PreCorrection_samples");
res = localNumericColumn(T, "ResidualTimingError_PostCorrection_samples");
n = localHeight(T);
complete = n > 0 && numel(inj) == n && numel(est) == n && numel(res) == n && ...
    all(isfinite(inj)) && all(isfinite(est)) && all(isfinite(res));
mismatch = localMaxAbs(inj - configured);
residual = localMaxAbs(res);
metadataTolerance = 32 * eps(max(abs(double(configured)), 1));
injectionOk = observed && n > 0 && numel(inj) == n && all(isfinite(inj)) && ...
    isfinite(mismatch) && mismatch <= metadataTolerance;
ok = injectionOk && complete && ...
    isfinite(residual) && residual <= 1;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredTimingOffset_samples", double(configured), "MeanInjectedTimingOffset_samples", localMean(inj), ...
    "MeanEstimatedTimingOffset_PreCorrection_samples", localMean(est), ...
    "MeanResidualTimingOffset_samples", localMean(res), ...
    "MaxConfiguredAppliedMismatch_samples", double(mismatch), "MaxResidualTimingError_samples", double(residual), ...
    "TimingInjectionConfiguredAppliedOk", logical(injectionOk), ...
    "TimingReceiverAccuracyQualified", false, ...
    "TimingReceiverAccuracyStatus", 'requires_matched_timing_reference_and_declared_accuracy_policy', ...
    "ReferenceResidualLimit_samples", 1, ...
    "ReferenceResidualLimitSource", 'legacy_reconciliation_policy_not_a_3GPP_accuracy_requirement', ...
    "InjectionMetadataTolerance_samples", metadataTolerance, ...
    "TimingOffsetConfiguredAppliedOk", logical(ok), ...
    "EvaluationScope", 'legacy_reference_alignment_check_not_correlation_peak_accuracy', ...
    "EvidenceSource", char(localEvidenceSource(observed, "trial_rf_timing_columns")));
end

function out = localBuildSynchronizationObservations(dlT, ulT)
% Lossless scalar observation view of actual trial rows. Do not substitute
% an injected/reference error for a missing post-correction measurement, or
% call a same-observation re-estimate independent residual qualification.
out = table();
numericFields = ["SweepPointIndex","SweepIndex","ConfiguredSNR_dB","UEIndex","RNTI", ...
    "Frame","Slot","SampleRate_Hz","InjectedCFO_Hz", ...
    "EstimatedCFO_PreCorrection_Hz","CFOCorrectionApplied_Hz", ...
    "ResidualCFO_PostCorrection_Hz","ResidualCFO_EstimatedPostCorrection_Hz", ...
    "ResidualCFOReusesAcquisitionObservation","ResidualCFOEstimatorConsistency_Hz", ...
    "InjectedTimingOffset_samples","EstimatedTimingOffset_PreCorrection_samples", ...
    "RawTimingEstimate_samples", ...
    "AppliedTimingCorrection_samples","ResidualTimingError_PostCorrection_samples"];
textFields = ["RunID","ObservationID","ResidualCFOEstimateSource","ResidualCFOEstimateDomain", ...
    "ResidualCFOEstimateRole","ResidualCFOReferenceDefinition", ...
    "TimingReferenceSource","TimingMetricRole","TimingErrorDefinition"];
for direction = ["DL","UL"]
    if direction == "DL", source = dlT; else, source = ulT; end
    n = localHeight(source);
    if n == 0, continue; end
    row = table(repmat(direction,n,1),'VariableNames',{'Direction'});
    for name = numericFields
        row.(name) = localNumericColumn(source,name);
    end
    for name = textFields
        value = localStringColumn(source,name);
        if isempty(value), value = strings(n,1); end
        row.(name) = value;
    end
    present = isfinite(row.ResidualCFO_EstimatedPostCorrection_Hz);
    row.ReceiverResidualObservationAvailable = present;
    row.ReceiverResidualObservationStatus = repmat("not_reported_by_receiver",n,1);
    row.ReceiverResidualObservationStatus(present) = "reported_independence_not_established";
    reused = present & row.ResidualCFOReusesAcquisitionObservation == 1;
    row.ReceiverResidualObservationStatus(reused) = "same_observation_consistency_not_independent_accuracy";
    row.ReceiverAccuracyQualified = false(n,1);
    row.EvaluationScope = repmat("actual_trial_observations_not_accuracy_qualification",n,1);
    row.SourceTableRole = repmat(direction + "_trial_input_to_RF_reconciliation",n,1);
    out = [out;row]; %#ok<AGROW>
end
end

function T = localBuildIQTable(dlT, ulT, cfg)
% Match the RX operator's endpoint -> internal -> authored YAML precedence.
% Nested legacy identity values must not hide the active scalar YAML fields.
configuredEnabled = localBool(cfg, ["rf.rx.iqImbalance.enable","rf.rx.iqImbalance.enabled", ...
    "rf.iqImbalance.enable","phy.impairments.iqImbalanceEnabled", ...
    "impairments.iq_imbalance_enabled","impairments.iq_imbalance.enabled","impairments.iq.enabled"], false);
gainCfg = localNumber(cfg, ["rf.rx.iqImbalance.gainImbalance_dB","rf.rx.iqImbalance.ampImb_dB", ...
    "rf.iqImbalance.gainImbalance_dB","rf.iqImbalance.ampImb_dB", ...
    "impairments.iq_amplitude_imbalance_dB","impairments.iq_imbalance.gain_imbalance_db", ...
    "impairments.iq_imbalance.amplitude_imbalance_db"], 0);
phaseCfg = localNumber(cfg, ["rf.rx.iqImbalance.phaseImbalance_deg","rf.rx.iqImbalance.phaseImb_deg", ...
    "rf.iqImbalance.phaseImbalance_deg","rf.iqImbalance.phaseImb_deg", ...
    "impairments.iq_phase_imbalance_deg","impairments.iq_imbalance.phase_imbalance_deg"], 0);
model = localString(cfg, ["rf.rx.iqImbalance.model","rf.iqImbalance.model", ...
    "impairments.iq_imbalance.model","impairments.iq.model"], "none");
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
configuredMatches = numel(cfgCol) == localHeight(T) && all(cfgCol == logical(configuredEnabled));
appliedMatches = ~isempty(appliedCol) && all(appliedCol == logical(configuredEnabled));
gainMatches = numel(gain) == localHeight(T) && localMaxAbs(gain - gainCfg) <= 1e-9;
phaseMatches = numel(phase) == localHeight(T) && localMaxAbs(phase - phaseCfg) <= 1e-9;
ok = observed && configuredMatches && appliedMatches && gainMatches && phaseMatches;
row = struct("Direction", char(direction), "ObservedRows", double(localHeight(T)), ...
    "ConfiguredIQEnabled", logical(configuredEnabled), "AppliedIQEnabled", localAny(appliedCol), ...
    "ConfiguredModel", char(string(model)), "ConfiguredGainImbalance_dB", double(gainCfg), ...
    "ConfiguredPhaseImbalance_deg", double(phaseCfg), "ObservedMeanGainImbalance_dB", localMean(gain), ...
    "ObservedMeanPhaseImbalance_deg", localMean(phase), "IqImbalanceConfiguredAppliedOk", logical(ok), ...
    "EvidenceSource", char(localEvidenceSource(observed, "trial_rf_iq_columns")));
end

function T = localBuildPhaseNoiseTable(dlT, ulT, cfg)
% The legacy flat trial fields belong to RX, not the TX oscillator.
configuredEnabled = localBool(cfg, ["rf.rx.phaseNoise.enable","rf.rx.phaseNoise.enabled", ...
    "rf.phaseNoise.enable","phy.impairments.phaseNoiseEnabled", ...
    "impairments.phase_noise_enabled","impairments.phase_noise.enabled","rf.phase_noise.enabled"], false);
model = localString(cfg, ["rf.phaseNoise.model","impairments.phase_noise_model", ...
    "impairments.phase_noise.model","rf.phase_noise.model"], "");
floorDbc = localNumber(cfg, ["rf.phaseNoise.floor_dBcHz","impairments.phase_noise_floor_dBcHz", ...
    "impairments.phase_noise.psd_floor_dbc_hz","rf.phase_noise.psd_floor_dbc_hz"], NaN);
if ~isempty(localGet(cfg,"rf.phaseNoise.model",[])) || ...
        ~isempty(localGet(cfg,"rf.frontend.phase_noise.profile_id",[]))
    floorDbc=localNumber(cfg,["rf.phaseNoise.floor_dBcHz", ...
        "rf.frontend.phase_noise.floor_dbc_hz"],NaN);
end
[observed, applied, flagsOk, count] = localStageFlags( ...
    dlT, ulT, "PhaseNoiseConfigured", "PhaseNoiseApplied", configuredEnabled);
backend = [localStringColumn(dlT,"PhaseNoiseAvailableBackend"); localStringColumn(ulT,"PhaseNoiseAvailableBackend")];
classification = [localStringColumn(dlT,"PhaseNoiseTruthClassification"); localStringColumn(ulT,"PhaseNoiseTruthClassification")];
backendOk = ~configuredEnabled || (localAllNonblank(backend,count) && localAllNonblank(classification,count));
ok = observed && flagsOk && backendOk;
T = table(logical(configuredEnabled), logical(applied), string(model), floorDbc, ok, ...
    string(localEvidenceSource(observed,"trial_RX_phase_noise_columns")), ...
    'VariableNames', {'ConfiguredPhaseNoiseEnabled','AppliedPhaseNoiseEnabled','ConfiguredModel', ...
    'PSD_floor_dBc_Hz','PhaseNoiseConfiguredAppliedOk','EvidenceSource'});
T.Endpoint = "RX";
T.ObservedRows = count;
T.ObservedBackend = strjoin(unique(backend,"stable"),"|");
T.ObservedTruthClassification = strjoin(unique(classification,"stable"),"|");
T.EvaluationScope = "observed_RX_stage_execution_not_oscillator_mask_qualification";
T.PSDFloorStatus = string(localTernary(isfinite(floorDbc), ...
    "explicit_configured_floor_not_measured_PSD", "not_supplied_by_selected_profile_no_default_floor"));
end

function T = localBuildPATable(dlT, ulT, cfg)
configuredEnabled = localBool(cfg, ["rf.pa.enable","phy.impairments.paNonlinearityEnabled", ...
    "rf_frontend.pa.enabled","impairments.pa_nonlinearity_enabled", ...
    "impairments.pa_nonlinearity.enabled","power_and_rf_frontend.pa_enabled"], false);
model = localString(cfg, ["rf.pa.method","rf_frontend.pa.model", ...
    "impairments.pa_nonlinearity.model","power_and_rf_frontend.pa_model"], "");
backoff = localNumber(cfg, ["rf.pa.backoff_dB","rf_frontend.pa.input_backoff_db", ...
    "impairments.pa_output_backoff_dB","lls6g.impairments.pa_output_backoff_dB"], NaN);
% These are optional authored parameters, never measured PA intercepts.
% In particular a Rapp PA does not supply IIP3/P1dB from its backoff.
iip3 = localNumber(cfg, ["impairments.pa_nonlinearity.iip3_dbm","power_and_rf_frontend.pa_iip3_dbm"], NaN);
p1db = localNumber(cfg, ["impairments.pa_nonlinearity.p1db_dbm","power_and_rf_frontend.pa_p1db_dbm"], NaN);
if configuredEnabled && any(lower(string(model)) == ["rapp","memoryless"])
    iip3=NaN; p1db=NaN;
end
[observed, applied, flagsOk, count] = localStageFlags(dlT,ulT,"PAEnabled","PAApplied",configuredEnabled);
models = [localStringColumn(dlT,"PAModel"); localStringColumn(ulT,"PAModel")];
backoffs = [localNumericColumn(dlT,"PABackoff_dB"); localNumericColumn(ulT,"PABackoff_dB")];
parametersOk = ~configuredEnabled || (localAllNonblank(models,count) && ...
    all(strcmpi(models,string(model))) && numel(backoffs)==count && ...
    all(isfinite(backoffs)) && isfinite(backoff) && localMaxAbs(backoffs-backoff)<=1e-9);
ok = observed && flagsOk && parametersOk;
T = table(logical(configuredEnabled), logical(applied), string(model), iip3, p1db, ok, ...
    string(localEvidenceSource(observed,"trial_TX_pa_columns")), ...
    'VariableNames', {'ConfiguredPAEnabled','AppliedPAEnabled','ConfiguredModel','IIP3_dBm','P1dB_dBm', ...
    'PaConfiguredAppliedOk','EvidenceSource'});
T.Endpoint = "TX";
T.ObservedRows = count;
T.ConfiguredBackoff_dB = backoff;
T.ObservedMeanBackoff_dB = localMean(backoffs);
T.InterceptParameterStatus = "configured_if_model_applicable_not_measured_intercept_or_compression";
T.EvaluationScope = "observed_TX_PA_execution_not_PA_conformance_qualification";
end

function [observed,applied,ok,count] = localStageFlags(dlT,ulT,configuredField,appliedField,expected)
% A present header or one successful row cannot qualify missing/NaN rows.
configured=[localNumericColumn(dlT,configuredField);localNumericColumn(ulT,configuredField)];
executed=[localNumericColumn(dlT,appliedField);localNumericColumn(ulT,appliedField)];
count=localHeight(dlT)+localHeight(ulT);
observed=count>0 && numel(configured)==count && numel(executed)==count && ...
    all(isfinite(configured) & ismember(configured,[0 1])) && ...
    all(isfinite(executed) & ismember(executed,[0 1]));
applied=any(executed==1);
ok=observed && all(configured==double(expected)) && all(executed==double(expected));
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
spatial = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, struct('DL',dlT,'UL',ulT));

dl = localMIMODirectionContract(dlT, "DL", cfgDLLayers, cfgBSTx, cfgUERx, maximumMCS, cfg, dlCfg, spatial.RankLayerTrials);
ul = localMIMODirectionContract(ulT, "UL", cfgULLayers, cfgUETx, cfgBSRx, maximumMCS, cfg, ulCfg, spatial.RankLayerTrials);
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

function out = localMIMODirectionContract(T, direction, configuredLayers, configuredTx, configuredRx, maximumMCS, cfg, cfgRow, rankTrials)
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
elseif sixgr.analytics.identityAWGNRuntimeEvidence(T,cfg,configuredTx,configuredRx)
    % An executed square identity operator has spatial dimensions but no
    % propagation-array or element-pattern claim. Never label it as one.
    out.RuntimeArrayModelOk = true;
    out.RuntimeArrayEvaluationStatus = "explicit_awgn_identity_spatial_operator";
    if ~isempty(sixgr.util.structGet(cfg,'channel.awgnSpatialMatrixDL',[]))
        out.RuntimeArrayEvaluationStatus="explicit_awgn_fixed_matrix_spatial_operator";
    end
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
bootstrapMCS = localNumber(cfg, ["phy.linkAdaptation.bootstrapMCSIndex", ...
    "link_adaptation.bootstrap_mcs_index","phy.linkAdaptation.initialMCSIndex", ...
    "link_adaptation.initial_mcs"], NaN);
out.AdaptivePolicyOk = localAdaptiveOperatingPointPolicyOk(T, mcs, mods, maximumMCS, out.AdaptiveMode, bootstrapMCS);

groupSize = localNumericColumn(T, "MUMIMOGroupSize");
muEnabled = localLogicalColumn(T, "MUMIMOEnabled");
if isempty(muEnabled)
    muEnabled = false(height(T), 1);
end
out.MUPairedRows = double(nnz(isfinite(groupSize) & groupSize >= 2 & muEnabled));
spatialAndProfileOk = rankExact && out.RuntimeArrayModelOk && out.MCSRangeOk && out.MCSProfileExactOk;
out.ExactOk = spatialAndProfileOk && out.ConfiguredMCSExactOk && out.ConfiguredModulationExactOk;
rankPolicyOk = rankExact;
if out.AdaptiveMode
    % Reuse the canonical scheduled/transmitted/capability contract. A
    % bootstrap mismatch is expected under AMC; a grant mismatch is not.
    selected = rankTrials(upper(string(rankTrials.Direction))==direction,:);
    rankPolicyOk = height(selected)==height(T) && ...
        all(logical(selected.SpatialContractMatch));
end
operatingPointPolicyOk = (~out.AdaptiveMode && out.ConfiguredMCSExactOk && ...
    out.ConfiguredModulationExactOk) || (out.AdaptiveMode && out.AdaptivePolicyOk);
out.ExecutionPolicyOk = rankPolicyOk && out.RuntimeArrayModelOk && ...
    out.MCSRangeOk && out.MCSProfileExactOk && operatingPointPolicyOk;
end

function tf = localAdaptiveOperatingPointPolicyOk(T, transmittedMCS, transmittedModulation, maximumMCS, adaptiveMode, bootstrapMCS)
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
% A current TB's post-decode CQI cannot prove which feedback selected it.
% Use only the decision retained on its frozen grant, including causal age.
decisionCQI = localNumericColumn(T, "AppliedLinkAdaptationResolvedCQI");
decisionMCS = localNumericColumn(T, "AppliedLinkAdaptationCQIBasedMCS");
sourceSlot = localNumericColumn(T, "LinkAdaptationAppliedFeedbackSourceSlot");
ageSlots = localNumericColumn(T, "LinkAdaptationAppliedFeedbackAgeSlots");
delaySlots = localNumericColumn(T, "LinkAdaptationFeedbackDelaySlots");
causalFeedback = isfinite(sourceSlot) & sourceSlot >= 0 & sourceSlot==fix(sourceSlot) & ...
    isfinite(ageSlots) & ageSlots>=0 & ageSlots==fix(ageSlots) & ...
    isfinite(delaySlots) & delaySlots>=0 & delaySlots==fix(delaySlots) & delaySlots<=ageSlots;
feedbackDecision = strlength(valueStatus) > 0 & ...
    ~contains(valueStatus, "bootstrap") & ...
    ~contains(valueStatus, "pending_data_feedback") & ...
    ~contains(valueStatus, "missing") & ...
    ~contains(valueStatus, "unavailable") & ...
    ~contains(valueStatus, "rejected") & ...
    ~contains(valueStatus, "error") & ...
    appliedFlag & isfinite(decisionCQI) & decisionCQI>=1 & decisionCQI<=15 & ...
    decisionCQI==fix(decisionCQI) & isfinite(decisionMCS) & ...
    decisionMCS>=0 & decisionMCS==fix(decisionMCS) & causalFeedback;
% Legitimate pre-feedback bootstrap is a configured operating point, not an
% applied adaptation decision. It may precede feedback-backed grants but
% cannot, alone, qualify an adaptive run. Keep the frozen-grant match below.
bootstrapFlag = localNumericColumn(T, "LinkAdaptationBootstrap")==1;
bootstrapDecision = bootstrapFlag & ~appliedFlag & ...
    valueStatus=="bootstrap_not_measured_cqi" & ...
    lower(lineage)=="bootstrap_cqi_conservative_lab_default" & ...
    isfinite(bootstrapMCS) & scheduled==bootstrapMCS & ...
    ~isfinite(sourceSlot) & ~isfinite(decisionCQI);
feedbackDecision = feedbackDecision & ~bootstrapFlag;
forbidden = ["proxy","fallback","configured_fixed","legacy","missing","unavailable","error","rejected"];
forbiddenLineage = false(height(T), 1);
for token = forbidden
    forbiddenLineage = forbiddenLineage | contains(lower(lineage), token);
end
tf = numel(scheduled) == height(T) && numel(transmittedMCS) == height(T) && ...
    numel(scheduledModulation) == height(T) && numel(transmittedModulation) == height(T) && ...
    all(scheduledFlag) && all(bootstrapDecision | feedbackDecision) && ...
    all(isfinite(scheduled) & isfinite(transmittedMCS) & scheduled == transmittedMCS) && ...
    all(scheduled >= 0 & scheduled <= maximumMCS) && ...
    all(strlength(scheduledModulation) > 0 & scheduledModulation == transmittedModulation) && ...
    all(strlength(lineage) > 0 & ~forbiddenLineage) && ...
    all(strlength(evidenceId) > 0) && any(feedbackDecision);
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
    T = sixgr.util.csvReadTable(char(path), "TextType", "string");
catch
    % Optional legacy side artifacts remain optional. Canonical receiver
    % populations use resolveRetainedDirectionalTrials and fail explicitly.
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
    values == "not_emitted_by_active_ul_pusch_trials_runtime" | ...
    values == "not_emitted_by_active_dl_fixed_link_campaign_trials_runtime" | ...
    values == "not_emitted_by_active_ul_fixed_link_campaign_trials_runtime";
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

function [value, source] = localNumber(cfg, paths, defaultValue)
value = defaultValue;
source = "unavailable";
for path = string(paths)
    raw = localGet(cfg, path, []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            source = path;
            return;
        end
    else
        x = str2double(string(raw));
        if isfinite(x)
            value = x;
            source = path;
            return;
        end
    end
end
end

function [value, source] = localString(cfg, paths, defaultValue)
value = string(defaultValue);
source = "unavailable";
for path = string(paths)
    raw = localGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    text = string(raw);
    if ~isempty(text) && strlength(strtrim(text(1))) > 0
        value = text(1);
        source = path;
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
