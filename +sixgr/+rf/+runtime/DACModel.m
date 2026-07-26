classdef DACModel
%DACMODEL Explicit Tx DAC with signed code, dither and aperture jitter.

    methods(Static)
        function result = convert(input, profile, sampleRateHz, seed)
            required = ["Bits","FullScale","Convention","DitherRMS", ...
                "ApertureJitter_s","ProfileID","Version"];
            if ~isstruct(profile) || ~all(isfield(profile, required)) || ...
                    ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && ...
                    sampleRateHz > 0) || ~(isscalar(seed) && isfinite(seed))
                error("RF:DACProfileMissing", ...
                    "DAC conversion requires an explicit versioned profile.");
            end
            ditherRMS = double(profile.DitherRMS);
            jitter = double(profile.ApertureJitter_s);
            if ~(isscalar(ditherRMS) && isfinite(ditherRMS) && ditherRMS >= 0) || ...
                    ~(isscalar(jitter) && isfinite(jitter) && jitter >= 0)
                error("RF:DACProfileMissing", ...
                    "DAC dither and aperture jitter must be finite and nonnegative.");
            end
            stream = RandStream("Threefry", "Seed", double(seed));
            dither = ditherRMS/sqrt(2) .* ...
                (randn(stream,size(input))+1j*randn(stream,size(input)));
            if isreal(input)
                dither = real(dither);
            end
            quantized = sixgr.rf.runtime.ADCModel.quantize( ...
                input+cast(dither,"like",input), struct( ...
                "Bits",profile.Bits,"FullScale",profile.FullScale, ...
                "Convention",profile.Convention));
            apertureError = zeros(size(input));
            if jitter > 0 && size(input,1) > 1
                derivative = [zeros(1,size(input,2)); diff(double(input),1,1)] .* ...
                    double(sampleRateHz);
                timeError = jitter .* randn(stream,size(input,1),1);
                apertureError = derivative .* timeError;
            end
            output = double(quantized.Output) + apertureError;
            result = quantized;
            result.Output = cast(output,"like",input);
            result.QuantizationError = output-double(input);
            result.ErrorVariance = mean(abs(result.QuantizationError(:)).^2);
            result.Dither = cast(dither,"like",input);
            result.ApertureError = apertureError;
            result.ProfileID = string(profile.ProfileID);
            result.Version = string(profile.Version);
            result.SampleRate_Hz = double(sampleRateHz);
            result.Source = "explicit_dac_runtime";
        end
    end
end
