function ok=testPUCCHPathlossReferenceAuthority()
% Channel-specific YAML identity and native power builder, not RF reception.
% Different PUSCH/PUCCH/SRS references deliberately expose cross-channel leaks.
setup6GRSimToolkit('Verbose',false);
relation=@(id,age)struct('reference_signal_type','SSB', ...
    'reference_signal_id',id,'pathloss_reference_rs_id',id,'maximum_age_slots',age);
cfg=struct();
cfg.phy.pusch.powerControl.pathlossReference=relation(7,1);
cfg.rf.frontend.ul_power_control.srs.pathloss_reference=relation(2,3);
cfg.lls6g.pucch_resources.spatial_relations=relation(0,20);
for channel=["PUCCH","PUSCH","SRS"]
    ref=sixgr.phy.refsig.resolveConfiguredPathlossReference(cfg,channel);
    switch channel
        case "PUCCH", id=0; age=20;
        case "PUSCH", id=7; age=1;
        case "SRS", id=2; age=3;
    end
    assert(ref.Available && ref.ReferenceSignalId==id && ...
        ref.MaximumAgeSlots==age && ref.ReferenceIdentity=="SSB-"+string(id));
end
% No dedicated PUCCH configuration is not permission to borrow PUSCH/SRS.
missing=cfg; missing.lls6g.pucch_resources=struct();
ref=sixgr.phy.refsig.resolveConfiguredPathlossReference(missing,'PUCCH');
assert(~ref.Available);
% Installed validation section is the typed builder's source of truth.
installed=cfg;
installed.validation.pucch_resources.spatial_relations=relation(5,12);
ref=sixgr.phy.refsig.resolveConfiguredPathlossReference(installed,'PUCCH');
assert(ref.ReferenceSignalId==5 && ref.MaximumAgeSlots==12);
installed.validation.pucch_resources=struct();
ref=sixgr.phy.refsig.resolveConfiguredPathlossReference(installed,'PUCCH');
assert(~ref.Available,'An installed empty PUCCH section cannot borrow a legacy alias.');
% Active spatial relation must be explicit for a multi-relation definition.
multi=cfg;
a=relation(0,20); a.id=10; a.active_id=11;
b=relation(4,9); b.id=11; b.active_id=11;
multi.lls6g.pucch_resources.spatial_relations=[a,b];
ref=sixgr.phy.refsig.resolveConfiguredPathlossReference(multi,'PUCCH');
assert(ref.ReferenceSignalId==4 && ref.SpatialRelationId==11 && ref.MaximumAgeSlots==9);
multi.lls6g.pucch_resources.spatial_relations=rmfield([a,b],'active_id');
reject(@()sixgr.phy.refsig.resolveConfiguredPathlossReference(multi,'PUCCH'), ...
    'sixgr:refsig:AmbiguousPathlossSpatialRelation');
for mutation=["conflicting_active","duplicate_id","absent_active_match", ...
        "text_id","logical_id","text_active","vector_active","missing_id"]
    relations=[a,b]; expected='sixgr:refsig:AmbiguousPathlossSpatialRelation';
    switch mutation
        case "conflicting_active", relations(2).active_id=10;
        case "duplicate_id", relations(1).id=11;
        case "absent_active_match"
            relations(1).active_id=12; relations(2).active_id=12;
            expected='sixgr:refsig:MissingActivePathlossSpatialRelation';
        case "text_id"
            relations(1).id='10'; expected='sixgr:refsig:InvalidPathlossSpatialRelationId';
        case "logical_id"
            relations(1).id=true; expected='sixgr:refsig:InvalidPathlossSpatialRelationId';
        case "text_active"
            relations(1).active_id='11'; expected='sixgr:refsig:InvalidActivePathlossSpatialRelationId';
        case "vector_active"
            relations(1).active_id=[10 11]; expected='sixgr:refsig:InvalidActivePathlossSpatialRelationId';
        case "missing_id"
            relations=rmfield(relations,'id'); expected='sixgr:refsig:InvalidPathlossSpatialRelationId';
    end
    multi.lls6g.pucch_resources.spatial_relations=relations;
    reject(@()sixgr.phy.refsig.resolveConfiguredPathlossReference(multi,'PUCCH'),expected);
end
bad=cfg; bad.lls6g.pucch_resources.spatial_relations.reference_signal_id=-1;
reject(@()sixgr.phy.refsig.resolveConfiguredPathlossReference(bad,'PUCCH'), ...
    'sixgr:refsig:InvalidPathlossReferenceSignalId');
for value={"0",'0',true,1+1i,[0 1],NaN,Inf}
    bad=cfg; bad.lls6g.pucch_resources.spatial_relations.reference_signal_id=value{1};
    reject(@()sixgr.phy.refsig.resolveConfiguredPathlossReference(bad,'PUCCH'), ...
        'sixgr:refsig:InvalidPathlossReferenceSignalId');
    bad=cfg; bad.lls6g.pucch_resources.spatial_relations.pathloss_reference_rs_id=value{1};
    reject(@()sixgr.phy.refsig.resolveConfiguredPathlossReference(bad,'PUCCH'), ...
        'sixgr:refsig:InvalidPathlossReferenceRSId');
end
for value={-Inf,-1,NaN,"20",'2',true,1+1i,[1 2]}
    bad=cfg; bad.lls6g.pucch_resources.spatial_relations.maximum_age_slots=value{1};
    reject(@()sixgr.phy.refsig.resolveConfiguredPathlossReference(bad,'PUCCH'), ...
        'sixgr:refsig:InvalidPathlossReferenceAge');
end
% Prove that the actual typed PUCCH builder uses its own configured identity.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
% This identity/age test deliberately retains a finite research age limit.
s=s.toStruct();
s.rf_frontend.ul_power_control.pathloss_reference_lifetime='configured_age_limit';
native=sixgr.lls6g.buildInternalConfig(s,tempname);
native.integration.run_mode='GEOMETRY_NETWORK';
native.integration.configured_snr_is_link_authority=false;
native.phy.pusch.powerControl.pathlossReference=relation(7,1);
native.validation.pucch_resources.spatial_relations.reference_signal_type='SSB';
native.validation.pucch_resources.spatial_relations.reference_signal_id=0;
native.validation.pucch_resources.spatial_relations.maximum_age_slots=20;
% This typed-builder fixture supplies declared measurement inputs directly;
% ordinary execution obtains this context through applyUserContext instead.
meta=struct();
meta.RuntimeServingPathloss_dB=103;
meta.RuntimeServingPathlossSource='ue_decoded_sib1_power_minus_filtered_ssb_rsrp';
meta.RuntimeServingPathlossReferenceRS='SSB-0';
meta.RuntimeServingPathlossMeasurementId='declared_builder_identity_fixture';
meta.RuntimeServingPathlossMeasurementSlot=4;
meta.RuntimeServingPathlossReferenceSignalType='SSB';
meta.RuntimeServingPathlossReferenceSignalId=0;
native.lls6g.userContext=meta;
identity=native.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',native.phy.pusch.RNTI,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
frame=struct('K1',4,'K1Source','decoded_dci','PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'PRIProvenance','declared_builder_identity_fixture', ...
    'FirstCCE',0,'NumCCE',4,'SlotSymbolOwnership','UUUUUUUUUUUUUU', ...
    'FlexibleResolutionProvided',false,'TriggeringEventID','pucch-reference-authority');
sr=sixgr.truth.initializeConfiguredSRProcedures(native,ue);
frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(sr,frame.TargetSlot-1);
connected=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(native,ue,true,frame);
power=connected.Assignment.PowerControlState.Data;
assert(power.RuntimeMeasuredPathlossUsed && power.PathlossdB==103 && ...
    string(power.PathlossReferenceRS)=="SSB-0");
bad=native; bad.lls6g.userContext.RuntimeServingPathlossReferenceSignalId=7;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(bad,ue,true,frame), ...
    'sixgr:phy:pucch:PathlossReferenceIdentityMismatch');
bad=native; bad.lls6g.userContext.RuntimeServingPathlossMeasurementId='';
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(bad,ue,true,frame), ...
    'sixgr:phy:pucch:PathlossReferenceSignalMeasurementMissing');
% Declared measurement/codec boundary inputs exercise reference-age ownership.
% This is selector arithmetic, not a new SSB capture or acquired UE.
policy=sixgr.rrc.resolvePreconnectionRSRPFilter(native);
entry=struct('ResourceId',0,'ServingCell',1, ...
    'ReferenceConfigurationEpoch',native.initial_access.configuration_epoch, ...
    'UEFilteredRSRP_dBm',-103,'RSRP_dBm',-103, ...
    'UERSRPFilterSource',policy.Source,'UERSRPFilterConfigHash',policy.ConfigHash, ...
    'MeasurementId',"declared_age_selector_fixture",'SignalType',"SSB", ...
    'TargetType',"UE",'TargetId',1,'Valid',true,'Direction',"DL", ...
    'ProducerSlot',1,'AvailableSlot',1,'UERSRPFilterEffectiveAlpha',1, ...
    'UERSRPFilterUpdateCount',1);
selector=struct('CurrentSlot',5,'CurrentServingIdx',1, ...
    'ReferenceSignalMeasurementTable',struct2table(entry), ...
    'UECommonCellConfigurationByUE',{{decodedSSBPowerCodecFixture(native,0,1,1)}});
native.phy.pusch.powerControl.maxPathlossMeasurementAgeSlots=1;
[bound,decision]=sixgr.truth.bindSharedSSBPowerReference(native,selector,1,5,0,'PUCCH');
assert(decision.ReferenceUsable && decision.MaximumAgeSlots==20 && ...
    bound.lls6g.userContext.RuntimeServingPathloss_dB==103);
native.phy.pusch.powerControl.maxPathlossMeasurementAgeSlots='not_a_PUCCH_policy';
[~,decision]=sixgr.truth.bindSharedSSBPowerReference(native,selector,1,5,0,'PUCCH');
assert(decision.ReferenceUsable && decision.MaximumAgeSlots==20, ...
    'An unrelated PUSCH age must not be parsed by PUCCH.');
selector.CurrentSlot=22;
[~,decision]=sixgr.truth.bindSharedSSBPowerReference(native,selector,1,22,0,'PUCCH');
assert(~decision.ReferenceUsable && decision.Status=="stale");
ok=true;
fprintf('PUCCH_PATHLOSS_REFERENCE_AUTHORITY_PASS: separate channel identities and typed builder; no RF trial.\n');
end

function reject(fn,expected)
try, fn(); catch cause
    assert(strcmp(cause.identifier,expected),'Expected %s, got %s: %s',expected,cause.identifier,cause.message);
    return;
end
error('test:PUCCHReferenceMissingGuard','Expected %s.',expected);
end
