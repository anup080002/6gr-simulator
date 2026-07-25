function out = RateMatchingIndexSpec(segmentation, rateMatchedBitCount, rv, qm, numLayers, nref)
%RATEMATCHINGINDEXSPEC Independent DL-SCH circular-buffer index oracle.
%   Positions and codeword indices in this oracle are zero based.

if nargin < 6
    nref = [];
end
required = ["BaseGraph","NumCodeBlocks","LiftingSize", ...
    "MotherCodeLength","FillerPositionsZeroBased"];
if ~(isstruct(segmentation) && all(isfield(segmentation, cellstr(required))))
    error("sixgr:pdsch:oracle:BadSegmentation", ...
        "segmentation must be an LDPCSegmentationSpec result.");
end
G = localPositiveInteger(rateMatchedBitCount, "RateMatchedBitCount");
rv = localIntegerInRange(rv, 0, 3, "RV");
qm = localIntegerInRange(qm, 1, 10, "Qm");
nLayers = localIntegerInRange(numLayers, 1, 4, "NumLayers");
quantum = qm * nLayers;
if mod(G, quantum) ~= 0
    error("sixgr:pdsch:oracle:BadRateMatchedBitCount", ...
        "RateMatchedBitCount must be divisible by Qm*NumLayers.");
end
C = double(segmentation.NumCodeBlocks);
N = double(segmentation.MotherCodeLength);
zc = double(segmentation.LiftingSize);
bgn = double(segmentation.BaseGraph);
if isempty(nref)
    ncb = N;
else
    ncb = min(N, localPositiveInteger(nref, "Nref"));
end
if bgn == 1
    factors = [0 17 33 56];
else
    factors = [0 13 25 43];
end
k0 = floor(factors(rv + 1) * ncb / N) * zc;

Gprime = G / quantum;
gamma = mod(Gprime, C);
ePerCB = zeros(1, C);
for c0 = 0:(C - 1)
    if c0 <= C - gamma - 1
        ePerCB(c0 + 1) = quantum * floor(Gprime / C);
    else
        ePerCB(c0 + 1) = quantum * ceil(Gprime / C);
    end
end

allMotherBit = zeros(G, 1);
allCB = zeros(G, 1);
cursor = 1;
for c = 1:C
    cbFiller = double(segmentation.FillerPositionsZeroBased{c}(:));
    encodedFiller = cbFiller - 2 * zc;
    encodedFiller = encodedFiller(encodedFiller >= 0 & encodedFiller < N);
    isFiller = false(ncb, 1);
    encodedFiller = encodedFiller(encodedFiller < ncb);
    isFiller(encodedFiller + 1) = true;
    available = nnz(~isFiller);
    if available == 0
        error("sixgr:pdsch:oracle:EmptyCircularBuffer", ...
            "All Ncb positions are filler bits.");
    end
    E = ePerCB(c);
    selected = zeros(E, 1);
    j = 0;
    k = 0;
    while j < E
        pos = mod(k0 + k, ncb);
        if ~isFiller(pos + 1)
            j = j + 1;
            selected(j) = pos;
        end
        k = k + 1;
    end
    selected = reshape(reshape(selected, E / qm, qm).', [], 1);
    idx = cursor:(cursor + E - 1);
    allMotherBit(idx) = selected;
    allCB(idx) = c - 1;
    cursor = cursor + E;
end

linear = allCB * N + allMotherBit;
out = struct( ...
    "ContractVersion", "IndependentRateMatchingIndexSpec/v1", ...
    "Ncb", ncb, ...
    "K0", k0, ...
    "EPerCodeBlock", ePerCB, ...
    "OutputBitIndexZeroBased", uint32((0:(G - 1)).'), ...
    "MotherCodeBitIndexZeroBased", uint32(allMotherBit), ...
    "CodeBlockIndexZeroBased", uint16(allCB), ...
    "MotherCodeLinearIndexZeroBased", uint32(linear), ...
    "Source", "independent_ts_38_212_rate_matching_index_oracle");
end

function value = localPositiveInteger(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value > 0 && ...
        abs(value - round(value)) < 1e-9)
    error("sixgr:pdsch:oracle:BadInteger", ...
        "%s must be a positive integer.", char(string(name)));
end
value = round(value);
end

function value = localIntegerInRange(raw, lo, hi, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && ...
        abs(value - round(value)) < 1e-9 && value >= lo && value <= hi)
    error("sixgr:pdsch:oracle:BadInteger", ...
        "%s must be an integer in [%d,%d].", char(string(name)), lo, hi);
end
value = round(value);
end
