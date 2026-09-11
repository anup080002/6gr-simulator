function ok=testGrantTimingIdentity()
% Scheduler contract tests, not received-waveform or full-run qualification.
setup6GRSimToolkit('Verbose',false);
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
for direction=["UL","DL"]
    scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction',direction);
    grant=sixgr.link.resolveWaveformGrant(cfg,direction,0);
    sixgr.phy.grant.assertGrantTimingIdentity(grant,direction);
    if direction=="UL"
        localQueueIdentity(grant);
    end
    unchanged=sixgr.phy.grant.freezePHYGrant(cfg,direction,grant);
    assert(isequaln(unchanged,grant.PHYGrant),'Unchanged frozen grants must remain reusable.');
    changed=grant;
    changed.SymbolAllocation(2)=changed.SymbolAllocation(2)-1;
    result=scheduler.finalizeExactPHYFeasibility(changed);
    assert(~result.ExactPHYFeasible && contains(string(result.ExactPHYInfeasibilityReason), ...
        'grant_timing_identity_mismatch:SymbolAllocation'), ...
        'Changing duration without changing N2+d2,1 must invalidate the old timing decision.');
    localReject(@()scheduler.buildDCIBitfield(changed));
    localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,direction,changed));
    edits={'ScheduledAbsoluteSlot',grant.ScheduledAbsoluteSlot+1; ...
        'ControlAbsoluteSlot',grant.ControlAbsoluteSlot+1; ...
        'ControlSymbolAllocation',[1 2]; 'PDCCHSymbolAllocation',[0 3]; ...
        'SourceBWPID',"wrong_source_bwp"; 'TargetBWPID',"wrong_target_bwp"; ...
        'SchedulingCCID',"wrong_control_cc"; 'ScheduledCCID',"wrong_data_cc"; ...
        'CarrierIndicator',grant.CarrierIndicator+1; ...
        'HARQFeedbackAbsoluteSlot',grant.HARQFeedbackAbsoluteSlot+1};
    if direction=="UL"
        edits=[edits; {'K2',grant.K2+1; ...
            'TimingAdvanceTicks',grant.TimingDecision.DataDecision.TimingAdvanceTicks+int64(1)}];
    else
        edits=[edits; {'K0',grant.K0+1; 'K1',grant.K1+1; ...
            'TimingAdvanceTicks',grant.TimingDecision.HARQACKDecision.TimingAdvanceTicks+int64(1); ...
            'PUCCHSymbolAllocation',[1 2]}];
    end
    for i=1:size(edits,1)
        bad=grant; bad.(edits{i,1})=edits{i,2};
        localReject(@()sixgr.phy.grant.assertGrantTimingIdentity(bad));
        localReject(@()scheduler.buildDCIBitfield(bad));
        localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,direction,bad));
        result=scheduler.finalizeExactPHYFeasibility(bad);
        assert(~result.ExactPHYFeasible && contains(string(result.ExactPHYInfeasibilityReason), ...
            'grant_timing_identity_mismatch:'),'Finalizer must reject stale timing identity.');
    end
    for symbols={[0 13.5],[0 14 0],[0.1 13],[0 13+1i]}
        bad=grant; bad.SymbolAllocation=symbols{1};
        result=scheduler.finalizeExactPHYFeasibility(bad);
        assert(~result.ExactPHYFeasible && string(result.ExactPHYInfeasibilityReason)== ...
            "invalid_symbol_allocation",'Do not round or truncate malformed allocations.');
        localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,direction,bad));
    end
    % Legal new timing must rebuild the attempt snapshot, even if the old
    % reporting Frame/Slot and complete PHY resource/coding layout match.
    rebound=grant; rebound.ControlAbsoluteSlot=grant.ControlAbsoluteSlot+2;
    rebound=scheduler.attachCanonicalTimingDecision(rebound);
    rebuilt=sixgr.phy.grant.freezePHYGrant(cfg,direction,rebound);
    assert(isequaln(rebuilt.LegacyGrantSnapshot.TimingDecision,rebound.TimingDecision), ...
        'Frozen contract reuse must not retain the previous attempt clock.');
end

% TDD uses its own real scenario timing catalog (not FDD fixture authority).
% These are scheduler contract checks; no new main FDD/TDD run is claimed.
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
tdd=sixgr.lls6g.buildInternalConfig(scenario,tempname);
for direction=["UL","DL"]
    control=8; name='pusch';
    if direction=="DL", control=5; name='pdsch'; end
    scheduler=sixgr.l2.mac.SchedulerPF(tdd,'Direction',direction);
    grant=struct('Direction',direction,'ControlAbsoluteSlot',control, ...
        'SymbolAllocation',tdd.phy.(name).symbolAllocation);
    grant=scheduler.attachCanonicalTimingDecision(grant);
    sixgr.phy.grant.assertGrantTimingIdentity(grant);
    if direction=="UL"
        localQueueIdentity(grant);
    end
    bad=grant; bad.SymbolAllocation(2)=bad.SymbolAllocation(2)-1;
    localReject(@()sixgr.phy.grant.assertGrantTimingIdentity(bad));
    localReject(@()sixgr.phy.grant.freezePHYGrant(tdd,direction,bad));
    bad=grant; bad.ScheduledAbsoluteSlot=bad.ScheduledAbsoluteSlot+1;
    localReject(@()sixgr.phy.grant.assertGrantTimingIdentity(bad));
end
ok=true; disp('GRANT_TIMING_IDENTITY_PASS');
end

function localQueueIdentity(grant)
control=grant.TimingDecision.ControlAbsoluteSlot+1;
data=grant.TimingDecision.DataAbsoluteSlot+1;
queued=sixgr.truth.bindQueuedULGrantOccasion(grant,control,data,1,2,grant.K2);
sixgr.phy.grant.assertGrantTimingIdentity(queued,'UL');
assert(sixgr.truth.runtimeULGrantSlot(queued)==data, ...
    'Runtime queue must not reinterpret canonical zero-based ScheduledAbsoluteSlot.');
badRuntime=queued; badRuntime.Slot=data+1;
localQueueReject(@()sixgr.truth.runtimeULGrantSlot(badRuntime), ...
    'sixgr:truth:QueuedULTimingMismatch');
badCanonical=queued; badCanonical.ScheduledAbsoluteSlot=data;
localReject(@()sixgr.truth.runtimeULGrantSlot(badCanonical));
for invalid={NaN,0,-1,1.5,1+1i,'5',[],[1 2]}
    badRuntime=queued; badRuntime.Slot=invalid{1};
    localQueueReject(@()sixgr.truth.runtimeULGrantSlot(badRuntime), ...
        'sixgr:truth:InvalidQueuedPUSCHDueSlot');
end
localQueueReject(@()sixgr.truth.runtimeULGrantSlot(rmfield(queued,'Slot')), ...
    'sixgr:truth:InvalidQueuedPUSCHDueSlot');
% Resource-only component contracts have an explicit runtime Slot, but no
% scheduler timing proof; an absent Slot must never be guessed from aliases.
assert(sixgr.truth.runtimeULGrantSlot(struct('Slot',1))==1);
assert(queued.ControlSlot==control && queued.Slot==data && queued.Frame==2 && ...
    queued.ControlFrame==1 && queued.ScheduledAbsoluteSlot==data-1 && ...
    isequaln(queued.TimingDecision,grant.TimingDecision));
if isfield(grant,'PHYGrant')
    assert(isequaln(queued.PHYGrant,grant.PHYGrant),'Queue labels must not refreeze PHY authority.');
end
try
    sixgr.truth.bindQueuedULGrantOccasion(grant,control,data+1,1,2,grant.K2);
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:QueuedULTimingMismatch'));
    bad=grant; bad.ScheduledAbsoluteSlot=data;
    localReject(@()sixgr.truth.bindQueuedULGrantOccasion(bad,control,data,1,2,grant.K2));
    return;
end
error('testGrantTimingIdentity:AcceptedWrongQueue','Queue must not relocate a scheduled transmission.');
end

function localQueueReject(fn,identifier)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,identifier),'Unexpected rejection: %s',cause.identifier);
    return;
end
error('testGrantTimingIdentity:AcceptedWrongRuntimeSlot','Invalid runtime queue slot accepted.');
end

function localReject(fn)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:grant:TimingIdentityMismatch'), ...
        'Unexpected rejection: %s: %s',cause.identifier,cause.message);
    return;
end
error('testGrantTimingIdentity:AcceptedStaleTiming','Stale grant timing was accepted.');
end
