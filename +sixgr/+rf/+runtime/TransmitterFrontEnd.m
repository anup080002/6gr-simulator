classdef TransmitterFrontEnd < handle
%TRANSMITTERFRONTEND Canonical DAC/filter/CFR/DPD/PA chain.

    properties(SetAccess=private)
        Configuration struct
        ConfigurationEpoch (1,1) double
        FilterState double = zeros(0,1)
    end

    methods
        function obj=TransmitterFrontEnd(configuration,configurationEpoch)
            required=["SampleRate_Hz","DACProfile","ReconstructionFilterProfile", ...
                "CFRProfile","DPDProfile","PAProfile","Seed"];
            if ~isstruct(configuration)||~all(isfield(configuration,required))
                error("RF:TransmitterFrontEndIncomplete", ...
                    "Transmitter front end requires every explicit stage profile.");
            end
            sixgr.rf.runtime.DPDProfile.validate(configuration.DPDProfile);
            obj.Configuration=configuration;
            obj.ConfigurationEpoch=configurationEpoch;
        end

        function [output,evidence]=apply(obj,input,expectedEpoch)
            if double(expectedEpoch)~=obj.ConfigurationEpoch
                error("RF:StateEpochMismatch", ...
                    "Transmitter-front-end state epoch mismatch.");
            end
            cfg=obj.Configuration;
            dac=sixgr.rf.runtime.DACModel.convert(input,cfg.DACProfile, ...
                cfg.SampleRate_Hz,cfg.Seed);
            filterProfile=cfg.ReconstructionFilterProfile;
            filterProfile.SampleRate_Hz=cfg.SampleRate_Hz;
            [filtered,obj.FilterState,filterEvidence]= ...
                sixgr.rf.runtime.ReconstructionFilter.apply( ...
                dac.Output,filterProfile,obj.FilterState);
            [cfr,cfrEvidence]=sixgr.rf.runtime.CrestFactorReduction.apply( ...
                filtered,cfg.CFRProfile.ClipLevel_dB, ...
                cfg.CFRProfile.Iterations);
            dpd=sixgr.rf.runtime.DPDTrainer.apply(cfr,cfg.DPDProfile);
            [output,paEvidence]=sixgr.rf.runtime.PAProfile.apply( ...
                dpd,cfg.PAProfile);
            evidence=struct("DAC",rmfield(dac, ...
                ["Output","Code","QuantizationError","Dither","ApertureError"]), ...
                "ReconstructionFilter",filterEvidence,"CFR",cfrEvidence, ...
                "DPDCoefficientSHA256",string(cfg.DPDProfile.CoefficientSHA256), ...
                "PA",paEvidence,"PowerRestorationApplied",false, ...
                "ReferencePlane","PA_OUTPUT", ...
                "StateEpoch",obj.ConfigurationEpoch);
        end
    end
end
