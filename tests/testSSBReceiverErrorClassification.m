function ok=testSSBReceiverErrorClassification()
% Configuration/capture failures must not be scored as physical non-detection.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg);
sampling=nrOFDMInfo(carrier);
fs=double(sampling.SampleRate);
capture=complex(zeros(round(.005*fs),double(cfg.phy.nRxAnt)));
bad=cfg; bad.phy.sync.freqSearchBW_Hz=0; bad.phy.sync.cfoHypothesesHz=100;
expected='sixgr:phy:sync:CFOHypothesisOutsideSearchRange';
reject(@()sixgr.phy.dl.SSB_Rx(capture,bad,'SampleRate_Hz',fs),expected);
result=sixgr.phy.broadcast.recoverSIB1FromWaveform(capture,bad,'RecoveryScope','SSB_MIB');
assert(result.Crash && result.Status=="ERROR" && ~result.StrictOk && ...
    result.FailureIdentifier==expected && ~result.DecodeAttempted);

for hypotheses={99,[-1 2],[0 NaN],[],.5,1+1i}
    bad=cfg; bad.phy.sync.nid2Hypotheses=hypotheses{1};
    reject(@()sixgr.phy.dl.SSB_Rx(capture,bad,'SampleRate_Hz',fs), ...
        'sixgr:phy:sync:InvalidNID2Hypotheses');
end
reject(@()sixgr.phy.dl.SSB_Rx(capture,cfg,'SampleRate_Hz',fs,'CandidateSSBIndex',99), ...
    'sixgr:phy:sync:UnknownSSBCandidateIndex');
reject(@()sixgr.phy.dl.SSB_Rx(capture(1,:),cfg,'SampleRate_Hz',fs), ...
    'sixgr:phy:sync:SSBCandidateWindowsOutsideCapture');
for invalid={NaN,Inf,complex(0,NaN)}
    malformed=capture; malformed(1)=invalid{1};
    reject(@()sixgr.phy.dl.SSB_Rx(malformed,cfg,'SampleRate_Hz',fs), ...
        'sixgr:phy:sync:InvalidSSBObservation');
end

% Physical no-signal observations remain legitimate missed detections.
reject(@()sixgr.phy.dl.SSB_Rx(capture,cfg,'SampleRate_Hz',fs), ...
    'sixgr:phy:ia:SSBNotDetected');
result=sixgr.phy.broadcast.recoverSIB1FromWaveform(capture,cfg,'RecoveryScope','SSB_MIB');
assert(~result.Crash && result.Status=="FAIL" && ~result.StrictOk && ...
    result.FailureIdentifier=="sixgr:phy:ia:SSBNotDetected" && ~result.DecodeAttempted);
stream=RandStream('mt19937ar','Seed',382151);
noise=complex(randn(stream,size(capture)),randn(stream,size(capture)))/sqrt(2);
result=sixgr.phy.broadcast.recoverSIB1FromWaveform(noise,cfg,'RecoveryScope','SSB_MIB');
assert(~result.Crash && ~result.StrictOk && ~result.DecodeAttempted && ...
    result.FailureIdentifier=="sixgr:phy:ia:SSBNotDetected");
assert(result.PSSDetectionDecisionAvailable && result.PSSDetectionMetricValid);
assert(isfinite(result.PSSNormalizedMetric) && ...
    result.PSSNormalizedMetric<=result.PSSDetectionThreshold);
assert(result.PSSDetectionHypothesisCount>0 && result.DetectionStage=="PSS");
assert(result.DetectionMetric==result.PSSNormalizedMetric && ...
    result.DetectionThreshold==result.PSSDetectionThreshold);
assert(~result.SSSDetectionDecisionAvailable && isnan(result.SSSNormalizedMetric), ...
    'A PSS miss must not invent an SSS measurement or run the decoder.');
evidence=sixgr.phy.sync.ssbDetectionEvidence(result);
assert(evidence.DetectionMetric==result.DetectionMetric);
fprintf('SSB_RECEIVER_ERROR_CLASSIFICATION_PASS config_capture_rejections=12 outage_cases=2\n');
ok=true;
end

function reject(action,expected)
try
    action();
catch cause
    assert(strcmp(cause.identifier,expected),'Expected %s, got %s: %s', ...
        expected,cause.identifier,cause.message);
    return;
end
error('test:ExpectedRejection','Expected %s was not raised.',expected);
end
