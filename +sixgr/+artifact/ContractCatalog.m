classdef ContractCatalog
    %CONTRACTCATALOG Canonical, normalized artifact requirements.
    %
    % The technical phase packs use several historical column names.  This
    % class is the only adapter for those schemas.  Runtime publication uses
    % the normalized catalog and never copies a CSV or image from artifacts/
    % or from a previous results/ run.

    methods (Static)
        function catalog = load(repositoryRoot, catalogScope)
            if nargin < 1 || strlength(string(repositoryRoot)) == 0
                repositoryRoot = sixgr.artifact.ContractCatalog.repositoryRoot();
            end
            if nargin < 2 || strlength(strtrim(string(catalogScope))) == 0
                catalogScope = "phase_pack";
            end
            repositoryRoot = char(string(repositoryRoot));
            catalogScope = lower(strtrim(string(catalogScope)));
            if ~ismember(catalogScope, ["phase_pack", "runtime_in_path"])
                error("sixgr:artifact:UnsupportedCatalogScope", ...
                    "Unsupported artifact catalog scope '%s'.", catalogScope);
            end
            vectorRoot = fullfile(repositoryRoot, "tests", "vectors");
            if ~isfolder(vectorRoot)
                error("sixgr:artifact:ContractRootMissing", ...
                    "Artifact contract root does not exist: %s", vectorRoot);
            end

            packs = sixgr.artifact.ContractCatalog.packRegistry();
            rows = repmat(localEmptyRow(), 0, 1);
            for packIndex = 1:height(packs)
                domain = packs.Domain(packIndex);
                packDir = fullfile(vectorRoot, packs.Directory(packIndex));
                if ~isfolder(packDir)
                    error("sixgr:artifact:ContractPackMissing", ...
                        "Artifact contract pack '%s' is missing: %s", domain, packDir);
                end
                definitions = localContractDefinitions(domain, packDir);
                for definitionIndex = 1:height(definitions)
                    contractPath = definitions.Path(definitionIndex);
                    if ~isfile(contractPath)
                        error("sixgr:artifact:ContractFileMissing", ...
                            "Required %s/%s %s contract is missing: %s", ...
                            domain, definitions.Profile(definitionIndex), ...
                            definitions.ArtifactType(definitionIndex), contractPath);
                    end
                    contractT = localReadContract(contractPath);
                    for rowIndex = 1:height(contractT)
                        rows(end + 1, 1) = localNormalizeRow(contractT, rowIndex, ... %#ok<AGROW>
                            domain, definitions.Profile(definitionIndex), ...
                            definitions.ArtifactType(definitionIndex), contractPath, ...
                            repositoryRoot);
                    end
                end
            end
            catalog = struct2table(rows, 'AsArray', true);
            localValidateCatalog(catalog);
            if catalogScope == "runtime_in_path"
                catalog = localRuntimeInPathCatalog(catalog);
            end
            catalog = sortrows(catalog, ...
                ["Domain", "Profile", "ArtifactType", "FileName", "Mode"]);
        end

        function packs = packRegistry()
            % The duplicate pdsch_dlsch_codex_pack is deliberately excluded.
            % tests/vectors/pdsch is the maintained production contract.
            domain = ["channel"; "frame_grid"; "initial_access"; ...
                "integration"; "mac"; "mimo"; "pdcch"; "pdsch"; ...
                "protocol"; "pucch"; "pusch"; "rf"; "rsla"; ...
                "validation"; "waveform"];
            packs = table(domain, domain, 'VariableNames', ...
                {'Domain', 'Directory'});
        end

        function key = evidenceKey(domain, profile, artifactType, fileName)
            [~, leaf, extension] = fileparts(char(string(fileName)));
            key = lower(strjoin([string(domain), string(profile), ...
                upper(string(artifactType)), string(leaf) + string(extension)], "|"));
        end

        function root = repositoryRoot()
            here = fileparts(mfilename("fullpath"));
            root = fileparts(fileparts(here));
        end
    end
end

function catalog = localRuntimeInPathCatalog(fullCatalog)
% A scenario execution may publish only evidence registered by that exact
% execution.  Phase-pack campaigns remain available through phase_pack and
% ComponentQualificationPublisher, but are never implied by a single run.
required = table( ...
    ["initial_access";"pdsch";"pusch"], ...
    ["CSV";"CSV";"CSV"], ...
    ["prach_detection_trials.csv"; ...
     "pdsch_bler_curve.csv"; ...
     "pusch_bler_curve.csv"], ...
    'VariableNames', {'Domain','ArtifactType','FileName'});
mask = false(height(fullCatalog), 1);
for index = 1:height(required)
    match = fullCatalog.Domain == required.Domain(index) & ...
        fullCatalog.Profile == "base" & ...
        fullCatalog.ArtifactType == required.ArtifactType(index) & ...
        fullCatalog.FileName == required.FileName(index);
    if nnz(match) ~= 1
        error("sixgr:artifact:RuntimeContractMissing", ...
            "Expected exactly one runtime contract for %s/%s/%s; observed %d.", ...
            required.Domain(index), required.ArtifactType(index), ...
            required.FileName(index), nnz(match));
    end
    mask = mask | match;
end
catalog = fullCatalog(mask, :);
if height(catalog) ~= height(required) || ...
        nnz(catalog.ArtifactType == "CSV") ~= 3 || ...
        any(catalog.ArtifactType == "PNG")
    error("sixgr:artifact:RuntimeContractCountMismatch", ...
        ["Runtime in-path catalog must contain exactly three CSV contracts " ...
        "and no raster contracts. Runtime rasters are generated only by " ...
        "the post-run CSV contract materializer."]);
end

% Phase-pack minima describe dedicated statistical campaigns (for example
% 100 PRACH trials and four BLER operating points). A scheduled scenario is
% a separate evidence scope: it may publish only observations produced by
% that exact execution, and the adapters label those rows in_path/MEASURED.
% Keep the source phase-pack rows unchanged and derive a separately named
% runtime contract that requires at least one real observation.
catalog.ContractID = catalog.ContractID + "|runtime_in_path";
catalog.ContractSection = catalog.ContractSection + "_runtime_in_path";
catalog.Description = catalog.Description + ...
    " Runtime scope contains measured rows from this exact execution; " + ...
    "phase-pack statistical minima remain authoritative in phase_pack.";
catalog.MinimumRows(:) = 1;
end

function definitions = localContractDefinitions(domain, packDir)
if domain == "integration"
    names = ["desired_integration_csv_contract.csv"; ...
        "desired_integration_image_contract.csv"];
    profiles = ["base"; "base"];
    types = ["CSV"; "PNG"];
else
    prefix = localContractPrefix(domain);
    names = ["desired_" + prefix + "_csv_contract.csv"; ...
        "desired_" + prefix + "_image_contract.csv"; ...
        "desired_" + prefix + "_impact_csv_contract.csv"; ...
        "desired_" + prefix + "_impact_image_contract.csv"];
    profiles = ["base"; "base"; "impact"; "impact"];
    types = ["CSV"; "PNG"; "CSV"; "PNG"];
end
paths = strings(numel(names), 1);
for index = 1:numel(names)
    paths(index) = string(fullfile(packDir, names(index)));
end
definitions = table(paths, profiles, types, ...
    'VariableNames', {'Path', 'Profile', 'ArtifactType'});
end

function prefix = localContractPrefix(domain)
switch domain
    case "frame_grid"
        prefix = "frame";
    otherwise
        prefix = domain;
end
end

function T = localReadContract(path)
options = detectImportOptions(path, "Delimiter", ",", ...
    "VariableNamingRule", "preserve", "TextType", "string");
options = setvartype(options, options.VariableNames, "string");
T = readtable(path, options);
end

function row = localNormalizeRow(T, rowIndex, domain, profile, artifactType, ...
        contractPath, repositoryRoot)
row = localEmptyRow();
row.Domain = domain;
row.Profile = profile;
row.ArtifactType = artifactType;
row.Mode = upper(localValue(T, rowIndex, ["Mode"], "ALL"));
row.ContractSection = localValue(T, rowIndex, ["Domain"], domain);

if artifactType == "CSV"
    artifactPath = localValue(T, rowIndex, ...
        ["FileName", "CSVFile", "Artifact"], "");
else
    artifactPath = localValue(T, rowIndex, ...
        ["ImageFile", "Artifact"], "");
end
localAssertSafeRelativePath(artifactPath, contractPath, rowIndex);
[~, leaf, extension] = fileparts(char(artifactPath));
row.FileName = string(leaf) + string(extension);
row.ContractArtifactPath = artifactPath;
row.Component = localComponent(domain, row.FileName);
row.Required = localRequired(T, rowIndex);
row.RequiredColumns = localValue(T, rowIndex, ["RequiredColumns"], "");
row.PrimaryKey = localValue(T, rowIndex, ["PrimaryKey"], "");
row.Description = localValue(T, rowIndex, ...
    ["Description", "ExpectedContent", "PassCondition"], "");
row.PassCondition = localValue(T, rowIndex, ["PassCondition"], "");
row.ProductionSource = localValue(T, rowIndex, ["ProductionSource"], "");
row.SourceCSV = localValue(T, rowIndex, ...
    ["SourceCSV", "SourceCSVFiles"], "");
row.ExpectedTitle = localValue(T, rowIndex, ...
    ["ExpectedTitle", "ExpectedTitleToken", "ExpectedTitleTokens", ...
     "TitleTokens"], "");
row.ExpectedXLabel = localValue(T, rowIndex, ...
    ["ExpectedXLabel", "ExpectedXLabelTokens", "XAxisTokens"], "");
row.ExpectedYLabel = localValue(T, rowIndex, ...
    ["ExpectedYLabel", "ExpectedYLabelTokens", "YAxisTokens"], "");
row.MinimumRows = localNumber(T, rowIndex, ...
    ["MinimumRows", "MinRows"], double(artifactType == "CSV"));
row.MinimumWidth = localNumber(T, rowIndex, ...
    ["MinimumWidth", "MinWidth"], 0);
row.MinimumHeight = localNumber(T, rowIndex, ...
    ["MinimumHeight", "MinHeight"], 0);
row.MinimumAxes = localNumber(T, rowIndex, ...
    ["MinimumAxes", "MinAxes", "MinAxesCount", "ExpectedAxes"], 0);
row.MinimumSeries = localNumber(T, rowIndex, ...
    ["MinimumSeries", "MinSeries", "MinSeriesCount"], 0);
row.MinimumFinitePoints = localNumber(T, rowIndex, ...
    ["MinimumFinitePoints", "MinFinitePoints", "MinFinitePointCount"], 0);
row.SourceContract = string(localRelativePath(repositoryRoot, contractPath));
row.ContractID = sixgr.artifact.ContractCatalog.evidenceKey( ...
    domain, profile, artifactType, row.FileName) + "|" + lower(row.Mode);
if profile == "impact"
    row.OutputRelativePath = string(fullfile(row.Component, "impact", ...
        lower(artifactType), row.FileName));
else
    row.OutputRelativePath = string(fullfile(row.Component, ...
        lower(artifactType), row.FileName));
end
end

function component = localComponent(domain, fileName)
name = lower(string(fileName));
component = domain;
if domain ~= "initial_access"
    return;
end
rachTokens = ["prach", "rach", "random_access", "msg1", "msg2", ...
    "msg3", "msg4", "rar_", "contention_resolution"];
if any(contains(name, rachTokens))
    component = "prach";
end
end

function required = localRequired(T, rowIndex)
value = localValue(T, rowIndex, ["Required", "Mandatory"], "true");
required = any(strcmpi(strtrim(value), ...
    ["true", "1", "yes", "pass", "required", "acceptance"]));
end

function value = localNumber(T, rowIndex, aliases, defaultValue)
textValue = localValue(T, rowIndex, aliases, "");
value = str2double(textValue);
if strlength(textValue) == 0 || ~isfinite(value)
    value = defaultValue;
end
end

function value = localValue(T, rowIndex, aliases, defaultValue)
value = string(defaultValue);
for alias = aliases
    match = strcmpi(string(T.Properties.VariableNames), alias);
    if any(match)
        candidate = string(T{rowIndex, find(match, 1, "first")});
        if ~ismissing(candidate) && strlength(strtrim(candidate)) > 0
            value = strtrim(candidate);
        end
        return;
    end
end
end

function localAssertSafeRelativePath(pathValue, contractPath, rowIndex)
pathValue = string(pathValue);
if strlength(pathValue) == 0
    error("sixgr:artifact:MissingArtifactPath", ...
        "Contract %s row %d has no artifact path.", contractPath, rowIndex);
end
normalized = replace(pathValue, "\\", "/");
segments = split(normalized, "/");
if startsWith(normalized, "/") || ...
        ~isempty(regexp(char(normalized), '^[A-Za-z]:', 'once')) || ...
        any(segments == "..")
    error("sixgr:artifact:UnsafeArtifactPath", ...
        "Contract %s row %d contains unsafe artifact path '%s'.", ...
        contractPath, rowIndex, pathValue);
end
end

function localValidateCatalog(catalog)
if isempty(catalog)
    error("sixgr:artifact:EmptyContractCatalog", ...
        "No artifact contracts were loaded.");
end
csvCount = nnz(catalog.ArtifactType == "CSV");
pngCount = nnz(catalog.ArtifactType == "PNG");
if csvCount ~= 659 || pngCount ~= 691
    error("sixgr:artifact:ContractCountMismatch", ...
        "Normalized catalog contains %d CSV/%d PNG rows; expected 659/691.", ...
        csvCount, pngCount);
end
extensions = lower(string(cellfun(@(x) localExtension(x), ...
    cellstr(catalog.FileName), "UniformOutput", false)));
badCSV = catalog.ArtifactType == "CSV" & extensions ~= ".csv";
badPNG = catalog.ArtifactType == "PNG" & extensions ~= ".png";
if any(badCSV | badPNG)
    bad = catalog(find(badCSV | badPNG, 1), :);
    error("sixgr:artifact:WrongArtifactExtension", ...
        "Contract %s requires %s but names '%s'.", ...
        bad.ContractID, bad.ArtifactType, bad.FileName);
end
if numel(unique(catalog.ContractID)) ~= height(catalog)
    error("sixgr:artifact:DuplicateContractID", ...
        "The normalized catalog contains duplicate contract identifiers.");
end
if numel(unique(lower(catalog.OutputRelativePath))) ~= height(catalog)
    error("sixgr:artifact:DuplicateOutputPath", ...
        "Two artifact requirements resolve to the same component output path.");
end
end

function extension = localExtension(pathValue)
[~, ~, extension] = fileparts(pathValue);
end

function relative = localRelativePath(root, pathValue)
root = char(string(root));
pathValue = char(string(pathValue));
prefix = [root, filesep];
if startsWith(pathValue, prefix, "IgnoreCase", ispc)
    relative = pathValue(numel(prefix) + 1:end);
else
    relative = pathValue;
end
end

function row = localEmptyRow()
row = struct( ...
    "ContractID", "", ...
    "Domain", "", ...
    "Component", "", ...
    "Profile", "", ...
    "Mode", "", ...
    "ContractSection", "", ...
    "ArtifactType", "", ...
    "FileName", "", ...
    "ContractArtifactPath", "", ...
    "OutputRelativePath", "", ...
    "Required", false, ...
    "MinimumRows", 0, ...
    "RequiredColumns", "", ...
    "PrimaryKey", "", ...
    "SourceCSV", "", ...
    "MinimumWidth", 0, ...
    "MinimumHeight", 0, ...
    "MinimumAxes", 0, ...
    "MinimumSeries", 0, ...
    "MinimumFinitePoints", 0, ...
    "ExpectedTitle", "", ...
    "ExpectedXLabel", "", ...
    "ExpectedYLabel", "", ...
    "Description", "", ...
    "PassCondition", "", ...
    "ProductionSource", "", ...
    "SourceContract", "");
end
