classdef ReferenceRSRPFilter
    % Causal logarithmic IIR with the TS 38.331 5.5.3.2 recurrence.
    % The caller owns reference identity and configuration authority. Using
    % this recurrence does NOT prove that a QuantityConfig was signalled.
    % Preserve time characteristics when the PHY measurement interval changes.
    properties (SetAccess=private)
        CoefficientK
        ReferencePeriod_s
        Source
        MeasurementId = ""
        ProducerTime_s = NaN
        AvailableTime_s = NaN
        InputRSRP_dBm = NaN
        FilteredRSRP_dBm = NaN
        PreviousFilteredRSRP_dBm = NaN
        EffectiveAlpha = NaN
        UpdateCount = 0
    end
    methods
        function obj=ReferenceRSRPFilter(k,period_s,source)
            validateattributes(k,{'numeric'},{'scalar','integer','nonnegative','finite'});
            if ~ismember(k,[0:9 11 13 15 17 19])
                error('sixgr:rrc:InvalidRSRPFilterCoefficient','Unsupported TS 38.331 FilterCoefficient k=%g.',k);
            end
            validateattributes(period_s,{'numeric'},{'scalar','real','finite','positive'});
            source=string(source);
            if ~isscalar(source) || ismissing(source) || strlength(source)==0
                error('sixgr:rrc:MissingRSRPFilterAuthority','Filter authority must be identified.');
            end
            obj.CoefficientK=double(k); obj.ReferencePeriod_s=double(period_s); obj.Source=source;
        end
        function obj=observe(obj,measurementId,rsrp_dBm,producerTime_s,availableTime_s,knownTime_s)
            validateattributes(rsrp_dBm,{'numeric'},{'scalar','real','finite'});
            validateattributes([producerTime_s availableTime_s knownTime_s],{'numeric'}, ...
                {'vector','numel',3,'real','finite','nonnegative'});
            measurementId=string(measurementId);
            if ~isscalar(measurementId) || ismissing(measurementId) || strlength(measurementId)==0
                error('sixgr:rrc:MissingRSRPMeasurementIdentity','Every filter input needs its actual measurement identity.');
            end
            if availableTime_s<producerTime_s || availableTime_s>knownTime_s
                error('sixgr:rrc:RSRPFilterFutureInput','The PHY measurement must have arrived at this UE knowledge boundary.');
            end
            if measurementId==obj.MeasurementId
                if rsrp_dBm~=obj.InputRSRP_dBm || producerTime_s~=obj.ProducerTime_s || availableTime_s~=obj.AvailableTime_s
                    error('sixgr:rrc:RSRPMeasurementMutation','An immutable measurement identity was reused with different values.');
                end
                return; % Re-reading the same observation must not filter twice.
            end
            if obj.UpdateCount>0 && (producerTime_s<=obj.ProducerTime_s || availableTime_s<obj.AvailableTime_s)
                error('sixgr:rrc:RSRPFilterTimeReversal','A reference filter cannot consume an older PHY observation as new.');
            end
            obj.PreviousFilteredRSRP_dBm=obj.FilteredRSRP_dBm;
            if obj.UpdateCount==0
                alpha=1; % F0=M1, not a fabricated initial dBm value.
                obj.FilteredRSRP_dBm=double(rsrp_dBm);
            else
                a=2^(-obj.CoefficientK/4);
                alpha=1-(1-a)^((producerTime_s-obj.ProducerTime_s)/obj.ReferencePeriod_s);
                obj.FilteredRSRP_dBm=(1-alpha)*obj.FilteredRSRP_dBm+alpha*double(rsrp_dBm);
            end
            obj.EffectiveAlpha=alpha;
            obj.InputRSRP_dBm=double(rsrp_dBm);
            obj.ProducerTime_s=double(producerTime_s); obj.AvailableTime_s=double(availableTime_s);
            obj.MeasurementId=measurementId; obj.UpdateCount=obj.UpdateCount+1;
        end
    end
end
