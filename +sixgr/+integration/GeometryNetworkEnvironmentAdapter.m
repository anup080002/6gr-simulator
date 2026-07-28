classdef GeometryNetworkEnvironmentAdapter
    %GEOMETRYNETWORKENVIRONMENTADAPTER Runtime link/power/interference adapter.
    properties (SetAccess=immutable)
        Seed (1,1) double
        Stream
    end
    methods
        function obj = GeometryNetworkEnvironmentAdapter(seed)
            obj.Seed = double(seed);
            obj.Stream = RandStream("Threefry","Seed",obj.Seed);
        end
        function result = apply(obj,linkInputs,noiseVariance,varargin)
            ip = inputParser;
            ip.addParameter("NoiseUnitSamples",[],@isnumeric);
            ip.addParameter("SampleToGridNoiseVarianceGain",[], ...
                @(v) isempty(v) || (isnumeric(v) && isscalar(v) && ...
                isreal(v) && isfinite(v) && v > 0));
            ip.parse(varargin{:});
            if ~iscell(linkInputs) || isempty(linkInputs)
                error("sixgr:integration:WaveformInterferenceRequired", ...
                    "Geometry mode requires explicit sample-domain links.");
            end
            contributions = cell(size(linkInputs));
            channelMetadata = cell(size(linkInputs));
            for ii = 1:numel(linkInputs)
                item = linkInputs{ii};
                if ~isfield(item,"Samples") || ~isfield(item,"Link")
                    error("sixgr:integration:WaveformInterferenceRequired", ...
                        "Each geometry link requires waveform samples and channel state.");
                end
                [samples,channelMetadata{ii}] = ...
                    sixgr.integration.ChannelApplicationContract.apply( ...
                    item.Samples,item.Link);
                contributions{ii} = struct("LinkID", ...
                    string(item.Link.LinkID),"Samples",samples);
            end
            [clean,ledger] = sixgr.integration.SampleDomainLinkGraph.compose( ...
                contributions);
            unit = ip.Results.NoiseUnitSamples;
            if isempty(unit)
                unit = (randn(obj.Stream,size(clean)) + ...
                    1j*randn(obj.Stream,size(clean)))/sqrt(2);
            end
            unitPower = mean(abs(double(unit(:))).^2);
            noise = complex(double(unit))*sqrt(double(noiseVariance)/unitPower);
            gridGain = ip.Results.SampleToGridNoiseVarianceGain;
            if isempty(gridGain)
                measuredSNR = 10*log10( ...
                    mean(abs(clean(:)).^2)/mean(abs(noise(:)).^2));
                referencePlane = "receiver_input_before_frontend_noise";
            else
                measuredSNR = 10*log10(1 / ...
                    (mean(abs(noise(:)).^2) * double(gridGain)));
                referencePlane = ...
                    "occupied_resource_grid_re_after_ofdm_demodulation";
            end
            result = struct("Samples",clean+noise,"CleanSamples",clean, ...
                "NoiseSamples",noise,"SignalPower",mean(abs(clean(:)).^2), ...
                "NoiseVariance",double(noiseVariance), ...
                "MeasuredInputSNR_dB",measuredSNR, ...
                "ReferencePlane",referencePlane, ...
                "SampleToGridNoiseVarianceGain",double(gridGain), ...
                "Adapter","GeometryNetworkEnvironmentAdapter", ...
                "ContributionLedger",ledger, ...
                "ChannelMetadata",{channelMetadata});
        end
    end
end
