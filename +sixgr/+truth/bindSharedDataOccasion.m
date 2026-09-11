function [cfg,occasion]=bindSharedDataOccasion(cfg,absoluteSlotOneBased,frameOneBased,sampleRateHz)
% Bind a scheduled waveform calendar, without advancing any runtime state.
% The control reception/decision time is NOT the future data-slot origin.
validateattributes(sampleRateHz,{'numeric'},{'scalar','real','finite','positive'});
[cfg,timeline]=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,absoluteSlotOneBased,frameOneBased);
carrier=sixgr.phy.grid.makeCarrier(cfg);
first=sixgr.phy.frame.slotStartSample(carrier,absoluteSlotOneBased-1,sampleRateHz);
stop=sixgr.phy.frame.slotStartSample(carrier,absoluteSlotOneBased,sampleRateHz);
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSlotStartTime_s',first/sampleRateHz);
occasion=struct('Timeline',timeline,'StartSample',first,'EndSampleExclusive',stop, ...
    'SampleRateHz',sampleRateHz,'Source',"scheduled_data_occasion_not_control_reception_time");
end
