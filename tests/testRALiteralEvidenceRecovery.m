function ok=testRALiteralEvidenceRecovery()
root=string(tempname); mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
assert(isempty(sixgr.truth.restoreRALiteralEvidence(root)));
legacy=fullfile(root,'legacy'); mkdir(fullfile(legacy,'raw'));
sixgr.util.jsonWrite(fullfile(legacy,'raw','execution_manifest.json'), ...
    struct('RawEvidenceIndexRelativePath',""));
assert(isempty(sixgr.truth.restoreRALiteralEvidence(legacy)));
id=struct('RunID',"run",'ExecutionID',"exec",'ScenarioID',"scenario", ...
    'ConfigHash',string(repmat('a',1,64)));
S=table(["ra1";"ra2"],[1;2],[1;1],[19;19],[37;57], ...
    ["0106000000000001310455452D31";"0106000000000002310455452D32"], ...
    ["000000000001";"000000000002"], ...
    ["020000000000011234320001";"020000000000021235320001"], ...
    'VariableNames',{'RARunId','RAUEId','RAAttemptId','Msg3ScheduledSlot', ...
    'Msg4ScheduledSlot','Msg3PayloadHex','Msg3ContentionIdentity','Msg4PayloadHex'});
S.Msg3TransmittedPayloadHex=S.Msg3PayloadHex;
S.Msg3TransmittedPayloadHex(2)=""; % Legitimately missing retained TX bytes.
S.Msg4TransmittedPayloadHex=S.Msg4PayloadHex;
S.Msg4ContentionIdentity=S.Msg3ContentionIdentity;
snapshot=sixgr.runtime.snapshotRawExecutionEvidence(root,struct('RawTrials', ...
    struct('PRACH',S)),id);
metadata=id; metadata.ExecutionStartUTC="2026-10-13T00:00:00Z";
metadata.ExecutionEndUTC="2026-10-13T00:00:01Z";
metadata.GitCommit="fixture"; metadata.GitDirty=false;
metadata.RawEvidenceIndexRelativePath="evidence/raw_evidence_index.csv";
metadata.RawEvidenceIndexSHA256=snapshot.IndexSHA256;
metadata.RawEvidenceTableCount=snapshot.TableCount;
metadata.RawEvidenceRowCount=snapshot.RowCount;
sixgr.runtime.RunEvidenceLifecycle.sealExecution(root,metadata);
target=fullfile(root,'control','csv','msg3_pusch_trials.csv');
T=table(["ra1";"ra2"],[1;2],[1;1],[19;19],[1.06e54;1.06e55],[1;2], ...
    ["0.123456789012345678901";"0000"], ...
    'VariableNames',{'RunId','UEId','AttemptId','ScheduledSlot','PayloadHex', ...
    'ContentionIdentity','OtherEvidence'});
T.TransmittedPayloadHex=[S.Msg3PayloadHex(1);""];
sixgr.util.csvWriteTable(target,T,'PreserveSchema',true);
original=fileread(target);
events=table(["ra1";"ra1"],[1;1],[1;1],[1;NaN],[1;0],[1;0],[1;0], ...
    'VariableNames',{'RunId','UEId','AttemptId','ReceivedIdentity', ...
    'IdentityMatches','DCICrcPass','TBCrcPass'});
eventPath=fullfile(root,'control','csv','ue_contention_events.csv');
sixgr.util.csvWriteTable(eventPath,events,'PreserveSchema',true);
audit=sixgr.truth.restoreRALiteralEvidence(root);
assert(height(audit)==2 && strcmp(fileread(audit.BackupPath(1)),original));
R=sixgr.util.csvReadTable(target,'ColumnTypes',struct('OtherEvidence','string'));
assert(isequal(R.PayloadHex,S.Msg3PayloadHex) && ...
    isequal(R.ContentionIdentity,S.Msg3ContentionIdentity));
assert(isequal(R.OtherEvidence,T.OtherEvidence));
assert(ismissing(R.TransmittedPayloadHex(2)) || strlength(R.TransmittedPayloadHex(2))==0);
E=sixgr.util.csvReadTable(eventPath);
assert(E.ReceivedIdentity(1)==S.Msg4ContentionIdentity(1) && ...
    (ismissing(E.ReceivedIdentity(2)) || E.ReceivedIdentity(2)=="NaN"));
bytes=fileread(target);
assert(isempty(sixgr.truth.restoreRALiteralEvidence(root)));
assert(strcmp(bytes,fileread(target)),'Idempotent recovery must not rewrite bytes.');
events.TBCrcPass(1)=0;
sixgr.util.csvWriteTable(eventPath,events,'PreserveSchema',true);
localReject(@()sixgr.truth.restoreRALiteralEvidence(root), ...
    'sixgr:truth:RALiteralObservationUnproven');
events.TBCrcPass(1)=1;
sixgr.util.csvWriteTable(eventPath,events,'PreserveSchema',true);
% A target from another attempt must not borrow an identity by UE position.
T.RunId(2)="wrong-attempt";
sixgr.util.csvWriteTable(target,T,'PreserveSchema',true);
bad=fileread(target);
localReject(@()sixgr.truth.restoreRALiteralEvidence(root), ...
    'sixgr:truth:RALiteralSourceAmbiguous');
assert(strcmp(bad,fileread(target)));
% A mutated raw source is never used even if the desired strings look valid.
rawPath=fullfile(root,'raw','evidence','tables','rawtrials_prach.csv');
fid=fopen(rawPath,'a'); fprintf(fid,'\n'); fclose(fid);
localReject(@()sixgr.truth.restoreRALiteralEvidence(root), ...
    'sixgr:truth:RALiteralHashMismatch');
assert(strcmp(bad,fileread(target)));
ok=true;
fprintf('RA_LITERAL_EVIDENCE_RECOVERY_PASS\n');
end
function localReject(call,identifier)
try
    call(); error('test:ExpectedRejection','Expected fail-closed recovery.');
catch ME
    assert(strcmp(ME.identifier,identifier),'Wrong failure: %s %s',ME.identifier,ME.message);
end
end
