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

    ofdmInfo = localResolveOFDMInfo(carrier, varargin{:});

    info = ofdmInfo;
    noiseTransform = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier, varargin{:});
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

function ofdmInfo = localResolveOFDMInfo(carrier, varargin)
infoArgs = {};
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
try
    ofdmInfo = nrOFDMInfo(carrier, infoArgs{:});
catch
    ofdmInfo = nrOFDMInfo(carrier);
end
end
