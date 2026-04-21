function metrics = deriveCodingTrialMetrics(tx, txInfo, rx, cfg)
%DERIVECODINGTRIALMETRICS Derive measured coding/decoder trial metrics.

metrics = struct( ...
    "OfferedBits", NaN, ...
    "DecoderIterations", NaN, ...
    "MaxDecoderIterations", NaN, ...
    "EarlyStopRate", NaN, ...
    "ComputeLatency_ms", NaN, ...
    "ProcedureDelay_ms", NaN, ...
    "DecodeLatency_ms", NaN, ...
    "Latency_ms", NaN, ...
    "DecoderComplexityUnits", NaN, ...
    "NormalizedDecoderComplexity", NaN, ...
    "AreaEfficiencyProxy", NaN, ...
    "NumCodeBlocks", NaN, ...
    "CodeBlockLength_bits", NaN, ...
    "SegmentationOccurred", NaN, ...
    "SegmentationPaddingBits", NaN, ...
    "TBCRCLength_bits", NaN, ...
    "TBLengthWithCRC_bits", NaN, ...
    "BaseGraph", NaN, ...
    "EncodedBits", NaN, ...
    "RateMatchedBits", NaN, ...
    "RateMatchPunctureBits", NaN, ...
    "RateMatchRepetitionBits", NaN, ...
    "CodeBlockErrors", NaN, ...
    "CodeBlockCount", NaN, ...
    "CodeBlockBLER", NaN, ...
    "CBGErrors", NaN, ...
    "CBGCount", NaN, ...
    "CBGBLER", NaN);

metrics.OfferedBits = double(sixgr.util.structGet(tx, "TransportBlockSize", NaN));
metrics.TBCRCLength_bits = double(sixgr.util.structGet(tx, "TransportBlockCRCLength", NaN));
metrics.TBLengthWithCRC_bits = double(sixgr.util.structGet(tx, "TransportBlockLenWithCRC", NaN));
metrics.BaseGraph = double(sixgr.util.structGet(tx, "BaseGraph", NaN));
metrics.RateMatchedBits = double(sixgr.util.structGet(tx, "G", NaN));

codeword = sixgr.util.structGet(tx, "Codeword", []);
if ~isempty(codeword)
    metrics.EncodedBits = double(numel(codeword));
end

seg = sixgr.util.structGet(txInfo, "Segmentation", struct());
metrics.NumCodeBlocks = double(sixgr.util.structGet(seg, "nCB", NaN));
metrics.CodeBlockLength_bits = double(sixgr.util.structGet(seg, "cbLen", NaN));
if isfinite(metrics.NumCodeBlocks)
    metrics.SegmentationOccurred = double(metrics.NumCodeBlocks > 1);
end
if isfinite(metrics.NumCodeBlocks) && isfinite(metrics.CodeBlockLength_bits) && isfinite(metrics.TBLengthWithCRC_bits)
    metrics.SegmentationPaddingBits = max(metrics.NumCodeBlocks * metrics.CodeBlockLength_bits - metrics.TBLengthWithCRC_bits, 0);
end

actIter = double(sixgr.util.structGet(rx, "ActiveIterations", []));
actIter = actIter(isfinite(actIter));
metrics.MaxDecoderIterations = double(sixgr.util.structGet(rx, "MaxDecoderIterations", ...
    sixgr.util.structGet(cfg, "phy.ldpc.maxIterations", sixgr.util.structGet(cfg, "phy.ldpc.maxIter", NaN))));
if ~isempty(actIter)
    metrics.DecoderIterations = mean(actIter, "omitnan");
    if isfinite(metrics.MaxDecoderIterations) && metrics.MaxDecoderIterations > 0
        metrics.EarlyStopRate = mean(actIter < metrics.MaxDecoderIterations);
    end
end

decodeLatency_s = double(sixgr.util.structGet(rx, "DecodeLatency_s", NaN));
if isfinite(decodeLatency_s)
    metrics.ComputeLatency_ms = 1e3 * decodeLatency_s;
    metrics.DecodeLatency_ms = metrics.ComputeLatency_ms;
    % Legacy alias preserved for backward compatibility with older exports.
    metrics.Latency_ms = metrics.ComputeLatency_ms;
    % In the standalone PHY decode path there is no extra procedure stage
    % beyond the observed grant processing unless a caller adds one.
    metrics.ProcedureDelay_ms = 0;
end

if isfinite(metrics.CodeBlockLength_bits) && ~isempty(actIter)
    metrics.DecoderComplexityUnits = sum(actIter .* metrics.CodeBlockLength_bits, "omitnan");
elseif isfinite(metrics.EncodedBits) && ~isempty(actIter)
    metrics.DecoderComplexityUnits = sum(actIter, "omitnan") * metrics.EncodedBits;
end
if isfinite(metrics.DecoderComplexityUnits) && isfinite(metrics.OfferedBits) && metrics.OfferedBits > 0
    metrics.NormalizedDecoderComplexity = metrics.DecoderComplexityUnits / metrics.OfferedBits;
    metrics.AreaEfficiencyProxy = metrics.OfferedBits / max(metrics.DecoderComplexityUnits, eps);
end

if isfinite(metrics.EncodedBits) && isfinite(metrics.RateMatchedBits)
    if metrics.RateMatchedBits <= metrics.EncodedBits
        metrics.RateMatchPunctureBits = metrics.EncodedBits - metrics.RateMatchedBits;
        metrics.RateMatchRepetitionBits = 0;
    else
        metrics.RateMatchPunctureBits = 0;
        metrics.RateMatchRepetitionBits = metrics.RateMatchedBits - metrics.EncodedBits;
    end
end

[cbErr, cbCount, cbgErr, cbgCount] = localCodeBlockErrorStats(tx, rx, cfg);
metrics.CodeBlockErrors = cbErr;
metrics.CodeBlockCount = cbCount;
if isfinite(cbErr) && isfinite(cbCount) && cbCount > 0
    metrics.CodeBlockBLER = cbErr / cbCount;
end
metrics.CBGErrors = cbgErr;
metrics.CBGCount = cbgCount;
if isfinite(cbgErr) && isfinite(cbgCount) && cbgCount > 0
    metrics.CBGBLER = cbgErr / cbgCount;
end
end

function [cbErr, cbCount, cbgErr, cbgCount] = localCodeBlockErrorStats(tx, rx, cfg)
cbErr = NaN;
cbCount = NaN;
cbgErr = NaN;
cbgCount = NaN;

cbCrcErr = double(sixgr.util.structGet(rx, "CodeBlockCRCError", []));
cbCrcErr = cbCrcErr(isfinite(cbCrcErr));
if ~isempty(cbCrcErr)
    cbCount = double(numel(cbCrcErr));
    cbErr = double(sum(cbCrcErr ~= 0));
    [cbgErr, cbgCount] = localResolveCBGErrorStats(cbErr, cbCount, cfg);
    return;
end

tbCrc = sixgr.util.structGet(tx, "TransportBlockCRC", []);
bgn = double(sixgr.util.structGet(tx, "BaseGraph", NaN));
decCbs = sixgr.util.structGet(rx, "DecodedCodeBlocks", []);
if isempty(tbCrc) || isempty(decCbs) || ~isfinite(bgn) || ~(bgn == 1 || bgn == 2)
    return;
end

try
    txCbs = sixgr.phy.tb.segmentLDPC(int8(tbCrc(:)), bgn);
catch
    return;
end

parity = double(sixgr.util.structGet(rx, "ParityChecks", []));
txCount = size(txCbs, 2);
rxCount = size(decCbs, 2);
cbCount = double(txCount);
if txCount < 1
    cbErr = 0;
    cbgCount = 0;
    cbgErr = 0;
    return;
end

errMask = false(txCount, 1);
for c = 1:txCount
    if c > rxCount
        errMask(c) = true;
        continue;
    end
    txCol = int8(txCbs(:, c));
    rxCol = int8(decCbs(:, c));
    L = min(numel(txCol), numel(rxCol));
    mismatch = (numel(txCol) ~= numel(rxCol));
    if L > 0
        mismatch = mismatch || any(txCol(1:L) ~= rxCol(1:L));
    else
        mismatch = true;
    end
    if numel(parity) >= c && isfinite(parity(c)) && parity(c) > 0
        mismatch = true;
    end
    errMask(c) = mismatch;
end
cbErr = double(sum(errMask));
[cbgErr, cbgCount] = localResolveCBGErrorStats(cbErr, cbCount, cfg);
end

function [cbgErr, cbgCount] = localResolveCBGErrorStats(cbErr, cbCount, cfg)
cbgErr = NaN;
cbgCount = NaN;
if ~(isfinite(cbErr) && isfinite(cbCount) && cbCount >= 0)
    return;
end

cbgEnabled = logical(sixgr.util.structGet(cfg, "phy.harq.cbgEnabled", false));
if cbgEnabled
    cbgCount = cbCount;
    cbgErr = cbErr;
else
    cbgCount = 1;
    cbgErr = double(cbErr > 0);
end
end
