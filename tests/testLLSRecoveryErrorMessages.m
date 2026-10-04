function ok=testLLSRecoveryErrorMessages()
% Exact production error branches, not full artifact-recovery qualification.
sources=[string(which('sixgr.truth.recoverLLSRunArtifacts')), ...
    string(which('sixgr.truth.recoverLLSRunArtifacts')), ...
    string(which('sixgr.lls6g.runners.runSingle'))];
ids=["sixgr:truth:recover:MissingPersistedTrialEvidence", ...
    "sixgr:truth:recover:TerminalArtifactFixedPointFailed", ...
    "sixgr:lls6g:TerminalArtifactFixedPointFailed"];
messages=["Persisted-trial re-finalization requires at least one primary DL or UL runtime trial row.", ...
    "Terminal status and exact plot-source hashes did not converge within three publication passes.", ...
    "Terminal status and exact plot-source hashes did not converge within three publication passes."];
for k=1:numel(ids)
    source=fileread(sources(k));
    expression='error\("'+ids(k)+'",[\s\S]*?\);';
    statements=regexp(source,char(expression),'match');
    assert(numel(statements)==1, ...
        'Expected one production error statement for %s.',ids(k));
    caught=false;
    try
        % Execute the exact literal diagnostic statement, not a duplicated
        % proposed message. Recovery conditions/gates are tested separately.
        eval(statements{1});
    catch failure
        caught=true;
        assert(string(failure.identifier)==ids(k), ...
            'Recovery diagnostic %s was hidden by %s.',ids(k),failure.identifier);
        assert(ischar(failure.message) && string(failure.message)==messages(k), ...
            'Recovery diagnostic text must survive unchanged as scalar text.');
    end
    assert(caught,'A recovery error statement must throw.');
end
ok=true;
end
