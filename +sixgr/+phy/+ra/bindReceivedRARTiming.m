function ra=bindReceivedRARTiming(cfg,ra,grant,receivedSchedule)
% Bind the actual CRC-valid RAR slot/TDRA to subsequent physical allocations.
% The planned Msg2 slot is not receiver authority.
ra=sixgr.mac.ra.bindReceivedRARIdentity(ra,grant);
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
window=ra.RARMonitoringWindow;
take=window.MonitoringSlots==ra.Msg2Slot;
window.MonitoringSlots=window.MonitoringSlots(take);
window.MonitoringStartTicks=window.MonitoringStartTicks(take);
timing=ra.TimingSchedule;
% Rebinding to received DCI changes the clock, not installed common-channel
% ownership. Use the decoded Msg2 allocation, then retain the same resource
% planner used before reception when selecting the future Msg4 occasion.
msg2Allocation=ra.Msg2PDSCH;
msg2Allocation.PRBStart=double(receivedSchedule.PRBStart);
msg2Allocation.NumPRB=double(receivedSchedule.NumPRB);
msg2Allocation.SymbolStart=double(receivedSchedule.PDSCH.SymbolAllocation(1));
msg2Allocation.NumSymbols=double(receivedSchedule.PDSCH.SymbolAllocation(2));
commonDL=sixgr.phy.frame.CommonDLResourcePlan(cfg);
commonDL.validateSIB1References();
stageAllocations=struct('Msg2',msg2Allocation,'Msg4',ra.Msg4PDSCH);
schedule=sixgr.phy.ia.RAEventScheduler.resolve( ...
    'PDSCHResourceAvailability',@(stage,slot0) commonDL.checkPDSCH(stageAllocations.(stage),slot0), ...
    'RARMonitoringWindow',window,'PRACHOccasionEndSlot',ra.PRACHOccasionEndSlot, ...
    'RAResponseWindowSlots',ra.RAResponseWindowSlots, ...
    'RARProcessingDelaySlots',max(1,ra.Msg2Slot-ra.PRACHOccasionEndSlot), ...
    'Msg3K2Slots',grant.K2,'Msg3TimeDomainAllocation',grant.TimeDomainAllocation, ...
    'Msg4ProcessingDelaySlots',timing.Msg4ProcessingDelaySlots, ...
    'ContentionResolutionTimerSlots',ra.RAContentionResolutionTimerSlots, ...
    'SetupCompleteK2Slots',timing.SetupCompleteK2Slots, ...
    'RequireSetupComplete',ra.RequireRRCSetupComplete,'FrameEngine',frame, ...
    'Msg2SymbolAllocation',double(receivedSchedule.PDSCH.SymbolAllocation), ...
    'Msg4SymbolAllocation',[ra.Msg4PDSCH.SymbolStart ra.Msg4PDSCH.NumSymbols], ...
    'SetupCompleteSymbolAllocation',[ra.SetupCompletePUSCH.SymbolStart ra.SetupCompletePUSCH.NumSymbols]);
if schedule.Msg2Slot~=ra.Msg2Slot
    error('sixgr:phy:ra:ReceivedRARSlotChanged','A decoded RAR cannot be moved to another planned slot.');
end
ra.TimingSchedule=schedule;
ra.Msg2PDSCH=msg2Allocation;
ra.Msg3Slot=schedule.Msg3Slot; ra.Msg4Slot=schedule.Msg4Slot;
ra.SetupCompleteSlot=schedule.SetupCompleteSlot;
sixgr.phy.ra.resolveMsg3SlotFromRAR(ra,grant);
end
