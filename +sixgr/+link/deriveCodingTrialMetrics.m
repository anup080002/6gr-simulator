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

metrics.OfferedBits = localFiniteSum(sixgr.util.structGet( ...
    tx, "TransportBlockSizePerCodeword", ...
    sixgr.util.structGet(tx, "TransportBlockSize", NaN)));
metrics.TBCRCLength_bits = localFiniteSum(sixgr.util.structGet( ...
    tx, "TransportBlockCRCLengthPerCodeword", ...
    sixgr.util.structGet(tx, "TransportBlockCRCLength", NaN)));
metrics.TBLengthWithCRC_bits = localFiniteSum(sixgr.util.structGet( ...
    tx, "TransportBlockLenWithCRCPerCodeword", ...
    sixgr.util.structGet(tx, "TransportBlockLenWithCRC", NaN)));
metrics.BaseGraph = localFiniteCommon(sixgr.util.structGet( ...
    tx, "BaseGraphPerCodeword", ...
    sixgr.util.structGet(tx, "BaseGraph", NaN)));
metrics.RateMatchedBits = localFiniteSum(sixgr.util.structGet( ...
    tx, "GPerCodeword",sixgr.util.structGet(tx, "G", NaN)));

codeword = sixgr.util.structGet(tx, "Codeword", []);
if ~isempty(codeword)
    metrics.EncodedBits = double(numel(codeword));
end

seg = sixgr.util.structGet(txInfo, "Segmentation", struct());
metrics.NumCodeBlocks = localFiniteSum( ...
    sixgr.util.structGet(seg, "nCB", NaN));
metrics.CodeBlockLength_bits = localFiniteCommon( ...
    sixgr.util.structGet(seg, "cbLen", NaN));
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
    infoMask = txCol == 0 | txCol == 1;
    if ~any(infoMask)
        mismatch = true;
    else
        lastInfo = find(infoMask, 1, "last");
        if numel(rxCol) < lastInfo
            mismatch = true;
        else
            mismatch = any(txCol(infoMask) ~= rxCol(infoMask));
        end
    end
    if numel(parity) >= c && isfinite(parity(c)) && parity(c) > 0
        mismatch = true;
    end
    errMask(c) = mismatch;
end

% For the C=1 case, TS 38.212 does not append a code-block CRC24B.
% The strongest simulator-side code-block check is therefore the recovered
% transport block equality plus the TB CRC result, not a fabricated CB CRC.
if txCount == 1
    txTB = sixgr.util.structGet(tx, "TransportBlock", []);
    rxTB = sixgr.util.structGet(rx, "TransportBlock", []);
    if ~isempty(txTB) && ~isempty(rxTB)
        txTB = int8(txTB(:));
        rxTB = int8(rxTB(:));
        Ltb = min(numel(txTB), numel(rxTB));
        tbMismatch = numel(txTB) ~= numel(rxTB);
        if Ltb > 0
            tbMismatch = tbMismatch || any(txTB(1:Ltb) ~= rxTB(1:Ltb));
        else
            tbMismatch = true;
        end
        errMask(1) = tbMismatch || localBool(rx, "CRCError", false) || ~localBool(rx, "CRCPass", localBool(rx, "Ok", false));
    end
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

function value = localBool(s, name, defaultValue)
raw = sixgr.util.structGet(s, name, defaultValue);
if islogical(raw) && isscalar(raw)
    value = logical(raw);
elseif isnumeric(raw) && isscalar(raw) && isfinite(raw)
    value = raw ~= 0;
elseif ischar(raw) || isstring(raw)
    value = any(strcmpi(strtrim(char(string(raw))), ["true","1","yes","ok","pass"]));
else
    value = logical(defaultValue);
end
end

function value = localFiniteSum(raw)
if ~(isnumeric(raw) || islogical(raw))
    value = NaN;
    return;
end
raw = double(raw(:));
if isempty(raw) || any(~isfinite(raw))
    value = NaN;
else
    value = sum(raw);
end
end

function value = localFiniteCommon(raw)
if ~(isnumeric(raw) || islogical(raw))
    value = NaN;
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if isempty(raw) || any(raw ~= raw(1))
    value = NaN;
else
    value = raw(1);
end
end
