function [waveform, info] = ofdmModulate(carrier, grid, varargin)
%OFDMODULATE OFDM modulator wrapper for SixGR simulator.
%
%   [waveform, info] = sixgr.phy.waveform.ofdmModulate(carrier, grid, ...)
%
%   This is the strict standard-waveform wrapper around 5G Toolbox
%   nrOFDMModulate. It adds:
%     - basic input shaping (ensure 3rd dim exists)
%     - canonical OFDM sampling validation
%     - explicit zero windowing when no implementation setting is supplied
%     - consistent info struct including sizes and engine used
%
%   Inputs
%     carrier : nrCarrierConfig (recommended) or numerology inputs supported
%               by nrOFDMModulate
%     grid    : K-by-L-by-P resource grid (P = number of antenna ports).
%
%   Name-value pairs are forwarded to nrOFDMModulate (for example:
%     "CarrierFrequency", "SampleRate", "Nfft", "Windowing").
%
%   Outputs
%     waveform : time-domain waveform
%     info     : struct including OFDM settings and metadata

    % Normalize grid dimensions: K-by-L-by-P
    if ismatrix(grid)
        grid = reshape(grid, size(grid,1), size(grid,2), 1);
    end
    if ndims(grid) > 3
        error("sixgr:phy:ofdmModulate:BadGridRank", ...
            "OFDM modulation expects a K-by-L-by-P resource grid. Got rank %d.", ndims(grid));
    end
    gridShape = size(grid);
    if numel(gridShape) < 3
        gridShape(3) = 1;
    end
    if any(~isfinite(double(gridShape))) || any(double(gridShape) < 1)
        error("sixgr:phy:ofdmModulate:BadGridShape", ...
            "OFDM modulation expects positive grid dimensions. Got %s.", mat2str(gridShape));
    end

    [ofdmArguments, samplingResolution] = ...
        localResolveSamplingArguments(carrier, varargin);

    try
        [waveform, ofdmInfo] = nrOFDMModulate( ...
            carrier, grid, ofdmArguments{:});
        engine = "nrOFDMModulate";
    catch ME
        failure = MException("sixgr:phy:ofdmModulate:Failed", ...
            "nrOFDMModulate rejected the validated OFDM configuration: %s", ...
            ME.message);
        failure = addCause(failure, ME);
        throwAsCaller(failure);
    end

    info = ofdmInfo;
    appliedWindowing = double(sixgr.util.structGet( ...
        ofdmInfo, "Windowing", NaN));
    if ~(isscalar(appliedWindowing) && isfinite(appliedWindowing) && ...
            appliedWindowing == samplingResolution.WindowingSamples)
        error("sixgr:phy:frame:WindowingNotAppliedExactly", ...
            "nrOFDMModulate reported Windowing=%g after the canonical " + ...
            "resolver required %d samples.", ...
            appliedWindowing, samplingResolution.WindowingSamples);
    end
    noiseTransform = sixgr.phy.waveform.calibrateOFDMNoiseTransform( ...
        carrier, ofdmArguments{:});
    info.NoiseTransform = noiseTransform;
    info.SampleToGridNoiseVarianceGain = double(noiseTransform.SampleToGridNoiseVarianceGain);
    info.GridToSampleNoiseVarianceGain = double(noiseTransform.GridToSampleNoiseVarianceGain);
    info.TimeDomainSignalPowerReference = char(string(noiseTransform.TimeDomainSignalPowerReference));
    info.FrequencyDomainSignalPowerReference = char(string(noiseTransform.FrequencyDomainSignalPowerReference));
    info.OFDMNoiseTransformVersion = char(string(noiseTransform.Version));
    info.OFDMSamplingResolution = samplingResolution;
    info.OFDMWindowingSamples = double( ...
        samplingResolution.WindowingSamples);
    info.OFDMWindowingSource = char(localWindowingSource(varargin));
    [gridPower, gridPowerInfo] = sixgr.phy.waveform.ofdmReferencePower(grid, info, "Domain", "occupied_re");
    [timePower, timePowerInfo] = sixgr.phy.waveform.ofdmReferencePower(waveform, info, "Domain", "active_samples");
    info.GridDomainSignalPower = double(gridPower);
    info.TimeDomainSignalPower = double(timePower);
    info.GridDomainSignalPowerInfo = gridPowerInfo;
    info.TimeDomainSignalPowerInfo = timePowerInfo;
    info.EngineUsed = engine;
    info.GridSize = gridShape;
    info.WaveformSize = size(waveform);
    info.DimensionContract = struct( ...
        "GridSubcarriers", double(gridShape(1)), ...
        "GridSymbols", double(gridShape(2)), ...
        "GridPorts", double(gridShape(3)), ...
        "WaveformSamples", double(size(waveform, 1)), ...
        "WaveformColumns", double(size(waveform, 2)), ...
        "Nfft", double(sixgr.util.structGet(info, "Nfft", NaN)), ...
        "SampleRate", double(sixgr.util.structGet(info, "SampleRate", NaN)));
end

function [outArguments, resolution] = localResolveSamplingArguments( ...
        carrier, inputArguments)
if mod(numel(inputArguments), 2) ~= 0
    error("sixgr:phy:ofdmModulate:BadNameValueArguments", ...
        "OFDM modulation options must occur in name-value pairs.");
end

outArguments = inputArguments;
resolverArguments = {};
windowingSpecified = false;
seen = strings(0, 1);
for index = 1:2:numel(inputArguments)
    rawName = inputArguments{index};
    if ~(ischar(rawName) || (isstring(rawName) && isscalar(rawName)))
        error("sixgr:phy:ofdmModulate:BadNameValueArguments", ...
            "OFDM option names must be character vectors or string scalars.");
    end
    name = lower(strtrim(string(rawName)));
    if any(seen == name)
        error("sixgr:phy:ofdmModulate:DuplicateOption", ...
            "OFDM option '%s' was supplied more than once.", char(name));
    end
    seen(end + 1, 1) = name; %#ok<AGROW>
    value = inputArguments{index + 1};
    switch name
        case "nfft"
            resolverArguments = [resolverArguments, ...
                {"Nfft", value}]; %#ok<AGROW>
        case "samplerate"
            resolverArguments = [resolverArguments, ...
                {"SampleRate", value}]; %#ok<AGROW>
        case "windowing"
            windowingSpecified = true;
            resolverArguments = [resolverArguments, ...
                {"WindowingSamples", value}]; %#ok<AGROW>
    end
end
if ~windowingSpecified
    outArguments = [outArguments, {"Windowing", 0}];
    resolverArguments = [resolverArguments, {"WindowingSamples", 0}];
end

resolution = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
    carrier, resolverArguments{:});
end

function source = localWindowingSource(inputArguments)
source = "standard_default_zero";
for index = 1:2:numel(inputArguments)
    if lower(strtrim(string(inputArguments{index}))) == "windowing"
        source = "explicit_windowing_samples";
        return;
    end
end
end
