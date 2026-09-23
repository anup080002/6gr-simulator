function ok = test5MHzSchedulerMinimumGrantPolicy()
% Real scheduler/resource/TBS paths with declared UE feedback, not PHY proof.
setup6GRSimToolkit('Verbose',false);
path = fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml');
source = sixgr.lls6g.config.loadScenarioConfig(path);
cfg = sixgr.lls6g.buildInternalConfig(source,tempname);
assert(cfg.mac.scheduler.minPRBPerUE==2);
ue = struct('RNTI',1,'UEIndex',1,'ServingCell',1,'DLBufferBytes',500000, ...
    'CQI',15,'RI',2,'PMI',30,'CRI',0,'HeadOfLineDelay_ms',1);
budget = struct('PRBSet',0:24,'SymbolAllocation',[2 12], ...
    'ControlAbsoluteSlot',40,'ControlSymbolAllocation',[0 2]);
for minimum = [4 2]
    fixture = cfg;
    fixture.mac.scheduler.minPRBPerUE = minimum;
    scheduler = sixgr.l2.mac.SchedulerPF(fixture,'Direction','DL');
    for slot = [40 41]
        budget.ControlAbsoluteSlot = slot;
        [grants,info] = scheduler.schedule(slot,ue,budget);
        assert(height(info.ResourceExclusions)==1);
        safe = double(jsondecode(info.ResourceExclusions.AvailablePRBSetJSON));
        assert(isequal(safe(:).',[0 1 23 24]));
        if minimum==4
            assert(isempty(grants));
            assert(all(string(info.CandidateTable.RejectionReason)== ...
                "NO_LEGAL_CONTIGUOUS_PRB_ALLOCATION"));
        else
            assert(numel(grants)==1 && grants.ExactPHYFeasible);
            assert(numel(grants.PRBSet)==2 && all(ismember(grants.PRBSet,safe)) && ...
                all(diff(grants.PRBSet)==1));
            assert(grants.NumLayers==2 && grants.TBSBits>0 && ...
                grants.ExactAllocationAbsoluteSlot0==slot);
        end
    end
    quiet = budget; quiet.ControlAbsoluteSlot = 30;
    [grants,info] = scheduler.schedule(30,ue,quiet);
    assert(numel(grants)==1 && numel(grants.PRBSet)==25 && isempty(info.ResourceExclusions));
end
for minimum = [0 1.5 NaN]
    bad = source.toStruct(); bad.scheduler.min_prbs_per_grant = minimum;
    localReject(bad);
end
bad = source.toStruct();
bad.scheduler.min_prbs_per_grant = bad.system.scheduler.maxPRBAllocationPerUE+1;
localReject(bad);
fprintf('5MHZ_SSB_MINIMUM_GRANT_POLICY_PASS configured_minimum=2 protected_SSB=1\n');
ok = true;
end

function localReject(data)
try
    sixgr.lls6g.buildInternalConfig(sixgr.lls6g.config.ScenarioConfig(data),tempname);
catch cause
    assert(strcmp(cause.identifier,'sixgr:lls6g:InvalidSchedulerMinimumPRBs'), ...
        'Unexpected error %s: %s',cause.identifier,cause.message);
    return;
end
error('test:ExpectedRejection','Invalid minimum PRB policy was accepted.');
end
