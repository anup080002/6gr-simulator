function [y, evidence, phaseState] = applyRFStudyBranch(x, cfg, phaseState)
%APPLYRFSTUDYBRANCH Execute explicit sample-domain RF study assumptions.
% x is samples-by-physical-chain. TX power is SUM over physical chains.
% This component does not decode a TB or qualify an oscillator/array model.
% Call once per independently seeded trial; preserve phaseState across
% contiguous blocks and use SampleOffset for the common CFO oscillator.
if nargin < 3, phaseState = []; end
required = ["Endpoint","SampleRateHz","CarrierFrequencyHz","SCSHz", ...
    "NormalizedCFO","SampleOffset","EVMPercent","EVMCorrelation", ...
    "EVMReferencePowerPerChain","Seed","PhaseNoiseEnabled"];
if ~isstruct(cfg) || ~all(isfield(cfg,required))
    error('sixgr:ran1ai1032:RFConfigMissing','RF branch requires every explicit sample-domain parameter.');
end
if ~isnumeric(x) || isempty(x) || ~ismatrix(x) || any(~isfinite(x(:)))
    error('sixgr:ran1ai1032:RFInvalidSamples','Finite samples-by-chain input is required.');
end
endpoint = string(cfg.Endpoint);
if ~isscalar(endpoint) || ~ismember(endpoint,["tx","rx"])
    error('sixgr:ran1ai1032:RFConfigInvalid','Endpoint must be tx or rx.');
end
localPositive(cfg.SampleRateHz,'SampleRateHz');
localPositive(cfg.CarrierFrequencyHz,'CarrierFrequencyHz');
localPositive(cfg.SCSHz,'SCSHz');
validateattributes(cfg.SampleOffset,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(cfg.Seed,{'numeric'},{'scalar','integer','nonnegative','finite','<=',2^32-1});
validateattributes(cfg.EVMPercent,{'numeric'},{'scalar','nonnegative','finite'});
validateattributes(cfg.NormalizedCFO,{'numeric'},{'scalar','finite','real'});
validateattributes(cfg.PhaseNoiseEnabled,{'logical','numeric'},{'scalar','binary'});
nChain=size(x,2); c=double(cfg.EVMCorrelation);
if ~isequal(size(c),[nChain nChain]) || any(~isfinite(c(:))) || ...
        norm(c-c','fro')>1e-10 || any(abs(diag(c)-1)>1e-10)
    error('sixgr:ran1ai1032:RFInvalidCovariance','EVM correlation must be Hermitian with unit diagonal for each physical chain.');
end
[v,d]=eig((c+c')/2); eigenvalues=real(diag(d));
if any(eigenvalues < -1e-10)
    error('sixgr:ran1ai1032:RFInvalidCovariance','EVM correlation must be positive semidefinite.');
end
refPower=double(cfg.EVMReferencePowerPerChain(:).');
if numel(refPower)~=nChain || any(~isfinite(refPower)) || any(refPower<0) || sum(refPower)<=0
    error('sixgr:ran1ai1032:RFReferencePowerMissing','Explicit clean-signal reference power is required for every physical chain.');
end
% Row samples have E[z''*z]=I; this factor gives E[e''*e]=C.
factor=diag(sqrt(max(eigenvalues,0)))*v';
stream=RandStream('Threefry','Seed',double(cfg.Seed));
% Trial callers provide a distinct seed. Block callers preserve draw order
% using a deterministic sample offset; real/imag innovations are interleaved.
if cfg.SampleOffset>0
    remaining=double(cfg.SampleOffset);
    while remaining>0
        count=min(remaining,65536);
        randn(stream,2*nChain,count);
        remaining=remaining-count;
    end
end
z=randn(stream,2*nChain,size(x,1));
z=(z(1:nChain,:)+1i*z(nChain+1:end,:)).'/sqrt(2);
distortion=(z*factor).*(sqrt(refPower)*double(cfg.EVMPercent)/100);
reference=double(x); y=reference+distortion;
requested=NaN; maximum=NaN; actual=NaN; capActive=false; scale=1;
if endpoint=="tx"
    if ~all(isfield(cfg,["RequestedPowerdBm","PowerClassMaxdBm","MPRdB"]))
        error('sixgr:ran1ai1032:RFPowerContextMissing','TX branch requires requested power, power-class maximum and MPR.');
    end
    validateattributes(cfg.RequestedPowerdBm,{'numeric'},{'scalar','finite','real'});
    validateattributes(cfg.PowerClassMaxdBm,{'numeric'},{'scalar','finite','real'});
    validateattributes(cfg.MPRdB,{'numeric'},{'scalar','nonnegative','finite'});
    requested=double(cfg.RequestedPowerdBm);
    maximum=double(cfg.PowerClassMaxdBm)-double(cfg.MPRdB);
    actual=min(requested,maximum); capActive=requested>maximum;
    % Cap the total radiated waveform INCLUDING additive transmitter EVM.
    % Each sample-power unit here is one watt; calibration is explicit.
    powerBefore=mean(sum(abs(y).^2,2));
    if ~isfinite(powerBefore) || powerBefore<=0
        error('sixgr:ran1ai1032:RFZeroTransmitPower','A zero/nonfinite waveform cannot be calibrated to requested TX power.');
    end
    scale=sqrt(10.^((actual-30)/10)/powerBefore);
    y=y*scale; reference=reference*scale; distortion=distortion*scale;
end
evmMeasured=100*sqrt(sum(abs(distortion(:)).^2)/ ...
    (size(x,1)*sum(refPower)*scale^2));
phaseTrace=struct();
if logical(cfg.PhaseNoiseEnabled)
    if ~isfield(cfg,'PhaseNoiseProfile')
        error('sixgr:ran1ai1032:RFPhaseNoiseProfileMissing','Enabled phase noise requires a versioned explicit mask; carrier defaults cannot qualify 7 GHz.');
    end
    profile=sixgr.rf.runtime.PhaseNoiseProfile.validate(cfg.PhaseNoiseProfile);
    if profile.CarrierFrequency_Hz~=cfg.CarrierFrequencyHz || profile.SampleRate_Hz~=cfg.SampleRateHz
        error('sixgr:ran1ai1032:RFPhaseNoiseProfileMismatch','Phase-noise mask must match the configured carrier and sample rate.');
    end
    if isempty(phaseState)
        if cfg.SampleOffset~=0
            error('sixgr:ran1ai1032:RFPhaseNoiseStateMissing','Continuation requires retained oscillator state.');
        end
        phaseState=sixgr.rf.runtime.PhaseNoiseProcess(profile,nChain,1);
    elseif phaseState.SampleIndex~=cfg.SampleOffset || ~isequaln(phaseState.Profile,profile)
        error('sixgr:ran1ai1032:RFPhaseNoiseStateMismatch','Retained oscillator state must match profile and sample offset.');
    end
    [y,phaseTrace]=phaseState.apply(y,1);
end
cfo=double(cfg.NormalizedCFO)*double(cfg.SCSHz);
n=double(cfg.SampleOffset)+(0:size(y,1)-1).';
y=y.*exp(1i*2*pi*cfo*n/double(cfg.SampleRateHz));
evidence=struct('Endpoint',endpoint,'CarrierFrequencyHz',double(cfg.CarrierFrequencyHz), ...
    'SampleRateHz',double(cfg.SampleRateHz),'ChainCount',nChain, ...
    'RequestedPowerdBm',requested,'MaximumAllowedPowerdBm',maximum, ...
    'AppliedPowerdBm',actual,'CapActive',capActive, ...
    'OutputPerChainPowerW',mean(abs(y).^2,1), ...
    'OutputTotalPowerW',mean(sum(abs(y).^2,2)), ...
    'EVMReferencePowerPerChain',refPower,'EVMCorrelation',c, ...
    'ConfiguredEVMPercent',double(cfg.EVMPercent),'MeasuredAdditiveEVMPercent',evmMeasured, ...
    'AppliedCFOHz',cfo,'PhaseNoiseEnabled',logical(cfg.PhaseNoiseEnabled), ...
    'PhaseNoiseTrace',phaseTrace,'Seed',double(cfg.Seed), ...
    'EVMInjectionPlane',endpoint+"_time_samples", ...
    'SourceClassification',"executed_sample_domain_rf_component", ...
    'DecodedPHYQualified',false,'AbsolutePowerPlane',"sample_squared_magnitude_watts_total_over_chains");
end

function localPositive(value,name)
validateattributes(value,{'numeric'},{'scalar','real','finite','positive'},mfilename,name);
end
