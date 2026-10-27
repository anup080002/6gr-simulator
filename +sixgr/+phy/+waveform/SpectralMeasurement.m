classdef SpectralMeasurement
    %SPECTRALMEASUREMENT Declared PSD/RBW and Parseval closure.
    methods (Static)
        function result=measure(samples,sampleRate,varargin)
            if ~isnumeric(samples)||~ismatrix(samples)||isempty(samples)||any(~isfinite(samples(:)))|| ...
                    ~(isnumeric(sampleRate)&&isreal(sampleRate)&&isscalar(sampleRate)&&isfinite(sampleRate)&&sampleRate>0)
                error('WAVEFORM:SpectralConfigurationInvalid','Require finite time-by-port samples and a positive real sample rate.');
            end
            if isvector(samples), samples=samples(:); end
            ip=inputParser;
            ip.addParameter("FFTSize",size(samples,1),@(x)isnumeric(x)&&isscalar(x));
            ip.addParameter("AnalysisWindow","rectangular",@(x)ischar(x)||isstring(x));
            ip.addParameter("SegmentOverlap",0,@isnumeric);
            ip.addParameter("OccupiedBand_Hz",[-sampleRate/4 sampleRate/4],@isnumeric);
            ip.addParameter("GuardBands_Hz",[-sampleRate/2 -sampleRate/4;sampleRate/4 sampleRate/2],@isnumeric);
            ip.parse(varargin{:});
            nfft=double(ip.Results.FFTSize);
            if ~isreal(nfft)||~isfinite(nfft)||nfft<size(samples,1)||nfft<1||nfft~=fix(nfft)
                error("WAVEFORM:SpectralConfigurationInvalid","Spectral FFT size is invalid.");
            end
            overlap=ip.Results.SegmentOverlap;
            if ~(isreal(overlap)&&isscalar(overlap)&&isfinite(overlap)&&overlap==0)
                error('WAVEFORM:SpectralConfigurationInvalid','This single-segment operator requires SegmentOverlap=0.');
            end
            name=lower(string(ip.Results.AnalysisWindow));
            switch name
                case "rectangular",w=ones(size(samples,1),1);
                case "hann"
                    if size(samples,1)<3
                        error('WAVEFORM:SpectralConfigurationInvalid','Symmetric Hann analysis needs at least three samples.');
                    end
                    w=0.5-0.5*cos(2*pi*(0:size(samples,1)-1).'/(size(samples,1)-1));
                otherwise,error("WAVEFORM:SpectralConfigurationInvalid","Unknown analysis window.");
            end
            x=double(samples).*w;
            windowPower=mean(w.^2);
            spectrum=fftshift(fft(x,nfft,1),1);
            perPortPSD=abs(spectrum).^2/(sampleRate*size(x,1)*windowPower);
            % Legacy scalar outputs are explicitly summed port powers, never
            % a concatenated waveform, coherent array field or TRP estimate.
            psd=sum(perPortPSD,2);
            frequency=(-floor(nfft/2):ceil(nfft/2)-1).'*sampleRate/nfft;
            binSpacing=sampleRate/nfft;
            enbw=sampleRate*sum(w.^2)/sum(w)^2;
            spectralPerPort=sum(perPortPSD,1)*binSpacing;
            timePerPort=mean(abs(x).^2,1)/windowPower;
            spectralPower=sum(spectralPerPort); timePower=sum(timePerPort);
            errorDB=10*log10(spectralPower/timePower);
            perPortError=10*log10(spectralPerPort./timePerPort);
            silent=timePerPort==0 & spectralPerPort==0;
            perPortError(silent)=0; % Exact zero-energy Parseval equality.
            if timePower==0 && spectralPower==0, errorDB=0; end
            occupied=double(ip.Results.OccupiedBand_Hz);
            bands=double(ip.Results.GuardBands_Hz);
            if ~(isreal(occupied)&&numel(occupied)==2&&all(isfinite(occupied))&& ...
                    occupied(1)<occupied(2)&&occupied(1)>=-sampleRate/2&&occupied(2)<=sampleRate/2) || ...
                    ~isreal(bands)||size(bands,2)~=2||any(~isfinite(bands(:)))|| ...
                    any(bands(:,1)>=bands(:,2))||any(abs(bands(:))>sampleRate/2)
                error('WAVEFORM:SpectralConfigurationInvalid','Occupied/guard bands must have finite ordered edges within the captured bandwidth.');
            end
            occupiedMask=frequency>=occupied(1)&frequency<occupied(2);
            guardMask=false(size(frequency));
            for i=1:size(bands,1)
                guardMask=guardMask|(frequency>=bands(i,1)&frequency<bands(i,2));
            end
            result=struct("Frequency_Hz",frequency,"PSD",psd, ...
                "PSD_dB_per_Hz",10*log10(psd), ...
                "SampleRate_Hz",double(sampleRate),"FFTSize",nfft, ...
                "AnalysisWindow",name,"SegmentOverlap",double(ip.Results.SegmentOverlap), ...
                "RBW_Hz",enbw,"FrequencyBinSpacing_Hz",binSpacing, ...
                "RBWDefinition","window_equivalent_noise_bandwidth", ...
                "Averaging","single_coherent_segment", ...
                "OccupiedPower",sum(psd(occupiedMask))*binSpacing, ...
                "GuardPower",sum(psd(guardMask))*binSpacing, ...
                "SpectralIntegralPower",spectralPower, ...
                "TimeDomainPower",timePower,"Error_dB",errorDB, ...
                "PSDPerPort",perPortPSD,"NumPorts",size(samples,2), ...
                "SpectralIntegralPowerPerPort",spectralPerPort, ...
                "TimeDomainPowerPerPort",timePerPort,"ErrorPerPort_dB",perPortError, ...
                "ZeroPowerPorts",silent,"Aggregation","sum_of_independent_port_powers", ...
                "PowerUnit","input_amplitude_squared_not_implicitly_watts", ...
                "RFConformanceQualified",false, ...
                "WaveformSHA256",sixgr.phy.waveform.WaveformHash.numeric(samples));
            if ~isfinite(errorDB)||any(~isfinite(perPortError))||abs(errorDB)>.01||any(abs(perPortError)>.01)
                error("WAVEFORM:PowerLedgerMismatch", ...
                    "Spectral/time power mismatch %.4g dB exceeds 0.01 dB.",errorDB);
            end
        end
    end
end
