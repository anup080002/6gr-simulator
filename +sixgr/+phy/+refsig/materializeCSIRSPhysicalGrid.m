function out = materializeCSIRSPhysicalGrid(carrier, cfg, options)
%MATERIALIZECSIRSPHYSICALGRID Build the configured NZP CSI-RS TX grid.
% This is the cell-common CSI-RS producer.  It is independent of a PDSCH
% grant, transport block, DCI result, HARQ state, or UE report payload.
arguments
    carrier (1,1) nrCarrierConfig
    cfg (1,1) struct
    options.BaseGrid = []
    options.WaveformPortCount (1,1) double = NaN
    options.OwnershipMode (1,1) string = "emit"
end

mode = lower(strtrim(options.OwnershipMode));
if ~ismember(mode, ["emit","reserve_only"])
    error("sixgr:refsig:InvalidCSIRSOwnershipMode", ...
        "CSI-RS ownership mode must be emit or reserve_only.");
end

K = 12 * double(carrier.NSizeGrid);
L = double(carrier.SymbolsPerSlot);
grid = options.BaseGrid;
if isempty(grid)
    waveformPorts = double(options.WaveformPortCount);
    if ~isfinite(waveformPorts)
        waveformPorts = double(sixgr.util.structGet(cfg, "channel.nTxAnt", NaN));
    end
    validateattributes(waveformPorts, {'numeric'}, ...
        {'scalar','real','finite','integer','positive'});
    grid = complex(zeros(K, L, waveformPorts));
else
    validateattributes(grid, {'single','double'}, {'finite'});
    assert(ndims(grid) <= 3 && size(grid,1) == K && size(grid,2) == L, ...
        'sixgr:refsig:CSIRSBaseGridDimensions', ...
        'CSI-RS base grid must match the configured carrier slot.');
    waveformPorts = size(grid,3);
    if isfinite(options.WaveformPortCount)
        assert(waveformPorts == options.WaveformPortCount, ...
            'sixgr:refsig:CSIRSWaveformPortCountMismatch', ...
            'Base-grid pages and configured waveform ports must agree.');
    end
end

[indices, symbols, info, configuration] = ...
    sixgr.phy.refsig.csirs(carrier, cfg);
scheduled = logical(sixgr.util.structGet(info, "Scheduled", ~isempty(symbols)));
event = localEmptyEvent(cfg);
event.Scheduled = scheduled;
event.CellCommonSignalOwnershipMode = char(mode);
event.Periodicity = localToken(sixgr.util.structGet(info, "Periodicity", ""));
event.NumResources = double(sixgr.util.structGet(info, "NumResources", NaN));
event.ResourceIDs = localToken(sixgr.util.structGet(info, "ResourceIDs", ...
    sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0)));
event.NumPorts = double(sixgr.util.structGet(info, "NumCSIRSPorts", NaN));
event.RowNumber = double(sixgr.util.structGet(info, "RowNumber", NaN));
event.SymbolLocations = localToken(sixgr.util.structGet(info, "SymbolLocations", []));
event.SubcarrierLocations = localToken(sixgr.util.structGet(info, "SubcarrierLocations", []));
event.RBOffset = double(localFirst(sixgr.util.structGet(info, "RBOffset", NaN)));
event.NumRB = double(localFirst(sixgr.util.structGet(info, "NumRB", NaN)));
event.NRE = double(numel(symbols));
event.WaveformPortCount = double(waveformPorts);
event.RuntimeEvidenceSource = ...
    "sixgr.phy.refsig.materializeCSIRSPhysicalGrid:configured_cell_common_producer";

if ~logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false))
    event.RuntimeMaterializationStatus = "disabled";
    event.Blocker = "phy.csirs.enable_false";
    event.UpdateOutcome = "not_scheduled";
    out = localOutput(grid, indices, symbols, info, configuration, event);
    return;
end
if ~scheduled
    assert(isempty(indices) && isempty(symbols), ...
        'sixgr:refsig:CSIRSCalendarMaterializationMismatch', ...
        'An inactive configured CSI-RS occasion must not produce REs.');
    event.RuntimeMaterializationStatus = "configured_not_scheduled_this_slot";
    event.Blocker = "outside_yaml_csirs_period_offset";
    event.UpdateOutcome = "not_scheduled";
    out = localOutput(grid, indices, symbols, info, configuration, event);
    return;
end
assert(~isempty(indices) && ~isempty(symbols), ...
    'sixgr:refsig:EmptyScheduledCSIRS', ...
    'A scheduled CSI-RS occasion must resolve to physical reference REs.');
if mode == "reserve_only"
    event.RuntimeMaterializationStatus = "reserved_only_cell_common_plane_owned_elsewhere";
    event.UpdateOutcome = "reserved_not_duplicated_in_user_dedicated_component";
    out = localOutput(grid, indices, symbols, info, configuration, event);
    return;
end

resources = sixgr.util.structGet(info, "Resources", []);
if isempty(resources)
    resources = struct("ResourceID", double(sixgr.util.structGet( ...
        cfg, "phy.csirs.resourceID", 0)), "Indices", indices, ...
        "Symbols", symbols);
end
precoders = complex(sixgr.util.structGet(cfg, "phy.csirs.precoderMatrices", []));
if isempty(precoders)
    if logical(sixgr.util.structGet(cfg, "phy.mimo.strict", false)) || ...
            numel(resources) ~= 1 || event.NumPorts ~= waveformPorts
        error("sixgr:refsig:MissingCSIRSPhysicalPrecoder", ...
            ['Scheduled independent CSI-RS requires a YAML-materialized ' ...
             'physical precoder per resource.']);
    end
    precoders = eye(waveformPorts);
    precoderAuthority = "identity_physical_ports_explicit_equal_port_fallback";
else
    precoderAuthority = ...
        "yaml_dft_ura_physical_csirs_resource_filter_via_runtime_port_projection";
end
if size(precoders,3) ~= numel(resources)
    error("sixgr:refsig:CSIRSPrecoderDimensionMismatch", ...
        "CSI-RS precoder shape %s does not match %d configured resource(s).", ...
        mat2str(size(precoders)), numel(resources));
end

physicalElements = size(precoders,1);
if physicalElements == waveformPorts
    portToElement = eye(waveformPorts);
    projectionSource = "identity_element_domain_waveform";
else
    architecture = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture( ...
        cfg, "bs", "Signal", "PDSCH", "NumElements", physicalElements, ...
        "NumPorts", waveformPorts, "MinimumPorts", waveformPorts);
    portToElement = complex(double(architecture.PortToElementMatrix));
    projectionSource = ...
        "AntennaArrayFactory.resolvePortArchitecture.PDSCH.PortToElementMatrix";
end
assert(isequal(size(portToElement), [physicalElements waveformPorts]) && ...
    all(isfinite(real(portToElement(:)))) && ...
    all(isfinite(imag(portToElement(:)))), ...
    'sixgr:refsig:CSIRSPortProjectionDimensions', ...
    'CSI-RS port-to-element projection has invalid dimensions or values.');
gramResidual = norm(portToElement' * portToElement - eye(waveformPorts), "fro");
if gramResidual > 1e-10
    error("sixgr:refsig:InvalidCSIRSPortProjection", ...
        "CSI-RS runtime projection is not semi-unitary (residual %.3g).", ...
        gramResidual);
end

plane = K * L;
resourceEvents = repmat(localEmptyResourceEvent(), numel(resources), 1);
occupied = zeros(0,1);
for ordinal = 1:numel(resources)
    resource = resources(ordinal);
    W = complex(precoders(:,:,ordinal));
    localAssertPrecoder(W, resource.ResourceID);
    [logicalSymbols, baseIndices, prb, symbolNumber] = ...
        localLogicalResourceMatrix(double(resource.Indices), ...
        complex(resource.Symbols), K, L, size(W,2));
    if ~isempty(intersect(baseIndices(:), occupied))
        error("sixgr:refsig:CSIRSResourceCollision", ...
            "CSI-RS resource %g overlaps another CSI-RS resource.", ...
            double(resource.ResourceID));
    end
    occupied = [occupied; baseIndices(:)]; %#ok<AGROW>
    if physicalElements == waveformPorts
        waveformPrecoder = W;
        projectionResidual = 0;
    else
        waveformPrecoder = portToElement' * W;
        projectionResidual = norm(portToElement * waveformPrecoder - W, "fro") / ...
            max(norm(W, "fro"), eps);
        if ~(isfinite(projectionResidual) && projectionResidual <= 1e-9)
            error("sixgr:refsig:CSIRSPrecoderOutsideRuntimePortSubspace", ...
                ['CSI-RS resource %g physical precoder is outside the ' ...
                 'configured runtime port subspace (residual %.3g).'], ...
                double(resource.ResourceID), projectionResidual);
        end
    end
    waveformSymbols = waveformPrecoder * logicalSymbols;
    localAssertMappedSymbols(waveformPrecoder, waveformSymbols, resource.ResourceID);
    grid = localMap(grid, baseIndices, waveformSymbols);
    [waveformIndices, mappedSymbols] = ...
        localPhysicalMapping(baseIndices, waveformSymbols, plane);
    re = localEmptyResourceEvent();
    re.ResourceID = double(resource.ResourceID);
    re.MappedRE = double(nnz(logicalSymbols));
    re.PhysicalRE = double(numel(W * logicalSymbols));
    re.PhysicalPortCount = double(size(W,1));
    re.WaveformPortCount = double(waveformPorts);
    re.LogicalPortCount = double(size(W,2));
    re.PrecoderSource = char(precoderAuthority);
    re.PrecoderDigest = sixgr.phy.mimo.MatrixContract.digest(W);
    re.WaveformPrecoderDigest = ...
        sixgr.phy.mimo.MatrixContract.digest(waveformPrecoder);
    re.PortToElementMatrixDigest = ...
        sixgr.phy.mimo.MatrixContract.digest(portToElement);
    re.PortProjectionSource = char(projectionSource);
    re.PortProjectionResidual = double(projectionResidual);
    beamIndices = double(sixgr.util.structGet( ...
        cfg, "phy.csirs.precoderBeamIndices", ...
        nan(numel(resources), size(W,2))));
    if size(beamIndices,1) >= ordinal
        re.BeamIndices = beamIndices(ordinal,:);
    end
    re.PRBSpan = [min(prb) max(prb)];
    re.SymbolSet = unique(symbolNumber(:)).';
    re.MappingStatus = ...
        "logical_csirs_ports_mapped_to_actual_waveform_port_grid";
    re.WaveformIndices = waveformIndices;
    re.WaveformSymbols = mappedSymbols;
    re.WaveformMappedRE = numel(waveformIndices);
    resourceEvents(ordinal) = re;
end

event.Transmitted = true;
event.ResourceEvents = resourceEvents;
event.PhysicalPortCount = max(double([resourceEvents.PhysicalPortCount]));
event.WaveformPortCount = double(waveformPorts);
event.PrecoderSource = strjoin(unique(string({resourceEvents.PrecoderSource}), ...
    "stable"), "|");
event.PrecoderDigests = string({resourceEvents.PrecoderDigest});
event.WaveformPrecoderDigests = string({resourceEvents.WaveformPrecoderDigest});
event.PortToElementMatrixDigests = ...
    string({resourceEvents.PortToElementMatrixDigest});
event.PortProjectionSource = strjoin(unique(string( ...
    {resourceEvents.PortProjectionSource}), "stable"), "|");
event.PortProjectionResidualMax = max(double( ...
    [resourceEvents.PortProjectionResidual]), [], "omitnan");
event.WaveformIndices = vertcat(resourceEvents.WaveformIndices);
event.WaveformSymbols = vertcat(resourceEvents.WaveformSymbols);
event.WaveformMappedRE = numel(event.WaveformIndices);
if any(abs(grid(event.WaveformIndices) - event.WaveformSymbols) > 1e-12)
    error("sixgr:refsig:CSIRSExecutedGridEvidenceMismatch", ...
        "CSI-RS evidence does not match the transmitted physical grid.");
end
if physicalElements == waveformPorts
    event.RuntimeMaterializationStatus = ...
        "physical_element_domain_csirs_resource_set_mapping";
else
    event.RuntimeMaterializationStatus = ...
        "physical_element_precoder_exact_runtime_port_projection_mapping";
end
event.UpdateOutcome = ...
    "all_configured_resources_precoded_and_transmitted_on_physical_grid";
out = localOutput(grid, indices, symbols, info, configuration, event);
end

function out = localOutput(grid, indices, symbols, info, configuration, event)
out = struct("Grid", grid, "Indices", indices, "Symbols", symbols, ...
    "Info", info, "Configuration", configuration, "Event", event);
end

function event = localEmptyEvent(cfg)
event = struct("SignalFamily","CSI-RS","SignalDirection","DL", ...
    "ResourceID",double(sixgr.util.structGet(cfg,"phy.csirs.resourceID",0)), ...
    "ResourceSetID",double(sixgr.util.structGet(cfg,"phy.csirs.resourceSetID",0)), ...
    "Scheduled",false,"Transmitted",false,"Observed",false,"Consumed",false, ...
    "Consumer","","RuntimeMaterializationStatus","","Blocker","", ...
    "UpdateOutcome","","RuntimeEvidenceSource","","NRE",NaN, ...
    "NumPorts",NaN,"RowNumber",NaN,"Periodicity","", ...
    "SymbolLocations","","SubcarrierLocations","","RBOffset",NaN, ...
    "NumRB",NaN,"NumResources",NaN,"ResourceIDs","", ...
    "ResourceEvents",repmat(localEmptyResourceEvent(),0,1), ...
    "PhysicalPortCount",NaN,"WaveformPortCount",NaN, ...
    "PrecoderSource","","PrecoderDigests",strings(0,1), ...
    "WaveformPrecoderDigests",strings(0,1), ...
    "PortToElementMatrixDigests",strings(0,1), ...
    "PortProjectionSource","","PortProjectionResidualMax",NaN, ...
    "WaveformIndices",zeros(0,1), ...
    "WaveformSymbols",complex(zeros(0,1)),"WaveformMappedRE",0, ...
    "CellCommonSignalOwnershipMode","");
end

function event = localEmptyResourceEvent()
event = struct("ResourceID",NaN,"MappedRE",NaN,"PhysicalRE",NaN, ...
    "PhysicalPortCount",NaN,"WaveformPortCount",NaN,"LogicalPortCount",NaN, ...
    "PrecoderSource","","PrecoderDigest","","WaveformPrecoderDigest","", ...
    "PortToElementMatrixDigest","","PortProjectionSource","", ...
    "PortProjectionResidual",NaN,"BeamIndices",[], ...
    "WaveformIndices",zeros(0,1),"WaveformSymbols",complex(zeros(0,1)), ...
    "WaveformMappedRE",0,"PRBSpan",[],"SymbolSet",[],"MappingStatus","");
end

function [logicalSymbols, baseIndices, prb, symbolNumber] = ...
        localLogicalResourceMatrix(indices, symbols, K, L, logicalPorts)
plane = K * L;
assert(~isempty(indices) && numel(indices) == numel(symbols), ...
    'sixgr:refsig:CSIRSResourceSymbolCountMismatch', ...
    'CSI-RS resource indices and symbols must be nonempty and equal length.');
assert(all(isfinite(indices(:))) && all(indices(:) >= 1) && ...
    all(indices(:) == round(indices(:))), ...
    'sixgr:refsig:InvalidCSIRSIndex','CSI-RS indices must be positive integers.');
port = floor((indices(:)-1) ./ plane) + 1;
if any(port > logicalPorts)
    error("sixgr:refsig:CSIRSPrecoderDimensionMismatch", ...
        "CSI-RS reference port exceeds the precoder logical-port dimension.");
end
baseRaw = mod(indices(:)-1, plane) + 1;
baseIndices = unique(baseRaw, "sorted");
logicalSymbols = complex(zeros(logicalPorts, numel(baseIndices)));
[present, positions] = ismember(baseRaw, baseIndices);
assert(all(present),'sixgr:refsig:CSIRSResourceIndexMismatch', ...
    'CSI-RS logical indices could not be resolved on the carrier grid.');
for item = 1:numel(symbols)
    logicalSymbols(port(item),positions(item)) = symbols(item);
end
[subcarrierOne,symbolOne] = ind2sub([K L],baseIndices);
prb = floor((double(subcarrierOne)-1)./12);
symbolNumber = double(symbolOne)-1;
end

function grid = localMap(grid, baseIndices, values)
assert(size(values,1) == size(grid,3) && ...
    size(values,2) == numel(baseIndices), ...
    'sixgr:refsig:CSIRSPhysicalMappingShapeMismatch', ...
    'Physical CSI-RS values must match grid ports and REs.');
for port = 1:size(grid,3)
    page = grid(:,:,port);
    if any(page(baseIndices) ~= 0)
        error("sixgr:refsig:CSIRSResourceCollision", ...
            "CSI-RS collided with another signal on waveform port %d.", port-1);
    end
    page(baseIndices) = values(port,:).';
    grid(:,:,port) = page;
end
end

function [indices, symbols] = localPhysicalMapping(baseIndices, values, plane)
matrix = double(baseIndices(:)) + double(plane) .* (0:(size(values,1)-1));
valueMatrix = transpose(values);
mask = abs(valueMatrix) > 0;
indices = double(matrix(mask));
symbols = complex(valueMatrix(mask));
indices = indices(:); symbols = symbols(:);
if isempty(indices) || numel(unique(indices)) ~= numel(indices)
    error("sixgr:refsig:InvalidCSIRSPhysicalMapping", ...
        "CSI-RS physical mapping must be nonempty and unique.");
end
end

function localAssertPrecoder(W, resourceID)
if any(~isfinite(real(W(:)))) || any(~isfinite(imag(W(:)))) || ...
        any(abs(sum(abs(W).^2,1)-1) > 1e-10)
    error("sixgr:refsig:InvalidCSIRSPhysicalPrecoder", ...
        "CSI-RS resource %g requires finite unit-norm precoder columns.", ...
        double(resourceID));
end
end

function localAssertMappedSymbols(W, values, resourceID)
if any(~isfinite(real(W(:)))) || any(~isfinite(imag(W(:)))) || ...
        any(~isfinite(real(values(:)))) || any(~isfinite(imag(values(:))))
    error("sixgr:refsig:InvalidCSIRSPhysicalPrecoder", ...
        "CSI-RS resource %g produced nonfinite waveform symbols.", ...
        double(resourceID));
end
end

function value = localFirst(raw)
raw = double(raw(:));
raw = raw(isfinite(raw));
if isempty(raw), value = NaN; else, value = raw(1); end
end

function token = localToken(raw)
if isnumeric(raw)
    raw = double(raw(:).'); raw = raw(isfinite(raw));
    token = strjoin(string(raw), "|");
else
    token = string(raw);
end
end
