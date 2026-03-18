function [out, info] = rateRecoverPolar(in, K, E, iBIL, varargin)
%RATERECOVERPOLAR Wrapper around nrRateRecoverPolar (5G Toolbox).
%
%   [OUT,INFO] = sixgr.phy.phycode.rateRecoverPolar(IN,K,E,IBIL,Name,Value,...)
%
%   IN   : received rate-matched soft bits (LLR) or hard bits (length E)
%   K    : number of information bits (including CRC bits) used in polar coding
%   E    : number of rate matched bits
%   iBIL : coded bit interleaver flag (0 or 1)
%
%   Name-Value pairs:
%     "NMax" : maximum polar code exponent (optional; only used by some releases)
%
%   OUT  : rate recovered soft bits (typically length N)

nMax = []; % optional
nv = varargin;
if mod(numel(nv),2) ~= 0
    error("sixgr:rateRecoverPolar:NV", "Name-value inputs must come in pairs.");
end
for ii = 1:2:numel(nv)
    key = lower(string(nv{ii}));
    val = nv{ii+1};
    switch key
        case {"nmax","n_max"}
            nMax = double(val);
        otherwise
            error("sixgr:rateRecoverPolar:UnknownNV", "Unknown name-value: %s", char(nv{ii}));
    end
end

x = in(:);
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
        out = nrRateRecoverPolar(x, K, E, iBIL);
        info.API = "nrRateRecoverPolar(in,K,E,iBIL)";
    else
        out = nrRateRecoverPolar(x, K, E, iBIL, nMax);
        info.API = "nrRateRecoverPolar(in,K,E,iBIL,nMax)";
    end
catch
    % Some releases may not support nMax argument
    out = nrRateRecoverPolar(x, K, E, iBIL);
    info.API = "nrRateRecoverPolar(in,K,E,iBIL)";
end

out = out(:);
end
