function ok=testSharedReceiverClockScoringWindow()
% Exact clock/index contract only; physical TRS has its own regression.
setup6GRSimToolkit('Verbose',false);
origin=1000; n=128;
x=complex((1:n).',-(n:-1:1).')*[1 2 3 4];
source=struct('Source',"actual_executed_link_contribution", ...
    'ReceiverID',"ue_1",'TransmitterID',"gnb_1", ...
    'ReceiverEstimatorInput',false,'AdditionalChannelExecutions',0, ...
    'AdditionalRFExecutions',0);
for precision=["double" "single"]
    wave=cast(x,precision);
    ref=localBuffer(wave,origin);
    for delay=[0 1 7]
        replay=localReplay(origin,n,delay);
        original=replay;
        [actual,e]=sixgr.truth.sharedReceiverClockScoringWindow( ...
            ref,source,replay,origin+16,80);
        assert(isequal(actual,wave(17-delay:96-delay,:)) && ...
            isa(actual,precision) && isequaln(replay,original));
        assert(e.RecordedReceiverTimingOffset_samples==delay && ...
            ~e.ReceiverEstimatorInput && ~e.TXTimingReapplied && ...
            ~e.GainOrPhaseFitted && e.AdditionalRFExecutions==0 && ...
            e.AdditionalChannelExecutions==0);
        % Neither the flattened TX+RX delay nor another UE owns this clock.
        replay.InjectedTimingOffset_samples=12345;
        poisoned=sixgr.truth.sharedReceiverClockScoringWindow(ref,source,replay,origin+16,80);
        assert(isequal(actual,poisoned));
        doubled=sixgr.truth.sharedReceiverClockScoringWindow( ...
            localBuffer(2*wave,origin),source,replay,origin+16,80);
        assert(isequal(doubled,2*actual),'Do not fit away an erroneous reference gain.');
        localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
            ref,e,replay,origin+16,80),'InvalidReceiverClockScoringSource');
    end
end
replay=localReplay(origin,n,1);
ref=localBuffer(x,origin);
localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
    ref,source,replay,origin,16),'MissingReceiverScoringHistory');
bad=replay; bad.ReceiverID="ue_2";
localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
    ref,source,bad,origin+16,80),'ReceiverClockScoringIdentityMismatch');
bad=replay; bad.ReceiveStreamExecutionSegments{2}.StartSample=origin+65;
localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
    ref,source,bad,origin+16,80),'IncompleteReceiverClockExecution');
bad=replay; bad.ReceiveStreamExecutionSegments{2}.StartSample=origin+63;
localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
    ref,source,bad,origin+16,80),'IncompleteReceiverClockExecution');
bad=replay; bad.ReceiveStreamExecutionSegments{2}.Execution.RX(2).Replay.InjectedTimingOffset_samples=2;
localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
    ref,source,bad,origin+16,80),'TimeVaryingReceiverScoringDelay');
bad=localReplay(origin,n,0.5);
localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
    ref,source,bad,origin+16,80),'UnsupportedReceiverScoringDelay');
bad=replay; bad.ReceiveStreamExecutionSegments{2}.Execution.RX(2)=[];
localReject(@()sixgr.truth.sharedReceiverClockScoringWindow( ...
    ref,source,bad,origin+16,80),'MissingReceiverClockExecution');
fprintf('Shared receiver scoring clock: exact samples, no padding/fitting, negative guards PASS.\n');
ok=true;
end

function ref=localBuffer(wave,origin)
ref=sixgr.phy.waveform.WaveformObservationBuffer(origin,origin+size(wave,1),122.88e6,size(wave,2));
ref.append(sixgr.phy.waveform.WaveformChunk(wave,origin),122.88e6);
end

function replay=localReplay(origin,n,delay)
rx(1)=struct('ID',"other_ue",'Replay',struct('InjectedTimingOffset_samples',50));
rx(2)=struct('ID',"ue_1",'Replay',struct('InjectedTimingOffset_samples',delay));
tx=struct('ID',"gnb_1",'Replay',struct('InjectedTimingOffset_samples',3));
segments={struct('StartSample',origin,'EndSampleExclusive',origin+n/2, ...
    'Execution',struct('RX',rx,'TX',tx)); ...
    struct('StartSample',origin+n/2,'EndSampleExclusive',origin+n, ...
    'Execution',struct('RX',rx,'TX',tx))};
replay=struct('ReceiverID',"ue_1",'TransmitterID',"gnb_1", ...
    'InjectedTimingOffset_samples',3+delay,'ReceiveStreamExecutionSegments',{segments});
end

function localReject(callback,suffix)
try
    callback();
catch cause
    assert(strcmp(cause.identifier,"sixgr:truth:"+suffix), ...
        'Unexpected failure: %s (%s)',cause.identifier,cause.message);
    return;
end
error('Expected sixgr:truth:%s.',suffix);
end
