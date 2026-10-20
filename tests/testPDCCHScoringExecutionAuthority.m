function ok=testPDCCHScoringExecutionAuthority()
% Real mini-anchor candidates plus explicitly labelled scoring negatives.
% Mutated records below are contracts, never extra physical trials.
setup6GRSimToolkit('Verbose',false);
b=pdcchStrictAnchorResult();
trials=b.Result.ArtifactTables.pdcch_trials;
candidates=b.Result.ArtifactTables.pdcch_candidates;
row=trials(find(trials.TrialType=="no_signal_coreset",1),:);
assert(height(row)==1);
observed=candidates(candidates.TrialId==row.TrialId,:);
assert(~isempty(observed) && all(~observed.CrcPass));
det=struct('Rx',struct('Ok',false),'DecodedDCI',struct(), ...
    'Candidates',observed,'DCIFormatAttempted',"1_0", ...
    'UsedOracleFields',"",'ProxyUsed',false,'Skipped',false,'ToolboxMissing',false);
actual=score(det,b.Config);
assert(actual.NegativeExpectedOk && actual.FalseCandidateCount==0);

% Empty or unexecuted decoding cannot enter the success denominator of H0.
bad=det; bad.Candidates=observed([],:);
reject(@()score(bad,b.Config));
for flag=["Skipped","ToolboxMissing","ProxyUsed"]
    bad=det; bad.(flag)=true; reject(@()score(bad,b.Config));
    bad=rmfield(det,flag); reject(@()score(bad,b.Config));
    bad=det; bad.(flag)=NaN; reject(@()score(bad,b.Config));
end
bad=det; bad.UsedOracleFields="injected_noise_variance";
reject(@()score(bad,b.Config));
bad=rmfield(det,'UsedOracleFields'); reject(@()score(bad,b.Config));
bad=det; bad.UsedOracleFields=missing; reject(@()score(bad,b.Config));
bad=det; bad.Rx.Ok=NaN; reject(@()score(bad,b.Config));
for field=["CrcPass","SelectedCandidate","DecodeAttempted"]
    bad=det; bad.Candidates=removevars(bad.Candidates,field);
    reject(@()score(bad,b.Config));
    for invalid=[NaN 2 -1]
        bad=det; bad.Candidates.(field)=double(bad.Candidates.(field));
        bad.Candidates.(field)(1)=invalid;
        reject(@()score(bad,b.Config));
    end
end
bad=det; bad.Candidates.DecodeAttempted(1)=false;
reject(@()score(bad,b.Config));

% A physically observed CRC pass is a false acceptance under H0, even if
% the later semantic parser rejects it or no candidate is selected.
for selected=[false true]
    bad=det; bad.Candidates.CrcPass(1)=true;
    bad.Candidates.SelectedCandidate(1)=selected;
    failed=score(bad,b.Config);
    assert(~failed.NegativeExpectedOk && failed.FalseCandidateCount==1);
end
ok=true;
fprintf('PDCCH_SCORING_EXECUTION_AUTHORITY_PASS actual_anchor_plus_contract_negatives\n');
end

function out=score(det,cfg)
out=sixgr.phy.pdcch.scorePDCCHDetection(det,struct(),cfg, ...
    'TrialType','no_signal_coreset','NegativeExpected',true);
end

function reject(fn)
try
    fn();
catch failure
    assert(strcmp(failure.identifier,'sixgr:phy:pdcch:UnmeasuredScoringTrial'), ...
        'Expected evidence rejection; got %s: %s',failure.identifier,failure.message);
    return;
end
error('test:UnmeasuredPDCCHAccepted','Missing/unexecuted decoder evidence was accepted by the scorer.');
end
