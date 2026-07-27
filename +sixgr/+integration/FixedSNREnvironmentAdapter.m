classdef FixedSNREnvironmentAdapter
    %FIXEDS NRENVIRONMENTADAPTER Controlled receiver-input reference plane.
    properties (SetAccess=immutable)
        Seed (1,1) double
        Stream
    end
    methods
        function obj = FixedSNREnvironmentAdapter(seed)
            obj.Seed = double(seed);
            obj.Stream = RandStream("Threefry","Seed",obj.Seed);
        end
        function result = apply(obj,txSamples,configuredSNR,varargin)
            ip = inputParser;
            ip.addParameter("NoiseUnitSamples",[],@isnumeric);
            ip.parse(varargin{:});
            signalPower = mean(abs(double(txSamples(:))).^2);
            if ~isfinite(signalPower) || signalPower <= 0
                error("sixgr:integration:PowerReconciliationFailure", ...
                    "Fixed-SNR reference waveform must have positive finite power.");
            end
            noiseVariance = signalPower/10^(double(configuredSNR)/10);
            unit = ip.Results.NoiseUnitSamples;
            if isempty(unit)
                unit = (randn(obj.Stream,size(txSamples)) + ...
                    1j*randn(obj.Stream,size(txSamples)))/sqrt(2);
            end
            unitPower = mean(abs(double(unit(:))).^2);
            if unitPower <= 0 || ~isfinite(unitPower)
                error("sixgr:integration:PowerReconciliationFailure", ...
                    "Noise realization must have positive finite power.");
            end
            noise = complex(double(unit))*sqrt(noiseVariance/unitPower);
            received = complex(double(txSamples)) + noise;
            measured = 10*log10(signalPower/mean(abs(noise(:)).^2));
            result = struct("Samples",received,"CleanSamples",txSamples, ...
                "NoiseSamples",noise,"ConfiguredSNR_dB",double(configuredSNR), ...
                "AnalyticalInputSNR_dB",double(configuredSNR), ...
                "MeasuredInputSNR_dB",measured, ...
                "SignalPower",signalPower,"NoiseVariance",noiseVariance, ...
                "ReferencePlane","receiver_input_before_frontend_noise", ...
                "Adapter","FixedSNREnvironmentAdapter");
        end
    end
end
