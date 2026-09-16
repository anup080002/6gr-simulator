function ok=testCSIOnlyPUCCHResourceAuthority()
% Resource-authority fixture, not RF reception or detector qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
frame=struct('K1',1,'K1Source','configured_periodic_CSI_report_occasion', ...
    'PDSCHEndSlot',3,'TargetSlot',4,'DecodedPRI',0,'PRIFieldWidth',3, ...
    'PRIProvenance','irrelevant_harq_pri','FirstCCE',0,'NumCCE',8, ...
    'SlotSymbolOwnership',"UUUUUUUUUUUUUU",'FlexibleResolutionProvided',false);
% The target installs an overlapping SR occasion. Explicit idle state still
% contributes a negative SR indication; resource tests must not omit it.
initial=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(initial,3);
% An installed CSI resource need not occur in any HARQ resource set.
section=cfg.validation.pucch_resources;
resource=section.resources([section.resources.id]==10);
resource.id=23; resource.starting_prb=8;
section.resources(end+1)=resource;
section.csi_resource_ids=23;
cfg.validation.pucch_resources=section;
part1=int8([1;0;1;0]);
planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,part1,int8([]),frame);
assert(planned.Plan.Resource.ID==23, ...
    'test:CSIResourceAuthorityMismatch', ...
    'CSI-only transmission must use configured CSI resource 23, not HARQ PRI resource 10.');
assert(isnan(planned.Plan.Data.PRIValue) && isnan(planned.Plan.Data.ResourceSetID));
assert(string(planned.Plan.Data.PRIProvenance)=="configured_csi_report_resource");
[calendar,~]=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,4,4);
assert(height(calendar)==1 && calendar.PUCCHResourceID==planned.Plan.Resource.ID && ...
    calendar.StartSymbol==planned.Plan.Resource.Data.StartSymbol && ...
    calendar.NumSymbols==planned.Plan.Resource.Data.NumSymbols);
authority=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'csi');
assert(authority.ResourceId==23 && isnan(authority.PRIValue) && isnan(authority.ResourceSetId));
% Primary trace retains unavailable PRI, instead of backfilling a HARQ PRI.
carrier=sixgr.phy.grid.makeCarrier(cfg);
state=struct('CfgMobility',cfg,'MultiUser',struct('Enabled',false), ...
    'SlotsPerFrame',10*carrier.SubcarrierSpacing/15);
feedback=struct('Direction',"DL",'FeedbackForDirection',"DL", ...
    'DueSlot',4,'SourceSlot',3,'UEIndex',1,'RNTI',1,'ServingCell',1, ...
    'UCIType',"csi_part1_part2",'PRIValue',planned.Plan.Data.PRIValue, ...
    'PRIProvenance',planned.Plan.Data.PRIProvenance, ...
    'PUCCHGrantId',"configured_csi_trace_fixture",'PUCCHResourceId',"23");
traced=sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,feedback);
assert(height(traced.PUCCHGrantTraceTable)==1 && ...
    isnan(traced.PUCCHGrantTraceTable.PRIValue) && ...
    isnan(traced.PUCCHGrantTraceTable.TBSBits));
badFeedback=feedback; badFeedback.PRIValue=0;
localReject(@()sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,badFeedback), ...
    'sixgr:truth:InvalidCSIResourceProvenance');
% Unrelated HARQ PRI, list order and payload values cannot change CSI resource.
frame.DecodedPRI=7;
cfg.validation.pucch_resources.resources=flip(cfg.validation.pucch_resources.resources);
other=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,1-part1,int8([]),frame);
assert(other.Plan.Resource.Digest==planned.Plan.Resource.Digest);
assert(other.Plan.Data.PRIProvenance==planned.Plan.Data.PRIProvenance);
% HARQ-bearing reports still resolve the real decoded PRI in a HARQ set.
frame.DecodedPRI=0; frame.K1Source='decoded_dci';
combined=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined( ...
    cfg,ue,int8(1),part1,int8([]),frame);
assert(combined.Plan.Resource.ID==10 && combined.Plan.Data.PRIValue==0 && ...
    combined.Plan.Data.ResourceSetID==1);
% No report/BWP binding exists for an ambiguous flat CSI list: reject it.
bad=cfg; bad.validation.pucch_resources.csi_resource_ids=[10 23];
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCSI( ...
    bad,ue,part1,int8([]),frame),'sixgr:phy:pucch:UnresolvedCSIReportingResource');
localReject(@()sixgr.phy.pucch.resolveConfiguredPRI(bad,1,1,NaN,'csi'), ...
    'sixgr:phy:pucch:UnresolvedCSIReportingResource');
bad.validation.pucch_resources.csi_resource_ids=23.5;
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCSI( ...
    bad,ue,part1,int8([]),frame),'sixgr:phy:pucch:UnresolvedCSIReportingResource');
bad.validation.pucch_resources.csi_resource_ids=999;
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCSI( ...
    bad,ue,part1,int8([]),frame),'sixgr:phy:pucch:InvalidResourceIndicator');
ok=true;
disp('CSI_ONLY_PUCCH_RESOURCE_AUTHORITY_PASS configured resource, PRI independence and invalid bindings.');
end

function localReject(fn,identifier)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,identifier),'Unexpected rejection: %s',cause.identifier);
    return;
end
error('test:MissingRejection','Expected %s.',identifier);
end
