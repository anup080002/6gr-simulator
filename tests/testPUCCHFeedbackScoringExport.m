function ok=testPUCCHFeedbackScoringExport()
% Declared reducer-output fixtures; no waveform or measured false-ACK claim.
setup6GRSimToolkit('Verbose',false);
t=table(true(4,1),false(4,1),logical([1;1;0;1]),[0;0;1;0], ...
    logical([1;1;1;0]),logical([1;0;0;0]),logical([0;1;1;0]), ...
    ["PASS";"FAIL";"FAIL";"FAIL"], ...
    'VariableNames',{'MultiplexedOnPUSCH','GrantExecutedFlag','RuntimeStateUpdated', ...
    'StaleFeedbackIgnored','PUSCHUCIDecodeOk','UCIContentMatch','FalseAck','Status'});
c=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedPUCCHGrantTraceTable(t);
check(c);
% Reconstructing omitted status must still respect retained content scoring.
blank=t; blank.Status(:)="";
check(sixgr.truth.CoupledTruthRuntime.canonicalizePersistedPUCCHGrantTraceTable(blank));
% No invented observation when both applied/stale dispositions are unknown.
unknown=t; unknown.RuntimeStateUpdated(:)=false; unknown.StaleFeedbackIgnored(:)=NaN;
u=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedPUCCHGrantTraceTable(unknown);
assert(~any(u.ControlObservationAvailable) && ~any(u.SuccessFlag) && ~any(u.FailureFlag));
logsRoot=fullfile(pwd,'logs');
if ~isfolder(logsRoot), mkdir(logsRoot); end
outputRoot=tempname(logsRoot); mkdir(outputRoot);
file=fullfile(outputRoot,'declared_feedback_export_fixture.csv');
writetable(c,file);
check(readtable(file,'TextType','string'));
fprintf('PUCCH_FEEDBACK_SCORING_EXPORT_PASS usable_false_ACK_stays_FAIL=1 CSV_roundtrip=1 RF_executions=0 file=%s\n',file);
ok=true;
end

function check(c)
assert(isequal(logical(c.DecodeSuccess),logical([1;1;1;0])));
assert(isequal(string(c.Status),["PASS";"FAIL";"FAIL";"FAIL"]), ...
    'Usable false ACKs, including stale observations, must retain scoring FAIL.');
assert(isequal(logical(c.SuccessFlag),logical([1;0;0;0])) && ...
    isequal(logical(c.FailureFlag),logical([0;1;1;1])));
assert(isequal(logical(c.FalseAck),logical([0;1;1;0])) && all(c.ControlObservationAvailable));
end
