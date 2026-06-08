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
out.EstimatedCFO_Hz = NaN;
out.EstimatedCFO_PreCorrection_Hz = NaN;
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
out.Notes = "";

if ~logical(sixgr.util.structGet(cfg, "phy.trs.enable", false))
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.trs.enable=false";
    return;
end

try
    tStart = tic;
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
    [trsInd, trsSym, trsInfo] = sixgr.phy.refsig.trs(carrier, cfg);
    if isempty(trsInd)
        out.Notes = "TRS mapping produced no resources.";
        return;
    end

    nPorts = max(1, round(double(sixgr.util.structGet(trsInfo, "NumPorts", 1))));
    txGrid = nrResourceGrid(carrier, nPorts);
    txGrid(trsInd) = trsSym;
    [txWave, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid);

    sampleRateHz = localResolveSampleRate(ofdmInfo, carrier);
    injectedDopplerHz = localResolveInjectedDopplerHz(cfg);
    [rxWave, replay] = localApplyTrackingChannelAndNoise(txWave, cfg, sampleRateHz, snr_dB, nPorts);
    [rxGrid, ~] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWave);
    rxSym = rxGrid(trsInd);
    den = trsSym(:);
    den(abs(den) < eps) = 1;
    hEst = rxSym(:) ./ den;

    [hTrue, symTimes_s, symIdx] = localReferencePilotChannel(carrier, trsInd, nPorts, sampleRateHz, injectedDopplerHz);
    nmse = localNormalizedMSE(hEst, hTrue);
    phaseErr = angle(mean(hEst .* conj(hTrue), "omitnan"));

    out.NMSE_dB = 10 * log10(max(nmse, eps));
    out.PhaseError_deg = rad2deg(phaseErr);
    out.EstimatedDoppler_Hz = localEstimateDopplerHz(symTimes_s, hEst);
    out.InjectedDoppler_Hz = injectedDopplerHz;
    out.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
    out.EstimatedCFO_Hz = localEstimateCommonPhaseFrequencyHz(symTimes_s, hEst);
    out.EstimatedCFO_PreCorrection_Hz = out.EstimatedCFO_Hz;
    if isfinite(out.EstimatedCFO_Hz)
        out.CFOEstimateAvailability = "available";
        out.CFOEstimateSource = "trs_reference_phase_slope_frequency_estimator";
        out.CFOEstimateDefinition = "common_phase_frequency_slope_hz_from_trs_reference_symbols";
    else
        out.CFOEstimateAvailability = "missing";
        out.CFOEstimateSource = "trs_reference_phase_slope_frequency_estimator";
        out.CFOEstimateDefinition = "not_available_without_multiple_valid_trs_symbol_times";
    end
    out.QCLAccuracy = localReferenceCorrelation(hEst, hTrue);
    out.InterpolationLoss_dB = localInterpolationLossNormalized(symIdx, hEst, hTrue);
    out.MismatchSensitivity_dB = localStaticMismatchSensitivity(hTrue);
    out.ComputeLatency_ms = 1e3 * toc(tStart);
    out.ProcedureDelay_ms = NaN;
    out.AirInterfaceObservation_ms = 1e3 * (size(txWave, 1) / max(sampleRateHz, eps));
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.TrackingFailure = 0;
    out.DetectionMetric = -out.NMSE_dB;
    out.ChannelModel = char(localResolveTrialChannelModel(cfg));
    out.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
    out.TrackingEstimateSource = "trs_reference_waveform_estimator";
    out.Ok = true;
    out.Notes = "TRS runtime tracking measurement from active coupled-reference path. NRE=" + string(numel(trsInd)) + ...
        ", injected Doppler=" + string(round(out.InjectedDoppler_Hz, 3)) + ...
        " Hz, estimated Doppler=" + string(round(out.EstimatedDoppler_Hz, 3)) + ...
        " Hz, estimated CFO=" + string(round(out.EstimatedCFO_Hz, 3)) + " Hz";
catch ME
    out.Ok = false;
    out.TrackingFailure = 1;
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runTRSTracking failed: " + string(ME.message));
    end
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
    y = localApplyTrackingDoppler(y, sampleRateHz, localResolveInjectedDopplerHz(cfg));
end
[y, replay.InjectedNoiseVariance] = localAddTrackingNoise(y, replay, snr_dB);
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

function dopplerHz = localResolveInjectedDopplerHz(cfg)
dopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
if ~isfinite(dopplerHz)
    dopplerHz = 0;
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
