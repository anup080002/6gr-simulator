function [wave,evidence]=applyExecutedReceiverFrequencyForScoring(wave,fs,first,execution)
% Post-decode reference coordinates only; NEVER practical receiver input.
% RX RF executes timing BEFORE CFO. Thus delayed sample n is rotated at n,
% not n-delay. TX CFO is already present in the retained desired-link IQ.
arguments
    wave {mustBeFloat,mustBeNonempty,mustBeFinite}
    fs (1,1) double {mustBeFinite,mustBePositive}
    first (1,1) double {mustBeFinite,mustBeInteger,mustBeNonnegative}
    execution (1,1) struct
end
count=size(wave,1); last=first+count;
if isfield(execution,'ReceiveStreamExecutionSegments')
    segments=execution.ReceiveStreamExecutionSegments;
    assert(iscell(segments) && ~isempty(segments) && isfield(execution,'ReceiverID'), ...
        'sixgr:truth:MissingScoringRXFrequencyExecution','Retain the actual RX endpoint execution.');
    next=first; values=[];
    for k=1:numel(segments)
        s=segments{k};
        a=double(s.StartSample); b=double(s.EndSampleExclusive);
        validateattributes([a b],{'double'},{'real','finite','integer','nonnegative'});
        assert(b>a,'sixgr:truth:InvalidScoringRXFrequencyInterval','Execution intervals must be nonempty.');
        if b<=first || a>=last, continue; end
        a=max(a,first); b=min(b,last);
        assert(a==next && isfield(s.Execution,'RX'), ...
            'sixgr:truth:IncompleteScoringRXFrequencyExecution','Every scored RX sample needs exactly one execution interval.');
        endpoints=s.Execution.RX;
        endpoint=endpoints(string({endpoints.ID})==string(execution.ReceiverID));
        assert(isscalar(endpoint),'sixgr:truth:ScoringRXFrequencyIdentity','Select one actual RX endpoint, never merged TX+RX metadata.');
        values(end+1)=localFrequency(endpoint.Replay); %#ok<AGROW>
        next=b;
    end
    assert(next==last && ~isempty(values), ...
        'sixgr:truth:IncompleteScoringRXFrequencyExecution','Executed RX frequency must cover the complete scoring window.');
    assert(all(values==values(1)), ...
        'sixgr:truth:ScoringRXFrequencyTransition','Changing oscillator frequency requires explicit phase-history scoring.');
    hz=values(1);
else
    assert(first==0,'sixgr:truth:ScoringRXFrequencyOrigin', ...
        'Isolated RF uses capture-local sample zero; nonzero origins require retained stream execution.');
    hz=localFrequency(execution);
end
n=first+(0:count-1).';
wave=wave.*cast(exp(2i*pi*hz/fs*n),'like',wave);
evidence=struct('ReceiverCFOIncluded',true,'ExecutedReceiverCFO_Hz',hz, ...
    'FrequencySource',"executed_RX_endpoint_not_configured_or_merged_TX_RX", ...
    'FrequencySampleClock',"RX_absolute_sample_after_executed_timing_delay", ...
    'ReceiveStartSample',first,'ReceiveEndSampleExclusive',last, ...
    'ReceiverEstimatorInput',false,'GainOrPhaseFitted',false, ...
    'AdditionalRFExecutions',0,'AdditionalChannelExecutions',0, ...
    'ResidualOscillatorQualification',false);
end

function hz=localFrequency(replay)
assert(all(isfield(replay,{'CFOApplied','InjectedCFO_Hz','RFEndpoint','RFStageOrder'})) && ...
    isscalar(replay.CFOApplied) && any(double(replay.CFOApplied)==[0 1]) && ...
    string(replay.RFEndpoint)=="rx" && ...
    contains(string(replay.RFStageOrder),"rx_timing>rx_lo_cfo"), ...
    'sixgr:truth:MissingScoringRXFrequencyExecution', ...
    'Require executed RX-only timing-then-CFO metadata; do not infer it from YAML.');
hz=double(replay.InjectedCFO_Hz);
validateattributes(hz,{'numeric'},{'scalar','real','finite'});
assert(logical(replay.CFOApplied) || hz==0, ...
    'sixgr:truth:ContradictoryScoringRXFrequency','Disabled RX CFO cannot carry a nonzero applied frequency.');
end
