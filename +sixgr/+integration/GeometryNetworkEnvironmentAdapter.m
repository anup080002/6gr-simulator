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
            result = struct("Samples",clean+noise,"CleanSamples",clean, ...
                "NoiseSamples",noise,"SignalPower",mean(abs(clean(:)).^2), ...
                "NoiseVariance",double(noiseVariance), ...
                "MeasuredInputSNR_dB",10*log10( ...
                mean(abs(clean(:)).^2)/mean(abs(noise(:)).^2)), ...
                "ReferencePlane","receiver_input_before_frontend_noise", ...
                "Adapter","GeometryNetworkEnvironmentAdapter", ...
                "ContributionLedger",ledger, ...
                "ChannelMetadata",{channelMetadata});
        end
    end
end
