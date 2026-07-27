classdef ArtifactRequirementRegistry
    %ARTIFACTREQUIREMENTREGISTRY Launch-surface-independent requirements.
    methods (Static)
        function result=validate(input)
            required=["Artifact","Mandatory","Generated","Valid"];
            if istable(input)
                if height(input)~=1
                    error("sixgr:validation:SchemaDuplicateKey", ...
                        "Artifact validation accepts one requirement row.");
                end
                input=table2struct(input);
            end
            for name=required
                if ~isstruct(input)||~isfield(input,char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Artifact requirement is missing %s.",name);
                end
            end
            mandatory=localBool(input.Mandatory);
            generated=localBool(input.Generated);
            valid=localBool(input.Valid);
            if mandatory && ~generated
                error("sixgr:validation:ArtifactMissing", ...
                    "Mandatory artifact %s is missing.",string(input.Artifact));
            end
            if mandatory && ~valid
                error("sixgr:validation:ArtifactHashMismatch", ...
                    "Mandatory artifact %s failed validation.",string(input.Artifact));
            end
            result=struct("Artifact",string(input.Artifact), ...
                "Mandatory",mandatory,"Generated",generated, ...
                "Valid",valid,"Status","PASS");
        end
    end
end

function out=localBool(value)
if islogical(value), out=value; return; end
if isnumeric(value)&&ismember(value,[0 1]), out=logical(value); return; end
text=lower(strtrim(string(value)));
if text=="true", out=true;
elseif text=="false", out=false;
else, error("sixgr:validation:SchemaWrongType","Boolean field is invalid.");
end
end
