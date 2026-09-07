function [y, replay, state] = applyWaveformTruthImpairments(x, snr_dB, state, cfg, tx, txInfo, varargin)
%APPLYWAVEFORMTRUTHIMPAIRMENTS Apply the authoritative waveform impairment path.

ip = inputParser;
ip.addParameter("InputSampleDomain", "logical_ports", @(v)ischar(v) || isstring(v));
ip.parse(varargin{:});
% Resolve ownership before a mutable fading object consumes samples. A
% reciprocal propagation object does not make gNB/UE noise figures, power
% contexts or receiver random streams interchangeable.
direction = localResolveDirection(cfg,state);
fs = sixgr.util.structGet(state, "SampleRate_Hz", []);
if isempty(fs), fs = localResolveSampleRate(tx, txInfo); end
validateattributes(fs, {'numeric'}, {'real','scalar','finite','positive'});
fs = double(fs);
startSample = double(sixgr.util.structGet(state, "WaveformImpairmentNextSample", ...
    sixgr.util.structGet(state, "RuntimeChannelState.CurrentSampleIndex", 0)));
validateattributes(startSample, {'numeric'}, {'real','scalar','finite','integer','nonnegative'});
if isfield(state,"WaveformImpairmentNextSample") && ...
        logical(sixgr.util.structGet(state,"RuntimeChannelState.Initialized",false)) && ...
        startSample ~= double(state.RuntimeChannelState.CurrentSampleIndex)
    % Reject before the mutable fading object consumes even one sample.
    % Another consumer cannot advance a shared channel behind this receiver.
    error("sixgr:link:ImpairmentClockDiscontinuity", ...
        "Retained receiver clock %.0f differs from the physical channel clock %.0f.", ...
        startSample,double(state.RuntimeChannelState.CurrentSampleIndex));
end
if isfield(state, "WaveformImpairmentSampleRate") && state.WaveformImpairmentSampleRate ~= fs
    error("sixgr:link:ImpairmentSampleRateChanged", ...
        "A retained waveform impairment stream cannot change sample rate.");
end
y = x;

replay = struct( ...
    "RawWaveform", x, ...
    "CorrectedWaveform", x, ...
    "InjectedCFO_Hz", NaN, ...
    "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "ResidualCFO_PostCorrection_Hz", NaN, ...
    "InjectedTimingOffset_samples", NaN, ...
    "EstimatedTimingOffset_PreCorrection_samples", NaN, ...
    "ResidualTimingError_PostCorrection_samples", NaN, ...
    "SampleRate_Hz", fs, ...
    "WaveformLinkDirection", direction, ...
    "CFOCorrectionApplied", false, ...
    "InjectedNoiseVariance", NaN, ...
    "LargeScaleGain_dB", double(sixgr.util.structGet(state, "LargeScaleGain_dB", 0)), ...
    "Pathloss_dB", double(sixgr.util.structGet(state, "Pathloss_dB", NaN)), ...
    "ShadowFading_dB", double(sixgr.util.structGet(state, "ShadowFading_dB", NaN)), ...
    "O2ILoss_dB", double(sixgr.util.structGet(state, "O2ILoss_dB", NaN)), ...
    "LOS", double(sixgr.util.structGet(state, "LOS", NaN)), ...
    "InterferenceSIR_dB", double(sixgr.util.structGet(state, "InterferenceSIR_dB", NaN)), ...
    "InjectedInterferenceVariance", NaN, ...
    "PhaseNoiseConfigured", localPhaseNoiseConfigured(cfg), ...
    "PhaseNoiseApplied", false, ...
    "PhaseNoiseBackend", "disabled", ...
    "PhaseNoiseTruthClassification", "disabled", ...
    "PhaseNoiseExecutionStatus", "not_configured");

if isstruct(state)
    if sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg) || ...
            logical(sixgr.util.structGet(state,"UseFading",false))
        % Broadcast acquisition observes physical sample time. Do not trim
        % channel delay or synthesize a future zero tail on a cloned fading
        % object as the legacy grant-aligned interface does.
        [y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel( ...
            x,state,"OutputSampleAlignment","continuous_raw_samples", ...
            "InputSampleDomain",ip.Results.InputSampleDomain);
    else
        [y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel( ...
            x,state,"InputSampleDomain",ip.Results.InputSampleDomain);
    end
    chFields = fieldnames(channelReplay);
    for chIdx = 1:numel(chFields)
        replay.(chFields{chIdx}) = channelReplay.(chFields{chIdx});
    end
    if isfinite(channelReplay.RuntimeChannelStartSample)
        startSample = double(channelReplay.RuntimeChannelStartSample);
    end
end

% Initial-access/control waveforms must use the same absolute-power and
% noise-mode authority as PDSCH/PUSCH.  The earlier implementation scaled
% the waveform by pathloss and then added AWGN at (configured SNR + gain),
% which made pathloss reduce SNR a second time.  Bind the runtime
% large-scale state into the canonical impairment replay instead.
cfgReplay = localBindRuntimeLargeScaleContext(cfg, state);
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments( ...
    y, cfgReplay, fs, "ApplyRFChain", false);
impairmentFields = fieldnames(impairmentReplay);
for impairmentIdx = 1:numel(impairmentFields)
    replay.(impairmentFields{impairmentIdx}) = ...
        impairmentReplay.(impairmentFields{impairmentIdx});
end
timingOffset = localResolveInjectedTimingOffsetSamples(cfg);
replay.InjectedTimingOffset_samples = timingOffset;
if timingOffset ~= 0
    y = localApplyTimingOffset(y, timingOffset);
end

cfoHz = localResolveInjectedCFOHz(cfg);
replay.InjectedCFO_Hz = cfoHz;
if isfinite(cfoHz) && cfoHz ~= 0
    y = localApplyCFO(y, fs, cfoHz, startSample);
end
if localPhaseNoiseConfigured(cfg)
    [y, replay] = localApplyPhaseNoise(y, replay, cfg, fs);
end
replay.RawWaveform = y;

% The impairment producer has no receiver observations or decoded reference
% symbols. Comparing y with the exact transmitted x here is a genie-aided
% estimator, especially before noise has been added. Leave CFO in the samples;
% SSB_Rx performs PSS/CP synchronization on the final noisy receiver input.
replay.CFOCorrectionAuthority = "receiver_synchronization_after_noise";
replay.CFOEstimateSource = "unavailable_in_impairment_producer";
replay.CorrectedWaveformRole = "legacy_alias_uncorrected_pre_noise_waveform";
replay.CorrectedWaveform = y;

sir_dB = double(sixgr.util.structGet(state, "InterferenceSIR_dB", NaN));
if isfinite(sir_dB)
    sigPow = mean(abs(y(:)).^2, "omitnan");
    if isfinite(sigPow) && sigPow > 0
        interfVar = sigPow ./ max(10 .^ (sir_dB / 10), eps);
        interf = sqrt(interfVar / 2) .* (randn(size(y), "like", real(y)) + 1i * randn(size(y), "like", real(y)));
        y = y + cast(interf, "like", y);
        replay.InjectedInterferenceVariance = double(interfVar);
    end
end

noiseMode = lower(strtrim(string(sixgr.util.structGet( ...
    replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"))));
if noiseMode == "receiver_noise_figure_thermal_noise"
    thermalNoisePower_dBm = double(sixgr.util.structGet( ...
        replay, "ThermalNoisePower_dBm", NaN));
    if ~(isfinite(thermalNoisePower_dBm))
        error("sixgr:link:MissingInitialAccessThermalNoisePower", ...
            ["Initial-access thermal-noise mode requires a finite " ...
             "bandwidth and receiver noise figure."]);
    end
    replay.InjectedNoiseVariance = sixgr.link.resolveReceiverThermalNoiseVariance(replay);
    noiseState = sixgr.util.structGet(state, "ReceiverNoiseState", struct());
    origin = double(sixgr.util.structGet(noiseState, "OriginSample", startSample));
    runSeed = sixgr.util.structGet(cfg, "run.seed", []);
    validateattributes(runSeed, {'numeric'}, {'real','scalar','finite','integer','nonnegative'});
    identity = struct("RunSeed",runSeed,"LinkKey", ...
        string(sixgr.util.structGet(state,"RuntimeChannelState.LinkKey","standalone_receiver")), ...
        "UEIndex",sixgr.util.structGet(cfg,"lls6g.userContext.UEIndex", ...
            sixgr.util.structGet(cfg,"lls6g.userContext.RuntimeUEIndex",[])), ...
        "ServingCell",sixgr.util.structGet(cfg,"lls6g.userContext.RuntimeServingCellIndex",[]), ...
        "CarrierFrequencyHz",sixgr.util.structGet(cfg,"phy.fc_Hz", ...
            sixgr.util.structGet(cfg,"channel.fc_Hz",[])), ...
        "OriginSample",origin,"SampleRateHz",fs,"Direction",direction, ...
        "Role","physical_receiver_thermal_noise");
    digest = sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(identity),"UTF-8")));
    noiseSeed = hex2dec(extractBefore(digest,9));
    [y, state.ReceiverNoiseState] = sixgr.link.addRuntimeComplexNoise( ...
        y,replay.InjectedNoiseVariance,noiseSeed,startSample,noiseState);
    replay.NoisePowerSource = "thermal_noise_plus_receiver_nf_absolute_sqrt_mW_samples";
    replay.NoiseSequenceSource = "persistent_threefry_time_major_complex_draws";
    replay.NoiseStreamSeed = noiseSeed;
    replay.NoiseStreamOriginSample = origin;
else
    appliedSnr_dB = double(sixgr.util.structGet( ...
        replay, "AppliedAWGNSNR_dB", snr_dB));
    [y, replay.InjectedNoiseVariance] = ...
        localAddAwgnAtEffectiveSNR(y, appliedSnr_dB);
end
% These are the exact final samples handed to the decoder. RawWaveform and
% CorrectedWaveform above retain their earlier synchronization-stage roles.
replay.ReceiverInputWaveform = y;
replay.ReceiverInputWaveformSource = "sixgr.link.applyWaveformTruthImpairments:returned_receiver_samples";
replay.ImpairmentStartSample = startSample;
replay.ImpairmentEndSampleExclusive = startSample+size(y,1);
state.WaveformImpairmentNextSample = replay.ImpairmentEndSampleExclusive;
state.WaveformImpairmentSampleRate = fs;
end

function [y, nVar] = localAddAwgnAtEffectiveSNR(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function cfgOut = localBindRuntimeLargeScaleContext(cfgIn, state)
cfgOut = cfgIn;
userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
if ~(isstruct(userMeta) && isscalar(userMeta))
    userMeta = struct();
end
direction = localResolveDirection(cfgIn,state);
userMeta.RuntimeCurrentDirection = direction;
userMeta.Direction = direction;
userMeta.RuntimeServingBasePathloss_dB = double(sixgr.util.structGet( ...
    state, "Pathloss_dB", NaN));
userMeta.RuntimeServingPathloss_dB = double(sixgr.util.structGet( ...
    state, "Pathloss_dB", NaN));
userMeta.RuntimeServingShadowFading_dB = double(sixgr.util.structGet( ...
    state, "ShadowFading_dB", NaN));
userMeta.RuntimeServingO2I_dB = double(sixgr.util.structGet( ...
    state, "O2ILoss_dB", NaN));
userMeta.RuntimePathlossModelSource = char(string(sixgr.util.structGet( ...
    state, "PathlossModelSource", "waveform_truth_channel_state")));
userMeta.RuntimePathlossComplianceStatus = char(string(sixgr.util.structGet( ...
    state, "PathlossComplianceStatus", "runtime_state_resolved")));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
end

function direction = localResolveDirection(cfg,state)
direction = upper(strtrim(string(sixgr.util.structGet(cfg, ...
    "lls6g.userContext.RuntimeCurrentDirection", ...
    sixgr.util.structGet(cfg,"lls6g.userContext.Direction","DL")))));
if ~isscalar(direction) || ismissing(direction) || ~any(direction == ["DL","UL"])
    error("sixgr:link:InvalidWaveformLinkDirection", ...
        "Waveform impairment execution requires an explicit valid DL/UL direction.");
end
bindings = {sixgr.util.structGet(state,"Direction",[]), ...
    sixgr.util.structGet(state,"RuntimeChannelState.Direction",[]), ...
    sixgr.util.structGet(cfg,"lls6g.runtimePowerContext.Direction",[])};
for k = 1:numel(bindings)
    if isempty(bindings{k}), continue; end
    bound = upper(strtrim(string(bindings{k})));
    if ~isscalar(bound) || ismissing(bound) || bound ~= direction
        error("sixgr:link:WaveformLinkDirectionMismatch", ...
            "Receiver, power and materialized link contexts must agree on direction before sample execution.");
    end
end
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
    if isempty(fs), fs=sixgr.util.structGet(txInfo,"OFDMInfo.SampleRate",[]); end
end
if isempty(fs) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            fs = [];
        end
    end
end
if ~isnumeric(fs) || ~isreal(fs) || ~isscalar(fs) || ~isfinite(fs) || fs<=0
    error("sixgr:link:WaveformSampleRateUnavailable", ...
        "Waveform impairment execution requires the actual producer sample clock.");
end
fs = double(fs);
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

function y = localApplyTimingOffset(x, timingOffset)
y = sixgr.util.applyFractionalSampleDelay(x, timingOffset);
end

function y = localApplyCFO(x, sampleRateHz, cfoHz, startSample)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(cfoHz) && cfoHz ~= 0)
    return;
end
n = startSample + (0:size(y, 1)-1).';
rot = exp(1j * 2 * pi * (cfoHz / sampleRateHz) * n);
y = y .* cast(rot, "like", y);
end

function tf = localPhaseNoiseConfigured(cfg)
tf = logical(sixgr.util.structGet(cfg, "rf.phaseNoise.enable", false)) || ...
    logical(sixgr.util.structGet(cfg, "phy.impairments.phaseNoiseEnabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "impairments.phase_noise_enabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "lls6g.resolvedConfig.impairments.phase_noise_enabled", false));
end

function [y, replay] = localApplyPhaseNoise(x, replay, cfg, fs)
y = x;
if ~(isfinite(double(fs)) && double(fs) > 0)
    replay.PhaseNoiseExecutionStatus = "configured_but_sample_rate_unavailable";
    return;
end
seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) + 3001;
pn = sixgr.rf.PhaseNoiseModel(cfg, double(fs), seed);
if ~logical(pn.Enable)
    replay.PhaseNoiseExecutionStatus = "disabled";
    return;
end
y = pn.apply(x, double(fs));
replay.PhaseNoiseApplied = true;
replay.PhaseNoiseBackend = char(pn.Backend);
replay.PhaseNoiseTruthClassification = char(pn.TruthClassification);
replay.PhaseNoiseExecutionStatus = "applied_sample_domain_phase_noise";
end
