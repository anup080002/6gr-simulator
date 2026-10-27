function out=srsPathPowerEvidence(result)
% Fixed schema for a received-path diagnostic; no default observed values.
out=struct('SRSPathPowerAvailable',false,'SRSPathPowerStatus',"disabled", ...
    'SRSPathPowerEvidenceJSON',"",'SRSPathPowerEvidenceSHA256',"", ...
    'SRSPathPowerDetectedCount',0,'SRSPathPowerReferencePlane',"", ...
    'SRSPathPowerIndependentAccuracyQualified',false,'SRSPathPowerHardwareQualified',false, ...
    'SRSPathPowerStandardizedReferencePointQualified',false, ...
    'SRSPathPowerFirstDetectedPerPortBranchJSON',"",'SRSPathPowerErrorIdentifier',"");
if nargin==0, return; end
out.SRSPathPowerAvailable=result.Available; out.SRSPathPowerStatus=string(result.Status);
out.SRSPathPowerDetectedCount=numel(result.Paths);
token=string(jsonencode(sixgr.util.jsonSafeValue(result)));
out.SRSPathPowerEvidenceJSON=token; out.SRSPathPowerEvidenceSHA256=sixgr.util.sha256Hex(char(token));
if isfield(result,'Binding'), out.SRSPathPowerReferencePlane=string(result.Binding.ReferencePlane); end
if ~isempty(result.Paths)
    out.SRSPathPowerFirstDetectedPerPortBranchJSON=string(jsonencode(result.Paths([result.Paths.FirstDetectedPath])));
end
end
