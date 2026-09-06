function ok = testPASoftLimiterResponse()
% Independently check the normalized p=2 Rapp law and coherent TX summation.
cfg.rf.pa = struct('enable',true,'method','softlimiter', ...
    'backoff_dB',0,'gain_dB',0,'ampm_deg',0);
pa = sixgr.rf.PAModel(cfg);
amplitude = [0; logspace(-8,8,257).'];
phase = 0.37;
x = amplitude * exp(1i*phase);
y = pa.apply(x);
expected = x ./ (1+amplitude.^4).^(1/4);
assert(max(abs(y-expected)) < 4e-15, 'Soft limiter differs from its defined Rapp transfer function.');
assert(all(diff(abs(y)) >= -8*eps) && max(abs(y)) <= 1+8*eps && ...
    abs(abs(y(end))-1) < 8*eps, ...
    'Output amplitude must grow monotonically to saturation, not fold back toward zero.');
assert(abs(pa.apply(exp(1i*phase)) - 2^(-1/4)*exp(1i*phase)) < 4e-15);
for sample = [complex(1e200,0),complex(0,1e200),complex(1e200,-1e200)]
    observed = pa.apply(sample);
    assert(isfinite(observed) && abs(abs(observed)-1) < 8*eps, ...
        'Finite overdriven inputs must saturate without overflow-induced foldback.');
end
ports = [x,conj(x)];
assert(isequal(pa.apply(ports),[y,conj(y)]), 'Each physical PA branch must preserve its own complex phase.');
singleOut = pa.apply(single(ports));
assert(isa(singleOut,'single') && max(abs(double(singleOut(:))-pa.apply(ports(:)))) < 4e-7);
% One device sees the coherent sum of contributors. Independent per-signal
% nonlinearities cannot be substituted for that physical transmitter.
a = complex(0.8,0.2)*ones(16,1);
b = complex(0.5,-0.1)*ones(16,1);
composed = pa.apply(a+b);
separate = pa.apply(a)+pa.apply(b);
assert(norm(composed-separate)>0.1);
ok = true;
disp('PA_SOFT_LIMITER_RESPONSE_PASS');
end
