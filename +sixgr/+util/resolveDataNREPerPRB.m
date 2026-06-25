function [nrePerPRB, gBits] = resolveDataNREPerPRB(info, nPRB, modStr, nLayers)
%RESOLVEDATANREPERPRB Resolve truthful data-bearing RE/PRB from allocation info.
%
% Prefer the Toolbox NREPerPRB for transport-block sizing. G is the
% rate-matched coded-bit budget and can include PTRS/reserved-resource effects;
% it is retained as evidence but must not replace the nrTBS NREPerPRB input.

if nargin < 2
    nPRB = NaN;
end
if nargin < 3
    modStr = "";
end
if nargin < 4
    nLayers = 1;
end

nrePerPRB = NaN;
gBits = NaN;
nPRB = max(double(nPRB), 1);
nLayers = max(double(nLayers), 1);

if isstruct(info) && isfield(info, "ResourceAccounting")
    acct = info.ResourceAccounting;
    nrePerPRB = double(sixgr.util.structGet(acct, "NREPerPRBForTBS", NaN));
    gBits = double(sixgr.util.structGet(acct, "CodedBitCountG", NaN));
    if isfinite(nrePerPRB) && nrePerPRB >= 0
        return;
    end
end
if isstruct(info) && isfield(info, "NREPerPRBForTBS")
    nrePerPRB = double(info.NREPerPRBForTBS);
    gBits = double(sixgr.util.structGet(info, "CodedBitCountG", NaN));
    if isfinite(nrePerPRB) && nrePerPRB >= 0
        return;
    end
end

if isstruct(info) && isfield(info, "IndicesInfo")
    indInfo = info.IndicesInfo;
elseif isstruct(info) && isfield(info, "PUSCHIndicesInfo")
    indInfo = info.PUSCHIndicesInfo;
elseif isstruct(info) && isfield(info, "PDSCHIndicesInfo")
    indInfo = info.PDSCHIndicesInfo;
else
    indInfo = info;
end

if isstruct(indInfo) && isfield(indInfo, "G")
    gBits = double(indInfo.G);
elseif isstruct(info) && isfield(info, "G")
    gBits = double(info.G);
end

if isstruct(indInfo) && isfield(indInfo, "NREPerPRB")
    nrePerPRB = double(indInfo.NREPerPRB);
elseif isstruct(info) && isfield(info, "NREPerPRB")
    nrePerPRB = double(info.NREPerPRB);
elseif isstruct(indInfo) && isfield(indInfo, "NRE")
    nrePerPRB = floor(double(indInfo.NRE) / max(double(nPRB), 1));
elseif isstruct(info) && isfield(info, "NRE")
    nrePerPRB = floor(double(info.NRE) / max(double(nPRB), 1));
end

if isfinite(nrePerPRB) && nrePerPRB >= 0
    return;
end

if ~(isfinite(nrePerPRB) && nrePerPRB >= 0)
    nrePerPRB = NaN;
end
end
