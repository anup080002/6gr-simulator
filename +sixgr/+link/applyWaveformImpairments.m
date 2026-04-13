function [y, replay] = applyWaveformImpairments(x, cfg, sampleRateHz)
%APPLYWAVEFORMIMPAIRMENTS Apply large-scale loss and sample-domain impairments.
% Keep this file ASCII-only.
%
% Large-scale attenuation is expressed as a power-domain loss in dB. We
% convert it to a complex-sample amplitude scale with:
%   AppliedLargeScaleGain_dB = -AppliedLargeScaleLoss_dB
%   amplitudeGain = 10^(AppliedLargeScaleGain_dB/20)
%
% The downstream AWGN helper can either:
%   - anchor noise to a configured SNR operating point, or
%   - inject thermal noise derived from bandwidth and receiver noise figure.
%
% In the thermal-noise mode we keep an explicit absolute-power bridge between
% the normalized waveform and the large-scale link budget by using the
% serving-cell RuntimeServingRxPower_dBm exported by the coupled runtime.

if nargin < 3 || ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    sampleRateHz = 0;
else
    sampleRateHz = double(sampleRateHz);
end

replay = localResolveReplayContext(cfg, sampleRateHz);
y = x;

ampGain = double(replay.AppliedLargeScaleAmplitudeGain);
if isfinite(ampGain) && ampGain > 0 && abs(ampGain - 1) > 1e-12
    y = y .* cast(ampGain, "like", y);
end

timingOffset = double(replay.InjectedTimingOffset_samples);
if isfinite(timingOffset) && timingOffset ~= 0
    timingOffset = round(timingOffset);
    if timingOffset > 0
        y = [zeros(timingOffset, size(y, 2), "like", y); y];
    else
        shift = abs(timingOffset);
        if shift >= size(y, 1)
            y = zeros(size(y), "like", y);
        else
            y = [y(shift+1:end, :); zeros(shift, size(y, 2), "like", y)];
        end
    end
end

cfoHz = double(replay.InjectedCFO_Hz);
if sampleRateHz > 0 && isfinite(cfoHz) && cfoHz ~= 0
    n = (0:size(y, 1)-1).';
    rot = exp(1j * 2 * pi * (cfoHz / sampleRateHz) * n);
    y = y .* cast(rot, "like", y);
end
end

function replay = localResolveReplayContext(cfg, sampleRateHz)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());

basePathloss_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingBasePathloss_dB", NaN));
pathloss_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingPathloss_dB", NaN));
shadow_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingShadowFading_dB", NaN));
o2i_dB = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingO2I_dB", NaN));

[loss_dB, gainSource] = localResolveLargeScaleLoss(pathloss_dB, basePathloss_dB, shadow_dB, o2i_dB);
gain_dB = -loss_dB;
ampGain = 10.^(gain_dB / 20);

configuredSNR_dB = localFiniteOrNaN(sixgr.util.structGet(cfg, "channel.snr_dB", NaN));
noiseMode = localResolveNoiseOperatingMode(cfg);
[servingRxPower_dBm, servingRxPowerSource, referenceTxPower_dBm, referenceTxPowerSource] = ...
    localResolveServingRxPower(cfg, userMeta, loss_dB);
noiseFigure_dB = localResolveNoiseFigure(cfg);
noiseBandwidth_Hz = localResolveNoiseBandwidth(cfg, sampleRateHz);
[appliedAWGNSNR_dB, targetNoiseVariance, thermalNoisePower_dBm, noiseSource] = ...
    localResolveAppliedNoise(noiseMode, configuredSNR_dB, loss_dB, servingRxPower_dBm, noiseBandwidth_Hz, noiseFigure_dB, ampGain);
[phaseNoiseConfigured, phaseNoiseBackend, phaseNoiseTruthClassification, phaseNoiseApproximationReason, phaseNoiseExecutionStatus] = ...
    localResolvePhaseNoiseTruthBoundary(cfg, sampleRateHz);

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
    "SampleRate_Hz", double(sampleRateHz), ...
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
    "ServingRxPower_dBm", servingRxPower_dBm, ...
    "ServingRxPowerSource", char(servingRxPowerSource), ...
    "ReferenceTxPower_dBm", referenceTxPower_dBm, ...
    "ReferenceTxPowerSource", char(referenceTxPowerSource), ...
    "ServingRSRP_dBm", servingRSRP_dBm, ...
    "ServingRSRPSource", "large_scale_serving_reference_signal", ...
    "LargeScaleSINR_dB", largeScaleSINR_dB, ...
    "LargeScaleSINRSource", largeScaleSINRSource, ...
    "InterferenceMode", char(interferenceMode), ...
    "PhaseNoiseConfigured", logical(phaseNoiseConfigured), ...
    "PhaseNoiseAvailableBackend", char(phaseNoiseBackend), ...
    "PhaseNoiseTruthClassification", char(phaseNoiseTruthClassification), ...
    "PhaseNoiseApproximationReason", char(phaseNoiseApproximationReason), ...
    "PhaseNoiseExecutionStatus", char(phaseNoiseExecutionStatus));
end

function mode = localResolveNoiseOperatingMode(cfg)
mode = string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ...
    "configured_snr_anchor_after_large_scale_gain"));
mode = strtrim(lower(mode));
if strlength(mode) == 0
    mode = "configured_snr_anchor_after_large_scale_gain";
end
end

function [servingRxPower_dBm, source, referenceTxPower_dBm, referenceTxPowerSource] = ...
        localResolveServingRxPower(cfg, userMeta, loss_dB)
servingRxPower_dBm = localFiniteOrNaN(sixgr.util.structGet(userMeta, "RuntimeServingRxPower_dBm", NaN));
source = "runtime_serving_rx_power";
referenceTxPower_dBm = NaN;
referenceTxPowerSource = "";
if isfinite(servingRxPower_dBm)
    return;
end
if ~(isfinite(loss_dB) && loss_dB >= 0)
    source = "unavailable";
    return;
end
[referenceTxPower_dBm, referenceTxPowerSource] = localResolveReferenceTxPower(cfg, userMeta);
if ~(isfinite(referenceTxPower_dBm))
    source = "unavailable";
    return;
end
servingRxPower_dBm = referenceTxPower_dBm - loss_dB;
source = "derived_tx_power_minus_large_scale_loss";
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

function appliedAWGNSNR_dB = localResolveAppliedAWGNSNR(noiseMode, configuredSNR_dB, loss_dB)
if ~isfinite(configuredSNR_dB)
    appliedAWGNSNR_dB = NaN;
    return;
end
switch strtrim(lower(string(noiseMode)))
    case "configured_snr_anchor_after_large_scale_gain"
        % Preserve the requested receive-side SNR after large-scale
        % attenuation has already been applied to the waveform samples.
        appliedAWGNSNR_dB = configuredSNR_dB;
    case {"configured_snr_before_large_scale_gain", "configured_launch_snr_before_pathloss"}
        % Interpret the configured SNR as a launch-point value before the
        % large-scale attenuation is applied.
        appliedAWGNSNR_dB = configuredSNR_dB - loss_dB;
    otherwise
        % Fail closed to the existing browser-visible operating mode.
        appliedAWGNSNR_dB = configuredSNR_dB;
end
end

function [appliedAWGNSNR_dB, targetNoiseVariance, thermalNoisePower_dBm, source] = ...
        localResolveAppliedNoise(noiseMode, configuredSNR_dB, loss_dB, servingRxPower_dBm, noiseBandwidth_Hz, noiseFigure_dB, ampGain)
targetNoiseVariance = NaN;
thermalNoisePower_dBm = NaN;
source = "configured_snr";
appliedAWGNSNR_dB = localResolveAppliedAWGNSNR(noiseMode, configuredSNR_dB, loss_dB);

switch strtrim(lower(string(noiseMode)))
    case "receiver_noise_figure_thermal_noise"
        thermalNoisePower_dBm = localResolveThermalNoisePower(noiseBandwidth_Hz, noiseFigure_dB);
        source = "thermal_noise_plus_receiver_nf";
        if isfinite(servingRxPower_dBm) && isfinite(thermalNoisePower_dBm)
            appliedAWGNSNR_dB = servingRxPower_dBm - thermalNoisePower_dBm;
        else
            appliedAWGNSNR_dB = NaN;
        end
        % Bridge the absolute thermal-noise power into the normalized
        % waveform domain inside the DL/UL kernels, where the desired
        % reference waveform power is still available after fading,
        % large-scale scaling, and interference synthesis.
        targetNoiseVariance = NaN;
    otherwise
        source = "configured_snr";
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

function noiseFigure_dB = localResolveNoiseFigure(cfg)
noiseFigure_dB = localFiniteOrNaN(sixgr.util.structGet(cfg, "scenario.ue.noiseFigure_dB", ...
    sixgr.util.structGet(cfg, "channel.receiverNoiseFigure_dB", 9)));
if ~isfinite(noiseFigure_dB)
    noiseFigure_dB = 9;
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
executionStatus = "configured_not_materialized_in_active_waveform_truth_path";
end

function noise_dBm = localResolveThermalNoisePower(bandwidth_Hz, noiseFigure_dB)
noise_dBm = NaN;
if ~(isfinite(bandwidth_Hz) && bandwidth_Hz > 0 && isfinite(noiseFigure_dB))
    return;
end
noise_dBm = -174 + 10 * log10(max(double(bandwidth_Hz), eps)) + double(noiseFigure_dB);
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
timingOffset = round(timingOffset);
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
