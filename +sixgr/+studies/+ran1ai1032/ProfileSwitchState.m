classdef ProfileSwitchState
    %PROFILESWITCHSTATE Explicit Option-B configuration state machine.
    %
    % A profile transition changes only the meaning available to future new
    % TB grants.  Retransmissions remain bound to the immutable profile and
    % MCS entry stored in their HARQ TB context.

    properties (SetAccess = private)
        ActiveProfile (1,1) string = "baseline"
        PendingProfile (1,1) string = ""
        State (1,1) string = "active"
        ConfigurationEpoch (1,1) double = 0
        MessageID (1,1) string = ""
        RequestSlot (1,1) double = NaN
        ConfirmationSlot (1,1) double = NaN
        ActivationSlot (1,1) double = NaN
        TransitionDelaySlots (1,1) double = 0
        MaxStateAgeSlots (1,1) double = Inf
        FailureCount (1,1) double = 0
    end

    methods
        function obj = ProfileSwitchState(activeProfile, transitionDelaySlots, maxStateAgeSlots)
            arguments
                activeProfile (1,1) string = "baseline"
                transitionDelaySlots (1,1) double = 0
                maxStateAgeSlots (1,1) double = Inf
            end
            localValidateProfile(activeProfile);
            validateattributes(transitionDelaySlots, {'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'});
            if ~(isscalar(maxStateAgeSlots) && isreal(maxStateAgeSlots) && ...
                    (isinf(maxStateAgeSlots) || ...
                    (isfinite(maxStateAgeSlots) && maxStateAgeSlots >= 1 && ...
                    maxStateAgeSlots == fix(maxStateAgeSlots))))
                error("sixgr:ran1ai1032:InvalidProfileStateAge", ...
                    "Profile-state age must be a positive integer or Inf.");
            end
            obj.ActiveProfile = activeProfile;
            obj.TransitionDelaySlots = transitionDelaySlots;
            obj.MaxStateAgeSlots = maxStateAgeSlots;
        end

        function obj = request(obj, targetProfile, slot, messageID)
            localValidateProfile(targetProfile);
            localValidateSlot(slot);
            if strlength(strtrim(messageID)) == 0
                error("sixgr:ran1ai1032:MissingProfileMessageID", ...
                    "Every profile transition must carry an explicit message identity.");
            end
            if obj.State ~= "active"
                error("sixgr:ran1ai1032:ProfileTransitionAlreadyPending", ...
                    "Cannot request a second profile while state is %s.", obj.State);
            end
            if targetProfile == obj.ActiveProfile
                error("sixgr:ran1ai1032:RedundantProfileTransition", ...
                    "Requested profile is already active.");
            end
            obj.PendingProfile = targetProfile;
            obj.State = "confirmation_pending";
            obj.MessageID = strtrim(messageID);
            obj.RequestSlot = slot;
            obj.ConfirmationSlot = NaN;
            obj.ActivationSlot = NaN;
        end

        function obj = confirm(obj, slot, messageID, success)
            arguments
                obj
                slot (1,1) double
                messageID (1,1) string
                success (1,1) logical
            end
            localValidateSlot(slot);
            if obj.State ~= "confirmation_pending" || messageID ~= obj.MessageID
                error("sixgr:ran1ai1032:ProfileConfirmationMismatch", ...
                    "Profile confirmation must match the outstanding message.");
            end
            if slot < obj.RequestSlot
                error("sixgr:ran1ai1032:NoncausalProfileConfirmation", ...
                    "Profile confirmation cannot precede its request.");
            end
            obj.ConfirmationSlot = slot;
            if ~success
                obj.PendingProfile = "";
                obj.State = "active";
                obj.MessageID = "";
                obj.FailureCount = obj.FailureCount + 1;
                return;
            end
            obj.ActivationSlot = slot + obj.TransitionDelaySlots;
            obj.State = "transition_pending";
        end

        function obj = advance(obj, slot)
            localValidateSlot(slot);
            if obj.State == "transition_pending" && slot >= obj.ActivationSlot
                obj.ActiveProfile = obj.PendingProfile;
                obj.PendingProfile = "";
                obj.State = "active";
                obj.MessageID = "";
                obj.ConfigurationEpoch = obj.ConfigurationEpoch + 1;
            end
            if obj.State == "confirmation_pending" && ...
                    isfinite(obj.MaxStateAgeSlots) && ...
                    slot - obj.RequestSlot > obj.MaxStateAgeSlots
                obj.PendingProfile = "";
                obj.State = "stale";
                obj.MessageID = "";
                obj.FailureCount = obj.FailureCount + 1;
            end
        end

        function [profile, source] = profileForGrant(obj, isNewTB, storedHARQProfile)
            arguments
                obj
                isNewTB (1,1) logical
                storedHARQProfile (1,1) string = ""
            end
            if isNewTB
                if obj.State ~= "active"
                    error("sixgr:ran1ai1032:ProfileStateNotSchedulable", ...
                        "New TB scheduling is blocked while profile state is %s.", obj.State);
                end
                profile = obj.ActiveProfile;
                source = "active_configuration_epoch_" + string(obj.ConfigurationEpoch);
                return;
            end
            localValidateProfile(storedHARQProfile);
            profile = storedHARQProfile;
            source = "immutable_stored_HARQ_TB_context";
        end

        function T = snapshot(obj, slot)
            localValidateSlot(slot);
            T = table(slot, obj.ActiveProfile, obj.PendingProfile, obj.State, ...
                obj.ConfigurationEpoch, obj.MessageID, obj.RequestSlot, ...
                obj.ConfirmationSlot, obj.ActivationSlot, obj.FailureCount, ...
                'VariableNames', {'slot','active_profile','pending_profile', ...
                'state','configuration_epoch','message_id','request_slot', ...
                'confirmation_slot','activation_slot','failure_count'});
        end
    end
end

function localValidateProfile(value)
value = string(value);
if ~isscalar(value) || ~any(value == ["baseline","fwa_high_order"])
    error("sixgr:ran1ai1032:InvalidProfile", ...
        "Profile must be baseline or fwa_high_order.");
end
end

function localValidateSlot(value)
validateattributes(value, {'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'});
end
