function ok=testBinomialQualificationSummary()
% Exact numerical stopping-engine outcomes, NOT simulated detector trials.
setup6GRSimToolkit('Verbose',false);
options={'ConfidenceLevel',.95,'MinimumTrials',1000,'MaximumTrials',1000, ...
    'MinimumEvents',0,'CIWidthTarget',.1,'LookIndex',1,'PlannedLooks',1};
failed=sixgr.stats.evaluateBinomialStopping(1000,1000,.001,options{:});
passed=sixgr.stats.evaluateBinomialStopping(0,1000,.01,options{:});
unknown=sixgr.stats.evaluateBinomialStopping(10,1000,.01,options{:});
assert(failed.StatisticallyQualified && failed.Qualification=="FAIL");
assert(passed.StatisticallyQualified && passed.Qualification=="PASS");
assert(~unknown.StatisticallyQualified && unknown.Qualification=="NOT_EVALUATED");
T=table([failed.StatisticallyQualified;passed.StatisticallyQualified;unknown.StatisticallyQualified], ...
    [failed.Qualification;passed.Qualification;unknown.Qualification], ...
    'VariableNames',{'StatisticallyQualified','StatisticalQualification'});
sets={1,2,3,[1 2],[1 3],[2 3],[],[2 2]};
expected=["FAIL","PASS","NOT_EVALUATED","FAIL","FAIL","NOT_EVALUATED","NOT_EVALUATED","PASS"];
decisions=[true true false true false false false true];
for n=1:numel(sets)
    [decisive,q]=sixgr.stats.summarizeBinomialQualifications(T(sets{n},:));
    assert(q==expected(n) && decisive==decisions(n));
end
bad=T(2,:); bad.StatisticallyQualified=NaN;
[decisive,q]=sixgr.stats.summarizeBinomialQualifications(bad);
assert(~decisive && q=="NOT_EVALUATED",'NaN is not evidence of statistical qualification.');
bad=T(2,:); bad.StatisticalQualification=missing;
[decisive,q]=sixgr.stats.summarizeBinomialQualifications(bad);
assert(~decisive && q=="NOT_EVALUATED");
fprintf('BINOMIAL_SUMMARY_PASS numerical_engine_cases=10 no_detector_qualification_claim=1\n');
ok=true;
end
