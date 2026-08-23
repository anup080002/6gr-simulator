function T = buildObservedREAllocation(tx, varargin)
%BUILDOBSERVEDREALLOCATION Exact RE occupancy from an executed TX object.
%
% This producer is deliberately downstream of PDSCH_Tx/PUSCH_Tx.  It uses
% the carrier and channel configuration actually consumed by the
% transmitter, rematerializes the Toolbox RE coordinates, and verifies the
% data/DM-RS/PT-RS index vectors against the indices retained by that TX
% object.  The resulting rows are runtime observations, not configured or
% planned occupancy.

p = inputParser;
p.addParameter("Direction", "", @(x) ischar(x) || isstring(x));
p.addParameter("AbsoluteSlot", NaN, @(x) isnumeric(x) && isscalar(x));
p.addParameter("CellID", NaN, @(x) isnumeric(x) && isscalar(x));
p.addParameter("UEID", NaN, @(x) isnumeric(x) && isscalar(x));
p.addParameter("LayerCount", NaN, @(x) isnumeric(x) && isscalar(x));
p.addParameter("AllocationID", "", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});

if ~(isstruct(tx) && isfield(tx, "Carrier"))
    error("sixgr:truth:MissingExecutedTXAllocation", ...
        "Observed RE allocation requires the executed TX structure and carrier.");
end
slot0 = double(p.Results.AbsoluteSlot);
if ~(isfinite(slot0) && slot0 >= 0 && slot0 == fix(slot0))
    error("sixgr:truth:InvalidObservedREAbsoluteSlot", ...
        "Observed RE allocation requires a finite zero-based absolute slot.");
end

direction = upper(strtrim(string(p.Results.Direction)));
if strlength(direction) == 0
    if isfield(tx, "PDSCH")
        direction = "DL";
    elseif isfield(tx, "PUSCH")
        direction = "UL";
    end
end

switch direction
    case "DL"
        if ~isfield(tx, "PDSCH")
            error("sixgr:truth:MissingExecutedPDSCHConfig", ...
                "DL observed allocation requires tx.PDSCH.");
        end
        result = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH( ...
            tx.Carrier, tx.PDSCH, "AbsoluteSlot", slot0);
        channel = "PDSCH";
        localAssertExecutedIndices(tx, result, ...
            ["PDSCHIndices", "DMRSIndices", "PTRSIndices"]);
        defaultLayers = double(tx.PDSCH.NumLayers);
        resolver = "executed_PDSCH_Tx+nrPDSCHIndices+nrPDSCHDMRSIndices+nrPDSCHPTRSIndices";
    case "UL"
        if ~isfield(tx, "PUSCH")
            error("sixgr:truth:MissingExecutedPUSCHConfig", ...
                "UL observed allocation requires tx.PUSCH.");
        end
        result = sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH( ...
            tx.Carrier, tx.PUSCH, "AbsoluteSlot", slot0);
        channel = "PUSCH";
        localAssertExecutedIndices(tx, result, ...
            ["PUSCHIndices", "DMRSIndices", "PTRSIndices"]);
        defaultLayers = double(tx.PUSCH.NumLayers);
        resolver = "executed_PUSCH_Tx+nrPUSCHIndices+nrPUSCHDMRSIndices+nrPUSCHPTRSIndices";
    otherwise
        error("sixgr:truth:UnsupportedObservedREDirection", ...
            "Observed RE allocation supports DL PDSCH or UL PUSCH, not '%s'.", ...
            char(direction));
end

layerCount = double(p.Results.LayerCount);
if ~(isfinite(layerCount) && layerCount >= 1)
    layerCount = defaultLayers;
end
cellID = double(p.Results.CellID);
if ~isfinite(cellID)
    cellID = double(tx.Carrier.NCellID);
end
ueID = double(p.Results.UEID);
allocationID = strtrim(string(p.Results.AllocationID));
if strlength(allocationID) == 0
    allocationID = lower(channel) + "_slot_" + string(slot0) + ...
        "_ue_" + string(ueID);
end

parts = {result.Data, result.DMRS, result.PTRS};
rows = repmat(localEmptyRow(), 0, 1);
for partIndex = 1:numel(parts)
    part = parts{partIndex};
    if ~(isstruct(part) && isfield(part, "Coordinates0Based") && ...
            ~isempty(part.Coordinates0Based))
        continue;
    end
    rows = [rows; localRows(double(part.Coordinates0Based), slot0, ... %#ok<AGROW>
        direction, channel, string(part.Label), cellID, ueID, ...
        layerCount, resolver, allocationID)];
end
if isempty(rows)
    error("sixgr:truth:EmptyObservedREAllocation", ...
        "Executed %s TX produced no exact occupied RE coordinates.", char(channel));
end

T = struct2table(rows, "AsArray", true);
slotsPerFrame = 10 * round(double(tx.Carrier.SlotsPerSubframe));
T.sfn = floor(T.absolute_slot ./ slotsPerFrame);
T.slot_within_frame = mod(T.absolute_slot, slotsPerFrame);
T = sortrows(T, ["absolute_slot", "direction", "symbol_index", ...
    "subcarrier_start", "port_index", "channel", "component"]);
end

function localAssertExecutedIndices(tx, result, txFields)
resultFields = ["Data", "DMRS", "PTRS"];
for index = 1:numel(txFields)
    txField = char(txFields(index));
    resultField = char(resultFields(index));
    if ~isfield(tx, txField) || isempty(tx.(txField))
        continue;
    end
    expected = sort(unique(double(result.(resultField).Indices1Based(:))));
    executedIndices = tx.(txField);
    observed = sort(unique(double(executedIndices(:))));
    if ~isequal(expected, observed)
        error("sixgr:truth:ExecutedREIndexMismatch", ...
            "Executed TX field %s differs from the Toolbox-rematerialized %s indices.", ...
            txField, resultField);
    end
end
end

function rows = localRows(coords, slot0, direction, channel, component, ...
        cellID, ueID, layerCount, resolver, allocationID)
coords = unique(double(coords), "rows", "sorted");
if size(coords, 2) ~= 3 || any(~isfinite(coords), "all") || ...
        any(coords < 0, "all") || any(coords ~= fix(coords), "all")
    error("sixgr:truth:InvalidObservedRECoordinates", ...
        "Executed RE coordinates must be finite zero-based [subcarrier symbol port] triples.");
end
rows = repmat(localEmptyRow(), 0, 1);
keys = unique(coords(:, 2:3), "rows", "stable");
for keyIndex = 1:size(keys, 1)
    sc = sort(coords(coords(:, 2) == keys(keyIndex, 1) & ...
        coords(:, 3) == keys(keyIndex, 2), 1));
    cuts = [1; find(diff(sc) ~= 1) + 1; numel(sc) + 1];
    for runIndex = 1:(numel(cuts) - 1)
        run = sc(cuts(runIndex):(cuts(runIndex + 1) - 1));
        row = localEmptyRow();
        row.absolute_slot = slot0;
        row.direction = direction;
        row.channel = channel;
        row.component = component;
        row.subcarrier_start = run(1);
        row.subcarrier_count = numel(run);
        row.symbol_index = keys(keyIndex, 1);
        row.port_index = keys(keyIndex, 2);
        row.re_count = numel(run);
        row.cell_id = cellID;
        row.ue_id = ueID;
        row.layer_count = layerCount;
        row.authority = "executed_tx_toolbox_config_and_indices";
        row.resolver = resolver;
        row.allocation_id = allocationID;
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
end
end

function row = localEmptyRow()
row = struct("absolute_slot", NaN, "sfn", NaN, "slot_within_frame", NaN, ...
    "direction", "", "channel", "", "component", "", ...
    "subcarrier_start", NaN, "subcarrier_count", NaN, "symbol_index", NaN, ...
    "port_index", NaN, "re_count", NaN, "cell_id", NaN, "ue_id", NaN, ...
    "layer_count", NaN, "authority", "", "resolver", "", ...
    "allocation_id", "", "coordinate_precision", "exact_contiguous_re_run", ...
    "evidence_scope", "runtime_observed_tx_occupancy");
end
