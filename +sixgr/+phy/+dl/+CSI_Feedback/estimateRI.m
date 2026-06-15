function ri = estimateRI(hEst, cfg, varargin)
%estimateRI Estimate RI from the singular values of a measured channel.
%
% This helper is intentionally narrow: it uses the channel estimate already
% available at the CSI reporting point and does not derive rank from CQI,
% MCS, configured layers, or any scheduler policy.

ip = inputParser;
ip.addParameter("MaxRank", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
ip.parse(varargin{:});
opt = ip.Results;

if nargin < 2 || isempty(cfg)
    cfg = struct();
end

ri = 1;
if isempty(hEst)
    return;
end

Hwb = localWidebandChannelMatrix(hEst);
if isempty(Hwb)
    return;
end

maxRank = opt.MaxRank;
if isempty(maxRank)
    maxRank = min(size(Hwb));
end
if ~(isfinite(double(maxRank)) && double(maxRank) >= 1)
    maxRank = 1;
end
maxRank = max(1, round(double(maxRank)));

sv = svd(double(Hwb));
sv = sv(isfinite(sv) & sv > 0);
if isempty(sv)
    return;
end

threshold_dB = double(sixgr.util.structGet(cfg, "phy.mimo.rankSelectionSVGap_dB", ...
    sixgr.util.structGet(cfg, "phy.csi.rankSelectionSVGap_dB", 3)));
if ~(isfinite(threshold_dB) && threshold_dB >= 0)
    threshold_dB = 3;
end

sv_dB = 20 .* log10(sv ./ max(sv));
ri = sum(sv_dB >= -threshold_dB);
ri = max(1, min(maxRank, ri));
end

function Hwb = localWidebandChannelMatrix(hEst)
Hwb = [];
if isempty(hEst)
    return;
end
H = double(hEst);
if ismatrix(H)
    Hwb = H;
    return;
end
dims = size(H);
if numel(dims) < 3
    return;
end
if numel(dims) == 3
    Hwb = squeeze(mean(H, 1, "omitnan"));
else
    Hwb = squeeze(mean(mean(H, 1, "omitnan"), 2, "omitnan"));
end
if isempty(Hwb) || ~ismatrix(Hwb)
    Hwb = [];
end
end
