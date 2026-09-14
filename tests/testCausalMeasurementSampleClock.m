function ok=testCausalMeasurementSampleClock()
% Declared timing-unit fixtures only. No CSI-RS/UCI/RF execution claim.
setup6GRSimToolkit('Verbose',false);
T=table(["CSI-RS";"CSI-RS"],["UE";"UE"],[1;1],[3;4],[9;9], ...
    [true;true],[300;400],[810;850],[1000;1000],[820;870],[7;7], ...
    ["older_available";"newer_pending"], ...
    'VariableNames',{'SignalType','TargetType','TargetId','ProducerSlot','AvailableSlot', ...
    'Valid','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','ResultAvailableAtSample','MeasurementClockEpoch','MeasurementId'});
snapshot=T;
before=query(T,819);
assert(~before.Usable && before.NextAvailableSample==820);
at=query(T,820);
assert(at.Usable && at.MeasurementId=="older_available");
mid=query(T,869);
assert(mid.Usable && mid.MeasurementId=="older_available");
after=query(T,870);
assert(after.Usable && after.MeasurementId=="newer_pending");
assert(after.ResultAvailableAtSample==870 && after.KnownAtSample==870);
reverse=query(T([2 1],:),870);
assert(reverse.MeasurementId==after.MeasurementId);
% Nonuniform abstract sample-clock slots: no PHY waveform or numerology claim.
boundaries=[0 110 190 300 410 500 620 710 805 910];
nonuniform=query(T,805,boundaries); assert(~nonuniform.Usable);
nonuniform=query(T,870,boundaries); assert(nonuniform.MeasurementId=="newer_pending");
assert(isequaln(T,snapshot),'Selector must never change the producer evidence.');
expect(@()sixgr.phy.refsig.causalMeasurementState(T,9),'sixgr:phy:refsig:MeasurementSampleKnowledgeRequired');
bad=T; bad.Valid=double(bad.Valid); bad.Valid(1)=NaN;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementValidity');
bad=T; bad.Valid=double(bad.Valid); bad.Valid(1)=2;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementValidity');
bad=T; bad.ObservationEndSampleExclusive(2)=871;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=T; bad.ResultAvailableAtSample(2)=870.5;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=T; bad.ObservationSampleRateHz(2)=2000;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=T; bad.MeasurementClockEpoch(2)=8;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=T; bad.AvailableSlot(2)=8;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=T; bad.ResultAvailableAtSample(2)=NaN;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=T; bad.ObservationStartSample(2)=-1;
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=T; bad.ObservationStartSample=string(bad.ObservationStartSample);
expect(@()query(bad,870),'sixgr:phy:refsig:InvalidMeasurementSampleClock');
bad=removevars(T,'ResultAvailableAtSample');
expect(@()query(bad,870),'sixgr:phy:refsig:MissingMeasurementSampleClock');
expect(@()query(T,870.5),'sixgr:phy:refsig:InvalidMeasurementKnowledgeClock');
expect(@()query(T,NaN),'sixgr:phy:refsig:InvalidMeasurementKnowledgeClock');
expect(@()query(T,900),'sixgr:phy:refsig:InvalidMeasurementKnowledgeClock');
expect(@()query(T,870,[0 100 100 300 400 500 600 700 800 900]), ...
    'sixgr:phy:refsig:InvalidMeasurementKnowledgeClock');
expect(@()sixgr.phy.refsig.causalMeasurementState(T,9,'KnownAtSample',870), ...
    'sixgr:phy:refsig:InvalidMeasurementKnowledgeClock');
none=query(T([],:),870); assert(~none.Usable && none.Status=="no_measurements");
invalid=T; invalid.Valid(:)=false; invalid.ResultAvailableAtSample(:)=NaN;
none=query(invalid,870); assert(~none.Usable);
% Unclocked slot-ledger callers keep their established semantics.
legacy=removevars(T,{'ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','ResultAvailableAtSample','MeasurementClockEpoch'});
candidate=sixgr.phy.refsig.causalMeasurementState(legacy,9);
assert(candidate.Usable && candidate.MeasurementId=="older_available" && ...
    candidate.ProducerSlot==3 && candidate.AvailableSlot==9 && candidate.AgeSlots==6);
fprintf('CSI_SAMPLE_CLOCK_UNIT_PASS boundary/retention/order/clock/epoch/malformed/legacy; RF_executions=0 not_12db_qualification=1\n');
ok=true;
end

function out=query(T,sample,boundaries)
if nargin<3, boundaries=0:100:900; end
out=sixgr.phy.refsig.causalMeasurementState(T,9,'SignalType','CSI-RS','TargetType','UE', ...
    'TargetId',1,'KnownAtSample',sample,'ClockSampleRateHz',1000, ...
    'SlotStartSamples',boundaries,'ClockEpoch',7);
end

function expect(action,id)
try
    action();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error %s, expected %s.',err.identifier,id);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
