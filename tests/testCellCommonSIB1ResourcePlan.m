function ok=testCellCommonSIB1ResourcePlan()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
for selected=0:3
    cfg.phy.ssb.runtimeSSBIndex=selected;
    assert(isequal(sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(cfg),0:3));
    plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
    assert(isequal([plan.SIB1Slot0 cellfun(@(q)q.SIB1Slot0,plan.SIB1AdditionalPlans)],5:8));
    plan.validateSIB1References();
    single=cfg; single.phy.sib1.transmissionScope="selected_ssb_occasion";
    singlePlan=sixgr.phy.frame.CommonDLResourcePlan(single);
    assert(singlePlan.SIB1Slot0==5+selected && isempty(singlePlan.SIB1AdditionalPlans));
end
[planned,checks]=sixgr.truth.buildPlannedREAllocation(cfg, ...
    'TargetChannels',["TYPE0_PDCCH","SIB1_PDSCH"]);
assert(all(checks.status(checks.enabled)=="PASS"));
si=planned(planned.channel=="SIB1_PDSCH",:);
assert(isequal(unique(si.absolute_slot).',5:8));
assert(all(si.evidence_scope=="planned_config_not_runtime_observation"));
bad=cfg; bad.phy.sib1.transmissionScope="receiver_selected_payload";
try
    sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(bad);
    error('test:MissingScopeRejection','Malformed SI scope was accepted.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:broadcast:InvalidSIB1TransmissionScope'));
end
fprintf('CELL_COMMON_SIB1_RESOURCE_PLAN_PASS all_4_beams_reserved_and_planned\n');
ok=true;
end
