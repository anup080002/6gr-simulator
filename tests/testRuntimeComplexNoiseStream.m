function ok = testRuntimeComplexNoiseStream()
% Exact realization/checkpoint tests plus independent complex-noise moments.
setup6GRSimToolkit('Verbose', false);
initialRNG = rng;
cleanup = onCleanup(@()rng(initialRNG)); %#ok<NASGU>
variance = 1.7e-8;
seed = 72391;
for precision = ["single","double"]
    for chains = [1 2 5]
        x = zeros(10007,chains,char(precision)); % Real quiet samples still need complex noise.
        [whole, final] = sixgr.link.addRuntimeComplexNoise(x,variance,seed,93);
        state = struct();
        divided = complex(zeros(size(x),'like',x));
        first = 0;
        for last = [1 2 71 4096 4100 size(x,1)]
            [divided(first+1:last,:),state] = sixgr.link.addRuntimeComplexNoise( ...
                x(first+1:last,:),variance,seed,93+first,state);
            first = last;
        end
        assert(isequal(whole,divided) && isequaln(final,state));
        assert(any(imag(whole(:))~=0) && isa(whole,char(precision)));
        snapshot = state;
        [a,nextA] = sixgr.link.addRuntimeComplexNoise(x(1:7,:),variance,seed,state.NextSample,state);
        [b,nextB] = sixgr.link.addRuntimeComplexNoise(x(1:7,:),variance,seed,state.NextSample,snapshot);
        assert(isequal(a,b) && isequaln(nextA,nextB) && isequaln(state,snapshot));
        localError(@()sixgr.link.addRuntimeComplexNoise(x,variance,seed,state.NextSample+1,state), ...
            'sixgr:link:NoiseStreamTimeDiscontinuity');
        localError(@()sixgr.link.addRuntimeComplexNoise(x,variance*2,seed,state.NextSample,state), ...
            'sixgr:link:NoiseStreamAuthorityChanged');
        localError(@()sixgr.link.addRuntimeComplexNoise(x,variance,seed+1,state.NextSample,state), ...
            'sixgr:link:NoiseStreamAuthorityChanged');
    end
end
[noise,~] = sixgr.link.addRuntimeComplexNoise(zeros(100000,2),variance,seed,0);
assert(all(abs(mean(abs(noise).^2)/variance-1)<0.02));
assert(all(abs(mean(real(noise).^2)/(variance/2)-1)<0.02));
assert(all(abs(mean(imag(noise).^2)/(variance/2)-1)<0.02));
assert(abs(mean(conj(noise(:,1)).*noise(:,2)))/variance<0.02);
assert(isequaln(rng,initialRNG), 'Receiver noise must not consume global RNG state.');
ok = true;
disp('RUNTIME_COMPLEX_NOISE_STREAM_PASS');
end

function localError(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id), 'Unexpected error: %s', cause.identifier);
    return;
end
error('TEST:MissingExpectedError','Expected %s.',id);
end
