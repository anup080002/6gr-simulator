classdef QualificationDomainArtifactAdapter
    %QUALIFICATIONDOMAINARTIFACTADAPTER Lossless domain evidence adapter.
    methods (Static)
        function [adapted,trace] = adapt( ...
                fileName,T,expressions,sourceHash)
            [adapted,trace] = sixgr.integration.qualification. ...
                QualificationArtifactSchemaAdapterRegistry. ...
                adaptEvidence(fileName,T,expressions,sourceHash);
        end

        function aliases = aliases()
            aliases = sixgr.integration.qualification. ...
                QualificationArtifactSchemaAdapterRegistry. ...
                evidenceAliases();
        end
    end
end
