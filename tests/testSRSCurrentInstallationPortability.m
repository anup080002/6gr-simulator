function ok=testSRSCurrentInstallationPortability()
% Declared installation/measurement boundary, not multi-cell RF reception.
% Real runtime UE builder and both MAC freezes must use CURRENT per-UE SRS.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
% Two configured sectors exercise a non-template serving PCI. Access and
% traffic gates are unchanged; this test calls explicit grant boundaries.
cfg.scenario.layout.nSites=1; cfg.scenario.layout.nSectorsPerSite=2;
rows=cfg.phy.srs.ueResourceBindings;
second=rows; for k=1:numel(second)
    second(k).serving_cell_id=2; second(k).resource_id=second(k).resource_id+17;
end
cfg=installCatalog(cfg,[rows(:);second(:)]);
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),8);
state.CurrentSlot=1; state.CurrentCanonicalSlot=1; state.CurrentServingIdx(:)=1;
[~,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
assert(state.NumUsers==2 && numel(state.BSAntennaRuntime)>=2);
state.CurrentServingIdx=[1;2];
[producer,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,2,'UL');
assert(producer.phy.carrier.NCellID~=cfg.phy.carrier.NCellID && ...
    producer.phy.srs.KBarTC~=cfg.phy.srs.KBarTC);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(producer);
[probe,timing]=legalTiming(cfg,state.ControlGating.SRSMaxAgeSlots);
source=double(timing.ControlAbsoluteSlot)+1;
epoch=cfg.rf.configurationEpoch;
id=sixgr.truth.srsConfigurationContextID(producer,epoch,2,2);
measurement=struct('MeasurementId',"declared_ue2_current_srs",'SignalType',"SRS", ...
    'TargetType',"UE",'TargetId',2,'ServingCell',2,'ProducerSlot',source, ...
    'AvailableSlot',source,'Valid',true,'RI',cfg.phy.pusch.numLayers,'PMI',0, ...
    'MeasurementClockDomain',"slot_only",'ResourceId',strict.ResourceId, ...
    'SRSConfigurationContextID',id,'SRSConfigurationContextVersion',"srs_configuration_context/v1", ...
    'SRSConfigurationEpoch',epoch,'SRSNumPorts',strict.NumSRSPorts, ...
    'SRSResourceID',strict.ResourceId,'SRSResourceIDsJSON',string(jsonencode(strict.ResourceIds)));
accepted=sixgr.truth.captureAcceptedSRSSpatialDecision(measurement,2,measurement.RI,0);
state.ReferenceSignalMeasurementTable=struct2table(measurement,'AsArray',true);
state.SRSValidityState(2)="valid"; state.LastSuccessfulSRSSlotByUE(2)=source;
state.LastSRSObservedSlotByUE(2)=source;
fb=sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRowRuntime();
fb.Valid=true; fb.Direction='UL'; fb.RI=measurement.RI; fb.PMI=0; fb.ServingCell=2;
fb.CQI=10; fb.SINR_dB=20; fb.SourceSlot=source; fb.DeliveredSlot=source; fb.DueSlot=source;
fb.SpatialDecisionSourceSlot=source; fb.SpatialDecisionDeliveredSlot=source;
fb.AcceptedSRSSpatialDecision=accepted; state.LatestULFeedback(2)=fb;
state.CurrentSlot=double(timing.DataAbsoluteSlot)+1; state.CurrentCanonicalSlot=state.CurrentSlot;
state.RuntimeViewMode='future_ul_grant_planning'; state.PlanningDecisionSlot=source;
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,2,'UL',2);
assert(ue.AcceptedSRSCausalUsable && ue.SRSCurrentInstallation.UEIndex==2 && ...
    ue.SRSCurrentInstallation.RNTI==2 && ue.SRSCurrentInstallation.ServingCell==2 && ...
    ue.SRSCurrentInstallation.ConfigurationContextID==id && ...
    isequaln(ue.AcceptedSRSSpatialDecision,accepted));
% Before the repair this template/producer mismatch rejected the valid UE.
throws(@()sixgr.truth.validateAcceptedSRSConfiguration(cfg,accepted), ...
    'sixgr:truth:AcceptedSRSConfigurationMismatch');
for kind=["PF","RR"]
    make=str2func("sixgr.l2.mac.Scheduler"+kind); scheduler=make(cfg,'Direction','UL');
    grant=probe; grant.UEIndex=2; grant.RNTI=2; grant.ServingCell=2;
    grant.PRBSet=0:11; grant.NumLayers=ue.RI; grant.RI=ue.RI;
    grant.Modulation=cfg.phy.pusch.modulation; grant.TargetCodeRate=cfg.phy.pusch.codeRate;
    grant.MCSIndex=cfg.phy.pusch.mcsIndex;
    grant.HARQ=struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false);
    grant=scheduler.attachULSRSAuthorityToGrant(grant,ue);
    first=scheduler.freezePHYGrantForGrant(grant);
    assert(first.ExactPHYFeasible && first.PHYGrant.IsFrozen);
    final=scheduler.freezePHYGrantForGrant(first,'TimingAlreadySelected',true,'ActiveConfig',producer);
    assert(final.PHYGrant.IsFrozen && ...
        isequaln(final.PHYGrant.PrecodingState.AcceptedSRSSpatialDecision,accepted) && ...
        string(final.PHYGrant.PrecodingState.SelectedMatrixSHA256)== ...
        string(first.PHYGrant.PrecodingState.SelectedMatrixSHA256));
    wrong=producer; wrong.phy.srs.resourceIds=strict.ResourceId+100;
    throws(@()scheduler.freezePHYGrantForGrant(first,'TimingAlreadySelected',true,'ActiveConfig',wrong), ...
        'sixgr:truth:AcceptedSRSConfigurationMismatch');
    assert(isequaln(wrong.phy.srs.resourceIds,strict.ResourceId+100), ...
        'Final ActiveConfig must be checked, never overwritten by the old descriptor.');
    changed=cfg; changedRows=changed.phy.srs.ueResourceBindings;
    hit=[changedRows.ue_index]==2 & [changedRows.serving_cell_id]==2;
    changedRows(hit).resource_id=changedRows(hit).resource_id+100;
    changed=installCatalog(changed,changedRows);
    other=make(changed,'Direction','UL');
    throws(@()other.freezePHYGrantForGrant(grant),'sixgr:truth:SRSCurrentInstallationMismatch');
end
% Renaming a resource leaves phase continuity and singleton SRI unchanged,
% but must invalidate the accepted-source configuration identity.
renamed=producer; renamed.phy.srs.resourceIds=strict.ResourceId+100;
assert(sixgr.truth.srsPilotPhaseContextID(producer,epoch,2,2)== ...
    sixgr.truth.srsPilotPhaseContextID(renamed,epoch,2,2));
assert(sixgr.truth.srsConfigurationContextID(renamed,epoch,2,2)~=id);
renamedStrict=sixgr.phy.srs.buildSRSConfigFromScenario(renamed);
assert(sixgr.system.abstraction.singleSRSResourceIndicator(strict)==0 && ...
    sixgr.system.abstraction.singleSRSResourceIndicator(renamedStrict)==0);
legacy=accepted; legacy.SRSConfigurationContextID=sixgr.truth.srsPilotPhaseContextID(producer,epoch,2,2);
legacy=rmfield(legacy,'SRSConfigurationContextVersion');
throws(@()sixgr.truth.validateAcceptedSRSConfiguration(producer,legacy),'sixgr:truth:MissingAcceptedSRSConfiguration');
bad=ue.SRSCurrentInstallation; bad.RNTI=1;
throws(@()sixgr.truth.resolveSRSCurrentInstallation(cfg,bad),'sixgr:srs:UEBindingRNTI');
bad=ue.SRSCurrentInstallation; bad.ConfigurationEpoch=epoch+1;
throws(@()sixgr.truth.resolveSRSCurrentInstallation(cfg,bad),'sixgr:truth:SRSCurrentInstallationMismatch');
nextEpoch=producer; nextEpoch.rf.configurationEpoch=epoch+1;
throws(@()sixgr.truth.validateAcceptedSRSConfiguration(nextEpoch,accepted), ...
    'sixgr:truth:AcceptedSRSConfigurationMismatch');
retired=state; retired.CfgMobility=changed;
throws(@()sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(retired,changed,2,'UL',2), ...
    'sixgr:truth:AcceptedSRSConfigurationMismatch');
fprintf('SRS_CURRENT_INSTALLATION_PORTABILITY_PASS UE2_cell2=1 PF_RR_initial_final=1 physical_qualification=0\n');
ok=true;
end

function cfg=installCatalog(cfg,rows)
cfg.phy.srs.ueResourceBindings=rows;
cfg.lls6g.reference_signals.srs.ue_resource_bindings=rows;
end

function [grant,timing]=legalTiming(cfg,maxAge)
grant=struct('Direction','UL','SymbolAllocation',cfg.phy.pusch.symbolAllocation, ...
    'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation,'TimingAdvanceTicks',0);
for slot=30:80
    grant.Slot=slot; grant.ControlAbsoluteSlot=slot;
    timing=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
    if timing.Valid && double(timing.DataAbsoluteSlot)-slot<=maxAge, return; end
end
error('sixgr:test:MissingULFixtureTiming','No configured legal fresh UL boundary.');
end

function throws(f,id)
try, f(); catch e
    assert(string(e.identifier)==id,'Expected %s, got %s: %s',id,e.identifier,e.message); return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',id);
end
