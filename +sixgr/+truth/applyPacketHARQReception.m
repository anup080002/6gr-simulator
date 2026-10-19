function sduT=applyPacketHARQReception(sduT,mask,harqRow,decodedTbBits,deliveryTiming,protocolEnabled,bridge)
% Production SDU-delivery reducer; input timing/identity is receiver-validated.
% Called only after the runtime's actual TX/RX and logical-TB binding checks.
assert(islogical(mask) && numel(mask)==height(sduT), ...
    'sixgr:protocol:InvalidPacketReceptionMask','Require one ownership decision per SDU row.');
if ~any(mask), return; end
tbId=unique(string(sduT.TransportBlockId(mask)));
assert(isscalar(tbId) && strlength(tbId)>0, ...
    'sixgr:protocol:AmbiguousPacketReception','One received TB must own this update.');
attemptSlot=double(localValue(harqRow,'Slot',NaN));
feedbackSlot=double(localValue(harqRow,'FeedbackDueSlot',NaN));
deliverySlot=double(deliveryTiming.DeliveryCanonicalSlot);
deliveryTime=double(deliveryTiming.DeliveryTime_s);
sduT.HARQAttemptCount(mask) = double(sduT.HARQAttemptCount(mask)) + 1;
sduT.LastAttemptSlot(mask) = double(attemptSlot);
sduT.HARQFeedbackDueSlot(mask) = double(feedbackSlot);
sduT.LastRV(mask) = double(localValue(harqRow, "RV", NaN));
sduT.TBCrcPass(mask) = logical(localValue(harqRow, "CombinedDecodeOK", false));
% First-success fields are immutable after delivery. Attempt fields instead
% describe this callback; a rejected duplicate has no fresh byte comparison.
firstMask = mask & ~logical(sduT.DeliverySuccess);
sduT.LastAttemptProtocolDeliveryStatus(mask) = "not_attempted_crc_failed";
sduT.LastAttemptProtocolDecodedBitCount(mask) = NaN;
sduT.LastAttemptProtocolDecodedBitExact(mask) = false;
sduT.LastAttemptProtocolDecodedMACSHA256(mask) = "";
sduT.LastAttemptProtocolDecodedRLC_SHA256(mask) = "";
sduT.LastAttemptProtocolReceiverEvidenceSource(mask) = "";
if logical(localValue(harqRow, "CombinedDecodeOK", false))
    protocolDelivered = true;
    protocolStatus = "not_required";
    if protocolEnabled
        if isempty(bridge) || ~isa(bridge, "sixgr.protocol.WaveformProtocolBridge")
            error("sixgr:protocol:WaveformProtocolBridgeMissing", ...
                "Decoded protocol-bound TB cannot be delivered without the coordinator bridge.");
        end
        if isempty(decodedTbBits)
            error("sixgr:protocol:MissingDecodedTransportBlockBits", ...
                ["A protocol-bound PHY decode passed for transport block %s, " + ...
                 "but the receiver did not return its decoded bits."], string(tbId));
        end
        [protocolDelivered, protocolEvidence] = bridge.deliverDecoded( ...
            string(tbId), decodedTbBits, double(deliveryTime));
        protocolStatus = string(sixgr.util.structGet(protocolEvidence, "Status", ""));
        sduT.LastAttemptProtocolDecodedBitCount(mask) = double(sixgr.util.structGet( ...
            protocolEvidence, "DecodedBitCount", NaN));
        sduT.LastAttemptProtocolDecodedBitExact(mask) = logical(sixgr.util.structGet( ...
            protocolEvidence, "DecodedBitExact", false));
        sduT.LastAttemptProtocolDecodedMACSHA256(mask) = string(sixgr.util.structGet( ...
            protocolEvidence, "DecodedMACSHA256", ""));
        sduT.LastAttemptProtocolDecodedRLC_SHA256(mask) = string(sixgr.util.structGet( ...
            protocolEvidence, "DecodedRLC_SHA256", ""));
        sduT.LastAttemptProtocolReceiverEvidenceSource(mask) = string(sixgr.util.structGet( ...
            protocolEvidence, "EvidenceSource", ""));
        fields=["ProtocolDecodedBitCount","ProtocolDecodedBitExact", ...
            "ProtocolDecodedMACSHA256","ProtocolDecodedRLC_SHA256","ProtocolReceiverEvidenceSource"];
        for field=fields
            sduT.(field)(firstMask)=sduT.("LastAttempt"+field)(firstMask);
        end
    end
    sduT.LastAttemptProtocolDeliveryStatus(mask) = protocolStatus;
    sduT.ProtocolDeliveryStatus(firstMask) = protocolStatus;
    if protocolDelivered
        sduT.DeliverySuccess(firstMask) = true;
        sduT.FirstSuccessDelivery(firstMask) = true;
        sduT.FirstSuccessSlot(firstMask) = double(deliverySlot);
        sduT.DeliveryCanonicalSlot(firstMask) = double(deliverySlot);
        sduT.DeliveryTime_s(firstMask) = double(deliveryTime);
        sduT.DeliveryTimingAuthority(firstMask) = string(deliveryTiming.TimingAuthority);
        sduT.DeliveryAvailableAtSample(firstMask) = deliveryTiming.DeliveryAvailableAtSample;
        sduT.DeliverySampleRateHz(firstMask) = deliveryTiming.DeliverySampleRateHz;
        sduT.DeliveryAvailableCanonicalSlot(firstMask) = deliveryTiming.DeliveryAvailableCanonicalSlot;
        sduT.NominalDataSlotEndTime_s(firstMask) = deliveryTiming.NominalDataSlotEndTime_s;
        sduT.NominalHARQFeedbackSlotStartTime_s(firstMask) = deliveryTiming.NominalHARQFeedbackSlotStartTime_s;
        sduT.DataReceiveTimingEvidenceJSON(firstMask) = string(sixgr.util.structGet(harqRow,'DataReceiveTimingEvidenceJSON',""));
        sduT.DeliveryLatency_ms(firstMask) = (double(deliveryTime) - double(sduT.ScheduleTime_s(firstMask))) * 1e3;
        sduT.TimingStatus(firstMask) = localTimingStatus( ...
            double(sduT.ScheduleTime_s(firstMask)), double(deliveryTime));
        sduT.Status(firstMask) = "first_success_delivery";
    else
        sduT.Status(firstMask) = "phy_decode_pass_protocol_delivery_rejected";
    end
else
    sduT.Status(mask & ~logical(sduT.DeliverySuccess)) = "harq_pending_or_failed";
end

end

function value=localValue(row,name,default)
value=sixgr.util.structGet(row,name,default);
end

function status=localTimingStatus(startTime,endTime)
startTime=double(startTime); endTime=double(endTime);
if isscalar(startTime) && ~isscalar(endTime)
    startTime=repmat(startTime,size(endTime));
elseif isscalar(endTime) && ~isscalar(startTime)
    endTime=repmat(endTime,size(startTime));
end
status=repmat("timing_unknown",size(endTime));
valid=isfinite(startTime) & isfinite(endTime);
status(valid & endTime>=startTime-1e-12)="canonical_timing_ok";
status(valid & endTime<startTime-1e-12)="negative_latency_invalid";
end
