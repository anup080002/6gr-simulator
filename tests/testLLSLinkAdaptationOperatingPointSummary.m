function ok = testLLSLinkAdaptationOperatingPointSummary()
%TESTLLSLINKADAPTATIONOPERATINGPOINTSUMMARY Validate runtime-only reductions.

setup6GRSimToolkit("Verbose", false);
[cfg,~] = sixgr.lls.loadConfig( ...
    "configs/lls/pusch_awgn_link_adaptation_regression.yaml");
cfg.simulation.snrDb = [-5 15];
cfg.simulation.statisticalClass = "diagnostic_only";
cfg.linkAdaptation.minimumMCSIndex = 0;
cfg.linkAdaptation.maximumMCSIndex = 20;

T = localTrials();
S = table([1;2],[-5;15],[0.2;0], [0.05;0], [0.55;0.3], ...
    [1e6;8e6],[false;false], ...
    'VariableNames', {'SNRIndex','SNRdB','BLER','BLERLowerCI', ...
    'BLERUpperCI','ThroughputBps','StatisticalPointQualified'});
out = sixgr.lls.buildLinkAdaptationOperatingPointSummary(cfg,S,T);
assert(height(out) == 2 && all(out.RuntimeTrials == 5));
assert(out.FeedbackDelaySlots(1) == 2 && ...
    out.PostDelayEvaluationTrials(1) == 3 && ...
    out.PostDelayBlockErrors(1) == 1);
assert(out.LowerMCSSaturated(1) && ...
    out.TargetTrackingClassification(1) == ...
    "coverage_limited_at_minimum_mcs");
assert(out.UpperMCSSaturated(2) && ...
    out.TargetTrackingClassification(2) == ...
    "capacity_limited_at_maximum_mcs");
assert(all(out.ExecutionBackend == "waveform_truth") && ...
    all(out.ApproximationMode == "none") && ...
    ~any(out.PublicationEligible));

bad = T;
bad.LinkAdaptationFeedbackAgeSlots(4) = 1;
localAssertError(@()sixgr.lls.buildLinkAdaptationOperatingPointSummary(cfg,S,bad), ...
    "sixgr:lls:LinkAdaptationSummaryCausalityMismatch");
ok = true;
end

function T = localTrials()
snrIndex = repelem([1;2],5);
trialIndex = repmat((1:5).',2,1);
crcError = [0;0;1;0;0; 0;0;0;0;0];
mcs = [0;0;0;0;0; 0;0;20;20;20];
postEq = [-5;-4.5;-5.2;-4.8;-4.7; 15;15.2;15.1;15.3;15.2];
delay = 2*ones(10,1);
age = [NaN;NaN;2;2;2; NaN;NaN;2;2;2];
cqi = [NaN;NaN;1;1;1; NaN;NaN;11;11;11];
eligible = true(10,1);
probe = false(10,1);
offset = [0;0;0.1;-0.8;-0.7; 0;0;0.1;0.2;0.3];
ack = [NaN;NaN;1;0;1; NaN;NaN;1;1;1];
updates = [0;0;1;2;3; 0;0;1;2;3];
T = table(snrIndex,trialIndex,logical(crcError),mcs,postEq,delay,age,cqi, ...
    eligible,probe,offset,ack,updates, ...
    'VariableNames', {'SNRIndex','TrialIndex','CRCError','MCSIndex', ...
    'PostEqSINRdB','LinkAdaptationFeedbackDelaySlots', ...
    'LinkAdaptationFeedbackAgeSlots','LinkAdaptationSelectedCQI', ...
    'LinkAdaptationSchedulingEligible','LinkAdaptationForcedWaveformProbe', ...
    'OLLAOffsetDbApplied','OLLAFeedbackACK','OLLAUpdateCount'});
end

function localAssertError(fcn, expected)
threw = false;
try
    fcn();
catch ME
    threw = true;
    assert(strcmp(ME.identifier, expected), ...
        "Expected %s, received %s.", expected, ME.identifier);
end
assert(threw, "Expected error %s was not raised.", expected);
end
