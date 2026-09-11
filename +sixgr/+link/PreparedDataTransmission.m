classdef PreparedDataTransmission
    %PREPAREDDATATRANSMISSION Retained coded TX; not a received trial.
    % Linear per-grant power is applied, but node RF, PA, propagation and
    % reception belong to the shared stream owner. Completion never regenerates
    % these samples or reconsumes power-control/UCI decisions.
    properties (SetAccess=private)
        Direction (1,1) string
        InputConfig struct
        RequestBinding struct
        Tx struct
        TxInfo struct
        ReceiverConfig struct
        PowerControl struct
        PowerControlState struct
        SampleRateHz (1,1) double
        StartSample (1,1) double
        EndSampleExclusive (1,1) double
        ReceiveStartSample (1,1) double
        ReceiveEndSampleExclusive (1,1) double
        PhysicalTiming struct
        NumPhysicalTransmitAntennas (1,1) double
        PreparationComputeTime_ms (1,1) double
    end
    methods
        function obj = PreparedDataTransmission(direction,cfg,binding,tx,info,rxCfg,fs,elapsed,varargin)
            obj.Direction = string(direction);
            assert(any(obj.Direction == ["DL","UL"]), 'sixgr:link:InvalidDataDirection', ...
                'Prepared data direction must be DL or UL.');
            validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(elapsed,{'numeric'},{'scalar','real','finite','nonnegative'});
            validateattributes(tx.Waveform,{'single','double'},{'2d','nonempty','finite'});
            pc = tx.PowerContext;
            assert(isfield(pc,'PAApplied') && ~pc.PAApplied && ...
                (~pc.PAEnabled || pc.PAExecutionDeferred), ...
                'sixgr:link:DataPreparationAppliedPA','Node PA must be deferred until waveform composition.');
            assert(~isfield(tx,'TxRFImpairmentReplay'), ...
                'sixgr:link:DataPreparationAppliedRF','Prepared contributions must precede node TX RF.');
            if obj.Direction=="UL"
                timing = sixgr.util.structGet(binding.Grant,'TimingDecision.DataDecision',struct());
                assert(isfield(timing,'TimingAdvanceTicks') && timing.Valid, ...
                    'sixgr:link:MissingPreparedULTiming','UL preparation requires the validated scheduling time relation.');
            end
            slot0 = sixgr.util.structGet(rxCfg,'lls6g.runtime.AbsoluteSlotIndex0',NaN);
            scs = double(tx.Carrier.SubcarrierSpacing);
            startTime = double(slot0)*1e-3*15/scs;
            declaredTime = sixgr.util.structGet(rxCfg,'lls6g.userContext.RuntimeSlotStartTime_s',startTime);
            validateattributes(startTime,{'numeric'},{'scalar','real','finite','nonnegative'});
            assert(isscalar(declaredTime) && isfinite(declaredTime) && ...
                abs(double(declaredTime)-startTime)*double(fs) < 1e-6, ...
                'sixgr:link:DataPreparationClockMismatch', ...
                'Declared runtime time and the frozen carrier slot must agree.');
            sampleOrigin = startTime*double(fs);
            assert(abs(sampleOrigin-round(sampleOrigin)) < 1e-6, ...
                'sixgr:link:DataPreparationClockMismatch','Slot origin must lie on the shared sample clock.');
            obj.InputConfig = cfg;
            obj.RequestBinding = binding;
            obj.Tx = tx; obj.TxInfo = info; obj.ReceiverConfig = rxCfg;
            obj.SampleRateHz = double(fs);
            obj.StartSample = round(sampleOrigin);
            obj.ReceiveStartSample = obj.StartSample;
            obj.ReceiveEndSampleExclusive = obj.StartSample+size(tx.Waveform,1);
            obj.PhysicalTiming = struct('Source',"explicit_aligned_component_fixture", ...
                'WaveformTimingApplied',false,'FiniteWaveformCropped',false);
            if obj.Direction=="UL"
                if isfield(cfg,'SharedULTimingContext')
                    physical=sixgr.link.resolveConnectedULTransmissionTiming( ...
                        cfg,startTime,fs,size(tx.Waveform,1));
                    assert(timing.TimingAdvanceTicks==physical.TotalAdvanceTicks, ...
                        'sixgr:link:DataTimingAuthorityMismatch', ...
                        'The frozen UL preparation-time relation must include the received NTA and common offset.');
                    obj.StartSample=physical.TransmitStartSample;
                    obj.ReceiveStartSample=physical.ReceiveStartSample;
                    obj.ReceiveEndSampleExclusive=physical.ReceiveEndWithoutChannelTail;
                    physical.WaveformTimingApplied=true;
                    obj.PhysicalTiming=physical;
                else
                    assert(timing.TimingAdvanceTicks==0, ...
                        'sixgr:link:SharedULTimingAdvanceNotIntegrated', ...
                        'Nonzero UL TA requires the received DL clock, RAR and common-offset authority.');
                end
            end
            obj.EndSampleExclusive = obj.StartSample+size(tx.Waveform,1);
            obj.NumPhysicalTransmitAntennas = double(binding.PHYGrant.AntennaArchitecture.NumElements);
            obj.PreparationComputeTime_ms = double(elapsed);
            obj.PowerControl = struct(); obj.PowerControlState = struct();
            if obj.Direction == "UL"
                assert(numel(varargin)==2,'sixgr:link:MissingPreparedPowerControl', ...
                    'UL preparation must retain its applied power-control decision and state.');
                obj.PowerControl = varargin{1}; obj.PowerControlState = varargin{2};
            end
        end

        function assertRequest(obj,direction,cfg,binding)
            assert(obj.Direction == string(direction) && isequaln(obj.InputConfig,cfg) && ...
                isequaln(obj.RequestBinding,binding), ...
                'sixgr:link:PreparedDataRequestMismatch', ...
                'Completion must retain the prepared configuration, frozen grant, payload, RV and UCI.');
        end

        function samples = readObservation(obj,buffer,numAntennas,plane)
            if nargin<4, plane="receiver"; end
            assert(any(string(plane)==["receiver","transmitter"]), ...
                'sixgr:link:DataObservationPlaneMismatch','Declare the transmitter or receiver observation plane.');
            assert(isa(buffer,'sixgr.phy.waveform.WaveformObservationBuffer') && isscalar(buffer), ...
                'sixgr:link:DataObservationRequired','Use actual contiguous sample observations.');
            first = obj.ReceiveStartSample;
            intervalOK = buffer.EndSampleExclusive >= obj.ReceiveEndSampleExclusive;
            if string(plane)=="transmitter"
                first = obj.StartSample;
                intervalOK = buffer.EndSampleExclusive == obj.EndSampleExclusive;
            end
            % The RX owner can collect actual channel/filter delay tails.
            % Do not crop those samples to the nominal TX slot length.
            assert(buffer.SampleRateHz == obj.SampleRateHz && ...
                buffer.StartSample == first && ...
                intervalOK && ...
                buffer.NumReceiveAntennas == numAntennas, ...
                'sixgr:link:DataObservationMismatch', ...
                'Observation rate, interval and antenna count must match the prepared data transmission.');
            samples = buffer.readComplete();
        end

        function interval = receiverTimingSearchWindow(obj,buffer)
            % Capture coverage, not UE TX phase or a perfect channel delay,
            % bounds the gNB's DM-RS timing search.
            obj.readObservation(buffer,buffer.NumReceiveAntennas,"receiver");
            interval=[0 buffer.EndSampleExclusive-buffer.StartSample-size(obj.Tx.Waveform,1)];
        end
    end
    methods (Static)
        function binding = requestBinding(options,grant,phyGrant)
            % Receiver evidence may arrive after DL TX preparation. No other
            % scheduling, payload or PHY allocation field may change.
            receiverFields = {'ControlDecodeOk','PDCCHGrantBindingOk', ...
                'PDCCHGrantDCIId','PDCCHGrantDCIFormat', ...
                'PDCCHGrantFirstCCE','PDCCHGrantNumCCE', ...
                'PDCCHGrantDCIFieldsHash','PDCCHGrantFieldsHash'};
            present = intersect(fieldnames(grant),receiverFields);
            grant = rmfield(grant,present);
            binding = struct('Grant',grant,'PHYGrant',phyGrant);
            fields = {'NumFrames','SNR_dB','StartFrameIndex','StartSlotIndex', ...
                'TransportBlockBits','RV','HARQContext','PreviousCombinedLLR', ...
                'InitialLinkAdaptationState','ExpectedUCIBits','ExpectedUCIPayload'};
            for k=1:numel(fields)
                if isfield(options,fields{k})
                    binding.(fields{k}) = options.(fields{k});
                end
            end
        end
    end
end
