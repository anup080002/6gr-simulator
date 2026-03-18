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
    if ndims(grid) == 2
        grid = reshape(grid, size(grid,1), size(grid,2), 1);
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
    info.EngineUsed = engine;
    info.GridSize = size(grid);
    info.WaveformSize = size(waveform);
end
