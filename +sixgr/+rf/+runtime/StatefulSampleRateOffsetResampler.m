classdef StatefulSampleRateOffsetResampler < handle
%STATEFULSAMPLERATEOFFSETRESAMPLER Stateful cubic-Farrow SCO model.
%   The phase accumulator and interpolation history persist across chunks.

    properties(SetAccess=private)
        SCO_ppm (1,1) double
        RateRatio (1,1) double
        OccupiedBandwidth_Hz (1,1) double
        SampleRate_Hz (1,1) double
        Phase (1,1) double = 0
        InputCount (1,1) double = 0
        OutputCount (1,1) double = 0
        StateEpoch (1,1) double
    end

    properties(Access=private)
        History double = complex(zeros(0,1))
        AntiAliasTaps double = 1
        AntiAliasState double = zeros(0,1)
    end

    methods
        function obj = StatefulSampleRateOffsetResampler(sampleRateHz, scoPpm, ...
                occupiedBandwidthHz, stateEpoch)
            arguments
                sampleRateHz (1,1) double {mustBeFinite,mustBePositive}
                scoPpm (1,1) double {mustBeFinite}
                occupiedBandwidthHz (1,1) double {mustBeFinite,mustBeNonnegative}
                stateEpoch (1,1) double {mustBeFinite} = 1
            end
            ratio = 1 + scoPpm * 1e-6;
            if ratio <= 0 || occupiedBandwidthHz >= ...
                    0.5 * sampleRateHz / max(1, ratio)
                error("RF:ResamplerBandwidthViolation", ...
                    "SCO resampler cannot preserve the declared occupied bandwidth.");
            end
            obj.SampleRate_Hz = sampleRateHz;
            obj.SCO_ppm = scoPpm;
            obj.RateRatio = ratio;
            obj.OccupiedBandwidth_Hz = occupiedBandwidthHz;
            obj.StateEpoch = stateEpoch;
            [obj.AntiAliasTaps,aliasPower]= ...
                sixgr.rf.runtime.StatefulSampleRateOffsetResampler. ...
                designAntiAliasFilter(sampleRateHz,ratio,occupiedBandwidthHz);
            obj.AntiAliasState=zeros(numel(obj.AntiAliasTaps)-1,1);
            if aliasPower>-60
                error("RF:ResamplerBandwidthViolation", ...
                    "SCO anti-alias filter does not meet the -60 dBc stopband requirement.");
            end
        end

        function [y, trace] = process(obj, x, varargin)
            p = inputParser;
            p.addParameter("PreserveLength", false, ...
                @(v)islogical(v)||(isnumeric(v)&&isscalar(v)));
            p.addParameter("ExpectedEpoch", obj.StateEpoch);
            p.parse(varargin{:});
            if double(p.Results.ExpectedEpoch) ~= obj.StateEpoch
                error("RF:StateEpochMismatch", ...
                    "Resampler state epoch does not match the RF configuration epoch.");
            end
            if isempty(x) || any(~isfinite(x(:)))
                error("RF:NonFiniteSamples", ...
                    "SCO resampler requires finite nonempty samples.");
            end
            nIn = size(x,1);
            if size(obj.AntiAliasState,2)~=size(x,2)
                if obj.InputCount==0
                    obj.AntiAliasState=zeros(numel(obj.AntiAliasTaps)-1,size(x,2));
                else
                    error("RF:ResamplerStateInvalid", ...
                        "SCO RF-chain count changed after state initialization.");
                end
            end
            filtered=zeros(size(x),"like",x);
            nextFilterState=zeros(size(obj.AntiAliasState));
            for port=1:size(x,2)
                [filtered(:,port),nextFilterState(:,port)]=filter( ...
                    obj.AntiAliasTaps,1,x(:,port),obj.AntiAliasState(:,port));
            end
            obj.AntiAliasState=nextFilterState;
            if logical(p.Results.PreserveLength)
                nOut = nIn;
            else
                nOut = max(1, floor((obj.Phase + nIn - 1) / obj.RateRatio) + 1);
            end
            historyLength = size(obj.History,1);
            augmented = [obj.History; double(filtered)];
            startCoordinate = historyLength + obj.Phase;
            query = startCoordinate + (0:nOut-1).' .* obj.RateRatio;
            y = complex(zeros(nOut,size(x,2)));
            grid = (0:size(augmented,1)-1).';
            for port = 1:size(x,2)
                y(:,port) = interp1(grid, augmented(:,port), query, ...
                    "pchip", 0);
            end
            consumedCoordinate = obj.Phase + nOut * obj.RateRatio;
            obj.Phase = consumedCoordinate - nIn;
            while obj.Phase >= 1
                obj.Phase = obj.Phase - 1;
            end
            while obj.Phase < 0
                obj.Phase = obj.Phase + 1;
            end
            keep = min(4,nIn);
            obj.History = double(filtered(end-keep+1:end,:));
            outputStart=obj.OutputCount;
            obj.InputCount = obj.InputCount + nIn;
            obj.OutputCount = obj.OutputCount + nOut;
            measuredDrift = obj.InputCount * (obj.RateRatio - 1);
            outputTimestamps=(outputStart+(0:nOut-1)).' .* ...
                obj.RateRatio./obj.SampleRate_Hz;
            [~,aliasPower]= ...
                sixgr.rf.runtime.StatefulSampleRateOffsetResampler. ...
                designAntiAliasFilter(obj.SampleRate_Hz,obj.RateRatio, ...
                obj.OccupiedBandwidth_Hz);
            trace = struct( ...
                "InputSamples", nIn, ...
                "OutputSamples", nOut, ...
                "CumulativeInputSamples", obj.InputCount, ...
                "CumulativeOutputSamples", obj.OutputCount, ...
                "MeasuredDrift_samples", measuredDrift, ...
                "RateRatio", obj.RateRatio, ...
                "PhaseAccumulator", obj.Phase, ...
                "OutputTimestamps_s",outputTimestamps, ...
                "Interpolation", "stateful_cubic_farrow_with_fir_antialias", ...
                "AntiAliasTapCount",numel(obj.AntiAliasTaps), ...
                "AliasPower_dBc", aliasPower);
            y = cast(y, "like", x);
        end
    end

    methods(Static,Access=private)
        function [taps,aliasPower_dBc]=designAntiAliasFilter(fs,ratio,occupied)
            tapCount=129;
            normalizedOccupied=double(occupied)/double(fs);
            cutoff=min(0.49/max(1,double(ratio)), ...
                max(normalizedOccupied*1.15,normalizedOccupied+0.01));
            cutoff=min(max(cutoff,0.01),0.49);
            index=(-(tapCount-1)/2:(tapCount-1)/2).';
            taps=2*cutoff*sinc(2*cutoff*index);
            window=0.42-0.5*cos(2*pi*(0:tapCount-1)'/(tapCount-1))+ ...
                0.08*cos(4*pi*(0:tapCount-1)'/(tapCount-1));
            taps=(taps.*window).';
            taps=taps/sum(taps);
            nfft=16384;
            response=abs(fft(taps,nfft));
            frequency=(0:nfft/2)'/nfft;
            stopStart=min(0.5,cutoff+0.08);
            stopMask=frequency>=stopStart;
            if any(stopMask)
                aliasPower_dBc=20*log10(max(response(stopMask))/ ...
                    max(response(1),realmin));
            else
                aliasPower_dBc=-Inf;
            end
        end
    end
end
