function ok=testCommonControlRuntimeReservations()
% Actual installed resource configurations; no receiver/CRC claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
c=sixgr.phy.grid.makeCarrier(cfg); c.NFrame=4; c.NSlot=8;
[p,~]=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfg,c,1,false);
p.AggregationLevel=8;
[~,own]=sixgr.phy.pdcch.allocateNonoverlappingCandidate(c,p,zeros(0,2));
common=plan.controlReservations(48);
assert(size(own,1)==576 && size(intersect(common,own,'rows'),1)==288, ...
    'Reproduce the exact slot-49 288/576-RE SIB1/connected-control collision.');
localReject(@()sixgr.phy.pdcch.allocateNonoverlappingCandidate(c,p,common), ...
    'sixgr:phy:pdcch:NoFreeCandidate');
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),80);
state.CurrentSlot=49; state.CurrentCanonicalSlot=49; state.CurrentFrame=5;
state.CurrentServingIdx(:)=1;
g=struct('UEIndex',1,'ServingCell',1,'RNTI',1,'Direction',"UL", ...
    'ControlSlot',49,'ControlAbsoluteSlot',48,'Slot',50,'PDCCHAggregationLevel',8);
[~,blocked]=sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg,cfg},g([]),g);
assert(~blocked.PDCCHAdmissionSelected && blocked.PDCCHAggregationLevel==8);
state.CurrentSlot=52; state.CurrentCanonicalSlot=52; state.CurrentFrame=6;
g.ControlSlot=52; g.ControlAbsoluteSlot=51; g.Slot=52; g.Direction="DL";
[allowed,~]=sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg,cfg},g,g([]));
assert(allowed.PDCCHAdmissionSelected,'Unoccupied occasions must remain available.');
assert(~isfield(state,'PDCCHResourceLedger') || isempty(fieldnames(state.PDCCHResourceLedger)));

% Future access reservations survive intervening lookups, and are scoped
% to the actual cell, direction, numerology and full signalled rectangle.
c.NStartGrid=5;
data=nrPDSCHConfig; data.PRBSet=0:23; data.SymbolAllocation=[2 12];
coords=sixgr.truth.CommonRAResourceCalendar.channelRectangle(c,data);
e=sixgr.truth.CommonRAResourceCalendar.entry(c,1,57,"DL","msg4_fixture",coords);
calendar=sixgr.truth.CommonRAResourceCalendar; calendar=calendar.reserve(e);
assert(isempty(calendar.lookup(1,40,"DL",c)) && isempty(calendar.lookup(2,57,"DL",c)));
assert(isempty(calendar.lookup(1,57,"UL",c)) && isequal(calendar.lookup(1,57,"DL",c),coords));
budget=struct('PRBSet',0:24,'NPRB',25,'SymbolAllocation',[2 12]);
b=sixgr.truth.CommonRAResourceCalendar.excludeFromBudget(budget,coords,c.NStartGrid);
assert(isequal(b.PRBSet,24) && b.NPRB==1);
budget.SymbolAllocation=[0 2];
b=sixgr.truth.CommonRAResourceCalendar.excludeFromBudget(budget,coords,c.NStartGrid);
assert(isequal(b.PRBSet,0:24),'Disjoint-symbol capacity must not disappear.');
duplicate=e; duplicate.Owner="other_msg4";
localReject(@()calendar.reserve(duplicate),'sixgr:truth:CommonRAResourceCollision');
wrong=c; wrong.SubcarrierSpacing=30;
localReject(@()calendar.lookup(1,57,"DL",wrong),'sixgr:truth:CommonRANumerologyMismatch');
% Installed periodic sounding stays on symbol 13. The previous full-slot
% SRB1 allocation collides; the explicitly shortened allocation does not.
c=sixgr.phy.grid.makeCarrier(cfg); p=nrPUSCHConfig; p.PRBSet=0:23;
p.SymbolAllocation=[0 14];
ul=sixgr.truth.CommonRAResourceCalendar.entry(c,1,59,"UL","srb1_fixture", ...
    sixgr.truth.CommonRAResourceCalendar.channelRectangle(c,p));
localReject(@()sixgr.truth.CommonRAResourceCalendar.assertPeriodicSRSDisjoint(ul,cfg), ...
    'sixgr:truth:CommonRAPeriodicSRSCollision');
p.SymbolAllocation=[cfg.random_access.setup_complete_pusch.symbol_start ...
    cfg.random_access.setup_complete_pusch.num_symbols];
assert(isequal(p.SymbolAllocation,[0 12]));
ul.Coordinates=sixgr.truth.CommonRAResourceCalendar.channelRectangle(c,p);
sixgr.truth.CommonRAResourceCalendar.assertPeriodicSRSDisjoint(ul,cfg);
identity=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
sixgr.truth.CommonRAResourceCalendar.assertInstalledPUCCHDisjoint(ul,cfg,identity);
% The old 13-symbol fix avoided SRS but still overlapped PUCCH on symbol 12.
p.SymbolAllocation=[0 13]; old=ul;
old.Coordinates=sixgr.truth.CommonRAResourceCalendar.channelRectangle(c,p);
localReject(@()sixgr.truth.CommonRAResourceCalendar.assertInstalledPUCCHDisjoint(old,cfg,identity), ...
    'sixgr:truth:CommonRAPUCCHCollision');
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,identity);
cal=sixgr.truth.CommonRAResourceCalendar; cal=cal.reserve(old);
localReject(@()cal.assertPUCCHDisjoint(1,59,c,rrc.resourceByID(0)), ...
    'sixgr:truth:CommonRAPUCCHCollision');
cal=sixgr.truth.CommonRAResourceCalendar; cal=cal.reserve(ul);
cal.assertPUCCHDisjoint(1,59,c,rrc.resourceByID(0));
ok=true; disp('COMMON_CONTROL_RESERVATIONS_PASS: exact SIB1 collision rejected, free AL8 retained, future RA ownership scoped.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('test:MissingExpectedRejection','Expected %s.',id);
end
