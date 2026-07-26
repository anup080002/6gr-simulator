classdef PUCCHBWPState
    %PUCCHBWPSTATE Causal active-UL-BWP switch state.

    properties (SetAccess=private)
        ActiveBWP
        ConfiguredBWPs
        ActivationEventID
        ConfigurationEpoch
        Digest
    end

    methods
        function obj = PUCCHBWPState(configuredBWPs,activeBWP,eventID,epoch)
            configuredBWPs = unique(double(configuredBWPs(:).'),"stable");
            if isempty(configuredBWPs) || any(~isfinite(configuredBWPs)) || ...
                    any(configuredBWPs<0 | configuredBWPs~=fix(configuredBWPs))
                error("sixgr:phy:pucch:StaleBWP", ...
                    "Configured UL BWPs must be explicit nonnegative integers.");
            end
            if ~ismember(double(activeBWP),configuredBWPs) || ...
                    strlength(string(eventID))==0
                error("sixgr:phy:pucch:StaleBWP", ...
                    "Active UL BWP requires a decoded activation event.");
            end
            sixgr.phy.pucch.PUCCHUtil.assertInteger(epoch,0,flintmax, ...
                "sixgr:phy:pucch:StaleConfiguration","ConfigurationEpoch");
            obj.ActiveBWP = double(activeBWP);
            obj.ConfiguredBWPs = configuredBWPs;
            obj.ActivationEventID = string(eventID);
            obj.ConfigurationEpoch = double(epoch);
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(struct( ...
                "ActiveBWP",obj.ActiveBWP, ...
                "ConfiguredBWPs",obj.ConfiguredBWPs, ...
                "ActivationEventID",obj.ActivationEventID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch));
        end
    end
end
