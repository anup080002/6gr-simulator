function [rxWaveform, evidence] = applyFadingChannelExact( ...
        channel, txWaveform, filterPadSamples, chunkSamples)
%APPLYFADINGCHANNELEXACT Apply one stateful fading channel without omission.
%
% CHUNKSAMPLES=0 uses one monolithic System-object call. A positive value
% streams the identical Tx sequence, followed by the identical zero filter
% padding, through the same channel object in order. No samples, inactive
% slots, or channel evolution are skipped. Chunking bounds the temporary
% path-gain/filter working set used by nrTDLChannel while preserving the
% complete truth waveform and a single continuous channel state.

if ~(isnumeric(txWaveform) && ismatrix(txWaveform) && ...
        ~isempty(txWaveform) && all(isfinite(txWaveform), "all"))
    error("sixgr:conformance:InvalidFadingChannelWaveform", ...
        "txWaveform must be a nonempty finite numeric matrix.");
end
localRequireNonnegativeInteger(filterPadSamples, "filterPadSamples");
localRequireNonnegativeInteger(chunkSamples, "chunkSamples");
filterPadSamples = double(filterPadSamples);
chunkSamples = double(chunkSamples);
txSamples = size(txWaveform, 1);
totalSamples = txSamples + filterPadSamples;

if chunkSamples == 0
    pad = zeros(filterPadSamples, size(txWaveform, 2), "like", txWaveform);
    channelInput = [txWaveform; pad];
    rxWaveform = channel(channelInput);
    callCount = 1;
    maximumInputRows = totalSamples;
    mode = "monolithic_complete_sequence";
else
    if ~isprop(channel, "NumReceiveAntennas")
        error("sixgr:conformance:FadingChannelReceiveDimensionUnavailable", ...
            "Streamed fading execution requires NumReceiveAntennas.");
    end
    nRx = double(channel.NumReceiveAntennas);
    rxWaveform = complex(zeros(totalSamples, nRx, "like", txWaveform));
    writeOffset = 0;
    callCount = 0;
    maximumInputRows = 0;

    for first = 1:chunkSamples:txSamples
        last = min(first + chunkSamples - 1, txSamples);
        inputChunk = txWaveform(first:last, :);
        outputChunk = channel(inputChunk);
        localAssertOutputChunk(outputChunk, size(inputChunk,1), nRx);
        rows = size(outputChunk,1);
        rxWaveform(writeOffset + (1:rows), :) = outputChunk;
        writeOffset = writeOffset + rows;
        callCount = callCount + 1;
        maximumInputRows = max(maximumInputRows, size(inputChunk,1));
    end

    padRemaining = filterPadSamples;
    while padRemaining > 0
        rows = min(chunkSamples, padRemaining);
        inputChunk = zeros(rows, size(txWaveform,2), "like", txWaveform);
        outputChunk = channel(inputChunk);
        localAssertOutputChunk(outputChunk, rows, nRx);
        rxWaveform(writeOffset + (1:rows), :) = outputChunk;
        writeOffset = writeOffset + rows;
        padRemaining = padRemaining - rows;
        callCount = callCount + 1;
        maximumInputRows = max(maximumInputRows, rows);
    end
    if writeOffset ~= totalSamples
        error("sixgr:conformance:FadingChannelStreamLengthMismatch", ...
            "Streamed channel produced %d sample rows; expected %d.", ...
            writeOffset, totalSamples);
    end
    mode = "streamed_complete_sequence";
end

if size(rxWaveform,1) ~= totalSamples || ...
        any(~isfinite(rxWaveform), "all")
    error("sixgr:conformance:InvalidFadingChannelOutput", ...
        "Fading channel output must contain %d finite sample rows.", ...
        totalSamples);
end
evidence = struct( ...
    "ContractVersion", "sixgr_exact_fading_channel_application/v1", ...
    "Mode", mode, ...
    "ChunkSamples", chunkSamples, ...
    "ChannelCallCount", callCount, ...
    "MaximumInputRows", maximumInputRows, ...
    "TxSamples", txSamples, ...
    "FilterPadSamples", filterPadSamples, ...
    "InputSamplesProcessed", totalSamples, ...
    "FullSequenceProcessed", true, ...
    "ProxyUsed", false, ...
    "FallbackUsed", false, ...
    "ApproximationMode", "none");
end

function localAssertOutputChunk(value, expectedRows, expectedColumns)
if ~(isnumeric(value) && ismatrix(value) && ...
        size(value,1) == expectedRows && ...
        size(value,2) == expectedColumns && all(isfinite(value), "all"))
    error("sixgr:conformance:FadingChannelChunkShapeMismatch", ...
        "Fading channel chunk output must have size [%d %d] and be finite.", ...
        expectedRows, expectedColumns);
end
end

function localRequireNonnegativeInteger(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value >= 0 && value == fix(value))
    error("sixgr:conformance:InvalidFadingChannelChunkPolicy", ...
        "%s must be a finite nonnegative integer.", name);
end
end
