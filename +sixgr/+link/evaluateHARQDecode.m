function diag = evaluateHARQDecode(tx, rx, cfg, combinedPrev)
%EVALUATEHARQDECODE Evaluate current and HARQ-combined decode outcomes.

if nargin < 4
    combinedPrev = [];
end

[recLLR, rxLayout] = localRateRecoveredLLRAndLayout(rx);
if isempty(recLLR)
    recLLR = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
end
txLayout = sixgr.util.structGet(tx, "CodingLayouts", []);
if isempty(txLayout)
    txLayout = sixgr.util.structGet(tx, "CodingLayout", rxLayout);
end

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
diag.SoftBuffer = sixgr.util.structGet(combineInfo, "SoftBuffer", struct());
diag.HARQSoftBuffer = diag.SoftBuffer;
diag.HARQSoftCombiningInfo = combineInfo;
diag.HARQSoftCombiningReason = char(string(combineInfo.Reason));
diag.HARQSoftCombiningApplied = logical(combineInfo.Applied);
diag.HARQSoftCombiningPositionAware = logical(sixgr.util.structGet(combineInfo, "PositionAware", false));
diag.HARQSoftCombiningOverlapPositionCount = double(sixgr.util.structGet(combineInfo, "OverlapPositionCount", NaN));
diag.LLRCombiningGain_dB = double(sixgr.util.structGet(combineInfo, "LLRCombiningGain_dB", NaN));
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
llr = sixgr.util.structGet(rx, "RecLLRCell", []);
if isempty(llr)
    llr = sixgr.util.structGet(rx, "RateRecoveredLLRCell", []);
end
if isempty(llr)
    llr = sixgr.util.structGet(rx, "RecLLR", []);
end
if isempty(llr)
    llr = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
end
layout = sixgr.util.structGet(rx, "CodingLayouts", []);
if isempty(layout)
    layout = sixgr.util.structGet(rx, "CodingLayout", struct());
end
end

function [combined, info] = localCombineRateRecoveredLLR(prev, cur, currentLayout)
if iscell(cur)
    [priorLLRCell, priorLayoutCell] = localUnwrapPriorCell(prev, numel(cur));
    combined = cell(size(cur));
    infoCell = cell(size(cur));
    for c = 1:numel(cur)
        [combined{c}, infoCell{c}] = sixgr.phy.harq.combineSoftLLR(localEnsureLLRMatrix(cur{c}), ...
            localCellOrScalar(priorLLRCell, c, []), ...
            "CurrentLayout", localCellOrScalar(currentLayout, c, struct()), ...
            "PriorLayout", localCellOrScalar(priorLayoutCell, c, struct()), ...
            "CodewordIndex", c);
    end
    info = localSummarizeCombineInfo(infoCell);
    return;
end
[priorLLR, priorLayout] = localUnwrapPrior(prev);
[combined, info] = sixgr.phy.harq.combineSoftLLR(localEnsureLLRMatrix(cur), ...
    priorLLR, ...
    "CurrentLayout", currentLayout, ...
    "PriorLayout", priorLayout);
end

function [priorLLR, priorLayout] = localUnwrapPrior(prev)
priorLayout = struct();
priorLLR = prev;
if isstruct(prev)
    if isfield(prev, "LLRSum") || isfield(prev, "SoftBuffer")
        priorLayout = sixgr.util.structGet(prev, "CodingLayout", struct());
        priorLLR = prev;
        return;
    end
    priorLayout = sixgr.util.structGet(prev, "CodingLayout", struct());
    priorLLR = sixgr.util.structGet(prev, "LLR", sixgr.util.structGet(prev, "RateRecoveredLLR", []));
end
end

function [priorLLRCell, priorLayoutCell] = localUnwrapPriorCell(prev, n)
priorLLRCell = cell(1, n);
priorLayoutCell = cell(1, n);
for c = 1:n
    priorLLRCell{c} = [];
    priorLayoutCell{c} = struct();
end
if isempty(prev)
    return;
end
if iscell(prev)
    for c = 1:min(n, numel(prev))
        priorLLRCell{c} = prev{c};
    end
    return;
end
if isstruct(prev)
    softCell = sixgr.util.structGet(prev, "SoftBufferCell", []);
    hadSoftBuffer = false;
    if iscell(softCell)
        for c = 1:min(n, numel(softCell))
            priorLLRCell{c} = softCell{c};
        end
        hadSoftBuffer = true;
    elseif isfield(prev, "LLRSum") || isfield(prev, "SoftBuffer")
        priorLLRCell{1} = prev;
        hadSoftBuffer = true;
    end
    rawLLR = sixgr.util.structGet(prev, "LLRCell", []);
    if isempty(rawLLR)
        rawLLR = sixgr.util.structGet(prev, "RateRecoveredLLRCell", []);
    end
    if iscell(rawLLR)
        for c = 1:min(n, numel(rawLLR))
            priorLLRCell{c} = rawLLR{c};
        end
    elseif ~hadSoftBuffer
        priorLLRCell{1} = sixgr.util.structGet(prev, "LLR", sixgr.util.structGet(prev, "RateRecoveredLLR", []));
    end
    rawLayout = sixgr.util.structGet(prev, "CodingLayouts", []);
    if iscell(rawLayout)
        for c = 1:min(n, numel(rawLayout))
            priorLayoutCell{c} = rawLayout{c};
        end
    elseif isstruct(rawLayout) && numel(rawLayout) >= n
        for c = 1:n
            priorLayoutCell{c} = rawLayout(c);
        end
    else
        priorLayoutCell{1} = sixgr.util.structGet(prev, "CodingLayout", struct());
    end
else
    priorLLRCell{1} = prev;
end
end

function value = localCellOrScalar(container, idx, fallback)
value = fallback;
if iscell(container)
    if numel(container) >= idx
        value = container{idx};
    end
elseif isstruct(container) && numel(container) >= idx && idx > 1
    value = container(idx);
elseif ~isempty(container)
    value = container;
end
end

function info = localSummarizeCombineInfo(infoCell)
applied = false(1, numel(infoCell));
cur = zeros(1, numel(infoCell));
prior = zeros(1, numel(infoCell));
reasons = strings(1, numel(infoCell));
gain = NaN(1, numel(infoCell));
overlap = NaN(1, numel(infoCell));
for c = 1:numel(infoCell)
    applied(c) = logical(sixgr.util.structGet(infoCell{c}, "Applied", false));
    cur(c) = double(sixgr.util.structGet(infoCell{c}, "CurrentNumel", NaN));
    prior(c) = double(sixgr.util.structGet(infoCell{c}, "PriorNumel", NaN));
    reasons(c) = string(sixgr.util.structGet(infoCell{c}, "Reason", ""));
    gain(c) = double(sixgr.util.structGet(infoCell{c}, "LLRCombiningGain_dB", NaN));
    overlap(c) = double(sixgr.util.structGet(infoCell{c}, "OverlapPositionCount", NaN));
end
finiteGain = gain(isfinite(gain));
finiteOverlap = overlap(isfinite(overlap));
info = struct( ...
    "Applied", any(applied), ...
    "AppliedPerCodeword", logical(applied), ...
    "PositionAware", any(cellfun(@(x) logical(sixgr.util.structGet(x, "PositionAware", false)), infoCell)), ...
    "Reason", char(strjoin(reasons, "|")), ...
    "CurrentNumel", double(sum(cur(isfinite(cur)))), ...
    "PriorNumel", double(sum(prior(isfinite(prior)))), ...
    "OverlapPositionCount", double(localSumOrNaN(finiteOverlap)), ...
    "LLRCombiningGain_dB", double(localMeanOrNaN(finiteGain)), ...
    "SoftBufferCell", {cellfun(@(x) sixgr.util.structGet(x, "SoftBuffer", struct()), infoCell, "UniformOutput", false)});
if numel(info.SoftBufferCell) == 1
    info.SoftBuffer = info.SoftBufferCell{1};
else
    info.SoftBuffer = struct("ContractVersion", "HARQSoftBufferCollection/v1", ...
        "SoftBufferCell", {info.SoftBufferCell});
end
end

function y = localMeanOrNaN(x)
if isempty(x)
    y = NaN;
else
    y = mean(double(x), "omitnan");
end
end

function y = localSumOrNaN(x)
if isempty(x)
    y = NaN;
else
    y = sum(double(x), "omitnan");
end
end
function [ok, meanIter] = localDecodeCombinedLLR(tx, recLLR, cfg, layout)
ok = false;
meanIter = NaN;
if iscell(recLLR)
    okVec = false(1, numel(recLLR));
    iterVec = NaN(1, numel(recLLR));
    for c = 1:numel(recLLR)
        [okVec(c), iterVec(c)] = localDecodeCombinedLLR(tx, recLLR{c}, cfg, localCellOrScalar(layout, c, struct()));
    end
    ok = all(okVec);
    meanIter = mean(iterVec(isfinite(iterVec)), "omitnan");
    return;
end
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
