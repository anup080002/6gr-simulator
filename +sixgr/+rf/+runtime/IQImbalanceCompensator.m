classdef IQImbalanceCompensator < handle
%IQIMBALANCECOMPENSATOR Stateful measured-coefficient IQ compensator.

    properties(SetAccess=private)
        Estimate struct
        StateEpoch (1,1) double
        SamplesProcessed (1,1) double = 0
    end

    methods
        function obj = IQImbalanceCompensator(estimate, stateEpoch)
            arguments
                estimate struct
                stateEpoch (1,1) double {mustBeFinite} = 1
            end
            required = ["Alpha","Beta","DCOffset","Source","EstimateID"];
            if ~all(isfield(estimate, required)) || ...
                    ~contains(lower(string(estimate.Source)), "measured")
                error("RF:IQCalibrationMissing", ...
                    "IQ compensator requires a measured estimator state.");
            end
            obj.Estimate = estimate;
            obj.StateEpoch = stateEpoch;
        end

        function [y, trace] = apply(obj, x, expectedEpoch)
            if double(expectedEpoch) ~= obj.StateEpoch
                error("RF:StateEpochMismatch", ...
                    "IQ compensator state epoch does not match the RF configuration.");
            end
            y = sixgr.rf.runtime.IQImbalanceProfile.compensate(x, obj.Estimate);
            obj.SamplesProcessed = obj.SamplesProcessed + size(x,1);
            trace = struct("EstimateID", string(obj.Estimate.EstimateID), ...
                "StateEpoch", obj.StateEpoch, ...
                "SamplesProcessed", obj.SamplesProcessed, ...
                "Source", string(obj.Estimate.Source));
        end
    end
end
