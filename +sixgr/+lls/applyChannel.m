function [rxWaveform, trueChannelGrid, channelInfo] = applyChannel(txWaveform, carrier, llsCfg, channelSeed)
%APPLYCHANNEL Apply one independent waveform channel realization.
%
% AWGN uses an explicit unit channel.  TDL/CDL paths use the corresponding
% 5G Toolbox stochastic waveform filter and derive the exact per-RE true
% channel from the same path gains and filters.  No scalar channel is
% expanded across a fading resource grid.

model = upper(string(llsCfg.channel.model));
if model == "AWGN"
    rxWaveform = txWaveform;
    trueChannelGrid = complex(ones(carrier.NSizeGrid*12, carrier.SymbolsPerSlot, 1, 1, "like", txWaveform));
    channelInfo = struct( ...
        "Model", "AWGN", ...
        "Source", "explicit_unit_flat_channel", ...
        "PathGainsAvailable", false, ...
        "TrueChannelGridAvailable", true, ...
        "TimingOffsetSamples", 0, ...
        "MaximumDopplerHz", 0, ...
        "ChannelSeed", double(channelSeed));
    return;
end

if startsWith(model, "TDL-")
    if exist("nrTDLChannel", "class") ~= 8 && exist("nrTDLChannel", "file") ~= 2
        error("sixgr:lls:MissingTDLChannel", "nrTDLChannel is required for %s.", model);
    end
    channel = nrTDLChannel;
    channel.DelayProfile = char(model);
    channel.NumTransmitAntennas = double(llsCfg.channel.txAntennas);
    channel.NumReceiveAntennas = double(llsCfg.channel.rxAntennas);
    try
        channel.TransmissionDirection = "Uplink";
    catch
    end
elseif startsWith(model, "CDL-")
    if exist("nrCDLChannel", "class") ~= 8 && exist("nrCDLChannel", "file") ~= 2
        error("sixgr:lls:MissingCDLChannel", "nrCDLChannel is required for %s.", model);
    end
    channel = nrCDLChannel;
    channel.DelayProfile = char(model);
    channel.CarrierFrequency = double(llsCfg.carrier.frequencyHz);
    txArray = channel.TransmitAntennaArray;
    txArray.Size = [double(llsCfg.channel.txAntennas) 1 1 1 1];
    channel.TransmitAntennaArray = txArray;
    rxArray = channel.ReceiveAntennaArray;
    rxArray.Size = [double(llsCfg.channel.rxAntennas) 1 1 1 1];
    channel.ReceiveAntennaArray = rxArray;
else
    error("sixgr:lls:UnsupportedChannel", "Unsupported waveform channel model %s.", model);
end

ofdm = nrOFDMInfo(carrier);
channel.SampleRate = double(ofdm.SampleRate);
channel.DelaySpread = double(llsCfg.channel.delaySpreadSeconds);
speedMps = double(llsCfg.channel.velocityKmph) / 3.6;
maximumDopplerHz = speedMps * double(llsCfg.carrier.frequencyHz) / 299792458;
channel.MaximumDopplerShift = maximumDopplerHz;
if isprop(channel, "RandomStream")
    channel.RandomStream = "mt19937ar with seed";
end
if isprop(channel, "Seed")
    channel.Seed = double(channelSeed);
end
if isprop(channel, "NormalizePathGains")
    channel.NormalizePathGains = true;
end
if isprop(channel, "NormalizeChannelOutputs")
    channel.NormalizeChannelOutputs = true;
end
reset(channel);
cleanup = onCleanup(@() release(channel)); %#ok<NASGU>
objectInfo = info(channel);
maximumDelay = max(0, round(double(sixgr.util.structGet(objectInfo, "MaximumChannelDelay", 0))));
padded = [txWaveform; complex(zeros(maximumDelay, size(txWaveform,2), "like", txWaveform))];
[rawWaveform, pathGains, sampleTimes] = channel(padded);
pathFilters = getPathFilters(channel);
[timingOffset, timingMagnitude] = nrPerfectTimingEstimate(pathGains, pathFilters);
timingOffset = max(0, round(double(timingOffset)));
first = timingOffset + 1;
last = first + size(txWaveform,1) - 1;
if last > size(rawWaveform,1)
    rawWaveform(end+1:last,:) = complex(0); %#ok<AGROW>
end
rxWaveform = rawWaveform(first:last,:);
trueChannelGrid = nrPerfectChannelEstimate( ...
    carrier, pathGains, pathFilters, timingOffset, sampleTimes);
expectedSize = [carrier.NSizeGrid*12 carrier.SymbolsPerSlot];
if size(trueChannelGrid,1) ~= expectedSize(1) || size(trueChannelGrid,2) ~= expectedSize(2)
    error("sixgr:lls:InvalidPerfectChannelGrid", ...
        "Perfect fading channel grid has size %s; expected first dimensions [%d %d].", ...
        mat2str(size(trueChannelGrid)), expectedSize(1), expectedSize(2));
end
if any(~isfinite(trueChannelGrid), "all")
    error("sixgr:lls:InvalidPerfectChannelGrid", ...
        "Perfect fading channel grid contains nonfinite values.");
end
channelInfo = struct( ...
    "Model", model, ...
    "Source", "nr" + extractBefore(model,4) + "Channel_path_gains_and_nrPerfectChannelEstimate", ...
    "PathGainsAvailable", ~isempty(pathGains), ...
    "TrueChannelGridAvailable", true, ...
    "TrueChannelGridSize", double(size(trueChannelGrid)), ...
    "TrueChannelGridVariance", double(var(abs(trueChannelGrid(:)))), ...
    "TimingOffsetSamples", timingOffset, ...
    "TimingMagnitude", double(timingMagnitude), ...
    "MaximumChannelDelaySamples", maximumDelay, ...
    "MaximumDopplerHz", maximumDopplerHz, ...
    "SampleRateHz", double(ofdm.SampleRate), ...
    "ChannelSeed", double(channelSeed), ...
    "NormalizePathGains", true, ...
    "NormalizeChannelOutputs", true);
end
