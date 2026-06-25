function ch = estimateULChannelFromSRS(det, srsCfg)
%ESTIMATEULCHANNELFROMSRS Estimate measured UL channel evidence from SRS REs.

obs = det.Extracted.ObservedSymbols(:);
ref = det.Extracted.ReferenceSymbols(:);
N = min(numel(obs), numel(ref));
meta = localAlignedMeta(det, srsCfg, N);
hTruth = localAlignedAppliedChannelTruth(det, N);

hLS = complex([]);
hEst = complex([]);
finiteMask = false(N, 1);
if N > 0
    obs = obs(1:N);
    ref = ref(1:N);
    finiteMask = isfinite(real(obs)) & isfinite(imag(obs)) & ...
        isfinite(real(ref)) & isfinite(imag(ref)) & abs(ref) > eps;
    hLS = complex(NaN(N, 1));
    hLS(finiteMask) = obs(finiteMask) ./ ref(finiteMask);
    hEst = localApplyConfiguredEstimator(hLS, meta, srsCfg);
end

validEst = isfinite(real(hEst)) & isfinite(imag(hEst));
validLS = isfinite(real(hLS)) & isfinite(imag(hLS));
valid = validEst & validLS;
[hPRB, prbRows] = localPerPRBEstimates(hEst, hLS, meta, srsCfg);
[hPort, portRows] = localPerPortEstimates(hEst, hLS, meta, srsCfg);
truthValid = validEst & isfinite(real(hTruth)) & isfinite(imag(hTruth));
if any(truthValid)
    [nmseDb, sinrDb, noiseVar, residualPower, signalPower] = localMeasuredResidualMetrics(hTruth(truthValid), hEst(truthValid));
    nmseReferenceSource = "applied_channel_gain_truth";
else
    [nmseDb, sinrDb, noiseVar, residualPower, signalPower] = localMeasuredResidualMetrics(hLS(valid), hEst(valid));
    nmseReferenceSource = "ls_residual_fallback";
end
riTpmi = localEstimateRITPMI(hEst, meta, noiseVar, srsCfg);

perPrbAvailable = ~isempty(prbRows) && all([prbRows.EstimateAvailable]);
perPortAvailable = ~isempty(portRows) && all([portRows.EstimateAvailable]);
perReAvailable = any(validEst);
available = logical(det.DetectionSuccess) && perReAvailable && perPrbAvailable && perPortAvailable && ...
    isfinite(nmseDb) && nmseDb <= double(srsCfg.ChannelNMSEThresholddB);
exportNMSEdB = double(nmseDb);
exportSINRdB = double(sinrDb);
if ~available
    exportNMSEdB = NaN;
    exportSINRdB = NaN;
end

row = struct("RunId", string(srsCfg.RunId), "TrialId", NaN, "UEId", double(srsCfg.UEId), ...
    "ResourceId", double(srsCfg.ResourceId), "Port", localFirstFinite(meta.Port), ...
    "PRBStart", double(det.Coverage.PRBStart), ...
    "NumRB", double(det.Coverage.OccupiedPRBCount), "ChannelEstimateAttempted", true, ...
    "SRSChannelEstimateAvailable", logical(available), "PerREEstimateAvailable", logical(perReAvailable), ...
    "PerPRBEstimateAvailable", logical(perPrbAvailable), "PerPortEstimateAvailable", logical(perPortAvailable), ...
    "NMSE_dB", double(exportNMSEdB), "WidebandSRSSINR_dB", double(exportSINRdB), ...
    "NMSEReferenceSource", string(nmseReferenceSource), ...
    "NoiseVarianceEstimate", double(noiseVar), "PilotResidualPower", double(residualPower), ...
    "PilotSignalPower", double(signalPower), "NumChannelSamples", double(sum(valid)), ...
    "NumFiniteLSSamples", double(sum(validLS)), "NumSRSRE", double(N), ...
    "NumPRBEstimates", double(numel(prbRows)), "NumPortEstimates", double(numel(portRows)), ...
    "CombNumber", double(srsCfg.CombNumber), "CombOffset", double(srsCfg.CombOffset), ...
    "CyclicShift", double(srsCfg.CyclicShift), "SequenceId", double(srsCfg.SequenceId), ...
    "Estimator", localEstimatorName(srsCfg), ...
    "ConfiguredEstimatorAlgorithm", string(sixgr.util.structGet(srsCfg, "ChannelEstimatorAlgorithm", "")), ...
    "ConfiguredInterpolation", string(sixgr.util.structGet(srsCfg, "ChannelEstimatorInterpolation", "")), ...
    "MMSEFilterApplied", localMMSEEnabled(srsCfg), ...
    "MMSEFrequencySmoothingBins", double(localOddWindow(sixgr.util.structGet(srsCfg, "MMSEFrequencySmoothingBins", 1))), ...
    "DFTFilterApplied", localDFTEnabled(srsCfg), ...
    "DFTDelayTapKeepCount", double(localDFTKeepCount(srsCfg, sum(validLS))), ...
    "SRSRITPMIValid", logical(sixgr.util.structGet(riTpmi, "Valid", false)), ...
    "RIEstimate", double(sixgr.util.structGet(riTpmi, "RI", NaN)), ...
    "TPMIEstimate", double(sixgr.util.structGet(riTpmi, "TPMI", NaN)), ...
    "RISource", string(sixgr.util.structGet(riTpmi, "RISource", "")), ...
    "TPMISource", string(sixgr.util.structGet(riTpmi, "TPMISource", "")), ...
    "TPMICandidateCount", double(sixgr.util.structGet(riTpmi, "TPMICandidateCount", NaN)), ...
    "TPMIMutualInformation", double(sixgr.util.structGet(riTpmi, "TPMIMutualInformation", NaN)), ...
    "RIConditionNumber_dB", double(sixgr.util.structGet(riTpmi, "ConditionNumber_dB", NaN)), ...
    "FailureReason", string(sixgr.phy.srs.localTernary(available, "", "srs_channel_estimate_unavailable_or_nmse_above_threshold")), ...
    "ConfigHash", string(srsCfg.ConfigHash), "TruthStatus", "real_lls_evidence");

ch = struct("ChannelEstimateAttempted", true, "SRSChannelEstimateAvailable", logical(available), ...
    "Hest", hEst(validEst), "HestLS", hLS(validLS), "HestPerRE", hEst, ...
    "HestPerPRB", hPRB, "HestPerPort", hPort, ...
    "PerREEstimateAvailable", logical(perReAvailable), ...
    "PerPRBEstimateAvailable", logical(perPrbAvailable), ...
    "PerPortEstimateAvailable", logical(perPortAvailable), ...
    "NMSE_dB", double(exportNMSEdB), "WidebandSRSSINR_dB", double(exportSINRdB), ...
    "NoiseVarianceEstimate", double(noiseVar), ...
    "NMSEReferenceSource", string(nmseReferenceSource), ...
    "SRSRITPMI", riTpmi, ...
    "RIEstimate", double(sixgr.util.structGet(riTpmi, "RI", NaN)), ...
    "TPMIEstimate", double(sixgr.util.structGet(riTpmi, "TPMI", NaN)), ...
    "RISource", string(sixgr.util.structGet(riTpmi, "RISource", "")), ...
    "TPMISource", string(sixgr.util.structGet(riTpmi, "TPMISource", "")), ...
    "TPMICandidateCount", double(sixgr.util.structGet(riTpmi, "TPMICandidateCount", NaN)), ...
    "TPMIMutualInformation", double(sixgr.util.structGet(riTpmi, "TPMIMutualInformation", NaN)), ...
    "RIConditionNumber_dB", double(sixgr.util.structGet(riTpmi, "ConditionNumber_dB", NaN)), ...
    "Table", struct2table(row, "AsArray", true), ...
    "PerPRBTable", localRowsToTable(prbRows, localPRBRow()), ...
    "PerPortTable", localRowsToTable(portRows, localPortRow()));
end

function hTruth = localAlignedAppliedChannelTruth(det, N)
hTruth = complex(NaN(N, 1));
if N <= 0 || ~isfield(det, "Extracted") || ~isfield(det.Extracted, "AppliedChannelGains")
    return;
end
raw = det.Extracted.AppliedChannelGains(:);
n = min(N, numel(raw));
if n > 0
    hTruth(1:n) = raw(1:n);
end
end

function meta = localAlignedMeta(det, srsCfg, N)
T = det.Extracted.Table;
meta = struct("Slot", NaN(N, 1), "Symbol", NaN(N, 1), "Subcarrier", NaN(N, 1), ...
    "PRB", NaN(N, 1), "Port", NaN(N, 1));
if istable(T) && height(T) > 0
    names = string(T.Properties.VariableNames);
    fields = fieldnames(meta);
    for ii = 1:numel(fields)
        f = fields{ii};
        if any(names == string(f))
            v = double(T.(f));
            meta.(f)(1:min(N, numel(v))) = v(1:min(N, numel(v)));
        end
    end
end
missing = ~isfinite(meta.PRB) | ~isfinite(meta.Port) | ~isfinite(meta.Subcarrier) | ~isfinite(meta.Symbol);
if any(missing)
    [subcarrier, symbol, port] = localIndexCoordinatesFromExtracted(T, srsCfg, N);
    meta.Subcarrier(missing) = subcarrier(missing);
    meta.Symbol(missing) = symbol(missing);
    meta.Port(missing) = port(missing);
    meta.PRB(missing) = floor(subcarrier(missing) / 12);
end
end

function [subcarrier, symbol, port] = localIndexCoordinatesFromExtracted(T, srsCfg, N)
subcarrier = NaN(N, 1);
symbol = NaN(N, 1);
port = NaN(N, 1);
if ~istable(T) || ~ismember("LinearIndex", string(T.Properties.VariableNames))
    return;
end
idx = double(T.LinearIndex(:));
idx = idx(1:min(N, numel(idx)));
K = double(srsCfg.ToolboxCarrier.NSizeGrid) * 12;
L = double(srsCfg.ToolboxCarrier.SymbolsPerSlot);
P = max(1, round(double(srsCfg.NumSRSPorts)));
if isempty(idx) || ~(isfinite(K) && K > 0 && isfinite(L) && L > 0)
    return;
end
try
    [k, l, p] = ind2sub([K L P], idx);
    n = numel(k);
    subcarrier(1:n) = double(k(:) - 1);
    symbol(1:n) = double(l(:) - 1);
    port(1:n) = double(p(:) - 1);
catch
end
end

function hOut = localApplyConfiguredEstimator(hLS, meta, srsCfg)
hOut = hLS;
if isempty(hLS)
    return;
end
if localMMSEEnabled(srsCfg)
    hOut = localWienerSmoothByPortSymbol(hOut, meta, localOddWindow(sixgr.util.structGet(srsCfg, "MMSEFrequencySmoothingBins", 1)));
end
if localDFTEnabled(srsCfg)
    hOut = localDFTDenoiseByPortSlot(hOut, meta, localDFTKeepCount(srsCfg, sum(isfinite(real(hOut)) & isfinite(imag(hOut)))));
end
end

function tf = localMMSEEnabled(srsCfg)
alg = lower(strtrim(string(sixgr.util.structGet(srsCfg, "ChannelEstimatorAlgorithm", ""))));
interp = lower(strtrim(string(sixgr.util.structGet(srsCfg, "ChannelEstimatorInterpolation", ""))));
tf = contains(alg, "mmse") || contains(alg, "wiener") || contains(interp, "mmse");
end

function tf = localDFTEnabled(srsCfg)
alg = lower(strtrim(string(sixgr.util.structGet(srsCfg, "ChannelEstimatorAlgorithm", ""))));
tf = contains(alg, "dft");
end

function name = localEstimatorName(srsCfg)
if localDFTEnabled(srsCfg) && localMMSEEnabled(srsCfg)
    name = "srs_ls_wiener_frequency_smoothing_dft_denoising";
elseif localDFTEnabled(srsCfg)
    name = "srs_ls_dft_denoising";
elseif localMMSEEnabled(srsCfg)
    name = "srs_ls_wiener_frequency_smoothing";
else
    name = "srs_ls_per_re_per_prb_estimator";
end
end

function win = localOddWindow(raw)
win = max(1, round(double(raw)));
if ~isfinite(win)
    win = 1;
end
if mod(win, 2) == 0
    win = win + 1;
end
end

function keep = localDFTKeepCount(srsCfg, n)
keep = max(1, round(double(sixgr.util.structGet(srsCfg, "DFTDelayTapKeepCount", 1))));
if ~isfinite(keep)
    keep = 1;
end
if nargin >= 2 && isfinite(double(n)) && double(n) > 0
    keep = min(keep, max(1, round(double(n))));
end
end

function hOut = localWienerSmoothByPortSymbol(hIn, meta, win)
hOut = hIn;
keys = localGroupKeys(meta.Port, meta.Symbol);
u = unique(keys(keys ~= ""), "stable");
for ii = 1:numel(u)
    mask = keys == u(ii) & isfinite(real(hIn)) & isfinite(imag(hIn));
    idx = find(mask);
    if numel(idx) < 3 || win <= 1
        continue;
    end
    [~, order] = sort(meta.Subcarrier(idx));
    idx = idx(order);
    x = hIn(idx);
    localMean = localMovingComplexMean(x, win);
    localVar = localMovingRealMean(abs(x - localMean).^2, win);
    noiseVar = median(localVar(isfinite(localVar)), "omitnan");
    if ~(isfinite(noiseVar) && noiseVar >= 0)
        noiseVar = 0;
    end
    gain = max(localVar - noiseVar, 0) ./ max(localVar, eps);
    gain(~isfinite(gain)) = 0;
    hOut(idx) = localMean + gain .* (x - localMean);
end
end

function hOut = localDFTDenoiseByPortSlot(hIn, meta, keep)
hOut = hIn;
keys = localGroupKeys(meta.Port, meta.Slot);
u = unique(keys(keys ~= ""), "stable");
for ii = 1:numel(u)
    mask = keys == u(ii) & isfinite(real(hIn)) & isfinite(imag(hIn));
    idx = find(mask);
    if numel(idx) < 4
        continue;
    end
    [~, order] = sortrows([meta.Symbol(idx), meta.Subcarrier(idx)]);
    idx = idx(order);
    x = hIn(idx);
    hDelay = ifft(x);
    tapCount = min(max(1, keep), numel(hDelay));
    keepMask = false(size(hDelay));
    keepMask(1:tapCount) = true;
    hDelay(~keepMask) = 0;
    hOut(idx) = fft(hDelay);
end
end

function keys = localGroupKeys(a, b)
a = double(a(:));
b = double(b(:));
keys = strings(size(a));
mask = isfinite(a) & isfinite(b);
keys(mask) = string(a(mask)) + "_" + string(b(mask));
end

function y = localMovingComplexMean(x, win)
y = complex(localMovingRealMean(real(x), win), localMovingRealMean(imag(x), win));
end

function y = localMovingRealMean(x, win)
x = double(x(:));
N = numel(x);
y = NaN(N, 1);
half = floor(max(1, win) / 2);
for ii = 1:N
    lo = max(1, ii - half);
    hi = min(N, ii + half);
    y(ii) = mean(x(lo:hi), "omitnan");
end
end

function [hPRB, rows] = localPerPRBEstimates(hEst, hLS, meta, srsCfg)
rows = repmat(localPRBRow(), 0, 1);
valid = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(meta.PRB) & isfinite(meta.Port);
if ~any(valid)
    hPRB = complex([]);
    return;
end
keys = localGroupKeys(meta.Port, meta.PRB);
u = unique(keys(valid), "stable");
hPRB = complex(NaN(numel(u), 1));
for ii = 1:numel(u)
    mask = keys == u(ii) & valid;
    x = hEst(mask);
    ls = hLS(mask);
    row = localPRBRow();
    row.RunId = string(srsCfg.RunId);
    row.ResourceId = double(srsCfg.ResourceId);
    row.Port = localFirstFinite(meta.Port(mask));
    row.PRB = localFirstFinite(meta.PRB(mask));
    row.NumRE = double(sum(mask));
    row.EstimateI = double(real(mean(x, "omitnan")));
    row.EstimateQ = double(imag(mean(x, "omitnan")));
    row.ResidualPower = double(mean(abs(ls - mean(x, "omitnan")).^2, "omitnan"));
    row.SignalPower = double(mean(abs(x).^2, "omitnan"));
    row.EstimateAvailable = isfinite(row.EstimateI) && isfinite(row.EstimateQ);
    row.ConfigHash = string(srsCfg.ConfigHash);
    row.TruthStatus = "real_lls_evidence";
    rows(end+1, 1) = row; %#ok<AGROW>
    hPRB(ii) = complex(row.EstimateI, row.EstimateQ);
end
end

function [hPort, rows] = localPerPortEstimates(hEst, hLS, meta, srsCfg)
rows = repmat(localPortRow(), 0, 1);
valid = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(meta.Port);
if ~any(valid)
    hPort = complex([]);
    return;
end
ports = unique(meta.Port(valid), "stable");
hPort = complex(NaN(numel(ports), 1));
for ii = 1:numel(ports)
    mask = meta.Port == ports(ii) & valid;
    x = hEst(mask);
    ls = hLS(mask);
    row = localPortRow();
    row.RunId = string(srsCfg.RunId);
    row.ResourceId = double(srsCfg.ResourceId);
    row.Port = double(ports(ii));
    row.NumRE = double(sum(mask));
    row.NumPRB = double(numel(unique(meta.PRB(mask & isfinite(meta.PRB)))));
    row.EstimateI = double(real(mean(x, "omitnan")));
    row.EstimateQ = double(imag(mean(x, "omitnan")));
    row.ResidualPower = double(mean(abs(ls - mean(x, "omitnan")).^2, "omitnan"));
    row.SignalPower = double(mean(abs(x).^2, "omitnan"));
    row.EstimateAvailable = isfinite(row.EstimateI) && isfinite(row.EstimateQ);
    row.ConfigHash = string(srsCfg.ConfigHash);
    row.TruthStatus = "real_lls_evidence";
    rows(end+1, 1) = row; %#ok<AGROW>
    hPort(ii) = complex(row.EstimateI, row.EstimateQ);
end
end

function [nmseDb, sinrDb, noiseVar, residualPower, signalPower] = localMeasuredResidualMetrics(hLS, hEst)
nmseDb = NaN;
sinrDb = NaN;
noiseVar = NaN;
residualPower = NaN;
signalPower = NaN;
if isempty(hLS) || isempty(hEst)
    return;
end
N = min(numel(hLS), numel(hEst));
hLS = hLS(1:N);
hEst = hEst(1:N);
mask = isfinite(real(hLS)) & isfinite(imag(hLS)) & isfinite(real(hEst)) & isfinite(imag(hEst));
if ~any(mask)
    return;
end
err = hLS(mask) - hEst(mask);
residualPower = mean(abs(err).^2, "omitnan");
signalPower = mean(abs(hEst(mask)).^2, "omitnan");
noiseVar = residualPower;
nmse = residualPower / max(signalPower, eps);
nmseDb = 10 * log10(max(nmse, eps));
sinrDb = 10 * log10(max(signalPower / max(residualPower, eps), eps));
end

function estimate = localEstimateRITPMI(hEst, meta, noiseVar, srsCfg)
Hgrid = localHestGrid(hEst, meta, srsCfg);
cfg = sixgr.util.structGet(srsCfg, "BaseConfig", struct());
estimate = sixgr.phy.ul.estimateSRSRITPMI(Hgrid, max(double(noiseVar), eps), cfg);
end

function Hgrid = localHestGrid(hEst, meta, srsCfg)
P = max(1, round(double(srsCfg.NumSRSPorts)));
Hgrid = complex(NaN(1, P));
valid = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(meta.Port);
for port = 0:(P - 1)
    mask = valid & round(double(meta.Port)) == port;
    if any(mask)
        Hgrid(1, port + 1) = mean(hEst(mask), "omitnan");
    end
end
end

function v = localFirstFinite(x)
v = NaN;
x = double(x(:));
x = x(isfinite(x));
if ~isempty(x)
    v = double(x(1));
end
end

function row = localPRBRow()
row = struct("RunId", "", "TrialId", NaN, "TrialType", "", "ResourceId", NaN, ...
    "Port", NaN, "PRB", NaN, "NumRE", NaN, "EstimateI", NaN, "EstimateQ", NaN, ...
    "ResidualPower", NaN, "SignalPower", NaN, "EstimateAvailable", false, ...
    "ConfigHash", "", "TruthStatus", "");
end

function row = localPortRow()
row = struct("RunId", "", "TrialId", NaN, "TrialType", "", "ResourceId", NaN, ...
    "Port", NaN, "NumRE", NaN, "NumPRB", NaN, "EstimateI", NaN, "EstimateQ", NaN, ...
    "ResidualPower", NaN, "SignalPower", NaN, "EstimateAvailable", false, ...
    "ConfigHash", "", "TruthStatus", "");
end

function T = localRowsToTable(rows, emptyRow)
if isempty(rows)
    T = struct2table(repmat(emptyRow, 0, 1));
else
    T = struct2table(rows, "AsArray", true);
end
end
