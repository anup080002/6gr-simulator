function ok=testFiniteOFDMTransferCovariance()
% Exact-kernel comparison, not BLER or production network qualification.
% The public reference uses nrOFDMModulate -> finite sample FIR -> native
% nrOFDMDemodulate for every source symbol, independently of FFT-transfer math.
stream=RandStream('mt19937ar','Seed',71832);
maxError=0;
for caseIndex=1:4
    carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30,'NSlot',mod(caseIndex,2));
    if caseIndex==4, carrier.SubcarrierSpacing=60; carrier.CyclicPrefix='extended'; end
    sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
    N=sampling.Nfft; fs=sampling.SampleRateHz; nsym=2*carrier.SymbolsPerSlot;
    nt=4; nr=2; layers=1+mod(caseIndex,2); paths=3;
    [W,~]=qr(randn(stream,nt,layers)+1i*randn(stream,nt,layers),0); W=W/sqrt(layers);
    source=[0 0;1 0;35 0;71 0;0 carrier.SymbolsPerSlot-1;35 carrier.SymbolsPerSlot-1; ...
        0 carrier.SymbolsPerSlot;36 carrier.SymbolsPerSlot;71 nsym-1];
    receive=[0 0;1 0;36 0;71 0;0 carrier.SymbolsPerSlot;1 carrier.SymbolsPerSlot; ...
        35 carrier.SymbolsPerSlot;36 carrier.SymbolsPerSlot;71 nsym-1];
    filters=randn(stream,23,paths)/sqrt(23*paths);
    filters(3,:)=0; % only exact zeros may be omitted, never small real taps
    tx=nrOFDMModulate(carrier,complex(zeros(72,nsym,nt)), ...
        'Nfft',N,'SampleRate',fs,'Windowing',0);
    trim=11; samples=size(tx,1)+trim;
    t=(0:samples-1)'/fs;
    base=randn(stream,1,paths,nt,nr)+1i*randn(stream,1,paths,nt,nr);
    rates=reshape([117 -391 783],1,paths,1,1);
    gains=base.*exp(1i*2*pi*t.*rates);
    % A real piecewise propagation gain change is applied at the RECEIVED
    % sample, not at the source RE and not interpolated across the boundary.
    gains(floor(samples/2):end,:,:,:)=gains(floor(samples/2):end,:,:,:)*.7;
    fractions=[0 .37 .5 1];
    realization=struct('PathFilters',filters,'PathGains',gains,'SampleTimes',t, ...
        'SampleRateHz',fs,'TrimSamples',trim,'NumberOfSymbols',nsym,'Nfft',N, ...
        'CyclicPrefixFraction',fractions(caseIndex));
    power=.2+rand(stream,size(source,1),1);
    reference=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
        carrier,source,W,power,receive,realization);
    [covariance,other,useful]=sixgr.system.abstraction.finiteOFDMTransferCovariance( ...
        carrier,source,W,power,receive,realization,sampling);
    integrated=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
        carrier,source,W,power,receive,realization,'Algorithm','fft_transfer');
    assert(isequaln(integrated.Covariance,covariance) && ...
        isequaln(integrated.OtherResourceCovariance,other) && ...
        isequaln(integrated.SameResourceEffectiveChannel,useful));
    metadata={'Covariance','OtherResourceCovariance','SameResourceEffectiveChannel'};
    assert(isequaln(rmfield(integrated,metadata),rmfield(reference,metadata)), ...
        'test:FiniteTransferMetadata','Optimization must preserve the physical contract and honest labels.');
    a=relative(covariance,reference.Covariance);
    b=relative(other,reference.OtherResourceCovariance);
    c=relative(useful,reference.SameResourceEffectiveChannel);
    maxError=max([maxError a b c]);
    assert(max([a b c])<2e-11, ...
        'test:FiniteTransferMismatch','Finite transfer differs from independent OFDM probes: %g %g %g.',a,b,c);
    fprintf('FINITE_TRANSFER_CASE case=%d layers=%d cp_fraction=%g covariance=%g other=%g useful=%g\n', ...
        caseIndex,layers,fractions(caseIndex),a,b,c);
end
% Both implementations must reject malformed realizations/allocations. The
% FFT kernel must not bypass validation previously performed by native FIRs.
for algorithm=["native_probes","fft_transfer"]
    bad=realization; bad.PathGains=bad.PathGains(:,1:end-1,:,:);
    reject(@()sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
        carrier,source,W,power,receive,bad,'Algorithm',algorithm), ...
        'sixgr:phy:waveform:SampledChannelDimensions');
    bad=realization; bad.SampleTimes(2)=bad.SampleTimes(1);
    reject(@()sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
        carrier,source,W,power,receive,bad,'Algorithm',algorithm), ...
        'sixgr:abstraction:FiniteOFDMSampleClock');
    bad=realization; bad.PathGains=bad.PathGains(1:20,:,:,:); bad.SampleTimes=bad.SampleTimes(1:20);
    reject(@()sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
        carrier,source,W,power,receive,bad,'Algorithm',algorithm), ...
        'sixgr:abstraction:FiniteOFDMWindow');
end
% Complete attenuation must not be rejected or repaired with a unit channel.
% Keep the native FIR support: all-zero filters have no declared propagation
% support and the public CP-support evidence intentionally rejects that case.
realization.PathGains(:)=0;
reference=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
    carrier,source,W,power,receive,realization);
[covariance,other,useful]=sixgr.system.abstraction.finiteOFDMTransferCovariance( ...
    carrier,source,W,power,receive,realization,sampling);
assert(isequal(covariance,reference.Covariance) && ...
    isequal(other,reference.OtherResourceCovariance) && ...
    isequal(useful,reference.SameResourceEffectiveChannel) && ...
    ~any(covariance,'all') && ~any(other,'all') && ~any(useful,'all'), ...
    'test:FiniteTransferZeroChannel','An exactly zero channel must retain zero response and covariance.');
% The internal linear kernel also defines a zero FIR; this does not confer
% the usable propagation-support claim required by the public observation.
realization.PathFilters(:)=0;
[covariance,other,useful]=sixgr.system.abstraction.finiteOFDMTransferCovariance( ...
    carrier,source,W,power,receive,realization,sampling);
assert(~any(covariance,'all') && ~any(other,'all') && ~any(useful,'all'));
fprintf('FINITE_OFDM_TRANSFER_PASS cases=5 max_relative_error=%g statistical_qualification=0\n',maxError);
ok=true;
end
function e=relative(a,b)
e=norm(a(:)-b(:))/max(norm(b(:)),realmin);
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
