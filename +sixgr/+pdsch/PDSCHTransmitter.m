function tx = PDSCHTransmitter(transportBlocks, assignment, resourcePlan, ...
        carrier, referenceConfig, varargin)
%PDSCHTRANSMITTER Execute the canonical explicit PDSCH/DL-SCH TX chain.
%
% TX = PDSCHTransmitter(TB,ASSIGNMENT,RESOURCEPLAN,CARRIER,REFCFG,...)
%
% REFCFG must be an immutable PDSCHReferenceSignalConfig.  Callers provide
% configuration only; DM-RS/PT-RS indices and symbols are generated and
% independently validated inside this transmitter boundary.
%
% Name-value options:
%   PrecoderBundle - optional sixgr.pdsch.PDSCHPrecoderBundle
%   IntegrationContext - required active BWP/CC/epoch/TCI context for
%                        connected_strict, sps_strict, and ra_si_strict
%   Nref           - empty, scalar, or one value per codeword
%
% No coding, allocation, scrambling, reference, or precoding policy is
% inferred from a fallback configuration.

localRequireStrictObjects(assignment, resourcePlan, carrier);
assignment.validateForExecution();
if ~isa(referenceConfig, ...
        "sixgr.pdsch.PDSCHReferenceSignalConfig")
    error("sixgr:pdsch:PDSCHTransmitter:MissingImmutableReferenceConfiguration", ...
        "Strict PDSCH TX requires PDSCHReferenceSignalConfig.");
end
referenceConfig.validateForExecution();
referenceData = referenceConfig.toStruct();
ip = inputParser;
ip.FunctionName = "sixgr.pdsch.PDSCHTransmitter";
ip.addParameter("PrecoderBundle", [], ...
    @(x) isempty(x) || isa(x, "sixgr.pdsch.PDSCHPrecoderBundle"));
ip.addParameter("IntegrationContext", struct(), ...
    @(x) isstruct(x) && isscalar(x));
ip.addParameter("Nref", [], @(x) isempty(x) || isnumeric(x));
ip.parse(varargin{:});
opt = ip.Results;

integrationBinding = localResolveIntegrationBinding( ...
    assignment, opt.IntegrationContext, opt.PrecoderBundle);
localValidateCarrierSymbolBoundary(assignment, carrier);
contract = localResolveContract(assignment, resourcePlan, referenceData);
[tbCells, tbs] = localTransportBlocks(transportBlocks, contract.NumCodewords);
nref = localPerCodewordOptional(opt.Nref, contract.NumCodewords, "Nref");
plans = localResolveCodingPlans(contract, resourcePlan, tbs, nref);
encode = sixgr.pdsch.DLSCHEncoder( ...
    localUnwrapOne(tbCells), localUnwrapOne(plans));
rateMatchedBits = localEncodedRateMatchedBits(encode, contract.NumCodewords);

scrambledBits = cell(1, contract.NumCodewords);
scramblingInfo = cell(1, contract.NumCodewords);
codewordSymbols = cell(1, contract.NumCodewords);
modulationInfo = cell(1, contract.NumCodewords);
for cw = 1:contract.NumCodewords
    [scrambledBits{cw}, scramblingInfo{cw}] = ...
        sixgr.pdsch.PDSCHScrambler(rateMatchedBits{cw}, ...
        contract.RNTI, cw - 1, contract.NID);
    [codewordSymbols{cw}, modulationInfo{cw}] = ...
        sixgr.pdsch.PDSCHModulator( ...
        scrambledBits{cw}, contract.Modulation(cw));
end

[layerSymbols, layerInfo] = sixgr.pdsch.CodewordLayerMapper( ...
    localUnwrapOne(codewordSymbols), contract.NumLayers);
if iscell(layerSymbols)
    error("sixgr:pdsch:PDSCHTransmitter:UnequalLayerLengths", ...
        "Strict PDSCH mapping requires equal symbol counts on every layer.");
end
if ~isequal(size(layerSymbols), ...
        [resourcePlan.ExactDataRECount, contract.NumLayers])
    error("sixgr:pdsch:PDSCHTransmitter:LayerResourcePlanMismatch", ...
        "Mapped layer shape %s does not match exact data plan [%d %d].", ...
        mat2str(size(layerSymbols)), resourcePlan.ExactDataRECount, ...
        contract.NumLayers);
end

[dataPRB, dataSymbol] = localResourceCoordinates( ...
    resourcePlan.DataIndices, carrier);
[dataPortSymbols, dataPrecoderTrace, nPhysicalPorts, precoderMode] = ...
    localApplyPrecoder(opt.PrecoderBundle, layerSymbols.', ...
    dataPRB, dataSymbol, "data", contract, referenceData);

referenceSignals = sixgr.pdsch.PDSCHReferenceSignalGenerator.generate( ...
    assignment,resourcePlan,carrier,referenceConfig);

[dmrsPortSymbols, dmrsIndices, dmrsPrecoderTrace] = ...
    localReferencePortSymbols(resourcePlan.DMRSIndicesPerPort, ...
    referenceSignals.DMRSSymbolsPerPort, "dmrs", opt.PrecoderBundle, ...
    carrier, contract, referenceData);
[ptrsPortSymbols, ptrsIndices, ptrsPrecoderTrace] = ...
    localReferencePortSymbols(resourcePlan.PTRSIndicesPerPort, ...
    referenceSignals.PTRSSymbolsPerPort, "ptrs", opt.PrecoderBundle, ...
    carrier, contract, referenceData);

grid = complex(zeros(carrier.NSizeGrid * 12, ...
    carrier.SymbolsPerSlot, nPhysicalPorts));
grid = localMapPortSymbols(grid, resourcePlan.DataIndices, dataPortSymbols);
grid = localMapPortSymbols(grid, dmrsIndices, dmrsPortSymbols);
grid = localMapPortSymbols(grid, ptrsIndices, ptrsPortSymbols);
[waveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate( ...
    carrier, grid, referenceData.OFDMOptions{:});

stageTrace = table( ...
    ["assignment";"resource_plan";"dlsch_coding";"scrambling"; ...
     "modulation";"layer_mapping";"precoding";"dmrs_generation"; ...
     "ptrs_generation";"reference_mapping";"resource_grid"; ...
     "ofdm_modulation"], ...
    repmat("PASS", 12, 1), ...
    [1;1;sum(cellfun(@numel,rateMatchedBits)); ...
     sum(cellfun(@numel,scrambledBits)); ...
     sum(cellfun(@numel,codewordSymbols));numel(layerSymbols); ...
     numel(dataPortSymbols); ...
     sum(cellfun(@numel,referenceSignals.DMRSSymbolsPerPort)); ...
     sum(cellfun(@numel,referenceSignals.PTRSSymbolsPerPort)); ...
     numel(dmrsPortSymbols)+numel(ptrsPortSymbols);nnz(grid); ...
     numel(waveform)], ...
    'VariableNames', {'Stage','Status','MaterializedElementCount'});

tx = struct();
tx.ContractVersion = "ExplicitPDSCHTransmitter/v1";
tx.Assignment = assignment;
tx.ResourcePlan = resourcePlan;
tx.Carrier = carrier;
tx.ReferenceConfig = referenceConfig;
tx.ReferenceSignals = referenceSignals;
tx.CodingPlans = plans;
tx.DLSCHEncode = encode;
tx.RateMatchedBits = rateMatchedBits;
tx.ScrambledBits = scrambledBits;
tx.ScramblingInfo = scramblingInfo;
tx.CodewordSymbols = codewordSymbols;
tx.ModulationInfo = modulationInfo;
tx.LayerSymbols = layerSymbols;
tx.LayerMappingInfo = layerInfo;
tx.PrecoderBundle = opt.PrecoderBundle;
tx.IntegrationBinding = integrationBinding;
tx.PrecoderMode = precoderMode;
tx.DataPortSymbols = dataPortSymbols;
tx.DataPrecoderTrace = dataPrecoderTrace;
tx.DMRSPortSymbols = dmrsPortSymbols;
tx.DMRSIndices = dmrsIndices;
tx.DMRSPrecoderTrace = dmrsPrecoderTrace;
tx.PTRSPortSymbols = ptrsPortSymbols;
tx.PTRSIndices = ptrsIndices;
tx.PTRSPrecoderTrace = ptrsPrecoderTrace;
tx.Grid = grid;
tx.Waveform = waveform;
tx.OFDMInfo = ofdmInfo;
tx.StageTrace = stageTrace;
tx.TransportBlockSizes = tbs;
tx.NumCodewords = contract.NumCodewords;
tx.NumLayers = contract.NumLayers;
tx.NPhysicalTxAntennas = nPhysicalPorts;
tx.Source = "explicit_pdsch_dlsch_production_chain";
end

function binding = localResolveIntegrationBinding( ...
        assignment, context, precoderBundle)
strictProfile = any(assignment.Profile == ...
    ["connected_strict","sps_strict","ra_si_strict"]);
if ~strictProfile
    binding = struct( ...
        "Required", false, ...
        "Profile", assignment.Profile, ...
        "Status", "NOT_REQUIRED_PHY_CALIBRATION");
    return;
end
if isempty(fieldnames(context))
    error("sixgr:pdsch:MissingIntegrationContext", ...
        "Strict PDSCH TX requires the explicit active BWP/CC/epoch/TCI " + ...
        "integration context.");
end
binding = sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, context, precoderBundle);
end

function localValidateCarrierSymbolBoundary(assignment, carrier)
allocation = double(assignment.get("SymbolAllocation"));
if numel(allocation) ~= 2 || any(~isfinite(allocation)) ...
        || any(allocation ~= fix(allocation)) ...
        || allocation(1) < 0 || allocation(2) < 1 ...
        || allocation(1) + allocation(2) > double(carrier.SymbolsPerSlot)
    error("sixgr:pdsch:PDSCHTransmitter:SymbolAllocationOutsideCarrier", ...
        "Assignment SymbolAllocation=%s is outside the carrier's " + ...
        "%d-symbol slot.", mat2str(allocation), carrier.SymbolsPerSlot);
end
end

function localRequireStrictObjects(assignment, resourcePlan, carrier)
if ~isa(assignment, "sixgr.pdsch.PDSCHSchedulingAssignment")
    error("sixgr:pdsch:PDSCHTransmitter:MissingSchedulingAssignment", ...
        "Strict PDSCH TX requires an immutable PDSCHSchedulingAssignment.");
end
if ~isa(resourcePlan, "sixgr.pdsch.PDSCHResourcePlan")
    error("sixgr:pdsch:PDSCHTransmitter:MissingResourcePlan", ...
        "Strict PDSCH TX requires an immutable PDSCHResourcePlan.");
end
if ~isa(carrier, "nrCarrierConfig")
    error("sixgr:pdsch:PDSCHTransmitter:InvalidCarrier", ...
        "Strict PDSCH TX requires an explicit nrCarrierConfig.");
end
end

function contract = localResolveContract(assignment, plan, referenceConfig)
if ~isstruct(referenceConfig) || ~isscalar(referenceConfig)
    error("sixgr:pdsch:PDSCHTransmitter:InvalidReferenceConfig", ...
        "Reference configuration must be a scalar struct.");
end
required = ["DataScramblingIdentityNID", ...
    "NPhysicalTxAntennas","OFDMOptions"];
missing = required(~isfield(referenceConfig, required));
if ~isempty(missing)
    error("sixgr:pdsch:PDSCHTransmitter:IncompleteReferenceConfig", ...
        "Reference configuration is missing: %s.", ...
        strjoin(cellstr(missing), ", "));
end
if ~iscell(referenceConfig.OFDMOptions) ...
        || mod(numel(referenceConfig.OFDMOptions), 2) ~= 0
    error("sixgr:pdsch:PDSCHTransmitter:InvalidOFDMOptions", ...
        "OFDMOptions must be a cell array of name-value pairs.");
end

contract = struct();
contract.NumCodewords = double(assignment.get("NumCodewords"));
contract.NumLayers = double(assignment.get("NumLayers"));
contract.LayerCount = double(assignment.get("LayerCountPerCodeword"));
contract.Modulation = localStringPerCodeword( ...
    assignment.get("ModulationPerCodeword"), contract.NumCodewords, ...
    "ModulationPerCodeword");
contract.TargetCodeRate = localNumericPerCodeword( ...
    assignment.get("TargetCodeRatePerCodeword"), contract.NumCodewords, ...
    "TargetCodeRatePerCodeword");
contract.RV = localNumericPerCodeword( ...
    assignment.get("RVPerCodeword"), contract.NumCodewords, ...
    "RVPerCodeword");
contract.RNTI = double(assignment.get("RNTI"));
contract.NID = double(referenceConfig.DataScramblingIdentityNID);
if ~ismember(contract.NumCodewords, [1 2]) ...
        || contract.NumCodewords ~= 1 + double(contract.NumLayers > 4)
    error("sixgr:pdsch:PDSCHTransmitter:CodewordLayerMismatch", ...
        "Strict PDSCH rank requires one codeword for ranks 1-4 and two for 5-8.");
end
if numel(contract.LayerCount) ~= contract.NumCodewords ...
        || sum(contract.LayerCount) ~= contract.NumLayers ...
        || ~isequal(contract.LayerCount, plan.LayerCountPerCodeword)
    error("sixgr:pdsch:PDSCHTransmitter:CodewordLayerMismatch", ...
        "Assignment and resource-plan codeword layer counts differ.");
end
qms = arrayfun(@localQm, contract.Modulation);
if ~isequal(qms, plan.QmPerCodeword)
    error("sixgr:pdsch:PDSCHTransmitter:ModulationResourcePlanMismatch", ...
        "Assignment modulation orders differ from the resource plan.");
end
if ~isequal(double(assignment.get("PRBSetCarrierRelative")), plan.PRBSet) ...
        || ~isequal(double(assignment.get("SymbolAllocation")), plan.SymbolAllocation)
    error("sixgr:pdsch:PDSCHTransmitter:AssignmentResourcePlanMismatch", ...
        "Assignment PRB/symbol allocation differs from the immutable resource plan.");
end
if ~(isscalar(contract.NID) && isfinite(contract.NID) ...
        && contract.NID == fix(contract.NID) ...
        && contract.NID >= 0 && contract.NID <= 1023)
    error("sixgr:pdsch:PDSCHTransmitter:InvalidScramblingIdentity", ...
        "DataScramblingIdentityNID must be an integer in [0,1023].");
end
if ~(isscalar(contract.RNTI) && isfinite(contract.RNTI) ...
        && contract.RNTI == fix(contract.RNTI) ...
        && contract.RNTI >= 0 && contract.RNTI <= 65535)
    error("sixgr:pdsch:PDSCHTransmitter:InvalidRNTI", ...
        "Assignment RNTI must be an integer in [0,65535].");
end
end

function [cells, sizes] = localTransportBlocks(value, count)
if count == 1 && ~iscell(value)
    cells = {value};
elseif iscell(value)
    cells = reshape(value, 1, []);
else
    cells = {value};
end
if numel(cells) ~= count
    error("sixgr:pdsch:PDSCHTransmitter:TransportBlockCountMismatch", ...
        "Expected %d transport block(s), received %d.", count, numel(cells));
end
sizes = zeros(1, count);
for idx = 1:count
    bits = cells{idx};
    if ~((isnumeric(bits) || islogical(bits)) && isvector(bits) ...
            && ~isempty(bits) && all(isfinite(double(bits(:)))) ...
            && all(bits(:) == 0 | bits(:) == 1))
        error("sixgr:pdsch:PDSCHTransmitter:InvalidTransportBlock", ...
            "Transport block %d must be a nonempty binary vector.", idx - 1);
    end
    cells{idx} = int8(bits(:));
    sizes(idx) = numel(bits);
end
end

function plans = localResolveCodingPlans(contract, resourcePlan, tbs, nref)
plans = cell(1, contract.NumCodewords);
for cw = 1:contract.NumCodewords
    args = {"TransportBlockSize",tbs(cw), ...
        "TargetCodeRate",contract.TargetCodeRate(cw), ...
        "RateMatchedBitCount",resourcePlan.GPerCodeword(cw), ...
        "RV",contract.RV(cw), "Modulation",contract.Modulation(cw), ...
        "NumLayers",contract.LayerCount(cw), "CodewordIndex",cw-1};
    if ~isempty(nref{cw})
        args = [args, {"Nref",nref{cw}}]; %#ok<AGROW>
    end
    plans{cw} = sixgr.pdsch.DLSCHCodingPlan.resolve(args{:});
end
end

function bits = localEncodedRateMatchedBits(encode, count)
bits = cell(1, count);
if count == 1
    bits{1} = int8(encode.RateMatchedBits(:));
else
    if ~isfield(encode, "Codewords") || numel(encode.Codewords) ~= count
        error("sixgr:pdsch:PDSCHTransmitter:DLSCHEncodeContractMismatch", ...
            "Explicit multi-codeword encoder output is incomplete.");
    end
    for idx = 1:count
        bits{idx} = int8(encode.Codewords{idx}.RateMatchedBits(:));
    end
end
end

function [values, trace, nPorts, mode] = localApplyPrecoder( ...
        bundle, layers, prb, symbol, domain, contract, referenceConfig)
nPorts = double(referenceConfig.NPhysicalTxAntennas);
if isempty(bundle)
    if nPorts ~= contract.NumLayers
        error("sixgr:pdsch:PDSCHTransmitter:MissingPrecoderBundle", ...
            "Without a PDSCHPrecoderBundle, NPhysicalTxAntennas must " + ...
            "equal NumLayers for explicit identity mapping.");
    end
    values = layers;
    trace = localIdentityTrace(prb, symbol, domain, contract.NumLayers);
    mode = "explicit_identity_no_bundle";
    return;
end
if bundle.NLayerPorts ~= contract.NumLayers ...
        || bundle.NPhysicalTxAntennas ~= nPorts
    error("sixgr:pdsch:PDSCHTransmitter:PrecoderDimensionMismatch", ...
        "Precoder bundle dimensions do not match rank/physical-port configuration.");
end
[values, trace] = bundle.apply(layers, prb, symbol, "Domain", domain);
mode = bundle.Mode;
end

function [portSymbols, unionIndices, trace] = localReferencePortSymbols( ...
        indexCells, symbolCells, domain, bundle, carrier, contract, referenceConfig)
if ~iscell(indexCells) || ~isrow(indexCells) ...
        || numel(indexCells) ~= contract.NumLayers
    error("sixgr:pdsch:PDSCHTransmitter:ReferencePortCountMismatch", ...
        "%s index cells must contain one stream per layer port.", upper(domain));
end
if ~iscell(symbolCells) || ~isrow(symbolCells) ...
        || numel(symbolCells) ~= contract.NumLayers
    error("sixgr:pdsch:PDSCHTransmitter:ReferencePortCountMismatch", ...
        "%s symbol cells must contain one stream per layer port.", upper(domain));
end
planeSize = carrier.NSizeGrid * 12 * carrier.SymbolsPerSlot;
unionIndices = unique([indexCells{:}], "sorted");
if any(unionIndices < 0 | unionIndices >= planeSize)
    error("sixgr:pdsch:PDSCHTransmitter:ReferenceIndexOutsideGrid", ...
        "%s contains an index outside the zero-based carrier grid.", upper(domain));
end
if isempty(unionIndices)
    nPorts = double(referenceConfig.NPhysicalTxAntennas);
    portSymbols = complex(zeros(nPorts, 0));
    trace = table();
    return;
end
logicalSymbols = complex(zeros(contract.NumLayers, numel(unionIndices)));
for layer = 1:contract.NumLayers
    indices = double(indexCells{layer}(:));
    symbols = symbolCells{layer};
    if ~(isnumeric(symbols) && isvector(symbols) ...
            && numel(symbols) == numel(indices) ...
            && all(isfinite(real(symbols(:)))) && all(isfinite(imag(symbols(:)))))
        error("sixgr:pdsch:PDSCHTransmitter:ReferenceSymbolCountMismatch", ...
            "%s symbols for layer port %d do not match its indices.", ...
            upper(domain), layer - 1);
    end
    [present, positions] = ismember(indices, unionIndices);
    if any(~present)
        error("sixgr:pdsch:PDSCHTransmitter:ReferenceIndexMismatch", ...
            "Unable to resolve %s indices for layer port %d.", ...
            upper(domain), layer - 1);
    end
    logicalSymbols(layer, positions) = complex(double(symbols(:)));
end
[prb, symbol] = localResourceCoordinates(unionIndices, carrier);
[portSymbols, trace] = localApplyPrecoder(bundle, logicalSymbols, ...
    prb, symbol, domain, contract, referenceConfig);
end

function grid = localMapPortSymbols(grid, indices, values)
if isempty(indices)
    return;
end
if size(values, 2) ~= numel(indices) || size(values, 1) ~= size(grid, 3)
    error("sixgr:pdsch:PDSCHTransmitter:GridMappingShapeMismatch", ...
        "Port-symbol shape does not match grid indices/ports.");
end
for port = 1:size(grid, 3)
    plane = grid(:,:,port);
    if any(plane(indices + 1) ~= 0)
        error("sixgr:pdsch:PDSCHTransmitter:ResourceCollision", ...
            "Strict grid mapping detected a data/reference collision.");
    end
    plane(indices + 1) = values(port, :).';
    grid(:,:,port) = plane;
end
end

function [prb, symbol] = localResourceCoordinates(indices, carrier)
K = carrier.NSizeGrid * 12;
indices = double(indices(:).');
subcarrier = mod(indices, K);
symbol = floor(indices / K);
prb = floor(subcarrier / 12);
if any(symbol < 0 | symbol >= carrier.SymbolsPerSlot)
    error("sixgr:pdsch:PDSCHTransmitter:ResourceIndexOutsideGrid", ...
        "A resource-plan index lies outside the carrier grid.");
end
end

function trace = localIdentityTrace(prb, symbol, domain, rank)
count = numel(prb);
resourceIndex = (0:count-1).';
PRB = prb(:);
Symbol = symbol(:);
PRG = zeros(count,1);
SymbolGroup = zeros(count,1);
Domain = repmat(string(domain),count,1);
Operation = repmat("apply",count,1);
digest = "identity_rank_" + string(rank);
ResolvedMatrixDigest = repmat(digest,count,1);
AppliedMatrixDigest = ResolvedMatrixDigest;
trace = table(resourceIndex,PRB,Symbol,PRG,SymbolGroup,Domain, ...
    Operation,ResolvedMatrixDigest,AppliedMatrixDigest, ...
    'VariableNames', {'ResourceIndex','PRB','Symbol','PRG','SymbolGroup', ...
    'Domain','Operation','ResolvedMatrixDigest','AppliedMatrixDigest'});
end

function values = localNumericPerCodeword(raw, count, name)
values = double(raw(:).');
if numel(values) ~= count || any(~isfinite(values))
    error("sixgr:pdsch:PDSCHTransmitter:CodewordParameterMismatch", ...
        "%s must contain one finite value per codeword.", name);
end
end

function values = localStringPerCodeword(raw, count, name)
if iscell(raw)
    values = string(raw);
else
    values = string(raw);
end
values = reshape(values,1,[]);
if numel(values) ~= count || any(strlength(strtrim(values)) == 0)
    error("sixgr:pdsch:PDSCHTransmitter:CodewordParameterMismatch", ...
        "%s must contain one nonempty value per codeword.", name);
end
end

function qm = localQm(modulation)
switch upper(erase(string(modulation)," "))
    case "QPSK", qm = 2;
    case "16QAM", qm = 4;
    case "64QAM", qm = 6;
    case "256QAM", qm = 8;
    case "1024QAM", qm = 10;
    otherwise
        error("sixgr:pdsch:PDSCHTransmitter:UnsupportedModulation", ...
            "Unsupported PDSCH modulation '%s'.", modulation);
end
end

function values = localPerCodewordOptional(raw, count, name)
if isempty(raw)
    values = repmat({[]},1,count);
    return;
end
raw = double(raw(:).');
if isscalar(raw)
    raw = repmat(raw,1,count);
end
if numel(raw) ~= count || any(~isfinite(raw)) ...
        || any(raw <= 0 | raw ~= fix(raw))
    error("sixgr:pdsch:PDSCHTransmitter:CodewordParameterMismatch", ...
        "%s must be empty or contain one positive integer per codeword.", name);
end
values = num2cell(raw);
end

function value = localUnwrapOne(cells)
if numel(cells) == 1
    value = cells{1};
else
    value = cells;
end
end
