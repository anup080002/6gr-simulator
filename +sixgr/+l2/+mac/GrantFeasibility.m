classdef GrantFeasibility
    %GRANTFEASIBILITY Read-only legal-resource and authority validation.
    methods (Static)
        function result=evaluate(candidate)
            if ~isa(candidate,"sixgr.l2.mac.CandidateGrant")
                error("sixgr:mac:InvalidGrantCandidate","Expected CandidateGrant.");
            end
            data=candidate.Data;
            required=["DecodedDCIEventID","UEID","ServingCell","ScheduledCell", ...
                "Direction","BWPID","PRBSet","SymbolAllocation","MCS", ...
                "TBSBits","HARQProcess","Codeword","NDIEpoch","RV", ...
                "ConfigurationEpoch","ActiveConfigurationEpoch","Eligible"];
            reasons=strings(0,1);
            for field=required
                if ~isfield(data,field), reasons(end+1,1)="missing_"+field; end %#ok<AGROW>
            end
            if ~isempty(reasons)
                result=struct("Feasible",false,"Reasons",join(reasons,"|")); return;
            end
            if strlength(string(data.DecodedDCIEventID))==0
                reasons(end+1,1)="decoded_authority_missing";
            end
            if ~logical(data.Eligible), reasons(end+1,1)="ue_ineligible"; end
            if double(data.ConfigurationEpoch)~=double(data.ActiveConfigurationEpoch)
                reasons(end+1,1)="stale_configuration_epoch";
            end
            if isempty(data.PRBSet) || numel(data.SymbolAllocation)~=2 || ...
                    data.SymbolAllocation(2)<1 || data.TBSBits<=0
                reasons(end+1,1)="invalid_phy_allocation";
            end
            result=struct("Feasible",isempty(reasons),"Reasons",join(reasons,"|"));
        end
    end
end
