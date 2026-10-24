classdef AppliedTXLinearReferenceStream
    % Fixed mathematical TX reference with independent explicit VALUE state.
    % No RF, oscillator, converter or channel is executed by this adapter.
    % Supplied samples/receipts are checked; their original owner is NOT
    % established here. A component is homogeneous. Only the aggregate adds
    % the supplied IQ DC term, once; its reference is consequently affine.
    %
    % Constructor binding fields: EndpointID, Direction (DL/UL), ReferenceID,
    % Role (aggregate/component), ConfigurationEpoch, SampleRateHz,
    % NumAntennas, NumericClass (single/double), WaveformAmplitudeUnit,
    % OriginSample, HistoryInitialization='declared_zero_model_state'.
    % Clock, epoch and count coordinates are canonical double integers in
    % [0,flintmax]; an interval must advance exactly by its sample count.
    % fromComponentBirth declares zero COMPONENT model history at a later
    % interval boundary. It does not reset the original RF/oscillator origin
    % and does not establish original-owner registration provenance.
    %
    % advance(modelInput,originalRFInput,originalRFOutput,interval) returns
    % [next,referenceSamples,receipt]. All arrays share the full interval.
    % Aggregate modelInput must equal originalRFInput. Interval fields:
    % ContractVersion='sixgr.rf.supplied_TX_operator_interval/v1', EndpointID,
    % Direction, ConfigurationEpoch, SampleRateHz, NumAntennas, NumericClass,
    % WaveformAmplitudeUnit, OriginSample, StartSample, EndSampleExclusive,
    % InstallationSHA256, RFInputWaveformSHA256, RFOutputWaveformSHA256,
    % StageOrder and Stages. Stages has EXACT keys DAC,IQ,Element,PA,
    % PhaseNoise,CFO,Timing,SampleClockOffset,CarrierPhase. Each has Enabled,
    % Executed (logical), InputSHA256,OutputSHA256,Parameters (scalar struct).
    % Disabled stages require empty Parameters and 'disabled_identity' hashes.
    % Enabled parameters (exact fields):
    % DAC: Profile,ReferenceModel='identity_converter_reference'. Profile is
    %      the original deterministic retained DAC profile incl Seed.
    % IQ: Alpha,Beta,DCOffset. Element: Gain,Coupling,PhysicalInputAlreadyMapped.
    % PA: Profile (original explicit executed profile, not chain summary).
    % PhaseNoise: Trace (agreed original PhaseNoiseModel optional trace).
    % CFO: FrequencyHz,Multiplier (original cast Ns-by-1 rotation).
    % Timing: DelaySamples (nonnegative integer). CarrierPhase: Multiplier.
    % Enabled SampleClockOffset is unsupported, never interpreted as identity.
    % Original StageOrder is the eight TX stages plus enabled carrier phase.
    %
    % DAC identity and PA first-order taps are DECLARED MODEL choices. The
    % aggregate receipt retains actual-minus-reference residual and cross
    % energy; it never discards distortion or attributes it uniquely to ports.
    properties (SetAccess=private)
        Binding
        NextSampleIndex
        StaticOperatorSHA256 = ""
        InstallationSHA256 = ""
        ModelHistoryStartSample
        ComponentBirth = struct()
    end
    properties (Access=private)
        PAHistory = []
        DelayHistory = []
    end
    methods
        function obj=AppliedTXLinearReferenceStream(binding)
            localExactFields(binding,{'EndpointID','Direction','ReferenceID','Role', ...
                'ConfigurationEpoch','SampleRateHz','NumAntennas','NumericClass', ...
                'WaveformAmplitudeUnit','OriginSample','HistoryInitialization'},'Binding');
            for name=["EndpointID","ReferenceID"]
                localText(binding.(name),'Binding');
            end
            assert(any(localText(binding.Direction,'Binding')==["DL","UL"]) && ...
                any(localText(binding.Role,'Binding')==["aggregate","component"]) && ...
                any(localText(binding.NumericClass,'Binding')==["single","double"]) && ...
                any(localText(binding.WaveformAmplitudeUnit,'Binding')== ...
                ["sqrt_mW","normalized_complex_baseband"]) && ...
                localText(binding.HistoryInitialization,'History')=="declared_zero_model_state", ...
                'RF:TXLinearReferenceBinding','Declare the exact component scope and zero MODEL history.');
            localInteger(binding.ConfigurationEpoch,0,'Binding');
            localInteger(binding.OriginSample,0,'Binding');
            localInteger(binding.NumAntennas,1,'Binding');
            localReal(binding.SampleRateHz,'Binding');
            assert(binding.SampleRateHz>0,'RF:TXLinearReferenceBinding','Positive Fs is required.');
            obj.Binding=binding; obj.NextSampleIndex=binding.OriginSample;
            obj.ModelHistoryStartSample=binding.OriginSample;
        end

        function [next,reference,receipt]=advance(obj,input,originalInput,originalOutput,interval)
            b=obj.Binding;
            localFields(interval,{'ContractVersion','EndpointID','Direction','ConfigurationEpoch', ...
                'SampleRateHz','NumAntennas','NumericClass','WaveformAmplitudeUnit','OriginSample', ...
                'StartSample','EndSampleExclusive','InstallationSHA256','RFInputWaveformSHA256', ...
                'RFOutputWaveformSHA256','StageOrder','Stages'},'Interval');
            assert(localText(interval.ContractVersion,'Interval')== ...
                "sixgr.rf.supplied_TX_operator_interval/v1", ...
                'RF:TXLinearReferenceInterval','Unsupported supplied operator contract.');
            for name=["EndpointID","Direction","ConfigurationEpoch","SampleRateHz", ...
                    "NumAntennas","NumericClass","WaveformAmplitudeUnit","OriginSample"]
                assert(isequaln(interval.(name),b.(name)), ...
                    'RF:TXLinearReferenceBinding','Supplied interval changed %s.',name);
            end
            localSamples(input,b); localSamples(originalInput,b); localSamples(originalOutput,b);
            n=size(input,1);
            localInteger(interval.StartSample,0,'Clock');
            localInteger(interval.EndSampleExclusive,0,'Clock');
            assert(n<=flintmax-obj.NextSampleIndex, ...
                'RF:TXLinearReferenceClock','Sample interval exceeds exact integer clock range.');
            stop=obj.NextSampleIndex+n;
            assert(stop>obj.NextSampleIndex&&stop-obj.NextSampleIndex==n, ...
                'RF:TXLinearReferenceClock','Sample interval must advance exactly by its nonzero length.');
            assert(isequal(size(input),size(originalInput),size(originalOutput)) && ...
                isequal(interval.StartSample,obj.NextSampleIndex)&& ...
                isequal(interval.EndSampleExclusive,stop), ...
                'RF:TXLinearReferenceClock','Require the next complete interval, without gaps or cropping.');
            localInteger(stop,0,'Clock');
            inputHash=localRFHash(originalInput); outputHash=localRFHash(originalOutput);
            assert(localHash(interval.RFInputWaveformSHA256)==inputHash && ...
                localHash(interval.RFOutputWaveformSHA256)==outputHash, ...
                'RF:TXLinearReferenceSamples','Supplied original RF sample hashes do not match.');
            aggregate=string(b.Role)=="aggregate";
            assert(~aggregate||isequal(input,originalInput), ...
                'RF:TXLinearReferenceSamples','Aggregate reference must consume ALL original RF input.');
            if ~isempty(fieldnames(obj.ComponentBirth))
                birth=obj.ComponentBirth;
                % A late reference is homogeneous and has zero input outside
                % its registered support, even while aggregate RF history is
                % nonzero. Keep complete original intervals/oscillator clocks.
                sample=interval.StartSample+(0:n-1).';
                outside=sample<birth.ComponentSupportStartSample | ...
                    sample>=birth.ComponentSupportEndSampleExclusive;
                assert(~any(any(input(outside,:)~=0)), ...
                    'RF:TXLinearReferenceHistory','Component input occurs outside its declared support.');
            end
            installation=localHash(interval.InstallationSHA256);
            assert(obj.InstallationSHA256==""||obj.InstallationSHA256==installation, ...
                'RF:TXLinearReferenceInstallation','Installation changed without a new declared origin.');
            [s,staticSHA,paReference]=localOperators(interval,b,n,inputHash,outputHash);
            assert(obj.StaticOperatorSHA256==""||obj.StaticOperatorSHA256==staticSHA, ...
                'RF:TXLinearReferenceInstallation','Static executed stage parameters changed.');
            % All validation precedes arithmetic/state construction. This is
            % a value object; a rejected call cannot advance the caller.
            reference=input;
            if s.IQ.Enabled
                p=s.IQ.Parameters;
                reference=p.Alpha.*reference+p.Beta.*conj(reference);
                if aggregate, reference=reference+cast(p.DCOffset,'like',reference); end
            end
            if s.Element.Enabled
                p=s.Element.Parameters;
                reference=reference.*cast(reshape(p.Gain,1,[]),'like',reference);
                reference=reference*cast(p.Coupling.','like',reference);
            end
            paState=obj.PAHistory;
            if s.PA.Enabled
                [reference,paState]=localFIR(reference,paReference.LinearTaps,paState);
            end
            if s.PhaseNoise.Enabled
                reference=reference.*s.PhaseNoise.Parameters.Trace.Multiplier;
            end
            if s.CFO.Enabled, reference=reference.*s.CFO.Parameters.Multiplier; end
            delayState=obj.DelayHistory;
            if s.Timing.Enabled
                delay=s.Timing.Parameters.DelaySamples;
                if isempty(delayState), delayState=zeros(delay,b.NumAntennas,'like',input); end
                [reference,delayState]=filter([zeros(1,delay) 1],1,reference,delayState,1);
            end
            if s.CarrierPhase.Enabled
                reference=reference.*s.CarrierPhase.Parameters.Multiplier;
            end
            assert(all(isfinite(reference(:)))&&strcmp(class(reference),char(b.NumericClass)), ...
                'RF:TXLinearReferenceOverflow','Reference samples must retain finite original precision.');
            next=obj; next.NextSampleIndex=stop;
            next.PAHistory=paState; next.DelayHistory=delayState;
            next.StaticOperatorSHA256=staticSHA; next.InstallationSHA256=installation;
            receipt=struct('ContractVersion',"sixgr.rf.AppliedTXLinearReferenceStream/v1", ...
                'Source',"validated_supplied_original_operator_operands", ...
                'ReferenceID',string(b.ReferenceID),'Role',string(b.Role), ...
                'EndpointID',string(b.EndpointID),'Direction',string(b.Direction), ...
                'ConfigurationEpoch',b.ConfigurationEpoch,'OriginSample',b.OriginSample, ...
                'ModelHistoryStartSample',obj.ModelHistoryStartSample, ...
                'ComponentBirth',obj.ComponentBirth, ...
                'StartSample',obj.NextSampleIndex,'EndSampleExclusive',stop, ...
                'SampleRateHz',b.SampleRateHz,'NumAntennas',b.NumAntennas, ...
                'NumericClass',string(b.NumericClass),'WaveformAmplitudeUnit',string(b.WaveformAmplitudeUnit), ...
                'InstallationSHA256',installation,'StaticOperatorSHA256',staticSHA, ...
                'OriginalRFInputSHA256',inputHash,'OriginalRFOutputSHA256',outputHash, ...
                'OriginalRFHashSerialization',"sixgr.rf.waveformSHA256", ...
                'ModelInputSHA256',localArrayHash(input),'ReferenceOutputSHA256',localArrayHash(reference), ...
                'ModelHashSerialization',"WaveformHash.runtimeArray", ...
                'IntervalOperatorSHA256',localIntervalOperatorHash(s,staticSHA), ...
                'ModelPAStateSHA256',localArrayHash(paState), ...
                'ModelDelayStateSHA256',localArrayHash(delayState), ...
                'HistoryAuthority',"independent_declared_zero_model_state_not_original_aggregate_memory", ...
                'DACReferenceModel',"identity_converter_reference_residual_retained", ...
                'PAReferenceModel',"fixed_declared_first_order_PA", ...
                'AggregateCommonIQDCIncluded',aggregate&&s.IQ.Enabled, ...
                'SuppliedOperandsValidated',true,'OriginalOwnerVerified',false, ...
                'SharedRuntimeIntegrationQualified',false,'ActualNonlinearPortAttribution',false, ...
                'StandardizedPowerAccuracyQualified',false,'HardwareQualified',false, ...
                'ReceiverEstimatorInput',false,'AdditionalRFExecutions',0,'AdditionalChannelExecutions',0, ...
                'ResidualAvailable',aggregate,'ResidualSHA256',"", ...
                'ReferenceEnergy',sum(abs(double(reference(:))).^2), ...
                'ActualAggregateOutputEnergy',NaN,'ResidualEnergy',NaN, ...
                'ReferenceResidualCrossEnergy',NaN,'PowerClosureRelativeError',NaN);
            if aggregate
                residual=double(originalOutput)-double(reference);
                actualEnergy=sum(abs(double(originalOutput(:))).^2);
                residualEnergy=sum(abs(residual(:)).^2);
                crossEnergy=2*real(sum(conj(double(reference(:))).*residual(:)));
                receipt.ResidualSHA256=localArrayHash(residual);
                receipt.ActualAggregateOutputEnergy=actualEnergy;
                receipt.ResidualEnergy=residualEnergy;
                receipt.ReferenceResidualCrossEnergy=crossEnergy;
                receipt.PowerClosureRelativeError=abs(actualEnergy- ...
                    (receipt.ReferenceEnergy+residualEnergy+crossEnergy))/max(actualEnergy,realmin);
            end
        end
    end
    methods (Static)
        function obj=fromComponentBirth(binding,birth)
            % These are DECLARED model coordinates, not a fabricated original
            % RF reset. A production owner must independently join registration
            % to the queued transmitter component and its original hashes.
            obj=sixgr.rf.runtime.AppliedTXLinearReferenceStream(binding);
            localExactFields(birth,{'ContractVersion','ParentComponentID','ResourceID', ...
                'LogicalPort','ModelHistoryStartSample','ComponentSupportStartSample', ...
                'ComponentSupportEndSampleExclusive','RegistrationSHA256'},'History');
            assert(string(binding.Role)=="component" && ...
                localText(birth.ContractVersion,'History')=="sixgr.rf.declared_TX_component_birth/v1", ...
                'RF:TXLinearReferenceHistory','Only a homogeneous component may declare a later birth.');
            localText(birth.ParentComponentID,'History'); localText(birth.ResourceID,'History');
            localInteger(birth.LogicalPort,0,'History');
            for key=["ModelHistoryStartSample","ComponentSupportStartSample","ComponentSupportEndSampleExclusive"]
                localInteger(birth.(key),0,'History');
            end
            localHash(birth.RegistrationSHA256);
            assert(binding.OriginSample<=birth.ModelHistoryStartSample && ...
                birth.ModelHistoryStartSample<=birth.ComponentSupportStartSample && ...
                birth.ComponentSupportStartSample<birth.ComponentSupportEndSampleExclusive, ...
                'RF:TXLinearReferenceHistory','Require original RF origin <= model origin <= nonempty component support.');
            obj.ComponentBirth=birth;
            obj.ModelHistoryStartSample=birth.ModelHistoryStartSample;
            obj.NextSampleIndex=birth.ModelHistoryStartSample;
        end
    end
end

function [s,digest,paReference]=localOperators(interval,b,n,inputHash,outputHash)
keys={'DAC','IQ','Element','PA','PhaseNoise','CFO','Timing','SampleClockOffset','CarrierPhase'};
names=["tx_dac","tx_iq","tx_element_rf","tx_pa","tx_phase_noise", ...
    "tx_cfo","tx_timing","tx_sample_clock_offset","tx_carrier_phase"];
s=interval.Stages; localExactFields(s,keys,'Stage');
signatures=strings(1,numel(keys)); previous=inputHash; paReference=struct();
for k=1:numel(keys)
    st=s.(keys{k});
    localExactFields(st,{'Enabled','Executed','InputSHA256','OutputSHA256','Parameters'},'Stage');
    assert(islogical(st.Enabled)&&isscalar(st.Enabled)&&islogical(st.Executed)&&isscalar(st.Executed) && ...
        st.Enabled==st.Executed && isstruct(st.Parameters)&&isscalar(st.Parameters), ...
        'RF:TXLinearReferenceStage','Explicit executed/disabled stage receipts are required.');
    if ~st.Enabled
        assert(isempty(fieldnames(st.Parameters))&&localText(st.InputSHA256,'Stage')=="disabled_identity" && ...
            localText(st.OutputSHA256,'Stage')=="disabled_identity", ...
            'RF:TXLinearReferenceStage','A disabled stage must explicitly be identity.');
        signatures(k)=names(k)+":disabled"; continue;
    end
    assert(localHash(st.InputSHA256)==previous,'RF:TXLinearReferenceStage', ...
        'Supplied original stage input/output hash chain is inconsistent.');
    previous=localHash(st.OutputSHA256); p=st.Parameters;
    switch keys{k}
        case 'DAC'
            localExactFields(p,{'Profile','ReferenceModel'},'Stage');
            assert(localText(p.ReferenceModel,'Stage')=="identity_converter_reference", ...
                'RF:TXLinearReferenceUnsupported','Unknown DAC reference model.');
            q=p.Profile;
            localExactFields(q,{'Bits','FullScale','Convention','DitherRMS','ApertureJitter_s', ...
                'ProfileID','Version','Seed'},'Stage');
            localInteger(q.Bits,2,'Stage'); localReal(q.FullScale,'Stage');
            localInteger(q.Seed,0,'Stage'); localText(q.ProfileID,'Stage'); localText(q.Version,'Stage');
            assert(q.Bits<=24&&q.FullScale>0&&isequal(q.DitherRMS,0)&&isequal(q.ApertureJitter_s,0) && ...
                any(localText(q.Convention,'Stage')==["signed_midtread","signed_midrise"]), ...
                'RF:TXLinearReferenceUnsupported','Only the original deterministic retained DAC is supported.');
            token=string(sixgr.util.sha256Hex(jsonencode(orderfields(q))));
        case 'IQ'
            localExactFields(p,{'Alpha','Beta','DCOffset'},'Stage');
            for field=["Alpha","Beta","DCOffset"], localComplexScalar(p.(field),'Stage'); end
            token=localArrayHash([p.Alpha p.Beta p.DCOffset]);
        case 'Element'
            localExactFields(p,{'Gain','Coupling','PhysicalInputAlreadyMapped'},'Stage');
            assert(isequal(p.PhysicalInputAlreadyMapped,true)&&isnumeric(p.Gain)&&isvector(p.Gain) && ...
                numel(p.Gain)==b.NumAntennas&&all(isfinite(p.Gain(:))) && ...
                isnumeric(p.Coupling)&&isequal(size(p.Coupling),[b.NumAntennas b.NumAntennas]) && ...
                all(isfinite(p.Coupling(:))), ...
                'RF:TXLinearReferenceStage','Use actual physical-column gains/coupling, never another port map.');
            token=localArrayHash(p.Gain)+":"+localArrayHash(p.Coupling);
        case 'PA'
            localExactFields(p,{'Profile'},'Stage');
            paReference=sixgr.rf.runtime.linearPAReferenceCoefficients(p.Profile);
            token=paReference.ConsumedProfileParametersSHA256;
        case 'PhaseNoise'
            localExactFields(p,{'Trace'},'Stage'); t=p.Trace;
            localFields(t,{'Available','Phase_rad','Multiplier','Backend','StateEpoch', ...
                'StartSample0','EndSampleExclusive','Scope'},'Stage');
            localInteger(t.StateEpoch,0,'Stage'); localInteger(t.StartSample0,0,'Stage');
            localInteger(t.EndSampleExclusive,0,'Stage');
            assert(isequal(t.Available,true)&&t.StateEpoch==b.ConfigurationEpoch && ...
                t.StartSample0==interval.StartSample-b.OriginSample && ...
                t.EndSampleExclusive==interval.EndSampleExclusive-b.OriginSample && ...
                localText(t.Backend,'Stage')=="sixgr_rf_runtime_phase_noise_process" && ...
                localText(t.Scope,'Stage')=="original_executed_phase_noise_multiplier" && ...
                isa(t.Phase_rad,'double')&&isreal(t.Phase_rad)&& ...
                isequal(size(t.Phase_rad),[n b.NumAntennas])&&all(isfinite(t.Phase_rad(:))), ...
                'RF:TXLinearReferenceStage','Require the original enabled oscillator interval, including zeros.');
            localMultiplier(t.Multiplier,[n b.NumAntennas],b.NumericClass);
            assert(isequal(t.Multiplier,cast(exp(1j.*t.Phase_rad),char(b.NumericClass))), ...
                'RF:TXLinearReferenceStage','Phase and actual cast multiplier contradict.');
            token=string(t.Backend)+":"+string(t.StateEpoch);
        case 'CFO'
            localExactFields(p,{'FrequencyHz','Multiplier'},'Stage'); localReal(p.FrequencyHz,'Stage');
            localMultiplier(p.Multiplier,[n 1],b.NumericClass);
            sample=interval.StartSample+(0:n-1).';
            expected=cast(exp(1j*2*pi*p.FrequencyHz/b.SampleRateHz*sample),char(b.NumericClass));
            assert(isequal(p.Multiplier,expected),'RF:TXLinearReferenceClock', ...
                'CFO multiplier must retain the original absolute sample phase origin.');
            token=localArrayHash(p.FrequencyHz);
        case 'Timing'
            localExactFields(p,{'DelaySamples'},'Stage'); localInteger(p.DelaySamples,0,'Stage');
            token=localArrayHash(p.DelaySamples);
        case 'SampleClockOffset'
            error('RF:TXLinearReferenceUnsupported','A sample-clock bridge is not implemented by this reference.');
        case 'CarrierPhase'
            localExactFields(p,{'Multiplier'},'Stage'); localComplexScalar(p.Multiplier,'Stage');
            assert(abs(abs(p.Multiplier)-1)<=8*eps('double'), ...
                'RF:TXLinearReferenceStage','Carrier phase must be the original unit-modulus scalar.');
            token=localArrayHash(p.Multiplier);
    end
    signatures(k)=names(k)+":executed:"+token;
end
expected=names(1:8); if s.CarrierPhase.Enabled, expected=names; end
assert(isequal(string(interval.StageOrder(:)).',expected)&&previous==outputHash, ...
    'RF:TXLinearReferenceStage','Original stage order or terminal RF output hash disagrees.');
digest=string(sixgr.util.sha256Hex(char(strjoin(signatures,'|'))));
end

function [y,state]=localFIR(x,taps,state)
memory=numel(taps)-1;
if isempty(state), state=zeros(memory,size(x,2),'like',x); end
assert(isequal(size(state),[memory size(x,2)]),'RF:TXLinearReferenceHistory','Independent model FIR history changed.');
% Explicit causal FIR in double precision, then original sample class. It
% implements the chosen linear model, not a second nonlinear PA execution.
extended=[double(state);double(x)]; y=complex(zeros(size(x)));
for k=1:numel(taps)
    y=y+taps(k).*extended(memory-k+2:memory-k+1+size(x,1),:);
end
if memory>0, state=cast(extended(end-memory+1:end,:), 'like',x);
else, state=zeros(0,size(x,2),'like',x); end
y=cast(y,'like',x);
end

function digest=localIntervalOperatorHash(s,staticSHA)
tokens=staticSHA;
if s.PhaseNoise.Enabled, tokens=tokens+":"+localArrayHash(s.PhaseNoise.Parameters.Trace.Multiplier); end
if s.CFO.Enabled, tokens=tokens+":"+localArrayHash(s.CFO.Parameters.Multiplier); end
digest=string(sixgr.util.sha256Hex(char(tokens)));
end
function localSamples(x,b)
assert(isfloat(x)&&ismatrix(x)&&~isempty(x)&&strcmp(class(x),char(b.NumericClass)) && ...
    size(x,2)==b.NumAntennas&&all(isfinite(x(:))), ...
    'RF:TXLinearReferenceSamples','Finite same-class physical-column samples are required.');
end
function localMultiplier(x,shape,numericClass)
assert(isfloat(x)&&strcmp(class(x),char(numericClass))&&isequal(size(x),shape) && ...
    all(isfinite(x(:))), 'RF:TXLinearReferenceStage','Original multiplier shape/class is required.');
end
function localFields(s,names,suffix)
assert(isstruct(s)&&isscalar(s)&&all(isfield(s,names)), ...
    ['RF:TXLinearReference' suffix],'Explicit scalar %s fields are required.',suffix);
end
function localExactFields(s,names,suffix)
localFields(s,names,suffix);
assert(isequal(sort(string(fieldnames(s))),sort(string(names(:)))), ...
    ['RF:TXLinearReference' suffix],'Unknown %s fields/operators are not supported.',suffix);
end
function value=localText(value,suffix)
assert((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)), ...
    ['RF:TXLinearReference' suffix],'Scalar text is required.');
value=string(value);
assert(~ismissing(value)&&strlength(strtrim(value))>0, ...
    ['RF:TXLinearReference' suffix],'Nonblank text is required.');
end
function localReal(v,suffix)
assert(isnumeric(v)&&isscalar(v)&&isreal(v)&&isfinite(v), ...
    ['RF:TXLinearReference' suffix],'Finite real scalar is required.');
end
function localInteger(v,minimum,suffix)
localReal(v,suffix);
assert(isa(v,'double')&&v>=minimum&&v<=flintmax&&v==fix(v), ...
    ['RF:TXLinearReference' suffix],'Exactly representable canonical double integer coordinate is required.');
end
function localComplexScalar(v,suffix)
assert(isnumeric(v)&&isscalar(v)&&isfinite(v), ...
    ['RF:TXLinearReference' suffix],'Finite complex scalar is required.');
end
function value=localHash(value)
value=lower(localText(value,'Samples'));
assert(~isempty(regexp(char(value),'^[0-9a-f]{64}$','once')), ...
    'RF:TXLinearReferenceSamples','A complete original SHA-256 is required.');
end
function digest=localRFHash(x)
digest=lower(string(sixgr.rf.waveformSHA256(x)));
end
function digest=localArrayHash(x)
digest=string(sixgr.phy.waveform.WaveformHash.runtimeArray(x));
end
