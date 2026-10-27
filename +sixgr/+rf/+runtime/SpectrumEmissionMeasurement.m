classdef SpectrumEmissionMeasurement
%SPECTRUMEMISSIONMEASUREMENT Explicit RBW/band emission integration.

    methods(Static)
        function result=measure(samples,sampleRateHz,profile)
            required=["ProfileID","Version","BandCenters_Hz", ...
                "Bandwidths_Hz","Limits_dB"];
            if ~isstruct(profile)||~isscalar(profile)||~all(isfield(profile,required)) || ...
                    ~isnumeric(samples)||~ismatrix(samples)||isempty(samples)||any(~isfinite(samples(:))) || ...
                    ~(isnumeric(sampleRateHz)&&isreal(sampleRateHz)&&isscalar(sampleRateHz)&&isfinite(sampleRateHz)&&sampleRateHz>0)
                error("RF:SpectrumMeasurementInvalid", ...
                    "Spectrum-emission measurement profile or waveform is invalid.");
            end
            for field=["BandCenters_Hz","Bandwidths_Hz","Limits_dB"]
                value=profile.(field);
                if ~(isnumeric(value)&&isreal(value)&&isvector(value))
                    error('RF:SpectrumMeasurementInvalid','Emission bands and limits must be real numeric vectors.');
                end
            end
            for field=["ProfileID","Version"]
                value=string(profile.(field));
                if ~isscalar(value)||ismissing(value)||strlength(strtrim(value))==0
                    error('RF:SpectrumMeasurementInvalid','An explicit scalar profile identity and version are required.');
                end
            end
            centers=double(profile.BandCenters_Hz(:));
            widths=double(profile.Bandwidths_Hz(:));
            limits=double(profile.Limits_dB(:));
            if isempty(centers)||numel(centers)~=numel(widths)||numel(widths)~=numel(limits)|| ...
                    any(~isfinite([centers;widths;limits]))||any(widths<=0)|| ...
                    any(abs(centers)+widths/2>sampleRateHz/2)
                error("RF:SpectrumMeasurementInvalid", ...
                    "Spectrum-emission bands are invalid.");
            end
            % Columns are simultaneous ports. Concatenating them invents
            % discontinuities and changes the observation duration.
            if isvector(samples), samples=samples(:); end
            count=size(samples,1); ports=size(samples,2);
            n=sixgr.util.structGet(profile,'FFTSize',max(4096,2^nextpow2(count)));
            if ~(isnumeric(n)&&isreal(n)&&isscalar(n)&&isfinite(n)&&n>=count&&n==fix(n))
                error('RF:SpectrumMeasurementInvalid','FFTSize must be an integer at least the captured sample count.');
            end
            n=double(n);
            spectrum=abs(fftshift(fft(double(samples),n,1),1)).^2/(n*count);
            frequency=(-floor(n/2):ceil(n/2)-1).'*double(sampleRateHz)/n;
            power=zeros(numel(centers),ports);
            for k=1:numel(centers)
                mask=frequency>=centers(k)-widths(k)/2 & frequency<centers(k)+widths(k)/2;
                if ~any(mask)
                    error('RF:SpectrumMeasurementInvalid','A requested emission band contains no FFT bins.');
                end
                power(k,:)=sum(spectrum(mask,:),1);
            end
            % Zero power remains -Inf, not an artificial finite noise floor.
            measured=10*log10(power(:));
            bandCount=numel(centers); rows=bandCount*ports;
            centers=repmat(centers,ports,1); widths=repmat(widths,ports,1);
            limits=repmat(limits,ports,1);
            result=table(centers,widths,limits,measured,limits-measured, ...
                repmat(string(profile.ProfileID),rows,1), ...
                repmat(string(profile.Version),rows,1), ...
                measured<=limits,'VariableNames', ...
                {'Center_Hz','Bandwidth_Hz','Limit_dB','Measured_dB', ...
                'Margin_dB','ProfileID','Version','Passed'});
            result.PortIndex=reshape(repelem((1:ports)',bandCount),[],1);
            result.MeasuredPower_InputAmplitudeSquared=power(:);
            result.CaptureSampleCount=repmat(count,rows,1);
            result.SampleRateHz=repmat(double(sampleRateHz),rows,1);
            result.Nfft=repmat(n,rows,1);
            result.FrequencyBinSpacing_Hz=repmat(double(sampleRateHz)/n,rows,1);
            result.IntegratedSpectrumPower=reshape(repelem(sum(spectrum,1).',bandCount),[],1);
            result.TimeDomainPower=reshape(repelem(mean(abs(double(samples)).^2,1).',bandCount),[],1);
            result.PowerUnit=repmat("input_amplitude_squared_not_implicitly_watts",rows,1);
            result.PowerDBReference=repmat("one_input_amplitude_squared",rows,1);
            result.MeasurementMethod=repmat("per_port_fft_integrated_explicit_rectangular_bands",rows,1);
            result.WaveformSHA256=repmat(string(sixgr.phy.waveform.WaveformHash.numeric(samples)),rows,1);
            result.RFConformanceQualified=false(rows,1);
        end
    end
end
