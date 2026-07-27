classdef PublicationGateEvaluator
    %PUBLICATIONGATEEVALUATOR All-required-evidence publication gate.
    methods (Static)
        function result=evaluate(input)
            if istable(input)
                if height(input)~=1, error("sixgr:validation:SchemaDuplicateKey", ...
                        "Publication gate input must contain one row."); end
                input=table2struct(input);
            end
            fields=["SchemaOK","OracleOK","ProvenanceOK","StatisticsOK", ...
                "CanonicalScenariosOK","RequiredTestsOK","ArtifactsOK","ArchiveOK"];
            for name=fields
                if ~isstruct(input)||~isfield(input,char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Publication gate input is missing %s.",name);
                end
            end
            ok=arrayfun(@(x)localBool(input.(char(x))),fields);
            if ~ok(5)
                error("sixgr:validation:CanonicalScenarioNotExecuted", ...
                    "Mandatory canonical runtime scenarios did not pass.");
            elseif ~ok(6)
                error("sixgr:validation:RequiredTestSkipped", ...
                    "A required validation test was skipped, blocked or failed.");
            elseif ~ok(7)
                error("sixgr:validation:ArtifactMissing", ...
                    "One or more mandatory publication artifacts are missing.");
            elseif ~ok(8)
                error("sixgr:validation:ArchiveSourceMismatch", ...
                    "Clean archive acceptance did not pass.");
            elseif ~all(ok)
                error("sixgr:validation:PublicationGateIncomplete", ...
                    "Schema, oracle, provenance or statistical evidence is incomplete.");
            end
            result=struct("Passed",true,"Status","PASS");
        end
    end
end

function out=localBool(value)
if islogical(value), out=value; return; end
if isnumeric(value)&&ismember(value,[0 1]), out=logical(value); return; end
text=lower(strtrim(string(value)));
if text=="true", out=true;
elseif text=="false", out=false;
else, error("sixgr:validation:SchemaWrongType","Gate Boolean is invalid.");
end
end
