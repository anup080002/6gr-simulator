classdef OscillatorState < handle
%OSCILLATORSTATE Continuous relative oscillator phase state.

    properties(SetAccess=private)
        SampleRate_Hz (1,1) double
        TxError_Hz (1,1) double
        RxError_Hz (1,1) double
        LinkDoppler_Hz (1,1) double
        Drift_HzPerS (1,1) double
        Phase_rad (1,1) double
        SampleIndex (1,1) double = 0
        StateEpoch (1,1) double
    end

    methods
        function obj = OscillatorState(sampleRateHz, txErrorHz, rxErrorHz, ...
                linkDopplerHz, initialPhaseRad, driftHzPerS, stateEpoch)
            arguments
                sampleRateHz (1,1) double {mustBeFinite,mustBePositive}
                txErrorHz (1,1) double {mustBeFinite} = 0
                rxErrorHz (1,1) double {mustBeFinite} = 0
                linkDopplerHz (1,1) double {mustBeFinite} = 0
                initialPhaseRad (1,1) double {mustBeFinite} = 0
                driftHzPerS (1,1) double {mustBeFinite} = 0
                stateEpoch (1,1) double {mustBeFinite} = 1
            end
            obj.SampleRate_Hz = sampleRateHz;
            obj.TxError_Hz = txErrorHz;
            obj.RxError_Hz = rxErrorHz;
            obj.LinkDoppler_Hz = linkDopplerHz;
            obj.Drift_HzPerS = driftHzPerS;
            obj.Phase_rad = initialPhaseRad;
            obj.StateEpoch = stateEpoch;
        end

        function [y, trace] = apply(obj, x, expectedEpoch)
            if nargin >= 3 && double(expectedEpoch) ~= obj.StateEpoch
                error("RF:StateEpochMismatch", ...
                    "Oscillator state epoch does not match the RF configuration epoch.");
            end
            if any(~isfinite(x(:)))
                error("RF:NonFiniteSamples", ...
                    "Oscillator input samples must be finite.");
            end
            n = (0:size(x,1)-1).';
            absoluteIndex = obj.SampleIndex + n;
            time_s = absoluteIndex ./ obj.SampleRate_Hz;
            relativeHz = obj.TxError_Hz - obj.RxError_Hz + ...
                obj.LinkDoppler_Hz + obj.Drift_HzPerS .* time_s;
            phaseIncrement = 2*pi .* relativeHz ./ obj.SampleRate_Hz;
            phase = obj.Phase_rad + cumsum([0; phaseIncrement(1:end-1)]);
            y = x .* cast(exp(1j .* phase), "like", x);
            if ~isempty(phaseIncrement)
                obj.Phase_rad = phase(end) + phaseIncrement(end);
            end
            obj.SampleIndex = obj.SampleIndex + size(x,1);
            trace = struct( ...
                "RelativeCFO_Hz", relativeHz, ...
                "Phase_rad", phase, ...
                "EndPhase_rad", obj.Phase_rad, ...
                "SampleIndex", obj.SampleIndex, ...
                "StateEpoch", obj.StateEpoch);
        end
    end
end
