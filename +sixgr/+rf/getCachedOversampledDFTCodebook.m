function B = getCachedOversampledDFTCodebook(numTxPorts, numBeams)
%GETCACHEDOVERSAMPLEDDFTCODEBOOK Cache oversampled DFT beam codebooks.

numTxPorts = max(1, round(double(numTxPorts)));
numBeams = max(1, round(double(numBeams)));

persistent codebookCache
if isempty(codebookCache)
    codebookCache = containers.Map("KeyType", "char", "ValueType", "any");
end

cacheKey = sprintf("%d|%d", numTxPorts, numBeams);
if isKey(codebookCache, cacheKey)
    B = codebookCache(cacheKey);
    return;
end

n = (0:(numTxPorts - 1)).';
m = 0:(numBeams - 1);
B = exp(-1j * 2 * pi * (n * m) / max(numBeams, 1));
B = B ./ sqrt(max(numTxPorts, 1));
codebookCache(cacheKey) = B;
end
