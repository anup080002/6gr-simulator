classdef ArtifactAuditResult
    %ARTIFACTAUDITRESULT Immutable artifact audit result.
    properties (SetAccess=private)
        Data struct
    end
    methods
        function obj=ArtifactAuditResult(data), obj.Data=data; end
        function out=passed(obj)
            out=isfield(obj.Data,"Status")&&string(obj.Data.Status)=="PASS";
        end
        function out=toStruct(obj), out=obj.Data; end
    end
end
