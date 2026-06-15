function [Rint, info] = estimateInterferenceCovarianceIRC(rxGrid, hEst, refInd, refSym, nVar)
%ESTIMATEINTERFERENCECOVARIANCEIRC Estimate IRC covariance from pilot residuals.
%
%   RINT = sixgr.phy.rx.estimateInterferenceCovarianceIRC(...) computes a
%   receive-antenna covariance matrix from DM-RS/PT-RS residuals:
%       e_k = y_k - H_k * pinv(H_k) * y_k
%       R   = E[e_k e_k'] + nVar I
%   The output is measured receiver evidence and is not a configured
%   interference shortcut.

info = struct('Available', false, 'Method', 'pilot_residual_covariance', ...
    'Source', 'dmrs_pilot_residual_runtime_evidence', 'Status', 'unavailable', ...
    'NRE', 0, 'NAReason', "");

nr = max(1, localNumRx(rxGrid));
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar >= 0)
    nVar = 0;
end
Rint = nVar .* eye(nr);

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
    if used < 1
        info.NAReason = "pilot_residuals_empty_after_shape_validation";
        return;
    end
    Rk = Rsum ./ used + nVar .* eye(nr);
    Rint = (Rk + Rk') ./ 2;
    info.Available = true;
    info.Status = "OK";
    info.NRE = double(used);
    info.NAReason = "";
catch ME
    info.NAReason = string(ME.identifier);
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
