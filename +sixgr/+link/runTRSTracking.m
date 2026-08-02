function out = runTRSTracking(cfg, varargin)
%RUNTRSTRACKING TRS generation/observation smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x, "sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 20), @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
log = p.Results.Logger;
snr_dB = double(p.Results.SNR_dB);

out = struct();
out.Ok = false;
out.Skipped = false;
out.NMSE_dB = NaN;
out.PhaseError_deg = NaN;
out.EstimatedDoppler_Hz = NaN;
out.InjectedDoppler_Hz = NaN;
out.ConfiguredMaxDoppler_Hz = NaN;
out.DopplerError_Hz = NaN;
out.EstimatedCFO_Hz = NaN;
out.EstimatedCFO_PreCorrection_Hz = NaN;
out.EstimatedOscillatorCFO_Hz = NaN;
out.EstimatedCommonFrequency_Hz = NaN;
out.PhysicalDoppler_Hz = NaN;
out.InjectedCFO_Hz = NaN;
out.CFOEstimateAvailability = "missing";
out.CFOEstimateSource = "";
out.CFOEstimateDefinition = "";
out.QCLAccuracy = NaN;
out.InterpolationLoss_dB = NaN;
out.MismatchSensitivity_dB = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.TrackingFailure = NaN;
out.DetectionMetric = NaN;
out.ChannelModel = "";
out.AppliedAWGNSNR_dB = NaN;
out.TrackingEstimateSource = "";
out.DetectionAttempted = false;
out.DetectionSuccess = false;
out.DetectionThreshold = NaN;
out.ResourceCoverageRatio = NaN;
out.MinCoverageRatio = NaN;
out.TimingTrackingAttempted = false;
out.TRSTimingEstimateAvailable = false;
out.TRSTimingEstimateUsable = false;
out.EstimatedTimingOffset_samples = NaN;
out.InjectedTimingOffset_samples = NaN;
out.TimingError_samples = NaN;
out.FrequencyTrackingAttempted = false;
out.TRSCFOEstimateAvailable = false;
out.TRSCFOEstimateUsable = false;
out.FrequencyError_Hz = NaN;
out.ChannelEstimationAttempted = false;
out.TRSChannelEstimateAvailable = false;
out.TRSRuntimeEvidenceUsable = false;
out.NoiseVariance = NaN;
out.StrictOk = false;
out.FailureReason = "";
out.Notes = "";

configuredTRS = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
configuredTracking = logical(sixgr.util.structGet(cfg, ...
    "phy.trackingRS.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "trs", configuredTRS, ...
    "runTRSTracking");
sixgr.config.assertRuntimeFeatureUse(cfg, "tracking_rs", configuredTracking, ...
    "runTRSTracking.tracking_receiver");
if ~(configuredTRS && configuredTracking)
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: TRS transmission or tracking receiver disabled by YAML";
    return;
end

try
    tStart = tic;
    [strictCfg, tx, rx, replay, timing, det, freq, ch, tracking, score] = ...
        localRunStrictRuntimeTRSEvidence(cfg, snr_dB);
    trial = score.TrialRow;
    runtimeEvidenceOk = localRuntimeTRSEvidenceComplete(trial, strictCfg);

    out.NMSE_dB = double(trial.NMSE_dB);
    out.PhaseError_deg = localMeanReferencePhaseDeg(det);
    out.EstimatedCFO_Hz = double(trial.EstimatedCFO_Hz);
    out.EstimatedCFO_PreCorrection_Hz = double(trial.EstimatedCFO_PreCorrection_Hz);
    out.EstimatedOscillatorCFO_Hz = double(sixgr.util.structGet(trial, "EstimatedOscillatorCFO_Hz", out.EstimatedCFO_Hz));
    out.EstimatedCommonFrequency_Hz = double(sixgr.util.structGet(trial, "EstimatedCommonFrequency_Hz", NaN));
    out.PhysicalDoppler_Hz = double(sixgr.util.structGet(trial, "PhysicalDoppler_Hz", ...
        sixgr.util.structGet(freq, "PhysicalDoppler_Hz", NaN)));
    out.InjectedCFO_Hz = double(trial.InjectedCFO_Hz);
    out.EstimatedDoppler_Hz = localResolveRuntimeDopplerEstimate(out.EstimatedCommonFrequency_Hz, out.EstimatedOscillatorCFO_Hz);
    out.ConfiguredMaxDoppler_Hz = localResolveConfiguredMaxDopplerHz(cfg);
    out.InjectedDoppler_Hz = localFirstFiniteValue(out.PhysicalDoppler_Hz, ...
        localResolveScalarInjectedDopplerHz(replay), localResolveConfiguredMaxDopplerHz(cfg));
    if isfinite(out.EstimatedDoppler_Hz) && isfinite(out.InjectedDoppler_Hz)
        out.DopplerError_Hz = out.EstimatedDoppler_Hz - out.InjectedDoppler_Hz;
    end
    out.ChannelModelApplied = string(sixgr.util.structGet(replay, "ChannelModelApplied", ...
        localResolveTrialChannelModel(cfg)));
    out.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false));
    out.QCLAccuracy = double(trial.QCLAccuracy);
    out.DetectionMetric = double(trial.DetectionMetric);
    out.AppliedAWGNSNR_dB = double(trial.AppliedAWGNSNR_dB);
    out.NoiseVariance = double(trial.NoiseVariance);
    out.ChannelModel = char(string(trial.ChannelModel));
    out.DetectionAttempted = logical(trial.DetectionAttempted);
    out.DetectionSuccess = logical(trial.DetectionSuccess);
    out.DetectionThreshold = localFirstTableNumber(sixgr.util.structGet(det, "Table", table()), "DetectionThreshold", NaN);
    out.ResourceCoverageRatio = double(trial.ResourceCoverageRatio);
    out.MinCoverageRatio = localFirstTableNumber(sixgr.util.structGet(det, "Table", table()), "MinCoverageRatio", NaN);
    out.TimingTrackingAttempted = logical(trial.TimingTrackingAttempted);
    out.TRSTimingEstimateAvailable = logical(trial.TRSTimingEstimateAvailable);
    out.TRSTimingEstimateUsable = localTimingEstimateUsable(trial, strictCfg);
    out.EstimatedTimingOffset_samples = double(trial.EstimatedTimingOffset_samples);
    out.InjectedTimingOffset_samples = double(trial.InjectedTimingOffset_samples);
    out.TimingError_samples = double(trial.TimingError_samples);
    out.FrequencyTrackingAttempted = logical(trial.FrequencyTrackingAttempted);
    out.TRSCFOEstimateAvailable = logical(trial.TRSCFOEstimateAvailable);
    out.TRSCFOEstimateUsable = localFrequencyEstimateUsable(trial, strictCfg);
    out.FrequencyError_Hz = double(trial.FrequencyError_Hz);
    out.ChannelEstimationAttempted = logical(trial.ChannelEstimationAttempted);
    out.TRSChannelEstimateAvailable = logical(trial.TRSChannelEstimateAvailable);
    out.TRSRuntimeEvidenceUsable = logical(runtimeEvidenceOk);
    out.StrictOk = logical(score.StrictOk);
    out.FailureReason = string(score.FailureReason);
    out.TrackingEstimateSource = "trs_reference_waveform_estimator";
    out.InterpolationLoss_dB = NaN;
    out.MismatchSensitivity_dB = NaN;
    out.ComputeLatency_ms = 1e3 * toc(tStart);
    out.ProcedureDelay_ms = NaN;
    out.AirInterfaceObservation_ms = 1e3 * (size(tx.Waveform, 1) / max(double(tx.SampleRateHz), eps));
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.TrackingFailure = double(~runtimeEvidenceOk);
    if isfinite(out.EstimatedCFO_Hz)
        out.CFOEstimateAvailability = "available";
        out.CFOEstimateSource = "trs_reference_phase_slope_frequency_estimator";
        out.CFOEstimateDefinition = "common_phase_frequency_slope_hz_from_trs_reference_symbols";
    else
        out.CFOEstimateAvailability = "missing";
        out.CFOEstimateSource = "trs_reference_phase_slope_frequency_estimator";
        out.CFOEstimateDefinition = "not_available_without_multiple_valid_trs_symbol_times";
    end
    out.Ok = logical(runtimeEvidenceOk);
    out.Notes = "TRS runtime tracking measurement from NZP-CSI-RS waveform path. NRE=" + string(localTRSNRE(tx)) + ...
        ", configured max Doppler=" + string(round(out.ConfiguredMaxDoppler_Hz, 3)) + ...
        " Hz, scalar injected Doppler=" + string(round(out.InjectedDoppler_Hz, 3)) + ...
        " Hz, measured Doppler component=" + string(round(out.EstimatedDoppler_Hz, 3)) + ...
        " Hz, estimated common frequency=" + string(round(out.EstimatedCommonFrequency_Hz, 3)) + ...
        " Hz, estimated oscillator CFO=" + string(round(out.EstimatedOscillatorCFO_Hz, 3)) + ...
        " Hz, strictOk=" + string(logical(score.StrictOk)) + ...
        ", runtimeEvidenceOk=" + string(runtimeEvidenceOk);
catch ME
    out.Ok = false;
    out.TrackingFailure = 1;
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runTRSTracking failed: " + string(ME.message));
    end
end
end

function [strictCfg, tx, rx, replay, timing, det, freq, ch, tracking, score] = localRunStrictRuntimeTRSEvidence(cfg, snr_dB)
runId = string(sixgr.util.structGet(cfg, "run.id", ...
    sixgr.util.structGet(cfg, "meta.scenario_id", "trs_runtime_tracking")));
scenarioName = string(sixgr.util.structGet(cfg, "scenario.name", ...
    sixgr.util.structGet(cfg, "meta.scenario_id", "trs_runtime_tracking")));
strictCfg = sixgr.phy.trs.buildTRSConfigFromScenario(cfg, ...
    "RunId", runId, "ScenarioName", scenarioName);
if isfield(strictCfg, "StrictValidation") && ...
        isfield(strictCfg.StrictValidation, "StrictValid") && ...
        ~logical(strictCfg.StrictValidation.StrictValid)
    reason = string(sixgr.util.structGet(strictCfg.StrictValidation, "StrictUnsupportedReason", ...
        "strict_trs_config_invalid"));
    error("sixgr:link:TRSStrictConfigInvalid", ...
        "Strict TRS runtime config is invalid: %s", char(reason));
end

tx = sixgr.phy.trs.generateTRSWaveform(strictCfg);
[rxWave, replay] = localApplyTrackingChannelAndNoise(tx.Waveform, ...
    localPrepareTRSReceiverObservationConfig(cfg, snr_dB), ...
    double(tx.SampleRateHz), snr_dB, double(strictCfg.NumCSIRSPorts));
rx = struct();
rx.Waveform = rxWave;
rx.NoiseOnlyWaveform = [];
rx.NoiseVariance = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
rx.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
rx.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", 0));
rx.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", 0));
physicalDopplerHz = localResolvePhysicalDopplerHz(cfg, replay);
rx.InjectedDoppler_Hz = double(physicalDopplerHz);
rx.PhysicalDoppler_Hz = double(physicalDopplerHz);
rx.FaultMode = "normal";
rx.SampleRateHz = double(tx.SampleRateHz);
rx.GridSlots = tx.GridSlots;
rx.TruthStatus = "real_lls_evidence";

timing = sixgr.phy.trs.estimateTRSTiming(rx, strictCfg, tx);
det = sixgr.phy.trs.detectTRSResources(rx, strictCfg, tx, "Timing", timing);
timing = localRejectTimingIfDetectionFailed(timing, det);
freq = sixgr.phy.trs.estimateTRSFrequencyOffset(det, strictCfg, tx, rx);
ch = sixgr.phy.trs.estimateTRSChannel(rx, strictCfg, tx, det);
tracking = sixgr.phy.trs.trackTRSOverTime(det, timing, freq, ch, strictCfg);
score = sixgr.phy.trs.scoreTRSDetection(strictCfg, rx, det, timing, freq, ch, tracking, ...
    "TrialId", 1, "TrialType", "runtime_coupled_trs", "NegativeExpected", false);
end

function timing = localRejectTimingIfDetectionFailed(timing, det)
if logical(sixgr.util.structGet(det, "DetectionSuccess", false))
    return;
end
timing.EstimateAvailable = false;
if istable(timing.Table) && ismember("TRSTimingEstimateAvailable", string(timing.Table.Properties.VariableNames))
    timing.Table.TRSTimingEstimateAvailable(:) = false;
    timing.Table.Status(:) = repmat("timing_estimate_rejected_no_valid_trs_detection", height(timing.Table), 1);
end
end

function tf = localRuntimeTRSEvidenceComplete(trial, cfg)
proxyClean = ~logical(trial.ProxyUsed) && ~logical(trial.Skipped) && ~logical(trial.ToolboxMissing) && ...
    strlength(strtrim(string(trial.UsedOracleFields))) == 0;
detectionUsable = logical(trial.DetectionAttempted) && logical(trial.DetectionSuccess) && ...
    isfinite(double(trial.DetectionMetric)) && ...
    double(trial.ResourceCoverageRatio) >= double(cfg.MinCoverageRatio);
timingUsable = localTimingEstimateUsable(trial, cfg);
frequencyUsable = localFrequencyEstimateUsable(trial, cfg);
channelUsable = logical(trial.ChannelEstimationAttempted) && logical(trial.TRSChannelEstimateAvailable) && ...
    isfinite(double(trial.NMSE_dB)) && double(trial.NMSE_dB) <= double(cfg.ChannelNMSEThresholddB);
tf = proxyClean && detectionUsable && timingUsable && frequencyUsable && channelUsable;
end

function tf = localTimingEstimateUsable(trial, cfg)
tf = false;
if ~(logical(trial.TimingTrackingAttempted) && logical(trial.TRSTimingEstimateAvailable))
    return;
end
est = double(trial.EstimatedTimingOffset_samples);
if ~isfinite(est)
    return;
end
maxSamples = localMaxRuntimeTimingCorrectionSamples(cfg);
tf = abs(est) <= maxSamples;
end

function tf = localFrequencyEstimateUsable(trial, cfg)
tf = false;
if ~(logical(trial.FrequencyTrackingAttempted) && logical(trial.TRSCFOEstimateAvailable))
    return;
end
est = double(trial.EstimatedCFO_Hz);
if ~isfinite(est)
    return;
end
maxHz = localMaxRuntimeFrequencyCorrectionHz(cfg);
tf = abs(est) <= maxHz;
end

function maxSamples = localMaxRuntimeTimingCorrectionSamples(cfg)
maxSamples = double(sixgr.util.structGet(cfg, "MaxRuntimeTimingCorrectionSamples", NaN));
if isfinite(maxSamples) && maxSamples >= 0
    return;
end
maxSamples = NaN;
try
    info = nrOFDMInfo(cfg.ToolboxCarrier);
    cp = double(sixgr.util.structGet(info, "CyclicPrefixLengths", []));
    symLen = double(sixgr.util.structGet(info, "SymbolLengths", []));
    nfft = double(sixgr.util.structGet(info, "Nfft", NaN));
    candidates = [];
    if ~isempty(symLen)
        symLen = symLen(isfinite(symLen) & symLen > 0);
        candidates = [candidates; symLen(:)]; %#ok<AGROW>
    end
    if isfinite(nfft) && nfft > 0
        candidates = [candidates; nfft]; %#ok<AGROW>
    end
    if ~isempty(cp)
        cp = cp(isfinite(cp) & cp >= 0);
        if ~isempty(cp) && isfinite(nfft) && nfft > 0
            candidates = [candidates; nfft + max(cp)]; %#ok<AGROW>
        else
            candidates = [candidates; cp(:)]; %#ok<AGROW>
        end
    end
    if ~isempty(candidates)
        maxSamples = max(candidates);
    end
catch
end
if ~(isfinite(maxSamples) && maxSamples >= 0)
    maxSamples = inf;
end
end

function maxHz = localMaxRuntimeFrequencyCorrectionHz(cfg)
scsHz = max(1, double(cfg.SubcarrierSpacingKHz) * 1e3);
baseCfg = sixgr.util.structGet(cfg, "BaseConfig", struct());
configuredCFOHz = abs(double(sixgr.util.structGet(baseCfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(baseCfg, "rf.cfoHz", 0))));
configuredDopplerHz = abs(double(sixgr.util.structGet(baseCfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(baseCfg, "channel.dopplerHz", ...
    sixgr.util.structGet(baseCfg, "channel.fading.maxDoppler_Hz", 0)))));
configuredSpanHz = configuredCFOHz + configuredDopplerHz + double(cfg.FrequencyToleranceHz);
maxHz = max([double(cfg.FrequencyToleranceHz), configuredSpanHz, scsHz / 2]);
end

function phaseDeg = localMeanReferencePhaseDeg(det)
phaseDeg = NaN;
T = sixgr.util.structGet(det, "Table", table());
if ~(istable(T) && height(T) > 0 && ismember("ReferencePhase_rad", string(T.Properties.VariableNames)))
    return;
end
phaseRad = double(T.ReferencePhase_rad);
phaseRad = phaseRad(isfinite(phaseRad));
if isempty(phaseRad)
    return;
end
phaseDeg = rad2deg(angle(mean(exp(1j * phaseRad), "omitnan")));
end

function nre = localTRSNRE(tx)
nre = NaN;
if ~(isstruct(tx) && isfield(tx, "GridSlots"))
    return;
end
vals = arrayfun(@(s) double(s.NRE), tx.GridSlots);
vals = vals(isfinite(vals));
if ~isempty(vals)
    nre = sum(vals);
end
end

function dopplerHz = localResolveRuntimeDopplerEstimate(commonFrequencyHz, estimatedOscillatorCFOHz)
dopplerHz = NaN;
if ~isfinite(double(commonFrequencyHz))
    return;
end
if isfinite(double(estimatedOscillatorCFOHz))
    dopplerHz = double(commonFrequencyHz) - double(estimatedOscillatorCFOHz);
else
    dopplerHz = double(commonFrequencyHz);
end
end

function value = localFirstTableNumber(T, name, defaultValue)
value = double(defaultValue);
if ~(istable(T) && height(T) > 0 && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
raw = double(T.(char(name)));
raw = raw(isfinite(raw));
if ~isempty(raw)
    value = raw(1);
end
end

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function [y, replay] = localApplyTrackingChannelAndNoise(txWave, cfg, sampleRateHz, snr_dB, nPorts)
replay = struct("AppliedAWGNSNR_dB", NaN, "ConfiguredSNR_dB", double(snr_dB), "InjectedNoiseVariance", NaN);
y = txWave;
modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
fadingApplied = false;
if ~(awgnOnly || any(modelRaw == ["AWGN", "NONE", "OFF", ""]))
    cfgCh = cfg;
    if startsWith(modelRaw, "TDL")
        cfgCh.channel.model = "TDL";
        if modelRaw ~= "TDL"
            cfgCh.channel.tdlProfile = char(modelRaw);
        end
    elseif startsWith(modelRaw, "CDL")
        cfgCh.channel.model = "CDL";
        if modelRaw ~= "CDL"
            cfgCh.channel.cdlProfile = char(modelRaw);
        end
    end
    ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
        "Model", cfgCh.channel.model, ...
        "SampleRate", sampleRateHz, ...
        "NumTxAnt", max(1, size(txWave, 2)), ...
        "NumRxAnt", localResolveTrackingNumRxAnt(cfg, nPorts), ...
        "Seed", sixgr.util.structGet(cfg, "run.seed", 1));
    if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
        chObj = ch.Object;
        try
            reset(chObj);
        catch
        end
        [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, sampleRateHz);
        xIn = txWave;
        if padSamples > 0
            xIn = [txWave; zeros(padSamples, size(txWave, 2), "like", txWave)];
        end
        try
            yRaw = chObj(xIn);
        catch
            [yRaw, ~] = chObj(xIn);
        end
        y = localTrimWaveform(yRaw, size(txWave, 1), trimSamples);
        fadingApplied = true;
    end
end
[y, replay] = sixgr.link.applyWaveformImpairments(y, cfg, sampleRateHz);
if ~fadingApplied
    scalarDopplerHz = localResolveConfiguredMaxDopplerHz(cfg);
    y = localApplyTrackingDoppler(y, sampleRateHz, scalarDopplerHz);
else
    scalarDopplerHz = NaN;
end
[y, replay.InjectedNoiseVariance] = localAddTrackingNoise(y, replay, snr_dB);
replay.ChannelFadingApplied = logical(fadingApplied);
replay.ChannelModelApplied = char(localResolveTrialChannelModel(cfg));
replay.ConfiguredMaxDoppler_Hz = double(localResolveConfiguredMaxDopplerHz(cfg));
replay.ScalarDopplerInjected = isfinite(scalarDopplerHz);
replay.InjectedScalarDoppler_Hz = double(scalarDopplerHz);
replay.PhysicalDoppler_Hz = double(localResolvePhysicalDopplerHz(cfg, replay));
end

function cfgOut = localPrepareTRSReceiverObservationConfig(cfg, snr_dB)
cfgOut = cfg;
cfgOut = sixgr.util.structSet(cfgOut, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
cfgOut = sixgr.util.structSet(cfgOut, "channel.snr_dB", double(snr_dB));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeSignalFamily", "TRS");
cfgOut = sixgr.util.structSet(cfgOut, "phy.runtimeSignalFamily", "TRS");
userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
if isstruct(userMeta)
    stripFields = { ...
        "RuntimeServingBSAntenna", ...
        "RuntimeServingBSAntennaMeta", ...
        "RuntimeUEAntenna", ...
        "RuntimeUEAntennaMeta", ...
        "RuntimeServingBasePathloss_dB", ...
        "RuntimeServingPathloss_dB", ...
        "RuntimeServingShadowFading_dB", ...
        "RuntimeServingO2I_dB", ...
        "RuntimeServingRxPower_dBm", ...
        "RuntimeServingRSRP_dBm", ...
        "RuntimeServingLargeScaleSINR_dB"};
    for idx = 1:numel(stripFields)
        if isfield(userMeta, stripFields{idx})
            userMeta = rmfield(userMeta, stripFields{idx});
        end
    end
    userMeta.RuntimeTRSReceiverObservationMode = "receiver_snr_calibrated_strict_trs_control_measurement";
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
end
end

function [y, nVar] = localAddTrackingNoise(x, replay, snr_dB)
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    nVar = localResolveThermalNoiseVariance(replay, x);
    if isfinite(nVar) && nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
    y = x;
    nVar = NaN;
    return;
end
[y, nVar] = localAddAwgn(x, double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", snr_dB)));
end

function sampleRateHz = localResolveSampleRate(ofdmInfo, carrier)
sampleRateHz = sixgr.util.structGet(ofdmInfo, "SampleRate", []);
if isempty(sampleRateHz)
    try
        nrInfo = nrOFDMInfo(carrier);
        sampleRateHz = double(sixgr.util.structGet(nrInfo, "SampleRate", []));
    catch
        sampleRateHz = [];
    end
end
if isempty(sampleRateHz)
    error("sixgr:link:TRSTrackingSampleRateMissing", ...
        "TRS tracking requires a known OFDM sample rate.");
end
sampleRateHz = double(sampleRateHz);
end

function numRx = localResolveTrackingNumRxAnt(cfg, fallback)
numRx = double(sixgr.util.structGet(cfg, "channel.nRxAnt", sixgr.util.structGet(cfg, "phy.nRxAnt", fallback)));
if ~(isfinite(numRx) && numRx >= 1)
    numRx = max(1, round(double(fallback)));
else
    numRx = max(1, round(numRx));
end
end

function dopplerHz = localResolveConfiguredMaxDopplerHz(cfg)
dopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
if ~isfinite(dopplerHz)
    dopplerHz = 0;
end
end

function dopplerHz = localResolveScalarInjectedDopplerHz(replay)
dopplerHz = NaN;
if ~(isstruct(replay) && logical(sixgr.util.structGet(replay, "ScalarDopplerInjected", false)))
    return;
end
dopplerHz = double(sixgr.util.structGet(replay, "InjectedScalarDoppler_Hz", NaN));
end

function dopplerHz = localResolvePhysicalDopplerHz(cfg, replay)
dopplerHz = localFirstFiniteValue( ...
    sixgr.util.structGet(cfg, "channel.runtimeSignedDoppler_Hz", NaN), ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingSignedDopplerHz", NaN), ...
    sixgr.util.structGet(replay, "PhysicalDoppler_Hz", NaN), ...
    sixgr.util.structGet(replay, "InjectedScalarDoppler_Hz", NaN));
if isfinite(dopplerHz)
    return;
end
if isstruct(replay) && logical(sixgr.util.structGet(replay, "ScalarDopplerInjected", false))
    dopplerHz = double(sixgr.util.structGet(replay, "InjectedScalarDoppler_Hz", NaN));
    return;
end
if isstruct(replay) && logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false))
    dopplerHz = NaN;
    return;
end
dopplerHz = 0;
end

function value = localFirstFiniteValue(varargin)
value = NaN;
for ii = 1:nargin
    raw = double(varargin{ii});
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, sampleRateHz)
padSamples = 0;
trimSamples = 0;
if isempty(chObj)
    return;
end
filterDelay = double(sixgr.util.structGet(chObj, "ChannelFilterDelay", sixgr.util.structGet(chObj, "FilterDelay", 0)));
pathDelays = sixgr.util.structGet(chObj, "PathDelays", []);
maxPathDelay = 0;
if ~isempty(pathDelays)
    pathDelays = double(pathDelays(:));
    pathDelays = pathDelays(isfinite(pathDelays) & pathDelays >= 0);
    if ~isempty(pathDelays)
        maxPathDelay = max(pathDelays) * max(double(sampleRateHz), 0);
    end
end
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function waveform = localTrimWaveform(yRaw, targetLen, trimSamples)
if trimSamples > 0 && size(yRaw, 1) >= (trimSamples + targetLen)
    waveform = yRaw(1 + trimSamples:trimSamples + targetLen, :);
else
    waveform = yRaw;
    if size(waveform, 1) > targetLen
        waveform = waveform(1:targetLen, :);
    elseif size(waveform, 1) < targetLen
        waveform(end + 1:targetLen, :) = cast(0, "like", waveform); %#ok<AGROW>
    end
end
end

function nVar = localResolveThermalNoiseVariance(replay, referenceWaveform)
nVar = NaN;
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
referencePower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
if ~(isfinite(servingRxPower_dBm) && isfinite(thermalNoisePower_dBm) && isfinite(referencePower) && referencePower > 0)
    return;
end
signalMilliwatt = 10.^(servingRxPower_dBm / 10);
noiseMilliwatt = 10.^(thermalNoisePower_dBm / 10);
if ~(isfinite(signalMilliwatt) && signalMilliwatt > 0 && isfinite(noiseMilliwatt) && noiseMilliwatt >= 0)
    return;
end
nVar = referencePower * (noiseMilliwatt / signalMilliwatt);
end

function model = localResolveTrialChannelModel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
if strlength(model) == 0 || any(model == ["NONE", "OFF"])
    model = "AWGN";
    return;
end
if model == "TDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.tdlProfile", sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
elseif model == "CDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.cdlProfile", sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
end
end

function y = localApplyTrackingDoppler(x, sampleRateHz, dopplerHz)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(dopplerHz) && dopplerHz ~= 0)
    return;
end
n = (0:size(y, 1)-1).';
h = exp(1j * 2 * pi * (dopplerHz / sampleRateHz) * n);
y = y .* h;
end

function [hTrue, symTimes_s, symIdx] = localReferencePilotChannel(carrier, pilotInd, nPorts, sampleRateHz, dopplerHz)
symIdx = localPilotSymbolIndices(carrier, pilotInd, nPorts);
symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz);
symTimes_s = symbolTimes(symIdx);
hTrue = exp(1j * 2 * pi * dopplerHz .* symTimes_s(:));
end

function symIdx = localPilotSymbolIndices(carrier, pilotInd, nPorts)
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
[~, symIdx, ~] = ind2sub([K, L, max(1, round(double(nPorts)))], double(pilotInd(:)));
symIdx = double(symIdx(:));
end

function symbolTimes_s = localSymbolCenterTimes(carrier, sampleRateHz)
L = double(carrier.SymbolsPerSlot);
symbolTimes_s = [];
try
    ofdmInfo = nrOFDMInfo(carrier);
    symbolLengths = double(sixgr.util.structGet(ofdmInfo, "SymbolLengths", []));
    if ~isempty(symbolLengths)
        symbolLengths = symbolLengths(:);
        if numel(symbolLengths) < L
            symbolLengths(end+1:L, 1) = symbolLengths(end);
        end
        symbolLengths = symbolLengths(1:L);
        symbolTimes_s = (cumsum(symbolLengths) - 0.5 * symbolLengths) / max(sampleRateHz, eps);
    end
catch
end
if isempty(symbolTimes_s)
    slotDur_s = 1e-3 / max(double(carrier.SubcarrierSpacing) / 15, eps);
    symDur_s = slotDur_s / max(L, 1);
    symbolTimes_s = ((0:L-1).' + 0.5) * symDur_s;
end
end

function nmse = localNormalizedMSE(hEst, hTrue)
hEst = hEst(:);
hTrue = hTrue(:);
N = min(numel(hEst), numel(hTrue));
if N == 0
    nmse = NaN;
    return;
end
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    nmse = NaN;
    return;
end
err = hEst(mask) - hTrue(mask);
hEst = hEst(mask);
hTrue = hTrue(mask);
alpha = (hTrue' * hEst) / max(hTrue' * hTrue, eps);
ref = alpha * hTrue;
err = hEst - ref;
den = mean(abs(ref).^2, "omitnan");
nmse = mean(abs(err).^2, "omitnan") / max(den, eps);
end

function estHz = localEstimateDopplerHz(symTimes_s, hEst)
estHz = NaN;
hEst = hEst(:);
symTimes_s = symTimes_s(:);
N = min(numel(symTimes_s), numel(hEst));
if N == 0
    return;
end
symTimes_s = symTimes_s(1:N);
hEst = hEst(1:N);
mask = isfinite(symTimes_s) & isfinite(real(hEst)) & isfinite(imag(hEst));
if nnz(mask) < 2
    estHz = 0;
    return;
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    estHz = 0;
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
phaseObs = unwrap(angle(hMean(:)));
p = polyfit(uTimes(:), phaseObs(:), 1);
estHz = p(1) / (2 * pi);
end

function estHz = localEstimateCommonPhaseFrequencyHz(symTimes_s, hEst)
% TRS alone observes a common phase slope; this is a receiver frequency
% tracking estimate, not a truth copy of the injected impairment.
estHz = NaN;
hEst = hEst(:);
symTimes_s = symTimes_s(:);
N = min(numel(symTimes_s), numel(hEst));
if N < 2
    return;
end
symTimes_s = symTimes_s(1:N);
hEst = hEst(1:N);
mask = isfinite(symTimes_s) & isfinite(real(hEst)) & isfinite(imag(hEst));
if nnz(mask) < 2
    return;
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
phaseObs = unwrap(angle(hMean(:)));
p = polyfit(uTimes(:), phaseObs(:), 1);
estHz = p(1) / (2 * pi);
end

function qcl = localReferenceCorrelation(hEst, hTrue)
qcl = NaN;
hEst = hEst(:);
hTrue = hTrue(:);
N = min(numel(hEst), numel(hTrue));
if N == 0
    return;
end
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    return;
end
hEst = hEst(mask);
hTrue = hTrue(mask);
den = norm(hEst) * norm(hTrue);
if den <= 0
    return;
end
qcl = abs(hTrue' * hEst) / den;
end

function loss_dB = localInterpolationLossNormalized(symIdx, hEst, hTrue)
loss_dB = NaN;
symIdx = double(symIdx(:));
hEst = hEst(:);
hTrue = hTrue(:);
N = min([numel(symIdx), numel(hEst), numel(hTrue)]);
if N == 0
    return;
end
symIdx = symIdx(1:N);
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(symIdx) & isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if nnz(mask) < 3
    loss_dB = 0;
    return;
end
[uSym, ~, grp] = unique(symIdx(mask), "stable");
if numel(uSym) < 3
    loss_dB = 0;
    return;
end
hEstSym = accumarray(grp, hEst(mask), [], @localComplexMean);
hTrueSym = accumarray(grp, hTrue(mask), [], @localComplexMean);
coarseSel = 1:2:numel(uSym);
if numel(coarseSel) < 2
    loss_dB = 0;
    return;
end
hInterp = complex( ...
    interp1(double(uSym(coarseSel)), real(hEstSym(coarseSel)), double(uSym), "linear", "extrap"), ...
    interp1(double(uSym(coarseSel)), imag(hEstSym(coarseSel)), double(uSym), "linear", "extrap"));
nmse = localNormalizedMSE(hInterp, hTrueSym);
loss_dB = 10 * log10(max(nmse, eps));
end

function sens_dB = localStaticMismatchSensitivity(hTrue)
sens_dB = NaN;
hTrue = hTrue(:);
mask = isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    return;
end
hTrue = hTrue(mask);
hStatic = mean(hTrue, "omitnan");
nmse = mean(abs(hTrue - hStatic).^2, "omitnan") / max(mean(abs(hTrue).^2, "omitnan"), eps);
sens_dB = 10 * log10(max(nmse, eps));
end

function y = localComplexMean(x)
if isempty(x)
    y = complex(NaN);
else
    y = mean(x, "omitnan");
end
end
