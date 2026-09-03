classdef CSIReportConfiguration
    %CSIREPORTCONFIGURATION Immutable report-dependent CSI Part 1/Part 2 schema.

    properties (SetAccess = immutable)
        ReportConfigID (1,1) string
        Epoch (1,1) double
        CodebookType (1,1) string
        Ports (1,1) double
        Rank (1,1) double
        ReportQuantity (1,1) string
        NumCSIResources (1,1) double
        FrequencyGranularity (1,1) string
        UCIChannel (1,1) string
        Part1Fields (1,:) string
        Part1Widths (1,:) double
        Part2Fields (1,:) string
        Part2Widths (1,:) double
        SpecificationProfile (1,1) string
    end

    methods
        function obj = CSIReportConfiguration(request, currentEpoch)
            arguments
                request (1,1) struct
                currentEpoch (1,1) double {mustBeInteger,mustBeNonnegative} = 0
            end
            if isfield(request,"Missing") && logical(request.Missing)
                error("sixgr:mimo:MissingCSIReportConfig", ...
                    "No active CSI report configuration exists.");
            end
            required = ["ReportConfigID","Epoch","CodebookType","Ports","Rank", ...
                "ReportQuantity","NumCSIResources","FrequencyGranularity"];
            for field = required
                if ~isfield(request,field) || isempty(request.(field))
                    error("sixgr:mimo:MissingCSIReportConfig", ...
                        "CSI report configuration requires %s.", field);
                end
            end
            epoch = double(request.Epoch);
            if epoch ~= currentEpoch
                error("sixgr:mimo:StaleCSIReportConfig", ...
                    "CSI report epoch %d differs from active epoch %d.", epoch, currentEpoch);
            end
            codebookType = string(request.CodebookType);
            ports = localInteger(request.Ports, "Ports");
            rankValue = localInteger(request.Rank, "Rank");
            numResources = localInteger(request.NumCSIResources, "NumCSIResources");
            if rankValue > min(8,ports)
                error("sixgr:mimo:InvalidRI", ...
                    "RI %d is invalid for %d ports.", rankValue, ports);
            end
            if contains(lower(codebookType),"unsupported") || ...
                    ismember(lower(codebookType), ["missing_config","stale_config","wrong_part1","wrong_part2"])
                error("sixgr:mimo:UnsupportedTypeIIProfile", ...
                    "CSI codebook type %s is not enabled.", codebookType);
            end
            uciChannel = upper(string(localField(request,"UCIChannel","PUCCH")));
            if ~ismember(uciChannel,["PUCCH","PUSCH"])
                error("sixgr:mimo:MissingCSIReportConfig", ...
                    "UCIChannel must be PUCCH or PUSCH.");
            end
            [part1Fields, part1Widths, part2Fields, part2Widths] = ...
                localSchema(codebookType,ports,rankValue,string(request.ReportQuantity), ...
                    numResources,string(request.FrequencyGranularity),request);

            obj.ReportConfigID = string(request.ReportConfigID);
            obj.Epoch = epoch;
            obj.CodebookType = codebookType;
            obj.Ports = ports;
            obj.Rank = rankValue;
            obj.ReportQuantity = string(request.ReportQuantity);
            obj.NumCSIResources = numResources;
            obj.FrequencyGranularity = string(request.FrequencyGranularity);
            obj.UCIChannel = uciChannel;
            obj.Part1Fields = part1Fields;
            obj.Part1Widths = part1Widths;
            obj.Part2Fields = part2Fields;
            obj.Part2Widths = part2Widths;
            obj.SpecificationProfile = ...
                sixgr.phy.mimo.MIMOSpecificationProfile().ProfileID;
        end

        function n = part1BitCount(obj)
            n = sum(obj.Part1Widths);
        end

        function n = part2BitCount(obj)
            n = sum(obj.Part2Widths);
        end

        function report = build(obj, values)
            arguments
                obj
                values (1,1) struct
            end
            [part1Bits, part1Owners] = localSerializeFields( ...
                obj.Part1Fields,obj.Part1Widths,values);
            [part2Bits, part2Owners] = localSerializeFields( ...
                obj.Part2Fields,obj.Part2Widths,values);
            part1Names = part1Owners;
            part2Names = part2Owners;
            report = struct( ...
                "ReportConfigID", obj.ReportConfigID, ...
                "ConfigurationEpoch", obj.Epoch, ...
                "Part1Bits", int8(part1Bits), ...
                "Part2Bits", int8(part2Bits), ...
                "Part1Owners", part1Owners, ...
                "Part2Owners", part2Owners, ...
                "Part1Sequence", sixgr.phy.pucch.UCISequence(1,part1Bits,part1Owners,part1Names), ...
                "Part2Sequence", sixgr.phy.pucch.UCISequence(2,part2Bits,part2Owners,part2Names), ...
                "SeparateEncoding", true, ...
                "CustomContainerUsed", false, ...
                "SpecificationProfile", obj.SpecificationProfile);
        end

        function decoded = encodeDecodeNoNoise(obj, report)
            localValidateReportLength(obj,report);
            decoded = struct();
            decoded.Part1 = localRoundTrip(report.Part1Sequence, "QPSK");
            decoded.Part2 = localRoundTrip(report.Part2Sequence, "QPSK");
            decoded.Part1BitErrors = nnz(decoded.Part1.Bits ~= report.Part1Bits);
            decoded.Part2BitErrors = nnz(decoded.Part2.Bits ~= report.Part2Bits);
            decoded.CRCPassed = decoded.Part1.CRCPassed && decoded.Part2.CRCPassed;
        end

        function validateDecoded(obj, part1Bits, part2Bits)
            if numel(part1Bits) ~= obj.part1BitCount()
                error("sixgr:mimo:InvalidCSIPart1Length", ...
                    "CSI Part 1 has %d bits; schema requires %d.", ...
                    numel(part1Bits),obj.part1BitCount());
            end
            if numel(part2Bits) ~= obj.part2BitCount()
                error("sixgr:mimo:InvalidCSIPart2Length", ...
                    "CSI Part 2 has %d bits; schema requires %d.", ...
                    numel(part2Bits),obj.part2BitCount());
            end
        end

        function values = decode(obj, part1Bits, part2Bits)
            %DECODE Reconstruct CSI fields from receiver-decoded UCI bits.
            % The scheduler must consume this result rather than the
            % transmitter-side values used to construct the report.
            obj.validateDecoded(part1Bits, part2Bits);
            values = localDeserializeFields(obj.Part1Fields, ...
                obj.Part1Widths, int8(part1Bits(:)), struct());
            values = localDeserializeFields(obj.Part2Fields, ...
                obj.Part2Widths, int8(part2Bits(:)), values);
            values.ReportConfigID = obj.ReportConfigID;
            values.ConfigurationEpoch = obj.Epoch;
            values.UCIChannel = obj.UCIChannel;
        end
    end
end

function [p1f,p1w,p2f,p2w] = localSchema(codebookType,ports,rankValue,quantity,nResources,granularity,request)
cb = lower(codebookType);
q = lower(quantity);
criWidth = localBits(nResources-1);
riWidth = localBits(min(8,ports)-1);
if contains(cb,"typei") && contains(cb,"single") && ports == 1
    % A single CSI-RS port has no spatial choice: RI is identically one
    % and PMI/LI carry no information.  Keep only the resource selector
    % (when multiple CSI-RS resources exist) and wideband CQI in Part 1.
    % Emitting a fabricated PMI for SISO would make the scheduler appear
    % spatially adaptive when no codebook decision exists.
    p1f = ["CRI","CQI_CW0"];
    p1w = [criWidth,4];
    p2f = strings(1,0);
    p2w = zeros(1,0);
    return;
end
if contains(cb,"typei") && contains(cb,"single") && ports == 2
    p1f = ["CRI","RI","CQI_CW0"];
    p1w = [criWidth,1,4];
    p2f = strings(1,0);
    p2w = zeros(1,0);
    if contains(q,"pmi") || contains(q,"i1")
        p2f(end+1) = "PMI";
        p2w(end+1) = 3-rankValue; % rank1:2 bits, rank2:1 bit
    end
    p2f(end+1) = "LI";
    p2w(end+1) = localBits(rankValue-1);
    return;
end
if contains(cb,"typei") && contains(cb,"single") && ports > 2
    n1 = localInteger(localField(request,"N1",NaN),"N1");
    n2 = localInteger(localField(request,"N2",NaN),"N2");
    o1 = localInteger(localField(request,"O1",NaN),"O1");
    o2 = localInteger(localField(request,"O2",NaN),"O2");
    maxRank = localInteger(localField(request,"MaxRank",rankValue),"MaxRank");
    codebookMode = localInteger(localField(request,"CodebookMode",NaN),"CodebookMode");
    if ports ~= 2*n1*n2 || ~ismember(codebookMode,[1 2]) || ...
            rankValue > 2 || maxRank > 2
        error("sixgr:mimo:UnsupportedAntennaTuple", ...
            "The enabled strict Type-I single-panel payload schema supports " + ...
            "dual-polarized ports=2*N1*N2 and ranks one or two.");
    end
    p1f = ["CRI","RI","CQI_CW0"];
    p1w = [criWidth,localBits(maxRank-1),4];
    p2f = strings(1,0);
    p2w = zeros(1,0);
    localAppendPMIField("PMI_I11",localBits(n1*o1-1));
    localAppendPMIField("PMI_I12",localBits(n2*o2-1));
    if rankValue == 2
        localAppendPMIField("PMI_I13",1);
    end
    if rankValue == 1
        localAppendPMIField("PMI_I2",2);
    else
        localAppendPMIField("PMI_I2",1);
    end
    p2f(end+1) = "LI";
    p2w(end+1) = localBits(rankValue-1);
    return;
end
if ~(contains(cb,"typeii") || contains(cb,"typei"))
    error("sixgr:mimo:InvalidCodebookType", ...
        "Unsupported CSI codebook type %s.", codebookType);
end
if ~strcmpi(granularity,"subband") && contains(cb,"typeii")
    error("sixgr:mimo:InvalidCodebookType", ...
        "The enabled Type-II subset requires subband reporting.");
end
beamCount = double(localField(request,"NumberOfBeams",min(4,ports)));
subbands = double(localField(request,"NumSubbands",1));
phaseAlphabet = double(localField(request,"PhaseAlphabetSize",4));
p1f = ["RI","CQI_CW0","NONZERO_AMPLITUDE_COUNT"];
p1w = [riWidth,4,localBits(ports+1)];
if contains(cb,"cjt")
    p1f = [p1f,"CSI_RS_RESOURCE_BITMAP","SELECTED_COMBINATION"];
    p1w = [p1w,nResources,localBits(max(1,nResources*(nResources-1)/2))];
end
p2f = ["PMI_COEFFICIENTS","LI"];
p2w = [rankValue*beamCount*(localBits(phaseAlphabet-1)+1)*subbands, ...
       localBits(rankValue-1)];

    function localAppendPMIField(name,width)
        if width > 0
            p2f(end+1) = name;
            p2w(end+1) = width;
        end
    end
end

function [bits,owners] = localSerializeFields(fields,widths,values)
bits = int8(zeros(0,1));
owners = strings(0,1);
for index = 1:numel(fields)
    width = widths(index);
    if width == 0
        continue;
    end
    name = fields(index);
    value = double(localField(values,char(name),0));
    if name == "RI"
        value = value-1;
    end
    maxValue = 2^width-1;
    if ~(isscalar(value) && isfinite(value) && value >= 0 && ...
            value == round(value) && value <= maxValue)
        error("sixgr:mimo:CSISerializationMismatch", ...
            "CSI field %s value %s exceeds its %d-bit domain.", ...
            name,mat2str(value),width);
    end
    fieldBits = int8(sixgr.l2.mac.SchedulerBase.uintToBits(value,width));
    bits = [bits;fieldBits(:)]; %#ok<AGROW>
    owners = [owners;repmat(name,width,1)]; %#ok<AGROW>
end
end

function values = localDeserializeFields(fields,widths,bits,values)
offset = 0;
for index = 1:numel(fields)
    width = widths(index);
    name = char(fields(index));
    if width == 0
        if strcmp(name,"RI")
            values.(name) = 1;
        else
            values.(name) = 0;
        end
        continue;
    end
    fieldBits = double(bits(offset + (1:width))).';
    if any(fieldBits ~= 0 & fieldBits ~= 1)
        error("sixgr:mimo:CSIDeserializationMismatch", ...
            "Decoded CSI field %s contains non-binary values.", name);
    end
    weights = 2.^((width-1):-1:0);
    value = sum(fieldBits .* weights);
    if strcmp(name,"RI")
        value = value + 1;
    end
    values.(name) = double(value);
    offset = offset + width;
end
if offset ~= numel(bits)
    error("sixgr:mimo:CSIDeserializationMismatch", ...
        "Decoded CSI bit consumption %d differs from payload length %d.", ...
        offset,numel(bits));
end
end

function decoded = localRoundTrip(sequence,modulation)
A = numel(sequence.Bits);
if A == 0
    decoded = struct("Bits",int8(zeros(0,1)),"CRCPassed",true);
    return;
end
E = max(32,2*A);
encoded = sixgr.phy.pucch.UCIEncoder.encode(sequence,E,modulation);
coded = double(encoded.CodedBits(:));
llr = zeros(size(coded));
llr(coded == 0) = 100;
llr(coded == 1) = -100;
result = sixgr.phy.pucch.UCIDecoder.decode(llr,A);
decoded = struct("Bits",int8(result.Bits(:)),"CRCPassed",logical(result.CRCPassed));
end

function localValidateReportLength(config,report)
config.validateDecoded(report.Part1Bits,report.Part2Bits);
end

function value = localField(s,name,defaultValue)
if isfield(s,name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function value = localInteger(raw,name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value >= 1 && value == round(value))
    error("sixgr:mimo:MissingCSIReportConfig", ...
        "%s must be a positive integer.",name);
end
end

function width = localBits(maxValue)
if maxValue <= 0
    width = 0;
else
    width = ceil(log2(double(maxValue)+1));
end
end
