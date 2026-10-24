function ok=testPeriodicCSIRefreshAudit()
% Declared metadata tests of the verifier, NOT physical integration evidence.
names={'Direction','Processed','QualityMeasurementSourceSlot','UEIndex', ...
    'ReportIdentity','SourceSlot','DueSlot','SpatialDecisionSourceSlot', ...
    'SpatialDecisionDeliveredSlot','QualityMeasurementDeliveredSlot', ...
    'CSIUCIDecodeOk','CRCPass','DeliveredSlot'};
t=table(["UL";"DL"],[true;false],[20;NaN],[1;1],["ul20";"dl30"], ...
    [20;16],[21;30],[15;NaN],[16;NaN],[21;NaN],[false;false],[1;NaN], ...
    [21;NaN],'VariableNames',names);
t.SourceSignal=["PUSCH-DMRS";"CSI-RS"];
t.AdaptationDeliveryStatus=["accepted_new_feedback_delivery";"not_evaluated"];
t.CSIReferenceSlot=[NaN;29]; t.CSIReportConfigID=["";"periodic1"];
t.CSIConfigurationEpoch=[NaN;1];
t.RNTI=[4660;4660]; t.ServingCell=[1;1];
t.RightCensored=false(2,1); t.CSIUCITransport=["";"pucch"];
t.CSIUCIMultiplexedOnPUSCH=false(2,1);
for f=["AvailableAtSample","ReceiverClockEpoch","CSIUCICRCPass"]
    t.(f)=nan(2,1);
end
for f=["ObservationID","ReceiverContextDigest","CSIUCIDecodedBitsToken"]
    t.(f)=strings(2,1);
end
oldSource=sourceRow(16,90,"old"); newSource=sourceRow(21,180,"new");
t=bindPayload(t,oldSource);
ul=table(20,1,"grant20",true,1,'VariableNames', ...
    {'Slot','UEIndex','FrozenGrantContextId','ULSCHDecodeAttempted','CRCPass'});
completion=table(1,20,"grant20","tx20","rx20",60,80,1000,"actual_fixture_sha",95,true,1, ...
    75,1000,'VariableNames',{'UEIndex','Slot','FrozenGrantContextId','TransmissionID', ...
    'ReceiverObservationID','ReceiverStartSample','ReceiverEndSampleExclusive','ReceiverSampleRateHz', ...
    'ReceiverSampleSHA256','CompletedAtSample','DecodeAttempted','CRCPass', ...
    'TransmitEndSampleExclusive','TransmitSampleRateHz'});
a=struct('Slot',21,'AtSample',100,'SampleRateHz',1000,'ClockEpoch',7,'PendingCSI',t, ...
    'ReceivedCSI',oldSource,'ULTrials',ul,'ULCompletions',completion);
b=a; b.Slot=22; b.AtSample=200; b.PendingCSI.SourceSlot(2)=21;
b.ReceivedCSI=[oldSource;newSource]; b.PendingCSI=bindPayload(b.PendingCSI,newSource);
p=PeriodicCSIRefreshAudit.verify({a,b});
assert(p.Observed && height(p.Witnesses)==1 && ~p.FullScenarioQualified && ...
    ~p.StatisticalQualification && p.Witnesses.CompletedULSlot==20);
% Equal wire bits in different lossless numeric containers are equivalent;
% a changed bit, population, nonbinary value or matrix is not.
for value={int8([1;0;1]),logical([1 0 1]),double([1;0;1])}
    c=b; c.PendingCSI.CSIPart1BitsToken(2)=sixgr.runtime.RawCSVArrayCodec.encode(value{1});
    p=PeriodicCSIRefreshAudit.verify({a,c}); assert(p.Observed);
end
for value={uint8([1;1;1]),uint8([1;0]),[1;0;0.5],[1;0;NaN], ...
        [1;0;Inf],[1;0;-1],complex([1;0;1],[0;0;1]),[1 0;0 1],uint8([])}
    c=b; c.PendingCSI.CSIPart1BitsToken(2)=sixgr.runtime.RawCSVArrayCodec.encode(value{1});
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshPayload');
end
for field=["RightCensored","CSIUCIMultiplexedOnPUSCH"]
    c=b; c.PendingCSI.(field)(2)=true;
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshObligation');
    c=a; c.PendingCSI.(field)(2)=true;
    reject(@()PeriodicCSIRefreshAudit.verify({c,b}),'test:CSIRefreshObligation');
end
c=b; c.PendingCSI.CSIUCITransport(2)="pusch";
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshObligation');
c=b; c.Slot=c.PendingCSI.DueSlot(2);
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshObligation');
c=b; c.ReceivedCSI.ServingCell(2)=2;
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshSource');
p=PeriodicCSIRefreshAudit.verify({a,a}); assert(~p.Observed);
c=a; c.ULTrials=table(); p=PeriodicCSIRefreshAudit.verify({c,b}); assert(~p.Observed);
c=a; c.PendingCSI.Processed(1)=false; p=PeriodicCSIRefreshAudit.verify({c,b}); assert(~p.Observed);
c=b; c.PendingCSI.ReportIdentity(2)="different_obligation";
p=PeriodicCSIRefreshAudit.verify({a,c}); assert(~p.Observed);
c=b; c.ReceivedCSI.Slot(2)=19;
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshSource');
c=b; c.PendingCSI.SpatialDecisionSourceSlot(2)=21;
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshPrematureAuthority');
c=b; c.AtSample=99; reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshClock');
c=a; c.ULTrials.UEIndex=2; p=PeriodicCSIRefreshAudit.verify({c,b}); assert(~p.Observed);
c=a; c.PendingCSI.UEIndex(1)=2; p=PeriodicCSIRefreshAudit.verify({c,b}); assert(~p.Observed);
c=b; c.ReceivedCSI.ResultAvailableAtSample(2)=201;
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshFutureSource');
c=a; c.PendingCSI.SourceSignal(1)="SRS";
p=PeriodicCSIRefreshAudit.verify({c,b}); assert(~p.Observed);
c=a; c.PendingCSI.AdaptationDeliveryStatus(1)="rejected";
p=PeriodicCSIRefreshAudit.verify({c,b}); assert(~p.Observed);
c=a; c.PendingCSI.QualityMeasurementDeliveredSlot(1)=22;
p=PeriodicCSIRefreshAudit.verify({c,b}); assert(~p.Observed);
c=b; c.PendingCSI.DueSlot(2)=31;
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshObligation');
for f=["CSIPart1BitsToken","CSIPart2BitsToken","CSIUCIChannel"]
    c=b; c.PendingCSI.(f)(2)="stale_payload";
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshPayload');
end
for f=["CQI","RI","PMI","LI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
    c=b; c.PendingCSI.(f)(2)=99;
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshPayload');
end
for f=["CSIMeasurementID","CSIMeasurementDigest"]
    c=b; c.PendingCSI.(f)(2)="foreign";
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshSource');
end
c=b; c.ReceivedCSI=[c.ReceivedCSI;c.ReceivedCSI(2,:)];
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshSource');
for f=["MeasurementClockEpoch","MeasurementAvailableAtSample"]
    c=b; c.PendingCSI.(f)(2)=999;
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshMeasurementClock');
end
for f=["ObservationSampleRateHz","MeasurementClockEpoch"]
    c=b; c.ReceivedCSI.(f)(2)=999;
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshMeasurementClock');
end
c=b; c.ReceivedCSI.CSIMeasurementAvailable(2)=false;
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshMeasurementClock');
c=b; c.PendingCSI.MeasurementClockDomain(2)="slot_only";
reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshMeasurementClock');
c=b; c.ClockEpoch=8; reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshClock');
for f=["AvailableAtSample","ReceiverClockEpoch","CSIUCICRCPass"]
    c=b; c.PendingCSI.(f)(2)=1;
    reject(@()PeriodicCSIRefreshAudit.verify({a,c}),'test:CSIRefreshPrematureAuthority');
end
for f=["CompletedAtSample","ReceiverSampleRateHz","TransmitSampleRateHz","ReceiverStartSample"]
    c=a; c.ULCompletions.(f)=999;
    reject(@()PeriodicCSIRefreshAudit.verify({c,b}),'test:CSIRefreshULCompletion');
end
c=a; c.ULCompletions.DecodeAttempted=false;
reject(@()PeriodicCSIRefreshAudit.verify({c,b}),'test:CSIRefreshULCompletion');
c=a; c.ULCompletions.FrozenGrantContextId="other_grant_same_slot";
reject(@()PeriodicCSIRefreshAudit.verify({c,b}),'test:CSIRefreshULCompletion');
c=a; c.ULCompletions=[completion;completion];
reject(@()PeriodicCSIRefreshAudit.verify({c,b}),'test:CSIRefreshULCompletion');
c=a; c.ULCompletions=table();
reject(@()PeriodicCSIRefreshAudit.verify({c,b}),'test:CSIRefreshULCompletion');
% An already available source can be encoded later; do not demand a new
% arrival after the previous snapshot or different numerical CQI/RI/bits.
c=b; c.ReceivedCSI.ResultAvailableAtSample(2)=90;
c.ReceivedCSI.ObservationStartSample(2)=70; c.ReceivedCSI.ObservationEndSampleExclusive(2)=80;
c.ReceivedCSI.DeliverySlotStartSample(2)=80; c.ReceivedCSI.DeliverySlotEndSampleExclusive(2)=100;
c.PendingCSI.MeasurementAvailableAtSample(2)=90;
p=PeriodicCSIRefreshAudit.verify({a,c}); assert(p.Observed);
% Multiple valid refresh transitions must preserve one witness per event.
d=b; d.Slot=27; d.AtSample=300;
third=sourceRow(26,280,"third"); d.ReceivedCSI=[b.ReceivedCSI;third];
d.PendingCSI.SourceSlot(2)=26; d.PendingCSI=bindPayload(d.PendingCSI,third);
p=PeriodicCSIRefreshAudit.verify({a,b,d}); assert(height(p.Witnesses)==2);
% Capture deduplicates the same original completion present in both current
% and accumulated bookkeeping, without retaining matrices or sample arrays.
app=struct('ScheduledGrant',struct('UEIndex',1,'Slot',20,'Direction',"UL", ...
    'PHYGrant',struct('GrantContextId',"grant20")), ...
    'TransmissionReceipt',struct('Identity',struct('PHYGrantContextId',"grant20", ...
    'TransmissionID',"tx20",'EndSampleExclusive',75,'SampleRateHz',1000)), ...
    'ReceiverObservationID',"rx20",'ReceiverStartSample',60,'ReceiverEndSampleExclusive',80, ...
    'ReceiverSampleRateHz',1000,'ReceiverSampleSHA256',"actual_fixture_sha", ...
    'CompletedAtSample',95,'DecodeAttempted',true,'CRCPass',1,'WaveformApplicationVerified',true);
state=struct('SharedWaveformStream',struct('Events',struct('NextSampleIndex',100), ...
    'SampleRateHz',1000,'Physical',struct('ConfigurationEpoch',7)), ...
    'CurrentSlot',21,'PendingCSITable',a.PendingCSI,'ControlTrials',struct('CSIRS',a.ReceivedCSI), ...
    'TestPublishedULTrials',a.ULTrials,'TestRankTransitionApplications',{{app}}, ...
    'TestSRSContinuationCompleted',true,'TestSRSContinuationApplication',app);
captured=PeriodicCSIRefreshAudit.capture(state);
assert(isequaln(captured.ULCompletions,completion));
p=PeriodicCSIRefreshAudit.verify({captured,b}); assert(p.Observed);
bad=state; bad.TestSRSContinuationApplication.CompletedAtSample=96;
reject(@()PeriodicCSIRefreshAudit.capture(bad),'test:CSIRefreshULCompletion');
c=a; c.ULTrials=[c.ULTrials;c.ULTrials];
reject(@()PeriodicCSIRefreshAudit.verify({c,b}),'test:CSIRefreshULCompletion');
ok=true; disp('PERIODIC_CSI_REFRESH_AUDITOR_PASS exact_payload_and_original_UL_completion=1 declared_metadata_only=1 waveform=0');
end

function row=sourceRow(slot,at,identity)
row=table(1,slot,at,'VariableNames',{'UEIndex','Slot','ResultAvailableAtSample'});
row.ServingCell=1;
row.CSIMeasurementID="measurement_"+identity; row.CSIMeasurementDigest="digest_"+identity;
row.ReceiverWindowID="window_"+identity;
row.CSIReportConfigID="periodic1"; row.CSIConfigurationEpoch=1; row.CSIUCIChannel="PUCCH";
row.CSIPart1BitsToken=sixgr.runtime.RawCSVArrayCodec.encode(uint8([1;0;1]));
row.CSIPart2BitsToken=sixgr.runtime.RawCSVArrayCodec.encode(zeros(0,1,'uint8'));
for f=["CQI","RI","PMI","LI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"], row.(f)=1; end
row.MeasurementClockEpoch=7; row.MeasurementClockDomain="shared_receiver_sample_clock/v1";
row.ObservationSampleRateHz=1000; row.ObservationStartSample=at-20;
row.ObservationEndSampleExclusive=at-10; row.ObservationDeliverySlot=slot;
row.DeliverySlotStartSample=at-10; row.DeliverySlotEndSampleExclusive=at+10;
for f=["Transmitted","Observed","Consumed","ResourceExtractionAvailable", ...
        "ChannelEstimateAvailable","CSIMeasurementAvailable"], row.(f)=true; end
end

function t=bindPayload(t,source)
for f=["CSIMeasurementID","CSIMeasurementDigest","CSIUCIChannel","CSIPart1BitsToken", ...
        "CSIPart2BitsToken","MeasurementClockDomain"]
    if ~ismember(f,string(t.Properties.VariableNames)), t.(f)=strings(height(t),1); end
    t.(f)(2)=source.(f);
end
for f=["CQI","RI","PMI","LI","PMI_I11","PMI_I12","PMI_I13","PMI_I2","MeasurementClockEpoch"]
    if ~ismember(f,string(t.Properties.VariableNames)), t.(f)=nan(height(t),1); end
    t.(f)(2)=source.(f);
end
if ~ismember('MeasurementAvailableAtSample',t.Properties.VariableNames), t.MeasurementAvailableAtSample=nan(height(t),1); end
t.MeasurementAvailableAtSample(2)=source.ResultAvailableAtSample;
end
function reject(action,id)
try, action(); catch e, assert(strcmp(e.identifier,id),'%s',e.message); return; end
error('test:ExpectedError','Expected %s.',id);
end
