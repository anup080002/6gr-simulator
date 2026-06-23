function [W_opt, pmi_i1, pmi_i2, info] = selectPMI(H_wb, rankValue, nTx, nRx, cfg)
%SELECTPMI Select a wideband PMI/codebook precoder from measured channel H.
%
% The search criterion is max ||H*W||_F^2 over deterministic Type-I-style
% DFT candidates. PMI values are zero-based for exported evidence.

if nargin < 5 || ~isstruct(cfg)
    cfg = struct();
end
H = localOrientChannel(H_wb, nTx);
nTx = size(H, 2);
nRx = size(H, 1);
rankValue = max(1, min(round(double(rankValue)), min(nTx, nRx)));

[W1, W2, cbInfo] = localCandidateCodebook(nTx, cfg);
if rankValue == 1
    gains = sum(abs(H * W1).^2, 1);
    [bestGain, bestIdx] = max(gains);
    W_opt = W1(:, bestIdx);
    [l1, l2] = localDecodePMI(bestIdx, cbInfo.NumHorizontalBeams, cbInfo.NumVerticalBeams);
    pmi_i1 = [l1, l2];
    pmi_i2 = NaN;
else
    nCand = size(W2, 3);
    gains = NaN(nCand, 1);
    for ii = 1:nCand
        gains(ii) = norm(H * W2(:, :, ii), "fro")^2;
    end
    [bestGain, bestIdx] = max(gains);
    W_opt = W2(:, :, bestIdx);
    beamIdx = floor((bestIdx - 1) / 4) + 1;
    pmi_i2 = mod(bestIdx - 1, 4);
    [l1, l2] = localDecodePMI(beamIdx, cbInfo.NumHorizontalBeams, cbInfo.NumVerticalBeams);
    pmi_i1 = [l1, l2];
end

info = cbInfo;
info.Rank = double(rankValue);
info.NumRx = double(nRx);
info.NumTx = double(nTx);
info.SelectedGain = double(bestGain);
info.SelectedPMI_i1 = double(pmi_i1);
info.SelectedPMI_i2 = double(pmi_i2);
info.SelectionMetric = "max_norm_H_times_W_frobenius";
end

function H = localOrientChannel(Hin, nTx)
H = Hin;
if isempty(H)
    error("sixgr:mimo:selectPMI:EmptyChannel", "PMI selection requires a non-empty channel matrix.");
end
if ndims(H) == 3
    H = mean(H, 3, "omitnan");
end
if ~ismatrix(H)
    error("sixgr:mimo:selectPMI:BadChannelShape", "H_wb must be a matrix or nRx-by-nTx-by-nSubcarrier array.");
end
if nargin >= 2 && ~isempty(nTx) && isnumeric(nTx) && isfinite(double(nTx))
    nTx = round(double(nTx));
    if size(H, 2) ~= nTx && size(H, 1) == nTx
        H = H.';
    end
end
end

function [W1, W2, info] = localCandidateCodebook(nTx, cfg)
N1 = round(localNumericCfg(cfg, ["N1","mimo.N1"], NaN));
N2 = round(localNumericCfg(cfg, ["N2","mimo.N2"], NaN));
O1 = round(localNumericCfg(cfg, ["O1","mimo.O1"], 4));
O2 = round(localNumericCfg(cfg, ["O2","mimo.O2"], 4));
if ~(isfinite(N1) && isfinite(N2) && N1 >= 1 && N2 >= 1 && N1 * N2 == nTx)
    N1 = max(1, floor(sqrt(double(nTx))));
    while mod(nTx, N1) ~= 0 && N1 > 1
        N1 = N1 - 1;
    end
    N2 = max(1, nTx / N1);
end

function value = localNumericCfg(cfg, paths, defaultValue)
value = defaultValue;
for p = string(paths)
    raw = sixgr.util.structGet(cfg, p, []);
    if isempty(raw)
        continue;
    end
    if isnumeric(raw) || islogical(raw)
        vals = double(raw(:));
    else
        vals = str2double(string(raw(:)));
    end
    idx = find(isfinite(vals), 1);
    if ~isempty(idx)
        value = vals(idx);
        return;
    end
end
end
[W1, W2, info] = sixgr.mimo.buildNRCodebook(N1, N2, O1, O2);
info.NumHorizontalBeams = double(N1 * O1);
info.NumVerticalBeams = double(N2 * O2);
end

function [l1, l2] = localDecodePMI(idx, nH, nV)
idx0 = max(0, round(double(idx)) - 1);
l1 = floor(idx0 / nV);
l2 = mod(idx0, nV);
l1 = mod(l1, nH);
end
