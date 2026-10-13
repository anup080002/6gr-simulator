function ok=testExecutedReceiverFrequencyScoring()
% Independent analytical and actual RF-stage comparison; no PHY pass claim.
setup6GRSimToolkit('Verbose',false);
fs=1.92e6; n=(0:1023).'; x=exp(1i*.173*n)+.2*exp(-1i*.071*n);
for direction=["DL","UL"]
 for delay=[0 7]
  for hz=[-1300 0 400]
    cfg=struct('rf',struct('rx',struct('timingOffsetSamples',delay,'cfo_Hz',hz)));
    rf=sixgr.rf.applyRFImpairmentChain(x,cfg,'SampleRateHz',fs, ...
        'Endpoint','rx','Direction',direction,'UseLegacyGlobalConfig',false, ...
        'ApplyPA',false,'ApplyADC',false,'StrictMutationRequired',false);
    delayed=sixgr.util.applyFractionalSampleDelay(x,delay);
    [scored,e]=sixgr.truth.applyExecutedReceiverFrequencyForScoring(delayed,fs,0,rf.Replay);
    expected=delayed.*exp(2i*pi*hz/fs*n);
    assert(max(abs(rf.Waveform-expected))<1e-12 && ...
        isequal(scored,expected) && ~e.ReceiverEstimatorInput);
    % Also verify the absolute retained-stream clock at a nonzero origin.
    first=8137; stream=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx',direction,fs,1,first,0,false);
    actual=stream.apply(sixgr.phy.waveform.WaveformChunk(x,first),0);
    endpoint=struct('ID',"receiver",'Replay',actual.Replay);
    segment=struct('StartSample',first,'EndSampleExclusive',first+numel(x), ...
        'Execution',struct('RX',endpoint));
    replay=struct('ReceiverID',"receiver",'InjectedCFO_Hz',99999, ...
        'ReceiveStreamExecutionSegments',{{segment}});
    [scored,e]=sixgr.truth.applyExecutedReceiverFrequencyForScoring(delayed,fs,first,replay);
    assert(max(abs(scored-actual.Waveform))<1e-12 && ...
        e.ExecutedReceiverCFO_Hz==hz && ~e.GainOrPhaseFitted);
  end
 end
end
bad=replay; bad.ReceiverID="transmitter";
localError(@()sixgr.truth.applyExecutedReceiverFrequencyForScoring(delayed,fs,first,bad), ...
    'sixgr:truth:ScoringRXFrequencyIdentity');
bad=replay; bad.ReceiveStreamExecutionSegments{1}.EndSampleExclusive=first+numel(x)-1;
localError(@()sixgr.truth.applyExecutedReceiverFrequencyForScoring(delayed,fs,first,bad), ...
    'sixgr:truth:IncompleteScoringRXFrequencyExecution');
bad=rf.Replay; bad.RFEndpoint="txrx";
localError(@()sixgr.truth.applyExecutedReceiverFrequencyForScoring(delayed,fs,0,bad), ...
    'sixgr:truth:MissingScoringRXFrequencyExecution');
bad=rmfield(rf.Replay,'CFOApplied');
localError(@()sixgr.truth.applyExecutedReceiverFrequencyForScoring(delayed,fs,0,bad), ...
    'sixgr:truth:MissingScoringRXFrequencyExecution');
fprintf('EXECUTED_RX_FREQUENCY_SCORING_PASS actual_RF_and_absolute_clock_cases=24\n');
ok=true;
end

function localError(fn,id)
caught=false;
try
    fn();
catch ME
    caught=strcmp(ME.identifier,id);
end
assert(caught,'Expected exact guard %s.',id);
end
