classdef LogicalChannelPrioritizer
    %LOGICALCHANNELPRIORITIZER Procedure-owned LCP over configured channels.
    methods (Static)
        function decision=select(channels,grantBytes,cellID,scsKHz)
            priorities=cellfun(@(x)x.Priority,channels);
            [~,order]=sort(priorities,"ascend");
            remaining=grantBytes;
            rows=repmat(struct("LCID",0,"Priority",0,"BjBefore",0, ...
                "EligibleBytes",0,"SelectedBytes",0,"BjAfter",0, ...
                "SelectionOrder",0,"RejectionReason",""),numel(channels),1);
            for jj=1:numel(order)
                ii=order(jj); channel=channels{ii}; before=channel.Bj_Bytes;
                reason="";
                try
                    selected=channel.serve(remaining,cellID,scsKHz);
                catch ME
                    if ME.identifier=="sixgr:mac:LogicalChannelRestriction"
                        selected=0; reason="restriction";
                    else
                        rethrow(ME);
                    end
                end
                remaining=remaining-selected;
                rows(jj)=struct("LCID",channel.LCID, ...
                    "Priority",channel.Priority,"BjBefore",before, ...
                    "EligibleBytes",min(before,channel.QueueBytes+selected), ...
                    "SelectedBytes",selected,"BjAfter",channel.Bj_Bytes, ...
                    "SelectionOrder",jj,"RejectionReason",reason);
            end
            decision=struct2table(rows);
        end
    end
end
