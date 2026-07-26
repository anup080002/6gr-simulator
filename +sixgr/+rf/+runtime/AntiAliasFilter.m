classdef AntiAliasFilter
%ANTIALIASFILTER Explicit ADC anti-alias filter facade.

    methods(Static)
        function [output,state,evidence] = apply(input,profile,state)
            if ~isstruct(profile) || ~isfield(profile,"SampleRate_Hz") || ...
                    ~isfield(profile,"ADCOutputRate_Hz") || ...
                    double(profile.Stopband_Hz) >= ...
                    min(double(profile.SampleRate_Hz), ...
                    double(profile.ADCOutputRate_Hz))/2
                error("RF:AntiAliasFilterMissing", ...
                    "Anti-alias filter must stop below the output Nyquist frequency.");
            end
            [output,state,evidence]=sixgr.rf.runtime.RFSelectivityFilter.apply( ...
                input,profile,state);
            evidence.ReferencePlane="ADC_INPUT";
            evidence.ADCOutputRate_Hz=double(profile.ADCOutputRate_Hz);
        end
    end
end
