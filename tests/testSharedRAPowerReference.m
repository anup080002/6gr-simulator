function ok=testSharedRAPowerReference()
% Explicit selector inputs, not emitted PHY measurements or run evidence.
cfg=raStrictAnchorConfig();
cfg.initial_access.configuration_epoch=1;
cfg.initial_access.preconnection_rsrp_filter_coefficient_k=4;
cfg.initial_access.preconnection_rsrp_filter_reference_period_ms=20;
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
    'RSRP_dBm',-76,'ServingCell',1);
state=struct('CurrentSlot',15,'CurrentServingIdx',1,'CfgMobility',cfg,'SlotDuration_s',.001);
[state,sample]=sixgr.truth.filterUEReferenceMeasurement(state,sample);
% Codec fixture, not an on-air SIB1 qualification: the main test uses PHY.
bc=sixgr.config.defaultConfig(); bc.frequency.band_name='n77';
bc.phy.carrier.NSizeGrid=25; bc.phy.carrier.SubcarrierSpacing=15;
bc.phy.prach.configurationIndex=157; bc.phy.prach.preambleFormat='B4';
bc.phy.prach.subcarrierSpacing_kHz=30; bc.rrc.sib1.ss_pbch_block_power_dbm=5;
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(bc);
received=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),received);
common=installed.UECommonCellConfiguration;
common.ServingCell=1; common.AvailableSlot=6; common.ConfigurationEpoch=1;
state.UECommonCellConfigurationByUE={common};
state.ReferenceSignalMeasurementTable=struct2table(sample);
[bound,d]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,15);
assert(d.ReferenceUsable && d.AgeSlots==14 && d.Pathloss_dB==81 && ...
    bound.lls6g.userContext.RuntimeServingPathlossMeasurementId=="unit_ssb_1" && ...
    d.SignalledSSPBCHBlockPower_dBm==5 && d.FilteredRSRP_dBm==-76);
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
state.ReferenceSignalMeasurementTable.Pathloss_dB(:)=NaN;
state.ReferenceSignalMeasurementTable.ReferenceSignalTxEPRE_dBm(:)=999;
[~,d]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,55);
assert(d.ReferenceUsable && d.Pathloss_dB==81,'Changing TX diagnostics cannot change a UE power decision.');
state.ReferenceSignalMeasurementTable.RSRP_dBm(:)=-90;
[~,d]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,55);
assert(d.ReferenceUsable && d.Pathloss_dB==81,'Power control consumes retained filtered RSRP, not the raw row.');
for field=["ServingCell","ConfigurationEpoch","AvailableSlot"]
    wrong=state; wrong.UECommonCellConfigurationByUE{1}.(field)=99;
    [cleared,d]=sixgr.truth.bindSharedRAPowerReference(bound,wrong,1,55);
    assert(~d.ReferenceUsable && d.Status=="no_available_decoded_sib1_power" && ...
        isnan(cleared.lls6g.userContext.RuntimeServingPathloss_dB));
end
wrong=state; wrong.UECommonCellConfigurationByUE={struct()};
[~,d]=sixgr.truth.bindSharedRAPowerReference(cfg,wrong,1,55);
assert(~d.ReferenceUsable,'Configured TX power cannot substitute for decoded SIB1.');
wrong=state; wrong.ReferenceSignalMeasurementTable.ServingCell(:)=2;
[~,d]=sixgr.truth.bindSharedRAPowerReference(cfg,wrong,1,55); assert(~d.ReferenceUsable);
changed=cfg; changed.initial_access.preconnection_rsrp_filter_coefficient_k=8;
[~,d]=sixgr.truth.bindSharedRAPowerReference(changed,state,1,55); assert(~d.ReferenceUsable);
wrong=state; wrong.ReferenceSignalMeasurementTable.UEFilteredRSRP_dBm(:)=10;
localReject(@()sixgr.truth.bindSharedRAPowerReference(cfg,wrong,1,55),'sixgr:truth:InvalidRAPowerReference');
localReject(@()sixgr.truth.bindSharedRAPowerReference(cfg,state,1,56),'sixgr:truth:RAPowerReferenceKnowledgeClock');
ok=true; disp('SHARED_RA_POWER_REFERENCE_PASS: decoded SIB1 minus filtered UE RSRP, cell/epoch/age/knowledge guards; no TX diagnostic authority.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testSharedRAPowerReference:MissingRejection','Expected %s.',id);
end
