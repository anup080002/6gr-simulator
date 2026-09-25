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
p.addParameter("Channel", "", @(x) ischar(x) || isstring(x));
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
channel = upper(strtrim(string(p.Results.Channel)));
if strlength(direction) == 0
    if isfield(tx, "PDSCH")
        direction = "DL";
    elseif isfield(tx, "PUSCH") || isfield(tx, "PUCCH") || ...
            isfield(tx, "SRS")
        direction = "UL";
    elseif isfield(tx, "PDCCH")
        direction = "DL";
    end
end
if strlength(channel) == 0
    channel = localInferChannel(tx);
end

parts = {};
symbolsPerSlot = double(tx.Carrier.SymbolsPerSlot);
switch channel
    case "PDSCH"
        if direction ~= "DL"
            error("sixgr:truth:ObservedREDirectionMismatch", ...
                "Executed PDSCH allocation must have Direction='DL'.");
        end
        % The compatibility facade retains ContractVersion but replaces
        % index aliases with Toolbox one-based indices and exposes PDSCH.
        % Only the direct canonical interface owns the zero-based aliases.
        if ~isfield(tx,'PDSCH') && isfield(tx,'ContractVersion') && ...
                string(tx.ContractVersion)=="ExplicitPDSCHTransmitter/v1"
            parts=localCanonicalPDSCHParts(tx);
            defaultLayers=double(tx.NumLayers);
            resolver="executed_canonical_PDSCHTransmitter_zero_based_indices_and_mapped_port_symbols";
        else
        if ~isfield(tx, "PDSCH")
            error("sixgr:truth:MissingExecutedPDSCHConfig", ...
                "DL observed allocation requires tx.PDSCH.");
        end
        result = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH( ...
            tx.Carrier, tx.PDSCH, "AbsoluteSlot", slot0);
        localAssertExecutedIndices(tx, result, ...
            ["PDSCHIndices", "DMRSIndices", "PTRSIndices"]);
        defaultLayers = double(tx.PDSCH.NumLayers);
        resolver = "executed_PDSCH_Tx+nrPDSCHIndices+nrPDSCHDMRSIndices+nrPDSCHPTRSIndices";
        parts = {result.Data, result.DMRS, result.PTRS};
        csirsEvent = sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct());
        if logical(sixgr.util.structGet(csirsEvent, "Transmitted", false))
            if ~isfield(tx, "CSIRSPhysicalIndices") || ...
                    isempty(tx.CSIRSPhysicalIndices)
                error("sixgr:truth:MissingExecutedCSIRSPhysicalIndices", ...
                    ["A transmitted CSI-RS must publish its exact nonzero " ...
                     "waveform-port indices; logical CSI-port indices are not " ...
                     "physical TX-grid occupancy evidence."]);
            end
            parts = localAppendExecutedPart(parts, tx, ...
                "CSIRSPhysicalIndices", "CSI-RS", ...
                "executed_PDSCH_Tx_physical_waveform_port_csirs_indices");
        end
        end
    case "PUSCH"
        if direction ~= "UL"
            error("sixgr:truth:ObservedREDirectionMismatch", ...
                "Executed PUSCH allocation must have Direction='UL'.");
        end
        if ~isfield(tx, "PUSCH")
            error("sixgr:truth:MissingExecutedPUSCHConfig", ...
                "UL observed allocation requires tx.PUSCH.");
        end
        result = sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH( ...
            tx.Carrier, tx.PUSCH, "AbsoluteSlot", slot0);
        localAssertExecutedIndices(tx, result, ...
            ["PUSCHIndices", "DMRSIndices", "PTRSIndices"]);
        defaultLayers = double(tx.PUSCH.NumLayers);
        resolver = "executed_PUSCH_Tx+nrPUSCHIndices+nrPUSCHDMRSIndices+nrPUSCHPTRSIndices";
        parts = {result.Data, result.DMRS, result.PTRS};
    case "SSB"
        localRequireDirection(direction, "DL", channel);
        parts = {localExecutedPart(tx,"PSSIndices","PSS"), ...
            localExecutedPart(tx,"SSSIndices","SSS"), ...
            localExecutedPart(tx,"PBCHIndices","PBCH"), ...
            localExecutedPart(tx,"DMRSIndices","PBCH-DMRS")};
        defaultLayers = 1;
        resolver = "executed_SSB_Tx_per_beam_spatial_grid_and_validated_SS_PBCH_ownership";
    case "PDCCH"
        localRequireDirection(direction, "DL", channel);
        parts = {localExecutedPart(tx, "PDCCHIndices", "DATA"), ...
            localExecutedPart(tx, "DMRSIndices", "DM-RS")};
        defaultLayers = 1;
        resolver = "executed_PDCCH_Tx_indices";
    case "PUCCH"
        localRequireDirection(direction, "UL", channel);
        parts = {localExecutedPart(tx, "PUCCHIndices", "DATA"), ...
            localExecutedPart(tx, "DMRSIndices", "DM-RS")};
        defaultLayers = 1;
        resolver = "executed_PUCCHTransmitter_indices";
    case "SRS"
        localRequireDirection(direction, "UL", channel);
        parts = {localExecutedPart(tx, "SRSIndices", "SRS")};
        defaultLayers = localPositiveObjectProperty(tx, "SRS", "NumSRSPorts", 1);
        resolver = "executed_SRS_Tx_nrSRSIndices";
    case "TRS"
        localRequireDirection(direction, "DL", channel);
        parts = {localExecutedPart(tx, "Indices", "TRS")};
        defaultLayers = size(tx.Grid, 3);
        resolver = "executed_generateTRSWaveform_nrCSIRSIndices";
    case "CSI-RS"
        localRequireDirection(direction, "DL", channel);
        event=sixgr.util.structGet(tx,"CSIRSRuntimeEvent",struct());
        if ~logical(sixgr.util.structGet(event,"Transmitted",false))
            error("sixgr:truth:MissingExecutedCSIRSTransmission", ...
                "Standalone CSI-RS occupancy requires an actually transmitted runtime event.");
        end
        physicalIndices=double(sixgr.util.structGet(tx,"CSIRSPhysicalIndices",zeros(0,1)));
        actualIndices=find(tx.Grid~=0);
        if isempty(physicalIndices) || ...
                ~isequal(sort(physicalIndices(:)),sort(double(actualIndices(:))))
            error("sixgr:truth:ExecutedCSIRSPhysicalIndicesMismatch", ...
                ['Standalone CSI-RS occupancy must equal the nonzero ' ...
                 'executed physical-port grid coordinates exactly.']);
        end
        parts = {localExecutedPart(tx,"CSIRSPhysicalIndices","CSI-RS")};
        defaultLayers = NaN; % Cell-common CSI-RS has ports, not UE data layers.
        resolver = "executed_independent_CSIRS_physical_waveform_port_indices";
    case "PRACH"
        localRequireDirection(direction, "UL", channel);
        [nativeGrid, nativePortDomain] = sixgr.truth.executedPRACHNativeGrid(tx);
        nativeTx = tx; nativeTx.Grid = nativeGrid;
        nativeTx.Indices = find(nativeGrid ~= 0);
        parts = {localExecutedPart(nativeTx, "Indices", "PRACH")};
        defaultLayers = NaN; % PRACH has no scheduled spatial layers.
        symbolsPerSlot = size(nativeGrid, 2); % Native PRACH period, not carrier symbols.
        resolver = "executed_PRACH_native_grid_and_applied_port_mapping";
    otherwise
        error("sixgr:truth:UnsupportedObservedREChannel", ...
            "Observed RE allocation does not support executed channel '%s'.", ...
            char(channel));
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

rows = repmat(localEmptyRow(), 0, 1);
for partIndex = 1:numel(parts)
    part = parts{partIndex};
    if ~(isstruct(part) && isfield(part, "Coordinates0Based") && ...
            ~isempty(part.Coordinates0Based))
        continue;
    end
    partResolver = resolver;
    if isfield(part, "Resolver") && strlength(strtrim(string(part.Resolver))) > 0
        partResolver = string(part.Resolver);
    end
    partChannel = channel;
    partUEID = ueID;
    partLayerCount = layerCount;
    partAllocationID = allocationID;
    if string(part.Label) == "CSI-RS"
        % CSI-RS is a cell transmission.  PDSCH_Tx carries the executed
        % CSI-RS grid so the physical indices can be audited, but invoking
        % this producer once per scheduled UE must not turn that one cell
        % resource into one CSI-RS allocation per PDSCH grant.  Canonicalize
        % its identity independently of the UE grant while retaining the
        % exact executed physical-port coordinates.
        partChannel = "CSI-RS";
        partUEID = NaN;
        partLayerCount = NaN;
        partAllocationID = "csirs_cell_" + string(cellID) + ...
            "_slot_" + string(slot0);
    end
    rows = [rows; localRows(double(part.Coordinates0Based), slot0, ... %#ok<AGROW>
        direction, partChannel, string(part.Label), cellID, partUEID, ...
        partLayerCount, partResolver, partAllocationID, symbolsPerSlot)];
end
if isempty(rows)
    error("sixgr:truth:EmptyObservedREAllocation", ...
        "Executed %s TX produced no exact occupied RE coordinates.", char(channel));
end

T = struct2table(rows, "AsArray", true);
if channel == "PRACH"
    T = sixgr.truth.annotatePRACHNativeAllocation(T, tx, nativeGrid, nativePortDomain);
end
slotsPerFrame = localSlotsPerFrame(tx.Carrier);
T.sfn = floor(T.absolute_slot ./ slotsPerFrame);
T.slot_within_frame = mod(T.absolute_slot, slotsPerFrame);
T = sortrows(T, ["absolute_slot", "direction", "symbol_index", ...
    "subcarrier_start", "port_index", "channel", "component"]);
end

function channel = localInferChannel(tx)
channel = "";
tests = {"PDSCH","PDSCH"; "PUSCH","PUSCH"; "PDCCHIndices","PDCCH"; ...
    "PUCCHIndices","PUCCH"; "SRSIndices","SRS"};
for ii = 1:size(tests, 1)
    if isfield(tx, tests{ii, 1})
        channel = string(tests{ii, 2});
        return;
    end
end
end

function parts=localCanonicalPDSCHParts(tx)
assert(isa(tx.ResourcePlan,'sixgr.pdsch.PDSCHResourcePlan') && ...
    isa(tx.Assignment,'sixgr.pdsch.PDSCHSchedulingAssignment'), ...
    'sixgr:truth:InvalidCanonicalTXAllocation','Canonical TX must retain its immutable assignment and resource plan.');
tx.Assignment.validateForExecution();
indexSets={tx.ResourcePlan.DataIndices,tx.DMRSIndices,tx.PTRSIndices};
symbols={tx.DataPortSymbols,tx.DMRSPortSymbols,tx.PTRSPortSymbols};
names=["DATA","DM-RS","PT-RS"]; fields=["DataIndices","DMRSIndices","PTRSIndices"];
planeSize=size(tx.Grid,1)*size(tx.Grid,2); ports=size(tx.Grid,3); parts=cell(1,3);
for k=1:3
    zero=double(indexSets{k}(:)); values=symbols{k};
    assert(all(isfinite(zero)) && all(zero>=0 & zero<planeSize & zero==fix(zero)) && ...
        size(values,1)==ports && size(values,2)==numel(zero), ...
        'sixgr:truth:InvalidCanonicalTXIndices','Canonical mapped indices and symbols must have exact port dimensions.');
    indices=zeros(0,1);
    for port=1:ports
        ids=zero+1+(port-1)*planeSize;
        assert(isequaln(tx.Grid(ids),reshape(values(port,:),[],1)), ...
            'sixgr:truth:CanonicalTXGridMismatch','Observed coordinates must match the symbols actually mapped by the TX.');
        indices=[indices;ids(tx.Grid(ids)~=0)]; %#ok<AGROW>
    end
    evidence=struct('Grid',tx.Grid); evidence.(fields(k))=indices;
    parts{k}=localExecutedPart(evidence,fields(k),names(k));
end
end

function localRequireDirection(actual, expected, channel)
if actual ~= expected
    error("sixgr:truth:ObservedREDirectionMismatch", ...
        "Executed %s allocation must have Direction='%s'.", ...
        char(channel), char(expected));
end
end

function parts = localAppendExecutedPart(parts, tx, fieldName, label, resolver)
if isfield(tx, fieldName) && ~isempty(tx.(fieldName))
    part = localExecutedPart(tx, fieldName, label);
    part.Resolver = string(resolver);
    parts{end + 1} = part;
end
end

function part = localExecutedPart(tx, fieldName, label)
if ~isfield(tx, fieldName) || isempty(tx.(fieldName))
    part = struct("Coordinates0Based", zeros(0, 3), ...
        "Label", string(label), "Resolver", "");
    return;
end
if ~isfield(tx, "Grid") || isempty(tx.Grid)
    error("sixgr:truth:MissingExecutedTXGrid", ...
        "Executed TX field %s cannot be resolved without its mapped resource grid.", ...
        fieldName);
end
gridSize = size(tx.Grid);
if numel(gridSize) < 3
    gridSize(3) = 1;
end
rawIndices = tx.(fieldName);
if ~isnumeric(rawIndices) || ~isreal(rawIndices)
    error("sixgr:truth:InvalidExecutedREIndices", ...
        "Executed TX field %s requires real numeric integer indices.", fieldName);
end
indices = double(rawIndices(:));
if any(~isfinite(indices)) || any(indices ~= fix(indices)) || ...
        any(indices < 1) || any(indices > prod(gridSize(1:3)))
    error("sixgr:truth:InvalidExecutedREIndices", ...
        "Executed TX field %s contains indices outside its mapped resource grid.", ...
        fieldName);
end
mapped = tx.Grid(indices);
if any(~isfinite(real(mapped))) || any(~isfinite(imag(mapped))) || any(abs(mapped) == 0)
    error("sixgr:truth:ExecutedRENotMapped", ...
        "Executed TX field %s contains a nonfinite or zero-valued mapped RE.", ...
        fieldName);
end
[subcarrier, symbol, port] = ind2sub(gridSize(1:3), indices);
part = struct("Coordinates0Based", ...
    [double(subcarrier(:))-1 double(symbol(:))-1 double(port(:))-1], ...
    "Label", string(label), "Resolver", "");
end

function value = localPositiveObjectProperty(tx, fieldName, propertyName, fallback)
value = fallback;
if isfield(tx, fieldName) && isobject(tx.(fieldName)) && ...
        isprop(tx.(fieldName), propertyName)
    candidate = double(tx.(fieldName).(propertyName));
    if isfinite(candidate) && candidate >= 1
        value = candidate;
    end
end
end

function value = localSlotsPerFrame(carrier)
value = NaN;
if isprop(carrier, "SlotsPerSubframe")
    value = 10 * round(double(carrier.SlotsPerSubframe));
elseif isprop(carrier, "SubcarrierSpacing")
    value = 10 * round(double(carrier.SubcarrierSpacing) / 15);
end
if ~(isfinite(value) && value >= 10)
    error("sixgr:truth:MissingCarrierTiming", ...
        "Executed carrier does not expose a valid slots-per-frame timing contract.");
end
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
        cellID, ueID, layerCount, resolver, allocationID, symbolsPerSlot)
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
        row.absolute_slot = slot0 + floor(keys(keyIndex, 1)/symbolsPerSlot);
        row.direction = direction;
        row.channel = channel;
        row.component = component;
        row.subcarrier_start = run(1);
        row.subcarrier_count = numel(run);
        row.symbol_index = mod(keys(keyIndex, 1),symbolsPerSlot);
        row.port_index = keys(keyIndex, 2);
        row.re_count = numel(run);
        row.active_flag = true;
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
    "evidence_scope", "runtime_observed_tx_occupancy", ...
    "active_flag", false, "grid_domain", "carrier_cp_ofdm");
end
