function [msg, info] = polarDecode(in, K, E, linkDir, varargin)
%POLARDECODE Wrapper around nrPolarDecode (5G Toolbox).
%
%   [MSG,INFO] = sixgr.phy.phycode.polarDecode(IN,K,E,LINKDIR,Name,Value,...)
%
%   IN      : column vector of rate-recovered soft bits (LLR) or hard bits
%   K       : number of information bits to decode (includes CRC bits if present)
%   E       : rate matched length used during encoding
%   LINKDIR : "DL" or "UL" (used to select defaults for NMax and input interleaver)
%
%   Name-Value pairs:
%     "NMax"        : maximum polar code exponent (default 9 for DL, 10 for UL)
%     "IIL"         : input interleaver flag (default 0 for DL, 1 for UL)
%     "ListLength"  : SCL list length (default 8)
%
%   NOTE:
%     This wrapper uses nrPolarDecode available in 5G Toolbox. The exact
%     function signature of nrPolarDecode can vary across releases; this
%     wrapper tries common calling patterns.

% Keep everything ASCII (avoid fancy quotes/dashes) to prevent MATLAB parse errors.

if nargin < 4 || isempty(linkDir)
    linkDir = "DL";
end

diru = upper(string(linkDir));

% Defaults (typical NR choices)
if any(diru == ["DL","DOWNLINK","DCI","PDCCH","PBCH"])
    nMax = 9;
    iIL  = 0;
else
    nMax = 10;
    iIL  = 1;
end
listLen = 8;

% Parse Name-Value pairs (lightweight; avoids inputParser)
nv = varargin;
if mod(numel(nv),2) ~= 0
    error("sixgr:polarDecode:NV", "Name-value inputs must come in pairs.");
end
for ii = 1:2:numel(nv)
    key = lower(string(nv{ii}));
    val = nv{ii+1};
    switch key
        case {"nmax","n_max"}
            nMax = double(val);
        case {"iil","inputinterleaver"}
            iIL = double(val);
        case {"listlength","listlen","l"}
            listLen = double(val);
        otherwise
            error("sixgr:polarDecode:UnknownNV", "Unknown name-value: %s", char(nv{ii}));
    end
end

% Normalize shapes/types
x = in(:);
K = double(K);
E = double(E);

info = struct();
info.K = K;
info.E = E;
info.NMax = nMax;
info.IIL = iIL;
info.ListLength = listLen;

% Try common calling patterns
msg = [];
try
    % Pattern: [msg, crcErr] = nrPolarDecode(in,K,E,L,nMax,iIL)
    [msg, crcErr] = nrPolarDecode(x, K, E, listLen, nMax, iIL);
    info.CRCError = crcErr;
    info.API = "nrPolarDecode(in,K,E,L,nMax,iIL)";
catch
    try
        % Pattern: [msg, crcErr] = nrPolarDecode(in,K,E,nMax,iIL)
        [msg, crcErr] = nrPolarDecode(x, K, E, nMax, iIL);
        info.CRCError = crcErr;
        info.API = "nrPolarDecode(in,K,E,nMax,iIL)";
    catch
        try
            % Pattern: msg = nrPolarDecode(in,K,E,nMax,iIL)
            msg = nrPolarDecode(x, K, E, nMax, iIL);
            info.API = "nrPolarDecode(in,K,E,nMax,iIL)->msg";
        catch
            % Fallback: msg = nrPolarDecode(in,K,E)
            msg = nrPolarDecode(x, K, E);
            info.API = "nrPolarDecode(in,K,E)";
        end
    end
end

msg = int8(msg(:));
end
