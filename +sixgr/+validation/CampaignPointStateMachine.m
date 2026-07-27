classdef CampaignPointStateMachine
    %CAMPAIGNPOINTSTATEMACHINE Canonical point transition authority.
    methods (Static)
        function result = evaluate(errorCount,trialCount,design,lookIndex)
            result = sixgr.validation.SequentialStoppingPolicy.evaluate( ...
                errorCount,trialCount,design,lookIndex);
        end
        function requirePassing(status)
            status = sixgr.validation.PointStatus.parse(status);
            if ~ismember(status,["COMPLETE","CENSORED_COMPLETE"])
                error("sixgr:validation:IncompleteMandatoryPoint", ...
                    "Mandatory point status %s is not passing.",status);
            end
        end
    end
end
