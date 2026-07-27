classdef EvidenceRecord
    %EVIDENCERECORD One typed evidence DAG node.
    properties (SetAccess=private)
        Data struct
    end
    methods
        function obj = EvidenceRecord(input)
            required = ["NodeID","FieldName","Value","Unit", ...
                "ProvenanceClass","RootID","ParentNodeIDs","FormulaID", ...
                "Producer","SourceArtifact","Timestamp","ConfigurationEpoch"];
            if istable(input)
                if height(input)~=1, error("sixgr:validation:SchemaDuplicateKey", ...
                        "Evidence record must contain one row."); end
                input=table2struct(input);
            end
            for name=required
                if ~isstruct(input)||~isfield(input,char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Evidence record is missing %s.",name);
                end
            end
            input.ProvenanceClass = ...
                sixgr.validation.EvidenceProvenanceClass.parse(input.ProvenanceClass);
            obj.Data=input;
        end
        function out=toStruct(obj), out=obj.Data; end
    end
end
