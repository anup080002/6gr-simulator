classdef MultiNumerologyComponentState < handle
    %MULTINUMEROLOGYCOMPONENTSTATE Persistent state for one BWP component.

    properties (SetAccess=private)
        ComponentID (1,1) string
        SampleRate_Hz (1,1) double
        FrequencyOffset_Hz (1,1) double
        StreamState
    end

    methods
        function obj = MultiNumerologyComponentState( ...
                componentID,sampleRate,frequencyOffset,epoch)
            if nargin<4, epoch=0; end
            obj.ComponentID = string(componentID);
            obj.SampleRate_Hz = double(sampleRate);
            obj.FrequencyOffset_Hz = double(frequencyOffset);
            obj.StreamState = sixgr.phy.waveform.OFDMStreamState( ...
                sampleRate,epoch);
        end
    end
end
