function ok=testControlDataMeasurementAcceptance()
% Authored accounting operands, not executed PHY or calibration evidence.
t=table([0;3],[100;200],[1;0],[0;0],[1;1],[100;0],[.5;.5], ...
    ["tb1";"tb2"],[0;0],[2;4],repmat("receiver_instrumented_ldpc_decode",2,1), ...
    'VariableNames',{'BitErrors','BitsCompared','CRCPass','Crash','DecodeAttempted', ...
    'UniqueDeliveredTBBits','AirInterfaceTTI_ms','TransportGoodputKey','IsRetransmission', ...
    'ComputeLatency_ms','ComputeLatencySource'});
before=t;
r=sixgr.report.collectControlDataMeasurementAcceptance(t,table());
assert(isequaln(before,t));
b=r(r.Direction=="DL"&r.Family=="information_BER",:);
assert(b.Status=="PASS"&&b.Numerator==3&&b.Denominator==300&&b.Value==.01);
b=r(r.Direction=="DL"&r.Family=="attempt_BLER",:);
assert(b.Status=="PASS"&&b.PhysicalFailures==1&&b.Value==.5);
b=r(r.Direction=="DL"&r.Family=="unique_transport_goodput",:);
assert(b.Status=="PASS"&&b.Value==100000&&contains(b.Unit,'active_trial'));
assert(all(r.Status(r.Direction=="UL")=="NOT_EXERCISED"));
assert(all(r.Status(ismember(r.Family,["HARQ_retry_population","packet_latency", ...
    "spatial_application_identity"]))=="NOT_EXERCISED"));
bad=t; bad.UniqueDeliveredTBBits=[100;100]; bad.TransportGoodputKey(:)="same";
r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
assert(r.Status(r.Direction=="DL"&r.Family=="unique_transport_goodput")=="FAIL");
bad=t; bad.BitErrors(1)=101;
r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
assert(r.Status(r.Direction=="DL"&r.Family=="information_BER")=="FAIL");
bad=t;bad.BitsCompared(1)=-1;
r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
assert(r.Status(r.Direction=="DL"&r.Family=="information_BER")=="FAIL");
bad=t;bad.BitErrors(1)=NaN;
r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
b=r(r.Direction=="DL"&r.Family=="information_BER",:);
assert(b.Status=="PARTIAL"&&b.EligibleRows==1&&b.Denominator==200);
for field=["Crash","DecodeAttempted","CRCPass"]
    bad=t;bad.(field)(1)=2;
    r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
    assert(r.Status(r.Direction=="DL"&r.Family=="attempt_BLER")=="FAIL");
end
bad=t;bad.CRCPass(1)=NaN;
r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
b=r(r.Direction=="DL"&r.Family=="attempt_BLER",:);
assert(b.Status=="PARTIAL"&&b.Denominator==1&&b.PhysicalFailures==1);
% A crash and a never-attempted row cannot dilute the radio BLER denominator.
bad=t; bad.Crash(2)=1;
r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
b=r(r.Direction=="DL"&r.Family=="attempt_BLER",:);
assert(b.Denominator==1&&b.Value==0);
bad=removevars(t,{'BitErrors','BitsCompared'}); bad.TBSize_bits=[100;200];
r=sixgr.report.collectControlDataMeasurementAcceptance(bad,table());
assert(r.Status(r.Direction=="DL"&r.Family=="information_BER")=="NOT_EXERCISED");
packets=table("DL",0,3000000,'VariableNames',{'Direction','ReassemblyCompleteFlag','RemainingBits'});
sdus=table("DL",0,"CRC_CONFIRMED_PACKET_MAPPING", ...
    'VariableNames',{'Direction','ProtocolPayloadSameWaveformTruth','DeliveryEvidenceMode'});
r=sixgr.report.collectControlDataMeasurementAcceptance(t,table(),packets,sdus);
b=r(r.Direction=="DL"&r.Family=="packet_latency",:);
assert(b.Status=="NOT_EXERCISED"&&contains(b.Reason,'incomplete_censored')&& ...
    contains(b.Reason,'not_decoded_application_fragments')&&isnan(b.Value));
ok=true;
end
