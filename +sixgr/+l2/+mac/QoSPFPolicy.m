classdef QoSPFPolicy < sixgr.l2.mac.SchedulerPolicy
    %QOSPFPOLICY PF with bounded priority and delay urgency weights.
    methods
        function obj=QoSPFPolicy(), obj@sixgr.l2.mac.SchedulerPolicy("QoS-PF"); end
        function metrics=score(~,snapshot)
            rows=snapshot.Rows;
            pf=double(rows.InstantRate)./max(double(rows.AverageRate),eps);
            priorityWeight=max(1,9-double(rows.Priority));
            urgency=1+double(rows.HoLDelay_ms)./max(double(rows.PDB_ms),eps);
            metrics=pf.*priorityWeight.*urgency;
            metrics(~logical(rows.Eligible))=-Inf;
        end
    end
end
