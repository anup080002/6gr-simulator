function [waveform,pathGains,sampleTimes,evidence] = applyWaveformChannelOnce(object,input,captureResponse)
%APPLYWAVEFORMCHANNELONCE Execute the inspected backend exactly once.
% Never adapt output arity by catching a step failure and stepping again:
% the first call may already have advanced a handle's fading/filter state.
% An exact static FIR response is NOT an NR path-gain tensor.
if nargin<3, captureResponse=false; end
validateattributes(captureResponse,{'logical','numeric'},{'scalar','binary'});
contract=sixgr.channel.waveformChannelOutputContract(object);
pathGains=[]; sampleTimes=[];
evidence=struct('Kind',contract.Kind,'ModelApplied',contract.ModelApplied, ...
    'ImpulseResponse',[],'ExecutionCompleted',false);
if ~captureResponse
    waveform=object(input);
elseif contract.Kind=="static_reciprocal_fir"
    [waveform,evidence.ImpulseResponse]=object(input);
elseif contract.OutputCount==3
    [waveform,pathGains,sampleTimes]=object(input);
elseif contract.OutputCount==2
    [waveform,pathGains]=object(input);
else
    error('sixgr:channel:WaveformResponseUnavailable', ...
        'Response capture was requested but the configured backend has no response output.');
end
assert(isfloat(waveform) && ismatrix(waveform) && size(waveform,1)==size(input,1), ...
    'sixgr:channel:WaveformOutputShape', ...
    'A filtered waveform must preserve the number of actual input samples.');
evidence.ExecutionCompleted=true;
end
