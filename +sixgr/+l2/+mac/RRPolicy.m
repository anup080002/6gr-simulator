classdef RRPolicy < sixgr.l2.mac.SchedulerPolicy
    %RRPOLICY Deterministic round-robin rank over eligible snapshot rows.
    methods
        function obj=RRPolicy(), obj@sixgr.l2.mac.SchedulerPolicy("RR"); end
        function metrics=score(~,snapshot)
            rows=snapshot.Rows;
            if ismember("NumUE",string(rows.Properties.VariableNames))
                numUE=max(1,double(rows.NumUE));
            else
                numUE=repmat(max(1,height(rows)),height(rows),1);
            end
            if ismember("Seed",string(rows.Properties.VariableNames))
                offset=double(rows.Seed)+1;
            else
                offset=zeros(height(rows),1);
            end
            metrics=mod(double(rows.UEID)-1+offset,numUE);
            metrics(~logical(rows.Eligible))=-Inf;
        end
    end
end
