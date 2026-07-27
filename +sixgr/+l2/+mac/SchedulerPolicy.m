classdef (Abstract) SchedulerPolicy
    %SCHEDULERPOLICY Base interface for immutable-snapshot policies.
    properties (SetAccess=immutable)
        Name (1,1) string
    end
    methods
        function obj=SchedulerPolicy(name), obj.Name=string(name); end
    end
    methods (Abstract)
        metrics=score(obj,snapshot)
    end
    methods (Static)
        function policy=create(name)
            switch upper(string(name))
                case "RR", policy=sixgr.l2.mac.RRPolicy();
                case "PF", policy=sixgr.l2.mac.PFPolicy();
                case "QOS-PF", policy=sixgr.l2.mac.QoSPFPolicy();
                case "EDF", policy=sixgr.l2.mac.EDFPolicy();
                otherwise
                    error("sixgr:mac:UnknownSchedulerPolicy", ...
                        "Unknown scheduler policy %s.",string(name));
            end
        end
    end
end
