function ok=testPUCCHActiveSpatialRelationSelection()
% Configuration-selection vectors only; not beam/RF execution evidence.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_tdd_connected_feedback_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.validation.pucch_resources.power_control.require_measured_reference_rs=false;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'harq');
frame=struct('K1',1,'K1Source','decoded_dci','PDSCHEndSlot',3, ...
    'TargetSlot',4,'DecodedPRI',pri.PRIValue,'PRIFieldWidth',3, ...
    'PRIProvenance',pri.Source,'FirstCCE',0,'NumCCE',8, ...
    'SlotSymbolOwnership',"UUUUUUUUUUUUUU", ...
    'FlexibleResolutionProvided',false,'TriggeringEventID',"selection_fixture");
first=cfg.validation.pucch_resources.spatial_relations(1);
first.id=1; first.active_id=2;
second=first; second.id=2;
cfg.validation.pucch_resources.spatial_relations=[first second];
tx=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(cfg,ue,true,frame);
assert(tx.Assignment.SpatialRelationState.Data.SpatialRelationID==2, ...
    'The active relation is not necessarily the first catalog entry.');
reversed=cfg;
reversed.validation.pucch_resources.spatial_relations=[second first];
tx2=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(reversed,ue,true,frame);
assert(tx.Assignment.SpatialRelationState.Digest==tx2.Assignment.SpatialRelationState.Digest, ...
    'Reordering inactive catalog entries must not alter the active relation.');
bad=cfg; bad.validation.pucch_resources.spatial_relations(2).active_id=1;
reject(bad,ue,frame,'sixgr:phy:pucch:AmbiguousSpatialRelation');
bad=cfg; bad.validation.pucch_resources.spatial_relations(1).id=2;
reject(bad,ue,frame,'sixgr:phy:pucch:AmbiguousSpatialRelation');
bad=cfg; bad.validation.pucch_resources.spatial_relations(2).id=3;
reject(bad,ue,frame,'sixgr:phy:pucch:InactiveSpatialRelation');
bad=cfg; bad.validation.pucch_resources.spatial_relations(2).state_age_slots= ...
    second.maximum_age_slots+1;
reject(bad,ue,frame,'sixgr:phy:pucch:StaleSpatialRelation');
ok=true; disp('PUCCH_ACTIVE_SPATIAL_RELATION_SELECTION_PASS');
end

function reject(cfg,ue,frame,id)
try
    sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(cfg,ue,true,frame);
catch cause
    assert(strcmp(cause.identifier,id),'Unexpected error %s.',cause.identifier);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
