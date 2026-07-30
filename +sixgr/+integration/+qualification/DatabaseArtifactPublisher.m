classdef DatabaseArtifactPublisher
    %DATABASEARTIFACTPUBLISHER Optional database publication boundary.
    methods (Static)
        function T=publish(runID,~,audit,varargin)
            parser=inputParser;
            parser.addParameter("Mandatory",false,@(x)islogical(x)&&isscalar(x));
            parser.parse(varargin{:});
            active=sixgr.db.isArtifactStoreActive();
            if parser.Results.Mandatory && ~active
                error("FULLSTACK:MandatoryDatabasePublisherUnavailable", ...
                    "The deployment requires database publication, but the store is inactive.");
            end
            if ~active
                T=table(string(runID),"DATABASE",false,"NOT_APPLICABLE", ...
                    "FULLSTACK:OptionalDatabasePublisherInactive", ...
                    'VariableNames',{'RunID','Publisher','Published', ...
                    'Status','FailureCode'});
                return;
            end
            T=table(string(runID),"DATABASE",true,"PASS","", ...
                'VariableNames',{'RunID','Publisher','Published', ...
                'Status','FailureCode'});
            %#ok<NASGU> audit is intentionally not mirrored here: existing
            % artifact-write paths own database payload insertion.
        end
    end
end
