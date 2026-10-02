classdef SpectralPhaseNoiseFilter < handle
% Stationary real Gaussian phase from an explicit two-sided PSD.
% Full FIR convolution with retained white history: no per-chunk spectral
% regeneration, RMS renormalization, or phase reset. S_phi(f)=10^(L(f)/10)
% on each side, consistent with variance=2*integral 10^(L/10) df.
    properties(Access=private)
        Impulse
        History
        Stream
        Correlation
    end
    methods
        function obj=SpectralPhaseNoiseFilter(profile,chains)
            obj.Impulse=sixgr.rf.runtime.SpectralPhaseNoiseFilter.design(profile);
            obj.Stream=RandStream('Threefry','Seed',double(profile.Seed));
            obj.Correlation=profile.LOCorrelation;
            % Stationary prehistory avoids startup transients. It belongs to
            % this oscillator's independent RNG, not the channel/payload RNG.
            obj.History=obj.draw(numel(obj.Impulse)-1,chains);
        end
        function phase=apply(obj,n,chains)
            fresh=obj.draw(n,chains); historyLength=size(obj.History,1);
            extended=[obj.History;fresh];
            filtered=fftfilt(obj.Impulse,extended);
            phase=real(filtered(historyLength+1:end,:));
            obj.History=extended(end-historyLength+1:end,:);
        end
    end
    methods(Access=private)
        function w=draw(obj,n,chains)
            w=randn(obj.Stream,chains,n).';
            w=sixgr.rf.runtime.PhaseNoiseCorrelationState.apply(w,obj.Correlation);
        end
    end
    methods(Static)
        function b=design(profile)
            n=double(profile.FIRLength); fs=double(profile.SampleRate_Hz);
            validateattributes(n,{'numeric'},{'scalar','integer','>=',32});
            assert(mod(n,2)==0,'RF:PhaseNoiseFIRLength','FIR length must be even.');
            offsets=double(profile.MaskOffsets_Hz(:)); levels=double(profile.MaskLevels_dBcHz(:));
            assert(fs/n<=offsets(1)/8,'RF:PhaseNoiseFIRResolution', ...
                'FIR frequency resolution must be <= minimum mask offset / 8. Increase fir_length.');
            f=(0:n-1).'*fs/n; f=min(f,fs-f);
            % Explicit flat low-frequency and Nyquist-end continuations.
            f=max(offsets(1),min(offsets(end),f));
            l=interp1(log10(offsets),levels,log10(f),'linear');
            b=fftshift(real(ifft(sqrt(fs*10.^(l/10)))));
            response=freqz(b,1,2*pi*offsets/fs);
            errorDB=10*log10(abs(response).^2/fs)-levels;
            assert(max(abs(errorDB))<1,'RF:PhaseNoiseMaskFitFailed', ...
                'Spectral FIR must reproduce every configured mask point within 1 dB.');
        end
        function levels=evaluatePSD(profile,offsets)
            b=sixgr.rf.runtime.SpectralPhaseNoiseFilter.design(profile);
            response=freqz(b,1,2*pi*double(offsets(:))/profile.SampleRate_Hz);
            levels=10*log10(abs(response).^2/profile.SampleRate_Hz);
        end
    end
end
