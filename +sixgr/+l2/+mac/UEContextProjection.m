classdef UEContextProjection
    %UECONTEXTPROJECTION Deterministic fold of per-UE MAC context.

    methods (Static)
        function state = initial(ueID, servingCell)
            state = struct("UEID",double(ueID), ...
                "ServingCell",double(servingCell),"RRCState","CONNECTED", ...
                "ActiveDLBWP",0,"ActiveULBWP",0,"DRXState","AWAKE", ...
                "TimeAligned",false,"ConfigurationEpoch",0, ...
                "DLQueueBytes",0,"ULQueueBytes",0);
        end

        function state = apply(state, event, ~)
            if event.UEID ~= 0 && event.UEID ~= state.UEID
                return;
            end
            payload = event.Payload;
            switch event.EventType
                case sixgr.l2.mac.MACEventType.CONFIGURATION_EPOCH
                    state.ConfigurationEpoch = event.ConfigurationEpoch;
                case sixgr.l2.mac.MACEventType.RRC_STATE_CHANGED
                    state.RRCState = string(payload.State);
                case sixgr.l2.mac.MACEventType.BWP_ACTIVATED
                    if event.Direction == "DL"
                        state.ActiveDLBWP = double(payload.BWPID);
                    elseif event.Direction == "UL"
                        state.ActiveULBWP = double(payload.BWPID);
                    end
                case sixgr.l2.mac.MACEventType.BUFFER_ARRIVAL
                    if event.Direction == "DL"
                        state.DLQueueBytes = state.DLQueueBytes + double(payload.Bytes);
                    else
                        state.ULQueueBytes = state.ULQueueBytes + double(payload.Bytes);
                    end
                case sixgr.l2.mac.MACEventType.TA_COMMAND
                    state.TimeAligned = true;
                case sixgr.l2.mac.MACEventType.TA_TIMER_EXPIRED
                    state.TimeAligned = false;
            end
        end

        function value = digest(state)
            value = sixgr.l2.mac.MACHash.of(state);
        end
    end
end
