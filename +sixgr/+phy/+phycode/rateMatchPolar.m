function [out, info] = rateMatchPolar(in, K, E, iBIL, varargin)
%RATEMATCHPOLAR Wrapper around nrRateMatchPolar (5G Toolbox).
%
%   [OUT,INFO] = sixgr.phy.phycode.rateMatchPolar(IN,K,E,IBIL,Name,Value,...)
%
%   IN   : polar-encoded bits (0/1) before rate matching (column or row)
%   K    : number of information bits (including CRC bits) used in polar coding
%   E    : desired number of rate matched bits
%   iBIL : coded bit interleaver flag (0 or 1)
%
%   Name-Value pairs:
%     "NMax" : maximum polar code exponent (optional; only used by some releases)
%
%   OUT  : rate matched bits (0/1) length E

nMax = []; % optional
nv = varargin;
if mod(numel(nv),2) ~= 0
    error("sixgr:rateMatchPolar:NV", "Name-value inputs must come in pairs.");
end
for ii = 1:2:numel(nv)
    key = lower(string(nv{ii}));
    val = nv{ii+1};
    switch key
        case {"nmax","n_max"}
            nMax = double(val);
        otherwise
            error("sixgr:rateMatchPolar:UnknownNV", "Unknown name-value: %s", char(nv{ii}));
    end
end

x = in(:);
% Force binary logical for toolbox functions
if ~islogical(x)
    x = logical(x ~= 0);
end

K = double(K);
E = double(E);
iBIL = double(iBIL);

info = struct();
info.K = K;
info.E = E;
info.iBIL = iBIL;
info.NMax = nMax;

out = [];
try
    if isempty(nMax)
        out = nrRateMatchPolar(x, K, E, iBIL);
        info.API = "nrRateMatchPolar(in,K,E,iBIL)";
    else
        out = nrRateMatchPolar(x, K, E, iBIL, nMax);
        info.API = "nrRateMatchPolar(in,K,E,iBIL,nMax)";
    end
catch
    % Some releases may not support nMax argument
    out = nrRateMatchPolar(x, K, E, iBIL);
    info.API = "nrRateMatchPolar(in,K,E,iBIL)";
end

out = int8(out(:));
end
