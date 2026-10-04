function ok = testSharedDLActualCodeRateFeasibility()
% Reproduce the slot-48 nominal-TBS versus actual rate-matching boundary.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
scheduler = sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
g = struct('Direction','DL','RNTI',1,'Slot',47, ...
    'ScheduledAbsoluteSlot',47,'PRBSet',0,'SymbolAllocation',[2 12], ...
    'Modulation','64QAM','NumLayers',2,'TargetCodeRate',948/1024, ...
    'MCSIndex',28,'MCSTable','qam64_table1','Valid',true, ...
    'CQIUsed',15,'AMCMode','cqi_table','BufferBytesBefore',1414);
actual = scheduler.finalizeExactPHYFeasibility(g);
fprintf('SLOT48_FEASIBILITY TBS=%g G=%g nominalNRE=%g valid=%d\n', ...
    actual.TBSBits,actual.ExactAllocationCodedBitsG, ...
    actual.NREPerPRB,actual.Valid);
% The current scenario has four CSI-RS ports (row 4), not the old
% two-port map. Its additional occupied REs leave G=1536, selecting MCS26.
assert(cfg.phy.csirs.nPorts == 4 && cfg.phy.csirs.rowNumbers == 4);
assert(actual.Valid && actual.MCSIndex == 26 && ...
    actual.CodedCapacityOriginalMCS == 28 && actual.NumLayers == 2, ...
    'Slot-48 AMC must choose the highest feasible MCS without changing rank.');
assert(actual.TBSBits == nrTBS('64QAM',2,1,138,actual.TargetCodeRate,0), ...
    'Slot-48 repair must use exact nominal nrTBS, not a proxy.');
assert(actual.ExactAllocationCodedBitsG == 1536, ...
    'Slot-48 reproduction must retain the actual reserved-resource budget.');
assert(~actual.Valid || actual.TBSBits/actual.ExactAllocationCodedBitsG <= 0.95, ...
    'test:SharedDLUnsafeInitialCodeRate', ...
    'An allocation that violates the existing HARQ initial-rate guard must not be issued as executable.');
assert(actual.ExactInitialCodeRateWithTBCRC <= 0.95 && ...
    actual.BufferBytesAfter == g.BufferBytesBefore-actual.TBSBytes);
nextProfile = sixgr.link.resolveMCSProfile('qam64_table1',27);
nextBits = nrTBS('64QAM',2,1,138,nextProfile.TargetCodeRate,0);
nextCoding = nrDLSCHInfo(nextBits,nextProfile.TargetCodeRate);
assert((nextBits+nextCoding.L)/actual.ExactAllocationCodedBitsG > 0.95, ...
    'The next MCS must independently violate the unchanged capacity limit.');
assert(actual.RawCQIDerivedMCS == 28 && actual.CQIUsed == 15, ...
    'Keep the received CQI recommendation distinct from capacity backoff.');
% A feasible full-band, reference-quiet grant must not inherit a backoff
% from the earlier constrained allocation or the nominal sizing cache.
wide = g; wide.PRBSet = 0:24; wide.ScheduledAbsoluteSlot = 43; wide.Slot = 43;
wideResult = scheduler.finalizeExactPHYFeasibility(wide);
assert(wideResult.Valid && wideResult.MCSIndex == 28);
% A fixed-MCS request must be rejected, not silently adapted.
fixed = rmfield(g,{'CQIUsed','AMCMode'});
fixedResult = scheduler.finalizeExactPHYFeasibility(fixed);
assert(~fixedResult.Valid && ~fixedResult.ExactPHYFeasible && ...
    string(fixedResult.GrantBlocker) == 'initial_dl_code_rate_exceeds_actual_capacity');
localSchedulerRejection(cfg);
ok = true;
end

function localSchedulerRejection(cfg)
% Exercise admission, not just the feasibility helper: no DCI, no reserved
% process, no NDI toggle or queue debit may survive an unissued proposal.
cfg.runtime.link_adaptation.Mode = 'fixed';
cfg.runtime.link_adaptation.DLPolicy = 'fixed';
cfg.runtime.phy.dl.MCSIndex = 28;
cfg.runtime.phy.dl.NumLayers = 2;
cfg.mac.scheduler.muMimoEnabled = false;
cfg.mac.scheduler.minPRBPerUE = 1;
cfg.mac.scheduler.maxPRBAllocationPerUE = 1;
cfg.mac.harq.enable = true;
cfg.mac.harq.numProcesses = 1;
ue = struct('RNTI',1,'RI',2,'CQI',15,'DLBufferBytes',100000, ...
    'ULBufferBytes',0,'ControlEligible',true,'GrantControlState','ok');
budget = struct('PRBSet',0,'SymbolAllocation',[2 12], ...
    'ControlSymbolAllocation',[0 2],'PDCCHCCEBudget',1);
for schedulerClass = ["sixgr.l2.mac.SchedulerPF","sixgr.l2.mac.SchedulerRR"]
    harq = sixgr.l2.mac.HARQEntity(cfg,'Direction','DL');
    scheduler = feval(schedulerClass,cfg,'Direction','DL','HARQ',harq);
    for repetition = 1:2
        [grants,info] = scheduler.schedule(47,ue,budget);
        assert(isempty(grants),'An infeasible fixed-MCS grant must not issue DCI.');
        assert(harq.hasFreeProcess(1,47),'Rejected grant leaked its HARQ process.');
        assert(info.PRBUnderuse == 1,'Rejected grant consumed data resources.');
        if schedulerClass == "sixgr.l2.mac.SchedulerPF"
            assert(any(string(info.CandidateTable.RejectionReason) == ...
                "initial_dl_code_rate_exceeds_actual_capacity"));
        else
            assert(any(string(info.PHYFeasibilityRejections.RejectionReason) == ...
                "initial_dl_code_rate_exceeds_actual_capacity"));
        end
    end
    assert(isempty(harq.getDeliveryLedger()),'No PHY attempt occurred.');
    [next,~] = scheduler.schedule(51,ue,budget);
    assert(isscalar(next) && next.MCSIndex == 28 && ~isempty(fieldnames(next.DCI)), ...
        'A later feasible grant must still be admitted without changing fixed MCS.');
    assert(next.HARQ.NDI && next.HARQ.NDIEpoch == 1, ...
        'Unissued proposals must not consume the receiver-visible NDI epoch.');
    assert(next.BufferBytesBefore == ue.DLBufferBytes, ...
        'Only an admitted grant may account queued traffic.');
end
end
