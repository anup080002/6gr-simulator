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

    try
        grid = nrOFDMDemodulate(carrier, waveform, varargin{:});
        engine = "nrOFDMDemodulate";
    catch ME
        error("sixgr:phy:ofdmDemodulate:Failed", ...
            "nrOFDMDemodulate failed: %s", ME.message);
    end

    % OFDM info (does not accept all demodulate name-value pairs, so keep simple)
    try
        ofdmInfo = nrOFDMInfo(carrier);
    catch
        ofdmInfo = struct();
    end

    info = ofdmInfo;
    info.EngineUsed = engine;
    info.WaveformSize = size(waveform);
    info.GridSize = size(grid);
end
