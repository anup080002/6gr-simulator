function [waveform, info] = ofdmModulate(carrier, grid, varargin)
%OFDMODULATE OFDM modulator wrapper for SixGR simulator.
%
%   [waveform, info] = sixgr.phy.waveform.ofdmModulate(carrier, grid, ...)
%
%   This is a thin wrapper around 5G Toolbox nrOFDMModulate. It adds:
%     - basic input shaping (ensure 3rd dim exists)
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

    try
        [waveform, ofdmInfo] = nrOFDMModulate(carrier, grid, varargin{:});
        engine = "nrOFDMModulate";
    catch ME
        % Provide a more actionable error
        error("sixgr:phy:ofdmModulate:Failed", ...
            "nrOFDMModulate failed: %s", ME.message);
    end

    info = ofdmInfo;
    noiseTransform = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier, varargin{:});
    info.NoiseTransform = noiseTransform;
    info.SampleToGridNoiseVarianceGain = double(noiseTransform.SampleToGridNoiseVarianceGain);
    info.GridToSampleNoiseVarianceGain = double(noiseTransform.GridToSampleNoiseVarianceGain);
    info.TimeDomainSignalPowerReference = char(string(noiseTransform.TimeDomainSignalPowerReference));
    info.FrequencyDomainSignalPowerReference = char(string(noiseTransform.FrequencyDomainSignalPowerReference));
    info.OFDMNoiseTransformVersion = char(string(noiseTransform.Version));
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
