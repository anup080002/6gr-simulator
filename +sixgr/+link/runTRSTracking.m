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
out.QCLAccuracy = NaN;
out.InterpolationLoss_dB = NaN;
out.MismatchSensitivity_dB = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.TrackingFailure = NaN;
out.DetectionMetric = NaN;
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
    txWave = localApplyTrackingDoppler(txWave, sampleRateHz, injectedDopplerHz);
    [rxWave, ~] = localAddAwgn(txWave, snr_dB);
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
    out.Ok = true;
    out.Notes = "TRS NRE=" + string(numel(trsInd)) + ...
        ", injected Doppler=" + string(round(out.InjectedDoppler_Hz, 3)) + ...
        " Hz, estimated Doppler=" + string(round(out.EstimatedDoppler_Hz, 3)) + " Hz";
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

function dopplerHz = localResolveInjectedDopplerHz(cfg)
dopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
if ~isfinite(dopplerHz)
    dopplerHz = 0;
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
