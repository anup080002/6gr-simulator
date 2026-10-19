function path = persistRuntimeFailureNotice(cause,state,runFolder,dlRows,ulRows)
% Persist the original failure BEFORE expensive recovery/export operations.
% This compact diagnostic is not a successful restart checkpoint, completed
% slot, receiver result or terminal artifact-acceptance receipt.
arguments
    cause (1,1) MException
    state (1,1) struct
    runFolder {mustBeTextScalar}
    dlRows (1,1) double {mustBeInteger,mustBeNonnegative}
    ulRows (1,1) double {mustBeInteger,mustBeNonnegative}
end
layout=sixgr.report.resultLayout(runFolder);
slot=double(sixgr.util.structGet(state,'CurrentSlot',NaN));
frame=double(sixgr.util.structGet(state,'CurrentFrame',NaN));
assert(isscalar(slot) && isscalar(frame), ...
    'sixgr:truth:FailureNoticeClock','Failure clock must be scalar.');
T=table(string(cause.identifier),string(cause.message),frame,slot,dlRows,ulRows, ...
    "failed_runtime_checkpoint_not_finalized", ...
    "completed_runtime_observations_before_failure", ...
    'VariableNames',{'ErrorIdentifier','ErrorMessage','Frame','Slot', ...
    'DLTrialRows','ULTrialRows','RunState','EvidenceScope'});
T.ErrorStackJSON=string(jsonencode(cause.stack));
T.ErrorReport=string(getReport(cause,'extended','hyperlinks','off'));
T.RecordedAtUTC=string(sixgr.util.utcNowISO8601());
T.RecoveryStage="before_heavy_artifact_recovery";
T.RecoveryCompleted=false;
path=fullfile(layout.ReportCSVDir,'runtime_failure_checkpoint.csv');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
end
