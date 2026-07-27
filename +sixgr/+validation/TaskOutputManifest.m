classdef TaskOutputManifest
    %TASKOUTPUTMANIFEST Immutable checksummed task output descriptor.
    methods (Static)
        function out=validate(input)
            required=["TaskID","OutputSHA256","RetryIndex"];
            if ~istable(input)||any(~ismember(required,string(input.Properties.VariableNames)))
                error("sixgr:validation:SchemaMissingColumn", ...
                    "Task output manifest is missing mandatory columns.");
            end
            hashes=lower(string(input.OutputSHA256));
            for hash=reshape(hashes,1,[])
                if strlength(hash)~=64 || ...
                        isempty(regexp(char(hash),"^[0-9a-f]{64}$","once"))
                    error("sixgr:validation:ArtifactHashMismatch", ...
                        "Task output hash must be a SHA-256 digest.");
                end
            end
            out=input;
        end
    end
end
