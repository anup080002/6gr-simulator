function out = publishComponentArtifactViews(runFolder, options)
%PUBLISHCOMPONENTARTIFACTVIEWS Publish hash-verified component-facing mirrors.
% Canonical artifacts are never moved or relabeled. Each published file is
% a byte-identical convenience mirror whose source and hashes are recorded.

arguments
    runFolder (1,1) string
    options.Enabled (1,1) logical = true
    options.Required (1,1) logical = true
    options.RequiredComponents string = strings(0, 1)
end

out = struct("Enabled", options.Enabled, "Required", options.Required, ...
    "Ok", true, "ManifestPath", "", "SummaryPath", "", ...
    "PublishedCount", 0, "MissingComponentCount", 0, ...
    "SkippedLegacySVGCount", 0, "RemovedStaleMirrorCount", 0, ...
    "PreservedModifiedMirrorCount", 0, "Rows", localEmptyTable(), ...
    "SummaryRows", localEmptySummaryTable());
if ~options.Enabled
    return;
end
root = string(java.io.File(char(runFolder)).getCanonicalPath());
if ~isfolder(root)
    error("sixgr:truth:componentViews:MissingRunFolder", ...
        "Run folder does not exist: %s", root);
end

specs = localSpecs();
componentRoots = string({specs.Folder});
requiredComponents = unique(strtrim(options.RequiredComponents(:)), "stable");
requiredComponents(requiredComponents == "") = [];
if isempty(requiredComponents)
    requiredComponents = componentRoots(:);
end
unknown = setdiff(requiredComponents, componentRoots(:), "stable");
if ~isempty(unknown)
    error("sixgr:truth:componentViews:UnknownComponent", ...
        "Unknown component folder(s): %s", strjoin(unknown, ", "));
end
specs = specs(ismember(componentRoots, requiredComponents));
manifestPath = fullfile(root, "reports", "csv", ...
    "component_artifact_publication_manifest.csv");
summaryPath = fullfile(root, "reports", "csv", ...
    "component_artifact_publication_summary.csv");
[out.RemovedStaleMirrorCount, out.PreservedModifiedMirrorCount] = ...
    localRemovePriorMirrors(root, manifestPath, componentRoots);
files = dir(fullfile(root, "**", "*"));
files = files(~[files.isdir]);
rows = repmat(localEmptyRow(), 0, 1);
for idx = 1:numel(files)
    sourcePath = string(fullfile(files(idx).folder, files(idx).name));
    rel = localRelativePath(root, sourcePath);
    firstPart = extractBefore(rel + "/", "/");
    if any(firstPart == componentRoots) || localIsPublicationControlArtifact(rel)
        continue;
    end
    [~, stem, ext] = fileparts(sourcePath);
    ext = lower(string(ext));
    component = localClassify(rel, specs);
    if strlength(component) == 0
        continue;
    end
    if ext == ".svg"
        out.SkippedLegacySVGCount = out.SkippedLegacySVGCount + 1;
        continue;
    end
    kind = localKind(ext);
    if strlength(kind) == 0
        continue;
    end
    sourceHash = localFileSHA256(sourcePath);
    targetDir = fullfile(root, component, kind);
    if ~isfolder(targetDir)
        mkdir(targetDir);
    end
    targetPath = fullfile(targetDir, string(stem) + ext);
    if isfile(targetPath)
        existingHash = localFileSHA256(targetPath);
        if existingHash ~= sourceHash
            targetPath = fullfile(targetDir, string(stem) + "__" + ...
                extractBefore(sourceHash, 13) + ext);
        end
    end
    if ~isfile(targetPath) || localFileSHA256(targetPath) ~= sourceHash
        [copied, message] = copyfile(sourcePath, targetPath, "f");
        if ~copied
            error("sixgr:truth:componentViews:CopyFailed", ...
                "Unable to publish %s to %s: %s", sourcePath, targetPath, message);
        end
    end
    publishedHash = localFileSHA256(targetPath);
    if publishedHash ~= sourceHash
        error("sixgr:truth:componentViews:HashMismatch", ...
            "Component mirror hash mismatch for %s.", targetPath);
    end
    info = dir(targetPath);
    row = localEmptyRow();
    row.Component = component;
    row.ArtifactType = kind;
    row.CanonicalRelativePath = rel;
    row.PublishedRelativePath = localRelativePath(root, targetPath);
    row.CanonicalSHA256 = sourceHash;
    row.PublishedSHA256 = publishedHash;
    row.ByteSize = double(info.bytes);
    row.MirrorOnly = true;
    row.CanonicalAuthorityRetained = true;
    row.SourceTruthClassification = "byte_identical_canonical_mirror";
    row.PublishStatus = "PUBLISHED_HASH_VERIFIED";
    rows(end + 1, 1) = row; %#ok<AGROW>
end

if isempty(rows)
    T = localEmptyTable();
else
    T = struct2table(rows);
    T = sortrows(T, ["Component", "ArtifactType", "PublishedRelativePath"]);
end
sixgr.util.csvWriteTable(manifestPath, T);
summaryT = localBuildSummary(requiredComponents, T);
sixgr.util.csvWriteTable(summaryPath, summaryT);
out.ManifestPath = localRelativePath(root, manifestPath);
out.SummaryPath = localRelativePath(root, summaryPath);
out.PublishedCount = height(T);
out.MissingComponentCount = sum(summaryT.SourceArtifactCount == 0);
out.Rows = T;
out.SummaryRows = summaryT;
out.Ok = ~options.Required || all(T.PublishStatus == "PUBLISHED_HASH_VERIFIED");
end

function value = localIsPublicationControlArtifact(relativePath)
pathValue = lower(replace(strtrim(string(relativePath)), "\", "/"));
value = any(pathValue == [ ...
    "reports/csv/component_artifact_publication_manifest.csv", ...
    "reports/csv/component_artifact_publication_summary.csv", ...
    "reports/csv/artifact_manifest.csv", ...
    "reports/csv/scenario_summary.csv", ...
    "meta/scenario_manifest.json"]) || ...
    contains(pathValue, "/artifact_manifest.");
end

function specs = localSpecs()
specs = struct( ...
    "Folder", {"prach","initial_access","ssb","pdcch","pdsch", ...
        "pusch","pucch","reference_signals","mimo","frame_grid", ...
        "waveform","l3","channel","rf","mac_harq_scheduler", ...
        "l2","traffic","validation"}, ...
    "Tokens", {{"prach","random_access","four_step_ra","contention"}, ...
        {"initial_access","sib1","attach_state","cell_acquisition"}, ...
        {"ssb","pbch","pss","sss"}, ...
        {"pdcch","dci","coreset","search_space"}, ...
        {"pdsch","dlsch","dl_pdsch","dl_scheduler_grant"}, ...
        {"pusch","ulsch","ul_pusch","ul_scheduler_grant"}, ...
        {"pucch","uci_"}, ...
        {"csi_rs","csirs","srs","trs","dmrs","ptrs","reference_signal", ...
            "rsla","link_adaptation","cqi","pmi","rank_indicator"}, ...
        {"mimo","beamforming","beam_","precoder","rank_layer"}, ...
        {"frame_grid","frame_","resource_grid","numerology","duplex", ...
            "slot_symbol","carrier_grid","component_carrier","guardband", ...
            "bwp_","tdd_","fdd_","k0_k1_k2"}, ...
        {"waveform","ofdm","constellation","spectrum","spectral"}, ...
        {"rrc","handover","mobility_event"}, ...
        {"channel_","geometry","mobility","interference","pathloss", ...
            "fading","doppler","blockage","shadow_fading","delay_spread", ...
            "angle_spread"}, ...
        {"rf_","frontend","agc","cfo","phase_noise","iq_imbalance", ...
            "adc_","dac_","aclr","power_control"}, ...
        {"mac_","harq","scheduler","bsr","phr","logical_channel", ...
            "lcp_"}, ...
        {"protocol_stack","protocol_","rlc","pdcp","sdap","bearer"}, ...
        {"traffic","packet_flow","flow_","goodput","latency","qos"}, ...
        {"validation","audit","coverage","manifest","contract", ...
            "acceptance","negative_test","verifier","schema","truth_", ...
            "configured_effective","scenario_summary","integration"}});
end

function component = localClassify(relativePath, specs)
text = lower("/" + replace(string(relativePath), "\", "/"));
component = "";
for idx = 1:numel(specs)
    if any(contains(text, string(specs(idx).Tokens)))
        component = string(specs(idx).Folder);
        return;
    end
end
firstPart = extractBefore(replace(string(relativePath), "\", "/") + "/", "/");
switch lower(firstPart)
    case {"air_interface", "control", "system", "mmtc"}
        % These are existing canonical top-level layouts. They are not
        % republished as mirrors because source and target would coincide.
        component = "";
    case "harq"
        component = "mac_harq_scheduler";
    case "beamforming"
        component = "mimo";
    case "numerology"
        component = "frame_grid";
    case "rf"
        component = "rf";
    case {"interference", "map", "ntn", "v2x"}
        component = "channel";
    case "packet_flow"
        component = "traffic";
    case {"reports", "meta"}
        component = "validation";
end
if ~any(component == string({specs.Folder}))
    component = "";
end
end

function [removedCount, preservedCount] = localRemovePriorMirrors(root, manifestPath, componentRoots)
removedCount = 0;
preservedCount = 0;
if ~isfile(manifestPath)
    return;
end
try
    prior = readtable(manifestPath, "TextType", "string", ...
        "VariableNamingRule", "preserve");
catch ME
    error("sixgr:truth:componentViews:PriorManifestUnreadable", ...
        "Unable to read prior component publication manifest: %s", ME.message);
end
requiredColumns = ["PublishedRelativePath", "PublishedSHA256", "MirrorOnly"];
if ~all(ismember(requiredColumns, string(prior.Properties.VariableNames)))
    error("sixgr:truth:componentViews:PriorManifestSchema", ...
        "Prior component publication manifest is missing required columns.");
end
for idx = 1:height(prior)
    rel = replace(strtrim(string(prior.PublishedRelativePath(idx))), "\", "/");
    parts = split(rel, "/");
    if numel(parts) < 3 || ~any(parts(1) == componentRoots) || ...
            ~any(parts(2) == ["csv", "image", "json", "mat"]) || ...
            ~localLogicalScalar(prior.MirrorOnly(idx))
        continue;
    end
    targetPath = string(java.io.File(char(fullfile(root, ...
        replace(rel, "/", filesep)))).getCanonicalPath());
    rootPrefix = string(root) + string(filesep);
    if ~startsWith(lower(targetPath), lower(rootPrefix))
        error("sixgr:truth:componentViews:PathEscape", ...
            "Prior component mirror path escapes the run folder: %s", rel);
    end
    if ~isfile(targetPath)
        continue;
    end
    expectedHash = lower(strtrim(string(prior.PublishedSHA256(idx))));
    if strlength(expectedHash) == 64 && lower(localFileSHA256(targetPath)) == expectedHash
        delete(targetPath);
        removedCount = removedCount + 1;
    else
        preservedCount = preservedCount + 1;
    end
end
end

function value = localLogicalScalar(raw)
if islogical(raw)
    value = logical(raw);
elseif isnumeric(raw)
    value = raw ~= 0;
else
    value = any(lower(strtrim(string(raw))) == ["true", "1", "yes"]);
end
end

function summaryT = localBuildSummary(requiredComponents, T)
rows = repmat(localEmptySummaryRow(), numel(requiredComponents), 1);
for idx = 1:numel(requiredComponents)
    component = requiredComponents(idx);
    if isempty(T)
        selected = false(0, 1);
    else
        selected = T.Component == component;
    end
    rows(idx).Component = component;
    rows(idx).Folder = component + "/{csv,image,json,mat}";
    rows(idx).SourceArtifactCount = sum(selected);
    rows(idx).CSVCount = sum(selected & T.ArtifactType == "csv");
    rows(idx).RasterImageCount = sum(selected & T.ArtifactType == "image");
    rows(idx).JSONCount = sum(selected & T.ArtifactType == "json");
    rows(idx).MATCount = sum(selected & T.ArtifactType == "mat");
    if rows(idx).SourceArtifactCount > 0
        rows(idx).PublicationStatus = "PUBLISHED_HASH_VERIFIED";
    else
        rows(idx).PublicationStatus = "NO_CANONICAL_ARTIFACTS";
    end
    rows(idx).EvidenceInterpretation = ...
        "Presence is not a pass verdict; absent evidence is never synthesized.";
end
summaryT = struct2table(rows);
end

function kind = localKind(ext)
if ext == ".csv"
    kind = "csv";
elseif any(ext == [".png", ".jpg", ".jpeg"])
    kind = "image";
elseif ext == ".json"
    kind = "json";
elseif ext == ".mat"
    kind = "mat";
else
    kind = "";
end
end

function relative = localRelativePath(root, pathValue)
rootText = replace(string(root), "\", "/");
pathText = replace(string(pathValue), "\", "/");
prefix = rootText + "/";
if ~startsWith(lower(pathText), lower(prefix))
    error("sixgr:truth:componentViews:PathEscape", ...
        "Artifact path is outside the run folder: %s", pathText);
end
relative = extractAfter(pathText, strlength(prefix));
end

function hash = localFileSHA256(pathValue)
fid = fopen(pathValue, "rb");
if fid < 0
    error("sixgr:truth:componentViews:ReadFailed", ...
        "Unable to read artifact for hashing: %s", pathValue);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "*uint8");
hash = string(sixgr.util.sha256Hex(bytes));
end

function row = localEmptyRow()
row = struct("Component", "", "ArtifactType", "", ...
    "CanonicalRelativePath", "", "PublishedRelativePath", "", ...
    "CanonicalSHA256", "", "PublishedSHA256", "", "ByteSize", 0, ...
    "MirrorOnly", true, "CanonicalAuthorityRetained", true, ...
    "SourceTruthClassification", "", "PublishStatus", "");
end

function T = localEmptyTable()
T = struct2table(repmat(localEmptyRow(), 0, 1));
end

function row = localEmptySummaryRow()
row = struct("Component", "", "Folder", "", ...
    "SourceArtifactCount", 0, "CSVCount", 0, "RasterImageCount", 0, ...
    "JSONCount", 0, "MATCount", 0, "PublicationStatus", "", ...
    "EvidenceInterpretation", "");
end

function T = localEmptySummaryTable()
T = struct2table(repmat(localEmptySummaryRow(), 0, 1));
end
