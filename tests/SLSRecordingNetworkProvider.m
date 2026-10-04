classdef SLSRecordingNetworkProvider < sixgr.system.abstraction.NetworkSpatialGrantProvider
    % Test-only capture of the actual last evaluated network population.
    % Does not alter observations or extend production causal history.
    properties (SetAccess=private)
        LastEvaluatedState struct = struct()
    end
    methods
        function obj=SLSRecordingNetworkProvider(cfg)
            obj@sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
        end
        function o=evaluate(obj,ctx,state)
            o=evaluate@sixgr.system.abstraction.NetworkSpatialGrantProvider(obj,ctx,state);
            obj.LastEvaluatedState=state;
        end
    end
end
