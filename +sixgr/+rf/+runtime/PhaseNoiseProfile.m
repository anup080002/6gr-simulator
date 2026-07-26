classdef PhaseNoiseProfile
%PHASENOISEPROFILE Explicit versioned oscillator-mask profile.

    methods(Static)
        function profile=validate(profile)
            required=["ProfileID","Version","SampleRate_Hz","CarrierFrequency_Hz", ...
                "MaskOffsets_Hz","MaskLevels_dBcHz","LOCorrelation","Seed"];
            if ~isstruct(profile)||~all(isfield(profile,required))
                error("RF:PhaseNoiseMaskMissing", ...
                    "Strict phase noise requires a versioned explicit mask.");
            end
            offsets=double(profile.MaskOffsets_Hz(:));
            levels=double(profile.MaskLevels_dBcHz(:));
            correlation=double(profile.LOCorrelation);
            if numel(offsets)<2||numel(offsets)~=numel(levels)|| ...
                    any(~isfinite(offsets))||any(~isfinite(levels))|| ...
                    any(offsets<=0)||any(diff(offsets)<=0)|| ...
                    any(offsets>=double(profile.SampleRate_Hz)/2)|| ...
                    ~isfinite(correlation)||correlation<=-1||correlation>1|| ...
                    strlength(strtrim(string(profile.Version)))==0
                error("RF:PhaseNoiseMaskMissing", ...
                    "Phase-noise mask values, correlation or provenance are invalid.");
            end
            profile.MaskOffsets_Hz=offsets;
            profile.MaskLevels_dBcHz=levels;
            profile.LOCorrelation=correlation;
            profile.IntegratedVariance_rad2= ...
                sixgr.rf.runtime.oracle.PhaseNoisePSDOracle. ...
                integratedVariance(offsets,levels);
            profile.RMSPhase_rad=sqrt(profile.IntegratedVariance_rad2);
            profile.Claim="runtime_calibrated_mask_model";
        end

        function variance=integratedVariance(offsets,levels)
            variance=sixgr.rf.runtime.oracle.PhaseNoisePSDOracle. ...
                integratedVariance(offsets,levels);
        end
    end
end
