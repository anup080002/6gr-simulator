function plan=planReceivedMIBSIMonitoring(state,ue,endSampleExclusive)
%PLANRECEIVEDMIBSIMONITORING Future RX windows from delivered original BCH.
% Monitoring is not transmission evidence. No gNB SI schedule, TX payload,
% association/precoder, or selected TX monitoring ordinal is consulted.
% Type-0 arithmetic remains in the canonical resolver; sample mapping uses
% the RAW received frame origin, not its filter-delay-adjusted timing alias.
localInteger(endSampleExclusive);
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
assert(isa(owner,'sixgr.truth.CoupledWaveformStream') && isscalar(owner), ...
    'sixgr:truth:ReceivedMIBSharedOwnerRequired','Use the original shared receiver owner.');
now=owner.Events.NextSampleIndex; localInteger(now);
assert(endSampleExclusive>=now,'sixgr:truth:InvalidSIMonitoringHorizon', ...
    'The receive planning horizon cannot end before the original physical clock.');
[available,status,binding]=sixgr.truth.ReceivedMIBDelivery.current(state,ue);
plan=struct('ContractVersion',"sixgr.truth.received_mib_SI_monitoring/v1", ...
    'Source',"delivered_original_MIB_Type0_calendar_and_raw_received_frame_clock", ...
    'Available',false,'Status',string(status),'UEIndex',double(ue), ...
    'PlanningSample',now,'EarliestReceiveSample',NaN, ...
    'HorizonEndSampleExclusive',endSampleExclusive,'SampleRateHz',owner.SampleRateHz, ...
    'ReceiverConfig',struct(),'ReceivedMIBBinding',binding, ...
    'Type0MonitoringWindowSHA256',"",'Windows',table(), ...
    'TransmissionScheduled',false,'ReceiverExecuted',false, ...
    'ConfiguredTransmitOrdinalUsed',false,'PlanSHA256',"");
if ~available, plan.PlanSHA256=localHash(plan); return; end
cfg=sixgr.truth.CoupledTruthRuntime.measurementConfigurationForUE(state,ue);
binding.Context.validate(cfg); data=binding.Context.Data;
plan.ReceiverConfig=cfg;
first=max(now,binding.DeliveredAvailableSample);
plan.EarliestReceiveSample=first;
if data.ReceiverGeometry.FrequencyRange=="FR1" && ...
        any(data.DecodedKSSBEvidence.Lmax==[4 8]) && data.DecodedKSSBEvidence.DecodedKSSB>=24
    plan.Status="no_associated_Type0_for_received_SSB";
    plan.PlanSHA256=localHash(plan); return;
end
origin=data.ReceivedFrameOriginSample;
assert(isa(origin,'double') && isreal(origin) && isscalar(origin) && isfinite(origin) && ...
    origin==fix(origin) && abs(origin)<=flintmax && first>=origin, ...
    'sixgr:truth:InvalidSIMonitoringClock','The delivered capture must follow its original raw measured frame origin.');
geometry=data.ReceiverGeometry;
spec=sixgr.phy.frame.NumerologyCatalog.resolve(geometry.SubcarrierSpacing, ...
    geometry.CyclicPrefix,'generic_waveform_test','');
localInteger(data.AbsoluteFrameNumber);
assert(data.AbsoluteFrameNumber<=flintmax/spec.SlotsPerFrame, ...
    'sixgr:truth:InvalidSIMonitoringClock','Received radio origin exceeds the exact coordinate domain.');
base=data.AbsoluteFrameNumber*spec.SlotsPerFrame;
% Invert arbitrary sample times with the existing exact NR clock. Do not
% round by a mean slot length (normal CP at mu>=2 is not uniform).
firstSlot=base+localFloorSlot(first-origin,data.SampleRateHz,spec);
lastSlot=base+localFloorSlot(endSampleExclusive-origin,data.SampleRateHz,spec)+1;
localInteger(firstSlot); localInteger(lastSlot);
assert(lastSlot<=flintmax/160,'sixgr:truth:InvalidSIMonitoringClock', ...
    'Monitoring radio coordinates must remain exactly representable.');
cfgType0=sixgr.phy.broadcast.ReceivedMIBContext.normalizeReceiverConfig(cfg,65535);
% This is solely a bounded seed for the existing Type-0 facade. Its
% configured selected ordinal must not control the actual receive calendar.
cfgType0=sixgr.util.structSet(cfgType0,'initial_access.type0.monitoring_occasion_ordinal',1);
cfgType0=sixgr.util.structSet(cfgType0,'phy.sib1.monitoringOccasionOrdinal',1);
carrier=sixgr.phy.grid.makeCarrier(cfgType0);
type0=sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,cfgType0,data.MIB);
window=sixgr.phy.pdcch.resolveType0MonitoringWindow(type0.Context,firstSlot,lastSlot);
rows=window.MonitoringOccasions;
rows.ReceiveStartSample=zeros(height(rows),1);
rows.ReceiveEndSampleExclusive=zeros(height(rows),1);
for k=1:height(rows)
    relative=rows.AbsoluteSlot(k)-base; localInteger(relative);
    a=origin+sixgr.phy.frame.slotStartSample(geometry,relative,data.SampleRateHz);
    b=origin+sixgr.phy.frame.slotStartSample(geometry,relative+1,data.SampleRateHz);
    localInteger(a); localInteger(b);
    assert(b>a,'sixgr:truth:InvalidSIMonitoringClock','A complete receive slot must have positive extent.');
    rows.ReceiveStartSample(k)=a; rows.ReceiveEndSampleExclusive(k)=b;
end
% A pair's first member can already be unavailable while its second member
% remains future. Filter individual slots, never the whole pair together.
rows=rows(rows.ReceiveStartSample>=first & ...
    rows.ReceiveEndSampleExclusive<=endSampleExclusive,:);
plan.Type0MonitoringWindowSHA256=string(window.WindowSHA256);
plan.Windows=rows;
plan.Available=~isempty(rows);
plan.Status="no_complete_future_monitoring_window";
if plan.Available, plan.Status="future_received_MIB_monitoring_windows"; end
plan.PlanSHA256=localHash(plan);
end

function slot=localFloorSlot(samples,fs,spec)
localInteger(samples);
ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
assert(isfinite(ticksPerSample) && ticksPerSample>=1 && ticksPerSample==fix(ticksPerSample) && ...
    samples<=flintmax/ticksPerSample,'sixgr:truth:InvalidSIMonitoringClock', ...
    'The received sample horizon must be exactly representable on the NR basic-time clock.');
time=sixgr.phy.frame.AbsoluteTime(int64(samples*ticksPerSample));
[~,frame,within]=time.floorToSlot(spec);
slot=double(frame)*spec.SlotsPerFrame+double(within);
end

function localInteger(value)
assert(isa(value,'double') && isreal(value) && isscalar(value) && isfinite(value) && ...
    value>=0 && value<=flintmax && value==fix(value), ...
    'sixgr:truth:InvalidSIMonitoringClock','Require exact nonnegative double sample/radio coordinates.');
end

function digest=localHash(plan)
% Compact integrity token, not an independent PHY execution attestation.
payload=rmfield(plan,{'PlanSHA256','ReceivedMIBBinding','ReceiverConfig'});
payload.Windows=table2struct(plan.Windows);
payload.ReceivedMIBBindingSHA256=""; payload.ReceivedMIBDeliverySHA256="";
if ~isempty(plan.ReceivedMIBBinding)
    payload.ReceivedMIBBindingSHA256=plan.ReceivedMIBBinding.BindingSHA256;
    payload.ReceivedMIBDeliverySHA256=plan.ReceivedMIBBinding.DeliverySHA256;
end
payload.ReceiverConfigSHA256=sixgr.phy.waveform.WaveformHash.bytes( ...
    getByteStreamFromArray(plan.ReceiverConfig));
digest=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(payload))));
end
