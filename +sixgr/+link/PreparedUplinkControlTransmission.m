classdef PreparedUplinkControlTransmission
    % Retained SRS/PUCCH contribution, before shared node RF and propagation.
    % UE TX and gNB RX origins are distinct when received clock/TA authority
    % is present. The aligned zero-TA component fixture remains explicit.
    properties (SetAccess=private)
        Channel (1,1) string
        InputConfig
        RequestBinding struct
        Tx struct
        TxInfo struct
        ReceiverConfig struct
        Metadata struct
        SampleRateHz (1,1) double
        StartSample (1,1) double
        EndSampleExclusive (1,1) double
        ReceiveStartSample (1,1) double
        ReceiveEndSampleExclusive (1,1) double
        PhysicalTiming struct
        NumPhysicalTransmitAntennas (1,1) double
        NumReceiveAntennas (1,1) double
    end
    methods
        function obj=PreparedUplinkControlTransmission(channel,cfg,options,tx,info,rxCfg,slot0,metadata)
            assert(any(string(channel)==["SRS","PUCCH"]), ...
                'sixgr:link:InvalidULControlChannel','Use a typed SRS or PUCCH contribution.');
            validateattributes(slot0,{'numeric'},{'scalar','finite','integer','nonnegative'});
            fs=double(info.OFDMInfo.SampleRate);
            validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(tx.Waveform,{'single','double'},{'2d','nonempty','finite'});
            assert(isfield(options,'TimingAdvanceSamples') && isfinite(options.TimingAdvanceSamples), ...
                'sixgr:link:MissingPreparedULControlTiming','Explicit timing-advance authority is required.');
            pc=rxCfg.lls6g.runtimePowerContext;
            assert(~pc.PAApplied && (~pc.PAEnabled || pc.PAExecutionDeferred), ...
                'sixgr:link:ULControlPreparationAppliedRF','Defer PA until node composition.');
            origin=double(slot0)*1e-3*15/double(tx.Carrier.SubcarrierSpacing)*fs;
            slotsPerFrame=10*double(tx.Carrier.SubcarrierSpacing)/15;
            assert(mod(double(tx.Carrier.NSlot),slotsPerFrame)==mod(double(slot0),slotsPerFrame), ...
                'sixgr:link:ULControlPreparationClockMismatch', ...
                'OFDM carrier slot and scheduled UL occasion must agree.');
            declared=sixgr.util.structGet(rxCfg,'lls6g.userContext.RuntimeSlotStartTime_s',origin/fs);
            assert(abs(origin-round(origin))<1e-6 && isscalar(declared) && ...
                isfinite(declared) && abs(double(declared)*fs-origin)<1e-6, ...
                'sixgr:link:ULControlPreparationClockMismatch', ...
                'The control occasion and runtime sample origin must agree.');
            array=sixgr.rf.AntennaArrayFactory.build(rxCfg,'ue', ...
                'signal',lower(string(channel)),'numPorts',size(tx.Waveform,2));
            obj.Channel=string(channel); obj.InputConfig=cfg;
            obj.RequestBinding=obj.requestBinding(options);
            obj.Tx=tx; obj.TxInfo=info; obj.ReceiverConfig=rxCfg; obj.Metadata=metadata;
            obj.SampleRateHz=fs; obj.StartSample=round(origin);
            obj.ReceiveStartSample=obj.StartSample;
            obj.ReceiveEndSampleExclusive=obj.StartSample+size(tx.Waveform,1);
            obj.PhysicalTiming=struct('Source',"explicit_aligned_zero_TA_component_fixture", ...
                'WaveformTimingApplied',false,'FiniteWaveformCropped',false);
            if isfield(cfg,'SharedULTimingContext')
                timing=sixgr.link.resolveConnectedULTransmissionTiming( ...
                    cfg,origin/fs,fs,size(tx.Waveform,1));
                ta=timing.ReceivedRARTiming;
                assert(options.TimingAdvanceSamples==ta.Samples, ...
                    'sixgr:link:ULControlTimingAuthorityMismatch','Received RAR timing and the requested TA must agree exactly.');
                obj.StartSample=timing.TransmitStartSample;
                obj.ReceiveStartSample=timing.ReceiveStartSample;
                obj.ReceiveEndSampleExclusive=timing.ReceiveEndWithoutChannelTail;
                timing.WaveformTimingApplied=true;
                obj.PhysicalTiming=timing;
            else
                assert(options.TimingAdvanceSamples==0, ...
                    'sixgr:link:SharedULControlTimingAdvanceNotIntegrated', ...
                    'Nonzero TA requires received DL clock/common offset/TA authority; no finite waveform shifting.');
            end
            obj.EndSampleExclusive=obj.StartSample+size(tx.Waveform,1);
            obj.NumPhysicalTransmitAntennas=size(array.PortToElementMatrix,1);
            % Shared pre/post-RF captures are physical-element samples before
            % receive combining. Runtime logical ports (e.g. two CSI ports
            % on four elements) must not shrink the expected capture width.
            rxArray=sixgr.util.structGet(rxCfg, ...
                'lls6g.userContext.RuntimeServingBSAntenna',struct());
            if isempty(fieldnames(rxArray))
                rxArray=sixgr.rf.AntennaArrayFactory.build(rxCfg,'bs');
            end
            validateattributes(rxArray.NumElements,{'numeric'}, ...
                {'scalar','integer','positive','finite'});
            obj.NumReceiveAntennas=double(rxArray.NumElements);
        end

        function validateReceived(obj,channel,cfg,options)
            assert(obj.Channel==string(channel) && isequaln(obj.InputConfig,cfg) && ...
                isequaln(obj.RequestBinding,obj.requestBinding(options)), ...
                'sixgr:link:PreparedULControlRequestMismatch', ...
                'Retain the prepared configuration, occasion, resource, UCI and receiver context.');
            context=options.ReceivedContext;
            required={'Observation','PhysicalMeasurementObservation','TransmitterObservation','Replay','ChannelState'};
            assert(all(isfield(context,required)) && isstruct(context.Replay) && ...
                isscalar(context.Replay) && isstruct(context.ChannelState) && isscalar(context.ChannelState), ...
                'sixgr:link:IncompleteULControlReceivedContext','Retain actual samples and execution evidence.');
            obj.readObservation(context.Observation,"receiver");
            obj.readObservation(context.PhysicalMeasurementObservation,"receiver");
            obj.readObservation(context.TransmitterObservation,"transmitter");
            assert(context.Observation.EndSampleExclusive==context.PhysicalMeasurementObservation.EndSampleExclusive, ...
                'sixgr:link:ULControlObservationPlaneMismatch','Pre/post RF observations must cover the same interval.');
            if isfield(context,'DesiredReferenceObservation')
                obj.readObservation(context.DesiredReferenceObservation,"receiver");
                assert(context.DesiredReferenceObservation.EndSampleExclusive==context.Observation.EndSampleExclusive, ...
                    'sixgr:link:ULControlObservationPlaneMismatch','Reference and received intervals must agree.');
            end
            for name=["ApproximationMode","RuntimeChannelReciprocityApproximationMode"]
                value=lower(strtrim(string(sixgr.util.structGet(context.Replay,name,""))));
                assert(isscalar(value) && any(value==["","none","exact"]), ...
                    'sixgr:link:ProxyULControlStreamForbidden','Do not relabel approximate samples as truth.');
            end
            for name=["FallbackUsedForPathloss","FallbackUsed","ProxyUsed","SyntheticUsed"]
                value=sixgr.util.structGet(context.Replay,name,false);
                assert((isnumeric(value)||islogical(value)) && isscalar(value) && isequal(double(value),0), ...
                    'sixgr:link:ProxyULControlStreamForbidden','No proxy/fallback primary control evidence.');
            end
            obj.receiverNoiseMode(context.Replay);
            if obj.Channel=="PUCCH" && obj.RequestBinding.Assignment.Format==0
                prior=sixgr.util.structGet(context,'ReceivedULTimingReference',[]);
                assert(isa(prior,'sixgr.phy.sync.ReceivedULTimingReference') && isscalar(prior), ...
                    'sixgr:phy:pucch:PUCCHTimingReferenceRequired', ...
                    'Retain an actual prior received gNB UL clock before receiving pilot-free Format 0.');
                prior.align(obj,context.Observation); % Validate identity, age and actual sample coverage before RX.
            end
        end

        function mode=receiverNoiseMode(obj,replay)
            noise=sixgr.util.structGet(replay,'SampleNoiseVariance',NaN);
            domain=string(sixgr.util.structGet(replay,'SampleNoiseVarianceDomain',''));
            mode="provided";
            if isnumeric(noise) && isreal(noise) && isscalar(noise) && isfinite(noise) && noise>=0 && ...
                    isscalar(domain) && domain=="receiver_sample_waveform_post_composite_front_end"
                return;
            end
            assert(isnumeric(noise) && isreal(noise) && isscalar(noise) && isnan(noise) && ...
                isscalar(domain) && any(domain==["unavailable_requires_received_reference_estimation", ...
                "requires_estimation_on_digital_gain_compensated_received_reference_REs"]), ...
                'sixgr:link:ULControlNoisePlaneMismatch', ...
                'Supply post-RF sample variance or explicitly require actual received-reference estimation.');
            % No oracle noise or scalar gain is invented for a nonlinear or
            % nonstationary front end. SRS and PUCCH DM-RS allow a practical
            % received-resource disturbance estimate, not exact thermal noise.
            if obj.Channel=="PUCCH"
                if obj.RequestBinding.Assignment.Format==0
                    assert(isempty(sixgr.util.structGet(obj.Tx,'DMRSIndices',[])), ...
                        'sixgr:link:InvalidFormat0DMRS','Format 0 uses normalized sequence correlation without DM-RS or noise-variance scaling.');
                    mode="noncoherent_correlation";
                    return; % Unknown variance stays NaN; it is not consumed.
                end
                assert(~isempty(sixgr.util.structGet(obj.Tx,'DMRSIndices',[])), ...
                    'sixgr:link:PUCCHNoiseObservationRequired','Formats 1-4 require actual received DM-RS disturbance evidence.');
            else
                assert(~isempty(obj.Tx.SRSIndices) && ~isempty(obj.Tx.SRSSymbols), ...
                    'sixgr:link:SRSNoiseReferenceRequired','Actual SRS reference resources are required.');
            end
            mode="received_reference_estimate";
        end

        function samples=readObservation(obj,buffer,plane)
            assert(isa(buffer,'sixgr.phy.waveform.WaveformObservationBuffer') && isscalar(buffer), ...
                'sixgr:link:ULControlObservationRequired','Supply contiguous actual sample observations.');
            antennas=obj.NumReceiveAntennas;
            first=obj.ReceiveStartSample;
            intervalOK=buffer.EndSampleExclusive>=obj.ReceiveEndSampleExclusive;
            if string(plane)=="transmitter"
                antennas=obj.NumPhysicalTransmitAntennas;
                first=obj.StartSample;
                intervalOK=buffer.EndSampleExclusive==obj.EndSampleExclusive;
            end
            assert(buffer.StartSample==first && buffer.SampleRateHz==obj.SampleRateHz && ...
                buffer.NumReceiveAntennas==antennas && intervalOK, ...
                'sixgr:link:ULControlObservationMismatch', ...
                ['%s %s observation mismatch: start actual/expected=%g/%g, ' ...
                'rate=%g/%g, branches=%g/%g, end=%g, TX end=%g, RX minimum end=%g.'], ...
                obj.Channel,string(plane),buffer.StartSample,first, ...
                buffer.SampleRateHz,obj.SampleRateHz,buffer.NumReceiveAntennas,antennas, ...
                buffer.EndSampleExclusive,obj.EndSampleExclusive,obj.ReceiveEndSampleExclusive);
            samples=buffer.readComplete();
        end

        function interval=receiverTimingSearchWindow(obj,buffer)
            % Capture extent is the gNB search authority, never the actual
            % UE TX origin or a perfect channel-delay measurement.
            obj.readObservation(buffer,"receiver");
            interval=[0 buffer.EndSampleExclusive-buffer.StartSample-size(obj.Tx.Waveform,1)];
        end
    end
    methods (Static)
        function binding=requestBinding(options)
            excluded={'Logger','PrepareOnly','ReceivedContext','ChannelState','InitialRuntimeChannelState'};
            binding=rmfield(options,intersect(fieldnames(options),excluded));
        end
    end
end
