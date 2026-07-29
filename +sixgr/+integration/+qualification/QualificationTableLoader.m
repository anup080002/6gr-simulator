classdef QualificationTableLoader
    %QUALIFICATIONTABLELOADER Load exact, hash-bound qualification tables.
    methods (Static)
        function loaded = load(resolver, identity, expressions, ...
                applyAdapters)
            if nargin<4
                applyAdapters = true;
            end
            resolution = sixgr.integration.qualification. ...
                ArtifactResolver.resolve(resolver,identity);
            if ~resolution.Resolved
                error(char(localResolutionError(resolution)), ...
                    "%s",resolution.Details);
            end
            try
                T = readtable(resolution.FullPath,"TextType","string", ...
                    "VariableNamingRule","preserve");
            catch ME
                error("FULLSTACK:ValueSourceUnreadable", ...
                    "Unable to read %s: %s",resolution.RelativePath,ME.message);
            end
            if height(T)==0
                error("FULLSTACK:ValueSourceEmpty", ...
                    "Required value source '%s' is empty.",identity);
            end
            adapterRows = sixgr.integration.qualification. ...
                EvidenceAdapterRegistry.emptyResults();
            if applyAdapters
                [T,adapterRows] = sixgr.integration.qualification. ...
                    EvidenceAdapterRegistry.adapt( ...
                    resolution.FileName,T,string(expressions), ...
                    resolution.ActualSHA256);
            end
            loaded = struct("Table",T,"Resolution",resolution, ...
                "AdapterResults",adapterRows);
        end
    end
end

function code = localResolutionError(resolution)
code = string(resolution.FailureCode);
if strlength(code)==0
    code = "FULLSTACK:ValueSourceMissing";
end
end
