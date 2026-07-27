classdef SchedulerSnapshot
    %SCHEDULERSNAPSHOT Immutable policy input shared by RR/PF/QoS-PF/EDF.
    properties (SetAccess=immutable)
        Rows table
        SnapshotID (1,1) string
    end
    methods
        function obj=SchedulerSnapshot(rows)
            arguments
                rows table
            end
            required={'UEID','ServingCell','Direction','QueueBytes', ...
                'HoLDelay_ms','PDB_ms','Priority','InstantRate', ...
                'AverageRate','Eligible'};
            if ~all(ismember(required,rows.Properties.VariableNames))
                error("sixgr:mac:InvalidSchedulerSnapshot", ...
                    "Scheduler snapshot lacks required columns. Actual: %s.", ...
                    strjoin(rows.Properties.VariableNames,","));
            end
            obj.Rows=rows;
            obj.SnapshotID=sixgr.l2.mac.MACHash.of(table2struct(rows));
        end
    end
end
