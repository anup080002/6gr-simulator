classdef FailingWaveformChannel < sixgr.channel.StaticReciprocalMIMOChannel
    % Declared fault-injection fixture, not a measured native-channel fault.
    properties
        Calls = 0
    end
    methods
        function obj=FailingWaveformChannel()
            obj@sixgr.channel.StaticReciprocalMIMOChannel(1,7.68e6);
        end
    end
    methods (Access=protected)
        function [y,h]=stepImpl(obj,~)
            obj.Calls=obj.Calls+1;
            y=[]; h=[]; %#ok<NASGU>
            error('sixgrtest:InjectedWaveformFailure','Declared failure after state mutation.');
        end
    end
end
