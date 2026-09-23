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
        ScoringPlanes = struct('ID',{},'LinkID',{},'RX',{})
        ChannelReferenceRequests = struct('LinkID',{},'RX',{},'Start',{},'End',{})
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
            noiseMode=lower(strtrim(string(ledger.NoiseOperatingMode)));
            if noiseMode=="receiver_noise_figure_thermal_noise"
                variance=sixgr.link.resolveReceiverThermalNoiseVariance(ledger);
                ledger.SharedNoiseCalibrationSource= ...
                    'receiver_thermal_noise_psd_times_sample_bandwidth';
            elseif noiseMode=="standalone_awgn_snr_argument"
                carrier=sixgr.phy.grid.makeCarrier(cfg);
                calibration=sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier);
                requested=double(sixgr.truth.resolveWaveformOperatingPointMetadata(cfg));
                [signalEnergy,referencePolicy]=sixgr.link.resolveAWGNReferenceEnergy(cfg);
                gridVariance=signalEnergy*10^(-requested/10);
                variance=gridVariance/double(calibration.SampleToGridNoiseVarianceGain);
                ledger.ConfiguredSNR_dB=requested;
                ledger.RequestedAWGNReferenceSNR_dB=requested;
                ledger.SignalEnergyPerOccupiedRE=signalEnergy;
                ledger.GridNoiseVariance=gridVariance;
                ledger.SampleNoiseVariance=variance;
                ledger.SampleToGridNoiseVarianceGain=double(calibration.SampleToGridNoiseVarianceGain);
                ledger.SNRReferencePlane='occupied_resource_grid_re_pre_equalization';
                ledger.SharedNoiseCalibrationSource=referencePolicy.CalibrationSource;
                ledger.AWGNReferenceEnergySource=referencePolicy.EnergySource;
                ledger.NoiseVarianceSource=referencePolicy.NoiseVarianceSource;
                ledger.ThermalSampleNoiseBandwidth_Hz=NaN;
                ledger.ThermalNoisePSD_mWPerHz=NaN;
            else
                error('WAVEFORM:SharedNoiseOperatingModeUnsupported', ...
                    'Shared waveform execution requires thermal-noise or fixed occupied-RE Es/N0 authority; got %s.',noiseMode);
            end
            validateattributes(variance,{'numeric'},{'real','scalar','finite','positive'});
            seed=sixgr.util.structGet(cfg,'run.seed',[]);
            validateattributes(seed,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            frequency=sixgr.util.structGet(cfg,'phy.fc_Hz',sixgr.util.structGet(cfg,'channel.fc_Hz',[]));
            validateattributes(frequency,{'numeric'},{'real','scalar','finite','positive'});
            identity=struct('ReceiverID',id,'Direction',rf.Chain.Direction,'RunSeed',seed, ...
                'CarrierFrequencyHz',frequency,'SampleRateHz',obj.SampleRateHz, ...
                'OriginSample',obj.NextSampleIndex,'Epoch',obj.ConfigurationEpoch, ...
                'Role','physical_receiver_noise','NoiseOperatingMode',char(noiseMode), ...
                'ConfiguredSNR_dB',double(sixgr.util.structGet(ledger, ...
                    'RequestedAWGNReferenceSNR_dB',NaN)));
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
            identity=sixgr.channel.IdentityAWGNRuntime.enabled(cfg) && ...
                sixgr.channel.IdentityAWGNRuntime.isState(state) && ...
                sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD";
            if (~identity && ~sixgr.channel.ChannelFactory.supportsDynamicRuntimeTDDReciprocity(cfg)) || ...
                    ~logical(sixgr.util.structGet(state,'Meta.RuntimeTDDReciprocityExact',false))
                error('WAVEFORM:DynamicReciprocalStateRequired','Retarget only a declared shared dynamic reciprocal channel.');
            end
            priorChannel=sixgr.util.structGet(link.Config,'channel',struct());
            nextChannel=sixgr.util.structGet(cfg,'channel',struct());
            if identity
                priorChannel=sixgr.channel.IdentityAWGNRuntime.physicalContract(link.Config);
                nextChannel=sixgr.channel.IdentityAWGNRuntime.physicalContract(cfg);
            end
            if ~isequaln(nextChannel,priorChannel)
                changed=localDifferingTopLevelFields(priorChannel,nextChannel);
                error('WAVEFORM:TDDRetargetChannelChanged', ...
                    ['A direction reversal cannot silently replace the channel profile, frequency or fading parameters. ' ...
                    'Differing channel fields: %s.'],strjoin(changed,','));
            end
            direction=string(obj.Transmitters(tx).RF.Chain.Direction);
            if direction==string(state.Direction) || direction~=string(obj.Receivers(rx).RF.Chain.Direction) || ...
                    obj.Transmitters(tx).RF.NumAntennas~=state.NumRxAnt || ...
                    obj.Receivers(rx).RF.NumAntennas~=state.NumTxAnt
                error('WAVEFORM:TDDRetargetEndpointMismatch','Reverse the physical TX/RX layout and direction.');
            end
            required=double(state.ChannelPadSamples)+1;
            if identity, required=0; end % No FIR memory in the executed y=x operator.
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
                if identity
                    state.Meta.RuntimeTDDReciprocityDirection=direction;
                end
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

        function id=registerLinkScoringPlane(obj,runtime,linkID,receiverID)
            % Observe the already executed link contribution. This plane
            % never feeds an RF chain, receiver estimator or transmission.
            obj.assertMutable();
            assert(isa(runtime,'sixgr.phy.waveform.WaveformEventRuntime') && ...
                runtime.SampleRateHz==obj.SampleRateHz && ...
                runtime.NextSampleIndex==obj.NextSampleIndex && isequal(runtime.ProcessorState,obj), ...
                'WAVEFORM:ScoringPlaneClockMismatch','Register scoring with the actual physical clock owner.');
            obj.findID(obj.Links,linkID);
            rx=obj.findID(obj.Receivers,receiverID);
            id=string(linkID)+":"+string(receiverID)+":desired_pre_noise";
            if any(string({obj.ScoringPlanes.ID})==id), return; end
            runtime.addReceiver(id,obj.Receivers(rx).RF.NumAntennas);
            obj.ScoringPlanes(end+1)=struct('ID',id,'LinkID',string(linkID),'RX',rx);
        end

        function requestLinkChannelReference(obj,runtime,linkID,receiverID,first,stop)
            obj.assertMutable();
            assert(isa(runtime,'sixgr.phy.waveform.WaveformEventRuntime') && ...
                isequal(runtime.ProcessorState,obj) && runtime.NextSampleIndex==obj.NextSampleIndex, ...
                'WAVEFORM:ScoringPlaneClockMismatch','Request evidence from the authoritative clock owner.');
            obj.findID(obj.Links,linkID); rx=obj.findID(obj.Receivers,receiverID);
            validateattributes(first,{'numeric'},{'scalar','real','finite','integer','>=',obj.NextSampleIndex});
            validateattributes(stop,{'numeric'},{'scalar','real','finite','integer','>',first});
            % Multiple consumers of one link/window share one capture, not
            % duplicated coefficient tensors. Distinct overlapping windows
            % remain separately scoped to their own receiver observations.
            requests=obj.ChannelReferenceRequests;
            if any(string({requests.LinkID})==string(linkID) & [requests.RX]==rx & ...
                    [requests.Start]==first & [requests.End]==stop)
                return;
            end
            obj.ChannelReferenceRequests(end+1)=struct('LinkID',string(linkID),'RX',rx,'Start',first,'End',stop);
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
                    'RX',struct('ID',{},'Replay',{}), ...
                    'ScoringPlanes',struct('ID',{},'LinkID',{},'TX',{},'RX',{},'Active',{},'Source',{}), ...
                    'ChannelReferences',struct('LinkID',{},'TX',{},'RX',{},'Reference',{}));
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
                contributions=cell(numel(obj.Links),1);
                for k=1:numel(obj.Links)
                    link=obj.Links(k); x=txSamples{link.TX};
                    requests=obj.ChannelReferenceRequests;
                    hits=find(string({requests.LinkID})==link.ID & [requests.RX]==link.RX & ...
                        [requests.Start]<stop & [requests.End]>first);
                    [contribution,replay,state,reference]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
                        link.State,x,'OutputSampleAlignment','continuous_raw_samples', ...
                        'InputSampleDomain','materialized_channel_ports','CaptureChannelReference',~isempty(hits));
                    for h=hits
                        request=requests(h); bounded=reference;
                        bounded.ObservationStartSample=request.Start;
                        bounded.ObservationEndSampleExclusive=request.End;
                        bounded.StartSample=max(first,request.Start);
                        bounded.EndSampleExclusive=min(stop,request.End);
                        indices=(bounded.StartSample-first+1):(bounded.EndSampleExclusive-first);
                        bounded.PathGains=reference.PathGains(indices,:,:,:);
                        bounded.SampleTimes_s=reference.SampleTimes_s(indices);
                        bounded.ExecutionStartSample=first; bounded.ExecutionEndSampleExclusive=stop;
                        execution.ChannelReferences(end+1)=struct('LinkID',link.ID, ...
                            'TX',obj.Transmitters(link.TX).ID,'RX',obj.Receivers(link.RX).ID, ...
                            'Reference',bounded); %#ok<AGROW>
                    end
                    if state.CurrentSampleIndex~=stop || ...
                            ~isequal(size(contribution),size(sums{link.RX}))
                        error('WAVEFORM:LinkOutputClockMismatch','Each link must return exactly the consumed physical interval.');
                    end
                    gain=double(link.LossReplay.AppliedLargeScaleAmplitudeGain);
                    beforeGain=contribution;
                    contribution=contribution.*cast(gain,'like',contribution);
                    lossReplay=link.LossReplay;
                    lossReplay.GainStageMeasurement=sixgr.truth.measureWaveformGainEnergy(beforeGain,contribution);
                    contributions{k}=contribution;
                    sums{link.RX}=sums{link.RX}+contribution;
                    lastNonzero=find(any(x~=0,2),1,'last');
                    if isempty(lastNonzero)
                        obj.Links(k).TrailingIdleSamples=link.TrailingIdleSamples+size(x,1);
                    else
                        obj.Links(k).TrailingIdleSamples=size(x,1)-lastNonzero;
                    end
                    obj.Links(k).State=state;
                    execution.Links(end+1)=struct('ID',link.ID,'TX',obj.Transmitters(link.TX).ID, ...
                        'RX',obj.Receivers(link.RX).ID,'Replay',replay,'LossReplay',lossReplay);
                end
                for plane=obj.ScoringPlanes
                    k=obj.findID(obj.Links,plane.LinkID); link=obj.Links(k);
                    active=link.RX==plane.RX;
                    if active
                        samples=contributions{k};
                    else
                        % The reciprocal TDD link currently points at the
                        % opposite endpoint: its contribution HERE is zero.
                        % This is not padding a missing receiver observation.
                        samples=zeros(size(sums{plane.RX}),'like',sums{plane.RX});
                    end
                    outputs(end+1)=struct('ID',plane.ID, ...
                        'Chunk',sixgr.phy.waveform.WaveformChunk(samples,first)); %#ok<AGROW>
                    execution.ScoringPlanes(end+1)=struct('ID',plane.ID,'LinkID',plane.LinkID, ...
                        'TX',obj.Transmitters(link.TX).ID,'RX',obj.Receivers(plane.RX).ID, ...
                        'Active',active,'Source',"actual_link_contribution_after_tx_rf_channel_loss_before_sum_noise_rx_rf");
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
                    if lower(strtrim(string(node.NoiseReplay.NoiseOperatingMode)))== ...
                            "standalone_awgn_snr_argument"
                        replay.NoiseVarianceSource=node.NoiseReplay.NoiseVarianceSource;
                    else
                        replay.NoiseVarianceSource= ...
                            'receiver_thermal_noise_plus_nf_absolute_sqrt_mW';
                    end
                    replay.NoiseStreamSeed=node.NoiseSeed;
                    replay.NoiseBandwidth_Hz=node.NoiseReplay.NoiseBandwidth_Hz;
                    replay.NoiseOperatingMode=node.NoiseReplay.NoiseOperatingMode;
                    replay.ThermalSampleNoiseBandwidth_Hz=node.NoiseReplay.ThermalSampleNoiseBandwidth_Hz;
                    replay.ThermalNoisePSD_mWPerHz=node.NoiseReplay.ThermalNoisePSD_mWPerHz;
                    replay.RequestedAWGNReferenceSNR_dB=double(sixgr.util.structGet( ...
                        node.NoiseReplay,'RequestedAWGNReferenceSNR_dB',NaN));
                    replay.SignalEnergyPerOccupiedRE=double(sixgr.util.structGet( ...
                        node.NoiseReplay,'SignalEnergyPerOccupiedRE',NaN));
                    replay.AWGNReferenceEnergySource=string(sixgr.util.structGet( ...
                        node.NoiseReplay,'AWGNReferenceEnergySource','not_applicable_thermal_noise'));
                    replay.GridNoiseVariance=double(sixgr.util.structGet( ...
                        node.NoiseReplay,'GridNoiseVariance',NaN));
                    replay.ReferenceAWGNGridNoiseVariance=replay.GridNoiseVariance;
                    replay.ReferenceAWGNSampleNoiseVariance=double(sixgr.util.structGet( ...
                        node.NoiseReplay,'SampleNoiseVariance',NaN));
                    replay.SampleToGridNoiseVarianceGain=double(sixgr.util.structGet( ...
                        node.NoiseReplay,'SampleToGridNoiseVarianceGain',NaN));
                    replay.AppliedAWGNSNR_dB=NaN;
                    replay.AppliedAWGNSNRSource="not_applicable_thermal_noise";
                    replay.AppliedAWGNSNRValueRole="applied_noise_reference_not_measured_receiver_sinr";
                    if lower(strtrim(string(node.NoiseReplay.NoiseOperatingMode)))== ...
                            "standalone_awgn_snr_argument"
                        % Use the variance passed to the physical noise
                        % generator, not a copied configured-SNR label.
                        % This is the pre-front-end injection reference;
                        % channel loss, interference and RX RF can change
                        % receiver-measured SINR without changing it.
                        appliedGridVariance=node.NoiseVariance* ...
                            replay.SampleToGridNoiseVarianceGain;
                        validateattributes(appliedGridVariance,{'numeric'}, ...
                            {'real','scalar','finite','positive'});
                        validateattributes(replay.SignalEnergyPerOccupiedRE, ...
                            {'numeric'},{'real','scalar','finite','positive'});
                        replay.AppliedAWGNSNR_dB=10*log10( ...
                            replay.SignalEnergyPerOccupiedRE/appliedGridVariance);
                        if ~isfinite(replay.RequestedAWGNReferenceSNR_dB) || ...
                                abs(replay.AppliedAWGNSNR_dB- ...
                                replay.RequestedAWGNReferenceSNR_dB)>1e-10
                            error('WAVEFORM:SharedAppliedAWGNSNRMismatch', ...
                                'Executed noise reference %.12g dB differs from requested %.12g dB.', ...
                                replay.AppliedAWGNSNR_dB,replay.RequestedAWGNReferenceSNR_dB);
                        end
                        replay.AppliedAWGNSNRSource= ...
                            "executed_sample_noise_variance_and_occupied_re_energy";
                    end
                    replay.SharedNoiseCalibrationSource=string(sixgr.util.structGet( ...
                        node.NoiseReplay,'SharedNoiseCalibrationSource',''));
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
                obj.ChannelReferenceRequests=obj.ChannelReferenceRequests([obj.ChannelReferenceRequests.End]>stop);
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
            if sixgr.channel.IdentityAWGNRuntime.enabled(cfg)
                assert(ledger.AppliedLargeScaleAmplitudeGain==1, ...
                    'WAVEFORM:IdentityAWGNUnexpectedLoss', ...
                    'The explicit identity-AWGN lab channel must not acquire hidden large-scale gain or loss.');
            end
            % Retain the geometry supplied to this executed link, not a
            % later report-time config snapshot. These are physical-model
            % inputs, not receiver-estimated ranges.
            d2=double(sixgr.util.structGet(cfg,'channel.distance2D_m',NaN));
            d3=double(sixgr.util.structGet(cfg,'channel.distance3D_m',NaN));
            ledger.RuntimeGeometryDistance2D_m=NaN;
            ledger.RuntimeGeometryDistance3D_m=NaN;
            ledger.RuntimeGeometrySource='unavailable_executed_link_geometry';
            if isscalar(d2) && isscalar(d3) && isfinite(d2) && isfinite(d3)
                assert(d2>=0 && d3>=d2,'WAVEFORM:InvalidPhysicalLinkGeometry', ...
                    'Executed geometry requires 0 <= horizontal distance <= 3-D distance.');
                ledger.RuntimeGeometryDistance2D_m=d2;
                ledger.RuntimeGeometryDistance3D_m=d3;
                ledger.RuntimeGeometrySource='executed_link_geometry_inputs_not_receiver_measurement';
            end
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

function changed=localDifferingTopLevelFields(a,b)
names=union(string(fieldnames(a)),string(fieldnames(b)));
changed=strings(0,1);
for k=1:numel(names)
    if ~isequaln(sixgr.util.structGet(a,names(k),[]), ...
            sixgr.util.structGet(b,names(k),[]))
        changed(end+1,1)=names(k); %#ok<AGROW>
    end
end
if isempty(changed), changed="unknown_nested_or_type_difference"; end
end
