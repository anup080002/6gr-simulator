function [Rint, info, covarianceState] = estimateInterferenceCovarianceIRC(rxGrid, hEst, refInd, refSym, nVar, varargin)
%ESTIMATEINTERFERENCECOVARIANCEIRC Estimate IRC covariance from pilot residuals.
%
%   RINT = sixgr.phy.rx.estimateInterferenceCovarianceIRC(...) computes a
%   receive-antenna covariance matrix from DM-RS/PT-RS residuals:
%       e_k = y_k - H_k * pinv(H_k) * y_k
%       R   = E[e_k e_k'] + nVar I
%   The output is measured receiver evidence and is not a configured
%   interference shortcut.

ip = inputParser;
ip.addParameter("MinSamples",8,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("AgeSlots",0,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("MaxAgeSlots",8,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("PRGID",0,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("ShrinkageFactor",0.05,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
ip.addParameter("Slot",0,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x==round(x));
ip.addParameter("CovarianceID","cov-dmrs-0",@(x)ischar(x)||isstring(x));
ip.addParameter("SourceResource","DMRS_RESIDUAL",@(x)ischar(x)||isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

info = struct('Available', false, 'Method', 'pilot_residual_covariance', ...
    'Source', 'dmrs_pilot_residual_runtime_evidence', 'Status', 'unavailable', ...
    'NRE', 0, 'SampleCount', 0, 'MinSamples', double(opt.MinSamples), ...
    'AgeSlots', double(opt.AgeSlots), 'MaxAgeSlots', double(opt.MaxAgeSlots), ...
    'PRGID', double(opt.PRGID), 'ShrinkageMethod', 'diagonal_target', ...
    'ShrinkageFactor', double(opt.ShrinkageFactor), ...
    'HermitianError', NaN, 'MinEigenvalue', NaN, ...
    'ConditionNumber', NaN, 'Valid', false, 'NAReason', "");

nr = max(1, localNumRx(rxGrid));
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar >= 0)
    nVar = 0;
end
Rint = [];
covarianceState = [];

if isempty(rxGrid) || isempty(hEst) || isempty(refInd) || isempty(refSym)
    info.NAReason = "missing_grid_channel_or_pilots";
    return;
end

try
    [rxP, hP] = localExtractPilotResources(rxGrid, hEst, refInd);
    if isempty(rxP) || isempty(hP)
        info.NAReason = "no_reference_resources_extracted";
        return;
    end
    if isvector(rxP)
        rxP = rxP(:);
    end
    nP = size(rxP, 1);
    Rsum = zeros(nr, nr);
    used = 0;
    for k = 1:nP
        rk = squeeze(rxP(k, :)).';
        hk = squeeze(hP(k, :, :));
        if isempty(rk) || isempty(hk)
            continue;
        end
        rk = rk(:);
        if size(hk, 1) ~= numel(rk) && size(hk, 2) == numel(rk)
            hk = hk.';
        end
        if size(hk, 1) ~= numel(rk)
            continue;
        end
        proj = hk * (pinv(hk) * rk);
        ek = rk - proj;
        if numel(ek) ~= nr
            continue;
        end
        Rsum = Rsum + ek * ek';
        used = used + 1;
    end
    info.NRE = double(used);
    info.SampleCount = double(used);
    if used < double(opt.MinSamples)
        info.NAReason = "insufficient_covariance_samples";
        info.Status = "INSUFFICIENT_SAMPLES";
        return;
    end
    if double(opt.AgeSlots) > double(opt.MaxAgeSlots)
        info.NAReason = "stale_covariance";
        info.Status = "STALE";
        return;
    end
    Rk = Rsum ./ used;
    target = trace(Rk)/nr*eye(nr);
    alpha = double(opt.ShrinkageFactor);
    Rk = (1-alpha)*Rk + alpha*target + nVar.*eye(nr);
    Rcandidate = (Rk + Rk') ./ 2;
    hermitianError = norm(Rcandidate-Rcandidate',"fro") / ...
        max(norm(Rcandidate,"fro"),realmin);
    eigValues = real(eig(Rcandidate));
    condition = cond(Rcandidate);
    info.HermitianError = double(hermitianError);
    info.MinEigenvalue = double(min(eigValues));
    info.ConditionNumber = double(condition);
    if hermitianError > 1e-12 || min(eigValues) < -1e-10*max(1,abs(trace(Rcandidate)))
        info.NAReason = "invalid_covariance_psd";
        info.Status = "INVALID_PSD";
        return;
    end
    if ~isfinite(condition) || condition > 1e12
        info.NAReason = "ill_conditioned_covariance";
        info.Status = "ILL_CONDITIONED";
        return;
    end
    Rint = Rcandidate;
    covarianceState = sixgr.phy.mimo.InterferenceCovarianceState(Rcandidate, ...
        CovarianceID=string(opt.CovarianceID), ...
        SampleCount=used,MinSamples=double(opt.MinSamples), ...
        Slot=double(opt.Slot),MaxAgeSlots=double(opt.MaxAgeSlots), ...
        PRGID=double(opt.PRGID), ...
        SourceResource=string(opt.SourceResource), ...
        ShrinkageFactor=double(opt.ShrinkageFactor), ...
        ApplyShrinkage=false,IncludesNoise=true);
    info.Available = true;
    info.Valid = true;
    info.Status = "OK";
    info.NAReason = "";
    info.CovarianceID = covarianceState.CovarianceID;
    info.CovarianceState = covarianceState;
    info.CovarianceIncludesNoise = true;
catch ME
    info.NAReason = string(ME.identifier);
    covarianceState = [];
end
end

function [rxP, hP] = localExtractPilotResources(rxGrid, hEst, refInd)
gridSize = size(rxGrid);
K = gridSize(1);
L = gridSize(2);
Nr = localNumRx(rxGrid);

baseInd = double(refInd(:));
baseInd = baseInd(isfinite(baseInd) & baseInd >= 1);
baseSpan = max(1, K * L);
baseInd = mod(round(baseInd) - 1, baseSpan) + 1;
baseInd = unique(baseInd, "stable");
if isempty(baseInd)
    rxP = [];
    hP = [];
    return;
end

nP = numel(baseInd);
rxP = complex(zeros(nP, Nr));
for r = 1:Nr
    plane = rxGrid(:, :, r);
    rxP(:, r) = plane(baseInd);
end

hSize = size(hEst);
if numel(hSize) < 4
    if numel(hSize) >= 3 && Nr == 1
        Nt = hSize(3);
        hP = complex(zeros(nP, Nr, Nt));
        for t = 1:Nt
            plane = hEst(:, :, t);
            hP(:, 1, t) = plane(baseInd);
        end
    else
        Nt = 1;
        hP = complex(zeros(nP, Nr, Nt));
        for r = 1:Nr
            if numel(hSize) >= 3
                plane = hEst(:, :, min(r, hSize(3)));
            else
                plane = hEst(:, :);
            end
            hP(:, r, 1) = plane(baseInd);
        end
    end
    return;
end

Nt = hSize(4);
hP = complex(zeros(nP, Nr, Nt));
for r = 1:Nr
    for t = 1:Nt
        plane = hEst(:, :, min(r, hSize(3)), t);
        hP(:, r, t) = plane(baseInd);
    end
end
end

function n = localNumRx(rxGrid)
sz = size(rxGrid);
if numel(sz) >= 3
    n = sz(3);
else
    n = 1;
end
n = max(1, double(n));
end
