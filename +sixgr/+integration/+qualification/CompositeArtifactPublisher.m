classdef CompositeArtifactPublisher
    %COMPOSITEARTIFACTPUBLISHER Mandatory filesystem plus optional database.
    methods (Static)
        function result=publish(runID,runRoot,audit,varargin)
            parser=inputParser;
            parser.addParameter("DatabaseMandatory",false, ...
                @(x)islogical(x)&&isscalar(x));
            parser.parse(varargin{:});
            filesystem=sixgr.integration.qualification. ...
                FilesystemArtifactPublisher.publish(runID,runRoot,audit);
            database=sixgr.integration.qualification. ...
                DatabaseArtifactPublisher.publish(runID,runRoot,audit, ...
                "Mandatory",parser.Results.DatabaseMandatory);
            result=struct("Filesystem",filesystem,"Database",database, ...
                "Status",localStatus(filesystem,database, ...
                parser.Results.DatabaseMandatory));
        end
    end
end

function status=localStatus(filesystem,database,databaseMandatory)
passed=all(filesystem.Status=="PASS");
if databaseMandatory
    passed=passed && all(database.Status=="PASS");
end
if passed,status="PASS";else,status="FAIL";end
end
