function [y,state] = addRuntimeComplexNoise(x,variance,seed,startSample,state)
%ADDRUNTIMECOMPLEXNOISE Persistent complex noise on a contiguous RX clock.
% State contains values, not a shared RandStream handle, so checkpoint/copy
% operations do not silently share stochastic state. Power is supplied by
% the receiver noise ledger, never estimated from the current signal block.
if nargin < 5, state = struct(); end
validateattributes(x, {'single','double'}, {'2d','finite','nonempty'});
validateattributes(variance, {'numeric'}, {'real','scalar','finite','nonnegative'});
validateattributes(seed, {'numeric'}, {'real','scalar','finite','integer','nonnegative','<=',2^32-1});
validateattributes(startSample, {'numeric'}, {'real','scalar','finite','integer','nonnegative','<=',flintmax});
if ~(isstruct(state) && isscalar(state))
    error('sixgr:link:InvalidNoiseStreamState', 'Receiver noise state must be a scalar value struct.');
end
n = size(x,1);
if startSample+n > flintmax
    error('sixgr:link:InvalidNoiseSampleClock', 'Receiver noise sample clock exceeds exact integer coordinates.');
end
stream = RandStream('Threefry', 'Seed', double(seed));
if isempty(fieldnames(state))
    state = struct('ContractVersion', "receiver_complex_noise/v1", ...
        'Seed', double(seed), 'Variance', double(variance), ...
        'NumReceiveAntennas', size(x,2), 'SampleClass', string(class(x)), ...
        'OriginSample', double(startSample), 'NextSample', double(startSample), ...
        'RandomState', stream.State);
else
    required = ["ContractVersion","Seed","Variance","NumReceiveAntennas", ...
        "SampleClass","OriginSample","NextSample","RandomState"];
    if ~all(isfield(state,required)) || state.ContractVersion ~= "receiver_complex_noise/v1"
        error('sixgr:link:InvalidNoiseStreamState', 'Receiver noise checkpoint contract is incomplete.');
    end
    if ~isequal(state.Seed,double(seed)) || ~isequal(state.Variance,double(variance)) || ...
            ~isequal(state.NumReceiveAntennas,size(x,2)) || state.SampleClass ~= string(class(x))
        error('sixgr:link:NoiseStreamAuthorityChanged', ...
            'A continuous noise stream cannot change seed, variance, receive layout or precision.');
    end
    if ~isequal(state.NextSample,double(startSample))
        error('sixgr:link:NoiseStreamTimeDiscontinuity', ...
            'Receiver noise expects sample %.0f, not %.0f. Supply every received interval.', ...
            state.NextSample, startSample);
    end
    stream.State = state.RandomState;
end
% Interleave I/Q and antennas per sample, not per call. Quiet or real-valued
% blocks still contain both quadratures of physical complex receiver noise.
draws = randn(stream, 2*size(x,2), n);
noise = sqrt(double(variance)/2) .* ...
    (draws(1:2:end,:).' + 1i*draws(2:2:end,:).');
y = x + cast(noise, 'like', x);
state.RandomState = stream.State;
state.NextSample = double(startSample)+n;
end
