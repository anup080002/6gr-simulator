classdef EDFPolicy < sixgr.l2.mac.SchedulerPolicy
    %EDFPOLICY Earliest nonnegative remaining packet deadline first.
    methods
        function obj=EDFPolicy(), obj@sixgr.l2.mac.SchedulerPolicy("EDF"); end
        function metrics=score(~,snapshot)
            rows=snapshot.Rows;
            metrics=-max(double(rows.PDB_ms)-double(rows.HoLDelay_ms),0);
            metrics(~logical(rows.Eligible))=-Inf;
        end
    end
end
