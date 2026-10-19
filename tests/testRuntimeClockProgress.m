function ok = testRuntimeClockProgress()
% Clock progress must not be inferred from directional data or access events.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
state=struct('CurrentSlot',46,'CompletedCanonicalSlots',45, ...
    'CanonicalSlotsPerSweepPoint',100,'SlotsPerFrame',20, ...
    'SymbolsPerSlot',14,'DLCompletedFrames',3,'ULCompletedFrames',0);
p=sixgr.truth.resolveRuntimeClockProgress(state);
assert(p.CurrentFrame==3 && p.CompletedFrames==2 && p.TotalFrames==5);
assert(p.CompletedSlots==45 && p.CompletedSymbols==630 && p.TotalSymbols==1400);
assert(p.RunCompletion==0.45);
assert(contains(p.ProgressMeaning,'not_CRC_success_checkpoint_or_final_acceptance'));
% Poison every directional counter. Radio progress must be byte-identical.
poisoned=state; poisoned.DLCompletedFrames=999; poisoned.ULCompletedFrames=999;
poisoned.DLCompletedSlots=999; poisoned.ULCompletedSlots=999;
assert(isequaln(p,sixgr.truth.resolveRuntimeClockProgress(poisoned)));

% Real numerology dimensions, including extended-CP symbol count. This is
% counter arithmetic only, not a new RF or throughput measurement.
for spf=[10 20 80]
    for sps=[12 14]
        state.SlotsPerFrame=spf; state.SymbolsPerSlot=sps;
        for slot=[1 spf spf+1 100]
            state.CurrentSlot=slot; state.CompletedCanonicalSlots=slot-1;
            q=sixgr.truth.resolveRuntimeClockProgress(state);
            assert(q.CurrentFrame==1+floor((slot-1)/spf));
            assert(q.CompletedFrames==floor((slot-1)/spf));
            assert(q.CompletedSymbols==(slot-1)*sps);
            assert(q.RunCompletion==(slot-1)/100);
            state.CompletedCanonicalSlots=slot;
            q=sixgr.truth.resolveRuntimeClockProgress(state);
            assert(q.CompletedSymbols==slot*sps && q.RunCompletion==slot/100);
        end
    end
end
% Campaign clock stays contiguous across points; a partial last radio frame
% is not a wholly processed frame even when the scheduled horizon has ended.
state=struct('CurrentSlot',58,'CompletedCanonicalSlots',58, ...
    'CanonicalSlotsPerSweepPoint',58,'SlotsPerFrame',20,'SymbolsPerSlot',14);
q=sixgr.truth.resolveRuntimeClockProgress(state);
assert(q.RunCompletion==1 && q.CompletedFrames==2 && q.TotalFrames==3);
state.CurrentSlot=101; state.CompletedCanonicalSlots=100;
state.CanonicalSlotsPerSweepPoint=800;
q=sixgr.truth.resolveRuntimeClockProgress(state);
assert(q.CurrentFrame==6 && q.RunCompletion==0.125);

state.CurrentSlot=0; state.CompletedCanonicalSlots=0;
q=sixgr.truth.resolveRuntimeClockProgress(state);
assert(isnan(q.CurrentFrame) && q.CompletedFrames==0 && q.RunCompletion==0);
legacy=rmfield(state,'CompletedCanonicalSlots');
legacy.DLCompletedFrames=99; legacy.ULCompletedFrames=99;
q=sixgr.truth.resolveRuntimeClockProgress(legacy);
assert(isnan(q.CompletedSlots) && isnan(q.CompletedFrames) && isnan(q.RunCompletion));
q=sixgr.truth.resolveRuntimeClockProgress(struct());
assert(isnan(q.CurrentSlot) && isnan(q.TotalFrames));
for field=["CurrentSlot","CompletedCanonicalSlots","SlotsPerFrame","SymbolsPerSlot"]
    bad=state; bad.(field)=[1 2]; localMustThrow(bad);
    bad.(field)=0.5; localMustThrow(bad);
end
bad=state; bad.CompletedCanonicalSlots=1; localMustThrow(bad);
bad=state; bad.CurrentSlot=801; localMustThrow(bad);

% Execute the real scalar table/CSV publication boundary and read it back.
state.CurrentSlot=46; state.CompletedCanonicalSlots=45;
state.CanonicalSlotsPerSweepPoint=100;
published=sixgr.truth.canonicalizeRuntimeStatusSnapshot( ...
    sixgr.truth.resolveRuntimeClockProgress(state));
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU> owned temporary test folder
file=fullfile(folder,'live_stage_status.csv');
sixgr.util.csvWriteTable(file,struct2table(published),'PreserveSchema',true);
row=sixgr.util.csvReadTable(file);
assert(height(row)==1 && row.CurrentFrame==3 && row.CompletedFrames==2);
assert(row.CompletedSlots==45 && row.CompletedSymbols==630 && row.RunCompletion==0.45);

% Guard production wiring: completion is set only after shared receiver
% drain; older checkpoints use the verified saved boundary, not trial rows.
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
start=strfind(source,'[runtimeState,~]=sixgr.truth.advanceSharedSlotWithULGrants(');
assert(numel(start)==1);
tail=source(start:end);
drain=strfind(tail,'localDrainSharedDataPlans(');
commit=strfind(tail,'runtimeState.CompletedCanonicalSlots=double(absoluteFrame);');
publish=strfind(tail,'localPublishCoupledTruthRuntimeState(cfg,runFolder');
assert(drain(1)<commit(1) && commit(1)<publish(1));
assert(contains(source,'runtimeState.CompletedCanonicalSlots=double(restored.CompletedSlot);'));
assert(~contains(source,'completedFrames = min(dlCompletedFrames, ulCompletedFrames)'));
assert(contains(source,'structGet(status, "CurrentFrame", NaN)'));
assert(contains(source,'clock = sixgr.truth.resolveRuntimeClockProgress(state);'));
assert(contains(source,'clock = sixgr.truth.resolveRuntimeClockProgress(runtimeState);'));
ok=true;
fprintf('[PASS] testRuntimeClockProgress\n');
end

function localMustThrow(state)
try
    sixgr.truth.resolveRuntimeClockProgress(state);
catch ME
    assert(strcmp(ME.identifier,'sixgr:truth:InvalidRuntimeClockProgress'));
    return;
end
error('testRuntimeClockProgress:MissingError','Invalid clock counter accepted.');
end
