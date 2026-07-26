function indices = puschPTRSGridIndices(carrier, pusch, varargin)
%PUSCHPTRSGRIDINDICES Return PUSCH PT-RS indices in carrier-grid domain.
%
% For transform-precoded PUSCH, the linear-index form returned by
% nrPUSCHPTRSIndices is in the transform-precoding sequence domain and
% cannot be used directly to address nrResourceGrid.  The subscript form
% is unambiguous.  This function converts those carrier-oriented
% subscripts to page-aware linear grid indices and preserves one matrix
% column per active antenna port.

parser = inputParser;
parser.FunctionName = "sixgr.phy.resource.puschPTRSGridIndices";
addParameter(parser, "IndexBase", "1based", ...
    @(v) ischar(v) || (isstring(v) && isscalar(v)));
parse(parser, varargin{:});
indexBase = lower(string(parser.Results.IndexBase));
if ~ismember(indexBase, ["1based","0based"])
    error("sixgr:phy:resource:InvalidIndexBase", ...
        "IndexBase must be '1based' or '0based'.");
end

subscripts = nrPUSCHPTRSIndices(carrier, pusch, ...
    "IndexStyle", "subscript", "IndexBase", "1based", ...
    "IndexOrientation", "carrier");
if isempty(subscripts)
    indices = zeros(0, 1);
    return;
end
if size(subscripts, 2) ~= 3 || any(~isfinite(subscripts), "all")
    error("sixgr:phy:resource:InvalidPUSCHPTRSSubscripts", ...
        "PUSCH PT-RS subscript evidence must be a finite M-by-3 matrix.");
end

nSubcarriers = 12 * double(carrier.NSizeGrid);
cyclicPrefix = lower(string(carrier.CyclicPrefix));
if cyclicPrefix == "extended"
    symbolsPerSlot = 12;
else
    symbolsPerSlot = 14;
end
pages = unique(double(subscripts(:, 3)), "stable");
counts = arrayfun(@(page) nnz(subscripts(:, 3) == page), pages);
if any(counts ~= counts(1))
    error("sixgr:phy:resource:IrregularPUSCHPTRSPortMap", ...
        "Each active PUSCH PT-RS port must expose the same RE count.");
end

indices = zeros(counts(1), numel(pages));
gridSize = [nSubcarriers, symbolsPerSlot, max(pages)];
for pageIndex = 1:numel(pages)
    rows = subscripts(:, 3) == pages(pageIndex);
    selected = double(subscripts(rows, :));
    indices(:, pageIndex) = sub2ind(gridSize, ...
        selected(:, 1), selected(:, 2), selected(:, 3));
end
if indexBase == "0based"
    indices = indices - 1;
end
end
