classdef PUSCHUCIReceiveContext
    % Payload-free PUSCH receive obligation; scheduling authority is upstream.
    % Never construct this from a UE report or from ExpectedUCIPayload.
    % Digests bind identities; the physical owner must prove those identities
    % against its transmitted schedule and installed configuration at capture.
    properties (SetAccess=private)
        Data
        Digest
    end
    methods
        function obj=PUSCHUCIReceiveContext(data)
            names=["ObservationID","ConfigurationEpoch","AssignmentDigest", ...
                "HARQMappingDigest","HARQACKBitCount","ConfiguredGrantUCIBitCount", ...
                "CSIReportConfigID","CSIConfigurationEpoch"];
            assert(isstruct(data) && isscalar(data) && all(isfield(data,names)) && ...
                isempty(setdiff(string(fieldnames(data)),names)), ...
                'sixgr:pusch:InvalidUCIReceiveObligation', ...
                'Use only receiver identities and configured counts, not payloads or UE state.');
            for name=["ConfigurationEpoch","HARQACKBitCount","ConfiguredGrantUCIBitCount"]
                localCount(data.(name));
                data.(name)=double(data.(name));
            end
            for name=["ObservationID","AssignmentDigest","HARQMappingDigest","CSIReportConfigID"]
                value=data.(name);
                assert((isstring(value) && isscalar(value)) || ...
                    (ischar(value) && (isrow(value)||isempty(value))), ...
                    'sixgr:pusch:InvalidUCIReceiveObligation','Receive identities must be scalar text.');
                value=string(value);
                assert(~ismissing(value) && value==strtrim(value), ...
                    'sixgr:pusch:InvalidUCIReceiveObligation','Receive identities cannot be missing or padded.');
                data.(name)=value;
            end
            assert(strlength(data.ObservationID)>0 && strlength(data.AssignmentDigest)>0 && ...
                ((data.HARQACKBitCount>0)==(strlength(data.HARQMappingDigest)>0)), ...
                'sixgr:pusch:InvalidUCIReceiveObligation', ...
                'Retain the actual receive occasion, UL assignment and nonempty HARQ mapping identity.');
            if strlength(data.CSIReportConfigID)==0
                assert(isnumeric(data.CSIConfigurationEpoch) && ...
                    isscalar(data.CSIConfigurationEpoch) && isreal(data.CSIConfigurationEpoch) && ...
                    isnan(data.CSIConfigurationEpoch), ...
                    'sixgr:pusch:InvalidUCIReceiveObligation','Absent CSI has no report epoch.');
            else
                localCount(data.CSIConfigurationEpoch);
                data.CSIConfigurationEpoch=double(data.CSIConfigurationEpoch);
            end
            obj.Data=data;
            obj.Digest=sixgr.phy.pucch.PUCCHUtil.hash(data);
        end

        function p=bitBudget(obj,reportConfig)
            if nargin<2, reportConfig=[]; end
            d=obj.Data;
            p=struct('OACK',d.HARQACKBitCount,'OCSI1',0,'OCSI2',0, ...
                'OCGUCI',d.ConfiguredGrantUCIBitCount);
            if strlength(d.CSIReportConfigID)==0
                assert(isempty(reportConfig),'sixgr:pusch:CSIReceiveConfigurationMismatch', ...
                    'An unscheduled CSI report must not change the receiver schema.');
            else
                assert(isa(reportConfig,'sixgr.phy.mimo.CSIReportConfiguration') && isscalar(reportConfig), ...
                    'sixgr:pusch:MissingCSIReportConfiguration', ...
                    'Scheduled CSI requires its installed typed report configuration.');
                reportConfig.assertQualifiedWireLayout();
                assert(reportConfig.UCIChannel=="PUSCH" && ...
                    reportConfig.ReportConfigID==d.CSIReportConfigID && ...
                    reportConfig.Epoch==d.CSIConfigurationEpoch, ...
                    'sixgr:pusch:CSIReceiveConfigurationMismatch', ...
                    'Bind the installed CSI report identity, epoch and PUSCH transport.');
                p.OCSI1=reportConfig.part1BitCount();
                % Part 2 deliberately remains unresolved here. Only received
                % Part 1 plus the installed schema may choose its length.
            end
        end
    end
end

function localCount(value)
assert(isnumeric(value) && isscalar(value) && isreal(value) && ...
    isfinite(value) && value>=0 && value==fix(value), ...
    'sixgr:pusch:InvalidUCIReceiveObligation','Receive counts and epochs must be exact nonnegative integers.');
end
