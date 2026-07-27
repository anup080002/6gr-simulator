classdef RLCEntityState < handle
    %RLCENTITYSTATE Bounded AM/UM state and timer transition authority.

    properties (SetAccess = private)
        EntityID (1,1) string
        Mode (1,1) string
        SNBits (1,1) double
        State (1,1) string = "IDLE"
        TX_NEXT (1,1) double = 0
        TX_NEXT_ACK (1,1) double = 0
        RX_NEXT (1,1) double = 0
        Lifecycle (1,1) string = "CREATED"
    end

    methods
        function obj = RLCEntityState(entityID, mode, snBits)
            arguments
                entityID (1,1) string
                mode (1,1) string
                snBits (1,1) double
            end
            mode = upper(mode);
            valid = (mode == "AM" && ismember(snBits, [12 18])) || ...
                (mode == "UM" && ismember(snBits, [6 12])) || ...
                (mode == "TM" && snBits == 0);
            if ~valid
                error("sixgr:rlc:InvalidSNLength", ...
                    "SN length %g is invalid for RLC %s.", snBits, mode);
            end
            obj.EntityID = entityID;
            obj.Mode = mode;
            obj.SNBits = snBits;
        end

        function activate(obj)
            if obj.Lifecycle ~= "CREATED"
                error("sixgr:rlc:TimerStateViolation", ...
                    "Only a newly created RLC entity may be activated.");
            end
            obj.Lifecycle = "ACTIVE";
        end

        function transition(obj, event)
            arguments
                obj
                event (1,1) string
            end
            from = obj.State;
            switch from + "|" + event
                case {"IDLE|TX_POLL", "RX_STABLE|GAP_DETECTED"}
                    if event == "TX_POLL"
                        obj.State = "POLL_WAIT";
                    else
                        obj.State = "REASSEMBLY_WAIT";
                    end
                case "POLL_WAIT|STATUS_ACK"
                    obj.State = "IDLE";
                case "POLL_WAIT|t_PollRetransmit_EXPIRE"
                    obj.State = "RETX_PENDING";
                case {"REASSEMBLY_WAIT|MISSING_PDU_ARRIVED", ...
                        "REASSEMBLY_WAIT|GAP_FILLED"}
                    obj.State = "RX_STABLE";
                case "REASSEMBLY_WAIT|t_Reassembly_EXPIRE"
                    obj.State = "STATUS_PENDING";
                case "STATUS_PENDING|STATUS_SENT"
                    obj.State = "STATUS_PROHIBITED";
                case "STATUS_PROHIBITED|t_StatusProhibit_EXPIRE"
                    obj.State = "RX_STABLE";
                case "ACTIVE|RRC_REESTABLISH"
                    obj.State = "RESETTING";
                case "RESETTING|RESET_COMPLETE"
                    obj.State = "ACTIVE";
                otherwise
                    error("sixgr:rlc:TimerStateViolation", ...
                        "Illegal RLC transition %s --%s--> ?.", from, event);
            end
        end

        function sn = allocateSN(obj)
            if obj.Lifecycle ~= "ACTIVE" || obj.Mode == "TM"
                error("sixgr:rlc:WindowViolation", ...
                    "Only an active acknowledged/unacknowledged entity owns SNs.");
            end
            sn = obj.TX_NEXT;
            obj.TX_NEXT = mod(obj.TX_NEXT + 1, 2^obj.SNBits);
        end

        function release(obj)
            obj.Lifecycle = "RELEASED";
            obj.State = "IDLE";
        end
    end
end
