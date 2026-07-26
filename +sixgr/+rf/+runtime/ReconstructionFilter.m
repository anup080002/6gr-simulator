classdef ReconstructionFilter
%RECONSTRUCTIONFILTER Explicit stateful Tx reconstruction FIR.

    methods(Static)
        function profile = validate(profile, sampleRateHz)
            required = ["ProfileID","Version","Taps","Passband_Hz", ...
                "Stopband_Hz"];
            if ~isstruct(profile) || ~all(isfield(profile, required))
                error("RF:ReconstructionFilterMissing", ...
                    "Reconstruction filter profile is incomplete.");
            end
            taps = double(profile.Taps(:));
            passband = double(profile.Passband_Hz);
            stopband = double(profile.Stopband_Hz);
            if isempty(taps) || any(~isfinite(taps)) || ...
                    abs(sum(taps)) <= eps || ~(passband > 0 && ...
                    stopband > passband && stopband < sampleRateHz/2)
                error("RF:ReconstructionFilterMissing", ...
                    "Reconstruction filter taps or bands are invalid.");
            end
            profile.Taps = taps./sum(taps);
            profile.SampleRate_Hz = double(sampleRateHz);
        end

        function [output, state, evidence] = apply(input, profile, state)
            profile = sixgr.rf.runtime.ReconstructionFilter.validate( ...
                profile, profile.SampleRate_Hz);
            if nargin < 3 || isempty(state)
                state = zeros(numel(profile.Taps)-1,size(input,2));
            end
            if size(state,1) ~= numel(profile.Taps)-1 || ...
                    size(state,2) ~= size(input,2)
                error("RF:FilterStateInvalid", ...
                    "Reconstruction-filter state dimensions are invalid.");
            end
            output = zeros(size(input), "like", input);
            nextState = zeros(size(state), "like", input);
            for port=1:size(input,2)
                [output(:,port), nextState(:,port)] = filter( ...
                    profile.Taps, 1, input(:,port), state(:,port));
            end
            state = nextState;
            evidence = struct("ProfileID",string(profile.ProfileID), ...
                "Version",string(profile.Version), ...
                "TapCount",numel(profile.Taps), ...
                "StateSamples",size(state,1), ...
                "ReferencePlane","POST_RECONSTRUCTION_FILTER");
        end
    end
end
