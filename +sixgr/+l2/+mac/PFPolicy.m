classdef PFPolicy < sixgr.l2.mac.SchedulerPolicy
    %PFPOLICY Instantaneous-rate / historical-average policy.
    methods
        function obj=PFPolicy(), obj@sixgr.l2.mac.SchedulerPolicy("PF"); end
        function metrics=score(~,snapshot)
            rows=snapshot.Rows;
            metrics=double(rows.InstantRate)./max(double(rows.AverageRate),eps);
            metrics(~logical(rows.Eligible))=-Inf;
        end
    end
end
