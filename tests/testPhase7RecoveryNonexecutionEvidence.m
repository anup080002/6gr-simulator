function ok=testPhase7RecoveryNonexecutionEvidence()
% Recovery publishes absence honestly without launching comparison jobs.
root=tempname(fullfile(pwd,'logs')); mkdir(root);
% Deliberately unusable enabled execution configuration: RecoveryOnly must
% not look up this FRC entry, request a pool or execute a fixed-link point.
cfg=struct('validation',struct('phase7_execution_validation', ...
    struct('enabled',true,'serial_parallel',struct('frc_entry_id','invalid_no_execution'))));
out=sixgr.validation.runPhase7ExecutionEvidence(cfg,root,'RecoveryOnly',true);
assert(~out.AllPassed && ~out.CheckpointResumeEquivalenceOk && ...
    ~out.SerialParallelDeterminismOk);
for T={out.CheckpointResume,out.SerialParallel}
    row=T{1};
    assert(row.EvidenceStatus=="NOT_EVALUATED" && ...
        row.FailureReason=="recovery_no_executed_comparison_receipt" && ...
        row.EvidenceSource=="recovery_nonexecution_receipt_not_waveform_evidence");
end
layout=sixgr.report.resultLayout(root);
paths=[fullfile(layout.ReportCSVDir,'checkpoint_resume_equivalence.csv'); ...
    fullfile(layout.ReportCSVDir,'serial_parallel_determinism.csv')];
before=arrayfun(@(p)string(fileread(p)),paths);
again=sixgr.validation.runPhase7ExecutionEvidence(cfg,root,'RecoveryOnly',true);
assert(~again.AllPassed && isequal(before,arrayfun(@(p)string(fileread(p)),paths)));

% A previously executed failure must survive recovery, not be downgraded
% to disabled/non-executed or overwritten by a new invocation.
failed=out.CheckpointResume;
failed.EvidenceStatus(:)="FAIL";
failed.FailureReason(:)="retained_comparison_mismatch";
failed.EvidenceSource(:)="unit_fixture_retained_failure";
sixgr.util.csvWriteTable(paths(1),failed,'PreserveSchema',true);
bytes=fileread(paths(1));
cfg.validation.phase7_execution_validation.enabled=false;
preserved=sixgr.validation.runPhase7ExecutionEvidence(cfg,root,'RecoveryOnly',true);
assert(~preserved.AllPassed && strcmp(bytes,fileread(paths(1))) && ...
    string(preserved.CheckpointResume.EvidenceStatus)=="FAIL");

disabledRoot=tempname(fullfile(pwd,'logs')); mkdir(disabledRoot);
disabled=sixgr.validation.runPhase7ExecutionEvidence(cfg,disabledRoot,'RecoveryOnly',true);
assert(~disabled.AllPassed && disabled.CheckpointResume.FailureReason=="validation_disabled");
dryRoot=tempname(fullfile(pwd,'logs'));
sixgr.validation.runPhase7ExecutionEvidence(cfg,dryRoot,'RecoveryOnly',true,'WriteArtifacts',false);
assert(~isfolder(dryRoot),'Read-only recovery must not create artifacts.');
source=fileread(which('sixgr.truth.recoverLLSRunArtifacts'));
assert(contains(source,'cfg,runFolder,"RecoveryOnly",true,"WriteArtifacts",true'), ...
    'Production failed-run recovery must use the no-execution publication path.');
fprintf('PHASE7_RECOVERY_PASS nonexecution=1 retained_failure_unchanged=1 folder=%s\n',root);
ok=true;
end
