classdef UEEligibilityEngine
    %UEELIGIBILITYENGINE Central all-reason scheduling eligibility gate.
    methods (Static)
        function decision=evaluate(context)
            arguments
                context (1,1) struct
            end
            names=["RRCEligible","BWPEligible","DRXEligible","GapEligible", ...
                "HalfDuplexEligible","TDDEligible","TAEligible", ...
                "PowerEligible","ControlEligible"];
            reasons=strings(0,1); values=false(size(names));
            for ii=1:numel(names)
                if ~isfield(context,names(ii))
                    error("sixgr:mac:MissingEligibilityInput", ...
                        "Eligibility context requires %s.",names(ii));
                end
                values(ii)=logical(context.(names(ii)));
                if ~values(ii), reasons(end+1,1)=names(ii); end %#ok<AGROW>
            end
            decision=context;
            decision.OverallEligible=all(values);
            decision.Reasons=join(reasons,"|");
        end
    end
end
