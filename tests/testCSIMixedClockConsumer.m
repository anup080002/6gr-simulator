function ok=testCSIMixedClockConsumer()
% Declared chronology/schema fixtures; no CSI RF execution claim.
setup6GRSimToolkit('Verbose',false);
T=table(["CSI-RS";"SSB"],["UE";"UE"],[1;1],[4;3],[9;3],[true;true], ...
    [300;NaN],[810;NaN],[1000;NaN],[820;NaN],[7;NaN], ...
    ["shared_receiver_sample_clock/v1";"slot_only"], ...
    'VariableNames',{'SignalType','TargetType','TargetId','ProducerSlot','AvailableSlot','Valid', ...
    'ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz', ...
    'ResultAvailableAtSample','MeasurementClockEpoch','MeasurementClockDomain'});
snapshot=T;
legacy=sixgr.phy.refsig.causalMeasurementState(T,9,'SignalType','SSB');
assert(legacy.Usable && legacy.ProducerSlot==3 && isnan(legacy.ResultAvailableAtSample));
opts={'SignalType','CSI-RS','KnownAtSample',819,'ClockSampleRateHz',1000, ...
    'ClockEpoch',7,'SlotStartSamples',0:100:900};
before=sixgr.phy.refsig.causalMeasurementState(T,9,opts{:});
at=sixgr.phy.refsig.causalMeasurementState(T,9,opts{:},'KnownAtSample',820);
assert(~before.Usable && at.Usable && at.ResultAvailableAtSample==820);
expect(@()sixgr.phy.refsig.causalMeasurementState(T,9,'SignalType','CSI-RS'), ...
    'sixgr:phy:refsig:MeasurementSampleKnowledgeRequired');
bad=T; bad.MeasurementClockDomain(1)="slot_only";
expect(@()sixgr.phy.refsig.causalMeasurementState(bad,9,opts{:}), ...
    'sixgr:phy:refsig:InvalidMeasurementClockDomain');
bad=T; bad.MeasurementClockDomain(1)="unrecognized_clock";
expect(@()sixgr.phy.refsig.causalMeasurementState(bad,9,opts{:}), ...
    'sixgr:phy:refsig:InvalidMeasurementClockDomain');
bad=T; bad.MeasurementClockDomain(1)=missing;
expect(@()sixgr.phy.refsig.causalMeasurementState(bad,9,opts{:}), ...
    'sixgr:phy:refsig:InvalidMeasurementClockDomain');
bad=T; bad.ResultAvailableAtSample(1)=NaN;
expect(@()sixgr.phy.refsig.causalMeasurementState(bad,9,opts{:}), ...
    'sixgr:phy:refsig:InvalidMeasurementSampleClock');
assert(isequaln(T,snapshot));
state=struct('NumUsers',1,'CurrentSlot',9,'ControlTrials',struct(), ...
    'CurrentServingIdx',1); % Declared receiver identity, not an RF measurement.
row=table(4,true,true,true,true,true,true,"declared_unit_fixture_no_RF",9, ...
    'VariableNames',{'Slot','Transmitted','Observed','Consumed','ResourceExtractionAvailable', ...
    'ChannelEstimateAvailable','CSIMeasurementAvailable','MeasurementSource','ObservationDeliverySlot'});
row.ObservationStartSample=300; row.ObservationEndSampleExclusive=810;
row.ResultAvailableAtSample=820; row.ObservationSampleRateHz=1000;
row.MeasurementClockEpoch=7; row.MeasurementClockDomain="shared_receiver_sample_clock/v1";
row.DeliverySlotStartSample=800; row.DeliverySlotEndSampleExclusive=900;
published=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,row);
assert(published.ControlTrials.CSIRS.UEIndex==1 && ...
    published.ControlTrials.CSIRS.ServingCell==state.CurrentServingIdx(1));
expect(@()sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime( ...
    published,'CSI-RS','UE',1,9,inf),'sixgr:truth:MeasurementPhysicalClockRequired');
for domain=["slot_only","unrecognized_clock"]
    bad=row; bad.MeasurementClockDomain=domain;
    expect(@()sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,bad), ...
        'sixgr:truth:InvalidCSIRSReceiverClock');
end
bad=removevars(row,'MeasurementClockDomain');
expect(@()sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,bad), ...
    'sixgr:truth:InvalidCSIRSReceiverClock');
fprintf('CSI_MIXED_CLOCK_CONSUMER_PASS padded_slot_rows=1 sample_CSI_strict=1 domain_downgrade_rejected=1 RF_executions=0\n');
ok=true;
end
function expect(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
