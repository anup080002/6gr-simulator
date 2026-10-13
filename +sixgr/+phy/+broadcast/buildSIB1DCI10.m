function [dci, pdsch] = buildSIB1DCI10(carrier, cfg, varargin)
%BUILDSIB1DCI10 Build/decode SI-RNTI DCI format 1_0.
%
% The SI-RNTI field set is FDRA/RIV, TDRA index, VRB mapping, MCS, RV,
% system-information indicator and reserved bits. The total monitored DCI
% length is derived from MIB-resolved CORESET0. PRBStart inputs are
% CORESET0-relative; materialized PDSCH PRBSet is carrier-relative.

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
[timeRows, mappingTypes] = localTimeAllocations(carrier, cfg);
frequency = sixgr.phy.broadcast.sib1FrequencyReference(carrier,cfg);
payloadLength = frequency.PayloadLengthBits;
nRB = frequency.NumRB;

if isempty(opt.Bits)
    localMCS(double(opt.MCSIndex));
    validateattributes(opt.RV, {'numeric'}, {'scalar','real','finite','integer','>=',0,'<=',3});
    if isempty(opt.PDSCH)
        row = localTimeRow(timeRows, opt.SymbolStart, opt.NumSymbols);
        opt.MappingType = mappingTypes(row);
        pdsch = localBuildPDSCH(carrier, cfg, opt);
    else
        pdsch = opt.PDSCH;
        row = localTimeRow(timeRows, pdsch.SymbolAllocation(1), pdsch.SymbolAllocation(2));
        if string(pdsch.MappingType) ~= mappingTypes(row)
            error("sixgr:phy:broadcast:InvalidSIB1TDRA", ...
                "SIB1 PDSCH mapping type disagrees with its default-A time allocation.");
        end
    end
    tda = timeRows(row,1);
    rbStartCarrier = min(double(pdsch.PRBSet));
    rbStart = rbStartCarrier-frequency.CarrierRelativeStart;
    rbLen = numel(pdsch.PRBSet);
    if isempty(pdsch.PRBSet) || ~isequal(double(pdsch.PRBSet(:).'),rbStartCarrier+(0:rbLen-1))
        error("sixgr:phy:broadcast:SIB1AllocationOutsideBWP", ...
            "SIB1 DCI format 1_0 requires a nonempty contiguous PRB allocation.");
    end
    riv = localEncodeRIV(nRB, rbStart, rbLen);
    bits = [];
    rivWidth = localRIVWidth(nRB);
    bits = localAppendUInt(bits, riv, rivWidth);
    bits = localAppendUInt(bits, tda, 4);
    bits = localAppendUInt(bits, double(pdsch.VRBToPRBInterleaving), 1);
    bits = localAppendUInt(bits, round(double(opt.MCSIndex)), 5);
    bits = localAppendUInt(bits, round(double(opt.RV)), 2);
    bits = localAppendUInt(bits, 0, 1); % SI indicator: SIB1
    while numel(bits) < payloadLength
        bits = localAppendUInt(bits, 0, 1); %#ok<AGROW>
    end
    bits = bits(1:payloadLength);
else
    if ~isvector(opt.Bits) || any(~isfinite(opt.Bits(:)) | ...
            (opt.Bits(:) ~= 0 & opt.Bits(:) ~= 1))
        error("sixgr:phy:broadcast:InvalidSIB1DCIBits", ...
            "SIB1 DCI must be a binary vector; values cannot be rounded into bits.");
    end
    bits = int8(opt.Bits(:)).';
    if numel(bits) ~= payloadLength
        error("sixgr:phy:pdcch:payload_length_mismatch", ...
            "SI-RNTI DCI 1_0 requires %d bits for CORESET0 size %d; received %d.", ...
            payloadLength, nRB, numel(bits));
    end
    [riv, pos] = localReadUInt(bits, 1, localRIVWidth(nRB));
    [tda, pos] = localReadUInt(bits, pos, 4);
    [vrb, pos] = localReadUInt(bits, pos, 1);
    [mcs, pos] = localReadUInt(bits, pos, 5);
    [rv, pos] = localReadUInt(bits, pos, 2);
    [si, ~] = localReadUInt(bits, pos, 1);
    if si ~= 0
        error("sixgr:phy:broadcast:UnsupportedSIIndicator", ...
            "SIB1 reception requires the SIB1 system-information indicator.");
    end
    localMCS(mcs);
    [rbLen, rbStart] = localDecodeRIV(nRB, riv);
    row = tda + 1;
    pdsch = localBuildPDSCH(carrier, cfg, struct( ...
        "PRBStart", rbStart, "PRBCount", rbLen, ...
        "SymbolStart", timeRows(row,2), "NumSymbols", timeRows(row,3), ...
        "MappingType", mappingTypes(row), ...
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
    "PayloadSizeSource", frequency.Source, ...
    "FrequencyReference", frequency, ...
    "PRBStartBWPRelative", double(min(pdsch.PRBSet))-frequency.CarrierRelativeStart, ...
    "RIV", localEncodeRIV(nRB, min(double(pdsch.PRBSet))-frequency.CarrierRelativeStart, numel(pdsch.PRBSet)), ...
    "TDRAIndex", double(tda), ...
    "TimeAllocationSource", "TS38.214_5.1.2.1.1_default_A_normal_CP", ...
    "MappingType", string(pdsch.MappingType), ...
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
prbStart = double(opt.PRBStart);
prbCount = double(opt.PRBCount);
frequency = sixgr.phy.broadcast.sib1FrequencyReference(carrier,cfg);
localEncodeRIV(frequency.NumRB, prbStart, prbCount);
pdsch.PRBSet = frequency.CarrierRelativeStart + prbStart + (0:prbCount-1);
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
    pdsch.MappingType = opt.MappingType;
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
% SIB1 is common SI-RNTI PDSCH and has its own higher-layer resource
% authority.  It must not inherit UE-dedicated data-PDSCH PT-RS merely
% because PT-RS is enabled for connected traffic in the same scenario.
% The explicit SIB1 setting remains YAML/config driven; absence retains the
% NR common-channel default (disabled).
ptrsEnabled = sixgr.util.structGet(cfg, ...
    "initial_access.sib1.pdsch.ptrs_enabled", false);
if ~((islogical(ptrsEnabled) || isnumeric(ptrsEnabled)) && ...
        isscalar(ptrsEnabled) && isfinite(double(ptrsEnabled)) && ...
        any(double(ptrsEnabled) == [0 1]))
    error("sixgr:phy:broadcast:InvalidSIB1PTRSConfiguration", ...
        "initial_access.sib1.pdsch.ptrs_enabled must be a scalar boolean.");
end
pdsch.EnablePTRS = logical(ptrsEnabled);
end

function width = localRIVWidth(nRB)
width = ceil(log2(double(nRB) * (double(nRB) + 1) / 2));
end

function riv = localEncodeRIV(nRB, rbStart, rbLen)
if ~(isscalar(rbStart) && isfinite(rbStart) && rbStart==fix(rbStart) && rbStart>=0 && ...
        isscalar(rbLen) && isfinite(rbLen) && rbLen==fix(rbLen) && rbLen>=1 && rbStart+rbLen<=nRB)
    error("sixgr:phy:broadcast:SIB1AllocationOutsideBWP", ...
        "SIB1 PRB start/count must describe an integer allocation inside the initial BWP.");
end
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
if localEncodeRIV(nRB,rbStart,rbLen)~=riv
    error("sixgr:phy:broadcast:SIB1AllocationOutsideBWP", ...
        "Received SIB1 frequency allocation is not a canonical in-BWP RIV.");
end
end

function [rate, modulation] = localMCS(mcs)
% TS 38.214 5.1.3.1: SI-RNTI uses table 1; Qm>2 is not expected.
profile = sixgr.link.resolveMCSProfile("qam64_table1",mcs);
if ~profile.Valid || profile.Qm~=2
    error("sixgr:phy:broadcast:UnsupportedSIB1MCS", ...
        "SIB1 requires a QPSK MCS from TS 38.214 table 1 (indices 0..9); no clamping is permitted.");
end
rate = profile.TargetCodeRate;
modulation = string(profile.Modulation);
end

function [rows,mapping] = localTimeAllocations(carrier,cfg)
% The implemented Type-0 resolver supports multiplexing pattern 1.
% Type0 SI-RNTI selects default A for normal CP (38.214 table 5.1.2.1.1-1).
pattern = double(sixgr.util.structGet(cfg,"phy.sib1.type0MultiplexingPattern",1));
if ~isequal(pattern,1) || string(carrier.CyclicPrefix)~="normal"
    error("sixgr:phy:broadcast:UnsupportedSIB1TimeAllocationTable", ...
        "This SIB1 Type-0 adapter requires multiplexing pattern 1 and normal CP; default B/C is not substituted.");
end
dmrs = double(sixgr.util.structGet(cfg,"phy.mib.dmrsTypeAPosition",2));
[rows,mapping] = sixgr.phy.pdcch.RARDCIContext.defaultA("normal",dmrs);
end

function row = localTimeRow(rows,symbolStart,numSymbols)
row = find(rows(:,2)==symbolStart & rows(:,3)==numSymbols);
if ~isscalar(row)
    error("sixgr:phy:broadcast:InvalidSIB1TDRA", ...
        "Configured SIB1 start/length must identify one legal default-A row for the MIB dmrs-TypeA-Position.");
end
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
