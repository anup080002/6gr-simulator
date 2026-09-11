function ok=testHARQRetransmissionSymbolBudget()
% No emitted waveform/results: test scheduling opportunity and HARQ state.
setup6GRSimToolkit('Verbose',false);
for direction=["DL","UL"]
    g=struct('SymbolAllocation',[2 12],'Slot',3,'RNTI',4101, ...
        'Direction',direction,'HARQ',struct('HarqID',0));
    [fits,row]=sixgr.l2.mac.harqRetransmissionFitsSymbolBudget(g,[2 8]);
    assert(~fits && height(row)==1 && isequal(row.StoredSymbolAllocation,[2 12]));
    assert(~sixgr.l2.mac.harqRetransmissionFitsSymbolBudget(g,[3 11]));
    assert(~sixgr.l2.mac.harqRetransmissionFitsSymbolBudget(g,[0 0]));
    assert(sixgr.l2.mac.harqRetransmissionFitsSymbolBudget(g,[0 14]));
    assert(sixgr.l2.mac.harqRetransmissionFitsSymbolBudget(g,[2 12]));
end
for kind=["RR","PF"]
    cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
    cfg.phy.pdsch.symbolAllocation=[2 12];
    cfg.phy.pdsch.timeDomainAllocations=[0 2 12 1;1 2 8 1];
    cfg.mac.scheduler.maxUEPerSlot=1;
    cfg.mac.scheduler.maxUEPerSlotDL=1;
    cfg.mac.scheduler.muMimoEnabled=false;
    cfg.mac.harq.enable=true;
    harq=sixgr.l2.mac.HARQEntity(cfg,'Direction','DL', ...
        'NumProcesses',4,'MaxRetx',3,'StoreTB',true);
    if kind=="RR"
        scheduler=sixgr.l2.mac.SchedulerRR(cfg,'Direction','DL','HARQ',harq);
    else
        scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL','HARQ',harq);
    end
    ue=struct('RNTI',4101,'UEIndex',1,'ServingCell',1, ...
        'DLBufferBytes',20000,'ULBufferBytes',0,'CQI',8,'RI',1, ...
        'HeadOfLineDelay_ms',1,'ControlEligible',true,'GrantControlState','ok');
    budget=struct('PRBSet',0:23,'ControlSymbolAllocation',[0 2], ...
        'SymbolAllocation',[2 12]);
    [first,firstInfo]=scheduler.schedule(0,ue,budget);
    assert(numel(first)==1);
    payload=zeros(first.TBSBits,1,'uint8');
    harq.onTx(ue.RNTI,first.HARQ.HarqID,payload,first,0);
    harq.onFeedback(ue.RNTI,first.HARQ.HarqID,'NACK','SourceSlot',0,'FeedbackSlot',4);
    before=harq.peekRetx(ue.RNTI,5);
    narrow=budget; narrow.SymbolAllocation=[2 8];
    [grants,info]=scheduler.schedule(5,ue,narrow);
    assert(height(info.HARQDeferrals)==1);
    decision=sixgr.l2.mac.schedulerHARQDeferralDecisions(info);
    assert(height(decision)==1 && ~decision.Scheduled && decision.Rejected);
    % Production recording must not drop a deferral when CandidateTable is
    % empty (normal RR and possible PF behavior). It must retain producer
    % identity and convert the scheduler zero-based clock exactly once.
    deferredOnly=info; deferredOnly.CandidateTable=table();
    runtime=struct('CurrentSlot',6,'CurrentFrame',1);
    runtime=sixgr.truth.CoupledTruthRuntime.recordSchedulerDecisionRuntime(runtime,deferredOnly,'DL',1);
    published=runtime.SchedulerDecisionTable;
    assert(height(published)==1 && published.Slot==6 && published.SchedulerAbsoluteSlot0==5);
    assert(published.ValueSource==string(class(scheduler))+".schedule");
    assert(published.ValueRole=="runtime_scheduler_deferral_not_transmission");
    assert(published.StoredStartSymbol0==2 && published.StoredNumSymbols==12 && ...
        published.AvailableStartSymbol0==2 && published.AvailableNumSymbols==8);
    % Exercise the actual mixed-table transition, not only an empty table.
    mixed=struct('CurrentSlot',1,'CurrentFrame',1);
    mixed=sixgr.truth.CoupledTruthRuntime.recordSchedulerDecisionRuntime(mixed,firstInfo,'DL',1);
    mixed.CurrentSlot=6;
    mixed=sixgr.truth.CoupledTruthRuntime.recordSchedulerDecisionRuntime(mixed,info,'DL',1);
    check=mixed.SchedulerDecisionTable;
    mask=string(check.DecisionKind)=="stored_harq_allocation_deferred";
    assert(nnz(mask)==1 && all(check.CandidateDecisionRowsAvailable(mask)));
    assert(all(check.StoredNumSymbols(mask)==12) && ...
        all(check.DecisionTruthStatus(mask)=="runtime_scheduler_harq_deferral_truth"));
    for k=1:numel(grants)
        assert(~sixgr.phy.grant.isExplicitHARQRetransmission(grants(k),grants(k).PHYGrant,struct()));
    end
    after=harq.peekRetx(ue.RNTI,6);
    assert(isequal(before.TB,after.TB) && isequal(before.HARQ,after.HARQ));
    resumed=scheduler.schedule(6,ue,budget);
    assert(numel(resumed)==1 && resumed.HARQ.IsRetransmission);
    assert(resumed.TBSBits==first.TBSBits && ...
        isequal(resumed.SymbolAllocation,first.SymbolAllocation));
end
ok=true;
end
