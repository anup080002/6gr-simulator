function [dci, pdsch] = buildSIB1DCI10(carrier, cfg, varargin)
%BUILDSIB1DCI10 Build/decode SI-RNTI DCI format 1_0.
%
% The SI-RNTI field set is FDRA/RIV, TDRA index, VRB mapping, MCS, RV,
% system-information indicator and reserved bits. The total monitored DCI
% length is derived from the actual initial DL BWP; it is never fixed.

p = inputParser;
p.addParameter("PDSCH", [], @(x) isempty(x) || isobject(x));
p.addParameter("Bits", [], @(x) isempty(x) || isnumeric(x) || islogical(x));
p.addParameter("MCSIndex", 0, @(x) isnumeric(x) && isscalar(x));
p.addParameter("RV", 0, @(x) isnumeric(x) && isscalar(x));
p.addParameter("PRBStart", 0, @(x) isnumeric(x) && isscalar(x));
p.addParameter("PRBCount", 24, @(x) isnumeric(x) && isscalar(x));
p.addParameter("SymbolStart", 2, @(x) isnumeric(x) && isscalar(x));
p.addParameter("NumSymbols", 12, @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;
[payloadLength, payloadDetails] = ...
    sixgr.phy.pdcch.dciPayloadSizeBits( ...
    double(carrier.NSizeGrid), "1_0");

if isempty(opt.Bits)
    if isempty(opt.PDSCH)
        pdsch = localBuildPDSCH(carrier, cfg, opt);
    else
        pdsch = opt.PDSCH;
    end
    rbStart = min(double(pdsch.PRBSet));
    rbLen = numel(pdsch.PRBSet);
    riv = localEncodeRIV(double(carrier.NSizeGrid), rbStart, rbLen);
    bits = [];
    rivWidth = localRIVWidth(double(carrier.NSizeGrid));
    bits = localAppendUInt(bits, riv, rivWidth);
    bits = localAppendUInt(bits, 0, 4); % TDRA row 0 in the anchor profile
    bits = localAppendUInt(bits, double(pdsch.VRBToPRBInterleaving), 1);
    bits = localAppendUInt(bits, round(double(opt.MCSIndex)), 5);
    bits = localAppendUInt(bits, round(double(opt.RV)), 2);
    bits = localAppendUInt(bits, 0, 1); % SI indicator: SIB1
    while numel(bits) < payloadLength
        bits = localAppendUInt(bits, 0, 1); %#ok<AGROW>
    end
    bits = bits(1:payloadLength);
else
    bits = int8(opt.Bits(:)).';
    if numel(bits) ~= payloadLength
        error("sixgr:phy:pdcch:payload_length_mismatch", ...
            "SI-RNTI DCI 1_0 requires %d bits for initial DL BWP size %d; received %d.", ...
            payloadLength, double(carrier.NSizeGrid), numel(bits));
    end
    [riv, pos] = localReadUInt(bits, 1, localRIVWidth(double(carrier.NSizeGrid)));
    [tda, pos] = localReadUInt(bits, pos, 4);
    [vrb, pos] = localReadUInt(bits, pos, 1);
    [mcs, pos] = localReadUInt(bits, pos, 5);
    [rv, pos] = localReadUInt(bits, pos, 2);
    [si, ~] = localReadUInt(bits, pos, 1);
    [rbLen, rbStart] = localDecodeRIV(double(carrier.NSizeGrid), riv);
    pdsch = localBuildPDSCH(carrier, cfg, struct( ...
        "PRBStart", rbStart, "PRBCount", rbLen, "SymbolStart", 2, "NumSymbols", 12, ...
        "MCSIndex", mcs, "RV", rv));
    try
        pdsch.VRBToPRBInterleaving = logical(vrb);
    catch
    end
    opt.MCSIndex = mcs;
    opt.RV = rv;
end

[targetCodeRate, modulation] = localMCS(double(opt.MCSIndex));
dci = struct( ...
    "Format", "1_0", ...
    "RNTI", 65535, ...
    "RNTIName", "SI-RNTI", ...
    "Bits", int8(bits(:)), ...
    "PayloadHex", sixgr.rrc.asn1.bitsToHex(bits(:)), ...
    "PayloadLengthBits", double(numel(bits)), ...
    "PayloadSizeSource", string(payloadDetails.SizeSource), ...
    "RIV", localEncodeRIV(double(carrier.NSizeGrid), min(double(pdsch.PRBSet)), numel(pdsch.PRBSet)), ...
    "TDRAIndex", 0, ...
    "VRBToPRBInterleaving", localObjectBool(pdsch, "VRBToPRBInterleaving", false), ...
    "MCSIndex", double(opt.MCSIndex), ...
    "Modulation", string(modulation), ...
    "TargetCodeRate", double(targetCodeRate), ...
    "RV", double(opt.RV), ...
    "SIIndicator", 0, ...
    "PRBStart", double(min(pdsch.PRBSet)), ...
    "PRBCount", double(numel(pdsch.PRBSet)), ...
    "SymbolStart", double(pdsch.SymbolAllocation(1)), ...
    "NumSymbols", double(pdsch.SymbolAllocation(2)));
pdsch.Modulation = char(modulation);
pdsch.RNTI = 65535;
try
    pdsch.NID = double(carrier.NCellID);
catch
end

function value = localObjectBool(obj, name, defaultValue)
value = logical(defaultValue);
try
    value = logical(obj.(name));
catch
end
end
end

function pdsch = localBuildPDSCH(carrier, cfg, opt)
pdsch = nrPDSCHConfig;
prbStart = max(0, round(double(sixgr.util.structGet(opt, "PRBStart", 0))));
prbCount = max(1, round(double(sixgr.util.structGet(opt, "PRBCount", 24))));
prbCount = min(prbCount, double(carrier.NSizeGrid) - prbStart);
pdsch.PRBSet = prbStart + (0:prbCount-1);
pdsch.SymbolAllocation = [round(double(sixgr.util.structGet(opt, "SymbolStart", 2))), ...
    round(double(sixgr.util.structGet(opt, "NumSymbols", 12)))];
pdsch.Modulation = "QPSK";
pdsch.NumLayers = 1;
pdsch.RNTI = 65535;
try
    pdsch.NID = double(carrier.NCellID);
catch
end
try
    pdsch.MappingType = "A";
    pdsch.VRBToPRBInterleaving = false;
    pdsch.DMRS.DMRSConfigurationType = 1;
    pdsch.DMRS.DMRSTypeAPosition = double(sixgr.util.structGet(cfg, "phy.mib.dmrsTypeAPosition", 2));
    pdsch.DMRS.DMRSLength = 1;
    pdsch.DMRS.DMRSAdditionalPosition = 0;
    pdsch.DMRS.DMRSPortSet = 0;
    pdsch.DMRS.NumCDMGroupsWithoutData = 2;
    pdsch.DMRS.NIDNSCID = double(carrier.NCellID);
    pdsch.DMRS.NSCID = 0;
catch
end
pdsch.EnablePTRS = false;
end

function width = localRIVWidth(nRB)
width = ceil(log2(double(nRB) * (double(nRB) + 1) / 2));
end

function riv = localEncodeRIV(nRB, rbStart, rbLen)
rbLen = round(double(rbLen));
rbStart = round(double(rbStart));
if rbLen <= floor((nRB + 1) / 2)
    riv = nRB * (rbLen - 1) + rbStart;
else
    riv = nRB * (nRB - rbLen + 1) + (nRB - 1 - rbStart);
end
end

function [rbLen, rbStart] = localDecodeRIV(nRB, riv)
rbLen = floor(double(riv) / nRB) + 1;
rbStart = double(riv) - nRB * (rbLen - 1);
if rbLen > nRB - rbStart
    rbLen = nRB - rbLen + 2;
    rbStart = nRB - 1 - rbStart;
end
end

function [rate, modulation] = localMCS(mcs)
rates = [120 157 193 251 308 379 449 526 602 679 340 378 434 490 553 616 658] / 1024;
mcs = max(0, min(round(double(mcs)), numel(rates)-1));
rate = rates(mcs + 1);
modulation = "QPSK";
end

function bits = localAppendUInt(bits, value, width)
value = round(double(value));
out = zeros(1, width);
for k = 1:width
    out(k) = bitget(uint64(value), width - k + 1);
end
bits = [bits, out]; %#ok<AGROW>
end

function [value, next] = localReadUInt(bits, pos, width)
value = uint64(0);
for k = 1:width
    value = bitshift(value, 1) + uint64(bits(pos + k - 1) ~= 0);
end
value = double(value);
next = pos + width;
end
