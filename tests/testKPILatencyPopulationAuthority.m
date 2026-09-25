function ok=testKPILatencyPopulationAuthority()
raw=struct();
raw.DL=table(["DL";"DL"],[1;1],[true;true],[0;0],[1000;1000], ...
    [1000;1000],[1000;1000],[1;1],[1;2],["tb1";"tb2"], ...
    [0;1],[0;0],[0;0],[1;1],[1;2], ...
    'VariableNames',{'Direction','Goodput_Mbps','CRCPass','BitErrors','BitsCompared', ...
    'TBSize_bits','GoodBits','Frame','Slot','TransportBlockId','HARQProcessId','RV','NDI', ...
    'AirInterfaceObservation_ms','TrialId'});
raw.ApplicationPackets=table(["DL";"DL"],["p1";"p1"],[true;true], ...
    [true;true],[800;800],[0;0],[.009;.005], ...
    'VariableNames',{'Direction','PacketId','DeliverySuccess','SameWaveformProtocolComplete', ...
    'DeliveredBits','EnqueueTime_s','DeliveryTime_s'});
out=reduce(raw); packet=row(out,"DL_Latency_ms"); tb=row(out,"DL_TB_Delivery_Latency_ms");
assert(packet.StrictOk && packet.Value==5 && packet.NumeratorValue==5 && packet.DenominatorValue==1);
assert(tb.StrictOk && tb.Value==1 && tb.DenominatorValue==2 && tb.NumeratorValue==2);
assert(packet.SourceRowsHash~=tb.SourceRowsHash && contains(packet.SourceTablePaths,"application_packet"));
assert(contains(tb.SourceTablePaths,"dl_pdsch_trials"));
scoped=raw; scoped.ApplicationPackets.UEId=[1;2];
out=reduce(scoped); goodput=row(out,"DL_Application_Goodput_Mbps");
assert(goodput.StrictOk && goodput.NumeratorValue==1600 && goodput.FirstSuccessDeliveryCount==2);
badID=raw; badID.ApplicationPackets.PacketId(1)="";
out=reduce(badID); goodput=row(out,"DL_Application_Goodput_Mbps");
assert(~goodput.StrictOk && contains(goodput.FailureReason,"identity_missing"));
assert(row(out,"DL_TB_Delivery_Goodput_Mbps").StrictOk);
missing=reduce(rmfield(raw,'ApplicationPackets'));
assert(~row(missing,"DL_Latency_ms").StrictOk && isnan(row(missing,"DL_Latency_ms").Value));
assert(row(missing,"DL_TB_Delivery_Latency_ms").StrictOk);
none=raw; none.ApplicationPackets.DeliverySuccess(:)=false;
out=reduce(none); packet=row(out,"DL_Latency_ms");
assert(~packet.StrictOk && packet.Status=="unavailable_no_successful_delivery" && isnan(packet.Value));
assert(row(out,"DL_TB_Delivery_Latency_ms").Value==1);
bad=raw; bad.ApplicationPackets.DeliveryTime_s(1)=NaN;
out=reduce(bad); packet=row(out,"DL_Latency_ms");
assert(~packet.StrictOk && contains(packet.FailureReason,"timestamp_missing"));
assert(row(out,"DL_TB_Delivery_Latency_ms").StrictOk);
failed=raw; failed.DL.CRCPass(:)=false; failed.DL.GoodBits(:)=0; failed.DL.Goodput_Mbps(:)=0;
out=reduce(failed); tb=row(out,"DL_TB_Delivery_Latency_ms");
assert(~tb.StrictOk && isnan(tb.Value) && tb.Status=="unavailable_no_successful_delivery");
fprintf('KPI_LATENCY_POPULATION_AUTHORITY_PASS\n'); ok=true;
end
function out=reduce(raw)
out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw,'StrictMode',true,'MeasurementWindowSec',.01);
end
function r=row(out,name)
r=out.ReconstructionSummary(out.ReconstructionSummary.KPIName==name,:);
assert(height(r)==1);
end
