function ok = testLLSPublicationSamplingPlan()
%TESTLLSPUBLICATIONSAMPLINGPLAN Fixed-sample publication stopping contract.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
[cfg,~] = sixgr.lls.loadConfig( ...
    "configs/lls/pdsch_awgn_qpsk_publication.yaml");
assert(string(cfg.simulation.samplingPlan) == "fixed_sample");
assert(string(cfg.simulation.confidenceIntervalMethod) == ...
    "wilson_two_sided_fixed_sample");

before = sixgr.lls.stats.evaluateSamplingPlan(cfg,0,3999);
assert(~before.Stop && ~before.StatisticallyQualified && ...
    before.StoppingReason == "prespecified_fixed_sample_budget_incomplete", ...
    "Publication evidence must not stop before the prespecified sample size.");

complete = sixgr.lls.stats.evaluateSamplingPlan(cfg,0,4000);
assert(complete.Stop && complete.StatisticallyQualified && ...
    complete.StoppingReason == "prespecified_fixed_sample_budget_completed");
assert(complete.ConfidenceUpper < min(double(cfg.comparison.targetBLER)), ...
    "The fixed sample budget must resolve the configured rarest zero-error target.");

diagnostic = cfg;
diagnostic.simulation.statisticalClass = "diagnostic_only";
diagnostic.simulation.samplingPlan = "adaptive_error_count_diagnostic";
diagnostic.simulation.minTransportBlocks = 3;
diagnostic.simulation.minBlockErrors = 2;
diagnostic.simulation.maxTransportBlocks = 6;
early = sixgr.lls.stats.evaluateSamplingPlan(diagnostic,2,3);
assert(early.Stop && ~early.StatisticallyQualified && ...
    startsWith(early.StoppingReason,"diagnostic_"), ...
    "Adaptive error-count stopping must remain diagnostic-only.");

bad = cfg;
bad.simulation.samplingPlan = "adaptive_error_count_diagnostic";
localAssertIdentifier(@() sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:PublicationSamplingPlanInvalid");

fprintf("PASS testLLSPublicationSamplingPlan: fixed-sample publication and diagnostic adaptive stopping remain separated.\n");
ok = true;
end

function localAssertIdentifier(fcn,expected)
try
    fcn();
    error("sixgr:test:ExpectedError","Expected %s.",expected);
catch ME
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, received %s.",expected,ME.identifier);
end
end
