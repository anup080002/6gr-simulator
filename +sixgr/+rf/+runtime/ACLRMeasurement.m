classdef ACLRMeasurement
%ACLRMEASUREMENT Filtered assigned/adjacent-channel power measurement.

    methods(Static)
        function result=measure(samples,sampleRateHz,profile)
            required=["FilterID","AssignedCenter_Hz","AdjacentOffset_Hz", ...
                "MeasurementBandwidth_Hz"];
            if ~isstruct(profile)||~all(isfield(profile,required))
                error("RF:ACLRFilterInvalid", ...
                    "ACLR measurement requires an explicit filter profile.");
            end
            if isempty(samples)||any(~isfinite(samples(:)))|| ...
                    ~isfinite(sampleRateHz)||sampleRateHz<=0
                error("RF:ACLRFilterInvalid","ACLR waveform/sample rate is invalid.");
            end
            n=max(4096,2^nextpow2(numel(samples)));
            spectrum=fftshift(fft(double(samples(:)),n));
            power=abs(spectrum).^2/n^2;
            frequency=(-n/2:n/2-1).'*double(sampleRateHz)/n;
            bandwidth=double(profile.MeasurementBandwidth_Hz);
            center=double(profile.AssignedCenter_Hz);
            offset=double(profile.AdjacentOffset_Hz);
            if ~(isfinite(bandwidth)&&bandwidth>0&&isfinite(center)&& ...
                    isfinite(offset)&&offset>bandwidth/2)
                error("RF:ACLRFilterInvalid","ACLR band definition is invalid.");
            end
            assigned=sixgr.rf.runtime.ACLRMeasurement.bandPower( ...
                power,frequency,center,bandwidth);
            lower=sixgr.rf.runtime.ACLRMeasurement.bandPower( ...
                power,frequency,center-offset,bandwidth);
            upper=sixgr.rf.runtime.ACLRMeasurement.bandPower( ...
                power,frequency,center+offset,bandwidth);
            result=struct( ...
                "AssignedPower_dB",10*log10(max(assigned,realmin)), ...
                "AdjacentLowerPower_dB",10*log10(max(lower,realmin)), ...
                "AdjacentUpperPower_dB",10*log10(max(upper,realmin)), ...
                "ACLRLower_dB",10*log10(max(assigned,realmin)/max(lower,realmin)), ...
                "ACLRUpper_dB",10*log10(max(assigned,realmin)/max(upper,realmin)), ...
                "FilterID",string(profile.FilterID), ...
                "Method","fft_integrated_explicit_rectangular_filter");
        end
    end

    methods(Static,Access=private)
        function value=bandPower(power,frequency,center,bandwidth)
            mask=abs(frequency-center)<=bandwidth/2;
            if ~any(mask)
                error("RF:ACLRFilterInvalid", ...
                    "ACLR filter has no FFT bins at the selected sample rate.");
            end
            value=sum(power(mask));
        end
    end
end
