function ok=testSchedulerStageProfiling()
% Same executable grants with profiling off/on. No waveform or BLER claim.
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.mac.scheduler.maxUEPerSlot=1;
ue=struct('RNTI',1,'DLBufferBytes',1200,'CQI',10,'RI',1,'HeadOfLineDelay_ms',1);
budget=struct('NPRB',24,'SymbolAllocation',[0 14]);
reference=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
[expected,~]=reference.schedule(0,ue,budget);
assert(~isempty(expected));
root=tempname; mkdir(root);
session=sixgr.runtime.ExecutionStageProfiler.start(root,true);
sixgr.runtime.ExecutionStageProfiler.setSlot(46,1);
before=rng;
instrumented=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
[actual,~]=instrumented.schedule(0,ue,budget);
assert(isequaln(rng,before),'Wall-clock profiling must not consume scientific RNG.');
clear session
assert(isequaln(actual,expected),'Profiling must preserve exact executable grants and DCI.');
T=readtable(fullfile(root,'reports','csv','execution_stage_profile.csv'),'TextType','string');
required=["DL_PF_total","DL_PF_probe_plan","DL_final_grant_plan", ...
    "DL_resource_TBS","DL_exact_grant_freeze","DL_DCI_creation"];
assert(all(ismember(required,T.Operation)));
assert(all(T.InclusiveSeconds>=T.ExclusiveSeconds) && all(T.ExclusiveSeconds>=0));
assert(all(T.SlotOneBased==46) && all(T.SweepPointIndex==1));
ok=true; disp('SCHEDULER_STAGE_PROFILING_PASS');
end
