function [cache, runtimeState] = bindProtocolPayloadsToGrantCache(cache, runtimeState, cfg, direction)
direction = upper(string(direction));
bridge = sixgr.util.structGet(runtimeState, "ProtocolBridge", []);
if isempty(bridge) || ~isa(bridge, "sixgr.protocol.WaveformProtocolBridge") || ~bridge.Enabled
    error("sixgr:protocol:WaveformProtocolBridgeMissing", ...
        "Strict protocol YAML is enabled, but the coordinator protocol bridge is unavailable.");
end
packetT = sixgr.util.structGet(runtimeState, "PacketDeliveryLedgerTable", table());
required = ["Direction","UEIndex","PacketId","ApplicationPacketId", ...
    "OfferedBits","RemainingBits","SegmentCount"];
if ~isempty(packetT) && ~all(ismember(required, string(packetT.Properties.VariableNames)))
    error("sixgr:protocol:ApplicationLedgerSchemaMismatch", ...
        "Application packet ledger lacks the fields required for protocol-TB binding.");
end
plannedRemaining=[]; plannedSegments=[];
if ~isempty(packetT)
    plannedRemaining=double(packetT.RemainingBits); plannedSegments=double(packetT.SegmentCount);
end

for i = 1:numel(cache)
    if ~logical(sixgr.util.structGet(cache(i), "Valid", false))
        continue;
    end
    signalType = upper(string(sixgr.util.structGet(cache(i), "SignalType", direction)));
    if ~any(signalType == ["DL","UL","PDSCH","PUSCH"])
        continue;
    end
    grant = sixgr.util.structGet(cache(i), "GrantSnapshot", struct());
    isRetx = sixgr.truth.GrantPreparation.grantIsRetransmission(grant);
    if isRetx
        if ~logical(sixgr.util.structGet(grant, "ProtocolPayloadSameWaveformTruth", false))
            error("sixgr:protocol:RetransmissionMissingProtocolBinding", ...
                "HARQ retransmission grant %d does not retain its original protocol payload binding.", i);
        end
        continue;
    end

    ueIdx = double(sixgr.util.structGet(cache(i), "UEIndex", NaN));
    if bridge.pendingReverseStatusBytes(ueIdx,direction)>0
        tbsBits=double(sixgr.util.structGet(grant,'TBSBits',sixgr.util.structGet(grant,'TransportBlockSize',NaN)));
        eventTime=runtimeState.SharedWaveformStream.Events.NextSampleIndex/runtimeState.SharedWaveformStream.SampleRateHz;
        tbId=localProtocolTransportBlockId(grant,direction,ueIdx,i);
        reserve=0;
        if direction=="UL"&&sixgr.util.structGet(cfg,'phy.mac.uplinkControl.Enabled',false), reserve=5; end
        [tbBits,e]=bridge.prepareReverseStatusTransportBlock(ueIdx,direction,tbId,tbsBits,eventTime,reserve);
        grant.TransportBlockId=char(tbId); grant.ProtocolPayloadSameWaveformTruth=true;
        grant.ProtocolControlOnly=true; grant.ProtocolPayloadBits=0; grant.ProtocolPayloadOffsetBits=0;
        grant.ProtocolRLCSegmentPayloadBytes=e.SegmentPayloadBytes;
        grant.ProtocolMACControlReservationBytes=reserve;
        grant.ProtocolMACSHA256=char(e.MACSHA256); grant.ProtocolEncodedRLC_SHA256=char(e.EncodedSHA256);
        grant.ProtocolEvidenceSource='original_receiver_triggered_reverse_RLC_STATUS_MAC_bytes';
        cache(i).GrantSnapshot=grant;
        if isfield(cache,'TransportBlockBits'), cache(i).TransportBlockBits=int8(tbBits(:)); end
        if isfield(cache,'TrialContext')
            cache(i).TrialContext.GrantSnapshot=grant; cache(i).TrialContext.TransportBlockBits=int8(tbBits(:));
        end
        continue;
    end
    queue=bridge.pendingTransmitBytes(ueIdx,direction);
    if direction=="UL"&&queue.TotalBSRBytes==0
        assert(isfield(cache,'Cfg')&&isstruct(cache(i).Cfg)&& ...
            isfield(cache(i).Cfg,'phy')&&isfield(cache(i).Cfg.phy,'pusch')&& ...
            isfield(cache(i).Cfg.phy.pusch,'receivedDCIAssignment')&& ...
            isstruct(cache(i).Cfg.phy.pusch.receivedDCIAssignment), ...
            'sixgr:mac:ReceivedMACAssignmentRequired', ...
            'Empty-queue UL MAC assembly requires the original received DCI assignment.');
        receivedCfg=cache(i).Cfg; a=receivedCfg.phy.pusch.receivedDCIAssignment;
        allocation=sixgr.phy.pdcch.connectedDataAllocation(receivedCfg,a);
        tbsBits=double(sixgr.util.structGet(grant,'TBSBits',sixgr.util.structGet(grant,'TransportBlockSize',NaN)));
        assert(tbsBits==allocation.NominalTBSBits,'sixgr:mac:ReceivedMACSizeMismatch','Received DCI must derive original MAC TBS.');
        authority=struct('Stage',"original_received_DCI_empty_UE_L2",'UEIndex',ueIdx, ...
            'TBSBits',tbsBits,'AssignmentDigest',string(a.AssignmentDigest));
        tbId=localProtocolTransportBlockId(grant,direction,ueIdx,i);
        [tbBits,e]=bridge.prepareMACOnlyTransportBlock(ueIdx,tbId,tbsBits,authority);
        grant.TransportBlockId=char(tbId);grant.ProtocolPayloadSameWaveformTruth=true;
        grant.ProtocolControlOnly=true;grant.ProtocolPayloadBits=0;grant.ProtocolPayloadOffsetBits=0;
        grant.ProtocolRLCSegmentPayloadBytes=0;grant.ProtocolMACControlReservationBytes=tbsBits/8;
        grant.ProtocolMACSHA256=char(e.MACSHA256);grant.ProtocolEncodedRLC_SHA256='';
        grant.ProtocolEvidenceSource='original_received_grant_empty_UE_L2_MAC_CE_padding';
        cache(i).GrantSnapshot=grant;
        if isfield(cache,'TransportBlockBits'),cache(i).TransportBlockBits=int8(tbBits(:));end
        if isfield(cache,'TrialContext')
            cache(i).TrialContext.GrantSnapshot=grant;cache(i).TrialContext.TransportBlockBits=int8(tbBits(:));
        end
        continue;
    end
    assert(~isempty(packetT),'sixgr:protocol:MissingApplicationTraffic','Original application ledger required for data SDU.');
    if queue.TotalBSRBytes<=0
        error("sixgr:protocol:NewDataGrantWithoutQueuedL2Payload", ...
            "New-data %s grant %d for UE %d has no original queued L2 payload.", ...
            direction, i, ueIdx);
    end
    tbsBits = double(sixgr.util.structGet(grant, "TBSBits", ...
        sixgr.util.structGet(grant, "TransportBlockSize", NaN)));
    reserved=0;
    policy=sixgr.util.structGet(cfg,"phy.mac.uplinkControl",struct('Enabled',false));
    if direction=="UL" && policy.Enabled, reserved=5; end % Single-entry PHR(3) + Short BSR(2), including subheaders.
    slot = double(sixgr.util.structGet(grant,"Slot",runtimeState.CurrentSlot));
    eventTime=max(0,(slot-1)*runtimeState.SlotDuration_s);
    if isfield(runtimeState,'SharedWaveformStream') && ~isempty(runtimeState.SharedWaveformStream)
        eventTime=runtimeState.SharedWaveformStream.Events.NextSampleIndex/runtimeState.SharedWaveformStream.SampleRateHz;
    end
    tbId=localProtocolTransportBlockId(grant,direction,ueIdx,i);
    [tbBits,evidence]=bridge.prepareQueuedSegment(ueIdx,direction,tbId,tbsBits,eventTime,reserved);
    packetId=string(evidence.PacketID);
    packetIdx=find(string(packetT.ApplicationPacketId)==packetId & ...
        double(packetT.UEIndex)==ueIdx & upper(string(packetT.Direction))==direction);
    assert(isscalar(packetIdx),'sixgr:protocol:ApplicationLedgerSchemaMismatch', ...
        'Original queued RLC segment must belong to exactly one application packet.');
    offsetBits=8*evidence.ApplicationOffsetBytes;
    segmentIndex=plannedSegments(packetIdx)+1;
    fragmentId=tbId;

    grant.TransportBlockId = char(tbId);
    grant.ProtocolPayloadSameWaveformTruth = true;
    grant.ProtocolPacketId = char(packetId);
    grant.ProtocolApplicationPacketId = char(string(packetT.ApplicationPacketId(packetIdx)));
    grant.ProtocolFragmentId = char(fragmentId);
    grant.ProtocolSegmentIndex = double(segmentIndex);
    grant.ProtocolPayloadOffsetBits = double(offsetBits);
    grant.ProtocolPayloadBits = double(evidence.PayloadBits);
    grant.ProtocolRLCSegmentPayloadBytes=double(evidence.SegmentPayloadBytes);
    grant.ProtocolPayloadSHA256 = char(evidence.PayloadSHA256);
    grant.ProtocolSDAPHeaderHex = char(evidence.SDAPHeaderHex);
    grant.ProtocolPDCPHeaderHex = char(evidence.PDCPHeaderHex);
    grant.ProtocolRLCHeaderHex = char(evidence.RLCHeaderHex);
    grant.ProtocolEncodedRLC_SHA256 = char(evidence.EncodedRLC_SHA256);
    grant.ProtocolMACSHA256 = char(evidence.MACSHA256);
    grant.ProtocolMACPDUBytes = double(evidence.MACPDUBytes);
    grant.ProtocolMACPaddingBytes = double(evidence.MACPaddingBytes);
    grant.ProtocolMACControlReservationBytes=reserved;
    grant.ProtocolEvidenceSource = char(evidence.EvidenceSource);
    cache(i).GrantSnapshot = grant;
    if isfield(cache,'TransportBlockBits'), cache(i).TransportBlockBits = int8(tbBits(:)); end

    if isfield(cache,'TrialContext')
        cache(i).TrialContext.GrantSnapshot=grant;
        cache(i).TrialContext.TransportBlockBits=int8(tbBits(:));
    end
    plannedRemaining(packetIdx) = plannedRemaining(packetIdx) - evidence.PayloadBits;
    plannedSegments(packetIdx) = segmentIndex;
end
runtimeState.ProtocolBridge = bridge;
end

function tbId = localProtocolTransportBlockId(grant, direction, ueIdx, grantIndex)
for name = ["TransportBlockId","TBId","GrantContextId","PHYGrantContextId"]
    value = strtrim(string(sixgr.util.structGet(grant, char(name), "")));
    if strlength(value) > 0 && lower(value) ~= "nan"
        tbId = value;
        return;
    end
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
harqId = double(sixgr.util.structGet(harq, "HarqID", NaN));
ndiEpoch = double(sixgr.util.structGet(harq, "NDIEpoch", NaN));
slot = double(sixgr.util.structGet(grant, "Slot", NaN));
if ~(isfinite(harqId) && isfinite(ndiEpoch) && isfinite(slot))
    error("sixgr:protocol:MissingTransportBlockIdentity", ...
        "Protocol grant %d lacks a stable grant or HARQ transport-block identity.", grantIndex);
end
tbId = direction + "_ue" + string(ueIdx) + "_harq" + string(harqId) + ...
    "_epoch" + string(ndiEpoch) + "_slot" + string(slot);
end

function bytes = localProtocolPayloadBytes(cfg, packetId, direction, ueIdx, offsetBytes, count)
seed = double(sixgr.util.structGet(cfg, "run.seed", NaN));
if ~(isfinite(seed) && seed >= 0)
    error("sixgr:protocol:MissingPayloadSeed", ...
        "Deterministic same-waveform application payload generation requires run.seed.");
end
bytes = sixgr.protocol.applicationPayloadBytes(seed,packetId,direction,ueIdx,offsetBytes,count);
end
