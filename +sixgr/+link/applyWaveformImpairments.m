function [y, replay] = applyWaveformImpairments(x, cfg, sampleRateHz, varargin)
%APPLYWAVEFORMIMPAIRMENTS Apply large-scale loss and sample-domain impairments.
% Keep this file ASCII-only.
%
% Large-scale attenuation and RF gains are expressed in power-domain dB. We
% convert them to a complex-sample amplitude scale with:
%   AppliedLargeScaleGain_dB =
%       -AppliedLargeScaleLoss_dB + G_tx + G_rx - implementationLoss
%   amplitudeGain = 10^(AppliedLargeScaleGain_dB/20)
%
% The downstream AWGN helper injects thermal noise derived from bandwidth and
% receiver noise figure. Configured SNR is retained only as operating-point
% metadata and must not be converted into measured SINR or AWGN. Standalone
% link-reference tests may explicitly request "standalone_awgn_snr_argument",
% which is exported as an AWGN baseline mode rather than receiver truth.
%
% In the thermal-noise mode we keep an explicit absolute-power bridge between
% the waveform amplitude convention and the large-scale link budget through
% sixgr.rf.PowerContext.

if nargin < 3 || ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    sampleRateHz = 0;
else
    sampleRateHz = double(sampleRateHz);
end
p = inputParser;
p.addParameter("Endpoint", "rx");
p.addParameter("UseLegacyGlobalConfig", true, @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
p.addParameter("ApplyPA", false, @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
p.addParameter("ApplyADC", true, @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
p.parse(varargin{:});
opt = p.Results;
profScope = sixgr.perf.TimeProfiler.scope("sixgr.link.applyWaveformImpairments", ...
    "Stage", "rf_impairments", ...
    "Metadata", struct("NSamples", double(numel(x)))); %#ok<NASGU>

replay = localResolveReplayContext(cfg, sampleRateHz);
y = x;

ampGain = double(replay.AppliedLargeScaleAmplitudeGain);
if isfinite(ampGain) && ampGain > 0 && abs(ampGain - 1) > 1e-12
    y = y .* cast(ampGain, "like", y);
end

[y, replay] = localApplyOrderedRFChain(y, cfg, sampleRateHz, replay, opt);
end

function [y, replay] = localApplyOrderedRFChain(x, cfg, sampleRateHz, replay, opt)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    replay.RFImpairmentChainContract = "sixgr.rf.ImpairmentChainConfig/v1";
    replay.RFEndpoint = string(opt.Endpoint);
    replay.RFStageOrder = "";
    replay.RFConfiguredStageCount = 0;
    replay.RFAppliedStageCount = 0;
    replay.RFExecutionStatus = "not_applied_sample_rate_unavailable";
    return;
end
rfOut = sixgr.rf.applyRFImpairmentChain(x, cfg, ...
    "SampleRateHz", sampleRateHz, ...
    "Direction", sixgr.util.structGet(replay, "PowerContextDirection", "DL"), ...
    "MeasurementPoint", string(opt.Endpoint) + "_front_end", ...
    "Endpoint", opt.Endpoint, ...
    "StrictMutationRequired", false, ...
    "UseLegacyGlobalConfig", logical(opt.UseLegacyGlobalConfig), ...
    "ApplyPA", logical(opt.ApplyPA), ...
    "ApplyADC", logical(opt.ApplyADC));
y = cast(rfOut.Waveform, "like", x);
replay = localMergeRFReplay(replay, rfOut.Replay, rfOut.Row);
replay.RFExecutionStatus = "applied_ordered_sample_domain_chain";
end

function replay = localMergeRFReplay(replay, rfReplay, rfRow)
rfFields = fieldnames(rfReplay);
for i = 1:numel(rfFields)
    replay.(rfFields{i}) = rfReplay.(rfFields{i});
end
replay.RFImpairmentChainId = char(string(rfRow.RFImpairmentChainId));
replay.RFStrictOk = logical(rfRow.StrictOk);
replay.RFFailureReason = char(string(rfRow.FailureReason));
replay.EVMMeasuredDb = double(rfRow.EVMMeasuredDb);
replay.EVMMeasuredPercent = double(rfRow.EVMMeasuredPercent);
if isfield(rfReplay, "InjectedCFO_Hz")
    replay.InjectedCFO_Hz = double(rfReplay.InjectedCFO_Hz);
end
if isfield(rfReplay, "InjectedTimingOffset_samples")
    replay.InjectedTimingOffset_samples = double(rfReplay.InjectedTimingOffset_samples);
end
if isfield(rfReplay, "TimingOffsetApplied")
    replay.TimingOffsetExecutionStatus = localConditionalString(logical(rfReplay.TimingOffsetApplied), ...
        "applied_fractional_sample_delay", "disabled_or_zero_identity");
end
if isfield(rfReplay, "CFOApplied")
    replay.CFOExecutionStatus = localConditionalString(logical(rfReplay.CFOApplied), ...
        "applied_cfo_rotation", "disabled_or_zero_identity");
end
if isfield(rfReplay, "PhaseNoiseApplied")
    replay.PhaseNoiseApplied = logical(rfReplay.PhaseNoiseApplied);
end
if isfield(rfReplay, "IQImbalanceApplied")
    replay.IQImbalanceApplied = logical(rfReplay.IQImbalanceApplied);
end
if isfield(rfReplay, "RFStageOrder") && contains(string(rfReplay.RFStageOrder), "carrier_phase")
    replay.CarrierPhaseOffsetApplied = true;
    replay.CarrierPhaseOffsetExecutionStatus = "applied_sample_domain_constant_rotation";
elseif isfield(replay, "CarrierPhaseOffsetExecutionStatus") && string(replay.CarrierPhaseOffsetExecutionStatus) ~= "disabled"
    replay.CarrierPhaseOffsetApplied = false;
    replay.CarrierPhaseOffsetExecutionStatus = "disabled_or_zero_identity";
end
end

function replay = localResolveReplayContext(cfg, sampleRateHz)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
direction = localResolveDirection(userMeta);
powerContext = sixgr.util.structGet(cfg, "lls6g.runtimePowerContext", struct());
if ~(isstruct(powerContext) && isfield(powerContext, "ContractVersion"))
    powerContext = sixgr.rf.PowerContext(cfg, direction);
end

basePathloss_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingBasePathloss_dB", NaN));
pathloss_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingPathloss_dB", NaN));
shadow_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingShadowFading_dB", NaN));
o2i_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingO2I_dB", NaN));
channelComplianceMode = string(sixgr.util.structGet(userMeta, "RuntimeChannelComplianceMode", ""));
pathlossModelSource = string(sixgr.util.structGet(userMeta, "RuntimePathlossModelSource", ""));
pathlossComplianceStatus = string(sixgr.util.structGet(userMeta, "RuntimePathlossComplianceStatus", ""));
fallbackUsedForPathloss = logical(sixgr.util.structGet(userMeta, "RuntimeFallbackUsedForPathloss", false));
o2iModelSource = string(sixgr.util.structGet(userMeta, "RuntimeO2IModelSource", ""));
o2iComplianceStatus = string(sixgr.util.structGet(userMeta, "RuntimeO2IComplianceStatus", ""));
o2iComplianceReason = string(sixgr.util.structGet(userMeta, "RuntimeO2IComplianceReason", ""));
losProbabilitySource = string(sixgr.util.structGet(userMeta, "RuntimeLOSProbabilitySource", ""));
losComplianceStatus = string(sixgr.util.structGet(userMeta, "RuntimeLOSComplianceStatus", ""));
losComplianceReason = string(sixgr.util.structGet(userMeta, "RuntimeLOSComplianceReason", ""));
if ~isfinite(pathloss_dB) && logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false))
    explicitPathloss_dB = localFiniteOrNaN(sixgr.util.structGet(cfg, "channel.pathloss_dB", NaN));
    if isfinite(explicitPathloss_dB)
        pathloss_dB = explicitPathloss_dB;
        pathlossModelSource = "cfg.channel.pathloss_dB";
        pathlossComplianceStatus = "explicit_config_pathloss";
        channelComplianceMode = localFirstNonEmptyString(channelComplianceMode, "standalone_explicit_pathloss");
    end
end

[loss_dB, gainSource] = localResolveLargeScaleLoss(pathloss_dB, basePathloss_dB, shadow_dB, o2i_dB);
gain_dB = -loss_dB + double(powerContext.TxGain_dB) + double(powerContext.RxGain_dB) - double(powerContext.AdditionalLoss_dB);
ampGain = 10.^(gain_dB / 20);

configuredSNR_dB = localFiniteOrNaN(sixgr.util.structGet(cfg, "channel.snr_dB", NaN));
noiseMode = localResolveNoiseOperatingMode(cfg);
[servingRxPower_dBm, servingRxPowerSource, referenceTxPower_dBm, referenceTxPowerSource] = ...
    localResolveServingRxPower(cfg, userMeta, loss_dB, pathloss_dB, basePathloss_dB, powerContext);
noiseFigure_dB = localResolveNoiseFigure(cfg, powerContext, direction);
noiseBandwidth_Hz = localResolveNoiseBandwidth(cfg, sampleRateHz);
[appliedAWGNSNR_dB, targetNoiseVariance, thermalNoisePower_dBm, noiseSource] = ...
    localResolveAppliedNoise(noiseMode, configuredSNR_dB, loss_dB, servingRxPower_dBm, ...
    servingRxPowerSource, noiseBandwidth_Hz, noiseFigure_dB, ampGain);
[phaseNoiseConfigured, phaseNoiseBackend, phaseNoiseTruthClassification, phaseNoiseApproximationReason, phaseNoiseExecutionStatus] = ...
    localResolvePhaseNoiseTruthBoundary(cfg, sampleRateHz);
[carrierPhaseOffset_deg, carrierPhaseOffsetSource] = localResolveInjectedCarrierPhaseOffsetDeg(cfg);
[carrierPhaseOffsetApplied, carrierPhaseOffsetStatus] = localInitialCarrierPhaseOffsetStatus( ...
    carrierPhaseOffset_deg, carrierPhaseOffsetSource);
[iqEnabled, iqModel, iqGainImbalance_dB, iqPhaseImbalance_deg, iqConfigSource, iqExecutionStatus] = ...
    localResolveIQImbalanceRuntime(cfg);

interferenceMode = localResolveInterferenceMode(cfg);
if any(interferenceMode == ["abstract_large_scale_scheduler_context","explicit_activity_power_sum","waveform_overlap_large_scale"])
    error("sixgr:link:NonWaveformInterferenceModeRemoved", ...
        "interference mode '%s' is not allowed in no-proxy waveform LLS. Use full_per_link_channel_waveform_sum or none.", char(interferenceMode));
end

servingRSRP_dBm = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingRSRP_dBm", NaN));
largeScaleSINR_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingLargeScaleSINR_dB", NaN));
if interferenceMode == "full_per_link_channel_waveform_sum"
    largeScaleSINRSource = "full_per_link_waveform_interference_runtime_state";
else
    largeScaleSINRSource = "not_available_without_intercell_waveform_interference";
end

replay = struct( ...
    "InjectedCFO_Hz", localResolveInjectedCFOHz(cfg), ...
    "InjectedTimingOffset_samples", localResolveInjectedTimingOffsetSamples(cfg), ...
    "InjectedCarrierPhaseOffset_deg", carrierPhaseOffset_deg, ...
    "InjectedCarrierPhaseOffset_rad", carrierPhaseOffset_deg * pi / 180, ...
    "CarrierPhaseOffsetApplied", logical(carrierPhaseOffsetApplied), ...
    "CarrierPhaseOffsetSource", char(carrierPhaseOffsetSource), ...
    "CarrierPhaseOffsetExecutionStatus", char(carrierPhaseOffsetStatus), ...
    "SampleRate_Hz", double(sampleRateHz), ...
    "PowerContext", powerContext, ...
    "PowerContextDirection", char(direction), ...
    "PowerContextTxEntity", char(string(powerContext.TxEntity)), ...
    "PowerContextRxEntity", char(string(powerContext.RxEntity)), ...
    "PowerContextAmplitudeUnit", char(string(powerContext.WaveformAmplitudeUnit)), ...
    "PowerContextTotalTxPower_dBm", double(powerContext.TotalTxPower_dBm), ...
    "PowerContextTxGain_dB", double(powerContext.TxGain_dB), ...
    "PowerContextRxGain_dB", double(powerContext.RxGain_dB), ...
    "PowerContextAdditionalLoss_dB", double(powerContext.AdditionalLoss_dB), ...
    "PowerContextRFChainCount", double(powerContext.RFChainCount), ...
    "PowerContextPAEfficiency", double(powerContext.PAEfficiency), ...
    "PowerContextPAEnabled", logical(sixgr.util.structGet(powerContext, "PAEnabled", false)), ...
    "PowerContextPAApplied", logical(sixgr.util.structGet(powerContext, "PAApplied", false)), ...
    "PowerContextPAModel", char(string(sixgr.util.structGet(powerContext, "PAModel", "disabled"))), ...
    "PowerContextPAExecutionStatus", char(string(sixgr.util.structGet(powerContext, "PAExecutionStatus", "disabled"))), ...
    "PowerContextPACompression_dB", double(sixgr.util.structGet(powerContext, "PACompression_dB", NaN)), ...
    "ConfiguredSNR_dB", configuredSNR_dB, ...
    "NoiseOperatingMode", char(noiseMode), ...
    "AppliedAWGNSNR_dB", appliedAWGNSNR_dB, ...
    "TargetNoiseVariance", targetNoiseVariance, ...
    "NoiseFigure_dB", noiseFigure_dB, ...
    "NoiseBandwidth_Hz", noiseBandwidth_Hz, ...
    "ThermalNoisePower_dBm", thermalNoisePower_dBm, ...
    "NoisePowerSource", char(noiseSource), ...
    "AppliedLargeScaleLoss_dB", loss_dB, ...
    "AppliedLargeScaleGain_dB", gain_dB, ...
    "AppliedLargeScaleAmplitudeGain", ampGain, ...
    "AppliedBasePathloss_dB", basePathloss_dB, ...
    "AppliedPathloss_dB", pathloss_dB, ...
    "AppliedShadowFading_dB", shadow_dB, ...
    "AppliedO2I_dB", o2i_dB, ...
    "AppliedLargeScaleGainSource", char(gainSource), ...
    "ChannelComplianceMode", char(channelComplianceMode), ...
    "PathlossModelSource", char(pathlossModelSource), ...
    "PathlossComplianceStatus", char(pathlossComplianceStatus), ...
    "FallbackUsedForPathloss", logical(fallbackUsedForPathloss), ...
    "O2IModelSource", char(o2iModelSource), ...
    "O2IComplianceStatus", char(o2iComplianceStatus), ...
    "O2IComplianceReason", char(o2iComplianceReason), ...
    "LOSProbabilitySource", char(losProbabilitySource), ...
    "LOSComplianceStatus", char(losComplianceStatus), ...
    "LOSComplianceReason", char(losComplianceReason), ...
    "ServingRxPower_dBm", servingRxPower_dBm, ...
    "ServingRxPowerSource", char(servingRxPowerSource), ...
    "ReferenceTxPower_dBm", referenceTxPower_dBm, ...
    "ReferenceTxPowerSource", char(referenceTxPowerSource), ...
    "ServingRSRP_dBm", servingRSRP_dBm, ...
    "ServingRSRPSource", "large_scale_per_reference_re_power", ...
    "LargeScaleSINR_dB", largeScaleSINR_dB, ...
    "LargeScaleSINRSource", largeScaleSINRSource, ...
    "InterferenceMode", char(interferenceMode), ...
    "PhaseNoiseConfigured", logical(phaseNoiseConfigured), ...
    "PhaseNoiseAvailableBackend", char(phaseNoiseBackend), ...
    "PhaseNoiseTruthClassification", char(phaseNoiseTruthClassification), ...
    "PhaseNoiseApproximationReason", char(phaseNoiseApproximationReason), ...
    "PhaseNoiseExecutionStatus", char(phaseNoiseExecutionStatus), ...
    "PhaseNoiseApplied", false, ...
    "PhaseNoiseRMS_rad", NaN, ...
    "PhaseNoiseSeed", NaN, ...
    "IQImbalanceConfigured", logical(iqEnabled), ...
    "IQImbalanceApplied", false, ...
    "IQImbalanceModel", char(iqModel), ...
    "ConfiguredIQGainImbalance_dB", iqGainImbalance_dB, ...
    "ConfiguredIQPhaseImbalance_deg", iqPhaseImbalance_deg, ...
    "ConfiguredIQImbalanceSource", char(iqConfigSource), ...
    "IQImbalanceMirrorPowerRatio_dB", NaN, ...
    "IQImbalanceImageRejection_dB", NaN, ...
    "IQImbalanceIQPowerRatio_dB", NaN, ...
    "IQImbalanceIQCorrelation", NaN, ...
    "IQImbalanceEstimatedAlphaAbs", NaN, ...
    "IQImbalanceEstimatedBetaAbs", NaN, ...
    "IQImbalanceMeasurementSource", "sample_domain_widely_linear_fit_after_iq_stage", ...
    "IQImbalanceMeasurementStatus", char(iqExecutionStatus));
end

function mode = localResolveNoiseOperatingMode(cfg)
mode = string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ...
    "receiver_noise_figure_thermal_noise"));
mode = strtrim(lower(mode));
if strlength(mode) == 0
    mode = "receiver_noise_figure_thermal_noise";
end
end

function tf = localHasExplicitNoiseOperatingMode(cfg)
tf = false;
if ~isstruct(cfg) || ~isfield(cfg, "run") || ~isstruct(cfg.run) || ~isfield(cfg.run, "noiseOperatingMode")
    return;
end
mode = string(cfg.run.noiseOperatingMode);
tf = strlength(strtrim(mode)) > 0;
end

function direction = localResolveDirection(userMeta)
direction = upper(strtrim(string(sixgr.util.structGet(userMeta, "RuntimeCurrentDirection", ""))));
if strlength(direction) == 0
    direction = upper(strtrim(string(sixgr.util.structGet(userMeta, "Direction", ""))));
end
if direction ~= "UL"
    direction = "DL";
end
end

function [servingRxPower_dBm, source, referenceTxPower_dBm, referenceTxPowerSource] = ...
        localResolveServingRxPower(cfg, userMeta, loss_dB, pathloss_dB, basePathloss_dB, powerContext)
servingRxPower_dBm = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingRxPower_dBm", NaN));
source = "runtime_serving_rx_power";
referenceTxPower_dBm = NaN;
referenceTxPowerSource = "";
if isstruct(powerContext) && isfield(powerContext, "TotalTxPower_dBm")
    referenceTxPower_dBm = double(powerContext.TotalTxPower_dBm);
    referenceTxPowerSource = "sixgr.rf.PowerContext.TotalTxPower_dBm";
end
if isfinite(servingRxPower_dBm)
    return;
end
if ~(isfinite(loss_dB) && loss_dB >= 0)
    source = "unavailable";
    return;
end
if ~(isfinite(pathloss_dB) || isfinite(basePathloss_dB))
    source = "unavailable_missing_pathloss_or_runtime_rx_power";
    return;
end
if ~(isfinite(referenceTxPower_dBm))
    [referenceTxPower_dBm, referenceTxPowerSource] = localResolveReferenceTxPower(cfg, userMeta);
end
if ~(isfinite(referenceTxPower_dBm))
    source = "unavailable";
    return;
end
txGain_dB = double(sixgr.util.structGet(powerContext, "TxGain_dB", 0));
rxGain_dB = double(sixgr.util.structGet(powerContext, "RxGain_dB", 0));
additionalLoss_dB = double(sixgr.util.structGet(powerContext, "AdditionalLoss_dB", 0));
servingRxPower_dBm = referenceTxPower_dBm + txGain_dB + rxGain_dB - loss_dB - additionalLoss_dB;
source = "power_context_link_budget";
end

function [txPower_dBm, source] = localResolveReferenceTxPower(cfg, userMeta)
txPower_dBm = NaN;
source = "";
direction = upper(strtrim(string(sixgr.util.structGet(userMeta, "RuntimeCurrentDirection", ""))));
if strlength(direction) == 0
    direction = upper(strtrim(string(sixgr.util.structGet(userMeta, "Direction", ""))));
end
resolved = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", struct());
switch direction
    case "UL"
        txPower_dBm = localFiniteOrNaN(sixgr.util.structGet(resolved, "power_and_rf_frontend.ue_tx_power_dbm", NaN));
        source = "resolved_config.power_and_rf_frontend.ue_tx_power_dbm";
        if isfinite(txPower_dBm)
            return;
        end
    otherwise
        txPower_dBm = localFiniteOrNaN(sixgr.util.structGet(resolved, "power_and_rf_frontend.bs_tx_power_dbm", NaN));
        source = "resolved_config.power_and_rf_frontend.bs_tx_power_dbm";
        if isfinite(txPower_dBm)
            return;
        end
end

% Keep the last-resort direction-specific config bridge explicit.
switch direction
    case "UL"
        txPower_dBm = localFiniteOrNaN(sixgr.util.structGet(cfg, "powerAndRF.ueTxPower_dBm", NaN));
        source = "cfg.powerAndRF.ueTxPower_dBm";
        if isfinite(txPower_dBm)
            return;
        end
    otherwise
        txPower_dBm = localFiniteOrNaN(sixgr.util.structGet(cfg, "scenario.bs.txPower_dBm", NaN));
        source = "cfg.scenario.bs.txPower_dBm";
        if isfinite(txPower_dBm)
            return;
        end
end
source = "unavailable";
end

function appliedAWGNSNR_dB = localResolveAppliedAWGNSNR(noiseMode, configuredSNR_dB, ~)
if ~isfinite(configuredSNR_dB)
    appliedAWGNSNR_dB = NaN;
    return;
end
switch strtrim(lower(string(noiseMode)))
    case "standalone_awgn_snr_argument"
        appliedAWGNSNR_dB = configuredSNR_dB;
    otherwise
        % Configured SNR is metadata only in strict LLS.
        appliedAWGNSNR_dB = NaN;
end
end

function [appliedAWGNSNR_dB, targetNoiseVariance, thermalNoisePower_dBm, source] = ...
        localResolveAppliedNoise(noiseMode, configuredSNR_dB, loss_dB, servingRxPower_dBm, servingRxPowerSource, noiseBandwidth_Hz, noiseFigure_dB, ampGain)
targetNoiseVariance = NaN;
thermalNoisePower_dBm = NaN;
source = "unavailable";
appliedAWGNSNR_dB = localResolveAppliedAWGNSNR(noiseMode, configuredSNR_dB, loss_dB);

switch strtrim(lower(string(noiseMode)))
    case "receiver_noise_figure_thermal_noise"
        thermalNoisePower_dBm = localResolveThermalNoisePower(noiseBandwidth_Hz, noiseFigure_dB);
        source = "thermal_noise_plus_receiver_nf";
        if isfinite(servingRxPower_dBm) && isfinite(thermalNoisePower_dBm)
            appliedAWGNSNR_dB = servingRxPower_dBm - thermalNoisePower_dBm;
        else
            appliedAWGNSNR_dB = NaN;
            if strcmpi(char(string(servingRxPowerSource)), "unavailable_missing_pathloss_or_runtime_rx_power")
                source = "thermal_noise_unavailable_missing_pathloss_or_runtime_rx_power";
            end
        end
        % Bridge the absolute thermal-noise power into the normalized
        % waveform domain inside the DL/UL kernels, where the desired
        % reference waveform power is still available after fading,
        % large-scale scaling, and interference synthesis.
        targetNoiseVariance = NaN;
    case "standalone_awgn_snr_argument"
        source = "standalone_awgn_snr_argument";
    otherwise
        source = "unsupported_noise_operating_mode_no_configured_snr_awgn";
end
end

function mode = localResolveInterferenceMode(cfg)
mode = string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""));
mode = strtrim(lower(mode));
if strlength(mode) == 0 && logical(sixgr.util.structGet(cfg, "run.useAbstractInterferenceModel", false))
    error("sixgr:link:AbstractInterferenceModeRemoved", ...
        "run.useAbstractInterferenceModel=true is not allowed in no-proxy waveform LLS.");
end
if strlength(mode) == 0
    mode = "none";
end
end

function noiseFigure_dB = localResolveNoiseFigure(cfg, powerContext, direction)
noiseFigure_dB = localFiniteOrNaN(sixgr.util.structGet(powerContext, "NoiseFigure_dB", NaN));
if isfinite(noiseFigure_dB)
    return;
end
if upper(string(direction)) == "UL"
    noiseFigure_dB = localFiniteOrNaN(sixgr.util.structGet(cfg, "scenario.bs.noiseFigure_dB", ...
        sixgr.util.structGet(cfg, "powerAndRF.bsNoiseFigure_dB", ...
        sixgr.util.structGet(cfg, "channel.receiverNoiseFigure_dB", 5))));
else
    noiseFigure_dB = localFiniteOrNaN(sixgr.util.structGet(cfg, "scenario.ue.noiseFigure_dB", ...
        sixgr.util.structGet(cfg, "powerAndRF.ueNoiseFigure_dB", ...
        sixgr.util.structGet(cfg, "channel.receiverNoiseFigure_dB", 9))));
end
if ~isfinite(noiseFigure_dB)
    if upper(string(direction)) == "UL"
        noiseFigure_dB = 5;
    else
        noiseFigure_dB = 9;
    end
end
end

function bandwidth_Hz = localResolveNoiseBandwidth(cfg, sampleRateHz)
bandwidth_Hz = localFiniteOrNaN(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", NaN));
if ~(isfinite(bandwidth_Hz) && bandwidth_Hz > 0)
    bandwidth_Hz = localFiniteOrNaN(sampleRateHz);
end
if ~(isfinite(bandwidth_Hz) && bandwidth_Hz > 0)
    bandwidth_Hz = 20e6;
end
end

function [configured, backend, truthClassification, approximationReason, executionStatus] = ...
        localResolvePhaseNoiseTruthBoundary(cfg, sampleRateHz)
configured = logical(sixgr.util.structGet(cfg, "rf.phaseNoise.enable", false));
configured = configured || logical(sixgr.util.structGet(cfg, "phy.impairments.phaseNoiseEnabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "impairments.phase_noise_enabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "lls6g.resolvedConfig.impairments.phase_noise_enabled", false));
backend = "disabled";
truthClassification = "disabled";
approximationReason = "";
executionStatus = "not_configured";
if ~configured
    return;
end

seed = double(sixgr.util.structGet(cfg, "run.seed", 1));
pn = sixgr.rf.PhaseNoiseModel(cfg, sampleRateHz, seed);
backend = string(pn.Backend);
truthClassification = string(pn.TruthClassification);
approximationReason = string(pn.ApproximationReason);
executionStatus = "configured_pending_sample_domain_phase_noise";
end

function [y, replay] = localApplyPhaseNoiseStage(x, replay, cfg, sampleRateHz)
y = x;
if isempty(x)
    replay.PhaseNoiseExecutionStatus = "empty_waveform";
    return;
end
if ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    replay.PhaseNoiseExecutionStatus = "configured_but_sample_rate_unavailable";
    return;
end
seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) + 3001;
pn = sixgr.rf.PhaseNoiseModel(cfg, double(sampleRateHz), seed);
if ~logical(pn.Enable)
    replay.PhaseNoiseExecutionStatus = "disabled";
    return;
end
y = pn.apply(x, double(sampleRateHz));
replay.PhaseNoiseApplied = true;
replay.PhaseNoiseSeed = double(seed);
replay.PhaseNoiseAvailableBackend = char(pn.Backend);
replay.PhaseNoiseTruthClassification = char(pn.TruthClassification);
replay.PhaseNoiseApproximationReason = char(pn.ApproximationReason);
replay.PhaseNoiseExecutionStatus = "applied_sample_domain_phase_noise";
try
    phaseDelta = angle(double(y(:)) .* conj(double(x(:))));
    replay.PhaseNoiseRMS_rad = sqrt(mean(double(unwrap(phaseDelta)).^2, "omitnan"));
catch
    replay.PhaseNoiseRMS_rad = NaN;
end
end

function [enabled, model, gainImbalance_dB, phaseImbalance_deg, source, status] = ...
        localResolveIQImbalanceRuntime(cfg)
resolved = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", struct());
model = string(localFirstNonEmptyString( ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.model", ""), ...
    sixgr.util.structGet(resolved, "power_and_rf_frontend.iq_imbalance", ""), ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.model", "")));
source = char(localFirstNonEmptyString( ...
    localSourceIfSet(resolved, "impairments.iq_imbalance.model"), ...
    localSourceIfSet(resolved, "power_and_rf_frontend.iq_imbalance"), ...
    localSourceIfSet(cfg, "rf.iqImbalance.model")));
enabled = logical(sixgr.util.structGet(cfg, "phy.impairments.iqImbalanceEnabled", false));
if ~enabled
    enabled = localModelImpliesEnabled(model);
end
gainImbalance_dB = localFirstFiniteValue( ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.ampImb_dB", NaN), ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.gainImbalance_dB", NaN), ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.gain_imbalance_db", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.iqGainImbalance_dB", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.iqImbalanceAmpImbalance_dB", NaN), ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.amp_imbalance_db", NaN), ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.ampImb_dB", NaN), ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.gain_imbalance_db", NaN), ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.gainImbalance_dB", NaN));
phaseImbalance_deg = localFirstFiniteValue( ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.phaseImb_deg", NaN), ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.phaseImbalance_deg", NaN), ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.phase_imbalance_deg", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.iqPhaseImbalance_deg", NaN), ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.phase_imbalance_deg", NaN), ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.phaseImbalance_deg", NaN), ...
    sixgr.util.structGet(resolved, "impairments.iq_imbalance.phaseImb_deg", NaN));
if ~isfinite(gainImbalance_dB)
    gainImbalance_dB = 0;
end
if ~isfinite(phaseImbalance_deg)
    phaseImbalance_deg = 0;
end
if strlength(strtrim(model)) == 0
    if enabled
        model = "configured_boolean_flag";
    else
        model = "none";
    end
end
if ~enabled
    status = "disabled";
elseif abs(gainImbalance_dB) <= 1e-12 && abs(phaseImbalance_deg) <= 1e-12
    status = "configured_zero_mismatch_noop";
else
    status = "configured";
end
end

function noise_dBm = localResolveThermalNoisePower(bandwidth_Hz, noiseFigure_dB)
noise_dBm = NaN;
if ~(isfinite(bandwidth_Hz) && bandwidth_Hz > 0 && isfinite(noiseFigure_dB))
    return;
end
noise_dBm = -174 + 10 * log10(max(double(bandwidth_Hz), eps)) + double(noiseFigure_dB);
end

function [y, replay] = localApplyIQImbalanceStage(x, replay)
y = x;
if isempty(x)
    replay.IQImbalanceMeasurementStatus = "empty_waveform";
    return;
end
enabled = logical(sixgr.util.structGet(replay, "IQImbalanceConfigured", false));
gainImbalance_dB = double(sixgr.util.structGet(replay, "ConfiguredIQGainImbalance_dB", 0));
phaseImbalance_deg = double(sixgr.util.structGet(replay, "ConfiguredIQPhaseImbalance_deg", 0));
status = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementStatus", "disabled"));
if enabled && (abs(gainImbalance_dB) > 1e-12 || abs(phaseImbalance_deg) > 1e-12)
    y = localApplyIQImbalanceModel(x, gainImbalance_dB, phaseImbalance_deg);
    replay.IQImbalanceApplied = true;
    status = "applied";
else
    replay.IQImbalanceApplied = false;
end
metrics = localMeasureIQImbalanceRuntime(x, y);
replay.IQImbalanceMirrorPowerRatio_dB = double(metrics.MirrorPowerRatio_dB);
replay.IQImbalanceImageRejection_dB = double(metrics.ImageRejection_dB);
replay.IQImbalanceIQPowerRatio_dB = double(metrics.IQPowerRatio_dB);
replay.IQImbalanceIQCorrelation = double(metrics.IQCorrelation);
replay.IQImbalanceEstimatedAlphaAbs = double(metrics.EstimatedAlphaAbs);
replay.IQImbalanceEstimatedBetaAbs = double(metrics.EstimatedBetaAbs);
replay.IQImbalanceMeasurementSource = char(metrics.MeasurementSource);
if replay.IQImbalanceApplied
    replay.IQImbalanceMeasurementStatus = char(metrics.MeasurementStatus);
else
    replay.IQImbalanceMeasurementStatus = char(status);
end
end

function y = localApplyIQImbalanceModel(x, gainImbalance_dB, phaseImbalance_deg)
% Avoid the iqimbal backend in unattended replay: on this Windows/MATLAB
% deployment it can terminate MATLAB with an access violation for larger
% multi-antenna waveforms, which try/catch cannot recover from. The
% widely-linear model below is the standard baseband IQ imbalance form.
g = 10.^(double(gainImbalance_dB) / 20);
phi = double(phaseImbalance_deg) * pi / 180;
alpha = 0.5 * (1 + g * exp(-1j * phi));
beta = 0.5 * (1 - g * exp(1j * phi));
y = alpha .* x + beta .* conj(x);
end

function metrics = localMeasureIQImbalanceRuntime(xRef, yObs)
metrics = struct( ...
    "MirrorPowerRatio_dB", NaN, ...
    "ImageRejection_dB", NaN, ...
    "IQPowerRatio_dB", NaN, ...
    "IQCorrelation", NaN, ...
    "EstimatedAlphaAbs", NaN, ...
    "EstimatedBetaAbs", NaN, ...
    "MeasurementSource", "sample_domain_widely_linear_fit_after_iq_stage", ...
    "MeasurementStatus", "not_measured");
x = double(xRef(:));
y = double(yObs(:));
mask = isfinite(real(x)) & isfinite(imag(x)) & isfinite(real(y)) & isfinite(imag(y));
if nnz(mask) < 8
    metrics.MeasurementStatus = "insufficient_samples";
    return;
end
x = x(mask);
y = y(mask);
A = [x, conj(x)];
if rank(A) < 2
    metrics.MeasurementStatus = "degenerate_reference";
    return;
end
coeff = A \ y;
alpha = coeff(1);
beta = coeff(2);
metrics.EstimatedAlphaAbs = abs(alpha);
metrics.EstimatedBetaAbs = abs(beta);
desiredComp = alpha .* x;
imageComp = beta .* conj(x);
desiredPower = mean(abs(desiredComp).^2, "omitnan");
imagePower = mean(abs(imageComp).^2, "omitnan");
numericImageFloor = max(realmin, eps(max(1, abs(double(desiredPower)))));
if isfinite(desiredPower) && desiredPower > 0 && isfinite(imagePower) && imagePower > 0
    rawMirrorRatio_dB = 10 * log10(imagePower / desiredPower);
    rawImageRejection_dB = 10 * log10(desiredPower / imagePower);
    if abs(beta) < 1e-9 || rawImageRejection_dB > 100
        metrics.MirrorPowerRatio_dB = -100;
        metrics.ImageRejection_dB = 100;
        metrics.MeasurementStatus = "below_numeric_floor_capped";
    else
        metrics.MirrorPowerRatio_dB = rawMirrorRatio_dB;
        metrics.ImageRejection_dB = max(-100, min(100, rawImageRejection_dB));
        metrics.MeasurementStatus = "measured";
    end
elseif isfinite(desiredPower) && desiredPower > 0 && isfinite(imagePower) && imagePower == 0
    metrics.MirrorPowerRatio_dB = -100;
    metrics.ImageRejection_dB = 100;
    metrics.MeasurementStatus = "below_numeric_floor_capped";
elseif isfinite(desiredPower) && desiredPower > 0 && isfinite(imagePower) && imagePower <= numericImageFloor
    metrics.MirrorPowerRatio_dB = -100;
    metrics.ImageRejection_dB = 100;
    metrics.MeasurementStatus = "below_numeric_floor_capped";
end
iVar = var(real(y), 1, "omitnan");
qVar = var(imag(y), 1, "omitnan");
if isfinite(iVar) && isfinite(qVar) && iVar > 0 && qVar > 0
    metrics.IQPowerRatio_dB = 10 * log10(iVar / qVar);
end
try
    rho = corrcoef(real(y), imag(y));
    if isequal(size(rho), [2 2]) && isfinite(rho(1,2))
        metrics.IQCorrelation = rho(1,2);
    end
catch
end
end

function tf = localModelImpliesEnabled(model)
model = strtrim(lower(string(model)));
tf = strlength(model) > 0 && ~any(model == ["none","disabled","ideal","off","false","constant_zero"]);
end

function value = localFirstFiniteValue(varargin)
value = NaN;
for i = 1:nargin
    candidate = double(varargin{i});
    if isempty(candidate)
        continue;
    end
    candidate = candidate(1);
    if isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function value = localFirstNonEmptyString(varargin)
value = "";
for i = 1:nargin
    candidate = strtrim(string(varargin{i}));
    if strlength(candidate) > 0
        value = candidate(1);
        return;
    end
end
end

function source = localSourceIfSet(root, path)
value = sixgr.util.structGet(root, path, []);
if ischar(value) || isstring(value)
    if strlength(strtrim(string(value))) > 0
        source = string(path);
        return;
    end
elseif isnumeric(value)
    value = double(value);
    if ~isempty(value) && isfinite(value(1))
        source = string(path);
        return;
    end
elseif islogical(value)
    if ~isempty(value)
        source = string(path);
        return;
    end
end
source = "";
end

function [loss_dB, source] = localResolveLargeScaleLoss(pathloss_dB, basePathloss_dB, shadow_dB, o2i_dB)
loss_dB = 0;
source = "none";
if isfinite(pathloss_dB)
    % Runtime Pathloss_dB already includes shadow fading and O2I loss.
    loss_dB = double(pathloss_dB);
    source = "runtime_total_pathloss_db";
    return;
end
parts = [basePathloss_dB, shadow_dB, o2i_dB];
finiteMask = isfinite(parts);
if any(finiteMask)
    loss_dB = sum(parts(finiteMask), "omitnan");
    source = "runtime_base_pathloss_plus_explicit_losses";
end
end

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0)));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", 0)));
if ~isfinite(timingOffset)
    timingOffset = 0;
end
end

function [phaseOffsetDeg, source] = localResolveInjectedCarrierPhaseOffsetDeg(cfg)
resolved = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", struct());
[phaseOffsetDeg, source] = localFirstFiniteValueWithSource( ...
    sixgr.util.structGet(cfg, "rf.phaseOffset_deg", NaN), "rf.phaseOffset_deg", ...
    sixgr.util.structGet(cfg, "rf.phase_shift_deg", NaN), "rf.phase_shift_deg", ...
    sixgr.util.structGet(cfg, "rf.carrierPhaseOffset_deg", NaN), "rf.carrierPhaseOffset_deg", ...
    sixgr.util.structGet(cfg, "phy.impairments.phaseOffset_deg", NaN), "phy.impairments.phaseOffset_deg", ...
    sixgr.util.structGet(cfg, "phy.impairments.phaseShift_deg", NaN), "phy.impairments.phaseShift_deg", ...
    sixgr.util.structGet(cfg, "impairments.phase_offset_deg", NaN), "impairments.phase_offset_deg", ...
    sixgr.util.structGet(cfg, "impairments.phase_shift_deg", NaN), "impairments.phase_shift_deg", ...
    sixgr.util.structGet(resolved, "impairments.phase_offset_deg", NaN), "lls6g.resolvedConfig.impairments.phase_offset_deg", ...
    sixgr.util.structGet(resolved, "impairments.phase_shift_deg", NaN), "lls6g.resolvedConfig.impairments.phase_shift_deg", ...
    sixgr.util.structGet(resolved, "impairments.carrier_phase_offset_deg", NaN), "lls6g.resolvedConfig.impairments.carrier_phase_offset_deg");
if ~isfinite(phaseOffsetDeg)
    phaseOffsetDeg = 0;
    source = "not_configured";
end
end

function [applied, status] = localInitialCarrierPhaseOffsetStatus(phaseOffsetDeg, source)
if string(source) == "not_configured"
    applied = false;
    status = "disabled";
elseif abs(double(phaseOffsetDeg)) <= 1e-12
    applied = false;
    status = "configured_zero_noop";
else
    applied = false;
    status = "configured_pending_sample_domain_rotation";
end
end

function [value, source] = localFirstFiniteValueWithSource(varargin)
value = NaN;
source = "not_configured";
for i = 1:2:nargin
    candidate = double(varargin{i});
    if isempty(candidate)
        continue;
    end
    candidate = candidate(1);
    if isfinite(candidate)
        value = candidate;
        source = string(varargin{i + 1});
        return;
    end
end
end

function value = localFiniteOrNaN(value)
value = double(value);
if isempty(value)
    value = NaN;
    return;
end
value = value(1);
if ~isfinite(value)
    value = NaN;
end
end

function value = localConditionalString(condition, trueValue, falseValue)
if condition
    value = string(trueValue);
else
    value = string(falseValue);
end
end
