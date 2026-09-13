classdef PUCCHReceptionAssignment
    %PUCCHRECEPTIONASSIGNMENT Receiver-owned resource and length hypothesis.
    % No UE transmission, payload, power state or applied beam is required.
    properties (SetAccess=private)
        Data
        Resource
        ReportContextDigest
        RRCContextDigest
        Digest
    end
    properties (Dependent)
        ReportID
        ConfigurationEpoch
        Format
    end
    methods
        function obj=PUCCHReceptionAssignment(data,rrc,context)
            assert(isstruct(data) && isscalar(data), ...
                'sixgr:phy:pucch:WrongResource','Provide one receiver allocation identity.');
            names=["ObservationID","ResourceID","RNTI","AbsoluteSlot0","Source","TimingSource"];
            sixgr.phy.pucch.UCIReport.requireFields(data,names);
            assert(isempty(setdiff(string(fieldnames(data)),names)), ...
                'sixgr:phy:pucch:OracleInputForbidden', ...
                'Receiver allocation accepts only observation/resource identity and provenance.');
            assert(isa(rrc,'sixgr.phy.pucch.PUCCHRRCContext') && isscalar(rrc) && ...
                isa(context,'sixgr.phy.pucch.UCIReportContext') && isscalar(context), ...
                'sixgr:phy:pucch:MissingUCIReportContext','Installed RRC and length-only receiver context are required.');
            allowed=["ReportID","ConfigurationEpoch","Sequence1Length","Sequence2Length", ...
                "HARQACKBits","SRBits","CSIPart1Bits","CSIPart2Bits","PriorityIndex","FieldLayout"];
            assert(isempty(setdiff(string(fieldnames(context.Data)),allowed)), ...
                'sixgr:phy:pucch:OracleInputForbidden','Receiver context contains unsupported fields.');
            if isfield(context.Data,'FieldLayout')
                layout=context.Data.FieldLayout;
                assert(istable(layout) && ~ismember('BitValue',layout.Properties.VariableNames), ...
                    'sixgr:phy:pucch:OracleInputForbidden','Field layout must not contain payload values.');
            end
            for name=["ResourceID","RNTI","AbsoluteSlot0"]
                validateattributes(data.(name),{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            end
            for name=["ObservationID","Source","TimingSource"]
                value=string(data.(name));
                assert(isscalar(value) && ~ismissing(value) && strlength(strtrim(value))>0, ...
                    'sixgr:phy:pucch:WrongResource','Receiver identity and provenance must be nonempty scalar text.');
            end
            validateattributes(context.ConfigurationEpoch,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(isscalar(context.ReportID) && ~ismissing(context.ReportID) && ...
                strlength(strtrim(context.ReportID))>0, ...
                'sixgr:phy:pucch:MissingUCIReportContext','Receiver report identity must be nonempty scalar text.');
            assert(context.ConfigurationEpoch==rrc.ConfigurationEpoch, ...
                'sixgr:phy:pucch:StaleConfiguration','Receiver hypothesis and installed RRC epochs differ.');
            resource=rrc.resourceByID(data.ResourceID);
            assert(resource.Data.RNTI==data.RNTI, ...
                'sixgr:phy:pucch:WrongRNTI','Receiver RNTI differs from the installed resource.');
            counts=[context.Sequence1Length context.Sequence2Length];
            validateattributes(counts,{'numeric'},{'real','finite','integer','nonnegative','numel',2});
            sixgr.phy.pucch.PUCCHFormatValidator.validateResource(resource.Data,sum(counts));
            obj.Data=data;
            obj.Data.ReportID=context.ReportID;
            obj.Data.ConfigurationEpoch=context.ConfigurationEpoch;
            obj.Resource=resource;
            obj.ReportContextDigest=context.Digest;
            obj.RRCContextDigest=rrc.Digest;
            obj.Digest=sixgr.phy.pucch.PUCCHUtil.hash(struct('Data',obj.Data, ...
                'ResourceDigest',resource.Digest,'ReportContextDigest',context.Digest, ...
                'RRCContextDigest',rrc.Digest));
        end
        function value=get.ReportID(obj), value=string(obj.Data.ReportID); end
        function value=get.ConfigurationEpoch(obj), value=double(obj.Data.ConfigurationEpoch); end
        function value=get.Format(obj), value=obj.Resource.Format; end
    end
end
