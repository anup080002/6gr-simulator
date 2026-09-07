classdef SharedWaveformPhysicalRuntime < handle
    % Physical processor for WaveformEventRuntime, not a scheduling policy.
    % Inputs are already composed, power-scaled PHYSICAL antenna samples.
    % TX RF once/node -> fading and loss once/link -> sum -> noise once/RX
    % -> RX RF once/node. No isolated-signal RF replay or noise-only rerun.
    % The main grant/access collectors still need chronological staging.
    properties (SetAccess=private)
        SampleRateHz (1,1) double
        NextSampleIndex (1,1) double
        ConfigurationEpoch (1,1) double
        Faulted (1,1) logical = false
    end
    properties (Access=private)
        Busy (1,1) logical = false
        Started (1,1) logical = false
        Transmitters = struct('ID',{},'RF',{})
        Receivers = struct('ID',{},'RF',{},'NoiseVariance',{},'NoiseSeed',{},'NoiseState',{},'NoiseReplay',{})
        Links = struct('ID',{},'TX',{},'RX',{},'State',{},'Config',{},'LossReplay',{},'TrailingIdleSamples',{})
    end
    methods
        function obj=SharedWaveformPhysicalRuntime(fs,first,epoch)
            validateattributes(fs,{'numeric'},{'real','scalar','finite','positive'});
            validateattributes(first,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            validateattributes(epoch,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            obj.SampleRateHz=double(fs); obj.NextSampleIndex=double(first);
            obj.ConfigurationEpoch=double(epoch);
        end

        function addTransmitter(obj,id,cfg,direction,nAnt,useLegacy)
            obj.assertRegistration(); id=obj.validID(id);
            obj.assertNewID(obj.Transmitters,id);
            rf=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction, ...
                obj.SampleRateHz,nAnt,obj.NextSampleIndex,obj.ConfigurationEpoch,useLegacy);
            obj.Transmitters(end+1)=struct('ID',id,'RF',rf);
        end

        function addReceiver(obj,id,cfg,direction,nAnt,useLegacy)
            obj.assertRegistration(); id=obj.validID(id);
            obj.assertNewID(obj.Receivers,id);
            rf=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx',direction, ...
                obj.SampleRateHz,nAnt,obj.NextSampleIndex,obj.ConfigurationEpoch,useLegacy);
            cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeCurrentDirection',upper(string(direction)));
            [~,ledger]=sixgr.link.applyWaveformImpairments(complex(zeros(1,nAnt)), ...
                cfg,obj.SampleRateHz,'ApplyRFChain',false);
            if string(ledger.NoiseOperatingMode)~="receiver_noise_figure_thermal_noise"
                error('WAVEFORM:ReceiverThermalNoiseAuthorityRequired', ...
                    'A physical shared receiver requires absolute thermal-noise/NF authority, not per-block requested SNR.');
            end
            variance=sixgr.link.resolveReceiverThermalNoiseVariance(ledger);
            validateattributes(variance,{'numeric'},{'real','scalar','finite','positive'});
            seed=sixgr.util.structGet(cfg,'run.seed',[]);
            validateattributes(seed,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            frequency=sixgr.util.structGet(cfg,'phy.fc_Hz',sixgr.util.structGet(cfg,'channel.fc_Hz',[]));
            validateattributes(frequency,{'numeric'},{'real','scalar','finite','positive'});
            identity=struct('ReceiverID',id,'Direction',rf.Chain.Direction,'RunSeed',seed, ...
                'CarrierFrequencyHz',frequency,'SampleRateHz',obj.SampleRateHz, ...
                'OriginSample',obj.NextSampleIndex,'Epoch',obj.ConfigurationEpoch, ...
                'Role','physical_receiver_thermal_noise');
            digest=sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(identity),'UTF-8')));
            noiseSeed=hex2dec(extractBefore(digest,9));
            obj.Receivers(end+1)=struct('ID',id,'RF',rf,'NoiseVariance',variance, ...
                'NoiseSeed',noiseSeed,'NoiseState',struct(),'NoiseReplay',ledger);
        end

        function addLink(obj,id,txID,rxID,state,cfg)
            obj.assertRegistration(); id=obj.validID(id); obj.assertNewID(obj.Links,id);
            tx=obj.findID(obj.Transmitters,txID); rx=obj.findID(obj.Receivers,rxID);
            obj.validateLink(state,cfg,tx,rx);
            for k=1:numel(obj.Links)
                prior=obj.Links(k).State;
                if string(prior.StateKey)==string(state.StateKey) || ...
                        (state.UseFading && prior.UseFading && isequal(prior.Obj,state.Obj))
                    error('WAVEFORM:DuplicatePhysicalChannelOwner', ...
                        'One retained channel cannot execute two overlapping links; compose its TX or retarget the TDD link.');
                end
            end
            ledger=obj.resolveLoss(cfg,tx,rx);
            obj.Links(end+1)=struct('ID',id,'TX',tx,'RX',rx,'State',state, ...
                'Config',cfg,'LossReplay',ledger,'TrailingIdleSamples',0);
        end

        function attach(obj,runtime,precision)
            obj.assertRegistration();
            assert(isa(runtime,'sixgr.phy.waveform.WaveformEventRuntime') && ...
                runtime.SampleRateHz==obj.SampleRateHz && runtime.NextSampleIndex==obj.NextSampleIndex, ...
                'WAVEFORM:PhysicalRuntimeClockMismatch','Event and physical owners must share one sample origin.');
            for k=1:numel(obj.Transmitters)
                node=obj.Transmitters(k);
                runtime.addTransmitter(node.ID,node.RF.NumAntennas,precision);
                runtime.addReceiver(node.ID+":tx",node.RF.NumAntennas);
            end
            for k=1:numel(obj.Receivers)
                node=obj.Receivers(k);
                runtime.addReceiver(node.ID+":pre_rf",node.RF.NumAntennas);
                runtime.addReceiver(node.ID+":post_rf",node.RF.NumAntennas);
            end
        end

        function retargetTDDLink(obj,id,txID,rxID,cfg)
            % Toolbox swap preserves fading, but resets the selected input
            % filter. A chronological owner may swap only after consuming
            % enough ACTUAL transmitted silence to drain the outgoing FIR.
            % Insufficient guard is a physical scheduling error, not a
            % reason to pad RX, discard a tail, clone or rewind the channel.
            obj.assertMutable(); k=obj.findID(obj.Links,id); link=obj.Links(k);
            tx=obj.findID(obj.Transmitters,txID); rx=obj.findID(obj.Receivers,rxID);
            if tx==link.TX && rx==link.RX
                error('WAVEFORM:TDDRetargetMustReverseEndpoints','Retarget requires the opposite link direction.');
            end
            state=link.State;
            if ~sixgr.channel.ChannelFactory.supportsDynamicRuntimeTDDReciprocity(cfg) || ...
                    ~logical(sixgr.util.structGet(state,'Meta.RuntimeTDDReciprocityExact',false))
                error('WAVEFORM:DynamicReciprocalStateRequired','Retarget only a declared shared dynamic reciprocal channel.');
            end
            if ~isequaln(sixgr.util.structGet(cfg,'channel',struct()), ...
                    sixgr.util.structGet(link.Config,'channel',struct()))
                error('WAVEFORM:TDDRetargetChannelChanged', ...
                    'A direction reversal cannot silently replace the channel profile, frequency or fading parameters.');
            end
            direction=string(obj.Transmitters(tx).RF.Chain.Direction);
            if direction==string(state.Direction) || direction~=string(obj.Receivers(rx).RF.Chain.Direction) || ...
                    obj.Transmitters(tx).RF.NumAntennas~=state.NumRxAnt || ...
                    obj.Receivers(rx).RF.NumAntennas~=state.NumTxAnt
                error('WAVEFORM:TDDRetargetEndpointMismatch','Reverse the physical TX/RX layout and direction.');
            end
            required=double(state.ChannelPadSamples)+1;
            if link.TrailingIdleSamples<required
                error('WAVEFORM:TDDChannelTailNotConsumed', ...
                    'Before direction reversal consume at least %.0f actual zero-input samples; observed %.0f.', ...
                    required,link.TrailingIdleSamples);
            end
            nextKey=sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,direction, ...
                'UEIndex',state.TargetUEIndex,'ServingCell',state.TargetServingCell);
            if string(sixgr.channel.ChannelFactory.runtimeChannelStateKey(cfg,nextKey))~=string(state.StateKey)
                error('WAVEFORM:TDDRetargetPhysicalLinkChanged', ...
                    'The reverse direction must retain the same actual endpoint pair and carrier identity.');
            end
            ledger=obj.resolveLoss(cfg,tx,rx);
            obj.Busy=true; unlock=onCleanup(@()obj.clearBusy()); %#ok<NASGU>
            try
                state.Direction=char(direction);
                state.LinkKey=char(nextKey);
                info=struct('OFDM',struct('SampleRate',obj.SampleRateHz));
                state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
                    state,cfg,complex(zeros(1,obj.Transmitters(tx).RF.NumAntennas)),info);
                obj.validateLink(state,cfg,tx,rx);
                obj.Links(k).State=state; obj.Links(k).TX=tx; obj.Links(k).RX=rx;
                obj.Links(k).Config=cfg; obj.Links(k).LossReplay=ledger;
                obj.Links(k).TrailingIdleSamples=0;
            catch cause
                obj.Faulted=true; rethrow(cause);
            end
        end

        function states=channelStates(obj)
            obj.assertMutable();
            states=cell(numel(obj.Links),1);
            for k=1:numel(obj.Links), states{k}=obj.Links(k).State; end
        end

        function [outputs,execution,nextState]=process(obj,inputs,first,stop,unusedState) %#ok<INUSD>
            obj.assertMutable();
            obj.validateInterval(inputs,first,stop);
            obj.Busy=true; obj.Started=true;
            unlock=onCleanup(@()obj.clearBusy()); %#ok<NASGU>
            try
                outputs=struct('ID',{},'Chunk',{});
                execution=struct('Source','composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf', ...
                    'ApproximationMode','none','StartSample',first,'EndSampleExclusive',stop, ...
                    'TX',struct('ID',{},'Replay',{}), ...
                    'Links',struct('ID',{},'TX',{},'RX',{},'Replay',{},'LossReplay',{}), ...
                    'RX',struct('ID',{},'Replay',{}));
                txSamples=cell(numel(obj.Transmitters),1);
                for k=1:numel(obj.Transmitters)
                    node=obj.Transmitters(k); index=obj.findID(inputs,node.ID);
                    actual=node.RF.apply(inputs(index).Chunk,obj.ConfigurationEpoch);
                    txSamples{k}=actual.Waveform;
                    outputs(end+1)=struct('ID',node.ID+":tx",'Chunk',actual.Chunk); %#ok<AGROW>
                    execution.TX(end+1)=struct('ID',node.ID,'Replay',actual.Replay);
                end
                sums=cell(numel(obj.Receivers),1);
                for k=1:numel(obj.Receivers)
                    sums{k}=complex(zeros(stop-first,obj.Receivers(k).RF.NumAntennas,'like',txSamples{1}));
                end
                for k=1:numel(obj.Links)
                    link=obj.Links(k); x=txSamples{link.TX};
                    [contribution,replay,state]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
                        link.State,x,'OutputSampleAlignment','continuous_raw_samples', ...
                        'InputSampleDomain','materialized_channel_ports');
                    if state.CurrentSampleIndex~=stop || ...
                            ~isequal(size(contribution),size(sums{link.RX}))
                        error('WAVEFORM:LinkOutputClockMismatch','Each link must return exactly the consumed physical interval.');
                    end
                    gain=double(link.LossReplay.AppliedLargeScaleAmplitudeGain);
                    contribution=contribution.*cast(gain,'like',contribution);
                    sums{link.RX}=sums{link.RX}+contribution;
                    lastNonzero=find(any(x~=0,2),1,'last');
                    if isempty(lastNonzero)
                        obj.Links(k).TrailingIdleSamples=link.TrailingIdleSamples+size(x,1);
                    else
                        obj.Links(k).TrailingIdleSamples=size(x,1)-lastNonzero;
                    end
                    obj.Links(k).State=state;
                    execution.Links(end+1)=struct('ID',link.ID,'TX',obj.Transmitters(link.TX).ID, ...
                        'RX',obj.Receivers(link.RX).ID,'Replay',replay,'LossReplay',link.LossReplay);
                end
                for k=1:numel(obj.Receivers)
                    node=obj.Receivers(k);
                    [pre,noiseState]=sixgr.link.addRuntimeComplexNoise(sums{k}, ...
                        node.NoiseVariance,node.NoiseSeed,first,node.NoiseState);
                    obj.Receivers(k).NoiseState=noiseState;
                    preChunk=sixgr.phy.waveform.WaveformChunk(pre,first);
                    actual=node.RF.apply(preChunk,obj.ConfigurationEpoch);
                    outputs(end+1)=struct('ID',node.ID+":pre_rf",'Chunk',preChunk); %#ok<AGROW>
                    outputs(end+1)=struct('ID',node.ID+":post_rf",'Chunk',actual.Chunk); %#ok<AGROW>
                    replay=actual.Replay;
                    replay.InjectedNoiseVariance=node.NoiseVariance;
                    replay.InjectedNoiseVarianceDomain='receiver_sample_waveform_pre_composite_front_end';
                    replay.NoiseVarianceSource='receiver_thermal_noise_plus_nf_absolute_sqrt_mW';
                    replay.NoiseStreamSeed=node.NoiseSeed;
                    replay.NoiseBandwidth_Hz=node.NoiseReplay.NoiseBandwidth_Hz;
                    replay.SampleNoiseVariance=NaN;
                    replay.SampleNoiseVarianceDomain='unavailable_requires_received_reference_estimation';
                    % Do not reinterpret a missing/time-varying AGC gain
                    % as unity or add ADC-error variance under an unproved
                    % independence assumption. Receivers must estimate the
                    % disturbance on their actual post-RF reference REs.
                    if double(replay.RFAppliedStageCount)==0
                        replay.SampleNoiseVariance=node.NoiseVariance;
                        replay.SampleNoiseVarianceDomain='receiver_sample_waveform_post_composite_front_end';
                    end
                    replay.CompositeReceiverFrontEndOrder= ...
                        'sum_power_scaled_physical_tx_then_tx_rf_then_per_link_fading_loss_then_sum_then_noise_then_rx_rf';
                    replay.PreRFMeanSamplePowerPerBranch_mW=mean(abs(double(pre)).^2,1);
                    replay.PreRFPowerMeasurementDefinition='total_time_sample_power_over_this_interval_not_SS_or_CSI_RSSI';
                    execution.RX(end+1)=struct('ID',node.ID,'Replay',replay);
                end
                obj.NextSampleIndex=stop; nextState=obj;
            catch cause
                obj.Faulted=true; rethrow(cause);
            end
        end
    end
    methods (Access=private)
        function validateInterval(obj,inputs,first,stop)
            validateattributes(stop,{'numeric'},{'real','scalar','finite','integer','>',obj.NextSampleIndex});
            if ~isequal(first,obj.NextSampleIndex) || isempty(obj.Transmitters) || isempty(obj.Receivers) || ...
                    ~isstruct(inputs) || ~all(isfield(inputs,{'ID','Chunk'})) || ...
                    numel(inputs)~=numel(obj.Transmitters) || ...
                    numel(unique(string({inputs.ID})))~=numel(inputs)
                error('WAVEFORM:PhysicalIntervalMismatch','Supply each composed transmitter once on the common clock.');
            end
            for k=1:numel(obj.Transmitters)
                index=obj.findID(inputs,obj.Transmitters(k).ID); chunk=inputs(index).Chunk;
                if ~isa(chunk,'sixgr.phy.waveform.WaveformChunk') || ~isscalar(chunk) || ...
                        chunk.StartSample~=first || ~isfloat(chunk.Samples) || ...
                        ~isequal(size(chunk.Samples),[stop-first obj.Transmitters(k).RF.NumAntennas]) || ...
                        any(~isfinite(chunk.Samples(:)))
                    error('WAVEFORM:PhysicalInputMismatch','Input clock, precision and physical antenna dimensions must agree.');
                end
                if k>1 && ~strcmp(class(chunk.Samples),class(inputs(1).Chunk.Samples))
                    error('WAVEFORM:PhysicalPrecisionMismatch','Physical sums must retain one declared sample precision.');
                end
            end
            for k=1:numel(obj.Links)
                if obj.Links(k).State.CurrentSampleIndex~=first
                    error('WAVEFORM:SharedChannelClockMismatch','A link was advanced outside its physical owner.');
                end
            end
        end

        function validateLink(obj,state,cfg,tx,rx)
            required={'Materialized','CurrentSampleIndex','SampleRate_Hz','NumTxAnt','NumRxAnt', ...
                'StateKey','Direction','UseFading','Obj','ChannelPadSamples'};
            if ~isstruct(state) || ~isscalar(state) || ~all(isfield(state,required)) || ...
                    ~state.Materialized || state.CurrentSampleIndex~=obj.NextSampleIndex || ...
                    state.SampleRate_Hz~=obj.SampleRateHz || strlength(string(state.StateKey))==0 || ...
                    state.NumTxAnt~=obj.Transmitters(tx).RF.NumAntennas || ...
                    state.NumRxAnt~=obj.Receivers(rx).RF.NumAntennas || ...
                    string(state.Direction)~=obj.Transmitters(tx).RF.Chain.Direction || ...
                    string(state.Direction)~=obj.Receivers(rx).RF.Chain.Direction
                error('WAVEFORM:PhysicalLinkAuthorityMismatch','Bind an actual materialized link at this clock and physical layout.');
            end
            if isfinite(sixgr.util.structGet(cfg,'channel.interferenceSIR_dB',NaN))
                error('WAVEFORM:RandomInterferenceProxyForbidden','Interference must be another physical transmitter/link, not a requested SIR draw.');
            end
        end

        function ledger=resolveLoss(obj,cfg,tx,rx)
            direction=obj.Transmitters(tx).RF.Chain.Direction;
            cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeCurrentDirection',direction);
            [~,ledger]=sixgr.link.applyWaveformImpairments( ...
                complex(zeros(1,obj.Receivers(rx).RF.NumAntennas)),cfg,obj.SampleRateHz,'ApplyRFChain',false);
            validateattributes(ledger.AppliedLargeScaleAmplitudeGain,{'numeric'},{'real','scalar','finite','positive'});
            if logical(sixgr.util.structGet(ledger,'FallbackUsedForPathloss',false))
                error('WAVEFORM:FallbackPhysicalPathlossForbidden','Shared physical execution cannot promote fallback pathloss.');
            end
        end

        function assertRegistration(obj)
            obj.assertMutable();
            if obj.Started, error('WAVEFORM:PhysicalLayoutFrozen','Declare physical nodes and links before consuming samples.'); end
        end
        function assertMutable(obj)
            if obj.Faulted, error('WAVEFORM:FaultedPhysicalRuntime','An advanced failed physical owner cannot be retried.'); end
            if obj.Busy, error('WAVEFORM:ReentrantPhysicalRuntime','Physical processing cannot mutate its own active interval.'); end
        end
        function clearBusy(obj), obj.Busy=false; end
    end
    methods (Static,Access=private)
        function id=validID(id)
            id=string(id);
            if ~isscalar(id)||ismissing(id)||strlength(strtrim(id))==0
                error('WAVEFORM:PhysicalIdentityRequired','Use an explicit scalar physical identity.');
            end
        end
        function index=findID(items,id)
            id=sixgr.truth.SharedWaveformPhysicalRuntime.validID(id);
            index=find(string({items.ID})==id,1);
            if isempty(index), error('WAVEFORM:UnknownPhysicalEndpoint','Unknown physical identity %s.',id); end
        end
        function assertNewID(items,id)
            if any(string({items.ID})==id)
                error('WAVEFORM:DuplicatePhysicalIdentity','Physical identity %s is already registered.',id);
            end
        end
    end
end
