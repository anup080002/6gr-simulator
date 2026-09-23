function rx = appendMeasuredPHYEvidence(rx, carrier, dmrsInd, dmrsAntInd, dmrsSym, dmrsInfo, ...
        rateMatchedLLR, rateRecoveredLLR, rateRecoveredBatch, rateRecoverInfo, ...
        decoderIterations, parityChecks, codeBlockCRCErrors, decoderAlgorithm, useMexDecoder, transportBlockCRCError)
%APPENDMEASUREDPHYEVIDENCE Attach compact measured PHY evidence to RX output.

if nargin < 1 || ~isstruct(rx)
    rx = struct();
end
if nargin < 4 || isempty(dmrsAntInd)
    dmrsAntInd = dmrsInd;
end
if nargin < 5
    dmrsSym = [];
end
if nargin < 6 || ~isstruct(dmrsInfo)
    dmrsInfo = struct();
end
if nargin < 7
    rateMatchedLLR = [];
end
if nargin < 8
    rateRecoveredLLR = [];
end
if nargin < 9
    rateRecoveredBatch = [];
end
if nargin < 10 || ~(isstruct(rateRecoverInfo) || iscell(rateRecoverInfo))
    rateRecoverInfo = struct();
end
if nargin < 11
    decoderIterations = [];
end
if nargin < 12
    parityChecks = [];
end
if nargin < 13
    codeBlockCRCErrors = [];
end
if nargin < 14
    decoderAlgorithm = "";
end
if nargin < 15
    useMexDecoder = false;
end
if nargin < 16
    transportBlockCRCError = [];
end

dmrs = localDMRSEvidence(carrier, dmrsInd, dmrsAntInd, dmrsSym, dmrsInfo);
rate = localRateRecoverEvidence(rateMatchedLLR, rateRecoveredLLR, rateRecoveredBatch, rateRecoverInfo);
ldpc = localLDPCEvidence(decoderIterations, parityChecks, codeBlockCRCErrors, decoderAlgorithm, useMexDecoder, ...
    transportBlockCRCError);

rx = localAppendFields(rx, dmrs);
rx = localAppendFields(rx, rate);
rx = localAppendFields(rx, ldpc);
end

function evidence = localDMRSEvidence(carrier, dmrsInd, dmrsAntInd, dmrsSym, dmrsInfo)
evidence = struct( ...
    "MeasuredDMRSRECount", localCountOrZero(dmrsInd), ...
    "MeasuredDMRSAntennaRECount", localCountOrZero(dmrsAntInd), ...
    "MeasuredDMRSSymbolCount", NaN, ...
    "MeasuredDMRSPortCount", NaN, ...
    "MeasuredDMRSAntennaPortCount", NaN, ...
    "MeasuredDMRSCDMLengthFD", NaN, ...
    "MeasuredDMRSCDMLengthTD", NaN);

[symbolCount, portCount] = localIndexSymbolAndPortCounts(carrier, dmrsInd);
evidence.MeasuredDMRSSymbolCount = symbolCount;
evidence.MeasuredDMRSPortCount = portCount;
[~, antPortCount] = localIndexSymbolAndPortCounts(carrier, dmrsAntInd);
evidence.MeasuredDMRSAntennaPortCount = antPortCount;

if ~isempty(dmrsSym)
    evidence.MeasuredDMRSRECount = double(numel(dmrsSym));
end
cdmLengths = double(sixgr.util.structGet(dmrsInfo, "CDMLengths", []));
if ~isempty(cdmLengths)
    cdmLengths = cdmLengths(:);
    evidence.MeasuredDMRSCDMLengthFD = cdmLengths(1);
    if numel(cdmLengths) >= 2
        evidence.MeasuredDMRSCDMLengthTD = cdmLengths(2);
    end
end
end

function evidence = localRateRecoverEvidence(rateMatchedLLR, rateRecoveredLLR, rateRecoveredBatch, rateRecoverInfo)
evidence = struct( ...
    "MeasuredRateMatchedCodewordLLRBits", NaN, ...
    "MeasuredRateRecoveredLLRBits", NaN, ...
    "MeasuredRateRecoveredFiniteLLRCount", NaN, ...
    "MeasuredRateRecoverFillerBits", NaN, ...
    "MeasuredRateRecoveredCodeBlockCount", NaN, ...
    "MeasuredRateRecoveredCodeBlockLength_bits", NaN, ...
    "MeasuredRateRecoverNrefBits", NaN);

rateMatchedValues = localNumericValues(rateMatchedLLR);
if ~isempty(rateMatchedValues)
    evidence.MeasuredRateMatchedCodewordLLRBits = double(numel(rateMatchedValues));
end
rateRecoveredValues = localNumericValues(rateRecoveredLLR);
if ~isempty(rateRecoveredValues)
    llr = double(rateRecoveredValues(:));
    evidence.MeasuredRateRecoveredLLRBits = double(numel(llr));
    evidence.MeasuredRateRecoveredFiniteLLRCount = double(sum(isfinite(llr)));
    evidence.MeasuredRateRecoverFillerBits = double(sum(isinf(llr)));
end
[codeBlockLength, codeBlockCount] = localRateRecoveredBatchShape(rateRecoveredBatch);
if isfinite(codeBlockCount)
    evidence.MeasuredRateRecoveredCodeBlockLength_bits = codeBlockLength;
    evidence.MeasuredRateRecoveredCodeBlockCount = codeBlockCount;
end
nref = localNrefUsed(rateRecoverInfo);
if isscalar(nref) && isfinite(nref)
    evidence.MeasuredRateRecoverNrefBits = nref;
end
end

function evidence = localLDPCEvidence(iterations, parityChecks, cbCrcErrors, decoderAlgorithm, useMexDecoder, transportBlockCRCError)
iter = localFiniteVector(iterations);
parity = localFiniteVector(parityChecks);
cbCrc = localFiniteVector(cbCrcErrors);
decodeErrors = localMeasuredDecodeErrors(iter, cbCrc, transportBlockCRCError);

evidence = struct( ...
    "MeasuredLDPCDecoderMeanIterations", NaN, ...
    "MeasuredLDPCDecoderMinIterations", NaN, ...
    "MeasuredLDPCDecoderMaxIterations", NaN, ...
    "MeasuredLDPCParityCheckFailures", NaN, ...
    "MeasuredCodeBlockDecodeErrorCount", NaN, ...
    "MeasuredCodeBlockDecodeCount", NaN, ...
    "MeasuredCodeBlockDecodeFailureRate", NaN, ...
    "MeasuredCodeBlockCRCErrorCount", NaN, ...
    "MeasuredCodeBlockCRCCount", NaN, ...
    "MeasuredCodeBlockCRCFailureRate", NaN, ...
    "MeasuredLDPCDecoderAlgorithm", string(decoderAlgorithm), ...
    "MeasuredLDPCDecoderEngine", localDecoderEngine(useMexDecoder), ...
    "MeasuredLDPCIterationVector", localFormatVector(iterations), ...
    "MeasuredLDPCParityCheckVector", localFormatVector(parityChecks), ...
    "MeasuredCodeBlockDecodeErrorVector", localFormatDecodeVector(decodeErrors), ...
    "MeasuredCodeBlockCRCErrorVector", localFormatVector(cbCrcErrors));

if ~isempty(iter)
    evidence.MeasuredLDPCDecoderMeanIterations = mean(iter, "omitnan");
    evidence.MeasuredLDPCDecoderMinIterations = min(iter);
    evidence.MeasuredLDPCDecoderMaxIterations = max(iter);
end
if ~isempty(parity)
    evidence.MeasuredLDPCParityCheckFailures = double(sum(parity ~= 0));
end
if ~isempty(decodeErrors)
    evidence.MeasuredCodeBlockDecodeCount = double(numel(decodeErrors));
    evidence.MeasuredCodeBlockDecodeErrorCount = double(sum(decodeErrors ~= 0));
    evidence.MeasuredCodeBlockDecodeFailureRate = evidence.MeasuredCodeBlockDecodeErrorCount ./ ...
        max(evidence.MeasuredCodeBlockDecodeCount, eps);
elseif ~isempty(iter)
    evidence.MeasuredCodeBlockDecodeCount = double(numel(iter));
end
if ~isempty(cbCrc)
    evidence.MeasuredCodeBlockCRCCount = double(numel(cbCrc));
    evidence.MeasuredCodeBlockCRCErrorCount = double(sum(cbCrc ~= 0));
    evidence.MeasuredCodeBlockCRCFailureRate = evidence.MeasuredCodeBlockCRCErrorCount ./ ...
        max(evidence.MeasuredCodeBlockCRCCount, eps);
elseif ~isempty(iter)
    % 38.212 code-block CRC24B exists only when LDPC segmentation creates
    % multiple code blocks. A single-code-block decode has zero CB-CRC checks.
    evidence.MeasuredCodeBlockCRCCount = 0;
    evidence.MeasuredCodeBlockCRCErrorCount = 0;
end
end

function errors = localMeasuredDecodeErrors(iter, cbCrc, transportBlockCRCError)
errors = double([]);
if ~isempty(cbCrc)
    errors = cbCrc;
    return;
end
if numel(iter) ~= 1
    return;
end
tbErr = localFiniteVector(transportBlockCRCError);
if isempty(tbErr)
    return;
end
% A single-code-block DL/UL-SCH decode has no CB CRC24B; the decoded
% code-block outcome is therefore measured by the transport-block CRC.
errors = double(tbErr(1) ~= 0);
end

function rx = localAppendFields(rx, evidence)
names = fieldnames(evidence);
for i = 1:numel(names)
    rx.(names{i}) = evidence.(names{i});
end
end

function count = localCountOrZero(x)
if isempty(x)
    count = 0;
else
    count = double(numel(x));
end
end

function [symbolCount, portCount] = localIndexSymbolAndPortCounts(carrier, indices)
symbolCount = NaN;
portCount = NaN;
if isempty(indices)
    symbolCount = 0;
    portCount = 0;
    return;
end
try
    nSubcarriers = 12 * double(carrier.NSizeGrid);
    symbolsPerSlot = double(carrier.SymbolsPerSlot);
catch
    return;
end
if ~(isfinite(nSubcarriers) && nSubcarriers > 0 && isfinite(symbolsPerSlot) && symbolsPerSlot > 0)
    return;
end
idx = double(indices(:));
idx = idx(isfinite(idx) & idx >= 1);
if isempty(idx)
    symbolCount = 0;
    portCount = 0;
    return;
end
nPorts = max(1, ceil(max(idx) / (nSubcarriers * symbolsPerSlot)));
try
    [~, symbolSub, portSub] = ind2sub([nSubcarriers symbolsPerSlot nPorts], idx);
catch
    return;
end
symbolCount = double(numel(unique(symbolSub)));
portCount = double(numel(unique(portSub)));
end

function values = localFiniteVector(raw)
values = localNumericValues(raw);
values = values(isfinite(values));
end

function values = localNumericValues(raw)
values = double([]);
if isempty(raw)
    return;
end
if iscell(raw)
    parts = cell(numel(raw), 1);
    for index = 1:numel(raw)
        parts{index} = localNumericValues(raw{index});
    end
    if ~isempty(parts)
        values = vertcat(parts{:});
    end
    return;
end
try
    values = double(raw(:));
catch
    values = double([]);
end
end

function [lengthBits, count] = localRateRecoveredBatchShape(raw)
lengthBits = NaN;
count = NaN;
if isempty(raw)
    return;
end
if ~iscell(raw)
    raw = {raw};
end
lengths = zeros(0, 1);
count = 0;
for index = 1:numel(raw)
    item = raw{index};
    if isempty(item) || ~(isnumeric(item) || islogical(item))
        continue;
    end
    lengths(end + 1, 1) = size(item, 1); %#ok<AGROW>
    count = count + size(item, 2);
end
if isempty(lengths)
    count = NaN;
elseif numel(unique(lengths)) == 1
    lengthBits = double(lengths(1));
end
count = double(count);
end

function value = localNrefUsed(raw)
value = NaN;
if isempty(raw)
    return;
end
if ~iscell(raw)
    raw = {raw};
end
values = zeros(0, 1);
for index = 1:numel(raw)
    if ~isstruct(raw{index}) || ~isscalar(raw{index})
        return;
    end
    candidate = double(sixgr.util.structGet(raw{index}, "NrefUsed", NaN));
    if isscalar(candidate) && isfinite(candidate)
        values(end + 1, 1) = candidate; %#ok<AGROW>
    else
        % A common per-transmission value requires evidence from every
        % codeword. Do not silently discard an unavailable codeword.
        return;
    end
end
if ~isempty(values) && numel(unique(values)) == 1
    value = double(values(1));
end
end

function txt = localFormatVector(raw)
txt = "";
values = localFiniteVector(raw);
if isempty(values)
    return;
end
txt = strjoin(string(values.'), "|");
end

function txt = localFormatDecodeVector(raw)
txt = "";
values = localFiniteVector(raw);
if isempty(values)
    return;
end
txt = "[" + strjoin(string(values.'), "|") + "]";
end

function engine = localDecoderEngine(useMexDecoder)
if logical(useMexDecoder)
    engine = "mex_ldpc_batch";
else
    engine = "matlab_ldpc_decode";
end
end
