classdef PAPRMeasurement
    %PAPRMEASUREMENT Oversampled PAPR and empirical CCDF evidence.
    methods (Static)
        function rows=measure(samples,factors,varargin)
            ip=inputParser;
            ip.addParameter("ReferenceDomain","useful_samples",@(x)ischar(x)||isstring(x));
            ip.addParameter("PayloadID","PAYLOAD",@(x)ischar(x)||isstring(x));
            ip.parse(varargin{:});
            if ~isnumeric(samples)||~ismatrix(samples)||isempty(samples)||any(~isfinite(samples(:)))
                error("WAVEFORM:PAPRInvalidSamples","PAPR needs finite time-by-port waveform samples.");
            end
            if isvector(samples), samples=samples(:); end
            factors=double(factors(:));
            if isempty(factors)||any(~isfinite(factors))
                error("WAVEFORM:PAPRInsufficientOversampling","Explicit finite interpolation factors are required.");
            end
            chunks=cell(numel(factors),1); ports=size(samples,2);
            for i=1:numel(factors)
                factor=factors(i);
                if factor<1||factor~=fix(factor)
                    error("WAVEFORM:PAPRInsufficientOversampling","Oversampling factor is invalid.");
                end
                x=samples;
                if factor>1,x=interpft(samples,size(samples,1)*factor,1);end
                power=abs(double(x)).^2;
                peak=max(power,[],1).'; average=mean(power,1).';
                papr=10*log10(peak./average); % Silent ports are undefined, not zero PAPR.
                status=repmat("measured",ports,1); status(average==0)="undefined_zero_power";
                chunks{i}=table(repmat(factor,ports,1),papr, ...
                    repmat(string(ip.Results.ReferenceDomain),ports,1), ...
                    repmat(string(ip.Results.PayloadID),ports,1),(1:ports)',peak,average, ...
                    repmat(size(x,1),ports,1),repmat(size(samples,1),ports,1),status, ...
                    repmat("additional_periodic_fft_interpolation_of_input_block",ports,1), ...
                    'VariableNames',{'OversamplingFactor','PAPR_dB','ReferenceDomain','PayloadID', ...
                    'PortIndex','PeakPower_InputAmplitudeSquared','MeanPower_InputAmplitudeSquared', ...
                    'MeasuredSampleCount','InputSampleCount','MeasurementStatus','OversamplingDefinition'});
            end
            rows=vertcat(chunks{:});
        end
        function row=ccdf(values,threshold,confidence)
            if nargin<3,confidence=.95;end
            if ~isnumeric(values)||~isvector(values)||isempty(values)||any(~isfinite(values(:)))|| ...
                    ~isscalar(threshold)||~isfinite(threshold)|| ...
                    ~isscalar(confidence)||~isfinite(confidence)||confidence<=0||confidence>=1
                error("WAVEFORM:PAPRInvalidCCDF","CCDF requires finite observations, threshold and confidence in (0,1).");
            end
            n=numel(values);k=sum(values(:)>threshold);p=k/n;
            z=-sqrt(2)*erfcinv(2*(1-(1-confidence)/2));
            den=1+z^2/n;
            center=(p+z^2/(2*n))/den;
            half=z*sqrt(p*(1-p)/n+z^2/(4*n^2))/den;
            row=struct("Threshold_dB",threshold,"Exceedances",k, ...
                "Trials",n,"CCDF",p,"LowerCI",max(0,center-half), ...
                "UpperCI",min(1,center+half),"ConfidenceLevel",confidence, ...
                "IntervalMethod","Wilson_assumes_independent_observations", ...
                "ThresholdComparator",">");
        end
    end
end
