classdef CFOState < handle
%CFOSTATE Stateful receiver-derived CFO estimate and correction phase.

    properties(SetAccess=private)
        Estimate_Hz (1,1) double = 0
        Phase_rad (1,1) double = 0
        SampleIndex (1,1) double = 0
        SampleRate_Hz (1,1) double
        StateEpoch (1,1) double
        Source string = "unacquired"
    end

    methods
        function obj = CFOState(sampleRateHz, stateEpoch)
            arguments
                sampleRateHz (1,1) double {mustBeFinite,mustBePositive}
                stateEpoch (1,1) double {mustBeFinite} = 1
            end
            obj.SampleRate_Hz = sampleRateHz;
            obj.StateEpoch = stateEpoch;
        end

        function update(obj, estimateHz, source, expectedEpoch)
            if double(expectedEpoch) ~= obj.StateEpoch
                error("RF:StateEpochMismatch", ...
                    "CFO state epoch does not match the RF configuration epoch.");
            end
            if ~(isscalar(estimateHz) && isfinite(estimateHz)) || ...
                    ~contains(lower(string(source)), ...
                    ["estimated","cp","dmrs","trs","tracking"])
                error("RF:CFOAcquisitionFailed", ...
                    "CFO state accepts receiver-derived estimates only.");
            end
            obj.Estimate_Hz = double(estimateHz);
            obj.Source = string(source);
        end

        function [y, trace] = correct(obj, x, expectedEpoch)
            if double(expectedEpoch) ~= obj.StateEpoch
                error("RF:StateEpochMismatch", ...
                    "CFO state epoch does not match the RF configuration epoch.");
            end
            if obj.Source == "unacquired"
                error("RF:CFOAcquisitionFailed", ...
                    "CFO correction requires an acquired receiver estimate.");
            end
            n = (0:size(x,1)-1).';
            phase = obj.Phase_rad - 2*pi*obj.Estimate_Hz*n/obj.SampleRate_Hz;
            y = x .* cast(exp(1j*phase), "like", x);
            obj.Phase_rad = mod(obj.Phase_rad - ...
                2*pi*obj.Estimate_Hz*size(x,1)/obj.SampleRate_Hz + pi, 2*pi)-pi;
            obj.SampleIndex = obj.SampleIndex + size(x,1);
            trace = struct("EstimatedCFO_Hz", obj.Estimate_Hz, ...
                "Source", obj.Source, "EndPhase_rad", obj.Phase_rad, ...
                "SampleIndex", obj.SampleIndex, "StateEpoch", obj.StateEpoch);
        end
    end
end
