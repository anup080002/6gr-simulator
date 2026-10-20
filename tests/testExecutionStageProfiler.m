function ok=testExecutionStageProfiler()
% Diagnostic timers must not alter RNG, bytes or radio results.
root=tempname; mkdir(root);
before=rng;
disabled=sixgr.runtime.ExecutionStageProfiler.start(root,false);
a=sixgr.runtime.ExecutionStageProfiler.scope("channel","disabled"); clear a disabled
assert(~isfolder(fullfile(root,'reports')));
session=sixgr.runtime.ExecutionStageProfiler.start(root,true);
sixgr.runtime.ExecutionStageProfiler.setSlot(45,1);
outer=sixgr.runtime.ExecutionStageProfiler.scope("receiver_pipeline","test_nested_scope");
bytes=uint8(0:255);
digest=sixgr.util.sha256Hex(bytes);
sixgr.util.csvWriteTable(fullfile(root,'real_fixture.csv'),table((1:5)'));
clear outer
% Exception unwinding closes timing scopes without claiming decode success.
try
    failInsideScope();
catch cause
    assert(strcmp(cause.identifier,'test:ExpectedDiagnosticFailure'));
end
sixgr.runtime.ExecutionStageProfiler.setSlot(46,1);
second=sixgr.runtime.ExecutionStageProfiler.scope("RF","test_scope"); clear second session
assert(isequal(rng,before),'Profiling must never consume scientific RNG.');
T=readtable(fullfile(root,'reports','csv','execution_stage_profile.csv'),'TextType','string');
assert(all(T.InclusiveSeconds>=T.ExclusiveSeconds) && all(T.ExclusiveSeconds>=0));
assert(all(T.ScopeExitCount>=1) && all(T.EvidenceScope=="wall_clock_scope_exit_not_PHY_acceptance"));
assert(any(T.SlotOneBased==45 & T.Stage=="hashing") && any(T.SlotOneBased==46 & T.Stage=="RF"));
parent=T(T.Operation=="test_nested_scope",:);
children=T(T.SlotOneBased==45 & ismember(T.Stage,["hashing","serialization"]),:);
assert(parent.InclusiveSeconds>=sum(children.ExclusiveSeconds));
assert(any(T.Operation=="unwound_error") && digest==sixgr.util.sha256Hex(bytes));
fprintf('EXECUTION_STAGE_PROFILE_PASS rows=%d RNG_unchanged=1\n',height(T));
ok=true;
end

function failInsideScope()
scope=sixgr.runtime.ExecutionStageProfiler.scope("receiver_pipeline","unwound_error"); %#ok<NASGU>
error('test:ExpectedDiagnosticFailure','Deliberate timing-unwind fixture.');
end
