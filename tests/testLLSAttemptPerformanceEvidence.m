function ok = testLLSAttemptPerformanceEvidence()
% Labelled unit fixtures: not simulated or accepted performance populations.
T = table([0;1;NaN],[0;1;NaN],[10;0;NaN],[100;100;NaN], ...
    [2;4;NaN],[0;4;NaN],[1;2;NaN], ...
    'VariableNames',{'CRCPass','IsRetransmission','BitErrors','BitsCompared', ...
    'Throughput_Mbps','Goodput_Mbps','Latency_ms'});
T.TBId = ["same_tb";"same_tb";"not_decoded"];
r = sixgr.validation.summarizeLLSAttemptPerformance(T);
assert(r.CRCTrialCount==2 && r.RawBLER==.5 && r.InitialBLER==1);
assert(r.InitialCRCTrialCount==1 && r.InitialFailedCRCTrialCount==1);
assert(r.HARQRetxRate==.5 && r.HARQRetxObservedTrialCount==2);
assert(r.RawBER==.05 && r.ComparedBits==200 && r.ComparedBitErrors==10);
assert(r.ThroughputMbps==3 && r.ThroughputTrialCount==2);
assert(r.GoodputMbps==2 && r.GoodputTrialCount==2 && startsWith(r.GoodputStatus,"partial_"));
assert(isnan(r.PacketLossRate) && contains(r.PacketLossRateStatus,"not_established"));
assert(contains(r.ThroughputAggregation,"not_run_time_rate") && ...
    contains(r.GoodputAggregation,"not_application_goodput"));

missing = removevars(T,{'Goodput_Mbps','Latency_ms','CRCPass','IsRetransmission'});
missing.OfferedThroughput_Mbps = [100;200;300];
missing.DecodeLatency_ms = [90;80;70];
r = sixgr.validation.summarizeLLSAttemptPerformance(missing);
assert(isnan(r.GoodputMbps) && r.GoodputTrialCount==0);
assert(isnan(r.LatencyMeanMs) && r.LatencyTrialCount==0);
assert(isnan(r.RawBLER) && r.CRCTrialCount==0 && isnan(r.HARQRetxRate));
assert(isnan(r.InitialBLER) && r.InitialCRCTrialCount==0);

alias = removevars(T,'IsRetransmission'); alias.HARQIsRetransmission = [0;1;NaN];
r = sixgr.validation.summarizeLLSAttemptPerformance(alias);
assert(r.HARQRetxRate==.5 && r.InitialBLER==1);
bad=alias; bad.IsRetransmission=[1;1;NaN];
localError(@()sixgr.validation.summarizeLLSAttemptPerformance(bad), ...
    'sixgr:validation:ConflictingRetransmissionEvidence');
bad=T; bad.CRCPass(1)=2;
localError(@()sixgr.validation.summarizeLLSAttemptPerformance(bad), ...
    'sixgr:validation:InvalidBooleanTrialEvidence');
bad=T; bad.BitErrors(1)=101;
localError(@()sixgr.validation.summarizeLLSAttemptPerformance(bad), ...
    'sixgr:validation:InvalidBitComparison');
bad=T; bad.Goodput_Mbps(1)=Inf;
localError(@()sixgr.validation.summarizeLLSAttemptPerformance(bad), ...
    'sixgr:validation:InvalidTrialRateOrLatency');
r=sixgr.validation.summarizeLLSAttemptPerformance(table());
assert(r.ExecutedTrialCount==0 && isnan(r.RawBLER) && isnan(r.GoodputMbps));

% Exercise the public writer, not just its arithmetic helper. Only the
% temporary fixture files are changed; no retained run is rewritten.
ctx=llsImplementationHarnessFixture("partial_actual");
path=fullfile(ctx.Layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv');
trial=sixgr.util.csvReadTable(path);
trial.Goodput_Mbps=[];
trial.OfferedThroughput_Mbps=100*ones(height(trial),1);
trial.Latency_ms=[];
trial.DecodeLatency_ms=900*ones(height(trial),1);
trial.CRCPass=[0;1;1]; trial.IsRetransmission=[0;1;0];
sixgr.util.csvWriteTable(path,trial);
out=sixgr.validation.LLSValidationHarness(ctx.RunFolder,ctx.ScenarioConfig,ctx.InternalConfig, ...
    'WriteArtifacts',true);
summary=out.LinkPerformanceSummary;
dl=summary(summary.Direction=="DL",:);
assert(height(dl)==1 && isnan(dl.GoodputMbps) && isnan(dl.LatencyMeanMs));
assert(abs(dl.RawBLER-1/3)<1e-12 && dl.InitialBLER==.5);
assert(abs(dl.HARQRetxRate-1/3)<1e-12 && isnan(dl.PacketLossRate));
csv=sixgr.util.csvReadTable(fullfile(ctx.Layout.ReportCSVDir,'lls_link_performance_summary.csv'));
assert(all(ismember({'CRCTrialCount','GoodputTrialCount','PacketLossRateStatus', ...
    'ThroughputAggregation'},csv.Properties.VariableNames)));
ok=true; fprintf('LLS_ATTEMPT_PERFORMANCE_EVIDENCE_PASS\n');
end

function localError(action,identifier)
try
    action();
catch err
    assert(strcmp(err.identifier,identifier),err.message);
    return;
end
error('test:MissingExpectedFailure','Expected %s.',identifier);
end
