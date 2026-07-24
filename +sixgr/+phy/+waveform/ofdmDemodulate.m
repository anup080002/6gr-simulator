function [grid, info] = ofdmDemodulate(carrier, waveform, varargin)
%OFDMDemodulate OFDM demodulator wrapper for SixGR simulator.
%
%   [grid, info] = sixgr.phy.waveform.ofdmDemodulate(carrier, waveform, ...)
%
%   Thin wrapper around 5G Toolbox nrOFDMDemodulate. It returns OFDMInfo
%   (nrOFDMInfo) plus metadata.
%
%   Inputs
%     carrier  : nrCarrierConfig
%     waveform : time-domain waveform (Nsamp-by-R), R = number of Rx antennas
%
%   Name-value pairs are forwarded to nrOFDMDemodulate (for example:
%     "CarrierFrequency", "SampleRate", "Nfft", "CyclicPrefix").
%
%   Outputs
%     grid : K-by-L-by-R resource grid
%     info : struct with OFDM info + metadata

    samplingResolution = localResolveSampling(carrier, varargin{:});

    try
        grid = nrOFDMDemodulate(carrier, waveform, varargin{:});
        engine = "nrOFDMDemodulate";
    catch ME
        failure = MException("sixgr:phy:ofdmDemodulate:Failed", ...
            "nrOFDMDemodulate rejected the validated OFDM configuration: %s", ...
            ME.message);
        failure = addCause(failure, ME);
        throwAsCaller(failure);
    end

    ofdmInfo = localResolveOFDMInfo( ...
        carrier, samplingResolution, varargin{:});

    info = ofdmInfo;
    info.OFDMSamplingResolution = samplingResolution;
    calibrationArguments = localCalibrationArguments(varargin{:});
    noiseTransform = sixgr.phy.waveform.calibrateOFDMNoiseTransform( ...
        carrier, calibrationArguments{:});
    info.NoiseTransform = noiseTransform;
    info.SampleToGridNoiseVarianceGain = double(noiseTransform.SampleToGridNoiseVarianceGain);
    info.GridToSampleNoiseVarianceGain = double(noiseTransform.GridToSampleNoiseVarianceGain);
    info.TimeDomainSignalPowerReference = char(string(noiseTransform.TimeDomainSignalPowerReference));
    info.FrequencyDomainSignalPowerReference = char(string(noiseTransform.FrequencyDomainSignalPowerReference));
    info.OFDMNoiseTransformVersion = char(string(noiseTransform.Version));
    info.EngineUsed = engine;
    info.WaveformSize = size(waveform);
    info.GridSize = size(grid);
end

function ofdmInfo = localResolveOFDMInfo( ...
        carrier, samplingResolution, varargin)
infoArgs = {"Windowing", double( ...
    samplingResolution.WindowingSamples)};
i = 1;
while i <= numel(varargin)
    if i == numel(varargin) || ~(ischar(varargin{i}) || isstring(varargin{i}))
        break;
    end
    name = lower(strtrim(string(varargin{i})));
    if any(name == ["carrierfrequency", "nfft", "samplerate"])
        infoArgs = [infoArgs, varargin(i:i+1)]; %#ok<AGROW>
    end
    i = i + 2;
end
ofdmInfo = nrOFDMInfo(carrier, infoArgs{:});
end

function resolution = localResolveSampling(carrier, varargin)
if mod(numel(varargin), 2) ~= 0
    error("sixgr:phy:ofdmDemodulate:BadNameValueArguments", ...
        "OFDM demodulation options must occur in name-value pairs.");
end

resolverArguments = {};
seen = strings(0, 1);
for index = 1:2:numel(varargin)
    rawName = varargin{index};
    if ~(ischar(rawName) || (isstring(rawName) && isscalar(rawName)))
        error("sixgr:phy:ofdmDemodulate:BadNameValueArguments", ...
            "OFDM option names must be character vectors or string scalars.");
    end
    name = lower(strtrim(string(rawName)));
    if any(seen == name)
        error("sixgr:phy:ofdmDemodulate:DuplicateOption", ...
            "OFDM option '%s' was supplied more than once.", char(name));
    end
    seen(end + 1, 1) = name; %#ok<AGROW>
    value = varargin{index + 1};
    switch name
        case "nfft"
            resolverArguments = [resolverArguments, ...
                {"Nfft", value}]; %#ok<AGROW>
        case "samplerate"
            resolverArguments = [resolverArguments, ...
                {"SampleRate", value}]; %#ok<AGROW>
    end
end
resolution = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
    carrier, resolverArguments{:});
end

function out = localCalibrationArguments(varargin)
out = varargin;
names = strings(0, 1);
for index = 1:2:numel(varargin)
    names(end + 1, 1) = lower(strtrim(string(varargin{index}))); %#ok<AGROW>
end
if ~any(names == "windowing")
    out = [out, {"Windowing", 0}];
end
end
