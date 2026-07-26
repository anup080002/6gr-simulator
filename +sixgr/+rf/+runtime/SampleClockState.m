classdef SampleClockState < handle
%SAMPLECLOCKSTATE Persistent sample-clock phase and timestamp state.

    properties(SetAccess=private)
        SampleRate_Hz (1,1) double
        SCO_ppm (1,1) double
        TimingOffset_samples (1,1) double
        InputSamples (1,1) double = 0
        FractionalPhase (1,1) double = 0
        StateEpoch (1,1) double
    end

    methods
        function obj = SampleClockState(sampleRateHz, scoPpm, ...
                timingOffsetSamples, stateEpoch)
            arguments
                sampleRateHz (1,1) double {mustBeFinite,mustBePositive}
                scoPpm (1,1) double {mustBeFinite}
                timingOffsetSamples (1,1) double {mustBeFinite} = 0
                stateEpoch (1,1) double {mustBeFinite} = 1
            end
            if 1+scoPpm*1e-6 <= 0
                error("RF:SampleClockProfileMissing", ...
                    "Sample-clock rate ratio must be positive.");
            end
            obj.SampleRate_Hz = sampleRateHz;
            obj.SCO_ppm = scoPpm;
            obj.TimingOffset_samples = timingOffsetSamples;
            obj.FractionalPhase = mod(timingOffsetSamples, 1);
            obj.StateEpoch = stateEpoch;
        end

        function trace = advance(obj, sampleCount, expectedEpoch)
            if double(expectedEpoch) ~= obj.StateEpoch || ...
                    ~(isscalar(sampleCount) && isfinite(sampleCount) && ...
                    sampleCount == round(sampleCount) && sampleCount >= 0)
                error("RF:StateEpochMismatch", ...
                    "Sample-clock advance is invalid or from the wrong epoch.");
            end
            startIndex = obj.InputSamples;
            obj.InputSamples = obj.InputSamples + double(sampleCount);
            drift = obj.InputSamples * obj.SCO_ppm * 1e-6;
            obj.FractionalPhase = mod(obj.TimingOffset_samples + drift, 1);
            trace = struct("StartInputSample", startIndex, ...
                "EndInputSample", obj.InputSamples, ...
                "CumulativeDrift_samples", drift, ...
                "FractionalPhase", obj.FractionalPhase, ...
                "LastTimestamp_s", (obj.TimingOffset_samples + ...
                obj.InputSamples*(1+obj.SCO_ppm*1e-6))/obj.SampleRate_Hz, ...
                "StateEpoch", obj.StateEpoch);
        end
    end
end
