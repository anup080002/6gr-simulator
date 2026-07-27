classdef ArchiveAcceptanceRunner
    %ARCHIVEACCEPTANCERUNNER Fail-closed clean archive acceptance checks.
    methods (Static)
        function result=validate(input)
            if istable(input)
                if height(input)~=1, error("sixgr:validation:SchemaDuplicateKey", ...
                        "Archive acceptance validates one archive."); end
                input=table2struct(input);
            end
            if upper(string(input.SourceTreeHash))~="MATCH" || ...
                    upper(string(input.ScenarioHash))~="MATCH"
                error("sixgr:validation:ArchiveSourceMismatch", ...
                    "Archive source or scenario hash does not match its manifest.");
            end
            if upper(string(input.Freshness))~="FRESH"
                error("sixgr:validation:ArtifactStale", ...
                    "Archive acceptance detected stale runtime artifacts.");
            end
            if upper(string(input.Toolchain))~="PINNED"
                error("sixgr:validation:MATLABUnavailable", ...
                    "Pinned MATLAB/toolbox execution evidence is unavailable.");
            end
            runtime=upper(string(input.RuntimeEvidence));
            if ismember(runtime,["MISSING_CANONICAL","FIXTURE_ONLY"])
                error("sixgr:validation:CanonicalScenarioNotExecuted", ...
                    "Fresh canonical runtime scenarios were not executed.");
            elseif runtime~="ALL_PASS"
                error("sixgr:validation:RequiredTestSkipped", ...
                    "Required archive tests or scenarios did not pass.");
            end
            result=struct("Passed",true,"Status","PASS");
        end
    end
end
