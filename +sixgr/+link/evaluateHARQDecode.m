function diag = evaluateHARQDecode(tx, rx, cfg, combinedPrev)
%EVALUATEHARQDECODE Evaluate current and HARQ-combined decode outcomes.

if nargin < 4
    combinedPrev = [];
end

[recLLR, rxLayout] = localRateRecoveredLLRAndLayout(rx);
if isempty(recLLR)
    recLLR = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
end
txLayout = sixgr.util.structGet(tx, "CodingLayout", rxLayout);

txBits = int8(sixgr.util.structGet(tx, "TransportBlock", int8([])));
txBits = txBits(:);
rxBits = int8(sixgr.util.structGet(rx, "TransportBlock", int8([])));
rxBits = rxBits(:);

[combinedLLR, combineInfo] = localCombineRateRecoveredLLR(combinedPrev, recLLR, rxLayout);
[combinedOK, combinedDecIt] = localDecodeCombinedLLR(tx, combinedLLR, cfg, txLayout);
[bitErr, bitsCompared] = localBitErrors(txBits, rxBits);
[cbgFailMask, cbgErrors, cbgCount, cbgBLER] = localCBGFailureStats(rx, tx);

currentOK = logical(sixgr.util.structGet(rx, "Ok", false)) && ...
    bitErr == 0 && numel(rxBits) == numel(txBits);

diag = struct();
diag.RateRecoveredLLR = recLLR;
diag.CombinedLLR = combinedLLR;
diag.CodingLayout = rxLayout;
diag.HARQSoftCombiningReason = char(string(combineInfo.Reason));
diag.HARQSoftCombiningApplied = logical(combineInfo.Applied);
diag.CurrentDecodeOK = currentOK;
diag.CombinedDecodeOK = logical(combinedOK);
diag.BitErrors = double(bitErr);
diag.BitsCompared = double(bitsCompared);
diag.CBGFailureMask = cbgFailMask;
diag.CBGErrors = double(cbgErrors);
diag.CBGCount = double(cbgCount);
diag.CBGBLER = double(cbgBLER);
diag.DecoderIterations = double(mean(double(sixgr.util.structGet(rx, "ActiveIterations", NaN)), "omitnan"));
diag.CombinedDecoderIterations = double(combinedDecIt);
diag.MeasuredSINR_dB = localExtractSINR(rx);
diag.Notes = "";
end

function [mask, errCount, cbgCount, cbgBLER] = localCBGFailureStats(rx, tx)
mask = false(0, 1);
errCount = NaN;
cbgCount = NaN;
cbgBLER = NaN;
cbCrc = double(sixgr.util.structGet(rx, "CodeBlockCRCError", []));
cbCrc = cbCrc(:);
cbCrc = cbCrc(isfinite(cbCrc));
if isempty(cbCrc)
    nCB = double(sixgr.util.structGet(rx, "NumCodeBlocks", ...
        sixgr.util.structGet(tx, "NumCodeBlocks", NaN)));
    if isfinite(nCB) && nCB >= 1
        mask = repmat(logical(sixgr.util.structGet(rx, "CRCError", true)), round(nCB), 1);
    else
        return;
    end
else
    mask = cbCrc ~= 0;
end
errCount = double(sum(mask));
cbgCount = double(numel(mask));
if cbgCount > 0
    cbgBLER = errCount ./ cbgCount;
end
end

function [llr, layout] = localRateRecoveredLLRAndLayout(rx)
llr = sixgr.util.structGet(rx, "RecLLR", []);
if isempty(llr)
    llr = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
end
layout = sixgr.util.structGet(rx, "CodingLayout", struct());
end

function [combined, info] = localCombineRateRecoveredLLR(prev, cur, currentLayout)
if isempty(prev)
    combined = localEnsureLLRMatrix(cur);
    info = struct("Applied", false, "Reason", "no_prior_harq_soft_buffer");
    return;
end
if isempty(cur)
    combined = localEnsureLLRMatrix(prev);
    info = struct("Applied", false, "Reason", "current_llr_empty");
    return;
end
[priorLLR, priorLayout] = localUnwrapPrior(prev);
[combined, info] = sixgr.phy.harq.combineSoftLLR(localEnsureLLRMatrix(cur), ...
    localEnsureLLRMatrix(priorLLR), ...
    "CurrentLayout", currentLayout, ...
    "PriorLayout", priorLayout);
end

function [priorLLR, priorLayout] = localUnwrapPrior(prev)
priorLayout = struct();
priorLLR = prev;
if isstruct(prev)
    priorLayout = sixgr.util.structGet(prev, "CodingLayout", struct());
    priorLLR = sixgr.util.structGet(prev, "LLR", sixgr.util.structGet(prev, "RateRecoveredLLR", []));
end
end

function [ok, meanIter] = localDecodeCombinedLLR(tx, recLLR, cfg, layout)
ok = false;
meanIter = NaN;
if isempty(recLLR) || ~(isstruct(layout) && ~isempty(fieldnames(layout)))
    return;
end
X = localEnsureLLRMatrix(recLLR);
if isempty(X)
    return;
end

nRow = size(X, 1);
nCB = size(X, 2);
if nRow ~= double(layout.MotherCodeLength) || nCB ~= double(layout.NumCodeBlocks)
    return;
end
decCbs = zeros(nRow, nCB, 'int8');
itVec = NaN(nCB, 1);
maxLen = 0;
alg = char(string(sixgr.util.structGet(cfg, "phy.ldpc.algorithm", "Normalized min-sum")));
maxIter = sixgr.phy.phycode.resolveLDPCMaxIterations(cfg);

for c = 1:nCB
    [d, it] = sixgr.phy.phycode.ldpcDecode(X(:, c), double(layout.BaseGraph), maxIter, alg);
    d = int8(d(:));
    Ld = min(numel(d), nRow);
    if Ld > 0
        decCbs(1:Ld, c) = d(1:Ld);
        maxLen = max(maxLen, Ld);
    end
    it = it(:);
    if ~isempty(it)
        itVec(c) = double(it(1));
    end
end
if maxLen <= 0
    return;
end

decCbs = decCbs(1:maxLen, :);
tbCrc = sixgr.phy.tb.desegmentLDPC(decCbs, layout);
[~, crcOk] = sixgr.phy.tb.checkCRC(tbCrc, char(string(layout.TBCRCType)));
ok = logical(crcOk);
meanIter = mean(itVec(isfinite(itVec)), "omitnan");
end

function X = localEnsureLLRMatrix(v)
X = double(v);
if isvector(X)
    X = X(:);
end
end

function sinr_dB = localExtractSINR(rx)
sinr_dB = NaN;
try
    csi = sixgr.util.structGet(rx, "CSI", []);
    if isstruct(csi)
        x = sixgr.util.structGet(csi, "SINRPerRE", []);
        x = double(x(:));
        x = x(isfinite(x) & x > 0);
        if ~isempty(x)
            sinr_dB = 10 * log10(mean(x, "omitnan"));
        end
    end
catch
end
end

function [be, bt] = localBitErrors(txBits, rxBits)
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
L = min(numel(txBits), numel(rxBits));
if L <= 0
    be = numel(txBits);
    bt = max(numel(txBits), 1);
    return;
end
be = sum(txBits(1:L) ~= rxBits(1:L));
bt = max(numel(txBits), L);
end
