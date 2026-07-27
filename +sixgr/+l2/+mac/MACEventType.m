classdef MACEventType
    %MACEVENTTYPE Canonical Phase-08 MAC event vocabulary.

    properties (Constant)
        CONFIGURATION_EPOCH = "CONFIGURATION_EPOCH"
        RRC_STATE_CHANGED = "RRC_STATE_CHANGED"
        BWP_ACTIVATED = "BWP_ACTIVATED"
        BUFFER_ARRIVAL = "BUFFER_ARRIVAL"
        BSR_TRIGGERED = "BSR_TRIGGERED"
        BSR_TRANSMITTED = "BSR_TRANSMITTED"
        PHR_TRIGGERED = "PHR_TRIGGERED"
        PHR_TRANSMITTED = "PHR_TRANSMITTED"
        SR_TRIGGERED = "SR_TRIGGERED"
        SR_TRANSMITTED = "SR_TRANSMITTED"
        DCI_DECODED = "DCI_DECODED"
        GRANT_CANDIDATE = "GRANT_CANDIDATE"
        GRANT_COMMITTED = "GRANT_COMMITTED"
        GRANT_CANCELLED = "GRANT_CANCELLED"
        HARQ_RESERVED = "HARQ_RESERVED"
        HARQ_TRANSMITTED = "HARQ_TRANSMITTED"
        HARQ_FEEDBACK = "HARQ_FEEDBACK"
        HARQ_RELEASED = "HARQ_RELEASED"
        TA_COMMAND = "TA_COMMAND"
        TA_TIMER_EXPIRED = "TA_TIMER_EXPIRED"
        PACKET_ARRIVED = "PACKET_ARRIVED"
        PACKET_DELIVERED = "PACKET_DELIVERED"
        PACKET_DROPPED = "PACKET_DROPPED"
    end

    methods (Static)
        function tf = isValid(value)
            value = upper(string(value));
            tf = ismember(value, [ ...
                sixgr.l2.mac.MACEventType.CONFIGURATION_EPOCH
                sixgr.l2.mac.MACEventType.RRC_STATE_CHANGED
                sixgr.l2.mac.MACEventType.BWP_ACTIVATED
                sixgr.l2.mac.MACEventType.BUFFER_ARRIVAL
                sixgr.l2.mac.MACEventType.BSR_TRIGGERED
                sixgr.l2.mac.MACEventType.BSR_TRANSMITTED
                sixgr.l2.mac.MACEventType.PHR_TRIGGERED
                sixgr.l2.mac.MACEventType.PHR_TRANSMITTED
                sixgr.l2.mac.MACEventType.SR_TRIGGERED
                sixgr.l2.mac.MACEventType.SR_TRANSMITTED
                sixgr.l2.mac.MACEventType.DCI_DECODED
                sixgr.l2.mac.MACEventType.GRANT_CANDIDATE
                sixgr.l2.mac.MACEventType.GRANT_COMMITTED
                sixgr.l2.mac.MACEventType.GRANT_CANCELLED
                sixgr.l2.mac.MACEventType.HARQ_RESERVED
                sixgr.l2.mac.MACEventType.HARQ_TRANSMITTED
                sixgr.l2.mac.MACEventType.HARQ_FEEDBACK
                sixgr.l2.mac.MACEventType.HARQ_RELEASED
                sixgr.l2.mac.MACEventType.TA_COMMAND
                sixgr.l2.mac.MACEventType.TA_TIMER_EXPIRED
                sixgr.l2.mac.MACEventType.PACKET_ARRIVED
                sixgr.l2.mac.MACEventType.PACKET_DELIVERED
                sixgr.l2.mac.MACEventType.PACKET_DROPPED]);
        end
    end
end
