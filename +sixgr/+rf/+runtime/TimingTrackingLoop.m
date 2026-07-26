classdef TimingTrackingLoop < handle
%TIMINGTRACKINGLOOP Stateful PI timing-error tracking loop.

    properties(SetAccess=private)
        ProportionalGain (1,1) double
        IntegralGain (1,1) double
        Estimate_samples (1,1) double = 0
        Integrator_samples (1,1) double = 0
        LastSlot (1,1) double = -Inf
        StateEpoch (1,1) double
    end

    methods
        function obj = TimingTrackingLoop(kp, ki, stateEpoch)
            arguments
                kp (1,1) double {mustBeFinite,mustBeNonnegative}
                ki (1,1) double {mustBeFinite,mustBeNonnegative}
                stateEpoch (1,1) double {mustBeFinite} = 1
            end
            if kp == 0 && ki == 0
                error("RF:TimingTrackingProfileInvalid", ...
                    "Timing tracking loop requires nonzero loop gain.");
            end
            obj.ProportionalGain = kp;
            obj.IntegralGain = ki;
            obj.StateEpoch = stateEpoch;
        end

        function trace = update(obj, measuredErrorSamples, slot, expectedEpoch)
            if double(expectedEpoch) ~= obj.StateEpoch || slot <= obj.LastSlot || ...
                    ~(isscalar(measuredErrorSamples) && isfinite(measuredErrorSamples))
                error("RF:TimingTrackingStateStale", ...
                    "Timing update is stale, nonfinite or from the wrong epoch.");
            end
            residual = double(measuredErrorSamples) - obj.Estimate_samples;
            obj.Integrator_samples = obj.Integrator_samples + ...
                obj.IntegralGain * residual;
            obj.Estimate_samples = obj.Estimate_samples + ...
                obj.ProportionalGain * residual + obj.Integrator_samples;
            obj.LastSlot = slot;
            trace = struct("MeasuredError_samples", double(measuredErrorSamples), ...
                "Estimate_samples", obj.Estimate_samples, ...
                "Residual_samples", measuredErrorSamples-obj.Estimate_samples, ...
                "Integrator_samples", obj.Integrator_samples, ...
                "Slot", double(slot), "StateEpoch", obj.StateEpoch);
        end
    end
end
