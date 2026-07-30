classdef OFDMParameterResolver
    %OFDMPARAMETERRESOLVER Strict carrier/BWP timing resolution.

    methods (Static)
        function result = resolve(carrier,varargin)
            try
                cp = lower(string(carrier.CyclicPrefix));
                scs = double(carrier.SubcarrierSpacing);
                if cp == "extended" && scs ~= 60
                    error("WAVEFORM:InvalidOFDMParameters", ...
                        "Extended CP is supported only at 60 kHz.");
                end
                result = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
                    carrier,varargin{:});
            catch exception
                identifier = string(exception.identifier);
                if identifier == "WAVEFORM:InvalidOFDMParameters" || ...
                        startsWith(identifier,"sixgr:phy:frame:")
                    rethrow(exception);
                end
                wrapped = MException("WAVEFORM:InvalidOFDMParameters", ...
                    "Strict OFDM parameter resolution failed: %s", ...
                    exception.message);
                wrapped = addCause(wrapped,exception);
                throwAsCaller(wrapped);
            end
            result.ProfileID = "nr_rel19_cp_ofdm_strict";
            result.Specification = ...
                sixgr.phy.waveform.WaveformSpecificationProfile.TS38211;
            result.NoFallback = true;
        end
    end
end
