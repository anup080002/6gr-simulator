function ok=testConnectedPDCCHPlannedAllocation()
% Configuration-only geometry: no generated DCI claims to be received.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
% Reproduce the integrated pre-slot-zero failure, including every channel.
[~,checks]=sixgr.truth.buildPlannedREAllocation(cfg);
sixgr.truth.assertAllocationPreflight(checks);
localCheck(cfg);
% Deliberately unrelated legacy RNTI and calendar cannot override installed
% connected monitoring. Preserve nonzero offset and multi-slot duration.
cfg.phy.pdcch.rnti=65000;
cfg.phy.pdcch.searchSpace.slotPeriodAndOffset=[1 0];
cfg.phy.pdcch.operatorControl.connected_monitoring.period_slots=10;
cfg.phy.pdcch.operatorControl.connected_monitoring.offset_slots=1;
cfg.phy.pdcch.operatorControl.connected_monitoring.duration_slots=2;
cfg.run.totalSlots=25;
localCheck(cfg);
[carrier,~]=sixgr.phy.grid.makeCarrier(cfg);
try
    sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfg,carrier,65000,false);
catch err
    assert(strcmp(err.identifier,'sixgr:phy:pdcch:ConnectedMonitoringIdentityMismatch'));
    fprintf('CONNECTED_PDCCH_PLANNED_ALLOCATION_PASS all_enabled_preflight=1 identity_guard_retained=1\n');
    ok=true; return;
end
error('test:MissingIdentityRejection','A mismatched runtime RNTI must still be rejected.');
end

function localCheck(cfg)
[planned,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels',"PDCCH");
sixgr.truth.assertAllocationPreflight(checks);
rows=planned(planned.channel=="PDCCH",:);
assert(~isempty(rows) && all(rows.evidence_scope=="planned_config_not_runtime_observation"));
frame=sixgr.phy.FrameStructureEngine(cfg);
policy=cfg.phy.pdcch.operatorControl.connected_monitoring;
expected=[];
for slot0=0:cfg.run.totalSlots-1
    if frame.IsDLSlot(slot0) && mod(slot0-policy.offset_slots,policy.period_slots)<policy.duration_slots
        expected(end+1,1)=slot0; %#ok<AGROW>
    end
end
assert(isequal(unique(rows.absolute_slot),expected),'Connected monitoring calendar differs from installed policy.');
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
[carrier,~]=sixgr.phy.grid.makeCarrier(cfg);
[pdcch,~]=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfg,carrier,context.Data.RNTIValue,false);
for slot0=expected.'
    carrier.NFrame=floor(slot0/carrier.SlotsPerFrame);
    carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
    materialized=sixgr.phy.frame.ChannelAllocationMaterializer.materializePDCCH(carrier,pdcch,'AbsoluteSlot',slot0);
    got=zeros(0,3); slotRows=rows(rows.absolute_slot==slot0,:);
    for k=1:height(slotRows)
        subcarriers=slotRows.subcarrier_start(k)+(0:slotRows.subcarrier_count(k)-1).';
        got=[got;subcarriers,repmat([slotRows.symbol_index(k),slotRows.port_index(k)],numel(subcarriers),1)]; %#ok<AGROW>
    end
    assert(isequal(sortrows(got),sortrows(materialized.ActualCoordinates0Based)), ...
        'Planned RE coordinates must exactly match Toolbox resource materialization.');
end
end
