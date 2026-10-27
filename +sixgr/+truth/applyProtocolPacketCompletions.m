function T=applyProtocolPacketCompletions(T,completions,clock)
% Only a retained decoded payload released by its real bearer can complete.
for k=1:numel(completions)
    row=completions(k);
    fragmentHash=string(sixgr.util.structGet(row,'ApplicationFragmentPayloadSHA256',row.PayloadSHA256));
    mask=string(T.TransportBlockId)==string(row.TransportBlockId);
    assert(any(mask),'sixgr:protocol:MissingDecodedPacketOwner', ...
        'A released protocol TB has no original application fragment owner.');
    assert(all(T.ProtocolPayloadSameWaveformTruth(mask)) && ...
        all(T.ProtocolDecodedBitExact(mask)) && ...
        all(string(T.ProtocolDecodedMACSHA256(mask))==string(row.DecodedMACSHA256)) && ...
        all(string(T.ProtocolDecodedRLC_SHA256(mask))==string(row.DecodedRLC_SHA256)) && ...
        all(string(T.ProtocolPayloadSHA256(mask))==fragmentHash), ...
        'sixgr:protocol:InvalidApplicationDeliveryEvidence', ...
        'Released packet must retain its own original decoded MAC/RLC/payload evidence.');
    assert(isfinite(row.DeliveryTime_s) && abs(row.DeliveryTime_s-clock.DeliveryTime_s)<1e-12, ...
        'sixgr:protocol:InvalidProtocolReleaseClock','Release must use the current actual receiver/timer event clock.');
    first=mask & ~logical(T.DeliverySuccess);
    assert(any(first),'sixgr:protocol:DuplicateProtocolCompletion','A bearer completed the same TB twice.');
    T.DeliverySuccess(first)=true; T.FirstSuccessDelivery(first)=true;
    T.ProtocolDeliveryStatus(first)="delivered_after_exact_phy_decode";
    if ~ismember('ProtocolDecodedPayloadSHA256',T.Properties.VariableNames)
        T.ProtocolDecodedPayloadSHA256=repmat("",height(T),1);
    end
    T.ProtocolDecodedPayloadSHA256(first)=fragmentHash;
    T.FirstSuccessSlot(first)=clock.DeliveryCanonicalSlot;
    T.DeliveryCanonicalSlot(first)=clock.DeliveryCanonicalSlot;
    T.DeliveryTime_s(first)=row.DeliveryTime_s;
    T.DeliveryTimingAuthority(first)="pdcp_release_after_original_phy_decode:"+string(clock.TimingAuthority);
    for field=["DeliveryAvailableAtSample","DeliverySampleRateHz","DeliveryAvailableCanonicalSlot"]
        T.(field)(first)=clock.(field);
    end
    T.DeliveryLatency_ms(first)=(row.DeliveryTime_s-double(T.ScheduleTime_s(first)))*1e3;
    assert(all(T.DeliveryLatency_ms(first)>=-1e-9), ...
        'sixgr:protocol:InvalidProtocolReleaseClock','Packet release precedes original scheduling.');
    T.TimingStatus(first)="canonical_timing_ok";
    T.Status(first)="first_success_delivery";
end
end
