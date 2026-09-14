function ok=testPUCCHResourcePlanningWithoutPower()
% Resource-selection fixture, not RF/measurement evidence.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_tdd_connected_feedback_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.validation.pucch_resources.power_control.require_measured_reference_rs);
if isfield(cfg.lls6g,'userContext'), cfg.lls6g=rmfield(cfg.lls6g,'userContext'); end
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'harq');
frame=struct('K1',1,'K1Source','decoded_dci','PDSCHEndSlot',3, ...
    'TargetSlot',4,'DecodedPRI',pri.PRIValue,'PRIFieldWidth',3, ...
    'PRIProvenance',pri.Source,'FirstCCE',0,'NumCCE',8, ...
    'SlotSymbolOwnership',"UUUUUUUUUUUUUU", ...
    'FlexibleResolutionProvided',false,'TriggeringEventID',"planning_fixture");
planned=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,true,frame);
assert(isa(planned.Plan,'sixgr.phy.pucch.PUCCHResourcePlan'));
assert(~isfield(planned,'Assignment') && ~isprop(planned.Plan,'PowerControlState'));
assert(planned.Plan.Data.DueSlot==frame.TargetSlot);
changed=cfg;
changed.validation.pucch_resources.configuration_epoch= ...
    changed.validation.pucch_resources.configuration_epoch+1;
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.materialize(changed,planned), ...
    'sixgr:phy:pucch:StaleConfiguration');
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(cfg,ue,true,frame), ...
    'sixgr:phy:pucch:PathlossReferenceSignalMeasurementMissing');
% Explicit static-calibration comparison only. Production validation above
% must still reject absent required measurement at transmit preparation.
calibration=cfg;
calibration.validation.pucch_resources.power_control.require_measured_reference_rs=false;
connected=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(calibration,ue,true,frame);
assert(connected.Assignment.Resource.Digest==planned.Plan.Resource.Digest);
assert(connected.Assignment.Data.DueSlot==planned.Plan.Data.DueSlot);
% Combined HARQ/CSI keeps HARQ DCI PRI; CSI-only authority has no PRI.
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'harq');
frame.DecodedPRI=pri.PRIValue; frame.PRIProvenance=pri.Source;
combined=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined( ...
    cfg,ue,int8([1;0]),int8([1;0;1;0]),int8([]),frame);
txCombined=sixgr.phy.pucch.PUCCHConfigBuilder.connectedCombined( ...
    calibration,ue,int8([1;0]),int8([1;0;1;0]),int8([]),frame);
assert(combined.Plan.Resource.Digest==txCombined.Assignment.Resource.Digest);
assert(combined.Report.Digest==txCombined.Report.Digest);
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'harq');
bad=frame; bad.DecodedPRI=pri.PRIValue;
bad.SlotSymbolOwnership="DDDDDDDDDDDDDD";
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,true,bad), ...
    'sixgr:phy:pucch:IllegalTDDResource');
ok=true;
fprintf('PUCCH_RESOURCE_PLANNING_WITHOUT_POWER_PASS: exact resource plan and strict transmit power binding.\n');
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
