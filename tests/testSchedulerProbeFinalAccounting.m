function ok=testSchedulerProbeFinalAccounting()
% Scheduler only; no waveform, calibrated BLER, or service claims.
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.mac.scheduler.maxUEPerSlot=1;
cfg.mac.scheduler.minPRBPerUE=3;
cfg.mac.scheduler.maxPRBAllocationPerUE=25;
s=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
ues=repmat(struct('RNTI',1,'CQI',5,'RI',1,'DLBufferBytes',50000, ...
    'ULBufferBytes',0,'ControlEligible',true,'GrantControlState','ok'),1,2);
ues(2).RNTI=2; ues(2).CQI=12;
[grants,info]=s.schedule(1,ues,struct('PRBSet',0:24,'SymbolAllocation',[0 14]));
T=info.CandidateTable; assert(~isempty(grants) && height(T)==2);
assert(all(abs(T.ProbeRate_bps.*T.RateNormalizationDuration_s-T.ProbeTBSBits)<1e-9));
assert(all(abs(T.PFMetric-T.ProbeRate_bps./T.AvgThroughput_bps)<1e-6));
chosen=T(T.Scheduled,:);
assert(chosen.PFMetric==max(T.PFMetric));
assert(chosen.FinalTBSBits==grants(1).TBSBits && chosen.FinalPRBCount==numel(grants(1).PRBSet));
assert(abs(chosen.FinalRate_bps*chosen.RateNormalizationDuration_s-chosen.FinalTBSBits)<1e-9);
assert(chosen.InstantRate_bps==chosen.FinalRate_bps);
assert(all(isnan(T.FinalTBSBits(~T.Scheduled))),'Rejected candidate has no final grant.');
ok=true;
end
