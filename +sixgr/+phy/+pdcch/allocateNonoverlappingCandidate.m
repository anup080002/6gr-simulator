function [pdcch, coordinates] = allocateNonoverlappingCandidate(carrier, pdcch, occupied)
%ALLOCATENONOVERLAPPINGCANDIDATE Select a legal, unoccupied configured candidate.
% Coordinates are [subcarrier relative to CRB0, symbol within slot], zero
% based. Include both payload and DM-RS REs, independent of antenna/port.
% The caller owns the cell and absolute control-slot reservation lifetime.
validateattributes(occupied, {'numeric'}, ...
    {'real','finite','integer','nonnegative','2d','ncols',2});
if ~isempty(pdcch.CCEOffset)
    % An explicitly located transmission must not silently move elsewhere.
    candidates = pdcch.AllocatedCandidate;
else
    levelIndex = find([1 2 4 8 16] == pdcch.AggregationLevel, 1);
    candidates = 1:pdcch.SearchSpace.NumCandidates(levelIndex);
end
for candidate = candidates
    pdcch.AllocatedCandidate = candidate;
    [dataIndices, ~, dmrsIndices] = nrPDCCHResources(carrier, pdcch);
    indices = double([dataIndices(:); dmrsIndices(:)]);
    if isempty(indices)
        continue;
    end
    nSubcarriers = 12 * double(carrier.NSizeGrid);
    symbol = floor((indices - 1) / nSubcarriers);
    subcarrier = mod(indices - 1, nSubcarriers) + 12 * double(carrier.NStartGrid);
    coordinates = unique([subcarrier symbol], 'rows');
    if isempty(intersect(coordinates, double(occupied), 'rows'))
        return;
    end
end
error('sixgr:phy:pdcch:NoFreeCandidate', ...
    ['No monitored AL%d PDCCH candidate has unoccupied data and DM-RS ' ...
     'resources in this control occasion.'], pdcch.AggregationLevel);
end
