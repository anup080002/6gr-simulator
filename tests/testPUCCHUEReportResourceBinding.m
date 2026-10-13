function ok=testPUCCHUEReportResourceBinding()
% Installed per-UE CSI/SR authority, independently of HARQ PRI and TX bits.
% This is a resource/calendar regression, not a detector qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_two_ue_report_binding_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
legacyScenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
legacy=sixgr.lls6g.buildInternalConfig(legacyScenario,tempname);
assert(isempty(cfg.validation.pucch_resources.csi_resource_ids) && ...
    isempty(cfg.validation.pucch_resources.sr_resource_ids) && ...
    isempty(cfg.validation.pucch_resources.scheduling_request_resources), ...
    'Per-UE runtime coverage must not rely on inherited global report associations.');
original=cfg;
id=cfg.phy.frame.DefaultIdentity;
for index=1:2
    ue=struct('UEID',index,'RNTI',index,'ServingCell',1,'PUCCHCell',1, ...
        'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
    rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
    assert(isequal(rrc.Data.CSIResources,9+index), ...
        'test:UECSIResourceBinding', ...
        'Periodic CSI must use its installed UE resource, not the shared single-UE default.');
    assert(isequal(rrc.Data.SRResources,index-1) && ...
        rrc.Data.SchedulingRequestResources.resource_id==index-1, ...
        'test:UESRResourceBinding','SR must retain its per-UE installed association.');
    calendar=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,1,14);
    srCalendar=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,14);
    assert(all(calendar.PUCCHResourceID==9+index) && ...
        all(srCalendar.PUCCHResourceID==index-1));
    assert(isequal(calendar.ReportSlot,[4;9;14]) && ...
        isequal(srCalendar.Slot,[4;9;14]), ...
        'Resource binding must not move a configured report occasion.');
    frame=struct('K1',1,'K1Source','configured_periodic_CSI_report_occasion', ...
        'PDSCHEndSlot',3,'TargetSlot',4,'DecodedPRI',0,'PRIFieldWidth',3, ...
        'PRIProvenance','irrelevant_harq_pri','FirstCCE',0,'NumCCE',8, ...
        'SlotSymbolOwnership',"DDDDDDDDDDGGUU",'FlexibleResolutionProvided',false);
    states=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
    frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(states,3);
    bits=int8([1;0;1;0]);
    a=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,bits,int8([]),frame);
    b=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,1-bits,int8([]),frame);
    assert(a.Plan.Resource.ID==9+index && a.Plan.Resource.Digest==b.Plan.Resource.Digest && ...
        isnan(a.Plan.Data.PRIValue) && isnan(a.Plan.Data.ResourceSetID));
    assert(a.RRCContext.Digest==rrc.Digest && b.RRCContext.Digest==rrc.Digest);
    authority=sixgr.phy.pucch.resolveConfiguredPRI(cfg,index,index,NaN,"csi",ue);
    assert(authority.ResourceId==9+index && isnan(authority.PRIValue) && ...
        isnan(authority.ResourceSetId),'The runtime must share the installed CSI authority.');
    % No per-UE catalog means shared legacy resources, not automatic
    % RNTI-derived separation. Collisions must not disappear by remapping.
    old=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(legacy,ue);
    assert(isequal(old.Data.CSIResources,10) && isequal(old.Data.SRResources,0));
end
assert(isequaln(cfg,original),'Resolving one UE must not mutate the shared installed catalog.');
identities=sixgr.phy.pucch.validateUEReportBindings(cfg);
assert(isequal([identities.UEID],[1 2]) && isequal([identities.RNTI],[1 2]));
assert(isempty(sixgr.phy.pucch.validateUEReportBindings(legacy)));
procedures=sixgr.truth.initializeUEConfiguredSRProcedures(cfg,2,2,1);
assert(all(cellfun(@isempty,procedures(:,2))), ...
    'Do not install per-UE SR state in a cell without a report binding.');
for k=1:2
    assert(isa(procedures{k,1},'sixgr.phy.pucch.SchedulingRequestState') && ...
        procedures{k,1}.Data.UEIndex==k && procedures{k,1}.Data.RNTI==k);
end
reject(@()sixgr.truth.initializeUEConfiguredSRProcedures(cfg,1,1,1), ...
    'sixgr:truth:SRRuntimeBindingMismatch');
reject(@()sixgr.truth.initializeUEConfiguredSRProcedures(cfg,2,1,2), ...
    'sixgr:truth:SRRuntimeBindingMismatch');
badCell=cfg; badCell.validation.pucch_resources.ue_report_bindings(2).serving_cell_id=2;
reject(@()sixgr.truth.initializeUEConfiguredSRProcedures(badCell,2,1,1), ...
    'sixgr:truth:SRRuntimeBindingMismatch');
globalProcedures=sixgr.truth.initializeUEConfiguredSRProcedures(legacy,2,2,1);
assert(all(~cellfun(@isempty,globalProcedures),'all'), ...
    'Legacy global SR installation remains explicit and unchanged.');
% Exercise production initialization, not only the standalone RRC helper.
% In particular, an empty global SR list must not suppress the explicit
% per-UE procedure installation. Uninstalled cells must not acquire an
% invented association merely because they exist in the topology.
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname, ...
    struct('Enabled',true,'NumUsers',2,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth'),struct(),1);
assert(runtime.NumUsers==2);
for k=1:2
    initial=runtime.UEConfiguredSRProcedures{k,1};
    assert(isa(initial,'sixgr.phy.pucch.SchedulingRequestState') && isscalar(initial), ...
        'test:MissingRuntimeUEReportInstallation', ...
        'The shared runtime must install the explicit UE SR procedure without global SR resources.');
    assert(initial.Data.UEIndex==k && initial.Data.RNTI==k && ...
        initial.Data.AbsoluteSlot==0 && ~initial.Data.PendingPositiveSR);
    for cellID=2:size(runtime.UEConfiguredSRProcedures,2)
        assert(isempty(runtime.UEConfiguredSRProcedures{k,cellID}), ...
            'A topology cell without an installed report binding must stay unconfigured.');
    end
end
% CSI installation must not replace a decoded HARQ PRI. Explicit PRI zero
% refers to resource 10, even for UE 2's periodic CSI resource 11.
frame.DecodedPRI=0;
harq=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,int8([1;0;1]),frame);
assert(harq.Plan.Resource.ID==10 && harq.Plan.Data.PRIValue==0, ...
    'An installed periodic CSI binding must not override the decoded HARQ PRI.');
% Receiver-only SR obligations do not consume PendingCSITable or UE bits.
srOnly=cfg; srOnly.phy.csi.reportCSI=false;
for k=1:2
    srOnly.validation.pucch_resources.ue_report_bindings(k).csi_resource_id=[];
    srOnly.validation.pucch_resources.ue_report_bindings(k).csi_report_config_id='';
end
state=struct('CurrentServingIdx',[1;1],'MultiUser',struct('RNTIStart',1), ...
    'NumUsers',2,'SharedWaveformStream',sixgr.truth.CoupledWaveformStream());
for k=1:2
    h=sixgr.truth.buildConfiguredPUCCHReception(state,srOnly,k,4,"sr_rx_"+k);
    assert(h.Assignment.Resource.ID==k-1 && h.Context.Data.SRBits==1 && ...
        h.Context.Data.HARQACKBits==0 && h.Context.Data.CSIPart1Bits==0);
    poisoned=state; poisoned.PendingCSITable=struct('not_a_table',true);
    other=sixgr.truth.buildConfiguredPUCCHReception(poisoned,srOnly,k,4,"sr_rx_"+k);
    assert(h.Assignment.Digest==other.Assignment.Digest && h.Context.Digest==other.Context.Digest);
end
% An explicitly shared resource remains shared. The resolver is not an
% orthogonalizer and does not infer success from distinct UE identities.
collision=cfg;
collision.validation.pucch_resources.ue_report_bindings(2).csi_resource_id=10;
collision.validation.pucch_resources.ue_report_bindings(2).scheduling_request_resources.resource_id=0;
shared=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(collision,ue);
assert(isequal(shared.Data.CSIResources,10) && isequal(shared.Data.SRResources,0));
% Invalid ownership must fail instead of choosing the first/list-modulo row.
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2).rnti=99;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:UEReportBindingRNTI');
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2)= ...
    bad.validation.pucch_resources.ue_report_bindings(1);
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:DuplicateUEReportBinding');
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2).csi_resource_id=999;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:InvalidResourceIndicator');
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2).csi_report_config_id='foreign-report';
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:UEReportConfigurationMismatch');
foreign=ue; foreign.ActiveULBWP=99;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,foreign), ...
    'sixgr:phy:pucch:MissingUEReportBinding');
reject(@()sixgr.phy.pucch.resolveConfiguredPRI(cfg,2,2,NaN,"csi"), ...
    'sixgr:phy:pucch:MissingUEReportIdentity');
reject(@()sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,2,NaN,"csi",ue), ...
    'sixgr:phy:pucch:UEReportIdentityMismatch');
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2).csi_report_config_id='';
bad.phy.csi.reportConfiguration.ReportConfigID='';
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:UEReportConfigurationMismatch');
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2).csi_resource_id=1;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:InvalidResourceIndicator');
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2).scheduling_request_resources.resource_id=11;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:InvalidResourceIndicator');
bad=cfg; bad.lls6g.users.n_users=1;
reject(@()sixgr.phy.pucch.validateUEReportBindings(bad), ...
    'sixgr:phy:pucch:UEReportUserConfigurationMismatch');
bad=cfg; bad.validation.pucch_resources.ue_report_bindings(2)=[];
reject(@()sixgr.phy.pucch.validateUEReportBindings(bad), ...
    'sixgr:phy:pucch:MissingUEReportBinding');
bad=cfg; bad.validation.pucch_resources.enabled=false;
reject(@()sixgr.phy.pucch.validateUEReportBindings(bad), ...
    'sixgr:phy:pucch:DisabledUEReportBindings');
ok=true;
end

function reject(fn,identifier)
try, fn(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s; got %s.',identifier,cause.identifier);
    return;
end
error('test:MissingRejection','Expected %s.',identifier);
end
