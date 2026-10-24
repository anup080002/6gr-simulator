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
        Transmitters = struct('ID',{},'RF',{},'Radiation',{})
        Receivers = struct('ID',{},'RF',{},'NoiseVariance',{},'NoiseSeed',{},'NoiseState',{},'NoiseReplay',{},'AdditiveEVM',{},'EVMState',{},'BranchLayout',{},'ElementLayout',{})
        Links = struct('ID',{},'TX',{},'RX',{},'State',{},'Config',{},'LossReplay',{},'TrailingIdleSamples',{},'TXRadiationInstallation',{},'SignalDependency',{})
        ScoringPlanes = struct('ID',{},'LinkID',{},'RX',{})
        ChannelReferenceRequests = struct('LinkID',{},'RX',{},'Start',{},'End',{})
        RFExecutionLedger = []
        % Separate diagnostic VALUE states. Historical owners remain empty;
        % never invent an aggregate model's missing original input history.
        TXLinearReferences = struct('ID',{},'Binding',{})
        LinearChannels = struct('ID',{},'Model',{})
        CSIRSReferenceParents = struct('TX',{},'Parent',{})
        CSIRSReferencePlanes = struct('ID',{},'LinkID',{},'TX',{},'RX',{},'Component',{}, ...
            'Model',{},'RetireAfterSample',{})
        CSIModelPlanes = struct('ID',{},'ResidualID',{},'LinkID',{},'RX',{})
        PendingReferenceCommit = []
        ReferenceEvent = []
        ReferenceLinkEndpoints = struct('LinkID',{},'Direction',{},'TX',{},'RX',{})
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
            assert(isempty(obj.RFExecutionLedger),'sixgr:truth:RFExecutionInventoryFrozen', ...
                'Register all RF endpoints before enabling their execution ledger.');
            obj.assertNewID(obj.Transmitters,id);
            rf=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction, ...
                obj.SampleRateHz,nAnt,obj.NextSampleIndex,obj.ConfigurationEpoch,useLegacy);
            [enabled,array,metadata,policy,reference]=localRadiationInstallation(cfg,direction);
            binding=[];
            if enabled
                binding=sixgr.rf.InstalledTXRadiationBinding.freeze(array,metadata,rf,id,policy,reference);
            end
            linearPolicy=sixgr.rf.InstalledTXLinearReference.resolvePolicy(cfg);
            if ~isempty(linearPolicy)&&linearPolicy.Enabled
                installed=sixgr.rf.InstalledTXLinearReference.freeze(rf,id,linearPolicy);
                obj.TXLinearReferences(end+1)=struct('ID',id,'Binding',installed);
            end
            obj.Transmitters(end+1)=struct('ID',id,'RF',rf,'Radiation',binding);
        end

        function validateTransmitterInstallation(obj,id,cfg,direction,nAnt)
            k=obj.findID(obj.Transmitters,id); node=obj.Transmitters(k);
            linearPolicy=sixgr.rf.InstalledTXLinearReference.resolvePolicy(cfg);
            wanted=~isempty(linearPolicy)&&linearPolicy.Enabled;
            referenceIndex=find(string({obj.TXLinearReferences.ID})==string(id));
            assert(wanted==~isempty(referenceIndex),'RF:TXLinearReferenceInstallationChanged', ...
                'A registered TX owner cannot enable or disable a reference model after registration.');
            if wanted, obj.TXLinearReferences(referenceIndex).Binding.validatePolicy(cfg); end
            [enabled,array,metadata,policy,reference]=localRadiationInstallation(cfg,direction);
            retained=isfield(node,'Radiation')&&~isempty(node.Radiation);
            assert(enabled==retained&&string(direction)==string(node.RF.Chain.Direction)&& ...
                nAnt==node.RF.NumAntennas,'RF:TXRadiationInstallationChanged', ...
                'A shared transmitter cannot change its installed radiation policy or direction.');
            if enabled
                assert(isequaln(sixgr.util.structGet(cfg,'rf',struct()), ...
                    sixgr.util.structGet(node.RF.Configuration,'rf',struct())), ...
                    'RF:TXRadiationInstallationChanged','The retained TX RF policy cannot be replaced through a link.');
                node.Radiation.validateInstallation(array,metadata,policy,reference);
            end
        end

        function addReceiver(obj,id,cfg,direction,nAnt,useLegacy)
            obj.assertRegistration(); id=obj.validID(id);
            assert(isempty(obj.RFExecutionLedger),'sixgr:truth:RFExecutionInventoryFrozen', ...
                'Register all RF endpoints before enabling their execution ledger.');
            obj.assertNewID(obj.Receivers,id);
            branchLayout=sixgr.rf.resolveReceiveBranchLayout( ...
                cfg,id,direction,nAnt,obj.SampleRateHz,obj.ConfigurationEpoch);
            % Reuse the original validated native installation even when
            % no RF-type reference exists. This separate scope is internal
            % element columns, never an invented qualified RF branch.
            elementLayout=sixgr.rf.ReceiveElementLayout.freezeInstallation(branchLayout.Installation);
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
            elseif noiseMode=="absolute_reference_esn0"
                variance=sixgr.link.resolveAbsoluteReferenceNoiseVariance(ledger);
                ledger.SharedNoiseCalibrationSource=ledger.AbsoluteReferenceNoise.Source;
                ledger.NoiseVarianceSource='absolute_nominal_reference_PSD_times_actual_sample_rate_sqrt_mW';
                ledger.SampleNoiseVariance=variance;
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
                    'Shared waveform execution requires explicit thermal, absolute-reference or fixed occupied-RE noise authority; got %s.',noiseMode);
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
            if noiseMode=="absolute_reference_esn0"
                identity.ReferenceContractSHA256=ledger.AbsoluteReferenceNoise.ReferenceContractSHA256;
            end
            digest=sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(identity),'UTF-8')));
            noiseSeed=hex2dec(extractBefore(digest,9));
            evm=sixgr.util.structGet(cfg,'rf.rx.additiveEVMStudy',struct('enabled',false));
            if logical(evm.enabled)
                assert(all(isfield(evm,["percent","seed","reference","normalization","observationSamples"])) && ...
                    string(evm.reference)=="pre_receiver_noise_physical_signal_per_chain" && ...
                    string(evm.normalization)=="complete_observation_mean", ...
                    'RF:AdditiveEVMReference','Declare the physical pre-noise signal reference for receiver EVM.');
                validateattributes(evm.percent,{'numeric'},{'scalar','real','finite','positive'});
                validateattributes(evm.seed,{'numeric'},{'scalar','real','integer','nonnegative','<=',2^32-1});
                validateattributes(evm.observationSamples,{'numeric'},{'scalar','real','integer','positive','finite'});
            end
            obj.Receivers(end+1)=struct('ID',id,'RF',rf,'NoiseVariance',variance, ...
                'NoiseSeed',noiseSeed,'NoiseState',struct(),'NoiseReplay',ledger, ...
                'AdditiveEVM',evm,'EVMState',struct(),'BranchLayout',branchLayout,'ElementLayout',elementLayout);
        end

        function binding=receiveBranchLayout(obj,id)
            % Immutable installation only; actual intervals are in RX replay.
            k=obj.findID(obj.Receivers,id);
            binding=obj.Receivers(k).BranchLayout;
        end

        function binding=receiveElementLayout(obj,id)
            k=obj.findID(obj.Receivers,id);
            binding=sixgr.rf.ReceiveElementLayout.freezeInstallation(struct());
            if isfield(obj.Receivers(k),'ElementLayout')
                binding=obj.Receivers(k).ElementLayout;
            end
        end

        function validateReceiverInstallation(obj,id,cfg,direction,nAnt)
            k=obj.findID(obj.Receivers,id);
            candidate=sixgr.rf.resolveReceiveBranchLayout( ...
                cfg,id,direction,nAnt,obj.SampleRateHz,obj.ConfigurationEpoch);
            assert(isequaln(candidate,obj.Receivers(k).BranchLayout), ...
                'RF:ReceiveBranchOwnerMismatch', ...
                'A shared receiver cannot change its installed array, order, RF reference or branch layout.');
            if isfield(obj.Receivers(k),'ElementLayout')
                element=sixgr.rf.ReceiveElementLayout.freezeInstallation(candidate.Installation);
                assert(isequaln(element,obj.Receivers(k).ElementLayout), ...
                    'RF:ReceiveElementOwnerMismatch','The original internal element layout cannot change.');
            end
        end

        function addLink(obj,id,txID,rxID,state,cfg)
            obj.assertRegistration(); id=obj.validID(id); obj.assertNewID(obj.Links,id);
            tx=obj.findID(obj.Transmitters,txID); rx=obj.findID(obj.Receivers,rxID);
            radiation=obj.validateLink(state,cfg,tx,rx);
            for k=1:numel(obj.Links)
                prior=obj.Links(k).State;
                if string(prior.StateKey)==string(state.StateKey) || ...
                        (state.UseFading && prior.UseFading && isequal(prior.Obj,state.Obj))
                    error('WAVEFORM:DuplicatePhysicalChannelOwner', ...
                        'One retained channel cannot execute two overlapping links; compose its TX or retarget the TDD link.');
                end
            end
            ledger=obj.resolveLoss(cfg,tx,rx);
            dependency=sixgr.channel.ChannelSignalDependency.install(state,obj.ConfigurationEpoch);
            % Old pre-start snapshots may have registered links but no
            % original dependency receipts. Preserve their state and leave
            % those receipts empty; only this newly installed link is known.
            obj.Links=sixgr.truth.normalizeSharedLinkDependencyMetadata(obj.Links);
            obj.Links(end+1)=struct('ID',id,'TX',tx,'RX',rx,'State',state, ...
                'Config',cfg,'LossReplay',ledger,'TrailingIdleSamples',0, ...
                'TXRadiationInstallation',radiation,'SignalDependency',dependency);
            obj.ReferenceLinkEndpoints(end+1)=struct('LinkID',id,'Direction',string(state.Direction), ...
                'TX',string(txID),'RX',string(rxID));
        end

        function attach(obj,runtime,precision)
            obj.assertRegistration();
            assert(isa(runtime,'sixgr.phy.waveform.WaveformEventRuntime') && ...
                runtime.SampleRateHz==obj.SampleRateHz && runtime.NextSampleIndex==obj.NextSampleIndex, ...
                'WAVEFORM:PhysicalRuntimeClockMismatch','Event and physical owners must share one sample origin.');
            assert(isempty(obj.ReferenceEvent),'WAVEFORM:ReferenceEventOwner','Attach exactly one chronological owner.');
            obj.ReferenceEvent=runtime;
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
            % Only attached chronological owners maintain full link model
            % history. Standalone aggregate RF diagnostics retain their old
            % channel-capture policy and never pretend to own this history.
            if string(precision)=="double"
                for link=obj.Links
                    txID=obj.Transmitters(link.TX).ID;
                    if any(string({obj.TXLinearReferences.ID})==txID)&&localSupportedReference(link.SignalDependency)
                        binding=localChannelBinding(link,obj.Transmitters,obj.Receivers,obj.ConfigurationEpoch);
                        model=sixgr.channel.AppliedChannelReferenceStream(binding,link.SignalDependency);
                        obj.LinearChannels(end+1)=struct('ID',link.ID,'Model',model);
                    end
                end
            end
        end

        function retargetTDDLink(obj,id,txID,rxID,cfg)
            % Toolbox swap preserves fading, but resets the selected input
            % filter. A chronological owner may swap only after consuming
            % enough ACTUAL transmitted silence to drain the outgoing FIR.
            % Insufficient guard is a physical scheduling error, not a
            % reason to pad RX, discard a tail, clone or rewind the channel.
            obj.assertMutable(); k=obj.findID(obj.Links,id); link=obj.Links(k);
            assert(isempty(obj.PendingReferenceCommit),'WAVEFORM:UncommittedReferenceInterval', ...
                'Complete the original interval before changing its channel direction.');
            componentHits=find(string({obj.CSIRSReferencePlanes.LinkID})==string(id));
            for h=componentHits
                p=obj.CSIRSReferencePlanes(h);
                if ~isempty(p.Model)
                    assert(p.Component.Birth.ComponentSupportStartSample>=obj.NextSampleIndex|| ...
                        obj.NextSampleIndex>=p.RetireAfterSample, ...
                        'WAVEFORM:CSIReferenceTailNotConsumed', ...
                        'Consume the complete fixed-linear component RF/FIR tail before reversing its link.');
                end
            end
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
            pair=find(string({obj.ReferenceLinkEndpoints.LinkID})==string(id)& ...
                string({obj.ReferenceLinkEndpoints.Direction})==direction);
            if ~isempty(pair)
                assert(isscalar(pair)&&obj.ReferenceLinkEndpoints(pair).TX==string(txID)&& ...
                    obj.ReferenceLinkEndpoints(pair).RX==string(rxID), ...
                    'WAVEFORM:TDDRetargetEndpointMismatch','The original directional physical endpoints cannot migrate.');
            end
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
                beforeRetarget=sixgr.channel.ChannelSignalDependency.beforeRetarget(state);
                state.Direction=char(direction);
                state.LinkKey=char(nextKey);
                if identity
                    state.Meta.RuntimeTDDReciprocityDirection=direction;
                    if state.Meta.IdentityOperatorSource=="explicit_matrix_AWGN_shared_sample_operator"
                        oldTx=state.NumTxAnt;
                        state.NumTxAnt=state.NumRxAnt; state.NumRxAnt=oldTx;
                        state.ExternalLogicalTxPorts=state.NumTxAnt;
                        state.PhysicalChannelTxElements=state.NumTxAnt;
                        state.Meta.AWGNSpatialMatrix=state.Meta.AWGNSpatialMatrix.';
                        % The beam-failure episode is an alternate physical
                        % channel operator on the same reciprocal TDD link.
                        % Retarget it with the baseline operator; otherwise a
                        % rectangular DL matrix remains RX-by-TX while the UL
                        % endpoint expects its nonconjugate transpose.
                        failureMatrix=sixgr.util.structGet( ...
                            state,'Meta.BeamFailureSpatialMatrix',[]);
                        if ~isempty(failureMatrix)
                            state.Meta.BeamFailureSpatialMatrix=failureMatrix.';
                        end
                    end
                end
                info=struct('OFDM',struct('SampleRate',obj.SampleRateHz));
                state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
                    state,cfg,complex(zeros(1,obj.Transmitters(tx).RF.NumAntennas)),info);
                radiation=obj.validateLink(state,cfg,tx,rx);
                dependency=sixgr.channel.ChannelSignalDependency.afterRetarget( ...
                    beforeRetarget,state,obj.ConfigurationEpoch,link.TrailingIdleSamples);
                obj.Links(k).State=state; obj.Links(k).TX=tx; obj.Links(k).RX=rx;
                obj.Links(k).Config=cfg; obj.Links(k).LossReplay=ledger;
                obj.Links(k).TrailingIdleSamples=0;
                obj.Links(k).TXRadiationInstallation=radiation;
                obj.Links(k).SignalDependency=dependency;
                if isempty(pair)
                    obj.ReferenceLinkEndpoints(end+1)=struct('LinkID',string(id),'Direction',direction, ...
                        'TX',string(txID),'RX',string(rxID));
                end
                j=find(string({obj.LinearChannels.ID})==string(id));
                if ~isempty(j)
                    if any(string({obj.TXLinearReferences.ID})==string(txID))
                        binding=localChannelBinding(obj.Links(k),obj.Transmitters,obj.Receivers,obj.ConfigurationEpoch);
                        obj.LinearChannels(j).Model=obj.LinearChannels(j).Model.retarget(binding,dependency);
                    else
                        assert(isempty(componentHits),'WAVEFORM:CSIReferenceReversePolicy', ...
                            'A registered component requires continuously modeled reciprocal link history.');
                        obj.LinearChannels(j)=[]; % No fabricated missing opposite-direction model history.
                    end
                end
                for h=componentHits, obj.CSIRSReferencePlanes(h).Model=[]; end
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

        function enabled=assertCSIRSPortReferenceSupport(obj,runtime,linkID,txID,prepared)
            % Preflight unsupported requests BEFORE original enqueue. A missing
            % opt-in leaves every existing (including AWGN) receiver unchanged.
            obj.assertMutable();
            enabled=any(string({obj.TXLinearReferences.ID})==string(txID));
            if ~enabled, return; end
            obj.assertReferenceEvent(runtime);
            k=obj.findID(obj.Links,linkID);
            pair=find(string({obj.ReferenceLinkEndpoints.LinkID})==string(linkID)& ...
                string({obj.ReferenceLinkEndpoints.Direction})=="DL");
            assert(isscalar(pair)&&obj.ReferenceLinkEndpoints(pair).TX==string(txID), ...
                'WAVEFORM:CSIReferenceEndpoint','Require the original installed DL endpoint, not an inferred reversed alias.');
            assert(any(string({obj.LinearChannels.ID})==string(linkID))&& ...
                localSupportedReference(obj.Links(k).SignalDependency)&& ...
                isa(prepared.TransmitSamples,'double')&& ...
                isfield(prepared.Tx.CSIRSInfo,'Resources')&& ...
                string(prepared.Tx.OFDMInfo.EngineUsed)=="canonical_nrOFDMModulate"&& ...
                prepared.Tx.OFDMInfo.Windowing==0&&prepared.Tx.OFDMInfo.OFDMWindowingSamples==0&& ...
                prepared.Tx.OFDMInfo.SampleRate==prepared.Tx.OFDMInfo.Nfft*double(prepared.Carrier.SubcarrierSpacing)*1000&& ...
                isequal(prepared.RFExecutionDeferred,true)&&isequal(prepared.ChannelExecutionDeferred,true)&& ...
                isequal(prepared.PowerContext.PAApplied,false)&& ...
                (~prepared.PowerContext.PAEnabled||prepared.PowerContext.PAExecutionDeferred), ...
                'WAVEFORM:UnsupportedCSIPortReference', ...
                ['CSI component references require original attached CPU-double CDL/Inf history ' ...
                 'and configured-resource-set preparation; no AWGN or late-history substitute.']);
        end

        function [planes,aggregatePlane,residualPlane]=registerCSIRSPortReferences( ...
                obj,runtime,linkID,txID,rxID,componentID,prepared)
            obj.assertMutable(); obj.assertReferenceEvent(runtime);
            assert(obj.assertCSIRSPortReferenceSupport(runtime,linkID,txID,prepared), ...
                'WAVEFORM:CSIPortReferenceDisabled','Explicitly enable the installed model before registration.');
            tx=obj.findID(obj.Transmitters,txID); rx=obj.findID(obj.Receivers,rxID);
            pair=find(string({obj.ReferenceLinkEndpoints.LinkID})==string(linkID)& ...
                string({obj.ReferenceLinkEndpoints.Direction})=="DL");
            assert(isscalar(pair)&&obj.ReferenceLinkEndpoints(pair).TX==string(txID)&& ...
                obj.ReferenceLinkEndpoints(pair).RX==string(rxID), ...
                'WAVEFORM:CSIReferenceEndpoint','A target plane must belong to the original installed directional pair.');
            j=find(string({obj.TXLinearReferences.ID})==string(txID));
            [installed,records,parent]=obj.TXLinearReferences(j).Binding.registerCSIRS(runtime,componentID,prepared);
            obj.TXLinearReferences(j).Binding=installed;
            parentHit=find(arrayfun(@(p)p.TX==tx&& ...
                string(p.Parent.Receipt.ComponentID)==string(componentID),obj.CSIRSReferenceParents));
            if isempty(parentHit)
                obj.CSIRSReferenceParents(end+1)=struct('TX',tx,'Parent',parent);
            else
                assert(isscalar(parentHit)&&isequaln(obj.CSIRSReferenceParents(parentHit).Parent,parent), ...
                    'WAVEFORM:CSIReferenceRegistrationChanged','Original parent registration changed.');
            end
            planes=struct('ResourceID',{},'ResourceSetID',{},'LogicalPortIndex0',{}, ...
                'ReferencePortNumber',{},'PlaneID',{},'RegistrationSHA256',{},'ParentComponentID',{});
            for record=records
                id=string(linkID)+":"+string(rxID)+":"+record.ID+":fixed_linear_model";
                hit=find(string({obj.CSIRSReferencePlanes.ID})==id);
                if isempty(hit)
                    runtime.addReceiver(id,obj.Receivers(rx).RF.NumAntennas);
                    obj.CSIRSReferencePlanes(end+1)=struct('ID',id,'LinkID',string(linkID), ...
                        'TX',tx,'RX',rx,'Component',record,'Model',[],'RetireAfterSample',Inf);
                else
                    assert(isscalar(hit)&&isequaln(obj.CSIRSReferencePlanes(hit).Component,record), ...
                        'WAVEFORM:CSIReferenceRegistrationChanged','A plane cannot acquire a new parent or port.');
                end
                planes(end+1)=struct('ResourceID',record.ResourceID,'ResourceSetID',record.ResourceSetID, ...
                    'LogicalPortIndex0',0,'ReferencePortNumber',3000,'PlaneID',id, ...
                    'RegistrationSHA256',record.RegistrationSHA256,'ParentComponentID',string(componentID));
            end
            aggregatePlane=string(linkID)+":"+string(rxID)+":fixed_linear_aggregate";
            residualPlane=string(linkID)+":"+string(rxID)+":nonlinear_model_residual";
            if ~any(string({obj.CSIModelPlanes.ID})==aggregatePlane)
                runtime.addReceiver(aggregatePlane,obj.Receivers(rx).RF.NumAntennas);
                runtime.addReceiver(residualPlane,obj.Receivers(rx).RF.NumAntennas);
                obj.CSIModelPlanes(end+1)=struct('ID',aggregatePlane,'ResidualID',residualPlane, ...
                    'LinkID',string(linkID),'RX',rx);
            end
        end

        function evidence=readCSIRSPortReferenceRegistrations(obj)
            % Original factors and private RF/channel states are not exported.
            evidence=struct('Parents',obj.CSIRSReferenceParents, ...
                'Planes',rmfield(obj.CSIRSReferencePlanes,{'Model','RetireAfterSample'}));
        end

        function execution=commitReferenceInterval(obj,runtime,execution)
            % Disabled/legacy/direct aggregate owners have no pending component
            % transaction; return their exact execution structure unchanged.
            if isempty(obj.PendingReferenceCommit), return; end
            p=obj.PendingReferenceCommit;
            try
                assert(isa(runtime,'sixgr.phy.waveform.WaveformEventRuntime')&& ...
                    runtime==obj.ReferenceEvent&&isequal(runtime.ProcessorState,obj), ...
                    'WAVEFORM:CSIReferenceCommit','Only the original attached event owner may commit.');
                authority=runtime.originalValidatedReferenceInterval();
                assert(execution.StartSample==p.First&&execution.EndSampleExclusive==p.Stop&& ...
                    obj.NextSampleIndex==p.Stop&&authority.First==p.First&&authority.Stop==p.Stop&& ...
                    isfield(execution,'ExecutedContributors')&& ...
                    isequaln(execution.ExecutedContributors,authority.Contributors), ...
                    'WAVEFORM:CSIReferenceCommit','Commit the same successful original physical interval.');
                actual=execution.ExecutedContributors;
                assert(numel(actual)==numel(p.Contributors),'WAVEFORM:CSIReferenceCommit','Contributor population changed.');
                for name=["CSIRSPortReferences","CSIModelReferences","TXLinearReferences"]
                    assert(isfield(execution,name)&&isequaln(execution.(name),p.ReferenceEvidence.(name)), ...
                        'WAVEFORM:CSIReferenceCommit', ...
                        'Original reference population, resource identity and operator receipts cannot be replaced or dropped.');
                end
                for k=1:numel(p.Contributors)
                    q=p.Contributors(k); hit=find(string({actual.TransmitterID})==q.ID);
                    assert(isscalar(hit)&&actual(hit).CommittedThroughSample>=p.Stop&& ...
                        isequaln(actual(hit).Receipt,q.Receipt),'WAVEFORM:CSIReferenceCommit', ...
                        'Successful consumption must exactly equal the original prospective composer receipt.');
                end
                for k=1:numel(execution.CSIRSPortReferences)
                    q=execution.CSIRSPortReferences(k);
                    localCommittedOutput(authority.Outputs,q.PlaneID,q.OutputSHA256);
                    execution.CSIRSPortReferences(k).SuccessfulContributorCommit=true;
                end
                for k=1:numel(execution.CSIModelReferences)
                    q=execution.CSIModelReferences(k);
                    localCommittedOutput(authority.Outputs,q.AggregatePlaneID,q.AggregateSHA256);
                    localCommittedOutput(authority.Outputs,q.ResidualPlaneID,q.ResidualSHA256);
                    execution.CSIModelReferences(k).SuccessfulContributorCommit=true;
                end
                execution.CSIReferenceCommit=struct('Source', ...
                    "original_event_output_validation_and_exact_contributor_join_before_dispatch", ...
                    'StartSample',p.First,'EndSampleExclusive',p.Stop, ...
                    'Committed',true,'ReceiverEstimatorInput',false);
                if ~isempty(obj.RFExecutionLedger), obj.RFExecutionLedger.append(execution); end
                obj.TXLinearReferences=p.TX; obj.LinearChannels=p.Channels;
                obj.CSIRSReferencePlanes=p.Planes; obj.PendingReferenceCommit=[];
            catch cause
                obj.Faulted=true; rethrow(cause);
            end
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

        function enableRFExecutionLedger(obj)
            % On an older checkpoint start at its actual retained clock.
            % Never manufacture the unrecorded historical prefix.
            obj.assertMutable();
            if ~isempty(obj.RFExecutionLedger), return; end
            inventory=table('Size',[0 4],'VariableTypes',{'string','string','string','double'}, ...
                'VariableNames',{'EndpointID','Role','Direction','PhysicalPortCount'});
            for node=obj.Transmitters
                inventory(end+1,:)={node.ID,"TX",string(node.RF.Chain.Direction),node.RF.NumAntennas};
            end
            for node=obj.Receivers
                inventory(end+1,:)={node.ID,"RX",string(node.RF.Chain.Direction),node.RF.NumAntennas};
            end
            obj.RFExecutionLedger=sixgr.truth.RFEndpointExecutionLedger( ...
                obj.SampleRateHz,obj.NextSampleIndex,obj.ConfigurationEpoch,inventory);
            library=struct('Installation',{},'Field',{});
            for node=obj.Transmitters
                if isfield(node,'Radiation')&&~isempty(node.Radiation)
                    library(end+1)=struct('Installation',node.Radiation.capsule(), ...
                        'Field',node.Radiation.fieldEvidence()); %#ok<AGROW>
                end
            end
            obj.RFExecutionLedger.installRadiationLibrary(library);
            linearLibrary=struct([]);
            for node=obj.TXLinearReferences
                if isempty(linearLibrary)
                    linearLibrary=node.Binding.capsule();
                else
                    linearLibrary(end+1)=node.Binding.capsule(); %#ok<AGROW>
                end
            end
            obj.RFExecutionLedger.installTXLinearReferenceLibrary(linearLibrary);
        end

        function evidence=readRFExecutionLedger(obj)
            evidence=[];
            if ~isempty(obj.RFExecutionLedger), evidence=obj.RFExecutionLedger.read(); end
        end

        function [outputs,execution,nextState]=process(obj,inputs,first,stop,unusedState) %#ok<INUSD>
            obj.assertMutable();
            assert(isempty(obj.PendingReferenceCommit),'WAVEFORM:UncommittedReferenceInterval', ...
                'Do not advance a model beyond an uncommitted physical interval.');
            obj.validateInterval(inputs,first,stop);
            contributors=obj.validateReferenceContributors(inputs,first,stop);
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
                    'SignalContributions',struct('LinkID',{},'TX',{},'RX',{}, ...
                        'NonzeroSampleCount',{},'SampleCount',{},'Source',{}), ...
                    'ConfigurationEpoch',obj.ConfigurationEpoch,'SampleRateHz',obj.SampleRateHz, ...
                    'ChannelReferences',struct('LinkID',{},'TX',{},'RX',{},'Reference',{}), ...
                    'TXLinearReferences',struct('ID',{},'Receipt',{}));
                txSamples=cell(numel(obj.Transmitters),1);
                txChunks=cell(numel(obj.Transmitters),1);
                txReferences=cell(numel(obj.Transmitters),1);
                pendingReferences=obj.TXLinearReferences;
                pendingChannels=obj.LinearChannels;
                pendingPlanes=obj.CSIRSReferencePlanes;
                if ~isempty(pendingPlanes)
                    execution.CSIRSPortReferences=struct([]);
                    execution.CSIModelReferences=struct([]);
                end
                for k=1:numel(obj.Transmitters)
                    node=obj.Transmitters(k); index=obj.findID(inputs,node.ID);
                    referenceIndex=find(string({pendingReferences.ID})==node.ID);
                    if isempty(referenceIndex)
                        actual=node.RF.apply(inputs(index).Chunk,obj.ConfigurationEpoch);
                    else
                        % Exactly one ORIGINAL RF call. Capture arrays live
                        % only in this iteration, never in Replay or the RX.
                        [installed,actual,referenceReceipt,txReferences{k}]=pendingReferences(referenceIndex).Binding.apply( ...
                            node.RF,node.ID,inputs(index).Chunk,obj.ConfigurationEpoch);
                        pendingReferences(referenceIndex).Binding=installed;
                        execution.TXLinearReferences(end+1)=struct('ID',node.ID,'Receipt',referenceReceipt);
                        clear installed referenceReceipt
                    end
                    % This owner accepts composed, already power-scaled
                    % physical-chain samples. Prepared waveform ingress
                    % validates the applied power contract before enqueue.
                    power=sixgr.rf.PowerContext(node.RF.Configuration,node.RF.Chain.Direction);
                    actual.Replay.WaveformAmplitudeUnit=string(power.WaveformAmplitudeUnit);
                    actual.Replay.TXSpatialPowerEnabled=logical(sixgr.util.structGet( ...
                        node.RF.Configuration,'rf.txSpatialPowerEnabled',false));
                    if actual.Replay.TXSpatialPowerEnabled
                        spatialScope=sixgr.runtime.ExecutionStageProfiler.scope("measurement","TX_spatial_power");
                        actual.Replay.TXSpatialPower=sixgr.rf.measurePhysicalTXSpatialPower(actual.Waveform);
                        clear spatialScope
                    end
                    if isfield(node,'Radiation')&&~isempty(node.Radiation)
                        % Original strict binding, no extra RF/channel execution.
                        % The immutable field was sampled once at registration.
                        actual.Replay.ModeledRadiation=node.Radiation.bindExecution( ...
                            inputs(index).Chunk,actual,node.RF,node.ID);
                    end
                    txSamples{k}=actual.Waveform;
                    txChunks{k}=actual.Chunk;
                    outputs(end+1)=struct('ID',node.ID+":tx",'Chunk',actual.Chunk); %#ok<AGROW>
                    execution.TX(end+1)=struct('ID',node.ID,'Replay',actual.Replay);
                end
                sums=cell(numel(obj.Receivers),1);
                for k=1:numel(obj.Receivers)
                    sums{k}=complex(zeros(stop-first,obj.Receivers(k).RF.NumAntennas,'like',txSamples{1}));
                end
                contributions=cell(numel(obj.Links),1);
                modelContributions=cell(numel(obj.Links),1);
                modelChannelReceipts=cell(numel(obj.Links),1);
                for k=1:numel(obj.Links)
                    link=obj.Links(k); x=txSamples{link.TX};
                    birthSnapshot=sixgr.channel.ChannelSignalDependency.beforeRetarget(link.State);
                    modelIndex=find(string({pendingChannels.ID})==link.ID);
                    requests=obj.ChannelReferenceRequests;
                    hits=find(string({requests.LinkID})==link.ID & [requests.RX]==link.RX & ...
                        [requests.Start]<stop & [requests.End]>first);
                    channelScope=sixgr.runtime.ExecutionStageProfiler.scope("channel","apply_retained_channel_state");
                    [contribution,replay,state,reference]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
                        link.State,x,'OutputSampleAlignment','continuous_raw_samples', ...
                        'InputSampleDomain','materialized_channel_ports', ...
                        'CaptureChannelReference',~isempty(hits)||~isempty(modelIndex));
                    replay.ChannelSignalDependency=sixgr.channel.ChannelSignalDependency.bind( ...
                        sixgr.util.structGet(link,'SignalDependency',struct()), ...
                        link.State,state,replay,first,stop);
                    if isfield(link,'TXRadiationInstallation')&&~isempty(link.TXRadiationInstallation)
                        replay.TXRadiationInstallation=link.TXRadiationInstallation;
                    end
                    clear channelScope
                    for h=hits
                        request=requests(h); bounded=reference;
                        bounded.ObservationStartSample=request.Start;
                        bounded.ObservationEndSampleExclusive=request.End;
                        bounded.StartSample=max(first,request.Start);
                        bounded.EndSampleExclusive=min(stop,request.End);
                        % Most requests cover this entire processor interval.
                        % Retain the immutable arrays by MATLAB value sharing;
                        % an explicit full-range subscript can allocate another
                        % multi-GiB tensor. Only actual partial windows need a
                        % slice. Observation bounds remain request-specific.
                        if bounded.StartSample~=first || bounded.EndSampleExclusive~=stop
                            indices=(bounded.StartSample-first+1):(bounded.EndSampleExclusive-first);
                            bounded.PathGains=reference.PathGains(indices,:,:,:);
                            bounded.SampleTimes_s=reference.SampleTimes_s(indices);
                        end
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
                    lossReplay.GainStageMeasurement=sixgr.truth.measureWaveformGainEnergy( ...
                        beforeGain,contribution,obj.Receivers(link.RX).NoiseReplay.PowerContextAmplitudeUnit);
                    contributions{k}=contribution;
                    % Exact nonzero count, without a detection threshold or
                    % another waveform buffer. Includes channel/RF tails.
                    execution.SignalContributions(end+1)=struct('LinkID',link.ID, ...
                        'TX',obj.Transmitters(link.TX).ID,'RX',obj.Receivers(link.RX).ID, ...
                        'NonzeroSampleCount',nnz(contribution), ...
                        'SampleCount',numel(contribution), ...
                        'Source',"actual_link_after_TX_RF_channel_loss_before_noise_RX_RF");
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
                    if ~isempty(modelIndex)
                        assert(~isempty(txReferences{link.TX}),'WAVEFORM:CSIReferenceTXHistory', ...
                            'The current original transmitter must retain its aggregate model history.');
                        [model,~,mapped,modelReceipt]=pendingChannels(modelIndex).Model.advance( ...
                            txReferences{link.TX}.AggregateSamples,txChunks{link.TX},reference,execution.Links(end));
                        pendingChannels(modelIndex).Model=model;
                        modelContributions{k}=mapped; modelChannelReceipts{k}=modelReceipt;
                    end
                    % Reuse the FULL untrimmed original gain/filter operands,
                    % never an observation crop or another channel execution.
                    planeHits=find(string({pendingPlanes.LinkID})==link.ID);
                    for h=planeHits
                        p=pendingPlanes(h); active=p.TX==link.TX&&p.RX==link.RX;
                        componentReceipt=struct(); channelReceipt=struct();
                        samples=complex(zeros(stop-first,obj.Receivers(p.RX).RF.NumAntennas,'like',x));
                        if active
                            descriptor=txReferences{p.TX}.Components;
                            t=find(string({descriptor.ID})==p.Component.ID);
                            assert(isscalar(t),'WAVEFORM:CSIReferenceTXHistory','Original TX component state is missing.');
                            assert(link.SignalDependency.MemorySamples<=flintmax-descriptor(t).RetireAfterSample, ...
                                'WAVEFORM:CSIReferenceClock','Channel tail exceeds exact sample coordinates.');
                            retire=descriptor(t).RetireAfterSample+link.SignalDependency.MemorySamples;
                            p.RetireAfterSample=retire;
                            if first<retire
                                if isempty(p.Model)
                                    assert(first<=p.Component.Birth.ComponentSupportStartSample, ...
                                        'WAVEFORM:CSIReferenceMissingComponentHistory', ...
                                        'Cannot reconstruct an already emitted component after a direction gap.');
                                    birth=p.Component.Birth; birth.ModelHistoryStartSample=first;
                                    binding=localChannelBinding(link,obj.Transmitters,obj.Receivers,obj.ConfigurationEpoch);
                                    p.Model=sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth( ...
                                        binding,link.SignalDependency, ...
                                        birthSnapshot,birth);
                                end
                                [component,~,componentReceipt]=txReferences{p.TX}.Component(p.Component.ID);
                                [p.Model,~,samples,channelReceipt]=p.Model.advance( ...
                                    component,txChunks{p.TX},reference,execution.Links(end));
                            else
                                p.Model=[]; % Proven finite RF + native FIR support has ended.
                            end
                        end
                        pendingPlanes(h)=p;
                        outputChunk=sixgr.phy.waveform.WaveformChunk(samples,first);
                        outputs(end+1)=struct('ID',p.ID,'Chunk',outputChunk);
                        parentIndex=find(arrayfun(@(r)r.TX==p.TX&& ...
                            string(r.Parent.Receipt.ComponentID)==p.Component.ParentComponentID,obj.CSIRSReferenceParents));
                        assert(isscalar(parentIndex),'WAVEFORM:CSIReferenceParent','Missing original parent registration.');
                        q=localPortReceipt(p,first,stop,active,outputChunk, ...
                            obj.CSIRSReferenceParents(parentIndex).Parent,obj.ConfigurationEpoch, ...
                            obj.SampleRateHz,obj.Receivers(p.RX).ID,componentReceipt,channelReceipt);
                        if isempty(execution.CSIRSPortReferences), execution.CSIRSPortReferences=q;
                        else, execution.CSIRSPortReferences(end+1)=q; end
                    end
                end
                for plane=obj.CSIModelPlanes
                    k=obj.findID(obj.Links,plane.LinkID); link=obj.Links(k);
                    active=link.RX==plane.RX;
                    mapped=complex(zeros(stop-first,obj.Receivers(plane.RX).RF.NumAntennas,'like',txSamples{1}));
                    residual=mapped; actualDesired=mapped; adapter=struct();
                    if active
                        assert(~isempty(modelContributions{k}),'WAVEFORM:CSIReferenceAggregateHistory', ...
                            'The complete aggregate model must originate at the original installation.');
                        mapped=modelContributions{k}; actualDesired=contributions{k};
                        residual=actualDesired-mapped; adapter=modelChannelReceipts{k};
                    end
                    aChunk=sixgr.phy.waveform.WaveformChunk(mapped,first);
                    rChunk=sixgr.phy.waveform.WaveformChunk(residual,first);
                    outputs(end+1)=struct('ID',plane.ID,'Chunk',aChunk);
                    outputs(end+1)=struct('ID',plane.ResidualID,'Chunk',rChunk);
                    q=struct('ContractVersion',"sixgr.csirs.shared_linear_aggregate_reference/v1", ...
                        'Source',"original_shared_owner_fixed_linear_model_and_actual_residual", ...
                        'LinkID',plane.LinkID,'AggregatePlaneID',plane.ID,'ResidualPlaneID',plane.ResidualID, ...
                        'StartSample',first,'EndSampleExclusive',stop,'Active',active, ...
                        'AggregateSHA256',aChunk.SHA256,'ResidualSHA256',rChunk.SHA256, ...
                        'ActualDesiredSHA256',sixgr.phy.waveform.WaveformHash.numeric(actualDesired), ...
                        'AggregateEnergy',sum(abs(mapped(:)).^2),'ResidualEnergy',sum(abs(residual(:)).^2), ...
                        'CrossEnergy',2*real(sum(conj(mapped(:)).*residual(:))), ...
                        'ActualDesiredEnergy',sum(abs(actualDesired(:)).^2), ...
                        'OriginalChannelAdapter',adapter,'SuccessfulContributorCommit',false, ...
                        'ActualNonlinearPortAttribution',false,'StandardizedPowerAccuracyQualified',false, ...
                        'ReceiverEstimatorInput',false);
                    if isempty(execution.CSIModelReferences), execution.CSIModelReferences=q;
                    else, execution.CSIModelReferences(end+1)=q; end
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
                    signal=sums{k}; evmReplay=struct('ConfiguredPercent',0, ...
                        'MeasuredPercent',0,'ReferencePowerPerChain',[], ...
                        'ReferenceSource',"disabled",'Seed',NaN);
                    if logical(node.AdditiveEVM.enabled)
                        assert(isempty(fieldnames(node.EVMState)) && ...
                            stop-first==node.AdditiveEVM.observationSamples, ...
                            'RF:AdditiveEVMObservationPartition', ...
                            ['Block-mean EVM requires one complete declared observation. ' ...
                             'Partitioned streaming needs an explicit fixed-reference distortion contract.']);
                        % Distortion is a forward physical model of the
                        % actual received signal. Neither its variance nor
                        % the clean reference is given to the decoder.
                        powerPerChain=mean(abs(double(signal)).^2,1);
                        [innovations,evmState]=sixgr.link.addRuntimeComplexNoise( ...
                            zeros(size(signal),'like',signal),1,node.AdditiveEVM.seed,first,node.EVMState);
                        obj.Receivers(k).EVMState=evmState;
                        distortion=innovations.*cast(sqrt(powerPerChain)* ...
                            double(node.AdditiveEVM.percent)/100,'like',signal);
                        signal=signal+distortion;
                        measured=NaN;
                        if sum(powerPerChain)>0
                            measured=100*sqrt(mean(sum(abs(double(distortion)).^2,2))/sum(powerPerChain));
                        end
                        evmReplay=struct('ConfiguredPercent',double(node.AdditiveEVM.percent), ...
                            'MeasuredPercent',measured,'ReferencePowerPerChain',powerPerChain, ...
                            'ReferenceSource',"actual_physical_sum_before_receiver_noise", ...
                            'Seed',double(node.AdditiveEVM.seed));
                    end
                    [pre,noiseState]=sixgr.link.addRuntimeComplexNoise(signal, ...
                        node.NoiseVariance,node.NoiseSeed,first,node.NoiseState);
                    obj.Receivers(k).NoiseState=noiseState;
                    preChunk=sixgr.phy.waveform.WaveformChunk(pre,first);
                    actual=node.RF.apply(preChunk,obj.ConfigurationEpoch);
                    outputs(end+1)=struct('ID',node.ID+":pre_rf",'Chunk',preChunk); %#ok<AGROW>
                    outputs(end+1)=struct('ID',node.ID+":post_rf",'Chunk',actual.Chunk); %#ok<AGROW>
                    replay=actual.Replay;
                    replay.ReceiveElementLayoutStatus="unavailable_no_original_receive_element_installation";
                    replay.ReceiveElementExecution=struct();
                    if isfield(node,'ElementLayout')&&node.ElementLayout.Available
                        % Bind the SAME preChunk supplied to the successful
                        % RF call above. No array operation, IQ copy, rehash
                        % or second physics execution is needed.
                        replay.ReceiveElementExecution=sixgr.rf.ReceiveElementLayout.bindOriginalOwnerExecution( ...
                            node.ElementLayout.Layout,preChunk,actual,node.RF,node.ID);
                        replay.ReceiveElementLayoutStatus="executed_internal_receive_element_columns";
                    end
                    replay.ReceiveBranchLayoutStatus=node.BranchLayout.Status;
                    replay.ReceiveBranchExecution=struct();
                    if node.BranchLayout.Available
                        % These are the SAME original physical-element and
                        % RF-input samples. No identity matrix multiply or
                        % second waveform/RF execution is performed.
                        replay.ReceiveBranchExecution=sixgr.rf.ReceiveBranchLayout.bindOriginalOwnerExecution( ...
                            node.BranchLayout.Layout,preChunk,preChunk,actual,node.RF,node.ID);
                        replay.ReceiveBranchLayoutStatus="executed_identity_combined_receiver_branches";
                    end
                    replay.AdditiveReceiverEVM=evmReplay;
                    replay.InjectedNoiseVariance=node.NoiseVariance;
                    replay.InjectedNoiseVarianceDomain='receiver_sample_waveform_pre_composite_front_end';
                    noiseMode=lower(strtrim(string(node.NoiseReplay.NoiseOperatingMode)));
                    if any(noiseMode==["standalone_awgn_snr_argument","absolute_reference_esn0"])
                        replay.NoiseVarianceSource=node.NoiseReplay.NoiseVarianceSource;
                    elseif noiseMode=="receiver_noise_figure_thermal_noise"
                        replay.NoiseVarianceSource= ...
                            'receiver_thermal_noise_plus_nf_absolute_sqrt_mW';
                    else
                        error('WAVEFORM:SharedNoiseOperatingModeUnsupported','Unsupported installed noise mode %s.',noiseMode);
                    end
                    replay.NoiseStreamSeed=node.NoiseSeed;
                    replay.NoiseBandwidth_Hz=node.NoiseReplay.NoiseBandwidth_Hz;
                    replay.NoiseOperatingMode=node.NoiseReplay.NoiseOperatingMode;
                    replay.WaveformAmplitudeUnit=string(node.NoiseReplay.PowerContextAmplitudeUnit);
                    replay.PowerContextAmplitudeUnit=node.NoiseReplay.PowerContextAmplitudeUnit;
                    replay.PowerContextDirection=node.NoiseReplay.PowerContextDirection;
                    replay.SampleRate_Hz=obj.SampleRateHz;
                    if noiseMode=="absolute_reference_esn0"
                        replay.AbsoluteReferenceNoiseInjectedSampleVariance_mW=node.NoiseVariance;
                        replay.AbsoluteReferenceNoiseInjectionDomain='receiver_sample_waveform_pre_composite_front_end';
                        for field=["AbsoluteReferenceNoise","RequestedReferenceEsN0_dB", ...
                                "ReferenceNoisePSD_mWPerHz","ReferenceNoiseSampleVariance_mW", ...
                                "ReferenceNoiseSampleRate_Hz","ReferenceNoiseContractSHA256", ...
                                "ReferenceNoiseSource","ReferenceNoiseReferencePlane", ...
                                "ThermalNoiseApplied","ControlledReferenceNoiseApplied"]
                            replay.(field)=node.NoiseReplay.(field);
                        end
                        sixgr.link.resolveAbsoluteReferenceNoiseVariance(replay);
                    end
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
                    if noiseMode=="absolute_reference_esn0"
                        replay.AppliedAWGNSNRSource="not_applicable_nominal_absolute_reference_not_measured_SINR";
                        replay.AWGNReferenceEnergySource="not_applicable_absolute_nominal_reference_PSD";
                    end
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
                if isempty(obj.CSIRSReferenceParents)
                    if ~isempty(obj.RFExecutionLedger), obj.RFExecutionLedger.append(execution); end
                    obj.TXLinearReferences=pendingReferences; obj.LinearChannels=pendingChannels;
                else
                    expected=struct('CSIRSPortReferences',execution.CSIRSPortReferences, ...
                        'CSIModelReferences',execution.CSIModelReferences, ...
                        'TXLinearReferences',execution.TXLinearReferences);
                    obj.PendingReferenceCommit=struct('First',first,'Stop',stop,'TX',pendingReferences, ...
                        'Channels',pendingChannels,'Planes',pendingPlanes,'Contributors',contributors, ...
                        'ReferenceEvidence',expected);
                end
                obj.NextSampleIndex=stop; nextState=obj;
            catch cause
                obj.Faulted=true; rethrow(cause);
            end
        end
    end
    methods (Access=private)
        function assertReferenceEvent(obj,runtime)
            assert(isempty(obj.PendingReferenceCommit)&& ...
                isa(runtime,'sixgr.phy.waveform.WaveformEventRuntime')&& ...
                runtime==obj.ReferenceEvent&&isequal(runtime.ProcessorState,obj)&&runtime.SampleRateHz==obj.SampleRateHz&& ...
                runtime.NextSampleIndex==obj.NextSampleIndex, ...
                'WAVEFORM:CSIReferenceEventOwner','Require the original unfaulted event/physical clock owner.');
        end

        function contributors=validateReferenceContributors(obj,inputs,first,stop)
            contributors=struct('ID',{},'Receipt',{});
            if isempty(obj.CSIRSReferenceParents), return; end
            for k=1:numel(inputs)
                input=inputs(k);
                assert(isfield(input,'ProspectiveContributors')&& ...
                    isstruct(input.ProspectiveContributors)&&isscalar(input.ProspectiveContributors), ...
                    'WAVEFORM:CSIReferenceContributors','Component reference processing requires the original composer receipt.');
                q=input.ProspectiveContributors;
                assert(all(isfield(q,{'Schema','CompleteContributorList','StartSample','EndSampleExclusive', ...
                    'SampleRateHz','CompositeInputSHA256','Components'}))&& ...
                    string(q.Schema)=="consumed_waveform_components/v1"&&isequal(q.CompleteContributorList,true)&& ...
                    q.StartSample==first&&q.EndSampleExclusive==stop&&q.SampleRateHz==obj.SampleRateHz&& ...
                    string(q.CompositeInputSHA256)==string(input.Chunk.SHA256), ...
                    'WAVEFORM:CSIReferenceContributors','Bind the complete original composite input, not just a target.');
                contributors(end+1)=struct('ID',string(input.ID),'Receipt',q);
            end
            for registration=obj.CSIRSReferenceParents
                original=registration.Parent.Receipt;
                lo=max(first,original.StartSample); hi=min(stop,original.EndSampleExclusive);
                if lo>=hi, continue; end
                t=find(string({contributors.ID})==string(original.TransmitterID));
                list=contributors(t).Receipt.Components;
                hit=find(string({list.ComponentID})==string(original.ComponentID));
                assert(isscalar(hit)&&list(hit).StartSample==lo&&list(hit).EndSampleExclusive==hi&& ...
                    string(list(hit).OriginalSampleSHA256)==string(original.OriginalSampleSHA256), ...
                    'WAVEFORM:CSIReferenceOriginalComponentChanged', ...
                    'A cancelled/replaced/missing component cannot reuse its original CSI reference factors.');
            end
        end

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

        function radiation=validateLink(obj,state,cfg,tx,rx)
            radiation=[];
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
            transmitter=obj.Transmitters(tx);
            obj.validateTransmitterInstallation(transmitter.ID,cfg,transmitter.RF.Chain.Direction,transmitter.RF.NumAntennas);
            if isfield(transmitter,'Radiation')&&~isempty(transmitter.Radiation)
                radiation=transmitter.Radiation.validateChannel(state,transmitter.ID);
            end
            node=obj.Receivers(rx);
            obj.validateReceiverInstallation(node.ID,cfg,node.RF.Chain.Direction,node.RF.NumAntennas);
            elementAvailable=isfield(node,'ElementLayout')&&node.ElementLayout.Available;
            if (elementAvailable||node.BranchLayout.Available) && isa(state.Obj,'nrCDLChannel')
                % R2026a's public getter already returns the CURRENT RX
                % array after swapTransmitAndReceive (nrCDLChannel's
                % get.ReceiveAntennaArray calls swapTxRx internally).
                % A second swap here would inspect the transmitter array.
                nativeArray=state.Obj.ReceiveAntennaArray;
                layout=node.BranchLayout.Layout;
                if elementAvailable, layout=node.ElementLayout.Layout; end
                geometry=layout.Geometry;
                actualConfig=node.RF.Configuration;
                if layout.Identity.Role=="bs"
                    arrayPath='lls6g.userContext.RuntimeServingBSAntenna';
                else
                    arrayPath='lls6g.userContext.RuntimeUEAntenna';
                end
                installedArray=sixgr.util.structGet(actualConfig,arrayPath,struct());
                installedArray.ArrayObj=nativeArray;
                actualConfig=sixgr.util.structSet(actualConfig,arrayPath,installedArray);
                nativeInstallation=sixgr.rf.validateReceiveBranchInstallation( ...
                    actualConfig,node.ID,node.RF.Chain.Direction,node.RF.NumAntennas, ...
                    obj.SampleRateHz,obj.ConfigurationEpoch);
                assert(isequaln(nativeInstallation.Geometry,geometry)&& ...
                    double(state.Obj.CarrierFrequency)==geometry.CarrierFrequencyHz, ...
                    'RF:ReceiveBranchChannelOrderMismatch', ...
                    'The actual native CDL output array must retain the installed receiver element order and frequency.');
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

function localCommittedOutput(outputs,id,sha)
hit=find(string({outputs.ID})==string(id));
assert(isscalar(hit)&&string(outputs(hit).SHA256)==string(sha), ...
    'WAVEFORM:CSIReferenceCommit','Reference receipt must bind the validated original output chunk.');
end
function supported=localSupportedReference(d)
supported=isstruct(d)&&isscalar(d)&&isfield(d,'Available')&&isequal(d.Available,true)&& ...
    isfield(d,'NativeFilterAuthority')&&string(d.NativeFilterAuthority)== ...
    "R2026a_Inf_fresh_both_direction_public_getPathFilters";
end
function binding=localChannelBinding(link,transmitters,receivers,epoch)
power=sixgr.rf.PowerContext(transmitters(link.TX).RF.Configuration,transmitters(link.TX).RF.Chain.Direction);
binding=struct('LinkID',string(link.ID),'TX',transmitters(link.TX).ID, ...
    'RX',receivers(link.RX).ID,'ConfigurationEpoch',epoch, ...
    'WaveformAmplitudeUnit',string(power.WaveformAmplitudeUnit));
end
function q=localPortReceipt(p,first,stop,active,chunk,parent,epoch,fs,rxID,rf,channel)
q=struct('ContractVersion',"sixgr.csirs.shared_fixed_linear_port_reference/v1", ...
    'Source',"original_shared_owner_fixed_linear_CSI_port_model", ...
    'PlaneID',p.ID,'LinkID',p.LinkID,'TransmitterID',string(parent.Receipt.TransmitterID), ...
    'ReceiverID',string(rxID),'ReceiveElementCount',size(chunk.Samples,2), ...
    'ParentComponentID',p.Component.ParentComponentID, ...
    'ResourceID',p.Component.ResourceID,'ResourceSetID',p.Component.ResourceSetID, ...
    'LogicalPortIndex0',p.Component.LogicalPortIndex0,'ReferencePortNumber',p.Component.ReferencePortNumber, ...
    'RegistrationSHA256',p.Component.RegistrationSHA256, ...
    'OriginalEnqueueReceiptSHA256',string(parent.Receipt.ReceiptSHA256), ...
    'TXInstallationSHA256',parent.TXInstallationSHA256, ...
    'OriginalParentSampleSHA256',string(parent.Receipt.OriginalSampleSHA256), ...
    'StartSample',first,'EndSampleExclusive',stop,'ConfigurationEpoch',epoch,'SampleRateHz',fs, ...
    'WaveformAmplitudeUnit',string(parent.Evidence.WaveformAmplitudeUnit), ...
    'OutputSHA256',string(chunk.SHA256),'HashSerialization',"WaveformHash.numeric", ...
    'Active',active,'InputNonzeroEndSample',p.Component.InputNonzeroEndSample, ...
    'RetireAfterSample',p.RetireAfterSample,'ModelSourceSupportEndAppliedAsTrim',false, ...
    'OriginalRFAdapter',rf,'OriginalChannelAdapter',channel, ...
    'OriginalOwnerOperandsBound',true,'SuccessfulContributorCommit',false, ...
    'PAReferenceModel',"fixed_declared_first_order_PA", ...
    'DACReferenceModel',"identity_converter_reference_residual_retained", ...
    'CommonIQDCIncluded',false,'ActualNonlinearPortAttribution',false, ...
    'StandardizedPowerAccuracyQualified',false,'HardwareQualified',false, ...
    'ReceiverEstimatorInput',false,'AdditionalRFExecutions',0,'AdditionalChannelExecutions',0);
end

function [enabled,array,metadata,quadrature,reference]=localRadiationInstallation(cfg,direction)
policy=sixgr.util.structGet(cfg,'rf.modeledRadiatedPower',struct('Enabled',false));
assert(isstruct(policy)&&isscalar(policy)&&isfield(policy,'Enabled')&& ...
    islogical(policy.Enabled)&&isscalar(policy.Enabled),'RF:ModeledRadiationPolicy','Require resolved radiation policy.');
enabled=policy.Enabled; array=[]; metadata=[]; quadrature=[]; reference=[];
if ~enabled, return; end
assert(isequal(sixgr.util.structGet(cfg,'rf.txSpatialPowerEnabled',false),true), ...
    'RF:ModeledRadiationDependencies','Enabled radiation requires the actual spatial-power producer.');
assert(all(isfield(policy,{'Quadrature','Scope','CoordinateFrame','FrequencyScope','UEReference'}))&& ...
    policy.Scope=="native_gain_pattern_post_tx_rf_model"&& ...
    policy.CoordinateFrame=="installed_array_local_coordinates"&& ...
    policy.FrequencyScope=="frequency_flat_installed_carrier_field_model", ...
    'RF:ModeledRadiationPolicy','Require resolved local frequency-flat model scope.');
u=sixgr.util.structGet(cfg,'lls6g.userContext',struct());
if string(direction)=="DL"
    array=sixgr.util.structGet(u,'RuntimeServingBSAntenna',[]);
    metadata=sixgr.util.structGet(u,'RuntimeServingBSAntennaMeta',[]);
    reference=sixgr.util.structGet(cfg,'rf.bsPowerReference',[]);
elseif string(direction)=="UL"
    array=sixgr.util.structGet(u,'RuntimeUEAntenna',[]);
    metadata=sixgr.util.structGet(u,'RuntimeUEAntennaMeta',[]);
    reference=policy.UEReference;
else
    error('RF:ModeledRadiationPolicy','Require explicit DL or UL direction.');
end
quadrature=policy.Quadrature;
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
