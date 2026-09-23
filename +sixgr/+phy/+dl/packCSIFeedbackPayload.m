function payload = packCSIFeedbackPayload(csi, cfg, varargin)
%PACKCSIFEEDBACKPAYLOAD Pack CQI/PMI/RI/CRI into a deterministic CSI payload.
%
% This packer covers the repo-supported wideband CSI subset and exposes the
% exact payload bits, field layout, and hex encoding used by runtime CSI
% reporting. The payload is reconstructable from the saved metadata and the
% deterministic candidate generator in pmiCodebookCandidates().

ip = inputParser;
ip.addParameter("Candidate", struct(), @(x) isempty(x) || (isstruct(x) && isscalar(x)));
ip.addParameter("CodebookInfo", struct(), @(x) isempty(x) || (isstruct(x) && isscalar(x)));
ip.addParameter("MaxRank", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
ip.parse(varargin{:});
opt = ip.Results;

strict = logical(sixgr.util.structGet(cfg,"Strict",false)) || ...
    logical(sixgr.util.structGet(cfg,"mimo.strict",false)) || ...
    logical(sixgr.util.structGet(cfg,"phy.mimo.strict",false));
typedReport = sixgr.util.structGet(csi,"TypedReport",[]);
if strict || ~isempty(typedReport)
    payload = localTypedReportPayload(csi,cfg,typedReport);
    return;
end

reportMode = string(sixgr.util.structGet(csi, "ChannelStateInformationMode", ...
    sixgr.util.structGet(cfg, "phy.csi.channelStateInformationMode", ...
    sixgr.util.structGet(cfg, "phy.csi.feedbackMode", "PMI+CQI+RI"))));
codebookMode = lower(string(sixgr.util.structGet(csi, "PMICodebookMode", ...
    sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "noncodebook"))));
payloadMode = lower(string(sixgr.util.structGet(cfg, "phy.csi.reportPayloadMode", "compressed")));
crcAttached = logical(sixgr.util.structGet(cfg, "phy.csi.crcAttached", false)) ...
    && payloadMode ~= "analog";

numRxAnt = max(1, round(double(sixgr.util.structGet(csi, "NumRxAnt", 1))));
numTxPorts = max(1, round(double(sixgr.util.structGet(csi, "NumTxPorts", 1))));
maxRank = opt.MaxRank;
if isempty(maxRank)
    maxRank = double(sixgr.util.structGet(cfg, "phy.csi.maxRank", min(numRxAnt, numTxPorts)));
end
maxRank = max(1, min([double(maxRank), numRxAnt, numTxPorts]));

orderedTokens = localOrderedReportTokens(reportMode);
fields = localEmptyFieldLayout();
payloadBits = uint8([]);

for i = 1:numel(orderedTokens)
    token = orderedTokens(i);
    switch token
        case "CQI"
            [fields, payloadBits] = localAppendCQI(fields, payloadBits, csi);
        case "RI"
            [fields, payloadBits] = localAppendRI(fields, payloadBits, csi, maxRank);
        case "PMI"
            [fields, payloadBits] = localAppendPMI(fields, payloadBits, csi, codebookMode, opt.Candidate, opt.CodebookInfo);
        case "CRI"
            [fields, payloadBits] = localAppendCRI(fields, payloadBits, csi);
    end
end

if crcAttached
    crcBits = localCRC6(payloadBits);
    [fields, payloadBits] = localAppendField(fields, payloadBits, ...
        "CSI_CRC", "crc", numel(crcBits), NaN, NaN, crcBits);
end

payload = struct();
payload.Enabled = logical(~isempty(payloadBits));
payload.Mode = char(payloadMode);
payload.ChannelStateInformationMode = char(reportMode);
payload.CodebookMode = char(codebookMode);
payload.StandardProfile = "legacy_custom_csi_container_not_3gpp_wire_format";
payload.BitExactSupported = false;
payload.CustomContainerUsed = true;
payload.WireFormatQualification = "unqualified_legacy_container";
payload.CRCEnabled = crcAttached;
payload.Bits = uint8(payloadBits(:));
payload.BitLength = double(numel(payloadBits));
payload.Hex = char(sixgr.l2.mac.SchedulerBase.bitsToHex(payloadBits));
payload.FieldLayout = fields;
payload.FieldCount = double(numel(fields));
payload.DecoderHints = struct( ...
    "NumTxPorts", double(numTxPorts), ...
    "NumRxAnt", double(numRxAnt), ...
    "MaxRank", double(maxRank), ...
    "NumResourceCandidates", double(max(1, round(double(sixgr.util.structGet(csi, "CRICandidateCount", 1))))), ...
    "PMICandidateCount", double(max(1, round(double(sixgr.util.structGet(csi, "PMICandidateCount", 1))))), ...
    "NumBeams", double(max(1, round(double(sixgr.util.structGet(opt.CodebookInfo, "NumBeams", numTxPorts))))), ...
    "StrideSet", double(sixgr.util.structGet(opt.CodebookInfo, "StrideSet", 1)), ...
    "NumPhaseVariants", double(max(1, round(double(sixgr.util.structGet(opt.CodebookInfo, "NumPhaseVariants", 1))))));
end

function tokens = localOrderedReportTokens(reportMode)
raw = upper(strtrim(reportMode));
if strlength(raw) == 0 || raw == "NONE"
    tokens = strings(0,1);
    return;
end
parts = split(raw, "+");
parts = strtrim(parts(:));
parts = parts(parts ~= "");
order = strings(0,1);
for i = 1:numel(parts)
    token = parts(i);
    if ismember(token, ["CQI","RI","PMI","CRI"]) && ~any(order == token)
        order(end+1,1) = token; %#ok<AGROW>
    end
end
tokens = order;
end

function fields = localEmptyFieldLayout()
fields = repmat(struct( ...
    "Name", "", ...
    "Category", "", ...
    "Width", 0, ...
    "Value", NaN, ...
    "EncodedValue", NaN, ...
    "Bits", uint8([])), 0, 1);
end

function [fields, payloadBits] = localAppendCQI(fields, payloadBits, csi)
if ~logical(sixgr.util.structGet(csi, "ReportCQI", false))
    return;
end
value = double(sixgr.util.structGet(csi, "CQI", NaN));
if ~isfinite(value)
    return;
end
enc = max(0, min(15, round(value)));
bits = localUIntToBits(enc, 4);
[fields, payloadBits] = localAppendField(fields, payloadBits, "CQI", "cqi", 4, value, enc, bits);
end

function [fields, payloadBits] = localAppendRI(fields, payloadBits, csi, maxRank)
if ~logical(sixgr.util.structGet(csi, "ReportRI", false))
    return;
end
value = double(sixgr.util.structGet(csi, "RI", NaN));
if ~isfinite(value)
    return;
end
width = localRequiredBits(maxRank - 1);
enc = max(0, min(maxRank - 1, round(value) - 1));
bits = localUIntToBits(enc, width);
[fields, payloadBits] = localAppendField(fields, payloadBits, "RI", "ri", width, value, enc, bits);
end

function [fields, payloadBits] = localAppendCRI(fields, payloadBits, csi)
if ~logical(sixgr.util.structGet(csi, "ReportCRI", false))
    return;
end
value = double(sixgr.util.structGet(csi, "CRI", NaN));
if ~isfinite(value)
    return;
end
numCandidates = max(1, round(double(sixgr.util.structGet(csi, "CRICandidateCount", 1))));
width = localRequiredBits(numCandidates - 1);
enc = max(0, min(numCandidates - 1, round(value)));
bits = localUIntToBits(enc, width);
[fields, payloadBits] = localAppendField(fields, payloadBits, "CRI", "cri", width, value, enc, bits);
end

function [fields, payloadBits] = localAppendPMI(fields, payloadBits, csi, codebookMode, candidate, codebookInfo)
if ~logical(sixgr.util.structGet(csi, "ReportPMI", false))
    return;
end
value = double(sixgr.util.structGet(csi, "PMI", NaN));
if ~isfinite(value)
    return;
end

numCandidates = max(1, round(double(sixgr.util.structGet(csi, "PMICandidateCount", 1))));
debugWidth = localRequiredBits(numCandidates - 1);
debugBits = localUIntToBits(max(0, min(numCandidates - 1, round(value))), debugWidth);

if isempty(candidate)
    candidate = struct();
end
if isempty(codebookInfo)
    codebookInfo = struct();
end

switch codebookMode
    case "type1_su_mimo"
        numBeams = max(1, round(double(sixgr.util.structGet(codebookInfo, "NumBeams", ...
            sixgr.util.structGet(candidate, "NumBeams", sixgr.util.structGet(csi, "NumTxPorts", 1))))));
        beamWidth = localRequiredBits(numBeams - 1);
        startBeam = max(0, min(numBeams - 1, round(double(sixgr.util.structGet(candidate, "StartBeamIndex", value)))));
        bits = localUIntToBits(startBeam, beamWidth);
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_START_BEAM", "pmi", beamWidth, startBeam, startBeam, bits);
    case "type2_mu_mimo"
        numBeams = max(1, round(double(sixgr.util.structGet(codebookInfo, "NumBeams", ...
            sixgr.util.structGet(candidate, "NumBeams", sixgr.util.structGet(csi, "NumTxPorts", 1))))));
        beamWidth = localRequiredBits(numBeams - 1);
        startBeam = max(0, min(numBeams - 1, round(double(sixgr.util.structGet(candidate, "StartBeamIndex", value)))));
        strideSet = double(sixgr.util.structGet(codebookInfo, "StrideSet", 1));
        strideSet = strideSet(:).';
        strideWidth = localRequiredBits(numel(strideSet) - 1);
        strideIdx = max(0, min(numel(strideSet) - 1, round(double(sixgr.util.structGet(candidate, "StrideIndex", 0)))));
        numPhaseVariants = max(1, round(double(sixgr.util.structGet(codebookInfo, "NumPhaseVariants", 1))));
        phaseWidth = localRequiredBits(numPhaseVariants - 1);
        phaseIdx = max(0, min(numPhaseVariants - 1, round(double(sixgr.util.structGet(candidate, "PhaseVariantIndex", 0)))));
        basisCount = max(1, round(double(sixgr.util.structGet(candidate, "BasisBeamCount", ...
            sixgr.util.structGet(codebookInfo, "Type2BasisBeamCount", 1)))));
        basisWidth = localRequiredBits(max(1, round(double(sixgr.util.structGet(codebookInfo, "Type2BasisBeamCount", basisCount)))) - 1);
        startBits = localUIntToBits(startBeam, beamWidth);
        strideBits = localUIntToBits(strideIdx, strideWidth);
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_START_BEAM", "pmi", beamWidth, startBeam, startBeam, startBits);
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_STRIDE_INDEX", "pmi", strideWidth, strideIdx, strideIdx, strideBits);
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_PHASE_INDEX", "pmi", phaseWidth, phaseIdx, phaseIdx, localUIntToBits(phaseIdx, phaseWidth));
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_TYPE2_BASIS_BEAM_COUNT_MINUS1", "pmi", basisWidth, basisCount - 1, basisCount - 1, localUIntToBits(basisCount - 1, basisWidth));
    case "etype2_candidate"
        numBeams = max(1, round(double(sixgr.util.structGet(codebookInfo, "NumBeams", ...
            sixgr.util.structGet(candidate, "NumBeams", sixgr.util.structGet(csi, "NumTxPorts", 1))))));
        beamWidth = localRequiredBits(numBeams - 1);
        startBeam = max(0, min(numBeams - 1, round(double(sixgr.util.structGet(candidate, "StartBeamIndex", value)))));
        strideSet = double(sixgr.util.structGet(codebookInfo, "StrideSet", 1));
        strideSet = strideSet(:).';
        strideWidth = localRequiredBits(numel(strideSet) - 1);
        strideIdx = max(0, min(numel(strideSet) - 1, round(double(sixgr.util.structGet(candidate, "StrideIndex", 0)))));
        numPhaseVariants = max(1, round(double(sixgr.util.structGet(codebookInfo, "NumPhaseVariants", 1))));
        phaseWidth = localRequiredBits(numPhaseVariants - 1);
        phaseIdx = max(0, min(numPhaseVariants - 1, round(double(sixgr.util.structGet(candidate, "PhaseVariantIndex", 0)))));
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_START_BEAM", "pmi", beamWidth, startBeam, startBeam, localUIntToBits(startBeam, beamWidth));
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_STRIDE_INDEX", "pmi", strideWidth, strideIdx, strideIdx, localUIntToBits(strideIdx, strideWidth));
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_PHASE_INDEX", "pmi", phaseWidth, phaseIdx, phaseIdx, localUIntToBits(phaseIdx, phaseWidth));
    otherwise
        [fields, payloadBits] = localAppendField(fields, payloadBits, ...
            "PMI_INDEX", "pmi", debugWidth, value, value, debugBits);
        return;
end

[fields, payloadBits] = localAppendField(fields, payloadBits, ...
    "PMI_INDEX_DEBUG", "pmi_debug", debugWidth, value, value, debugBits);
end

function [fields, payloadBits] = localAppendField(fields, payloadBits, name, category, width, value, enc, bits)
row = struct( ...
    "Name", char(string(name)), ...
    "Category", char(string(category)), ...
    "Width", double(width), ...
    "Value", double(value), ...
    "EncodedValue", double(enc), ...
    "Bits", uint8(bits(:)));
fields(end+1,1) = row; %#ok<AGROW>
payloadBits = [payloadBits; uint8(bits(:))]; %#ok<AGROW>
end

function bits = localUIntToBits(value, width)
width = max(0, round(double(width)));
if width == 0
    bits = uint8([]);
    return;
end
bits = sixgr.l2.mac.SchedulerBase.uintToBits(max(0, floor(double(value))), width);
end

function width = localRequiredBits(maxValue)
maxValue = max(0, round(double(maxValue)));
if maxValue <= 0
    width = 0;
else
    width = ceil(log2(double(maxValue + 1)));
end
end

function bits = localCRC6(dataBits)
bits = uint8(dataBits(:) ~= 0);
state = zeros(1, 6, "uint8");
poly = uint8([1 0 0 0 0 1]);
for i = 1:numel(bits)
    fb = bitxor(bits(i), state(1));
    state(1:5) = state(2:6);
    state(6) = 0;
    if fb ~= 0
        state = bitxor(state, poly);
    end
end
bits = state(:);
end

function payload = localTypedReportPayload(csi,cfg,report)
reportConfig=sixgr.util.structGet(cfg,"ReportConfigurationObject", ...
    sixgr.util.structGet(csi,"CSIReportConfiguration",[]));
activeRequest=sixgr.util.structGet(cfg,"ReportConfiguration", ...
    sixgr.util.structGet(cfg,"phy.csi.reportConfiguration",[]));
if isempty(sixgr.util.structGet(cfg,'ReportConfigurationObject',[])) && ~isempty(activeRequest)
    activeEpoch=sixgr.util.structGet(cfg,"ReportConfigurationEpoch", ...
        sixgr.util.structGet(activeRequest,'Epoch',NaN));
    reportConfig=sixgr.phy.mimo.CSIReportConfiguration(activeRequest,activeEpoch);
end
if ~isa(reportConfig,"sixgr.phy.mimo.CSIReportConfiguration")
    error("sixgr:mimo:MissingCSIReportConfig", ...
        "Typed CSI packing requires its active CSIReportConfiguration; supplied bits are not configuration authority.");
end
reportConfig.assertQualifiedWireLayout();
if isempty(report)
    values = struct( ...
        "CRI",double(sixgr.util.structGet(csi,"CRI",NaN)), ...
        "RI",double(sixgr.util.structGet(csi,"RI",NaN)), ...
        "CQI_CW0",double(sixgr.util.structGet(csi,"CQI",NaN)), ...
        "PMI",double(sixgr.util.structGet(csi,"PMI",NaN)), ...
        "LI",double(sixgr.util.structGet(csi,"LI",NaN)));
    for field=["PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
        values.(field)=double(sixgr.util.structGet(csi,field,NaN));
    end
    if isfield(csi,'PMIComponents'), values.PMIComponents=csi.PMIComponents; end
    report = reportConfig.build(values);
end
if ~isstruct(report) || ~isfield(report,"Part1Bits") || ~isfield(report,"Part2Bits")
    error("sixgr:mimo:CSISerializationMismatch", ...
        "Typed CSI report does not contain Part 1 and Part 2.");
end
required=["ReportConfigID","ConfigurationEpoch","Part1Owners","Part2Owners"];
assert(all(isfield(report,required)) && ...
    isequal(string(report.ReportConfigID),reportConfig.ReportConfigID) && ...
    isequal(double(report.ConfigurationEpoch),reportConfig.Epoch), ...
    'sixgr:mimo:CSISerializationMismatch', ...
    'Typed CSI must retain its exact active report identity, epoch and field ownership.');
% Decode validates binary values, received RI, padding and both lengths
% BEFORE any uint8 cast. Rebuild owners from the active schema, never trust
% externally supplied owner labels merely because the bit count matches.
canonical=reportConfig.transcode(report.Part1Bits,report.Part2Bits,reportConfig.UCIChannel);
assert(isequal(string(report.Part1Owners(:)),canonical.Part1Owners(:)) && ...
    isequal(string(report.Part2Owners(:)),canonical.Part2Owners(:)), ...
    'sixgr:mimo:CSISerializationMismatch','Typed CSI field ownership differs from its active wire layout.');
part1 = uint8(report.Part1Bits(:));
part2 = uint8(report.Part2Bits(:));
bits = [part1;part2];
payloadHex = char(sixgr.l2.mac.SchedulerBase.bitsToHex(bits));
owners = [string(report.Part1Owners(:));string(report.Part2Owners(:))];
fields = repmat(struct( ...
    "Name","","Category","","Width",0,"Value",NaN, ...
    "EncodedValue",NaN,"Bits",uint8([])),0,1);
uniqueOwners = unique(owners,"stable");
for index = 1:numel(uniqueOwners)
    owner = uniqueOwners(index);
    mask = owners == owner;
    fields(end+1,1) = struct( ... %#ok<AGROW>
        "Name",char(owner), ...
        "Category",char(lower(owner)), ...
        "Width",double(nnz(mask)), ...
        "Value",NaN, ...
        "EncodedValue",NaN, ...
        "Bits",uint8(bits(mask)));
end
mode="typed_csi_single_part";
if ~isempty(part2), mode="typed_csi_part1_part2"; end
wireQualification="qualified_typeI_singlepanel_wideband_codec_only";
if lower(reportConfig.CodebookType)=="typeii"
    wireQualification="qualified_typeII_wideband_pusch_codec_only";
end
payload = struct( ...
    "Enabled",~isempty(bits), ...
    "Mode",mode, ...
    "ChannelStateInformationMode",char(string(sixgr.util.structGet(csi, ...
        "ChannelStateInformationMode","configured_report_quantity"))), ...
    "CodebookMode",char(string(sixgr.util.structGet(csi,"PMICodebookMode","configured"))), ...
    "StandardProfile","TS38.214_V18.9.0_TS38.212_V18.8.0", ...
    "BitExactSupported",true, ...
    "WireFormatQualification",wireQualification, ...
    "CRCEnabled",false, ...
    "Bits",bits, ...
    "BitLength",double(numel(bits)), ...
    "Hex",payloadHex, ...
    "FieldLayout",fields, ...
    "FieldCount",double(numel(fields)), ...
    "Part1Bits",part1, ...
    "Part2Bits",part2, ...
    "Part1BitLength",double(numel(part1)), ...
    "Part2BitLength",double(numel(part2)), ...
    "SeparateEncoding",~isempty(part2), ...
    "CustomContainerUsed",false, ...
    "DecoderHints",struct("ReportConfigID",string(sixgr.util.structGet(report, ...
        "ReportConfigID",""))));
end
