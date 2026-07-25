function out = TBSAndBaseGraphSpec(varargin)
%TBSANDBASEGRAPHSPEC Independent scalar oracle for PDSCH TBS/CRC/BG.
%   This implementation is intentionally free of nr* and production calls.

ip = inputParser;
ip.addParameter("NPRB", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("NScheduledSymbols", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("NDMRSREPerPRB", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("NOverheadREPerPRB", 0, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("Qm", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("TargetCodeRate", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("NumLayers", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("TBScaling", 1, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
x = ip.Results;

nPRB = localInteger(x.NPRB);
if ~(isfinite(nPRB) && nPRB >= 1 && nPRB <= 275)
    localError("NPRBOutOfRange", "NPRB must be an integer in [1,275].");
end
nSym = localInteger(x.NScheduledSymbols);
if ~(isfinite(nSym) && nSym >= 1 && nSym <= 14)
    localError("SymbolAllocationEmpty", ...
        "NScheduledSymbols must be an integer in [1,14].");
end
nDMRS = localNonnegativeInteger(x.NDMRSREPerPRB, "NDMRSREPerPRB");
nOH = localNonnegativeInteger(x.NOverheadREPerPRB, "NOverheadREPerPRB");
qm = localInteger(x.Qm);
if ~ismember(qm, [2 4 6 8 10])
    localError("UnsupportedQm", "Qm must be one of 2, 4, 6, 8, or 10.");
end
R = double(x.TargetCodeRate);
if ~(isfinite(R) && R > 0 && R <= 1)
    localError("TargetCodeRateOutOfRange", ...
        "TargetCodeRate must be finite in (0,1].");
end
layers = localInteger(x.NumLayers);
if ~(isfinite(layers) && layers >= 1 && layers <= 8)
    localError("NumLayersOutOfRange", "NumLayers must be an integer in [1,8].");
end
scaling = double(x.TBScaling);
if ~(isfinite(scaling) && scaling > 0 && scaling <= 1)
    localError("TBScalingOutOfRange", "TBScaling must be finite in (0,1].");
end

nREPrime = 12 * nSym - nDMRS - nOH;
if nREPrime <= 0
    localError("NegativeDataRE", ...
        "DM-RS and overhead leave no PDSCH data RE in each allocated PRB.");
end
nRE = min(156, nREPrime) * nPRB;
nInfo = scaling * nRE * R * qm * layers;
if ~(isfinite(nInfo) && nInfo > 0)
    localError("NonpositiveNInfo", "The allocation produces no information bits.");
end

if nInfo <= 3824
    n = max(3, floor(log2(nInfo)) - 6);
    nInfoPrime = max(24, 2^n * floor(nInfo / 2^n));
    smallTBS = localSmallTBSTable();
    idx = find(smallTBS >= nInfoPrime, 1);
    tbs = smallTBS(idx);
    cForTBS = 1;
else
    n = floor(log2(nInfo - 24)) - 5;
    nInfoPrime = max(3840, 2^n * localRoundHalfUp((nInfo - 24) / 2^n));
    if R <= 0.25
        cForTBS = ceil((nInfoPrime + 24) / 3816);
    elseif nInfoPrime > 8424
        cForTBS = ceil((nInfoPrime + 24) / 8424);
    else
        cForTBS = 1;
    end
    tbs = 8 * cForTBS * ceil((nInfoPrime + 24) / (8 * cForTBS)) - 24;
end

if tbs > 3824
    crcType = "24A";
    crcLength = 24;
else
    crcType = "16";
    crcLength = 16;
end
if tbs <= 292 || (tbs <= 3824 && R <= 0.67) || R <= 0.25
    baseGraph = 2;
else
    baseGraph = 1;
end

out = struct( ...
    "ContractVersion", "IndependentPDSCHTBSSpec/v1", ...
    "NREPrimePerPRB", nREPrime, ...
    "NRE", nRE, ...
    "NInfo", nInfo, ...
    "NInfoPrime", nInfoPrime, ...
    "CForTBS", cForTBS, ...
    "TBS", tbs, ...
    "TBCRCType", char(crcType), ...
    "TBCRCLength", crcLength, ...
    "BaseGraph", baseGraph, ...
    "Source", "independent_ts_38_214_and_ts_38_212_scalar_oracle");
end

function value = localInteger(value)
value = double(value);
if ~(isscalar(value) && isfinite(value) && abs(value - round(value)) < 1e-9)
    value = NaN;
else
    value = round(value);
end
end

function value = localNonnegativeInteger(value, name)
value = localInteger(value);
if ~(isfinite(value) && value >= 0)
    localError("BadInteger", "%s must be a non-negative integer.", name);
end
end

function value = localRoundHalfUp(value)
value = floor(value + 0.5);
end

function values = localSmallTBSTable()
values = [ ...
    24 32 40 48 56 64 72 80 88 96 104 112 120 128 136 144 152 160 168 176 ...
    184 192 208 224 240 256 272 288 304 320 336 352 368 384 408 432 456 480 ...
    504 528 552 576 608 640 672 704 736 768 808 848 888 928 984 1032 1064 ...
    1128 1160 1192 1224 1256 1288 1320 1352 1416 1480 1544 1608 1672 1736 ...
    1800 1864 1928 2024 2088 2152 2216 2280 2408 2472 2536 2600 2664 2728 ...
    2792 2856 2976 3104 3240 3368 3496 3624 3752 3824];
end

function localError(token, message, varargin)
error("sixgr:pdsch:oracle:" + string(token), message, varargin{:});
end
