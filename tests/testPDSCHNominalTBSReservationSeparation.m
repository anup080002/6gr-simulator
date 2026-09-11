function ok=testPDSCHNominalTBSReservationSeparation()
% TS 38.214 nominal TBS N_RE is not a current-slot schedulability verdict.
% Slot/PRB-specific SSB exclusions must be enforced on the actual grant,
% not against the cached PRB-zero/slot-zero nominal sizing probe.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
[bits,bytes,nre]=scheduler.estimateTBS('QPSK',1,25,[2 12],120/1024, ...
    'PlanningOnly',false,'ForceExact',true);
assert(bits>0 && bytes*8==bits && isfinite(nre) && nre>0);
% A correct nominal result must NOT authorize an SSB/DM-RS collision.
g=struct('Direction','DL','RNTI',1,'Slot',40, ...
    'ScheduledAbsoluteSlot',40,'PRBSet',0:24,'SymbolAllocation',[2 12], ...
    'Modulation','QPSK','NumLayers',1,'TargetCodeRate',120/1024, ...
    'MCSIndex',0,'Valid',true);
bad=scheduler.finalizeExactPHYFeasibility(g);
assert(~bad.Valid && ~bad.ExactPHYFeasible && ...
    contains(string(bad.GrantBlocker),'SS/PBCH excludes'));
% Same nominal query, but a different actual slot: no stale slot-zero
% reservation may leak into this grant from the scheduler cache.
g.ScheduledAbsoluteSlot=43;
quiet=scheduler.finalizeExactPHYFeasibility(g);
assert(quiet.Valid && quiet.ExactPHYFeasible, ...
    '%s',string(quiet.ExactPHYInfeasibilityReason));
assert(quiet.ExactAllocationAbsoluteSlot0==43 && ...
    quiet.ExactAllocationCodedBitsG>0 && quiet.NREPerPRB==nre);
assert(quiet.TBSBits==bits && quiet.ExactAllocationReservedRE==0);
% On the SSB occasion a frequency-disjoint allocation remains executable.
% This is resource feasibility, not a new scheduler minimum-PRB policy.
g.ScheduledAbsoluteSlot=40; g.PRBSet=0:1;
legal=scheduler.finalizeExactPHYFeasibility(g);
assert(legal.Valid && legal.ExactPHYFeasible, ...
    '%s',string(legal.ExactPHYInfeasibilityReason));
assert(legal.ExactAllocationAbsoluteSlot0==40 && ...
    legal.ExactAllocationCodedBitsG>0);
% Re-query nominal sizing after both actual allocations.
[again,~,againNRE]=scheduler.estimateTBS('QPSK',1,25,[2 12],120/1024, ...
    'PlanningOnly',false,'ForceExact',true);
assert(again==bits && againNRE==nre);
ok=true;
end
