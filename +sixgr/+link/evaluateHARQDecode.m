function diag = evaluateHARQDecode(tx, rx, cfg, combinedPrev)
%EVALUATEHARQDECODE Evaluate current and HARQ-combined decode outcomes.

if nargin < 4
    combinedPrev = [];
end

recLLR = sixgr.util.structGet(rx, "RecLLR", []);
if isempty(recLLR)
    recLLR = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
end

txBits = int8(sixgr.util.structGet(tx, "TransportBlock", int8([])));
txBits = txBits(:);
rxBits = int8(sixgr.util.structGet(rx, "TransportBlock", int8([])));
rxBits = rxBits(:);

combinedLLR = localCombineRateRecoveredLLR(combinedPrev, recLLR);
[combinedOK, combinedDecIt] = localDecodeCombinedLLR(tx, combinedLLR, cfg);
[bitErr, bitsCompared] = localBitErrors(txBits, rxBits);

currentOK = logical(sixgr.util.structGet(rx, "Ok", false)) && ...
    bitErr == 0 && numel(rxBits) == numel(txBits);

diag = struct();
diag.RateRecoveredLLR = recLLR;
diag.CombinedLLR = combinedLLR;
diag.CurrentDecodeOK = currentOK;
diag.CombinedDecodeOK = logical(combinedOK);
diag.BitErrors = double(bitErr);
diag.BitsCompared = double(bitsCompared);
diag.DecoderIterations = double(mean(double(sixgr.util.structGet(rx, "ActiveIterations", NaN)), "omitnan"));
diag.CombinedDecoderIterations = double(combinedDecIt);
diag.MeasuredSINR_dB = localExtractSINR(rx);
diag.Notes = "";
end

function combined = localCombineRateRecoveredLLR(prev, cur)
if isempty(prev)
    combined = cur;
    return;
end
if isempty(cur)
    combined = prev;
    return;
end
X = localEnsureLLRMatrix(prev);
Y = localEnsureLLRMatrix(cur);
nRow = max(size(X, 1), size(Y, 1));
nCol = max(size(X, 2), size(Y, 2));
X(end+1:nRow, end+1:nCol) = 0;
Y(end+1:nRow, end+1:nCol) = 0;
combined = X + Y;
end

function [ok, meanIter] = localDecodeCombinedLLR(tx, recLLR, cfg)
ok = false;
meanIter = NaN;
if isempty(recLLR)
    return;
end
X = localEnsureLLRMatrix(recLLR);
if isempty(X)
    return;
end

nRow = size(X, 1);
nCB = size(X, 2);
decCbs = zeros(nRow, nCB, 'int8');
itVec = NaN(nCB, 1);
maxLen = 0;
alg = char(string(sixgr.util.structGet(cfg, "phy.ldpc.algorithm", "Normalized min-sum")));
maxIter = double(sixgr.util.structGet(cfg, "phy.ldpc.maxIterations", 8));

for c = 1:nCB
    [d, it] = sixgr.phy.phycode.ldpcDecode(X(:, c), double(tx.BaseGraph), maxIter, alg);
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
B = double(tx.TransportBlockSize) + double(sixgr.util.structGet(tx, "TransportBlockCRCLength", 24));
tbCrc = sixgr.phy.tb.desegmentLDPC(decCbs, double(tx.BaseGraph), B);
[~, crcOk] = sixgr.phy.tb.checkCRC(tbCrc, char(string(sixgr.util.structGet(tx, "TransportBlockCRCType", "24A"))));
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
