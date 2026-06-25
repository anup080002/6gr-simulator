function layout = resolveCodingLayout(varargin)
%RESOLVECODINGLAYOUT Canonical CRC/LDPC/rate-match layout producer.
%   Produces the immutable coding contract shared by TX, RX and HARQ. The
%   rate-match map is derived by applying nrRateMatchLDPC to numeric labels,
%   so the map follows the same Toolbox path as the coded bits.

ip = inputParser;
ip.addParameter("Direction", "DL", @(x) ischar(x) || isstring(x));
ip.addParameter("TransportBlockSize", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("TargetCodeRate", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("RV", 0, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("Modulation", "QPSK", @(x) ischar(x) || isstring(x));
ip.addParameter("NumLayers", 1, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("RateMatchedBitCount", [], @(x) isnumeric(x) && isscalar(x));
ip.addParameter("Nref", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("TBCRCType", "", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

A = localPositiveInteger(opt.TransportBlockSize, "TransportBlockSize");
R = double(opt.TargetCodeRate);
if ~(isscalar(R) && isfinite(R) && R > 0 && R <= 1)
    error("sixgr:phy:phycode:CodingLayoutBadRate", ...
        "TargetCodeRate must be finite in (0,1].");
end
rv = localNonnegativeInteger(opt.RV, "RV");
if rv > 3
    error("sixgr:phy:phycode:CodingLayoutBadRV", "RV must be in [0,3].");
end
nLayers = localPositiveInteger(opt.NumLayers, "NumLayers");
E = localPositiveInteger(opt.RateMatchedBitCount, "RateMatchedBitCount");
direction = upper(strtrim(string(opt.Direction)));
if ~(direction == "DL" || direction == "UL")
    error("sixgr:phy:phycode:CodingLayoutBadDirection", ...
        "Direction must be DL or UL.");
end
modulation = char(string(opt.Modulation));

tbCRCType = char(string(opt.TBCRCType));
tbCRCLen = 24;
if strlength(string(tbCRCType)) == 0
    if direction == "UL"
        schInfo = nrULSCHInfo(A, R);
    else
        schInfo = nrDLSCHInfo(A, R);
    end
    bgn = double(schInfo.BGN);
    [tbCRCType, tbCRCLen] = localResolveTBCRCSpec(schInfo, '24A', 24);
else
    if direction == "UL"
        schInfo = nrULSCHInfo(A, R);
    else
        schInfo = nrDLSCHInfo(A, R);
    end
    bgn = double(schInfo.BGN);
    tbCRCLen = localCRCPolynomialLength(tbCRCType);
end

zeroTB = int8(zeros(A, 1));
tbCrc = sixgr.phy.tb.attachCRC(zeroTB, tbCRCType);
[cbs, seg] = sixgr.phy.tb.segmentLDPC(tbCrc, bgn);
[codedCB, encInfo] = sixgr.phy.phycode.ldpcEncode(cbs, bgn);
if isempty(opt.Nref)
    [~, rmInfo] = sixgr.phy.phycode.rateMatchLDPC(codedCB, E, rv, modulation, nLayers);
    nrefUsed = [];
else
    nrefUsed = localPositiveInteger(opt.Nref, "Nref");
    [~, rmInfo] = sixgr.phy.phycode.rateMatchLDPC(codedCB, E, rv, modulation, nLayers, nrefUsed);
end

C = size(cbs, 2);
K = size(cbs, 1);
N = size(codedCB, 1);
Zc = localResolveLiftingSize(bgn, K);
fillerMask = cbs < 0;
fillerByCB = cell(1, C);
for c = 1:C
    fillerByCB{c} = uint32(find(fillerMask(:, c)));
end
cbCRCType = "";
cbCRCLen = 0;
if C > 1
    cbCRCType = "24B";
    cbCRCLen = 24;
end

positionMap = rmInfo.PositionMap;
combineSignature = localSignature(struct( ...
    "A", A, "TBCRCType", char(tbCRCType), "BaseGraph", bgn, "C", C, ...
    "K", K, "N", N, "Zc", Zc, "Nref", localNrefToken(nrefUsed)));
rateMatchSignature = localSignature(struct( ...
    "CombineSignature", combineSignature, "E", E, "RV", rv, ...
    "Modulation", modulation, "NumLayers", nLayers));

layout = struct();
layout.ContractVersion = "CodingLayout/v1";
layout.Immutable = true;
layout.Direction = char(direction);
layout.A = uint32(A);
layout.TransportBlockSize = uint32(A);
layout.TBCRCType = char(tbCRCType);
layout.TBCRCLength = uint16(tbCRCLen);
layout.TransportBlockLengthWithCRC = uint32(numel(tbCrc));
layout.B = uint32(numel(tbCrc));
layout.BaseGraph = uint8(bgn);
layout.BGN = uint8(bgn);
layout.NumCodeBlocks = uint16(C);
layout.C = uint16(C);
layout.CodeBlockLength = uint32(K);
layout.K = uint32(K);
layout.MotherCodeLength = uint32(N);
layout.N = uint32(N);
layout.LiftingSize = uint16(Zc);
layout.Zc = uint16(Zc);
layout.FillerPositions = fillerByCB;
layout.FillerCount = uint32(nnz(fillerMask));
layout.CBCRCType = char(cbCRCType);
layout.CBCRCLength = uint16(cbCRCLen);
layout.RV = uint8(rv);
layout.Nref = nrefUsed;
layout.RateMatchedBitCount = uint32(E);
layout.E = uint32(E);
layout.E_r = uint32(rmInfo.EPerCodeBlock(:).');
layout.Modulation = char(modulation);
layout.NumLayers = uint8(nLayers);
layout.NumCodewords = uint8(1);
layout.CircularBufferPositionMap = positionMap;
layout.RateMatchPositionMap = positionMap;
layout.CombineSignature = combineSignature;
layout.RateMatchSignature = rateMatchSignature;
layout.Segmentation = seg;
layout.LDPCEncodeInfo = encInfo;
layout.Source = "sixgr.phy.phycode.resolveCodingLayout";
end

function value = localPositiveInteger(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:phycode:CodingLayoutBadInteger", ...
        "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
end

function value = localNonnegativeInteger(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value >= 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:phycode:CodingLayoutBadInteger", ...
        "%s must be a non-negative integer scalar.", char(string(name)));
end
value = round(value);
end

function [crcType, crcLen] = localResolveTBCRCSpec(schInfo, defaultType, defaultLen)
crcType = defaultType;
crcLen = defaultLen;
if isstruct(schInfo)
    rawType = char(string(sixgr.util.structGet(schInfo, 'CRC', defaultType)));
    if ~isempty(rawType)
        crcType = rawType;
    end
    rawLen = double(sixgr.util.structGet(schInfo, 'L', defaultLen));
    if isfinite(rawLen) && rawLen >= 0
        crcLen = rawLen;
    end
end
end

function n = localCRCPolynomialLength(poly)
token = upper(strrep(char(string(poly)), "CRC", ""));
switch token
    case {"24A","24B","24C"}
        n = 24;
    case "16"
        n = 16;
    case "11"
        n = 11;
    case "6"
        n = 6;
    otherwise
        error("sixgr:phy:phycode:CodingLayoutBadCRC", ...
            "Unsupported CRC polynomial '%s'.", char(string(poly)));
end
end

function zc = localResolveLiftingSize(bgn, K)
if round(double(bgn)) == 1
    denom = 22;
else
    denom = 10;
end
zc = double(K) / denom;
if ~(isfinite(zc) && abs(zc - round(zc)) < 1e-9)
    error("sixgr:phy:phycode:CodingLayoutBadZc", ...
        "Cannot resolve integer lifting size from K=%d BGN=%d.", K, bgn);
end
zc = round(zc);
end

function token = localNrefToken(nref)
if isempty(nref)
    token = "[]";
else
    token = string(double(nref));
end
end

function sig = localSignature(s)
fields = sort(string(fieldnames(s)));
parts = strings(numel(fields), 1);
for i = 1:numel(fields)
    value = s.(char(fields(i)));
    if isnumeric(value) || islogical(value)
        valueText = mat2str(double(value));
    else
        valueText = char(string(value));
    end
    parts(i) = fields(i) + "=" + string(valueText);
end
sig = char(strjoin(parts, "|"));
end
