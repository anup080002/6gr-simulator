classdef GrantCommit
    %GRANTCOMMIT Two-phase atomic candidate commit.
    methods (Static)
        function [grant,state]=commit(candidate,state)
            checkpoint=state;
            result=sixgr.l2.mac.GrantFeasibility.evaluate(candidate);
            if ~result.Feasible
                state=checkpoint;
                error("sixgr:mac:GrantFeasibilityRejected", ...
                    "Grant rejected: %s.",result.Reasons);
            end
            data=candidate.Data;
            try
                state.QueueBytes=state.QueueBytes-ceil(double(data.TBSBits)/8);
                if state.QueueBytes<0
                    error("sixgr:mac:QueueUnderflow","Grant exceeds queued bytes.");
                end
                state.HARQReserved=true;
                grant=data;
                grant.CandidateID=candidate.CandidateID;
                grant.Committed=true;
                grant.GrantID=sixgr.l2.mac.MACHash.of(struct( ...
                    "CandidateID",candidate.CandidateID, ...
                    "DecodedDCIEventID",string(data.DecodedDCIEventID), ...
                    "TBSBits",double(data.TBSBits)));
                grant.GrantSHA256=sixgr.l2.mac.MACHash.of(grant);
            catch ME
                state=checkpoint;
                rethrow(ME);
            end
        end
    end
end
