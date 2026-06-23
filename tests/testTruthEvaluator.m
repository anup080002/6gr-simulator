function ok = testTruthEvaluator()
%TESTTRUTHEVALUATOR Verify root ResultOk cannot override a failed gate.

setup6GRSimToolkit("Verbose", false);

gateNames = sixgr.runtime.RuntimeTruthEvaluator.rootGateNames();
flags = struct();
for i = 1:numel(gateNames)
    flags.(char(gateNames(i))) = true;
end
status = sixgr.runtime.RuntimeTruthEvaluator.evaluate(flags);
assert(logical(status.ResultOk), "All root gates true must produce ResultOk=true.");
assert(status.RunCompletion == "completed_success", "All root gates true must complete successfully.");

flags.MandatoryPhyEvidenceOk = false;
status = sixgr.runtime.RuntimeTruthEvaluator.evaluate(flags);
assert(~logical(status.ResultOk), "Mandatory PHY evidence failure must force ResultOk=false.");
assert(status.RunCompletion == "completed_with_validation_failures", ...
    "Missing mandatory PHY evidence must be a validation failure, not runtime success.");
assert(any(status.FailureCodes == "MandatoryPhyEvidenceOk_false"), ...
    "Failure codes must include the failed root gate.");

flags.MandatoryPhyEvidenceOk = true;
flags.ReportingPipelineOk = false;
status = sixgr.runtime.RuntimeTruthEvaluator.evaluate(flags);
assert(~logical(status.ResultOk), "Reporting failure must force ResultOk=false.");
assert(status.RunCompletion == "completed_with_reporting_failure", ...
    "Reporting failure must produce reporting-failure completion.");

ok = true;
end
