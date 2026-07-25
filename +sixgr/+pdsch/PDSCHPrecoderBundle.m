classdef PDSCHPrecoderBundle
    %PDSCHPRECODERBUNDLE Immutable frequency-selective PDSCH precoder.
    %
    % Canonical matrix orientation:
    %   W: [NPhysicalTxAntennas, NLayerPorts, NPRG, NSymbolGroups]
    %
    % All PRB and OFDM-symbol indices exposed by this object are zero based.
    % The object never resolves a scalar PMI into a matrix and never silently
    % renormalizes an explicit matrix.

    properties (SetAccess = immutable)
        W
        Mode (1,1) string
        NPhysicalTxAntennas (1,1) double
        NLayerPorts (1,1) double
        NPRG (1,1) double
        NSymbolGroups (1,1) double
        PRGSize (1,1) double
        PRBSet (1,:) double
        ScheduledSymbols (1,:) double
        PRGIndexPerPRB (1,:) double
        SymbolGroupIndexPerSymbol (1,:) double
        PRGToPRBMap (1,:) cell
        MatrixSource (1,1) string
        CodebookIdentifier (1,1) string
        NormalizationConvention (1,1) string
        NormalizationTolerance (1,1) double
        MatrixDigestPerSlice (:,:) string
        PowerRelativeErrorPerSlice (:,:) double
        MatrixShape (1,4) double
        MatrixRank (1,1) double
        IndexBase (1,1) string
        ImmutableBundleDigest (1,1) string
    end

    methods
        function obj = PDSCHPrecoderBundle(spec)
            if ~isstruct(spec) || ~isscalar(spec)
                error("sixgr:pdsch:PDSCHPrecoderBundle:InvalidSpecification", ...
                    "PDSCH precoder specification must be a scalar struct.");
            end
            required = ["Mode","NPorts","NLayers","NPRG","NSymbolGroups", ...
                "PRGSize","PRBSet","ScheduledSymbols","SymbolGroupMap","W", ...
                "MatrixSource","CodebookIdentifier","NormalizationConvention"];
            missing = required(~isfield(spec, required));
            if ~isempty(missing)
                error("sixgr:pdsch:PDSCHPrecoderBundle:IncompleteSpecification", ...
                    "PDSCH precoder specification is missing: %s.", ...
                    strjoin(cellstr(missing), ", "));
            end

            mode = lower(strtrim(string(spec.Mode)));
            supportedModes = ["siso_identity","wideband_codebook", ...
                "wideband_noncodebook","wideband_fixed_matrix", ...
                "prg_codebook","prg_noncodebook","prb_explicit", ...
                "prg_symbol_selective"];
            if contains(mode, "scalar_pmi")
                error("sixgr:pdsch:PDSCHPrecoderBundle:ScalarPMINotPrecoderBundle", ...
                    "A scalar PMI is not an applied PDSCH precoder matrix bundle.");
            end
            if ~any(mode == supportedModes)
                error("sixgr:pdsch:PDSCHPrecoderBundle:UnsupportedPrecoderMode", ...
                    "Unsupported PDSCH precoder mode '%s'.", mode);
            end

            nPorts = localPositiveInteger(spec.NPorts, "InvalidPortCount");
            nLayers = localPositiveInteger(spec.NLayers, "InvalidLayerCount");
            nPRG = localPositiveInteger(spec.NPRG, "InvalidPRGCount");
            nSymbolGroups = localPositiveInteger( ...
                spec.NSymbolGroups, "InvalidSymbolGroupCount");
            if nPorts < nLayers
                error("sixgr:pdsch:PDSCHPrecoderBundle:TooFewPortsForLayers", ...
                    "NPhysicalTxAntennas=%d cannot carry NLayerPorts=%d.", ...
                    nPorts, nLayers);
            end

            prbSet = localIndexVector(spec.PRBSet, "InvalidPRBSet");
            scheduledSymbols = localIndexVector( ...
                spec.ScheduledSymbols, "InvalidScheduledSymbols");
            if numel(unique(prbSet)) ~= numel(prbSet)
                error("sixgr:pdsch:PDSCHPrecoderBundle:DuplicatePRB", ...
                    "PRBSet must not contain duplicate zero-based PRB indices.");
            end
            if numel(unique(scheduledSymbols)) ~= numel(scheduledSymbols)
                error("sixgr:pdsch:PDSCHPrecoderBundle:DuplicateSymbol", ...
                    "ScheduledSymbols must not contain duplicate indices.");
            end

            prgSize = double(spec.PRGSize);
            isWideband = startsWith(mode, "wideband") || mode == "siso_identity";
            if isWideband
                if ~(isscalar(prgSize) && isfinite(prgSize) && prgSize == 0)
                    error("sixgr:pdsch:PDSCHPrecoderBundle:InvalidPRGSize", ...
                        "Wideband and SISO modes require PRGSize=0.");
                end
                requiredPRGPages = 1;
                prgIndexPerPRB = zeros(1, numel(prbSet));
            else
                if ~(isscalar(prgSize) && isfinite(prgSize) ...
                        && prgSize == fix(prgSize) && prgSize >= 1)
                    error("sixgr:pdsch:PDSCHPrecoderBundle:InvalidPRGSize", ...
                        "Frequency-selective modes require a positive integer PRGSize.");
                end
                requiredPRGPages = ceil(numel(prbSet) / prgSize);
                prgIndexPerPRB = floor((0:numel(prbSet)-1) / prgSize);
            end
            if nPRG < requiredPRGPages
                error("sixgr:pdsch:PDSCHPrecoderBundle:IncompletePRGCoverage", ...
                    "NPRG=%d leaves scheduled PRBs uncovered; %d pages are required.", ...
                    nPRG, requiredPRGPages);
            elseif nPRG > requiredPRGPages
                error("sixgr:pdsch:PDSCHPrecoderBundle:ExcessPRGPages", ...
                    "NPRG=%d exceeds the %d pages selected by PRB coverage.", ...
                    nPRG, requiredPRGPages);
            end

            symbolGroupMap = double(spec.SymbolGroupMap(:).');
            if numel(symbolGroupMap) ~= numel(scheduledSymbols) ...
                    || any(~isfinite(symbolGroupMap)) ...
                    || any(symbolGroupMap ~= fix(symbolGroupMap)) ...
                    || any(symbolGroupMap < 0) ...
                    || any(symbolGroupMap >= nSymbolGroups) ...
                    || ~isequal(unique(symbolGroupMap, "sorted"), 0:nSymbolGroups-1)
                error("sixgr:pdsch:PDSCHPrecoderBundle:IncompleteSymbolGroupCoverage", ...
                    ["SymbolGroupMap must select every group 0:%d exactly over " ...
                    "all scheduled symbols."], nSymbolGroups - 1);
            end

            W = spec.W;
            if isscalar(W) && (nPorts ~= 1 || nLayers ~= 1 ...
                    || nPRG ~= 1 || nSymbolGroups ~= 1)
                error("sixgr:pdsch:PDSCHPrecoderBundle:ScalarPMINotPrecoderBundle", ...
                    "A scalar cannot represent the requested four-dimensional matrix bundle.");
            end
            if ~(isnumeric(W) && all(isfinite(real(W(:)))) ...
                    && all(isfinite(imag(W(:)))))
                error("sixgr:pdsch:PDSCHPrecoderBundle:InvalidPrecoderMatrix", ...
                    "PDSCH precoder matrices must contain finite numeric values.");
            end
            actualShape = [size(W,1), size(W,2), size(W,3), size(W,4)];
            if actualShape(1) ~= nPorts
                error("sixgr:pdsch:PDSCHPrecoderBundle:PrecoderPortDimensionMismatch", ...
                    "Matrix port dimension %d does not match NPorts=%d.", ...
                    actualShape(1), nPorts);
            end
            if actualShape(2) ~= nLayers
                error("sixgr:pdsch:PDSCHPrecoderBundle:PrecoderLayerDimensionMismatch", ...
                    "Matrix layer dimension %d does not match NLayers=%d.", ...
                    actualShape(2), nLayers);
            end
            if actualShape(3) < nPRG
                error("sixgr:pdsch:PDSCHPrecoderBundle:IncompletePRGCoverage", ...
                    "Matrix contains %d PRG pages but %d are required.", ...
                    actualShape(3), nPRG);
            elseif actualShape(3) > nPRG
                error("sixgr:pdsch:PDSCHPrecoderBundle:ExcessPRGPages", ...
                    "Matrix contains %d PRG pages but only %d are selected.", ...
                    actualShape(3), nPRG);
            end
            if actualShape(4) < nSymbolGroups
                error("sixgr:pdsch:PDSCHPrecoderBundle:IncompleteSymbolGroupCoverage", ...
                    "Matrix contains %d symbol-group pages but %d are required.", ...
                    actualShape(4), nSymbolGroups);
            elseif actualShape(4) > nSymbolGroups
                error("sixgr:pdsch:PDSCHPrecoderBundle:ExcessSymbolGroupPages", ...
                    "Matrix contains %d symbol-group pages but only %d are selected.", ...
                    actualShape(4), nSymbolGroups);
            end
            W = reshape(complex(double(W)), [nPorts,nLayers,nPRG,nSymbolGroups]);

            if isfield(spec, "PMI") && isfield(spec, "MatrixPMI") ...
                    && ~isempty(spec.PMI) && ~isempty(spec.MatrixPMI) ...
                    && ~isequal(spec.PMI, spec.MatrixPMI)
                error("sixgr:pdsch:PDSCHPrecoderBundle:StalePrecoderPMIContext", ...
                    "Configured PMI and resolved-matrix PMI identify different states.");
            end

            matrixSource = string(spec.MatrixSource);
            codebookIdentifier = string(spec.CodebookIdentifier);
            if strlength(strtrim(matrixSource)) == 0
                error("sixgr:pdsch:PDSCHPrecoderBundle:MissingMatrixSource", ...
                    "MatrixSource must identify the resolved matrix owner.");
            end
            if contains(mode, "codebook") && ~contains(mode, "noncodebook") ...
                    && strlength(strtrim(codebookIdentifier)) == 0
                error("sixgr:pdsch:PDSCHPrecoderBundle:MissingCodebookIdentifier", ...
                    "Codebook modes require an explicit CodebookIdentifier.");
            end

            normalization = lower(strtrim(string(spec.NormalizationConvention)));
            supportedNormalization = ["semi_unitary","unit_frobenius", ...
                "explicit_no_normalization"];
            if ~any(normalization == supportedNormalization)
                error("sixgr:pdsch:PDSCHPrecoderBundle:UnsupportedNormalization", ...
                    "Unsupported normalization convention '%s'.", normalization);
            end
            tolerance = 1e-12;
            if isfield(spec, "NormalizationTolerance")
                tolerance = double(spec.NormalizationTolerance);
            end
            if ~(isscalar(tolerance) && isfinite(tolerance) && tolerance >= 0)
                error("sixgr:pdsch:PDSCHPrecoderBundle:InvalidNormalizationTolerance", ...
                    "NormalizationTolerance must be a finite nonnegative scalar.");
            end

            digests = strings(nPRG, nSymbolGroups);
            powerErrors = zeros(nPRG, nSymbolGroups);
            for prg = 1:nPRG
                for symbolGroup = 1:nSymbolGroups
                    page = W(:,:,prg,symbolGroup);
                    if rank(page, max(size(page)) * eps(norm(page))) < nLayers
                        error("sixgr:pdsch:PDSCHPrecoderBundle:RankDeficientPrecoder", ...
                            "Precoder slice PRG=%d symbol-group=%d is rank deficient.", ...
                            prg - 1, symbolGroup - 1);
                    end
                    gramError = norm(page' * page - eye(nLayers), "fro") ...
                        / max(1, sqrt(nLayers));
                    powerErrors(prg, symbolGroup) = gramError;
                    if normalization == "semi_unitary" && gramError > tolerance
                        error("sixgr:pdsch:PDSCHPrecoderBundle:PrecoderNormalizationMismatch", ...
                            ["Precoder slice PRG=%d symbol-group=%d violates " ...
                            "semi-unitary normalization by %.6g (tolerance %.6g)."], ...
                            prg - 1, symbolGroup - 1, gramError, tolerance);
                    elseif normalization == "unit_frobenius" ...
                            && abs(norm(page, "fro") - 1) > tolerance
                        error("sixgr:pdsch:PDSCHPrecoderBundle:PrecoderNormalizationMismatch", ...
                            ["Precoder slice PRG=%d symbol-group=%d violates " ...
                            "unit-Frobenius normalization."], prg - 1, symbolGroup - 1);
                    end
                    digests(prg, symbolGroup) = localMatrixDigest(page);
                end
            end

            prgToPRB = cell(1, nPRG);
            for prg = 0:(nPRG - 1)
                prgToPRB{prg + 1} = prbSet(prgIndexPerPRB == prg);
            end

            obj.W = W;
            obj.Mode = mode;
            obj.NPhysicalTxAntennas = nPorts;
            obj.NLayerPorts = nLayers;
            obj.NPRG = nPRG;
            obj.NSymbolGroups = nSymbolGroups;
            obj.PRGSize = prgSize;
            obj.PRBSet = prbSet;
            obj.ScheduledSymbols = scheduledSymbols;
            obj.PRGIndexPerPRB = prgIndexPerPRB;
            obj.SymbolGroupIndexPerSymbol = symbolGroupMap;
            obj.PRGToPRBMap = prgToPRB;
            obj.MatrixSource = matrixSource;
            obj.CodebookIdentifier = codebookIdentifier;
            obj.NormalizationConvention = normalization;
            obj.NormalizationTolerance = tolerance;
            obj.MatrixDigestPerSlice = digests;
            obj.PowerRelativeErrorPerSlice = powerErrors;
            obj.MatrixShape = [nPorts,nLayers,nPRG,nSymbolGroups];
            obj.MatrixRank = 4;
            obj.IndexBase = "zero_based";
            obj.ImmutableBundleDigest = localBundleDigest( ...
                mode, nPorts, nLayers, nPRG, nSymbolGroups, prgSize, ...
                prbSet, scheduledSymbols, symbolGroupMap, matrixSource, ...
                codebookIdentifier, normalization, digests);
        end

        function [portSymbols, trace] = apply(obj, layerSymbols, prb, symbol, varargin)
            %APPLY Apply the resolved slice to data or reference layer ports.
            domain = localDomain(varargin);
            values = localResourceMatrix(layerSymbols, obj.NLayerPorts, ...
                "LayerDimensionMismatch");
            resourceCount = size(values, 2);
            prb = localExpandResourceIndex(prb, resourceCount, "PRB");
            symbol = localExpandResourceIndex(symbol, resourceCount, "Symbol");
            portSymbols = complex(zeros(obj.NPhysicalTxAntennas, resourceCount));
            [prg, symbolGroup, digest] = localSelections(obj, prb, symbol);
            for idx = 1:resourceCount
                page = obj.W(:,:,prg(idx)+1,symbolGroup(idx)+1);
                portSymbols(:, idx) = page * values(:, idx);
            end
            trace = localTrace(prb, symbol, prg, symbolGroup, digest, domain, "apply");
        end

        function [layerSymbols, trace] = deapply(obj, portSymbols, prb, symbol, varargin)
            %DEAPPLY Recover layer streams from noiseless precoded port values.
            domain = localDomain(varargin);
            values = localResourceMatrix(portSymbols, ...
                obj.NPhysicalTxAntennas, "PortDimensionMismatch");
            resourceCount = size(values, 2);
            prb = localExpandResourceIndex(prb, resourceCount, "PRB");
            symbol = localExpandResourceIndex(symbol, resourceCount, "Symbol");
            layerSymbols = complex(zeros(obj.NLayerPorts, resourceCount));
            [prg, symbolGroup, digest] = localSelections(obj, prb, symbol);
            for idx = 1:resourceCount
                page = obj.W(:,:,prg(idx)+1,symbolGroup(idx)+1);
                layerSymbols(:, idx) = page \ values(:, idx);
            end
            trace = localTrace(prb, symbol, prg, symbolGroup, digest, domain, "deapply");
        end

        function [page, prg, symbolGroup, digest] = slice(obj, prb, symbol)
            %SLICE Return the one resolved matrix for a scheduled resource.
            [prgValues, symbolGroupValues, digestValues] = ...
                localSelections(obj, double(prb), double(symbol));
            if numel(prgValues) ~= 1
                error("sixgr:pdsch:PDSCHPrecoderBundle:SliceRequiresScalarResource", ...
                    "slice requires one scalar PRB and one scalar symbol.");
            end
            prg = prgValues(1);
            symbolGroup = symbolGroupValues(1);
            digest = digestValues(1);
            page = obj.W(:,:,prg+1,symbolGroup+1);
        end
    end
end

function value = localPositiveInteger(raw, suffix)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && value >= 1)
    error("sixgr:pdsch:PDSCHPrecoderBundle:" + suffix, ...
        "Expected a positive integer; received %s.", mat2str(raw));
end
end

function values = localIndexVector(raw, suffix)
values = double(raw(:).');
if isempty(values) || any(~isfinite(values)) || any(values ~= fix(values)) ...
        || any(values < 0)
    error("sixgr:pdsch:PDSCHPrecoderBundle:" + suffix, ...
        "Expected a nonempty zero-based nonnegative integer vector.");
end
end

function digest = localMatrixDigest(page)
shapeBytes = typecast(uint64([size(page,1),size(page,2)]), "uint8");
valueBytes = typecast([real(double(page(:))); imag(double(page(:)))], "uint8");
digest = string(sixgr.util.sha256Hex([shapeBytes(:); valueBytes(:)]));
end

function digest = localBundleDigest(mode, nPorts, nLayers, nPRG, ...
        nSymbolGroups, prgSize, prbSet, scheduledSymbols, symbolGroupMap, ...
        matrixSource, codebookIdentifier, normalization, matrixDigests)
payload = struct( ...
    "Mode", char(mode), ...
    "NPhysicalTxAntennas", double(nPorts), ...
    "NLayerPorts", double(nLayers), ...
    "NPRG", double(nPRG), ...
    "NSymbolGroups", double(nSymbolGroups), ...
    "PRGSize", double(prgSize), ...
    "PRBSet", double(prbSet), ...
    "ScheduledSymbols", double(scheduledSymbols), ...
    "SymbolGroupMap", double(symbolGroupMap), ...
    "MatrixSource", char(matrixSource), ...
    "CodebookIdentifier", char(codebookIdentifier), ...
    "NormalizationConvention", char(normalization), ...
    "MatrixDigestShape", double(size(matrixDigests)), ...
    "MatrixDigestPerSlice", {cellstr(matrixDigests(:).')});
bytes = uint8(unicode2native(jsonencode(orderfields(payload)), "UTF-8"));
digest = string(sixgr.util.sha256Hex(bytes));
end

function domain = localDomain(options)
domain = "data";
if mod(numel(options), 2) ~= 0
    error("sixgr:pdsch:PDSCHPrecoderBundle:BadNameValue", ...
        "Application options must be supplied as name-value pairs.");
end
for idx = 1:2:numel(options)
    name = lower(strtrim(string(options{idx})));
    if name ~= "domain"
        error("sixgr:pdsch:PDSCHPrecoderBundle:UnknownOption", ...
            "Unknown precoder application option '%s'.", name);
    end
    domain = lower(strtrim(string(options{idx + 1})));
end
if ~any(domain == ["data","dmrs","ptrs","effective_channel"])
    error("sixgr:pdsch:PDSCHPrecoderBundle:UnsupportedDomain", ...
        "Precoder application domain '%s' is unsupported.", domain);
end
end

function values = localResourceMatrix(raw, expectedRows, suffix)
if ~(isnumeric(raw) && all(isfinite(real(raw(:)))) ...
        && all(isfinite(imag(raw(:)))))
    error("sixgr:pdsch:PDSCHPrecoderBundle:InvalidResourceValues", ...
        "Precoder input values must be finite numeric values.");
end
if isvector(raw) && expectedRows == 1
    values = reshape(complex(double(raw)), 1, []);
else
    values = complex(double(raw));
end
if ~ismatrix(values) || size(values, 1) ~= expectedRows
    error("sixgr:pdsch:PDSCHPrecoderBundle:" + suffix, ...
        "Precoder input must have exactly %d rows.", expectedRows);
end
end

function values = localExpandResourceIndex(raw, count, label)
values = double(raw(:).');
if isscalar(values)
    values = repmat(values, 1, count);
end
if numel(values) ~= count || any(~isfinite(values)) ...
        || any(values ~= fix(values)) || any(values < 0)
    error("sixgr:pdsch:PDSCHPrecoderBundle:Invalid" + label + "Vector", ...
        "%s indices must be zero-based integers, scalar or one per resource.", label);
end
end

function [prg, symbolGroup, digest] = localSelections(obj, prb, symbol)
if numel(prb) ~= numel(symbol)
    error("sixgr:pdsch:PDSCHPrecoderBundle:ResourceIndexCountMismatch", ...
        "PRB and symbol index vectors must have the same length.");
end
prg = zeros(size(prb));
symbolGroup = zeros(size(symbol));
digest = strings(numel(prb), 1);
for idx = 1:numel(prb)
    prbPosition = find(obj.PRBSet == prb(idx), 1);
    if isempty(prbPosition)
        error("sixgr:pdsch:PDSCHPrecoderBundle:UnscheduledPRB", ...
            "PRB %d is not covered by this PDSCH precoder bundle.", prb(idx));
    end
    symbolPosition = find(obj.ScheduledSymbols == symbol(idx), 1);
    if isempty(symbolPosition)
        error("sixgr:pdsch:PDSCHPrecoderBundle:UnscheduledSymbol", ...
            "Symbol %d is not covered by this PDSCH precoder bundle.", symbol(idx));
    end
    prg(idx) = obj.PRGIndexPerPRB(prbPosition);
    symbolGroup(idx) = obj.SymbolGroupIndexPerSymbol(symbolPosition);
    digest(idx) = obj.MatrixDigestPerSlice(prg(idx)+1, symbolGroup(idx)+1);
end
end

function trace = localTrace(prb, symbol, prg, symbolGroup, digest, domain, operation)
resourceIndex = (0:numel(prb)-1).';
PRB = prb(:);
Symbol = symbol(:);
PRG = prg(:);
SymbolGroup = symbolGroup(:);
Domain = repmat(domain, numel(prb), 1);
Operation = repmat(operation, numel(prb), 1);
ResolvedMatrixDigest = digest(:);
AppliedMatrixDigest = digest(:);
trace = table(resourceIndex, PRB, Symbol, PRG, SymbolGroup, Domain, ...
    Operation, ResolvedMatrixDigest, AppliedMatrixDigest, ...
    'VariableNames', {'ResourceIndex','PRB','Symbol','PRG','SymbolGroup', ...
    'Domain','Operation','ResolvedMatrixDigest','AppliedMatrixDigest'});
end
