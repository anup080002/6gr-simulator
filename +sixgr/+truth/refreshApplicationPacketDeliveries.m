function state = refreshApplicationPacketDeliveries(state)
% Reconcile only the owning application's decoded, gap-free fragments.
    if ~isfield(state, "PacketDeliveryLedgerTable") || ~istable(state.PacketDeliveryLedgerTable) || isempty(state.PacketDeliveryLedgerTable) || ...
            ~isfield(state, "PacketSDULedgerTable") || ~istable(state.PacketSDULedgerTable)
        return;
    end
    % Attempt ownership is independent of application completion and of
    % whether the optional same-waveform protocol bridge is enabled. Count
    % each actual received TB attempt once, not once per carried fragment.
    state = sixgr.truth.reconcilePacketHARQAttempts(state);
    packetT = state.PacketDeliveryLedgerTable;
    sduT = state.PacketSDULedgerTable;
    recoveryT=sixgr.util.structGet(state,'RLCRecoveryTransportLedgerTable',table());
    if isempty(sduT)
        state=sixgr.truth.reconcilePacketBitConservation(state);
        return;
    end
    keys={'Direction','UEIndex','PacketId','ApplicationPacketId'};
    assert(height(unique(packetT(:,keys),'rows'))==height(packetT), ...
        'sixgr:protocol:AmbiguousApplicationIdentity','Application owner keys must be unique.');
    for pidx = 1:height(packetT)
        if logical(packetT.DeliverySuccess(pidx))
            continue;
        end
        smask = string(sduT.PacketId) == string(packetT.PacketId(pidx)) & ...
            string(sduT.ApplicationPacketId) == string(packetT.ApplicationPacketId(pidx)) & ...
            sduT.UEIndex == packetT.UEIndex(pidx) & ...
            upper(string(sduT.Direction)) == upper(string(packetT.Direction(pidx)));
        if ~any(smask)
            continue;
        end
        fullyScheduled = double(packetT.RemainingBits(pidx)) <= 0;
        allDelivered = all(logical(sduT.DeliverySuccess(smask)));
        protocolRequired = logical(sixgr.util.structGet(state, "ProtocolWaveformEnabled", false));
        if ~protocolRequired
            % PHY/HARQ delivery is not application delivery.  Without
            % the configured same-waveform SDAP/PDCP/RLC/MAC bridge,
            % retain the packet as an offered/scheduled application
            % object and make the missing end-to-end boundary explicit.
            if fullyScheduled && allDelivered
                packetT.ProtocolReassemblyStatus(pidx) = "protocol_stack_not_enabled";
                packetT.DeliverySource(pidx) = "not_available_without_same_waveform_protocol";
                packetT.Status(pidx) = "phy_delivery_complete_protocol_not_enabled";
            end
            continue;
        end
        rmask=false(height(recoveryT),1);
        if ~isempty(recoveryT)
            rmask=string(recoveryT.PacketId)==string(packetT.PacketId(pidx)) & ...
                string(recoveryT.ApplicationPacketId)==string(packetT.ApplicationPacketId(pidx)) & ...
                recoveryT.UEIndex==packetT.UEIndex(pidx) & ...
                upper(string(recoveryT.Direction))==upper(string(packetT.Direction(pidx)));
        end
        recovered=any(rmask);
        bridge=sixgr.util.structGet(state,"ProtocolBridge",[]);
        if recovered
            if ~fullyScheduled,continue;end
            assert(isa(bridge,"sixgr.protocol.WaveformProtocolBridge"), ...
                'sixgr:protocol:WaveformProtocolBridgeMissing','Recovery needs the private original decoded payload owner.');
            [ready,decodedPayload,receipt]=bridge.applicationRecoveryReceipt( ...
                packetT.UEIndex(pidx),string(packetT.Direction(pidx)),string(packetT.PacketId(pidx)));
            if ~ready,continue;end
            decodedHash=receipt.DecodedApplicationPayloadSHA256;
            allTransport=sixgr.truth.combinePacketTransportLedgers(state);
            contributors=ismember(string(allTransport.TransportBlockId),receipt.ContributorTransportBlockIDs);
            assert(nnz(contributors)==numel(receipt.ContributorTransportBlockIDs)&& ...
                all(allTransport.DeliverySuccess(contributors)), ...
                'sixgr:protocol:InvalidRLCApplicationRecovery','Private released TBs must join actual delivered transport records.');
            if ~ismember('RLCApplicationRecoveryEvidenceJSON',packetT.Properties.VariableNames)
                packetT.RLCApplicationRecoveryEvidenceJSON=strings(height(packetT),1);
                packetT.RLCApplicationRecoveryEvidenceSHA256=strings(height(packetT),1);
            end
            packetT.RLCApplicationRecoveryEvidenceJSON(pidx)=string(jsonencode(receipt));
            packetT.RLCApplicationRecoveryEvidenceSHA256(pidx)=receipt.SHA256;
            deliveryTime=receipt.DeliveryTime_s;
            deliverySlot=max(allTransport.FirstSuccessSlot(contributors));
            fragmentCount=nnz(contributors);protocolComplete=true;
        else
        protocolComplete = all(logical(sduT.ProtocolPayloadSameWaveformTruth(smask))) && ...
            all(string(sduT.ProtocolDeliveryStatus(smask)) == "delivered_after_exact_phy_decode");
        if ~(fullyScheduled && allDelivered && protocolComplete)
            continue;
        end
        validateFragments(sduT(smask,:),double(packetT.OfferedBits(pidx)));
        assert(isa(bridge,"sixgr.protocol.WaveformProtocolBridge"), ...
            'sixgr:protocol:WaveformProtocolBridgeMissing', ...
            'Application completion requires the retained original decoded payload owner.');
        fragments=sduT(smask,:);
        [~,order]=sort(double(fragments.ProtocolPayloadOffsetBits));
        [decodedPayload,decodedHash]=bridge.reassembleDecodedApplication( ...
            string(fragments.TransportBlockId(order)),double(fragments.PayloadBits(order))/8);
        deliveryTime = max(double(sduT.DeliveryTime_s(smask)), [], "omitnan");
        deliverySlot = max(double(sduT.FirstSuccessSlot(smask)), [], "omitnan");
        fragmentCount=sum(smask);
        end
        assert(ismember("OriginalApplicationPayloadSHA256",string(packetT.Properties.VariableNames)) && ...
            strlength(string(packetT.OriginalApplicationPayloadSHA256(pidx)))==64 && ...
            decodedHash==string(packetT.OriginalApplicationPayloadSHA256(pidx)), ...
            'sixgr:protocol:InvalidApplicationPayload', ...
            'Reassembled original decoded bytes must match the offered application packet.');
        if ~ismember("DecodedApplicationPayloadSHA256",string(packetT.Properties.VariableNames))
            packetT.DecodedApplicationPayloadSHA256=repmat("",height(packetT),1);
            packetT.DecodedApplicationBytes=nan(height(packetT),1);
        end
        packetT.DecodedApplicationPayloadSHA256(pidx)=decodedHash;
        packetT.DecodedApplicationBytes(pidx)=numel(decodedPayload);
        packetT.DeliveredBits(pidx) = double(packetT.OfferedBits(pidx));
        packetT.DeliverySuccess(pidx) = true;
        packetT.ReassemblyCompleteFlag(pidx) = true;
        packetT.DeliverySlot(pidx) = double(deliverySlot);
        packetT.DeliveryCanonicalSlot(pidx) = double(deliverySlot);
        packetT.DeliveryTime_s(pidx) = double(deliveryTime);
        packetT.Latency_ms(pidx) = (double(deliveryTime) - double(packetT.EnqueueTime_s(pidx))) * 1e3;
        packetT.TimingStatus(pidx) = localTimingStatus( ...
            double(packetT.EnqueueTime_s(pidx)), double(deliveryTime));
        packetT.ProtocolFragmentCount(pidx) = fragmentCount;
        packetT.SameWaveformProtocolComplete(pidx) = logical(protocolComplete);
        packetT.ProtocolReassemblyStatus(pidx) = "sdap_pdcp_rlc_mac_fragments_delivered_after_exact_phy_decode";
        packetT.DeliverySource(pidx) = "same_waveform_protocol_harq_first_success_reassembly";
        if recovered
            packetT.ProtocolReassemblyStatus(pidx)="original_RLC_recovery_byte_union_released_by_PDCP";
            packetT.DeliverySource(pidx)="same_waveform_RLC_recovery_and_original_PDCP_application_release";
            recoveryT.ReassemblyCompleteFlag(rmask & recoveryT.DeliverySuccess)=true;
            recoveryT.ApplicationDeliveryFlag(rmask & recoveryT.DeliverySuccess)=true;
        end
        packetT.Status(pidx) = "delivered";
        sduT.ReassemblyCompleteFlag(smask & sduT.DeliverySuccess) = true;
        sduT.ApplicationDeliveryFlag(smask & sduT.DeliverySuccess) = true;
    end
    state.PacketDeliveryLedgerTable = packetT;
    state.PacketSDULedgerTable = sduT;
    if ~isempty(recoveryT),state.RLCRecoveryTransportLedgerTable=recoveryT;end
    state=sixgr.truth.reconcilePacketBitConservation(state);
end

function validateFragments(T,offered)
% Neither a success flag nor a sum of fragment sizes proves byte coverage.
[offsets,order]=sort(double(T.ProtocolPayloadOffsetBits));
lengths=double(T.PayloadBits(order));
expected=[0;cumsum(lengths(1:end-1))];
ids=string(T.ProtocolFragmentId);
coverage=isfinite(offered) && offered>0 && mod(offered,8)==0 && ...
    all(isfinite(offsets) & offsets>=0 & mod(offsets,8)==0) && ...
    all(isfinite(lengths) & lengths>=0 & mod(lengths,8)==0) && ...
    isequal(offsets,expected) && sum(lengths)==offered && ...
    isequal(double(T.SegmentIndex(order)),(1:height(T)).') && ...
    all(~ismissing(ids) & strlength(ids)>0) && numel(unique(ids))==height(T);
assert(coverage,'sixgr:protocol:InvalidApplicationFragmentCoverage', ...
    'Decoded fragments must cover the offered application bytes exactly once, without gaps or overlaps.');
exact=ismember('ProtocolDecodedPayloadSHA256',T.Properties.VariableNames) && ...
    all(T.ProtocolDecodedBitExact) && ...
    all(string(T.ProtocolDecodedPayloadSHA256)==string(T.ProtocolPayloadSHA256)) && ...
    all(T.ProtocolDecodedBitCount==8*T.ProtocolMACPDUBytes) && ...
    all(T.ProtocolDecodedBitCount>0 & isfinite(T.ProtocolDecodedBitCount)) && ...
    all(strlength(string(T.ProtocolMACSHA256))==64 & ...
        string(T.ProtocolDecodedMACSHA256)==string(T.ProtocolMACSHA256)) && ...
    all(strlength(string(T.ProtocolEncodedRLC_SHA256))==64 & ...
        string(T.ProtocolDecodedRLC_SHA256)==string(T.ProtocolEncodedRLC_SHA256)) && ...
    all(string(T.ProtocolReceiverEvidenceSource)== ...
        "actual_phy_decoder_bits_demuxed_through_strict_mac_rlc_pdcp_sdap") && ...
    all(isfinite(T.DeliveryTime_s) & T.DeliveryTime_s>=T.ScheduleTime_s-1e-12);
assert(exact,'sixgr:protocol:InvalidApplicationDeliveryEvidence', ...
    'Application delivery requires retained exact decoder byte comparisons and causal first-success timing.');
end
function status=localTimingStatus(startTime,endTime)
status="timing_unknown";
if isfinite(startTime) && isfinite(endTime)
    if endTime>=startTime-1e-12
        status="canonical_timing_ok";
    else
        status="negative_latency_invalid";
    end
end
end
