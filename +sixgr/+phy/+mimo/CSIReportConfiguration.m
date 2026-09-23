classdef CSIReportConfiguration
    %CSIREPORTCONFIGURATION Immutable report-dependent CSI Part 1/Part 2 schema.

    properties (SetAccess = immutable)
        ReportConfigID (1,1) string
        Epoch (1,1) double
        CodebookType (1,1) string
        Ports (1,1) double
        Rank (1,1) double
        AllowedRanks (1,:) double
        ReportQuantity (1,1) string
        NumCSIResources (1,1) double
        FrequencyGranularity (1,1) string
        UCIChannel (1,1) string
        ConfiguredUCIChannel (1,1) string
        Part1Fields (1,:) string
        Part1Widths (1,:) double
        Part2Fields (1,:) string
        Part2Widths (1,:) double
        SpecificationProfile (1,1) string
    end

    properties (SetAccess = immutable, GetAccess = private)
        SchemaRequest (1,1) struct
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
            allowedRanks=localAllowedRanks(request,ports);
            if ~ismember(rankValue,allowedRanks)
                error('sixgr:mimo:InvalidRI','RI %d is excluded by the active report rank restriction.',rankValue);
            end
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
            configuredChannel=upper(string(localField(request,"ConfiguredUCIChannel",uciChannel)));
            assert(isscalar(configuredChannel) && ismember(configuredChannel,["PUCCH","PUSCH"]), ...
                'sixgr:mimo:MissingCSIReportConfig','ConfiguredUCIChannel must be PUCCH or PUSCH.');
            % TS 38.214 5.2.3: a PUCCH-configured report multiplexed on
            % PUSCH retains the payload definition of the configured report.
            request.ConfiguredUCIChannel=configuredChannel;
            [part1Fields, part1Widths, part2Fields, part2Widths] = ...
                localSchema(codebookType,ports,rankValue,string(request.ReportQuantity), ...
                    numResources,string(request.FrequencyGranularity),request);

            obj.ReportConfigID = string(request.ReportConfigID);
            obj.SchemaRequest = request;
            obj.Epoch = epoch;
            obj.CodebookType = codebookType;
            obj.Ports = ports;
            obj.Rank = rankValue;
            obj.AllowedRanks = allowedRanks;
            obj.ReportQuantity = string(request.ReportQuantity);
            obj.NumCSIResources = numResources;
            obj.FrequencyGranularity = string(request.FrequencyGranularity);
            obj.UCIChannel = uciChannel;
            obj.ConfiguredUCIChannel = configuredChannel;
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

        function counts = part2BitCountCandidates(obj)
            % Resource discovery before RI reception uses only configured
            % possibilities, never the transmitter's selected RI/bit count.
            request=obj.SchemaRequest;
            counts=zeros(size(obj.AllowedRanks));
            for index=1:numel(obj.AllowedRanks)
                request.Rank=obj.AllowedRanks(index);
                candidate=sixgr.phy.mimo.CSIReportConfiguration(request,obj.Epoch);
                counts(index)=candidate.part2BitCount();
            end
            counts=unique(counts);
        end

        function target = forTransport(obj,channel)
            request=obj.SchemaRequest;
            request.UCIChannel=upper(string(channel));
            target=sixgr.phy.mimo.CSIReportConfiguration(request,obj.Epoch);
        end

        function assertQualifiedWireLayout(obj)
            % Legacy advanced schema-size formulas are internal inspection
            % objects, not implementations of TS 38.212 CSI wire formats.
            assert(lower(obj.CodebookType)=="typei-singlepanel" && ...
                lower(obj.FrequencyGranularity)=="wideband" && ...
                (all(obj.AllowedRanks<=2) || ...
                    (obj.Ports==4 && all(obj.AllowedRanks<=4))), ...
                'sixgr:mimo:UnqualifiedCSIWireLayout', ...
                'CSI %s/%s has no qualified wire implementation; do not serialize or consume the legacy schema as NR UCI.', ...
                obj.CodebookType,obj.FrequencyGranularity);
        end

        function [encoded,target] = transcode(obj,part1,part2,channel)
            % Physical transport reassignment does not reconfigure CSI.
            % Preserve the installed reporting format, including padding
            % and Part-1/Part-2 ownership (TS 38.214 5.2.3).
            values=obj.decode(part1,part2);
            request=obj.SchemaRequest;
            if isfield(values,'RI'), request.Rank=values.RI; end
            request.UCIChannel=upper(string(channel));
            target=sixgr.phy.mimo.CSIReportConfiguration(request,obj.Epoch);
            encoded=target.build(values);
        end

        function report = build(obj, values)
            arguments
                obj
                values (1,1) struct
            end
            obj.assertQualifiedWireLayout();
            if any(obj.Part1Fields=="CRI") && isfield(values,'CRI')
                localValidateCRI(values.CRI,obj.NumCSIResources);
            end
            if any(obj.Part1Fields=="RI")
                assert(isfield(values,'RI') && ~isempty(values.RI), ...
                    'sixgr:mimo:MissingCSIReportMeasurement','RI requires an explicit measured rank.');
                assert(isequal(double(values.RI),obj.Rank), ...
                    'sixgr:mimo:InvalidRI','Serialized RI must agree with the report layout rank.');
                riValues=localRIValues(obj.SchemaRequest);
                values.RI=find(riValues==obj.Rank); % Restricted codebook ordinal; see Table 6.3.1.1.2-3.
            end
            values.ZERO_PADDING=0; % Normative reserved padding, not a measurement.
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
                "SeparateEncoding", ~isempty(part2Bits), ...
                "CustomContainerUsed", false, ...
                "SpecificationProfile", obj.SpecificationProfile);
        end

        function decoded = encodeDecodeNoNoise(obj, report)
            obj.assertQualifiedWireLayout();
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

        function [values, receivedConfig] = decodePart1(obj, part1Bits)
            % Resolve rank-dependent Part 2 from RECEIVED Part 1, never
            % the rank used by a pending transmitter-side report object.
            obj.assertQualifiedWireLayout();
            localValidateBinaryBits(part1Bits);
            if numel(part1Bits) ~= obj.part1BitCount()
                error("sixgr:mimo:InvalidCSIPart1Length", ...
                    "CSI Part 1 has %d bits; schema requires %d.",numel(part1Bits),obj.part1BitCount());
            end
            receivedConfig = obj;
            riIndex=find(obj.Part1Fields=="RI",1);
            if ~isempty(riIndex)
                % CRI/RI precede every rank-dependent field on both channels.
                prefixLength=sum(obj.Part1Widths(1:riIndex));
                prefix=localDeserializeFields(obj.Part1Fields(1:riIndex), ...
                    obj.Part1Widths(1:riIndex),part1Bits(1:prefixLength),struct());
                riValues=localRIValues(obj.SchemaRequest);
                if prefix.RI>numel(riValues) || ~ismember(riValues(prefix.RI),obj.AllowedRanks)
                    error('sixgr:mimo:InvalidRI','Received RI ordinal is excluded by the report rank restriction.');
                end
                request = obj.SchemaRequest;
                request.Rank = riValues(prefix.RI);
                receivedConfig = sixgr.phy.mimo.CSIReportConfiguration(request,obj.Epoch);
                assert(obj.part1BitCount()==receivedConfig.part1BitCount(), ...
                    'sixgr:mimo:RankDependentCSIPart1Schema', ...
                    'Part-1 resource size must be fixed by configuration, not the reported rank.');
            end
            values=localDeserializeFields(receivedConfig.Part1Fields, ...
                receivedConfig.Part1Widths,part1Bits(:),struct());
            if isfield(values,'CRI')
                localValidateCRI(values.CRI,obj.NumCSIResources);
            end
            if isfield(values,'RI')
                riValues=localRIValues(obj.SchemaRequest); values.RI=riValues(values.RI);
            end
            if obj.Ports==1, values.RI=1; end % No transmitted spatial choice for one CSI-RS port.
        end

        function values = decode(obj, part1Bits, part2Bits)
            %DECODE Reconstruct CSI fields from receiver-decoded UCI bits.
            % The scheduler must consume this result rather than the
            % transmitter-side values used to construct the report.
            [values, receivedConfig] = obj.decodePart1(part1Bits);
            localValidateBinaryBits(part2Bits);
            receivedConfig.validateDecoded(part1Bits, part2Bits);
            values = localDeserializeFields(receivedConfig.Part2Fields, ...
                receivedConfig.Part2Widths, part2Bits(:), values);
            if obj.Ports>2 && lower(obj.CodebookType)=="typei-singlepanel" && ...
                    contains(lower(obj.ReportQuantity),'pmi') && isfield(values,"PMI_I11")
                % Reconstruct the internal index ONLY from received fields
                % and the active geometry. Never inherit a TX scalar PMI.
                values.PMI=sixgr.phy.mimo.TypeISinglePanelCodebook.linearIndex( ...
                    receivedConfig.SchemaRequest,values);
                [~,components]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix( ...
                    receivedConfig.SchemaRequest,values.PMI);
                for field=["PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
                    values.(field)=components.(field);
                end
            end
            values.ReportConfigID = obj.ReportConfigID;
            values.ConfigurationEpoch = obj.Epoch;
            values.UCIChannel = obj.UCIChannel;
        end
    end
end

function localValidateCRI(value,count)
% Bit width permits spare binary values when the resource count is not a
% power of two. Neither TX nor RX may turn a spare value into a resource.
assert((isnumeric(value)||islogical(value)) && isscalar(value) && isreal(value) && ...
    isfinite(value) && value==fix(value) && value>=0 && value<count, ...
    'sixgr:mimo:InvalidCRI','CRI must identify a configured resource in [0,%d].',count-1);
end

function localValidateBinaryBits(bits)
if ~((isnumeric(bits) || islogical(bits)) && isreal(bits) && ...
        (isvector(bits) || isempty(bits)) && all(bits(:)==0 | bits(:)==1))
    error('sixgr:mimo:CSIDeserializationMismatch', ...
        'Receiver-decoded CSI must be a binary vector; do not round or cast invalid values into bits.');
end
end

function [p1f,p1w,p2f,p2w] = localSchema(codebookType,ports,rankValue,quantity,nResources,granularity,request)
cb = lower(codebookType);
q = lower(quantity);
criWidth = localBits(nResources-1);
riWidth = localBits(min(8,ports)-1);
if cb=="typei-singlepanel"
    [p1f,p1w,p2f,p2w]=localTypeIWidebandSchema(request);
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

end

function ranks=localAllowedRanks(request,ports)
maximum=localInteger(localField(request,'MaxRank',min(8,ports)),'MaxRank');
ranks=double(localField(request,'AllowedRanks',1:maximum));
assert(isrow(ranks) && ~isempty(ranks) && all(isfinite(ranks)) && ...
    all(ranks==fix(ranks) & ranks>=1 & ranks<=min(maximum,ports)) && ...
    isequal(ranks,unique(ranks,'sorted')), ...
    'sixgr:mimo:InvalidRI','AllowedRanks must be increasing unique valid ranks within MaxRank and the CSI-RS ports.');
end

function [p1f,p1w,p2f,p2w]=localTypeIWidebandSchema(request)
% TS 38.212 Tables 6.3.1.1.2-7 (PUCCH) and 6.3.2.1.2-3/4 (PUSCH).
ports=double(request.Ports); rank=double(request.Rank);
ranks=localAllowedRanks(request,ports); q=lower(string(request.ReportQuantity));
assert(lower(string(request.FrequencyGranularity))=="wideband", ...
    'sixgr:mimo:UnsupportedCSIReportLayout','Type-I subband CSI requires its actual differential-CQI/PMI layout.');
assert(any(q==["cri-ri-pmi-cqi","cri-ri-li-pmi-cqi","cri-ri-cqi","cri-ri-i1","cri-ri-i1-cqi","cri-cqi","cqi"]), ...
    'sixgr:mimo:UnsupportedCSIReportLayout','Unsupported Type-I report quantity %s; do not substitute a CQI payload.',q);
assert(ports==1 || contains(q,'ri'), ...
    'sixgr:mimo:UnsupportedCSIReportLayout','Spatial Type-I reports require their configured RI field.');
if ports>2
    assert(max(ranks)<=2 || (ports==4 && max(ranks)<=4), ...
        'sixgr:mimo:UnsupportedAntennaTuple', ...
        'Type-I ranks above two are implemented only for four CSI-RS ports.');
end
prefix=strings(1,0); prefixWidths=zeros(1,0);
if contains(q,'cri'), prefix(end+1)="CRI"; prefixWidths(end+1)=localBits(request.NumCSIResources-1); end
if ports>1 && contains(q,'ri'), prefix(end+1)="RI"; prefixWidths(end+1)=localBits(numel(localRIValues(request))-1); end
cqi=strings(1,0); cqiWidths=zeros(1,0);
if contains(q,'cqi'), cqi="CQI_CW0"; cqiWidths=4; end
[li,liWidths,pmi,pmiWidths]=localTypeIRankFields(request);
if upper(string(localField(request,'ConfiguredUCIChannel', ...
        localField(request,'UCIChannel','PUCCH'))))=="PUSCH"
    p1f=[prefix cqi]; p1w=[prefixWidths cqiWidths];
    p2f=[li pmi]; p2w=[liWidths pmiWidths];
else
    widths=zeros(size(ranks));
    for k=1:numel(ranks)
        candidate=request; candidate.Rank=ranks(k);
        [~,lw,~,pw]=localTypeIRankFields(candidate);
        widths(k)=sum(lw)+sum(pw)+sum(cqiWidths);
    end
    padding=max(widths)-sum(liWidths)-sum(pmiWidths)-sum(cqiWidths);
    p1f=[prefix li "ZERO_PADDING" pmi cqi];
    p1w=[prefixWidths liWidths padding pmiWidths cqiWidths];
    p2f=strings(1,0); p2w=zeros(1,0);
end
end

function values=localRIValues(request)
if lower(string(request.ReportQuantity))=="cri-ri-cqi"
    % No-codebook RI keeps the port-count-dependent field and physical
    % rank-minus-one encoding (TS 38.212 Table 6.3.1.1.2-3).
    values=1:min(8,double(request.Ports));
else
    values=localAllowedRanks(request,double(request.Ports));
end
end

function [li,lw,pmi,pw]=localTypeIRankFields(request)
ports=double(request.Ports); rank=double(request.Rank); q=lower(string(request.ReportQuantity));
li=strings(1,0); lw=zeros(1,0); pmi=strings(1,0); pw=zeros(1,0);
if ports==1, return; end
if contains(q,'-li-'), li="LI"; lw=localBits(rank-1); end
if ~(contains(q,'pmi') || contains(q,'i1')), return; end
if ports==2
    assert(~contains(q,'i1'),'sixgr:mimo:UnsupportedCSIReportLayout', ...
        'A two-port Type-I codebook has a scalar PMI, not an i1 component.');
    pmi="PMI"; pw=3-rank;
else
    layout=sixgr.phy.mimo.TypeISinglePanelCodebook.layout(request);
    names=["PMI_I11","PMI_I12","PMI_I13","PMI_I2"];
    dims=layout.Dimensions([2 3 4 1]);
    if ~contains(q,'pmi'), names=names(1:3); dims=dims(1:3); end
    for k=1:numel(names)
        width=localBits(dims(k)-1);
        if width>0, pmi(end+1)=names(k); pw(end+1)=width; end %#ok<AGROW>
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
    if ~isfield(values,name) || isempty(values.(name))
        error("sixgr:mimo:MissingCSIReportMeasurement", ...
            "CSI field %s requires an explicit measured value for its %d-bit payload; missing evidence cannot be serialized as zero.", ...
            name,width);
    end
    value = double(values.(name));
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
    if strcmp(name,'ZERO_PADDING') && value~=0
        error('sixgr:mimo:InvalidCSIPadding','Received CSI reserved padding must be zero.');
    end
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
