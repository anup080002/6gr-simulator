function [selectedIndex, classification] = reduceBlindHypotheses(validHypotheses)
%REDUCEBLINDHYPOTHESES Reduce CRC-valid PDCCH hypotheses without an oracle.
%
% A blind search can yield more than one CRC-valid resource hypothesis when
% monitored candidates overlap. If every valid hypothesis decodes to the
% same DCI payload, they represent one semantic control observation and the
% most specific (smallest aggregation-level) hypothesis is selected. If the
% payloads differ, selection would require unavailable prior knowledge and
% the result is classified ambiguous so the caller can fail closed.

selectedIndex = 0;
classification = "none";
if isempty(validHypotheses)
    return;
end
if isstruct(validHypotheses)
    validHypotheses = num2cell(validHypotheses(:));
end
if ~iscell(validHypotheses)
    error("sixgr:phy:pdcch:InvalidBlindHypothesisContainer", ...
        "CRC-valid PDCCH hypotheses must be supplied as a cell or struct array.");
end
n = numel(validHypotheses);
if n == 1
    selectedIndex = 1;
    classification = "single";
    return;
end

referenceBits = localBits(validHypotheses{1});
equivalent = true;
for ii = 2:n
    if ~isequal(referenceBits, localBits(validHypotheses{ii}))
        equivalent = false;
        break;
    end
end
if ~equivalent
    classification = "ambiguous";
    return;
end

aggregation = inf(n, 1);
candidate = inf(n, 1);
flat = (1:n).';
for ii = 1:n
    h = validHypotheses{ii};
    aggregation(ii) = localFiniteScalar(h, "CandidateAggregationLevel", inf);
    candidate(ii) = localFiniteScalar(h, "CandidateIndexWithinAggregation", inf);
    flat(ii) = localFiniteScalar(h, "CandidateFlatIndex", ii);
end
[~, order] = sortrows([aggregation candidate flat], [1 2 3]);
selectedIndex = order(1);
classification = "equivalent";
end

function bits = localBits(value)
bits = int8([]);
if isstruct(value) && isfield(value, "DCIBits")
    bits = int8(value.DCIBits(:));
end
end

function value = localFiniteScalar(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName)
    candidate = double(s.(fieldName));
    if isscalar(candidate) && isfinite(candidate)
        value = candidate;
    end
end
end
