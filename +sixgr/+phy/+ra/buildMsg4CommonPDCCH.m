function [pdcch,evidence] = buildMsg4CommonPDCCH(cfg,raCfg,carrier)
% Msg4 uses the configured Type1 common search space, not a TX oracle.
[pdcch,evidence] = sixgr.phy.ra.resolveRARCommonControl(cfg,carrier);
period = pdcch.SearchSpace.SlotPeriodAndOffset;
assert(mod(raCfg.Msg4Slot-period(2),period(1))<pdcch.SearchSpace.Duration, ...
    'sixgr:phy:ra:Msg4OutsideMonitoringOccasion','Msg4 is outside the common monitoring occasion.');
frame = sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
assert(frame.IsDLAllocation(raCfg.Msg4Slot, ...
    [pdcch.SearchSpace.StartSymbolWithinSlot pdcch.CORESET.Duration]), ...
    'sixgr:phy:ra:Msg4ControlNotDL','Msg4 CORESET symbols must be DL-eligible.');
evidence.Slot=double(raCfg.Msg4Slot);
evidence.Procedure="msg4_contention_resolution";
end
