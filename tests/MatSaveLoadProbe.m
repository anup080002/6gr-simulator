classdef MatSaveLoadProbe < handle
    % Explicit persistence fixture; never a physical receiver or result.
    properties
        Samples
    end
    methods
        function obj=MatSaveLoadProbe(samples)
            obj.Samples=samples;
        end
        function state=saveobj(obj)
            state=struct('Samples',obj.Samples);
        end
    end
    methods (Static)
        function obj=loadobj(state)
            MatSaveLoadProbe.loadCount("increment");
            obj=MatSaveLoadProbe(state.Samples);
        end
        function value=loadCount(action)
            persistent count
            if isempty(count), count=0; end
            if action=="reset", count=0; end
            if action=="increment", count=count+1; end
            value=count;
        end
    end
end
