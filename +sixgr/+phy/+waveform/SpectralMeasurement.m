classdef SpectralMeasurement
    %SPECTRALMEASUREMENT Declared PSD/RBW and Parseval closure.
    methods (Static)
        function result=measure(samples,sampleRate,varargin)
            ip=inputParser;
            ip.addParameter("FFTSize",size(samples,1),@(x)isnumeric(x)&&isscalar(x));
            ip.addParameter("AnalysisWindow","rectangular",@(x)ischar(x)||isstring(x));
            ip.addParameter("SegmentOverlap",0,@isnumeric);
            ip.addParameter("OccupiedBand_Hz",[-sampleRate/4 sampleRate/4],@isnumeric);
            ip.addParameter("GuardBands_Hz",[-sampleRate/2 -sampleRate/4;sampleRate/4 sampleRate/2],@isnumeric);
            ip.parse(varargin{:});
            nfft=double(ip.Results.FFTSize);
            if nfft<size(samples,1)||nfft<1||nfft~=fix(nfft)
                error("WAVEFORM:SpectralConfigurationInvalid","Spectral FFT size is invalid.");
            end
            name=lower(string(ip.Results.AnalysisWindow));
            switch name
                case "rectangular",w=ones(size(samples,1),1);
                case "hann",w=0.5-0.5*cos(2*pi*(0:size(samples,1)-1).'/(size(samples,1)-1));
                otherwise,error("WAVEFORM:SpectralConfigurationInvalid","Unknown analysis window.");
            end
            x=double(samples(:,1)).*w;
            windowPower=mean(w.^2);
            spectrum=fftshift(fft(x,nfft));
            psd=abs(spectrum).^2/(sampleRate*numel(x)*windowPower);
            frequency=(-nfft/2:nfft/2-1).'*sampleRate/nfft;
            rbw=sampleRate/nfft;
            spectralPower=sum(psd)*rbw;
            timePower=mean(abs(x).^2)/windowPower;
            errorDB=10*log10(max(spectralPower,realmin)/max(timePower,realmin));
            occupied=ip.Results.OccupiedBand_Hz;
            occupiedMask=frequency>=occupied(1)&frequency<occupied(2);
            guardMask=false(size(frequency));
            bands=ip.Results.GuardBands_Hz;
            for i=1:size(bands,1)
                guardMask=guardMask|(frequency>=bands(i,1)&frequency<bands(i,2));
            end
            result=struct("Frequency_Hz",frequency,"PSD",psd, ...
                "PSD_dB_per_Hz",10*log10(max(psd,realmin)), ...
                "SampleRate_Hz",double(sampleRate),"FFTSize",nfft, ...
                "AnalysisWindow",name,"SegmentOverlap",double(ip.Results.SegmentOverlap), ...
                "RBW_Hz",rbw,"Averaging","single_coherent_segment", ...
                "OccupiedPower",sum(psd(occupiedMask))*rbw, ...
                "GuardPower",sum(psd(guardMask))*rbw, ...
                "SpectralIntegralPower",spectralPower, ...
                "TimeDomainPower",timePower,"Error_dB",errorDB, ...
                "WaveformSHA256",sixgr.phy.waveform.WaveformHash.numeric(samples));
            if abs(errorDB)>.01
                error("WAVEFORM:PowerLedgerMismatch", ...
                    "Spectral/time power mismatch %.4g dB exceeds 0.01 dB.",errorDB);
            end
        end
    end
end
