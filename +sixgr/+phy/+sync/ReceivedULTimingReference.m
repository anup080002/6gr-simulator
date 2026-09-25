classdef ReceivedULTimingReference
    % Retained measured gNB UL clock, not UE TA or channel-delay truth.
    % A later pilot-free receiver may predict constant phase while this
    % measured reference remains fresh and its cell/BWP/TAG is unchanged.
    properties (SetAccess=private)
        SourceSignal string
        Identity struct
        TAG struct
        SampleRateHz double
        NominalStartSample double
        ArrivalOffsetFromNominalSamples double
        AvailableAtSample double
        ObservationStartSample double
    end
    methods
        function obj=ReceivedULTimingReference(prepared,observation,timing)
            isControl=isa(prepared,'sixgr.link.PreparedUplinkControlTransmission');
            isData=isa(prepared,'sixgr.link.PreparedDataTransmission');
            assert(isscalar(prepared) && ((isControl && prepared.Channel=="SRS") || ...
                (isData && prepared.Direction=="UL")), ...
                'sixgr:phy:sync:ULTimingPilotRequired','Retain an actually received SRS or PUSCH DM-RS clock.');
            if isData
                prepared.readObservation(observation, ...
                    prepared.RequestBinding.PHYGrant.AntennaArchitecture.NumRxAntennas,'receiver');
            else
                prepared.readObservation(observation,'receiver');
            end
            required={'AppliedTimingCorrectionSamples','TimingSource','OracleTimingUsed','ReceiverZeroPaddingUsed'};
            assert(isstruct(timing) && all(isfield(timing,required)) && ...
                ~timing.OracleTimingUsed && ~timing.ReceiverZeroPaddingUsed && ...
                string(timing.TimingSource)=="received_reference_correlation_bounded_search", ...
                'sixgr:phy:sync:MeasuredULTimingRequired','A new timing reference requires actual pilot correlation, not a prior prediction.');
            offset=timing.AppliedTimingCorrectionSamples;
            validateattributes(offset,{'numeric'},{'scalar','integer','nonnegative','finite'});
            count=sixgr.util.structGet(timing,'DemodulatedSampleCount',NaN);
            validateattributes(count,{'numeric'},{'scalar','integer','positive','finite'});
            assert(offset+count<=observation.EndSampleExclusive-observation.StartSample, ...
                'sixgr:phy:sync:ULTimingOutsideCapture','The measured demodulation interval must fit its actual capture.');
            cfg=prepared.ReceiverConfig;
            obj.Identity=localIdentity(cfg,prepared.SampleRateHz);
            obj.TAG=cfg.SharedULTimingContext;
            obj.SampleRateHz=prepared.SampleRateHz;
            obj.SourceSignal="PUSCH_DMRS"; if isControl, obj.SourceSignal="SRS"; end
            obj.NominalStartSample=prepared.PhysicalTiming.NominalStartSample;
            obj.ArrivalOffsetFromNominalSamples=observation.StartSample+offset-obj.NominalStartSample;
            obj.AvailableAtSample=observation.EndSampleExclusive;
            obj.ObservationStartSample=observation.StartSample;
        end
        function [samples,evidence]=align(obj,prepared,observation)
            assert(isa(prepared,'sixgr.link.PreparedUplinkControlTransmission') && ...
                isscalar(prepared) && prepared.Channel=="PUCCH", ...
                'sixgr:phy:sync:ULTimingTargetRequired','Prior timing alignment here is for a prepared PUCCH observation.');
            prepared.readObservation(observation,'receiver');
            cfg=prepared.ReceiverConfig;
            slot0=double(prepared.RequestBinding.Assignment.DueSlot)-1;
            [samples,evidence]=obj.alignObservation(cfg,observation,slot0);
        end
        function [samples,evidence]=alignCompletedObservation(obj,cfg,observation,absoluteSlot0)
            % A buffered receiver may use a completed pilot from this same
            % slot. It may not use a later slot or samples beyond completion.
            [samples,evidence]=obj.alignObservation(cfg,observation,absoluteSlot0,true);
        end
        function [samples,evidence]=alignObservation(obj,cfg,observation,absoluteSlot0,completed)
            % A gNB receive window exists even when the UE transmits nothing.
            % Its clock comes from the scheduled slot and a received pilot;
            % no prepared UE waveform, TA value or TX origin is consumed.
            if nargin<5, completed=false; end
            validateattributes(completed,{'logical'},{'scalar'});
            validateattributes(absoluteSlot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && isscalar(observation), ...
                'sixgr:phy:sync:ULTimingObservationRequired','Supply a complete actual received sample buffer.');
            raw=observation.readComplete();
            targetIdentity=localIdentity(cfg,observation.SampleRateHz);
            assert(isequaln(obj.Identity,targetIdentity) && ...
                isequaln(obj.TAG,cfg.SharedULTimingContext), ...
                'sixgr:phy:sync:ULTimingReferenceIdentityMismatch', ...
                ['A prior UL clock cannot cross UE, cell, carrier, BWP, sample clock or received TAG changes. ' ...
                 'PriorIdentity=%s TargetIdentity=%s PriorTAG=%s TargetTAG=%s'], ...
                jsonencode(obj.Identity),jsonencode(targetIdentity), ...
                jsonencode(obj.TAG),jsonencode(cfg.SharedULTimingContext));
            maximum=sixgr.util.structGet(cfg,'phy.synchronization.maxReceivedULTimingAgeSlots',NaN);
            validateattributes(maximum,{'numeric'},{'scalar','finite','integer','nonnegative'});
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            carrier.NFrame=floor(absoluteSlot0/double(carrier.SlotsPerFrame));
            carrier.NSlot=mod(absoluteSlot0,double(carrier.SlotsPerFrame));
            nominal=sixgr.phy.frame.slotStartSample(carrier,absoluteSlot0,obj.SampleRateHz);
            sameSlot=completed && obj.NominalStartSample==nominal && ...
                obj.AvailableAtSample<=observation.EndSampleExclusive;
            assert(obj.AvailableAtSample<=observation.StartSample || sameSlot, ...
                'sixgr:phy:sync:FutureULTimingReference', ...
                'Require a prior clock, or an explicitly completed same-slot pilot within the buffered observation deadline.');
            slotSamples=obj.SampleRateHz*1e-3*15/double(carrier.SubcarrierSpacing);
            age=(nominal-obj.NominalStartSample)/slotSamples;
            assert(age>=0 && age<=maximum,'sixgr:phy:sync:StaleULTimingReference', ...
                'The prior measured UL clock is outside synchronization.max_received_ul_timing_age_slots.');
            offset=nominal+obj.ArrivalOffsetFromNominalSamples-observation.StartSample;
            info=nrOFDMInfo(carrier); n=double(carrier.SymbolsPerSlot);
            localSlot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
            count=sum(double(info.SymbolLengths(localSlot*n+(1:n))));
            assert(offset>=0 && offset==fix(offset) && offset+count<=size(raw,1), ...
                'sixgr:phy:sync:IncompletePriorAlignedULObservation', ...
                'Predicted FFT placement must fit complete real received samples; no zero padding or clipping.');
            samples=raw(offset+(1:count),:);
            evidence=struct('TimingOffsetSamples',NaN,'AppliedTimingCorrectionSamples',offset, ...
                'TimingSource',"prior_received_UL_pilot_constant_phase_prediction", ...
                'TimingValueRole',"predicted_from_prior_measurement_not_current_timing_measurement", ...
                'ReferenceSource',obj.SourceSignal,'ReferenceAvailableAtSample',obj.AvailableAtSample, ...
                'ReferenceArrivalOffsetFromNominalSamples',obj.ArrivalOffsetFromNominalSamples, ...
                'ReferenceAgeSlots',age,'InputSampleCount',size(raw,1),'DemodulatedSampleCount',count, ...
                'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
            if sameSlot
                evidence.TimingOffsetSamples=offset;
                evidence.TimingSource="completed_same_slot_received_UL_pilot_alignment";
                evidence.TimingValueRole="measured_same_slot_pilot_applied_to_buffered_observation";
                evidence.ReceiverTimingAvailableAtSample=obj.AvailableAtSample;
            end
        end
    end
end

function identity=localIdentity(cfg,fs)
carrier=sixgr.phy.grid.makeCarrier(cfg);
rnti=sixgr.util.structGet(cfg,'phy.pusch.RNTI',NaN);
validateattributes(rnti,{'numeric'},{'scalar','integer','positive','finite'});
identity=struct('RNTI',double(rnti),'NCellID',carrier.NCellID, ...
    'SCSkHz',carrier.SubcarrierSpacing,'NSizeGrid',carrier.NSizeGrid, ...
    'NStartGrid',carrier.NStartGrid,'CyclicPrefix',carrier.CyclicPrefix, ...
    'SampleRateHz',fs,'CenterFrequencyHz',cfg.frequency.centerFrequencyHz, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ULBWPID',cfg.phy.frame.DefaultIdentity.ULBWPID);
end
