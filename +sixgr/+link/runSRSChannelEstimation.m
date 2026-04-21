function out = runSRSChannelEstimation(cfg, varargin)
%RUNSRSCHANNELESTIMATION SRS Tx/Rx channel-estimation smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 20), @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
log = p.Results.Logger;
snr_dB = double(p.Results.SNR_dB);

out = struct();
out.Ok = false;
out.Skipped = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";
out.NMSE_dB = NaN;
out.InterpolationLoss_dB = NaN;
out.MismatchSensitivity_dB = NaN;
out.QCLAccuracy = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = 0;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.TrackingFailure = 1;
out.InjectedDoppler_Hz = NaN;
out.EstimatedDopplerHz = NaN;
out.DopplerError_Hz = NaN;
out.EstimatedRI = NaN;
out.EstimatedTPMI = NaN;
out.RISource = "";
out.TPMISource = "";
out.TPMICandidateCount = NaN;
out.TPMIMutualInformation = NaN;
out.SRSConditionNumber_dB = NaN;

if ~logical(sixgr.util.structGet(cfg, "phy.srs.enable", true))
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.srs.enable=true for SRS coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.srs.enable=false";
    return;
end

if exist("nrSRS", "file") ~= 2 || exist("nrSRSIndices", "file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrSRS/nrSRSIndices for SRS coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrSRS APIs unavailable.";
    return;
end

try
    tStart = tic;
    [tx, info] = sixgr.phy.ul.SRS_Tx(cfg);
    sampleRateHz = localResolveSampleRate(info, tx, cfg);
    injectedDopplerHz = localResolveInjectedDopplerHz(cfg);
    txWave = localApplyTrackingDoppler(tx.Waveform, sampleRateHz, injectedDopplerHz);
    rxWave = localAddAwgn(txWave, snr_dB);
    [rx, ~] = sixgr.phy.ul.SRS_Rx(rxWave, cfg, "Carrier", tx.Carrier, "SRS", tx.SRS);

    if isempty(rx.Hest)
        out.Ok = false;
        out.Notes = "SRS channel estimate is empty.";
        return;
    end

    hEst = localSRSLSEstimate(rx.Hest, rx.RxGrid, tx.SRSIndices, tx.SRSSymbols);
    [hTrue, symTimes_s, symIdx] = localReferencePilotChannel(tx.Carrier, tx.SRSIndices, tx.SRS, sampleRateHz, injectedDopplerHz);
    nmse = localNormalizedMSE(hEst, hTrue);
    estimatedDopplerHz = localEstimateDopplerHz(hEst, symTimes_s);

    out.NMSE_dB = 10*log10(max(nmse, eps));
    out.InterpolationLoss_dB = localInterpolationLossNormalized(symIdx, hEst, hTrue);
    out.MismatchSensitivity_dB = localStaticMismatchSensitivity(hTrue);
    out.QCLAccuracy = localReferenceCorrelation(hEst, hTrue);
    out.ComputeLatency_ms = 1e3 * toc(tStart);
    out.ProcedureDelay_ms = 0;
    out.AirInterfaceObservation_ms = 1e3 * (size(txWave, 1) / max(sampleRateHz, eps));
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.TrackingFailure = 0;
    out.InjectedDoppler_Hz = injectedDopplerHz;
    out.EstimatedDopplerHz = estimatedDopplerHz;
    if isfinite(out.EstimatedDopplerHz) && isfinite(out.InjectedDoppler_Hz)
        out.DopplerError_Hz = out.EstimatedDopplerHz - out.InjectedDoppler_Hz;
    end
    srsULCSI = sixgr.phy.ul.estimateSRSRITPMI(rx.Hest, rx.NoiseVar, cfg);
    out.EstimatedRI = double(sixgr.util.structGet(srsULCSI, "RI", NaN));
    out.EstimatedTPMI = double(sixgr.util.structGet(srsULCSI, "TPMI", NaN));
    out.RISource = char(string(sixgr.util.structGet(srsULCSI, "RISource", "")));
    out.TPMISource = char(string(sixgr.util.structGet(srsULCSI, "TPMISource", "")));
    out.TPMICandidateCount = double(sixgr.util.structGet(srsULCSI, "TPMICandidateCount", NaN));
    out.TPMIMutualInformation = double(sixgr.util.structGet(srsULCSI, "TPMIMutualInformation", NaN));
    out.SRSConditionNumber_dB = double(sixgr.util.structGet(srsULCSI, "ConditionNumber_dB", NaN));
    out.Ok = true;
    out.Notes = "SRS NMSE=" + string(round(out.NMSE_dB,2)) + ...
        " dB, injected Doppler=" + string(round(injectedDopplerHz, 3)) + " Hz";
catch ME
    out.Ok = false;
    out.TrackingFailure = 1;
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runSRSChannelEstimation failed: " + string(ME.message));
    end
end
end

function y = localAddAwgn(x, snr_dB)
[y, ~] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function sampleRateHz = localResolveSampleRate(info, tx, cfg)
sampleRateHz = sixgr.util.structGet(info, "OFDMInfo.SampleRate", []);
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, "phy.sampleRate_Hz", []);
end
if isempty(sampleRateHz)
    try
        nrInfo = nrOFDMInfo(tx.Carrier);
        sampleRateHz = double(sixgr.util.structGet(nrInfo, "SampleRate", []));
    catch
        sampleRateHz = [];
    end
end
if isempty(sampleRateHz)
    error("sixgr:link:SRSChannelEstimationSampleRateMissing", ...
        "SRS tracking requires a known OFDM sample rate.");
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

function hEst = localSRSLSEstimate(Hest, rxGrid, srsInd, srsSym)
hEst = [];
if isempty(srsInd) || isempty(srsSym)
    return;
end
pilotHest = localPilotChannelEstimateSlice(Hest, srsInd);
if ~isempty(pilotHest)
    hEst = pilotHest(:);
    return;
end
if isempty(rxGrid)
    return;
end
try
    pilotObs = nrExtractResources(srsInd, rxGrid);
catch
    if ndims(rxGrid) >= 3
        pilotObs = rxGrid(:, :, 1);
        pilotObs = pilotObs(srsInd);
    else
        pilotObs = rxGrid(srsInd);
    end
end
pilotObs = localCollapsePilotObservations(pilotObs);
srsSym = srsSym(:);
N = min(numel(pilotObs), numel(srsSym));
if N == 0
    return;
end
pilotObs = pilotObs(1:N);
srsSym = srsSym(1:N);
den = srsSym;
den(abs(den) < eps) = 1;
hEst = pilotObs ./ den;
end

function pilotH = localPilotChannelEstimateSlice(H, pilotInd)
pilotH = [];
if isempty(H) || isempty(pilotInd)
    return;
end
sz = size(H);
if numel(sz) < 2
    return;
end
K = sz(1);
L = sz(2);
Nr = 1;
Np = 1;
if numel(sz) >= 3
    Nr = sz(3);
end
if numel(sz) >= 4
    Np = sz(4);
end
flatDim = max(K * L, 1);
ind = double(pilotInd(:));
ind = ind(isfinite(ind) & ind >= 1);
if isempty(ind)
    return;
end
try
    pDim = max(1, ceil(max(ind) / flatDim));
    [k, l, p] = ind2sub([K, L, pDim], ind);
catch
    return;
end
N = numel(ind);
pilotH = complex(NaN(N, 1));
for i = 1:N
    portIdx = min(max(round(double(p(i))), 1), Np);
    if numel(sz) >= 4
        v = squeeze(H(k(i), l(i), :, portIdx));
    elseif numel(sz) == 3
        v = squeeze(H(k(i), l(i), :));
    else
        v = H(k(i), l(i));
    end
    if isempty(v)
        continue;
    end
    if Nr > 1 || numel(v) > 1
        pilotH(i) = mean(v(:), "omitnan");
    else
        pilotH(i) = v;
    end
end
mask = isfinite(real(pilotH)) & isfinite(imag(pilotH));
if ~any(mask)
    pilotH = [];
end
end

function obs = localCollapsePilotObservations(pilotObs)
if isempty(pilotObs)
    obs = [];
    return;
end
if isvector(pilotObs)
    obs = pilotObs(:);
    return;
end
obs = mean(pilotObs, 2, "omitnan");
obs = obs(:);
end

function [hTrue, symTimes_s, symIdx] = localReferencePilotChannel(carrier, pilotInd, srs, sampleRateHz, dopplerHz)
nPorts = max(1, round(double(sixgr.util.structGet(srs, "NumSRSPorts", 1))));
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

function dopplerHz = localEstimateDopplerHz(hEst, symTimes_s)
dopplerHz = NaN;
hEst = hEst(:);
symTimes_s = double(symTimes_s(:));
N = min(numel(hEst), numel(symTimes_s));
if N == 0
    return;
end
hEst = hEst(1:N);
symTimes_s = symTimes_s(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(symTimes_s);
if nnz(mask) < 2
    dopplerHz = 0;
    return;
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    dopplerHz = 0;
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
phaseObs = unwrap(angle(hMean(:)));
p = polyfit(uTimes(:), phaseObs(:), 1);
dopplerHz = p(1) / (2 * pi);
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
