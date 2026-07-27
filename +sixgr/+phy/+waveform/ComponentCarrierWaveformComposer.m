classdef ComponentCarrierWaveformComposer
    %COMPONENTCARRIERWAVEFORMCOMPOSER Stateful common-clock CC composition.
    methods (Static)
        function result=compose(carriers,commonRate)
            for i=1:numel(carriers)
                carriers(i).ComponentID=string(sixgr.util.structGet(carriers(i),"CCID","CC-"+i));
            end
            result=sixgr.phy.waveform.MultiNumerologyWaveformComposer.compose( ...
                carriers,commonRate);
            result.CarrierCount=numel(carriers);
        end
    end
end
