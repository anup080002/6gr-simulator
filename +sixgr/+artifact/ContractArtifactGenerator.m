classdef ContractArtifactGenerator
    %CONTRACTARTIFACTGENERATOR Publish contract artifacts from runtime evidence.
    %
    % Publication is fail closed and atomic at the components/ tree.  The
    % generator never reads legacy results or artifacts as an input source.

    methods (Static)
        function result = generate(runFolder, evidence, varargin)
            arguments
                runFolder {mustBeTextScalar}
                evidence (1,1) sixgr.artifact.EvidenceRegistry
            end
            arguments (Repeating)
                varargin
            end

            options = localParseOptions(varargin{:});
            runFolder = char(string(runFolder));
            if ~isfolder(runFolder)
                mkdir(runFolder);
            end
            catalog = options.Catalog;
            if isempty(catalog)
                catalog = sixgr.artifact.ContractCatalog.load();
            end
            catalog = localSelectCatalog(catalog, options);
            if isempty(catalog)
                error("sixgr:artifact:EmptyCatalogSelection", ...
                    "No artifact contracts match the requested profile, mode and domains.");
            end

            stageRoot = fullfile(runFolder, ".artifact_stage_" + localUUID());
            stageComponents = fullfile(stageRoot, options.PublishRoot);
            mkdir(stageComponents);
            stageCleanup = onCleanup(@() localDeleteOwnedDirectory(stageRoot, runFolder)); %#ok<NASGU>

            auditRows = repmat(localEmptyAuditRow(), height(catalog), 1);
            validatedTables = containers.Map('KeyType', 'char', 'ValueType', 'any');
            tableProvenance = containers.Map('KeyType', 'char', 'ValueType', 'char');
            tableHashes = containers.Map('KeyType', 'char', 'ValueType', 'char');

            csvIndexes = find(catalog.ArtifactType == "CSV");
            for cursor = 1:numel(csvIndexes)
                index = csvIndexes(cursor);
                contract = catalog(index, :);
                auditRows(index) = localGenerateCSV(contract, evidence, ...
                    stageComponents, validatedTables, tableProvenance, ...
                    tableHashes, options);
            end

            pngIndexes = find(catalog.ArtifactType == "PNG");
            for cursor = 1:numel(pngIndexes)
                index = pngIndexes(cursor);
                contract = catalog(index, :);
                auditRows(index) = localGeneratePNG(contract, evidence, ...
                    stageComponents, validatedTables, tableProvenance, tableHashes);
            end

            audit = struct2table(auditRows, 'AsArray', true);
            audit = sortrows(audit, ["Domain", "Profile", "ArtifactType", "FileName"]);
            auditDir = fullfile(runFolder, "artifact_generation");
            if ~isfolder(auditDir)
                mkdir(auditDir);
            end
            localAtomicWriteTable(fullfile(auditDir, "contract_catalog_snapshot.csv"), catalog);
            localAtomicWriteTable(fullfile(auditDir, "artifact_generation_results.csv"), audit);
            failures = audit(audit.Status ~= "PASS", :);
            localAtomicWriteTable(fullfile(auditDir, "artifact_generation_failures.csv"), failures);

            requiredFailure = audit.Required & audit.Status ~= "PASS";
            if options.FailOnMissingRequired && any(requiredFailure)
                first = audit(find(requiredFailure, 1, "first"), :);
                error("sixgr:artifact:RequiredArtifactGenerationFailed", ...
                    ['Artifact generation failed closed for %d required artifacts. ' ...
                     'First failure: %s (%s). Audit: %s'], ...
                    nnz(requiredFailure), first.ContractID, first.Message, ...
                    fullfile(auditDir, "artifact_generation_failures.csv"));
            end

            publishedRoot = fullfile(runFolder, options.PublishRoot);
            localPublishComponents(stageComponents, publishedRoot, runFolder);
            result = struct();
            result.Ok = ~any(requiredFailure);
            result.CatalogCount = height(catalog);
            result.CSVCount = nnz(audit.ArtifactType == "CSV" & audit.Status == "PASS");
            result.PNGCount = nnz(audit.ArtifactType == "PNG" & audit.Status == "PASS");
            result.FailureCount = height(failures);
            result.RequiredFailureCount = nnz(requiredFailure);
            result.ComponentsRoot = string(publishedRoot);
            result.Audit = audit;
        end
    end
end

function options = localParseOptions(varargin)
parser = inputParser();
parser.addParameter("Catalog", table(), @(x) istable(x));
parser.addParameter("Profiles", "base", @(x) ischar(x) || isstring(x));
parser.addParameter("Domains", "all", @(x) ischar(x) || isstring(x));
parser.addParameter("Mode", "ALL", @(x) ischar(x) || isstring(x));
parser.addParameter("PublishRoot", "components", @(x) ischar(x) || isstring(x));
parser.addParameter("FailOnMissingRequired", true, @(x) islogical(x) && isscalar(x));
parser.addParameter("TruthOnly", true, @(x) islogical(x) && isscalar(x));
parser.addParameter("ExpectedIdentity", struct(), @(x) isstruct(x) && isscalar(x));
parser.addParameter("RequireIdentityColumns", false, @(x) islogical(x) && isscalar(x));
parser.addParameter("RequireRadioIdentityColumns", false, @(x) islogical(x) && isscalar(x));
parser.parse(varargin{:});
options = parser.Results;
options.Profiles = lower(string(options.Profiles));
options.Domains = lower(string(options.Domains));
options.Mode = upper(string(options.Mode));
options.PublishRoot = string(options.PublishRoot);
if ~isscalar(options.PublishRoot) || strlength(strtrim(options.PublishRoot)) == 0 || ...
        contains(options.PublishRoot, ["/", "\\"]) || options.PublishRoot == "." || ...
        options.PublishRoot == ".."
    error("sixgr:artifact:UnsafePublishRoot", ...
        "PublishRoot must be one non-empty directory name beneath the run root.");
end
end

function selected = localSelectCatalog(catalog, options)
required = ["ContractID", "Domain", "Component", "Profile", "Mode", ...
    "ArtifactType", "FileName", "OutputRelativePath", "Required", ...
    "MinimumRows", "RequiredColumns", "PrimaryKey", "SourceCSV", ...
    "MinimumWidth", "MinimumHeight", "MinimumAxes", "MinimumSeries", ...
    "MinimumFinitePoints", "ExpectedTitle", "ExpectedXLabel", "ExpectedYLabel"];
missing = setdiff(required, string(catalog.Properties.VariableNames));
if ~isempty(missing)
    error("sixgr:artifact:MalformedCatalog", ...
        "Normalized artifact catalog is missing columns: %s", strjoin(missing, ", "));
end
mask = true(height(catalog), 1);
if ~any(options.Profiles == "all")
    mask = mask & ismember(lower(catalog.Profile), options.Profiles);
end
if ~any(options.Domains == "all")
    mask = mask & ismember(lower(catalog.Domain), options.Domains);
end
if ~any(options.Mode == "ALL")
    mask = mask & (upper(catalog.Mode) == "ALL" | ...
        upper(catalog.Mode) == "BOTH" | ...
        ismember(upper(catalog.Mode), options.Mode));
end
selected = catalog(mask, :);
end

function audit = localGenerateCSV(contract, evidence, stageComponents, ...
        validatedTables, tableProvenance, tableHashes, options)
audit = localAuditFromContract(contract);
[found, value, provenance] = evidence.resolveTable( ...
    contract.Domain, contract.Profile, contract.FileName);
if ~found
    audit.Status = "MISSING";
    audit.Message = "No in-memory runtime table was registered.";
    return;
end
audit.Producer = provenance;
audit.SourceRows = height(value);
try
    localValidateTable(value, contract, provenance, options);
    outputPath = fullfile(stageComponents, contract.OutputRelativePath);
    localAtomicWriteTable(outputPath, value);
    audit.SHA256 = localFileSHA256(outputPath);
    audit.SourceSHA256 = audit.SHA256;
    audit.Status = "PASS";
    key = char(sixgr.artifact.ContractCatalog.evidenceKey( ...
        contract.Domain, contract.Profile, "CSV", contract.FileName));
    validatedTables(key) = value;
    tableProvenance(key) = char(provenance);
    tableHashes(key) = char(audit.SHA256);
catch ME
    audit.Status = "FAIL";
    audit.Message = string(ME.identifier) + ": " + string(ME.message);
end
end

function audit = localGeneratePNG(contract, evidence, stageComponents, ...
        validatedTables, tableProvenance, tableHashes)
audit = localAuditFromContract(contract);
[found, renderer, provenance] = evidence.resolveRenderer( ...
    contract.Domain, contract.Profile, contract.FileName);
if ~found
    audit.Status = "MISSING";
    audit.Message = "No explicit production PNG renderer was registered.";
    return;
end
audit.Producer = provenance;
try
    bundle = localResolveSourceTables(contract, validatedTables, ...
        tableProvenance, tableHashes);
    audit.SourceRows = sum(cellfun(@height, bundle.Tables));
    audit.SourceSHA256 = localAggregateSourceHash(bundle);
    figureHandle = renderer(bundle, contract);
    figureCleanup = onCleanup(@() localCloseFigure(figureHandle)); %#ok<NASGU>
    localNormalizeFigureForDeterministicRaster(figureHandle, contract);
    metrics = localValidateFigure(figureHandle, contract);
    outputPath = fullfile(stageComponents, contract.OutputRelativePath);
    sixgr.util.ensureDir(outputPath);
    exportgraphics(figureHandle, outputPath, "Resolution", 150, ...
        "BackgroundColor", "white", "ContentType", "image");
    localCanonicalizePNG(outputPath);
    imageInfo = imfinfo(outputPath);
    if imageInfo.Width < contract.MinimumWidth || imageInfo.Height < contract.MinimumHeight
        error("sixgr:artifact:PNGDimensionsBelowContract", ...
            "Rendered PNG is %dx%d but contract requires at least %dx%d.", ...
            imageInfo.Width, imageInfo.Height, ...
            contract.MinimumWidth, contract.MinimumHeight);
    end
    audit.Width = imageInfo.Width;
    audit.Height = imageInfo.Height;
    audit.AxesCount = metrics.AxesCount;
    audit.SeriesCount = metrics.SeriesCount;
    audit.FinitePointCount = metrics.FinitePointCount;
    audit.SHA256 = localFileSHA256(outputPath);
    audit.Status = "PASS";
catch ME
    audit.Status = "FAIL";
    audit.Message = string(ME.identifier) + ": " + string(ME.message);
end

function localNormalizeFigureForDeterministicRaster(figureHandle, contract)
if ~(isscalar(figureHandle) && isgraphics(figureHandle, "figure"))
    error("sixgr:artifact:RendererDidNotReturnFigure", ...
        "The PNG renderer must return one MATLAB figure handle.");
end
width = max(640, ceil(double(contract.MinimumWidth)));
height = max(480, ceil(double(contract.MinimumHeight)));
set(figureHandle, "Visible", "off", "Color", "white", ...
    "Units", "pixels", "Position", [100 100 width height], ...
    "Renderer", "painters", "InvertHardcopy", "off");
drawnow;
end

function localCanonicalizePNG(pathValue)
% exportgraphics/imwrite may emit a variable PNG byte stream even when the
% decoded pixels are identical. Re-encode an explicit opaque RGB raster via
% Java ImageIO, which emits deterministic bytes without time-varying PNG
% ancillary chunks.
[pixels, colorMap, alpha] = imread(pathValue);
temporary = string(pathValue) + ".canonical." + localUUID() + ".png";
cleanup = onCleanup(@() localDeleteFile(temporary)); %#ok<NASGU>
if ~isempty(colorMap)
    pixels = uint8(round(255 * ind2rgb(pixels, colorMap)));
else
    pixels = localToUint8Raster(pixels);
end
if ismatrix(pixels)
    pixels = repmat(pixels, 1, 1, 3);
elseif size(pixels, 3) > 3
    pixels = pixels(:, :, 1:3);
end
if ~isempty(alpha)
    alphaUnit = localRasterToUnitDouble(alpha);
    if ismatrix(alphaUnit)
        alphaUnit = repmat(alphaUnit, 1, 1, 3);
    end
    pixels = uint8(round(double(pixels) .* alphaUnit + ...
        255 .* (1 - alphaUnit)));
end
[height, width, ~] = size(pixels);
bufferedImage = javaObject('java.awt.image.BufferedImage', width, height, 1); % TYPE_INT_RGB
packed = bitor(bitshift(uint32(pixels(:, :, 1)), 16), ...
    bitor(bitshift(uint32(pixels(:, :, 2)), 8), uint32(pixels(:, :, 3))));
packed = int32(reshape(packed.', [], 1));
bufferedImage.setRGB(0, 0, width, height, packed, 0, width);
written = javaMethod('write', 'javax.imageio.ImageIO', bufferedImage, 'png', ...
    javaObject('java.io.File', char(temporary)));
if ~written
    error("sixgr:artifact:PNGCanonicalizationFailed", ...
        "Java ImageIO did not provide a PNG writer for %s.", pathValue);
end
[ok, message] = movefile(temporary, pathValue, "f");
if ~ok
    error("sixgr:artifact:PNGCanonicalizationFailed", ...
        "Unable to atomically canonicalize PNG %s: %s", pathValue, message);
end
end

function pixels = localToUint8Raster(pixels)
if isa(pixels, "uint8")
    return;
elseif isa(pixels, "uint16")
    pixels = uint8(round(double(pixels) / 257));
elseif islogical(pixels)
    pixels = uint8(pixels) * 255;
else
    pixels = uint8(round(255 * min(max(double(pixels), 0), 1)));
end
end

function values = localRasterToUnitDouble(values)
if isa(values, "uint8")
    values = double(values) / 255;
elseif isa(values, "uint16")
    values = double(values) / 65535;
elseif islogical(values)
    values = double(values);
else
    values = min(max(double(values), 0), 1);
end
end
end

function localValidateTable(T, contract, provenance, options)
requiredColumns = localSplitList(contract.RequiredColumns);
missing = setdiff(requiredColumns, string(T.Properties.VariableNames), "stable");
if ~isempty(missing)
    error("sixgr:artifact:MissingRequiredColumns", ...
        "Table %s lacks required columns: %s", contract.FileName, strjoin(missing, ", "));
end
if height(T) < contract.MinimumRows
    error("sixgr:artifact:TooFewRows", ...
        "Table %s has %d rows; contract requires at least %d.", ...
        contract.FileName, height(T), contract.MinimumRows);
end
if height(T) > 1 && height(unique(T, "rows", "stable")) ~= height(T)
    error("sixgr:artifact:ExactDuplicateRows", ...
        "Table %s contains exact duplicate rows; canonical artifacts must be idempotent sets.", ...
        contract.FileName);
end
primaryKey = localSplitList(contract.PrimaryKey);
if ~isempty(primaryKey)
    missingKey = setdiff(primaryKey, string(T.Properties.VariableNames), "stable");
    if ~isempty(missingKey)
        error("sixgr:artifact:MissingPrimaryKeyColumns", ...
            "Table %s lacks primary-key columns: %s", ...
            contract.FileName, strjoin(missingKey, ", "));
    end
    keyTable = T(:, cellstr(primaryKey));
    if height(unique(keyTable, "rows", "stable")) ~= height(keyTable)
        error("sixgr:artifact:DuplicatePrimaryKey", ...
            "Table %s contains duplicate primary-key rows (%s).", ...
            contract.FileName, strjoin(primaryKey, ", "));
    end
end
if options.TruthOnly
    localRejectProxyEvidence(T, provenance, contract.FileName);
end
localRejectIncompleteOrFailedEvidence(T, contract);
if ~isempty(fieldnames(options.ExpectedIdentity)) || ...
        options.RequireIdentityColumns || options.RequireRadioIdentityColumns
    sixgr.artifact.validateEvidenceIdentity(T, options.ExpectedIdentity, ...
        contract.FileName, ...
        "RequireIdentityColumns", options.RequireIdentityColumns, ...
        "RequireRadioIdentityColumns", options.RequireRadioIdentityColumns);
end
end

function localRejectIncompleteOrFailedEvidence(T, contract)
% Structural presence is not scientific acceptance.  Required production
% artifacts must fail closed when their own row-level verdict says that the
% measurement was incomplete, unevaluated, unqualified, or failed.
if ~logical(contract.Required) || isempty(T)
    return;
end
names = string(T.Properties.VariableNames);
for name = ["Incomplete","IncompleteFlag","MissingEvidence", ...
        "PlaceholderFlag","FallbackFlag"]
    match = strcmpi(names, name);
    if any(match) && any(localLogicalValues(T{:, find(match, 1, "first")}))
        error("sixgr:artifact:IncompleteRuntimeEvidence", ...
            "Required artifact %s contains true %s row(s).", ...
            contract.FileName, name);
    end
end
for name = ["StrictOk","Pass","Passed","Ok","Success", ...
        "TruthQualified","StatisticallyQualified"]
    match = strcmpi(names, name);
    if any(match)
        values = localLogicalValues(T{:, find(match, 1, "first")});
        if numel(values) ~= height(T) || any(~values)
            error("sixgr:artifact:FailedRuntimeEvidence", ...
                "Required artifact %s contains false %s row(s).", ...
                contract.FileName, name);
        end
    end
end
for name = ["Status","QualificationStatus","PublicationStatus"]
    match = strcmpi(names, name);
    if ~any(match)
        continue;
    end
    values = upper(strtrim(string(T{:, find(match, 1, "first")})));
    badExact = ["FAIL","FAILED","ERROR","INCOMPLETE","NOT_EVALUATED", ...
        "MISSING","BLOCKED","UNAVAILABLE","NOT_REGISTERED", ...
        "MEASURED_NOT_QUALIFIED","NOT_QUALIFIED"];
    bad = ismissing(values) | strlength(values) == 0 | ...
        ismember(values, badExact) | contains(values, "NOT_QUALIFIED") | ...
        contains(values, "NOT_EVALUATED");
    if any(bad)
        first = find(bad, 1, "first");
        error("sixgr:artifact:NonPassingRuntimeStatus", ...
            "Required artifact %s contains non-passing %s='%s'.", ...
            contract.FileName, name, values(first));
    end
end
end

function values = localLogicalValues(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    token = lower(strtrim(string(raw(:))));
    values = ismember(token, ["true","1","yes","pass","passed","ok"]);
end
end

function localRejectProxyEvidence(T, provenance, fileName)
forbidden = "(?i)(^|[^a-z])(lut|logistic|fast_proxy|synthetic|fallback)([^a-z]|$)";
if ~isempty(regexp(char(provenance), forbidden, "once"))
    error("sixgr:artifact:ProxyEvidenceRejected", ...
        "Truth-only table %s has proxy/fallback producer provenance '%s'.", ...
        fileName, provenance);
end
semanticColumns = ["Source", "ExecutionBackend", "ApproximationMode", ...
    "E2EAirModel", "Notes"];
for name = semanticColumns
    match = strcmpi(string(T.Properties.VariableNames), name);
    if ~any(match)
        continue;
    end
    values = string(T{:, find(match, 1, "first")});
    for valueIndex = 1:numel(values)
        if ~isempty(regexp(char(values(valueIndex)), forbidden, "once"))
            error("sixgr:artifact:ProxyEvidenceRejected", ...
                "Truth-only table %s marks %s='%s'.", ...
                fileName, name, values(valueIndex));
        end
    end
end
end

function bundle = localResolveSourceTables(contract, validatedTables, ...
        tableProvenance, tableHashes)
sourceNames = localSplitList(contract.SourceCSV);
if isempty(sourceNames)
    error("sixgr:artifact:MissingPNGSourceContract", ...
        "PNG %s does not declare a source CSV.", contract.FileName);
end
bundle = struct();
bundle.Names = strings(numel(sourceNames), 1);
bundle.Tables = cell(numel(sourceNames), 1);
bundle.Provenance = strings(numel(sourceNames), 1);
bundle.SourceSHA256 = strings(numel(sourceNames), 1);
for index = 1:numel(sourceNames)
    [~, leaf, extension] = fileparts(char(sourceNames(index)));
    fileName = string(leaf) + string(extension);
    key = char(sixgr.artifact.ContractCatalog.evidenceKey( ...
        contract.Domain, contract.Profile, "CSV", fileName));
    if ~isKey(validatedTables, key)
        error("sixgr:artifact:PNGSourceEvidenceUnavailable", ...
            "PNG %s requires validated runtime source table %s.", ...
            contract.FileName, fileName);
    end
    bundle.Names(index) = fileName;
    bundle.Tables{index} = validatedTables(key);
    bundle.Provenance(index) = string(tableProvenance(key));
    bundle.SourceSHA256(index) = string(tableHashes(key));
end
end

function hash = localAggregateSourceHash(bundle)
[names, order] = sort(bundle.Names);
hashes = bundle.SourceSHA256(order);
payload = strjoin(names + "=" + hashes, newline);
hash = sixgr.util.sha256Hex(payload);
end

function metrics = localValidateFigure(fig, contract)
if isempty(fig) || ~ishghandle(fig, "figure")
    error("sixgr:artifact:RendererDidNotReturnFigure", ...
        "Renderer for %s must return one MATLAB figure handle.", contract.FileName);
end
set(fig, "Visible", "off", "Units", "pixels");
position = get(fig, "Position");
position(3) = max(position(3), max(1, contract.MinimumWidth));
position(4) = max(position(4), max(1, contract.MinimumHeight));
set(fig, "Position", position);
drawnow();

axesHandles = findall(fig, "Type", "axes");
metrics = struct("AxesCount", numel(axesHandles), ...
    "SeriesCount", 0, "FinitePointCount", 0);
titles = strings(0, 1);
xlabels = strings(0, 1);
ylabels = strings(0, 1);
dataTypes = ["line", "scatter", "image", "surface", "patch", ...
    "bar", "histogram", "stem", "area", "contour"];
for axesIndex = 1:numel(axesHandles)
    axesHandle = axesHandles(axesIndex);
    titles(end + 1, 1) = string(get(get(axesHandle, "Title"), "String")); %#ok<AGROW>
    xlabels(end + 1, 1) = string(get(get(axesHandle, "XLabel"), "String")); %#ok<AGROW>
    ylabels(end + 1, 1) = string(get(get(axesHandle, "YLabel"), "String")); %#ok<AGROW>
    children = findall(axesHandle);
    for childIndex = 1:numel(children)
        child = children(childIndex);
        type = lower(string(get(child, "Type")));
        if any(type == dataTypes)
            metrics.SeriesCount = metrics.SeriesCount + 1;
            metrics.FinitePointCount = metrics.FinitePointCount + localFinitePoints(child);
        end
    end
end
if metrics.AxesCount < contract.MinimumAxes || ...
        metrics.SeriesCount < contract.MinimumSeries || ...
        metrics.FinitePointCount < contract.MinimumFinitePoints
    error("sixgr:artifact:FigureContentBelowContract", ...
        ['Figure %s has axes/series/finite-points %d/%d/%d; ' ...
         'contract requires at least %d/%d/%d.'], ...
        contract.FileName, metrics.AxesCount, metrics.SeriesCount, ...
        metrics.FinitePointCount, contract.MinimumAxes, ...
        contract.MinimumSeries, contract.MinimumFinitePoints);
end
localRequireTextToken(strjoin(titles, " "), contract.ExpectedTitle, ...
    contract.FileName, "title");
localRequireTextToken(strjoin(xlabels, " "), contract.ExpectedXLabel, ...
    contract.FileName, "x-axis label");
localRequireTextToken(strjoin(ylabels, " "), contract.ExpectedYLabel, ...
    contract.FileName, "y-axis label");
end

function count = localFinitePoints(graphic)
count = 0;
properties = ["XData", "YData", "ZData", "CData"];
for property = properties
    if isprop(graphic, property)
        value = get(graphic, property);
        if isnumeric(value)
            count = count + nnz(isfinite(value));
        end
    end
end
end

function localRequireTextToken(actual, expected, fileName, label)
expected = strtrim(string(expected));
if strlength(expected) == 0
    return;
end
if ~contains(lower(strjoin(string(actual), " ")), lower(expected))
    error("sixgr:artifact:FigureTextMismatch", ...
        "Figure %s %s does not contain required text '%s'.", ...
        fileName, label, expected);
end
end

function values = localSplitList(value)
value = strtrim(string(value));
if strlength(value) == 0
    values = strings(0, 1);
    return;
end
values = string(regexp(char(value), '[|;,]', 'split')).';
values = strtrim(values);
values = values(strlength(values) > 0);
end

function localAtomicWriteTable(pathValue, T)
sixgr.util.ensureDir(pathValue);
targetDirectory = fileparts(char(string(pathValue)));
temporaryPath = [tempname(targetDirectory), '.csv'];
cleanup = onCleanup(@() localDeleteFile(temporaryPath)); %#ok<NASGU>
writetable(T, temporaryPath, "Delimiter", ",", "QuoteStrings", true);
[ok, message] = movefile(temporaryPath, pathValue, "f");
if ~ok
    error("sixgr:artifact:AtomicCSVPublishFailed", ...
        "Unable to publish CSV %s: %s", pathValue, message);
end
end

function localPublishComponents(stageComponents, targetComponents, runFolder)
localAssertOwnedPath(stageComponents, runFolder);
localAssertOwnedPath(targetComponents, runFolder);
backup = targetComponents + ".backup_" + localUUID();
localAssertOwnedPath(backup, runFolder);
hadExisting = isfolder(targetComponents);
if hadExisting
    [ok, message] = movefile(targetComponents, backup);
    if ~ok
        error("sixgr:artifact:ComponentBackupFailed", ...
            "Unable to back up existing component artifacts: %s", message);
    end
end
try
    [ok, message] = movefile(stageComponents, targetComponents);
    if ~ok
        error("sixgr:artifact:ComponentPublishFailed", ...
            "Unable to publish component artifacts: %s", message);
    end
catch ME
    if hadExisting && ~isfolder(targetComponents) && isfolder(backup)
        movefile(backup, targetComponents);
    end
    rethrow(ME);
end
if isfolder(backup)
    localDeleteOwnedDirectory(backup, runFolder);
end
end

function localDeleteOwnedDirectory(pathValue, ownerRoot)
if ~isfolder(pathValue)
    return;
end
localAssertOwnedPath(pathValue, ownerRoot);
rmdir(pathValue, "s");
end

function localAssertOwnedPath(pathValue, ownerRoot)
pathValue = localCanonicalPath(pathValue);
ownerRoot = localCanonicalPath(ownerRoot);
prefix = ownerRoot + string(filesep);
if pathValue == ownerRoot || ~startsWith(pathValue, prefix, "IgnoreCase", ispc)
    error("sixgr:artifact:UnsafeOwnedPath", ...
        "Refusing filesystem mutation outside run root %s: %s", ownerRoot, pathValue);
end
end

function value = localCanonicalPath(pathValue)
file = java.io.File(char(string(pathValue)));
value = string(char(file.getCanonicalPath()));
end

function hash = localFileSHA256(pathValue)
fileID = fopen(pathValue, "rb");
if fileID < 0
    error("sixgr:artifact:ArtifactHashReadFailed", ...
        "Unable to open generated artifact for hashing: %s", pathValue);
end
cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
bytes = fread(fileID, Inf, "*uint8");
hash = sixgr.util.sha256Hex(bytes);
end

function uuid = localUUID()
uuid = lower(string(char(java.util.UUID.randomUUID())));
end

function localCloseFigure(fig)
if ~isempty(fig) && ishghandle(fig)
    close(fig);
end
end

function localDeleteFile(pathValue)
if isfile(pathValue)
    delete(pathValue);
end
end

function audit = localAuditFromContract(contract)
audit = localEmptyAuditRow();
audit.ContractID = contract.ContractID;
audit.Domain = contract.Domain;
audit.Component = contract.Component;
audit.Profile = contract.Profile;
audit.ArtifactType = contract.ArtifactType;
audit.FileName = contract.FileName;
audit.Required = contract.Required;
audit.OutputRelativePath = contract.OutputRelativePath;
end

function row = localEmptyAuditRow()
row = struct( ...
    "ContractID", "", ...
    "Domain", "", ...
    "Component", "", ...
    "Profile", "", ...
    "ArtifactType", "", ...
    "FileName", "", ...
    "Required", false, ...
    "Status", "NOT_EVALUATED", ...
    "Producer", "", ...
    "SourceRows", 0, ...
    "OutputRelativePath", "", ...
    "SourceSHA256", "", ...
    "SHA256", "", ...
    "Width", 0, ...
    "Height", 0, ...
    "AxesCount", 0, ...
    "SeriesCount", 0, ...
    "FinitePointCount", 0, ...
    "Message", "");
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:artifact:TextScalarRequired", ...
        "Artifact output path must be a text scalar.");
end
end
