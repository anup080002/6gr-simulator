function ok=testSLSIssuedControlPopulation()
% Clock/population wiring only; these bits are NOT PHY/control qualification.
empty=struct('TTI',1,'AbsoluteSlot0',0,'GrantsDL',struct([]), ...
    'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',struct('Pathloss_dB',80));
dl=struct('Direction','DL','ControlAbsoluteSlot',0,'ScheduledAbsoluteSlot',1, ...
    'RNTI',201,'SystemServingCellID',1,'DCI',struct('Bits',uint8([1;0;1])));
ul=dl; ul.Direction='UL'; ul.ScheduledAbsoluteSlot=2; ul.DCI.Bits=uint8([0;1;0]);
history=sixgr.system.abstraction.ScheduledSlotHistory(2);
issued=sixgr.system.bindSLSIssuedControlPopulation(empty,dl,1,ul,1);
assert(isempty(issued.GrantsDL) && isempty(issued.GrantsUL) && ...
    isequal(issued.IssuedGrantsDL.DCI.Bits,dl.DCI.Bits) && ...
    isequal(issued.IssuedGrantsUL.DCI.Bits,ul.DCI.Bits) && ...
    ~issued.IssuedControlWaveformExecuted);
history.append(issued);
mutated=issued; mutated.IssuedGrantsUL.DCI.Bits(1)=1;
reject(@()history.append(mutated),'sixgr:abstraction:SlotHistoryMutation');
assert(isequaln(history.scheduledState(1),issued));
% Later DL/UL execution must not reconstruct/re-emit the earlier control.
second=empty; second.TTI=2; second.AbsoluteSlot0=1;
second.GrantsDL=dl; second.GrantCellsDL=1;
second=sixgr.system.bindSLSIssuedControlPopulation(second,struct([]),[],struct([]),[]);
history.append(second);
third=empty; third.TTI=3; third.AbsoluteSlot0=2;
third.GrantsUL=ul; third.GrantCellsUL=1;
third=sixgr.system.bindSLSIssuedControlPopulation(third,struct([]),[],struct([]),[]);
history.append(third);
[states,~]=history.window(3);
assert(numel(states)==3 && numel(states{1}.IssuedGrantsUL)==1 && ...
    isempty(states{2}.IssuedGrantsDL) && isempty(states{3}.IssuedGrantsUL));
reject(@()sixgr.system.bindSLSIssuedControlPopulation(second,dl,1,struct([]),[]), ...
    'sixgr:system:IssuedControlClock');
bad=dl; bad.ControlAbsoluteSlot=1;
reject(@()sixgr.system.bindSLSIssuedControlPopulation(empty,bad,1,struct([]),[]), ...
    'sixgr:system:IssuedControlClock');
bad=dl; bad.ScheduledAbsoluteSlot=-1;
reject(@()sixgr.system.bindSLSIssuedControlPopulation(empty,bad,1,struct([]),[]), ...
    'sixgr:system:IssuedControlClock');
reject(@()sixgr.system.bindSLSIssuedControlPopulation(empty,dl,2,struct([]),[]), ...
    'sixgr:system:IssuedControlIdentity');
bad=dl; bad.Direction='UL';
reject(@()sixgr.system.bindSLSIssuedControlPopulation(empty,bad,1,struct([]),[]), ...
    'sixgr:system:IssuedControlIdentity');
reject(@()sixgr.system.bindSLSIssuedControlPopulation(empty,dl,[],struct([]),[]), ...
    'sixgr:system:IssuedControlPopulation');
% K0=0 is valid and remains independently present in control/data records.
same=dl; same.ScheduledAbsoluteSlot=0;
now=empty; now.GrantsDL=same; now.GrantCellsDL=1;
now=sixgr.system.bindSLSIssuedControlPopulation(now,same,1,struct([]),[]);
assert(isequaln(now.GrantsDL,now.IssuedGrantsDL));
fprintf('SLS_ISSUED_CONTROL_POPULATION_PASS K0_K2_clock=1 immutable=1 no_reemit=1\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'%s',cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
