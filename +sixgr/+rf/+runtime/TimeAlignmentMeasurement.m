classdef TimeAlignmentMeasurement
%TIMEALIGNMENTMEASUREMENT Correlation-derived timing/alignment metric.

    methods(Static)
        function result=measure(reference,observed,sampleRateHz, ...
                referencePlane)
            plane=sixgr.rf.runtime.RFReferencePlane.validate(referencePlane);
            estimate=sixgr.rf.runtime.TimingAcquisitionEngine.estimate( ...
                observed,reference,"AmbiguityRatio",1.0001);
            result=estimate;
            result.TimeAlignment_s=estimate.EstimatedTiming_samples/ ...
                double(sampleRateHz);
            result.ReferencePlane=plane;
            result.Source="receiver_correlation_timing_measurement";
        end
    end
end
