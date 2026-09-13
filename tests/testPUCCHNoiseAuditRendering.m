function ok=testPUCCHNoiseAuditRendering(root)
% Existing CSV only: this test never executes PHY or resamples noise.
trials=readtable(fullfile(root,'noise_trials.csv'),'TextType','string');
summary=readtable(fullfile(root,'noise_summary.csv'),'TextType','string');
path=fullfile(root,'noise_detector_audit_verified.png');
assert(~isfile(path),'test:EvidenceExists','Do not replace an earlier render.');
sixgr.report.plotPUCCHNoiseObservationAudit(trials,summary,path);
bad=summary; bad.FalseACKBits(1)=bad.FalseACKBits(1)+1;
rejected=false;
try
    sixgr.report.plotPUCCHNoiseObservationAudit(trials,bad,tempname);
catch cause
    assert(strcmp(cause.identifier,'sixgr:report:PUCCHNoiseCountMismatch'));
    rejected=true;
end
assert(rejected,'test:ExpectedCountGuard','Inconsistent summary counts must fail.');
fprintf('PUCCH_NOISE_RENDER_AND_NEGATIVE_GUARD_PASS\n');
ok=true;
end
