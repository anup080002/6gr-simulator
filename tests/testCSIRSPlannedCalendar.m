function ok=testCSIRSPlannedCalendar()
% Planned CSI resources must retain the same calendar as actual generation.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
localCheck(cfg,"CSI_RS");
localCheck(cfg,'CSI_RS');
% Explicit cross-frame fixture also starts planning on an inactive slot.
cfg.phy.csirs.period_slots=20;
cfg.phy.csirs.offset_slots=11;
cfg.run.totalSlots=40;
localCheck(cfg,"CSI_RS");
fprintf('CSIRS_PLANNED_CALENDAR_PASS\n');
ok=true;
end

function localCheck(cfg,selector)
[planned,checks]=sixgr.truth.buildPlannedREAllocation(cfg,"TargetChannels",selector);
c=checks(checks.feature=="CSI_RS",:);
assert(height(c)==1 && c.resolved && c.status=="PASS", ...
    'testCSIRSPlannedCalendar:Unresolved','CSI-RS planning failed: %s',strjoin(c.detail));
rows=planned(planned.channel=="CSI_RS",:);
frame=sixgr.phy.FrameStructureEngine(cfg);
expectedSlots=[];
for slot0=0:cfg.run.totalSlots-1
    if frame.IsDLSlot(slot0) && mod(slot0-cfg.phy.csirs.offset_slots,cfg.phy.csirs.period_slots)==0
        expectedSlots(end+1,1)=slot0; %#ok<AGROW>
    end
end
assert(~isempty(expectedSlots) && isequal(unique(rows.absolute_slot),expectedSlots), ...
    'testCSIRSPlannedCalendar:WrongOccasions', ...
    'Planned CSI-RS must neither omit active slots nor populate inactive ones.');
fprintf('CSI_PLANNED_CALENDAR period=%d offset=%d slots=%s\n', ...
    cfg.phy.csirs.period_slots,cfg.phy.csirs.offset_slots,mat2str(expectedSlots'));
end
