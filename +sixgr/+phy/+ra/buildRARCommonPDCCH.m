function [pdcch,evidence] = buildRARCommonPDCCH(cfg,raCfg,carrier)
%BUILDRARCOMMONPDCCH Bind the decoded Type1 layout to a scheduled occasion.
[pdcch,evidence]=sixgr.phy.ra.resolveRARCommonControl(cfg,carrier);
validateattributes(raCfg.Msg2Slot,{'numeric'},{'scalar','finite','integer','nonnegative'});
period=pdcch.SearchSpace.SlotPeriodAndOffset;
if mod(raCfg.Msg2Slot-period(2),period(1))>=pdcch.SearchSpace.Duration
    error("sixgr:phy:ra:RAROutsideMonitoringOccasion", ...
        "Scheduled Msg2 is outside the decoded Type1 monitoring occasion.");
end
evidence.Slot=double(raCfg.Msg2Slot);
end
