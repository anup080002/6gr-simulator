function observation=sampledOFDMInterferenceCovariance(carrier,sourceCoordinates,precoder,powerPerRE,receiveCoordinates,realization,options)
%SAMPLEDOFDMINTERFERENCECOVARIANCE Finite-window independent-symbol covariance.
% Reference operator for qualifying a network covariance calculation. Every
% declared RE/layer is an independent unit-variance complex symbol. Channel
% coefficients are modeled inputs, not a receiver estimate. Neighboring
% symbols/slots must be included by the caller; outside this window is ZERO.
% Do not interpret this bounded operator as a complete network population.
% The optional FFT-transfer kernel is the same finite linear operator, not
% a diagonal/cyclic approximation. Keep native_probes as the independent
% reference and preserve the output schema/qualification labels for both.
% SourceSymbols optionally evaluates a declared deterministic population as
% well. Covariance remains the INDEPENDENT-symbol model for compatibility;
% ExplicitSymbolResponse and ExplicitSymbolSecondMoment are separate fields.
% For phase-coherent emitters, sum responses before taking the outer product.
arguments
    carrier (1,1) nrCarrierConfig
    sourceCoordinates (:,2) double {mustBeInteger,mustBeNonnegative,mustBeFinite}
    precoder (:,:) double {mustBeFinite}
    powerPerRE (:,1) double {mustBeNonnegative,mustBeFinite}
    receiveCoordinates (:,2) double {mustBeInteger,mustBeNonnegative,mustBeFinite}
    realization (1,1) struct
    options.Algorithm (1,1) string {mustBeMember(options.Algorithm,["native_probes","fft_transfer"])}="native_probes"
    options.SourceSymbols (:,:) double {mustBeFinite}=[]
end
fields={'PathFilters','PathGains','SampleTimes','SampleRateHz','TrimSamples','NumberOfSymbols','Nfft','CyclicPrefixFraction'};
assert(all(isfield(realization,fields)), ...
    'sixgr:abstraction:FiniteOFDMRealization','Supply the complete sampled channel and FFT clock.');
nsym=realization.NumberOfSymbols; nfft=realization.Nfft; fs=realization.SampleRateHz;
trim=realization.TrimSamples; fraction=realization.CyclicPrefixFraction;
validateattributes(nsym,{'double'},{'scalar','integer','positive','finite'});
validateattributes(trim,{'double'},{'scalar','integer','nonnegative','finite'});
validateattributes(fraction,{'double'},{'scalar','>=',0,'<=',1,'finite'});
assert(mod(nsym,carrier.SymbolsPerSlot)==0 && ~isempty(sourceCoordinates) && ...
    ~isempty(receiveCoordinates) && size(sourceCoordinates,1)==numel(powerPerRE) && ...
    size(unique(sourceCoordinates,'rows'),1)==size(sourceCoordinates,1) && ...
    all(sourceCoordinates(:,1)<12*carrier.NSizeGrid) && all(sourceCoordinates(:,2)<nsym) && ...
    all(receiveCoordinates(:,1)<12*carrier.NSizeGrid) && all(receiveCoordinates(:,2)<nsym) && ...
    ~isempty(precoder) && abs(norm(precoder,'fro')^2-1)<1e-12, ...
    'sixgr:abstraction:FiniteOFDMAllocation', ...
    'Require explicit in-window REs, one power per source RE and unit-total-power precoding.');
sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier,'Nfft',nfft,'SampleRate',fs);
filters=realization.PathFilters; gains=realization.PathGains;
nt=size(precoder,1); rank=size(precoder,2); nr=size(gains,4);
symbols=options.SourceSymbols;
assert(isempty(symbols) || isequal(size(symbols),[size(sourceCoordinates,1) rank]), ...
    'sixgr:abstraction:FiniteOFDMSymbolPopulation', ...
    'Explicit symbols must match every declared source RE and layer; no phase or pilot fill is inferred.');
explicitResponse=complex(zeros(nr,size(receiveCoordinates,1)));
% The native probe path enforced these through applySampledFadingChannel on
% every impulse. Enforce the same contract ONCE for both implementations.
validateattributes(filters,{'double'},{'2d','real','finite','nonempty'});
validateattributes(gains,{'double'},{'finite','nonempty'});
assert(ndims(gains)<=4 && size(gains,2)==size(filters,2), ...
    'sixgr:phy:waveform:SampledChannelDimensions', ...
    'Every sampled channel path must match one finite real-valued FIR.');
assert(size(gains,3)==nt && size(gains,1)>1, ...
    'sixgr:abstraction:FiniteOFDMRealization','Require a per-sample realization matching the TX port basis.');
times=double(realization.SampleTimes(:));
assert(numel(times)==size(gains,1) && all(isfinite(times)) && ...
    all(abs(diff(times)-1/fs)<=max(1e-12/fs,16*eps(max(abs(times))))), ...
    'sixgr:abstraction:FiniteOFDMSampleClock', ...
    'Gains must be sampled on the declared waveform clock; implicit interpolation is forbidden.');
cpCycle=sampling.CyclicPrefixLengths;
cp=cpCycle(mod(carrier.NSlot*carrier.SymbolsPerSlot+(0:nsym-1),numel(cpCycle))+1);
if options.Algorithm=="fft_transfer"
    % Resampled OFDM is a different sample-domain operator. It is not
    % silently represented by this Nfft-sample FFT transfer kernel.
    assert(abs(fs-nfft*carrier.SubcarrierSpacing*1e3)<=1e-12*fs, ...
        'sixgr:abstraction:FiniteOFDMResampling', ...
        'FFT transfer requires SampleRateHz=Nfft*SCS; use native probes for explicit resampling.');
    assert(size(gains,1)>=sum(nfft+cp)+trim, ...
        'sixgr:abstraction:FiniteOFDMWindow', ...
        'The retained gain samples do not cover the requested FFT window.');
    [covariance,otherResourceCovariance,sameResourceEffectiveChannel,explicitResponse]= ...
        sixgr.system.abstraction.finiteOFDMTransferCovariance( ...
        carrier,sourceCoordinates,precoder,powerPerRE,receiveCoordinates,realization,sampling,symbols);
else
covariance=complex(zeros(nr,nr,size(receiveCoordinates,1)));
otherResourceCovariance=complex(zeros(size(covariance)));
sameResourceEffectiveChannel=complex(zeros(nr,rank,size(receiveCoordinates,1)));
initial=complex(zeros(size(filters,1)-1,nt,size(filters,2)));
for source=1:size(sourceCoordinates,1)
    for layer=1:rank
        grid=complex(zeros(12*carrier.NSizeGrid,nsym,nt));
        grid(sourceCoordinates(source,1)+1,sourceCoordinates(source,2)+1,:)= ...
            sqrt(powerPerRE(source))*reshape(precoder(:,layer),1,1,nt);
        waveform=nrOFDMModulate(carrier,grid,'Nfft',nfft,'SampleRate',fs,'Windowing',0);
        assert(size(gains,1)>=size(waveform,1)+trim, ...
            'sixgr:abstraction:FiniteOFDMWindow','The retained gain samples do not cover the requested FFT window.');
        padded=[waveform;zeros(size(gains,1)-size(waveform,1),nt)];
        received=sixgr.phy.waveform.applySampledFadingChannel(padded,filters,gains,initial);
        rx=nrOFDMDemodulate(carrier,received(trim+(1:size(waveform,1)),:), ...
            'Nfft',nfft,'SampleRate',fs,'CyclicPrefixFraction',fraction);
        for k=1:size(receiveCoordinates,1)
            value=reshape(rx(receiveCoordinates(k,1)+1,receiveCoordinates(k,2)+1,:),nr,1);
            covariance(:,:,k)=covariance(:,:,k)+value*value';
            if ~isempty(symbols)
                explicitResponse(:,k)=explicitResponse(:,k)+value*symbols(source,layer);
            end
            if isequal(receiveCoordinates(k,:),sourceCoordinates(source,:))
                % This coefficient already includes the declared source
                % power and frozen layer-to-port precoder. Other layers on
                % this same RE belong in the spatial detector, not a second
                % copy in the external/noise covariance.
                sameResourceEffectiveChannel(:,layer,k)=value;
            else
                % Accumulate directly instead of subtracting near-equal
                % covariances and clipping a negative roundoff residual.
                otherResourceCovariance(:,:,k)=otherResourceCovariance(:,:,k)+value*value';
            end
        end
    end
end
end
observation=struct('Covariance',covariance,'Coordinates0Based',receiveCoordinates, ...
    'SameResourceEffectiveChannel',sameResourceEffectiveChannel, ...
    'SameResourceChannelIncludesTransmitPower',true, ...
    'OtherResourceCovariance',otherResourceCovariance, ...
    'SourceCoordinates0Based',sourceCoordinates,'TransmitPowerPerRE_W',powerPerRE, ...
    'Precoder',precoder,'NumberOfSymbols',nsym, ...
    'SymbolCovarianceAssumption',"independent_unit_variance_per_declared_RE_and_layer", ...
    'SourceClassification',"modeled_finite_filter_independent_symbol_covariance", ...
    'BoundaryPolicy',"explicit_zero_outside_declared_observation_window", ...
    'ChannelStartTime_s',times(1),'SampleRateHz',fs,'Nfft',nfft, ...
    'CyclicPrefixSupport',sixgr.phy.waveform.channelCyclicPrefixSupport(filters,trim, ...
        sampling.CyclicPrefixLengths,fraction), ...
    'WithinWindowISIICIIncluded',true,'CommonControlInterferenceQualified',false, ...
    'FullNetworkInterferenceQualified',false, ...
    'StatisticalBLERQualified',false,'PrimaryStudyAccepted',false);
if ~isempty(symbols)
    secondMoment=complex(zeros(nr,nr,size(receiveCoordinates,1)));
    for k=1:size(receiveCoordinates,1)
        v=explicitResponse(:,k); secondMoment(:,:,k)=v*v';
    end
    observation.ExplicitSymbolResponse=explicitResponse;
    observation.ExplicitSymbolSecondMoment=secondMoment;
    observation.ExplicitSymbolSourceSHA256=string(sixgr.phy.mimo.MatrixContract.digest(symbols));
    observation.ExplicitSymbolAssumption="declared_complex_symbols_coherent_within_source_population";
    observation.ExplicitSymbolQualification="finite_linear_operator_not_complete_network_or_receiver_measurement";
end
end
