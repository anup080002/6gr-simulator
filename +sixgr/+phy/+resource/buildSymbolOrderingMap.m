function order = buildSymbolOrderingMap(carrierOrGrid, indices, domain)
%BUILDSYMBOLORDERINGMAP Preserve the resource-index order of symbol arrays.
%   The map is intentionally structural metadata: it records which
%   subcarrier, OFDM symbol, and layer/port plane each symbol matrix cell
%   corresponds to without reordering or flattening the payload.

if nargin < 3
    domain = "";
end
domain = lower(strtrim(string(domain)));
if strlength(domain) == 0
    domain = "unknown";
end
idx = double(indices);
order = struct( ...
    "Domain", char(domain), ...
    "Ordering", "matrix_column_major_matches_nr_resource_indices", ...
    "IndexBase", "1based", ...
    "IndexShape", size(indices), ...
    "LinearIndex", idx, ...
    "VectorOrder", reshape(1:numel(idx), size(idx)), ...
    "SubcarrierIndex", NaN(size(idx)), ...
    "OFDMSymbolIndex", NaN(size(idx)), ...
    "PlaneIndex", NaN(size(idx)), ...
    "LayerIndex", NaN(size(idx)), ...
    "PortIndex", NaN(size(idx)));

if isempty(idx)
    return;
end

[K, Nsym, Nplane] = localGridDimensions(carrierOrGrid, idx);
if ~(isfinite(K) && K > 0 && isfinite(Nsym) && Nsym > 0 && isfinite(Nplane) && Nplane > 0)
    return;
end

finite = isfinite(idx) & idx >= 1 & idx <= K * Nsym * Nplane;
if ~any(finite(:))
    return;
end
[sc, sym, plane] = ind2sub([K, Nsym, Nplane], idx(finite));
order.SubcarrierIndex(finite) = double(sc);
order.OFDMSymbolIndex(finite) = double(sym);
order.PlaneIndex(finite) = double(plane);
if domain == "layer"
    order.LayerIndex(finite) = double(plane);
elseif domain == "port"
    order.PortIndex(finite) = double(plane);
end
end

function [K, Nsym, Nplane] = localGridDimensions(carrierOrGrid, idx)
K = NaN;
Nsym = NaN;
Nplane = max(size(idx, 2), 1);
if isnumeric(carrierOrGrid) || islogical(carrierOrGrid)
    dims = size(carrierOrGrid);
    if numel(dims) >= 2
        K = dims(1);
        Nsym = dims(2);
        if numel(dims) >= 3
            Nplane = max([Nplane, dims(3)]);
        end
    end
    return;
end
try
    K = double(carrierOrGrid.NSizeGrid) * 12;
catch
end
try
    Nsym = double(carrierOrGrid.SymbolsPerSlot);
catch
end
if ~(isfinite(Nsym) && Nsym > 0)
    Nsym = 14;
end
maxIdx = max(idx(:), [], "omitnan");
if isfinite(K) && K > 0 && isfinite(Nsym) && Nsym > 0 && isfinite(maxIdx)
    Nplane = max(Nplane, ceil(maxIdx / (K * Nsym)));
end
end
