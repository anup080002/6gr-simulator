function ok=testReferenceRSRPFilter()
% Analytic, explicitly labelled inputs; these are not production PHY rows.
f=sixgr.rrc.ReferenceRSRPFilter(4,.02,'unit_test_policy');
f=f.observe('one',-80,0,.005,.005);
assert(f.FilteredRSRP_dBm==-80 && f.UpdateCount==1 && f.EffectiveAlpha==1);
assert(isequaln(f,f.observe('one',-80,0,.005,.015)),'Duplicate delivery must not filter twice.');
localReject(@()f.observe('one',-79,0,.005,.015),'sixgr:rrc:RSRPMeasurementMutation');
localReject(@()f.observe('two',-100,.02,.025,.024),'sixgr:rrc:RSRPFilterFutureInput');
g=f.observe('two',-100,.02,.025,.025);
assert(g.FilteredRSRP_dBm==-90 && abs(g.EffectiveAlpha-.5)<1e-14);
g=g.observe('three',-70,.06,.065,.065);
assert(g.FilteredRSRP_dBm==-75 && abs(g.EffectiveAlpha-.75)<1e-14);
localReject(@()g.observe('older',-80,.04,.07,.07),'sixgr:rrc:RSRPFilterTimeReversal');
z=sixgr.rrc.ReferenceRSRPFilter(0,.02,'unit_test_no_filter');
z=z.observe('first',-80,0,0,0); z=z.observe('second',-95,.01,.01,.01);
assert(z.FilteredRSRP_dBm==-95 && z.EffectiveAlpha==1);
localReject(@()sixgr.rrc.ReferenceRSRPFilter(10,.02,'unit_test'),'sixgr:rrc:InvalidRSRPFilterCoefficient');

cfg=struct('initial_access',struct('configuration_epoch',1, ...
    'preconnection_rsrp_filter_coefficient_k',4,'preconnection_rsrp_filter_reference_period_ms',20));
state=struct('CfgMobility',cfg,'CurrentSlot',6,'SlotDuration_s',.001);
sample=struct('ServingCell',1,'Slot',1,'SSBIndex',0,'SS_RSRP_dBm',-80);
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,sample,'ProducerSlot',1,'AvailableSlot',6,'Valid',true,'Direction','DL');
T=state.ReferenceSignalMeasurementTable;
assert(height(T)==1 && T.UEFilteredRSRP_dBm==-80 && T.ServingCell==1 && ...
    isnan(T.Pathloss_dB) && isnan(T.ReferenceSignalTxEPRE_dBm), ...
    'A UE reference does not require a transmitter/pathloss oracle.');
state.CurrentSlot=26; sample.Slot=21; sample.SS_RSRP_dBm=-100;
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,sample,'ProducerSlot',21,'AvailableSlot',26,'Valid',true,'Direction','DL');
assert(state.ReferenceSignalMeasurementTable.UEFilteredRSRP_dBm(end)==-90);
% Changing beam, UE, cell or epoch must never mix an unrelated filter history.
row=table2struct(state.ReferenceSignalMeasurementTable(end,:)); row.RSRP_dBm=-60;
for dimension=["ResourceId","TargetId","ServingCell"]
    other=row; other.(dimension)=other.(dimension)+1;
    [~,observed]=sixgr.truth.filterUEReferenceMeasurement(state,other);
    assert(observed.UEFilteredRSRP_dBm==-60 && observed.UERSRPFilterUpdateCount==1);
end
for epoch=[0 2]
    other=state; other.CfgMobility.initial_access.configuration_epoch=epoch;
    [~,observed]=sixgr.truth.filterUEReferenceMeasurement(other,row);
    assert(observed.UEFilteredRSRP_dBm==-60 && observed.ReferenceConfigurationEpoch==epoch);
end
other=state; other.SweepPointStartSlot=21;
[~,observed]=sixgr.truth.filterUEReferenceMeasurement(other,row);
assert(observed.UEFilteredRSRP_dBm==-60 && observed.UERSRPFilterUpdateCount==1);
incomplete=cfg; incomplete.initial_access=rmfield(incomplete.initial_access,'preconnection_rsrp_filter_reference_period_ms');
localReject(@()sixgr.rrc.resolvePreconnectionRSRPFilter(incomplete),'sixgr:truth:IncompleteUEFilterConfiguration');
negative=cfg; negative.initial_access.configuration_epoch=-1;
localReject(@()sixgr.rrc.resolvePreconnectionRSRPFilter(negative),'MATLAB:expectedNonnegative');
% The same 20 ms measurement spacing gives the same result at different SCS.
for slotDuration=[.001 .0005]
    fresh=struct('CfgMobility',cfg,'CurrentSlot',1,'SlotDuration_s',slotDuration);
    sample=row; sample.MeasurementId='first'; sample.ProducerSlot=1; sample.AvailableSlot=1; sample.RSRP_dBm=-80;
    [fresh,~]=sixgr.truth.filterUEReferenceMeasurement(fresh,sample);
    sample.MeasurementId='next'; sample.ProducerSlot=1+round(.02/slotDuration);
    sample.AvailableSlot=sample.ProducerSlot; sample.RSRP_dBm=-100; fresh.CurrentSlot=sample.AvailableSlot;
    [~,observed]=sixgr.truth.filterUEReferenceMeasurement(fresh,sample);
    assert(observed.UEFilteredRSRP_dBm==-90 && abs(observed.UERSRPFilterEffectiveAlpha-.5)<1e-14);
end
assert(isempty(fieldnames(sixgr.rrc.resolvePreconnectionRSRPFilter(struct()))));
ok=true; disp('REFERENCE_RSRP_FILTER_PASS: log recurrence, elapsed-time coefficient, identity isolation, causal and no-oracle guards.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testReferenceRSRPFilter:MissingRejection','Expected %s.',id);
end
