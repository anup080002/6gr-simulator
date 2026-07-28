classdef ComponentCarrierState < sixgr.phy.waveform.MultiNumerologyComponentState
    %COMPONENTCARRIERSTATE Persistent state for one component carrier.

    properties (SetAccess=private)
        CCID (1,1) string
        CenterFrequency_Hz (1,1) double
    end

    methods
        function obj = ComponentCarrierState( ...
                ccID,centerFrequency,sampleRate,frequencyOffset,epoch)
            if nargin<5, epoch=0; end
            obj@sixgr.phy.waveform.MultiNumerologyComponentState( ...
                ccID,sampleRate,frequencyOffset,epoch);
            obj.CCID = string(ccID);
            obj.CenterFrequency_Hz = double(centerFrequency);
        end
    end
end
