function ok=testREAllocationRadioClock()
% Exact allocation-clock arithmetic and bounded original planner wiring.
% Boundary vectors are declared metadata, not executed radio observations.
% Actual broadcast frame-1024 publication is tested by the original TX in
% testBroadcastRuntimeOrigin and testMixedSSBNativeResources.
setup6GRSimToolkit('Verbose',false);
for slotsPerFrame=[10 20 40 80 160]
    slot0=[0 slotsPerFrame-1 slotsPerFrame 1024*slotsPerFrame-1 ...
        1024*slotsPerFrame 1024*slotsPerFrame+1];
    original=slot0;
    [sfn,within]=sixgr.truth.reAllocationRadioClock(slot0,slotsPerFrame);
    assert(isequal(sfn,[0 0 1 1023 0 0]) && ...
        isequal(within,[0 slotsPerFrame-1 0 slotsPerFrame-1 0 1]) && ...
        isequal(slot0,original));
    [columnSFN,columnSlot]=sixgr.truth.reAllocationRadioClock(slot0',slotsPerFrame);
    assert(isequal(columnSFN,sfn') && isequal(columnSlot,within'));
end
% Carrier15 and nativeSSB30 clocks at one physical boundary. PRACH's
% carrier-origin slot remains carrier-clocked, not PRACH-grid-SCS-clocked.
slot0=[10240;20480;10240;20479]; counts=[10;20;10;20];
[sfn,within]=sixgr.truth.reAllocationRadioClock(slot0,counts);
assert(isequal(sfn,[0;0;0;1023]) && isequal(within,[0;0;0;19]));
for shape={[0 1],[1 0],[0 0]}
    empty=zeros(shape{1});
    [sfn,within]=sixgr.truth.reAllocationRadioClock(empty,20);
    assert(isequal(size(sfn),size(empty)) && isequal(size(within),size(empty)));
end
for bad={-1,.5,NaN,Inf,flintmax,single(0),uint64(0),false,'0',[0 1;2 3]}
    reject(@()sixgr.truth.reAllocationRadioClock(bad{1},20));
end
for bad={0,-1,.5,NaN,Inf,flintmax,single(20),true,'20',[10 20],[10;20;30]}
    reject(@()sixgr.truth.reAllocationRadioClock([0;1],bad{1}));
end
% Exercise the actual planner's finalization on a short configured horizon;
% no many-thousand-slot plan is required to check its shared clock adapter.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.run.totalSlots=20;
[T,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels','SSB_PBCH');
assert(~isempty(T) && all(checks.resolved(checks.enabled)) && ...
    all(T.evidence_scope=="planned_config_not_runtime_observation"));
c=sixgr.phy.grid.makeCarrier(cfg);
assert(all(T.sfn==mod(floor(T.absolute_slot/double(c.SlotsPerFrame)),1024)) && ...
    all(T.slot_within_frame==mod(T.absolute_slot,double(c.SlotsPerFrame))));
fprintf('RE_ALLOCATION_RADIO_CLOCK_PASS boundary_numerologies=5 planner_slots=20 planned_rows=%d receiver_executions=0\n',height(T));
ok=true;
end

function reject(fn)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:InvalidREAllocationClock'), ...
        'Unexpected failure: %s %s',cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected exact allocation-clock rejection.');
end
