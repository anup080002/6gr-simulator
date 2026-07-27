classdef MACCEPriorityResolver
    %MACCEPRIORITYRESOLVER Procedure-owned CE ordering and fit decision.
    methods (Static)
        function decision=select(triggeredCEs,grantBytes)
            order=["C_RNTI","BFR","TA_REPORT","BSR","PHR", ...
                "CG_CONFIRM","CONFIGURED_GRANT_CONFIRMATION", ...
                "SR","DATA","PADDING"];
            names=upper(string({triggeredCEs.Name}));
            [~,rank]=ismember(names,order); rank(rank==0)=numel(order)+1;
            [~,indices]=sort(rank);
            remaining=grantBytes; selected=strings(0,1); rejected=strings(0,1);
            for ii=indices
                bytes=double(triggeredCEs(ii).RequiredBytes);
                if bytes<=remaining
                    selected(end+1,1)=names(ii); %#ok<AGROW>
                    remaining=remaining-bytes;
                else
                    rejected(end+1,1)=names(ii); %#ok<AGROW>
                end
            end
            decision=struct("Selected",selected,"Rejected",rejected, ...
                "RemainingBytes",remaining);
        end
    end
end
