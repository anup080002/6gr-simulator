function ok=testSharedRAPowerReference()
% Explicit selector inputs, not emitted PHY measurements or run evidence.
cfg=raStrictAnchorConfig();
cfg.random_access.associated_ssb_index=0;
cfg.lls6g.userContext=struct('RuntimeServingPathloss_dB',94, ...
    'RuntimeServingBasePathloss_dB',94);
cfg.phy.pusch.powerControl.maxPathlossMeasurementAgeSlots=20;
cfg.phy.pusch.powerControl.pathlossReference=struct('reference_signal_type','SSB', ...
    'reference_signal_id',0,'maximum_age_slots',20);
sample=struct('SignalType',"SSB",'TargetType',"UE",'TargetId',1,'ResourceId',0, ...
    'ProducerSlot',1,'AvailableSlot',6,'Valid',true,'Direction',"DL", ...
    'MeasurementId',"unit_ssb_1",'Pathloss_dB',81,'PathlossReferenceRS',"SSB-0", ...
    'PathlossSource',"unit_test_physical_reference_inputs",'ReferenceSignalTxEPRE_dBm',5, ...
    'RSRP_dBm',-76);
state=struct('CurrentSlot',15,'ReferenceSignalMeasurementTable',struct2table(sample));
[bound,d]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,15);
assert(d.ReferenceUsable && d.AgeSlots==14 && d.Pathloss_dB==81 && ...
    bound.lls6g.userContext.RuntimeServingPathlossMeasurementId=="unit_ssb_1");
sample.ProducerSlot=21; sample.AvailableSlot=26; sample.MeasurementId="unit_ssb_21";
state.CurrentSlot=45; state.ReferenceSignalMeasurementTable=struct2table(sample);
[blocked,d]=sixgr.truth.bindSharedRAPowerReference(bound,state,1,45);
assert(~d.ReferenceUsable && d.Status=="stale" && d.MinimumAvailableAgeSlots==24 && ...
    isnan(d.Pathloss_dB) && isnan(blocked.lls6g.userContext.RuntimeServingPathloss_dB) && ...
    isempty(blocked.lls6g.userContext.RuntimeServingPathlossMeasurementId) && ...
    blocked.lls6g.userContext.RuntimeServingBasePathloss_dB==94);
sample.ProducerSlot=41; sample.AvailableSlot=46; sample.MeasurementId="unit_ssb_41";
state.ReferenceSignalMeasurementTable=[state.ReferenceSignalMeasurementTable;struct2table(sample)];
[~,d]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,45);
assert(~d.ReferenceUsable,'An undelivered fresh measurement cannot rescue a stale delivered reference.');
state.CurrentSlot=55;
[~,d]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,55);
assert(d.ReferenceUsable && d.MeasurementId=="unit_ssb_41" && d.AgeSlots==14);
state.ReferenceSignalMeasurementTable.ResourceId(:)=1;
[~,d]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,55);
assert(~d.ReferenceUsable && isnan(d.Pathloss_dB),'Another SSB cannot supply the selected reference.');
state.ReferenceSignalMeasurementTable.ResourceId(:)=0;
state.ReferenceSignalMeasurementTable.Pathloss_dB(:)=94;
localReject(@()sixgr.truth.bindSharedRAPowerReference(cfg,state,1,55),'sixgr:truth:InvalidRAPowerReference');
localReject(@()sixgr.truth.bindSharedRAPowerReference(cfg,state,1,56),'sixgr:truth:RAPowerReferenceKnowledgeClock');
ok=true; disp('SHARED_RA_POWER_REFERENCE_PASS: selected identity, same-row power closure, stale/future/wrong-reference rejection; no geometry substitution.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testSharedRAPowerReference:MissingRejection','Expected %s.',id);
end
