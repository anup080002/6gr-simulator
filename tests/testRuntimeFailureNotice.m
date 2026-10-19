function ok = testRuntimeFailureNotice()
% Diagnostic component test: no radio scenario or successful PHY claim.
setup6GRSimToolkit('Verbose',false);
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU> owned temporary test folder
state=struct('CurrentSlot',46,'CurrentFrame',3);
try
    localRaise();
catch cause
    original=cause;
end
path=sixgr.truth.persistRuntimeFailureNotice(original,state,folder,4,0);
T=sixgr.util.csvReadTable(path);
assert(height(T)==1 && T.Slot==46 && T.Frame==3);
assert(T.DLTrialRows==4 && T.ULTrialRows==0);
assert(string(T.ErrorIdentifier)==string(original.identifier));
assert(string(T.ErrorMessage)==string(original.message));
assert(isequaln(jsondecode(char(T.ErrorStackJSON)),original.stack));
assert(contains(string(T.ErrorReport),'testRuntimeFailureNotice'));
assert(string(T.RecoveryStage)=="before_heavy_artifact_recovery");
assert(~logical(T.RecoveryCompleted));
assert(string(T.RunState)=="failed_runtime_checkpoint_not_finalized");
assert(strlength(string(T.RecordedAtUTC))>0);
before=sixgr.util.sha256File(path);
% A subsequent recovery failure cannot erase or rewrite the first record.
try
    error('sixgr:test:RecoveryFailure','Report rebuilding failed after the notice.');
catch recovery
    combined=addCause(original,recovery);
end
assert(strcmp(combined.identifier,original.identifier));
assert(sixgr.util.sha256File(path)==before);
assert(~isfile(fullfile(folder,'meta','latest_slot_checkpoint.json')));

% Protect the actual production ordering, not just this helper's output.
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
start=strfind(source,'function ME = localPersistCoupledRuntimeFailureCheckpoint(');
finish=strfind(source,'function localWriteNonemptyFailureTrialTable(');
section=source(start:finish-1);
notice=strfind(section,'sixgr.truth.persistRuntimeFailureNotice(');
rebuild=strfind(section,'state = localWriteCoupledRuntimeTables(');
capture=strfind(section,'for capture=');
assert(isscalar(notice) && notice<capture && notice<rebuild);
assert(contains(section,'ME = addCause(ME, checkpointME);'));
ok=true;
fprintf('[PASS] testRuntimeFailureNotice\n');
end
function localRaise()
error('sixgr:test:OriginalRuntimeFailure','Original error, with "quoted" detail.');
end
