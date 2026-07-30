classdef QualificationArtifactAuditSchema
    %QUALIFICATIONARTIFACTAUDITSCHEMA Versioned finalization audit contract.
    properties (Constant)
        Version = "phase18-artifact-audit/v1"
        ArtifactTypes = ["CSV","PNG","JSON","YAML","MAT","LOG", ...
            "MARKDOWN","TEXT","OTHER"]
        StatusValues = ["PASS","FAIL","MISSING","INVALID_SCHEMA", ...
            "INVALID_HASH","INVALID_SEMANTICS","UNAVAILABLE", ...
            "NOT_APPLICABLE"]
        VariableNames = ["SchemaVersion","RunID","ArtifactID","Domain", ...
            "SubcaseID","RelativePath","ArtifactType","MIMEType", ...
            "Required","Present","Valid","Status","FailureCode","SHA256", ...
            "ByteCount","GeneratedUTC","SourceArtifactIDs", ...
            "SourceCSVRelativePath","SourceCSV_SHA256", ...
            "SemanticAuditStatus","ProvenanceClass", ...
            "PublicationStatus","ArtifactTypeSource","SchemaValid", ...
            "HashValid","SemanticValid"]
    end

    methods (Static)
        function T = empty(rowCount)
            if nargin < 1
                rowCount = 0;
            end
            text = strings(rowCount,1);
            truth = false(rowCount,1);
            count = zeros(rowCount,1);
            T = table( ...
                repmat(sixgr.integration.qualification. ...
                    QualificationArtifactAuditSchema.Version,rowCount,1), ...
                text,text,text,text,text,text,text,truth,truth,truth,text, ...
                text,text,count,text,text,text,text,text,text,text,text, ...
                truth,truth,truth, ...
                'VariableNames',cellstr(sixgr.integration.qualification. ...
                    QualificationArtifactAuditSchema.VariableNames));
        end

        function mimeType = mimeFor(artifactType)
            type = upper(strtrim(string(artifactType)));
            mimeType = repmat("application/octet-stream",size(type));
            mimeType(type=="CSV") = "text/csv";
            mimeType(type=="PNG") = "image/png";
            mimeType(type=="JSON") = "application/json";
            mimeType(type=="YAML") = "application/yaml";
            mimeType(type=="MAT") = "application/x-matlab-data";
            mimeType(type=="LOG" | type=="TEXT") = "text/plain";
            mimeType(type=="MARKDOWN") = "text/markdown";
        end

        function type = typeFromPath(path)
            path = lower(strtrim(string(path)));
            [~,~,extension] = arrayfun(@fileparts,path, ...
                'UniformOutput',false);
            extension = string(extension);
            type = repmat("OTHER",size(path));
            type(extension==".csv") = "CSV";
            type(extension==".png") = "PNG";
            type(extension==".json") = "JSON";
            type(ismember(extension,[".yaml",".yml"])) = "YAML";
            type(extension==".mat") = "MAT";
            type(extension==".log") = "LOG";
            type(ismember(extension,[".md",".markdown"])) = "MARKDOWN";
            type(ismember(extension,[".txt",".text"])) = "TEXT";
        end
    end
end
