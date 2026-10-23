classdef RFImpairmentStream < handle
    % One physical node endpoint, one absolute sample clock and RF epoch.
    % Uses the same ordered RF stages/config resolver as block execution,
    % but retains actual AGC, ADC, PA, oscillator and delay state. Thermal
    % noise belongs to the receiver owner and is not added a second time.
    properties (SetAccess=private)
        Chain struct
        Configuration struct
        ConfigurationEpoch (1,1) double
        SampleRateHz (1,1) double
        NumAntennas (1,1) double
        OriginSample (1,1) double
        NextSampleIndex (1,1) double
        Faulted (1,1) logical = false
        LastAGCTrace struct = struct()
        EvidenceRunId (1,1) string = ""
        EvidenceTrialId (1,1) string = "rf_stream"
    end
    properties (Access=private)
        Applying (1,1) logical = false
        InputClass (1,1) string = ""
        AGC
        ADCState struct = struct()
        ADCProfile struct = struct()
        DACProfile struct = struct()
        PAProfile struct = struct()
        PAState = []
        DelayState = []
        TXSignalDependency struct = struct()
    end
    methods
        function obj=RFImpairmentStream(cfg,endpoint,direction,fs,nAnt,first,epoch,useLegacy,evidenceIdentity)
            % Identity is reporting context, not a PHY or qualification flag.
            % Existing callers without a run owner retain an empty RunId;
            % the actual endpoint/sample interval still has explicit identity.
            if nargin<9
                evidenceIdentity=struct('RunId',"",'TrialId',"rf_stream");
            end
            if ~isstruct(evidenceIdentity)||~isscalar(evidenceIdentity)|| ...
                    ~isequal(sort(string(fieldnames(evidenceIdentity))),["RunId";"TrialId"])
                error('RF:InvalidExecutionIdentity','Supply only explicit RunId and TrialId.');
            end
            for name=["RunId","TrialId"]
                value=evidenceIdentity.(name);
                if ~(ischar(value)||isstring(value))||~isscalar(string(value))||ismissing(string(value))
                    error('RF:InvalidExecutionIdentity','RF identity must be scalar text.');
                end
            end
            if strlength(strtrim(string(evidenceIdentity.TrialId)))==0
                error('RF:InvalidExecutionIdentity','Declare the RF execution prefix.');
            end
            obj.EvidenceRunId=string(evidenceIdentity.RunId);
            obj.EvidenceTrialId=string(evidenceIdentity.TrialId);
            validateattributes(fs,{'numeric'},{'real','scalar','finite','positive'});
            validateattributes(nAnt,{'numeric'},{'real','scalar','finite','integer','positive'});
            validateattributes(first,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            validateattributes(epoch,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            endpoint=string(endpoint); direction=upper(string(direction));
            if ~isscalar(endpoint)||~any(endpoint==["tx","rx"])|| ...
                    ~isscalar(direction)||~any(direction==["DL","UL"])|| ...
                    ~islogical(useLegacy)||~isscalar(useLegacy)
                error('RF:InvalidStreamEndpoint','Declare one TX/RX endpoint, DL/UL direction and legacy-field ownership.');
            end
            resolved=sixgr.rf.applyRFImpairmentChain([],cfg,'SampleRateHz',fs, ...
                'Endpoint',endpoint,'Direction',direction,'UseLegacyGlobalConfig',useLegacy, ...
                'ResolveOnly',true);
            obj.Chain=resolved.Config;
            obj.Configuration=cfg; obj.ConfigurationEpoch=double(epoch);
            obj.SampleRateHz=double(fs); obj.NumAntennas=double(nAnt);
            obj.OriginSample=double(first); obj.NextSampleIndex=double(first);
            obj.validateStatefulStages();
            obj.TXSignalDependency=obj.resolveTXSignalDependency();
        end

        function out=apply(obj,chunk,expectedEpoch)
            rfProfileScope=sixgr.runtime.ExecutionStageProfiler.scope("RF", ...
                string(obj.Chain.Direction)+"_"+string(obj.Chain.Endpoint)); %#ok<NASGU>
            if obj.Faulted, error('RF:FaultedStream','A failed RF stream cannot be retried.'); end
            if obj.Applying, error('RF:ReentrantStream','An RF interval is already executing.'); end
            if ~isequal(double(expectedEpoch),obj.ConfigurationEpoch)
                error('RF:StateEpochMismatch','RF stream configuration epoch mismatch.');
            end
            if ~isa(chunk,'sixgr.phy.waveform.WaveformChunk')||~isscalar(chunk)|| ...
                    ~isequal(chunk.StartSample,obj.NextSampleIndex)
                error('RF:StreamClockDiscontinuity','Supply the next actual contiguous RF input chunk.');
            end
            x=chunk.Samples;
            if ~isfloat(x)||~ismatrix(x)||isempty(x)||size(x,2)~=obj.NumAntennas|| ...
                    any(~isfinite(x(:)))|| ...
                    (obj.InputClass~="" && obj.InputClass~=string(class(x)))
                error('RF:StreamInputMismatch','RF input must retain finite samples, precision and physical antenna layout.');
            end
            % RF is complex baseband even when an idle chunk contains only
            % zero real samples. Do not change ADC random-stream dimensions.
            x=complex(real(x),imag(x));
            obj.Applying=true;
            unlock=onCleanup(@()obj.clearApplying()); %#ok<NASGU>
            try
                obj.LastAGCTrace=struct();
                out=sixgr.rf.applyRFImpairmentChain(x,obj.Configuration, ...
                    'RunId',obj.EvidenceRunId, ...
                    'TrialId',obj.EvidenceTrialId+"/"+string(obj.Chain.Endpoint)+"/"+ ...
                        string(obj.Chain.Direction)+"/samples_"+string(obj.NextSampleIndex)+"_"+ ...
                        string(obj.NextSampleIndex+size(x,1)), ...
                    'SampleRateHz',obj.SampleRateHz,'Endpoint',obj.Chain.Endpoint, ...
                    'Direction',obj.Chain.Direction, ...
                    'MeasurementPoint',string(obj.Chain.Endpoint)+"_output", ...
                    'UseLegacyGlobalConfig',obj.Chain.UseLegacyGlobalConfig, ...
                    'StrictMutationRequired',false,'Stream',obj);
                if ~isequal(size(out.Waveform),size(x))||any(~isfinite(out.Waveform(:)))
                    error('RF:StreamOutputMismatch','RF output changed its physical sample clock or antenna dimensions.');
                end
                out.Chunk=sixgr.phy.waveform.WaveformChunk(out.Waveform,obj.NextSampleIndex);
                out.ExecutionStage="actual_retained_rf_stream";
                if obj.Chain.IncludeTx
                    dependency=obj.TXSignalDependency;
                    if isempty(fieldnames(dependency))
                        % Historical serialized owners did not retain this
                        % installation proof. Their PHY may continue; never
                        % manufacture a qualified memory receipt afterwards.
                        dependency=struct('ContractVersion',"sixgr.rf.executed_tx_signal_dependency/v1", ...
                            'Available',false,'Status',"unavailable_original_installation_receipt_missing", ...
                            'SampleRateHz',obj.SampleRateHz,'ConfigurationEpoch',obj.ConfigurationEpoch);
                    end
                    dependency.StartSample=obj.NextSampleIndex;
                    dependency.EndSampleExclusive=obj.NextSampleIndex+size(x,1);
                    dependency.OriginalInputChunkSHA256=string(chunk.SHA256);
                    dependency.RFInputWaveformSHA256=string(out.Replay.RFInputWaveformSHA256);
                    dependency.RFOutputWaveformSHA256=string(out.Replay.RFOutputWaveformSHA256);
                    dependency.RFStageOrder=string(out.Replay.RFStageOrder);
                    out.Replay.TXSignalDependency=dependency;
                end
                obj.NextSampleIndex=obj.NextSampleIndex+size(x,1);
                obj.InputClass=string(class(x));
            catch cause
                obj.Faulted=true;
                rethrow(cause);
            end
        end

        function assertApplying(obj)
            if ~obj.Applying || obj.Faulted
                error('RF:StreamOwnerRequired','Execute retained RF stages through the stream owner.');
            end
        end

        function y=applyCFO(obj,x,hz)
            obj.assertApplying();
            n=obj.NextSampleIndex+(0:size(x,1)-1).';
            y=x.*cast(exp(1j*2*pi*hz/obj.SampleRateHz*n),'like',x);
        end

        function y=applyTiming(obj,x,delay)
            obj.assertApplying();
            if isempty(obj.DelayState)
                obj.DelayState=zeros(delay,size(x,2),'like',x);
            end
            [y,obj.DelayState]=filter([zeros(1,delay) 1],1,x,obj.DelayState,1);
        end

        function y=applyAGC(obj,x)
            obj.assertApplying();
            [y,trace]=obj.AGC.apply(x,obj.Chain.RxADC.FullScale,obj.ConfigurationEpoch);
            trace.StartSample=trace.StartSample+obj.OriginSample;
            trace.EndSampleExclusive=trace.EndSampleExclusive+obj.OriginSample;
            assert(trace.StartSample==obj.NextSampleIndex && ...
                trace.EndSampleExclusive==obj.NextSampleIndex+size(x,1), ...
                'RF:AGCStreamClockMismatch','Translate the AGC relative clock to the physical origin exactly once.');
            trace.SampleCoordinateDomain="absolute_receiver_sample_clock";
            obj.LastAGCTrace=trace;
        end

        function result=applyADC(obj,x)
            obj.assertApplying();
            % Delay/filter/AGC arithmetic can drop MATLAB's complex-storage
            % flag for an all-zero startup interval. The hardware still
            % samples both I and Q; retain that declared ADC input domain.
            x=complex(real(x),imag(x));
            [result,obj.ADCState]=sixgr.rf.runtime.ADCModel.quantize(x,obj.ADCProfile,obj.ADCState);
        end

        function result=applyDAC(obj,x)
            obj.assertApplying();
            result=sixgr.rf.runtime.DACModel.convert(x,obj.DACProfile, ...
                obj.SampleRateHz,double(obj.DACProfile.Seed));
        end

        function y=applyPA(obj,x)
            obj.assertApplying();
            if lower(string(obj.PAProfile.Model))=="memory_polynomial"
                x=x.*cast(10.^(-double(obj.PAProfile.InputBackoff_dB)/20),'like',x);
                [y,obj.PAState]=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
                    x,obj.PAProfile.Coefficients,obj.PAProfile.Orders,obj.PAState);
            else
                [y,~]=sixgr.rf.runtime.PAProfile.apply(x,obj.PAProfile);
            end
        end
    end
    methods (Access=private)
        function clearApplying(obj), obj.Applying=false; end

        function d=resolveTXSignalDependency(obj)
            % This contract describes the installed, actually executed
            % streaming implementation, not nominal YAML delay spread.
            % IQ uses the canonical instantaneous alpha*x+beta*conj(x)
            % with literal zero DC offset; element mixing is instantaneous.
            % PN/CFO are multiplicative and introduce no signal memory.
            c=obj.Chain;
            d=struct();
            if ~c.IncludeTx, return; end
            memory=0; delay=0; zeroPreserving=true; model="disabled";
            paSHA=""; convention="disabled";
            if c.TxPA.Enabled
                model=lower(string(obj.PAProfile.Model));
                if model=="memory_polynomial", memory=double(obj.PAProfile.MemoryDepth)-1; end
                paSHA=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(obj.PAProfile),'UTF-8'))));
            end
            if c.TxTiming.Enabled, delay=double(c.TxTiming.TimingOffset_samples); end
            if c.TxDAC.Enabled
                convention=string(obj.DACProfile.Convention);
                zeroPreserving=convention=="signed_midtread" && ...
                    obj.DACProfile.DitherRMS==0 && obj.DACProfile.ApertureJitter_s==0;
            end
            d=struct('ContractVersion',"sixgr.rf.executed_tx_signal_dependency/v1", ...
                'Available',zeroPreserving,'Status',"installed_zero_preserving_finite_signal_memory", ...
                'SampleRateHz',obj.SampleRateHz,'ConfigurationEpoch',obj.ConfigurationEpoch, ...
                'Endpoint',string(c.Endpoint),'Direction',string(c.Direction), ...
                'MemorySamples',memory,'DelaySamples',delay, ...
                'HistoryOriginSample',obj.OriginSample,'ZeroInputHistoryAtOrigin',true, ...
                'ZeroPreserving',zeroPreserving,'AdditiveTXOutput',~zeroPreserving, ...
                'PAModel',model,'PAProfileSHA256',paSHA,'DACConvention',convention, ...
                'IQDCOffset',0,'SignalMemorySource',"installed_PA_memory_and_retained_integer_delay", ...
                'AdditionalRFExecutions',0,'DependencyScope',"signal_dependency_not_oscillator_state");
            if ~zeroPreserving, d.Status="unavailable_TX_quantizer_zero_input_not_zero"; end
        end

        function validateStatefulStages(obj)
            c=obj.Chain;
            if c.IncludeTx, prefix="Tx"; else, prefix="Rx"; end
            timing=c.(prefix+"Timing");
            delay=timing.TimingOffset_samples;
            if timing.Enabled && (delay<0 || delay~=fix(delay))
                error('RF:StreamingFractionalTimingRequiresClockBridge', ...
                    'Fractional/advancing timing needs an explicit clock bridge and latency; finite-buffer interpolation is forbidden.');
            end
            if c.(prefix+"SampleClockOffset").Enabled
                error('RF:StreamingSampleClockRequiresClockBridge', ...
                    'SCO needs a retained resampling clock/latency contract; per-block PreserveLength is forbidden.');
            end
            pn=c.(prefix+"PhaseNoise");
            if pn.Enabled && (pn.Backend~="sixgr_rf_runtime_phase_noise_process" || ...
                    strlength(string(pn.Model.ApproximationReason))>0)
                error('RF:StreamingPhaseNoiseProfileRequired', ...
                    'Retained phase noise requires the canonical explicit runtime mask profile.');
            end
            if pn.Enabled && ~isequal(double(sixgr.util.structGet( ...
                    obj.Configuration,'rf.configurationEpoch',NaN)),obj.ConfigurationEpoch)
                error('RF:StateEpochMismatch','The oscillator and retained RF owner must share the explicit configuration epoch.');
            end
            if c.IncludeTx && c.TxPA.Enabled
                [obj.PAProfile,canonical]=sixgr.rf.runtime.PAProfile.fromConfiguration(obj.Configuration,c.Direction);
                if ~canonical || ~any(lower(string(obj.PAProfile.Model))==["rapp","saleh","memory_polynomial"])
                    error('RF:StreamingPAProfileRequired','Use an explicit streaming-supported calibrated PA profile.');
                end
                if lower(string(obj.PAProfile.Model))=="memory_polynomial"
                    p=obj.PAProfile;
                    if isvector(p.Coefficients) && p.MemoryDepth==1 && numel(p.Coefficients)==numel(p.Orders)
                        obj.PAProfile.Coefficients=p.Coefficients(:);
                    end
                    if ~isscalar(p.MemoryDepth) || ~isfinite(p.MemoryDepth) || p.MemoryDepth<1 || ...
                            p.MemoryDepth~=fix(p.MemoryDepth) || ...
                            size(obj.PAProfile.Coefficients,1)~=numel(p.Orders) || ...
                            size(obj.PAProfile.Coefficients,2)~=p.MemoryDepth
                        error('RF:PAProfileDimensionMismatch','Retained PA coefficients must match declared orders and memory depth.');
                    end
                end
            end
            if c.IncludeTx && c.TxDAC.Enabled
                if c.TxDAC.DitherEnabled || c.TxDAC.DitherRMS~=0 || ...
                        c.TxDAC.ApertureJitter_s~=0
                    error('RF:StreamingDACRandomStateRequired', ...
                        ['Retained DAC dither/jitter needs a persistent sample-indexed random state. ' ...
                         'Use the qualified deterministic quantizer profile for this runtime.']);
                end
                obj.DACProfile=struct('Bits',c.TxDAC.Bits, ...
                    'FullScale',c.TxDAC.FullScale, ...
                    'Convention',c.TxDAC.Convention, ...
                    'DitherRMS',c.TxDAC.DitherRMS, ...
                    'ApertureJitter_s',c.TxDAC.ApertureJitter_s, ...
                    'ProfileID',c.TxDAC.ProfileID, ...
                    'Version',c.TxDAC.Version, ...
                    'Seed',double(sixgr.util.structGet( ...
                    obj.Configuration,'run.seed',1)));
            end
            if c.IncludeRx && c.RxAGC.Enabled
                raw=sixgr.util.structGet(obj.Configuration,'rf.frontend.receiver.agc.stream_profile',struct());
                required={'control_model','attack','release','hold_samples','update_period_samples'};
                if ~isstruct(raw)||~isscalar(raw)||~all(isfield(raw,required))|| ...
                        string(raw.control_model)~="causal_windowed_joint_rms_attack_hold_release"
                    error('RF:ImplicitAGCForbidden','rf_frontend.receiver.agc.stream_profile must explicitly configure causal AGC.');
                end
                profile=struct('TargetRMS',c.RxAGC.TargetRMS,'MinGain_dB',c.RxAGC.MinGain_dB, ...
                    'MaxGain_dB',c.RxAGC.MaxGain_dB,'Attack',raw.attack,'Release',raw.release, ...
                    'HoldSamples',raw.hold_samples,'UpdatePeriodSamples',raw.update_period_samples);
                if isfield(raw,'overload_guard'), profile.OverloadGuard=raw.overload_guard; end
                obj.AGC=sixgr.rf.runtime.AGCState(profile,obj.ConfigurationEpoch);
            end
            if c.IncludeRx && c.RxADC.Enabled
                obj.ADCProfile=c.RxADC.Profile;
            end
        end
    end
end
